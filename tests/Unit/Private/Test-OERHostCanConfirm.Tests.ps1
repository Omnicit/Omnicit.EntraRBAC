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
            InModuleScope $script:moduleName { Test-OERHostCanConfirm } | Should -BeExactly $Expected
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

    It 'answers $true in a background job (Start-Job, ServerRemoteHost), whose prompt Receive-Job shows (BL-198)' {
        $Job = Start-Job -ScriptBlock {
            Import-Module Omnicit.EntraRBAC -Force -ErrorAction Stop
            "HOST:$($Host.Name)"
            "SENDER:$($null -ne $PSSenderInfo)"
            "ANSWER:$(& (Get-Module Omnicit.EntraRBAC) { Test-OERHostCanConfirm })"
        }
        try {
            $null = $Job | Wait-Job -Timeout 120
            $Output = @($Job | Receive-Job -ErrorAction Stop | ForEach-Object { "$_" })
            $Job.State | Should -BeExactly 'Completed'
        } finally {
            $Job | Remove-Job -Force
        }
        $Output | Should -Be @('HOST:ServerRemoteHost', 'SENDER:True', 'ANSWER:True')
    }

    It 'returns a [bool]' {
        InModuleScope $script:moduleName { (Test-OERHostCanConfirm) -is [bool] } | Should -BeTrue
    }
}
