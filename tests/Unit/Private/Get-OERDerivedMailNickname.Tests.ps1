BeforeAll {
    Import-Module Omnicit.EntraRBAC -Force
    . "$PSScriptRoot/../TestHelpers/OERTransportTripwire.ps1"
    Install-OERTransportTripwire
}

AfterAll {
    try { Assert-OERTransportTripwire } finally { Uninstall-OERTransportTripwire }
}

Describe 'Get-OERDerivedMailNickname' {
    # The single owner of the mail alias New-OERGroup derives from a display name (Sprint 11 step 3,
    # BL-132). Pure: it is called here with no mock at all and reaches no transport.
    It 'keeps a name made of the allowed characters as it is' {
        InModuleScope Omnicit.EntraRBAC {
            Get-OERDerivedMailNickname -DisplayName 'role_sec_team' | Should -BeExactly 'role_sec_team'
        }
    }

    It 'removes white space and parentheses' {
        InModuleScope Omnicit.EntraRBAC {
            Get-OERDerivedMailNickname -DisplayName 'Grupp med mellanslag (test)' | Should -BeExactly 'Gruppmedmellanslagtest'
        }
    }

    It 'keeps the dot, the underscore and the hyphen' {
        InModuleScope Omnicit.EntraRBAC {
            Get-OERDerivedMailNickname -DisplayName 'a.b-c_d' | Should -BeExactly 'a.b-c_d'
        }
    }

    It 'removes a non-ASCII letter, so a name made only of such letters derives the empty string' {
        InModuleScope Omnicit.EntraRBAC {
            $Name = "$([char]0x00C5)$([char]0x00C4)"
            $Derived = Get-OERDerivedMailNickname -DisplayName $Name
            $Derived | Should -BeOfType [string]
            $Derived.Length | Should -Be 0
        }
    }

    It 'derives the empty string from the empty string' {
        InModuleScope Omnicit.EntraRBAC {
            $Derived = Get-OERDerivedMailNickname -DisplayName ''
            $Derived | Should -BeOfType [string]
            $Derived.Length | Should -Be 0
        }
    }

    It 'does not shorten the result: a 65 character name derives 65 characters (the caller decides)' {
        InModuleScope Omnicit.EntraRBAC {
            (Get-OERDerivedMailNickname -DisplayName ('g' * 65)).Length | Should -Be 65
        }
    }

    It 'keeps letter case' {
        InModuleScope Omnicit.EntraRBAC {
            Get-OERDerivedMailNickname -DisplayName 'Old Name (x)' | Should -BeExactly 'OldNamex'
        }
    }
}
