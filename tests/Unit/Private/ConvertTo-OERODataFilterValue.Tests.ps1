BeforeAll {
    Import-Module Omnicit.EntraRBAC -Force
}

Describe 'ConvertTo-OERODataFilterValue' {
    It 'returns a plain value unchanged' {
        InModuleScope Omnicit.EntraRBAC {
            ConvertTo-OERODataFilterValue -Value 'role_sec_it_core' | Should -Be 'role_sec_it_core'
        }
    }

    It 'doubles an embedded single quote and then percent-encodes both quotes' {
        # Microsoft Learn: double the quote inside the literal FIRST, then percent-encode the
        # whole value. The doubled '' therefore reaches Graph as %27%27, which Graph decodes
        # back to a literal '' inside the string literal.
        InModuleScope Omnicit.EntraRBAC {
            ConvertTo-OERODataFilterValue -Value "O'Brien" | Should -Be 'O%27%27Brien'
        }
    }

    It 'percent-encodes the reserved characters that would otherwise corrupt the query string' {
        InModuleScope Omnicit.EntraRBAC {
            ConvertTo-OERODataFilterValue -Value 'A&B' | Should -Be 'A%26B'
            ConvertTo-OERODataFilterValue -Value 'A+B' | Should -Be 'A%2BB'
            ConvertTo-OERODataFilterValue -Value 'A#B' | Should -Be 'A%23B'
            ConvertTo-OERODataFilterValue -Value 'A B' | Should -Be 'A%20B'
        }
    }

    It 'encodes the guest-user #EXT# marker so the fragment delimiter cannot truncate the query' {
        InModuleScope Omnicit.EntraRBAC {
            ConvertTo-OERODataFilterValue -Value 'anna_contoso.com#EXT#@fabrikam.onmicrosoft.com' |
                Should -Be 'anna_contoso.com%23EXT%23%40fabrikam.onmicrosoft.com'
        }
    }

    It 'returns an empty string for null and for empty input' {
        InModuleScope Omnicit.EntraRBAC {
            ConvertTo-OERODataFilterValue -Value $null | Should -Be ''
            ConvertTo-OERODataFilterValue -Value '' | Should -Be ''
        }
    }

    It 'makes no network call and never throws' {
        InModuleScope Omnicit.EntraRBAC {
            Mock Invoke-OERGraphRequest { throw 'the helper must not call Graph' }
            { ConvertTo-OERODataFilterValue -Value "weird '&#+ value" } | Should -Not -Throw
            Should -Invoke Invoke-OERGraphRequest -Times 0
        }
    }
}
