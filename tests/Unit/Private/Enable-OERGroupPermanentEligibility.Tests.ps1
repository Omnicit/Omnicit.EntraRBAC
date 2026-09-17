BeforeAll {
    Import-Module Omnicit.EntraRBAC -Force
}

Describe 'Enable-OERGroupPermanentEligibility' {
    BeforeEach { InModuleScope Omnicit.EntraRBAC { $script:_OERAuthState = $null } }

    It 'GETs then PATCHes Expiration_Admin_Eligibility with isExpirationRequired false' {
        InModuleScope Omnicit.EntraRBAC {
            Mock Invoke-OERGraphRequest {
                [PSCustomObject]@{ id = 'Expiration_Admin_Eligibility'; isExpirationRequired = $true; maximumDuration = 'P365D'; '@odata.type' = '#microsoft.graph.unifiedRoleManagementPolicyExpirationRule'; target = [PSCustomObject]@{ caller = 'Admin' } }
            } -ParameterFilter { $Method -ne 'PATCH' }
            Mock Invoke-OERGraphRequest { } -ParameterFilter { $Method -eq 'PATCH' }

            $Result = Enable-OERGroupPermanentEligibility -PolicyId 'pol-1' -Confirm:$false

            # The caller keys PolicyOpenedButGrantFailed off this value, so it has to say "written".
            $Result | Should -Be $true
            Should -Invoke Invoke-OERGraphRequest -Times 1 -ParameterFilter {
                $Method -eq 'PATCH' -and
                $Uri -eq 'beta/policies/roleManagementPolicies/pol-1/rules/Expiration_Admin_Eligibility' -and
                $Body.isExpirationRequired -eq $false -and
                $Body.maximumDuration -eq 'P365D'
            }
        }
    }
    It 'does not PATCH under -WhatIf (but does GET)' {
        InModuleScope Omnicit.EntraRBAC {
            Mock Invoke-OERGraphRequest {
                [PSCustomObject]@{ id = 'Expiration_Admin_Eligibility'; isExpirationRequired = $true; maximumDuration = 'P365D' }
            } -ParameterFilter { $Method -ne 'PATCH' }
            Mock Invoke-OERGraphRequest { } -ParameterFilter { $Method -eq 'PATCH' }

            $Result = Enable-OERGroupPermanentEligibility -PolicyId 'pol-1' -WhatIf

            # A declined gate must report $false, never $null -- the caller treats $null as "unknown"
            # only because it is falsy, and an explicit $false is what makes the contract testable.
            $Result | Should -Be $false
            Should -Invoke Invoke-OERGraphRequest -Times 0 -ParameterFilter { $Method -eq 'PATCH' }
        }
    }

    It 'rethrows a failing rule GET unchanged and scrubs the bearer-hygiene record first' {
        # Enable-OERGroupPermanentEligibility.ps1:32-37 is bare `throw` (not $PSCmdlet.WriteError). A
        # bare throw re-throws the SAME ErrorRecord/Exception instance, so the caller's own
        # Remove-OERErrorRecord -Record $PSItem removes it whether or not this function's own catch
        # already did. When no outer catch scrubs either, the engine re-appends that identical record
        # at the next call boundary -- undoing this function's scrub when it ran, and covering for the
        # missing append when it did not -- so both states settle at exactly 1 matching record in
        # $global:Error (measured). The $global:Error + [object]::ReferenceEquals proof (see
        # Get-OERGroupPermanentEligibilityState.Tests.ps1:43) only discriminates for a function that
        # re-throws a CONVERTED exception (Invoke-OERGraphRequest via Convert-GraphHttpException,
        # Invoke-OERArmRequest via its ArmTransportError), where the original Exception is never
        # re-appended. For a bare re-throw, Mock Remove-OERErrorRecord {} plus
        # Should -Invoke ... -Times 1 is the only shape that detects a deleted scrub line.
        InModuleScope Omnicit.EntraRBAC {
            $Converted = [System.Exception]::new('Authorization_RequestDenied: Insufficient privileges.')
            $Record = [System.Management.Automation.ErrorRecord]::new(
                $Converted, 'Authorization_RequestDenied',
                [System.Management.Automation.ErrorCategory]::PermissionDenied, $null)
            Mock Invoke-OERGraphRequest { throw $Record } -ParameterFilter { $Method -ne 'PATCH' }
            Mock Remove-OERErrorRecord { }

            $Caught = $null
            try {
                Enable-OERGroupPermanentEligibility -PolicyId 'pol-1' -Confirm:$false
            } catch {
                $Caught = $PSItem
            }

            $Caught | Should -Not -BeNullOrEmpty
            $Caught.FullyQualifiedErrorId | Should -Match 'Authorization_RequestDenied'
            Should -Invoke Remove-OERErrorRecord -Times 1
        }
    }

    It 'rethrows a failing rule PATCH unchanged and scrubs the bearer-hygiene record first' {
        InModuleScope Omnicit.EntraRBAC {
            $Converted = [System.Exception]::new('Request_BadRequest: The rule is not patchable.')
            $Record = [System.Management.Automation.ErrorRecord]::new(
                $Converted, 'Request_BadRequest',
                [System.Management.Automation.ErrorCategory]::InvalidOperation, $null)
            Mock Invoke-OERGraphRequest {
                @{ id = 'Expiration_Admin_Eligibility'; isExpirationRequired = $true }
            } -ParameterFilter { $Method -ne 'PATCH' }
            Mock Invoke-OERGraphRequest { throw $Record } -ParameterFilter { $Method -eq 'PATCH' }
            Mock Remove-OERErrorRecord { }

            $Caught = $null
            try {
                Enable-OERGroupPermanentEligibility -PolicyId 'pol-1' -Confirm:$false
            } catch {
                $Caught = $PSItem
            }

            $Caught.FullyQualifiedErrorId | Should -Match 'Request_BadRequest'
            Should -Invoke Remove-OERErrorRecord -Times 1
        }
    }
}
