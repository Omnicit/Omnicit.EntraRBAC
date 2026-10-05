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

Describe 'ConvertTo-OERScopeSplat' {
    # No id below is version-4 shaped.

    It 'parses <Scope> into exactly one <Key> key holding <Value>' -ForEach @(
        @{ Scope = 'mg:platform'; Key = 'ManagementGroup'; Value = 'platform' }
        @{ Scope = 'MG:platform'; Key = 'ManagementGroup'; Value = 'platform' }
        @{ Scope = 'sub:Prod'; Key = 'Subscription'; Value = 'Prod' }
        @{ Scope = 'subscription:aaaa1111-0000-0000-0000-000000000001'; Key = 'Subscription'; Value = 'aaaa1111-0000-0000-0000-000000000001' }
        @{ Scope = '/subscriptions/x/resourceGroups/y/'; Key = 'Scope'; Value = '/subscriptions/x/resourceGroups/y' }
    ) {
        InModuleScope $script:moduleName -Parameters @{ Scope = $Scope; Key = $Key; Value = $Value } {
            param($Scope, $Key, $Value)
            $Splat = ConvertTo-OERScopeSplat -Scope $Scope
            $Splat | Should -BeOfType [hashtable]
            @($Splat.Keys) | Should -Be @($Key)
            $Splat[$Key] | Should -BeExactly $Value
        }
    }
}
