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

Describe 'Resolve-OERInventoryScopeTree' {
    BeforeEach {
        InModuleScope $script:moduleName { $script:_OERAuthState = $null }
        Mock -ModuleName $script:moduleName Initialize-OERAuth {}
    }

    It 'returns every management group and subscription as scopes plus a hierarchy' {
        # The full tree lists through Get-OERManagementGroupList (raw ARM items) and converts them
        # itself; it never reads the parents (A10).
        Mock -ModuleName $script:moduleName Get-OERManagementGroupList {
            [PSCustomObject]@{ id = '/providers/Microsoft.Management/managementGroups/Root'; name = 'Root'; properties = [PSCustomObject]@{ tenantId = 't'; displayName = 'Tenant Root' } }
            [PSCustomObject]@{ id = '/providers/Microsoft.Management/managementGroups/Platform'; name = 'Platform'; properties = [PSCustomObject]@{ tenantId = 't'; displayName = 'Platform' } }
        }
        Mock -ModuleName $script:moduleName Get-OERManagementGroup { }
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
            @($Tree.Hierarchy.managementGroups.name) | Should -Be @('Root', 'Platform')
            @($Tree.Hierarchy.managementGroups.displayName) | Should -Be @('Tenant Root', 'Platform')
        }
        Should -Invoke -ModuleName $script:moduleName Get-OERManagementGroupList -Times 1 -Exactly
        Should -Invoke -ModuleName $script:moduleName Get-OERManagementGroup -Times 0
    }

    It 'walks every listed group without reading a parent, so a failing Entities - List adds no failure mode' {
        # The real Get-OERManagementGroupList and converter run; only the transport is mocked, and
        # the Entities - List path throws. The export must not reach it at all.
        $ArmErr = InModuleScope $script:moduleName {
            Convert-ArmHttpException -Response ([PSCustomObject]@{ StatusCode = 403; Content = '{"error":{"code":"AuthorizationFailed","message":"denied"}}' })
        }
        Mock -ModuleName $script:moduleName Invoke-OERArmRequest -ParameterFilter {
            $Path -like '*/managementGroups?api-version=*'
        } {
            [PSCustomObject]@{ value = @(
                    [PSCustomObject]@{ id = '/providers/Microsoft.Management/managementGroups/t'; name = 't'; type = 'Microsoft.Management/managementGroups'; properties = [PSCustomObject]@{ tenantId = 't'; displayName = 'Tenant Root Group' } }
                    [PSCustomObject]@{ id = '/providers/Microsoft.Management/managementGroups/mg-a'; name = 'mg-a'; type = 'Microsoft.Management/managementGroups'; properties = [PSCustomObject]@{ tenantId = 't'; displayName = 'MG A' } }
                    [PSCustomObject]@{ id = '/providers/Microsoft.Management/managementGroups/mg-b'; name = 'mg-b'; type = 'Microsoft.Management/managementGroups'; properties = [PSCustomObject]@{ tenantId = 't'; displayName = 'MG B' } }
                ) }
        }
        Mock -ModuleName $script:moduleName Invoke-OERArmRequest -ParameterFilter {
            $Path -like '*/getEntities?*'
        } { [CmdletBinding()] param($Path, $Method, $Body, [switch]$All) throw $ArmErr }
        Mock -ModuleName $script:moduleName Get-OERSubscription { }

        $Tree = InModuleScope $script:moduleName { Resolve-OERInventoryScopeTree 3>&1 }
        $Warnings = @($Tree | Where-Object { $_ -is [System.Management.Automation.WarningRecord] })
        $Tree = @($Tree | Where-Object { $_ -isnot [System.Management.Automation.WarningRecord] })[0]

        $Warnings.Count | Should -Be 0
        @($Tree.SkippedScopes).Count | Should -Be 0
        @($Tree.Scopes) | Should -Be @(
            '/providers/Microsoft.Management/managementGroups/t'
            '/providers/Microsoft.Management/managementGroups/mg-a'
            '/providers/Microsoft.Management/managementGroups/mg-b'
        )
        @($Tree.Hierarchy.managementGroups.name) | Should -Be @('t', 'mg-a', 'mg-b')
        Should -Invoke -ModuleName $script:moduleName Invoke-OERArmRequest -Times 0 -ParameterFilter { $Path -like '*/getEntities?*' }
        Should -Invoke -ModuleName $script:moduleName Invoke-OERArmRequest -Times 1 -Exactly -ParameterFilter {
            $Path -ceq '/providers/Microsoft.Management/managementGroups?api-version=2020-05-01' -and $All
        }
    }

    It 'narrows to a single management group branch when -ManagementGroup is given' {
        Mock -ModuleName $script:moduleName Get-OERManagementGroup {
            param($Name)
            [PSCustomObject]@{ Name = 'Platform'; DisplayName = 'Platform'; ResourceId = '/providers/Microsoft.Management/managementGroups/Platform' }
        }
        Mock -ModuleName $script:moduleName Get-OERManagementGroupList { }
        Mock -ModuleName $script:moduleName Get-OERSubscription {
            [PSCustomObject]@{ SubscriptionId = '2222'; DisplayName = 'Plat-Sub'; ResourceId = '/subscriptions/2222'; State = 'Enabled' }
        }
        InModuleScope $script:moduleName {
            $Tree = Resolve-OERInventoryScopeTree -ManagementGroup 'Platform'
            $Tree.Scopes | Should -Contain '/providers/Microsoft.Management/managementGroups/Platform'
            $Tree.Scopes | Should -Contain '/subscriptions/2222'
        }
        Should -Invoke -ModuleName $script:moduleName Get-OERSubscription -Times 1 -ParameterFilter { $ManagementGroup -eq 'Platform' }
        Should -Invoke -ModuleName $script:moduleName Get-OERManagementGroup -Times 1 -Exactly -ParameterFilter { $Name -eq 'Platform' }
        Should -Invoke -ModuleName $script:moduleName Get-OERManagementGroupList -Times 0
    }

    It 'returns exactly the supplied raw scope when -Scope is given' {
        Mock -ModuleName $script:moduleName Get-OERManagementGroup { }
        Mock -ModuleName $script:moduleName Get-OERManagementGroupList { }
        InModuleScope $script:moduleName {
            $Tree = Resolve-OERInventoryScopeTree -Scope '/subscriptions/abc'
            @($Tree.Scopes).Count | Should -Be 1
            $Tree.Scopes[0] | Should -Be '/subscriptions/abc'
        }
        Should -Invoke -ModuleName $script:moduleName Get-OERManagementGroup -Times 0
        Should -Invoke -ModuleName $script:moduleName Get-OERManagementGroupList -Times 0
    }

    It 'reads Name off a REAL ConvertTo-OERManagementGroup object via its Task 8a AliasProperty (positive half of the type-tag hazard)' {
        # The source reads [string]$Mg.Name -- Name is no longer a stored NoteProperty on
        # Omnicit.EntraRBAC.ManagementGroup, it is an AliasProperty of ManagementGroupName (Task 8a).
        # An AliasProperty resolves through the TYPE, not the object instance, so this only works while
        # the tag Omnicit.EntraRBAC.ManagementGroup survives on the piped object. Here the listing
        # helper hands back a raw ARM item and the REAL converter, called by
        # Resolve-OERInventoryScopeTree itself, builds the object -- so this test exercises the real
        # converter's registration, not a fixture shaped like its output.
        Mock -ModuleName $script:moduleName Get-OERManagementGroupList {
            [PSCustomObject]@{
                id         = '/providers/Microsoft.Management/managementGroups/mg-real'
                name       = 'mg-real'
                properties = [PSCustomObject]@{ tenantId = 't'; displayName = 'Real MG' }
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

            The stripped object is injected at the converter, the step where Resolve-OERInventoryScopeTree
            builds it: a REAL converter object is built first, its tag cleared, and the mocked
            ConvertTo-OERManagementGroup hands that object back for the raw item the listing returns.
        #>
        $Stripped = InModuleScope $script:moduleName {
            $Real = ConvertTo-OERManagementGroup -InputObject @{
                id         = '/providers/Microsoft.Management/managementGroups/mg-stripped'
                name       = 'mg-stripped'
                properties = @{ tenantId = 't'; displayName = 'Stripped MG' }
            }
            $Real.PSObject.TypeNames.Clear()
            $Real.PSObject.TypeNames.Add('System.Management.Automation.PSCustomObject')
            $Real
        }
        Mock -ModuleName $script:moduleName Get-OERManagementGroupList {
            [PSCustomObject]@{
                id         = '/providers/Microsoft.Management/managementGroups/mg-stripped'
                name       = 'mg-stripped'
                properties = [PSCustomObject]@{ tenantId = 't'; displayName = 'Stripped MG' }
            }
        }
        Mock -ModuleName $script:moduleName ConvertTo-OERManagementGroup { $Stripped }
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
        Should -Invoke -ModuleName $script:moduleName ConvertTo-OERManagementGroup -Times 1 -Exactly -ParameterFilter {
            $InputObject.name -eq 'mg-stripped'
        }
    }

    # A listing that fails is never read as an empty level (measured live 2026-09-30: app-only, the
    # management-group listing answers AuthorizationFailed).
    Context 'a level that cannot be listed' {
        It 'names a failed management-group listing in SkippedScopes, warns, and still enumerates the subscriptions' {
            InModuleScope $script:moduleName {
                # Get-OERManagementGroupList catches nothing: a refused listing throws to this caller,
                # as the transport's AuthorizationFailed record.
                $ArmErr = Convert-ArmHttpException -Response ([PSCustomObject]@{ StatusCode = 403; Content = '{"error":{"code":"AuthorizationFailed","message":"no Microsoft.Management/managementGroups/read"}}' })
                Mock Get-OERManagementGroupList { [CmdletBinding()] param() throw $ArmErr }
                Mock Get-OERManagementGroup { }
                Mock Get-OERSubscription { [PSCustomObject]@{ SubscriptionId = 's1'; DisplayName = 'Sub 1'; ResourceId = '/subscriptions/s1'; State = 'Enabled' } }
                $T = Resolve-OERInventoryScopeTree -WarningAction SilentlyContinue -WarningVariable W
                @($T.SkippedScopes) | Should -Be @('<management groups: the listing failed>')
                @($T.Scopes) | Should -Be @('/subscriptions/s1')
                @($T.Hierarchy.managementGroups).Count | Should -Be 0
                @($W | Where-Object { [string]$_ -like 'Could not list the management groups*AuthorizationFailed*' }).Count | Should -Be 1
                Should -Invoke Get-OERManagementGroupList -Exactly -Times 1
                Should -Invoke Get-OERManagementGroup -Times 0
            }
        }

        It 'names a failed subscription listing in SkippedScopes and still enumerates the management groups' {
            InModuleScope $script:moduleName {
                Mock Get-OERManagementGroupList { [PSCustomObject]@{ id = '/providers/Microsoft.Management/managementGroups/mg-1'; name = 'mg-1'; properties = [PSCustomObject]@{ tenantId = 't'; displayName = 'MG 1' } } }
                Mock Get-OERSubscription { Write-Error -Message 'AuthorizationFailed: subscriptions' -ErrorId 'AuthorizationFailed' }
                $T = Resolve-OERInventoryScopeTree -WarningAction SilentlyContinue
                @($T.SkippedScopes) | Should -Be @('<subscriptions: the listing failed>')
                @($T.Scopes) | Should -Be @('/providers/Microsoft.Management/managementGroups/mg-1')
            }
        }

        It 'reports no skipped level when both listings succeed' {
            InModuleScope $script:moduleName {
                Mock Get-OERManagementGroupList { }
                Mock Get-OERSubscription { @() }
                @((Resolve-OERInventoryScopeTree).SkippedScopes).Count | Should -Be 0
            }
        }

        It 'throws, rather than walking nothing, when the named -ManagementGroup branch cannot be read' {
            InModuleScope $script:moduleName {
                Mock Get-OERManagementGroup { Write-Error -Message 'AuthorizationFailed: mg-x' -ErrorId 'AuthorizationFailed' }
                Mock Get-OERSubscription { @() }
                { Resolve-OERInventoryScopeTree -ManagementGroup 'mg-x' } | Should -Throw -ExpectedMessage '*AuthorizationFailed*'
            }
        }
    }
}