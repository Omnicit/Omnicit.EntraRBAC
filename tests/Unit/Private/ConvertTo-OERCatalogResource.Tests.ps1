BeforeAll {
    $script:moduleName = 'Omnicit.EntraRBAC'
    Get-Module $script:moduleName | Remove-Module -Force -ErrorAction SilentlyContinue
    Import-Module $script:moduleName -Force -ErrorAction Stop
}

Describe 'ConvertTo-OERCatalogResource' {
    It 'maps Graph resource properties and tags the type' {
        InModuleScope $script:moduleName {
            $Raw = @{
                id = 'res-1'; displayName = 'Grp-Sales'; resourceType = 'Security Group'
                originId = 'grp-guid'; originSystem = 'AadGroup'
            }
            $Out = ConvertTo-OERCatalogResource -InputObject $Raw
            $Out.Id | Should -Be 'res-1'
            $Out.DisplayName | Should -Be 'Grp-Sales'
            $Out.ResourceType | Should -Be 'Security Group'
            $Out.OriginSystem | Should -Be 'AadGroup'
            $Out.OriginId | Should -Be 'grp-guid'
            $Out.PSObject.TypeNames[0] | Should -Be 'Omnicit.EntraRBAC.CatalogResource'
        }
    }

    It 'surfaces the Url property when present' {
        InModuleScope $script:moduleName {
            $Raw = @{
                id = 'res-2'; displayName = 'SP-Site'; resourceType = 'SharePoint Online Site'
                originId = 'site-guid'; originSystem = 'SharePointOnline'
                url = 'https://contoso.sharepoint.com/sites/IT'
            }
            $Out = ConvertTo-OERCatalogResource -InputObject $Raw
            $Out.Url | Should -Be 'https://contoso.sharepoint.com/sites/IT'
        }
    }

    It 'sets Url to $null when the property is absent' {
        InModuleScope $script:moduleName {
            $Raw = @{ id = 'res-3'; displayName = 'App-Test'; resourceType = 'Application' }
            $Out = ConvertTo-OERCatalogResource -InputObject $Raw
            $Out.Url | Should -BeNullOrEmpty
        }
    }

    It 'derives ResourceType from originSystem when the Graph resourceType is empty' {
        InModuleScope $script:moduleName {
            (ConvertTo-OERCatalogResource -InputObject @{ id = 'g'; originSystem = 'AadGroup' }).ResourceType | Should -Be 'Group'
            (ConvertTo-OERCatalogResource -InputObject @{ id = 'a'; originSystem = 'AadApplication' }).ResourceType | Should -Be 'Application'
            (ConvertTo-OERCatalogResource -InputObject @{ id = 's'; originSystem = 'SharePointOnline' }).ResourceType | Should -Be 'SharePoint Online Site'
        }
    }

    It 'prefers the Graph resourceType over the originSystem fallback when present' {
        InModuleScope $script:moduleName {
            $Out = ConvertTo-OERCatalogResource -InputObject @{ id = 'g'; resourceType = 'Microsoft 365 Group'; originSystem = 'AadGroup' }
            $Out.ResourceType | Should -Be 'Microsoft 365 Group'
        }
    }

    It 'falls back to the raw originSystem for an unknown origin when resourceType is empty' {
        InModuleScope $script:moduleName {
            $Out = ConvertTo-OERCatalogResource -InputObject @{ id = 'x'; originSystem = 'SomeFutureSystem' }
            $Out.ResourceType | Should -Be 'SomeFutureSystem'
        }
    }

    It 'accepts pipeline input and emits one object per item' {
        InModuleScope $script:moduleName {
            $Items = @(
                @{ id = 'r1'; displayName = 'A'; resourceType = 'Security Group'; originId = 'o1'; originSystem = 'AadGroup' },
                @{ id = 'r2'; displayName = 'B'; resourceType = 'Application';    originId = 'o2'; originSystem = 'AadApplication' }
            )
            $Results = $Items | ConvertTo-OERCatalogResource
            $Results.Count | Should -Be 2
            $Results[0].Id | Should -Be 'r1'
            $Results[1].Id | Should -Be 'r2'
            $Results[0].PSObject.TypeNames[0] | Should -Be 'Omnicit.EntraRBAC.CatalogResource'
            $Results[1].PSObject.TypeNames[0] | Should -Be 'Omnicit.EntraRBAC.CatalogResource'
        }
    }

    It 'maps attached roles into a Roles array' {
        InModuleScope $script:moduleName {
            $Raw = @{ id = 'res-1'; displayName = 'G'; originSystem = 'AadGroup'; roles = @(@{ displayName = 'Owner'; id = 'r1'; originId = 'Owner_g' }) }
            $Out = ConvertTo-OERCatalogResource -InputObject $Raw
            $Out.Roles[0].DisplayName | Should -Be 'Owner'
        }
    }

    It 'leaves Roles null when no roles are attached' {
        InModuleScope $script:moduleName {
            $Out = ConvertTo-OERCatalogResource -InputObject @{ id = 'res-1'; displayName = 'G'; originSystem = 'AadGroup' }
            $Out.Roles | Should -BeNullOrEmpty
        }
    }

    It 'stamps CatalogId onto the emitted object when the caller supplies it' {
        InModuleScope $script:moduleName {
            $Out = ConvertTo-OERCatalogResource -InputObject @{ id = 'res-1'; originSystem = 'AadGroup' } -CatalogId 'cat-77'
            $Out.CatalogId | Should -Be 'cat-77'
        }
    }

    It 'leaves CatalogId null when the caller does not supply it' {
        InModuleScope $script:moduleName {
            # Prove the object is real before measuring it: $null.CatalogId is also $null, so a bare
            # BeNullOrEmpty would pass just as happily on nothing at all.
            $Out = ConvertTo-OERCatalogResource -InputObject @{ id = 'res-1'; originSystem = 'AadGroup' }
            $Out | Should -Not -BeNullOrEmpty
            $Out.PSObject.Properties.Name | Should -Contain 'CatalogId'
            $Out.CatalogId | Should -BeNullOrEmpty
        }
    }
}
