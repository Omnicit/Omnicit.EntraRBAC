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

Describe 'ConvertTo-OERCanonicalScope' {
    # No id below is version-4 shaped.

    It 'returns <Expected> for <Scope>' -ForEach @(
        @{ Scope = 'mg:Plat'; Expected = '/providers/Microsoft.Management/managementGroups/Plat' }
        @{ Scope = 'MG:Plat'; Expected = '/providers/Microsoft.Management/managementGroups/Plat' }
        @{ Scope = 'sub:aaaa1111-0000-0000-0000-000000000001'; Expected = '/subscriptions/aaaa1111-0000-0000-0000-000000000001' }
        @{ Scope = 'SUBSCRIPTION:aaaa1111-0000-0000-0000-000000000001'; Expected = '/subscriptions/aaaa1111-0000-0000-0000-000000000001' }
        @{ Scope = 'Subscription:aaaa1111-0000-0000-0000-000000000001'; Expected = '/subscriptions/aaaa1111-0000-0000-0000-000000000001' }
        @{ Scope = 'sub:Prod'; Expected = 'sub:Prod' }
        @{ Scope = 'subscription:Prod'; Expected = 'sub:Prod' }
        @{ Scope = '/subscriptions/aaaa1111-0000-0000-0000-000000000001/resourceGroups/rg/'; Expected = '/subscriptions/aaaa1111-0000-0000-0000-000000000001/resourceGroups/rg' }
        @{ Scope = '/subscriptions/aaaa1111-0000-0000-0000-000000000001//'; Expected = '/subscriptions/aaaa1111-0000-0000-0000-000000000001' }
        @{ Scope = '/'; Expected = '/' }
        @{ Scope = '//'; Expected = '/' }
        @{ Scope = '/Subscriptions/ABC'; Expected = '/Subscriptions/ABC' }
        @{ Scope = 'Prod'; Expected = 'Prod' }
    ) {
        InModuleScope $script:moduleName -Parameters @{ Scope = $Scope; Expected = $Expected } {
            param($Scope, $Expected)
            ConvertTo-OERCanonicalScope -Scope $Scope | Should -BeExactly $Expected
        }
    }

    It 'never calls the Azure Resource Manager or Microsoft Graph transport' {
        InModuleScope $script:moduleName {
            Mock Invoke-OERArmRequest { throw 'unexpected ARM request' }
            Mock Invoke-OERGraphRequest { throw 'unexpected Graph request' }
            # A subscription name and a management group name are the two spellings an online
            # resolver would look up; the canonical form keeps the one and expands the other offline.
            ConvertTo-OERCanonicalScope -Scope 'sub:Prod' | Should -BeExactly 'sub:Prod'
            ConvertTo-OERCanonicalScope -Scope 'mg:Platform Display' | Should -BeExactly '/providers/Microsoft.Management/managementGroups/Platform Display'
            Should -Invoke Invoke-OERArmRequest -Times 0
            Should -Invoke Invoke-OERGraphRequest -Times 0
        }
    }
}
