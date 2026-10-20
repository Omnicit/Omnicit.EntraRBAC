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

    It 'returns $true in the host the tests run in, which is not the Default Host' {
        # Reached: the test host has a name of its own, so the answer below is about that host.
        $Host.Name | Should -Not -Be 'Default Host'
        InModuleScope $script:moduleName { Test-OERHostCanConfirm } | Should -BeExactly $true
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

    It 'returns a [bool]' {
        InModuleScope $script:moduleName { (Test-OERHostCanConfirm) -is [bool] } | Should -BeTrue
    }
}
