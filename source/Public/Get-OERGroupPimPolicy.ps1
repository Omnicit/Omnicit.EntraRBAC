function Get-OERGroupPimPolicy {
    <#
    .SYNOPSIS
    Reads the PIM-for-groups activation policy (template) for a group.

    .DESCRIPTION
    Resolves the roleManagementPolicy governing a group's PIM-for-groups access (via the private
    Get-OERPimGroupPolicyId) and reads its rules. The rules are projected into the tagged
    Omnicit.EntraRBAC.GroupPimPolicy shape by the private ConvertTo-OERGroupPimPolicy, the single owner
    of this read shape: friendly properties ActivationMaxHours, AuthenticationContextId,
    ActivationEnabledRules, AllowPermanentEligibility, EligibleDuration, EligibleDurationDays,
    AllowPermanentActive, ActiveDuration, ActiveDurationDays, ActiveEnabledRules, and a Notifications
    object carrying EligibleAlert, ActiveAlert, and ActivationAlert recipient lists -- alongside the raw
    Rules array. A group that has not been onboarded to PIM for Groups (no policy assignment) produces a
    non-terminating PimPolicyNotFound error. A policy-assignment lookup that FAILED rather than
    answering -- a 403, a throttle, a dead transport -- is a different fact and is reported separately
    as a non-terminating PimPolicyReadFailed error, so a caller suppressing the ordinary
    not-onboarded case does not suppress a refusal along with it.

    .PARAMETER Group
    The target group whose PIM-for-groups activation policy is read, given as a display name or object id
    (GUID) and resolved via Resolve-OERGroupId. Accepts the GroupId, Id, and DisplayName aliases (GroupId
    takes precedence during pipeline binding so a piped Get-OERGroupMember object binds the group's
    GroupId instead of a principal's Id) and binds from the pipeline by property name so
    Get-OERGroup pipes straight in.

    .PARAMETER AccessType
    Whether to read the member (default) or owner activation policy for the group. Binds from the
    pipeline by property name, so a piped Omnicit.EntraRBAC.GroupPimPolicy or GroupPimPolicyResult
    object (both carry an AccessType property) re-reads the same access type it reported.

    .PARAMETER TenantId
    Optional tenant id or domain to authenticate against, forwarded to Initialize-OERAuth.

    .EXAMPLE
    Get-OERGroupPimPolicy -Group 'role_sec_identity_administrator'
    Reads the member activation template for the named group.
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory, ValueFromPipelineByPropertyName)]
        # GroupId precedes Id so a piped GroupMember object binds the group's GroupId, not the
        # principal's Id, during ValueFromPipelineByPropertyName alias resolution.
        [Alias('GroupId', 'Id', 'DisplayName')]
        [string]$Group,

        [Parameter(ValueFromPipelineByPropertyName)]
        [ValidateSet('member', 'owner')]
        [string]$AccessType = 'member',

        [string]$TenantId
    )
    begin {
        $AuthParams = @{}
        if ($TenantId) { $AuthParams.TenantId = $TenantId }
        Initialize-OERAuth @AuthParams
    }
    process {
        # Refuse an ambiguous display name loudly; any other throw falls through to the not-found branch.
        $GroupId = $null
        try {
            $GroupId = Resolve-OERGroupId -DisplayName $Group
        } catch {
            Remove-OERErrorRecord -Record $PSItem
            if (Test-OERAmbiguousNameError -Record $PSItem) {
                Write-CmdletError `
                    -Message ([System.Exception]::new($PSItem.Exception.Message)) `
                    -ErrorId 'AmbiguousGroupName' -Category InvalidArgument `
                    -TargetObject $Group -Cmdlet $PSCmdlet
                return
            }
        }
        if (-not $GroupId) {
            Write-CmdletError `
                -Message ([System.Exception]::new(
                    "Group '$Group' not found. Verify the display name matches exactly (leading or trailing spaces " +
                    "and punctuation count) or pass the group object id instead.")) `
                -ErrorId 'GroupNotFound' -Category ObjectNotFound -TargetObject $Group -Cmdlet $PSCmdlet
            return
        }

        # A FAILED LOOKUP IS NOT AN ABSENT POLICY (issue #76). Get-OERPimGroupPolicyId returns $null
        # only where it LEARNED there is no policy assignment: an empty assignments collection, or
        # the 400 ResourceTypeNotSupported it declares to the transport as an expected answer for a
        # group that was never onboarded. Every OTHER outcome -- 403, 429, 500, a dead transport --
        # still throws, and that is a different fact: "I was not allowed to look" or "I could not
        # look", never "there is nothing there".
        #
        # Collapsing the two into one PimPolicyNotFound is what let a live 403 on the policy-id
        # lookup for 96 groups reach the operator as ZERO error records and an inventory silently
        # short of every PIM policy: a caller that suppresses the ordinary not-onboarded case --
        # which is most groups in most tenants -- suppressed the refusal along with it. The two
        # answers now carry DIFFERENT error ids so a caller can suppress one and surface the other.
        # PimPolicyNotFound keeps its exact meaning and its exact id for the genuinely absent case.
        $PolicyId = $null
        try {
            $PolicyId = Get-OERPimGroupPolicyId -GroupId $GroupId -AccessType $AccessType
        } catch {
            Remove-OERErrorRecord -Record $PSItem
            Write-CmdletError `
                -Message ([System.Exception]::new(
                    "Could not read the PIM-for-groups policy assignment for group '$GroupId' ('$AccessType' access): " +
                    "$($PSItem.Exception.Message). Whether this group has a policy is UNKNOWN, which is not the same " +
                    'as the group having none, so no policy is reported for it.')) `
                -ErrorId 'PimPolicyReadFailed' -Category ReadError -TargetObject $GroupId `
                -InnerException $PSItem.Exception -Cmdlet $PSCmdlet
            return
        }
        if (-not $PolicyId) {
            Write-CmdletError `
                -Message ([System.Exception]::new("Group '$GroupId' has no PIM-for-groups policy for '$AccessType' access. Onboard it first with Add-OERGroupEligibility.")) `
                -ErrorId 'PimPolicyNotFound' -Category ObjectNotFound -TargetObject $GroupId -Cmdlet $PSCmdlet
            return
        }

        try {
            $Rules = @((Invoke-OERGraphRequest -Uri (Get-OERPimGroupsGraphPath -Path ("policies/roleManagementPolicies/{0}/rules" -f $PolicyId)) -All).value)
        } catch {
            Remove-OERErrorRecord -Record $PSItem
            $PSCmdlet.WriteError($PSItem)
            return
        }

        ConvertTo-OERGroupPimPolicy -Rules $Rules -GroupId $GroupId -PolicyId $PolicyId -AccessType $AccessType
    }
}
