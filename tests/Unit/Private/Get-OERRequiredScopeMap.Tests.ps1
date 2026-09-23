BeforeAll {
    Import-Module Omnicit.EntraRBAC -Force
}

Describe 'Get-OERRequiredScopeMap' {
    Context 'Table shape' {
        It 'Returns one entry per exported cmdlet, and no orphans' {
            InModuleScope Omnicit.EntraRBAC {
                $Exported = @((Get-Module Omnicit.EntraRBAC).ExportedFunctions.Keys)
                $Names = @((Get-OERRequiredScopeMap).Cmdlet)

                $Missing = @($Exported | Where-Object { $_ -notin $Names })
                $Missing | Should -BeNullOrEmpty -Because (
                    'every exported cmdlet needs a scope entry; missing: {0}' -f ($Missing -join ', '))

                $Orphan = @($Names | Where-Object { $_ -notin $Exported })
                $Orphan | Should -BeNullOrEmpty -Because (
                    'the table must not name a cmdlet that is not exported; orphans: {0}' -f ($Orphan -join ', '))
            }
        }

        It 'Names each cmdlet exactly once' {
            InModuleScope Omnicit.EntraRBAC {
                $Duplicate = @(Get-OERRequiredScopeMap | Group-Object Cmdlet | Where-Object Count -GT 1)

                $Duplicate | Should -BeNullOrEmpty -Because (
                    'a duplicated entry makes the union ambiguous; duplicated: {0}' -f ($Duplicate.Name -join ', '))
            }
        }

        It 'Exposes every documented property on every entry' {
            InModuleScope Omnicit.EntraRBAC {
                foreach ($Entry in Get-OERRequiredScopeMap) {
                    foreach ($Property in 'Cmdlet', 'Transport', 'GraphScope', 'AzureRole', 'Verified', 'Note') {
                        $Entry.PSObject.Properties.Name |
                            Should -Contain $Property -Because ('{0} must expose {1}' -f $Entry.Cmdlet, $Property)
                    }
                }
            }
        }

        It 'Types the two permission collections as string arrays, never a bare null' {
            InModuleScope Omnicit.EntraRBAC {
                <#
                    @($null).Count is 1 in PowerShell, so a row that omits the key must still produce
                    a genuinely EMPTY array rather than a one-element array holding $null.
                #>
                foreach ($Entry in Get-OERRequiredScopeMap) {
                    # Comma-wrap: piping an array to Should -BeOfType unrolls it and tests an element.
                    , $Entry.GraphScope | Should -BeOfType [string[]] -Because $Entry.Cmdlet
                    , $Entry.AzureRole | Should -BeOfType [string[]] -Because $Entry.Cmdlet

                    @($Entry.GraphScope | Where-Object { $null -eq $_ }).Count |
                        Should -Be 0 -Because ('{0} must not carry a null permission' -f $Entry.Cmdlet)
                    @($Entry.AzureRole | Where-Object { $null -eq $_ }).Count |
                        Should -Be 0 -Because ('{0} must not carry a null role' -f $Entry.Cmdlet)
                }
            }
        }
    }

    Context 'Transport contract' {
        It 'Uses only the four defined transport values' {
            InModuleScope Omnicit.EntraRBAC {
                $Bad = @(Get-OERRequiredScopeMap |
                        Where-Object { $_.Transport -notin 'Graph', 'Arm', 'GraphAndArm', 'None' })

                $Bad | Should -BeNullOrEmpty -Because (
                    'Transport is a closed set; offenders: {0}' -f ($Bad.Cmdlet -join ', '))
            }
        }

        It 'Declares a Graph permission exactly when the transport reaches Graph' {
            InModuleScope Omnicit.EntraRBAC {
                foreach ($Entry in Get-OERRequiredScopeMap) {
                    if ($Entry.Transport -in 'Graph', 'GraphAndArm') {
                        $Entry.GraphScope.Count | Should -BeGreaterThan 0 -Because (
                            '{0} reaches Graph so it must name at least one permission' -f $Entry.Cmdlet)
                    } else {
                        $Entry.GraphScope.Count | Should -Be 0 -Because (
                            '{0} does not reach Graph so it must name no permission' -f $Entry.Cmdlet)
                    }
                }
            }
        }

        It 'Explains itself whenever an ARM cmdlet names no Azure role' {
            InModuleScope Omnicit.EntraRBAC {
                <#
                    An empty AzureRole on an ARM cmdlet is legitimate -- self-activation acts on the
                    caller's own eligibility -- but it must never be indistinguishable from an entry
                    nobody filled in.
                #>
                $Silent = @(Get-OERRequiredScopeMap | Where-Object {
                        $_.Transport -in 'Arm', 'GraphAndArm' -and
                        -not $_.AzureRole.Count -and
                        [string]::IsNullOrWhiteSpace($_.Note)
                    })

                $Silent | Should -BeNullOrEmpty -Because (
                    'an ARM cmdlet with no Azure role must say why in Note; offenders: {0}' -f ($Silent.Cmdlet -join ', '))
            }
        }

        It 'Names no permission at all for an offline cmdlet' {
            InModuleScope Omnicit.EntraRBAC {
                foreach ($Entry in Get-OERRequiredScopeMap | Where-Object Transport -EQ 'None') {
                    $Entry.GraphScope.Count | Should -Be 0 -Because $Entry.Cmdlet
                    $Entry.AzureRole.Count | Should -Be 0 -Because $Entry.Cmdlet
                    $Entry.Note | Should -Not -BeNullOrEmpty -Because (
                        '{0} touches no tenant, and the table must say so rather than look blank' -f $Entry.Cmdlet)
                }
            }
        }
    }

    Context 'Verification bookkeeping' {
        It 'Marks Verified as a boolean on every entry' {
            InModuleScope Omnicit.EntraRBAC {
                foreach ($Entry in Get-OERRequiredScopeMap) {
                    $Entry.Verified | Should -BeOfType [bool] -Because $Entry.Cmdlet
                }
            }
        }

        It 'Requires an unverified entry to explain why' {
            InModuleScope Omnicit.EntraRBAC {
                $Unexplained = @(Get-OERRequiredScopeMap |
                        Where-Object { -not $_.Verified -and [string]::IsNullOrWhiteSpace($_.Note) })

                $Unexplained | Should -BeNullOrEmpty -Because (
                    'an entry not confirmed against Microsoft Learn must say so in Note rather than look authoritative; offenders: {0}' -f (
                        $Unexplained.Cmdlet -join ', '))
            }
        }
    }

    Context 'Permission value hygiene' {
        It 'Sorts and deduplicates the permissions on every entry' {
            InModuleScope Omnicit.EntraRBAC {
                foreach ($Entry in Get-OERRequiredScopeMap) {
                    $Sorted = @($Entry.GraphScope | Sort-Object -Unique)
                    ($Entry.GraphScope -join '|') | Should -Be ($Sorted -join '|') -Because (
                        '{0} permissions must be sorted and free of duplicates' -f $Entry.Cmdlet)
                }
            }
        }

        It 'Never lists a read permission alongside its own write permission' {
            InModuleScope Omnicit.EntraRBAC {
                <#
                    Group.ReadWrite.All already implies Group.Read.All. Listing both inflates the
                    consent request an administrator is asked to approve.
                #>
                foreach ($Entry in Get-OERRequiredScopeMap) {
                    foreach ($Scope in $Entry.GraphScope) {
                        if ($Scope -match '\.Read(Basic)?\.') {
                            $Write = $Scope -replace '\.Read(Basic)?\.', '.ReadWrite.'
                            $Entry.GraphScope | Should -Not -Contain $Write -Because (
                                '{0} lists {1} which already covers {2}' -f $Entry.Cmdlet, $Write, $Scope)
                        }
                    }
                }
            }
        }

        It 'Never lists a permission that a broader declared permission already covers' {
            InModuleScope Omnicit.EntraRBAC {
                <#
                    Directory.Read.All is the umbrella over the directory reads, and several entries
                    have to declare it outright because directoryObjects/getByIds accepts nothing
                    narrower. Listing the covered permissions as well inflates the consent request an
                    administrator is asked to approve, which is a real defect in a module whose
                    stated principle is least privilege -- Get-OERRoleAssignment asked for four
                    permissions where one sufficed before this guard existed.
                #>
                $Covers = @{
                    'Directory.Read.All'      = @('User.ReadBasic.All', 'User.Read.All', 'Group.Read.All',
                        'GroupMember.Read.All', 'Application.Read.All')
                    'Directory.ReadWrite.All' = @('User.ReadBasic.All', 'User.Read.All', 'User.ReadWrite.All',
                        'Group.Read.All', 'Group.ReadWrite.All', 'GroupMember.Read.All',
                        'GroupMember.ReadWrite.All', 'Application.Read.All', 'Application.ReadWrite.All')
                }

                foreach ($Entry in Get-OERRequiredScopeMap) {
                    foreach ($Broad in $Entry.GraphScope) {
                        if (-not $Covers.ContainsKey($Broad)) { continue }

                        $Redundant = @($Entry.GraphScope | Where-Object { $_ -in $Covers[$Broad] })

                        $Redundant | Should -BeNullOrEmpty -Because (
                            '{0} declares {1}, which already covers {2}' -f $Entry.Cmdlet, $Broad, ($Redundant -join ', '))
                    }
                }
            }
        }

        It 'Uses only well-formed Graph permission names' {
            InModuleScope Omnicit.EntraRBAC {
                $Malformed = @(Get-OERRequiredScopeMap |
                        ForEach-Object { $_.GraphScope } |
                            Where-Object { $_ -notmatch '^[A-Za-z][A-Za-z0-9-]*(\.[A-Za-z][A-Za-z0-9]*){2}$' } |
                                Sort-Object -Unique)

                $Malformed | Should -BeNullOrEmpty -Because (
                    'a Graph permission is three dot-separated segments; malformed: {0}' -f ($Malformed -join ', '))
            }
        }

        It 'Uses only Azure built-in role display names the module already curates' {
            InModuleScope Omnicit.EntraRBAC {
                $Known = @(Get-OERCommonRoleName)
                $Unknown = @(Get-OERRequiredScopeMap |
                        ForEach-Object { $_.AzureRole } |
                            Where-Object { $_ -notin $Known } |
                                Sort-Object -Unique)

                $Unknown | Should -BeNullOrEmpty -Because (
                    'Get-OERCommonRoleName is the curated Azure role vocabulary; unknown: {0}' -f ($Unknown -join ', '))
            }
        }
    }

    Context 'Pinned entries' {
        It 'Lists the role-management scope Set-OERGroup needs for a role-assignable group' {
            InModuleScope Omnicit.EntraRBAC {
                <#
                    tests/QA/requiredscope.tests.ps1 only checks that the declared scopes COVER the
                    endpoints reached, so it cannot notice this scope going missing: PATCH v1.0/groups
                    is satisfied by Group.ReadWrite.All alone. Updating a role-assignable group needs
                    RoleManagement.ReadWrite.Directory as well, so the value is pinned here.
                #>
                $Entry = @(Get-OERRequiredScopeMap | Where-Object Cmdlet -EQ 'Set-OERGroup')

                $Entry.Count | Should -Be 1 -Because 'Set-OERGroup must have exactly one entry'
                $Entry[0].GraphScope | Should -Contain 'Group.ReadWrite.All'
                $Entry[0].GraphScope | Should -Contain 'RoleManagement.ReadWrite.Directory' -Because (
                    'Group.ReadWrite.All alone cannot update a role-assignable group')
                $Entry[0].Note | Should -Match 'role-assignable' -Because (
                    'the Note must say the extra scope is needed only for a role-assignable group')
                # The Update group permission table on Microsoft Learn does not list the extra scope;
                # it is derived from the role-assignable group guidance, so the entry is not marked as
                # confirmed against the per-API table.
                $Entry[0].Verified | Should -BeFalse -Because (
                    'the per-API table does not state the role-management scope, and the Note says where it comes from')
            }
        }
    }

    Context 'Purity' {
        It 'Makes no tenant call' {
            Mock -ModuleName Omnicit.EntraRBAC Initialize-OERAuth { throw 'must not authenticate' }
            Mock -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest { throw 'must not call Graph' }
            Mock -ModuleName Omnicit.EntraRBAC Invoke-OERArmRequest { throw 'must not call ARM' }

            InModuleScope Omnicit.EntraRBAC { { Get-OERRequiredScopeMap } | Should -Not -Throw }

            Should -Invoke -ModuleName Omnicit.EntraRBAC Initialize-OERAuth -Times 0
            Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest -Times 0
            Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-OERArmRequest -Times 0
        }
    }
}
