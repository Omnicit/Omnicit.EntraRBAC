BeforeAll {
    Import-Module Omnicit.EntraRBAC -Force
    . "$PSScriptRoot/../TestHelpers/OERTransportTripwire.ps1"
    Install-OERTransportTripwire
}

AfterAll {
    try { Assert-OERTransportTripwire } finally { Uninstall-OERTransportTripwire }
}

# Ruling R11 (Sprint 11 step 2): the assignment policy name lookup moved, unchanged, out of
# Resolve-OERAccessReviewScopeTarget into this helper, so the apply engine's access review target check
# (Get-OERAccessReviewTargetMismatch) resolves a policy name exactly as creation does. No id below is
# version-4 shaped.
Describe 'Resolve-OERAssignmentPolicyId' {
    BeforeEach { InModuleScope Omnicit.EntraRBAC { $script:_OERAuthState = $null } }

    It 'returns a GUID verbatim and lists nothing' {
        InModuleScope Omnicit.EntraRBAC {
            Mock Invoke-OERGraphRequest { throw 'Unexpected Graph request for a GUID policy.' }
            $R = Resolve-OERAssignmentPolicyId -AccessPackageId '11111111-1111-1111-1111-111111111111' -AssignmentPolicy '22222222-2222-2222-2222-222222222222'
            $R | Should -BeExactly '22222222-2222-2222-2222-222222222222'
            Should -Invoke Invoke-OERGraphRequest -Times 0
        }
    }

    It 'lists the package''s policies once, with the exact filter, and returns the one id that carries the name' {
        InModuleScope Omnicit.EntraRBAC {
            Mock Invoke-OERGraphRequest {
                @{ value = @(
                        @{ id = '33333333-3333-3333-3333-333333333333'; displayName = 'Standard' }
                        @{ id = '44444444-4444-4444-4444-444444444444'; displayName = 'Other' }
                    ) }
            }
            $R = Resolve-OERAssignmentPolicyId -AccessPackageId '11111111-1111-1111-1111-111111111111' -AssignmentPolicy 'Standard'
            $R | Should -BeExactly '33333333-3333-3333-3333-333333333333'
            Should -Invoke Invoke-OERGraphRequest -Times 1 -Exactly
            Should -Invoke Invoke-OERGraphRequest -Times 1 -Exactly -ParameterFilter {
                $Uri -ceq "v1.0/identityGovernance/entitlementManagement/assignmentPolicies?`$filter=accessPackage/id eq '11111111-1111-1111-1111-111111111111'"
            }
        }
    }

    It 'returns $null when no policy of the package carries the name' {
        InModuleScope Omnicit.EntraRBAC {
            Mock Invoke-OERGraphRequest { @{ value = @(@{ id = '44444444-4444-4444-4444-444444444444'; displayName = 'Other' }) } }
            $R = Resolve-OERAssignmentPolicyId -AccessPackageId '11111111-1111-1111-1111-111111111111' -AssignmentPolicy 'Standard'
            $R | Should -BeNullOrEmpty
            Should -Invoke Invoke-OERGraphRequest -Times 1 -Exactly
        }
    }

    It 'returns $null when the package has no policy at all' {
        InModuleScope Omnicit.EntraRBAC {
            Mock Invoke-OERGraphRequest { @{ value = @() } }
            $R = Resolve-OERAssignmentPolicyId -AccessPackageId '11111111-1111-1111-1111-111111111111' -AssignmentPolicy 'Standard'
            $R | Should -BeNullOrEmpty
            Should -Invoke Invoke-OERGraphRequest -Times 1 -Exactly
        }
    }

    It 'throws AmbiguousName naming every candidate id when two policies carry the name, and returns no id' {
        InModuleScope Omnicit.EntraRBAC {
            Mock Invoke-OERGraphRequest {
                @{ value = @(
                        @{ id = '33333333-3333-3333-3333-333333333333'; displayName = 'Standard' }
                        @{ id = '55555555-5555-5555-5555-555555555555'; displayName = 'Standard' }
                    ) }
            }
            $R = $null
            $Thrown = { $R = Resolve-OERAssignmentPolicyId -AccessPackageId '11111111-1111-1111-1111-111111111111' -AssignmentPolicy 'Standard' -AccessPackageLabel 'AP-Sales' } |
                Should -Throw -PassThru
            $R | Should -BeNullOrEmpty
            Should -Invoke Invoke-OERGraphRequest -Times 1 -Exactly
            [string]$Thrown.FullyQualifiedErrorId | Should -BeLike 'AmbiguousName*'
            $Thrown.CategoryInfo.Category | Should -Be 'InvalidArgument'
            $Thrown.TargetObject | Should -BeExactly 'Standard'
            $Thrown.Exception.Message | Should -BeExactly ("Assignment policy display name 'Standard' matches 2 policies " +
                "(33333333-3333-3333-3333-333333333333, 55555555-5555-5555-5555-555555555555) in access package 'AP-Sales'. " +
                'Access packages do not enforce unique policy display names, so this name cannot identify a single policy. ' +
                'Re-run with the assignment policy id instead of the display name.')
        }
    }

    It 'names the access package id in the ambiguity message when no -AccessPackageLabel is given' {
        InModuleScope Omnicit.EntraRBAC {
            Mock Invoke-OERGraphRequest {
                @{ value = @(
                        @{ id = '33333333-3333-3333-3333-333333333333'; displayName = 'Standard' }
                        @{ id = '55555555-5555-5555-5555-555555555555'; displayName = 'Standard' }
                        @{ id = '66666666-6666-6666-6666-666666666666'; displayName = 'Standard' }
                    ) }
            }
            $Thrown = { Resolve-OERAssignmentPolicyId -AccessPackageId '11111111-1111-1111-1111-111111111111' -AssignmentPolicy 'Standard' } |
                Should -Throw -PassThru
            [string]$Thrown.FullyQualifiedErrorId | Should -BeLike 'AmbiguousName*'
            $Thrown.Exception.Message | Should -BeLike ("Assignment policy display name 'Standard' matches 3 policies (*66666666-6666-6666-6666-666666666666) " +
                "in access package '11111111-1111-1111-1111-111111111111'. *")
        }
    }

    It 'lets a failed listing propagate as itself, never as a not-found' {
        InModuleScope Omnicit.EntraRBAC {
            Mock Invoke-OERGraphRequest {
                throw [System.Management.Automation.ErrorRecord]::new(
                    [System.Exception]::new('Authorization_RequestDenied: Insufficient privileges to complete the operation.'),
                    'Authorization_RequestDenied', [System.Management.Automation.ErrorCategory]::PermissionDenied, 'policy listing')
            }
            $Thrown = { Resolve-OERAssignmentPolicyId -AccessPackageId '11111111-1111-1111-1111-111111111111' -AssignmentPolicy 'Standard' } |
                Should -Throw -PassThru
            [string]$Thrown.FullyQualifiedErrorId | Should -BeLike 'Authorization_RequestDenied*'
            $Thrown.CategoryInfo.Category | Should -Be 'PermissionDenied'
            $Thrown.Exception.Message | Should -BeExactly 'Authorization_RequestDenied: Insufficient privileges to complete the operation.'
            $Thrown.TargetObject | Should -BeExactly 'policy listing'
        }
    }
}
