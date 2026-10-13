function Get-OERGroupPimHeldAccess {
    <#
    .SYNOPSIS
    Returns the principals whose access to a group PIM for Groups holds or makes eligible, one object
    per principal and access type, each with the reason worded for an operator.

    .DESCRIPTION
    The single owner of the rule that tells a member or owner whose access PIM for Groups holds from
    a standing one (BL-125, A3). Given the group's PIM for Groups assignment schedule instances
    (Read-OERGroupPimAssignment) and, optionally, its eligibility schedule instances, it returns one
    tagged Omnicit.EntraRBAC.GroupPimHeldAccess object for every principal and access type that PIM
    for Groups holds or makes eligible. A principal it does not return is a standing one, or not
    named at all.

    The rule (docs/development/rationale.md#pim-activation-is-not-membership). An assignment schedule
    instance holds its principal's access through PIM for Groups unless it is a standing one: its
    assignmentType is 'assigned' (compared without regard to letter case) AND it has no endDateTime.
    Graph lists a membership or ownership added outside PIM in exactly that standing shape (measured
    live 2026-10-13), and it is never returned. Every other instance is returned, with the Kind:
    - Activated when its assignmentType is 'activated';
    - otherwise TimeBound when it has an endDateTime;
    - otherwise Unrecognized (any other assignmentType, or none).
    An endDateTime counts as set when it is not null and does not read as blank text, so a DateTime
    object (the shape the Graph SDK hands back) counts as set. memberType is never consulted. Every
    eligibility schedule instance is returned with the Kind Eligible.

    The access type is the instance's accessId in lower case, and 'member' when the instance has none.
    Graph names 'member' and 'owner'; any other value -- a later enum value such as
    unknownFutureValue -- is passed through lower-cased, not mapped, and a caller matches member and
    owner only, so such an instance leaves nobody out of either collection. The principal id is the
    instance's principalId in lower case, so a caller compares ids without regard to letter case; an
    instance with no principalId is skipped.

    At most one object is returned per principal id and access type. An assignment kind wins over
    Eligible for the same principal and access type, and among assignment kinds the first instance in
    input order wins. A principal that is a standing member and activated as an owner is therefore
    returned once, for owner access: access is matched per access type, never per principal alone.
    Objects come out in the order their principal and access type was first found, the assignments
    first.

    Each object carries PrincipalId, AccessType, Kind and Reason. Reason is the wording this function
    owns, so every caller names the hold the same way:
    - Activated: 'holds <access> access through an activation in PIM for Groups'
    - TimeBound: 'holds <access> access through a time-bound active assignment in PIM for Groups'
    - Unrecognized: 'holds <access> access through a PIM for Groups active assignment that is not a
      standing one'
    - Eligible: 'is eligible for <access> access in PIM for Groups'

    It is pure: it makes no request, writes nothing to any stream but its objects, and reads only the
    instances it is given.

    .PARAMETER Assignment
    The group's PIM for Groups assignment schedule instances, as Read-OERGroupPimAssignment returns
    them in its Value (hashtables or objects carrying principalId, accessId, assignmentType and
    endDateTime). Null or empty returns no assignment kind.

    .PARAMETER Eligibility
    The group's PIM for Groups eligibility schedule instances (carrying principalId and accessId).
    Null or empty returns no Eligible object.

    .EXAMPLE
    $Held = @(Get-OERGroupPimHeldAccess -Assignment $AssignmentRead.Value)
    $Held | Where-Object { $_.AccessType -eq 'member' } | ForEach-Object { $_.PrincipalId }
    Lists the ids of the members whose membership PIM for Groups holds -- an activation, a time-bound
    active assignment, or an active assignment that is not a standing one.

    .EXAMPLE
    Get-OERGroupPimHeldAccess -Assignment $AssignmentRead.Value -Eligibility $Group.PimEligibility
    Returns every principal PIM for Groups holds or makes eligible, one object per principal and
    access type, an assignment kind winning over Eligible.
    #>
    [OutputType([PSCustomObject])]
    [CmdletBinding()]
    param(
        [AllowNull()]
        [AllowEmptyCollection()]
        [object[]]$Assignment,

        [AllowNull()]
        [AllowEmptyCollection()]
        [object[]]$Eligibility
    )

    # One entry per '<principal id>|<access type>', in the order first found: the assignments are
    # walked first, so an assignment kind is in place before an eligibility of the same principal and
    # access could claim the key, and the first assignment instance of a key keeps it.
    $Found = [ordered]@{}

    $NewHeld = {
        param([string]$PrincipalId, [string]$AccessType, [string]$Kind)
        $Reason = switch ($Kind) {
            'Activated'    { "holds $AccessType access through an activation in PIM for Groups" }
            'TimeBound'    { "holds $AccessType access through a time-bound active assignment in PIM for Groups" }
            'Unrecognized' { "holds $AccessType access through a PIM for Groups active assignment that is not a standing one" }
            'Eligible'     { "is eligible for $AccessType access in PIM for Groups" }
        }
        $O = [PSCustomObject]@{
            PrincipalId = $PrincipalId
            AccessType  = $AccessType
            Kind        = $Kind
            Reason      = $Reason
        }
        $O.PSObject.TypeNames.Insert(0, 'Omnicit.EntraRBAC.GroupPimHeldAccess')
        $O
    }

    # The principal id and the access type of one instance, both lower case; $null for an instance
    # that names no principal.
    $KeyOf = {
        param([object]$Instance)
        $PrincipalId = [string]$Instance.principalId
        if ([string]::IsNullOrWhiteSpace($PrincipalId)) { return $null }
        $AccessType = [string]$Instance.accessId
        if ([string]::IsNullOrWhiteSpace($AccessType)) { $AccessType = 'member' }
        [PSCustomObject]@{ PrincipalId = $PrincipalId.ToLowerInvariant(); AccessType = $AccessType.ToLowerInvariant() }
    }

    foreach ($Instance in @($Assignment)) {
        if ($null -eq $Instance) { continue }
        $Key = & $KeyOf $Instance
        if ($null -eq $Key) { continue }
        # The rule. -eq compares text without regard to letter case, so 'Assigned' and 'Activated' read
        # as Graph's lower-case values do. A DateTime end is "set": it is not null and reads as text.
        $End = $Instance.endDateTime
        $EndSet = $null -ne $End -and -not [string]::IsNullOrWhiteSpace([string]$End)
        $Type = [string]$Instance.assignmentType
        if ($Type -eq 'assigned' -and -not $EndSet) { continue }
        $Kind = if ($Type -eq 'activated') { 'Activated' } elseif ($EndSet) { 'TimeBound' } else { 'Unrecognized' }
        $Id = "$($Key.PrincipalId)|$($Key.AccessType)"
        if ($Found.Contains($Id)) { continue }
        $Found[$Id] = & $NewHeld $Key.PrincipalId $Key.AccessType $Kind
    }

    foreach ($Instance in @($Eligibility)) {
        if ($null -eq $Instance) { continue }
        $Key = & $KeyOf $Instance
        if ($null -eq $Key) { continue }
        $Id = "$($Key.PrincipalId)|$($Key.AccessType)"
        if ($Found.Contains($Id)) { continue }
        $Found[$Id] = & $NewHeld $Key.PrincipalId $Key.AccessType 'Eligible'
    }

    foreach ($Held in $Found.Values) { $Held }
}
