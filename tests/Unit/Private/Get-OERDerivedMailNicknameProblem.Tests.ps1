BeforeAll {
    Import-Module Omnicit.EntraRBAC -Force
    . "$PSScriptRoot/../TestHelpers/OERTransportTripwire.ps1"
    Install-OERTransportTripwire
}

AfterAll {
    try { Assert-OERTransportTripwire } finally { Uninstall-OERTransportTripwire }
}

Describe 'Get-OERDerivedMailNicknameProblem' {
    # The single owner of the condition and the text of the DerivedMailNicknameInvalid refusal (BL-143b).
    # Pure: called with no mock at all.
    It 'returns $null for a name whose alias is accepted' {
        InModuleScope Omnicit.EntraRBAC {
            Get-OERDerivedMailNicknameProblem -DisplayName 'role_sec_team' | Should -BeNullOrEmpty
        }
    }

    It 'returns $null for a name with spaces whose alias is non-empty' {
        InModuleScope Omnicit.EntraRBAC {
            Get-OERDerivedMailNicknameProblem -DisplayName 'Grupp med mellanslag (test)' | Should -BeNullOrEmpty
        }
    }

    It 'returns $null at exactly 64 derived characters' {
        InModuleScope Omnicit.EntraRBAC {
            Get-OERDerivedMailNicknameProblem -DisplayName ('g' * 64) | Should -BeNullOrEmpty
        }
    }

    It 'returns the empty-alias message when the derivation is empty' {
        InModuleScope Omnicit.EntraRBAC {
            $Msg = Get-OERDerivedMailNicknameProblem -DisplayName '!!!'
            $Msg | Should -BeOfType [string]
            $Msg | Should -BeExactly ("The mail alias derived from the group name '!!!' is empty (the name has no character A-Z, a-z, 0-9, '.', '_' or '-'); " +
                'Microsoft Graph accepts 1 to 64 characters. Nothing was sent. Pass -MailNickname with the alias the group should carry.')
        }
    }

    It 'returns the empty-alias message for the empty string' {
        InModuleScope Omnicit.EntraRBAC {
            Get-OERDerivedMailNicknameProblem -DisplayName '' | Should -BeLike "The mail alias derived from the group name '' is empty*"
        }
    }

    It 'returns the length message at 65 derived characters' {
        InModuleScope Omnicit.EntraRBAC {
            $Name = 'g' * 65
            Get-OERDerivedMailNicknameProblem -DisplayName $Name | Should -BeExactly ("The mail alias derived from the group name '$Name' is 65 characters long; " +
                'Microsoft Graph accepts 1 to 64 characters. Nothing was sent. Pass -MailNickname with the alias the group should carry.')
        }
    }

    It 'counts the derived characters, not the name: spaces do not count towards 64' {
        InModuleScope Omnicit.EntraRBAC {
            Get-OERDerivedMailNicknameProblem -DisplayName (('g ' * 64).Trim()) | Should -BeNullOrEmpty
        }
    }

    It 'is the text New-OERGroup publishes' {
        Mock -ModuleName Omnicit.EntraRBAC Initialize-OERAuth { }
        Mock -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest { }
        $Msg = InModuleScope Omnicit.EntraRBAC { Get-OERDerivedMailNicknameProblem -DisplayName '!!!' }
        $null = New-OERGroup -DisplayName '!!!' -Confirm:$false -ErrorVariable Ev -ErrorAction SilentlyContinue
        @($Ev | Where-Object { $_.FullyQualifiedErrorId -like 'DerivedMailNicknameInvalid*' })[0].Exception.Message | Should -BeExactly $Msg
    }
}
