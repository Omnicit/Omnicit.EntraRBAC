BeforeAll {
    $script:moduleName = 'Omnicit.EntraRBAC'
    Get-Module $script:moduleName | Remove-Module -Force -ErrorAction SilentlyContinue
    Import-Module $script:moduleName -Force -ErrorAction Stop
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
            foreach ($Section in 'Groups','AdministrativeUnits','Catalogs','AccessPackages','AccessReviews','RoleAssignments','RoleManagementPolicies') {
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
                'accessReviews', 'roleAssignments', 'roleManagementPolicies') {
                $Names -ccontains $Key | Should -Be $true -Because "'$Key' is the spelling schema.json declares"
            }
            foreach ($Key in 'Version', 'Groups', 'AdministrativeUnits', 'Catalogs', 'AccessPackages',
                'AccessReviews', 'RoleAssignments', 'RoleManagementPolicies') {
                $Names -ccontains $Key | Should -Be $false -Because "a second stored copy of '$Key' would violate additionalProperties:false"
            }
            $Names.Count | Should -Be 8
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
}
