# tests/Unit/Private/Resolve-OERPrincipalName.Tests.ps1
BeforeAll {
    $script:moduleName = 'Omnicit.EntraRBAC'
    Get-Module $script:moduleName | Remove-Module -Force -ErrorAction SilentlyContinue
    Import-Module $script:moduleName -Force -ErrorAction Stop
}

Describe 'Resolve-OERPrincipalName' {
    It 'maps user ids to UPN and group ids to displayName' {
        InModuleScope $script:moduleName {
            Mock Invoke-OERGraphRequest {
                @{ value = @(
                    @{ id = 'u-1'; userPrincipalName = 'anna@contoso.com'; displayName = 'Anna' },
                    @{ id = 'g-1'; displayName = 'Sales Team' }
                ) }
            }
            $Map = Resolve-OERPrincipalName -Id @('u-1', 'g-1')
            $Map['u-1'] | Should -Be 'anna@contoso.com'
            $Map['g-1'] | Should -Be 'Sales Team'
        }
    }

    It 'posts to getByIds with the user/group/servicePrincipal types' {
        InModuleScope $script:moduleName {
            Mock Invoke-OERGraphRequest { @{ value = @() } }
            Resolve-OERPrincipalName -Id @('u-1') | Out-Null
            Should -Invoke Invoke-OERGraphRequest -Times 1 -ParameterFilter {
                $Method -eq 'POST' -and
                $Uri -eq 'v1.0/directoryObjects/getByIds' -and
                ($Body.ids -contains 'u-1') -and ($Body.types -contains 'servicePrincipal')
            }
        }
    }

    It 'falls back to the GUID for an unresolvable id and never throws' {
        InModuleScope $script:moduleName {
            Mock Invoke-OERGraphRequest { @{ value = @() } }
            $Map = Resolve-OERPrincipalName -Id @('missing-1')
            $Map['missing-1'] | Should -Be 'missing-1'
        }
    }

    It 'returns an empty map for empty input without calling Graph' {
        InModuleScope $script:moduleName {
            Mock Invoke-OERGraphRequest { @{ value = @() } }
            $Map = Resolve-OERPrincipalName -Id @()
            @($Map.Keys).Count | Should -Be 0
            Should -Invoke Invoke-OERGraphRequest -Times 0
        }
    }

    It 'swallows a Graph failure and falls back to GUIDs' {
        InModuleScope $script:moduleName {
            Mock Invoke-OERGraphRequest { throw 'graph 500' }
            $Map = Resolve-OERPrincipalName -Id @('u-1')
            $Map['u-1'] | Should -Be 'u-1'
        }
    }

    It 'batches more than 1000 ids into multiple getByIds calls' {
        InModuleScope $script:moduleName {
            Mock Invoke-OERGraphRequest { @{ value = @() } }
            $Ids = 1..1500 | ForEach-Object { "id-$_" }
            Resolve-OERPrincipalName -Id $Ids | Out-Null
            Should -Invoke Invoke-OERGraphRequest -Times 2 -Exactly
        }
    }

    It 'scrubs the bearer-hygiene record when the getByIds request fails' {
        InModuleScope $script:moduleName {
            Mock Invoke-OERGraphRequest { throw 'transport failure' }
            Mock Remove-OERErrorRecord { }
            $null = Resolve-OERPrincipalName -Id @('u-1')
            Should -Invoke Remove-OERErrorRecord -Times 1
        }
    }

    It 'resolves a user id to displayName, not UPN, with -PreferDisplayName' {
        InModuleScope $script:moduleName {
            Mock Invoke-OERGraphRequest {
                @{ value = @(
                    @{ id = 'u-1'; userPrincipalName = 'anna@contoso.com'; displayName = 'Anna Berg' }
                ) }
            }
            $Map = Resolve-OERPrincipalName -Id @('u-1') -PreferDisplayName
            $Map['u-1'] | Should -Be 'Anna Berg'
            $Map['u-1'] | Should -Not -Be 'anna@contoso.com'
        }
    }

    It 'falls back to the id, never the UPN, with -PreferDisplayName when displayName is absent' {
        InModuleScope $script:moduleName {
            Mock Invoke-OERGraphRequest {
                @{ value = @(
                    @{ id = 'u-1'; userPrincipalName = 'anna@contoso.com' }
                ) }
            }
            $Map = Resolve-OERPrincipalName -Id @('u-1') -PreferDisplayName
            $Map['u-1'] | Should -Be 'u-1'
        }
    }

    It 'still prefers UPN for a user when -PreferDisplayName is not supplied (default unchanged)' {
        InModuleScope $script:moduleName {
            Mock Invoke-OERGraphRequest {
                @{ value = @(
                    @{ id = 'u-1'; userPrincipalName = 'anna@contoso.com'; displayName = 'Anna Berg' }
                ) }
            }
            $Map = Resolve-OERPrincipalName -Id @('u-1')
            $Map['u-1'] | Should -Be 'anna@contoso.com'
        }
    }

    It 'omits the types filter with -PreferDisplayName so every directory object type resolves (M-1)' {
        # The default path restricts the getByIds search to user/group/servicePrincipal, which is
        # correct for Get-OERInventory's UPN lookup but would silently exclude device and
        # foreignGroup principals -- types an Azure role assignment can legitimately carry. The
        # per-principal GET this batching replaced had no such restriction, so -PreferDisplayName
        # must omit 'types' entirely: per Microsoft Learn (directoryObject: getByIds), an omitted
        # 'types' defaults to the full directoryObject set, not a narrower one.
        InModuleScope $script:moduleName {
            Mock Invoke-OERGraphRequest { @{ value = @() } }
            Resolve-OERPrincipalName -Id @('dev-1') -PreferDisplayName | Out-Null
            Should -Invoke Invoke-OERGraphRequest -Times 1 -Exactly -ParameterFilter {
                $Method -eq 'POST' -and $Uri -eq 'v1.0/directoryObjects/getByIds' -and
                -not $Body.ContainsKey('types')
            }
        }
    }

    It 'still restricts to user/group/servicePrincipal without -PreferDisplayName (default unchanged)' {
        InModuleScope $script:moduleName {
            Mock Invoke-OERGraphRequest { @{ value = @() } }
            Resolve-OERPrincipalName -Id @('u-1') | Out-Null
            Should -Invoke Invoke-OERGraphRequest -Times 1 -Exactly -ParameterFilter {
                $Body.ContainsKey('types') -and ($Body.types -contains 'servicePrincipal')
            }
        }
    }
}
