BeforeAll {
    Import-Module Omnicit.EntraRBAC -Force
    . "$PSScriptRoot/../TestHelpers/OERTransportTripwire.ps1"
    Install-OERTransportTripwire
}

AfterAll {
    try { Assert-OERTransportTripwire } finally { Uninstall-OERTransportTripwire }
}

Describe 'Get-OERSubscriptionHomeTenant (BL-150, A19)' {
    # The single owner of whether a subscription belongs to the tenant the session's Microsoft Graph token
    # was issued for, by the tenantId Azure Resource Manager returns for the subscription. No id below is
    # version-4 shaped.
    BeforeAll {
        $script:HtSession = 'eeee0000-0000-0000-0000-000000000001'
        $script:HtOther = 'eeee0000-0000-0000-0000-000000000002'
        $script:HtSub = 'aaaa1111-0000-0000-0000-000000000001'
        $script:HtGetPath = '/subscriptions/aaaa1111-0000-0000-0000-000000000001?api-version=2022-12-01'
        $script:HtRgScope = '/subscriptions/aaaa1111-0000-0000-0000-000000000001/resourceGroups/rg1'
        $script:HtShape = 'Scope,SubscriptionId,DisplayName,Verdict,HomeTenantId,SessionTenantId,Reason,ErrorRecord'
        $script:HtTail = '. Invoke-OERStructure and Export-OERInventory read and write a role assignment or a role management policy only in a subscription they can show to belong to the tenant the session''s Microsoft Graph token was issued for -- not in one another tenant delegated to it, for example through Azure Lighthouse -- so none was read or written at that scope. Sign in to the subscription''s home tenant to manage it there.'
        # The real resolver, taken before any test mocks it, so a spy can call through to it.
        $script:HtRealResolveScope = InModuleScope Omnicit.EntraRBAC { Get-Command Resolve-OERScope -CommandType Function }
        function script:Invoke-HtOwner {
            param([hashtable]$Splat)
            InModuleScope Omnicit.EntraRBAC -Parameters @{ S = $Splat } {
                param($S)
                Get-OERSubscriptionHomeTenant @S
            }
        }
        function script:Set-HtState {
            param($TokenTenantId)
            InModuleScope Omnicit.EntraRBAC -Parameters @{ T = $TokenTenantId } {
                param($T)
                $script:_OERAuthState = [PSCustomObject]@{ TokenTenantId = $T }
            }
        }
        function script:New-HtArmError {
            param([string]$Code, [string]$Message)
            [System.Management.Automation.ErrorRecord]::new(
                [System.Exception]::new($Message), $Code,
                [System.Management.Automation.ErrorCategory]::ObjectNotFound, $null)
        }
    }

    BeforeEach {
        Set-HtState -TokenTenantId $script:HtSession
        # What the subscription GET answers; a test sets another tenant or shape.
        $script:HtAnswer = [PSCustomObject]@{
            id             = '/subscriptions/aaaa1111-0000-0000-0000-000000000001'
            subscriptionId = 'aaaa1111-0000-0000-0000-000000000001'
            displayName    = 'Prod'
            tenantId       = $script:HtSession
        }
        Mock -ModuleName Omnicit.EntraRBAC Invoke-OERArmRequest { $script:HtAnswer }
        Mock -ModuleName Omnicit.EntraRBAC Resolve-OERScope { & $script:HtRealResolveScope @PesterBoundParameters }
        Mock -ModuleName Omnicit.EntraRBAC Remove-OERErrorRecord {}
    }

    AfterAll {
        InModuleScope Omnicit.EntraRBAC { $script:_OERAuthState = $null }
    }

    Context 'the -Scope set' {
        It 'is Home when the subscription''s tenantId is the session''s tenant, in any letter case (<Name>)' -ForEach @(
            @{ Name = 'the same letter case'; Tenant = 'eeee0000-0000-0000-0000-000000000001' }
            @{ Name = 'upper case'; Tenant = 'EEEE0000-0000-0000-0000-000000000001' }
        ) {
            $script:HtAnswer.tenantId = $Tenant
            $V = Invoke-HtOwner -Splat @{ Scope = $script:HtRgScope }
            $V.Verdict | Should -BeExactly 'Home'
            $V.Scope | Should -BeExactly $script:HtRgScope
            $V.SubscriptionId | Should -BeExactly $script:HtSub
            $V.DisplayName | Should -BeExactly 'Prod'
            $V.HomeTenantId | Should -BeExactly $Tenant
            $V.SessionTenantId | Should -BeExactly $script:HtSession
            $V.Reason | Should -BeNullOrEmpty
            $null -eq $V.ErrorRecord | Should -BeTrue
            Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-OERArmRequest -Times 1 -Exactly
            Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-OERArmRequest -Times 1 -Exactly -ParameterFilter { $Path -ceq '/subscriptions/aaaa1111-0000-0000-0000-000000000001?api-version=2022-12-01' }
        }

        It 'is Foreign when the subscription''s tenantId is another tenant, with the reason and a SubscriptionTenantMismatch record' {
            $script:HtAnswer.tenantId = $script:HtOther
            $V = Invoke-HtOwner -Splat @{ Scope = $script:HtRgScope }
            $V.Verdict | Should -BeExactly 'Foreign'
            $V.Scope | Should -BeExactly $script:HtRgScope
            $V.SubscriptionId | Should -BeExactly $script:HtSub
            $V.DisplayName | Should -BeExactly 'Prod'
            $V.HomeTenantId | Should -BeExactly $script:HtOther
            $V.SessionTenantId | Should -BeExactly $script:HtSession
            $Reason = "subscription 'aaaa1111-0000-0000-0000-000000000001' belongs to tenant 'eeee0000-0000-0000-0000-000000000002', not to tenant 'eeee0000-0000-0000-0000-000000000001', the tenant the session's Microsoft Graph token was issued for"
            $V.Reason | Should -BeExactly $Reason
            $V.ErrorRecord | Should -BeOfType ([System.Management.Automation.ErrorRecord])
            $V.ErrorRecord.FullyQualifiedErrorId | Should -BeExactly 'SubscriptionTenantMismatch'
            $V.ErrorRecord.CategoryInfo.Category | Should -Be ([System.Management.Automation.ErrorCategory]::InvalidOperation)
            $V.ErrorRecord.TargetObject | Should -BeExactly $script:HtRgScope
            $V.ErrorRecord.Exception.Message | Should -BeExactly ("Scope '$($script:HtRgScope)' was refused: $Reason" + $script:HtTail)
            Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-OERArmRequest -Times 1 -Exactly -ParameterFilter { $Path -ceq '/subscriptions/aaaa1111-0000-0000-0000-000000000001?api-version=2022-12-01' }
        }

        It 'writes a brace in the scope into the message as text: the scope is an argument of the format, never part of it' {
            $script:HtAnswer.tenantId = $script:HtOther
            $Scope = '/subscriptions/aaaa1111-0000-0000-0000-000000000001/resourceGroups/rg{0}{1}'
            $V = Invoke-HtOwner -Splat @{ Scope = $Scope }
            $V.Verdict | Should -BeExactly 'Foreign'
            $V.ErrorRecord.Exception.Message | Should -BeLike "Scope '$([System.Management.Automation.WildcardPattern]::Escape($Scope))' was refused: subscription*"
            $V.ErrorRecord.TargetObject | Should -BeExactly $Scope
        }

        It 'is NoSubscription with no request for <Name>' -ForEach @(
            @{ Name = 'the root scope'; Scope = '/'; Expected = '/'; Resolves = $true }
            @{ Name = 'a management group path'; Scope = '/providers/Microsoft.Management/managementGroups/mg1'; Expected = '/providers/Microsoft.Management/managementGroups/mg1'; Resolves = $true }
            @{ Name = 'an mg: form'; Scope = 'mg:mg1'; Expected = $null; Resolves = $false }
            @{ Name = 'an mg: form in upper case'; Scope = 'MG:mg1'; Expected = $null; Resolves = $false }
        ) {
            $V = Invoke-HtOwner -Splat @{ Scope = $Scope }
            $V.Verdict | Should -BeExactly 'NoSubscription'
            if ($null -eq $Expected) { $null -eq $V.Scope | Should -BeTrue } else { $V.Scope | Should -BeExactly $Expected }
            $null -eq $V.SubscriptionId | Should -BeTrue
            $null -eq $V.DisplayName | Should -BeTrue
            $null -eq $V.HomeTenantId | Should -BeTrue
            $V.SessionTenantId | Should -BeExactly $script:HtSession
            $null -eq $V.Reason | Should -BeTrue
            $null -eq $V.ErrorRecord | Should -BeTrue
            Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-OERArmRequest -Times 0
            # An mg: form is not even resolved; a raw path is resolved (offline) and then known to lie in no subscription.
            Should -Invoke -ModuleName Omnicit.EntraRBAC Resolve-OERScope -Times $(if ($Resolves) { 1 } else { 0 }) -Exactly
        }

        It 'gives the subscription id of <Name>, with one GET of the subscription' -ForEach @(
            @{ Name = 'a resource group scope'; Scope = '/subscriptions/aaaa1111-0000-0000-0000-000000000001/resourceGroups/rg1' }
            @{ Name = 'a resource scope'; Scope = '/subscriptions/aaaa1111-0000-0000-0000-000000000001/resourceGroups/rg1/providers/Microsoft.Storage/storageAccounts/st1' }
            @{ Name = 'a subscription scope'; Scope = '/subscriptions/aaaa1111-0000-0000-0000-000000000001' }
        ) {
            $V = Invoke-HtOwner -Splat @{ Scope = $Scope }
            $V.Verdict | Should -BeExactly 'Home'
            $V.Scope | Should -BeExactly $Scope
            $V.SubscriptionId | Should -BeExactly $script:HtSub
            Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-OERArmRequest -Times 1 -Exactly
            Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-OERArmRequest -Times 1 -Exactly -ParameterFilter { $Path -ceq '/subscriptions/aaaa1111-0000-0000-0000-000000000001?api-version=2022-12-01' }
        }

        It 'reads a sub: form that names the subscription id with one GET and no subscription list' {
            $V = Invoke-HtOwner -Splat @{ Scope = 'sub:aaaa1111-0000-0000-0000-000000000001' }
            $V.Verdict | Should -BeExactly 'Home'
            $V.Scope | Should -BeExactly '/subscriptions/aaaa1111-0000-0000-0000-000000000001'
            $V.SubscriptionId | Should -BeExactly $script:HtSub
            Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-OERArmRequest -Times 1 -Exactly
            Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-OERArmRequest -Times 0 -ParameterFilter { $Path.StartsWith('/subscriptions?') }
            Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-OERArmRequest -Times 1 -Exactly -ParameterFilter { $Path -ceq '/subscriptions/aaaa1111-0000-0000-0000-000000000001?api-version=2022-12-01' }
        }

        It 'resolves a subscription: form that names a display name through Resolve-OERScope and decides on the resolved scope in its canonical form' {
            Mock -ModuleName Omnicit.EntraRBAC Resolve-OERScope -ParameterFilter { $Subscription -ceq 'Prod' } { '/subscriptions/aaaa1111-0000-0000-0000-000000000001/' }
            $V = Invoke-HtOwner -Splat @{ Scope = 'subscription:Prod' }
            $V.Verdict | Should -BeExactly 'Home'
            # The trailing '/' the resolver gave is trimmed: the canonical scope.
            $V.Scope | Should -BeExactly '/subscriptions/aaaa1111-0000-0000-0000-000000000001'
            $V.SubscriptionId | Should -BeExactly $script:HtSub
            Should -Invoke -ModuleName Omnicit.EntraRBAC Resolve-OERScope -Times 1 -Exactly -ParameterFilter { $Subscription -ceq 'Prod' }
            Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-OERArmRequest -Times 1 -Exactly -ParameterFilter { $Path -ceq '/subscriptions/aaaa1111-0000-0000-0000-000000000001?api-version=2022-12-01' }
        }

        It 'is Undecided with the resolver''s own record, scrubbed first, and sends no GET when the scope cannot be resolved' {
            $script:HtResolveErr = [System.Management.Automation.ErrorRecord]::new(
                [System.Exception]::new("Subscription display name 'Shared' matches 2 subscriptions."), 'AmbiguousName',
                [System.Management.Automation.ErrorCategory]::InvalidArgument, 'Shared')
            Mock -ModuleName Omnicit.EntraRBAC Resolve-OERScope -ParameterFilter { $Subscription -ceq 'Shared' } { [CmdletBinding()] param($Subscription) throw $script:HtResolveErr }
            $V = Invoke-HtOwner -Splat @{ Scope = 'subscription:Shared' }
            $V.Verdict | Should -BeExactly 'Undecided'
            $null -eq $V.Scope | Should -BeTrue
            $null -eq $V.SubscriptionId | Should -BeTrue
            $V.SessionTenantId | Should -BeExactly $script:HtSession
            $V.Reason | Should -BeExactly "scope 'subscription:Shared' could not be resolved: Subscription display name 'Shared' matches 2 subscriptions."
            # The resolver's own record, not a new one.
            [object]::ReferenceEquals($V.ErrorRecord.Exception, $script:HtResolveErr.Exception) | Should -BeTrue
            $V.ErrorRecord.FullyQualifiedErrorId | Should -BeLike 'AmbiguousName*'
            Should -Invoke -ModuleName Omnicit.EntraRBAC Remove-OERErrorRecord -Times 1 -Exactly -ParameterFilter { [object]::ReferenceEquals($Record.Exception, $script:HtResolveErr.Exception) }
            Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-OERArmRequest -Times 0
        }

        It 'is Undecided with the read''s own record, scrubbed first, when the read of the subscription fails' {
            $script:HtReadErr = New-HtArmError -Code 'SubscriptionNotFound' -Message "The subscription 'aaaa1111-0000-0000-0000-000000000001' could not be found."
            Mock -ModuleName Omnicit.EntraRBAC Invoke-OERArmRequest { [CmdletBinding()] param($Path) throw $script:HtReadErr }
            $V = Invoke-HtOwner -Splat @{ Scope = $script:HtRgScope }
            $V.Verdict | Should -BeExactly 'Undecided'
            $V.Scope | Should -BeExactly $script:HtRgScope
            $V.SubscriptionId | Should -BeExactly $script:HtSub
            $null -eq $V.HomeTenantId | Should -BeTrue
            $V.Reason | Should -BeExactly "the read of subscription 'aaaa1111-0000-0000-0000-000000000001' failed: The subscription 'aaaa1111-0000-0000-0000-000000000001' could not be found."
            [object]::ReferenceEquals($V.ErrorRecord.Exception, $script:HtReadErr.Exception) | Should -BeTrue
            $V.ErrorRecord.FullyQualifiedErrorId | Should -BeLike 'SubscriptionNotFound*'
            Should -Invoke -ModuleName Omnicit.EntraRBAC Remove-OERErrorRecord -Times 1 -Exactly -ParameterFilter { [object]::ReferenceEquals($Record.Exception, $script:HtReadErr.Exception) }
            Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-OERArmRequest -Times 1 -Exactly
        }

        It 'is never Home and is Undecided with the no-field reason when the tenantId is <Name>' -ForEach @(
            @{ Name = 'empty'; Tenant = ''; Present = $true }
            @{ Name = 'white space'; Tenant = '   '; Present = $true }
            @{ Name = 'null'; Tenant = $null; Present = $true }
            @{ Name = 'absent'; Tenant = $null; Present = $false }
            @{ Name = 'not a GUID'; Tenant = 'contoso.onmicrosoft.com'; Present = $true }
            @{ Name = 'the session tenant braced'; Tenant = '{eeee0000-0000-0000-0000-000000000001}'; Present = $true }
            @{ Name = 'the empty GUID braced'; Tenant = '{00000000-0000-0000-0000-000000000000}'; Present = $true }
        ) {
            $script:HtAnswer = if ($Present) {
                [PSCustomObject]@{ subscriptionId = $script:HtSub; displayName = 'Prod'; tenantId = $Tenant }
            } else {
                [PSCustomObject]@{ subscriptionId = $script:HtSub; displayName = 'Prod' }
            }
            $V = Invoke-HtOwner -Splat @{ Scope = $script:HtRgScope }
            $V.Verdict | Should -BeExactly 'Undecided'
            $null -eq $V.HomeTenantId | Should -BeTrue
            $V.DisplayName | Should -BeExactly 'Prod'
            $Reason = "Azure Resource Manager gave no home tenant (tenantId) for subscription 'aaaa1111-0000-0000-0000-000000000001'"
            $V.Reason | Should -BeExactly $Reason
            $V.ErrorRecord.FullyQualifiedErrorId | Should -BeExactly 'SubscriptionTenantMismatch'
            $V.ErrorRecord.CategoryInfo.Category | Should -Be ([System.Management.Automation.ErrorCategory]::InvalidOperation)
            $V.ErrorRecord.TargetObject | Should -BeExactly $script:HtRgScope
            $V.ErrorRecord.Exception.Message | Should -BeExactly ("Scope '$($script:HtRgScope)' was refused: $Reason" + $script:HtTail)
            Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-OERArmRequest -Times 1 -Exactly
        }

        It 'sends no request and is Undecided with the no-session reason when <Name>' -ForEach @(
            @{ Name = 'the session holds no state'; NoState = $true; Token = $null }
            @{ Name = 'the token tenant is a domain'; NoState = $false; Token = 'contoso.onmicrosoft.com' }
            @{ Name = 'the token tenant is empty'; NoState = $false; Token = '' }
            @{ Name = 'the token tenant is a braced GUID'; NoState = $false; Token = '{eeee0000-0000-0000-0000-000000000001}' }
        ) {
            if ($NoState) { InModuleScope Omnicit.EntraRBAC { $script:_OERAuthState = $null } } else { Set-HtState -TokenTenantId $Token }
            $V = Invoke-HtOwner -Splat @{ Scope = $script:HtRgScope }
            $V.Verdict | Should -BeExactly 'Undecided'
            # Reach proof: the scope was resolved and its subscription found before the session was asked.
            $V.Scope | Should -BeExactly $script:HtRgScope
            $V.SubscriptionId | Should -BeExactly $script:HtSub
            $null -eq $V.SessionTenantId | Should -BeTrue
            $Reason = "the session holds no Microsoft Graph token whose tenant ID subscription 'aaaa1111-0000-0000-0000-000000000001' could be compared with"
            $V.Reason | Should -BeExactly $Reason
            $V.ErrorRecord.FullyQualifiedErrorId | Should -BeExactly 'SubscriptionTenantMismatch'
            $V.ErrorRecord.Exception.Message | Should -BeExactly ("Scope '$($script:HtRgScope)' was refused: $Reason" + $script:HtTail)
            Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-OERArmRequest -Times 0
        }
    }

    Context 'the cache' {
        It 'reads a subscription once per cache, however its id is written, and gives the same verdict to every scope in it' {
            # An ordinal dictionary, so the key is found again only because the owner lower-cases it.
            $Cache = [System.Collections.Generic.Dictionary[string, object]]::new([System.StringComparer]::Ordinal)
            $script:HtAnswer.tenantId = $script:HtOther
            $Scopes = @(
                '/subscriptions/aaaa1111-0000-0000-0000-000000000001/resourceGroups/rg1'
                '/SUBSCRIPTIONS/AAAA1111-0000-0000-0000-000000000001/resourceGroups/rg2'
                'sub:AAAA1111-0000-0000-0000-000000000001'
            )
            $Verdicts = @(foreach ($One in $Scopes) { Invoke-HtOwner -Splat @{ Scope = $One; Cache = $Cache } })
            $Verdicts.Count | Should -Be 3
            @($Verdicts | ForEach-Object { $_.Verdict }) | Should -Be @('Foreign', 'Foreign', 'Foreign')
            @($Verdicts | ForEach-Object { $_.HomeTenantId }) | Should -Be @($script:HtOther, $script:HtOther, $script:HtOther)
            # The id is kept as each scope writes it.
            @($Verdicts | ForEach-Object { $_.SubscriptionId }) | Should -Be @($script:HtSub, 'AAAA1111-0000-0000-0000-000000000001', 'AAAA1111-0000-0000-0000-000000000001')
            Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-OERArmRequest -Times 1 -Exactly
            @($Cache.Keys) | Should -Be @('aaaa1111-0000-0000-0000-000000000001')
        }

        It 'caches a failed read: a second call sends no GET and gives the same record' {
            $Cache = @{}
            $script:HtReadErr = New-HtArmError -Code 'AuthorizationFailed' -Message 'The client does not have authorization to read the subscription.'
            Mock -ModuleName Omnicit.EntraRBAC Invoke-OERArmRequest { [CmdletBinding()] param($Path) throw $script:HtReadErr }
            $First = Invoke-HtOwner -Splat @{ Scope = $script:HtRgScope; Cache = $Cache }
            $Second = Invoke-HtOwner -Splat @{ Scope = '/subscriptions/aaaa1111-0000-0000-0000-000000000001'; Cache = $Cache }
            $First.Verdict | Should -BeExactly 'Undecided'
            $Second.Verdict | Should -BeExactly 'Undecided'
            [object]::ReferenceEquals($Second.ErrorRecord.Exception, $script:HtReadErr.Exception) | Should -BeTrue
            [object]::ReferenceEquals($Second.ErrorRecord, $First.ErrorRecord) | Should -BeTrue
            $Second.Reason | Should -BeExactly $First.Reason
            Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-OERArmRequest -Times 1 -Exactly
        }

        It 'reads again on every call without -Cache' {
            $First = Invoke-HtOwner -Splat @{ Scope = $script:HtRgScope }
            $Second = Invoke-HtOwner -Splat @{ Scope = $script:HtRgScope }
            $First.Verdict | Should -BeExactly 'Home'
            $Second.Verdict | Should -BeExactly 'Home'
            Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-OERArmRequest -Times 2 -Exactly
        }
    }

    Context 'the -Subscription set' {
        BeforeAll {
            function script:New-HtListed {
                param([string]$TenantId, [string]$ResourceId = '/subscriptions/aaaa1111-0000-0000-0000-000000000001', [string]$DisplayName = 'Prod')
                [PSCustomObject]@{ ResourceId = $ResourceId; SubscriptionId = 'aaaa1111-0000-0000-0000-000000000001'; DisplayName = $DisplayName; State = 'Enabled'; TenantId = $TenantId }
            }
        }

        It 'decides <Name> from the object, with no request' -ForEach @(
            @{ Name = 'Home'; Tenant = 'EEEE0000-0000-0000-0000-000000000001'; NoState = $false; Verdict = 'Home'; HomeExpected = 'EEEE0000-0000-0000-0000-000000000001'
                Reason = $null }
            @{ Name = 'Foreign'; Tenant = 'eeee0000-0000-0000-0000-000000000002'; NoState = $false; Verdict = 'Foreign'; HomeExpected = 'eeee0000-0000-0000-0000-000000000002'
                Reason = "subscription 'aaaa1111-0000-0000-0000-000000000001' belongs to tenant 'eeee0000-0000-0000-0000-000000000002', not to tenant 'eeee0000-0000-0000-0000-000000000001', the tenant the session's Microsoft Graph token was issued for" }
            @{ Name = 'a blank TenantId as Undecided'; Tenant = ''; NoState = $false; Verdict = 'Undecided'; HomeExpected = $null
                Reason = "Azure Resource Manager gave no home tenant (tenantId) for subscription 'aaaa1111-0000-0000-0000-000000000001'" }
            @{ Name = 'no session as Undecided'; Tenant = 'eeee0000-0000-0000-0000-000000000001'; NoState = $true; Verdict = 'Undecided'; HomeExpected = $null
                Reason = "the session holds no Microsoft Graph token whose tenant ID subscription 'aaaa1111-0000-0000-0000-000000000001' could be compared with" }
        ) {
            if ($NoState) { InModuleScope Omnicit.EntraRBAC { $script:_OERAuthState = $null } }
            $V = Invoke-HtOwner -Splat @{ Subscription = (New-HtListed -TenantId $Tenant) }
            $V.Verdict | Should -BeExactly $Verdict
            $V.Scope | Should -BeExactly '/subscriptions/aaaa1111-0000-0000-0000-000000000001'
            $V.SubscriptionId | Should -BeExactly $script:HtSub
            if ($null -eq $HomeExpected) { $null -eq $V.HomeTenantId | Should -BeTrue } else { $V.HomeTenantId | Should -BeExactly $HomeExpected }
            if ($null -eq $Reason) {
                $null -eq $V.Reason | Should -BeTrue
                $null -eq $V.ErrorRecord | Should -BeTrue
            } else {
                $V.Reason | Should -BeExactly $Reason
                $V.ErrorRecord.FullyQualifiedErrorId | Should -BeExactly 'SubscriptionTenantMismatch'
                $V.ErrorRecord.TargetObject | Should -BeExactly '/subscriptions/aaaa1111-0000-0000-0000-000000000001'
                $V.ErrorRecord.Exception.Message | Should -BeExactly ("Scope '/subscriptions/aaaa1111-0000-0000-0000-000000000001' was refused: $Reason" + $script:HtTail)
            }
            Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-OERArmRequest -Times 0
            Should -Invoke -ModuleName Omnicit.EntraRBAC Resolve-OERScope -Times 0
        }

        It 'names the subscription by its /subscriptions path when its ResourceId is blank, and writes a blank display name as null' {
            $V = Invoke-HtOwner -Splat @{ Subscription = (New-HtListed -TenantId $script:HtSession -ResourceId '' -DisplayName ' ') }
            $V.Verdict | Should -BeExactly 'Home'
            $V.Scope | Should -BeExactly '/subscriptions/aaaa1111-0000-0000-0000-000000000001'
            $null -eq $V.DisplayName | Should -BeTrue
        }
    }

    It 'returns its properties in this order for every verdict (<Name>)' -ForEach @(
        @{ Name = 'Home'; Splat = @{ Scope = '/subscriptions/aaaa1111-0000-0000-0000-000000000001' }; Tenant = 'eeee0000-0000-0000-0000-000000000001' }
        @{ Name = 'Foreign'; Splat = @{ Scope = '/subscriptions/aaaa1111-0000-0000-0000-000000000001' }; Tenant = 'eeee0000-0000-0000-0000-000000000002' }
        @{ Name = 'Undecided'; Splat = @{ Scope = '/subscriptions/aaaa1111-0000-0000-0000-000000000001' }; Tenant = '' }
        @{ Name = 'NoSubscription'; Splat = @{ Scope = 'mg:mg1' }; Tenant = '' }
        @{ Name = 'NoSubscription at the root'; Splat = @{ Scope = '/' }; Tenant = '' }
    ) {
        $script:HtAnswer.tenantId = $Tenant
        $V = Invoke-HtOwner -Splat $Splat
        @($V).Count | Should -Be 1
        ($V.PSObject.Properties.Name -join ',') | Should -BeExactly $script:HtShape
    }

    It 'returns its properties in this order for a listed subscription' {
        $Listed = [PSCustomObject]@{ ResourceId = '/subscriptions/aaaa1111-0000-0000-0000-000000000001'; SubscriptionId = $script:HtSub; DisplayName = 'Prod'; State = 'Enabled'; TenantId = $script:HtSession }
        $V = Invoke-HtOwner -Splat @{ Subscription = $Listed }
        @($V).Count | Should -Be 1
        ($V.PSObject.Properties.Name -join ',') | Should -BeExactly $script:HtShape
    }
}
