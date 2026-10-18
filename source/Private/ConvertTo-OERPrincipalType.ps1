function ConvertTo-OERPrincipalType {
    <#
    .SYNOPSIS
    Maps a Microsoft Graph object type to the principal type the module's documents write.

    .DESCRIPTION
    Single owner of the mapping from a Microsoft Graph object type to the principal type enum the
    module's documents and bundle files write (Sprint 11 step 8): user becomes User, group becomes
    Group and servicePrincipal becomes ServicePrincipal. The type is given either as the @odata.type
    Microsoft Graph returns ('#microsoft.graph.user') or without its prefix ('user'); the
    '#microsoft.graph.' prefix is optional, and both the prefix and the type are compared without
    regard to letter case (ordinally, so the culture never changes the answer).

    Anything else returns $null: a device, another directory object type, a type with any other
    prefix, white space around the type, an empty value and $null. A type is never guessed, so a
    caller that needs a value for such a type decides for itself what to write.

    Pure: no Graph, ARM or filesystem access.

    .PARAMETER ODataType
    The Microsoft Graph object type, with or without the '#microsoft.graph.' prefix. An empty value
    and $null are accepted and return $null.

    .EXAMPLE
    ConvertTo-OERPrincipalType -ODataType '#microsoft.graph.servicePrincipal'
    Returns 'ServicePrincipal'.

    .EXAMPLE
    ConvertTo-OERPrincipalType -ODataType 'device'
    Returns $null: a device is not one of the three principal types.
    #>
    [OutputType([string])]
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowNull()]
        [AllowEmptyString()]
        [string]$ODataType
    )

    if ([string]::IsNullOrEmpty($ODataType)) { return $null }

    $Name = $ODataType
    $Prefix = '#microsoft.graph.'
    if ($Name.StartsWith($Prefix, [System.StringComparison]::OrdinalIgnoreCase)) { $Name = $Name.Substring($Prefix.Length) }

    $Types = [System.Collections.Generic.Dictionary[string, string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    $Types['user'] = 'User'
    $Types['group'] = 'Group'
    $Types['servicePrincipal'] = 'ServicePrincipal'

    if ($Types.ContainsKey($Name)) { return $Types[$Name] }
    return $null
}
