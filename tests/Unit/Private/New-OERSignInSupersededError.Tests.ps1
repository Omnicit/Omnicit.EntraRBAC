BeforeAll {
    Import-Module Omnicit.EntraRBAC -Force
    . "$PSScriptRoot/../TestHelpers/OERTransportTripwire.ps1"
    Install-OERTransportTripwire
}

AfterAll {
    try { Assert-OERTransportTripwire } finally { Uninstall-OERTransportTripwire }
}

Describe 'New-OERSignInSupersededError' {
    BeforeAll {
        # Built while the module holds a state with a tenant, so the message can be shown not to carry it.
        $script:Record = InModuleScope Omnicit.EntraRBAC {
            $script:_OERAuthState = @{
                TenantId    = '11111111-1111-1111-1111-111111111111'
                AuthMethod  = 'Interactive'
                ClientId    = '33333333-3333-3333-3333-333333333333'
                Environment = 'Global'
            }
            try {
                New-OERSignInSupersededError -Command 'New-OERGroup'
            } finally {
                $script:_OERAuthState = $null
            }
        }
    }

    It 'returns an ErrorRecord' {
        $script:Record | Should -BeOfType ([System.Management.Automation.ErrorRecord])
    }

    It 'carries the id SignInSuperseded' {
        $script:Record.FullyQualifiedErrorId | Should -BeExactly 'SignInSuperseded'
    }

    It 'carries the category AuthenticationError' {
        $script:Record.CategoryInfo.Category | Should -Be ([System.Management.Automation.ErrorCategory]::AuthenticationError)
    }

    It 'targets the superseded command' {
        $script:Record.TargetObject | Should -BeOfType ([string])
        $script:Record.TargetObject | Should -BeExactly 'New-OERGroup'
    }

    It 'carries the exact message' {
        $script:Record.Exception | Should -BeOfType ([System.Exception])
        $script:Record.Exception.Message | Should -BeExactly (
            'Another OER command in the same pipeline signed in to a different tenant or identity after this command ' +
            'signed in, so Omnicit.EntraRBAC sends nothing for this command: this request was not sent. Run the ' +
            'commands as separate statements, so that each one signs in and finishes before the next one starts.')
    }

    It 'names no tenant in its message' {
        $script:Record.Exception.Message | Should -Not -Match '11111111-1111-1111-1111-111111111111'
        $script:Record.ToString() | Should -Not -Match '11111111-1111-1111-1111-111111111111'
    }

    It 'keeps the same message whatever command it targets' {
        $Other = InModuleScope Omnicit.EntraRBAC { New-OERSignInSupersededError -Command 'a script block' }
        $Other.TargetObject | Should -BeExactly 'a script block'
        $Other.Exception.Message | Should -BeExactly $script:Record.Exception.Message
    }

    It 'requires the command it targets' {
        $Parameter = InModuleScope Omnicit.EntraRBAC { (Get-Command New-OERSignInSupersededError).Parameters['Command'] }
        $Parameter.ParameterType | Should -Be ([string])
        @($Parameter.Attributes | Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] -and $_.Mandatory }).Count |
            Should -Be 1
    }
}
