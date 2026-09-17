BeforeAll {
    $script:moduleName = 'Omnicit.EntraRBAC'
    Get-Module $script:moduleName | Remove-Module -Force -ErrorAction SilentlyContinue
    Import-Module $script:moduleName -Force -ErrorAction Stop
}

Describe 'ConvertTo-OERCatalog' {
    It 'maps Graph properties and tags the type' {
        InModuleScope $script:moduleName {
            $Raw = @{
                id = 'cat-1'; displayName = 'CAT-IT-Core'; description = 'Core IT'
                catalogType = 'userManaged'; state = 'published'; isExternallyVisible = $true
            }
            $Out = ConvertTo-OERCatalog -InputObject $Raw
            $Out.Id | Should -Be 'cat-1'
            $Out.DisplayName | Should -Be 'CAT-IT-Core'
            $Out.ExternallyVisible | Should -BeTrue
            $Out.State | Should -Be 'published'
            $Out.PSObject.TypeNames[0] | Should -Be 'Omnicit.EntraRBAC.Catalog'
        }
    }

    It 'coerces a missing isExternallyVisible to $false' {
        InModuleScope $script:moduleName {
            $Out = ConvertTo-OERCatalog -InputObject @{ id = 'c'; displayName = 'd' }
            $Out.ExternallyVisible | Should -BeFalse
        }
    }
}
