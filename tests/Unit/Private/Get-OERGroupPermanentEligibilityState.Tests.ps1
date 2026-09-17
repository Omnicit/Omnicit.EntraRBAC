BeforeAll {
    Import-Module Omnicit.EntraRBAC -Force
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
    It 'reports HasPolicy false when the policy lookup throws (not onboarded)' {
        InModuleScope Omnicit.EntraRBAC {
            Mock Get-OERPimGroupPolicyId { throw 'ResourceTypeNotSupported' }
            (Get-OERGroupPermanentEligibilityState -GroupId 'g1').HasPolicy | Should -BeFalse
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
