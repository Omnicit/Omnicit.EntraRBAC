BeforeAll {
    $script:moduleName = 'Omnicit.EntraRBAC'
    Get-Module $script:moduleName | Remove-Module -Force -ErrorAction SilentlyContinue
    Import-Module $script:moduleName -Force -ErrorAction Stop
}

Describe 'Get-OERGroup' {
    BeforeEach {
        InModuleScope $script:moduleName { $script:_OERAuthState = $null }
        Mock -ModuleName $script:moduleName Initialize-OERAuth {}
    }

    It 'gets a group by id' {
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {
            @{ id = '22222222-2222-2222-2222-222222222222'; displayName = 'role_sec_team'; securityEnabled = $true; isAssignableToRole = $false; groupTypes = @() }
        } -ParameterFilter { $Uri -eq 'v1.0/groups/22222222-2222-2222-2222-222222222222' }
        $Result = Get-OERGroup -Id '22222222-2222-2222-2222-222222222222'
        $Result.Id | Should -Be '22222222-2222-2222-2222-222222222222'
        $Result.PSObject.TypeNames[0] | Should -Be 'Omnicit.EntraRBAC.Group'
    }

    It 'gets a group by display name via a filter query' {
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {
            @{ value = @(@{ id = 'gid-2'; displayName = 'role_sec_team'; securityEnabled = $true; isAssignableToRole = $false; groupTypes = @() }) }
        } -ParameterFilter { $Uri -match "displayName eq 'role_sec_team'" }
        (Get-OERGroup -DisplayName 'role_sec_team').Id | Should -Be 'gid-2'
    }

    It 'errors (non-terminating) when the named group is not found' {
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest { @{ value = @() } }
        Get-OERGroup -DisplayName 'missing' -ErrorVariable err -ErrorAction SilentlyContinue | Out-Null
        $err.FullyQualifiedErrorId | Should -Match 'GroupNotFound'
    }

    It 'scrubs the bearer-hygiene record when the group read fails' {
        # Drives the main read catch in source/Public/Get-OERGroup.ps1 (the try around the
        # ByGroup/ByFilter switch). CLAUDE.md SECURITY rule 6 makes Remove-OERErrorRecord -Record
        # $PSItem the mandatory FIRST statement of that catch. The end-to-end Describe at the bottom
        # of this file proves Invoke-OERGraphRequest's OWN scrub; it does NOT cover Get-OERGroup's
        # four catches, because the converted GraphError record no longer carries an
        # HttpRequestException type for its filter to match.
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest { throw 'transport failure' }
        Mock -ModuleName $script:moduleName Remove-OERErrorRecord { }
        Get-OERGroup -Group 'role_sec_team' -ErrorAction SilentlyContinue | Out-Null
        Should -Invoke -ModuleName $script:moduleName Remove-OERErrorRecord -Times 1
    }

    It 'includes members when -IncludeMembers is set' {
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {
            @{ id = '22222222-2222-2222-2222-222222222222'; displayName = 'role_sec_team'; securityEnabled = $true; isAssignableToRole = $false; groupTypes = @() }
        } -ParameterFilter { $Uri -eq 'v1.0/groups/22222222-2222-2222-2222-222222222222' }
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {
            @{ value = @(@{ id = 'm-1'; displayName = 'Alice' }) }
        } -ParameterFilter { $Uri -eq 'v1.0/groups/22222222-2222-2222-2222-222222222222/members' }
        $Result = Get-OERGroup -Id '22222222-2222-2222-2222-222222222222' -IncludeMembers
        $Result.Members.id | Should -Be 'm-1'
    }

    It 'returns tagged GroupMember objects for -IncludeMembers, not raw Graph dictionaries' {
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {
            @{ id = '22222222-2222-2222-2222-222222222222'; displayName = 'role_sec_team'; securityEnabled = $true; isAssignableToRole = $false; groupTypes = @() }
        } -ParameterFilter { $Uri -eq 'v1.0/groups/22222222-2222-2222-2222-222222222222' }
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {
            @{ value = @(
                    @{ '@odata.type' = '#microsoft.graph.user'; id = 'u1'; displayName = 'Ada'; userPrincipalName = 'ada@contoso.com' }
                    @{ '@odata.type' = '#microsoft.graph.group'; id = 'g2'; displayName = 'Nested' }
                ) }
        } -ParameterFilter { $Uri -eq 'v1.0/groups/22222222-2222-2222-2222-222222222222/members' }
        $Group = Get-OERGroup -Id '22222222-2222-2222-2222-222222222222' -IncludeMembers
        $Member = @($Group.Members)[0]
        $Member.PSObject.TypeNames[0] | Should -Be 'Omnicit.EntraRBAC.GroupMember'
        $Member.ObjectType | Should -Be 'user'
        $Member.MemberType | Should -Be 'Member'
        $Member.PrincipalId | Should -Be 'u1'
        $Member.GroupId | Should -Be $Group.Id
        @($Group.Members)[1].ObjectType | Should -Be 'group'
    }

    It 'keeps the raw Graph key spellings resolvable so the inventory projection is unaffected' {
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {
            @{ id = '22222222-2222-2222-2222-222222222222'; displayName = 'role_sec_team'; securityEnabled = $true; isAssignableToRole = $false; groupTypes = @() }
        } -ParameterFilter { $Uri -eq 'v1.0/groups/22222222-2222-2222-2222-222222222222' }
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {
            @{ value = @(@{ '@odata.type' = '#microsoft.graph.user'; id = 'u1'; displayName = 'Ada'; userPrincipalName = 'ada@contoso.com' }) }
        } -ParameterFilter { $Uri -eq 'v1.0/groups/22222222-2222-2222-2222-222222222222/members' }
        $Group = Get-OERGroup -Id '22222222-2222-2222-2222-222222222222' -IncludeMembers
        @($Group.Members)[0].userPrincipalName | Should -Be 'ada@contoso.com'
        @($Group.Members)[0].id | Should -Be 'u1'
    }

    It 'attaches Owners when -IncludeOwners is used' {
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {
            @{ id = '22222222-2222-2222-2222-222222222222'; displayName = 'role_sec_team'; securityEnabled = $true; isAssignableToRole = $false; groupTypes = @() }
        } -ParameterFilter { $Uri -eq 'v1.0/groups/22222222-2222-2222-2222-222222222222' }
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {
            @{ value = @(@{ '@odata.type' = '#microsoft.graph.user'; id = 'o-1'; displayName = 'Owner One'; userPrincipalName = 'owner1@contoso.com' }) }
        } -ParameterFilter { $Uri -eq 'v1.0/groups/22222222-2222-2222-2222-222222222222/owners' }
        $Result = Get-OERGroup -Id '22222222-2222-2222-2222-222222222222' -IncludeOwners
        @($Result.Owners).Count | Should -Be 1
        $Owner = @($Result.Owners)[0]
        $Owner.PSObject.TypeNames[0] | Should -Be 'Omnicit.EntraRBAC.GroupMember'
        $Owner.MemberType | Should -Be 'Owner'
        $Owner.PrincipalId | Should -Be 'o-1'
    }

    It 'does not read owners without -IncludeOwners' {
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {
            @{ id = '22222222-2222-2222-2222-222222222222'; displayName = 'role_sec_team'; securityEnabled = $true; isAssignableToRole = $false; groupTypes = @() }
        } -ParameterFilter { $Uri -eq 'v1.0/groups/22222222-2222-2222-2222-222222222222' }
        Get-OERGroup -Id '22222222-2222-2222-2222-222222222222' | Out-Null
        Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 0 -ParameterFilter {
            $Uri -match '/owners'
        }
    }

    It 'omits Owners and errors (not warns) when the owners read fails' {
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {
            @{ id = '22222222-2222-2222-2222-222222222222'; displayName = 'role_sec_team'; securityEnabled = $true; isAssignableToRole = $false; groupTypes = @() }
        } -ParameterFilter { $Uri -eq 'v1.0/groups/22222222-2222-2222-2222-222222222222' }
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {
            throw [System.Management.Automation.ErrorRecord]::new(
                [System.Exception]::new('TooManyRequests: throttled'),
                'TooManyRequests', [System.Management.Automation.ErrorCategory]::LimitsExceeded, $null)
        } -ParameterFilter { $Uri -eq 'v1.0/groups/22222222-2222-2222-2222-222222222222/owners' }
        $Result = Get-OERGroup -Id '22222222-2222-2222-2222-222222222222' -IncludeOwners -WarningVariable warned -WarningAction SilentlyContinue -ErrorVariable ReadErr -ErrorAction SilentlyContinue
        # Prove the cmdlet actually emitted the group object before trusting an absent-property
        # read on it -- a $null result also satisfies '-contains' -> $false, so that check alone
        # cannot tell "read the group and correctly omitted Owners" from "emitted nothing at all".
        $Result | Should -Not -BeNullOrEmpty
        $Result.Id | Should -Be '22222222-2222-2222-2222-222222222222'
        $Result.PSObject.Properties.Name -contains 'Owners' | Should -BeFalse
        $warned | Should -BeNullOrEmpty
        # -ErrorVariable also accumulates Pester's own internal mock-invocation bookkeeping noise
        # (see the bearer-hygiene Describe at the bottom of this file); restrict to the record
        # actually published through Get-OERGroup's own WriteError call.
        $Published = @($ReadErr) | Where-Object {
            $_.InvocationInfo -and $_.InvocationInfo.MyCommand -and $_.InvocationInfo.MyCommand.Name -eq 'Get-OERGroup'
        }
        @($Published)[0].FullyQualifiedErrorId | Should -Match 'GroupOwnerReadFailed'
    }

    It 'includes PIM eligibility when -IncludePimEligibility is set' {
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {
            @{ id = '22222222-2222-2222-2222-222222222222'; displayName = 'role_sec_team'; securityEnabled = $true; isAssignableToRole = $false; groupTypes = @() }
        } -ParameterFilter { $Uri -eq 'v1.0/groups/22222222-2222-2222-2222-222222222222' }
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {
            @{ value = @(@{ id = 'e-1'; principalId = 'p-1'; accessId = 'member' }) }
        } -ParameterFilter { $Uri -match 'eligibilityScheduleInstances' }
        $Result = Get-OERGroup -Id '22222222-2222-2222-2222-222222222222' -IncludePimEligibility
        $Result.PimEligibility.principalId | Should -Be 'p-1'
    }

    It 'does not warn when a group is not onboarded to PIM (ResourceTypeNotSupported)' {
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {
            @{ id = '22222222-2222-2222-2222-222222222222'; displayName = 'plain'; securityEnabled = $true; isAssignableToRole = $false; groupTypes = @() }
        } -ParameterFilter { $Uri -eq 'v1.0/groups/22222222-2222-2222-2222-222222222222' }
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {
            throw [System.Management.Automation.ErrorRecord]::new(
                [System.Exception]::new('ResourceTypeNotSupported: Resource type not supported for onboarding'),
                'ResourceTypeNotSupported', [System.Management.Automation.ErrorCategory]::OperationStopped, $null)
        } -ParameterFilter { $Uri -match 'eligibilityScheduleInstances' }
        $Result = Get-OERGroup -Id '22222222-2222-2222-2222-222222222222' -IncludePimEligibility -WarningVariable warned -WarningAction SilentlyContinue
        @($Result.PimEligibility).Count | Should -Be 0
        $warned | Should -BeNullOrEmpty
    }

    It 'errors (not warns) and omits PimEligibility when the read fails for a non-NotSupported reason' {
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {
            @{ id = '22222222-2222-2222-2222-222222222222'; displayName = 'plain'; securityEnabled = $true; isAssignableToRole = $false; groupTypes = @() }
        } -ParameterFilter { $Uri -eq 'v1.0/groups/22222222-2222-2222-2222-222222222222' }
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {
            throw [System.Management.Automation.ErrorRecord]::new(
                [System.Exception]::new('TooManyRequests: throttled'),
                'TooManyRequests', [System.Management.Automation.ErrorCategory]::LimitsExceeded, $null)
        } -ParameterFilter { $Uri -match 'eligibilityScheduleInstances' }
        $Result = Get-OERGroup -Id '22222222-2222-2222-2222-222222222222' -IncludePimEligibility -WarningVariable warned -WarningAction SilentlyContinue -ErrorVariable ReadErr -ErrorAction SilentlyContinue
        # Prove the cmdlet actually emitted the group object before trusting an absent-property
        # read on it -- a $null result also satisfies '-contains' -> $false, so that check alone
        # cannot tell "read the group and correctly omitted PimEligibility" from "emitted nothing".
        $Result | Should -Not -BeNullOrEmpty
        $Result.Id | Should -Be '22222222-2222-2222-2222-222222222222'
        $warned | Should -BeNullOrEmpty
        $Result.PSObject.Properties.Name -contains 'PimEligibility' | Should -BeFalse
        # -ErrorVariable also accumulates Pester's own internal mock-invocation bookkeeping noise
        # (see the bearer-hygiene Describe at the bottom of this file); restrict to the record
        # actually published through Get-OERGroup's own WriteError call.
        $Published = @($ReadErr) | Where-Object {
            $_.InvocationInfo -and $_.InvocationInfo.MyCommand -and $_.InvocationInfo.MyCommand.Name -eq 'Get-OERGroup'
        }
        @($Published)[0].FullyQualifiedErrorId | Should -Match 'GroupPimEligibilityReadFailed'
    }

    It 'accepts pipeline input via GroupId alias (ValueFromPipelineByPropertyName)' {
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {
            @{ id = '33333333-3333-3333-3333-333333333333'; displayName = 'pipe-group'; securityEnabled = $true; isAssignableToRole = $false; groupTypes = @() }
        } -ParameterFilter { $Uri -eq 'v1.0/groups/33333333-3333-3333-3333-333333333333' }
        $Result = [pscustomobject]@{ GroupId = '33333333-3333-3333-3333-333333333333' } | Get-OERGroup
        $Result.Id | Should -Be '33333333-3333-3333-3333-333333333333'
    }

    It 'accepts pipeline input via Id property (ValueFromPipelineByPropertyName)' {
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {
            @{ id = '44444444-4444-4444-4444-444444444444'; displayName = 'pipe-group-2'; securityEnabled = $true; isAssignableToRole = $false; groupTypes = @() }
        } -ParameterFilter { $Uri -eq 'v1.0/groups/44444444-4444-4444-4444-444444444444' }
        $Result = [pscustomobject]@{ Id = '44444444-4444-4444-4444-444444444444' } | Get-OERGroup
        $Result.Id | Should -Be '44444444-4444-4444-4444-444444444444'
    }

    It 'accepts pipeline input via DisplayName (ValueFromPipelineByPropertyName)' {
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {
            @{ value = @(@{ id = 'gid-dn'; displayName = 'pipe-by-name'; securityEnabled = $true; isAssignableToRole = $false; groupTypes = @() }) }
        } -ParameterFilter { $Uri -match "displayName eq 'pipe-by-name'" }
        $Result = [pscustomobject]@{ DisplayName = 'pipe-by-name' } | Get-OERGroup
        $Result.Id | Should -Be 'gid-dn'
    }

    Context 'unified -Group target (audit PR6)' {
        It 'reads a group by GUID through -Group with a direct GET' {
            Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {
                @{ id = '11111111-1111-1111-1111-111111111111'; displayName = 'g'; securityEnabled = $true; isAssignableToRole = $false; groupTypes = @() }
            } -ParameterFilter { $Uri -eq 'v1.0/groups/11111111-1111-1111-1111-111111111111' }
            Get-OERGroup -Group '11111111-1111-1111-1111-111111111111' | Out-Null
            Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 1 -ParameterFilter {
                $Uri -eq 'v1.0/groups/11111111-1111-1111-1111-111111111111'
            }
        }
        It 'reads a group by display name through -Group with a filtered query' {
            Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {
                @{ value = @(@{ id = 'gid-x'; displayName = 'role_sec_identity_administrator'; securityEnabled = $true; isAssignableToRole = $false; groupTypes = @() }) }
            } -ParameterFilter { $Uri -like "*displayName eq 'role_sec_identity_administrator'*" }
            Get-OERGroup -Group 'role_sec_identity_administrator' | Out-Null
            Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 1 -ParameterFilter {
                $Uri -like "*`$filter=displayName eq 'role_sec_identity_administrator'*"
            }
        }
        It 'still binds the historical -Id parameter name' {
            Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {
                @{ id = '11111111-1111-1111-1111-111111111111'; displayName = 'g'; securityEnabled = $true; isAssignableToRole = $false; groupTypes = @() }
            } -ParameterFilter { $Uri -eq 'v1.0/groups/11111111-1111-1111-1111-111111111111' }
            Get-OERGroup -Id '11111111-1111-1111-1111-111111111111' | Out-Null
            Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 1 -ParameterFilter {
                $Uri -eq 'v1.0/groups/11111111-1111-1111-1111-111111111111'
            }
        }
        It 'still binds the historical -DisplayName parameter name' {
            Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {
                @{ value = @(@{ id = 'gid-x'; displayName = 'role_sec_identity_administrator'; securityEnabled = $true; isAssignableToRole = $false; groupTypes = @() }) }
            } -ParameterFilter { $Uri -like "*displayName eq 'role_sec_identity_administrator'*" }
            Get-OERGroup -DisplayName 'role_sec_identity_administrator' | Out-Null
            Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 1 -ParameterFilter {
                $Uri -like "*displayName eq 'role_sec_identity_administrator'*"
            }
        }
        It 'prefers the Id property when a piped object carries both Id and DisplayName' {
            Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {
                @{ id = '11111111-1111-1111-1111-111111111111'; displayName = 'role_sec_x'; securityEnabled = $true; isAssignableToRole = $false; groupTypes = @() }
            } -ParameterFilter { $Uri -eq 'v1.0/groups/11111111-1111-1111-1111-111111111111' }
            [PSCustomObject]@{ Id = '11111111-1111-1111-1111-111111111111'; DisplayName = 'role_sec_x' } | Get-OERGroup | Out-Null
            Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 1 -ParameterFilter {
                $Uri -eq 'v1.0/groups/11111111-1111-1111-1111-111111111111'
            }
        }
        It 'escapes a single quote in a display name' {
            Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {
                @{ value = @(@{ id = 'gid-y'; displayName = "O'Brien group"; securityEnabled = $true; isAssignableToRole = $false; groupTypes = @() }) }
            } -ParameterFilter { $Uri -match 'O%27%27Brien' }
            Get-OERGroup -Group "O'Brien group" | Out-Null
            Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 1 -ParameterFilter {
                # Doubled quote first (''), then percent-encoded ('' -> %27%27).
                $Uri -match 'O%27%27Brien'
            }
        }
        It 'percent-encodes a reserved character in a display name' {
            Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {
                @{ value = @(@{ id = 'gid-amp'; displayName = 'Sales & Marketing'; securityEnabled = $true; isAssignableToRole = $false; groupTypes = @() }) }
            } -ParameterFilter { $Uri -match 'Sales%20%26%20Marketing' }
            Get-OERGroup -Group 'Sales & Marketing' | Out-Null
            Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 1 -ParameterFilter {
                # '&' must be percent-encoded (%26), never sent as a bare query-string separator.
                $Uri -match 'Sales%20%26%20Marketing' -and $Uri -notmatch "Sales & Marketing"
            }
        }
        It 'keeps the -Filter parameter set working' {
            Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {
                @{ value = @(@{ id = 'gid-z'; displayName = 'role_sec_x'; securityEnabled = $true; isAssignableToRole = $false; groupTypes = @() }) }
            } -ParameterFilter { $Uri -like '*startswith*' }
            Get-OERGroup -Filter "startswith(displayName,'role_sec_')" | Out-Null
            Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 1 -ParameterFilter {
                $Uri -like '*startswith*'
            }
        }
    }

    Context 'the -All parameter set reads the tenant with no filter' {
        # The roster Export-OERInventory writes is the one file in the bundle that claims to list
        # every group, and it was built from 'securityEnabled eq true'. Measured against a real
        # tenant that claim was false by six groups out of 106 -- five Microsoft 365 groups with
        # securityEnabled false and one distribution group -- with nothing in the bundle saying so.
        # -All is what makes the claim true, so what it must NOT do is send a $filter.
        It 'sends an unfiltered, paged GET for -All' {
            Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {
                @{ value = @(
                        @{ id = 'g1'; displayName = 'SecurityOne'; securityEnabled = $true; isAssignableToRole = $false; groupTypes = @() }
                        @{ id = 'g2'; displayName = 'DistributionOne'; securityEnabled = $false; mailEnabled = $true; isAssignableToRole = $false; groupTypes = @() }
                    ) }
            }
            $Result = @(Get-OERGroup -All)
            $Result.Count | Should -Be 2
            Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 1 -Exactly -ParameterFilter {
                $Uri -eq 'v1.0/groups' -and $All
            }
            # Stated separately and negatively: a URI that merely "looks unfiltered" is not the
            # same claim as one carrying no $filter at all, and the second is the one that matters.
            Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 0 -Exactly -ParameterFilter {
                $Uri -like '*$filter*'
            }
        }

        It 'returns a group the securityEnabled filter would have excluded' {
            Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {
                @{ value = @(
                        @{ id = 'g2'; displayName = 'DistributionOne'; securityEnabled = $false; mailEnabled = $true; isAssignableToRole = $false; groupTypes = @() }
                    ) }
            }
            $Result = @(Get-OERGroup -All)
            $Result.Count | Should -Be 1
            $Result[0].DisplayName | Should -Be 'DistributionOne' -Because (
                'a roster read must carry the group types a security-enabled filter drops, since ' +
                'their absence from the result is otherwise indistinguishable from their absence ' +
                'from the tenant'
            )
            $Result[0].PSObject.TypeNames[0] | Should -Be 'Omnicit.EntraRBAC.Group'
        }

        It 'reports an empty tenant read as a non-terminating GroupNotFound naming the -All target' {
            Mock -ModuleName $script:moduleName Invoke-OERGraphRequest { @{ value = @() } }
            $Err = $null
            Get-OERGroup -All -ErrorAction SilentlyContinue -ErrorVariable Err | Out-Null
            @($Err).Count | Should -BeGreaterThan 0
            $Err[0].FullyQualifiedErrorId | Should -Match 'GroupNotFound'
            # The old target expression resolved to $Filter for every set that was not ByGroup,
            # so this message would have read "No group found for ''".
            [string]$Err[0].Exception.Message | Should -Match 'every group in the tenant'
        }
    }

    Context 'paging (-All opt-in, closes rt-graph-list-reads-first-page-only)' {
        It 'passes -All to the tenant-wide -Filter list read' {
            Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {
                @{ value = @(
                        @{ id = 'g1'; displayName = 'Group One'; securityEnabled = $true; isAssignableToRole = $false; groupTypes = @() }
                        @{ id = 'g2'; displayName = 'Group Two'; securityEnabled = $true; isAssignableToRole = $false; groupTypes = @() }
                    ) }
            }
            $Result = @(Get-OERGroup -Filter 'securityEnabled eq true')
            $Result.Count | Should -Be 2
            Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 1 -Exactly -ParameterFilter {
                $Uri -like '*v1.0/groups?*' -and $All
            }
        }

        It 'passes -All to the /members read for -IncludeMembers' {
            Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {
                @{ id = '22222222-2222-2222-2222-222222222222'; displayName = 'role_sec_team'; securityEnabled = $true; isAssignableToRole = $false; groupTypes = @() }
            } -ParameterFilter { $Uri -eq 'v1.0/groups/22222222-2222-2222-2222-222222222222' }
            Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {
                @{ value = @(@{ id = 'm-1'; displayName = 'Alice' }) }
            } -ParameterFilter { $Uri -eq 'v1.0/groups/22222222-2222-2222-2222-222222222222/members' }
            Get-OERGroup -Id '22222222-2222-2222-2222-222222222222' -IncludeMembers | Out-Null
            Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 1 -Exactly -ParameterFilter {
                $Uri -eq 'v1.0/groups/22222222-2222-2222-2222-222222222222/members' -and $All
            }
        }

        It 'passes -All to the /owners read for -IncludeOwners' {
            Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {
                @{ id = '22222222-2222-2222-2222-222222222222'; displayName = 'role_sec_team'; securityEnabled = $true; isAssignableToRole = $false; groupTypes = @() }
            } -ParameterFilter { $Uri -eq 'v1.0/groups/22222222-2222-2222-2222-222222222222' }
            Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {
                @{ value = @(@{ id = 'o-1'; displayName = 'Owner One' }) }
            } -ParameterFilter { $Uri -eq 'v1.0/groups/22222222-2222-2222-2222-222222222222/owners' }
            Get-OERGroup -Id '22222222-2222-2222-2222-222222222222' -IncludeOwners | Out-Null
            Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 1 -Exactly -ParameterFilter {
                $Uri -eq 'v1.0/groups/22222222-2222-2222-2222-222222222222/owners' -and $All
            }
        }

        It 'passes -All to the PIM eligibility instances read for -IncludePimEligibility' {
            Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {
                @{ id = '22222222-2222-2222-2222-222222222222'; displayName = 'role_sec_team'; securityEnabled = $true; isAssignableToRole = $false; groupTypes = @() }
            } -ParameterFilter { $Uri -eq 'v1.0/groups/22222222-2222-2222-2222-222222222222' }
            Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {
                @{ value = @(@{ id = 'e-1'; principalId = 'p-1'; accessId = 'member' }) }
            } -ParameterFilter { $Uri -match 'eligibilityScheduleInstances' }
            Get-OERGroup -Id '22222222-2222-2222-2222-222222222222' -IncludePimEligibility | Out-Null
            Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 1 -Exactly -ParameterFilter {
                $Uri -match 'eligibilityScheduleInstances' -and $All
            }
        }
    }

    Context 'a failed collection read is not an empty collection' {
        BeforeEach {
            Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {
                @{ id = 'aaaaaaaa-1111-1111-1111-111111111111'; displayName = 'role_sec_team'; securityEnabled = $true; isAssignableToRole = $false; groupTypes = @() }
            } -ParameterFilter { $Uri -eq 'v1.0/groups/aaaaaaaa-1111-1111-1111-111111111111' }
        }

        It 'carries a Members property holding an empty array when the group genuinely has no members' {
            Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {
                @{ value = @() }
            } -ParameterFilter { $Uri -eq 'v1.0/groups/aaaaaaaa-1111-1111-1111-111111111111/members' }

            $Group = Get-OERGroup -Id 'aaaaaaaa-1111-1111-1111-111111111111' -IncludeMembers
            $Group.PSObject.Properties.Name -contains 'Members' |
                Should -BeTrue -Because 'a successful read of an empty group is a fact the document may state'
            @($Group.Members).Count | Should -Be 0
        }

        It 'omits the Members property entirely when the member read fails' {
            Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {
                throw 'TooManyRequests'
            } -ParameterFilter { $Uri -eq 'v1.0/groups/aaaaaaaa-1111-1111-1111-111111111111/members' }

            $Group = Get-OERGroup -Id 'aaaaaaaa-1111-1111-1111-111111111111' -IncludeMembers -ErrorAction SilentlyContinue
            # Prove the cmdlet actually emitted the group object before trusting an absent-property
            # read on it -- a $null result also satisfies '-contains' -> $false, so that check alone
            # cannot tell "read the group and correctly omitted Members" from "emitted nothing".
            $Group | Should -Not -BeNullOrEmpty
            $Group.Id | Should -Be 'aaaaaaaa-1111-1111-1111-111111111111'
            $Group.PSObject.Properties.Name -contains 'Members' |
                Should -BeFalse -Because 'an empty collection would be indistinguishable from a group with no members, and -Prune deletes on that'
        }

        It 'writes a non-terminating error, not just a warning, when the member read fails' {
            Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {
                throw 'TooManyRequests'
            } -ParameterFilter { $Uri -eq 'v1.0/groups/aaaaaaaa-1111-1111-1111-111111111111/members' }

            Get-OERGroup -Id 'aaaaaaaa-1111-1111-1111-111111111111' -IncludeMembers -ErrorVariable ReadErr -ErrorAction SilentlyContinue | Out-Null
            # -ErrorVariable also accumulates records from Pester's own internal mock-invocation
            # bookkeeping (empty InvocationInfo.MyCommand -- see the bearer-hygiene Describe at the
            # bottom of this file), which is noise no real caller of Get-OERGroup could ever see.
            # Restrict to the record actually published through Get-OERGroup's own WriteError call.
            $Published = @($ReadErr) | Where-Object {
                $_.InvocationInfo -and $_.InvocationInfo.MyCommand -and $_.InvocationInfo.MyCommand.Name -eq 'Get-OERGroup'
            }
            @($Published).Count | Should -BeGreaterThan 0
            @($Published)[0].FullyQualifiedErrorId | Should -Match 'GroupMemberReadFailed'
        }

        It 'scrubs the bearer-hygiene record before writing the member-read error' {
            Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {
                throw 'TooManyRequests'
            } -ParameterFilter { $Uri -eq 'v1.0/groups/aaaaaaaa-1111-1111-1111-111111111111/members' }
            Mock -ModuleName $script:moduleName Remove-OERErrorRecord { }

            Get-OERGroup -Id 'aaaaaaaa-1111-1111-1111-111111111111' -IncludeMembers -ErrorAction SilentlyContinue | Out-Null
            Should -Invoke -ModuleName $script:moduleName Remove-OERErrorRecord -Times 1 -Exactly
        }

        It 'omits the Owners property and errors when the owner read fails' {
            Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {
                throw 'Forbidden'
            } -ParameterFilter { $Uri -eq 'v1.0/groups/aaaaaaaa-1111-1111-1111-111111111111/owners' }

            $Group = Get-OERGroup -Id 'aaaaaaaa-1111-1111-1111-111111111111' -IncludeOwners -ErrorVariable ReadErr -ErrorAction SilentlyContinue
            # Prove the cmdlet actually emitted the group object before trusting an absent-property
            # read on it -- a $null result also satisfies '-contains' -> $false, so that check alone
            # cannot tell "read the group and correctly omitted Owners" from "emitted nothing".
            $Group | Should -Not -BeNullOrEmpty
            $Group.Id | Should -Be 'aaaaaaaa-1111-1111-1111-111111111111'
            $Group.PSObject.Properties.Name -contains 'Owners' | Should -BeFalse
            # Filtered for the same reason as the member-read test above: -ErrorVariable also
            # accumulates unrelated Pester mock-invocation bookkeeping noise.
            $Published = @($ReadErr) | Where-Object {
                $_.InvocationInfo -and $_.InvocationInfo.MyCommand -and $_.InvocationInfo.MyCommand.Name -eq 'Get-OERGroup'
            }
            @($Published)[0].FullyQualifiedErrorId | Should -Match 'GroupOwnerReadFailed'
        }

        It 'omits the PimEligibility property and errors when the eligibility read fails for a real reason' {
            Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {
                throw 'Forbidden'
            } -ParameterFilter { $Uri -match 'eligibilityScheduleInstances' }

            $Group = Get-OERGroup -Id 'aaaaaaaa-1111-1111-1111-111111111111' -IncludePimEligibility -ErrorVariable ReadErr -ErrorAction SilentlyContinue
            # Prove the cmdlet actually emitted the group object before trusting an absent-property
            # read on it -- a $null result also satisfies '-contains' -> $false, so that check alone
            # cannot tell "read the group and correctly omitted PimEligibility" from "emitted nothing".
            $Group | Should -Not -BeNullOrEmpty
            $Group.Id | Should -Be 'aaaaaaaa-1111-1111-1111-111111111111'
            $Group.PSObject.Properties.Name -contains 'PimEligibility' | Should -BeFalse
            # Filtered for the same reason as the member-read test above: -ErrorVariable also
            # accumulates unrelated Pester mock-invocation bookkeeping noise.
            $Published = @($ReadErr) | Where-Object {
                $_.InvocationInfo -and $_.InvocationInfo.MyCommand -and $_.InvocationInfo.MyCommand.Name -eq 'Get-OERGroup'
            }
            @($Published)[0].FullyQualifiedErrorId | Should -Match 'GroupPimEligibilityReadFailed'
        }

        It 'keeps PimEligibility as an empty array, with no error, for a group not onboarded to PIM' {
            Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {
                $Rec = [System.Management.Automation.ErrorRecord]::new(
                    [System.Exception]::new('The resource type is not supported.'),
                    'ResourceTypeNotSupported',
                    [System.Management.Automation.ErrorCategory]::InvalidOperation,
                    $null)
                throw $Rec
            } -ParameterFilter { $Uri -match 'eligibilityScheduleInstances' }

            $Group = Get-OERGroup -Id 'aaaaaaaa-1111-1111-1111-111111111111' -IncludePimEligibility -ErrorVariable ReadErr -ErrorAction SilentlyContinue
            $Group.PSObject.Properties.Name -contains 'PimEligibility' |
                Should -BeTrue -Because 'a group that is not PIM-onboarded genuinely has no eligibility; that is a read that succeeded'
            @($Group.PimEligibility).Count | Should -Be 0
            # Filtered for the same reason as the member-read test above: -ErrorVariable also
            # accumulates unrelated Pester mock-invocation bookkeeping noise, even on a code path
            # that itself never calls WriteError.
            $Published = @($ReadErr) | Where-Object {
                $_.InvocationInfo -and $_.InvocationInfo.MyCommand -and $_.InvocationInfo.MyCommand.Name -eq 'Get-OERGroup'
            }
            @($Published).Count | Should -Be 0
        }
    }
}

