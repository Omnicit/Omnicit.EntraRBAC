BeforeAll {
    $script:moduleName = 'Omnicit.EntraRBAC'
    Get-Module $script:moduleName | Remove-Module -Force -ErrorAction SilentlyContinue
    Import-Module $script:moduleName -Force -ErrorAction Stop
}

Describe 'Set-OERGroup' {
    BeforeEach {
        InModuleScope $script:moduleName { $script:_OERAuthState = $null }
        Mock -ModuleName $script:moduleName Initialize-OERAuth {}
        Mock -ModuleName $script:moduleName Resolve-OERGroupId { 'gid-1' }
    }

    It 'patches the description' {
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {
            @{ id = 'gid-1'; displayName = 'role_sec_team'; description = 'new desc'; securityEnabled = $true; isAssignableToRole = $false; groupTypes = @() }
        } -ParameterFilter { $Uri -eq 'v1.0/groups/gid-1' -and ($Method -eq 'GET' -or -not $Method) }
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {} -ParameterFilter { $Method -eq 'PATCH' }
        Set-OERGroup -Id 'gid-1' -Description 'new desc' | Out-Null
        Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 1 -ParameterFilter {
            $Method -eq 'PATCH' -and $Uri -eq 'v1.0/groups/gid-1' -and $Body.description -eq 'new desc'
        }
    }

    It 'errors when the group cannot be resolved' {
        Mock -ModuleName $script:moduleName Resolve-OERGroupId { $null }
        Set-OERGroup -DisplayName 'missing' -Description 'x' -ErrorVariable err -ErrorAction SilentlyContinue | Out-Null
        $err.FullyQualifiedErrorId | Should -Match 'GroupNotFound'
    }

    It 'does not PATCH under -WhatIf' {
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {}
        Set-OERGroup -Id 'gid-1' -Description 'x' -WhatIf | Out-Null
        Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 0 -ParameterFilter { $Method -eq 'PATCH' }
    }

    It 'errors NothingToUpdate when no updatable property is supplied' {
        Set-OERGroup -Id 'gid-1' -ErrorVariable Err -ErrorAction SilentlyContinue | Out-Null
        # Cmdlet-qualified: a bare-code match passes even with the WriteError deleted, because the
        # engine re-records a thrown record into -ErrorVariable at every call boundary it crosses.
        @($Err | Where-Object { $_.FullyQualifiedErrorId -eq 'NothingToUpdate,Set-OERGroup' }).Count | Should -Be 1
    }

    It 'errors with NotDynamicGroup when -MembershipRule targets a static group' {
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {
            @{ id = 'gid-1'; groupTypes = @() }
        } -ParameterFilter { $Method -ne 'PATCH' }
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {} -ParameterFilter { $Method -eq 'PATCH' }
        Set-OERGroup -Id 'gid-1' -MembershipRule '(user.department -eq "IT")' -ErrorVariable err -ErrorAction SilentlyContinue | Out-Null
        $err.FullyQualifiedErrorId | Should -Match 'NotDynamicGroup'
        Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 0 -ParameterFilter { $Method -eq 'PATCH' }
    }

    It 'patches the membership rule on a dynamic group' {
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {
            @{ id = 'gid-1'; displayName = 'dyn'; securityEnabled = $true; isAssignableToRole = $false
                groupTypes = @('DynamicMembership'); membershipRule = '(user.department -eq "IT")' }
        } -ParameterFilter { $Method -ne 'PATCH' }
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {} -ParameterFilter { $Method -eq 'PATCH' }
        Set-OERGroup -Id 'gid-1' -MembershipRule '(user.department -eq "IT")' | Out-Null
        Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 1 -ParameterFilter {
            $Method -eq 'PATCH' -and $Body.membershipRule -eq '(user.department -eq "IT")'
        }
    }

    It 'accepts the group id from the pipeline by property name (Get-OERGroup | Set-OERGroup)' {
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {
            @{ id = 'gid-1'; displayName = 'g'; securityEnabled = $true; isAssignableToRole = $false; groupTypes = @() }
        } -ParameterFilter { $Method -ne 'PATCH' }
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {} -ParameterFilter { $Method -eq 'PATCH' }
        [pscustomobject]@{ Id = 'gid-1' } | Set-OERGroup -Description 'piped' | Out-Null
        Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 1 -ParameterFilter {
            $Method -eq 'PATCH' -and $Uri -eq 'v1.0/groups/gid-1' -and $Body.description -eq 'piped'
        }
    }

    It 'accepts -DisplayName from the pipeline by property name (name-only object | Set-OERGroup)' {
        Mock -ModuleName $script:moduleName Resolve-OERGroupId { 'gid-2' }
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {
            @{ id = 'gid-2'; displayName = 'role_sec_x'; securityEnabled = $true; isAssignableToRole = $false; groupTypes = @() }
        } -ParameterFilter { $Method -ne 'PATCH' }
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {} -ParameterFilter { $Method -eq 'PATCH' }
        [pscustomobject]@{ DisplayName = 'role_sec_x' } | Set-OERGroup -Description 'by-name' | Out-Null
        Should -Invoke -ModuleName $script:moduleName Resolve-OERGroupId -Times 1 -ParameterFilter {
            $DisplayName -eq 'role_sec_x'
        }
        Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 1 -ParameterFilter {
            $Method -eq 'PATCH' -and $Body.description -eq 'by-name'
        }
    }

    It 'scrubs the bearer-hygiene record when the PATCH fails' {
        # Drives the update catch in source/Public/Set-OERGroup.ps1 (the PATCH + read-back try
        # inside ShouldProcess). Only -Description is supplied, so the membership-rule pre-read
        # branch is skipped and the mocked transport failure lands in that catch. CLAUDE.md
        # SECURITY rule 6 makes Remove-OERErrorRecord -Record $PSItem its mandatory first statement.
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest { throw 'transport failure' }
        Mock -ModuleName $script:moduleName Remove-OERErrorRecord { }
        Set-OERGroup -Group 'gid-1' -Description 'x' -Confirm:$false -ErrorAction SilentlyContinue | Out-Null
        Should -Invoke -ModuleName $script:moduleName Remove-OERErrorRecord -Times 1
    }

    Context 'unified -Group target (audit PR6)' {
        It 'updates a group addressed by -Group display name' {
            Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {
                @{ id = 'gid-1'; displayName = 'role_sec_identity_administrator'; securityEnabled = $true; isAssignableToRole = $false; groupTypes = @() }
            } -ParameterFilter { $Method -ne 'PATCH' }
            Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {} -ParameterFilter { $Method -eq 'PATCH' }
            Set-OERGroup -Group 'role_sec_identity_administrator' -Description 'Updated' -Confirm:$false | Out-Null
            Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 1 -ParameterFilter {
                $Method -eq 'PATCH' -and $Body.description -eq 'Updated'
            }
        }
        It 'still binds the historical -Id parameter name' {
            Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {
                @{ id = 'gid-1'; displayName = 'g'; securityEnabled = $true; isAssignableToRole = $false; groupTypes = @() }
            } -ParameterFilter { $Method -ne 'PATCH' }
            Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {} -ParameterFilter { $Method -eq 'PATCH' }
            Set-OERGroup -Id '11111111-1111-1111-1111-111111111111' -Description 'Updated' -Confirm:$false | Out-Null
            Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 1 -ParameterFilter { $Method -eq 'PATCH' }
        }
        It 'still binds the historical -DisplayName parameter name' {
            Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {
                @{ id = 'gid-1'; displayName = 'role_sec_identity_administrator'; securityEnabled = $true; isAssignableToRole = $false; groupTypes = @() }
            } -ParameterFilter { $Method -ne 'PATCH' }
            Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {} -ParameterFilter { $Method -eq 'PATCH' }
            Set-OERGroup -DisplayName 'role_sec_identity_administrator' -Description 'Updated' -Confirm:$false | Out-Null
            Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 1 -ParameterFilter { $Method -eq 'PATCH' }
        }
        It 'binds a piped group object' {
            Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {
                @{ id = 'gid-1'; displayName = 'g'; securityEnabled = $true; isAssignableToRole = $false; groupTypes = @() }
            } -ParameterFilter { $Method -ne 'PATCH' }
            Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {} -ParameterFilter { $Method -eq 'PATCH' }
            [PSCustomObject]@{ Id = '11111111-1111-1111-1111-111111111111' } |
                Set-OERGroup -Description 'Updated' -Confirm:$false | Out-Null
            Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 1 -ParameterFilter { $Method -eq 'PATCH' }
        }
    }
}
