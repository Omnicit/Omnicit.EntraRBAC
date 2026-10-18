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

Describe 'ConvertTo-OERPrincipalType' {
    It 'maps <ODataType> to <Expected>' -ForEach @(
        @{ ODataType = '#microsoft.graph.user'; Expected = 'User' }
        @{ ODataType = 'user'; Expected = 'User' }
        @{ ODataType = '#Microsoft.Graph.USER'; Expected = 'User' }
        @{ ODataType = 'User'; Expected = 'User' }
        @{ ODataType = '#microsoft.graph.group'; Expected = 'Group' }
        @{ ODataType = 'group'; Expected = 'Group' }
        @{ ODataType = '#MICROSOFT.GRAPH.Group'; Expected = 'Group' }
        @{ ODataType = 'GROUP'; Expected = 'Group' }
        @{ ODataType = '#microsoft.graph.servicePrincipal'; Expected = 'ServicePrincipal' }
        @{ ODataType = 'servicePrincipal'; Expected = 'ServicePrincipal' }
        @{ ODataType = '#microsoft.graph.SERVICEPRINCIPAL'; Expected = 'ServicePrincipal' }
        @{ ODataType = 'serviceprincipal'; Expected = 'ServicePrincipal' }
    ) {
        $Result = InModuleScope $script:moduleName -Parameters @{ Type = $ODataType } { param($Type) ConvertTo-OERPrincipalType -ODataType $Type }
        $Result | Should -BeExactly $Expected
        $Result | Should -BeOfType ([string])
    }

    It 'returns $null for <Name>: a type is never guessed' -ForEach @(
        @{ Name = 'a device'; ODataType = '#microsoft.graph.device' }
        @{ Name = 'a bare device'; ODataType = 'device' }
        @{ Name = 'another directory object type'; ODataType = '#microsoft.graph.application' }
        @{ Name = 'an empty value'; ODataType = '' }
        @{ Name = 'null'; ODataType = $null }
        @{ Name = 'a type with a different prefix'; ODataType = '#microsoft.directory.user' }
        @{ Name = 'a prefix without its number sign'; ODataType = 'microsoft.graph.user' }
        @{ Name = 'the prefix alone'; ODataType = '#microsoft.graph.' }
        @{ Name = 'white space around a type'; ODataType = ' user ' }
        @{ Name = 'a type that merely starts with a known one'; ODataType = '#microsoft.graph.userX' }
    ) {
        $Result = InModuleScope $script:moduleName -Parameters @{ Type = $ODataType } { param($Type) ConvertTo-OERPrincipalType -ODataType $Type }
        $null -eq $Result | Should -BeTrue
    }

    It 'answers the same under a culture whose case rules differ (ordinal comparison)' {
        $Saved = [System.Globalization.CultureInfo]::CurrentCulture
        try {
            [System.Globalization.CultureInfo]::CurrentCulture = [System.Globalization.CultureInfo]::new('tr-TR')
            $Result = InModuleScope $script:moduleName { ConvertTo-OERPrincipalType -ODataType '#MICROSOFT.GRAPH.SERVICEPRINCIPAL' }
        } finally {
            [System.Globalization.CultureInfo]::CurrentCulture = $Saved
        }
        $Result | Should -BeExactly 'ServicePrincipal'
    }
}
