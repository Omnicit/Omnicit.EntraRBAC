BeforeAll {
    Import-Module Omnicit.EntraRBAC -Force
}

Describe 'ConvertTo-OERTenantConfiguration' {
    It 'emits every field of the single tenant configuration shape' {
        InModuleScope Omnicit.EntraRBAC {
            $Out = ConvertTo-OERTenantConfiguration -TenantAlias 'contoso' -TenantId '11111111-1111-1111-1111-111111111111' `
                -Naming @{ Group = 'role_sec_{area}' } -Defaults @{ ActivationMaxHours = 8 } -Path 'C:\p\contoso.psd1'
            $Out.TenantAlias | Should -Be 'contoso'
            $Out.TenantId | Should -Be '11111111-1111-1111-1111-111111111111'
            $Out.Naming.Group | Should -Be 'role_sec_{area}'
            $Out.Defaults.ActivationMaxHours | Should -Be 8
            $Out.Path | Should -Be 'C:\p\contoso.psd1'
        }
    }

    It 'tags the output with the TenantConfiguration type name' {
        InModuleScope Omnicit.EntraRBAC {
            $Out = ConvertTo-OERTenantConfiguration -TenantAlias 'a' -TenantId 'b' -Path 'c'
            $Out.PSObject.TypeNames[0] | Should -Be 'Omnicit.EntraRBAC.TenantConfiguration'
        }
    }

    It 'always exposes Naming and Defaults, as null when they were not supplied' {
        InModuleScope Omnicit.EntraRBAC {
            $Out = ConvertTo-OERTenantConfiguration -TenantAlias 'a' -TenantId 'b' -Path 'c'
            $Out.PSObject.Properties.Name | Should -Contain 'Naming'
            $Out.PSObject.Properties.Name | Should -Contain 'Defaults'
            $Out.Naming | Should -BeNullOrEmpty
            $Out.Defaults | Should -BeNullOrEmpty
        }
    }

    It 'emits the properties in the canonical order' {
        InModuleScope Omnicit.EntraRBAC {
            $Out = ConvertTo-OERTenantConfiguration -TenantAlias 'a' -TenantId 'b' -Path 'c'
            @($Out.PSObject.Properties.Name) -join ',' |
                Should -Be 'TenantAlias,TenantId,Environment,Naming,Defaults,Path'
        }
    }

    # -------------------------------------------------------------------------------------------
    # Sovereign clouds (Sprint 1.5, issue #81, Task 5): Environment joins the output shape.
    # -------------------------------------------------------------------------------------------
    It 'emits the supplied Environment value' {
        InModuleScope Omnicit.EntraRBAC {
            $Out = ConvertTo-OERTenantConfiguration -TenantAlias 'contoso' -TenantId 'tid' -Environment 'USGov' -Path 'c'
            $Out.Environment | Should -Be 'USGov'
        }
    }

    It 'exposes Environment as null when it was not supplied' {
        InModuleScope Omnicit.EntraRBAC {
            $Out = ConvertTo-OERTenantConfiguration -TenantAlias 'a' -TenantId 'b' -Path 'c'
            $Out.PSObject.Properties.Name | Should -Contain 'Environment'
            $Out.Environment | Should -BeNullOrEmpty
        }
    }
}
