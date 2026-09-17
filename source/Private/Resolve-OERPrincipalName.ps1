function Resolve-OERPrincipalName {
    <#
    .SYNOPSIS
    Batch-resolves directory object ids to friendly names via the getByIds Graph function.

    .DESCRIPTION
    Resolves a set of directory object ids to friendly names through a single POST to
    v1.0/directoryObjects/getByIds per 1000 ids (the documented batch limit), via
    Invoke-OERGraphRequest. By default the request is restricted to types=user,group,servicePrincipal
    and users resolve to their userPrincipalName (groups and service principals to their displayName)
    -- this is the shape Get-OERInventory needs for its 'principal' apply-document field, whose '@'
    heuristic requires a UPN. With -PreferDisplayName the 'types' filter is omitted entirely (Graph
    defaults an omitted 'types' to the full directoryObject set, covering every directory object type
    the tenant has, not just the three named above), and every principal type resolves to its
    displayName instead (falling straight back to the id, never a UPN) -- this is the shape a
    PrincipalDisplayName property needs per the module's property-naming rule. The result is a
    hashtable mapping each input id to its resolved name. Duplicate and empty/whitespace ids are
    de-duplicated before the call; an id the directory does not return (deleted, or not readable) falls
    back to the id itself, so the map always contains every input id. A Graph failure is swallowed and
    all ids in that batch fall back to their id; this helper never throws. It performs no authentication
    of its own -- the caller authenticates before calling it.

    .PARAMETER Id
    One or more directory object ids (GUIDs) to resolve. An empty collection returns an empty map and
    makes no Graph call.

    .PARAMETER PreferDisplayName
    Resolve every id to its displayName (falling back to the id itself when displayName is absent),
    instead of the default UPN-preferred selection. Use this for a PrincipalDisplayName property; never
    use it for the inventory's UPN-carrying 'principal' field. Also omits the getByIds 'types' filter,
    so every directory object type resolves (including device and foreignGroup principals, which an
    Azure role assignment can carry but the default user/group/servicePrincipal filter would miss) --
    matching the coverage of the per-principal GET this batching replaced.

    .EXAMPLE
    Resolve-OERPrincipalName -Id @('11111111-1111-1111-1111-111111111111')
    Returns a hashtable mapping the id to the user's UPN (or the id itself when unresolvable).

    .EXAMPLE
    Resolve-OERPrincipalName -Id @('11111111-1111-1111-1111-111111111111') -PreferDisplayName
    Returns a hashtable mapping the id to the principal's displayName (or the id itself when
    unresolvable) -- never a UPN, even for a user.
    #>
    [OutputType([hashtable])]
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [string[]]$Id,

        [switch]$PreferDisplayName
    )

    $Map = @{}
    $ToLookup = [System.Collections.Generic.List[string]]::new()
    foreach ($Single in $Id) {
        if ([string]::IsNullOrWhiteSpace($Single)) { continue }
        if (-not $ToLookup.Contains($Single)) { $ToLookup.Add($Single) }
    }
    if ($ToLookup.Count -eq 0) { return $Map }

    $BatchSize = 1000
    for ($Offset = 0; $Offset -lt $ToLookup.Count; $Offset += $BatchSize) {
        $Count = [System.Math]::Min($BatchSize, $ToLookup.Count - $Offset)
        $Chunk = $ToLookup.GetRange($Offset, $Count)
        # -PreferDisplayName is used by Get-OERRoleAssignment, whose ARM principals can be any
        # directory object type (including device and foreignGroup, per Get-OERInventory's own
        # comments on role assignment principal types) -- so the type filter is omitted there and
        # Graph searches every directoryObject type. The default path (Get-OERInventory's UPN lookup)
        # keeps the narrower filter unchanged.
        $Body = @{ ids = @($Chunk) }
        if (-not $PreferDisplayName) { $Body.types = @('user', 'group', 'servicePrincipal') }
        $Response = $null
        try {
            $Response = Invoke-OERGraphRequest -Method POST -Uri 'v1.0/directoryObjects/getByIds' -Body $Body
        } catch {
            Remove-OERErrorRecord -Record $PSItem
            $Response = $null
        }
        foreach ($Obj in @($Response.value)) {
            if ($null -eq $Obj) { continue }
            $ObjId = [string]$Obj.id
            if ([string]::IsNullOrEmpty($ObjId)) { continue }
            $Name = if ($PreferDisplayName) {
                if ($Obj.displayName) { [string]$Obj.displayName } else { $ObjId }
            } elseif ($Obj.userPrincipalName) {
                [string]$Obj.userPrincipalName
            } elseif ($Obj.displayName) {
                [string]$Obj.displayName
            } else {
                $ObjId
            }
            $Map[$ObjId] = $Name
        }
    }

    foreach ($Single in $ToLookup) {
        if (-not $Map.ContainsKey($Single)) { $Map[$Single] = $Single }
    }
    return $Map
}
