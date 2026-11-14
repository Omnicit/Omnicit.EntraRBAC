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

Describe 'Test-OERProcessServerMode (BL-198)' {
    BeforeAll {
        # Runs the script text in a pwsh started with -sshs (the SSH remoting subsystem's command line) and
        # driven over stdio, no ssh involved. Returns $null when the process instance's start info cannot
        # be changed, so the caller reports Inconclusive and never a false pass.
        function script:Invoke-SshsScript {
            param([string]$ScriptText)
            $Ppi = [System.Management.Automation.Runspaces.PowerShellProcessInstance]::new()
            $Runspace = $null
            $Shell = $null
            try {
                $Field = $Ppi.GetType().GetField('_startInfo', [System.Reflection.BindingFlags]'Instance,NonPublic')
                if ($null -eq $Field) { return $null }
                $StartInfo = $Field.GetValue($Ppi)
                $Index = -1
                for ($i = 0; $i -lt $StartInfo.ArgumentList.Count; $i++) {
                    if ($StartInfo.ArgumentList[$i] -eq '-s') { $Index = $i; break }
                }
                if ($Index -lt 0) { return $null }
                $StartInfo.ArgumentList[$Index] = '-sshs'
                $Runspace = [runspacefactory]::CreateOutOfProcessRunspace($null, $Ppi)
                $Runspace.Open()
                $Shell = [powershell]::Create()
                $Shell.Runspace = $Runspace
                $null = $Shell.AddScript($ScriptText)
                @($Shell.Invoke() | ForEach-Object { "$_" })
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
        $Output = Invoke-SshsScript -ScriptText @'
Import-Module Omnicit.EntraRBAC -Force -ErrorAction Stop
"HOST:$($Host.Name)"
"ARGS:$([Environment]::GetCommandLineArgs() -join ' ')"
"ANSWER:$(& (Get-Module Omnicit.EntraRBAC) { Test-OERProcessServerMode })"
'@
        if ($null -eq $Output) {
            Set-ItResult -Inconclusive -Because 'the PowerShellProcessInstance _startInfo field or its -s argument is not there in this PowerShell build'
            return
        }
        $Output | Should -Contain 'HOST:ServerRemoteHost'
        ($Output | Where-Object { $_ -like 'ARGS:*' }) | Should -Match '(^| )-sshs( |$)'
        $Output | Should -Contain 'ANSWER:False'
    }
}

Describe 'Test-OERProcessServerMode is the single reader of the startup parser (BL-198)' {
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