Describe 'Get-OERGroup bearer-hygiene (end-to-end)' {
    # Deliberately does NOT mock Invoke-OERGraphRequest (unlike every other test in this file): the
    # whole point is to exercise the REAL Invoke-OERGraphRequest -> Convert-GraphHttpException ->
    # Remove-OERErrorRecord chain, mocking only the raw SDK call at the true transport boundary, so a
    # regression in ANY of those three layers is caught here. This is the end-to-end reproduction of
    # the audit-pr8 finding: a transport failure with no parseable JSON body (a genuine connection
    # failure, or an HTML 5xx gateway page) used to fall through Convert-GraphHttpException's
    # "nothing extractable" branch as the RAW InputRecord, whose .Exception is the original SDK
    # exception -- in production that exception references the HttpRequestMessage carrying
    # "Authorization: Bearer <token>" in plain text.
    BeforeEach {
        InModuleScope $script:moduleName { $script:_OERAuthState = $null }
        Mock -ModuleName $script:moduleName Initialize-OERAuth {}
    }

    It 'never leaks the raw transport exception through $Error or -ErrorVariable on an HttpRequestException' {
        # Mocked at the standard module boundary (Mock -ModuleName, matching every other test in this
        # file and Invoke-OERGraphRequest.Tests.ps1) rather than via a bare InModuleScope Mock: the
        # latter was tried first and produced a large, unrelated noise floor of raw-typed records in
        # -ErrorVariable that trace (via .InvocationInfo) back to the Mock DEFINITION statement itself,
        # not to any Get-OERGroup/Invoke-OERGraphRequest code path -- a Pester mock-bookkeeping artifact
        # with no counterpart in real (unmocked) production use, confirmed by an explicit call counter
        # in the mock body showing exactly ONE real invocation regardless of that noise.
        Mock -ModuleName $script:moduleName Invoke-MgGraphRequest {
            throw [System.Net.Http.HttpRequestException]::new('The SSL connection could not be established.')
        }
        $Error.Clear()
        $ErrVar = $null

        Get-OERGroup -Id '22222222-2222-2222-2222-222222222222' -ErrorAction SilentlyContinue -ErrorVariable ErrVar | Out-Null

        # Assert on exception TYPE (via reflection, not a compile-time [type] literal -- the ASP.NET
        # HttpResponseException type is not loaded in this session, so a `-is` type-literal comparison
        # against it would fail to even parse), never on message text, and never on "(?i)authorization"
        # (every ARM resource id contains the literal Microsoft.Authorization).
        $LeakedFromError = @($Error) | Where-Object { $_.Exception } |
            Where-Object { $_.Exception.GetType().FullName -match 'HttpRequestException|HttpResponseException' }
        $LeakedFromError.Count | Should -Be 0

        # -ErrorVariable also accumulates records from Pester's own internal mock-invocation
        # bookkeeping (empty InvocationInfo.MyCommand -- verified by direct inspection: those trace
        # back to the Mock registration statement, never to real module code), which is noise that no
        # real (unmocked) caller of Get-OERGroup could ever see. Restrict the check to the record(s)
        # actually published through Get-OERGroup's own $PSCmdlet.WriteError call -- identifiable by
        # InvocationInfo.MyCommand.Name -- which is precisely the record the audit-pr8 finding is about.
        $PublishedByGetOERGroup = @($ErrVar) | Where-Object {
            $_.InvocationInfo -and $_.InvocationInfo.MyCommand -and $_.InvocationInfo.MyCommand.Name -eq 'Get-OERGroup'
        }
        $PublishedByGetOERGroup.Count | Should -BeGreaterThan 0
        $LeakedFromErrorVariable = $PublishedByGetOERGroup | Where-Object { $_.Exception } |
            Where-Object { $_.Exception.GetType().FullName -match 'HttpRequestException|HttpResponseException' }
        $LeakedFromErrorVariable.Count | Should -Be 0
    }
}

