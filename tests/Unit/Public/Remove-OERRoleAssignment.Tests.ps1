BeforeAll {
    Import-Module Omnicit.EntraRBAC -Force
}

Describe 'Remove-OERRoleAssignment' {
    BeforeEach {
        InModuleScope Omnicit.EntraRBAC { $script:_OERAuthState = $null }
        Mock -ModuleName Omnicit.EntraRBAC Initialize-OERAuth { }
    }

    It 'rejects an id that is not a role assignment resource id' {
        { Remove-OERRoleAssignment -Id '/subscriptions/abc' -Confirm:$false -ErrorAction Stop } |
            Should -Throw -ErrorId 'InvalidRoleAssignmentId,Remove-OERRoleAssignment'
    }

    It 'DELETEs the full id with the pinned api-version and warns' {
        Mock -ModuleName Omnicit.EntraRBAC Invoke-OERArmRequest {
            [PSCustomObject]@{
                id = '/subscriptions/s/providers/Microsoft.Authorization/roleAssignments/00000000-0000-0000-0000-000000000059'
                name = '00000000-0000-0000-0000-000000000059'
                properties = [PSCustomObject]@{ principalId = 'p'; principalType = 'User'; roleDefinitionId = 'r'; scope = '/subscriptions/s' }
            }
        }
        $Warnings = @()
        Remove-OERRoleAssignment `
            -Id '/subscriptions/s/providers/Microsoft.Authorization/roleAssignments/00000000-0000-0000-0000-000000000059' `
            -Confirm:$false -WarningVariable Warnings -WarningAction SilentlyContinue
        $Warnings.Count | Should -BeGreaterThan 0
        Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-OERArmRequest -Times 1 -Exactly -ParameterFilter {
            $Method -eq 'DELETE' -and
            $Path -eq '/subscriptions/s/providers/Microsoft.Authorization/roleAssignments/00000000-0000-0000-0000-000000000059?api-version=2022-04-01'
        }
    }

    It 'treats a 204 (null response) as RoleAssignmentNotFound' {
        Mock -ModuleName Omnicit.EntraRBAC Invoke-OERArmRequest { $null }
        { Remove-OERRoleAssignment `
            -Id '/subscriptions/s/providers/Microsoft.Authorization/roleAssignments/00000000-0000-0000-0000-000000000059' `
            -Confirm:$false -WarningAction SilentlyContinue -ErrorAction Stop } |
            Should -Throw -ErrorId 'RoleAssignmentNotFound,Remove-OERRoleAssignment'
    }

    It 'returns the deleted object only with -PassThru' {
        Mock -ModuleName Omnicit.EntraRBAC Invoke-OERArmRequest {
            [PSCustomObject]@{
                id = '/subscriptions/s/providers/Microsoft.Authorization/roleAssignments/00000000-0000-0000-0000-000000000059'
                name = '00000000-0000-0000-0000-000000000059'
                properties = [PSCustomObject]@{ principalId = 'p' }
            }
        }
        $Silent = Remove-OERRoleAssignment -Id '/subscriptions/s/providers/Microsoft.Authorization/roleAssignments/00000000-0000-0000-0000-000000000059' -Confirm:$false -WarningAction SilentlyContinue
        $Silent | Should -BeNullOrEmpty
        $Out = Remove-OERRoleAssignment -Id '/subscriptions/s/providers/Microsoft.Authorization/roleAssignments/00000000-0000-0000-0000-000000000059' -Confirm:$false -PassThru -WarningAction SilentlyContinue
        $Out.PSObject.TypeNames[0] | Should -Be 'Omnicit.EntraRBAC.RoleAssignment'
    }

    It 'honors -WhatIf (no ARM call)' {
        Mock -ModuleName Omnicit.EntraRBAC Invoke-OERArmRequest { }
        Remove-OERRoleAssignment `
            -Id '/subscriptions/s/providers/Microsoft.Authorization/roleAssignments/00000000-0000-0000-0000-000000000059' `
            -WhatIf
        Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-OERArmRequest -Times 0 -Exactly
    }

    It 'binds -Id from piped Get-OERRoleAssignment output and processes multiple items' {
        Mock -ModuleName Omnicit.EntraRBAC Invoke-OERArmRequest {
            [PSCustomObject]@{ id = '/x/providers/Microsoft.Authorization/roleAssignments/n'; name = 'n'; properties = [PSCustomObject]@{} }
        }
        $Items = @(
            [PSCustomObject]@{ RoleAssignmentId = '/subscriptions/s/providers/Microsoft.Authorization/roleAssignments/a1111111-0000-0000-0000-000000000001' }
            [PSCustomObject]@{ RoleAssignmentId = '/subscriptions/s/providers/Microsoft.Authorization/roleAssignments/a2222222-0000-0000-0000-000000000002' }
        )
        $Items | Remove-OERRoleAssignment -Confirm:$false -WarningAction SilentlyContinue
        Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-OERArmRequest -Times 2 -Exactly -ParameterFilter { $Method -eq 'DELETE' }
    }

    It 'scrubs the bearer-hygiene record when the ARM DELETE fails' {
        # CLAUDE.md SECURITY rule 6. Drives the transport catch at
        # source/Public/Remove-OERRoleAssignment.ps1:63 -- the cmdlet's only catch.
        Mock -ModuleName Omnicit.EntraRBAC Invoke-OERArmRequest { throw 'transport failure' }
        Mock -ModuleName Omnicit.EntraRBAC Remove-OERErrorRecord { }
        $null = Remove-OERRoleAssignment -Id '/subscriptions/s/providers/Microsoft.Authorization/roleAssignments/00000000-0000-0000-0000-000000000059' -Confirm:$false -WarningAction SilentlyContinue -ErrorAction SilentlyContinue
        Should -Invoke -ModuleName Omnicit.EntraRBAC Remove-OERErrorRecord -Times 1
    }
}
