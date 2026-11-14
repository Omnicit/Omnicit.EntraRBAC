function Test-OERProcessServerMode {
    <#
    .SYNOPSIS
    Reports whether the process was started as a PowerShell job server (the -s switch of pwsh, as Start-Job starts it).

    .DESCRIPTION
    Test-OERHostCanConfirm asks this to tell a local background job from the other hosts that report the
    name 'ServerRemoteHost'. This function is the single place that reads it.

    A background job (Start-Job) runs in a child pwsh started as `pwsh -s -NoLogo -NoProfile`. The pwsh
    startup parameter parser keeps that switch as its NonPublic instance property ServerMode, and the
    parser itself in the NonPublic static field s_cpp of Microsoft.PowerShell.ConsoleHost. Both are read
    by reflection: the loaded assembly Microsoft.PowerShell.ConsoleHost -> its type
    Microsoft.PowerShell.ConsoleHost -> the static field s_cpp -> the property ServerMode.

    Measured on 2026-11-14 in pwsh 7.6 on Windows (BL-202): ServerMode is $true in every local background
    job, and also in a runspace attached with Enter-PSHostProcess to a job's own process (the switch is
    process wide). It is $false in a pwsh started with -sshs (the SSH remoting subsystem) and in a pwsh
    attached over a named pipe that was not started as a job server. A WinRM session runs in
    wsmprovhost.exe (documented on Microsoft Learn), which is not started through pwsh's own entry point, so
    the parser is presumably not set there and the answer $false (inferred from the documented host
    process and pwsh's entry point; not measured).

    It returns $false for a process that is not a job server, when the assembly, the field or the property
    is not there (a PowerShell build without them, for example) and on any other failure. It never throws
    and never writes an error record. Only Test-OERHostCanConfirm asks it.

    .EXAMPLE
    Test-OERProcessServerMode
    Returns $true inside a Start-Job script block, and $false in an ordinary pwsh session.
    #>
    [OutputType([bool])]
    [CmdletBinding()]
    param()

    try {
        $Assembly = [System.AppDomain]::CurrentDomain.GetAssemblies() |
            Where-Object { $_.GetName().Name -eq 'Microsoft.PowerShell.ConsoleHost' } |
            Select-Object -First 1
        if ($null -eq $Assembly) { return $false }
        $ConsoleHostType = $Assembly.GetType('Microsoft.PowerShell.ConsoleHost')
        $Parser = $ConsoleHostType.GetField('s_cpp', [System.Reflection.BindingFlags]'NonPublic,Static').GetValue($null)
        if ($null -eq $Parser) { return $false }
        $Property = $Parser.GetType().GetProperty('ServerMode', [System.Reflection.BindingFlags]'NonPublic,Public,Instance')
        [bool]($Property.GetValue($Parser) -eq $true)
    } catch {
        # A caught exception is also appended to $global:Error; the answer is "no", not a failure.
        Remove-OERErrorRecord -Record $PSItem
        $false
    }
}
