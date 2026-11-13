function Test-OERConsoleInputRedirected {
    <#
    .SYNOPSIS
    Reports whether the standard input of the process is redirected away from the console.

    .DESCRIPTION
    The single reader of [System.Console]::IsInputRedirected in the module. Only Test-OERHostCanConfirm
    asks it: in the console host (pwsh) a confirmation prompt reads its answer from the console's standard
    input, so with that input redirected the answer comes from the pipe or file, not from a person, or the
    prompt fails at the end of the input. Measured on 2026-11-13 in child pwsh 7.6 processes: with standard
    input redirected, ShouldProcess with ConfirmImpact High read y, n or an empty line (the default answer,
    Yes) from it, and threw a NullReferenceException at its end; with the console as standard input it
    waited for an answer.

    It returns the .NET property as it is: $true when standard input is a pipe, a file or the null device,
    $false when it is a console. It is a separate function so the tests can stand in for it.

    .EXAMPLE
    Test-OERConsoleInputRedirected
    Returns $false in a pwsh typed into a terminal, and $true in a pwsh whose input is piped, such as
    'y' | pwsh -File apply.ps1.
    #>
    [OutputType([bool])]
    [CmdletBinding()]
    param()

    [bool][System.Console]::IsInputRedirected
}
