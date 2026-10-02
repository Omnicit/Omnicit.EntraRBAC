function Get-OERGroupPermanentEligibilityState {
    <#
    .SYNOPSIS
    Reports whether a group's PIM-for-groups policy currently allows permanent eligible assignments.

    .DESCRIPTION
    Resolves the roleManagementPolicy governing a group's PIM-for-groups access (member or owner) via
    the private Get-OERPimGroupPolicyId and inspects its Expiration_Admin_Eligibility rule. A lookup
    that returns null (Microsoft Graph lists no policy for that access type, in practice for a group
    created moments ago) is reported as no policy. A lookup that THROWS is not: a refused or failed
    read (a 403, an exhausted 429, a 5xx) says nothing about whether a policy is listed, so it is
    rethrown after the scrub, exactly as a failed rules read is, and the caller decides what to do
    (Add-OERGroupEligibility proceeds and lets Microsoft Graph enforce the policy). A group that was
    never used with PIM for Groups is not a no-policy case either: Graph lists its policies before the
    group is onboarded. The result reports HasPolicy (whether a policy is listed), the PolicyId, and
    PermanentAllowed (true only when the eligibility rule does NOT require expiration; a missing rule
    yields true so no unjustified policy write is attempted). This is a pure read used by the permanent
    self-heal in Add-OERGroupEligibility. Both reads are guarded: Invoke-OERGraphRequest already
    converts any non-recoverable failure into a sanitized ErrorRecord before throwing it, so each catch
    here only scrubs that record from $global:Error and rethrows it unchanged, preserving the real
    Graph error code for the caller instead of destroying it with a second conversion pass.

    .PARAMETER GroupId
    The object id of the group whose PIM-for-groups eligibility policy state is read.

    .PARAMETER AccessType
    Which access policy to inspect: 'member' (default) or 'owner'.

    .EXAMPLE
    Get-OERGroupPermanentEligibilityState -GroupId '00000000-0000-0000-0000-000000000001' -AccessType member
    Returns whether the group's member eligibility policy allows permanent assignments.
    #>
    [OutputType([PSCustomObject])]
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$GroupId,

        [ValidateSet('member', 'owner')]
        [string]$AccessType = 'member'
    )

    # A throw here is a FAILED read (Get-OERPimGroupPolicyId returns $null for every "no policy listed"
    # answer, including the 400 ResourceTypeNotSupported it declares to the transport), so it is
    # rethrown, never folded into HasPolicy = $false: that would tell Add-OERGroupEligibility the
    # group is not onboarded (GroupNotOnboarded) when it was merely unreadable. Same scrub-then-bare-
    # rethrow as the rules read below.
    $PolicyId = try {
        Get-OERPimGroupPolicyId -GroupId $GroupId -AccessType $AccessType
    } catch {
        Remove-OERErrorRecord -Record $PSItem
        throw
    }
    if (-not $PolicyId) {
        return [PSCustomObject]@{ HasPolicy = $false; PolicyId = $null; PermanentAllowed = $false }
    }

    # SECURITY: guard the read so a swallowed failure record is scrubbed from $global:Error before it
    # is rethrown. Invoke-OERGraphRequest itself already routes every non-recoverable failure through
    # Convert-GraphHttpException, so the record caught here is already a sanitized, freshly built
    # ErrorRecord (never the raw Graph SDK exception carrying the bearer token) -- it is rethrown
    # unchanged (bare `throw`) so its real Graph error code and FullyQualifiedErrorId survive for the
    # caller instead of being destroyed by a second conversion pass. Callers must not have to remember
    # to do the $global:Error scrub for us.
    $Rules = try {
        @((Invoke-OERGraphRequest -Uri (Get-OERPimGroupsGraphPath -Path ("policies/roleManagementPolicies/{0}/rules" -f $PolicyId)) -All).value)
    } catch {
        Remove-OERErrorRecord -Record $PSItem
        throw
    }
    $Rule = $Rules | Where-Object { $PSItem.id -eq 'Expiration_Admin_Eligibility' } | Select-Object -First 1

    [PSCustomObject]@{
        HasPolicy        = $true
        PolicyId         = [string]$PolicyId
        PermanentAllowed = -not [bool]$Rule.isExpirationRequired
    }
}
