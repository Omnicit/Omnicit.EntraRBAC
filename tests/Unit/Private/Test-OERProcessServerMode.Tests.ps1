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

Describe 'Test-OERProcessServerMode (BL-202)' {
    BeforeAll {
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

        # Runs the script text in a pwsh started with -sshs (the SSH remoting subsystem's command line) and
        # driven over stdio, no ssh involved. Returns Output, or a Reason when the case cannot be reached
        # on this platform (the caller reports Inconclusive and never a false pass). Every wait is bounded.
        function script:Invoke-SshsScript {
            param([string]$ScriptText)
            $Ppi = [System.Management.Automation.Runspaces.PowerShellProcessInstance]::new()
            $Runspace = $null
            $Shell = $null
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
                    return @{ Output = $null; Reason = 'the PowerShellProcessInstance _startInfo field or its -s argument is not there in this PowerShell build' }
                }
                $StartInfo.ArgumentList[$Index] = '-sshs'
                $Runspace = [runspacefactory]::CreateOutOfProcessRunspace($null, $Ppi)
                if (-not (Open-BoundedRunspace -Runspace $Runspace -TimeoutSec 30)) {
                    return @{ Output = $null; Reason = 'the -sshs runspace did not open within 30 seconds on this platform' }
                }
                $Shell = [powershell]::Create()
                $Shell.Runspace = $Runspace
                $null = $Shell.AddScript($ScriptText)
                @{ Output = (Invoke-BoundedShell -Shell $Shell -TimeoutSec 60); Reason = $null }
            } finally {
                if ($Shell) { $Shell.Dispose() }
                if ($Runspace) { $Runspace.Dispose() }
                $Ppi.Dispose()
            }
        }
    }
    It 'returns a [bool] $false in the Pester process, which was not started as a job server' {
        [Environment]::GetCommandLineArgs() | Should -Not -Contain '-s'
        $Answer = InModuleScope $script:moduleName { Test-OERProcessServerMode }
        $Answer | Should -BeOfType [bool]
        $Answer | Should -BeFalse
    }

    It 'returns $true in a real background job (Start-Job)' {
        $Job = Start-Job -ScriptBlock {
            Import-Module Omnicit.EntraRBAC -Force -ErrorAction Stop
            "ANSWER:$(& (Get-Module Omnicit.EntraRBAC) { Test-OERProcessServerMode })"
        }
        try {
            $null = $Job | Wait-Job -Timeout 120
            $Output = @($Job | Receive-Job -ErrorAction Stop | ForEach-Object { "$_" })
            $Job.State | Should -BeExactly 'Completed'
        } finally {
            $Job | Remove-Job -Force
        }
        $Output | Should -Be @('ANSWER:True')
    }

    It 'returns $false in a pwsh started with -sshs and driven over stdio (the SSH remoting subsystem)' {
        $Run = Invoke-SshsScript -ScriptText @'
Import-Module Omnicit.EntraRBAC -Force -ErrorAction Stop
"HOST:$($Host.Name)"
"ARGS:$([Environment]::GetCommandLineArgs() -join ' ')"
"ANSWER:$(& (Get-Module Omnicit.EntraRBAC) { Test-OERProcessServerMode })"
'@
        if ($null -eq $Run.Output) {
            Set-ItResult -Inconclusive -Because $Run.Reason
            return
        }
        $Output = $Run.Output
        $Output | Should -Contain 'HOST:ServerRemoteHost'
        ($Output | Where-Object { $_ -like 'ARGS:*' }) | Should -Match '(^| )-sshs( |$)'
        $Output | Should -Contain 'ANSWER:False'
    }
}

Describe 'Test-OERProcessServerMode is the single reader of the startup parser (BL-202)' {
    BeforeAll {
        $script:SourceRoot = (Resolve-Path (Join-Path $PSScriptRoot '../../../source')).Path
    }

    It 'is the only file under source that names s_cpp' {
        $Named = @(Get-ChildItem -Path $script:SourceRoot -Recurse -File -Filter '*.ps1' |
                Where-Object { (Get-Content -LiteralPath $_.FullName -Raw) -match 's_cpp' } |
                ForEach-Object { $_.Name })
        $Named | Should -Be @('Test-OERProcessServerMode.ps1')
    }

    It 'is called only by Test-OERHostCanConfirm' {
        $Callers = @(Get-ChildItem -Path $script:SourceRoot -Recurse -File -Filter '*.ps1' |
                Where-Object { $_.Name -ne 'Test-OERProcessServerMode.ps1' -and
                    (Get-Content -LiteralPath $_.FullName -Raw) -match 'Test-OERProcessServerMode' } |
                ForEach-Object { $_.Name })
        $Callers | Should -Be @('Test-OERHostCanConfirm.ps1')
    }
}
