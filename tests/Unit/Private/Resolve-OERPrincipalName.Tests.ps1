# tests/Unit/Private/Resolve-OERPrincipalName.Tests.ps1
BeforeAll {
    $script:moduleName = 'Omnicit.EntraRBAC'
    Get-Module $script:moduleName | Remove-Module -Force -ErrorAction SilentlyContinue
    Import-Module $script:moduleName -Force -ErrorAction Stop
    . "$PSScriptRoot/../TestHelpers/OERTransportTripwire.ps1"
    Install-OERTransportTripwire
}

AfterAll {
    try { Assert-OERTransportTripwire } finally { Uninstall-OERTransportTripwire }
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

    Context '-Detailed (Sprint 11 step 6, BL-133, A18)' {
        # The export's role assignment principals need to tell three answers apart: a principal the
        # directory returned, one a successful lookup did not return, and one whose lookup failed. The
        # default map cannot: it falls back to the id for both of the last two. -Detailed answers one
        # object per id instead, and a failed batch is reported, never swallowed.
        It 'answers one object per distinct id, in input order: a found user by UPN, a found group by display name, and an id the batch did not return' {
            InModuleScope $script:moduleName {
                Mock Invoke-OERGraphRequest {
                    @{ value = @(
                            @{ id = 'g-1'; '@odata.type' = '#microsoft.graph.group'; displayName = 'Sales Team' },
                            @{ id = 'u-1'; '@odata.type' = '#microsoft.graph.user'; userPrincipalName = 'anna@contoso.com'; displayName = 'Anna' }
                        ) }
                }
                $Result = @(Resolve-OERPrincipalName -Id @('u-1', 'g-1', 'gone-1', 'u-1', ' ') -Detailed)
                $Result.Count | Should -Be 3
                @($Result[0].PSObject.Properties.Name) | Should -Be @('Id', 'Read', 'Found', 'Name', 'ObjectType', 'Cause')
                @($Result | ForEach-Object { "$($_.Id)|$($_.Read)|$($_.Found)|$($_.Name)|$($_.ObjectType)|$($_.Cause)" }) | Should -Be @(
                    'u-1|True|True|anna@contoso.com|user|'
                    'g-1|True|True|Sales Team|group|'
                    'gone-1|True|False|||'
                )
                Should -Invoke Invoke-OERGraphRequest -Times 1 -Exactly
            }
        }

        It 'names a found object with no user principal name by its display name, and one with neither by its id' {
            InModuleScope $script:moduleName {
                Mock Invoke-OERGraphRequest {
                    @{ value = @(
                            @{ id = 'dev-1'; '@odata.type' = '#microsoft.graph.device'; displayName = 'Kiosk 7' },
                            @{ id = 'odd-1'; '@odata.type' = '#microsoft.graph.servicePrincipal' }
                        ) }
                }
                $Result = @(Resolve-OERPrincipalName -Id @('dev-1', 'odd-1') -Detailed)
                @($Result | ForEach-Object { "$($_.Id)|$($_.Found)|$($_.Name)|$($_.ObjectType)" }) | Should -Be @(
                    'dev-1|True|Kiosk 7|device'
                    'odd-1|True|odd-1|servicePrincipal'
                )
            }
        }

        It 'omits the types filter, so every directory object type is searched' {
            InModuleScope $script:moduleName {
                Mock Invoke-OERGraphRequest { @{ value = @() } }
                $null = Resolve-OERPrincipalName -Id @('dev-1') -Detailed
                Should -Invoke Invoke-OERGraphRequest -Times 1 -Exactly -ParameterFilter {
                    $Method -eq 'POST' -and $Uri -eq 'v1.0/directoryObjects/getByIds' -and
                    -not $Body.ContainsKey('types') -and @($Body.ids) -contains 'dev-1'
                }
            }
        }

        It 'answers every id of a failed batch as not read, with the cause, scrubs the record first, and never throws' {
            # Two batches: the first fails, the second answers. Only the first batch's ids are unread.
            InModuleScope $script:moduleName {
                $script:DetailedCall = 0
                Mock Invoke-OERGraphRequest {
                    $script:DetailedCall++
                    if ($script:DetailedCall -eq 1) { throw 'Too many requests (429)' }
                    @{ value = @(@{ id = 'id-1001'; '@odata.type' = '#microsoft.graph.user'; userPrincipalName = 'person1@example.com' }) }
                }
                Mock Remove-OERErrorRecord { }
                $Ids = 1..1001 | ForEach-Object { "id-$_" }
                $Errors = $null
                $Result = @(Resolve-OERPrincipalName -Id $Ids -Detailed -ErrorVariable Errors)
                $Result.Count | Should -Be 1001
                @($Result | Select-Object -First 1000 | Where-Object { $_.Read -eq $false -and $_.Found -eq $false -and $_.Cause -ceq 'Too many requests (429)' }).Count | Should -Be 1000
                "$($Result[1000].Id)|$($Result[1000].Read)|$($Result[1000].Found)|$($Result[1000].Name)|$($Result[1000].Cause)" | Should -Be 'id-1001|True|True|person1@example.com|'
                Should -Invoke Remove-OERErrorRecord -Times 1 -Exactly
                Should -Invoke Invoke-OERGraphRequest -Times 2 -Exactly
                # -ErrorVariable also collects the stray the failed batch raised inside the call (the
                # engine fills it before any catch runs); the helper itself publishes none.
                @($Errors | Where-Object { @(([string]$_.FullyQualifiedErrorId) -split ',') -contains 'Resolve-OERPrincipalName' }).Count | Should -Be 0
            }
        }

        It 'answers every id of a batch whose answer carries no value as not read, with the cause (<Case>)' -ForEach @(
            @{ Case = 'an empty answer'; NoValueKey = $false }
            @{ Case = 'an answer with no value'; NoValueKey = $true }
        ) {
            # Fix round 1 (F5): an answer with no value says nothing about the ids, so none of them is read
            # as one the directory did not return. The default map is left exactly as it was.
            InModuleScope $script:moduleName -Parameters @{ NoValueKey = $NoValueKey } {
                param($NoValueKey)
                if ($NoValueKey) { Mock Invoke-OERGraphRequest { @{ '@odata.context' = 'https://graph.microsoft.com/v1.0/$metadata#directoryObjects' } } }
                else { Mock Invoke-OERGraphRequest { } }
                $Result = @(Resolve-OERPrincipalName -Id @('u-1', 'g-1') -Detailed)
                @($Result | ForEach-Object { "$($_.Id)|$($_.Read)|$($_.Found)|$($_.Name)|$($_.Cause)" }) | Should -Be @(
                    'u-1|False|False||Microsoft Graph returned no value for directoryObjects/getByIds.'
                    'g-1|False|False||Microsoft Graph returned no value for directoryObjects/getByIds.'
                )
                $Map = Resolve-OERPrincipalName -Id @('u-1')
                $Map['u-1'] | Should -Be 'u-1'
            }
        }

        It 'answers an id of a batch whose value is empty as read and not found' {
            InModuleScope $script:moduleName {
                Mock Invoke-OERGraphRequest { @{ value = @() } }
                $Result = @(Resolve-OERPrincipalName -Id @('gone-1') -Detailed)
                "$($Result[0].Read)|$($Result[0].Found)|$($Result[0].Cause)" | Should -Be 'True|False|'
            }
        }

        It 'returns nothing and makes no call for an empty input' {
            InModuleScope $script:moduleName {
                Mock Invoke-OERGraphRequest { @{ value = @() } }
                @(Resolve-OERPrincipalName -Id @() -Detailed).Count | Should -Be 0
                Should -Invoke Invoke-OERGraphRequest -Times 0
            }
        }

        It 'refuses -Detailed together with -PreferDisplayName at binding, before any request' {
            InModuleScope $script:moduleName {
                Mock Invoke-OERGraphRequest { @{ value = @() } }
                { Resolve-OERPrincipalName -Id @('u-1') -Detailed -PreferDisplayName } | Should -Throw -ErrorId 'AmbiguousParameterSet,Resolve-OERPrincipalName'
                Should -Invoke Invoke-OERGraphRequest -Times 0
            }
        }

        It 'leaves the default map exactly as it was: no -Detailed, the same map for a found, a missing and a failed lookup' {
            InModuleScope $script:moduleName {
                Mock Invoke-OERGraphRequest {
                    @{ value = @(@{ id = 'u-1'; '@odata.type' = '#microsoft.graph.user'; userPrincipalName = 'anna@contoso.com' }) }
                }
                $Map = Resolve-OERPrincipalName -Id @('u-1', 'gone-1')
                $Map | Should -BeOfType ([hashtable])
                $Map['u-1'] | Should -Be 'anna@contoso.com'
                $Map['gone-1'] | Should -Be 'gone-1'
            }
        }
    }
}
