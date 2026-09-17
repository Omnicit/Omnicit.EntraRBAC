BeforeAll {
    $script:moduleName = 'Omnicit.EntraRBAC'
    Get-Module $script:moduleName | Remove-Module -Force -ErrorAction SilentlyContinue
    Import-Module $script:moduleName -Force -ErrorAction Stop
}

Describe 'Resolve-OERName' {
    It 'substitutes tokens from a template' {
        InModuleScope $script:moduleName {
            $Name = Resolve-OERName -Template 'role_sec_{area}_{tier}' -Tokens @{ area = 'identity'; tier = 'administrator' }
            $Name | Should -Be 'role_sec_identity_administrator'
        }
    }

    It 'throws when a token in the template has no value' {
        InModuleScope $script:moduleName {
            { Resolve-OERName -Template 'role_sec_{area}_{tier}' -Tokens @{ area = 'identity' } } |
                Should -Throw -ExpectedMessage '*tier*'
        }
    }

    It 'rejects names exceeding the maximum length' {
        InModuleScope $script:moduleName {
            { Resolve-OERName -Template '{name}' -Tokens @{ name = ('x' * 300) } -MaxLength 256 } |
                Should -Throw -ExpectedMessage '*length*'
        }
    }

    It 'rejects disallowed characters when -Strict is set' {
        InModuleScope $script:moduleName {
            { Resolve-OERName -Template '{name}' -Tokens @{ name = 'bad/name' } -Strict } |
                Should -Throw -ExpectedMessage '*character*'
        }
    }
}
