BeforeAll {
    $script:moduleName = 'Omnicit.EntraRBAC'
    Get-Module $script:moduleName | Remove-Module -Force -ErrorAction SilentlyContinue
    Import-Module $script:moduleName -Force -ErrorAction Stop
}

Describe 'ConvertTo-OERAccessPackage' {
    It 'maps Graph properties and tags the type' {
        InModuleScope $script:moduleName {
            $Raw = @{ id = 'ap-1'; displayName = 'AP-Sales'; description = 'Sales access'; isHidden = $true; catalogId = 'cat-1' }
            $Out = ConvertTo-OERAccessPackage -InputObject $Raw
            $Out.Id | Should -Be 'ap-1'
            $Out.DisplayName | Should -Be 'AP-Sales'
            $Out.Description | Should -Be 'Sales access'
            $Out.CatalogId | Should -Be 'cat-1'
            $Out.IsHidden | Should -BeTrue
            $Out.PSObject.TypeNames[0] | Should -Be 'Omnicit.EntraRBAC.AccessPackage'
        }
    }

    It 'falls back to catalog.id when catalogId is absent' {
        InModuleScope $script:moduleName {
            $Raw = @{ id = 'ap-2'; displayName = 'AP-HR'; catalog = @{ id = 'cat-9' } }
            $Out = ConvertTo-OERAccessPackage -InputObject $Raw
            $Out.CatalogId | Should -Be 'cat-9'
        }
    }

    It 'coerces a missing isHidden to $false' {
        InModuleScope $script:moduleName {
            $Out = ConvertTo-OERAccessPackage -InputObject @{ id = 'ap-3'; displayName = 'AP-Test' }
            $Out.IsHidden | Should -BeFalse
        }
    }

    It 'yields a null CatalogId for a bare v1.0 accessPackage, which has neither catalogId nor catalog' {
        InModuleScope $script:moduleName {
            # The v1.0 accessPackage entity exposes only createdDateTime, description, displayName, id,
            # isHidden and modifiedDateTime. There is no catalogId property, and catalog is a navigation
            # property absent from an unexpanded response, so the converter has no source to read and
            # CatalogId is $null. This is why Get-OERAccessPackage expands catalog unconditionally.
            $Raw = @{
                id               = 'ap-5'
                displayName      = 'AP-Bare'
                description      = 'no catalog anywhere in this payload'
                isHidden         = $false
                createdDateTime  = '2026-08-01T00:00:00Z'
                modifiedDateTime = '2026-08-02T00:00:00Z'
            }
            $Out = ConvertTo-OERAccessPackage -InputObject $Raw
            # Prove the object is real before measuring it: $null.CatalogId is also $null, so a bare
            # BeNullOrEmpty would pass just as happily on nothing at all.
            $Out | Should -Not -BeNullOrEmpty
            $Out.Id | Should -BeExactly 'ap-5'
            $Out.PSObject.Properties.Name | Should -Contain 'CatalogId'
            $Out.CatalogId | Should -BeNullOrEmpty
        }
    }

    It 'accepts pipeline input' {
        InModuleScope $script:moduleName {
            $Raw = @{ id = 'ap-4'; displayName = 'AP-Pipe'; catalogId = 'cat-2' }
            $Out = $Raw | ConvertTo-OERAccessPackage
            $Out.Id | Should -Be 'ap-4'
            $Out.PSObject.TypeNames[0] | Should -Be 'Omnicit.EntraRBAC.AccessPackage'
        }
    }

    It 'surfaces AssignmentPolicies, routed through ConvertTo-OERAssignmentPolicy, when the input carries assignmentPolicies (#58)' {
        InModuleScope $script:moduleName {
            $Raw = @{
                id                 = 'ap-6'
                displayName        = 'AP-Policies'
                assignmentPolicies = @(
                    @{ id = 'pol-1'; displayName = 'Default'; allowedTargetScope = 'allMemberUsers' }
                )
            }
            $Out = ConvertTo-OERAccessPackage -InputObject $Raw
            $Out.AssignmentPolicies.Count | Should -Be 1
            $Out.AssignmentPolicies[0].DisplayName | Should -Be 'Default'
            $Out.AssignmentPolicies[0].AccessPackageId | Should -Be 'ap-6'
            $Out.AssignmentPolicies[0].PSObject.TypeNames[0] | Should -Be 'Omnicit.EntraRBAC.AssignmentPolicy'
        }
    }

    It 'surfaces ResourceRoleScopes, routed through ConvertTo-OERAccessPackageResourceRole, with ResourceDisplayName left null (#58)' {
        InModuleScope $script:moduleName {
            # ResourceDisplayName MUST stay $null here: joining it against catalog resources requires a
            # second Graph call, and this private converter must never make a transport call.
            $Raw = @{
                id                 = 'ap-7'
                displayName        = 'AP-Roles'
                resourceRoleScopes = @(
                    @{ id = 'rrs-1'; role = @{ displayName = 'Member' }; scope = @{ displayName = 'Root'; originId = 'grp-1'; originSystem = 'AadGroup' } }
                )
            }
            $Out = ConvertTo-OERAccessPackage -InputObject $Raw
            $Out.ResourceRoleScopes.Count | Should -Be 1
            $Out.ResourceRoleScopes[0].RoleName | Should -Be 'Member'
            $Out.ResourceRoleScopes[0].AccessPackageId | Should -Be 'ap-7'
            $Out.ResourceRoleScopes[0].ResourceDisplayName | Should -BeNullOrEmpty
            $Out.ResourceRoleScopes[0].PSObject.TypeNames[0] | Should -Be 'Omnicit.EntraRBAC.AccessPackageResourceRole'
        }
    }

    It 'treats an empty expanded array as PRESENT (not absent) on a hashtable input -- presence, not truthiness (#58)' {
        # A truthiness rewrite (if ($InputObject.assignmentPolicies)) would ALSO pass every other
        # #58 test in this file, since they all feed either a non-empty array or no key at all. An
        # empty array is falsy in PowerShell, so this is the one input shape that actually
        # discriminates presence-checking from truthiness-checking. A fresh catalog's first access
        # package -- zero policies, zero resource roles -- is the common case this guards.
        InModuleScope $script:moduleName {
            $Raw = @{ id = 'ap-10'; displayName = 'AP-Empty'; assignmentPolicies = @(); resourceRoleScopes = @() }
            $Out = ConvertTo-OERAccessPackage -InputObject $Raw
            # Both halves are needed: an absent property fails -Contain; $null (or a scalar) fails
            # the count check too, since @($null).Count is 1, not 0.
            $Out.PSObject.Properties.Name | Should -Contain 'AssignmentPolicies'
            $Out.PSObject.Properties.Name | Should -Contain 'ResourceRoleScopes'
            @($Out.AssignmentPolicies).Count | Should -Be 0
            @($Out.ResourceRoleScopes).Count | Should -Be 0
        }
    }

    It 'treats an empty expanded array as PRESENT on a PSObject input, not only a hashtable one (#58)' {
        # Every other #58 test in this file feeds a [hashtable] (the ContainsKey branch of the
        # presence check). A PSCustomObject input -- as ConvertTo-OERAssignmentPolicy's own
        # dual-shape re-run pattern documents callers may pass -- exercises the OTHER half of the
        # presence check (.PSObject.Properties.Name -contains), which no test reached before this one.
        InModuleScope $script:moduleName {
            $Raw = [PSCustomObject]@{ id = 'ap-11'; displayName = 'AP-Empty-PSObj'; assignmentPolicies = @(); resourceRoleScopes = @() }
            $Out = ConvertTo-OERAccessPackage -InputObject $Raw
            $Out.PSObject.Properties.Name | Should -Contain 'AssignmentPolicies'
            $Out.PSObject.Properties.Name | Should -Contain 'ResourceRoleScopes'
            @($Out.AssignmentPolicies).Count | Should -Be 0
            @($Out.ResourceRoleScopes).Count | Should -Be 0
        }
    }

    It 'omits AssignmentPolicies and ResourceRoleScopes entirely when the input does not carry them (#58)' {
        InModuleScope $script:moduleName {
            $Out = ConvertTo-OERAccessPackage -InputObject @{ id = 'ap-8'; displayName = 'AP-Bare' }
            $Out.PSObject.Properties.Name | Should -Not -Contain 'AssignmentPolicies'
            $Out.PSObject.Properties.Name | Should -Not -Contain 'ResourceRoleScopes'
        }
    }

    It 'appends AssignmentPolicies and ResourceRoleScopes after the five original properties, preserving member order (#58)' {
        InModuleScope $script:moduleName {
            $Raw = @{
                id                 = 'ap-9'
                displayName        = 'AP-Order'
                assignmentPolicies = @(@{ id = 'pol-1' })
                resourceRoleScopes = @(@{ id = 'rrs-1' })
            }
            $Out = ConvertTo-OERAccessPackage -InputObject $Raw
            $Names = @($Out.PSObject.Properties.Name)
            $Names[0..4] | Should -Be @('Id', 'DisplayName', 'Description', 'CatalogId', 'IsHidden')
            $Names | Should -Contain 'AssignmentPolicies'
            $Names | Should -Contain 'ResourceRoleScopes'
            ([array]::IndexOf($Names, 'AssignmentPolicies')) | Should -BeGreaterThan 4
            ([array]::IndexOf($Names, 'ResourceRoleScopes')) | Should -BeGreaterThan 4
        }
    }
}
