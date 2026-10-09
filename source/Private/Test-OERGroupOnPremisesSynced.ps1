function Test-OERGroupOnPremisesSynced {
    <#
    .SYNOPSIS
    Tells whether a live group is synchronized from on-premises Active Directory.

    .DESCRIPTION
    The single owner of the rule that a group is managed on-premises (decision A15). A group is
    synchronized when its OnPremisesSyncEnabled, as ConvertTo-OERGroup carries Graph's
    onPremisesSyncEnabled, is the boolean True. False (the group was synchronized and no longer is)
    and empty (it never was, or its source of authority was converted to the cloud) are not: such a
    group is managed in the cloud. Anything that is not a boolean, a missing property and a null
    group answer False, so a value that is not an answer is never read as synchronized.

    Microsoft Learn ("Configure Group Source of Authority") documents a synchronized group as
    read-only in the cloud. Sync-OERStructureGroup asks this helper about its live read and writes
    nothing to a group it answers True for; Get-OERInventory writes the document key
    onPremisesSynced and Export-OERInventory the roster flag from the same answer.

    .PARAMETER Group
    The live group, as Get-OERGroup or New-OERGroup returns it (an Omnicit.EntraRBAC.Group object).

    .EXAMPLE
    if (Test-OERGroupOnPremisesSynced -Group $Cur) { 'managed on-premises' }

    Answers True only for a group whose OnPremisesSyncEnabled is True.
    #>
    [OutputType([bool])]
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][AllowNull()]$Group
    )
    if ($null -eq $Group) { return $false }
    $Value = $Group.OnPremisesSyncEnabled
    return [bool]($Value -is [bool] -and $Value)
}
