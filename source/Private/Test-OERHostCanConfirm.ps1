function Test-OERHostCanConfirm {
    <#
    .SYNOPSIS
    Reports whether the host the command runs in can show a confirmation prompt, where that can be told beforehand.

    .DESCRIPTION
    Invoke-OERStructure asks for confirmation before each change (ConfirmImpact High). A host that cannot
    ask a person throws at the first change, or answers from a pipe, and every entry the engine reaches
    stops or is answered by nobody. This function answers whether the host is known to be one of those
    BEFORE anything is read, and is the single place that decides it.

    It returns $false for (a) the Default Host ($Host.Name 'Default Host': a runspace made with
    [powershell]::Create() or [runspacefactory]::CreateRunspace() without a PSHost, a thread job started
    without -StreamingHost), (b) the console host started with -NonInteractive, asked through
    Test-OERHostNonInteractive, the single owner of that question, and (c) the console host whose standard
    input is redirected (Test-OERConsoleInputRedirected). It returns $true for every other host.

    Measured on 2026-10-20 in plain PowerShell: $Host.UI is never null, and a ShouldProcess with
    ConfirmImpact High, no -Confirm:$false and no -WhatIf throws a MethodInvocationException whose inner
    exception is a HostException in the Default Host, a PSInvalidOperationException under pwsh
    -NonInteractive (and -noni), and a NullReferenceException with standard input at its end, while with
    standard input redirected from a non-empty pipe it read the default answer (Yes).

    Measured on 2026-11-13 in child pwsh 7.6 processes on Windows, with -File and -Command, with and without
    -NonInteractive, and standard input inherited redirected, closed, an empty line, n, y, and the console:
    with redirected input ShouldProcess read y, n or the empty line from the pipe, or threw a
    NullReferenceException at its end; under -NonInteractive it threw a PSInvalidOperationException
    whatever the input; only with the console as input and without -NonInteractive did it wait for an
    answer. [Environment]::UserInteractive was True in every case and decides nothing.

    Measured on 2026-11-14 in pwsh 7.6 on Windows (BL-198), with the same kind of function, in more hosts.
    A background job (Start-Job) runs in the host 'ServerRemoteHost' with $PSSenderInfo set. Its
    ShouldProcess did not throw: the job turned Blocked, Wait-Job stopped with an error, and Receive-Job
    showed the prompt in the host that received the job, where an answer was read (Yes typed into a pseudo
    console, No from a pipe); received in pwsh -NonInteractive, the job's ShouldProcess threw. A person
    can answer it there, so it answers $true. A thread job started with -StreamingHost $Host runs in its
    caller's console host and prompts there, so (b) and (c) decide it as they decide its caller; without
    -StreamingHost it is the Default Host (a). A console host in a new console with no visible window
    (Start-Process -WindowStyle Hidden) waited for an answer nobody could give, and answers $true: its
    host name and type, $PSSenderInfo, its input redirection (c), [Environment]::UserInteractive and
    process session id read as in a console a person types into, and its console window was not visible,
    as it was not for pwsh in a pseudo console made with CreatePseudoConsole (the API through which terminal
    applications such as Windows Terminal host a shell; Windows Terminal itself was not started and may
    read differently), where a typed answer was read. No
    signal measured tells the hidden console apart, so it is not refused.

    Limits: a console nobody sees answers $true and its prompt waits; a scheduled task or a service was
    not measured. A background job's prompt waits until Receive-Job passes it to the host that
    receives the job, which answers it from its input when that is piped, and fails it with a
    RemoteException Test-OERConfirmPromptFailure does not count when it runs -NonInteractive. Another
    host (an editor's
    integrated console, a runspace on an application's own PSHost) answers $true and was not measured.
    Run the command there with -Confirm:$false or -WhatIf. A terminal that hands pwsh a pipe instead of a
    console is refused although a person may be typing into it; that is the safer side, since
    -Confirm:$false or -WhatIf runs the document. Test-OERConfirmPromptFailure names the cause when a
    prompt fails anyway.

    .EXAMPLE
    Test-OERHostCanConfirm
    Returns $true in pwsh typed into a terminal, and $false in a runspace made with [powershell]::Create(),
    under pwsh -NonInteractive, and with input piped in.
    #>
    [OutputType([bool])]
    [CmdletBinding()]
    param()

    $HostName = $Host.Name
    if ($HostName -eq 'Default Host') { return $false }
    if ($HostName -ne 'ConsoleHost') { return $true }
    if (Test-OERHostNonInteractive) { return $false }
    -not (Test-OERConsoleInputRedirected)
}
