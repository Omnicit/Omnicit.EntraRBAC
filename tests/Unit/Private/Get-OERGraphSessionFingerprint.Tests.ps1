BeforeAll {
    Import-Module Omnicit.EntraRBAC -Force
    . "$PSScriptRoot/../TestHelpers/OERTransportTripwire.ps1"
    Install-OERTransportTripwire
}

AfterAll {
    try { Assert-OERTransportTripwire } finally { Uninstall-OERTransportTripwire }
}

# MEASURED 2026-10-05 against Microsoft.Graph.Authentication 2.41.1, by reflection over the type
# Get-MgContext declares, with no session in the process. What the SDK puts in those properties was
# READ in that release's source (tag v2.41.1), not executed: a Connect-MgGraph -AccessToken session,
# the one this module makes, has AuthType and TokenCredentialType UserProvidedAccessToken, and ClientId,
# TenantId, Account, AppName and Scopes decoded from the token's appid, tid, upn, app_displayname and
# scp/roles claims; a certificate session has AuthType AppOnly and TokenCredentialType
# ClientCertificate. CI resolves the newest SDK on every run, so a renamed or retyped property turns
# this Describe red instead of leaving the fingerprint to compare two empty values as equal.
Describe 'Get-OERGraphSessionFingerprint: the Graph SDK context contract (measured)' {
    BeforeAll {
        $script:ContextType = (Get-Command -Name Get-MgContext -Module Microsoft.Graph.Authentication).OutputType[0].Type
    }

    It 'Get-MgContext declares IAuthContext as its output' {
        $script:ContextType.FullName | Should -Be 'Microsoft.Graph.PowerShell.Authentication.IAuthContext'
    }

    It 'IAuthContext exposes <Name> as <Type>, which the fingerprint reads' -ForEach @(
        @{ Name = 'AuthType'; Type = 'AuthenticationType' }
        @{ Name = 'TokenCredentialType'; Type = 'TokenCredentialType' }
        @{ Name = 'ClientId'; Type = 'String' }
        @{ Name = 'TenantId'; Type = 'String' }
        @{ Name = 'Account'; Type = 'String' }
        @{ Name = 'AppName'; Type = 'String' }
        @{ Name = 'Environment'; Type = 'String' }
        @{ Name = 'Scopes'; Type = 'String[]' }
    ) {
        $Property = $script:ContextType.GetProperty($Name)
        $Property | Should -Not -BeNullOrEmpty -Because "the fingerprint reads $Name"
        $Property.PropertyType.Name | Should -Be $Type
    }

    It 'IAuthContext also carries <Name>, which the fingerprint never reads' -ForEach @(
        @{ Name = 'ClientSecret'; Type = 'SecureString' }
        @{ Name = 'Certificate'; Type = 'X509Certificate2' }
    ) {
        $Property = $script:ContextType.GetProperty($Name)
        $Property | Should -Not -BeNullOrEmpty
        $Property.PropertyType.Name | Should -Be $Type
    }
}
