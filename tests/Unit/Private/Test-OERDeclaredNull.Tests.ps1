BeforeAll {
    $script:moduleName = 'Omnicit.EntraRBAC'
    Get-Module $script:moduleName | Remove-Module -Force -ErrorAction SilentlyContinue
    Import-Module $script:moduleName -Force -ErrorAction Stop
}

Describe 'Test-OERDeclaredNull' {

    It 'returns false for a null node' {
        InModuleScope $script:moduleName {
            Test-OERDeclaredNull -Node $null -Name 'members' | Should -Be $false
        }
    }

    It 'returns false when the property is absent' {
        InModuleScope $script:moduleName {
            Test-OERDeclaredNull -Node ([PSCustomObject]@{ displayName = 'x' }) -Name 'members' | Should -Be $false
        }
    }

    It 'returns true when the property is present and explicitly null' {
        InModuleScope $script:moduleName {
            Test-OERDeclaredNull -Node ([PSCustomObject]@{ members = $null }) -Name 'members' | Should -Be $true
        }
    }

    It 'returns false for an explicitly empty array, which is a declared (non-null) value' {
        InModuleScope $script:moduleName {
            Test-OERDeclaredNull -Node ([PSCustomObject]@{ members = @() }) -Name 'members' | Should -Be $false
        }
    }

    It 'returns false for an explicitly empty string, which is a declared (non-null) value' {
        InModuleScope $script:moduleName {
            Test-OERDeclaredNull -Node ([PSCustomObject]@{ description = '' }) -Name 'description' | Should -Be $false
        }
    }

    It 'matches the property name case-insensitively' {
        InModuleScope $script:moduleName {
            Test-OERDeclaredNull -Node ([PSCustomObject]@{ Members = $null }) -Name 'members' | Should -Be $true
        }
    }

    It 'reads a ConvertFrom-Json node carrying an explicit null' {
        InModuleScope $script:moduleName {
            $Node = '{ "members": null, "displayName": "x" }' | ConvertFrom-Json
            Test-OERDeclaredNull -Node $Node -Name 'members' | Should -Be $true
            Test-OERDeclaredNull -Node $Node -Name 'displayName' | Should -Be $false
        }
    }
}
