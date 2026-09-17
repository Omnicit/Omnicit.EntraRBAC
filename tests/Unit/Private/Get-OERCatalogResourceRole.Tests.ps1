BeforeAll {
    $script:moduleName = 'Omnicit.EntraRBAC'
    Get-Module $script:moduleName | Remove-Module -Force -ErrorAction SilentlyContinue
    Import-Module $script:moduleName -Force -ErrorAction Stop
}

Describe 'Get-OERCatalogResourceRole' {
    BeforeEach {
        InModuleScope $script:moduleName { $script:_OERAuthState = $null }
    }

    It 'reads roles from the resourceRoles endpoint with a literal OData filter' {
        InModuleScope $script:moduleName {
            Mock Invoke-OERGraphRequest { @{ value = @(@{ id = 'role-1'; displayName = 'Member'; originId = 'Member_grp' }) } }
            $Roles = Get-OERCatalogResourceRole -CatalogId 'cat-1' -OriginSystem 'AadGroup' -ResourceId 'res-1'
            $Roles[0].displayName | Should -Be 'Member'
            Should -Invoke Invoke-OERGraphRequest -Times 1 -ParameterFilter {
                $Uri -like "*catalogs/cat-1/resourceRoles*" -and
                $Uri -like "*originSystem eq 'AadGroup'*" -and
                $Uri -like "*resource/id eq 'res-1'*"
            }
        }
    }

    It 'returns an empty array when the endpoint returns no roles' {
        InModuleScope $script:moduleName {
            Mock Invoke-OERGraphRequest { @{ value = @() } }
            $Roles = Get-OERCatalogResourceRole -CatalogId 'cat-1' -OriginSystem 'AadGroup' -ResourceId 'res-99'
            $Roles | Should -BeNullOrEmpty
        }
    }

    It 'includes $expand=resource in the URI' {
        InModuleScope $script:moduleName {
            Mock Invoke-OERGraphRequest { @{ value = @() } }
            Get-OERCatalogResourceRole -CatalogId 'cat-2' -OriginSystem 'AadApplication' -ResourceId 'app-1' | Out-Null
            Should -Invoke Invoke-OERGraphRequest -Times 1 -ParameterFilter { $Uri -like '*expand=resource*' }
        }
    }

    Context 'paging (-All opt-in, Task 7 fix-round Minor 4 -- a filtered resourceRoles collection read the original Task 7 sweep missed)' {
        It 'passes -All to the resourceRoles read' {
            InModuleScope $script:moduleName {
                Mock Invoke-OERGraphRequest { @{ value = @(@{ id = 'role-1'; displayName = 'Member'; originId = 'Member_grp' }) } }
                Get-OERCatalogResourceRole -CatalogId 'cat-1' -OriginSystem 'AadGroup' -ResourceId 'res-1' | Out-Null
                Should -Invoke Invoke-OERGraphRequest -Times 1 -Exactly -ParameterFilter {
                    $Uri -eq "v1.0/identityGovernance/entitlementManagement/catalogs/cat-1/resourceRoles?`$filter=(originSystem eq 'AadGroup' and resource/id eq 'res-1')&`$expand=resource" -and $All
                }
            }
        }
    }
}
