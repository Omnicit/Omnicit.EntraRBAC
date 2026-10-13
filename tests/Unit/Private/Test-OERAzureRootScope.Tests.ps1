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
    # for it. No id below is version-4 shaped.

    It 'returns <Expected> for <Case>' -ForEach @(
        @{ Case = 'the root scope'; Scope = '/'; Expected = $true }
        @{ Case = 'a doubled slash'; Scope = '//'; Expected = $true }
        @{ Case = 'a tripled slash'; Scope = '///'; Expected = $true }
        @{ Case = 'null'; Scope = $null; Expected = $false }
        @{ Case = 'an empty string'; Scope = ''; Expected = $false }
        @{ Case = 'a space'; Scope = ' '; Expected = $false }
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

    It 'compares the canonical form exactly, so a mock of it that answers anything else is never the root' {
        InModuleScope $script:moduleName {
            Mock ConvertTo-OERCanonicalScope { '/x' }
            Test-OERAzureRootScope -Scope '/' | Should -BeFalse
            Should -Invoke ConvertTo-OERCanonicalScope -Times 1 -Exactly
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
