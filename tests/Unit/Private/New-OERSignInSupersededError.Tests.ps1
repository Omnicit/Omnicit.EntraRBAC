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

    It 'carries the exact message, naming the command it targets' {
        $script:Record.Exception | Should -BeOfType ([System.Exception])
        $script:Record.Exception.Message | Should -BeExactly (
            'Another OER command in the same pipeline signed in to a different tenant or identity after New-OERGroup ' +
            'began, so Omnicit.EntraRBAC sends nothing while New-OERGroup runs: this request was not sent. Run ' +
            'the commands as separate statements, so that each one signs in and finishes before the next one starts.')
    }

    It 'names no tenant in its message' {
        # The name passed holds no tenant, so a tenant in the text could only come from the state.
        $script:Record.TargetObject | Should -Not -Match '11111111-1111-1111-1111-111111111111'
        $script:Record.Exception.Message | Should -Not -Match '11111111-1111-1111-1111-111111111111'
        $script:Record.ToString() | Should -Not -Match '11111111-1111-1111-1111-111111111111'
    }

    It 'names the command it targets exactly as passed, and changes nothing else in the message' {
        $Other = InModuleScope Omnicit.EntraRBAC { New-OERSignInSupersededError -Command 'a script block' }
        $Other.TargetObject | Should -BeExactly 'a script block'
        $Other.Exception.Message | Should -BeExactly (
            'Another OER command in the same pipeline signed in to a different tenant or identity after a script block ' +
            'began, so Omnicit.EntraRBAC sends nothing while a script block runs: this request was not sent. Run ' +
            'the commands as separate statements, so that each one signs in and finishes before the next one starts.')
        # The name is the only value in the text: with each name taken out, the two messages are one.
        $Other.Exception.Message.Replace('a script block', '#') |
            Should -BeExactly $script:Record.Exception.Message.Replace('New-OERGroup', '#')
    }

    It 'writes a name that holds a format item as it is' {
        $Braced = InModuleScope Omnicit.EntraRBAC { New-OERSignInSupersededError -Command 'Invoke-{0}Probe' }
        $Braced.TargetObject | Should -BeExactly 'Invoke-{0}Probe'
        $Braced.Exception.Message | Should -BeLike '*after Invoke-{0}Probe began,*while Invoke-{0}Probe runs:*'
    }

    It 'requires the command it targets' {
        $Parameter = InModuleScope Omnicit.EntraRBAC { (Get-Command New-OERSignInSupersededError).Parameters['Command'] }
        $Parameter.ParameterType | Should -Be ([string])
        @($Parameter.Attributes | Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] -and $_.Mandatory }).Count |
            Should -Be 1
    }
}
