function Remove-OERAdministrativeUnitMember {
    <#
    .SYNOPSIS
    Removes one or more members from an Entra ID administrative unit.

    .DESCRIPTION
    Removes each principal in -MemberId from the administrative unit identified by -AdministrativeUnit
    through the unit's members/{id}/$ref navigation endpoint. Removing a member detaches it from the unit;
    it does not delete the member object. Each principal is processed individually so a failure on one is
    reported without stopping the remaining removals. A unit that cannot be resolved produces a
    non-terminating AdministrativeUnitNotFound error. Supports -WhatIf and -Confirm.

    Members may be given as raw object ids with -MemberId or by name with -User (user principal name) and
    -Group (group display name); the parameters are unioned into a single run. A non-GUID value passed to
    -MemberId produces a non-terminating InvalidMemberId error naming the friendly alternatives instead of
    an opaque members/$ref failure. Devices are removed by object id with -MemberId.

    .PARAMETER AdministrativeUnit
    The administrative unit to remove the members from, given as either its object id (GUID) or its
    display name. Binds from the pipeline by property name, and still accepts the historical -Id,
    -AdministrativeUnitId and -DisplayName parameter names as aliases.

    .PARAMETER MemberId
    One or more object ids of the members to remove from the administrative unit. Must be canonical
    GUIDs; to name a user or group instead, use -User or -Group. Also bindable as -PrincipalId, the
    name the group-membership and scoped-role cmdlets use for the same concept, and binds from the
    pipeline by property name through that alias, so a ConvertTo-OERAdministrativeUnitMember object
    pipes straight back in. A ConvertTo-OERGroupMember object does NOT: it carries no
    AdministrativeUnitId, so its own Id (the principal) would bind -AdministrativeUnit through the Id
    alias instead.

    .PARAMETER User
    One or more users to remove, each given as a user principal name or object id (GUID) and resolved
    via Resolve-OERPrincipal. Combined with -MemberId and -Group rather than exclusive.

    .PARAMETER Group
    One or more groups to remove, each given as a group display name or object id (GUID) and resolved
    via Resolve-OERPrincipal. Combined with -MemberId and -User rather than exclusive. Group display
    names are not guaranteed unique in Entra ID; if more than one group shares the given name, the
    command fails with an error naming the candidate object ids, so re-run with the object id.

    .PARAMETER TenantId
    Optional tenant id or domain to authenticate against, forwarded to Initialize-OERAuth.

    .EXAMPLE
    Remove-OERAdministrativeUnitMember -AdministrativeUnit 'au_hr' -MemberId $UserId
    Removes the user from the named administrative unit.

    .EXAMPLE
    Remove-OERAdministrativeUnitMember -AdministrativeUnit 'au_hr' -User 'anna.berg@contoso.com' -Group 'Sales Team'
    Removes a user (by UPN) and a group (by display name) from the named administrative unit.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([void])]
    param(
        [Parameter(Mandatory, ValueFromPipelineByPropertyName)]
        # AdministrativeUnitId precedes Id/DisplayName so a piped AdministrativeUnitMember object binds
        # the parent unit's id, not the member's own Id/DisplayName, during ValueFromPipelineByPropertyName
        # alias resolution.
        [Alias('AdministrativeUnitId', 'Id', 'DisplayName')]
        [string]$AdministrativeUnit,

        [Parameter(ValueFromPipelineByPropertyName)]
        [Alias('PrincipalId')]
        [string[]]$MemberId,

        [string]$TenantId,

        # Declared after the pre-existing parameters so their positional binding is unchanged.
        [string[]]$User,

        [string[]]$Group
    )
    begin {
        $AuthParams = @{}
        if ($TenantId) { $AuthParams.TenantId = $TenantId }
        Initialize-OERAuth @AuthParams
    }
    process {
        # A throw here is a transport/permission/throttling failure, NOT a missing unit. Reporting it as
        # AdministrativeUnitNotFound would send the operator hunting for a unit that exists, so the two
        # outcomes are reported separately (mirrors Get-OERAccessReviewInstance's definition handling).
        # Resolve-OERAdministrativeUnitId has no GUID short-circuit of its own, so the dispatch happens
        # here: a canonical GUID goes to -Id (no Graph call), anything else goes to -DisplayName.
        $AuId = try {
            if (Test-OERGuid -Value $AdministrativeUnit) {
                Resolve-OERAdministrativeUnitId -Id $AdministrativeUnit
            } else {
                Resolve-OERAdministrativeUnitId -DisplayName $AdministrativeUnit
            }
        } catch {
            Remove-OERErrorRecord -Record $PSItem
            Write-CmdletError `
                -Message ([System.Exception]::new(
                    "Failed to look up administrative unit '$AdministrativeUnit': $($PSItem.Exception.Message)")) `
                -InnerException $PSItem.Exception `
                -ErrorId 'AdministrativeUnitResolveFailed' `
                -Category NotSpecified `
                -TargetObject $AdministrativeUnit `
                -Cmdlet $PSCmdlet
            return
        }
        if (-not $AuId) {
            Write-CmdletError `
                -Message ([System.Exception]::new('No administrative unit found for the supplied id/display name.')) `
                -ErrorId 'AdministrativeUnitNotFound' `
                -Category ObjectNotFound `
                -TargetObject $AdministrativeUnit `
                -Cmdlet $PSCmdlet
            return
        }
        Write-Verbose "[Remove-OERAdministrativeUnitMember] Resolved administrative unit to '$AuId'."

        $Hint = '-User or -Group'
        $PrincipalSpecs = @()
        foreach ($Value in $MemberId) { $PrincipalSpecs += @{ PrincipalId = $Value } }
        foreach ($Value in $User) { $PrincipalSpecs += @{ User = $Value } }
        foreach ($Value in $Group) { $PrincipalSpecs += @{ Group = $Value } }

        if ($PrincipalSpecs.Count -eq 0) {
            $NoPrincipal = Resolve-OERPrincipalOrId -IdParameterName 'MemberId' -FriendlyParameterHint $Hint
            Write-CmdletError -Message ([System.Exception]::new($NoPrincipal.Message)) `
                -ErrorId $NoPrincipal.ErrorId -Category $NoPrincipal.Category `
                -TargetObject $AuId -Cmdlet $PSCmdlet
            return
        }

        foreach ($Spec in $PrincipalSpecs) {
            $Resolved = Resolve-OERPrincipalOrId @Spec -IdParameterName 'MemberId' `
                -InvalidIdErrorId 'InvalidMemberId' -FriendlyParameterHint $Hint
            if ($Resolved.ErrorId) {
                Write-CmdletError -Message ([System.Exception]::new($Resolved.Message)) `
                    -ErrorId $Resolved.ErrorId -Category $Resolved.Category `
                    -TargetObject $Resolved.TargetObject -Cmdlet $PSCmdlet
                continue
            }
            $Member = $Resolved.PrincipalId
            Write-Verbose "[Remove-OERAdministrativeUnitMember] Resolved principal to '$Member'."
            if ($PSCmdlet.ShouldProcess($AuId, "Remove member '$Member'")) {
                try {
                    Invoke-OERGraphRequest -Method DELETE -Uri ("v1.0/directory/administrativeUnits/{0}/members/{1}/`$ref" -f $AuId, $Member) | Out-Null
                } catch {
                    Remove-OERErrorRecord -Record $PSItem
                    $PSCmdlet.WriteError($PSItem)
                    continue
                }
            }
        }
    }
}
