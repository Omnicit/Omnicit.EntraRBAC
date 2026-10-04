function ConvertTo-OERScopeSplat {
    <#
    .SYNOPSIS
    Parses a structure-document scope into the splat Resolve-OERScope and the Azure cmdlets take.

    .DESCRIPTION
    The single owner of the structure document's scope syntax, shared by the roleAssignments
    pre-pass (Resolve-OERStructureRoleAssignmentScope) and Sync-OERStructureRoleManagementPolicy.
    - 'mg:<name>' or 'mg:<displayName>' (prefix in any letter case) -> @{ ManagementGroup = <value> }
    - 'subscription:<id or name>' or 'sub:<id or name>' -> @{ Subscription = <value> }
    - anything else -> @{ Scope = <value> }, normalized by ConvertTo-OERCanonicalScope, so a raw
      Azure Resource Manager path loses its trailing '/'.
    It never calls a transport.

    .PARAMETER Scope
    The scope string as the document wrote it.

    .EXAMPLE
    ConvertTo-OERScopeSplat -Scope 'mg:platform'
    Returns @{ ManagementGroup = 'platform' }.
    #>
    [OutputType([hashtable])]
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][AllowEmptyString()][string]$Scope
    )

    if ($Scope -match '^(?i)mg:(.+)$') { return @{ ManagementGroup = $Matches[1] } }
    if ($Scope -match '^(?i)(?:subscription|sub):(.+)$') { return @{ Subscription = $Matches[1] } }
    @{ Scope = (ConvertTo-OERCanonicalScope -Scope $Scope) }
}
