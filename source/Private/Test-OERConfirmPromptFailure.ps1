function Test-OERConfirmPromptFailure {
    <#
    .SYNOPSIS
    Reports whether an error record is a ShouldProcess confirmation prompt the host could not show.

    .DESCRIPTION
    The single owner of how the apply engine tells, from a caught error record, that a handler stopped
    because the host cannot show the confirmation prompt Invoke-OERStructure asks before each change.
    Invoke-OERStructure uses it in its two handler-error catches (the administrative unit pre-pass and
    the section dispatch) to word that entry's Failed row: the host cannot show the prompt, nothing was
    written for the entry, and -Confirm:$false or -WhatIf runs it.

    It returns $true when the record's exception is a MethodInvocationException whose message contains
    'ShouldProcess' (compared ordinally, so letter case counts) and whose inner exception is one of the
    three types measured on 2026-10-20 in plain PowerShell, where a ShouldProcess with ConfirmImpact High,
    no -Confirm:$false and no -WhatIf failed: a HostException (the Default Host, a runspace made without
    a PSHost or a thread job), a PSInvalidOperationException (pwsh -NonInteractive) and a
    NullReferenceException (standard input at its end). A type derived from one of the three counts as
    that type. Every other record, a null record included, returns $false, so its row keeps the
    exception's own message. The record is only read: nothing is written, thrown or sent.

    .PARAMETER Record
    The error record a catch block caught ($PSItem). A null record is not a prompt failure.

    .EXAMPLE
    Test-OERConfirmPromptFailure -Record $PSItem
    Inside a catch block, returns $true when the handler stopped at a confirmation prompt the host could
    not show, and $false for any other error.
    #>
    [OutputType([bool])]
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowNull()]
        [System.Management.Automation.ErrorRecord]$Record
    )

    if ($null -eq $Record) { return $false }
    $Exception = $Record.Exception
    if ($Exception -isnot [System.Management.Automation.MethodInvocationException]) { return $false }
    $Inner = $Exception.InnerException
    $Measured = ($Inner -is [System.Management.Automation.Host.HostException]) -or
        ($Inner -is [System.Management.Automation.PSInvalidOperationException]) -or
        ($Inner -is [System.NullReferenceException])
    if (-not $Measured) { return $false }
    ([string]$Exception.Message).IndexOf('ShouldProcess', [System.StringComparison]::Ordinal) -ge 0
}
