function Get-OERDerivedMailNicknameProblem {
    <#
    .SYNOPSIS
    Returns the refusal text for a group name whose derived mail alias Microsoft Graph would refuse,
    or $null when the alias is acceptable.

    .DESCRIPTION
    The single owner of the condition and the text of the DerivedMailNicknameInvalid refusal. The alias
    is derived through Get-OERDerivedMailNickname; Microsoft Graph accepts 1 to 64 characters, so an
    empty derivation or one over 64 characters is a problem. New-OERGroup publishes the returned text
    when -MailNickname is not given, and the apply engine (Sync-OERStructureGroup) asks the same
    question for a group it would create, so the plan and the run refuse it before anything is sent.
    Pure: no Graph, ARM or file access.

    .PARAMETER DisplayName
    The group display name the alias would be derived from.

    .EXAMPLE
    Get-OERDerivedMailNicknameProblem -DisplayName '!!!'
    Returns the refusal text (the derived alias is empty).

    .EXAMPLE
    Get-OERDerivedMailNicknameProblem -DisplayName 'role_sec_team'
    Returns $null.
    #>
    [OutputType([string])]
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string]$DisplayName
    )

    $Nick = Get-OERDerivedMailNickname -DisplayName $DisplayName
    if ($Nick.Length -ge 1 -and $Nick.Length -le 64) { return $null }

    $Why = if ($Nick.Length -eq 0) {
        'is empty (the name has no character A-Z, a-z, 0-9, ''.'', ''_'' or ''-'')'
    } else {
        "is $($Nick.Length) characters long"
    }
    "The mail alias derived from the group name '$DisplayName' $Why; Microsoft Graph accepts 1 to 64 characters. " +
        'Nothing was sent. Pass -MailNickname with the alias the group should carry.'
}
