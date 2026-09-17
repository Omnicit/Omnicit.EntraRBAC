BeforeAll {
    Import-Module Omnicit.EntraRBAC -Force
}

Describe 'ConvertTo-OERAssignmentRequest' {
    It 'maps the modern v1.0 state/status spelling' {
        InModuleScope Omnicit.EntraRBAC {
            $Raw = @{
                id                = 'req-1'
                requestType       = 'adminAdd'
                state             = 'submitted'
                status            = 'Accepted'
                justification     = 'onboarding'
                createdDateTime   = '2026-08-12T09:00:00Z'
                completedDateTime = $null
            }
            $Out = ConvertTo-OERAssignmentRequest -InputObject $Raw -AccessPackageId 'ap-1' -AssignmentPolicyId 'pol-1' -TargetId 'usr-1'
            $Out.RequestId | Should -Be 'req-1'
            $Out.RequestType | Should -Be 'adminAdd'
            $Out.State | Should -Be 'submitted'
            $Out.Status | Should -Be 'Accepted'
            $Out.Justification | Should -Be 'onboarding'
            $Out.TargetId | Should -Be 'usr-1'
            $Out.AccessPackageId | Should -Be 'ap-1'
            $Out.AssignmentPolicyId | Should -Be 'pol-1'
            $Out.CreatedDateTime | Should -Be '2026-08-12T09:00:00Z'
        }
    }

    It 'falls back to the requestState/requestStatus spelling the same endpoint also returns' {
        InModuleScope Omnicit.EntraRBAC {
            $Raw = @{ id = 'req-2'; requestType = 'adminAdd'; requestState = 'Submitted'; requestStatus = 'Accepted' }
            $Out = ConvertTo-OERAssignmentRequest -InputObject $Raw
            $Out.State | Should -Be 'Submitted'
            $Out.Status | Should -Be 'Accepted'
        }
    }

    It 'tags the output with the AssignmentRequest type name' {
        InModuleScope Omnicit.EntraRBAC {
            $Out = ConvertTo-OERAssignmentRequest -InputObject @{ id = 'r' }
            $Out.PSObject.TypeNames[0] | Should -Be 'Omnicit.EntraRBAC.AssignmentRequest'
        }
    }

    It 'does not expose a bare Id, so a request id cannot bind Remove-OERAccessPackageAssignment -AssignmentId' {
        InModuleScope Omnicit.EntraRBAC {
            $Out = ConvertTo-OERAssignmentRequest -InputObject @{ id = 'r' }
            $Out.PSObject.Properties.Name | Should -Not -Contain 'Id'
        }
    }

    It 'accepts pipeline input' {
        InModuleScope Omnicit.EntraRBAC {
            $Out = @(@{ id = 'a' }, @{ id = 'b' }) | ConvertTo-OERAssignmentRequest
            @($Out).Count | Should -Be 2
            $Out[1].RequestId | Should -Be 'b'
        }
    }
}
