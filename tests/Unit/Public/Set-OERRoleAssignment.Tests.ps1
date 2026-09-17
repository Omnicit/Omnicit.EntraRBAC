BeforeAll {
    Import-Module Omnicit.EntraRBAC -Force
}

Describe 'Set-OERRoleAssignment' {
    BeforeEach {
        InModuleScope Omnicit.EntraRBAC { $script:_OERAuthState = $null }
        Mock -ModuleName Omnicit.EntraRBAC Initialize-OERAuth { }
    }

    # NOTE: every id and expected value below is a LITERAL, repeated in full. Do NOT hoist them into
    # $Script: variables -- a mock body and a -ParameterFilter scriptblock are evaluated in the MODULE
    # scope when the mock runs, so a $Script: variable defined in the test file resolves to $null there
    # and the assertion silently compares nothing against nothing. This matches the literal style
    # already used in tests/Unit/Public/Remove-OERRoleAssignment.Tests.ps1.

    It 'rejects an id that is not a role assignment resource id' {
        { Set-OERRoleAssignment -Id '/subscriptions/abc' -Description 'x' -Confirm:$false -ErrorAction Stop } |
            Should -Throw -ErrorId 'InvalidRoleAssignmentId,Set-OERRoleAssignment'
    }

    It 'emits NothingToUpdate when no editable parameter is bound' {
        Mock -ModuleName Omnicit.EntraRBAC Invoke-OERArmRequest { }
        { Set-OERRoleAssignment -Id '/subscriptions/s/providers/Microsoft.Authorization/roleAssignments/00000000-0000-0000-0000-000000000059' -Confirm:$false -ErrorAction Stop } |
            Should -Throw -ErrorId 'NothingToUpdate,Set-OERRoleAssignment'
        Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-OERArmRequest -Times 0 -Exactly
    }

    It 'PUTs to the SAME id and carries roleDefinitionId and principalId unchanged' {
        Mock -ModuleName Omnicit.EntraRBAC Invoke-OERArmRequest {
            [PSCustomObject]@{
                id   = '/subscriptions/s/providers/Microsoft.Authorization/roleAssignments/00000000-0000-0000-0000-000000000059'
                name = '00000000-0000-0000-0000-000000000059'
                properties = [PSCustomObject]@{
                    scope            = '/subscriptions/s'
                    roleDefinitionId = '/subscriptions/s/providers/Microsoft.Authorization/roleDefinitions/acdd72a7-3385-48ef-bd42-f606fba81ae7'
                    principalId      = '11111111-2222-3333-4444-555555555555'
                    principalType    = 'Group'
                    description      = 'original description'
                    condition        = "@Resource[y] StringEquals 'z'"
                    conditionVersion = '2.0'
                }
            }
        }
        Set-OERRoleAssignment -Id '/subscriptions/s/providers/Microsoft.Authorization/roleAssignments/00000000-0000-0000-0000-000000000059' -Description 'new description' -Confirm:$false
        Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-OERArmRequest -Times 1 -Exactly -ParameterFilter {
            $Method -eq 'PUT' -and
            $Path -eq '/subscriptions/s/providers/Microsoft.Authorization/roleAssignments/00000000-0000-0000-0000-000000000059?api-version=2022-04-01' -and
            $Body.properties.roleDefinitionId -eq '/subscriptions/s/providers/Microsoft.Authorization/roleDefinitions/acdd72a7-3385-48ef-bd42-f606fba81ae7' -and
            $Body.properties.principalId -eq '11111111-2222-3333-4444-555555555555'
        }
    }

    It 'carries a live delegatedManagedIdentityResourceId forward on a description-only edit' {
        Mock -ModuleName Omnicit.EntraRBAC Invoke-OERArmRequest {
            [PSCustomObject]@{
                id   = '/subscriptions/s/providers/Microsoft.Authorization/roleAssignments/00000000-0000-0000-0000-000000000059'
                name = '00000000-0000-0000-0000-000000000059'
                properties = [PSCustomObject]@{
                    roleDefinitionId = '/r'; principalId = 'p'; principalType = 'Group'
                    description = 'original description'
                    delegatedManagedIdentityResourceId = '/subscriptions/lighthouse-sub/resourceGroups/rg/providers/Microsoft.ManagedServices/registrationAssignments/00000000-0000-0000-0000-000000000052'
                }
            }
        }
        Set-OERRoleAssignment -Id '/subscriptions/s/providers/Microsoft.Authorization/roleAssignments/00000000-0000-0000-0000-000000000059' -Description 'new description' -Confirm:$false
        Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-OERArmRequest -Times 1 -Exactly -ParameterFilter {
            $Method -eq 'PUT' -and
            $Body.properties.description -eq 'new description' -and
            $Body.properties.delegatedManagedIdentityResourceId -eq '/subscriptions/lighthouse-sub/resourceGroups/rg/providers/Microsoft.ManagedServices/registrationAssignments/00000000-0000-0000-0000-000000000052'
        }
    }

    It 'clears the description for an empty -Description' {
        Mock -ModuleName Omnicit.EntraRBAC Invoke-OERArmRequest {
            [PSCustomObject]@{
                id   = '/subscriptions/s/providers/Microsoft.Authorization/roleAssignments/00000000-0000-0000-0000-000000000059'
                name = '00000000-0000-0000-0000-000000000059'
                properties = [PSCustomObject]@{
                    roleDefinitionId = '/r'; principalId = 'p'; principalType = 'Group'
                    description = 'original description'
                }
            }
        }
        Set-OERRoleAssignment -Id '/subscriptions/s/providers/Microsoft.Authorization/roleAssignments/00000000-0000-0000-0000-000000000059' -Description '' -Confirm:$false
        Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-OERArmRequest -Times 1 -Exactly -ParameterFilter {
            $Method -eq 'PUT' -and $Body.properties.description -eq ''
        }
    }

    It 'does not warn when the live assignment had no condition and -Condition '''' is passed' {
        Mock -ModuleName Omnicit.EntraRBAC Invoke-OERArmRequest {
            [PSCustomObject]@{
                id   = '/subscriptions/s/providers/Microsoft.Authorization/roleAssignments/00000000-0000-0000-0000-000000000059'
                name = '00000000-0000-0000-0000-000000000059'
                properties = [PSCustomObject]@{
                    roleDefinitionId = '/r'; principalId = 'p'; principalType = 'Group'
                }
            }
        }
        $Warnings = @()
        Set-OERRoleAssignment -Id '/subscriptions/s/providers/Microsoft.Authorization/roleAssignments/00000000-0000-0000-0000-000000000059' -Condition '' -Confirm:$false -WarningVariable Warnings -WarningAction SilentlyContinue
        $Warnings.Count | Should -Be 0
        Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-OERArmRequest -Times 1 -Exactly -ParameterFilter {
            $Method -eq 'PUT' -and -not $Body.properties.ContainsKey('condition')
        }
    }

    It 'does not raise ConditionVersionWithoutCondition for an orphaned live conditionVersion on a description-only edit' {
        Mock -ModuleName Omnicit.EntraRBAC Invoke-OERArmRequest {
            [PSCustomObject]@{
                id   = '/subscriptions/s/providers/Microsoft.Authorization/roleAssignments/00000000-0000-0000-0000-000000000059'
                name = '00000000-0000-0000-0000-000000000059'
                properties = [PSCustomObject]@{
                    roleDefinitionId = '/r'; principalId = 'p'; principalType = 'Group'
                    conditionVersion = '1.0'
                }
            }
        }
        { Set-OERRoleAssignment -Id '/subscriptions/s/providers/Microsoft.Authorization/roleAssignments/00000000-0000-0000-0000-000000000059' -Description 'new description' -Confirm:$false -ErrorAction Stop } |
            Should -Not -Throw
        Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-OERArmRequest -Times 1 -Exactly -ParameterFilter {
            $Method -eq 'PUT' -and $Body.properties.description -eq 'new description' -and -not $Body.properties.ContainsKey('condition')
        }
    }

    It 'preserves the live condition when only -Description is supplied' {
        Mock -ModuleName Omnicit.EntraRBAC Invoke-OERArmRequest {
            [PSCustomObject]@{
                id   = '/subscriptions/s/providers/Microsoft.Authorization/roleAssignments/00000000-0000-0000-0000-000000000059'
                name = '00000000-0000-0000-0000-000000000059'
                properties = [PSCustomObject]@{
                    roleDefinitionId = '/r'; principalId = 'p'; principalType = 'Group'
                    description = 'original description'
                    condition = "@Resource[y] StringEquals 'z'"; conditionVersion = '2.0'
                }
            }
        }
        Set-OERRoleAssignment -Id '/subscriptions/s/providers/Microsoft.Authorization/roleAssignments/00000000-0000-0000-0000-000000000059' -Description 'new description' -Confirm:$false
        Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-OERArmRequest -Times 1 -Exactly -ParameterFilter {
            $Method -eq 'PUT' -and
            $Body.properties.description -eq 'new description' -and
            $Body.properties.condition -eq "@Resource[y] StringEquals 'z'" -and
            $Body.properties.conditionVersion -eq '2.0'
        }
    }

    It 'preserves the live description when only -Condition is supplied' {
        Mock -ModuleName Omnicit.EntraRBAC Invoke-OERArmRequest {
            [PSCustomObject]@{
                id   = '/subscriptions/s/providers/Microsoft.Authorization/roleAssignments/00000000-0000-0000-0000-000000000059'
                name = '00000000-0000-0000-0000-000000000059'
                properties = [PSCustomObject]@{
                    roleDefinitionId = '/r'; principalId = 'p'; principalType = 'Group'
                    description = 'original description'
                    condition = "@Resource[y] StringEquals 'z'"; conditionVersion = '2.0'
                }
            }
        }
        Set-OERRoleAssignment -Id '/subscriptions/s/providers/Microsoft.Authorization/roleAssignments/00000000-0000-0000-0000-000000000059' -Condition "@Resource[a] StringEquals 'b'" -Confirm:$false
        Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-OERArmRequest -Times 1 -Exactly -ParameterFilter {
            $Method -eq 'PUT' -and $Body.properties.description -eq 'original description'
        }
    }

    # ARM rejects an empty conditionVersion outright ("The specified role assignment ConditionVersion
    # '' is not supported" -- observed live 2026-08-12), despite the REST docs saying an empty string
    # clears it. Because the PUT replaces the whole property bag, a condition is cleared by OMITTING
    # both keys. This test pins that wire shape; the mocked suite cannot otherwise catch it.
    It 'clears a condition by OMITTING both condition and conditionVersion, and warns' {
        Mock -ModuleName Omnicit.EntraRBAC Invoke-OERArmRequest {
            [PSCustomObject]@{
                id   = '/subscriptions/s/providers/Microsoft.Authorization/roleAssignments/00000000-0000-0000-0000-000000000059'
                name = '00000000-0000-0000-0000-000000000059'
                properties = [PSCustomObject]@{
                    roleDefinitionId = '/r'; principalId = 'p'; principalType = 'Group'
                    condition = "@Resource[y] StringEquals 'z'"; conditionVersion = '2.0'
                }
            }
        }
        $Warnings = @()
        Set-OERRoleAssignment -Id '/subscriptions/s/providers/Microsoft.Authorization/roleAssignments/00000000-0000-0000-0000-000000000059' -Condition '' -Confirm:$false -WarningVariable Warnings -WarningAction SilentlyContinue
        $Warnings.Count | Should -BeGreaterThan 0
        Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-OERArmRequest -Times 1 -Exactly -ParameterFilter {
            $Method -eq 'PUT' -and
            -not $Body.properties.ContainsKey('condition') -and
            -not $Body.properties.ContainsKey('conditionVersion') -and
            $Body.properties.roleDefinitionId -eq '/r' -and
            $Body.properties.principalId -eq 'p'
        }
    }

    It 'defaults conditionVersion to 2.0 for a new condition on an assignment that had none' {
        Mock -ModuleName Omnicit.EntraRBAC Invoke-OERArmRequest {
            [PSCustomObject]@{
                id = '/subscriptions/s/providers/Microsoft.Authorization/roleAssignments/00000000-0000-0000-0000-000000000059'
                name = '00000000-0000-0000-0000-000000000059'
                properties = [PSCustomObject]@{
                    roleDefinitionId = '/r'; principalId = 'p'; principalType = 'User'
                }
            }
        }
        Set-OERRoleAssignment -Id '/subscriptions/s/providers/Microsoft.Authorization/roleAssignments/00000000-0000-0000-0000-000000000059' -Condition "@Resource[a] StringEquals 'b'" -Confirm:$false
        Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-OERArmRequest -Times 1 -Exactly -ParameterFilter {
            $Method -eq 'PUT' -and $Body.properties.conditionVersion -eq '2.0'
        }
    }

    # The combination Sync-OERStructureRoleAssignment produces when a document declares condition,
    # conditionVersion and description together -- the only integration path that matters.
    It 'sends both -Condition and -ConditionVersion when they are bound together' {
        Mock -ModuleName Omnicit.EntraRBAC Invoke-OERArmRequest {
            [PSCustomObject]@{
                id   = '/subscriptions/s/providers/Microsoft.Authorization/roleAssignments/00000000-0000-0000-0000-000000000059'
                name = '00000000-0000-0000-0000-000000000059'
                properties = [PSCustomObject]@{
                    roleDefinitionId = '/r'; principalId = 'p'; principalType = 'Group'
                    description = 'original description'
                    condition = "@Resource[old] StringEquals 'old'"; conditionVersion = '1.0'
                }
            }
        }
        Set-OERRoleAssignment -Id '/subscriptions/s/providers/Microsoft.Authorization/roleAssignments/00000000-0000-0000-0000-000000000059' `
            -Condition "@Resource[new] StringEquals 'new'" -ConditionVersion '2.0' -Description 'new description' -Confirm:$false
        Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-OERArmRequest -Times 1 -Exactly -ParameterFilter {
            $Method -eq 'PUT' -and
            $Body.properties.condition -eq "@Resource[new] StringEquals 'new'" -and
            $Body.properties.conditionVersion -eq '2.0' -and
            $Body.properties.description -eq 'new description'
        }
    }

    It 'errors when -ConditionVersion is supplied but no condition exists' {
        Mock -ModuleName Omnicit.EntraRBAC Invoke-OERArmRequest {
            [PSCustomObject]@{
                id = '/subscriptions/s/providers/Microsoft.Authorization/roleAssignments/00000000-0000-0000-0000-000000000059'
                name = 'n'
                properties = [PSCustomObject]@{ roleDefinitionId = '/r'; principalId = 'p' }
            }
        }
        { Set-OERRoleAssignment -Id '/subscriptions/s/providers/Microsoft.Authorization/roleAssignments/00000000-0000-0000-0000-000000000059' -ConditionVersion '2.0' -Confirm:$false -ErrorAction Stop } |
            Should -Throw -ErrorId 'ConditionVersionWithoutCondition,Set-OERRoleAssignment'
    }

    It 'still binds -ConditionVersion 1.0 (task-2: this cmdlet is deliberately EXCLUDED from the 2.0 ValidateSet)' {
        # The create cmdlets (New-OERRoleAssignment/New-OERActiveRoleAssignment/New-OEREligibleRoleAssignment)
        # gained [ValidateSet('2.0')] on -ConditionVersion. Set-OERRoleAssignment is read-modify-write
        # and its own help documents the 1.0 -> 2.0 upgrade path, so constraining it would block editing
        # a legacy assignment -- it must keep accepting '1.0'.
        Mock -ModuleName Omnicit.EntraRBAC Invoke-OERArmRequest {
            [PSCustomObject]@{
                id   = '/subscriptions/s/providers/Microsoft.Authorization/roleAssignments/00000000-0000-0000-0000-000000000059'
                name = '00000000-0000-0000-0000-000000000059'
                properties = [PSCustomObject]@{
                    roleDefinitionId = '/r'; principalId = 'p'; principalType = 'Group'
                    condition = "@Resource[old] StringEquals 'old'"; conditionVersion = '1.0'
                }
            }
        }
        Set-OERRoleAssignment -Id '/subscriptions/s/providers/Microsoft.Authorization/roleAssignments/00000000-0000-0000-0000-000000000059' `
            -Condition "@Resource[old] StringEquals 'old'" -ConditionVersion '1.0' -Confirm:$false
        Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-OERArmRequest -Times 1 -Exactly -ParameterFilter {
            $Method -eq 'PUT' -and $Body.properties.conditionVersion -eq '1.0'
        }
    }

    It 'emits RoleAssignmentNotFound when the read returns nothing' {
        Mock -ModuleName Omnicit.EntraRBAC Invoke-OERArmRequest { $null }
        { Set-OERRoleAssignment -Id '/subscriptions/s/providers/Microsoft.Authorization/roleAssignments/00000000-0000-0000-0000-000000000059' -Description 'x' -Confirm:$false -ErrorAction Stop } |
            Should -Throw -ErrorId 'RoleAssignmentNotFound,Set-OERRoleAssignment'
    }

    It 'honors -WhatIf (reads but never PUTs)' {
        Mock -ModuleName Omnicit.EntraRBAC Invoke-OERArmRequest {
            [PSCustomObject]@{
                id = '/subscriptions/s/providers/Microsoft.Authorization/roleAssignments/00000000-0000-0000-0000-000000000059'
                name = 'n'
                properties = [PSCustomObject]@{ roleDefinitionId = '/r'; principalId = 'p'; principalType = 'Group' }
            }
        }
        Set-OERRoleAssignment -Id '/subscriptions/s/providers/Microsoft.Authorization/roleAssignments/00000000-0000-0000-0000-000000000059' -Description 'x' -WhatIf
        Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-OERArmRequest -Times 0 -Exactly -ParameterFilter {
            $Method -eq 'PUT'
        }
        Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-OERArmRequest -Times 1 -Exactly -ParameterFilter {
            $Method -ne 'PUT'
        }
    }

    It 'emits RoleAssignmentNotFound (non-terminating) when the PUT response is null' {
        Mock -ModuleName Omnicit.EntraRBAC Invoke-OERArmRequest {
            if ($Method -eq 'PUT') { return $null }
            [PSCustomObject]@{
                id = '/subscriptions/s/providers/Microsoft.Authorization/roleAssignments/00000000-0000-0000-0000-000000000059'
                name = 'n'
                properties = [PSCustomObject]@{ roleDefinitionId = '/r'; principalId = 'p'; principalType = 'Group' }
            }
        }
        { Set-OERRoleAssignment -Id '/subscriptions/s/providers/Microsoft.Authorization/roleAssignments/00000000-0000-0000-0000-000000000059' -Description 'x' -Confirm:$false -ErrorAction Stop } |
            Should -Throw -ErrorId 'RoleAssignmentNotFound,Set-OERRoleAssignment'
    }

    It 'returns a tagged RoleAssignment object' {
        Mock -ModuleName Omnicit.EntraRBAC Invoke-OERArmRequest {
            [PSCustomObject]@{
                id = '/subscriptions/s/providers/Microsoft.Authorization/roleAssignments/00000000-0000-0000-0000-000000000059'
                name = '00000000-0000-0000-0000-000000000059'
                properties = [PSCustomObject]@{ roleDefinitionId = '/r'; principalId = 'p'; principalType = 'Group' }
            }
        }
        $Out = Set-OERRoleAssignment -Id '/subscriptions/s/providers/Microsoft.Authorization/roleAssignments/00000000-0000-0000-0000-000000000059' -Description 'x' -Confirm:$false
        $Out.PSObject.TypeNames[0] | Should -Be 'Omnicit.EntraRBAC.RoleAssignment'
    }

    It 'binds -Id from piped Get-OERRoleAssignment output' {
        Mock -ModuleName Omnicit.EntraRBAC Invoke-OERArmRequest {
            [PSCustomObject]@{
                id = '/subscriptions/s/providers/Microsoft.Authorization/roleAssignments/00000000-0000-0000-0000-000000000059'
                name = '00000000-0000-0000-0000-000000000059'
                properties = [PSCustomObject]@{ roleDefinitionId = '/r'; principalId = 'p'; principalType = 'Group' }
            }
        }
        [PSCustomObject]@{ RoleAssignmentId = '/subscriptions/s/providers/Microsoft.Authorization/roleAssignments/00000000-0000-0000-0000-000000000059' } |
            Set-OERRoleAssignment -Description 'piped' -Confirm:$false
        Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-OERArmRequest -Times 1 -Exactly -ParameterFilter {
            $Method -eq 'PUT' -and $Body.properties.description -eq 'piped'
        }
    }

    It 'scrubs the bearer-hygiene record when the ARM PUT fails' {
        # CLAUDE.md SECURITY rule 6. Drives the WRITE-side transport catch at
        # source/Public/Set-OERRoleAssignment.ps1:179, not the read-modify-write GET catch at :107.
        # The unfiltered behaviour answers the GET (that call carries no -Method); the PUT-filtered
        # behaviour is what throws, so this cannot be satisfied by the read catch instead.
        Mock -ModuleName Omnicit.EntraRBAC Invoke-OERArmRequest -ParameterFilter { $Method -eq 'PUT' } { throw 'transport failure' }
        Mock -ModuleName Omnicit.EntraRBAC Invoke-OERArmRequest {
            [PSCustomObject]@{
                id = '/subscriptions/s/providers/Microsoft.Authorization/roleAssignments/00000000-0000-0000-0000-000000000059'
                name = '00000000-0000-0000-0000-000000000059'
                properties = [PSCustomObject]@{ roleDefinitionId = '/r'; principalId = 'p'; principalType = 'Group' }
            }
        }
        Mock -ModuleName Omnicit.EntraRBAC Remove-OERErrorRecord { }
        $null = Set-OERRoleAssignment -Id '/subscriptions/s/providers/Microsoft.Authorization/roleAssignments/00000000-0000-0000-0000-000000000059' -Description 'x' -Confirm:$false -ErrorAction SilentlyContinue
        Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-OERArmRequest -Times 1 -ParameterFilter { $Method -eq 'PUT' }
        Should -Invoke -ModuleName Omnicit.EntraRBAC Remove-OERErrorRecord -Times 1
    }
}
