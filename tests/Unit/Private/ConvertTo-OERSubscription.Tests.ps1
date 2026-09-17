BeforeAll {
    Import-Module Omnicit.EntraRBAC -Force
}

Describe 'ConvertTo-OERSubscription' {
    It 'tags the type and maps properties including the SubscriptionId pipeline alias' {
        InModuleScope Omnicit.EntraRBAC {
            $Raw = [PSCustomObject]@{
                id             = '/subscriptions/00000000-0000-0000-0000-000000000060'
                subscriptionId = '00000000-0000-0000-0000-000000000060'
                displayName    = 'Example Subscription'
                state          = 'Enabled'
                tenantId       = '00000000-0000-0000-0000-000000000061'
                tags           = [PSCustomObject]@{ env = 'prod' }
            }
            $Out = ConvertTo-OERSubscription -InputObject $Raw
            $Out.PSObject.TypeNames[0] | Should -Be 'Omnicit.EntraRBAC.Subscription'
            $Out.ResourceId | Should -Be '/subscriptions/00000000-0000-0000-0000-000000000060'
            $Out.PSObject.Properties.Name | Should -Not -Contain 'Id'
            $Out.SubscriptionId | Should -Be '00000000-0000-0000-0000-000000000060'
            $Out.DisplayName | Should -Be 'Example Subscription'
            $Out.State | Should -Be 'Enabled'
            $Out.TenantId | Should -Be '00000000-0000-0000-0000-000000000061'
            $Out.Tags.env | Should -Be 'prod'
        }
    }

    It 'exposes the ARM path only as ResourceId so a piped subscription cannot set a schedule id' {
        InModuleScope Omnicit.EntraRBAC {
            $Out = ConvertTo-OERSubscription -InputObject @{
                id = '/subscriptions/11111111-1111-1111-1111-111111111111'
                subscriptionId = '11111111-1111-1111-1111-111111111111'
                displayName = 'Prod'
                state = 'Enabled'
            }
            $Out.ResourceId | Should -Be '/subscriptions/11111111-1111-1111-1111-111111111111'
            $Out.PSObject.Properties.Name | Should -Not -Contain 'Id'
        }
    }

    It 'exposes the ARM path as ResourceId and never as a bare Id' {
        InModuleScope Omnicit.EntraRBAC {
            $Out = ConvertTo-OERSubscription -InputObject @{
                id             = '/subscriptions/aaaa0000-0000-0000-0000-000000000001'
                subscriptionId = 'aaaa0000-0000-0000-0000-000000000001'
                displayName    = 'Sub'
            }
            $Out.ResourceId | Should -Be '/subscriptions/aaaa0000-0000-0000-0000-000000000001'
            $Out.PSObject.Properties.Name | Should -Not -Contain 'Id'
        }
    }

    It 'does not bind Get-OERRoleManagementPolicy -PolicyId when piped, so the scope parameter set wins' {
        Mock -ModuleName Omnicit.EntraRBAC Initialize-OERAuth { }
        $Sub = InModuleScope Omnicit.EntraRBAC {
            ConvertTo-OERSubscription -InputObject @{
                id = '/subscriptions/11111111-1111-1111-1111-111111111111'
                subscriptionId = '11111111-1111-1111-1111-111111111111'
                displayName = 'Prod'; state = 'Enabled'
            }
        }
        $Bound = @($Sub.PSObject.Properties.Name)
        $Bound | Should -Not -Contain 'Id'
        $Bound | Should -Not -Contain 'PolicyId'
        $Bound | Should -Not -Contain 'RoleEligibilityScheduleId'
    }
}
