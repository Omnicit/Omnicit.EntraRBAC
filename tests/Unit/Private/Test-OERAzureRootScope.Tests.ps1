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

Describe 'Test-OERAzureRootScope' {
    # BL-126 (R1): an Azure scope is the root scope when ConvertTo-OERCanonicalScope returns exactly '/'
    # for it, or when it starts with '/' and the ARM transport would send its role assignment request to
    # the root: Invoke-OERArmRequest sends "<host><scope>/providers/Microsoft.Authorization/roleAssignments..."
    # through System.Uri, which removes dot segments, decodes '%2e' and reads '\' as '/'. No id below is
    # version-4 shaped.

    It 'returns <Expected> for <Case>' -ForEach @(
        @{ Case = 'the root scope'; Scope = '/'; Expected = $true }
        @{ Case = 'a doubled slash'; Scope = '//'; Expected = $true }
        @{ Case = 'a tripled slash'; Scope = '///'; Expected = $true }
        @{ Case = 'a dot segment'; Scope = '/.'; Expected = $true }
        @{ Case = 'a double dot segment'; Scope = '/..'; Expected = $true }
        @{ Case = 'a dot segment and a slash'; Scope = '/./'; Expected = $true }
        @{ Case = 'an escaped dot'; Scope = '/%2e'; Expected = $true }
        @{ Case = 'an escaped dot in capitals'; Scope = '/%2E'; Expected = $true }
        @{ Case = 'two escaped dots'; Scope = '/%2e%2e'; Expected = $true }
        @{ Case = 'a backslash'; Scope = '/\'; Expected = $true }
        @{ Case = 'a subscription path climbed out of'; Scope = '/subscriptions/11111111-1111-1111-1111-111111111111/../..'; Expected = $true }
        @{ Case = 'null'; Scope = $null; Expected = $false }
        @{ Case = 'an empty string'; Scope = ''; Expected = $false }
        @{ Case = 'a space'; Scope = ' '; Expected = $false }
        @{ Case = 'a slash and a space (sent as /%20/)'; Scope = '/ '; Expected = $false }
        @{ Case = 'a subscription path with one parent segment (/subscriptions)'; Scope = '/subscriptions/11111111-1111-1111-1111-111111111111/..'; Expected = $false }
        @{ Case = 'a management group path with one parent segment'; Scope = '/providers/Microsoft.Management/managementGroups/..'; Expected = $false }
        @{ Case = 'a query after the slash'; Scope = '/?x'; Expected = $false }
        @{ Case = 'a management group shorthand of a parent segment'; Scope = 'mg:..'; Expected = $false }
        @{ Case = 'a subscription shorthand of a parent segment'; Scope = 'sub:..'; Expected = $false }
        @{ Case = 'a subscription path'; Scope = '/subscriptions/x'; Expected = $false }
        @{ Case = 'a management group shorthand'; Scope = 'mg:x'; Expected = $false }
        @{ Case = 'a subscription shorthand'; Scope = 'sub:x'; Expected = $false }
        @{ Case = 'a management group path'; Scope = '/providers/Microsoft.Management/managementGroups/aaaa1111-0000-0000-0000-000000000001'; Expected = $false }
    ) {
        InModuleScope $script:moduleName -Parameters @{ Scope = $Scope; Expected = $Expected } {
            param($Scope, $Expected)
            $Result = Test-OERAzureRootScope -Scope $Scope
            $Result | Should -BeOfType ([bool])
            $Result | Should -Be $Expected
        }
    }

    It 'returns $false when called with no scope at all' {
        InModuleScope $script:moduleName {
            Test-OERAzureRootScope | Should -BeFalse
        }
    }

    It 'decides on the canonical form ConvertTo-OERCanonicalScope owns, so a mock of it that answers ''/'' makes any scope the root' {
        InModuleScope $script:moduleName {
            Mock ConvertTo-OERCanonicalScope { '/' }
            Test-OERAzureRootScope -Scope '/subscriptions/aaaa1111-0000-0000-0000-000000000001' | Should -BeTrue
            Should -Invoke ConvertTo-OERCanonicalScope -Times 1 -Exactly -ParameterFilter { $Scope -ceq '/subscriptions/aaaa1111-0000-0000-0000-000000000001' }
        }
    }

    It 'compares the canonical form exactly, so a mock of it that answers anything else is never the root for a scope that does not start with ''/''' {
        # A scope that starts with '/' is also tested as the transport sends it (below), so the canonical
        # comparison alone decides only for a scope that does not.
        InModuleScope $script:moduleName {
            Mock ConvertTo-OERCanonicalScope { '/x' }
            Test-OERAzureRootScope -Scope 'sub:x' | Should -BeFalse
            Should -Invoke ConvertTo-OERCanonicalScope -Times 1 -Exactly
        }
    }

    It 'answers, for <Scope>, exactly whether the role assignment read the ARM transport is sent lands at the root' -ForEach @(
        @{ Scope = '/' }
        @{ Scope = '/.' }
        @{ Scope = '/..' }
        @{ Scope = '/./' }
        @{ Scope = '/%2e' }
        @{ Scope = '/%2e%2e' }
        @{ Scope = '/\' }
        @{ Scope = '/subscriptions/11111111-1111-1111-1111-111111111111/../..' }
        @{ Scope = '/ ' }
        @{ Scope = '/subscriptions/11111111-1111-1111-1111-111111111111/..' }
        @{ Scope = '/providers/Microsoft.Management/managementGroups/..' }
        @{ Scope = '/?x' }
        @{ Scope = '/subscriptions/11111111-1111-1111-1111-111111111111' }
    ) {
        # Known answer: the predicate builds the URI as the transport does. Get-OERRoleAssignment sends
        # "<scope>/providers/Microsoft.Authorization/roleAssignments?..." to Invoke-OERArmRequest, which
        # sends "<host><path>" through System.Uri; the path that request reaches must be the root's role
        # assignments path exactly when the predicate says the scope is the root.
        InModuleScope $script:moduleName -Parameters @{ Scope = $Scope } {
            param($Scope)
            $script:RootScopeSentPath = $null
            Mock Initialize-OERAuth {}
            Mock Invoke-OERArmRequest { $script:RootScopeSentPath = $Path; [PSCustomObject]@{ value = @() } }
            Get-OERRoleAssignment -Scope $Scope -AtScope -ErrorAction Stop | Out-Null
            Should -Invoke Invoke-OERArmRequest -Times 1 -Exactly
            $Sent = $script:RootScopeSentPath
            $Sent.StartsWith($Scope + '/providers/Microsoft.Authorization/roleAssignments?', [System.StringComparison]::Ordinal) |
                Should -BeTrue -Because "the transport is sent '$Sent'"
            $Reached = ([uri]('https://scope.invalid' + $Sent)).AbsolutePath
            $AtRoot = $Reached -match '^/+providers/Microsoft\.Authorization/roleAssignments$'
            Test-OERAzureRootScope -Scope $Scope | Should -Be $AtRoot -Because "the request reaches '$Reached'"
        }
    }

    It 'never calls the Azure Resource Manager or Microsoft Graph transport' {
        InModuleScope $script:moduleName {
            Mock Invoke-OERArmRequest { throw 'unexpected ARM request' }
            Mock Invoke-OERGraphRequest { throw 'unexpected Graph request' }
            Test-OERAzureRootScope -Scope 'sub:Prod' | Should -BeFalse
            Test-OERAzureRootScope -Scope 'mg:Platform Display' | Should -BeFalse
            Test-OERAzureRootScope -Scope '/' | Should -BeTrue
            Should -Invoke Invoke-OERArmRequest -Times 0
            Should -Invoke Invoke-OERGraphRequest -Times 0
        }
    }
}
