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
        # BL-150 (A19): a listed subscription is walked only when its tenantId is the tenant the session's
        # Microsoft Graph token was issued for, so every test runs with a session; a test about a missing
        # session clears it.
        InModuleScope $script:moduleName { $script:_OERAuthState = [PSCustomObject]@{ TokenTenantId = 'eeee0000-0000-0000-0000-000000000001' } }
        Mock -ModuleName $script:moduleName Initialize-OERAuth {}
    }

    AfterAll {
        InModuleScope $script:moduleName { $script:_OERAuthState = $null }
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
            [PSCustomObject]@{ SubscriptionId = '1111'; DisplayName = 'Prod'; ResourceId = '/subscriptions/1111'; State = 'Enabled'; TenantId = 'eeee0000-0000-0000-0000-000000000001' }
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
            [PSCustomObject]@{ SubscriptionId = '2222'; DisplayName = 'Plat-Sub'; ResourceId = '/subscriptions/2222'; State = 'Enabled'; TenantId = 'eeee0000-0000-0000-0000-000000000001' }
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
        # BL-150 (A19): the subscription the scope lies in is read once, and belongs to this tenant.
        Mock -ModuleName $script:moduleName Invoke-OERArmRequest { [PSCustomObject]@{ subscriptionId = 'abc'; displayName = 'ABC'; tenantId = 'eeee0000-0000-0000-0000-000000000001' } }
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
                Mock Get-OERSubscription { [PSCustomObject]@{ SubscriptionId = 's1'; DisplayName = 'Sub 1'; ResourceId = '/subscriptions/s1'; State = 'Enabled'; TenantId = 'eeee0000-0000-0000-0000-000000000001' } }
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

    # BL-150 (A19): the walk enters only the subscriptions whose home tenant (the tenantId Azure Resource
    # Manager returns for the subscription) is the tenant the session's Microsoft Graph token was issued
    # for. Get-OERSubscriptionHomeTenant decides it; a listed subscription costs no request. No id below is
    # version-4 shaped.
    Context 'only the home tenant''s subscriptions are walked (BL-150, A19)' {
        BeforeAll {
            $script:TrOwn = [PSCustomObject]@{ ResourceId = '/subscriptions/aaaa1111-0000-0000-0000-000000000001'; SubscriptionId = 'aaaa1111-0000-0000-0000-000000000001'; DisplayName = 'Own'; State = 'Enabled'; TenantId = 'eeee0000-0000-0000-0000-000000000001' }
            $script:TrForeign = [PSCustomObject]@{ ResourceId = '/subscriptions/aaaa1111-0000-0000-0000-000000000002'; SubscriptionId = 'aaaa1111-0000-0000-0000-000000000002'; DisplayName = 'Customer'; State = 'Enabled'; TenantId = 'eeee0000-0000-0000-0000-000000000002' }
            $script:TrBlank = [PSCustomObject]@{ ResourceId = '/subscriptions/aaaa1111-0000-0000-0000-000000000003'; SubscriptionId = 'aaaa1111-0000-0000-0000-000000000003'; DisplayName = 'Blank'; State = 'Enabled'; TenantId = '' }
            $script:TrBlankReason = "Azure Resource Manager gave no home tenant (tenantId) for subscription 'aaaa1111-0000-0000-0000-000000000003'"
            $script:TrMg = [PSCustomObject]@{ id = '/providers/Microsoft.Management/managementGroups/mg1'; name = 'mg1'; properties = [PSCustomObject]@{ tenantId = 'eeee0000-0000-0000-0000-000000000001'; displayName = 'MG 1' } }
            # The tree, and the text of every warning it wrote.
            function script:Invoke-TrTree {
                param([hashtable]$Splat = @{})
                $All = @(InModuleScope $script:moduleName -Parameters @{ S = $Splat } { param($S) Resolve-OERInventoryScopeTree @S 3>&1 })
                [PSCustomObject]@{
                    Tree     = @($All | Where-Object { $_ -isnot [System.Management.Automation.WarningRecord] })[0]
                    Warnings = @($All | Where-Object { $_ -is [System.Management.Automation.WarningRecord] } | ForEach-Object { [string]$_.Message })
                }
            }
        }

        BeforeEach {
            # A request the tree must not send for a listed subscription: answered, and counted.
            Mock -ModuleName $script:moduleName Invoke-OERArmRequest { [PSCustomObject]@{ subscriptionId = 'unexpected'; tenantId = 'eeee0000-0000-0000-0000-000000000001' } }
        }

        It 'walks the own subscription only, names the foreign and the undecided one, warns once, and sends no request (<Name>)' -ForEach @(
            @{ Name = 'the full tree'; Splat = @{} }
            @{ Name = 'a -ManagementGroup branch'; Splat = @{ ManagementGroup = 'mg1' } }
        ) {
            Mock -ModuleName $script:moduleName Get-OERManagementGroupList { $script:TrMg }
            Mock -ModuleName $script:moduleName Get-OERManagementGroup { [PSCustomObject]@{ Name = 'mg1'; DisplayName = 'MG 1'; ResourceId = '/providers/Microsoft.Management/managementGroups/mg1' } }
            Mock -ModuleName $script:moduleName Get-OERSubscription { $script:TrOwn; $script:TrForeign; $script:TrBlank }
            $Run = Invoke-TrTree -Splat $Splat
            $T = $Run.Tree
            @($T.Scopes) | Should -Be @('/providers/Microsoft.Management/managementGroups/mg1', '/subscriptions/aaaa1111-0000-0000-0000-000000000001')
            @($T.Hierarchy.subscriptions).Count | Should -Be 1
            $T.Hierarchy.subscriptions[0].subscriptionId | Should -BeExactly 'aaaa1111-0000-0000-0000-000000000001'
            @($T.Hierarchy.managementGroups).Count | Should -Be 1
            @($T.ForeignSubscriptions).Count | Should -Be 1
            ($T.ForeignSubscriptions[0].PSObject.Properties.Name -join ',') | Should -BeExactly 'SubscriptionId,DisplayName,HomeTenantId,Scope'
            $T.ForeignSubscriptions[0].SubscriptionId | Should -BeExactly 'aaaa1111-0000-0000-0000-000000000002'
            $T.ForeignSubscriptions[0].DisplayName | Should -BeExactly 'Customer'
            $T.ForeignSubscriptions[0].HomeTenantId | Should -BeExactly 'eeee0000-0000-0000-0000-000000000002'
            $T.ForeignSubscriptions[0].Scope | Should -BeExactly '/subscriptions/aaaa1111-0000-0000-0000-000000000002'
            @($T.UndecidedSubscriptions).Count | Should -Be 1
            ($T.UndecidedSubscriptions[0].PSObject.Properties.Name -join ',') | Should -BeExactly 'SubscriptionId,Scope,Reason'
            $T.UndecidedSubscriptions[0].SubscriptionId | Should -BeExactly 'aaaa1111-0000-0000-0000-000000000003'
            $T.UndecidedSubscriptions[0].Scope | Should -BeExactly '/subscriptions/aaaa1111-0000-0000-0000-000000000003'
            $T.UndecidedSubscriptions[0].Reason | Should -BeExactly $script:TrBlankReason
            $Run.Warnings | Should -Be @("Could not tell whether 1 subscription(s) belong to this tenant, so none of them is walked: '/subscriptions/aaaa1111-0000-0000-0000-000000000003' ($($script:TrBlankReason))")
            Should -Invoke -ModuleName $script:moduleName Invoke-OERArmRequest -Times 0
            Should -Invoke -ModuleName $script:moduleName Get-OERSubscription -Times 1 -Exactly
        }

        It 'puts its lists after the existing three properties, and keeps both an empty array when every subscription is the tenant''s own' {
            Mock -ModuleName $script:moduleName Get-OERManagementGroupList { }
            Mock -ModuleName $script:moduleName Get-OERSubscription { $script:TrOwn }
            $Run = Invoke-TrTree
            ($Run.Tree.PSObject.Properties.Name -join ',') | Should -BeExactly 'Scopes,Hierarchy,SkippedScopes,ForeignSubscriptions,UndecidedSubscriptions'
            $Run.Tree.ForeignSubscriptions -is [array] | Should -BeTrue
            $Run.Tree.UndecidedSubscriptions -is [array] | Should -BeTrue
            @($Run.Tree.ForeignSubscriptions).Count | Should -Be 0
            @($Run.Tree.UndecidedSubscriptions).Count | Should -Be 0
            @($Run.Tree.Scopes) | Should -Be @('/subscriptions/aaaa1111-0000-0000-0000-000000000001')
            $Run.Warnings.Count | Should -Be 0
        }

        It 'walks no listed subscription, reads none, and names every one undecided in one warning when the session holds no tenant' {
            InModuleScope $script:moduleName { $script:_OERAuthState = $null }
            Mock -ModuleName $script:moduleName Get-OERManagementGroupList { }
            Mock -ModuleName $script:moduleName Get-OERSubscription { $script:TrOwn; $script:TrForeign }
            $Run = Invoke-TrTree
            @($Run.Tree.Scopes).Count | Should -Be 0
            @($Run.Tree.Hierarchy.subscriptions).Count | Should -Be 0
            @($Run.Tree.ForeignSubscriptions).Count | Should -Be 0
            @($Run.Tree.UndecidedSubscriptions | ForEach-Object { $_.SubscriptionId }) | Should -Be @('aaaa1111-0000-0000-0000-000000000001', 'aaaa1111-0000-0000-0000-000000000002')
            $R1 = "the session holds no Microsoft Graph token whose tenant ID subscription 'aaaa1111-0000-0000-0000-000000000001' could be compared with"
            $R2 = "the session holds no Microsoft Graph token whose tenant ID subscription 'aaaa1111-0000-0000-0000-000000000002' could be compared with"
            $Run.Warnings | Should -Be @("Could not tell whether 2 subscription(s) belong to this tenant, so none of them is walked: '/subscriptions/aaaa1111-0000-0000-0000-000000000001' ($R1); '/subscriptions/aaaa1111-0000-0000-0000-000000000002' ($R2)")
            Should -Invoke -ModuleName $script:moduleName Invoke-OERArmRequest -Times 0
        }

        It 'reads the subscription of a -Scope once, and walks nothing in it when it belongs to another tenant' {
            Mock -ModuleName $script:moduleName Invoke-OERArmRequest { [PSCustomObject]@{ subscriptionId = 'aaaa1111-0000-0000-0000-000000000002'; displayName = 'Customer'; tenantId = 'eeee0000-0000-0000-0000-000000000002' } }
            Mock -ModuleName $script:moduleName Get-OERSubscription { }
            Mock -ModuleName $script:moduleName Get-OERManagementGroupList { }
            $Run = Invoke-TrTree -Splat @{ Scope = '/subscriptions/aaaa1111-0000-0000-0000-000000000002/resourceGroups/rg1' }
            @($Run.Tree.Scopes).Count | Should -Be 0
            @($Run.Tree.ForeignSubscriptions).Count | Should -Be 1
            $Run.Tree.ForeignSubscriptions[0].Scope | Should -BeExactly '/subscriptions/aaaa1111-0000-0000-0000-000000000002/resourceGroups/rg1'
            $Run.Tree.ForeignSubscriptions[0].SubscriptionId | Should -BeExactly 'aaaa1111-0000-0000-0000-000000000002'
            $Run.Tree.ForeignSubscriptions[0].DisplayName | Should -BeExactly 'Customer'
            $Run.Tree.ForeignSubscriptions[0].HomeTenantId | Should -BeExactly 'eeee0000-0000-0000-0000-000000000002'
            @($Run.Tree.UndecidedSubscriptions).Count | Should -Be 0
            $Run.Warnings.Count | Should -Be 0
            Should -Invoke -ModuleName $script:moduleName Invoke-OERArmRequest -Times 1 -Exactly
            Should -Invoke -ModuleName $script:moduleName Invoke-OERArmRequest -Times 1 -Exactly -ParameterFilter { $Path -ceq '/subscriptions/aaaa1111-0000-0000-0000-000000000002?api-version=2022-12-01' }
            Should -Invoke -ModuleName $script:moduleName Get-OERSubscription -Times 0
        }

        It 'returns a -Scope in the tenant''s own subscription verbatim, after one read' {
            Mock -ModuleName $script:moduleName Invoke-OERArmRequest { [PSCustomObject]@{ subscriptionId = 'aaaa1111-0000-0000-0000-000000000001'; displayName = 'Own'; tenantId = 'EEEE0000-0000-0000-0000-000000000001' } }
            # Written in upper case, as ARM does not; a trailing '/' would make it undecided (Ruling R-27, below).
            $Given = '/SUBSCRIPTIONS/aaaa1111-0000-0000-0000-000000000001/resourceGroups/rg1'
            $Run = Invoke-TrTree -Splat @{ Scope = $Given }
            @($Run.Tree.Scopes) | Should -BeExactly @($Given)
            @($Run.Tree.ForeignSubscriptions).Count | Should -Be 0
            @($Run.Tree.UndecidedSubscriptions).Count | Should -Be 0
            $Run.Warnings.Count | Should -Be 0
            Should -Invoke -ModuleName $script:moduleName Invoke-OERArmRequest -Times 1 -Exactly
        }

        It 'reads nothing for a -Scope that lies in no subscription (<Name>), and returns it verbatim' -ForEach @(
            @{ Name = 'a management group'; Given = '/providers/Microsoft.Management/managementGroups/mg1' }
            @{ Name = 'the root scope'; Given = '/' }
        ) {
            $Run = Invoke-TrTree -Splat @{ Scope = $Given }
            @($Run.Tree.Scopes) | Should -BeExactly @($Given)
            @($Run.Tree.ForeignSubscriptions).Count | Should -Be 0
            @($Run.Tree.UndecidedSubscriptions).Count | Should -Be 0
            Should -Invoke -ModuleName $script:moduleName Invoke-OERArmRequest -Times 0
        }

        It 'walks nothing in a -Scope whose subscription could not be read, names it undecided and warns once' {
            Mock -ModuleName $script:moduleName Remove-OERErrorRecord {}
            Mock -ModuleName $script:moduleName Invoke-OERArmRequest {
                [CmdletBinding()] param($Path)
                throw [System.Management.Automation.ErrorRecord]::new([System.Exception]::new('Service unavailable (503).'), 'ServiceUnavailable', [System.Management.Automation.ErrorCategory]::ConnectionError, $null)
            }
            $Given = '/subscriptions/aaaa1111-0000-0000-0000-000000000001/resourceGroups/rg1'
            $Run = Invoke-TrTree -Splat @{ Scope = $Given }
            @($Run.Tree.Scopes).Count | Should -Be 0
            @($Run.Tree.ForeignSubscriptions).Count | Should -Be 0
            @($Run.Tree.UndecidedSubscriptions).Count | Should -Be 1
            $Reason = "the read of subscription 'aaaa1111-0000-0000-0000-000000000001' failed: Service unavailable (503)."
            $Run.Tree.UndecidedSubscriptions[0].SubscriptionId | Should -BeExactly 'aaaa1111-0000-0000-0000-000000000001'
            $Run.Tree.UndecidedSubscriptions[0].Scope | Should -BeExactly $Given
            $Run.Tree.UndecidedSubscriptions[0].Reason | Should -BeExactly $Reason
            $Run.Warnings | Should -Be @("Could not tell whether 1 subscription(s) belong to this tenant, so none of them is walked: '$Given' ($Reason)")
            Should -Invoke -ModuleName $script:moduleName Invoke-OERArmRequest -Times 1 -Exactly
        }

        It 'walks nothing in a -Scope spelled so that the request would not reach it as written (<Name>), names it undecided, warns once, and sends no request (Ruling R-27)' -ForEach @(
            @{ Name = '..-segments from the own subscription to another'; Rules = 'DotSegment'
                Given = '/subscriptions/aaaa1111-0000-0000-0000-000000000001/../../subscriptions/aaaa1111-0000-0000-0000-000000000002/resourceGroups/rg1' }
            @{ Name = '..-segments from a management group path to a subscription'; Rules = 'DotSegment'
                Given = '/providers/Microsoft.Management/managementGroups/mg1/../../../../subscriptions/aaaa1111-0000-0000-0000-000000000002' }
            @{ Name = 'a trailing slash'; Rules = 'Slash'
                Given = '/subscriptions/aaaa1111-0000-0000-0000-000000000001/resourceGroups/rg1/' }
        ) {
            # Every subscription GET would answer the session's tenant, so a read would have walked the scope.
            Mock -ModuleName $script:moduleName Invoke-OERArmRequest { [PSCustomObject]@{ subscriptionId = 'aaaa1111-0000-0000-0000-000000000001'; displayName = 'Own'; tenantId = 'eeee0000-0000-0000-0000-000000000001' } }
            Mock -ModuleName $script:moduleName Get-OERSubscription { }
            Mock -ModuleName $script:moduleName Get-OERManagementGroupList { }
            $Run = Invoke-TrTree -Splat @{ Scope = $Given }
            @($Run.Tree.Scopes).Count | Should -Be 0
            @($Run.Tree.ForeignSubscriptions).Count | Should -Be 0
            @($Run.Tree.UndecidedSubscriptions).Count | Should -Be 1
            $Reason = "scope '$Given' is written in a spelling no structure document can declare ($Rules), so the path a request sends for it may name another scope than its text; nothing was resolved or read for it"
            $null -eq $Run.Tree.UndecidedSubscriptions[0].SubscriptionId | Should -BeTrue
            $Run.Tree.UndecidedSubscriptions[0].Scope | Should -BeExactly $Given
            $Run.Tree.UndecidedSubscriptions[0].Reason | Should -BeExactly $Reason
            $Run.Warnings | Should -Be @("Could not tell whether 1 subscription(s) belong to this tenant, so none of them is walked: '$Given' ($Reason)")
            # Not one request: neither the subscription the text names first nor the one it reaches.
            Should -Invoke -ModuleName $script:moduleName Invoke-OERArmRequest -Times 0
            Should -Invoke -ModuleName $script:moduleName Get-OERSubscription -Times 0
        }

        It 'walks nothing in a -Scope that cannot be resolved, names it undecided with the resolver''s message, warns once, and sends no request' {
            Mock -ModuleName $script:moduleName Remove-OERErrorRecord {}
            Mock -ModuleName $script:moduleName Get-OERSubscription { }
            Mock -ModuleName $script:moduleName Get-OERManagementGroupList { }
            $Given = 'subscriptions/aaaa1111-0000-0000-0000-000000000001'
            $Run = Invoke-TrTree -Splat @{ Scope = $Given }
            @($Run.Tree.Scopes).Count | Should -Be 0
            @($Run.Tree.ForeignSubscriptions).Count | Should -Be 0
            @($Run.Tree.UndecidedSubscriptions).Count | Should -Be 1
            $Reason = "scope '$Given' could not be resolved: Scope '$Given' is not a valid ARM resource id: it must start with '/'."
            $null -eq $Run.Tree.UndecidedSubscriptions[0].SubscriptionId | Should -BeTrue
            $Run.Tree.UndecidedSubscriptions[0].Scope | Should -BeExactly $Given
            $Run.Tree.UndecidedSubscriptions[0].Reason | Should -BeExactly $Reason
            $Run.Warnings | Should -Be @("Could not tell whether 1 subscription(s) belong to this tenant, so none of them is walked: '$Given' ($Reason)")
            Should -Invoke -ModuleName $script:moduleName Invoke-OERArmRequest -Times 0
        }
    }

    # A20 (BL-152): -Cache reaches every Get-OERSubscriptionHomeTenant call, which leaves there what it
    # learned about each subscription, so Export-OERInventory's Get-OERInventory calls at the scopes the tree
    # returns are answered from it. The REAL owner runs; the tree's requests and decisions are unchanged.
    Context 'what the tree learned is left in -Cache (A20, BL-152)' {
        BeforeAll {
            $script:TcOwn = [PSCustomObject]@{ ResourceId = '/subscriptions/aaaa1111-0000-0000-0000-000000000001'; SubscriptionId = 'aaaa1111-0000-0000-0000-000000000001'; DisplayName = 'Own'; State = 'Enabled'; TenantId = 'eeee0000-0000-0000-0000-000000000001' }
            $script:TcForeign = [PSCustomObject]@{ ResourceId = '/subscriptions/aaaa1111-0000-0000-0000-000000000002'; SubscriptionId = 'aaaa1111-0000-0000-0000-000000000002'; DisplayName = 'Customer'; State = 'Enabled'; TenantId = 'eeee0000-0000-0000-0000-000000000002' }
            function script:Invoke-TcTree {
                param([hashtable]$Splat = @{})
                InModuleScope $script:moduleName -Parameters @{ S = $Splat } { param($S) Resolve-OERInventoryScopeTree @S 3>$null }
            }
        }

        BeforeEach {
            Mock -ModuleName $script:moduleName Get-OERManagementGroupList { }
            Mock -ModuleName $script:moduleName Get-OERSubscription { $script:TcOwn; $script:TcForeign }
            Mock -ModuleName $script:moduleName Invoke-OERArmRequest { [PSCustomObject]@{ subscriptionId = 'aaaa1111-0000-0000-0000-000000000003'; displayName = 'Third'; tenantId = 'eeee0000-0000-0000-0000-000000000001' } }
        }

        It 'stores the facts the list gave for every listed subscription, the foreign one included, with no request' {
            $Cache = [System.Collections.Generic.Dictionary[string, object]]::new([System.StringComparer]::OrdinalIgnoreCase)
            $Tree = Invoke-TcTree -Splat @{ Cache = $Cache }
            @($Tree.Scopes) | Should -Be @('/subscriptions/aaaa1111-0000-0000-0000-000000000001')
            @($Tree.ForeignSubscriptions).Count | Should -Be 1
            (@($Cache.Keys) | Sort-Object) -join ',' | Should -BeExactly 'aaaa1111-0000-0000-0000-000000000001,aaaa1111-0000-0000-0000-000000000002'
            $Cache['aaaa1111-0000-0000-0000-000000000001'].TenantId | Should -BeExactly 'eeee0000-0000-0000-0000-000000000001'
            $Cache['aaaa1111-0000-0000-0000-000000000002'].TenantId | Should -BeExactly 'eeee0000-0000-0000-0000-000000000002'
            $Cache['aaaa1111-0000-0000-0000-000000000002'].DisplayName | Should -BeExactly 'Customer'
            Should -Invoke -ModuleName $script:moduleName Invoke-OERArmRequest -Times 0
        }

        It 'stores the one read of the subscription of a -Scope' {
            $Cache = [System.Collections.Generic.Dictionary[string, object]]::new([System.StringComparer]::OrdinalIgnoreCase)
            $Tree = Invoke-TcTree -Splat @{ Scope = '/subscriptions/aaaa1111-0000-0000-0000-000000000003/resourceGroups/rg1'; Cache = $Cache }
            @($Tree.Scopes) | Should -Be @('/subscriptions/aaaa1111-0000-0000-0000-000000000003/resourceGroups/rg1')
            @($Cache.Keys) | Should -Be @('aaaa1111-0000-0000-0000-000000000003')
            $Cache['aaaa1111-0000-0000-0000-000000000003'].Read | Should -BeTrue
            $Cache['aaaa1111-0000-0000-0000-000000000003'].DisplayName | Should -BeExactly 'Third'
            Should -Invoke -ModuleName $script:moduleName Invoke-OERArmRequest -Times 1 -Exactly
            Should -Invoke -ModuleName $script:moduleName Get-OERSubscription -Times 0
        }

        It 'answers a -Scope in a listed subscription from the cache the same call filled, with no request' {
            # The cache is the caller's: a second tree call with it is answered from what the first left.
            $Cache = [System.Collections.Generic.Dictionary[string, object]]::new([System.StringComparer]::OrdinalIgnoreCase)
            $null = Invoke-TcTree -Splat @{ Cache = $Cache }
            $Tree = Invoke-TcTree -Splat @{ Scope = '/subscriptions/aaaa1111-0000-0000-0000-000000000002/resourceGroups/rg1'; Cache = $Cache }
            @($Tree.Scopes).Count | Should -Be 0
            $Tree.ForeignSubscriptions[0].HomeTenantId | Should -BeExactly 'eeee0000-0000-0000-0000-000000000002'
            Should -Invoke -ModuleName $script:moduleName Invoke-OERArmRequest -Times 0
        }

        It 'decides and requests the same without -Cache (<Name>)' -ForEach @(
            @{ Name = 'the listed walk'; Splat = @{}; Requests = 0 }
            @{ Name = 'a -Scope'; Splat = @{ Scope = '/subscriptions/aaaa1111-0000-0000-0000-000000000003/resourceGroups/rg1' }; Requests = 1 }
        ) {
            $Cache = [System.Collections.Generic.Dictionary[string, object]]::new([System.StringComparer]::OrdinalIgnoreCase)
            $With = Invoke-TcTree -Splat ($Splat + @{ Cache = $Cache })
            $Without = Invoke-TcTree -Splat $Splat
            ($With | ConvertTo-Json -Depth 6 -Compress) | Should -BeExactly ($Without | ConvertTo-Json -Depth 6 -Compress)
            Should -Invoke -ModuleName $script:moduleName Invoke-OERArmRequest -Times (2 * $Requests) -Exactly
        }
    }
}
