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

    Context 'with -SessionUncertain (A10)' {
        BeforeAll {
            $script:UncertainRecord = InModuleScope Omnicit.EntraRBAC { New-OERSignInRefusedError -Command 'Invoke-OERStructure' -SessionUncertain }
        }

        It 'carries the same id, category and target' {
            $script:UncertainRecord | Should -BeOfType ([System.Management.Automation.ErrorRecord])
            $script:UncertainRecord.FullyQualifiedErrorId | Should -BeExactly 'SignInRefused'
            $script:UncertainRecord.CategoryInfo.Category | Should -Be ([System.Management.Automation.ErrorCategory]::AuthenticationError)
            $script:UncertainRecord.TargetObject | Should -BeOfType ([string])
            $script:UncertainRecord.TargetObject | Should -BeExactly 'Invoke-OERStructure'
        }

        It 'carries the exact session-uncertain message, naming no tenant' {
            $script:UncertainRecord.Exception | Should -BeOfType ([System.Exception])
            $script:UncertainRecord.Exception.Message | Should -BeExactly (
                "An earlier sign-in in this PowerShell session failed or was refused, so the module's session may not be the one " +
                'that sign-in asked for, and Omnicit.EntraRBAC sends nothing for a command that names no tenant: this request ' +
                'was not sent. Name the tenant with -TenantId, or run Connect-OER or Disconnect-OER, to send requests again.')
        }

        It 'does not say the session belongs to the tenant before it (BL-93)' {
            # The marker holds no cause: a failed renewal of the session's own token, an ARM step that failed
            # after the Graph half connected and a changed Graph SDK session all set it, and in the first
            # the sign-in asked for the very tenant the session already holds.
            $script:UncertainRecord.Exception.Message | Should -Not -Match 'tenant before'
            $script:UncertainRecord.Exception.Message | Should -Not -Match 'belong'
        }

        It 'keeps the default message without the switch' {
            $script:UncertainRecord.Exception.Message | Should -Not -BeExactly $script:Record.Exception.Message
            $Default = InModuleScope Omnicit.EntraRBAC { New-OERSignInRefusedError -Command 'Invoke-OERStructure' -SessionUncertain:$false }
            $Default.Exception.Message | Should -BeExactly $script:Record.Exception.Message
        }

        It 'declares -SessionUncertain as an optional switch' {
            $Parameter = InModuleScope Omnicit.EntraRBAC { (Get-Command New-OERSignInRefusedError).Parameters['SessionUncertain'] }
            $Parameter.ParameterType | Should -Be ([switch])
            @($Parameter.Attributes | Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] -and $_.Mandatory }).Count |
                Should -Be 0
        }
    }
}
