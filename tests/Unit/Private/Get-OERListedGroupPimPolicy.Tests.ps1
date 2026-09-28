BeforeAll {
    $script:moduleName = 'Omnicit.EntraRBAC'
    Get-Module $script:moduleName | Remove-Module -Force -ErrorAction SilentlyContinue
    Import-Module $script:moduleName -Force -ErrorAction Stop
}

Describe 'Get-OERListedGroupPimPolicy' {
    # Measured live 2026-09-28: a policy the assignment query has just listed for a new group can
    # answer its rules read with 404 ResourceNotFound a second later. Only the apply engine's wait for a
    # group created in the same run calls this helper; Get-OERGroupPimPolicy keeps its own read.
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

    It 'reads the rules of the listed policy id and declares ResourceNotFound on the request' {
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest { @{ value = @() } }
        InModuleScope $script:moduleName {
            $null = Get-OERListedGroupPimPolicy -GroupId 'g1' -PolicyId 'pol-member' -AccessType 'member'
        }
        Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 1 -Exactly -ParameterFilter {
            $Uri -like '*policies/roleManagementPolicies/pol-member/rules' -and $All -and
            @($ExpectedErrorCode) -contains 'ResourceNotFound'
        }
    }

    It 'projects the rules through the shared converter, stamped with the group, policy and access type' {
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {
            @{ value = @(
                    @{ id = 'Expiration_EndUser_Assignment'; maximumDuration = 'PT3H' }
                    @{ id = 'Approval_EndUser_Assignment'; setting = @{ isApprovalRequired = $true; approvalStages = @() } }
                ) }
        }
        InModuleScope $script:moduleName {
            $Out = Get-OERListedGroupPimPolicy -GroupId 'g1' -PolicyId 'pol-owner' -AccessType 'owner'
            @($Out.PSObject.TypeNames) | Should -Contain 'Omnicit.EntraRBAC.GroupPimPolicy'
            $Out.GroupId | Should -Be 'g1'
            $Out.PolicyId | Should -Be 'pol-owner'
            $Out.AccessType | Should -Be 'owner'
            $Out.ActivationMaxHours | Should -Be 3
            $Out.RequireApproval | Should -BeTrue
        }
    }

    It 'returns $null for a 404 ResourceNotFound, with no error record and a verbose line' {
        InModuleScope $script:moduleName {
            Mock Invoke-OERGraphRequest { & $script:NotFoundMarker -Status 404 }
            $Err = $null
            $Out = @(Get-OERListedGroupPimPolicy -GroupId 'g1' -PolicyId 'pol-member' -AccessType 'member' `
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
            { Get-OERListedGroupPimPolicy -GroupId 'g1' -PolicyId 'pol-member' -AccessType 'member' } |
                Should -Throw -ErrorId 'ResourceNotFound'
        }
    }

    It 'still throws a refusal' {
        InModuleScope $script:moduleName {
            Mock Invoke-OERGraphRequest {
                throw [System.Management.Automation.ErrorRecord]::new(
                    [System.Exception]::new('Authorization_RequestDenied: Insufficient privileges'),
                    'Authorization_RequestDenied',
                    [System.Management.Automation.ErrorCategory]::PermissionDenied, $null)
            }
            { Get-OERListedGroupPimPolicy -GroupId 'g1' -PolicyId 'pol-member' -AccessType 'member' } |
                Should -Throw -ErrorId 'Authorization_RequestDenied'
        }
    }
}
