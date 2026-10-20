function Test-OERJsonDateKindSupport {
    <#
    .SYNOPSIS
    Reports whether the running PowerShell's ConvertFrom-Json has a -DateKind parameter.

    .DESCRIPTION
    ConvertFrom-Json on PowerShell before 7.5 turns a string that holds an ISO 8601 date and time with
    seconds into a [datetime] while it parses, so the text the document author wrote is lost. PowerShell
    7.5 added -DateKind, and -DateKind String leaves every string as it was written. This function
    answers with one Get-Command check whether the parameter exists, and is the single place that asks:
    Read-OERStructureDocument adds -DateKind String to its parse when this returns $true, and without it
    Test-OERStructureSchema refuses every date value the parse produced. It is a function of its own so
    a test can mock either answer in module scope on whatever PowerShell runs the suite.

    The command is looked up by its module-qualified name, so a function or alias another module or
    the caller's session defines under the name ConvertFrom-Json is never the one asked. The check
    reads the command's metadata only; nothing is parsed, read from disk or sent anywhere.

    .EXAMPLE
    Test-OERJsonDateKindSupport
    Returns $true on PowerShell 7.5 or later, and $false on 7.2 to 7.4.
    #>
    [OutputType([bool])]
    [CmdletBinding()]
    param()

    $Command = Get-Command -Name 'Microsoft.PowerShell.Utility\ConvertFrom-Json' -ErrorAction SilentlyContinue
    $null -ne $Command -and $Command.Parameters.ContainsKey('DateKind')
}
