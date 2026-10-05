BeforeAll {
    Import-Module Omnicit.EntraRBAC -Force
    . "$PSScriptRoot/../TestHelpers/OERTransportTripwire.ps1"
    Install-OERTransportTripwire
}

AfterAll {
    try { Assert-OERTransportTripwire } finally { Uninstall-OERTransportTripwire }
}

Describe 'Get-OERGroupPermanentEligibilityState' {
    BeforeEach { InModuleScope Omnicit.EntraRBAC { $script:_OERAuthState = $null } }

    It 'reports HasPolicy false when the group has no PIM policy' {
        InModuleScope Omnicit.EntraRBAC {
            Mock Get-OERPimGroupPolicyId { $null }
            $State = Get-OERGroupPermanentEligibilityState -GroupId 'g1' -AccessType 'member'
            $State.HasPolicy        | Should -BeFalse
            $State.PermanentAllowed | Should -BeFalse
        }
    }
    It 'rethrows a refused policy-id read (a 403) as itself and reports no HasPolicy fact' {
        # REPLACES an It that pinned the swallow with a mock throwing 'ResourceTypeNotSupported' -- a
        # premise production no longer has: Get-OERPimGroupPolicyId declares that code to the transport
        # and returns $null for it (a $null is the It above: HasPolicy false). What reaches this catch
        # now is a REAL failure (a 403, an exhausted 429, a 5xx), and reporting that as "no policy" made
        # Add-OERGroupEligibility refuse with GroupNotOnboarded for a group that was merely unreadable.
        # The record is rethrown unchanged; Add-OERGroupEligibility's own catch decides what to do.
        InModuleScope Omnicit.EntraRBAC {
            $Denied = [System.Management.Automation.ErrorRecord]::new(
                [System.Exception]::new('Authorization_RequestDenied: Insufficient privileges to complete the operation.'),
                'Authorization_RequestDenied',
                [System.Management.Automation.ErrorCategory]::PermissionDenied,
                'g1')
            Mock Get-OERPimGroupPolicyId { throw $Denied }
            Mock Invoke-OERGraphRequest { }

            $Caught = $null
            $State = $null
            try {
                $State = Get-OERGroupPermanentEligibilityState -GroupId 'g1' -AccessType 'owner'
            } catch {
                $Caught = $PSItem
            }

            # The positive half: the policy-id read was reached, once, for this group and access type.
            Should -Invoke Get-OERPimGroupPolicyId -Times 1 -Exactly -ParameterFilter {
                $GroupId -eq 'g1' -and $AccessType -eq 'owner'
            }
            $Caught | Should -Not -BeNullOrEmpty
            $Caught.FullyQualifiedErrorId | Should -Match '^Authorization_RequestDenied'
            $Caught.CategoryInfo.Category | Should -Be 'PermissionDenied'
            # No fact was reported, and the rules were never read.
            $State | Should -BeNullOrEmpty
            Should -Invoke Invoke-OERGraphRequest -Times 0 -Exactly
        }
    }
    It 'scrubs the refused policy-id read record before rethrowing it (bearer hygiene)' {
        # The catch is a bare rethrow of the SAME record, which PowerShell re-appends to $global:Error
        # at the next call boundary whether or not the scrub ran, so only the mocked call detects a
        # deleted scrub line (the rules-read It below this one gives the same reasoning at length).
        InModuleScope Omnicit.EntraRBAC {
            $Denied = [System.Management.Automation.ErrorRecord]::new(
                [System.Exception]::new('Authorization_RequestDenied: policy id read scrub marker.'),
                'Authorization_RequestDenied',
                [System.Management.Automation.ErrorCategory]::PermissionDenied,
                'g1')
            Mock Get-OERPimGroupPolicyId { throw $Denied }
            Mock Remove-OERErrorRecord { }

            $Caught = $null
            try {
                Get-OERGroupPermanentEligibilityState -GroupId 'g1'
            } catch {
                $Caught = $PSItem
            }

            $Caught | Should -Not -BeNullOrEmpty
            $Caught.Exception.Message | Should -Be 'Authorization_RequestDenied: policy id read scrub marker.'
            Should -Invoke Remove-OERErrorRecord -Times 1 -Exactly -ParameterFilter {
                $Record.Exception.Message -eq 'Authorization_RequestDenied: policy id read scrub marker.'
            }
        }
    }
    It 'reports PermanentAllowed false when the eligibility rule requires expiration' {
        InModuleScope Omnicit.EntraRBAC {
            Mock Get-OERPimGroupPolicyId { 'pol-1' }
            Mock Invoke-OERGraphRequest { @{ value = @(
                [PSCustomObject]@{ id = 'Expiration_Admin_Eligibility'; isExpirationRequired = $true }
            ) } }
            $State = Get-OERGroupPermanentEligibilityState -GroupId 'g1'
            $State.HasPolicy        | Should -BeTrue
            $State.PolicyId         | Should -Be 'pol-1'
            $State.PermanentAllowed | Should -BeFalse
        }
    }
    It 'reports PermanentAllowed true when the eligibility rule allows permanent' {
        InModuleScope Omnicit.EntraRBAC {
            Mock Get-OERPimGroupPolicyId { 'pol-1' }
            Mock Invoke-OERGraphRequest { @{ value = @(
                [PSCustomObject]@{ id = 'Expiration_Admin_Eligibility'; isExpirationRequired = $false }
            ) } }
            (Get-OERGroupPermanentEligibilityState -GroupId 'g1').PermanentAllowed | Should -BeTrue
        }
    }
    It 'rethrows a failing rules GET unchanged and scrubs the bearer-hygiene record first' {
        # Invoke-OERGraphRequest never lets a raw, bearer-carrying record escape: every non-recoverable
        # failure is already routed through Convert-GraphHttpException before it is thrown, so the
        # record this function's catch block sees is already a sanitized, freshly built ErrorRecord
        # (a plain System.Exception, no InnerException, ErrorId = the real Graph error code). Model
        # that shape here instead of a raw transport exception -- mocking a raw exception would let a
        # regression that re-converts (and so destroys) the Graph error code pass unnoticed.
        #
        # This function's catch is a bare `throw` (not $PSCmdlet.WriteError), which re-throws the SAME
        # ErrorRecord/Exception instance. PowerShell then re-appends that identical record into
        # $global:Error at the next call boundary regardless of whether the inner catch scrubbed it --
        # so a $global:Error + [object]::ReferenceEquals proof passes whether or not the scrub line
        # ran (measured: deleting `Remove-OERErrorRecord -Record $PSItem` from source left all Its in
        # this file green). That proof only discriminates for a function that re-throws a CONVERTED
        # exception (Invoke-OERGraphRequest via Convert-GraphHttpException, Invoke-OERArmRequest via
        # its ArmTransportError), where the original Exception is never re-appended. For a bare
        # re-throw like this one, Mock Remove-OERErrorRecord {} plus Should -Invoke ... -Times 1 is the
        # only shape that detects a deleted scrub line.
        InModuleScope Omnicit.EntraRBAC {
            $ConvertedException = [System.Exception]::new('Authorization_RequestDenied: Insufficient privileges to complete the operation.')
            $ConvertedRecord = [System.Management.Automation.ErrorRecord]::new(
                $ConvertedException,
                'Authorization_RequestDenied',
                [System.Management.Automation.ErrorCategory]::OperationStopped,
                $null)
            Mock Get-OERPimGroupPolicyId { 'policy-id-1' }
            Mock Invoke-OERGraphRequest { throw $ConvertedRecord }
            Mock Remove-OERErrorRecord { }

            $Caught = $null
            try {
                Get-OERGroupPermanentEligibilityState -GroupId 'g1'
            } catch {
                $Caught = $PSItem
            }

            # The real Graph error code must survive the rethrow -- a double conversion would replace
            # it with the generic 'GraphError' fallback code from Convert-GraphHttpException.
            $Caught | Should -Not -BeNullOrEmpty
            $Caught.FullyQualifiedErrorId | Should -Match '^Authorization_RequestDenied'

            Should -Invoke Remove-OERErrorRecord -Times 1
        }
    }
    It 'still reports PermanentAllowed from the rule when the read succeeds' {
        InModuleScope Omnicit.EntraRBAC {
            Mock Get-OERPimGroupPolicyId { 'policy-id-1' }
            Mock Invoke-OERGraphRequest {
                @{ value = @(@{ id = 'Expiration_Admin_Eligibility'; isExpirationRequired = $false }) }
            }
            $State = Get-OERGroupPermanentEligibilityState -GroupId 'g1'
            $State.HasPolicy        | Should -BeTrue
            $State.PermanentAllowed | Should -BeTrue
        }
    }

    Context 'paging (-All opt-in, Task 7 closes PR36 deliberately-not-fixed item 3)' {
        It 'passes -All to the beta rules read' {
            InModuleScope Omnicit.EntraRBAC {
                Mock Get-OERPimGroupPolicyId { 'pol-1' }
                Mock Invoke-OERGraphRequest {
                    @{ value = @(@{ id = 'Expiration_Admin_Eligibility'; isExpirationRequired = $false }) }
                }
                Get-OERGroupPermanentEligibilityState -GroupId 'g1' | Out-Null
                Should -Invoke Invoke-OERGraphRequest -Times 1 -Exactly -ParameterFilter {
                    $Uri -eq 'beta/policies/roleManagementPolicies/pol-1/rules' -and $All
                }
            }
        }
    }
}
