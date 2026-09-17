BeforeAll {
    $script:moduleName = 'Omnicit.EntraRBAC'
    Get-Module $script:moduleName | Remove-Module -Force -ErrorAction SilentlyContinue
    Import-Module $script:moduleName -Force -ErrorAction Stop
}

Describe 'Remove-OERGroupMember' {
    BeforeEach {
        InModuleScope $script:moduleName { $script:_OERAuthState = $null }
        Mock -ModuleName $script:moduleName Initialize-OERAuth {}
        Mock -ModuleName $script:moduleName Resolve-OERGroupId { param($DisplayName) $DisplayName }
    }

    It 'removes a member via the members/{id}/$ref endpoint' {
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {}
        Remove-OERGroupMember -Group 'gid-1' -PrincipalId '11111111-1111-1111-1111-111111111111' -Confirm:$false
        Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 1 -ParameterFilter {
            $Method -eq 'DELETE' -and $Uri -eq 'v1.0/groups/gid-1/members/11111111-1111-1111-1111-111111111111/$ref'
        }
    }

    It 'removes an owner when -AccessType owner is used' {
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {}
        Remove-OERGroupMember -Group 'gid-1' -PrincipalId '22222222-2222-2222-2222-222222222222' -AccessType owner -Confirm:$false
        Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 1 -ParameterFilter {
            $Method -eq 'DELETE' -and $Uri -eq 'v1.0/groups/gid-1/owners/22222222-2222-2222-2222-222222222222/$ref'
        }
    }

    It 'does not DELETE under -WhatIf' {
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {}
        Remove-OERGroupMember -Group 'gid-1' -PrincipalId '11111111-1111-1111-1111-111111111111' -WhatIf
        Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 0 -ParameterFilter { $Method -eq 'DELETE' }
    }

    It 'round-trips a piped GroupMember object: GroupId->-Group, PrincipalId->-PrincipalId and DELETE targets the group and principal' {
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {}
        $Member = [pscustomobject]@{
            Id          = '44444444-4444-4444-4444-444444444444'
            DisplayName = 'Anna'
            GroupId     = 'GROUP'
            MemberType  = 'Member'
            PrincipalId = '44444444-4444-4444-4444-444444444444'
        }
        $Member | Remove-OERGroupMember -Confirm:$false
        Should -Invoke -ModuleName $script:moduleName Resolve-OERGroupId -Times 1 -ParameterFilter {
            $DisplayName -eq 'GROUP'
        }
        Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 1 -ParameterFilter {
            $Method -eq 'DELETE' -and $Uri -eq 'v1.0/groups/GROUP/members/44444444-4444-4444-4444-444444444444/$ref'
        }
    }

    It 'piped owner object routes to the owners collection via -AccessType binding' {
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {}
        $Owner = [pscustomobject]@{
            Id          = '55555555-5555-5555-5555-555555555555'
            DisplayName = 'Bob'
            GroupId     = 'GROUP'
            MemberType  = 'Owner'
            PrincipalId = '55555555-5555-5555-5555-555555555555'
        }
        $Owner | Remove-OERGroupMember -Confirm:$false
        Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 1 -ParameterFilter {
            $Method -eq 'DELETE' -and $Uri -eq 'v1.0/groups/GROUP/owners/55555555-5555-5555-5555-555555555555/$ref'
        }
    }

    It 'back-compat: explicit -Id alias still resolves the group' {
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {}
        Remove-OERGroupMember -Id 'gid-1' -PrincipalId '11111111-1111-1111-1111-111111111111' -Confirm:$false
        Should -Invoke -ModuleName $script:moduleName Resolve-OERGroupId -Times 1 -ParameterFilter {
            $DisplayName -eq 'gid-1'
        }
        Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 1 -ParameterFilter {
            $Method -eq 'DELETE' -and $Uri -like '*gid-1/members/11111111-1111-1111-1111-111111111111/*'
        }
    }

    It 'back-compat: explicit -DisplayName alias still resolves the group by name' {
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {}
        Remove-OERGroupMember -DisplayName 'role_sec_team' -PrincipalId '11111111-1111-1111-1111-111111111111' -Confirm:$false
        Should -Invoke -ModuleName $script:moduleName Resolve-OERGroupId -Times 1 -ParameterFilter {
            $DisplayName -eq 'role_sec_team'
        }
    }

    It 'scrubs the bearer-hygiene record when the DELETE fails' {
        # Drives the DELETE catch in source/Public/Remove-OERGroupMember.ps1 (the $ref try inside
        # ShouldProcess). Resolve-OERGroupId is mocked to SUCCEED by the Describe BeforeEach and the
        # principal is a literal GUID, so the mocked transport failure is what reaches the catch.
        # CLAUDE.md SECURITY rule 6 makes Remove-OERErrorRecord -Record $PSItem its first statement.
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest { throw 'transport failure' }
        Mock -ModuleName $script:moduleName Remove-OERErrorRecord { }
        Remove-OERGroupMember -Group 'gid-1' -PrincipalId '11111111-1111-1111-1111-111111111111' `
            -Confirm:$false -ErrorAction SilentlyContinue
        Should -Invoke -ModuleName $script:moduleName Remove-OERErrorRecord -Times 1
    }

    Context 'friendly principal input' {
        BeforeEach {
            InModuleScope Omnicit.EntraRBAC { $script:_OERAuthState = $null }
            Mock -ModuleName Omnicit.EntraRBAC Initialize-OERAuth { }
            Mock -ModuleName Omnicit.EntraRBAC Resolve-OERGroupId { 'gggg0000-0000-0000-0000-00000000000a' }
            Mock -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest { }
        }

        It 'resolves -User to an object id and deletes it from members/$ref' {
            Mock -ModuleName Omnicit.EntraRBAC Resolve-OERPrincipal {
                [PSCustomObject]@{ PrincipalId = 'bbbb0000-0000-0000-0000-000000000002'; PrincipalType = 'User' }
            }
            Remove-OERGroupMember -Group 'role_sec_team' -User 'anna.berg@contoso.com' -Confirm:$false
            Should -Invoke Invoke-OERGraphRequest -ModuleName Omnicit.EntraRBAC -Times 1 -ParameterFilter {
                $Method -eq 'DELETE' -and
                $Uri -eq 'v1.0/groups/gggg0000-0000-0000-0000-00000000000a/members/bbbb0000-0000-0000-0000-000000000002/$ref'
            }
        }

        It 'resolves -GroupPrincipal and routes -AccessType owner to owners/{id}/$ref' {
            Mock -ModuleName Omnicit.EntraRBAC Resolve-OERPrincipal {
                [PSCustomObject]@{ PrincipalId = 'cccc0000-0000-0000-0000-000000000003'; PrincipalType = 'Group' }
            }
            Remove-OERGroupMember -Group 'role_sec_team' -GroupPrincipal 'Sales Team' -AccessType owner -Confirm:$false
            Should -Invoke Invoke-OERGraphRequest -ModuleName Omnicit.EntraRBAC -Times 1 -ParameterFilter {
                $Method -eq 'DELETE' -and
                $Uri -eq 'v1.0/groups/gggg0000-0000-0000-0000-00000000000a/owners/cccc0000-0000-0000-0000-000000000003/$ref'
            }
        }

        It 'resolves -ServicePrincipal to an object id and deletes it from members/$ref' {
            Mock -ModuleName Omnicit.EntraRBAC Resolve-OERPrincipal {
                [PSCustomObject]@{ PrincipalId = 'dddd0000-0000-0000-0000-000000000004'; PrincipalType = 'ServicePrincipal' }
            }
            Remove-OERGroupMember -Group 'role_sec_team' -ServicePrincipal 'Contoso App' -Confirm:$false
            Should -Invoke Resolve-OERPrincipal -ModuleName Omnicit.EntraRBAC -Times 1 -ParameterFilter {
                $ServicePrincipal -eq 'Contoso App'
            }
            Should -Invoke Invoke-OERGraphRequest -ModuleName Omnicit.EntraRBAC -Times 1 -ParameterFilter {
                $Method -eq 'DELETE' -and
                $Uri -eq 'v1.0/groups/gggg0000-0000-0000-0000-00000000000a/members/dddd0000-0000-0000-0000-000000000004/$ref'
            }
        }

        It 'unions -PrincipalId, -User and -GroupPrincipal into one call per principal, each with its own distinct id' {
            Mock -ModuleName Omnicit.EntraRBAC Resolve-OERPrincipal {
                if ($User) { [PSCustomObject]@{ PrincipalId = 'bbbb0000-0000-0000-0000-000000000002'; PrincipalType = 'User' } }
                else { [PSCustomObject]@{ PrincipalId = 'cccc0000-0000-0000-0000-000000000003'; PrincipalType = 'Group' } }
            }
            Remove-OERGroupMember -Group 'role_sec_team' `
                -PrincipalId 'aaaa0000-0000-0000-0000-000000000001' `
                -User 'anna.berg@contoso.com' -GroupPrincipal 'Sales Team' -Confirm:$false
            Should -Invoke Invoke-OERGraphRequest -ModuleName Omnicit.EntraRBAC -Times 3 -ParameterFilter {
                $Method -eq 'DELETE'
            }
            Should -Invoke Invoke-OERGraphRequest -ModuleName Omnicit.EntraRBAC -Times 1 -ParameterFilter {
                $Method -eq 'DELETE' -and
                $Uri -eq 'v1.0/groups/gggg0000-0000-0000-0000-00000000000a/members/aaaa0000-0000-0000-0000-000000000001/$ref'
            }
            Should -Invoke Invoke-OERGraphRequest -ModuleName Omnicit.EntraRBAC -Times 1 -ParameterFilter {
                $Method -eq 'DELETE' -and
                $Uri -eq 'v1.0/groups/gggg0000-0000-0000-0000-00000000000a/members/bbbb0000-0000-0000-0000-000000000002/$ref'
            }
            Should -Invoke Invoke-OERGraphRequest -ModuleName Omnicit.EntraRBAC -Times 1 -ParameterFilter {
                $Method -eq 'DELETE' -and
                $Uri -eq 'v1.0/groups/gggg0000-0000-0000-0000-00000000000a/members/cccc0000-0000-0000-0000-000000000003/$ref'
            }
        }

        It 'rejects a UPN passed to -PrincipalId with InvalidPrincipalId and does not call Graph' {
            $Err = $null
            Remove-OERGroupMember -Group 'role_sec_team' -PrincipalId 'anna.berg@contoso.com' `
                -Confirm:$false -ErrorAction SilentlyContinue -ErrorVariable Err
            $Err[0].FullyQualifiedErrorId | Should -BeLike 'InvalidPrincipalId*'
            $Err[0].Exception.Message | Should -BeLike '*-User*'
            Should -Invoke Invoke-OERGraphRequest -ModuleName Omnicit.EntraRBAC -Times 0 -ParameterFilter {
                $Method -eq 'DELETE'
            }
        }

        It 'keeps processing the remaining principals after one fails the GUID guard' {
            $Err = $null
            Remove-OERGroupMember -Group 'role_sec_team' `
                -PrincipalId 'anna.berg@contoso.com', 'aaaa0000-0000-0000-0000-000000000001' `
                -Confirm:$false -ErrorAction SilentlyContinue -ErrorVariable Err
            $Err.Count | Should -Be 1
            Should -Invoke Invoke-OERGraphRequest -ModuleName Omnicit.EntraRBAC -Times 1 -ParameterFilter {
                $Method -eq 'DELETE' -and
                $Uri -eq 'v1.0/groups/gggg0000-0000-0000-0000-00000000000a/members/aaaa0000-0000-0000-0000-000000000001/$ref'
            }
        }

        It 'reports NoPrincipal when no principal parameter is supplied' {
            $Err = $null
            Remove-OERGroupMember -Group 'role_sec_team' -Confirm:$false `
                -ErrorAction SilentlyContinue -ErrorVariable Err
            $Err[0].FullyQualifiedErrorId | Should -BeLike 'NoPrincipal*'
        }

        It 'still round-trips a piped Get-OERGroupMember object' {
            $Member = [PSCustomObject]@{
                GroupId     = 'gggg0000-0000-0000-0000-00000000000a'
                PrincipalId = 'aaaa0000-0000-0000-0000-000000000001'
                MemberType  = 'member'
            }
            $Member | Remove-OERGroupMember -Confirm:$false
            Should -Invoke Invoke-OERGraphRequest -ModuleName Omnicit.EntraRBAC -Times 1 -ParameterFilter {
                $Method -eq 'DELETE' -and
                $Uri -eq 'v1.0/groups/gggg0000-0000-0000-0000-00000000000a/members/aaaa0000-0000-0000-0000-000000000001/$ref'
            }
        }
    }
}

Describe 'Remove-OERGroupMember verbose output' {
    BeforeEach {
        InModuleScope $script:moduleName { $script:_OERAuthState = $null }
        Mock -ModuleName $script:moduleName Initialize-OERAuth {}
        Mock -ModuleName $script:moduleName Resolve-OERGroupId { 'gid-1' }
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {}
    }

    It 'reports the resolved group and one line per resolved principal under -Verbose' {
        $Verbose = Remove-OERGroupMember -Group 'gid-1' -PrincipalId @(
            '11111111-1111-1111-1111-111111111111',
            '22222222-2222-2222-2222-222222222222'
        ) -Confirm:$false -Verbose 4>&1 |
            Where-Object { $_ -is [System.Management.Automation.VerboseRecord] }

        $Text = $Verbose.Message -join "`n"
        $Text | Should -Match "\[Remove-OERGroupMember\] Resolved group to 'gid-1'."
        @($Verbose | Where-Object { $_.Message -match 'Resolved principal to ' }).Count | Should -Be 2
    }

    It 'emits no verbose output without -Verbose' {
        $Verbose = Remove-OERGroupMember -Group 'gid-1' -PrincipalId '11111111-1111-1111-1111-111111111111' `
            -Confirm:$false 4>&1 | Where-Object { $_ -is [System.Management.Automation.VerboseRecord] }
        $Verbose | Should -BeNullOrEmpty
    }
}
