BeforeAll {
    $script:moduleName = 'Omnicit.EntraRBAC'
    Get-Module $script:moduleName | Remove-Module -Force -ErrorAction SilentlyContinue
    Import-Module $script:moduleName -Force -ErrorAction Stop
    . "$PSScriptRoot/../TestHelpers/OERTransportTripwire.ps1"
    Install-OERTransportTripwire
}

AfterAll {
    try { Assert-OERTransportTripwire } finally { Uninstall-OERTransportTripwire }
}

Describe 'Test-OERHostCanConfirm (BL-53)' {
    BeforeAll {
        . "$PSScriptRoot/../TestHelpers/OERConfirmHost.ps1"
        # Runs the self-contained script in a runspace made without a PSHost -- the Default Host, as in a
        # [powershell]::Create() runspace or a thread job -- with the transport tripwire installed there.
        function script:Invoke-DefaultHostScript {
            param([scriptblock]$Script)
            $Runspace = [runspacefactory]::CreateRunspace()
            $Runspace.Open()
            $Shell = [powershell]::Create()
            try {
                Install-OERTransportTripwireInRunspace -Runspace $Runspace
                $Shell.Runspace = $Runspace
                $null = $Shell.AddScript($Script.ToString())
                $Output = $Shell.Invoke()
                Test-OERTransportTripwireInRunspace -Runspace $Runspace
                [PSCustomObject]@{
                    Output = @($Output)
                    Errors = @($Shell.Streams.Error | ForEach-Object { $_.ToString() })
                }
            } finally {
                $Shell.Dispose()
                $Runspace.Dispose()
            }
        }
        # Opens a runspace without blocking: OpenAsync, then a bounded poll of its state. $false on a
        # runspace that breaks, closes or is not open within the timeout.
        function script:Open-BoundedRunspace {
            param($Runspace, [int]$TimeoutSec = 10)
            try { $null = $Runspace.OpenAsync() } catch { return $false }
            $Watch = [System.Diagnostics.Stopwatch]::StartNew()
            while ($Watch.Elapsed.TotalSeconds -lt $TimeoutSec) {
                $State = "$($Runspace.RunspaceStateInfo.State)"
                if ($State -eq 'Opened') { return $true }
                if ($State -in 'Broken', 'Closed', 'Closing') { return $false }
                Start-Sleep -Milliseconds 100
            }
            $false
        }
        # Runs the shell with BeginInvoke and a bounded wait; stops it and throws when it does not finish.
        function script:Invoke-BoundedShell {
            param($Shell, [int]$TimeoutSec = 60)
            $Async = $Shell.BeginInvoke()
            if (-not $Async.AsyncWaitHandle.WaitOne($TimeoutSec * 1000)) {
                try { $Shell.Stop() } catch { $null = $_ }
                throw "The script did not finish within $TimeoutSec seconds in the attached runspace."
            }
            @($Shell.EndInvoke($Async) | ForEach-Object { "$_" })
        }
    }

    Context 'in the console host (BL-195)' {
        BeforeAll {
            $script:PwshPath = (Get-Process -Id $PID).Path
            $script:AskCommand = "Import-Module Omnicit.EntraRBAC -Force -ErrorAction Stop; " +
                "'ANSWER:' + (& (Get-Module Omnicit.EntraRBAC) { Test-OERHostCanConfirm })"
        }

        It 'is reached: the test host is the console host' {
            $Host.Name | Should -BeExactly 'ConsoleHost'
        }

        It 'answers <Expected> when NonInteractive is <NonInteractive> and input redirected is <Redirected>' -TestCases @(
            @{ NonInteractive = $false; Redirected = $false; Expected = $true }
            @{ NonInteractive = $true; Redirected = $false; Expected = $false }
            @{ NonInteractive = $false; Redirected = $true; Expected = $false }
            @{ NonInteractive = $true; Redirected = $true; Expected = $false }
        ) {
            param($NonInteractive, $Redirected, $Expected)
            Mock -ModuleName Omnicit.EntraRBAC Test-OERHostNonInteractive { $NonInteractive }
            Mock -ModuleName Omnicit.EntraRBAC Test-OERConsoleInputRedirected { $Redirected }
            Mock -ModuleName Omnicit.EntraRBAC Test-OERProcessServerMode { $true }
            InModuleScope $script:moduleName { Test-OERHostCanConfirm } | Should -BeExactly $Expected
            Should -Invoke -ModuleName Omnicit.EntraRBAC Test-OERProcessServerMode -Times 0
            Should -Invoke -ModuleName Omnicit.EntraRBAC Test-OERHostNonInteractive -Times 1 -Exactly
            if ($NonInteractive) {
                Should -Invoke -ModuleName Omnicit.EntraRBAC Test-OERConsoleInputRedirected -Times 0
            } else {
                Should -Invoke -ModuleName Omnicit.EntraRBAC Test-OERConsoleInputRedirected -Times 1 -Exactly
            }
        }

        It 'answers $false in a real child console host started with -NonInteractive' {
            $Output = & $script:PwshPath -NoProfile -NonInteractive -Command $script:AskCommand 2>&1
            @($Output | ForEach-Object { "$_" }) | Should -Contain 'ANSWER:False'
        }

        It 'answers $false in a real child console host whose standard input is piped' {
            $Output = 'y' | & $script:PwshPath -NoProfile -Command $script:AskCommand 2>&1
            @($Output | ForEach-Object { "$_" }) | Should -Contain 'ANSWER:False'
        }
    }

    It 'answers $true in a host that is not the console host even when both console signals say refuse' {
        $Run = Invoke-OERWithConfirmAnswer -Answer '&Yes' -Script {
            Import-Module Omnicit.EntraRBAC -Force -ErrorAction Stop
            "HOST:$($Host.Name)"
            & (Get-Module Omnicit.EntraRBAC) {
                Set-Item -Path function:script:Test-OERHostNonInteractive -Value { $true }
                Set-Item -Path function:script:Test-OERConsoleInputRedirected -Value { $true }
            }
            "STUB:$(& (Get-Module Omnicit.EntraRBAC) { (Test-OERHostNonInteractive) -and (Test-OERConsoleInputRedirected) })"
            "ANSWER:$(& (Get-Module Omnicit.EntraRBAC) { Test-OERHostCanConfirm })"
        }
        $Run.Output | Should -Be @('HOST:OERAnsweringHost', 'STUB:True', 'ANSWER:True')
        $Run.Errors | Should -BeNullOrEmpty
    }

    It 'returns $false in a runspace made with no PSHost (the Default Host)' {
        $Run = Invoke-DefaultHostScript -Script {
            Import-Module Omnicit.EntraRBAC -Force -ErrorAction Stop
            "HOST:$($Host.Name)"
            "ANSWER:$(& (Get-Module Omnicit.EntraRBAC) { Test-OERHostCanConfirm })"
            'END'
        }
        $Run.Output | Should -Be @('HOST:Default Host', 'ANSWER:False', 'END')
        $Run.Errors | Should -BeNullOrEmpty
    }

    It 'returns $true in a runspace on a host of its own that can prompt (the answering host)' {
        $Run = Invoke-OERWithConfirmAnswer -Answer '&Yes' -Script {
            Import-Module Omnicit.EntraRBAC -Force -ErrorAction Stop
            "HOST:$($Host.Name)"
            "ANSWER:$(& (Get-Module Omnicit.EntraRBAC) { Test-OERHostCanConfirm })"
            'END'
        }
        $Run.Output | Should -Be @('HOST:OERAnsweringHost', 'ANSWER:True', 'END')
        $Run.Errors | Should -BeNullOrEmpty
    }

    It 'answers $false in a background job (Start-Job: ServerRemoteHost, $PSSenderInfo set) (BL-198)' {
        $Job = Start-Job -ScriptBlock {
            Import-Module Omnicit.EntraRBAC -Force -ErrorAction Stop
            "HOST:$($Host.Name)"
            "SENDER:$($null -ne $PSSenderInfo)"
            "SERVERMODE:$(& (Get-Module Omnicit.EntraRBAC) { Test-OERProcessServerMode })"
            "ANSWER:$(& (Get-Module Omnicit.EntraRBAC) { Test-OERHostCanConfirm })"
        }
        try {
            $null = $Job | Wait-Job -Timeout 120
            $Output = @($Job | Receive-Job -ErrorAction Stop | ForEach-Object { "$_" })
            $Job.State | Should -BeExactly 'Completed'
        } finally {
            $Job | Remove-Job -Force
        }
        $Output | Should -Be @('HOST:ServerRemoteHost', 'SENDER:True', 'SERVERMODE:True', 'ANSWER:False')
    }

    It 'answers $true in a ServerRemoteHost when the reader answers $false (stubbed in a job)' {
        $Job = Start-Job -ScriptBlock {
            Import-Module Omnicit.EntraRBAC -Force -ErrorAction Stop
            "HOST:$($Host.Name)"
            & (Get-Module Omnicit.EntraRBAC) { Set-Item -Path function:script:Test-OERProcessServerMode -Value { $false } }
            "STUB:$(& (Get-Module Omnicit.EntraRBAC) { Test-OERProcessServerMode })"
            "ANSWER:$(& (Get-Module Omnicit.EntraRBAC) { Test-OERHostCanConfirm })"
        }
        try {
            $null = $Job | Wait-Job -Timeout 120
            $Output = @($Job | Receive-Job -ErrorAction Stop | ForEach-Object { "$_" })
            $Job.State | Should -BeExactly 'Completed'
        } finally {
            $Job | Remove-Job -Force
        }
        $Output | Should -Be @('HOST:ServerRemoteHost', 'STUB:False', 'ANSWER:True')
    }

    It 'answers $false in a ServerRemoteHost when the reader answers $true and both console signals answer $false (stubbed in a job)' {
        $Job = Start-Job -ScriptBlock {
            Import-Module Omnicit.EntraRBAC -Force -ErrorAction Stop
            "HOST:$($Host.Name)"
            & (Get-Module Omnicit.EntraRBAC) {
                Set-Item -Path function:script:Test-OERProcessServerMode -Value { $true }
                Set-Item -Path function:script:Test-OERHostNonInteractive -Value { $false }
                Set-Item -Path function:script:Test-OERConsoleInputRedirected -Value { $false }
            }
            "STUB:$(& (Get-Module Omnicit.EntraRBAC) { (Test-OERProcessServerMode) -and -not (Test-OERHostNonInteractive) -and -not (Test-OERConsoleInputRedirected) })"
            "ANSWER:$(& (Get-Module Omnicit.EntraRBAC) { Test-OERHostCanConfirm })"
        }
        try {
            $null = $Job | Wait-Job -Timeout 120
            $Output = @($Job | Receive-Job -ErrorAction Stop | ForEach-Object { "$_" })
            $Job.State | Should -BeExactly 'Completed'
        } finally {
            $Job | Remove-Job -Force
        }
        $Output | Should -Be @('HOST:ServerRemoteHost', 'STUB:True', 'ANSWER:False')
    }

    It 'answers $true in a pwsh started with -sshs and driven over stdio (the SSH remoting subsystem) (BL-198)' {
        $Ppi = [System.Management.Automation.Runspaces.PowerShellProcessInstance]::new()
        $Runspace = $null
        $Shell = $null
        $Output = $null
        $Reason = $null
        try {
            $Field = $Ppi.GetType().GetField('_startInfo', [System.Reflection.BindingFlags]'Instance,NonPublic')
            $Index = -1
            if ($null -ne $Field) {
                $StartInfo = $Field.GetValue($Ppi)
                for ($i = 0; $i -lt $StartInfo.ArgumentList.Count; $i++) {
                    if ($StartInfo.ArgumentList[$i] -eq '-s') { $Index = $i; break }
                }
            }
            if ($Index -lt 0) {
                $Reason = 'the PowerShellProcessInstance _startInfo field or its -s argument is not there in this PowerShell build'
            } else {
                $StartInfo.ArgumentList[$Index] = '-sshs'
                $Runspace = [runspacefactory]::CreateOutOfProcessRunspace($null, $Ppi)
                if (-not (Open-BoundedRunspace -Runspace $Runspace -TimeoutSec 30)) {
                    $Reason = 'the -sshs runspace did not open within 30 seconds on this platform'
                } else {
                    $Shell = [powershell]::Create()
                    $Shell.Runspace = $Runspace
                    $null = $Shell.AddScript(@'
Import-Module Omnicit.EntraRBAC -Force -ErrorAction Stop
"HOST:$($Host.Name)"
"ARGS:$([Environment]::GetCommandLineArgs() -join ' ')"
"ANSWER:$(& (Get-Module Omnicit.EntraRBAC) { Test-OERHostCanConfirm })"
'@)
                    $Output = Invoke-BoundedShell -Shell $Shell -TimeoutSec 60
                }
            }
        } finally {
            if ($Shell) { $Shell.Dispose() }
            if ($Runspace) { $Runspace.Dispose() }
            $Ppi.Dispose()
        }
        if ($null -eq $Output) {
            Set-ItResult -Inconclusive -Because $Reason
            return
        }
        $Output | Should -Contain 'HOST:ServerRemoteHost'
        ($Output | Where-Object { $_ -like 'ARGS:*' }) | Should -Match '(^| )-sshs( |$)'
        $Output | Should -Contain 'ANSWER:True'
    }

    It 'answers $true in a runspace attached over a named pipe to a pwsh that is not a job server (BL-198)' {
        $PwshPath = (Get-Process -Id $PID).Path
        $StartArgs = @{
            FilePath     = $PwshPath
            ArgumentList = @('-NoProfile', '-NonInteractive', '-Command', 'Start-Sleep 120')
            PassThru     = $true
        }
        if ($IsWindows) { $StartArgs['WindowStyle'] = 'Hidden' }
        $Child = Start-Process @StartArgs
        $Runspace = $null
        $Shell = $null
        $Output = $null
        try {
            for ($Try = 0; $Try -lt 5 -and $null -eq $Output; $Try++) {
                $ConnectionInfo = [System.Management.Automation.Runspaces.NamedPipeConnectionInfo]::new($Child.Id)
                $ConnectionInfo.OpenTimeout = 5000
                $ConnectionInfo.OperationTimeout = 5000
                $Runspace = [runspacefactory]::CreateRunspace($Host, $ConnectionInfo)
                if (Open-BoundedRunspace -Runspace $Runspace -TimeoutSec 8) {
                    $Shell = [powershell]::Create()
                    $Shell.Runspace = $Runspace
                    $null = $Shell.AddScript(@'
Import-Module Omnicit.EntraRBAC -Force -ErrorAction Stop
"HOST:$($Host.Name)"
"ANSWER:$(& (Get-Module Omnicit.EntraRBAC) { Test-OERHostCanConfirm })"
'@)
                    $Output = Invoke-BoundedShell -Shell $Shell -TimeoutSec 60
                } else {
                    $Runspace.Dispose()
                    $Runspace = $null
                    Start-Sleep -Seconds 1
                }
            }
        } finally {
            if ($Shell) { $Shell.Dispose() }
            if ($Runspace) { $Runspace.Dispose() }
            Stop-Process -Id $Child.Id -Force -ErrorAction SilentlyContinue
        }
        if ($null -eq $Output) {
            Set-ItResult -Inconclusive -Because 'no named pipe attach to the child pwsh succeeded within 5 bounded attempts on this platform'
            return
        }
        $Output | Should -Be @('HOST:ServerRemoteHost', 'ANSWER:True')
    }

    It 'returns a [bool]' {
        InModuleScope $script:moduleName { (Test-OERHostCanConfirm) -is [bool] } | Should -BeTrue
    }
}
