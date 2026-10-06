BeforeAll {
    Import-Module Omnicit.EntraRBAC -Force
    . "$PSScriptRoot/../TestHelpers/OERTransportTripwire.ps1"
    Install-OERTransportTripwire
}

AfterAll {
    try { Assert-OERTransportTripwire } finally { Uninstall-OERTransportTripwire }
}

Describe 'New-OERSignInRefusedError' {
    BeforeAll {
        $script:Record = InModuleScope Omnicit.EntraRBAC { New-OERSignInRefusedError -Command 'Get-OERGroup' }
    }

    It 'returns an ErrorRecord' {
        $script:Record | Should -BeOfType ([System.Management.Automation.ErrorRecord])
    }

    It 'carries the id SignInRefused' {
        $script:Record.FullyQualifiedErrorId | Should -BeExactly 'SignInRefused'
    }

    It 'carries the category AuthenticationError' {
        $script:Record.CategoryInfo.Category | Should -Be ([System.Management.Automation.ErrorCategory]::AuthenticationError)
    }

    It 'targets the refused command' {
        $script:Record.TargetObject | Should -BeOfType ([string])
        $script:Record.TargetObject | Should -BeExactly 'Get-OERGroup'
    }

    It 'carries the exact message' {
        $script:Record.Exception | Should -BeOfType ([System.Exception])
        $script:Record.Exception.Message | Should -BeExactly (
            "The module's sign-in for this command was refused, so Omnicit.EntraRBAC sends nothing for this command: " +
            'this request was not sent. Run Connect-OER, or run a new command whose sign-in succeeds, to send requests again.')
    }

    It 'keeps the same message whatever command it targets' {
        $Other = InModuleScope Omnicit.EntraRBAC { New-OERSignInRefusedError -Command 'a script block' }
        $Other.TargetObject | Should -BeExactly 'a script block'
        $Other.Exception.Message | Should -BeExactly $script:Record.Exception.Message
    }

    It 'requires the command it targets' {
        $Parameter = InModuleScope Omnicit.EntraRBAC { (Get-Command New-OERSignInRefusedError).Parameters['Command'] }
        $Parameter.ParameterType | Should -Be ([string])
        @($Parameter.Attributes | Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] -and $_.Mandatory }).Count |
            Should -Be 1
    }
}
