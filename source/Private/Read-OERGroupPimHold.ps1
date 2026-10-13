function Read-OERGroupPimHold {
    <#
    .SYNOPSIS
    Reads whether PIM for Groups holds a group's members and owners or makes them eligible, and
    returns one lookup the apply engine consults per principal and access type.

    .DESCRIPTION
    The apply engine's one read of a group's PIM for Groups hold (BL-125, decision A3).
    Sync-OERStructureGroup calls it at most once per group item, and only when a member or owner it
    would add or prune reaches its PIM check, so that it never adds a standing membership or
    ownership for a principal whose access PIM for Groups holds or makes eligible, and never prunes
    one.

    It makes two reads and never a third:
    - the group's PIM for Groups assignment schedule instances, always through
      Read-OERGroupPimAssignment;
    - the group's PIM for Groups eligibility schedule instances, through
      Read-OERGroupCollection -Collection PimEligibility -- unless the caller passes -EligibilityRead,
      in which case the eligibility given in -Eligibility (empty or null included) is used as read
      and no eligibility request is made. The engine passes the eligibility its own group read
      returned when the document entry declares eligibility, so that read is never made twice.
    Both reads are made even when the first one fails, so a failure of each is named.

    When both reads succeeded, Get-OERGroupPimHeldAccess -- the single owner of the rule that tells
    a member or owner PIM for Groups holds from a standing one -- turns them into the Held lookup.
    This function applies no rule of its own.

    It returns ONE tagged Omnicit.EntraRBAC.GroupPimHold object and never writes an error record or
    a warning:
    - Read: true only when both reads succeeded.
    - Held: a hashtable keyed '<principal id>|<access type>' in lower case (for example
      'u-1|member'), whose value is the reason Get-OERGroupPimHeldAccess words for that principal
      and access type (for example 'is eligible for member access in PIM for Groups'). A principal
      and access type it does not hold -- a standing member or owner, or one not named at all -- is
      not a key. Empty when Read is false: a lookup that was not read decides nothing.
    - Cause: null when Read is true; otherwise the message of each failed read, the assignment read
      first, joined with '; '. The eligibility read's message is given without its closing sentence
      that the PimEligibility property is omitted, which describes Get-OERGroup's output and not the
      apply engine's.

    It makes no sign-in of its own; the calling command must already have signed in
    (Initialize-OERAuth).

    .PARAMETER GroupId
    The object id of the group whose PIM for Groups hold is read. An empty or null id is accepted
    and passed on as given, as the two readers do.

    .PARAMETER Eligibility
    The group's PIM for Groups eligibility schedule instances, as the caller already read them
    (carrying principalId and accessId). Used only with -EligibilityRead; null or empty means the
    read found none.

    .PARAMETER EligibilityRead
    Says that -Eligibility holds a successful eligibility read, so no eligibility request is made.
    Without it the eligibility is read with Read-OERGroupCollection -Collection PimEligibility and
    -Eligibility is ignored.

    .EXAMPLE
    $Hold = Read-OERGroupPimHold -GroupId $Gid
    if (-not $Hold.Read) { Write-Warning $Hold.Cause }
    elseif ($Hold.Held.ContainsKey(('{0}|member' -f $PrincipalId).ToLowerInvariant())) { 'held' }

    Reads both PIM for Groups collections of a group and asks whether a principal's member access
    is held or eligible.

    .EXAMPLE
    Read-OERGroupPimHold -GroupId $Gid -Eligibility @($Group.PimEligibility) -EligibilityRead

    Reads only the assignment schedule instances, and uses the eligibility the caller's own group
    read already returned.
    #>
    [OutputType([PSCustomObject])]
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowNull()]
        [AllowEmptyString()]
        [string]$GroupId,

        [AllowNull()]
        [AllowEmptyCollection()]
        [object[]]$Eligibility,

        [switch]$EligibilityRead
    )

    $Causes = [System.Collections.Generic.List[string]]::new()

    $AssignmentRead = Read-OERGroupPimAssignment -GroupId $GroupId
    if (-not $AssignmentRead.Read) { $Causes.Add([string]$AssignmentRead.Message) }

    $EligibilityInstances = @()
    if ($EligibilityRead) {
        $EligibilityInstances = @($Eligibility)
    } else {
        $EligibilityReadResult = Read-OERGroupCollection -GroupId $GroupId -Collection PimEligibility
        if ($EligibilityReadResult.Read) {
            $EligibilityInstances = @($EligibilityReadResult.Value)
        } else {
            # The reader's message ends with a sentence about Get-OERGroup's own output (the property
            # it omits), which says nothing true in the apply engine's warning and row. That sentence
            # is cut; the rest of the message, which the reader alone words, is kept as it is.
            $EligibilityCause = [string]$EligibilityReadResult.Message
            $OmittedSentence = ' The PimEligibility property is omitted rather than reported as empty.'
            if ($EligibilityCause.EndsWith($OmittedSentence, [System.StringComparison]::Ordinal)) {
                $EligibilityCause = $EligibilityCause.Substring(0, $EligibilityCause.Length - $OmittedSentence.Length)
            }
            $Causes.Add($EligibilityCause)
        }
    }

    $Read = $Causes.Count -eq 0
    $Held = @{}
    if ($Read) {
        foreach ($Access in @(Get-OERGroupPimHeldAccess -Assignment @($AssignmentRead.Value) -Eligibility $EligibilityInstances)) {
            $Held[('{0}|{1}' -f $Access.PrincipalId, $Access.AccessType).ToLowerInvariant()] = [string]$Access.Reason
        }
    }

    $O = [PSCustomObject]@{
        Read  = $Read
        Held  = $Held
        Cause = if ($Read) { $null } else { $Causes -join '; ' }
    }
    $O.PSObject.TypeNames.Insert(0, 'Omnicit.EntraRBAC.GroupPimHold')
    $O
}