Describe 'Get-OERGroup PIM eligibility guard on the REAL transport shape' {
    # WHY THIS DESCRIBE EXISTS, and what the older tests were really asserting.
    #
    # Every other test of this guard mocks Invoke-OERGraphRequest and throws a hand-built
    # ErrorRecord whose ErrorId is already the literal string the guard tests for. That asserts the
    # guard against a shape the test itself chose -- it can never discover what the real transport
    # produces, and it is the same family as the recorded "guard is correct in tests and inert in
    # production" defect: mocking the wrapper hides every transport-level property.
    #
    # These tests mock only Invoke-MgGraphRequest, at the true transport boundary, so the record the
    # guard sees is built by the real Invoke-OERGraphRequest -> Convert-GraphHttpException chain
    # from a real HTTP 400 body -- the exact response a group that is not onboarded to PIM for
    # Groups returns from the beta eligibilityScheduleInstances endpoint.
    BeforeAll {
        # A minimal stand-in for the Graph SDK exception: an Exception carrying a real
        # HttpResponseMessage on .Response. Defined in a namespace unique to this file so a second
        # Add-Type of the same name can never collide inside the one Pester process, and guarded so
        # a re-run in the same session is a no-op rather than a duplicate-type error.
        if (-not ('OERGroupGuardFixture.GraphHttpException' -as [type])) {
            Add-Type -TypeDefinition @'
using System;
using System.Net.Http;
namespace OERGroupGuardFixture {
    public class GraphHttpException : Exception {
        public HttpResponseMessage Response { get; private set; }
        public GraphHttpException(string message, HttpResponseMessage response) : base(message) {
            Response = response;
        }
    }
}
'@
        }

        function New-NotOnboardedResponse {
            $Response = [System.Net.Http.HttpResponseMessage]::new([System.Net.HttpStatusCode]::BadRequest)
            $Response.Content = [System.Net.Http.StringContent]::new(
                '{"error":{"code":"ResourceTypeNotSupported","message":"Resource type not supported for onboarding"}}')
            # A correlation header and NO Retry-After: the ordinary shape of a non-throttled Graph
            # failure, and the one whose absent Retry-After used to make GetValues throw.
            $Response.Headers.TryAddWithoutValidation('request-id', 'r-1') | Out-Null
            $Response.RequestMessage = [System.Net.Http.HttpRequestMessage]::new(
                'GET', 'https://graph.microsoft.com/beta/identityGovernance/privilegedAccess/group/eligibilityScheduleInstances')
            return [OERGroupGuardFixture.GraphHttpException]::new(
                'Response status code does not indicate success: 400 (Bad Request).', $Response)
        }
    }

    BeforeEach {
        InModuleScope $script:moduleName { $script:_OERAuthState = $null }
        Mock -ModuleName $script:moduleName Initialize-OERAuth { }
    }

    It 'treats a real 400 ResourceTypeNotSupported as an empty eligibility, silently' {
        Mock -ModuleName $script:moduleName Invoke-MgGraphRequest {
            if ([string]$Uri -match 'eligibilityScheduleInstances') { throw (New-NotOnboardedResponse) }
            @{ id = '22222222-2222-2222-2222-222222222222'; displayName = 'plain'; securityEnabled = $true; isAssignableToRole = $false; groupTypes = @() }
        }

        $ErrVar = $null
        $Group = Get-OERGroup -Id '22222222-2222-2222-2222-222222222222' -IncludePimEligibility `
            -ErrorAction SilentlyContinue -ErrorVariable ErrVar

        # Prove the cmdlet emitted the group before trusting any property read on it: $null also
        # satisfies '-contains' -> $false, so that check alone cannot tell a correct empty
        # eligibility from a cmdlet that produced nothing.
        $Group | Should -Not -BeNullOrEmpty
        $Group.PSObject.Properties.Name -contains 'PimEligibility' |
            Should -BeTrue -Because 'a group that is not PIM-onboarded genuinely has no eligibility; that read succeeded'
        @($Group.PimEligibility).Count | Should -Be 0

        # The guard must publish NOTHING of its own. Restricted to records Get-OERGroup itself wrote
        # (identified by InvocationInfo.MyCommand.Name), since -ErrorVariable also accumulates
        # Pester mock-invocation bookkeeping and the engine's own capture of records raised inside
        # nested calls -- neither of which this cmdlet can suppress.
        $Published = @($ErrVar) | Where-Object {
            $_.InvocationInfo -and $_.InvocationInfo.MyCommand -and $_.InvocationInfo.MyCommand.Name -eq 'Get-OERGroup'
        }
        @($Published).Count | Should -Be 0
    }

    It 'raises no GetValues header record while handling that same 400' {
        # The live-run companion to the test above: one in three of the 288 records a single clean
        # Get-OERInventory read produced was a MethodInvocationException from
        # HttpResponseHeaders.GetValues('Retry-After'), which throws when the header is absent.
        # -ErrorVariable captures it even though the wrapper's catch swallowed it, so this assertion
        # has to be made on the CALLER's collection, not on $Error.
        Mock -ModuleName $script:moduleName Invoke-MgGraphRequest {
            if ([string]$Uri -match 'eligibilityScheduleInstances') { throw (New-NotOnboardedResponse) }
            @{ id = '22222222-2222-2222-2222-222222222222'; displayName = 'plain'; securityEnabled = $true; isAssignableToRole = $false; groupTypes = @() }
        }

        $ErrVar = $null
        Get-OERGroup -Id '22222222-2222-2222-2222-222222222222' -IncludePimEligibility `
            -ErrorAction SilentlyContinue -ErrorVariable ErrVar | Out-Null

        $HeaderNoise = @($ErrVar) | Where-Object { $_ -and $_.Exception } |
            Where-Object { $_.Exception.Message -match 'GetValues|given header was not found' }
        @($HeaderNoise).Count | Should -Be 0 -Because 'probing for an absent header must never raise a record of its own'
    }

    It 'refuses to swallow a DIFFERENT code that merely starts with the same text' {
        # The prefix-only '-like ResourceTypeNotSupported*' this guard used to carry would have
        # matched this and reported "no eligibility" for a read that genuinely failed -- silently
        # turning a failure into an empty collection, the exact outcome the members and owners
        # handling in this cmdlet exists to prevent.
        Mock -ModuleName $script:moduleName Invoke-MgGraphRequest {
            if ([string]$Uri -match 'eligibilityScheduleInstances') {
                $Response = [System.Net.Http.HttpResponseMessage]::new([System.Net.HttpStatusCode]::BadRequest)
                $Response.Content = [System.Net.Http.StringContent]::new(
                    '{"error":{"code":"ResourceTypeNotSupportedInThisTenant","message":"different failure"}}')
                throw [OERGroupGuardFixture.GraphHttpException]::new('400', $Response)
            }
            @{ id = '22222222-2222-2222-2222-222222222222'; displayName = 'plain'; securityEnabled = $true; isAssignableToRole = $false; groupTypes = @() }
        }

        $ErrVar = $null
        $Group = Get-OERGroup -Id '22222222-2222-2222-2222-222222222222' -IncludePimEligibility `
            -ErrorAction SilentlyContinue -ErrorVariable ErrVar

        $Group | Should -Not -BeNullOrEmpty
        $Group.PSObject.Properties.Name -contains 'PimEligibility' |
            Should -BeFalse -Because 'an unrecognised failure omits the property rather than reporting it empty'
        $Published = @($ErrVar) | Where-Object {
            $_.InvocationInfo -and $_.InvocationInfo.MyCommand -and $_.InvocationInfo.MyCommand.Name -eq 'Get-OERGroup'
        }
        @($Published)[0].FullyQualifiedErrorId | Should -Match 'GroupPimEligibilityReadFailed'
    }

    It 'matches the code when it is not the first segment of a composed FullyQualifiedErrorId' {
        # A FullyQualifiedErrorId is composed from the frames that re-raise the record, and the code
        # is not always first -- 'PathNotFound,Microsoft.PowerShell.Commands.GetItemCommand' is the
        # engine's own shape. A prefix-anchored -like misses the code in that position.
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {
            @{ id = '22222222-2222-2222-2222-222222222222'; displayName = 'plain'; securityEnabled = $true; isAssignableToRole = $false; groupTypes = @() }
        } -ParameterFilter { $Uri -eq 'v1.0/groups/22222222-2222-2222-2222-222222222222' }
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {
            throw [System.Management.Automation.ErrorRecord]::new(
                [System.Exception]::new('Resource type not supported for onboarding'),
                'SomeOuterFrame,ResourceTypeNotSupported',
                [System.Management.Automation.ErrorCategory]::OperationStopped, $null)
        } -ParameterFilter { $Uri -match 'eligibilityScheduleInstances' }

        $ErrVar = $null
        $Group = Get-OERGroup -Id '22222222-2222-2222-2222-222222222222' -IncludePimEligibility `
            -ErrorAction SilentlyContinue -ErrorVariable ErrVar

        $Group.PSObject.Properties.Name -contains 'PimEligibility' | Should -BeTrue
        @($Group.PimEligibility).Count | Should -Be 0
        $Published = @($ErrVar) | Where-Object {
            $_.InvocationInfo -and $_.InvocationInfo.MyCommand -and $_.InvocationInfo.MyCommand.Name -eq 'Get-OERGroup'
        }
        @($Published).Count | Should -Be 0
    }

    It 'matches the code carried only in the detail text of a status-derived record' {
        # Convert-GraphHttpException falls back to a STATUS-derived id ('BadRequest') whenever it
        # cannot extract error.code from the body, leaving the code only in the record's
        # "<code>: <message>" detail text. Reading the id alone misses it there.
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {
            @{ id = '22222222-2222-2222-2222-222222222222'; displayName = 'plain'; securityEnabled = $true; isAssignableToRole = $false; groupTypes = @() }
        } -ParameterFilter { $Uri -eq 'v1.0/groups/22222222-2222-2222-2222-222222222222' }
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {
            $Record = [System.Management.Automation.ErrorRecord]::new(
                [System.Exception]::new('ResourceTypeNotSupported: Resource type not supported for onboarding'),
                'BadRequest',
                [System.Management.Automation.ErrorCategory]::OperationStopped, $null)
            $Record.ErrorDetails = [System.Management.Automation.ErrorDetails]::new(
                'ResourceTypeNotSupported: Resource type not supported for onboarding')
            throw $Record
        } -ParameterFilter { $Uri -match 'eligibilityScheduleInstances' }

        $ErrVar = $null
        $Group = Get-OERGroup -Id '22222222-2222-2222-2222-222222222222' -IncludePimEligibility `
            -ErrorAction SilentlyContinue -ErrorVariable ErrVar

        $Group.PSObject.Properties.Name -contains 'PimEligibility' | Should -BeTrue
        @($Group.PimEligibility).Count | Should -Be 0
        $Published = @($ErrVar) | Where-Object {
            $_.InvocationInfo -and $_.InvocationInfo.MyCommand -and $_.InvocationInfo.MyCommand.Name -eq 'Get-OERGroup'
        }
        @($Published).Count | Should -Be 0
    }
}

Describe 'Get-OERGroup PIM eligibility raises no error record for a not-onboarded group' {
    # THE LIVE DEFECT THIS EXISTS FOR. Get-OERGroup's own guard already treated 400
    # ResourceTypeNotSupported as an expected answer and published nothing -- and a live
    # Get-OERInventory -Include Groups read of 100 groups, 96 of them not onboarded, still handed the
    # caller 261 error records. Every earlier test of that guard counted only the records
    # Get-OERGroup PUBLISHED (InvocationInfo.MyCommand.Name), so all of them passed while the caller
    # drowned. -ErrorVariable is filled by the ENGINE and also collects records raised inside nested
    # calls, even ones an inner catch swallowed, so the WHOLE collection is the only honest measure.
    #
    # The transport is a plain function stub rather than a Pester mock on purpose: the SDK sets
    # -StatusCodeVariable in the scope that INVOKED it (a binary cmdlet pushes no scope), and a mock
    # body runs too many frames below the wrapper for Set-Variable to reach it. The stub is declared
    # without a script:/global: qualifier so it cannot outlive the block, and is removed with
    # Remove-Item 'function:...' -- a script:-qualified path there removes nothing at all and the
    # leaked stub then shadows the real cmdlet for the rest of the Pester process. The removal sits
    # in a FINALLY so a failing assertion cannot skip it; measured, the unqualified declaration is
    # genuinely block-scoped either way, so that is the line meaning what it reads as rather than a
    # bug fix.
    BeforeEach {
        InModuleScope $script:moduleName { $script:_OERAuthState = $null }
        Mock -ModuleName $script:moduleName Initialize-OERAuth { }
    }

    It 'leaves the caller''s -ErrorVariable completely empty across a mixed tenant' {
        InModuleScope $script:moduleName {
            try {
                # Four onboarded groups and six that are not -- the live proportion in miniature.
                function Invoke-MgGraphRequest {
                    [CmdletBinding()]
                    param([string]$Method, [string]$Uri, $Body, [switch]$SkipHttpErrorCheck,
                        [string]$StatusCodeVariable, [string]$ResponseHeadersVariable)
                    if ([string]$Uri -match 'eligibilityScheduleInstances') {
                        $Index = 0
                        if ([string]$Uri -match "groupId eq '(\d{8})-") { $Index = [int]$Matches[1] }
                        if ($Index -gt 4) {
                            # InvokeMgGraphRequest.cs, verbatim:
                            #   if (ShouldCheckHttpStatus && !isSuccess) { ThrowTerminatingError(...) }
                            #   await ProcessResponseAsync(httpResponseMessage);
                            # with ShouldCheckHttpStatus => !SkipHttpErrorCheck. Modelling BOTH halves is
                            # what makes this test mutation-sensitive: strip -ExpectedErrorCode from the
                            # cmdlet and the raising half runs, so the eligibility still resolves to an
                            # empty collection through the fallback guard and ONLY the record count moves.
                            if (-not $SkipHttpErrorCheck) {
                                throw [System.Exception]::new(
                                    '{"error":{"code":"ResourceTypeNotSupported","message":"Resource type not supported for onboarding"}}')
                            }
                            Set-Variable -Name $StatusCodeVariable -Value 400 -Scope 1
                            return ('{"error":{"code":"ResourceTypeNotSupported","message":"Resource type not supported for onboarding"}}' |
                                    ConvertFrom-Json -AsHashtable)
                        }
                        if ($StatusCodeVariable) { Set-Variable -Name $StatusCodeVariable -Value 200 -Scope 1 }
                        return @{ value = @(@{ id = 'e1'; accessId = 'member' }) }
                    }
                    if ([string]$Uri -match '/members|/owners') { return @{ value = @() } }
                    return @{ value = @(1..10 | ForEach-Object {
                                @{ id = ('{0:d8}-0000-0000-0000-000000000000' -f $_); displayName = "g$_"
                                    securityEnabled = $true; isAssignableToRole = $false; groupTypes = @()
                                }
                            }) }
                }

                $Err = $null
                $Groups = @(Get-OERGroup -Filter 'securityEnabled eq true' -IncludePimEligibility `
                        -ErrorAction SilentlyContinue -ErrorVariable Err)

                # The count assertion comes FIRST on purpose. It is the one this whole change exists to
                # move, and Pester reports the first failing assertion -- putting it last would let a
                # mutation be "caught" by an unrelated projection check instead.
                @($Err).Count | Should -Be 0 -Because 'a normal read of a tenant whose groups are mostly not PIM-onboarded must be silent'

                @($Groups).Count | Should -Be 10 -Because 'the read itself must still work'
                # Present on all ten, empty on the six that are not onboarded, populated on the four
                # that are: a not-onboarded group has genuinely no eligibility, and that is a read which
                # SUCCEEDED. Omitting the property is reserved for a read that FAILED (issue #76).
                @($Groups | Where-Object { $_.PSObject.Properties.Name -contains 'PimEligibility' }).Count | Should -Be 10
                @($Groups | Where-Object { @($_.PimEligibility).Count -eq 0 }).Count | Should -Be 6
                @($Groups | Where-Object { @($_.PimEligibility).Count -gt 0 }).Count | Should -Be 4
            } finally {
                Remove-Item 'function:Invoke-MgGraphRequest'
            }
        }
    }

    It 'still omits the property and errors when the eligibility read genuinely fails' {
        # The other half of issue #76, on the same transport shape: 403 is not the declared code, so
        # it must still surface, and the property must be ABSENT rather than reported empty.
        InModuleScope $script:moduleName {
            try {
                function Invoke-MgGraphRequest {
                    [CmdletBinding()]
                    param([string]$Method, [string]$Uri, $Body, [switch]$SkipHttpErrorCheck,
                        [string]$StatusCodeVariable, [string]$ResponseHeadersVariable)
                    if ([string]$Uri -match 'eligibilityScheduleInstances') {
                        if (-not $SkipHttpErrorCheck) {
                            throw [System.Exception]::new(
                                '{"error":{"code":"Authorization_RequestDenied","message":"Insufficient privileges"}}')
                        }
                        Set-Variable -Name $StatusCodeVariable -Value 403 -Scope 1
                        return ('{"error":{"code":"Authorization_RequestDenied","message":"Insufficient privileges"}}' |
                                ConvertFrom-Json -AsHashtable)
                    }
                    return @{ value = @(@{ id = '00000001-0000-0000-0000-000000000000'; displayName = 'g1'
                            securityEnabled = $true; isAssignableToRole = $false; groupTypes = @()
                        }) }
                }

                $Err = $null
                $Group = Get-OERGroup -Filter 'securityEnabled eq true' -IncludePimEligibility `
                    -ErrorAction SilentlyContinue -ErrorVariable Err

                $Group | Should -Not -BeNullOrEmpty
                $Group.PSObject.Properties.Name -contains 'PimEligibility' |
                    Should -BeFalse -Because 'a failed read must never be recorded as an empty fact'
                $Published = @($Err) | Where-Object {
                    $_.InvocationInfo -and $_.InvocationInfo.MyCommand -and $_.InvocationInfo.MyCommand.Name -eq 'Get-OERGroup'
                }
                @($Published).Count | Should -BeGreaterThan 0
                @($Published)[0].FullyQualifiedErrorId | Should -Match 'GroupPimEligibilityReadFailed'
            } finally {
                Remove-Item 'function:Invoke-MgGraphRequest'
            }
        }
    }
}

Describe 'Get-OERGroup PIM eligibility refuses a 403 whose prose mentions the expected code' {
    # THE DEFECT, seen from the cmdlet that suffers it. Both the wrapper's expected-code match and
    # this cmdlet's own inline fallback used to split the record's message on ':' unconditionally, so
    #   {"code":"Authorization_RequestDenied","message":"Insufficient privileges: ResourceTypeNotSupported"}
    # produced 'ResourceTypeNotSupported' as a whole segment and a real 403 was recorded as
    # PimEligibility = @(). An operator reading that document sees a group with no PIM eligibility;
    # what actually happened is that nobody was allowed to look. Issue #76 exists for exactly this.
    #
    # THE TWO GUARDS ARE NOT BACKUPS FOR EACH OTHER, so do not read this Describe as covering one via
    # the other. The stub below models BOTH halves of InvokeMgGraphRequest.cs, which is what lets one
    # fixture reach both: with -ExpectedErrorCode declared the failure arrives at the WRAPPER's gate
    # as data, and the inline catch never runs at all. Measured -- softening the wrapper's gate alone
    # brings the defect back completely and silently (PimEligibility present, Count 0, zero error
    # records); softening the inline copy alone leaves PimEligibility = @() with 5 records. Different
    # arrival shapes, different guards, and the wrapper's is the one a live tenant exercises.
    BeforeEach {
        InModuleScope $script:moduleName { $script:_OERAuthState = $null }
        Mock -ModuleName $script:moduleName Initialize-OERAuth { }
    }

    It 'omits PimEligibility and reports GroupPimEligibilityReadFailed instead of an empty collection' {
        InModuleScope $script:moduleName {
            try {
                function Invoke-MgGraphRequest {
                    [CmdletBinding()]
                    param([string]$Method, [string]$Uri, $Body, [switch]$SkipHttpErrorCheck,
                        [string]$StatusCodeVariable, [string]$ResponseHeadersVariable)
                    if ([string]$Uri -match 'eligibilityScheduleInstances') {
                        # Both halves of InvokeMgGraphRequest.cs, so the assertion holds whether the
                        # failure arrives as data (the -SkipHttpErrorCheck path) or is raised.
                        if (-not $SkipHttpErrorCheck) {
                            throw [System.Exception]::new(
                                '{"error":{"code":"Authorization_RequestDenied","message":"Insufficient privileges: ResourceTypeNotSupported"}}')
                        }
                        Set-Variable -Name $StatusCodeVariable -Value 403 -Scope 1
                        return ('{"error":{"code":"Authorization_RequestDenied","message":"Insufficient privileges: ResourceTypeNotSupported"}}' |
                                ConvertFrom-Json -AsHashtable)
                    }
                    if ($StatusCodeVariable) { Set-Variable -Name $StatusCodeVariable -Value 200 -Scope 1 }
                    if ([string]$Uri -match '/members|/owners') { return @{ value = @() } }
                    return @{ value = @(@{ id = '00000001-0000-0000-0000-000000000000'; displayName = 'g1'
                            securityEnabled = $true; isAssignableToRole = $false; groupTypes = @()
                        }) }
                }

                $Err = $null
                $Group = Get-OERGroup -Filter 'securityEnabled eq true' -IncludePimEligibility `
                    -ErrorAction SilentlyContinue -ErrorVariable Err

                $Group | Should -Not -BeNullOrEmpty
                $Group.PSObject.Properties.Name -contains 'PimEligibility' |
                    Should -BeFalse -Because 'a read nobody was allowed to perform is not an empty fact'
                $Published = @($Err) | Where-Object {
                    $_.InvocationInfo -and $_.InvocationInfo.MyCommand -and $_.InvocationInfo.MyCommand.Name -eq 'Get-OERGroup'
                }
                @($Published).Count | Should -BeGreaterThan 0 -Because 'the operator must be told the read failed'
                @($Published)[0].FullyQualifiedErrorId | Should -Match 'GroupPimEligibilityReadFailed'
            } finally {
                Remove-Item 'function:Invoke-MgGraphRequest'
            }
        }
    }

    It 'still treats a status-derived record carrying the code only in its text as not-onboarded' {
        # The allowance the guard above must not break, at this call site: when Graph named no code
        # the converter derives the id from the status and the code survives only in the detail text.
        # That IS the not-onboarded answer and the property must be present and empty.
        InModuleScope $script:moduleName {
            try {
                function Invoke-MgGraphRequest {
                    [CmdletBinding()]
                    param([string]$Method, [string]$Uri, $Body, [switch]$SkipHttpErrorCheck,
                        [string]$StatusCodeVariable, [string]$ResponseHeadersVariable)
                    if ([string]$Uri -match 'eligibilityScheduleInstances') {
                        if (-not $SkipHttpErrorCheck) {
                            throw [System.Exception]::new('{"error":{"message":"ResourceTypeNotSupported: not onboarded"}}')
                        }
                        Set-Variable -Name $StatusCodeVariable -Value 400 -Scope 1
                        return @{ error = @{ message = 'ResourceTypeNotSupported: not onboarded' } }
                    }
                    if ($StatusCodeVariable) { Set-Variable -Name $StatusCodeVariable -Value 200 -Scope 1 }
                    if ([string]$Uri -match '/members|/owners') { return @{ value = @() } }
                    return @{ value = @(@{ id = '00000001-0000-0000-0000-000000000000'; displayName = 'g1'
                            securityEnabled = $true; isAssignableToRole = $false; groupTypes = @()
                        }) }
                }

                $Err = $null
                $Group = Get-OERGroup -Filter 'securityEnabled eq true' -IncludePimEligibility `
                    -ErrorAction SilentlyContinue -ErrorVariable Err

                $Group.PSObject.Properties.Name -contains 'PimEligibility' | Should -BeTrue
                @($Group.PimEligibility).Count | Should -Be 0
                @($Err) | Where-Object {
                    $_.InvocationInfo -and $_.InvocationInfo.MyCommand -and $_.InvocationInfo.MyCommand.Name -eq 'Get-OERGroup'
                } | Should -BeNullOrEmpty -Because 'a group that is simply not onboarded is not a failure'
            } finally {
                Remove-Item 'function:Invoke-MgGraphRequest'
            }
        }
    }
}
