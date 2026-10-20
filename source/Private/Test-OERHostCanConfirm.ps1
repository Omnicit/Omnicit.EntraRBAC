function Test-OERHostCanConfirm {
    <#
    .SYNOPSIS
    Reports whether the host the command runs in can show a confirmation prompt, where that can be told beforehand.

    .DESCRIPTION
    Invoke-OERStructure asks for confirmation before each change (ConfirmImpact High). A host that has no
    user interface cannot ask: its ShouldProcess throws at the first change, and every entry the engine
    reaches stops there. This function answers whether the host is known to be one of those BEFORE
    anything is read, and is the single place that decides it.

    It returns $false exactly when the host is the Default Host ($Host.Name 'Default Host'), and $true for
    every other host. Measured on 2026-10-20 in plain PowerShell: $Host.UI is never null, and a
    ShouldProcess with ConfirmImpact High, no -Confirm:$false and no -WhatIf throws a
    MethodInvocationException whose inner exception is a HostException in the Default Host -- a runspace
    made with [powershell]::Create() or [runspacefactory]::CreateRunspace() without a PSHost, and a
    thread job (Start-ThreadJob) -- a PSInvalidOperationException under pwsh -NonInteractive (and
    -noni), and a NullReferenceException with standard input at its end, while with standard input
    redirected from a non-empty pipe it read the default answer (Yes). Only the Default Host can be told
    from the host itself; the other two need the process command line or the console's state, so this
    function answers $true for them, and Test-OERConfirmPromptFailure names the cause when their prompt
    fails.

    .EXAMPLE
    Test-OERHostCanConfirm
    Returns $true in the console host (pwsh), and $false in a runspace made with [powershell]::Create().
    #>
    [OutputType([bool])]
    [CmdletBinding()]
    param()

    $Host.Name -ne 'Default Host'
}
