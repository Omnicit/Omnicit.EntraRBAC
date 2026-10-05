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

Describe 'Get-OERGraphSessionFingerprint' {
    BeforeAll {
        # A context shaped like the one Connect-MgGraph -AccessToken leaves for this module (see the
        # contract Describe above), with every IAuthContext property present.
        function script:New-TestGraphContext {
            param([hashtable]$Override = @{})
            $Values = [ordered]@{
                AuthType               = 'UserProvidedAccessToken'
                TokenCredentialType    = 'UserProvidedAccessToken'
                ClientId               = '11111111-1111-1111-1111-111111111111'
                TenantId               = '22222222-2222-2222-2222-222222222222'
                Account                = 'admin@contoso.com'
                AppName                = 'oer-test-app'
                Environment            = 'Global'
                Scopes                 = @('Group.ReadWrite.All', 'Directory.Read.All')
                ContextScope           = 'Process'
                CertificateThumbprint  = $null
                CertificateSubjectName = $null
                ManagedIdentityId      = $null
                LoginHint              = $null
                HomeAccountId          = $null
                PSHostVersion          = [version]'7.6.0'
                ClientSecret           = $null
                Certificate            = $null
            }
            foreach ($Key in $Override.Keys) { $Values[$Key] = $Override[$Key] }
            [pscustomobject]$Values
        }
    }

    It 'returns $null for a $null context' {
        InModuleScope Omnicit.EntraRBAC { Get-OERGraphSessionFingerprint -Context $null } | Should -BeNullOrEmpty
    }

    It 'calls Get-MgContext exactly once when no context is given, and returns $null when it writes nothing' {
        Mock -ModuleName Omnicit.EntraRBAC Get-MgContext { }
        InModuleScope Omnicit.EntraRBAC { Get-OERGraphSessionFingerprint } | Should -BeNullOrEmpty
        Should -Invoke -ModuleName Omnicit.EntraRBAC Get-MgContext -Times 1 -Exactly
    }

    It 'fingerprints the context Get-MgContext returns when no context is given' {
        $script:FixtureContext = New-TestGraphContext
        $Ctx = $script:FixtureContext
        Mock -ModuleName Omnicit.EntraRBAC Get-MgContext { $script:FixtureContext }
        $FromCall = InModuleScope Omnicit.EntraRBAC { Get-OERGraphSessionFingerprint }
        $Direct = InModuleScope Omnicit.EntraRBAC -Parameters @{ C = $Ctx } { param($C) Get-OERGraphSessionFingerprint -Context $C }
        $FromCall | Should -Not -BeNullOrEmpty
        $FromCall | Should -BeExactly $Direct
    }

    It 'gives two distinct context objects with equal values the same fingerprint' {
        # Two runspaces connected as the same identity to the same tenant must not refuse each other.
        $A = New-TestGraphContext
        $B = New-TestGraphContext
        [object]::ReferenceEquals($A, $B) | Should -BeFalse
        $Fa = InModuleScope Omnicit.EntraRBAC -Parameters @{ C = $A } { param($C) Get-OERGraphSessionFingerprint -Context $C }
        $Fb = InModuleScope Omnicit.EntraRBAC -Parameters @{ C = $B } { param($C) Get-OERGraphSessionFingerprint -Context $C }
        $Fa | Should -BeExactly $Fb
    }

    It 'ignores the order of the scopes' {
        $A = New-TestGraphContext
        $B = New-TestGraphContext -Override @{ Scopes = @('Directory.Read.All', 'Group.ReadWrite.All') }
        $Fa = InModuleScope Omnicit.EntraRBAC -Parameters @{ C = $A } { param($C) Get-OERGraphSessionFingerprint -Context $C }
        $Fb = InModuleScope Omnicit.EntraRBAC -Parameters @{ C = $B } { param($C) Get-OERGraphSessionFingerprint -Context $C }
        $Fa | Should -BeExactly $Fb
    }

    It 'changes when <Name> changes' -ForEach @(
        @{ Name = 'AuthType'; Value = 'AppOnly' }
        @{ Name = 'TokenCredentialType'; Value = 'ClientCertificate' }
        @{ Name = 'ClientId'; Value = '33333333-3333-3333-3333-333333333333' }
        @{ Name = 'TenantId'; Value = '44444444-4444-4444-4444-444444444444' }
        @{ Name = 'Account'; Value = 'other@contoso.com' }
        @{ Name = 'AppName'; Value = 'another-app' }
        @{ Name = 'Environment'; Value = 'USGov' }
        @{ Name = 'Scopes'; Value = @('Group.ReadWrite.All') }
    ) {
        $A = New-TestGraphContext
        $B = New-TestGraphContext -Override @{ $Name = $Value }
        $Fa = InModuleScope Omnicit.EntraRBAC -Parameters @{ C = $A } { param($C) Get-OERGraphSessionFingerprint -Context $C }
        $Fb = InModuleScope Omnicit.EntraRBAC -Parameters @{ C = $B } { param($C) Get-OERGraphSessionFingerprint -Context $C }
        $Fb | Should -Not -BeExactly $Fa
    }

    It 'tells a certificate session for another app in the same tenant from the module''s own session' {
        $Own = New-TestGraphContext
        $Other = New-TestGraphContext -Override @{
            AuthType = 'AppOnly'; TokenCredentialType = 'ClientCertificate'
            ClientId = '55555555-5555-5555-5555-555555555555'; AppName = 'another-app'; Account = $null
            CertificateThumbprint = 'NOT-A-REAL-THUMBPRINT'; Scopes = @()
        }
        $Fo = InModuleScope Omnicit.EntraRBAC -Parameters @{ C = $Own } { param($C) Get-OERGraphSessionFingerprint -Context $C }
        $Fx = InModuleScope Omnicit.EntraRBAC -Parameters @{ C = $Other } { param($C) Get-OERGraphSessionFingerprint -Context $C }
        $Fx | Should -Not -BeExactly $Fo
    }

    It 'does not change when <Name> changes' -ForEach @(
        @{ Name = 'ContextScope'; Value = 'CurrentUser' }
        @{ Name = 'CertificateThumbprint'; Value = 'NOT-A-REAL-THUMBPRINT' }
        @{ Name = 'LoginHint'; Value = 'admin@contoso.com' }
        @{ Name = 'HomeAccountId'; Value = 'home' }
        @{ Name = 'PSHostVersion'; Value = [version]'7.4.0' }
    ) {
        $A = New-TestGraphContext
        $B = New-TestGraphContext -Override @{ $Name = $Value }
        $Fa = InModuleScope Omnicit.EntraRBAC -Parameters @{ C = $A } { param($C) Get-OERGraphSessionFingerprint -Context $C }
        $Fb = InModuleScope Omnicit.EntraRBAC -Parameters @{ C = $B } { param($C) Get-OERGraphSessionFingerprint -Context $C }
        $Fb | Should -BeExactly $Fa
    }

    It 'builds a fingerprint for a context with no scopes and no account' {
        $Ctx = New-TestGraphContext -Override @{ Scopes = $null; Account = $null }
        $F = InModuleScope Omnicit.EntraRBAC -Parameters @{ C = $Ctx } { param($C) Get-OERGraphSessionFingerprint -Context $C }
        $F | Should -Not -BeNullOrEmpty
    }

    It 'never reads the client secret or the certificate' {
        # Each getter RECORDS that it ran. A getter that throws proves nothing: PowerShell swallows an
        # exception raised by a ScriptProperty getter on member access and returns $null, inside a try
        # as well (measured 2026-10-05, PowerShell 7), so a throwing getter passes with the read in place.
        $Reads = [System.Collections.Generic.List[string]]::new()
        $Ctx = New-TestGraphContext
        $Ctx.PSObject.Properties.Remove('ClientSecret')
        $Ctx.PSObject.Properties.Remove('Certificate')
        $Ctx | Add-Member -MemberType ScriptProperty -Name ClientSecret -Value ({ $Reads.Add('ClientSecret') }.GetNewClosure())
        $Ctx | Add-Member -MemberType ScriptProperty -Name Certificate -Value ({ $Reads.Add('Certificate') }.GetNewClosure())
        $F = InModuleScope Omnicit.EntraRBAC -Parameters @{ C = $Ctx } { param($C) Get-OERGraphSessionFingerprint -Context $C }
        $F | Should -Not -BeNullOrEmpty
        ($Reads -join ', ') | Should -BeNullOrEmpty -Because 'the fingerprint reads neither property'
        # The getters do fire when read, so the empty record above is evidence and not an inert hook.
        $null = $Ctx.ClientSecret
        $null = $Ctx.Certificate
        ($Reads -join ', ') | Should -BeExactly 'ClientSecret, Certificate'
    }

    It 'holds no secret and no token' {
        $Secret = ConvertTo-SecureString 'NOT-A-REAL-TOKEN-secret-value' -AsPlainText -Force
        $Ctx = New-TestGraphContext -Override @{ ClientSecret = $Secret }
        $F = InModuleScope Omnicit.EntraRBAC -Parameters @{ C = $Ctx } { param($C) Get-OERGraphSessionFingerprint -Context $C }
        $F | Should -Not -Match 'NOT-A-REAL-TOKEN'
        $F | Should -Not -Match 'eyJ'
    }
}
