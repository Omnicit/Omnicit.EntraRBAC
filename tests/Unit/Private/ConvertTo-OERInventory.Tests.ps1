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

Describe 'ConvertTo-OERInventory' {
    It 'tags the output Omnicit.EntraRBAC.Inventory and sets Version' {
        InModuleScope $script:moduleName {
            $Out = ConvertTo-OERInventory
            $Out.PSObject.TypeNames[0] | Should -Be 'Omnicit.EntraRBAC.Inventory'
            $Out.Version | Should -Be '1.0'
        }
    }

    It 'defaults every section to an empty array' {
        InModuleScope $script:moduleName {
            $Out = ConvertTo-OERInventory
            foreach ($Section in 'Groups','AdministrativeUnits','Catalogs','AccessPackages','AccessReviews',
                'DirectoryRoleManagementPolicies','DirectoryRoleAssignments','RoleAssignments','RoleManagementPolicies') {
                @($Out.$Section).Count | Should -Be 0
            }
        }
    }

    It 'passes supplied section arrays through unchanged' {
        InModuleScope $script:moduleName {
            $Groups = @([PSCustomObject]@{ displayName = 'g1' }, [PSCustomObject]@{ displayName = 'g2' })
            $Out = ConvertTo-OERInventory -Groups $Groups -Catalogs @([PSCustomObject]@{ displayName = 'c1' })
            @($Out.Groups).Count | Should -Be 2
            $Out.Groups[0].displayName | Should -Be 'g1'
            @($Out.Catalogs).Count | Should -Be 1
        }
    }

    It 'passes the directory role sections through unchanged' {
        InModuleScope $script:moduleName {
            $Out = ConvertTo-OERInventory `
                -DirectoryRoleManagementPolicies @([PSCustomObject]@{ role = 'Fixture Role A' }) `
                -DirectoryRoleAssignments @(
                    [PSCustomObject]@{ role = 'Fixture Role A'; principal = 'person1@example.com'; assignmentType = 'Eligible' }
                    [PSCustomObject]@{ role = 'Fixture Role A'; principal = 'person2@example.com'; assignmentType = 'Active' }
                )
            @($Out.directoryRoleManagementPolicies).Count | Should -Be 1
            $Out.directoryRoleManagementPolicies[0].role | Should -BeExactly 'Fixture Role A'
            @($Out.directoryRoleAssignments).Count | Should -Be 2
            $Out.directoryRoleAssignments[1].principal | Should -BeExactly 'person2@example.com'
        }
    }

    It 'serializes to a document that validates against the shipped schema.json' -Skip:(-not (Get-Command Test-Json).Parameters.ContainsKey('Schema')) {
        InModuleScope $script:moduleName {
            # This is the module's headline loop: Export-OERInventory writes this object as
            # inventory.json and Get-OERStructureSchemaJson beside it as schema.json. The root keys
            # were PascalCase while the schema declares lowercase, additionalProperties:false and
            # required:["version"], so every exported document was rejected by its own schema.
            $Out = ConvertTo-OERInventory `
                -Groups @([PSCustomObject]@{ displayName = 'role_sec_identity_reader' }) `
                -AdministrativeUnits @([PSCustomObject]@{ displayName = 'au-nordics' }) `
                -Catalogs @([PSCustomObject]@{ displayName = 'CAT-IT-Core' }) `
                -AccessPackages @([PSCustomObject]@{ displayName = 'AP-Reader'; catalog = 'CAT-IT-Core' }) `
                -AccessReviews @([PSCustomObject]@{ displayName = 'AR-Quarterly'; accessPackage = 'AP-Reader'; assignmentPolicy = 'AP-Reader-Policy' }) `
                -DirectoryRoleManagementPolicies @([PSCustomObject]@{ role = 'Fixture Role A'; requireApproval = $false }) `
                -DirectoryRoleAssignments @([PSCustomObject]@{ role = 'Fixture Role A'; principal = 'person1@example.com'; principalType = 'User'; assignmentType = 'Eligible'; durationDays = 30 }) `
                -RoleAssignments @([PSCustomObject]@{ scope = '/subscriptions/00000000-0000-0000-0000-000000000001'; role = 'Reader'; principal = 'role_sec_identity_reader' }) `
                -RoleManagementPolicies @([PSCustomObject]@{ scope = '/subscriptions/00000000-0000-0000-0000-000000000001'; role = 'Reader' })
            $Json = $Out | ConvertTo-Json -Depth 32
            Test-Json -Json $Json -Schema (Get-OERStructureSchemaJson) -ErrorAction SilentlyContinue |
                Should -Be $true
        }
    }

    It 'stores the root keys in the schema spelling and stores no second copy' {
        InModuleScope $script:moduleName {
            $Out = ConvertTo-OERInventory
            $Names = @($Out.PSObject.Properties.Name)
            # -ccontains is case-SENSITIVE on purpose: it is the only operator that can tell the two
            # spellings apart, and the point of this assertion is that exactly one of them is stored.
            foreach ($Key in 'version', 'groups', 'administrativeUnits', 'catalogs', 'accessPackages',
                'accessReviews', 'directoryRoleManagementPolicies', 'directoryRoleAssignments', 'roleAssignments',
                'roleManagementPolicies') {
                $Names -ccontains $Key | Should -Be $true -Because "'$Key' is the spelling schema.json declares"
            }
            foreach ($Key in 'Version', 'Groups', 'AdministrativeUnits', 'Catalogs', 'AccessPackages',
                'AccessReviews', 'DirectoryRoleManagementPolicies', 'DirectoryRoleAssignments', 'RoleAssignments',
                'RoleManagementPolicies') {
                $Names -ccontains $Key | Should -Be $false -Because "a second stored copy of '$Key' would violate additionalProperties:false"
            }
            $Names.Count | Should -Be 10
        }
    }

    It 'emits the sections in the order the apply engine dispatches them' {
        InModuleScope $script:moduleName {
            $Out = ConvertTo-OERInventory
            @($Out.PSObject.Properties.Name) | Should -Be @('version', 'groups', 'administrativeUnits', 'catalogs',
                'accessPackages', 'accessReviews', 'directoryRoleManagementPolicies', 'directoryRoleAssignments',
                'roleAssignments', 'roleManagementPolicies')
        }
    }

    It 'keeps PascalCase property access working for existing PowerShell consumers' {
        InModuleScope $script:moduleName {
            # Backward-compatibility direction 1. PowerShell member lookup is case-insensitive, so
            # $Inventory.Groups resolves the stored 'groups' key with no alias. A case-only ETS alias
            # cannot be registered at all (member names collide case-insensitively), which is why
            # suffix.ps1 is not involved.
            $Out = ConvertTo-OERInventory -Groups @([PSCustomObject]@{ displayName = 'g1' }, [PSCustomObject]@{ displayName = 'g2' })
            $Out.Version | Should -Be '1.0'
            @($Out.Groups).Count | Should -Be 2
            $Out.Groups[0].displayName | Should -Be 'g1'
            @($Out | Select-Object -ExpandProperty Groups).Count | Should -Be 2
            $Out.PSObject.Properties['Groups'].Name | Should -Be 'groups'
            @($Out.RoleManagementPolicies).Count | Should -Be 0
        }
    }

    Context 'tenantId (BL-88, A14)' {
        It 'emits tenantId directly after version when -TenantId is a GUID' {
            InModuleScope $script:moduleName {
                $Out = ConvertTo-OERInventory -TenantId '44444444-4444-4444-4444-444444444444'
                $Out.tenantId | Should -BeExactly '44444444-4444-4444-4444-444444444444'
                $Names = @($Out.PSObject.Properties.Name)
                $Names[0..2] | Should -Be @('version', 'tenantId', 'groups')
                $Names.Count | Should -Be 11
            }
        }

        It 'keeps the nine sections in their existing order after tenantId' {
            InModuleScope $script:moduleName {
                $Out = ConvertTo-OERInventory -TenantId '44444444-4444-4444-4444-444444444444'
                @($Out.PSObject.Properties.Name) | Should -Be @('version', 'tenantId', 'groups', 'administrativeUnits',
                    'catalogs', 'accessPackages', 'accessReviews', 'directoryRoleManagementPolicies',
                    'directoryRoleAssignments', 'roleAssignments', 'roleManagementPolicies')
            }
        }

        It 'stores tenantId in the schema spelling, once' {
            InModuleScope $script:moduleName {
                $Names = @((ConvertTo-OERInventory -TenantId '44444444-4444-4444-4444-444444444444').PSObject.Properties.Name)
                $Names -ccontains 'tenantId' | Should -Be $true
                $Names -ccontains 'TenantId' | Should -Be $false -Because 'a second stored copy would violate additionalProperties:false'
            }
        }

        It 'still tags the object Omnicit.EntraRBAC.Inventory and carries the sections it was given' {
            InModuleScope $script:moduleName {
                $Out = ConvertTo-OERInventory -TenantId '44444444-4444-4444-4444-444444444444' `
                    -Groups @([PSCustomObject]@{ displayName = 'g1' })
                $Out.PSObject.TypeNames[0] | Should -Be 'Omnicit.EntraRBAC.Inventory'
                $Out.Version | Should -Be '1.0'
                @($Out.Groups).Count | Should -Be 1
                $Out.Groups[0].displayName | Should -Be 'g1'
            }
        }

        It 'leaves tenantId out when -TenantId is <Label>' -ForEach @(
            @{ Label = 'not given'; Splat = @{} }
            @{ Label = 'empty'; Splat = @{ TenantId = '' } }
            @{ Label = 'a domain'; Splat = @{ TenantId = 'contoso.onmicrosoft.com' } }
            @{ Label = 'organizations'; Splat = @{ TenantId = 'organizations' } }
            @{ Label = 'a braced GUID'; Splat = @{ TenantId = '{44444444-4444-4444-4444-444444444444}' } }
            @{ Label = 'a dash-less GUID'; Splat = @{ TenantId = '44444444444444444444444444444444' } }
        ) {
            InModuleScope $script:moduleName -Parameters @{ Splat = $Splat } {
                param($Splat)
                $Out = ConvertTo-OERInventory @Splat
                $Out.PSObject.Properties.Name | Should -Not -Contain 'tenantId'
                @($Out.PSObject.Properties.Name).Count | Should -Be 10
                @($Out.PSObject.Properties.Name)[0..1] | Should -Be @('version', 'groups')
            }
        }

        It 'serializes with tenantId to a document that validates against the shipped schema.json' -Skip:(-not (Get-Command Test-Json).Parameters.ContainsKey('Schema')) {
            InModuleScope $script:moduleName {
                $Out = ConvertTo-OERInventory -TenantId '44444444-4444-4444-4444-444444444444' `
                    -Groups @([PSCustomObject]@{ displayName = 'role_sec_identity_reader' })
                $Json = $Out | ConvertTo-Json -Depth 32
                $Json | Should -Match '"tenantId":\s*"44444444-4444-4444-4444-444444444444"'
                Test-Json -Json $Json -Schema (Get-OERStructureSchemaJson) -ErrorAction SilentlyContinue |
                    Should -Be $true
            }
        }
    }
}
