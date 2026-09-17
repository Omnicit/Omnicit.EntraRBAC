BeforeAll {
    Import-Module Omnicit.EntraRBAC -Force
}

Describe 'Test-OERTenantAlias' {
    It 'accepts a plain alias' {
        InModuleScope Omnicit.EntraRBAC {
            Test-OERTenantAlias -Value 'contoso' | Should -BeTrue
        }
    }
    It 'accepts dots, dashes and underscores' {
        InModuleScope Omnicit.EntraRBAC {
            Test-OERTenantAlias -Value 'contoso.prod_eu-1' | Should -BeTrue
        }
    }
    It 'rejects a relative traversal segment' {
        InModuleScope Omnicit.EntraRBAC {
            Test-OERTenantAlias -Value '../../../evil' | Should -BeFalse
        }
    }
    It 'rejects a backslash traversal segment' {
        InModuleScope Omnicit.EntraRBAC {
            Test-OERTenantAlias -Value '..\..\evil' | Should -BeFalse
        }
    }
    It 'rejects an embedded double dot even without a separator' {
        InModuleScope Omnicit.EntraRBAC {
            Test-OERTenantAlias -Value 'a..b' | Should -BeFalse
        }
    }
    It 'rejects a bare dot and a bare double dot' {
        InModuleScope Omnicit.EntraRBAC {
            Test-OERTenantAlias -Value '.'  | Should -BeFalse
            Test-OERTenantAlias -Value '..' | Should -BeFalse
        }
    }
    It 'rejects a rooted path' {
        InModuleScope Omnicit.EntraRBAC {
            Test-OERTenantAlias -Value 'C:\Windows\System32\evil' | Should -BeFalse
        }
    }
    It 'rejects a UNC path' {
        InModuleScope Omnicit.EntraRBAC {
            Test-OERTenantAlias -Value '\\server\share\evil' | Should -BeFalse
        }
    }
    It 'rejects a forward slash' {
        InModuleScope Omnicit.EntraRBAC {
            Test-OERTenantAlias -Value 'a/b' | Should -BeFalse
        }
    }
    It 'rejects a wildcard' {
        InModuleScope Omnicit.EntraRBAC {
            Test-OERTenantAlias -Value 'con*oso' | Should -BeFalse
        }
    }
    It 'rejects null and empty' {
        InModuleScope Omnicit.EntraRBAC {
            Test-OERTenantAlias -Value $null | Should -BeFalse
            Test-OERTenantAlias -Value ''    | Should -BeFalse
        }
    }
    It 'does not throw on any input' {
        InModuleScope Omnicit.EntraRBAC {
            { Test-OERTenantAlias -Value '../x' } | Should -Not -Throw
        }
    }
    It 'rejects a Windows reserved device name' {
        InModuleScope Omnicit.EntraRBAC {
            Test-OERTenantAlias -Value 'CON' | Should -BeFalse
        }
    }
    It 'rejects a Windows reserved device name case-insensitively' {
        InModuleScope Omnicit.EntraRBAC {
            Test-OERTenantAlias -Value 'com1' | Should -BeFalse
        }
    }
    It 'rejects a reserved device name used as the segment before the first dot' {
        InModuleScope Omnicit.EntraRBAC {
            Test-OERTenantAlias -Value 'con.prod' | Should -BeFalse
        }
    }
    It 'accepts an alias that merely starts with a reserved device name' {
        InModuleScope Omnicit.EntraRBAC {
            Test-OERTenantAlias -Value 'contoso' | Should -BeTrue
            Test-OERTenantAlias -Value 'communications' | Should -BeTrue
        }
    }
}
