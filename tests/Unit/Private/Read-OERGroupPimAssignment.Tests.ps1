BeforeAll {
    Import-Module Omnicit.EntraRBAC -Force
    . "$PSScriptRoot/../TestHelpers/OERTransportTripwire.ps1"
    Install-OERTransportTripwire
}

AfterAll {
    try { Assert-OERTransportTripwire } finally { Uninstall-OERTransportTripwire }
}

Describe 'Read-OERGroupPimAssignment' {
    # BL-125 (A3). The read the inventory and the apply engine take a group's PIM for Groups
    # assignment schedule instances from. It lists every direct member and owner, standing ones too
    # (measured live 2026-10-13), so Get-OERGroupPimHeldAccess can tell an activation from a standing
    # membership. It returns the read or its failure and never writes an error record.
    BeforeEach {
        Mock -ModuleName Omnicit.EntraRBAC Initialize-OERAuth { }
    }

    It 'returns the instances read, tagged, with no error fields' {
        InModuleScope Omnicit.EntraRBAC {
            Mock Invoke-OERGraphRequest {
                @{ value = @(
                        @{ principalId = 'u-1'; accessId = 'member'; assignmentType = 'activated'; endDateTime = $null }
                        @{ principalId = 'u-2'; accessId = 'owner'; assignmentType = 'assigned'; endDateTime = $null }
                    ) }
            }
            $R = Read-OERGroupPimAssignment -GroupId '11111111-1111-1111-1111-111111111111'
            $R.PSObject.TypeNames[0] | Should -BeExactly 'Omnicit.EntraRBAC.GroupPimAssignmentRead'
            @($R.PSObject.Properties.Name) | Should -Be @('Read', 'Value', 'Message', 'Exception')
            $R.Read | Should -BeTrue
            @($R.Value).Count | Should -Be 2
            @($R.Value)[0].principalId | Should -Be 'u-1'
            @($R.Value)[1].accessId | Should -Be 'owner'
            $null -eq $R.Message | Should -BeTrue
            $null -eq $R.Exception | Should -BeTrue
        }
    }

    It 'sends ONE request, for every page, through the pinned PIM for Groups path, declaring ResourceTypeNotSupported as an answer' {
        InModuleScope Omnicit.EntraRBAC {
            Mock Invoke-OERGraphRequest { @{ value = @() } }
            Mock Get-OERPimGroupsGraphPath { param($Path) "beta/$Path" }
            $null = Read-OERGroupPimAssignment -GroupId '11111111-1111-1111-1111-111111111111'
            Should -Invoke Invoke-OERGraphRequest -Exactly -Times 1
            Should -Invoke Invoke-OERGraphRequest -Exactly -Times 1 -ParameterFilter {
                $All -and
                @($ExpectedErrorCode) -contains 'ResourceTypeNotSupported' -and @($ExpectedErrorCode).Count -eq 1 -and
                $Uri -ceq "beta/identityGovernance/privilegedAccess/group/assignmentScheduleInstances?`$filter=groupId eq '11111111-1111-1111-1111-111111111111'" -and
                (-not $Method -or $Method -eq 'GET')
            }
            # The version prefix comes from the single owner of the pin, never from a literal here.
            Should -Invoke Get-OERPimGroupsGraphPath -Exactly -Times 1 -ParameterFilter {
                $Path -ceq "identityGovernance/privilegedAccess/group/assignmentScheduleInstances?`$filter=groupId eq '11111111-1111-1111-1111-111111111111'"
            }
        }
    }

    It 'builds the URI with the real pin as beta' {
        InModuleScope Omnicit.EntraRBAC {
            Mock Invoke-OERGraphRequest { @{ value = @() } }
            $null = Read-OERGroupPimAssignment -GroupId '11111111-1111-1111-1111-111111111111'
            Should -Invoke Invoke-OERGraphRequest -Exactly -Times 1 -ParameterFilter {
                $Uri -ceq "beta/identityGovernance/privilegedAccess/group/assignmentScheduleInstances?`$filter=groupId eq '11111111-1111-1111-1111-111111111111'"
            }
        }
    }

    It 'returns an empty array, not null, when the read succeeded and found none' {
        InModuleScope Omnicit.EntraRBAC {
            Mock Invoke-OERGraphRequest { @{ value = @() } }
            $R = Read-OERGroupPimAssignment -GroupId '11111111-1111-1111-1111-111111111111'
            $R.Read | Should -BeTrue
            $null -ne $R.Value | Should -BeTrue
            , $R.Value | Should -BeOfType ([object[]])
            $R.Value.Count | Should -Be 0
            $null -eq $R.Message | Should -BeTrue
        }
    }

    It 'returns an empty array, not one null, when the answer carries no value at all' {
        InModuleScope Omnicit.EntraRBAC {
            Mock Invoke-OERGraphRequest { @{ } }
            $R = Read-OERGroupPimAssignment -GroupId '11111111-1111-1111-1111-111111111111'
            $R.Read | Should -BeTrue
            $null -ne $R.Value | Should -BeTrue
            $R.Value.Count | Should -Be 0
        }
    }

    It 'reads the expected-error marker as a successful, empty answer' {
        InModuleScope Omnicit.EntraRBAC {
            Mock Invoke-OERGraphRequest {
                $M = [PSCustomObject]@{ ExpectedErrorCode = 'ResourceTypeNotSupported'; StatusCode = 400; Message = 'ResourceTypeNotSupported'; Uri = 'x' }
                $M.PSObject.TypeNames.Insert(0, 'Omnicit.EntraRBAC.GraphExpectedError')
                $M
            }
            $R = Read-OERGroupPimAssignment -GroupId '11111111-1111-1111-1111-111111111111'
            $R.Read | Should -BeTrue
            $null -ne $R.Value | Should -BeTrue
            $R.Value.Count | Should -Be 0
            $null -eq $R.Message | Should -BeTrue
            $null -eq $R.Exception | Should -BeTrue
        }
    }

    It 'returns a thrown failure as unread, with the exact message, and scrubs the record first' {
        InModuleScope Omnicit.EntraRBAC {
            Mock Remove-OERErrorRecord { }
            Mock Invoke-OERGraphRequest {
                throw [System.Management.Automation.ErrorRecord]::new(
                    [System.Exception]::new('Insufficient privileges to complete the operation'),
                    'Authorization_RequestDenied',
                    [System.Management.Automation.ErrorCategory]::PermissionDenied, $null)
            }
            $R = Read-OERGroupPimAssignment -GroupId '11111111-1111-1111-1111-111111111111' -ErrorAction SilentlyContinue -ErrorVariable ReadErr
            $R.PSObject.TypeNames[0] | Should -BeExactly 'Omnicit.EntraRBAC.GroupPimAssignmentRead'
            $R.Read | Should -BeFalse
            $null -eq $R.Value | Should -BeTrue
            $R.Message | Should -BeExactly 'Could not read the PIM for Groups assignments of group 11111111-1111-1111-1111-111111111111: Insufficient privileges to complete the operation.'
            $R.Exception.Message | Should -BeExactly 'Insufficient privileges to complete the operation'
            Should -Invoke Remove-OERErrorRecord -Times 1 -Exactly -ParameterFilter {
                $Record.Exception.Message -eq 'Insufficient privileges to complete the operation'
            }
            @($ReadErr | Where-Object {
                    $_.InvocationInfo -and $_.InvocationInfo.MyCommand -and $_.InvocationInfo.MyCommand.Name -eq 'Read-OERGroupPimAssignment'
                }).Count | Should -Be 0 -Because 'the function returns the failure and leaves reporting it to the caller'
        }
    }

    It 'reads a THROWN ResourceTypeNotSupported as unread, never as an empty answer' {
        # Only the marker the transport returns for the declared code is an answer. A failure that
        # arrives thrown, whatever its code, is unread: the safe direction for a read that decides
        # whether a member is written.
        InModuleScope Omnicit.EntraRBAC {
            Mock Remove-OERErrorRecord { }
            Mock Invoke-OERGraphRequest {
                throw [System.Management.Automation.ErrorRecord]::new(
                    [System.Exception]::new('The resource type is not supported.'),
                    'ResourceTypeNotSupported',
                    [System.Management.Automation.ErrorCategory]::InvalidOperation, $null)
            }
            $R = Read-OERGroupPimAssignment -GroupId '11111111-1111-1111-1111-111111111111'
            $R.Read | Should -BeFalse
            $null -eq $R.Value | Should -BeTrue
            $R.Message | Should -BeExactly 'Could not read the PIM for Groups assignments of group 11111111-1111-1111-1111-111111111111: The resource type is not supported.'
            Should -Invoke Remove-OERErrorRecord -Times 1 -Exactly
        }
    }

    It 'ends the failure message with one period when the reason already ends with one' {
        InModuleScope Omnicit.EntraRBAC {
            Mock Remove-OERErrorRecord { }
            Mock Invoke-OERGraphRequest {
                throw [System.Management.Automation.ErrorRecord]::new(
                    [System.Exception]::new('Insufficient privileges to complete the operation.'),
                    'Authorization_RequestDenied',
                    [System.Management.Automation.ErrorCategory]::PermissionDenied, $null)
            }
            $R = Read-OERGroupPimAssignment -GroupId '11111111-1111-1111-1111-111111111111'
            $R.Read | Should -BeFalse
            $R.Message | Should -BeExactly 'Could not read the PIM for Groups assignments of group 11111111-1111-1111-1111-111111111111: Insufficient privileges to complete the operation.'
            $R.Message | Should -Not -BeLike '*..'
            # The exception itself is kept as it was raised, its own period included.
            $R.Exception.Message | Should -BeExactly 'Insufficient privileges to complete the operation.'
        }
    }

    It 'returns a statement-terminating failure of the transport as unread too' {
        InModuleScope Omnicit.EntraRBAC {
            Mock Remove-OERErrorRecord { }
            Mock Invoke-OERGraphRequest { [CmdletBinding()] param($Uri, [switch]$All, $ExpectedErrorCode) $PSCmdlet.ThrowTerminatingError(
                    [System.Management.Automation.ErrorRecord]::new([System.Exception]::new('throttled'), 'TooManyRequests',
                        [System.Management.Automation.ErrorCategory]::LimitsExceeded, $null)) }
            $R = Read-OERGroupPimAssignment -GroupId '11111111-1111-1111-1111-111111111111'
            $R.Read | Should -BeFalse
            $R.Message | Should -BeExactly 'Could not read the PIM for Groups assignments of group 11111111-1111-1111-1111-111111111111: throttled.'
            Should -Invoke Remove-OERErrorRecord -Times 1 -Exactly -ParameterFilter { $Record.Exception.Message -eq 'throttled' }
        }
    }

    It 'sends the request with the id as given for an empty or null id (<Label>)' -ForEach @(
        @{ Label = 'empty'; Id = '' }
        @{ Label = 'null'; Id = $null }
    ) {
        # Accepted, not refused at binding: a caller reads a group it already holds, and a binding error
        # would end the caller's statement outside any try. The id is sent as given, as the
        # eligibility read does.
        InModuleScope Omnicit.EntraRBAC -Parameters @{ Id = $Id } {
            param($Id)
            Mock Invoke-OERGraphRequest { @{ value = @() } }
            $R = Read-OERGroupPimAssignment -GroupId $Id
            $R.Read | Should -BeTrue
            Should -Invoke Invoke-OERGraphRequest -Exactly -Times 1 -ParameterFilter {
                $Uri -ceq "beta/identityGovernance/privilegedAccess/group/assignmentScheduleInstances?`$filter=groupId eq ''"
            }
        }
    }

    It 'makes no sign-in of its own' {
        Mock -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest { @{ value = @() } }
        InModuleScope Omnicit.EntraRBAC {
            $null = Read-OERGroupPimAssignment -GroupId '11111111-1111-1111-1111-111111111111'
        }
        # Reach proof: the read was sent, and no sign-in with it.
        Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest -Exactly -Times 1
        Should -Invoke -ModuleName Omnicit.EntraRBAC Initialize-OERAuth -Times 0
    }
}
