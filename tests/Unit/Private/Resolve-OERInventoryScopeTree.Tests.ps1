BeforeAll {
    $script:moduleName = 'Omnicit.EntraRBAC'
    Get-Module $script:moduleName | Remove-Module -Force -ErrorAction SilentlyContinue
    Import-Module $script:moduleName -Force -ErrorAction Stop
}

Describe 'Resolve-OERInventoryScopeTree' {
    BeforeEach {
        InModuleScope $script:moduleName { $script:_OERAuthState = $null }
        Mock -ModuleName $script:moduleName Initialize-OERAuth {}
    }

    It 'returns every management group and subscription as scopes plus a hierarchy' {
        Mock -ModuleName $script:moduleName Get-OERManagementGroup {
            [PSCustomObject]@{ Name = 'Root'; DisplayName = 'Tenant Root'; ResourceId = '/providers/Microsoft.Management/managementGroups/Root' }
            [PSCustomObject]@{ Name = 'Platform'; DisplayName = 'Platform'; ResourceId = '/providers/Microsoft.Management/managementGroups/Platform' }
        }
        Mock -ModuleName $script:moduleName Get-OERSubscription {
            [PSCustomObject]@{ SubscriptionId = '1111'; DisplayName = 'Prod'; ResourceId = '/subscriptions/1111'; State = 'Enabled' }
        }
        InModuleScope $script:moduleName {
            $Tree = Resolve-OERInventoryScopeTree
            $Tree.Scopes | Should -Contain '/providers/Microsoft.Management/managementGroups/Root'
            $Tree.Scopes | Should -Contain '/providers/Microsoft.Management/managementGroups/Platform'
            $Tree.Scopes | Should -Contain '/subscriptions/1111'
            @($Tree.Hierarchy.managementGroups).Count | Should -Be 2
            @($Tree.Hierarchy.subscriptions).Count | Should -Be 1
            $Tree.Hierarchy.subscriptions[0].displayName | Should -Be 'Prod'
            $Tree.Hierarchy.subscriptions[0].id | Should -Be '/subscriptions/1111'
            $Tree.Hierarchy.managementGroups[0].id | Should -Be '/providers/Microsoft.Management/managementGroups/Root'
        }
    }

    It 'narrows to a single management group branch when -ManagementGroup is given' {
        Mock -ModuleName $script:moduleName Get-OERManagementGroup {
            param($Name)
            [PSCustomObject]@{ Name = 'Platform'; DisplayName = 'Platform'; ResourceId = '/providers/Microsoft.Management/managementGroups/Platform' }
        }
        Mock -ModuleName $script:moduleName Get-OERSubscription {
            [PSCustomObject]@{ SubscriptionId = '2222'; DisplayName = 'Plat-Sub'; ResourceId = '/subscriptions/2222'; State = 'Enabled' }
        }
        InModuleScope $script:moduleName {
            $Tree = Resolve-OERInventoryScopeTree -ManagementGroup 'Platform'
            $Tree.Scopes | Should -Contain '/providers/Microsoft.Management/managementGroups/Platform'
            $Tree.Scopes | Should -Contain '/subscriptions/2222'
        }
        Should -Invoke -ModuleName $script:moduleName Get-OERSubscription -Times 1 -ParameterFilter { $ManagementGroup -eq 'Platform' }
    }

    It 'returns exactly the supplied raw scope when -Scope is given' {
        Mock -ModuleName $script:moduleName Get-OERManagementGroup { }
        InModuleScope $script:moduleName {
            $Tree = Resolve-OERInventoryScopeTree -Scope '/subscriptions/abc'
            @($Tree.Scopes).Count | Should -Be 1
            $Tree.Scopes[0] | Should -Be '/subscriptions/abc'
        }
        Should -Invoke -ModuleName $script:moduleName Get-OERManagementGroup -Times 0
    }

    It 'reads Name off a REAL ConvertTo-OERManagementGroup object via its Task 8a AliasProperty (positive half of the type-tag hazard)' {
        # Line 60 of the source reads [string]$Mg.Name -- Name is no longer a stored NoteProperty on
        # Omnicit.EntraRBAC.ManagementGroup, it is an AliasProperty of ManagementGroupName (Task 8a).
        # An AliasProperty resolves through the TYPE, not the object instance, so this only works while
        # the tag Omnicit.EntraRBAC.ManagementGroup survives on the piped object. Every other test in
        # this file hands Resolve-OERInventoryScopeTree a hand-built fixture with Name as a literal
        # NoteProperty, which would pass identically whether or not the real alias resolves -- this
        # test is the one that actually exercises the real converter's registration.
        Mock -ModuleName $script:moduleName Get-OERManagementGroup {
            InModuleScope $script:moduleName {
                ConvertTo-OERManagementGroup -InputObject @{
                    id         = '/providers/Microsoft.Management/managementGroups/mg-real'
                    name       = 'mg-real'
                    properties = @{ tenantId = 't'; displayName = 'Real MG' }
                }
            }
        }
        Mock -ModuleName $script:moduleName Get-OERSubscription { }
        InModuleScope $script:moduleName {
            $Tree = Resolve-OERInventoryScopeTree
            $Tree.Hierarchy.managementGroups[0].name | Should -Be 'mg-real' -Because (
                'a real ManagementGroup object keeps its type tag through this call, so .Name must still resolve via the AliasProperty')
        }
    }

    It 'pins the type-tag hazard: Name reads $null once the ManagementGroup type tag is stripped (Task 8a documented fragility)' {
        <#
            The other half of the same hazard: an AliasProperty is registered on the TYPE (Update-TypeData
            -TypeName 'Omnicit.EntraRBAC.ManagementGroup' in suffix.ps1), not on the object instance, so
            it only resolves while that tag is present in PSObject.TypeNames. Empirically verified this
            is NOT reproduced by "Select-Object *": Select-Object copies each selected member's CURRENT
            VALUE into a new NoteProperty on the result, so Name (already resolved to its aliased value at
            selection time) survives as a plain NoteProperty even though the result's own type becomes
            'Selected.System.Management.Automation.PSCustomObject'. The real failure mode is narrower and
            more surprising: the SAME object instance, with its type tag cleared directly, silently loses
            the Name member entirely ($null, not merely empty) while ManagementGroupName -- the actually
            stored property -- is completely unaffected. This test does NOT fix that; it PINS the current,
            documented-as-fragile behavior so a future change that starts relying on Name surviving a
            type-stripped object is caught here instead of failing silently downstream in the inventory
            hierarchy JSON.
        #>
        Mock -ModuleName $script:moduleName Get-OERManagementGroup {
            InModuleScope $script:moduleName {
                $Real = ConvertTo-OERManagementGroup -InputObject @{
                    id         = '/providers/Microsoft.Management/managementGroups/mg-stripped'
                    name       = 'mg-stripped'
                    properties = @{ tenantId = 't'; displayName = 'Stripped MG' }
                }
                $Real.PSObject.TypeNames.Clear()
                $Real.PSObject.TypeNames.Add('System.Management.Automation.PSCustomObject')
                $Real
            }
        }
        Mock -ModuleName $script:moduleName Get-OERSubscription { }
        InModuleScope $script:moduleName {
            $Tree = Resolve-OERInventoryScopeTree
            $Tree.Hierarchy.managementGroups[0].name | Should -BeNullOrEmpty -Because (
                'documents the known hazard: Name is bound to the type tag, so a type-stripped object silently loses it -- this is NOT the desired behavior, it is the current one')
            # ManagementGroupName (the actually-stored property) is untouched by the type-tag clear,
            # which is exactly why this is a real, live hazard and not a hypothetical: the value is
            # right there on the object under a different name the whole time.
            $Tree.Hierarchy.managementGroups[0].id | Should -Be '/providers/Microsoft.Management/managementGroups/mg-stripped'
        }
    }
}
