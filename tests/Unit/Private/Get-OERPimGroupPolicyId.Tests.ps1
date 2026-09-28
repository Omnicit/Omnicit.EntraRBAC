BeforeAll {
    $script:moduleName = 'Omnicit.EntraRBAC'
    Get-Module $script:moduleName | Remove-Module -Force -ErrorAction SilentlyContinue
    Import-Module $script:moduleName -Force -ErrorAction Stop
}

Describe 'Get-OERPimGroupPolicyId' {
    It 'returns the policyId for the matching access type' {
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {
            @{ value = @(
                @{ policyId = 'pol-member'; roleDefinitionId = 'member' }
                @{ policyId = 'pol-owner';  roleDefinitionId = 'owner' }
            ) }
        }
        InModuleScope $script:moduleName {
            Get-OERPimGroupPolicyId -GroupId 'g1' -AccessType 'member' | Should -Be 'pol-member'
        }
    }

    It 'returns $null when no policy assignment exists' {
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest { @{ value = @() } }
        InModuleScope $script:moduleName {
            Get-OERPimGroupPolicyId -GroupId 'g1' | Should -BeNullOrEmpty
        }
    }

    It 'returns the owner policy when -AccessType owner is requested' {
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {
            @{ value = @(
                @{ policyId = 'pol-member'; roleDefinitionId = 'member' }
                @{ policyId = 'pol-owner';  roleDefinitionId = 'owner' }
            ) }
        }
        InModuleScope $script:moduleName {
            Get-OERPimGroupPolicyId -GroupId 'g1' -AccessType 'owner' | Should -Be 'pol-owner'
        }
    }

    It 'defaults to the member policy when -AccessType is omitted' {
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {
            @{ value = @(
                @{ policyId = 'pol-owner';  roleDefinitionId = 'owner' }
                @{ policyId = 'pol-member'; roleDefinitionId = 'member' }
            ) }
        }
        InModuleScope $script:moduleName {
            Get-OERPimGroupPolicyId -GroupId 'g1' | Should -Be 'pol-member'
        }
    }

    It 'returns $null when no assignment matches the requested access type' {
        # Get-OERPimGroupPolicyId.ps1:38. This helper is the sole policy-id resolver behind both
        # Get- and Set-OERGroupPimPolicy, so a regression here silently targets the wrong policy
        # and mis-applies high-privilege PIM rules.
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {
            @{ value = @(
                @{ policyId = 'pol-first';  roleDefinitionId = 'somethingElse' }
                @{ policyId = 'pol-second'; roleDefinitionId = 'alsoNotMember' }
            ) }
        }
        InModuleScope $script:moduleName {
            Get-OERPimGroupPolicyId -GroupId 'g1' -AccessType 'member' | Should -BeNullOrEmpty
        }
    }

    It 'returns $null for owner, never the member policy id, when only the member assignment exists' {
        # A no-match must never fall back to whatever assignment happens to be first: right after a
        # group is created, one access type's assignment can be listed before the other, and a
        # fallback here returned the MEMBER policy for an OWNER lookup (owner settings were then
        # written to the member policy with no error).
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {
            @{ value = @(
                @{ policyId = 'pol-member'; roleDefinitionId = 'member' }
            ) }
        }
        InModuleScope $script:moduleName {
            $Result = Get-OERPimGroupPolicyId -GroupId 'g1' -AccessType 'owner'
            $Result | Should -BeNullOrEmpty
            $Result | Should -Not -Be 'pol-member'
        }
    }

    It 'returns $null for member, never the owner policy id, when only the owner assignment exists' {
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {
            @{ value = @(
                @{ policyId = 'pol-owner'; roleDefinitionId = 'owner' }
            ) }
        }
        InModuleScope $script:moduleName {
            $Result = Get-OERPimGroupPolicyId -GroupId 'g1' -AccessType 'member'
            $Result | Should -BeNullOrEmpty
            $Result | Should -Not -Be 'pol-owner'
        }
    }

    It 'queries roleManagementPolicyAssignments scoped to the group and doubles an embedded quote' {
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest { @{ value = @() } }
        InModuleScope $script:moduleName {
            Get-OERPimGroupPolicyId -GroupId "g'1" | Out-Null
        }
        Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 1 -ParameterFilter {
            $Uri -eq "beta/policies/roleManagementPolicyAssignments?`$filter=scopeId eq 'g''1' and scopeType eq 'Group'"
        }
    }
}

