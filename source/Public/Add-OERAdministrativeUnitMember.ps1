function Add-OERAdministrativeUnitMember {
    <#
    .SYNOPSIS
    Adds one or more existing principals (users, groups, or devices) as members of an administrative unit.

    .DESCRIPTION
    Adds each principal in -MemberId to the administrative unit identified by -AdministrativeUnit through
    the unit's members/$ref navigation endpoint. Each principal is processed individually so a failure on
    one (for example, one that is already a member) is reported without stopping the remaining additions.
    A unit that cannot be resolved produces a non-terminating AdministrativeUnitNotFound error. To create a
    new group directly inside a (restricted) administrative unit, use New-OERGroup -AdministrativeUnit
    instead. Supports -WhatIf and -Confirm.

    Members may be given as raw object ids with -MemberId or by name with -User (user principal name) and
    -Group (group display name); the parameters are unioned into a single run. A non-GUID value passed to
    -MemberId produces a non-terminating InvalidMemberId error naming the friendly alternatives instead of
    an opaque members/$ref failure. Devices are added by object id with -MemberId.

    .PARAMETER AdministrativeUnit
    The administrative unit to add the members to, given as either its object id (GUID) or its display
    name. Binds from the pipeline by property name, and still accepts the historical -Id,
    -AdministrativeUnitId and -DisplayName parameter names as aliases.

    .PARAMETER MemberId
    One or more object ids of the users, groups, or devices to add as members of the administrative unit.
    Must be canonical GUIDs; to name a user or group instead, use -User or -Group. Also bindable as
    -PrincipalId, the name the group-membership and scoped-role cmdlets use for the same concept, and
    binds from the pipeline by property name through that alias, so a ConvertTo-OERAdministrativeUnitMember
    object pipes straight back in. A ConvertTo-OERGroupMember object does NOT: it carries no
    AdministrativeUnitId, so its own Id (the principal) would bind -AdministrativeUnit through the Id
    alias instead.

    .PARAMETER User
    One or more users to add, each given as a user principal name or object id (GUID) and resolved via
    Resolve-OERPrincipal. Combined with -MemberId and -Group rather than exclusive.

    .PARAMETER Group
    One or more groups to add, each given as a group display name or object id (GUID) and resolved via
    Resolve-OERPrincipal. Combined with -MemberId and -User rather than exclusive. Group display names
    are not guaranteed unique in Entra ID; if more than one group shares the given name, the command
    fails with an error naming the candidate object ids, so re-run with the object id.

    .PARAMETER TenantId
    Optional tenant id or domain to authenticate against, forwarded to Initialize-OERAuth.

    .EXAMPLE
    Add-OERAdministrativeUnitMember -AdministrativeUnit 'au_hr' -MemberId $UserId
    Adds the user as a member of the named administrative unit.

    .EXAMPLE
    Add-OERAdministrativeUnitMember -AdministrativeUnit $AuId -MemberId $GroupId1, $GroupId2
    Adds two groups as members of the administrative unit.

    .EXAMPLE
    Add-OERAdministrativeUnitMember -AdministrativeUnit 'au_hr' -User 'anna.berg@contoso.com' -Group 'Sales Team'
    Adds a user (by UPN) and a group (by display name) to the named administrative unit.
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
        # Resolved once per invocation, immediately after Initialize-OERAuth populates the session
        # state it reads -- not per principal in the loop below, since Initialize-OERAuth itself
        # runs once per invocation and the session's cloud cannot change between pipeline items of
        # the same call.
        $GraphServiceRoot = Get-OERGraphServiceRoot
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
        Write-Verbose "[Add-OERAdministrativeUnitMember] Resolved administrative unit to '$AuId'."

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
            Write-Verbose "[Add-OERAdministrativeUnitMember] Resolved principal to '$Member'."
            $Body = @{ '@odata.id' = "$GraphServiceRoot/directoryObjects/$Member" }
            if ($PSCmdlet.ShouldProcess($AuId, "Add member '$Member'")) {
                try {
                    Invoke-OERGraphRequest -Method POST -Uri ("v1.0/directory/administrativeUnits/{0}/members/`$ref" -f $AuId) -Body $Body | Out-Null
                } catch {
                    Remove-OERErrorRecord -Record $PSItem
                    $PSCmdlet.WriteError($PSItem)
                    continue
                }
            }
        }
    }
}
