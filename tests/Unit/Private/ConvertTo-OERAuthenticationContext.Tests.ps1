BeforeAll {
    $script:moduleName = 'Omnicit.EntraRBAC'
    Get-Module $script:moduleName | Remove-Module -Force -ErrorAction SilentlyContinue
    Import-Module $script:moduleName -Force -ErrorAction Stop
}

Describe 'ConvertTo-OERAuthenticationContext' {
    It 'maps the Graph shape onto the module shape and tags it' {
        InModuleScope $script:moduleName {
            $R = ConvertTo-OERAuthenticationContext -InputObject @{
                id = 'c1'; displayName = 'Require MFA'; description = 'Step-up'; isAvailable = $true
            }
            $R.AuthenticationContextId | Should -Be 'c1'
            $R.DisplayName | Should -Be 'Require MFA'
            $R.Description | Should -Be 'Step-up'
            $R.IsAvailable | Should -BeTrue
            $R.PSObject.TypeNames[0] | Should -Be 'Omnicit.EntraRBAC.AuthenticationContext'
        }
    }

    It 'reports IsAvailable as a boolean false when Graph omits it' {
        InModuleScope $script:moduleName {
            $R = ConvertTo-OERAuthenticationContext -InputObject @{ id = 'c2'; displayName = 'Unpublished' }
            $R.IsAvailable | Should -BeOfType [bool]
            $R.IsAvailable | Should -BeFalse
        }
    }
}
