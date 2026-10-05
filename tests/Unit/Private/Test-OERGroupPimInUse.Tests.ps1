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

Describe 'Test-OERGroupPimInUse' {
    # The single owner of "does this group use PIM for Groups". Microsoft Graph lists PIM-for-Groups
    # policies for every group, so a listed policy is NOT evidence of use; a modified one is. An
    # untouched group policy reads lastModifiedDateTime null and a lastModifiedBy whose id and
    # displayName are null (Microsoft Learn, "List roleManagementPolicies"). Not proven until the
    # step 5 live checklist measures it -- see docs/development/rationale.md#pim-in-use-criterion.

    It 'answers in use from the eligibility count alone, with no request' {
        InModuleScope $script:moduleName {
            Mock Invoke-OERGraphRequest { throw 'should not be called' }
            $Usage = Test-OERGroupPimInUse -GroupId '11111111-1111-1111-1111-111111111111' -EligibilityCount 2
            $Usage.InUse | Should -BeTrue
            $Usage.Reason | Should -Be 'the group has PIM eligibility'
            $Usage.Manageable | Should -BeTrue
            $Usage.PSObject.TypeNames[0] | Should -Be 'Omnicit.EntraRBAC.GroupPimUsage'
            Should -Invoke Invoke-OERGraphRequest -Times 0
        }
    }

    It 'answers not in use when every listed policy is untouched' {
        # Two policies (member and owner), both exactly as Learn shows an untouched group policy.
        # This is the case the whole helper exists for: a group whose policies Graph lists although
        # nothing ever used it with PIM for Groups.
        InModuleScope $script:moduleName {
            Mock Invoke-OERGraphRequest {
                @{ value = @(
                        @{ id = 'Group_1_member'; lastModifiedDateTime = $null; lastModifiedBy = @{ id = $null; displayName = $null } }
                        @{ id = 'Group_1_owner'; lastModifiedDateTime = $null; lastModifiedBy = @{ id = $null; displayName = $null } }
                    )
                }
            }
            $Usage = Test-OERGroupPimInUse -GroupId '11111111-1111-1111-1111-111111111111'
            $Usage.InUse | Should -BeFalse
            $Usage.Reason | Should -Match 'no PIM policy of the group has been modified'
            $Usage.Manageable | Should -BeTrue
            $Usage.PSObject.TypeNames[0] | Should -Be 'Omnicit.EntraRBAC.GroupPimUsage'
            Should -Invoke Invoke-OERGraphRequest -Times 1 -Exactly
        }
    }

    It 'answers not in use when -EligibilityCount is 0 and Graph lists no policy at all' {
        InModuleScope $script:moduleName {
            Mock Invoke-OERGraphRequest { @{ value = @() } }
            (Test-OERGroupPimInUse -GroupId '11111111-1111-1111-1111-111111111111' -EligibilityCount 0).InUse | Should -BeFalse
        }
    }

    It 'answers in use when one policy carries a lastModifiedDateTime' {
        InModuleScope $script:moduleName {
            Mock Invoke-OERGraphRequest {
                @{ value = @(
                        @{ id = 'Group_1_member'; lastModifiedDateTime = $null; lastModifiedBy = @{ id = $null; displayName = $null } }
                        @{ id = 'Group_1_owner'; lastModifiedDateTime = '2026-01-01T00:00:00Z'; lastModifiedBy = @{ id = $null; displayName = $null } }
                    )
                }
            }
            $Usage = Test-OERGroupPimInUse -GroupId '11111111-1111-1111-1111-111111111111'
            $Usage.InUse | Should -BeTrue
            $Usage.Reason | Should -Be 'a PIM policy of the group has been modified'
        }
    }

    It 'answers in use when one policy carries only a lastModifiedBy displayName' {
        # Learn's modified example carries a displayName with a NULL id, so the id alone is not
        # enough to recognise a modified policy.
        InModuleScope $script:moduleName {
            Mock Invoke-OERGraphRequest {
                @{ value = @(
                        @{ id = 'Group_1_member'; lastModifiedDateTime = $null; lastModifiedBy = @{ id = $null; displayName = 'Person One' } }
                    )
                }
            }
            (Test-OERGroupPimInUse -GroupId '11111111-1111-1111-1111-111111111111').InUse | Should -BeTrue
        }
    }

    It 'answers in use when one policy carries only a lastModifiedBy id' {
        InModuleScope $script:moduleName {
            Mock Invoke-OERGraphRequest {
                @{ value = @(
                        @{ id = 'Group_1_member'; lastModifiedDateTime = $null; lastModifiedBy = @{ id = '22222222-2222-2222-2222-222222222222'; displayName = $null } }
                    )
                }
            }
            (Test-OERGroupPimInUse -GroupId '11111111-1111-1111-1111-111111111111').InUse | Should -BeTrue
        }
    }

    It 'lists the policies through Get-OERPimGroupsGraphPath, scoped to the group, in one paged request' {
        InModuleScope $script:moduleName {
            Mock Invoke-OERGraphRequest { @{ value = @() } }
            $null = Test-OERGroupPimInUse -GroupId '11111111-1111-1111-1111-111111111111'
            $Prefix = Get-OERPimGroupsGraphPath -Path 'policies/'
            Should -Invoke Invoke-OERGraphRequest -Times 1 -Exactly -ParameterFilter {
                $Uri.StartsWith($Prefix + 'roleManagementPolicies?') -and
                $Uri -match [regex]::Escape("scopeId eq '11111111-1111-1111-1111-111111111111'") -and
                $Uri -match [regex]::Escape("scopeType eq 'Group'") -and
                $Uri -match [regex]::Escape('$select=id,lastModifiedDateTime,lastModifiedBy') -and
                $All -eq $true -and
                @($ExpectedErrorCode) -contains 'ResourceNotFound' -and
                @($ExpectedErrorCode) -contains 'ResourceTypeNotSupported'
            }
        }
    }

    It 'answers not in use when Graph answers 400 ResourceTypeNotSupported (PIM for Groups cannot manage the group)' {
        # Microsoft Learn: a dynamic group and a group synchronized from on-premises cannot be managed
        # in PIM for Groups. The sibling PIM-for-Groups reads (Get-OERGroup's eligibility read,
        # Get-OERPimGroupPolicyId) already take this code as an answer; the criterion must too, or
        # every such group turns an export into InventoryPartial.
        InModuleScope $script:moduleName {
            Mock Invoke-OERGraphRequest {
                $Marker = [PSCustomObject]@{ ExpectedErrorCode = 'ResourceTypeNotSupported'; StatusCode = 400; Message = 'Resource type not supported for onboarding'; Uri = 'x' }
                $Marker.PSObject.TypeNames.Insert(0, 'Omnicit.EntraRBAC.GraphExpectedError')
                $Marker
            }
            $Usage = Test-OERGroupPimInUse -GroupId '11111111-1111-1111-1111-111111111111'
            $Usage.InUse | Should -BeFalse
            $Usage.Reason | Should -BeExactly 'PIM for Groups cannot manage the group (ResourceTypeNotSupported)'
            $Usage.Manageable | Should -BeFalse -Because (
                'this is the ONLY case the group can never be onboarded; every other not-in-use answer ' +
                'leaves onboarding possible'
            )
            $Usage.PSObject.TypeNames[0] | Should -Be 'Omnicit.EntraRBAC.GroupPimUsage'
            Should -Invoke Invoke-OERGraphRequest -Times 1 -Exactly
        }
    }

    It 'answers not in use when Graph answers 404 ResourceNotFound (PIM does not know the group)' {
        InModuleScope $script:moduleName {
            Mock Invoke-OERGraphRequest {
                $Marker = [PSCustomObject]@{ ExpectedErrorCode = 'ResourceNotFound'; StatusCode = 404; Message = 'not found'; Uri = 'x' }
                $Marker.PSObject.TypeNames.Insert(0, 'Omnicit.EntraRBAC.GraphExpectedError')
                $Marker
            }
            $Usage = Test-OERGroupPimInUse -GroupId '11111111-1111-1111-1111-111111111111'
            $Usage.InUse | Should -BeFalse
            $Usage.Reason | Should -Match 'ResourceNotFound'
            $Usage.Manageable | Should -BeTrue -Because 'PIM not knowing the group yet does not mean it can never be onboarded'
        }
    }

    It 'throws when Graph names ResourceNotFound with a status other than 404' {
        # Only the 404 is the documented "PIM does not know the group" answer; the same code with
        # another status is a failure, never a guess in either direction.
        InModuleScope $script:moduleName {
            Mock Invoke-OERGraphRequest {
                $Marker = [PSCustomObject]@{ ExpectedErrorCode = 'ResourceNotFound'; StatusCode = 400; Message = 'odd answer'; Uri = 'x' }
                $Marker.PSObject.TypeNames.Insert(0, 'Omnicit.EntraRBAC.GraphExpectedError')
                $Marker
            }
            { Test-OERGroupPimInUse -GroupId '11111111-1111-1111-1111-111111111111' } | Should -Throw -ExpectedMessage '*odd answer*'
        }
    }

    It 'lets a transport failure propagate to the caller' {
        InModuleScope $script:moduleName {
            Mock Invoke-OERGraphRequest {
                throw [System.Management.Automation.ErrorRecord]::new(
                    [System.Exception]::new('Authorization_RequestDenied: Insufficient privileges'),
                    'Authorization_RequestDenied',
                    [System.Management.Automation.ErrorCategory]::PermissionDenied, $null)
            }
            { Test-OERGroupPimInUse -GroupId '11111111-1111-1111-1111-111111111111' } |
                Should -Throw -ExpectedMessage '*Authorization_RequestDenied*'
        }
    }
}
