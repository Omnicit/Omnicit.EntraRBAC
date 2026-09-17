function Get-OERAdministrativeUnit {
    <#
    .SYNOPSIS
    Reads one or more Entra ID administrative units by id, display name, or OData filter.

    .DESCRIPTION
    Retrieves administrative units through Microsoft Graph and returns them as tagged
    Omnicit.EntraRBAC.AdministrativeUnit objects. Supply -AdministrativeUnit as either an object id (GUID)
    for a direct read or a display name for an exact display-name match, -Filter for an arbitrary OData
    filter expression, or no selector at all to list every administrative unit in the tenant. With
    -IncludeMembers the unit's members are attached as a Members property; with -IncludeScopedRoles the
    unit's scoped role members are attached as a ScopedRoles property (tagged
    Omnicit.EntraRBAC.AdministrativeUnitScopedRole). A named unit that does not exist produces a
    non-terminating AdministrativeUnitNotFound error. For each of those two collections, the property
    is attached only when its read succeeds; a failed read omits the property entirely and raises a
    non-terminating error instead, so an empty array in the result always means the unit genuinely
    has none.

    .PARAMETER AdministrativeUnit
    The administrative unit to read, given as either its object id (GUID) or its exact display name --
    the same name-or-GUID target the other administrative-unit cmdlets accept. Binds from the pipeline
    by property name, and still accepts the historical -Id, -AdministrativeUnitId and -DisplayName
    parameter names as aliases. AdministrativeUnitId precedes Id and DisplayName during pipeline
    binding so a piped administrative-unit-member object binds the parent unit's id instead of the
    member's own Id/DisplayName.

    .PARAMETER Filter
    An OData filter expression (without the $filter= prefix) used to query administrative units.

    .PARAMETER IncludeMembers
    When set, attaches the unit's members as a Members property on the returned object. The property
    is present only when the read succeeds; a failed read is reported as a non-terminating
    AdministrativeUnitMemberReadFailed error and the Members property is omitted, so a returned empty
    array always means the unit has no members.

    .PARAMETER IncludeScopedRoles
    When set, attaches the unit's scoped role members as a ScopedRoles property on the returned object.
    The property is present only when the read succeeds; a failed read is reported as a
    non-terminating AdministrativeUnitScopedRoleReadFailed error and the ScopedRoles property is
    omitted, so a returned empty array always means the unit has no scoped role members.

    .PARAMETER TenantId
    Optional tenant id or domain to authenticate against, forwarded to Initialize-OERAuth.

    .EXAMPLE
    Get-OERAdministrativeUnit -AdministrativeUnit 'au_hr' -IncludeMembers
    Returns the administrative unit with its members attached.

    .EXAMPLE
    Get-OERAdministrativeUnit -DisplayName 'au_hr'
    Returns the unit, using the historical -DisplayName alias for -AdministrativeUnit.

    .EXAMPLE
    Get-OERAdministrativeUnit -Filter "startswith(displayName,'au_')"
    Returns every administrative unit whose display name starts with au_.

    .EXAMPLE
    Get-OERAdministrativeUnit -IncludeMembers -IncludeScopedRoles
    Lists every administrative unit in the tenant with members and scoped roles attached.
    #>
    [CmdletBinding(DefaultParameterSetName = 'List')]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(ParameterSetName = 'ByAdministrativeUnit', Mandatory, ValueFromPipelineByPropertyName)]
        # AdministrativeUnitId precedes Id/DisplayName so a piped AdministrativeUnitMember object binds
        # the parent unit's id, not the member's own Id/DisplayName, during ValueFromPipelineByPropertyName
        # alias resolution.
        [Alias('AdministrativeUnitId', 'Id', 'DisplayName')]
        [string]$AdministrativeUnit,

        [Parameter(ParameterSetName = 'ByFilter', Mandatory)]
        [string]$Filter,

        [switch]$IncludeMembers,
        [switch]$IncludeScopedRoles,
        [string]$TenantId
    )
    begin {
        $AuthParams = @{}
        if ($TenantId) { $AuthParams.TenantId = $TenantId }
        Initialize-OERAuth @AuthParams
    }
    process {
        try {
            $Raw = switch ($PSCmdlet.ParameterSetName) {
                'List' { @((Invoke-OERGraphRequest -Uri 'v1.0/directory/administrativeUnits' -All).value) }
                'ByAdministrativeUnit' {
                    if (Test-OERGuid -Value $AdministrativeUnit) {
                        , @(Invoke-OERGraphRequest -Uri ("v1.0/directory/administrativeUnits/{0}" -f $AdministrativeUnit))
                    }
                    else {
                        $Escaped = ConvertTo-OERODataFilterValue -Value $AdministrativeUnit
                        @((Invoke-OERGraphRequest -Uri "v1.0/directory/administrativeUnits?`$filter=displayName eq '$Escaped'").value)
                    }
                }
                'ByFilter' {
                    $Encoded = [System.Uri]::EscapeDataString($Filter)
                    @((Invoke-OERGraphRequest -Uri "v1.0/directory/administrativeUnits?`$filter=$Encoded" -All).value)
                }
            }
        } catch {
            Remove-OERErrorRecord -Record $PSItem
            $PSCmdlet.WriteError($PSItem)
            return
        }

        $Raw = @($Raw | Where-Object { $_ })
        if ($Raw.Count -eq 0) {
            # Listing every unit in a tenant that simply has none is not an error.
            if ($PSCmdlet.ParameterSetName -eq 'List') { return }
            $Target = if ($PSCmdlet.ParameterSetName -eq 'ByFilter') { $Filter } else { $AdministrativeUnit }
            Write-CmdletError `
                -Message ([System.Exception]::new("No administrative unit found for '$Target'.")) `
                -ErrorId 'AdministrativeUnitNotFound' `
                -Category ObjectNotFound `
                -TargetObject $Target `
                -Cmdlet $PSCmdlet
            return
        }

        foreach ($GraphAu in $Raw) {
            $Au = ConvertTo-OERAdministrativeUnit -InputObject $GraphAu
            if ($IncludeMembers) {
                # A failed read is NOT an empty membership -- see Get-OERGroup for the full rule and
                # issue #76 for the chain. The property is omitted and the failure is a
                # non-terminating error so -ErrorAction and -ErrorVariable can see it.
                $Members = $null
                $MembersRead = $true
                try {
                    $Members = @((Invoke-OERGraphRequest -Uri ("v1.0/directory/administrativeUnits/{0}/members" -f $Au.Id) -All).value)
                    $Members = @($Members | Where-Object { $_ } | ForEach-Object { ConvertTo-OERAdministrativeUnitMember -InputObject $_ -AdministrativeUnitId $Au.Id })
                } catch {
                    Remove-OERErrorRecord -Record $PSItem
                    $MembersRead = $false
                    Write-CmdletError `
                        -Message ([System.Exception]::new("Could not read members for administrative unit $($Au.Id): $($PSItem.Exception.Message). The Members property is omitted rather than reported as empty.")) `
                        -ErrorId 'AdministrativeUnitMemberReadFailed' `
                        -Category ReadError `
                        -TargetObject $Au.Id `
                        -InnerException $PSItem.Exception `
                        -Cmdlet $PSCmdlet
                }
                if ($MembersRead) {
                    $Au | Add-Member -NotePropertyName Members -NotePropertyValue $Members -Force
                }
            }
            if ($IncludeScopedRoles) {
                # Same rule as members: an omitted scopedRoles key in an apply document still
                # reconciles and still prunes, so a failed read must not be written as an empty set.
                $Scoped = $null
                $ScopedRead = $true
                try {
                    $Scoped = @((Invoke-OERGraphRequest -Uri ("v1.0/directory/administrativeUnits/{0}/scopedRoleMembers" -f $Au.Id) -All).value)
                    $RoleMap = Get-OERDirectoryRoleNameMap
                    $Scoped = @($Scoped | ForEach-Object { ConvertTo-OERScopedRoleMember -InputObject $_ -RoleName ([string]$RoleMap[[string]$_.roleId]) })
                } catch {
                    Remove-OERErrorRecord -Record $PSItem
                    $ScopedRead = $false
                    Write-CmdletError `
                        -Message ([System.Exception]::new("Could not read scoped roles for administrative unit $($Au.Id): $($PSItem.Exception.Message). The ScopedRoles property is omitted rather than reported as empty.")) `
                        -ErrorId 'AdministrativeUnitScopedRoleReadFailed' `
                        -Category ReadError `
                        -TargetObject $Au.Id `
                        -InnerException $PSItem.Exception `
                        -Cmdlet $PSCmdlet
                }
                if ($ScopedRead) {
                    $Au | Add-Member -NotePropertyName ScopedRoles -NotePropertyValue $Scoped -Force
                }
            }
            $Au
        }
    }
}
