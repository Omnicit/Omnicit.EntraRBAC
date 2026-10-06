function Get-OERGroupRelation {
    <#
    .SYNOPSIS
    Reads a group's members or owners in full, service principals included.

    .DESCRIPTION
    The single reader of a group's members and owners collections, used by Get-OERGroup
    (-IncludeMembers, -IncludeOwners) and Get-OERGroupMember. Microsoft Graph's v1.0
    groups/{id}/members and groups/{id}/owners do not list a service principal (a Microsoft Learn
    known issue for members, and a note on List group owners; measured 2026-10-06, live checklist
    fix-read-service-principal-group-members, checks 1.1 and 1.2). So the untyped collection is
    read, then the typed groups/{id}/{relation}/microsoft.graph.servicePrincipal collection, both
    with -All. The results are merged on id, case-insensitively and without duplicates: the untyped
    read's order first, then what only the typed read added. Each object is converted through
    ConvertTo-OERGroupMember; an object whose id the typed read lists carries ObjectType
    servicePrincipal even when Graph answers without an @odata.type annotation, which the typed
    read does (measured).

    A collection is read whole or not at all. Nothing is emitted until both reads have succeeded,
    and a failure of either read is not caught here: it propagates to the caller, whose catch
    reports it. Half a collection would let a later -Prune remove what the missing half held. Call
    it only inside a try (or with -ErrorAction Stop inside one): outside any try a caller can
    continue past the failed read, and the untyped half would then be emitted.

    Why the collection is read twice, what was measured, and what the second read costs an apply
    document: docs/development/rationale.md#typed-group-member-read.

    .PARAMETER GroupId
    The object id of the group whose collection is read.

    .PARAMETER Relation
    Which collection to read: members or owners. Members are emitted with MemberType Member,
    owners with MemberType Owner.

    .EXAMPLE
    Get-OERGroupRelation -GroupId $Group.Id -Relation owners
    Returns every owner of the group, service principals included, as GroupMember objects.
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory)]
        [string]$GroupId,

        [Parameter(Mandatory)]
        [ValidateSet('members', 'owners')]
        [string]$Relation
    )
    $MemberType = if ($Relation -eq 'owners') { 'Owner' } else { 'Member' }
    # The object types the untyped v1.0 read leaves out, each read typed. Measured 2026-10-06:
    # service principals only (members and owners); the user, group, device and organizational
    # contact casts showed nothing missing. Add a type here only after measuring it.
    # Why: docs/development/rationale.md#typed-group-member-read
    $TypedReadTypes = @('servicePrincipal')

    $Untyped = @(@((Invoke-OERGraphRequest -Uri ('v1.0/groups/{0}/{1}' -f $GroupId, $Relation) -All).value) |
            Where-Object { $null -ne $_ })
    $TypeOfId = @{}
    $TypedAdded = [System.Collections.Generic.List[object]]::new()
    foreach ($Type in $TypedReadTypes) {
        $Rows = @(@((Invoke-OERGraphRequest -Uri ('v1.0/groups/{0}/{1}/microsoft.graph.{2}' -f $GroupId, $Relation, $Type) -All).value) |
                Where-Object { $null -ne $_ })
        foreach ($Row in $Rows) {
            $TypeOfId[([string]$Row.id).ToLowerInvariant()] = $Type
            $TypedAdded.Add([PSCustomObject]@{ Row = $Row; Type = $Type })
        }
    }

    # Both reads succeeded: only now is anything emitted.
    $Seen = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($Row in $Untyped) {
        $null = $Seen.Add([string]$Row.id)
        ConvertTo-OERGroupMember -InputObject $Row -GroupId $GroupId -MemberType $MemberType `
            -DefaultObjectType $TypeOfId[([string]$Row.id).ToLowerInvariant()]
    }
    foreach ($Added in $TypedAdded) {
        if (-not $Seen.Add([string]$Added.Row.id)) { continue }
        ConvertTo-OERGroupMember -InputObject $Added.Row -GroupId $GroupId -MemberType $MemberType -DefaultObjectType $Added.Type
    }
}
