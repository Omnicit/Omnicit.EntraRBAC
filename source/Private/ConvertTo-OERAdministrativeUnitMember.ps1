function ConvertTo-OERAdministrativeUnitMember {
    <#
    .SYNOPSIS
    Converts a raw Microsoft Graph administrative unit member (directoryObject) into a tagged
    Omnicit.EntraRBAC.AdministrativeUnitMember object.

    .DESCRIPTION
    Maps a Graph member object (a user, group, or device returned from an administrative unit's members
    collection) into a [PSCustomObject] tagged with the type name Omnicit.EntraRBAC.AdministrativeUnitMember
    so Format and Types views apply. The member kind is derived from the Graph @odata.type annotation (for
    example '#microsoft.graph.user' becomes 'user') and surfaced as ObjectType, the same name
    ConvertTo-OERGroupMember uses; the historical Type property is kept as an alias of it. When the
    annotation is absent ObjectType is $null. PrincipalId is the only STORED copy of the member's id;
    Id is registered as an AliasProperty of it in suffix.ps1 (Task 8a), mirroring ConvertTo-OERGroupMember,
    so piped output still round-trips, via -MemberId's -PrincipalId alias
    (ValueFromPipelineByPropertyName binding), into both Add-OERAdministrativeUnitMember and
    Remove-OERAdministrativeUnitMember. AdministrativeUnitId
    carries the id of the unit the member belongs to (when the caller supplies -AdministrativeUnitId),
    so the same piped object also binds, via the AdministrativeUnitId alias on the unified
    -AdministrativeUnit parameter, into the cmdlets whose target IS the parent unit:
    Get-OERAdministrativeUnit, Add-OERAdministrativeUnitScopedRole and
    Remove-OERAdministrativeUnitScopedRole. Read that binding literally rather than as a round trip.
    Set-OERAdministrativeUnit and Remove-OERAdministrativeUnit also accept the piped object through
    the same alias, but they act on the PARENT UNIT -- piping a member into
    Remove-OERAdministrativeUnit deletes the whole unit, not that member. To remove the member itself,
    pipe into Remove-OERAdministrativeUnitMember, which binds the member through -MemberId's
    -PrincipalId alias as described above. This private converter is the single owner of the AU
    member output shape and is used by Get-OERAdministrativeUnit -IncludeMembers.

    .PARAMETER InputObject
    The raw Graph member object (hashtable or PSObject) to convert into a tagged object.

    .PARAMETER AdministrativeUnitId
    The id of the administrative unit the member belongs to, stamped onto the output as
    AdministrativeUnitId. Optional; $null when the caller does not supply it.

    .EXAMPLE
    $Member = ConvertTo-OERAdministrativeUnitMember -InputObject $GraphMember -AdministrativeUnitId $Au.Id
    Converts a single administrative unit member into a tagged object, stamped with its parent unit's id.
    #>
    [OutputType([PSCustomObject])]
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
        $InputObject,

        # Declared LAST: this module has no Position attributes, so declaration order is positional
        # binding order and inserting a parameter earlier would silently re-bind existing calls.
        [string]$AdministrativeUnitId
    )
    process {
        $OdataType = $InputObject.'@odata.type'
        $ObjectType = if ($OdataType) { ($OdataType -replace '^#microsoft\.graph\.', '') } else { $null }
        $Out = [PSCustomObject]@{
            PrincipalId          = $InputObject.id
            DisplayName          = $InputObject.displayName
            UserPrincipalName    = $InputObject.userPrincipalName
            ObjectType           = $ObjectType
            AdministrativeUnitId = $AdministrativeUnitId
        }
        $Out.PSObject.TypeNames.Insert(0, 'Omnicit.EntraRBAC.AdministrativeUnitMember')
        $Out
    }
}
