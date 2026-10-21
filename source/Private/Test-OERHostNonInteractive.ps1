function Test-OERHostNonInteractive {
    <#
    .SYNOPSIS
    Reports whether the console host the command runs in was started with -NonInteractive.

    .DESCRIPTION
    Initialize-OERAuth asks this before an interactive (browser) sign-in: a host started with
    pwsh -NonInteractive declares that nobody can answer a prompt, so the module does not start an
    interactive sign-in there (a policy; whether a browser could be completed in such a host is not
    measured), and AzAuth would still open the browser from the token request. This function is the
    single place that decides it.

    It returns $true only when $Host.Name is 'ConsoleHost' and the console's user interface has its
    ThrowOnReadAndPrompt switch set. PowerShell exposes that switch as a setter only, so it is read by
    reflection: $Host (the internal host) -> its NonPublic ExternalHost property -> its public UI
    -> the NonPublic instance field _throwOnReadAndPrompt of ConsoleHostUserInterface. Measured on
    2026-10-21 against the PowerShell 7.2.0 and 7.6.0 sources and in this repository's tool host: the
    field is $true under pwsh -NonInteractive (also -noni and -NonI) and $false under plain -File and
    -Command, and also $false when -NonInteractive is only an argument of the script. A runspace made
    without a PSHost is the 'Default Host' and answers $false.

    It returns $false for every other host, and when any step of the reflection fails (a PowerShell
    build without the property or the field, for example). It never throws and never writes an error
    record.

    The limit: a host that is not the ConsoleHost (an editor's integrated console, a runspace of
    another application) is not detected, and neither is a service or scheduled task that runs
    pwsh without -NonInteractive; the sign-in there is the caller's to avoid. A false answer is
    therefore "not known to be non-interactive", never "can show a browser".

    .EXAMPLE
    Test-OERHostNonInteractive
    Returns $true in a pwsh started with -NonInteractive, and $false in an ordinary pwsh session.
    #>
    [OutputType([bool])]
    [CmdletBinding()]
    param()

    try {
        if ($Host.Name -ne 'ConsoleHost') {
            return $false
        }
        $Instance = [System.Reflection.BindingFlags]'NonPublic,Instance'
        $ExternalHost = $Host.GetType().GetProperty('ExternalHost', $Instance).GetValue($Host)
        $Ui = $ExternalHost.UI
        $Field = $Ui.GetType().GetField('_throwOnReadAndPrompt', $Instance)
        [bool]($Field.GetValue($Ui) -eq $true)
    } catch {
        # A caught exception is also appended to $global:Error; the answer is "no", not a failure.
        Remove-OERErrorRecord -Record $PSItem
        $false
    }
}
