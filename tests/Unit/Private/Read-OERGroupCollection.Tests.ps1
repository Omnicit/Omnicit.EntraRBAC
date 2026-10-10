BeforeAll {
    Import-Module Omnicit.EntraRBAC -Force
    . "$PSScriptRoot/../TestHelpers/OERTransportTripwire.ps1"
    Install-OERTransportTripwire
}

AfterAll {
    try { Assert-OERTransportTripwire } finally { Uninstall-OERTransportTripwire }
}

Describe 'Read-OERGroupCollection' {
    BeforeEach {
        Mock -ModuleName Omnicit.EntraRBAC Initialize-OERAuth { }
    }

    Context 'Members' {
        It 'returns the members read, tagged, with no error fields' {
            InModuleScope Omnicit.EntraRBAC {
                Mock Get-OERGroupRelation {
                    [PSCustomObject]@{ PrincipalId = 'u1' }
                    [PSCustomObject]@{ PrincipalId = 'u2' }
                } -ParameterFilter { $Relation -eq 'members' }
                $R = Read-OERGroupCollection -GroupId '11111111-1111-1111-1111-111111111111' -Collection Members
                $R.PSObject.TypeNames[0] | Should -Be 'Omnicit.EntraRBAC.GroupCollectionRead'
                $R.Collection | Should -Be 'Members'
                $R.Read | Should -BeTrue
                @($R.Value).Count | Should -Be 2
                $null -eq $R.ErrorId | Should -BeTrue
                $null -eq $R.Message | Should -BeTrue
                $null -eq $R.Exception | Should -BeTrue
                Should -Invoke Get-OERGroupRelation -Exactly -Times 1 -ParameterFilter {
                    $GroupId -eq '11111111-1111-1111-1111-111111111111' -and $Relation -eq 'members'
                }
            }
        }

        It 'returns an empty array, not null, for a group that genuinely has no members' {
            InModuleScope Omnicit.EntraRBAC {
                Mock Get-OERGroupRelation { } -ParameterFilter { $Relation -eq 'members' }
                $R = Read-OERGroupCollection -GroupId '11111111-1111-1111-1111-111111111111' -Collection Members
                $R.Read | Should -BeTrue
                $null -ne $R.Value | Should -BeTrue
                @($R.Value).Count | Should -Be 0
            }
        }

        It 'returns the failure instead of writing it, and scrubs the record first' {
            InModuleScope Omnicit.EntraRBAC {
                Mock Remove-OERErrorRecord { }
                Mock Get-OERGroupRelation { throw [System.Exception]::new('boom') } -ParameterFilter { $Relation -eq 'members' }
                $R = Read-OERGroupCollection -GroupId '11111111-1111-1111-1111-111111111111' -Collection Members -ErrorAction SilentlyContinue -ErrorVariable ReadErr
                $R.Collection | Should -Be 'Members'
                $R.Read | Should -BeFalse
                $null -eq $R.Value | Should -BeTrue
                $R.ErrorId | Should -Be 'GroupMemberReadFailed'
                $R.Message | Should -Be 'Could not read members for group 11111111-1111-1111-1111-111111111111: boom. The Members property is omitted rather than reported as empty.'
                $R.Exception.Message | Should -Be 'boom'
                Should -Invoke Remove-OERErrorRecord -Exactly -Times 1
                @($ReadErr | Where-Object {
                        $_.InvocationInfo -and $_.InvocationInfo.MyCommand -and $_.InvocationInfo.MyCommand.Name -eq 'Read-OERGroupCollection'
                    }).Count | Should -Be 0 -Because 'the function returns the failure and leaves writing it to the caller'
            }
        }
    }

    Context 'an empty or null group id (as inside Get-OERGroup before the reads moved here)' {
        # Get-OERGroup used to make each read INSIDE a try, so an empty id's binding error in
        # Get-OERGroupRelation became a failure result, and the eligibility request was built with
        # the id as given. The parameter allows null and empty so the same outcome holds here, rather
        # than a terminating binding error in the caller, outside any try.
        It 'returns the members failure, naming the empty id, and sends no request (<Label>)' -ForEach @(
            @{ Label = 'empty'; Id = '' }
            @{ Label = 'null'; Id = $null }
        ) {
            InModuleScope Omnicit.EntraRBAC -Parameters @{ Id = $Id } {
                param($Id)
                Mock Invoke-OERGraphRequest { throw 'no request expected' }
                $R = Read-OERGroupCollection -GroupId $Id -Collection Members
                $R.Read | Should -BeFalse
                $R.ErrorId | Should -Be 'GroupMemberReadFailed'
                $R.Message | Should -BeLike 'Could not read members for group : * The Members property is omitted rather than reported as empty.'
                $R.Exception | Should -BeOfType ([System.Management.Automation.ParameterBindingException])
                Should -Invoke Invoke-OERGraphRequest -Exactly -Times 0
            }
        }

        It 'returns the owners failure, naming the empty id, and sends no request (<Label>)' -ForEach @(
            @{ Label = 'empty'; Id = '' }
            @{ Label = 'null'; Id = $null }
        ) {
            InModuleScope Omnicit.EntraRBAC -Parameters @{ Id = $Id } {
                param($Id)
                Mock Invoke-OERGraphRequest { throw 'no request expected' }
                $R = Read-OERGroupCollection -GroupId $Id -Collection Owners
                $R.Read | Should -BeFalse
                $R.ErrorId | Should -Be 'GroupOwnerReadFailed'
                $R.Message | Should -BeLike 'Could not read owners for group : * The Owners property is omitted rather than reported as empty.'
                $R.Exception | Should -BeOfType ([System.Management.Automation.ParameterBindingException])
                Should -Invoke Invoke-OERGraphRequest -Exactly -Times 0
            }
        }

        It 'sends the eligibility request with the id as given (<Label>)' -ForEach @(
            @{ Label = 'empty'; Id = '' }
            @{ Label = 'null'; Id = $null }
        ) {
            InModuleScope Omnicit.EntraRBAC -Parameters @{ Id = $Id } {
                param($Id)
                Mock Invoke-OERGraphRequest { @{ value = @() } }
                $R = Read-OERGroupCollection -GroupId $Id -Collection PimEligibility
                $R.Read | Should -BeTrue
                @($R.Value).Count | Should -Be 0
                Should -Invoke Invoke-OERGraphRequest -Exactly -Times 1 -ParameterFilter {
                    $Uri -eq "beta/identityGovernance/privilegedAccess/group/eligibilityScheduleInstances?`$filter=groupId eq ''"
                }
            }
        }
    }

    Context 'Owners' {
        It 'returns the owners read, from the owners relation only' {
            InModuleScope Omnicit.EntraRBAC {
                Mock Get-OERGroupRelation {
                    [PSCustomObject]@{ PrincipalId = 'o1' }
                    [PSCustomObject]@{ PrincipalId = 'o2' }
                } -ParameterFilter { $Relation -eq 'owners' }
                $R = Read-OERGroupCollection -GroupId '11111111-1111-1111-1111-111111111111' -Collection Owners
                $R.PSObject.TypeNames[0] | Should -Be 'Omnicit.EntraRBAC.GroupCollectionRead'
                $R.Collection | Should -Be 'Owners'
                $R.Read | Should -BeTrue
                @($R.Value).Count | Should -Be 2
                $R.ErrorId | Should -BeNullOrEmpty
                Should -Invoke Get-OERGroupRelation -Exactly -Times 1 -ParameterFilter { $Relation -eq 'owners' }
                Should -Invoke Get-OERGroupRelation -Exactly -Times 0 -ParameterFilter { $Relation -eq 'members' }
            }
        }

        It 'returns an empty array, not null, for a group that genuinely has no owners' {
            InModuleScope Omnicit.EntraRBAC {
                Mock Get-OERGroupRelation { } -ParameterFilter { $Relation -eq 'owners' }
                $R = Read-OERGroupCollection -GroupId '11111111-1111-1111-1111-111111111111' -Collection Owners
                $R.Read | Should -BeTrue
                $null -ne $R.Value | Should -BeTrue
                @($R.Value).Count | Should -Be 0
            }
        }

        It 'returns the failure instead of writing it, and scrubs the record first' {
            InModuleScope Omnicit.EntraRBAC {
                Mock Remove-OERErrorRecord { }
                Mock Get-OERGroupRelation { throw [System.Exception]::new('boom') } -ParameterFilter { $Relation -eq 'owners' }
                $R = Read-OERGroupCollection -GroupId '11111111-1111-1111-1111-111111111111' -Collection Owners
                $R.Collection | Should -Be 'Owners'
                $R.Read | Should -BeFalse
                $null -eq $R.Value | Should -BeTrue
                $R.ErrorId | Should -Be 'GroupOwnerReadFailed'
                $R.Message | Should -Be 'Could not read owners for group 11111111-1111-1111-1111-111111111111: boom. The Owners property is omitted rather than reported as empty.'
                $R.Exception.Message | Should -Be 'boom'
                Should -Invoke Remove-OERErrorRecord -Exactly -Times 1
            }
        }
    }

    Context 'PimEligibility' {
        It 'returns the eligibility instances and asks the transport to answer ResourceTypeNotSupported as data' {
            InModuleScope Omnicit.EntraRBAC {
                Mock Invoke-OERGraphRequest { @{ value = @(@{ principalId = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa' }) } }
                $R = Read-OERGroupCollection -GroupId '11111111-1111-1111-1111-111111111111' -Collection PimEligibility
                $R.PSObject.TypeNames[0] | Should -Be 'Omnicit.EntraRBAC.GroupCollectionRead'
                $R.Collection | Should -Be 'PimEligibility'
                $R.Read | Should -BeTrue
                @($R.Value).Count | Should -Be 1
                @($R.Value)[0].principalId | Should -Be 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'
                $null -eq $R.ErrorId | Should -BeTrue
                $null -eq $R.Message | Should -BeTrue
                $null -eq $R.Exception | Should -BeTrue
                Should -Invoke Invoke-OERGraphRequest -Exactly -Times 1 -ParameterFilter {
                    $All -and $ExpectedErrorCode -contains 'ResourceTypeNotSupported' -and
                    $Uri -like "*eligibilityScheduleInstances*groupId eq '11111111-1111-1111-1111-111111111111'*"
                }
            }
        }

        It 'reads the expected-error marker as a successful, empty answer' {
            InModuleScope Omnicit.EntraRBAC {
                Mock Invoke-OERGraphRequest {
                    $M = [PSCustomObject]@{}
                    $M.PSObject.TypeNames.Insert(0, 'Omnicit.EntraRBAC.GraphExpectedError')
                    $M
                }
                $R = Read-OERGroupCollection -GroupId '11111111-1111-1111-1111-111111111111' -Collection PimEligibility
                $R.Read | Should -BeTrue
                $null -ne $R.Value | Should -BeTrue
                @($R.Value).Count | Should -Be 0
                $R.ErrorId | Should -BeNullOrEmpty
            }
        }

        It 'reads a thrown ResourceTypeNotSupported as a successful, empty answer' {
            InModuleScope Omnicit.EntraRBAC {
                Mock Remove-OERErrorRecord { }
                Mock Invoke-OERGraphRequest {
                    throw [System.Management.Automation.ErrorRecord]::new(
                        [System.Exception]::new('The resource type is not supported.'),
                        'ResourceTypeNotSupported',
                        [System.Management.Automation.ErrorCategory]::InvalidOperation,
                        $null)
                }
                $R = Read-OERGroupCollection -GroupId '11111111-1111-1111-1111-111111111111' -Collection PimEligibility
                $R.Read | Should -BeTrue
                $null -ne $R.Value | Should -BeTrue
                @($R.Value).Count | Should -Be 0
                $R.ErrorId | Should -BeNullOrEmpty
                Should -Invoke Remove-OERErrorRecord -Exactly -Times 1
            }
        }

        It 'matches the code when it is not the first segment of a composed FullyQualifiedErrorId' {
            InModuleScope Omnicit.EntraRBAC {
                Mock Invoke-OERGraphRequest {
                    throw [System.Management.Automation.ErrorRecord]::new(
                        [System.Exception]::new('Resource type not supported for onboarding'),
                        'SomeOuterFrame,ResourceTypeNotSupported',
                        [System.Management.Automation.ErrorCategory]::OperationStopped, $null)
                }
                $R = Read-OERGroupCollection -GroupId '11111111-1111-1111-1111-111111111111' -Collection PimEligibility
                $R.Read | Should -BeTrue
                @($R.Value).Count | Should -Be 0
            }
        }

        It 'reads a status-derived record carrying the code only in its detail text as an empty answer' {
            InModuleScope Omnicit.EntraRBAC {
                Mock Invoke-OERGraphRequest {
                    $Record = [System.Management.Automation.ErrorRecord]::new(
                        [System.Exception]::new('ResourceTypeNotSupported: Resource type not supported for onboarding'),
                        'BadRequest',
                        [System.Management.Automation.ErrorCategory]::OperationStopped, $null)
                    $Record.ErrorDetails = [System.Management.Automation.ErrorDetails]::new(
                        'ResourceTypeNotSupported: Resource type not supported for onboarding')
                    throw $Record
                }
                $R = Read-OERGroupCollection -GroupId '11111111-1111-1111-1111-111111111111' -Collection PimEligibility
                $R.Read | Should -BeTrue
                @($R.Value).Count | Should -Be 0
            }
        }

        It 'refuses a different code that merely starts with the expected one' {
            InModuleScope Omnicit.EntraRBAC {
                Mock Invoke-OERGraphRequest {
                    throw [System.Management.Automation.ErrorRecord]::new(
                        [System.Exception]::new('different failure'),
                        'ResourceTypeNotSupportedInThisTenant',
                        [System.Management.Automation.ErrorCategory]::OperationStopped, $null)
                }
                $R = Read-OERGroupCollection -GroupId '11111111-1111-1111-1111-111111111111' -Collection PimEligibility
                $R.Read | Should -BeFalse
                $R.ErrorId | Should -Be 'GroupPimEligibilityReadFailed'
            }
        }

        It 'returns the failure of a 403 whose prose mentions the expected code' {
            InModuleScope Omnicit.EntraRBAC {
                Mock Remove-OERErrorRecord { }
                Mock Invoke-OERGraphRequest {
                    throw [System.Management.Automation.ErrorRecord]::new(
                        [System.Exception]::new('Insufficient privileges: ResourceTypeNotSupported'),
                        'Authorization_RequestDenied',
                        [System.Management.Automation.ErrorCategory]::PermissionDenied, $null)
                }
                $R = Read-OERGroupCollection -GroupId '11111111-1111-1111-1111-111111111111' -Collection PimEligibility
                $R.Collection | Should -Be 'PimEligibility'
                $R.Read | Should -BeFalse
                $null -eq $R.Value | Should -BeTrue
                $R.ErrorId | Should -Be 'GroupPimEligibilityReadFailed'
                $R.Message | Should -BeLike 'Could not read PIM eligibility for group 11111111-1111-1111-1111-111111111111: *'
                $R.Message | Should -BeLike '* The PimEligibility property is omitted rather than reported as empty.'
                $R.Message | Should -Be 'Could not read PIM eligibility for group 11111111-1111-1111-1111-111111111111: Insufficient privileges: ResourceTypeNotSupported. The PimEligibility property is omitted rather than reported as empty.'
                $R.Exception.Message | Should -Be 'Insufficient privileges: ResourceTypeNotSupported'
                Should -Invoke Remove-OERErrorRecord -Exactly -Times 1
            }
        }
    }

    It 'refuses a collection it does not know' {
        InModuleScope Omnicit.EntraRBAC {
            { Read-OERGroupCollection -GroupId '11111111-1111-1111-1111-111111111111' -Collection Roles } |
                Should -Throw -ExpectedMessage '*does not belong to the set*'
        }
    }
}
