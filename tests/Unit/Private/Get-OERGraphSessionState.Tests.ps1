BeforeAll {
    Import-Module Omnicit.EntraRBAC -Force
    . "$PSScriptRoot/../TestHelpers/OERTransportTripwire.ps1"
    Install-OERTransportTripwire
}

AfterAll {
    try { Assert-OERTransportTripwire } finally { Uninstall-OERTransportTripwire }
}

Describe 'Get-OERGraphSessionState' {
    BeforeAll {
        # The session this module connected, as Connect-MgGraph -AccessToken leaves it.
        $script:OwnContext = [pscustomobject]@{
            AuthType = 'UserProvidedAccessToken'; TokenCredentialType = 'UserProvidedAccessToken'
            ClientId = '33333333-3333-3333-3333-333333333333'; TenantId = '44444444-4444-4444-4444-444444444444'
            Account = 'admin@contoso.com'; AppName = 'oer-test-app'; Environment = 'Global'
            Scopes = @('Group.ReadWrite.All')
        }
        $script:OwnFingerprint = InModuleScope Omnicit.EntraRBAC -Parameters @{ C = $script:OwnContext } {
            param($C) Get-OERGraphSessionFingerprint -Context $C
        }
    }

    AfterEach {
        InModuleScope Omnicit.EntraRBAC { $script:_OERAuthState = $null }
    }

    It 'is Untracked with no auth state, and does not read the session' {
        Mock -ModuleName Omnicit.EntraRBAC Get-MgContext { $script:OwnContext }
        InModuleScope Omnicit.EntraRBAC { $script:_OERAuthState = $null }
        InModuleScope Omnicit.EntraRBAC { Get-OERGraphSessionState } | Should -BeExactly 'Untracked'
        Should -Invoke -ModuleName Omnicit.EntraRBAC Get-MgContext -Times 0
    }

    It 'is Untracked for a state that carries no GraphSessionFingerprint key, and does not read the session' {
        Mock -ModuleName Omnicit.EntraRBAC Get-MgContext { $script:OwnContext }
        InModuleScope Omnicit.EntraRBAC {
            $script:_OERAuthState = @{ TenantId = '44444444-4444-4444-4444-444444444444'; AuthMethod = 'Interactive' }
        }
        InModuleScope Omnicit.EntraRBAC { Get-OERGraphSessionState } | Should -BeExactly 'Untracked'
        Should -Invoke -ModuleName Omnicit.EntraRBAC Get-MgContext -Times 0
    }

    It 'is Untracked for a state that is not a dictionary, even one with a GraphSessionFingerprint property' {
        Mock -ModuleName Omnicit.EntraRBAC Get-MgContext { $script:OwnContext }
        InModuleScope Omnicit.EntraRBAC -Parameters @{ F = $script:OwnFingerprint } {
            param($F)
            $script:_OERAuthState = [pscustomobject]@{
                TenantId = '44444444-4444-4444-4444-444444444444'; GraphSessionFingerprint = $F
            }
        }
        InModuleScope Omnicit.EntraRBAC { Get-OERGraphSessionState } | Should -BeExactly 'Untracked'
        Should -Invoke -ModuleName Omnicit.EntraRBAC Get-MgContext -Times 0
    }

    It 'is Own when the session in the process fingerprints to the recorded value' {
        Mock -ModuleName Omnicit.EntraRBAC Get-MgContext { $script:OwnContext }
        InModuleScope Omnicit.EntraRBAC -Parameters @{ F = $script:OwnFingerprint } {
            param($F)
            $script:_OERAuthState = @{ TenantId = '44444444-4444-4444-4444-444444444444'; GraphSessionFingerprint = $F }
        }
        InModuleScope Omnicit.EntraRBAC { Get-OERGraphSessionState } | Should -BeExactly 'Own'
        Should -Invoke -ModuleName Omnicit.EntraRBAC Get-MgContext -Times 1 -Exactly
    }

    It 'is Absent when the process holds no session and a fingerprint was recorded' {
        Mock -ModuleName Omnicit.EntraRBAC Get-MgContext { }
        InModuleScope Omnicit.EntraRBAC -Parameters @{ F = $script:OwnFingerprint } {
            param($F)
            $script:_OERAuthState = @{ TenantId = '44444444-4444-4444-4444-444444444444'; GraphSessionFingerprint = $F }
        }
        InModuleScope Omnicit.EntraRBAC { Get-OERGraphSessionState } | Should -BeExactly 'Absent'
        Should -Invoke -ModuleName Omnicit.EntraRBAC Get-MgContext -Times 1 -Exactly
    }

    It 'is Absent when the process holds no session and the recorded value is $null' {
        Mock -ModuleName Omnicit.EntraRBAC Get-MgContext { }
        InModuleScope Omnicit.EntraRBAC {
            $script:_OERAuthState = @{ TenantId = '44444444-4444-4444-4444-444444444444'; GraphSessionFingerprint = $null }
        }
        InModuleScope Omnicit.EntraRBAC { Get-OERGraphSessionState } | Should -BeExactly 'Absent'
    }

    It 'is Changed when another session replaced the recorded one (another ClientId)' {
        $script:OtherContext = [pscustomobject]@{
            AuthType = 'UserProvidedAccessToken'; TokenCredentialType = 'UserProvidedAccessToken'
            ClientId = '55555555-5555-5555-5555-555555555555'; TenantId = '44444444-4444-4444-4444-444444444444'
            Account = 'admin@contoso.com'; AppName = 'oer-test-app'; Environment = 'Global'
            Scopes = @('Group.ReadWrite.All')
        }
        Mock -ModuleName Omnicit.EntraRBAC Get-MgContext { $script:OtherContext }
        InModuleScope Omnicit.EntraRBAC -Parameters @{ F = $script:OwnFingerprint } {
            param($F)
            $script:_OERAuthState = @{ TenantId = '44444444-4444-4444-4444-444444444444'; GraphSessionFingerprint = $F }
        }
        InModuleScope Omnicit.EntraRBAC { Get-OERGraphSessionState } | Should -BeExactly 'Changed'
    }

    It 'is Changed when a session appears and the recorded value is $null (the key is present)' {
        Mock -ModuleName Omnicit.EntraRBAC Get-MgContext { $script:OwnContext }
        InModuleScope Omnicit.EntraRBAC {
            $script:_OERAuthState = @{ TenantId = '44444444-4444-4444-4444-444444444444'; GraphSessionFingerprint = $null }
        }
        InModuleScope Omnicit.EntraRBAC { Get-OERGraphSessionState } | Should -BeExactly 'Changed'
    }

    It 'is Changed for a session that differs from the recorded one only in letter case (ordinal comparison)' {
        $Upper = [pscustomobject]@{
            AuthType = 'UserProvidedAccessToken'; TokenCredentialType = 'UserProvidedAccessToken'
            ClientId = '33333333-3333-3333-3333-333333333333'; TenantId = '44444444-4444-4444-4444-444444444444'
            Account = 'ADMIN@contoso.com'; AppName = 'oer-test-app'; Environment = 'Global'
            Scopes = @('Group.ReadWrite.All')
        }
        $UpperFingerprint = InModuleScope Omnicit.EntraRBAC -Parameters @{ C = $Upper } {
            param($C) Get-OERGraphSessionFingerprint -Context $C
        }
        # The lower-case account is the only difference: the fixture context above.
        $script:OwnContext.Account | Should -BeExactly 'admin@contoso.com'
        Mock -ModuleName Omnicit.EntraRBAC Get-MgContext { $script:OwnContext }
        InModuleScope Omnicit.EntraRBAC -Parameters @{ F = $UpperFingerprint } {
            param($F)
            $script:_OERAuthState = @{ TenantId = '44444444-4444-4444-4444-444444444444'; GraphSessionFingerprint = $F }
        }
        InModuleScope Omnicit.EntraRBAC { Get-OERGraphSessionState } | Should -BeExactly 'Changed'
    }
}
