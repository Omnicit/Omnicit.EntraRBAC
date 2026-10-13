function Get-OERDerivedMailNickname {
    <#
    .SYNOPSIS
    Returns the mail alias New-OERGroup derives from a group display name.

    .DESCRIPTION
    The single owner of that derivation: every character outside A-Z, a-z, 0-9, '.', '_' and '-' is
    removed. New-OERGroup sends the result as mailNickname when -MailNickname is not given, and
    Test-OERStructureSchema compares a renamed group's mailNickname with the alias derived from its
    previous name. The result can be empty, or longer than the 64 characters Microsoft Graph accepts;
    the callers decide what that means. Pure: no Graph, ARM or file access.

    .PARAMETER DisplayName
    The group display name.

    .EXAMPLE
    Get-OERDerivedMailNickname -DisplayName 'role_sec (team)'
    Returns 'role_secteam'.
    #>
    [OutputType([string])]
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string]$DisplayName
    )

    $DisplayName -replace '[^A-Za-z0-9._-]', ''
}
