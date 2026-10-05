BeforeAll {
    Import-Module Omnicit.EntraRBAC -Force
    . "$PSScriptRoot/../TestHelpers/OERTransportTripwire.ps1"
    Install-OERTransportTripwire
}

AfterAll {
    try { Assert-OERTransportTripwire } finally { Uninstall-OERTransportTripwire }
}

Describe 'New-OERGraphSessionChangedError' {
    AfterEach {
        InModuleScope Omnicit.EntraRBAC { $script:_OERAuthState = $null }
    }

    Context 'with the module''s auth state' {
        BeforeEach {
            InModuleScope Omnicit.EntraRBAC {
                $script:_OERAuthState = @{ TenantId = '44444444-4444-4444-4444-444444444444'; AuthMethod = 'Interactive' }
            }
            $script:Record = InModuleScope Omnicit.EntraRBAC { New-OERGraphSessionChangedError }
        }

        It 'returns an ErrorRecord' {
            $script:Record | Should -BeOfType ([System.Management.Automation.ErrorRecord])
        }

        It 'carries the id GraphSessionChanged' {
            $script:Record.FullyQualifiedErrorId | Should -BeExactly 'GraphSessionChanged'
        }

        It 'carries the category AuthenticationError' {
            $script:Record.CategoryInfo.Category | Should -Be ([System.Management.Automation.ErrorCategory]::AuthenticationError)
        }

        It 'targets the module''s own tenant and names it in the message' {
            $script:Record.TargetObject | Should -BeExactly '44444444-4444-4444-4444-444444444444'
            $script:Record.Exception.Message | Should -Match "tenant '44444444-4444-4444-4444-444444444444'"
        }

        It 'tells the operator to run Connect-OER or use a new PowerShell process' {
            $script:Record.Exception.Message | Should -Match 'Connect-OER'
            $script:Record.Exception.Message | Should -Match 'new PowerShell process'
        }

        It 'names the sign-in Connect-OER needs, the certificate or client secret of an app-only session' {
            # A bare Connect-OER signs in interactively, which does not take back an app-only session.
            $script:Record.Exception.Message | Should -Match ([regex]::Escape(
                    'Run Connect-OER with the same sign-in you used -- for an app-only session, its certificate or client secret -- to connect the module again'))
        }

        It 'names no tenant but the module''s own' {
            $Guids = @([regex]::Matches($script:Record.Exception.Message, '[0-9a-fA-F]{8}(-[0-9a-fA-F]{4}){3}-[0-9a-fA-F]{12}') | ForEach-Object { $_.Value })
            $Guids | Should -Be @('44444444-4444-4444-4444-444444444444')
        }
    }

    It 'builds with no auth state, targeting the empty string' {
        InModuleScope Omnicit.EntraRBAC { $script:_OERAuthState = $null }
        { InModuleScope Omnicit.EntraRBAC { $null = New-OERGraphSessionChangedError } } | Should -Not -Throw
        $NoStateRecord = InModuleScope Omnicit.EntraRBAC { New-OERGraphSessionChangedError }
        $NoStateRecord.FullyQualifiedErrorId | Should -BeExactly 'GraphSessionChanged'
        $NoStateRecord.TargetObject | Should -BeOfType ([string])
        $NoStateRecord.TargetObject | Should -BeExactly ''
    }
}
