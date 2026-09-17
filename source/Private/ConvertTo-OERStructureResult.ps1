function ConvertTo-OERStructureResult {
    <#
    .SYNOPSIS
    Builds one tagged Omnicit.EntraRBAC.StructureResult record for an apply operation.

    .DESCRIPTION
    The single owner of the per-item apply-result shape produced by Invoke-OERStructure and its
    Sync-OERStructure* handlers. Returns a [PSCustomObject] tagged Omnicit.EntraRBAC.StructureResult
    carrying the Section, the Item name, the Action taken (Created, Updated, Unchanged, Removed, Extra,
    Failed, or Skipped), a free-text Detail, and the ErrorRecord when the Action is Failed.

    .PARAMETER Section
    The document section the item belongs to (for example groups or catalogs).

    .PARAMETER Item
    The display name or identifier of the item the result describes.

    .PARAMETER Action
    The reconcile outcome: Created, Updated, Unchanged, Removed, Extra, Failed, or Skipped.

    .PARAMETER Detail
    Optional free-text describing what happened (for example "added 2 members; pimPolicy set").

    .PARAMETER ErrorRecord
    The ErrorRecord to attach when the Action is Failed; otherwise omitted.

    .EXAMPLE
    ConvertTo-OERStructureResult -Section 'groups' -Item 'role_sec_x' -Action 'Created' -Detail 'created group'
    Returns a tagged StructureResult describing a created group.
    #>
    [OutputType([PSCustomObject])]
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Section,
        [Parameter(Mandatory)][string]$Item,
        [Parameter(Mandatory)]
        [ValidateSet('Created', 'Updated', 'Unchanged', 'Removed', 'Extra', 'Failed', 'Skipped')]
        [string]$Action,
        [string]$Detail = '',
        [System.Management.Automation.ErrorRecord]$ErrorRecord
    )
    $Out = [PSCustomObject]@{
        Section = $Section
        Item    = $Item
        Action  = $Action
        Detail  = $Detail
        Error   = $ErrorRecord
    }
    $Out.PSObject.TypeNames.Insert(0, 'Omnicit.EntraRBAC.StructureResult')
    $Out
}