Describe 'Get-OERPimGroupPolicyId not-onboarded contract' {
    It 'declares ResourceTypeNotSupported as an expected answer on the request' {
        # The code has to be declared at the REQUEST, not recognised in a catch afterwards.
        # -ErrorVariable is filled by the ENGINE and collects records raised inside nested calls even
        # when an inner catch swallowed them, so the try/catch every caller already wraps this in
        # turned the throw back into $null only after the records had escaped.
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest { @{ value = @() } }
        InModuleScope $script:moduleName {
            $null = Get-OERPimGroupPolicyId -GroupId 'g1' -AccessType 'member'
        }
        Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 1 -Exactly -ParameterFilter {
            @($ExpectedErrorCode) -contains 'ResourceTypeNotSupported'
        }
    }

    It 'returns $null, without raising, when the transport answers with the expected marker' {
        InModuleScope $script:moduleName {
            Mock Invoke-OERGraphRequest {
                $Marker = [PSCustomObject]@{
                    ExpectedErrorCode = 'ResourceTypeNotSupported'; StatusCode = 400
                    Message           = 'ResourceTypeNotSupported: Resource type not supported for onboarding'
                    Uri               = 'beta/x'
                }
                $Marker.PSObject.TypeNames.Insert(0, 'Omnicit.EntraRBAC.GraphExpectedError')
                $Marker
            }
            $Err = $null
            $Result = Get-OERPimGroupPolicyId -GroupId 'g1' -AccessType 'member' `
                -ErrorAction SilentlyContinue -ErrorVariable Err
            $Result | Should -BeNullOrEmpty
            @($Err).Count | Should -Be 0 -Because 'a group that was never onboarded is an answer, not a failure'
        }
    }

    It 'still surfaces a genuinely failed policy read' {
        # Only the declared code is softened. A 403 must keep reaching the caller's catch, which is
        # what makes the difference between "no policy" and "could not tell" visible.
        InModuleScope $script:moduleName {
            Mock Invoke-OERGraphRequest {
                throw [System.Management.Automation.ErrorRecord]::new(
                    [System.Exception]::new('Authorization_RequestDenied: Insufficient privileges'),
                    'Authorization_RequestDenied',
                    [System.Management.Automation.ErrorCategory]::PermissionDenied, $null)
            }
            { Get-OERPimGroupPolicyId -GroupId 'g1' -AccessType 'member' } |
                Should -Throw -ErrorId 'Authorization_RequestDenied'
        }
    }
}

Describe 'Get-OERPimGroupPolicyId -NotFoundAsUnlisted (the new-group wait)' {
    # Measured live 2026-09-28: a group PIM does not know yet answers the assignment query with 404
    # ResourceNotFound. Only the apply engine's wait for a group created in the same run passes this
    # switch; every other caller keeps the contract it always had, in which a 404 throws.
    BeforeEach {
        InModuleScope $script:moduleName {
            $script:NotFoundMarker = {
                param([int]$Status)
                $Marker = [PSCustomObject]@{
                    ExpectedErrorCode = 'ResourceNotFound'; StatusCode = $Status
                    Message           = 'ResourceNotFound: The resource is not found.'
                    Uri               = 'beta/x'
                }
                $Marker.PSObject.TypeNames.Insert(0, 'Omnicit.EntraRBAC.GraphExpectedError')
                $Marker
            }
        }
    }

    It 'declares ResourceNotFound on the request only when the switch is set' {
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest { @{ value = @() } }
        InModuleScope $script:moduleName {
            $null = Get-OERPimGroupPolicyId -GroupId 'g1' -AccessType 'member'
            $null = Get-OERPimGroupPolicyId -GroupId 'g1' -AccessType 'member' -NotFoundAsUnlisted
        }
        Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 1 -Exactly -ParameterFilter {
            @($ExpectedErrorCode) -contains 'ResourceNotFound'
        }
        Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 2 -Exactly -ParameterFilter {
            @($ExpectedErrorCode) -contains 'ResourceTypeNotSupported'
        }
    }

    It 'returns $null for a 404 ResourceNotFound, with no error record and a verbose line' {
        InModuleScope $script:moduleName {
            Mock Invoke-OERGraphRequest { & $script:NotFoundMarker -Status 404 }
            $Err = $null
            $Out = @(Get-OERPimGroupPolicyId -GroupId 'g1' -AccessType 'member' -NotFoundAsUnlisted `
                    -ErrorAction SilentlyContinue -ErrorVariable Err -Verbose 4>&1)
            # 'return $null' emits one $null element; nothing else may come out besides the verbose line.
            @($Out | Where-Object { $null -ne $_ -and $_ -isnot [System.Management.Automation.VerboseRecord] }).Count | Should -Be 0
            @($Out | Where-Object { $_ -is [System.Management.Automation.VerboseRecord] -and $_.Message -match '404 ResourceNotFound' }).Count | Should -Be 1
            @($Err).Count | Should -Be 0
        }
    }

    It 'still throws ResourceNotFound that did not come with a 404' {
        InModuleScope $script:moduleName {
            Mock Invoke-OERGraphRequest { & $script:NotFoundMarker -Status 400 }
            { Get-OERPimGroupPolicyId -GroupId 'g1' -AccessType 'member' -NotFoundAsUnlisted } |
                Should -Throw -ErrorId 'ResourceNotFound'
        }
    }

    It 'still throws a 404 for a caller that does not pass the switch' {
        InModuleScope $script:moduleName {
            Mock Invoke-OERGraphRequest {
                throw [System.Management.Automation.ErrorRecord]::new(
                    [System.Exception]::new('ResourceNotFound: The resource is not found.'),
                    'ResourceNotFound',
                    [System.Management.Automation.ErrorCategory]::OperationStopped, $null)
            }
            { Get-OERPimGroupPolicyId -GroupId 'g1' -AccessType 'member' } | Should -Throw -ErrorId 'ResourceNotFound'
        }
    }

    It 'still throws a refusal with the switch set' {
        InModuleScope $script:moduleName {
            Mock Invoke-OERGraphRequest {
                throw [System.Management.Automation.ErrorRecord]::new(
                    [System.Exception]::new('Authorization_RequestDenied: Insufficient privileges'),
                    'Authorization_RequestDenied',
                    [System.Management.Automation.ErrorCategory]::PermissionDenied, $null)
            }
            { Get-OERPimGroupPolicyId -GroupId 'g1' -AccessType 'member' -NotFoundAsUnlisted } |
                Should -Throw -ErrorId 'Authorization_RequestDenied'
        }
    }
}
