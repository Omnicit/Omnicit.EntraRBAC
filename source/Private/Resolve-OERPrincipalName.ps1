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

    -Detailed (Sprint 11 step 6, BL-133, A18) answers the question the map cannot: whether an id was
    returned, not returned, or not looked up at all. It omits the 'types' filter, as -PreferDisplayName
    does, so every directory object type is searched, and returns one object per distinct input id, in
    input order: Id, Read, Found, Name, ObjectType and Cause. Read is false for every id of a batch whose
    request failed, with the failure's message as Cause (the record is scrubbed first) -- the failure is
    reported, never swallowed. Read true and Found true is an id the directory returned, with Name (a
    user's userPrincipalName, else the displayName, else the id) and ObjectType (the @odata.type without
    its '#microsoft.graph.' prefix, for example user, group, servicePrincipal or device). Read true and
    Found false is an id a successful batch did not return: deleted, or not readable. -Detailed and
    -PreferDisplayName belong to two parameter sets and cannot be combined. The default map, without
    -Detailed, is exactly what it was.

    .PARAMETER Id
    One or more directory object ids (GUIDs) to resolve. An empty collection returns an empty map (with
    -Detailed, nothing) and makes no Graph call.

    .PARAMETER PreferDisplayName
    Resolve every id to its displayName (falling back to the id itself when displayName is absent),
    instead of the default UPN-preferred selection. Use this for a PrincipalDisplayName property; never
    use it for the inventory's UPN-carrying 'principal' field. Also omits the getByIds 'types' filter,
    so every directory object type resolves (including device and foreignGroup principals, which an
    Azure role assignment can carry but the default user/group/servicePrincipal filter would miss) --
    matching the coverage of the per-principal GET this batching replaced.

    .PARAMETER Detailed
    Return one object per distinct id (Id, Read, Found, Name, ObjectType, Cause) instead of the map, so a
    caller can tell an id the directory returned from one it did not return and from one whose lookup
    failed. Omits the getByIds 'types' filter. Cannot be combined with -PreferDisplayName.

    .EXAMPLE
    Resolve-OERPrincipalName -Id @('11111111-1111-1111-1111-111111111111')
    Returns a hashtable mapping the id to the user's UPN (or the id itself when unresolvable).

    .EXAMPLE
    Resolve-OERPrincipalName -Id @('11111111-1111-1111-1111-111111111111') -PreferDisplayName
    Returns a hashtable mapping the id to the principal's displayName (or the id itself when
    unresolvable) -- never a UPN, even for a user.

    .EXAMPLE
    Resolve-OERPrincipalName -Id @('11111111-1111-1111-1111-111111111111') -Detailed
    Returns one object for the id: Found true with its Name and ObjectType when the directory returned
    it, Found false when a successful lookup did not, and Read false with the Cause when the lookup failed.
    #>
    [OutputType([hashtable], ParameterSetName = 'Map')]
    [OutputType([PSCustomObject], ParameterSetName = 'Detailed')]
    [CmdletBinding(DefaultParameterSetName = 'Map')]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [string[]]$Id,

        [Parameter(ParameterSetName = 'Map')]
        [switch]$PreferDisplayName,

        [Parameter(ParameterSetName = 'Detailed')]
        [switch]$Detailed
    )

    $Map = @{}
    $ToLookup = [System.Collections.Generic.List[string]]::new()
    foreach ($Single in $Id) {
        if ([string]::IsNullOrWhiteSpace($Single)) { continue }
        if (-not $ToLookup.Contains($Single)) { $ToLookup.Add($Single) }
    }
    if ($ToLookup.Count -eq 0) {
        if ($Detailed) { return }
        return $Map
    }

    # -Detailed: the answer per id, keyed without regard to letter case as the map is. An id whose batch
    # failed is stored with Read false; one the directory returned with Found true.
    $Answers = [System.Collections.Generic.Dictionary[string, object]]::new([System.StringComparer]::OrdinalIgnoreCase)

    $BatchSize = 1000
    for ($Offset = 0; $Offset -lt $ToLookup.Count; $Offset += $BatchSize) {
        $Count = [System.Math]::Min($BatchSize, $ToLookup.Count - $Offset)
        $Chunk = $ToLookup.GetRange($Offset, $Count)
        # -PreferDisplayName is used by Get-OERRoleAssignment, whose ARM principals can be any
        # directory object type (including device and foreignGroup, per Get-OERInventory's own
        # comments on role assignment principal types) -- so the type filter is omitted there and
        # Graph searches every directoryObject type. -Detailed omits it for the same reason. The
        # default path keeps the narrower filter unchanged.
        $Body = @{ ids = @($Chunk) }
        if (-not $PreferDisplayName -and -not $Detailed) { $Body.types = @('user', 'group', 'servicePrincipal') }
        $Response = $null
        try {
            $Response = Invoke-OERGraphRequest -Method POST -Uri 'v1.0/directoryObjects/getByIds' -Body $Body
        } catch {
            Remove-OERErrorRecord -Record $PSItem
            $Response = $null
            # -Detailed reports the failure for every id of the batch: an id that was not looked up is
            # not an id the directory did not return.
            if ($Detailed) {
                $BatchCause = [string]$PSItem.Exception.Message
                foreach ($Single in $Chunk) {
                    $Answers[$Single] = [PSCustomObject]@{ Id = $Single; Read = $false; Found = $false; Name = $null; ObjectType = $null; Cause = $BatchCause }
                }
            }
            continue
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
            if ($Detailed) {
                $ObjectType = ([string]$Obj.'@odata.type') -replace '^#microsoft\.graph\.', ''
                $Answers[$ObjId] = [PSCustomObject]@{
                    Id = $ObjId; Read = $true; Found = $true; Name = $Name
                    ObjectType = $(if ($ObjectType) { $ObjectType } else { $null }); Cause = $null
                }
            }
        }
    }

    if ($Detailed) {
        # One answer per distinct id, in input order. An id a successful batch did not return is read and
        # not found.
        foreach ($Single in $ToLookup) {
            if ($Answers.ContainsKey($Single)) {
                $Answer = $Answers[$Single]
                [PSCustomObject]@{ Id = $Single; Read = $Answer.Read; Found = $Answer.Found; Name = $Answer.Name; ObjectType = $Answer.ObjectType; Cause = $Answer.Cause }
            } else {
                [PSCustomObject]@{ Id = $Single; Read = $true; Found = $false; Name = $null; ObjectType = $null; Cause = $null }
            }
        }
        return
    }

    foreach ($Single in $ToLookup) {
        if (-not $Map.ContainsKey($Single)) { $Map[$Single] = $Single }
    }
    return $Map
}
