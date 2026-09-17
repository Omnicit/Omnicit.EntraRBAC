BeforeAll {
    $script:moduleName = 'Omnicit.EntraRBAC'
    Get-Module $script:moduleName | Remove-Module -Force -ErrorAction SilentlyContinue
    Import-Module $script:moduleName -Force -ErrorAction Stop
}

Describe 'Resolve-OERCatalogResource' {
    It 'returns the matching resource by originId' {
        InModuleScope $script:moduleName {
            Mock Invoke-OERGraphRequest {
                @{ value = @(
                    @{ id = 'res-1'; originId = 'grp-a'; displayName = 'A' },
                    @{ id = 'res-2'; originId = 'grp-b'; displayName = 'B' }
                ) }
            }
            $R = Resolve-OERCatalogResource -CatalogId 'cat-1' -OriginId 'grp-b'
            $R.id | Should -Be 'res-2'
            Should -Invoke Invoke-OERGraphRequest -Times 1 -ParameterFilter { $Uri -like '*catalogs/cat-1/resources' }
        }
    }

    It 'returns $null when no resource matches' {
        InModuleScope $script:moduleName {
            Mock Invoke-OERGraphRequest { @{ value = @() } }
            Resolve-OERCatalogResource -CatalogId 'cat-1' -OriginId 'nope' | Should -BeNullOrEmpty
        }
    }

    It 'reads roles via Get-OERCatalogResourceRole and attaches them when -IncludeRoles is set' {
        InModuleScope $script:moduleName {
            # The resources list call.
            Mock Invoke-OERGraphRequest {
                @{ value = @(@{ id = 'res-3'; originId = 'grp-c'; originSystem = 'AadGroup' }) }
            } -ParameterFilter { $Uri -like '*catalogs/cat-1/resources' }
            # Mock the shared helper that now owns the resourceRoles read.
            Mock Get-OERCatalogResourceRole {
                @(
                    @{ displayName = 'Member'; originId = 'Member_x'; originSystem = 'AadGroup' },
                    @{ displayName = 'Owner';  originId = 'Owner_x';  originSystem = 'AadGroup' }
                )
            }

            $R = Resolve-OERCatalogResource -CatalogId 'cat-1' -OriginId 'grp-c' -IncludeRoles
            $R.id | Should -Be 'res-3'
            @($R.roles).displayName | Should -Contain 'Member'
            Should -Invoke Get-OERCatalogResourceRole -Times 1 -ParameterFilter {
                $CatalogId -eq 'cat-1' -and $OriginSystem -eq 'AadGroup' -and $ResourceId -eq 'res-3'
            }
        }
    }

    It 'does not call Get-OERCatalogResourceRole when -IncludeRoles is not set' {
        InModuleScope $script:moduleName {
            # Return a resource whose originId MATCHES so $Match is non-null and the
            # if ($IncludeRoles) branch is actually evaluated (not skipped due to early return).
            Mock Invoke-OERGraphRequest {
                @{ value = @(@{ id = 'res-4'; originId = 'x'; originSystem = 'AadGroup' }) }
            }
            Mock Get-OERCatalogResourceRole {}
            Resolve-OERCatalogResource -CatalogId 'cat-1' -OriginId 'x' | Out-Null
            Should -Invoke Get-OERCatalogResourceRole -Times 0
        }
    }

    It 'finds a resource that only exists on the second page' {
        InModuleScope $script:moduleName {
            # The un-paged mock returns only page 1 (grp-a), so today (without -All) a resource
            # that only exists on page 2 (grp-b) is never seen and the function returns $null.
            Mock Invoke-OERGraphRequest -ParameterFilter { $Uri -like '*catalogs/cat-1/resources' -and $All } -MockWith {
                @{ value = @(
                    @{ id = 'res-1'; originId = 'grp-a'; displayName = 'A' },
                    @{ id = 'res-2'; originId = 'grp-b'; displayName = 'B' }
                ) }
            }
            Mock Invoke-OERGraphRequest -ParameterFilter { $Uri -like '*catalogs/cat-1/resources' -and -not $All } -MockWith {
                @{ value = @(@{ id = 'res-1'; originId = 'grp-a'; displayName = 'A' }) }
            }
            $R = Resolve-OERCatalogResource -CatalogId 'cat-1' -OriginId 'grp-b'
            $R.id | Should -Be 'res-2'
        }
    }
}
