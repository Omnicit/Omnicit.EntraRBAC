BeforeAll {
    $script:moduleName = 'Omnicit.EntraRBAC'
    Get-Module $script:moduleName | Remove-Module -Force -ErrorAction SilentlyContinue
    Import-Module $script:moduleName -Force -ErrorAction Stop
    . "$PSScriptRoot/../TestHelpers/OERTransportTripwire.ps1"
    Install-OERTransportTripwire

    # One stable Graph SDK context for every test in this file, unless a test mocks its own. Without
    # it the state rebuild would read the REAL Get-MgContext: empty on CI, a developer's own session
    # on a workstation.
    $script:DefaultGraphContext = [pscustomobject]@{
        AuthType = 'UserProvidedAccessToken'; TokenCredentialType = 'UserProvidedAccessToken'
        ClientId = '11111111-1111-1111-1111-111111111111'; TenantId = '22222222-2222-2222-2222-222222222222'
        Account = 'admin@contoso.com'; AppName = 'oer-test-app'; Environment = 'Global'
        Scopes = @('Group.ReadWrite.All')
    }
    Mock -ModuleName $script:moduleName Get-MgContext { $script:DefaultGraphContext }

    # The host these tests run in may have been started with -NonInteractive (the build agent's tool host
    # is), and Initialize-OERAuth refuses an interactive sign-in there (BL-100). Every suite below
    # signs in interactively as an ordinary user would, so the host question is answered "no" for the
    # whole file; the Describe on that refusal mocks it to $true for itself.
    Mock -ModuleName $script:moduleName Test-OERHostNonInteractive { $false }

    # Builds a JWT-shaped string at run time only -- never a literal starting 'eyJ' in this tracked
    # file -- for the Get-OERTokenObjectId (oid claim / SignedInObjectId) tests below. The signature
    # segment is deliberately not a real signature; nothing here checks one.
    function New-TestToken {
        param([hashtable]$Claims)
        $Encode = {
            param([string]$Json)
            [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($Json)).TrimEnd('=').Replace('+', '-').Replace('/', '_')
        }
        $Header = & $Encode (@{ alg = 'none'; typ = 'JWT' } | ConvertTo-Json -Compress)
        $Payload = & $Encode ($Claims | ConvertTo-Json -Compress)
        "$Header.$Payload.NOT-A-REAL-TOKEN"
    }
}

AfterAll {
    try { Assert-OERTransportTripwire } finally { Uninstall-OERTransportTripwire }
}

Describe 'Initialize-OERAuth' {
    BeforeEach {
        # $script:_OERLastAuthorityHost is deliberately NOT cleared by Disconnect-OER, so nothing in
        # the module ever resets it. Reset it here, or a sovereign test leaks its authority into the
        # next test, which would then silently gain the -Force the public path must never carry.
        InModuleScope $script:moduleName {
            $script:_OERAuthState = $null
            $script:_OERSessionUncertain = $null
            $script:_OERLastAuthorityHost = $null
            $script:_OERLastTokenRequest = $null
            $script:_OERInteractiveCredential = $null
        }
        # BL-12: a tenant named by anything but a GUID or 'organizations' is looked up before any token
        # is requested. The tokens in this Describe carry no GUID tenant, so the mocked lookup answers
        # with any tenant ID.
        Mock -ModuleName $script:moduleName Resolve-OERTenantDomain { '11111111-1111-1111-1111-111111111111' }
    }

    # -- Existing test 1: interactive flow acquires graph token ------------------------------------
    It 'acquires a Graph token via Get-AzToken (interactive) and connects MgGraph' {
        Mock -ModuleName $script:moduleName Get-AzToken {
            [pscustomobject]@{ Token = 'fake-graph-token'; ExpiresOn = [DateTimeOffset]::UtcNow.AddHours(1); Identity = 'admin@contoso.com'; TenantId = 'contoso' }
        }
        Mock -ModuleName $script:moduleName Connect-MgGraph { }

        InModuleScope $script:moduleName {
            Initialize-OERAuth -TenantId 'contoso' -AuthMethod 'Interactive'
            $script:_OERAuthState.TenantId | Should -Be 'contoso'
            $script:_OERAuthState.GraphTokenExpiry | Should -BeGreaterThan ([DateTime]::UtcNow)
        }
        Should -Invoke -ModuleName $script:moduleName Get-AzToken -Times 1
        Should -Invoke -ModuleName $script:moduleName Connect-MgGraph -Times 1
    }

    # Delegated Graph must use the preauthorized public client (Microsoft Graph Command Line Tools)
    # so interactive consent for the Graph scopes works; the AzAuth default client (Azure CLI) is
    # not preauthorized and fails with AADSTS65002.
    It 'requests delegated Graph with the Microsoft Graph Command Line Tools client id' {
        Mock -ModuleName $script:moduleName Get-AzToken {
            param($ClientId, $ClientSecret, $Resource, $Tenant, $ErrorAction, $Interactive,
                  $DeviceCode, $ManagedIdentity, $ClientCertificate, $ClientCertificatePath,
                  $Scope, $Force, $Claim)
            $script:CapturedClientId = $ClientId
            [pscustomobject]@{ Token = 'fake'; ExpiresOn = [DateTimeOffset]::UtcNow.AddHours(1); Identity = 'u'; TenantId = 'contoso' }
        }
        Mock -ModuleName $script:moduleName Connect-MgGraph { }
        InModuleScope $script:moduleName {
            Initialize-OERAuth -TenantId 'contoso' -AuthMethod 'Interactive'
        }
        $script:CapturedClientId | Should -Be '14d82eec-204b-4c2f-b7e8-296a70dab67e'
    }

    # The delegated scope set must include AccessReview.ReadWrite.All so the Phase 3b access-review
    # cmdlets work; without it a token would be issued lacking the scope and Graph returns 403.
    It 'requests the AccessReview.ReadWrite.All delegated scope' {
        Mock -ModuleName $script:moduleName Get-AzToken {
            param($ClientId, $ClientSecret, $Resource, $Tenant, $ErrorAction, $Interactive,
                  $DeviceCode, $ManagedIdentity, $ClientCertificate, $ClientCertificatePath,
                  $Scope, $Force, $Claim)
            $script:CapturedScope = $Scope
            [pscustomobject]@{ Token = 'fake'; ExpiresOn = [DateTimeOffset]::UtcNow.AddHours(1); Identity = 'u'; TenantId = 'contoso' }
        }
        Mock -ModuleName $script:moduleName Connect-MgGraph { }
        InModuleScope $script:moduleName {
            Initialize-OERAuth -TenantId 'contoso' -AuthMethod 'Interactive'
        }
        $script:CapturedScope | Should -Contain 'AccessReview.ReadWrite.All'
    }

    # A caller-supplied ClientId must drive delegated sign-in (own app => own throttling bucket).
    It 'uses a caller-supplied ClientId for interactive sign-in instead of the default client' {
        Mock -ModuleName $script:moduleName Get-AzToken {
            param($ClientId, $ClientSecret, $Resource, $Tenant, $ErrorAction, $Interactive,
                  $DeviceCode, $ManagedIdentity, $ClientCertificate, $ClientCertificatePath,
                  $Scope, $Force, $Claim)
            $script:CapturedClientId = $ClientId
            [pscustomobject]@{ Token = 'fake'; ExpiresOn = [DateTimeOffset]::UtcNow.AddHours(1); Identity = 'u'; TenantId = 'contoso' }
        }
        Mock -ModuleName $script:moduleName Connect-MgGraph { }
        InModuleScope $script:moduleName {
            Initialize-OERAuth -TenantId 'contoso' -AuthMethod 'Interactive' -ClientId 'my-app-id'
        }
        $script:CapturedClientId | Should -Be 'my-app-id'
    }

    # Existing test 2: idempotency
    It 'is idempotent: a cached valid token skips Get-AzToken' {
        Mock -ModuleName $script:moduleName Get-AzToken {
            [pscustomobject]@{ Token = 'fake'; ExpiresOn = [DateTimeOffset]::UtcNow.AddHours(1); Identity = 'a@b.c'; TenantId = 'contoso' }
        }
        Mock -ModuleName $script:moduleName Connect-MgGraph { }
        InModuleScope $script:moduleName {
            Initialize-OERAuth -TenantId 'contoso' -AuthMethod 'Interactive'
            Initialize-OERAuth -TenantId 'contoso' -AuthMethod 'Interactive'
        }
        Should -Invoke -ModuleName $script:moduleName Get-AzToken -Times 1
    }

    # -- Existing test 3: ClientSecret params forwarded (updated to pass SecureString) -------------
    It 'passes ClientSecret parameters through to Get-AzToken, materialising the SecureString as plaintext' {
        Mock -ModuleName $script:moduleName Get-AzToken {
            param($ClientId, $ClientSecret, $Resource, $Tenant, $ErrorAction, $Interactive,
                  $DeviceCode, $ManagedIdentity, $ClientCertificate, $ClientCertificatePath,
                  $Scope, $Force, $Claim)
            $script:CapturedKeys   = $PSBoundParameters.Keys
            $script:CapturedSecret = $PSBoundParameters['ClientSecret']
            [pscustomobject]@{ Token = 'fake'; ExpiresOn = [DateTimeOffset]::UtcNow.AddHours(1); Identity = 'sp'; TenantId = 'contoso' }
        }
        Mock -ModuleName $script:moduleName Connect-MgGraph { }

        # Pass the SecureString via -Parameters so InModuleScope receives it as a local variable.
        $Secret = ConvertTo-SecureString 'sek' -AsPlainText -Force
        InModuleScope $script:moduleName -Parameters @{ Secret = $Secret } {
            Initialize-OERAuth -TenantId 'contoso' -AuthMethod 'ClientSecret' -ClientId 'cid' `
                -ClientSecret $Secret
        }

        $script:CapturedKeys   | Should -Contain 'ClientSecret'
        $script:CapturedKeys   | Should -Contain 'ClientId'
        # The SecureString must have been materialised to the correct plaintext at the call boundary.
        $script:CapturedSecret | Should -Be 'sek'
    }

    # -- Existing test 4: ARM token ----------------------------------------------------------------
    It 'acquires and caches an ARM bearer token (no Connect-AzAccount) when -IncludeARM is set' {
        Mock -ModuleName $script:moduleName Get-AzToken {
            [pscustomobject]@{ Token = 'fake'; ExpiresOn = [DateTimeOffset]::UtcNow.AddHours(1); Identity = 'admin@contoso.com'; TenantId = 'contoso' }
        }
        Mock -ModuleName $script:moduleName Connect-MgGraph { }
        Mock -ModuleName $script:moduleName Connect-AzAccount { }
        InModuleScope $script:moduleName {
            Initialize-OERAuth -TenantId 'contoso' -AuthMethod 'Interactive' -IncludeARM
            $script:_OERAuthState.ArmTokenExpiry | Should -BeGreaterThan ([DateTime]::UtcNow)
            $script:_OERAuthState.ArmToken | Should -BeOfType [System.Security.SecureString]
            $script:_OERAuthState.ArmResourceUrl | Should -Be 'https://management.azure.com/'
        }
        Should -Invoke -ModuleName $script:moduleName Get-AzToken -Times 2
        # The module no longer establishes an Az context; it sends the bearer token directly.
        # This negative assertion is the test-level proof of the premise Az.Resources was removed
        # on (2026-09-21). It depends on Az.Accounts being resolved into output/RequiredModules so
        # that the Mock above can resolve Connect-AzAccount at all. If that Mock ever fails to
        # resolve, restore the Az.Accounts entry in RequiredModules.psd1 -- never delete this
        # assertion to make the error go away, which would leave the suite green and the proof
        # gone. See docs/development/rationale.md#dependencies.
        Should -Invoke -ModuleName $script:moduleName Connect-AzAccount -Times 0
    }

    # -- New test 5: ForceRefresh bypasses the cache -----------------------------------------------
    It 'ForceRefresh bypasses the cache and re-acquires a fresh token' {
        Mock -ModuleName $script:moduleName Get-AzToken {
            [pscustomobject]@{ Token = 'fake'; ExpiresOn = [DateTimeOffset]::UtcNow.AddHours(1); Identity = 'a@b.c'; TenantId = 'contoso' }
        }
        Mock -ModuleName $script:moduleName Connect-MgGraph { }

        InModuleScope $script:moduleName {
            # First call primes the cache.
            Initialize-OERAuth -TenantId 'contoso' -AuthMethod 'Interactive'
            # Second call with -ForceRefresh must not return from cache.
            Initialize-OERAuth -TenantId 'contoso' -AuthMethod 'Interactive' -ForceRefresh
        }

        Should -Invoke -ModuleName $script:moduleName Get-AzToken -Times 2
    }

    # -- New test 6: identity switch (different AuthMethod) re-acquires ----------------------------
    It 'does not reuse the cache when AuthMethod or ClientId changes' {
        Mock -ModuleName $script:moduleName Get-AzToken {
            [pscustomobject]@{ Token = 'fake'; ExpiresOn = [DateTimeOffset]::UtcNow.AddHours(1); Identity = 'a@b.c'; TenantId = 'contoso' }
        }
        Mock -ModuleName $script:moduleName Connect-MgGraph { }

        # Pass the SecureString via -Parameters so InModuleScope receives it as a local variable.
        $Secret = ConvertTo-SecureString 'sek' -AsPlainText -Force
        InModuleScope $script:moduleName -Parameters @{ Secret = $Secret } {
            # First call: Interactive, no ClientId.
            Initialize-OERAuth -TenantId 'contoso' -AuthMethod 'Interactive'
            # Second call: different AuthMethod + ClientId -- cache must NOT be reused.
            Initialize-OERAuth -TenantId 'contoso' -AuthMethod 'ClientSecret' -ClientId 'cid' `
                -ClientSecret $Secret
        }

        Should -Invoke -ModuleName $script:moduleName Get-AzToken -Times 2
    }

    # -- New test 7: Graph token acquisition failure is terminating --------------------------------
    It 'throws a terminating error when Get-AzToken fails for the Graph resource' {
        Mock -ModuleName $script:moduleName Get-AzToken { throw 'graph boom' }
        Mock -ModuleName $script:moduleName Connect-MgGraph { }

        { InModuleScope $script:moduleName { Initialize-OERAuth -TenantId 'contoso' -AuthMethod 'Interactive' } } |
            Should -Throw
    }

    # -- New test 8: ARM token failure is non-terminating (Graph state preserved) ------------------
    It 'emits a non-terminating error for ARM failure and preserves the Graph token state' {
        # Use a script-scoped call counter to differentiate Graph vs ARM token requests.
        $script:GetAzTokenCallCount = 0
        Mock -ModuleName $script:moduleName Get-AzToken {
            $script:GetAzTokenCallCount++
            if ($script:GetAzTokenCallCount -eq 1) {
                # First call = Graph token; succeed.
                [pscustomobject]@{ Token = 'fake-graph'; ExpiresOn = [DateTimeOffset]::UtcNow.AddHours(1); Identity = 'a@b.c'; TenantId = 'contoso' }
            } else {
                # Second call = ARM token; fail.
                throw 'arm boom'
            }
        }
        Mock -ModuleName $script:moduleName Connect-MgGraph { }
        Mock -ModuleName $script:moduleName Connect-AzAccount { }

        # The call must not throw (ARM failure is non-terminating).
        { InModuleScope $script:moduleName {
            Initialize-OERAuth -TenantId 'contoso' -AuthMethod 'Interactive' -IncludeARM -ErrorAction SilentlyContinue
        } } | Should -Not -Throw

        # Graph state must still be set despite the ARM failure.
        InModuleScope $script:moduleName {
            $script:_OERAuthState.GraphTokenExpiry | Should -BeGreaterThan ([DateTime]::UtcNow)
        }
    }

    # -- New test: certificate in-memory forwarded -------------------------------------------------
    It 'forwards client certificate (in-memory) to Get-AzToken' {
        Mock -ModuleName $script:moduleName Get-AzToken {
            param($ClientId, $ClientSecret, $Resource, $Tenant, $ErrorAction, $Interactive,
                  $DeviceCode, $ManagedIdentity, $ClientCertificate, $ClientCertificatePath,
                  $Scope, $Force, $Claim)
            $script:CapturedKeys = $PSBoundParameters.Keys
            [pscustomobject]@{ Token = 'fake'; ExpiresOn = [DateTimeOffset]::UtcNow.AddHours(1); Identity = 'sp'; TenantId = 'contoso' }
        }
        Mock -ModuleName $script:moduleName Connect-MgGraph { }
        $Cert = [System.Security.Cryptography.X509Certificates.X509Certificate2]::new()
        InModuleScope $script:moduleName -Parameters @{ Cert = $Cert } {
            param($Cert)
            Initialize-OERAuth -TenantId 'contoso' -AuthMethod 'ClientCertificate' -ClientId 'cid' -Certificate $Cert
        }
        $script:CapturedKeys | Should -Contain 'ClientCertificate'
    }

    # -- New test: certificate path forwarded ------------------------------------------------------
    It 'forwards client certificate path to Get-AzToken' {
        Mock -ModuleName $script:moduleName Get-AzToken {
            param($ClientId, $ClientSecret, $Resource, $Tenant, $ErrorAction, $Interactive,
                  $DeviceCode, $ManagedIdentity, $ClientCertificate, $ClientCertificatePath,
                  $Scope, $Force, $Claim)
            $script:CapturedKeys = $PSBoundParameters.Keys
            [pscustomobject]@{ Token = 'fake'; ExpiresOn = [DateTimeOffset]::UtcNow.AddHours(1); Identity = 'sp'; TenantId = 'contoso' }
        }
        Mock -ModuleName $script:moduleName Connect-MgGraph { }
        InModuleScope $script:moduleName {
            Initialize-OERAuth -TenantId 'contoso' -AuthMethod 'ClientCertificate' -ClientId 'cid' -CertificatePath 'C:\c\app.pfx'
        }
        $script:CapturedKeys | Should -Contain 'ClientCertificatePath'
    }

    # -- New test: SignedInObjectId recorded from an app-only token's oid claim (R11) ---------------
    It 'records SignedInObjectId from the oid claim of an app-only (certificate) token' {
        $AppOnlyToken = New-TestToken -Claims @{
            oid   = 'aaaaaaaa-0000-0000-0000-000000000002'
            roles = @('RoleManagement.ReadWrite.Directory')
            idtyp = 'app'
            appid = '11111111-1111-1111-1111-111111111111'
        }
        Mock -ModuleName $script:moduleName Get-AzToken {
            param($ClientId, $ClientSecret, $Resource, $Tenant, $ErrorAction, $Interactive,
                  $DeviceCode, $ManagedIdentity, $ClientCertificate, $ClientCertificatePath,
                  $Scope, $Force, $Claim)
            [pscustomobject]@{ Token = $AppOnlyToken; ExpiresOn = [DateTimeOffset]::UtcNow.AddHours(1); Identity = 'sp'; TenantId = 'contoso' }
        }
        Mock -ModuleName $script:moduleName Connect-MgGraph { }
        InModuleScope $script:moduleName -Parameters @{ AppOnlyToken = $AppOnlyToken } {
            param($AppOnlyToken)
            Initialize-OERAuth -TenantId 'contoso' -AuthMethod 'ClientCertificate' -ClientId 'cid' -CertificatePath 'C:\c\app.pfx'
            $script:_OERAuthState.SignedInObjectId | Should -BeExactly 'aaaaaaaa-0000-0000-0000-000000000002'
        }
    }

    # -- New test: the oid reader receives the Graph token as a SecureString (module logging) ---------
    # PowerShell module logging (Event 4103) records every bound parameter value, so the token must
    # never be bound to a [string] parameter. AzAuth hands the token back as plain text (the mocked
    # Get-AzToken below keeps that shape); Initialize-OERAuth must pass the SecureString it already
    # builds for Connect-MgGraph, and that SecureString must carry exactly the acquired token.
    It 'passes the Graph token to Get-OERTokenObjectId as a SecureString, never as plain text' {
        $AppOnlyToken = New-TestToken -Claims @{
            oid   = 'aaaaaaaa-0000-0000-0000-000000000002'
            idtyp = 'app'
        }
        Mock -ModuleName $script:moduleName Get-AzToken {
            [pscustomobject]@{ Token = $AppOnlyToken; ExpiresOn = [DateTimeOffset]::UtcNow.AddHours(1); Identity = 'sp'; TenantId = 'contoso' }
        }
        Mock -ModuleName $script:moduleName Connect-MgGraph { }
        Mock -ModuleName $script:moduleName Get-OERTokenObjectId { 'aaaaaaaa-0000-0000-0000-000000000009' }
        InModuleScope $script:moduleName {
            Initialize-OERAuth -TenantId 'contoso' -AuthMethod 'ClientCertificate' -ClientId 'cid' -CertificatePath 'C:\c\app.pfx'
            $script:_OERAuthState.SignedInObjectId | Should -BeExactly 'aaaaaaaa-0000-0000-0000-000000000009'
        }
        Should -Invoke -ModuleName $script:moduleName Get-OERTokenObjectId -Times 1 -Exactly -ParameterFilter {
            $Token -is [securestring] -and
            [System.Net.NetworkCredential]::new('', $Token).Password -ceq $AppOnlyToken
        }
    }

    # -- New test: SignedInObjectId is $null for a non-JWT mocked token (the fixtures every other -----
    # -- test in this file uses), so this key never regresses an existing test's expectations. --------
    It 'records SignedInObjectId as $null for a non-JWT mocked token' {
        Mock -ModuleName $script:moduleName Get-AzToken {
            [pscustomobject]@{ Token = 'fake'; ExpiresOn = [DateTimeOffset]::UtcNow.AddHours(1); Identity = 'sp'; TenantId = 'contoso' }
        }
        Mock -ModuleName $script:moduleName Connect-MgGraph { }
        InModuleScope $script:moduleName {
            Initialize-OERAuth -TenantId 'contoso' -AuthMethod 'ClientCertificate' -ClientId 'cid' -CertificatePath 'C:\c\app.pfx'
            $script:_OERAuthState.SignedInObjectId | Should -BeNullOrEmpty
        }
    }

    # -- New test: missing cert/path is terminating ------------------------------------------------
    It 'throws MissingClientCertificate when no cert or path is supplied' {
        Mock -ModuleName $script:moduleName Get-AzToken { throw 'should not be called' }
        Mock -ModuleName $script:moduleName Connect-MgGraph { }
        InModuleScope $script:moduleName {
            $Caught = $null
            try { Initialize-OERAuth -TenantId 'contoso' -AuthMethod 'ClientCertificate' -ClientId 'cid' } catch { $Caught = $_ }
            $Caught.FullyQualifiedErrorId | Should -Match 'MissingClientCertificate'
        }
    }

    # -- New test: DeviceCode parameter forwarded --------------------------------------------------
    It 'uses the DeviceCode parameter for Get-AzToken' {
        Mock -ModuleName $script:moduleName Get-AzToken {
            param($ClientId, $ClientSecret, $Resource, $Tenant, $ErrorAction, $Interactive,
                  $DeviceCode, $ManagedIdentity, $ClientCertificate, $ClientCertificatePath,
                  $Scope, $Force, $Claim)
            $script:CapturedKeys = $PSBoundParameters.Keys
            [pscustomobject]@{ Token = 'fake'; ExpiresOn = [DateTimeOffset]::UtcNow.AddHours(1); Identity = 'u'; TenantId = 'contoso' }
        }
        Mock -ModuleName $script:moduleName Connect-MgGraph { }
        InModuleScope $script:moduleName {
            Initialize-OERAuth -TenantId 'contoso' -AuthMethod 'DeviceCode'
        }
        $script:CapturedKeys | Should -Contain 'DeviceCode'
    }

    # -- New test: ManagedIdentity parameter forwarded ---------------------------------------------
    It 'uses the ManagedIdentity parameter for Get-AzToken' {
        Mock -ModuleName $script:moduleName Get-AzToken {
            param($ClientId, $ClientSecret, $Resource, $Tenant, $ErrorAction, $Interactive,
                  $DeviceCode, $ManagedIdentity, $ClientCertificate, $ClientCertificatePath,
                  $Scope, $Force, $Claim)
            $script:CapturedKeys = $PSBoundParameters.Keys
            [pscustomobject]@{ Token = 'fake'; ExpiresOn = [DateTimeOffset]::UtcNow.AddHours(1); Identity = 'mi'; TenantId = 'contoso' }
        }
        Mock -ModuleName $script:moduleName Connect-MgGraph { }
        InModuleScope $script:moduleName {
            Initialize-OERAuth -TenantId 'contoso' -AuthMethod 'ManagedIdentity'
        }
        $script:CapturedKeys | Should -Contain 'ManagedIdentity'
    }

    # -- New test: Connect-MgGraph failure is terminating ------------------------------------------
    It 'emits a terminating error when Connect-MgGraph fails' {
        Mock -ModuleName $script:moduleName Get-AzToken {
            [pscustomobject]@{ Token = 'fake'; ExpiresOn = [DateTimeOffset]::UtcNow.AddHours(1); Identity = 'u'; TenantId = 'contoso' }
        }
        Mock -ModuleName $script:moduleName Connect-MgGraph { throw 'connect boom' }
        InModuleScope $script:moduleName {
            { Initialize-OERAuth -TenantId 'contoso' -AuthMethod 'Interactive' } | Should -Throw
        }
    }

    # -- New test: a cached, valid ARM token is reused without re-acquiring ---------------------------
    It 'reuses a cached ARM token without re-acquiring it' {
        Mock -ModuleName $script:moduleName Get-AzToken {
            [pscustomobject]@{ Token = 'fake'; ExpiresOn = [DateTimeOffset]::UtcNow.AddHours(1); Identity = 'u'; TenantId = 'contoso' }
        }
        Mock -ModuleName $script:moduleName Connect-MgGraph { }
        InModuleScope $script:moduleName {
            # First call primes both the Graph and ARM tokens (2 Get-AzToken calls).
            Initialize-OERAuth -TenantId 'contoso' -AuthMethod 'Interactive' -IncludeARM
            # Second call: both tokens are cached and valid -> no further acquisition.
            Initialize-OERAuth -TenantId 'contoso' -AuthMethod 'Interactive' -IncludeARM
            $script:_OERAuthState.ArmToken | Should -BeOfType [System.Security.SecureString]
        }
        Should -Invoke -ModuleName $script:moduleName Get-AzToken -Times 2
    }

    It 'reuses an existing session when no AuthMethod is explicitly passed' {
        Mock -ModuleName $script:moduleName Get-AzToken {
            [pscustomobject]@{ Token = 'fake'; ExpiresOn = [DateTimeOffset]::UtcNow.AddHours(1); Identity = 'sp'; TenantId = 'contoso' }
        }
        Mock -ModuleName $script:moduleName Connect-MgGraph {}
        InModuleScope $script:moduleName {
            # Simulate a prior Connect-OER -ClientSecret session.
            $script:_OERAuthState = @{
                TenantId = 'contoso'; AuthMethod = 'ClientSecret'; ClientId = 'cid'; Environment = 'Global'
                Account = 'sp'; GraphTokenExpiry = [DateTime]::UtcNow.AddHours(1); ArmTokenExpiry = $null; ClaimsSatisfied = $false
            }
            # A group cmdlet ensures connectivity without specifying a method.
            Initialize-OERAuth -TenantId 'contoso'
        }
        Should -Invoke -ModuleName $script:moduleName Get-AzToken -Times 0
    }

    It 'still authenticates when no session exists and no AuthMethod is passed' {
        Mock -ModuleName $script:moduleName Get-AzToken {
            [pscustomobject]@{ Token = 'fake'; ExpiresOn = [DateTimeOffset]::UtcNow.AddHours(1); Identity = 'a@b.c'; TenantId = 'contoso' }
        }
        Mock -ModuleName $script:moduleName Connect-MgGraph {}
        InModuleScope $script:moduleName { Initialize-OERAuth -TenantId 'contoso' }
        Should -Invoke -ModuleName $script:moduleName Get-AzToken -Times 1
    }

    It 'requests the EntitlementManagement.ReadWrite.All scope by default' {
        InModuleScope $script:moduleName {
            $Scopes = (Get-Command Initialize-OERAuth).ScriptBlock.Ast.FindAll(
                { $args[0] -is [System.Management.Automation.Language.StringConstantExpressionAst] }, $true
            ).Value
            $Scopes | Should -Contain 'EntitlementManagement.ReadWrite.All'
        }
    }

    # -- New test 9: Missing ClientSecret produces a terminating error -----------------------------
    It 'throws a terminating MissingClientSecret error when -ClientSecret is omitted for ClientSecret auth' {
        Mock -ModuleName $script:moduleName Get-AzToken { }
        Mock -ModuleName $script:moduleName Connect-MgGraph { }

        # ThrowTerminatingError surfaces as a script-terminating exception; use -Throw without type
        # filter and then inspect the ErrorRecord on the caught exception.
        $thrownError = $null
        try {
            InModuleScope $script:moduleName {
                Initialize-OERAuth -TenantId 'contoso' -AuthMethod 'ClientSecret' -ClientId 'cid'
                # No -ClientSecret supplied.
            }
        } catch {
            $thrownError = $_
        }
        $thrownError | Should -Not -BeNullOrEmpty
        $thrownError.FullyQualifiedErrorId | Should -Match 'MissingClientSecret'
    }
}

Describe 'Initialize-OERAuth ARM cache isolation' {
    BeforeEach {
        # $script:_OERLastAuthorityHost is deliberately NOT cleared by Disconnect-OER, so nothing in
        # the module ever resets it. Reset it here, or a sovereign test leaks its authority into the
        # next test, which would then silently gain the -Force the public path must never carry.
        InModuleScope $script:moduleName {
            $script:_OERAuthState = $null
            $script:_OERSessionUncertain = $null
            $script:_OERLastAuthorityHost = $null
            $script:_OERLastTokenRequest = $null
            $script:_OERInteractiveCredential = $null
        }
        # BL-12: a tenant named by anything but a GUID or 'organizations' is looked up before any token
        # is requested. The tokens in this Describe carry no GUID tenant, so the mocked lookup answers
        # with any tenant ID.
        Mock -ModuleName $script:moduleName Resolve-OERTenantDomain { '11111111-1111-1111-1111-111111111111' }
    }

    # SEC-arm-token-survives-tenant-switch: without a tenant/identity term on the ARM predicate, a
    # tenant switch kept the previous tenant's ARM token cached while $script:_OERAuthState.TenantId
    # reported the new tenant, so ARM reads silently returned the previous customer's resources.
    It 'RE-ACQUIRES the ARM token when the tenant changes (SEC-arm-token-survives-tenant-switch)' {
        Mock -ModuleName $script:moduleName Get-AzToken {
            param($Resource)
            [pscustomobject]@{
                Token     = "token-for-$Resource"
                Identity  = 'user@contoso'
                ExpiresOn = [DateTimeOffset]::UtcNow.AddHours(1)
            }
        }
        Mock -ModuleName $script:moduleName Connect-MgGraph { }

        InModuleScope $script:moduleName {
            # A live session for tenant A, holding a still-valid ARM token.
            $script:_OERAuthState = @{
                TenantId         = 'tenant-a'
                AuthMethod       = 'Interactive'
                ClientId         = ''
                Environment      = 'Global'
                Account          = 'user@contoso'
                GraphTokenExpiry = [DateTime]::UtcNow.AddHours(1)
                ArmToken         = [System.Net.NetworkCredential]::new('', 'ARM-TOKEN-FOR-A').SecurePassword
                ArmTokenExpiry   = [DateTime]::UtcNow.AddHours(1)
                ArmResourceUrl   = 'https://management.azure.com/'
                ClaimsSatisfied  = $false
            }

            Initialize-OERAuth -TenantId 'tenant-b' -AuthMethod 'Interactive' -IncludeARM

            $script:_OERAuthState.TenantId | Should -Be 'tenant-b'
            [System.Net.NetworkCredential]::new('', $script:_OERAuthState.ArmToken).Password |
                Should -Be 'token-for-https://management.azure.com/'
        }

        # The ARM resource must have been requested again for tenant B.
        Should -Invoke -ModuleName $script:moduleName Get-AzToken -Times 1 -ParameterFilter {
            $Resource -eq 'https://management.azure.com/'
        }
    }

    # The other half of the same finding: a tenant switch made WITHOUT -IncludeARM never runs the
    # ARM acquisition block at all, so only the carry-forward guard at the state rebuild can stop
    # tenant A's ARM token from riding along under tenant B's label.
    It 'DROPS a carried-forward ARM token when the tenant changes without -IncludeARM (SEC-arm-token-survives-tenant-switch)' {
        Mock -ModuleName $script:moduleName Get-AzToken {
            [pscustomobject]@{
                Token     = 'graph-token'
                Identity  = 'user@contoso'
                ExpiresOn = [DateTimeOffset]::UtcNow.AddHours(1)
            }
        }
        Mock -ModuleName $script:moduleName Connect-MgGraph { }

        InModuleScope $script:moduleName {
            $script:_OERAuthState = @{
                TenantId         = 'tenant-a'
                AuthMethod       = 'Interactive'
                ClientId         = ''
                Environment      = 'Global'
                Account          = 'user@contoso'
                GraphTokenExpiry = [DateTime]::UtcNow.AddHours(1)
                ArmToken         = [System.Net.NetworkCredential]::new('', 'ARM-TOKEN-FOR-A').SecurePassword
                ArmTokenExpiry   = [DateTime]::UtcNow.AddHours(1)
                ArmResourceUrl   = 'https://management.azure.com/'
                ClaimsSatisfied  = $false
            }

            # No -IncludeARM: the ARM branch never runs, so ONLY the carry-forward guard can help.
            Initialize-OERAuth -TenantId 'tenant-b' -AuthMethod 'Interactive'

            $script:_OERAuthState.TenantId       | Should -Be 'tenant-b'
            $script:_OERAuthState.ArmToken       | Should -BeNullOrEmpty
            $script:_OERAuthState.ArmTokenExpiry | Should -BeNullOrEmpty
            $script:_OERAuthState.ArmResourceUrl | Should -BeNullOrEmpty
        }
    }

    # SEC-arm-forcerefresh-does-not-refresh-arm: an ARM 401 is not necessarily an expiry (revocation,
    # CAE, key rotation), so -ForceRefresh must re-acquire the ARM token even for the SAME tenant and
    # identity, with a still-valid ArmTokenExpiry.
    It 'RE-ACQUIRES the ARM token under -ForceRefresh for the SAME tenant (SEC-arm-forcerefresh-does-not-refresh-arm)' {
        Mock -ModuleName $script:moduleName Get-AzToken {
            param($Resource)
            [pscustomobject]@{
                Token     = "fresh-for-$Resource"
                Identity  = 'user@contoso'
                ExpiresOn = [DateTimeOffset]::UtcNow.AddHours(1)
            }
        }
        Mock -ModuleName $script:moduleName Connect-MgGraph { }

        InModuleScope $script:moduleName {
            $script:_OERAuthState = @{
                TenantId         = 'tenant-a'
                AuthMethod       = 'Interactive'
                ClientId         = ''
                Environment      = 'Global'
                Account          = 'user@contoso'
                GraphTokenExpiry = [DateTime]::UtcNow.AddHours(1)
                ArmToken         = [System.Net.NetworkCredential]::new('', 'REVOKED-ARM-TOKEN').SecurePassword
                ArmTokenExpiry   = [DateTime]::UtcNow.AddHours(1)   # NOT expired -- a 401 is not an expiry
                ArmResourceUrl   = 'https://management.azure.com/'
                ClaimsSatisfied  = $false
            }

            Initialize-OERAuth -TenantId 'tenant-a' -AuthMethod 'Interactive' -IncludeARM -ForceRefresh

            [System.Net.NetworkCredential]::new('', $script:_OERAuthState.ArmToken).Password |
                Should -Be 'fresh-for-https://management.azure.com/'
        }

        Should -Invoke -ModuleName $script:moduleName Get-AzToken -Times 1 -ParameterFilter {
            $Resource -eq 'https://management.azure.com/'
        }
    }
}

Describe 'Initialize-OERAuth carries an ARM token over a renewal only for the renewed Graph token''s tenant (A13, BL-95)' {
    # BL-95: a sign-in that rebuilds the state -- a renewal of the Microsoft Graph token near its expiry,
    # or a transport's refresh -- carried the cached Azure Resource Manager token into the new state
    # whenever the tenant LABEL, method, client and cloud were unchanged. On a session that names no
    # tenant ('organizations') that label says nothing about the tenant: an interactive renewal answered
    # by another tenant's account rebuilt the state with that tenant's Graph token beside the first
    # tenant's ARM token, under one sign-in identity, and a later -Prune without -TenantId removed Azure
    # role assignments in the first tenant. The ARM token is now carried only when its recorded tenant
    # equals the renewed Graph token's tenant, both GUIDs; otherwise it is dropped, and acquired again --
    # in the same call under -IncludeARM -- and compared with the Graph token (F3).
    #
    # A mutation set: (a), (d), (e) and (f) fail with the old carry condition ($ArmIdentityUnchanged
    # alone); (a), (d) and (e) with the equality term deleted; (d) and (e) when the ARM step reads
    # $ArmCached alone; (b) and (c) when the token is never carried; and (f)'s last two cases with the
    # GUID term deleted, since two absent tenants, or two copies of one domain, compare equal.
    BeforeEach {
        InModuleScope $script:moduleName {
            $script:_OERAuthState = $null
            $script:_OERSessionUncertain = $null
            $script:_OERLastAuthorityHost = $null
            $script:_OERLastTokenRequest = $null
            $script:_OERInteractiveCredential = $null
        }
        $script:BL95GraphTenant = '11111111-1111-1111-1111-111111111111'
        $script:BL95ArmTenant = '11111111-1111-1111-1111-111111111111'
        # Every token names the tenant it was issued for, so the test can tell which one the state holds.
        Mock -ModuleName $script:moduleName Get-AzToken {
            param($ClientId, $ClientSecret, $Resource, $Tenant, $ErrorAction, $Interactive,
                  $DeviceCode, $ManagedIdentity, $ClientCertificate, $ClientCertificatePath,
                  $Scope, $Force, $Claim)
            $IsArm = $Resource -match 'management'
            $Granted = if ($IsArm) { $script:BL95ArmTenant } else { $script:BL95GraphTenant }
            [pscustomobject]@{
                Token     = '{0}-{1}' -f $(if ($IsArm) { 'NOT-A-REAL-TOKEN-arm' } else { 'NOT-A-REAL-TOKEN-graph' }), $Granted
                ExpiresOn = [DateTimeOffset]::UtcNow.AddHours(1)
                Identity  = 'admin@contoso.com'
                TenantId  = $Granted
            }
        }
        Mock -ModuleName $script:moduleName Connect-MgGraph { }
    }

    It '(a) drops the ARM token when a Microsoft Graph-only renewal of an organizations session is answered from another tenant' {
        InModuleScope $script:moduleName {
            Initialize-OERAuth -AuthMethod 'Interactive' -IncludeARM
            $script:_OERAuthState.ArmTokenTenantId | Should -BeExactly '11111111-1111-1111-1111-111111111111'
            # The Graph token nears its expiry; the ARM token stays valid for an hour.
            $script:_OERAuthState.GraphTokenExpiry = [DateTime]::UtcNow.AddMinutes(1)
        }
        # The renewal's prompt is answered by an account of another tenant.
        $script:BL95GraphTenant = '22222222-2222-2222-2222-222222222222'

        InModuleScope $script:moduleName {
            # A cmdlet that calls only Microsoft Graph, naming no tenant, renews the Graph token.
            Initialize-OERAuth

            $script:_OERAuthState.TenantId | Should -BeExactly 'organizations'
            $script:_OERAuthState.TokenTenantId | Should -BeExactly '22222222-2222-2222-2222-222222222222'
            $script:_OERAuthState.ArmToken | Should -BeNullOrEmpty
            $script:_OERAuthState.ArmTokenExpiry | Should -BeNullOrEmpty
            $script:_OERAuthState.ArmResourceUrl | Should -BeNullOrEmpty
            $script:_OERAuthState.ArmTokenTenantId | Should -BeNullOrEmpty
        }
        # The first sign-in's two tokens and the renewal's Graph token: the renewal requested no ARM token.
        Should -Invoke -ModuleName $script:moduleName Get-AzToken -Times 3 -Exactly
        Should -Invoke -ModuleName $script:moduleName Get-AzToken -Times 1 -Exactly -ParameterFilter {
            $Resource -match 'management'
        }
    }

    It '(b) carries the ARM token over a Microsoft Graph-only renewal answered from its own tenant, on <Case>' -ForEach @(
        @{ Case = 'an organizations session'; Tenant = $null }
        @{ Case = 'a session named by its tenant ID'; Tenant = '11111111-1111-1111-1111-111111111111' }
    ) {
        InModuleScope $script:moduleName -Parameters @{ Tenant = $Tenant } {
            param($Tenant)
            $Named = @{}
            if ($Tenant) { $Named.TenantId = $Tenant }
            Initialize-OERAuth @Named -AuthMethod 'Interactive' -IncludeARM
            $Before = $script:_OERAuthState.ArmToken
            $script:_OERAuthState.GraphTokenExpiry = [DateTime]::UtcNow.AddMinutes(1)

            Initialize-OERAuth @Named

            $script:_OERAuthState.TokenTenantId | Should -BeExactly '11111111-1111-1111-1111-111111111111'
            [object]::ReferenceEquals($script:_OERAuthState.ArmToken, $Before) | Should -BeTrue
            $script:_OERAuthState.ArmTokenExpiry | Should -Not -BeNullOrEmpty
            $script:_OERAuthState.ArmResourceUrl | Should -Not -BeNullOrEmpty
            $script:_OERAuthState.ArmTokenTenantId | Should -BeExactly '11111111-1111-1111-1111-111111111111'
        }
        Should -Invoke -ModuleName $script:moduleName Get-AzToken -Times 3 -Exactly
    }

    It '(c) keeps the carried ARM token without a new ARM request when a renewal under -IncludeARM is answered from its own tenant' {
        InModuleScope $script:moduleName {
            Initialize-OERAuth -AuthMethod 'Interactive' -IncludeARM
            $Before = $script:_OERAuthState.ArmToken
            $script:_OERAuthState.GraphTokenExpiry = [DateTime]::UtcNow.AddMinutes(1)

            Initialize-OERAuth -IncludeARM

            [object]::ReferenceEquals($script:_OERAuthState.ArmToken, $Before) | Should -BeTrue
        }
        # One ARM token in all: the renewal kept it, and requested only a Graph token.
        Should -Invoke -ModuleName $script:moduleName Get-AzToken -Times 3 -Exactly
        Should -Invoke -ModuleName $script:moduleName Get-AzToken -Times 1 -Exactly -ParameterFilter {
            $Resource -match 'management'
        }
    }

    It '(d) acquires a new ARM token when a renewal under -IncludeARM is answered from another tenant, and caches it when it matches the renewed Graph token' {
        InModuleScope $script:moduleName {
            Initialize-OERAuth -AuthMethod 'Interactive' -IncludeARM
            $script:_OERAuthState.GraphTokenExpiry = [DateTime]::UtcNow.AddMinutes(1)
        }
        $script:BL95GraphTenant = '22222222-2222-2222-2222-222222222222'
        $script:BL95ArmTenant = '22222222-2222-2222-2222-222222222222'

        InModuleScope $script:moduleName {
            # The cached ARM token is still valid, so before A13 this call requested no ARM token at all
            # and kept the first tenant's.
            Initialize-OERAuth -IncludeARM

            $script:_OERAuthState.TokenTenantId | Should -BeExactly '22222222-2222-2222-2222-222222222222'
            $script:_OERAuthState.ArmTokenTenantId | Should -BeExactly '22222222-2222-2222-2222-222222222222'
            [System.Net.NetworkCredential]::new('', $script:_OERAuthState.ArmToken).Password |
                Should -BeExactly 'NOT-A-REAL-TOKEN-arm-22222222-2222-2222-2222-222222222222'
        }
        Should -Invoke -ModuleName $script:moduleName Get-AzToken -Times 2 -Exactly -ParameterFilter {
            $Resource -match 'management'
        }
    }

    It '(e) refuses the new ARM token with TenantMismatch when it comes from another tenant than the renewed Graph token, caching none (F3)' {
        InModuleScope $script:moduleName {
            Initialize-OERAuth -AuthMethod 'Interactive' -IncludeARM
            $script:_OERAuthState.GraphTokenExpiry = [DateTime]::UtcNow.AddMinutes(1)
        }
        # The Graph prompt is answered from tenant 2, the ARM prompt again from tenant 1.
        $script:BL95GraphTenant = '22222222-2222-2222-2222-222222222222'

        InModuleScope $script:moduleName {
            $Caught = $null
            try {
                Initialize-OERAuth -IncludeARM
            } catch {
                $Caught = $PSItem
            }

            $Caught | Should -Not -BeNullOrEmpty -Because 'an ARM token from another tenant than the renewed Graph token must terminate rather than stay cached'
            $Caught.FullyQualifiedErrorId | Should -BeExactly 'TenantMismatch,Initialize-OERAuth'
            $Caught.Exception.Message | Should -Match ([regex]::Escape(
                "The Azure Resource Manager token was issued for tenant '11111111-1111-1111-1111-111111111111', but the Microsoft Graph token of the same session was issued for tenant '22222222-2222-2222-2222-222222222222'"))
            # Neither the carried token nor the refused one is left for Invoke-OERArmRequest to send.
            $script:_OERAuthState.ArmToken | Should -BeNullOrEmpty
            $script:_OERAuthState.ArmTokenTenantId | Should -BeNullOrEmpty
            $script:_OERAuthState.TokenTenantId | Should -BeExactly '22222222-2222-2222-2222-222222222222'
        }
        Should -Invoke -ModuleName $script:moduleName Get-AzToken -Times 2 -Exactly -ParameterFilter {
            $Resource -match 'management'
        }
    }

    It '(f) does not carry the ARM token over a renewal when <Case>' -ForEach @(
        @{ Case = 'the cached ARM token reports no GUID tenant'; FirstGraph = '11111111-1111-1111-1111-111111111111'; FirstArm = $null; RenewGraph = '11111111-1111-1111-1111-111111111111' }
        @{ Case = 'the renewed Graph token reports no GUID tenant'; FirstGraph = '11111111-1111-1111-1111-111111111111'; FirstArm = '11111111-1111-1111-1111-111111111111'; RenewGraph = $null }
        @{ Case = 'neither token reports a tenant, so the two compare equal'; FirstGraph = $null; FirstArm = $null; RenewGraph = $null }
        @{ Case = 'both tokens report the same tenant that is not a GUID'; FirstGraph = 'contoso.onmicrosoft.com'; FirstArm = 'contoso.onmicrosoft.com'; RenewGraph = 'contoso.onmicrosoft.com' }
    ) {
        # Nothing proves that such a token belongs with the renewed Graph token, so it is acquired again
        # when a call next needs one rather than carried. The last two cases are the GUID term's own: two
        # absent tenants, or two copies of the same domain (AzAuth's decompiled fallback echoes the
        # requested tenant when a token carries no tid claim), are equal, so only that term refuses to
        # carry the token.
        $script:BL95GraphTenant = $FirstGraph
        $script:BL95ArmTenant = $FirstArm
        InModuleScope $script:moduleName {
            Initialize-OERAuth -AuthMethod 'Interactive' -IncludeARM
            $script:_OERAuthState.ArmToken | Should -Not -BeNullOrEmpty
            $script:_OERAuthState.GraphTokenExpiry = [DateTime]::UtcNow.AddMinutes(1)
        }
        $script:BL95GraphTenant = $RenewGraph

        InModuleScope $script:moduleName {
            Initialize-OERAuth

            $script:_OERAuthState.ArmToken | Should -BeNullOrEmpty
            $script:_OERAuthState.ArmTokenTenantId | Should -BeNullOrEmpty
        }
        Should -Invoke -ModuleName $script:moduleName Get-AzToken -Times 3 -Exactly
    }
}

Describe 'Initialize-OERAuth error hygiene' {
    BeforeEach {
        # $script:_OERLastAuthorityHost is deliberately NOT cleared by Disconnect-OER, so nothing in
        # the module ever resets it. Reset it here, or a sovereign test leaks its authority into the
        # next test, which would then silently gain the -Force the public path must never carry.
        InModuleScope $script:moduleName {
            $script:_OERAuthState = $null
            $script:_OERSessionUncertain = $null
            $script:_OERLastAuthorityHost = $null
            $script:_OERLastTokenRequest = $null
            $script:_OERInteractiveCredential = $null
        }
        # BL-12: a tenant named by anything but a GUID or 'organizations' is looked up before any token
        # is requested. The tokens in this Describe carry no GUID tenant, so the mocked lookup answers
        # with any tenant ID.
        Mock -ModuleName $script:moduleName Resolve-OERTenantDomain { '11111111-1111-1111-1111-111111111111' }
    }

    # Initialize-OERAuth re-throws via Write-CmdletError -Terminating, NOT a converted exception,
    # so the $global:Error + ReferenceEquals proof is inert here (PR #34 measured this). Guard the
    # scrub call directly.
    It 'scrubs the error record when the Graph token acquisition fails' {
        InModuleScope $script:moduleName {
            Mock Get-AzToken { throw [System.Exception]::new('AADSTS50076: interaction required') }
            Mock Remove-OERErrorRecord { }

            { Initialize-OERAuth -TenantId 'contoso' -AuthMethod Interactive } |
                Should -Throw -ErrorId 'GraphTokenAcquisitionFailed,Initialize-OERAuth'

            Should -Invoke Remove-OERErrorRecord -Times 1
        }
    }

    It 'scrubs the error record when Connect-MgGraph fails' {
        InModuleScope $script:moduleName {
            Mock Get-AzToken {
                [PSCustomObject]@{
                    Token     = 'graph-token'
                    Identity  = 'user@contoso'
                    ExpiresOn = [DateTimeOffset]::UtcNow.AddHours(1)
                }
            }
            Mock Connect-MgGraph { throw [System.Exception]::new('handshake failed') }
            Mock Remove-OERErrorRecord { }

            { Initialize-OERAuth -TenantId 'contoso' -AuthMethod Interactive } |
                Should -Throw -ErrorId 'GraphConnectFailed,Initialize-OERAuth'

            Should -Invoke Remove-OERErrorRecord -Times 1
        }
    }

    It 'scrubs the error record when the ARM token acquisition fails' {
        InModuleScope $script:moduleName {
            Mock Connect-MgGraph { }
            Mock Get-AzToken {
                param($Resource)
                if ($Resource -eq 'https://management.azure.com/') {
                    throw [System.Exception]::new('ARM consent required')
                }
                [PSCustomObject]@{
                    Token     = 'graph-token'
                    Identity  = 'user@contoso'
                    ExpiresOn = [DateTimeOffset]::UtcNow.AddHours(1)
                }
            }
            Mock Remove-OERErrorRecord { }

            # The ARM failure is NON-terminating (Write-CmdletError without -Terminating + return).
            $Err = $null
            Initialize-OERAuth -TenantId 'contoso' -AuthMethod Interactive -IncludeARM -ErrorVariable Err -ErrorAction SilentlyContinue

            @($Err | Where-Object { $_.FullyQualifiedErrorId -eq 'ArmTokenAcquisitionFailed,Initialize-OERAuth' }).Count |
                Should -Be 1
            Should -Invoke Remove-OERErrorRecord -Times 1
        }
    }

    It 'materializes the client secret into the Get-AzToken splat and surfaces the terminating error' {
        InModuleScope $script:moduleName {
            # The function's own finally block nulls its LOCAL $TokenParams/$GraphParams/$ArmParams
            # references on every exit path, including this terminating one. That effect is on
            # function-local hashtables and is not observable from outside the function -- there is
            # no reference this test can capture that would show whether the finally ran or not.
            # $script:CapturedSplat below is a DIFFERENT object: it is the mock's own
            # $PSBoundParameters, captured before the throw. What this test actually proves is (a)
            # the secret plaintext reaches the Get-AzToken call boundary, so the test is not vacuous,
            # and (b) the terminating path (Get-AzToken throwing) is exercised end to end. The
            # finally's cleanup of the function-local hashtables is verified by inspection of
            # source/Private/Initialize-OERAuth.ps1, not by this test.
            $script:CapturedSplat = $null
            Mock Get-AzToken {
                param($ClientSecret)
                $script:CapturedSplat = $PSBoundParameters
                throw [System.Exception]::new('AADSTS7000215: invalid client secret')
            }
            Mock Remove-OERErrorRecord { }

            $Secret = ConvertTo-SecureString 'super-secret-value' -AsPlainText -Force
            { Initialize-OERAuth -TenantId 'contoso' -AuthMethod ClientSecret -ClientId 'app-id' -ClientSecret $Secret } |
                Should -Throw -ErrorId 'GraphTokenAcquisitionFailed,Initialize-OERAuth'

            # The secret DID reach Get-AzToken (so the test is not vacuous) ...
            $script:CapturedSplat.ClientSecret | Should -Be 'super-secret-value'
        }
    }
}

Describe 'Initialize-OERAuth session inheritance' {
    BeforeEach {
        # $script:_OERLastAuthorityHost is deliberately NOT cleared by Disconnect-OER, so nothing in
        # the module ever resets it. Reset it here, or a sovereign test leaks its authority into the
        # next test, which would then silently gain the -Force the public path must never carry.
        InModuleScope $script:moduleName {
            $script:_OERAuthState = $null
            $script:_OERSessionUncertain = $null
            $script:_OERLastAuthorityHost = $null
            $script:_OERLastTokenRequest = $null
            $script:_OERInteractiveCredential = $null
        }
        # BL-12: a tenant named by anything but a GUID or 'organizations' is looked up before any token
        # is requested. The tokens in this Describe carry no GUID tenant, so the mocked lookup answers
        # with any tenant ID.
        Mock -ModuleName $script:moduleName Resolve-OERTenantDomain { '11111111-1111-1111-1111-111111111111' }
    }

    # SEC-auth-tenant-defaults-to-organizations: when the caller omits -TenantId, $EffectiveTenant
    # fell back to 'organizations' even though a live session named a real tenant. Get-AzToken was
    # then called with no -Tenant and the rebuilt state was stamped 'organizations', so
    # $script:_OERAuthState.TenantId no longer described the token beneath it. This reproduces on an
    # Interactive session, where the derived AuthMethod is 'Interactive' with or without the
    # AuthMethod fix -- it is a defect in its own right, not a symptom of that one.
    It 'RE-ACQUIRES against the SESSION tenant when -TenantId is omitted (SEC-auth-tenant-defaults-to-organizations)' {
        Mock -ModuleName $script:moduleName Get-AzToken {
            [pscustomobject]@{ Token = 'fake'; ExpiresOn = [DateTimeOffset]::UtcNow.AddHours(1); Identity = 'user@contoso' }
        }
        Mock -ModuleName $script:moduleName Connect-MgGraph { }

        InModuleScope $script:moduleName {
            # A live Interactive session for tenant A whose Graph token has passed the 5-minute floor.
            $script:_OERAuthState = @{
                TenantId         = 'tenant-a'
                AuthMethod       = 'Interactive'
                ClientId         = ''
                Environment      = 'Global'
                Account          = 'user@contoso'
                GraphTokenExpiry = [DateTime]::UtcNow.AddMinutes(-1)
                ArmToken         = $null
                ArmTokenExpiry   = $null
                ArmResourceUrl   = $null
                ClaimsSatisfied  = $false
            }

            # A Graph cmdlet ensuring connectivity: no -TenantId, no -AuthMethod.
            Initialize-OERAuth

            $script:_OERAuthState.TenantId | Should -Be 'tenant-a'
        }

        Should -Invoke -ModuleName $script:moduleName Get-AzToken -Exactly -Times 1 -ParameterFilter {
            $Tenant -eq 'tenant-a'
        }
    }

    # SEC-auth-default-authmethod-forces-interactive: -AuthMethod declared '= Interactive', so both
    # cache predicates compared the cached method against that DEFAULT whenever the caller omitted
    # the parameter. All 22 ARM cmdlets call Initialize-OERAuth -IncludeARM without -AuthMethod, so
    # a managed-identity session was pushed into an interactive browser sign-in -- fatal in the
    # unattended pipeline run that is the whole point of managed identity.
    It 'acquires ARM as the SESSION identity, not Interactive (SEC-auth-default-authmethod-forces-interactive)' {
        Mock -ModuleName $script:moduleName Get-AzToken {
            param($ClientId, $ClientSecret, $Resource, $Tenant, $ErrorAction, $Interactive,
                  $DeviceCode, $ManagedIdentity, $ClientCertificate, $ClientCertificatePath,
                  $Scope, $Force, $Claim)
            $script:CapturedArmKeys = $PSBoundParameters.Keys
            [pscustomobject]@{ Token = "token-for-$Resource"; ExpiresOn = [DateTimeOffset]::UtcNow.AddHours(1); Identity = 'umi' }
        }
        Mock -ModuleName $script:moduleName Connect-MgGraph { }

        InModuleScope $script:moduleName {
            # A user-assigned managed-identity session for tenant A: Graph token valid, no ARM token.
            $script:_OERAuthState = @{
                TenantId         = 'tenant-a'
                AuthMethod       = 'ManagedIdentity'
                ClientId         = 'umi-client-id'
                Environment      = 'Global'
                Account          = 'umi'
                GraphTokenExpiry = [DateTime]::UtcNow.AddHours(1)
                ArmToken         = $null
                ArmTokenExpiry   = $null
                ArmResourceUrl   = $null
                ClaimsSatisfied  = $false
            }

            # Exactly what all 22 ARM cmdlets do: no -TenantId, no -AuthMethod.
            Initialize-OERAuth -IncludeARM

            $script:_OERAuthState.AuthMethod | Should -Be 'ManagedIdentity'
            $script:_OERAuthState.TenantId   | Should -Be 'tenant-a'
            $script:_OERAuthState.ArmToken   | Should -BeOfType [System.Security.SecureString]
        }

        # Only the ARM resource is acquired -- the cached Graph token is still valid.
        Should -Invoke -ModuleName $script:moduleName Get-AzToken -Exactly -Times 1
        Should -Invoke -ModuleName $script:moduleName Get-AzToken -Exactly -Times 1 -ParameterFilter {
            $ManagedIdentity -and $ClientId -eq 'umi-client-id' -and $Tenant -eq 'tenant-a' -and
            $Resource -eq 'https://management.azure.com/'
        }
        $script:CapturedArmKeys | Should -Not -BeNullOrEmpty
        $script:CapturedArmKeys | Should -Not -Contain 'Interactive'
    }

    # The other direction of the same rule: an EXPLICIT -AuthMethod must still beat the session, or
    # an operator can no longer deliberately step up to an interactive sign-in from an app-only one.
    It 'lets an EXPLICIT -AuthMethod override the cached app-only session' {
        Mock -ModuleName $script:moduleName Get-AzToken {
            param($ClientId, $ClientSecret, $Resource, $Tenant, $ErrorAction, $Interactive,
                  $DeviceCode, $ManagedIdentity, $ClientCertificate, $ClientCertificatePath,
                  $Scope, $Force, $Claim)
            $script:CapturedOverrideKeys = $PSBoundParameters.Keys
            [pscustomobject]@{ Token = 'fake'; ExpiresOn = [DateTimeOffset]::UtcNow.AddHours(1); Identity = 'user@contoso' }
        }
        Mock -ModuleName $script:moduleName Connect-MgGraph { }

        InModuleScope $script:moduleName {
            $script:_OERAuthState = @{
                TenantId         = 'tenant-a'
                AuthMethod       = 'ClientSecret'
                ClientId         = 'app-c'
                Environment      = 'Global'
                Account          = 'sp'
                GraphTokenExpiry = [DateTime]::UtcNow.AddHours(1)
                ArmToken         = $null
                ArmTokenExpiry   = $null
                ArmResourceUrl   = $null
                ClaimsSatisfied  = $false
            }

            Initialize-OERAuth -AuthMethod 'Interactive'

            $script:_OERAuthState.AuthMethod | Should -Be 'Interactive'
        }

        $script:CapturedOverrideKeys | Should -Contain 'Interactive'
        Should -Invoke -ModuleName $script:moduleName Get-AzToken -Exactly -Times 1
    }

    # An inherited app-only identity CANNOT mint a token: the client-credentials flow issues no
    # refresh token, a token is minted for exactly one resource, and the module deliberately never
    # stores the secret or certificate to replay it. So the fix cannot make this case succeed -- it
    # makes it fail loudly instead of opening a browser as a different principal. Same policy as
    # Invoke-OERGraphRequest's AppOnlyClaimsChallengeUnsatisfiable and Invoke-OERArmRequest's
    # AppOnlyTokenRefreshUnsatisfiable.
    It 'refuses to prompt for an inherited app-only session and leaves the state intact (SEC-auth-default-authmethod-forces-interactive)' {
        Mock -ModuleName $script:moduleName Get-AzToken {
            [pscustomobject]@{ Token = 'fake'; ExpiresOn = [DateTimeOffset]::UtcNow.AddHours(1); Identity = 'user@contoso' }
        }
        Mock -ModuleName $script:moduleName Connect-MgGraph { }

        InModuleScope $script:moduleName {
            # Connect-OER -TenantId A -ClientId C -ClientSecret S, WITHOUT -IncludeARM.
            $script:_OERAuthState = @{
                TenantId         = 'tenant-a'
                AuthMethod       = 'ClientSecret'
                ClientId         = 'app-c'
                Environment      = 'Global'
                Account          = 'sp'
                GraphTokenExpiry = [DateTime]::UtcNow.AddHours(1)
                ArmToken         = $null
                ArmTokenExpiry   = $null
                ArmResourceUrl   = $null
                ClaimsSatisfied  = $false
            }

            $Caught = $null
            try { Initialize-OERAuth -IncludeARM } catch { $Caught = $PSItem }

            $Caught | Should -Not -BeNullOrEmpty
            $Caught.FullyQualifiedErrorId | Should -Be 'AppOnlySessionCredentialUnavailable,Initialize-OERAuth'

            # The state must survive untouched: no 'organizations' stamp, no Interactive stamp.
            $script:_OERAuthState.TenantId   | Should -Be 'tenant-a'
            $script:_OERAuthState.AuthMethod | Should -Be 'ClientSecret'
            $script:_OERAuthState.ClientId   | Should -Be 'app-c'
        }

        # No browser. This is the half that matters in an unattended pipeline run.
        Should -Invoke -ModuleName $script:moduleName Get-AzToken -Exactly -Times 0
    }

    # The guard is gated on INHERITANCE. An explicit -AuthMethod ClientSecret with no secret is a
    # caller mistake and must keep its own, more specific error.
    It 'still raises MissingClientSecret for an EXPLICIT -AuthMethod ClientSecret with no secret' {
        Mock -ModuleName $script:moduleName Get-AzToken { throw 'Get-AzToken must not be reached' }
        Mock -ModuleName $script:moduleName Connect-MgGraph { }

        InModuleScope $script:moduleName {
            $script:_OERAuthState = @{
                TenantId         = 'tenant-a'
                AuthMethod       = 'ClientSecret'
                ClientId         = 'app-c'
                Environment      = 'Global'
                Account          = 'sp'
                GraphTokenExpiry = [DateTime]::UtcNow.AddHours(1)
                ArmToken         = $null
                ArmTokenExpiry   = $null
                ArmResourceUrl   = $null
                ClaimsSatisfied  = $false
            }

            $Caught = $null
            try {
                Initialize-OERAuth -AuthMethod 'ClientSecret' -ClientId 'app-c' -IncludeARM
            } catch { $Caught = $PSItem }

            $Caught.FullyQualifiedErrorId | Should -Be 'MissingClientSecret,Initialize-OERAuth'
        }
    }

    # $PassiveReuse ignored -ClientId entirely, so a caller naming the SAME client id as the session
    # used to reuse it. $InheritIdentity must keep that case working -- naming the client id you are
    # already signed in as is not an identity change.
    It 'still reuses the session when -ClientId names the SAME application and -AuthMethod is omitted' {
        Mock -ModuleName $script:moduleName Get-AzToken {
            [pscustomobject]@{ Token = 'fake'; ExpiresOn = [DateTimeOffset]::UtcNow.AddHours(1); Identity = 'sp' }
        }
        Mock -ModuleName $script:moduleName Connect-MgGraph { }

        InModuleScope $script:moduleName {
            $script:_OERAuthState = @{
                TenantId         = 'tenant-a'
                AuthMethod       = 'ClientSecret'
                ClientId         = 'app-c'
                Environment      = 'Global'
                Account          = 'sp'
                GraphTokenExpiry = [DateTime]::UtcNow.AddHours(1)
                ArmToken         = $null
                ArmTokenExpiry   = $null
                ArmResourceUrl   = $null
                ClaimsSatisfied  = $false
            }

            Initialize-OERAuth -ClientId 'app-c'

            $script:_OERAuthState.AuthMethod | Should -Be 'ClientSecret'
        }

        Should -Invoke -ModuleName $script:moduleName Get-AzToken -Exactly -Times 0
    }

    # The other half: a DIFFERENT client id is a different application and must NOT inherit.
    It 'does NOT inherit the session credential when -ClientId names a DIFFERENT application' {
        Mock -ModuleName $script:moduleName Get-AzToken {
            param($ClientId, $ClientSecret, $Resource, $Tenant, $ErrorAction, $Interactive,
                  $DeviceCode, $ManagedIdentity, $ClientCertificate, $ClientCertificatePath,
                  $Scope, $Force, $Claim)
            $script:CapturedOtherAppKeys = $PSBoundParameters.Keys
            [pscustomobject]@{ Token = 'fake'; ExpiresOn = [DateTimeOffset]::UtcNow.AddHours(1); Identity = 'user@contoso' }
        }
        Mock -ModuleName $script:moduleName Connect-MgGraph { }

        InModuleScope $script:moduleName {
            $script:_OERAuthState = @{
                TenantId         = 'tenant-a'
                AuthMethod       = 'ClientSecret'
                ClientId         = 'app-c'
                Environment      = 'Global'
                Account          = 'sp'
                GraphTokenExpiry = [DateTime]::UtcNow.AddHours(1)
                ArmToken         = $null
                ArmTokenExpiry   = $null
                ArmResourceUrl   = $null
                ClaimsSatisfied  = $false
            }

            Initialize-OERAuth -ClientId 'other-app'

            $script:_OERAuthState.AuthMethod | Should -Be 'Interactive'
            $script:_OERAuthState.ClientId   | Should -Be 'other-app'
        }

        $script:CapturedOtherAppKeys | Should -Contain 'Interactive'
        Should -Invoke -ModuleName $script:moduleName Get-AzToken -Exactly -Times 1
    }

    # BL-90: the tenant term of $SessionUsable is Test-OERSessionUsable's, and -TenantId binds the tenant,
    # not the identity: a sign-in naming the session's own tenant takes the session's identity (here the
    # cached return, no token request), one naming ANOTHER tenant takes none of it and signs in itself.
    It 'inherits the session identity when -TenantId names the session''s own tenant and -AuthMethod is omitted (BL-90)' {
        Mock -ModuleName $script:moduleName Get-AzToken {
            [pscustomobject]@{ Token = 'fake'; ExpiresOn = [DateTimeOffset]::UtcNow.AddHours(1); Identity = 'sp' }
        }
        Mock -ModuleName $script:moduleName Connect-MgGraph { }

        InModuleScope $script:moduleName {
            $script:_OERAuthState = @{
                TenantId         = 'tenant-a'
                AuthMethod       = 'ClientSecret'
                ClientId         = 'app-c'
                Environment      = 'Global'
                Account          = 'sp'
                GraphTokenExpiry = [DateTime]::UtcNow.AddHours(1)
                ArmToken         = $null
                ArmTokenExpiry   = $null
                ArmResourceUrl   = $null
                ClaimsSatisfied  = $false
            }

            Initialize-OERAuth -TenantId 'tenant-a'

            $script:_OERAuthState.AuthMethod | Should -Be 'ClientSecret'
            $script:_OERAuthState.ClientId   | Should -Be 'app-c'
        }

        Should -Invoke -ModuleName $script:moduleName Get-AzToken -Exactly -Times 0
    }

    It 'does NOT inherit the session identity when -TenantId names ANOTHER tenant and -AuthMethod is omitted (BL-90)' {
        Mock -ModuleName $script:moduleName Get-AzToken {
            param($ClientId, $ClientSecret, $Resource, $Tenant, $ErrorAction, $Interactive,
                  $DeviceCode, $ManagedIdentity, $ClientCertificate, $ClientCertificatePath,
                  $Scope, $Force, $Claim)
            $script:CapturedOtherTenantKeys = $PSBoundParameters.Keys
            [pscustomobject]@{ Token = 'fake'; ExpiresOn = [DateTimeOffset]::UtcNow.AddHours(1); Identity = 'user@contoso' }
        }
        Mock -ModuleName $script:moduleName Connect-MgGraph { }

        InModuleScope $script:moduleName {
            $script:_OERAuthState = @{
                TenantId         = 'tenant-a'
                AuthMethod       = 'ClientSecret'
                ClientId         = 'app-c'
                Environment      = 'Global'
                Account          = 'sp'
                GraphTokenExpiry = [DateTime]::UtcNow.AddHours(1)
                ArmToken         = $null
                ArmTokenExpiry   = $null
                ArmResourceUrl   = $null
                ClaimsSatisfied  = $false
            }

            Initialize-OERAuth -TenantId 'tenant-b'

            $script:_OERAuthState.AuthMethod | Should -Be 'Interactive'
            $script:_OERAuthState.TenantId   | Should -Be 'tenant-b'
        }

        $script:CapturedOtherTenantKeys | Should -Contain 'Interactive'
        $script:CapturedOtherTenantKeys | Should -Not -Contain 'ClientSecret'
        Should -Invoke -ModuleName $script:moduleName Get-AzToken -Exactly -Times 1 -ParameterFilter { $Tenant -eq 'tenant-b' }
    }
}

# -------------------------------------------------------------------------------------------------
# Sovereign clouds (Sprint 1.5, issue #81).
#
# Every expected value in this block is read from Get-OERCloudEndpoint rather than written out as a
# literal. The literals themselves are pinned once, in Get-OERCloudEndpoint.Tests.ps1; repeating them
# here would only prove that two copies of a table agree with each other.
# -------------------------------------------------------------------------------------------------
Describe 'Initialize-OERAuth sovereign clouds' {
    BeforeAll {
        # AZURE_AUTHORITY_HOST is PROCESS state shared with everything else running in this pwsh,
        # including the operator's own Azure tooling. Borrow it for the suite and hand it back.
        $script:AmbientAuthorityHost = [System.Environment]::GetEnvironmentVariable('AZURE_AUTHORITY_HOST')
    }

    AfterAll {
        # [NullString]::Value, not $null: PowerShell coerces $null to '' when binding a .NET string
        # parameter, and an EMPTY AZURE_AUTHORITY_HOST is a different state from an absent one.
        if ($null -eq $script:AmbientAuthorityHost) {
            [System.Environment]::SetEnvironmentVariable('AZURE_AUTHORITY_HOST', [NullString]::Value)
        }
        else {
            [System.Environment]::SetEnvironmentVariable('AZURE_AUTHORITY_HOST', $script:AmbientAuthorityHost)
        }
    }

    BeforeEach {
        [System.Environment]::SetEnvironmentVariable('AZURE_AUTHORITY_HOST', [NullString]::Value)
        # $script:_OERLastAuthorityHost is deliberately NOT cleared by Disconnect-OER, so nothing in
        # the module ever resets it. Reset it here, or a sovereign test leaks its authority into the
        # next test, which would then silently gain the -Force the public path must never carry.
        InModuleScope $script:moduleName {
            $script:_OERAuthState = $null
            $script:_OERSessionUncertain = $null
            $script:_OERLastAuthorityHost = $null
            $script:_OERLastTokenRequest = $null
            $script:_OERInteractiveCredential = $null
        }
        # BL-12: a tenant named by anything but a GUID or 'organizations' is looked up before any token
        # is requested. The tokens in this Describe carry no GUID tenant, so the mocked lookup answers
        # with any tenant ID.
        Mock -ModuleName $script:moduleName Resolve-OERTenantDomain { '11111111-1111-1111-1111-111111111111' }
    }

    # The whole point of the sprint: a session that names no cloud must behave exactly as it did
    # before -Environment existed. Every term below is a way the new code could have leaked into the
    # public path, asserted directly rather than reasoned about.
    It 'leaves the public path unchanged: no -Force, no -Environment, no AZURE_AUTHORITY_HOST write' {
        # A sentinel value that is not a real authority. Asserting only that the mock saw $null would
        # also pass if the mock never ran, and would not distinguish "we did not write" from "we
        # wrote and then something cleared it"; observing the sentinel unchanged proves no write.
        [System.Environment]::SetEnvironmentVariable('AZURE_AUTHORITY_HOST', 'https://sentinel.invalid/')

        Mock -ModuleName $script:moduleName Get-AzToken {
            param($ClientId, $ClientSecret, $Resource, $Tenant, $ErrorAction, $Interactive,
                  $DeviceCode, $ManagedIdentity, $ClientCertificate, $ClientCertificatePath,
                  $Scope, $Force, $Claim)
            $script:PublicPathTokenKeys = @($PSBoundParameters.Keys)
            $script:PublicPathAuthority = [System.Environment]::GetEnvironmentVariable('AZURE_AUTHORITY_HOST')
            [pscustomobject]@{ Token = "token-for-$Resource"; ExpiresOn = [DateTimeOffset]::UtcNow.AddHours(1); Identity = 'a@b.c' }
        }
        Mock -ModuleName $script:moduleName Connect-MgGraph {
            param($AccessToken, $NoWelcome, $ErrorAction, $Environment)
            $script:PublicPathConnectKeys        = @($PSBoundParameters.Keys)
            $script:PublicPathConnectEnvironment = $Environment
        }

        # The sentinel is not the commercial authority, so this Global sign-in warns about it, by design
        # ('warns when AZURE_AUTHORITY_HOST is set to a non-commercial authority on a Global sign-in').
        # Captured and pinned here, so it is asserted rather than printed into the test output.
        $PublicPathWarnings = @(InModuleScope $script:moduleName {
                Initialize-OERAuth -TenantId 'contoso' -AuthMethod 'Interactive' -IncludeARM `
                    -WarningVariable Captured -WarningAction SilentlyContinue
                $script:_OERAuthState.Environment    | Should -Be 'Global'
                $script:_OERAuthState.ArmResourceUrl | Should -Be 'https://management.azure.com/'
                $Captured | ForEach-Object { [string]$_.Message }
            })
        $PublicPathWarnings.Count | Should -Be 1 -Because 'the Global sign-in writes exactly one warning, the one about the sentinel authority'
        $PublicPathWarnings[0] | Should -BeExactly (
            "AZURE_AUTHORITY_HOST is set to 'https://sentinel.invalid/' in this process, which is not the " +
            "commercial-cloud authority 'https://login.microsoftonline.com/'. Microsoft Entra ID sign-in " +
            "follows that variable, so this 'Global' sign-in will be sent to that authority instead. " +
            'Omnicit.EntraRBAC does not change the variable on the Global cloud. If this is not what you ' +
            'intended, clear it with Remove-Item Env:AZURE_AUTHORITY_HOST and sign in again; if you meant ' +
            'to target a sovereign cloud, use Connect-OER -Environment instead.')

        Should -Invoke -ModuleName $script:moduleName Get-AzToken -Exactly -Times 1 -ParameterFilter {
            $Resource -eq 'https://graph.microsoft.com/'
        }
        Should -Invoke -ModuleName $script:moduleName Get-AzToken -Exactly -Times 1 -ParameterFilter {
            $Resource -eq 'https://management.azure.com/'
        }

        $script:PublicPathTokenKeys | Should -Not -BeNullOrEmpty -Because 'the mock must have run, or every assertion below is vacuous'
        $script:PublicPathTokenKeys | Should -Not -Contain 'Force'
        $script:PublicPathConnectKeys | Should -Not -BeNullOrEmpty
        $script:PublicPathConnectKeys | Should -Not -Contain 'Environment'
        $script:PublicPathConnectEnvironment | Should -BeNullOrEmpty
        $script:PublicPathAuthority | Should -Be 'https://sentinel.invalid/'
        [System.Environment]::GetEnvironmentVariable('AZURE_AUTHORITY_HOST') | Should -Be 'https://sentinel.invalid/'
    }

    # The other half of the same invariant: on a machine where the variable does not exist at all,
    # the public path must not bring it into existence.
    It 'does not create AZURE_AUTHORITY_HOST at all on the public path' {
        Mock -ModuleName $script:moduleName Get-AzToken {
            param($ClientId, $ClientSecret, $Resource, $Tenant, $ErrorAction, $Interactive,
                  $DeviceCode, $ManagedIdentity, $ClientCertificate, $ClientCertificatePath,
                  $Scope, $Force, $Claim)
            $script:PublicUnsetAuthorityRan = $true
            $script:PublicUnsetAuthority    = [System.Environment]::GetEnvironmentVariable('AZURE_AUTHORITY_HOST')
            [pscustomobject]@{ Token = 'fake'; ExpiresOn = [DateTimeOffset]::UtcNow.AddHours(1); Identity = 'a@b.c' }
        }
        Mock -ModuleName $script:moduleName Connect-MgGraph { }

        InModuleScope $script:moduleName {
            Initialize-OERAuth -TenantId 'contoso' -AuthMethod 'Interactive'
        }

        $script:PublicUnsetAuthorityRan | Should -BeTrue -Because 'a null capture proves nothing unless the capture actually ran'
        $script:PublicUnsetAuthority    | Should -BeNullOrEmpty
        Test-Path -Path 'Env:AZURE_AUTHORITY_HOST' | Should -BeFalse
    }

    It 'reads Graph, ARM, Connect-MgGraph and the authority host from the <Cloud> endpoint row' -ForEach @(
        @{ Cloud = 'USGov' }
        @{ Cloud = 'USGovDoD' }
        @{ Cloud = 'China' }
    ) {
        $Expected = InModuleScope $script:moduleName -Parameters @{ Cloud = $Cloud } {
            Get-OERCloudEndpoint -Environment $Cloud
        }
        # Guards the assertions below against being trivially satisfied by the public-cloud values.
        $Expected.AuthorityHost | Should -Not -Be 'https://login.microsoftonline.com/'
        $Expected.GraphResource | Should -Not -Be 'https://graph.microsoft.com/'

        Mock -ModuleName $script:moduleName Get-AzToken {
            param($ClientId, $ClientSecret, $Resource, $Tenant, $ErrorAction, $Interactive,
                  $DeviceCode, $ManagedIdentity, $ClientCertificate, $ClientCertificatePath,
                  $Scope, $Force, $Claim)
            # The delegated Graph call is the one that carries -Scope; the ARM call never does. That
            # separates the two captures without an array append, whose read-back across the mock
            # boundary is not something this suite should be relying on.
            if ($PSBoundParameters.ContainsKey('Scope')) {
                $script:SovereignGraphResource  = $Resource
                $script:SovereignGraphAuthority = [System.Environment]::GetEnvironmentVariable('AZURE_AUTHORITY_HOST')
                $script:SovereignGraphKeys      = @($PSBoundParameters.Keys)
            }
            else {
                $script:SovereignArmResource  = $Resource
                $script:SovereignArmAuthority = [System.Environment]::GetEnvironmentVariable('AZURE_AUTHORITY_HOST')
            }
            [pscustomobject]@{ Token = "token-for-$Resource"; ExpiresOn = [DateTimeOffset]::UtcNow.AddHours(1); Identity = 'a@b.c' }
        }
        Mock -ModuleName $script:moduleName Connect-MgGraph {
            param($AccessToken, $NoWelcome, $ErrorAction, $Environment)
            $script:SovereignConnectEnvironment = $Environment
        }

        InModuleScope $script:moduleName -Parameters @{ Cloud = $Cloud } {
            Initialize-OERAuth -TenantId 'contoso' -AuthMethod 'Interactive' -Environment $Cloud -IncludeARM
        }

        $State = InModuleScope $script:moduleName { $script:_OERAuthState }
        $State.Environment    | Should -Be $Cloud
        $State.ArmResourceUrl | Should -Be $Expected.ArmResource

        $script:SovereignGraphResource      | Should -Be $Expected.GraphResource
        $script:SovereignArmResource        | Should -Be $Expected.ArmResource
        $script:SovereignConnectEnvironment | Should -Be $Expected.GraphEnvironment

        # Observed DURING the call, since Azure.Identity bakes the authority into the credential at
        # construction time -- a value written after Get-AzToken returned would prove nothing.
        $script:SovereignGraphAuthority | Should -Be $Expected.AuthorityHost
        $script:SovereignArmAuthority   | Should -Be $Expected.AuthorityHost

        # AzAuth reuses a credential keyed on type and client id only, so moving the authority needs
        # -Force to drop the cached one.
        $script:SovereignGraphKeys | Should -Contain 'Force'

        # Borrowed, not taken: the process must be handed back exactly as it was found.
        Test-Path -Path 'Env:AZURE_AUTHORITY_HOST' | Should -BeFalse
    }

    # SEC-token-survives-cloud-switch: a token is minted by ONE cloud's authority for ONE cloud's
    # resource. Reusing a Global token for a USGov request is the same defect class as the audit's
    # only Critical (an ARM token surviving a tenant switch), so the Environment term on $GraphCached
    # is load-bearing. Delete it and this test goes green with one acquisition instead of two.
    It 'does NOT reuse a Global token for the SAME tenant and identity in USGov (SEC-token-survives-cloud-switch)' {
        Mock -ModuleName $script:moduleName Get-AzToken {
            param($Resource)
            [pscustomobject]@{ Token = "token-for-$Resource"; ExpiresOn = [DateTimeOffset]::UtcNow.AddHours(1); Identity = 'a@b.c' }
        }
        Mock -ModuleName $script:moduleName Connect-MgGraph { }

        InModuleScope $script:moduleName {
            Initialize-OERAuth -TenantId 'contoso' -AuthMethod 'Interactive'
            $script:_OERAuthState.Environment | Should -Be 'Global'

            # Same tenant, same identity, still-valid Graph token -- only the cloud differs.
            Initialize-OERAuth -TenantId 'contoso' -AuthMethod 'Interactive' -Environment 'USGov'
            $script:_OERAuthState.Environment | Should -Be 'USGov'
        }

        Should -Invoke -ModuleName $script:moduleName Get-AzToken -Exactly -Times 2
        Should -Invoke -ModuleName $script:moduleName Get-AzToken -Exactly -Times 1 -ParameterFilter {
            $Resource -eq 'https://graph.microsoft.us/'
        }
    }

    # The ARM half of the same rule, via $ArmCached: an ARM token minted at the public authority for
    # the public ARM audience must not be served to a USGov session.
    It 'RE-ACQUIRES the ARM token when the cloud changes (SEC-token-survives-cloud-switch)' {
        Mock -ModuleName $script:moduleName Get-AzToken {
            param($Resource)
            [pscustomobject]@{ Token = "token-for-$Resource"; ExpiresOn = [DateTimeOffset]::UtcNow.AddHours(1); Identity = 'a@b.c' }
        }
        Mock -ModuleName $script:moduleName Connect-MgGraph { }

        InModuleScope $script:moduleName {
            Initialize-OERAuth -TenantId 'contoso' -AuthMethod 'Interactive' -IncludeARM
            $script:_OERAuthState.ArmResourceUrl | Should -Be 'https://management.azure.com/'

            Initialize-OERAuth -TenantId 'contoso' -AuthMethod 'Interactive' -Environment 'USGov' -IncludeARM

            $script:_OERAuthState.ArmResourceUrl | Should -Be 'https://management.usgovcloudapi.net/'
            [System.Net.NetworkCredential]::new('', $script:_OERAuthState.ArmToken).Password |
                Should -Be 'token-for-https://management.usgovcloudapi.net/'
        }
    }

    # The other half of the ARM rule, via $ArmIdentityUnchanged: a cloud switch made WITHOUT
    # -IncludeARM short-circuits $ArmCached to $true and never enters the ARM branch, so only the
    # carry-forward guard at the state rebuild can stop the public-cloud ARM token riding along
    # under a sovereign label.
    It 'DROPS a carried-forward ARM token when the cloud changes without -IncludeARM' {
        Mock -ModuleName $script:moduleName Get-AzToken {
            param($Resource)
            [pscustomobject]@{ Token = "token-for-$Resource"; ExpiresOn = [DateTimeOffset]::UtcNow.AddHours(1); Identity = 'a@b.c' }
        }
        Mock -ModuleName $script:moduleName Connect-MgGraph { }

        InModuleScope $script:moduleName {
            Initialize-OERAuth -TenantId 'contoso' -AuthMethod 'Interactive' -IncludeARM
            $script:_OERAuthState.ArmToken | Should -BeOfType [System.Security.SecureString]

            Initialize-OERAuth -TenantId 'contoso' -AuthMethod 'Interactive' -Environment 'China'

            $script:_OERAuthState.Environment    | Should -Be 'China'
            $script:_OERAuthState.ArmToken       | Should -BeNullOrEmpty
            $script:_OERAuthState.ArmTokenExpiry | Should -BeNullOrEmpty
            $script:_OERAuthState.ArmResourceUrl | Should -BeNullOrEmpty
        }
    }

    # A sovereign session must keep its cloud for every later cmdlet, none of which names one.
    It 'inherits the session cloud when no -Environment is supplied' {
        Mock -ModuleName $script:moduleName Get-AzToken {
            param($Resource)
            [pscustomobject]@{ Token = "token-for-$Resource"; ExpiresOn = [DateTimeOffset]::UtcNow.AddHours(1); Identity = 'a@b.c' }
        }
        Mock -ModuleName $script:moduleName Connect-MgGraph { }

        InModuleScope $script:moduleName {
            Initialize-OERAuth -TenantId 'contoso' -AuthMethod 'Interactive' -Environment 'USGov'

            # Exactly what all 22 ARM cmdlets do: no -TenantId, no -AuthMethod, no -Environment.
            Initialize-OERAuth -IncludeARM

            $script:_OERAuthState.Environment    | Should -Be 'USGov'
            $script:_OERAuthState.ArmResourceUrl | Should -Be 'https://management.usgovcloudapi.net/'
        }

        Should -Invoke -ModuleName $script:moduleName Get-AzToken -Exactly -Times 1 -ParameterFilter {
            $Resource -eq 'https://management.usgovcloudapi.net/'
        }
    }

    It 'passes -Force on a cloud switch and NOT on a same-cloud re-acquisition' {
        Mock -ModuleName $script:moduleName Get-AzToken {
            param($ClientId, $ClientSecret, $Resource, $Tenant, $ErrorAction, $Interactive,
                  $DeviceCode, $ManagedIdentity, $ClientCertificate, $ClientCertificatePath,
                  $Scope, $Force, $Claim)
            $script:ForceProbeKeys = @($PSBoundParameters.Keys)
            [pscustomobject]@{ Token = 'fake'; ExpiresOn = [DateTimeOffset]::UtcNow.AddHours(1); Identity = 'a@b.c' }
        }
        Mock -ModuleName $script:moduleName Connect-MgGraph { }

        # 1. First sign-in, public cloud. $script:_OERLastAuthorityHost seeds to the PUBLIC authority
        #    rather than null precisely so this call gains no -Force it did not have before.
        InModuleScope $script:moduleName { Initialize-OERAuth -TenantId 'contoso' -AuthMethod 'Interactive' }
        $script:ForceProbeKeys | Should -Not -BeNullOrEmpty
        $script:ForceProbeKeys | Should -Not -Contain 'Force'

        # 2. Cloud switch: AzAuth's static credential is still baked to the public authority, and
        #    -Force is the only way to make it drop that credential and construct a new one.
        InModuleScope $script:moduleName { Initialize-OERAuth -TenantId 'contoso' -AuthMethod 'Interactive' -Environment 'USGov' }
        $script:ForceProbeKeys | Should -Contain 'Force'

        # 3. A fresh acquisition in the SAME cloud (different tenant, so the cache misses) needs no
        #    -Force: the credential in AzAuth's static field is already at this authority.
        InModuleScope $script:moduleName { Initialize-OERAuth -TenantId 'fabrikam' -AuthMethod 'Interactive' -Environment 'USGov' }
        $script:ForceProbeKeys | Should -Not -Contain 'Force'
    }
}

Describe 'Initialize-OERAuth AZURE_AUTHORITY_HOST restore' {
    BeforeAll {
        $script:AmbientAuthorityHost = [System.Environment]::GetEnvironmentVariable('AZURE_AUTHORITY_HOST')
    }

    AfterAll {
        # [NullString]::Value, not $null: PowerShell coerces $null to '' when binding a .NET string
        # parameter, and an EMPTY AZURE_AUTHORITY_HOST is a different state from an absent one.
        if ($null -eq $script:AmbientAuthorityHost) {
            [System.Environment]::SetEnvironmentVariable('AZURE_AUTHORITY_HOST', [NullString]::Value)
        }
        else {
            [System.Environment]::SetEnvironmentVariable('AZURE_AUTHORITY_HOST', $script:AmbientAuthorityHost)
        }
    }

    BeforeEach {
        [System.Environment]::SetEnvironmentVariable('AZURE_AUTHORITY_HOST', [NullString]::Value)
        InModuleScope $script:moduleName {
            $script:_OERAuthState = $null
            $script:_OERSessionUncertain = $null
            $script:_OERLastAuthorityHost = $null
            $script:_OERLastTokenRequest = $null
            $script:_OERInteractiveCredential = $null
        }
        # BL-12: a tenant named by anything but a GUID or 'organizations' is looked up before any token
        # is requested. The tokens in this Describe carry no GUID tenant, so the mocked lookup answers
        # with any tenant ID.
        Mock -ModuleName $script:moduleName Resolve-OERTenantDomain { '11111111-1111-1111-1111-111111111111' }
    }

    # AZURE_AUTHORITY_HOST is process-wide. A terminating Write-CmdletError unwinds straight out of
    # Initialize-OERAuth, so without the restore living in the finally the caller's process stays
    # pinned to a sovereign authority for every later Azure.Identity credential it constructs --
    # including ones this module never touches.
    It 'DELETES AZURE_AUTHORITY_HOST again when the Graph token call throws and it was unset' {
        Mock -ModuleName $script:moduleName Get-AzToken { throw 'graph boom' }
        Mock -ModuleName $script:moduleName Connect-MgGraph { }

        { InModuleScope $script:moduleName {
            Initialize-OERAuth -TenantId 'contoso' -AuthMethod 'Interactive' -Environment 'USGov'
        } } | Should -Throw

        # Deleted, not emptied. Only [NullString]::Value removes the variable from PowerShell;
        # writing '' would leave an empty AZURE_AUTHORITY_HOST behind, which is a different state
        # from an absent one and is exactly what a [string]-typed capture would have produced.
        Test-Path -Path 'Env:AZURE_AUTHORITY_HOST' | Should -BeFalse
    }

    It 'RESTORES a pre-existing AZURE_AUTHORITY_HOST when the Graph token call throws' {
        [System.Environment]::SetEnvironmentVariable('AZURE_AUTHORITY_HOST', 'https://ambient.invalid/')
        Mock -ModuleName $script:moduleName Get-AzToken { throw 'graph boom' }
        Mock -ModuleName $script:moduleName Connect-MgGraph { }

        { InModuleScope $script:moduleName {
            Initialize-OERAuth -TenantId 'contoso' -AuthMethod 'Interactive' -Environment 'China'
        } } | Should -Throw

        [System.Environment]::GetEnvironmentVariable('AZURE_AUTHORITY_HOST') | Should -Be 'https://ambient.invalid/'
    }

    It 'RESTORES AZURE_AUTHORITY_HOST when Connect-MgGraph throws' {
        [System.Environment]::SetEnvironmentVariable('AZURE_AUTHORITY_HOST', 'https://ambient.invalid/')
        Mock -ModuleName $script:moduleName Get-AzToken {
            [pscustomobject]@{ Token = 'fake'; ExpiresOn = [DateTimeOffset]::UtcNow.AddHours(1); Identity = 'a@b.c' }
        }
        Mock -ModuleName $script:moduleName Connect-MgGraph { throw 'connect boom' }

        { InModuleScope $script:moduleName {
            Initialize-OERAuth -TenantId 'contoso' -AuthMethod 'Interactive' -Environment 'USGovDoD'
        } } | Should -Throw

        [System.Environment]::GetEnvironmentVariable('AZURE_AUTHORITY_HOST') | Should -Be 'https://ambient.invalid/'
    }

    # The ARM failure is NON-terminating and returns from inside the try, which is a third way out
    # of the block and therefore a third way to skip a restore written anywhere but the finally.
    It 'RESTORES AZURE_AUTHORITY_HOST when the ARM token call fails' {
        [System.Environment]::SetEnvironmentVariable('AZURE_AUTHORITY_HOST', 'https://ambient.invalid/')
        $script:ArmRestoreCallCount = 0
        Mock -ModuleName $script:moduleName Get-AzToken {
            $script:ArmRestoreCallCount++
            if ($script:ArmRestoreCallCount -eq 1) {
                [pscustomobject]@{ Token = 'fake-graph'; ExpiresOn = [DateTimeOffset]::UtcNow.AddHours(1); Identity = 'a@b.c' }
            }
            else {
                throw 'arm boom'
            }
        }
        Mock -ModuleName $script:moduleName Connect-MgGraph { }

        InModuleScope $script:moduleName {
            Initialize-OERAuth -TenantId 'contoso' -AuthMethod 'Interactive' -Environment 'USGov' `
                -IncludeARM -ErrorAction SilentlyContinue
        }

        [System.Environment]::GetEnvironmentVariable('AZURE_AUTHORITY_HOST') | Should -Be 'https://ambient.invalid/'
    }

    It 'RESTORES AZURE_AUTHORITY_HOST on the success path too' {
        [System.Environment]::SetEnvironmentVariable('AZURE_AUTHORITY_HOST', 'https://ambient.invalid/')
        Mock -ModuleName $script:moduleName Get-AzToken {
            [pscustomobject]@{ Token = 'fake'; ExpiresOn = [DateTimeOffset]::UtcNow.AddHours(1); Identity = 'a@b.c' }
        }
        Mock -ModuleName $script:moduleName Connect-MgGraph { }

        InModuleScope $script:moduleName {
            Initialize-OERAuth -TenantId 'contoso' -AuthMethod 'Interactive' -Environment 'USGov' -IncludeARM
        }

        [System.Environment]::GetEnvironmentVariable('AZURE_AUTHORITY_HOST') | Should -Be 'https://ambient.invalid/'
    }
}

# -------------------------------------------------------------------------------------------------
# Sovereign clouds, review fix round 1 (Sprint 1.5, issue #81).
# -------------------------------------------------------------------------------------------------
Describe 'Initialize-OERAuth sovereign cloud -Force scoping' {
    BeforeAll {
        $script:AmbientAuthorityHost = [System.Environment]::GetEnvironmentVariable('AZURE_AUTHORITY_HOST')
    }

    AfterAll {
        if ($null -eq $script:AmbientAuthorityHost) {
            [System.Environment]::SetEnvironmentVariable('AZURE_AUTHORITY_HOST', [NullString]::Value)
        }
        else {
            [System.Environment]::SetEnvironmentVariable('AZURE_AUTHORITY_HOST', $script:AmbientAuthorityHost)
        }
    }

    BeforeEach {
        [System.Environment]::SetEnvironmentVariable('AZURE_AUTHORITY_HOST', [NullString]::Value)
        InModuleScope $script:moduleName {
            $script:_OERAuthState = $null
            $script:_OERSessionUncertain = $null
            $script:_OERLastAuthorityHost = $null
            $script:_OERLastTokenRequest = $null
            $script:_OERInteractiveCredential = $null
        }
        # BL-12: a tenant named by anything but a GUID or 'organizations' is looked up before any token
        # is requested. The tokens in this Describe carry no GUID tenant, so the mocked lookup answers
        # with any tenant ID.
        Mock -ModuleName $script:moduleName Resolve-OERTenantDomain { '11111111-1111-1111-1111-111111111111' }
    }

    # The authority-move -Force is consumed by the GRAPH call: AzAuth clears its static credential
    # and constructs a new one at the new authority. Cloning it into the ARM call as well makes
    # AzAuth throw that fresh credential away and construct another one at the same authority. That
    # matters for the credential types AzAuth reuses, such as a client secret: without Force, its ARM
    # call on the standard 'Connect-OER -Environment USGov -IncludeARM' path reuses the credential the
    # Graph call just built. It is NOT what decides whether a second prompt appears. On DeviceCode the
    # ARM call builds a new credential anyway, since it passes no client id where the Graph call
    # passes one (measured offline), and on Interactive every call constructs a new credential
    # (decompiled, not executed). Interactive below only makes the splat observable.
    It 'does NOT repeat the cloud-switch -Force on the ARM call after a Graph acquisition' {
        Mock -ModuleName $script:moduleName Get-AzToken {
            param($ClientId, $ClientSecret, $Resource, $Tenant, $ErrorAction, $Interactive,
                  $DeviceCode, $ManagedIdentity, $ClientCertificate, $ClientCertificatePath,
                  $Scope, $Force, $Claim)
            if ($PSBoundParameters.ContainsKey('Scope')) {
                $script:SwitchGraphKeys = @($PSBoundParameters.Keys)
            }
            else {
                $script:SwitchArmKeys = @($PSBoundParameters.Keys)
            }
            [pscustomobject]@{ Token = "token-for-$Resource"; ExpiresOn = [DateTimeOffset]::UtcNow.AddHours(1); Identity = 'a@b.c' }
        }
        Mock -ModuleName $script:moduleName Connect-MgGraph { }

        InModuleScope $script:moduleName {
            Initialize-OERAuth -TenantId 'contoso' -AuthMethod 'Interactive'
            Initialize-OERAuth -TenantId 'contoso' -AuthMethod 'Interactive' -Environment 'USGov' -IncludeARM
        }

        $script:SwitchGraphKeys | Should -Not -BeNullOrEmpty
        $script:SwitchGraphKeys | Should -Contain 'Force'
        $script:SwitchArmKeys   | Should -Not -BeNullOrEmpty -Because 'the ARM call must have run, or the assertion below is vacuous'
        $script:SwitchArmKeys   | Should -Not -Contain 'Force'
    }

    # The caller's own -ForceRefresh is an instruction, not an implementation detail of the cloud
    # move, so it must survive onto BOTH calls exactly as it did before this branch.
    It 'KEEPS -Force on the ARM call when the caller passed -ForceRefresh' {
        Mock -ModuleName $script:moduleName Get-AzToken {
            param($ClientId, $ClientSecret, $Resource, $Tenant, $ErrorAction, $Interactive,
                  $DeviceCode, $ManagedIdentity, $ClientCertificate, $ClientCertificatePath,
                  $Scope, $Force, $Claim)
            if ($PSBoundParameters.ContainsKey('Scope')) {
                $script:RefreshGraphKeys = @($PSBoundParameters.Keys)
            }
            else {
                $script:RefreshArmKeys = @($PSBoundParameters.Keys)
            }
            [pscustomobject]@{ Token = "token-for-$Resource"; ExpiresOn = [DateTimeOffset]::UtcNow.AddHours(1); Identity = 'a@b.c' }
        }
        Mock -ModuleName $script:moduleName Connect-MgGraph { }

        InModuleScope $script:moduleName {
            Initialize-OERAuth -TenantId 'contoso' -AuthMethod 'Interactive'
            Initialize-OERAuth -TenantId 'contoso' -AuthMethod 'Interactive' -IncludeARM -ForceRefresh
        }

        $script:RefreshGraphKeys | Should -Contain 'Force'
        $script:RefreshArmKeys   | Should -Not -BeNullOrEmpty
        $script:RefreshArmKeys   | Should -Contain 'Force'
    }

    # The exact case that makes the removal's PLACEMENT load-bearing. The removal sits inside the
    # Graph-acquired branch, so when the Graph token is cached and only ARM runs, the authority-move
    # -Force survives -- and it is genuinely needed, since a FAILED sovereign attempt moved AzAuth's
    # static credential to the sovereign authority without ever rebuilding $script:_OERAuthState.
    # Hoisting the removal out of that branch would silently break this.
    It 'KEEPS -Force on an ARM-only acquisition whose authority differs from the last attempt' {
        $script:ArmOnlyCallCount = 0
        Mock -ModuleName $script:moduleName Get-AzToken {
            param($ClientId, $ClientSecret, $Resource, $Tenant, $ErrorAction, $Interactive,
                  $DeviceCode, $ManagedIdentity, $ClientCertificate, $ClientCertificatePath,
                  $Scope, $Force, $Claim)
            $script:ArmOnlyCallCount++
            # Call 1: the Global Graph token, which succeeds and is cached below.
            # Call 2: the sovereign attempt, which fails AFTER AzAuth built its credential.
            # Call 3: the ARM-only acquisition under the inherited Global cloud.
            if ($script:ArmOnlyCallCount -eq 2) { throw 'sovereign boom' }
            if ($script:ArmOnlyCallCount -eq 3) { $script:ArmOnlyKeys = @($PSBoundParameters.Keys) }
            [pscustomobject]@{ Token = "token-for-$Resource"; ExpiresOn = [DateTimeOffset]::UtcNow.AddHours(1); Identity = 'a@b.c' }
        }
        Mock -ModuleName $script:moduleName Connect-MgGraph { }

        InModuleScope $script:moduleName {
            # A Global session with a valid Graph token and NO ARM token.
            Initialize-OERAuth -TenantId 'contoso' -AuthMethod 'Interactive'

            # A sovereign attempt that fails. The state is untouched; AzAuth's credential is not.
            try {
                Initialize-OERAuth -TenantId 'contoso' -AuthMethod 'Interactive' -Environment 'USGov'
            }
            catch {
                # Expected: GraphTokenAcquisitionFailed is terminating.
            }
            $script:_OERAuthState.Environment | Should -Be 'Global'

            # An ARM cmdlet: Graph is cached, so ONLY the ARM branch runs. It names the session's tenant:
            # after the failed attempt the session is uncertain (A10), and a sign-in that names no tenant
            # would be refused before its token call. Named or inherited, the tenant is the same.
            Initialize-OERAuth -TenantId 'contoso' -IncludeARM
        }

        $script:ArmOnlyKeys | Should -Not -BeNullOrEmpty -Because 'the third call must have run, or the assertion below is vacuous'
        $script:ArmOnlyKeys | Should -Not -Contain 'Scope' -Because 'the third call has to be the ARM one, not a second Graph acquisition'
        $script:ArmOnlyKeys | Should -Contain 'Force'
    }
}

Describe 'Initialize-OERAuth authority tracking across a failed acquisition' {
    BeforeAll {
        $script:AmbientAuthorityHost = [System.Environment]::GetEnvironmentVariable('AZURE_AUTHORITY_HOST')
    }

    AfterAll {
        if ($null -eq $script:AmbientAuthorityHost) {
            [System.Environment]::SetEnvironmentVariable('AZURE_AUTHORITY_HOST', [NullString]::Value)
        }
        else {
            [System.Environment]::SetEnvironmentVariable('AZURE_AUTHORITY_HOST', $script:AmbientAuthorityHost)
        }
    }

    BeforeEach {
        [System.Environment]::SetEnvironmentVariable('AZURE_AUTHORITY_HOST', [NullString]::Value)
        InModuleScope $script:moduleName {
            $script:_OERAuthState = $null
            $script:_OERSessionUncertain = $null
            $script:_OERLastAuthorityHost = $null
            $script:_OERLastTokenRequest = $null
            $script:_OERInteractiveCredential = $null
        }
        # BL-12: a tenant named by anything but a GUID or 'organizations' is looked up before any token
        # is requested. The tokens in this Describe carry no GUID tenant, so the mocked lookup answers
        # with any tenant ID.
        Mock -ModuleName $script:moduleName Resolve-OERTenantDomain { '11111111-1111-1111-1111-111111111111' }
    }

    # Get-AzToken constructs the credential and THEN requests the token, so a sovereign attempt that
    # fails still leaves AzAuth's static credential baked to the sovereign authority. If the tracker
    # only recorded SUCCESSES it would still name the commercial authority, the operator's next
    # plain Global sign-in would compare equal, skip -Force, and reuse that sovereign-baked
    # credential -- failing with an AADSTS error that names the tenant and never the authority, and
    # poisoning every later Global sign-in in the process until a -ForceRefresh or a restart.
    It 'passes -Force on the next GLOBAL sign-in after a sovereign acquisition threw' {
        $script:PoisonCallCount = 0
        Mock -ModuleName $script:moduleName Get-AzToken {
            param($ClientId, $ClientSecret, $Resource, $Tenant, $ErrorAction, $Interactive,
                  $DeviceCode, $ManagedIdentity, $ClientCertificate, $ClientCertificatePath,
                  $Scope, $Force, $Claim)
            $script:PoisonCallCount++
            if ($script:PoisonCallCount -eq 1) { throw 'cancelled prompt' }
            $script:PoisonRecoveryKeys = @($PSBoundParameters.Keys)
            [pscustomobject]@{ Token = 'fake'; ExpiresOn = [DateTimeOffset]::UtcNow.AddHours(1); Identity = 'a@b.c' }
        }
        Mock -ModuleName $script:moduleName Connect-MgGraph { }

        InModuleScope $script:moduleName {
            # No session at all: the tracker seeds to the PUBLIC authority.
            try {
                Initialize-OERAuth -TenantId 'contoso' -AuthMethod 'Interactive' -Environment 'USGov'
            }
            catch {
                # Expected.
            }

            # The operator retries against the commercial cloud.
            Initialize-OERAuth -TenantId 'contoso' -AuthMethod 'Interactive'
            $script:_OERAuthState.Environment | Should -Be 'Global'
        }

        $script:PoisonRecoveryKeys | Should -Not -BeNullOrEmpty -Because 'the recovery call must have run, or the assertion below is vacuous'
        $script:PoisonRecoveryKeys | Should -Contain 'Force'
    }

    # The other direction, so the fix above cannot be satisfied by simply forcing everything: a
    # first-ever Global sign-in in a clean process still carries no -Force.
    It 'still passes NO -Force on a first Global sign-in in a clean process' {
        Mock -ModuleName $script:moduleName Get-AzToken {
            param($ClientId, $ClientSecret, $Resource, $Tenant, $ErrorAction, $Interactive,
                  $DeviceCode, $ManagedIdentity, $ClientCertificate, $ClientCertificatePath,
                  $Scope, $Force, $Claim)
            $script:CleanStartKeys = @($PSBoundParameters.Keys)
            [pscustomobject]@{ Token = 'fake'; ExpiresOn = [DateTimeOffset]::UtcNow.AddHours(1); Identity = 'a@b.c' }
        }
        Mock -ModuleName $script:moduleName Connect-MgGraph { }

        InModuleScope $script:moduleName {
            Initialize-OERAuth -TenantId 'contoso' -AuthMethod 'Interactive'
        }

        $script:CleanStartKeys | Should -Not -BeNullOrEmpty
        $script:CleanStartKeys | Should -Not -Contain 'Force'
    }
}


Describe 'Initialize-OERAuth ambient AZURE_AUTHORITY_HOST warning' {
    BeforeAll {
        $script:AmbientAuthorityHost = [System.Environment]::GetEnvironmentVariable('AZURE_AUTHORITY_HOST')
    }

    AfterAll {
        if ($null -eq $script:AmbientAuthorityHost) {
            [System.Environment]::SetEnvironmentVariable('AZURE_AUTHORITY_HOST', [NullString]::Value)
        }
        else {
            [System.Environment]::SetEnvironmentVariable('AZURE_AUTHORITY_HOST', $script:AmbientAuthorityHost)
        }
    }

    BeforeEach {
        [System.Environment]::SetEnvironmentVariable('AZURE_AUTHORITY_HOST', [NullString]::Value)
        InModuleScope $script:moduleName {
            $script:_OERAuthState = $null
            $script:_OERSessionUncertain = $null
            $script:_OERLastAuthorityHost = $null
            $script:_OERLastTokenRequest = $null
            $script:_OERInteractiveCredential = $null
        }
        # BL-12: a tenant named by anything but a GUID or 'organizations' is looked up before any token
        # is requested. The tokens in this Describe carry no GUID tenant, so the mocked lookup answers
        # with any tenant ID.
        Mock -ModuleName $script:moduleName Resolve-OERTenantDomain { '11111111-1111-1111-1111-111111111111' }
        Mock -ModuleName $script:moduleName Get-AzToken {
            [pscustomobject]@{ Token = 'fake'; ExpiresOn = [DateTimeOffset]::UtcNow.AddHours(1); Identity = 'a@b.c' }
        }
        Mock -ModuleName $script:moduleName Connect-MgGraph { }
    }

    # A Global sign-in must never WRITE the variable -- that is the byte-identical public path this
    # sprint protects -- but Azure.Identity follows it regardless, and the STS error that results
    # names the tenant and never the authority. The warning is the only thing that explains it.
    It 'warns when AZURE_AUTHORITY_HOST is set to a non-commercial authority on a Global sign-in' {
        [System.Environment]::SetEnvironmentVariable('AZURE_AUTHORITY_HOST', 'https://login.microsoftonline.us/')

        $Warnings = @(InModuleScope $script:moduleName {
            Initialize-OERAuth -TenantId 'contoso' -AuthMethod 'Interactive' `
                -WarningVariable Captured -WarningAction SilentlyContinue
            $Captured | ForEach-Object { $_.ToString() }
        })

        $Warnings | Should -Not -BeNullOrEmpty
        ($Warnings -join ' ') | Should -Match 'AZURE_AUTHORITY_HOST'
        ($Warnings -join ' ') | Should -Match ([regex]::Escape('https://login.microsoftonline.us/'))
        ($Warnings -join ' ') | Should -Match ([regex]::Escape('https://login.microsoftonline.com/'))

        # Named and explained, never overwritten.
        [System.Environment]::GetEnvironmentVariable('AZURE_AUTHORITY_HOST') |
            Should -Be 'https://login.microsoftonline.us/'
    }

    It 'does NOT warn when AZURE_AUTHORITY_HOST is unset' {
        $Warnings = @(InModuleScope $script:moduleName {
            Initialize-OERAuth -TenantId 'contoso' -AuthMethod 'Interactive' `
                -WarningVariable Captured -WarningAction SilentlyContinue
            $Captured | ForEach-Object { $_.ToString() }
        })

        $Warnings | Should -BeNullOrEmpty
        Test-Path -Path 'Env:AZURE_AUTHORITY_HOST' | Should -BeFalse
    }

    # Trailing-slash tolerant: an operator who pins the commercial authority by hand, with or
    # without the slash, is not doing anything that needs explaining.
    It 'does NOT warn when AZURE_AUTHORITY_HOST already names the commercial authority' {
        [System.Environment]::SetEnvironmentVariable('AZURE_AUTHORITY_HOST', 'https://login.microsoftonline.com')

        $Warnings = @(InModuleScope $script:moduleName {
            Initialize-OERAuth -TenantId 'contoso' -AuthMethod 'Interactive' `
                -WarningVariable Captured -WarningAction SilentlyContinue
            $Captured | ForEach-Object { $_.ToString() }
        })

        $Warnings | Should -BeNullOrEmpty
    }

    # The warning belongs to the Global branch only. On a sovereign cloud the module OVERWRITES the
    # variable for the duration of the call, so an ambient value is simply irrelevant there, and
    # warning about it would be noise on the normal path -- training operators to ignore it.
    It 'does NOT warn on a sovereign sign-in, where the variable is overwritten anyway' {
        [System.Environment]::SetEnvironmentVariable('AZURE_AUTHORITY_HOST', 'https://login.microsoftonline.com/')

        $Warnings = @(InModuleScope $script:moduleName {
            Initialize-OERAuth -TenantId 'contoso' -AuthMethod 'Interactive' -Environment 'USGov' `
                -WarningVariable Captured -WarningAction SilentlyContinue
            $Captured | ForEach-Object { $_.ToString() }
        })

        $Warnings | Should -BeNullOrEmpty
        [System.Environment]::GetEnvironmentVariable('AZURE_AUTHORITY_HOST') |
            Should -Be 'https://login.microsoftonline.com/'
    }
}

Describe 'Initialize-OERAuth device-code instruction visibility' {
    # THE LIVE DEFECT. A device-code sign-in printed:
    #
    #   WARNING: To sign in, use a web browser to open the page https://login.microsoftonline.us/device
    #   and enter the code EDC46Y2SV to authenticate.
    #
    # AzAuth emits that on the WARNING stream: PipeHow.AzAuth.TokenManager's device-code callback
    # pushes Azure.Identity's DeviceCodeInfo.Message into a BlockingCollection[string] and
    # PipeHow.AzAuth.GetAzToken.EndProcessing drains it through Cmdlet::WriteWarning. It is not a
    # warning at all -- it is the primary interaction, and the sign-in cannot complete without it --
    # and anything running under -WarningAction SilentlyContinue or
    # $WarningPreference = 'SilentlyContinue' never saw the code, so the sign-in looked like a hang
    # until it timed out. AzAuth cannot be changed from here; how this module consumes it can.
    BeforeEach {
        InModuleScope $script:moduleName {
            $script:_OERAuthState = $null
            $script:_OERSessionUncertain = $null
            $script:_OERLastAuthorityHost = $null
            $script:_OERLastTokenRequest = $null
            $script:_OERInteractiveCredential = $null
        }
        # BL-12: a tenant named by anything but a GUID or 'organizations' is looked up before any token
        # is requested. The tokens in this Describe carry no GUID tenant, so the mocked lookup answers
        # with any tenant ID.
        Mock -ModuleName $script:moduleName Resolve-OERTenantDomain { '11111111-1111-1111-1111-111111111111' }
        Mock -ModuleName $script:moduleName Connect-MgGraph { }
    }

    It 'surfaces the device code on the information stream even when warnings are silenced' {
        # WHY THIS TEST DOES NOT USE A PESTER MOCK, AND WHY THE PREVIOUS ONE PROVED NOTHING.
        # The title is the entire point of the fix, and the earlier version never silenced anything:
        # -WarningAction SilentlyContinue on the Initialize-OERAuth call does NOT reach a Pester mock
        # body, so the mocked Get-AzToken kept warning at full volume and the test passed for a
        # reason unrelated to the protection it names -- visible as a 'WARNING: ... EDC46Y2SV' line
        # printed to the console while the test was green.
        #
        # Silencing it properly is not enough either. MEASURED, on this module and Pester 5.7.1:
        # a mock body resolves $WarningPreference from the GLOBAL scope only. Neither
        # -WarningAction Continue bound at the call site nor a $WarningPreference assignment in the
        # calling function reaches it -- both were tried and both left the mock body reading
        # SilentlyContinue. Under a silenced global preference NO change inside this module can make
        # a mocked Get-AzToken emit, so a mock-based version of this test is unsatisfiable: it fails
        # identically with the fix present and absent, which is the opposite of a regression test.
        #
        # A real advanced function in the module's own scope behaves like the real compiled cmdlet
        # instead: its Write-Warning honours the effective preference, so the record is genuinely
        # dropped when warnings are silenced and genuinely restored by the -WarningAction Continue
        # the fix passes. Nothing authenticates -- the stub returns a fabricated token object and
        # never loads or calls AzAuth -- and it is removed again in a finally so it cannot leak into
        # any test that runs after this one.
        $Captured = InModuleScope $script:moduleName {
            function script:Get-AzToken {
                [CmdletBinding()]
                param(
                    [string]$Resource, [string]$Tenant, [string]$ClientId, $ClientSecret,
                    [switch]$Interactive, [switch]$DeviceCode, [switch]$ManagedIdentity,
                    $ClientCertificate, [string]$ClientCertificatePath, [string[]]$Scope,
                    [switch]$Force, [string]$Claim
                )
                Write-Warning 'To sign in, use a web browser to open the page https://login.microsoftonline.us/device and enter the code EDC46Y2SV to authenticate.'
                [pscustomobject]@{ Token = 'fake'; ExpiresOn = [DateTimeOffset]::UtcNow.AddHours(1); Identity = 'admin@contoso.com'; TenantId = 'contoso' }
            }
            try {
                $InfoVar = $null
                $WarnVar = $null
                # The automation host, reproduced: warnings silenced at the one scope every callee
                # resolves through. Restored in a finally -- leaving it silenced would quietly mute
                # warnings for the rest of the run.
                $PreviousWarningPreference = $global:WarningPreference
                $global:WarningPreference = 'SilentlyContinue'
                try {
                    Initialize-OERAuth -TenantId 'contoso' -AuthMethod 'DeviceCode' `
                        -InformationVariable InfoVar -WarningVariable WarnVar 6>$null
                } finally {
                    $global:WarningPreference = $PreviousWarningPreference
                }
                [pscustomobject]@{
                    Information = @($InfoVar | ForEach-Object { [string]$_.MessageData })
                    Warning     = @($WarnVar | ForEach-Object { [string]$_.Message })
                    Account     = $script:_OERAuthState.Account
                }
            } finally {
                # 'function:Get-AzToken', NOT 'function:script:Get-AzToken'. The function: provider
                # does not honour a scope qualifier inside the path: the qualified form removes
                # nothing and does not even error under -ErrorAction Stop, so the stub survived and
                # shadowed the real AzAuth cmdlet in module scope for the rest of the Pester
                # process. Every later test file reaching Initialize-OERAuth without its own
                # Get-AzToken mock would then have received a fabricated successful token instead
                # of failing. Verified both ways before changing it.
                Remove-Item -Path 'function:Get-AzToken' -ErrorAction SilentlyContinue
            }
        }

        # The instruction reached the operator on a stream that a silenced warning preference does
        # not touch. Asserted on the CODE itself, not on the sentence, since the sentence is
        # AzAuth's text and may change.
        ($Captured.Information -join "`n") | Should -Match 'EDC46Y2SV' -Because (
            'a silenced warning preference is exactly the automation case the device code was ' +
            'invisible in, and without -WarningAction Continue the record is dropped at source, so ' +
            'the 3>&1 redirection has nothing left to merge'
        )
        # ...and it is no longer presented as a warning. 3>&1 consumes the record, so nothing is
        # left on the warning stream to mislabel the interaction.
        ($Captured.Warning -join "`n") | Should -Not -Match 'EDC46Y2SV'
        # The AzToken object still reached the caller unchanged: the pipeline that re-emits the
        # warning must not wrap, unroll or lose it.
        $Captured.Account | Should -Be 'admin@contoso.com'
    }

    It 'passes -WarningAction Continue on the device-code token call' {
        # The mechanism above, pinned at the call site as well. This one CAN use a mock, since it
        # asserts what was bound rather than what the callee then did with it -- and a bound common
        # parameter is visible to a ParameterFilter even though it never reaches the mock body.
        Mock -ModuleName $script:moduleName Get-AzToken {
            [pscustomobject]@{ Token = 'fake'; ExpiresOn = [DateTimeOffset]::UtcNow.AddHours(1); Identity = 'admin@contoso.com'; TenantId = 'contoso' }
        }

        InModuleScope $script:moduleName {
            Initialize-OERAuth -TenantId 'contoso' -AuthMethod 'DeviceCode' 6>$null
        }

        Should -Invoke -ModuleName $script:moduleName Get-AzToken -Times 1 -Exactly -ParameterFilter {
            $WarningAction -eq 'Continue'
        }
    }

    It 'leaves every other credential type calling Get-AzToken with no pipeline in between' {
        # The public, non-device-code path staying byte-identical is the invariant this change must
        # not spend. An Interactive sign-in that warns keeps its warning on the WARNING stream and
        # writes nothing to the information stream.
        # Module-qualified on purpose: a mock body resolves commands from the test's scope, where a build
        # runner may define a Write-Warning of its own -- Invoke-Build does, and counts every message it
        # carries as a build warning, whatever -WarningAction says. The cmdlet writes the same record.
        Mock -ModuleName $script:moduleName Get-AzToken {
            Microsoft.PowerShell.Utility\Write-Warning 'some unrelated AzAuth warning'
            [pscustomobject]@{ Token = 'fake'; ExpiresOn = [DateTimeOffset]::UtcNow.AddHours(1); Identity = 'admin@contoso.com'; TenantId = 'contoso' }
        }

        $Captured = InModuleScope $script:moduleName {
            $InfoVar = $null
            $WarnVar = $null
            # 3>&1 merges the warning stream into the output: the warning is asserted below as a record
            # on that stream, and is not printed to the console. A mock body does not see the
            # -WarningAction bound here (see the first test of this Describe), so -WarningAction
            # SilentlyContinue alone never kept it off the console.
            $Merged = @(Initialize-OERAuth -TenantId 'contoso' -AuthMethod 'Interactive' `
                    -InformationVariable InfoVar -WarningVariable WarnVar `
                    -WarningAction SilentlyContinue 6>$null 3>&1)
            [pscustomobject]@{
                Information = @($InfoVar | ForEach-Object { [string]$_.MessageData })
                Warning     = @($WarnVar | ForEach-Object { [string]$_.Message })
                Streamed    = @($Merged | Where-Object { $_ -is [System.Management.Automation.WarningRecord] } | ForEach-Object { [string]$_.Message })
                Account     = $script:_OERAuthState.Account
            }
        }

        ($Captured.Warning -join "`n") | Should -Match 'some unrelated AzAuth warning'
        $Captured.Streamed | Should -Be @('some unrelated AzAuth warning') -Because (
            'the warning stays on the warning stream, exactly once, and is not turned into anything else')
        ($Captured.Information -join "`n") | Should -Not -Match 'some unrelated AzAuth warning'
        $Captured.Account | Should -Be 'admin@contoso.com'
        # And the splat itself is untouched: the device-code branch's -WarningAction Continue must
        # not be applied here. A bound common parameter IS visible to a ParameterFilter, so this
        # reads the real binding rather than inferring it from behaviour.
        Should -Invoke -ModuleName $script:moduleName Get-AzToken -Times 0 -Exactly -ParameterFilter {
            $WarningAction -eq 'Continue'
        }
    }

    It 'still surfaces a terminating GraphTokenAcquisitionFailed when the device-code call fails' {
        # A redirection must not swallow a throw. Without this the whole failure path could go
        # silent on the one credential type this change touches.
        Mock -ModuleName $script:moduleName Get-AzToken { throw 'device code boom' }

        InModuleScope $script:moduleName {
            $Caught = $null
            try {
                Initialize-OERAuth -TenantId 'contoso' -AuthMethod 'DeviceCode' 6>$null
            } catch {
                $Caught = $PSItem
            }
            $Caught | Should -Not -BeNullOrEmpty
            $Caught.FullyQualifiedErrorId | Should -Match 'GraphTokenAcquisitionFailed'
        }
    }

    It 'surfaces a device code raised by the ARM acquisition too' {
        # On the device-code path the ARM acquisition is expected to raise a device code of its own:
        # the Graph call passes a client id and the ARM call passes none, so AzAuth rebuilds its
        # credential for the ARM call (measured offline; the second device code itself has not yet
        # been observed live). -ForceRefresh keeps -Force on the splat, and an -IncludeARM call made
        # when only the Graph token was cached runs the ARM acquisition alone. Every one of these
        # shapes can raise a real device code, and an invisible one there fails in exactly the same way.
        Mock -ModuleName $script:moduleName Get-AzToken {
            param($ClientId, $ClientSecret, $Resource, $Tenant, $ErrorAction, $Interactive,
                  $DeviceCode, $ManagedIdentity, $ClientCertificate, $ClientCertificatePath,
                  $Scope, $Force, $Claim)
            if ($Resource -match 'management') {
                # Module-qualified, for the reason given in 'leaves every other credential type calling
                # Get-AzToken with no pipeline in between'.
                Microsoft.PowerShell.Utility\Write-Warning 'To sign in, use a web browser to open the page https://microsoft.com/devicelogin and enter the code ARMCODE99 to authenticate.'
            }
            [pscustomobject]@{ Token = 'fake'; ExpiresOn = [DateTimeOffset]::UtcNow.AddHours(1); Identity = 'admin@contoso.com'; TenantId = 'contoso' }
        }

        $Captured = InModuleScope $script:moduleName {
            $InfoVar = $null
            Initialize-OERAuth -TenantId 'contoso' -AuthMethod 'DeviceCode' -IncludeARM `
                -InformationVariable InfoVar -WarningAction SilentlyContinue 6>$null
            @($InfoVar | ForEach-Object { [string]$_.MessageData })
        }

        ($Captured -join "`n") | Should -Match 'ARMCODE99'
    }
}

Describe 'Initialize-OERAuth forces every device code sign-in (A17, BL-112)' {
    # AzAuth keeps the device code credential it built for the whole process and reuses it for the next
    # device code request with the same client id, and a reused device code credential never returns:
    # GetAzToken.EndProcessing waits on a queue that only a NEW credential's callback completes
    # (DECOMPILED, AzAuth 2.10.0; MEASURED live 2026-09-16 for a tenant switch). -Force makes AzAuth clear
    # that credential and build a new one, which prints a new code. So every device code token request
    # carries Force (decision A17): the Microsoft Graph and the Azure Resource Manager token, in
    # Connect-OER, at a command's start near expiry, on an Azure Resource Manager token acquired on its
    # own, under -ForceRefresh and -ClaimsChallenge, and after Disconnect-OER. Every other sign-in type
    # keeps Force for -ForceRefresh and a cloud switch only, and a device code session whose tokens are
    # still valid still answers from the cache with no token request at all.
    #
    # Every assertion counts the token requests exactly, Microsoft Graph and Azure Resource Manager apart,
    # so a "without Force" can never pass on a request that was not made. The tenant is an invented GUID,
    # so no domain lookup runs.
    BeforeAll {
        $script:A17Tenant = '33333333-3333-3333-3333-333333333333'
        $script:A17ClientId = '55555555-5555-5555-5555-555555555555'
        $script:A17Claims = '{"access_token":{"acrs":{"essential":true,"value":"c1"}}}'

        # The capturing Get-AzToken. Its param() block lists every parameter the module passes, since a
        # mock body without one sees an empty $PSBoundParameters. Each request is recorded as the resource
        # it asked for and the parameter names it bound, and answered with a token issued for the tenant
        # it named.
        $script:A17TokenMock = {
            param($ClientId, $ClientSecret, $Resource, $Tenant, $ErrorAction, $WarningAction, $Interactive,
                  $DeviceCode, $ManagedIdentity, $ClientCertificate, $ClientCertificatePath,
                  $Scope, $Force, $Claim)
            $script:A17Calls.Add([pscustomobject]@{ Resource = $Resource; Keys = @($PSBoundParameters.Keys) })
            [pscustomobject]@{
                Token     = 'NOT-A-REAL-TOKEN-a17'
                ExpiresOn = [DateTimeOffset]::UtcNow.AddHours(1)
                Identity  = 'admin@contoso.com'
                TenantId  = $Tenant
            }
        }

        # Calls Initialize-OERAuth from a script block in the module scope, as the other Describes do.
        function script:Invoke-A17SignIn {
            param([hashtable]$Parameters)
            InModuleScope $script:moduleName -Parameters @{ P = $Parameters } {
                param($P)
                Initialize-OERAuth @P
            }
        }

        # Moves the cached tokens' expiry, as time passing would.
        function script:Set-A17Expiry {
            param([int]$GraphMinutes, [int]$ArmMinutes)
            InModuleScope $script:moduleName -Parameters @{ G = $GraphMinutes; A = $ArmMinutes } {
                param($G, $A)
                $script:_OERAuthState.GraphTokenExpiry = [DateTime]::UtcNow.AddMinutes($G)
                $script:_OERAuthState.ArmTokenExpiry = [DateTime]::UtcNow.AddMinutes($A)
            }
        }

        # One sign-in type with its credential named explicitly: for Initialize-OERAuth (-AuthMethod) or
        # for Connect-OER (its parameter set). An inherited app-only identity cannot renew, so every call
        # names its credential again.
        function script:Get-A17SignIn {
            param([string]$Method, [switch]$ForConnectOER)
            $P = @{}
            if (-not $ForConnectOER) { $P.AuthMethod = $Method }
            switch ($Method) {
                'Interactive' { if ($ForConnectOER) { $P.Interactive = $true } }
                'ManagedIdentity' { if ($ForConnectOER) { $P.ManagedIdentity = $true } }
                'ClientSecret' {
                    $P.ClientId = $script:A17ClientId
                    $P.ClientSecret = ConvertTo-SecureString 'not-a-real-secret' -AsPlainText -Force
                }
                'ClientCertificate' {
                    $P.ClientId = $script:A17ClientId
                    $P.CertificatePath = 'oer-a17-not-a-real-certificate.pfx'
                }
            }
            $P
        }

        # The recorded requests for one resource.
        function script:Get-A17Call {
            param([ValidateSet('Graph', 'Arm')][string]$Kind)
            [string]$Pattern = if ($Kind -eq 'Graph') { '*graph*' } else { '*management*' }
            @($script:A17Calls | Where-Object { [string]$_.Resource -like $Pattern })
        }

        # Exactly $Graph Microsoft Graph and $Arm Azure Resource Manager token requests and no other, each
        # with Force when $Force is $true and without it when $Force is $false, and each carrying every
        # parameter named in $Key. The counts come first, so a missing Force can never pass on a request
        # that was not made, and Graph is checked before ARM, so a failure names the resource it is about.
        function script:Assert-A17TokenCall {
            param([int]$Graph, [int]$Arm, [bool]$Force, [string[]]$Key = @())
            $GraphCalls = @(Get-A17Call -Kind Graph)
            $ArmCalls = @(Get-A17Call -Kind Arm)
            $script:A17Calls.Count | Should -Be ($Graph + $Arm) -Because 'every token request is recorded, each for Microsoft Graph or Azure Resource Manager'
            $GraphCalls.Count | Should -Be $Graph -Because 'the Microsoft Graph token requests are counted exactly'
            $ArmCalls.Count | Should -Be $Arm -Because 'the Azure Resource Manager token requests are counted exactly'
            [string]$Expected = if ($Force) { 'carries' } else { 'does not carry' }
            foreach ($Call in $GraphCalls) {
                ($Call.Keys -contains 'Force') | Should -Be $Force -Because "the Microsoft Graph token request $Expected Force"
                foreach ($Name in $Key) {
                    ($Call.Keys -contains $Name) | Should -BeTrue -Because "the Microsoft Graph token request carries $Name"
                }
            }
            foreach ($Call in $ArmCalls) {
                ($Call.Keys -contains 'Force') | Should -Be $Force -Because "the Azure Resource Manager token request $Expected Force"
                foreach ($Name in $Key) {
                    ($Call.Keys -contains $Name) | Should -BeTrue -Because "the Azure Resource Manager token request carries $Name"
                }
            }
        }
    }

    BeforeEach {
        InModuleScope $script:moduleName {
            $script:_OERAuthState = $null
            $script:_OERSessionUncertain = $null
            $script:_OERLastAuthorityHost = $null
            $script:_OERLastTokenRequest = $null
            $script:_OERInteractiveCredential = $null
        }
        $script:A17Calls = [System.Collections.Generic.List[object]]::new()
        # BL-12: every tenant here is a GUID, so no lookup runs; the mock keeps one off the network if it did.
        Mock -ModuleName $script:moduleName Resolve-OERTenantDomain { '33333333-3333-3333-3333-333333333333' }
        Mock -ModuleName $script:moduleName Connect-MgGraph { }
        # Disconnect-OER calls it for the module's own Graph SDK session, and the transport tripwire
        # refuses a real one.
        Mock -ModuleName $script:moduleName Disconnect-MgGraph { }
    }

    Context 'a device code sign-in' {
        BeforeEach {
            Mock -ModuleName $script:moduleName Get-AzToken -MockWith $script:A17TokenMock
        }

        It 'D1: Connect-OER -DeviceCode -IncludeARM sends the Microsoft Graph and the Azure Resource Manager token request with Force' {
            Connect-OER -TenantId $script:A17Tenant -DeviceCode -IncludeARM

            Assert-A17TokenCall -Graph 1 -Arm 1 -Force $true -Key 'DeviceCode'
        }

        It 'D1b: Connect-OER -DeviceCode without -IncludeARM sends one Microsoft Graph token request, with Force' {
            Connect-OER -TenantId $script:A17Tenant -DeviceCode

            Assert-A17TokenCall -Graph 1 -Arm 0 -Force $true -Key 'DeviceCode'
        }

        It 'D2: a command that starts within five minutes of expiry and inherits the session renews both tokens with Force' {
            Invoke-A17SignIn @{ TenantId = $script:A17Tenant; AuthMethod = 'DeviceCode'; IncludeARM = $true }
            Set-A17Expiry -GraphMinutes 2 -ArmMinutes 2
            $script:A17Calls.Clear()

            # No -TenantId and no -AuthMethod: inherited from the session, as every cmdlet does.
            Invoke-A17SignIn @{ IncludeARM = $true }

            Assert-A17TokenCall -Graph 1 -Arm 1 -Force $true -Key 'DeviceCode'
        }

        It 'D2b: a public cmdlet that starts within five minutes of expiry (Get-OERSubscription) renews both tokens with Force' {
            Mock -ModuleName $script:moduleName Invoke-OERArmRequest { @{ value = @() } }
            Invoke-A17SignIn @{ TenantId = $script:A17Tenant; AuthMethod = 'DeviceCode'; IncludeARM = $true }
            Set-A17Expiry -GraphMinutes 2 -ArmMinutes 2
            $script:A17Calls.Clear()

            $Subscriptions = @(Get-OERSubscription)

            $Subscriptions.Count | Should -Be 0
            # The cmdlet got past its sign-in and sent its one request.
            Should -Invoke -ModuleName $script:moduleName Invoke-OERArmRequest -Times 1 -Exactly
            Assert-A17TokenCall -Graph 1 -Arm 1 -Force $true -Key 'DeviceCode'
        }

        It 'D3: an Azure Resource Manager token acquired beside a cached Microsoft Graph token is requested with Force' {
            Invoke-A17SignIn @{ TenantId = $script:A17Tenant; AuthMethod = 'DeviceCode'; IncludeARM = $true }
            Set-A17Expiry -GraphMinutes 60 -ArmMinutes 2
            $script:A17Calls.Clear()

            Invoke-A17SignIn @{ IncludeARM = $true }

            Assert-A17TokenCall -Graph 0 -Arm 1 -Force $true -Key 'DeviceCode'
        }

        It 'D4: -ForceRefresh -IncludeARM on a device code session sends both token requests with Force' {
            Invoke-A17SignIn @{ TenantId = $script:A17Tenant; AuthMethod = 'DeviceCode'; IncludeARM = $true }
            $script:A17Calls.Clear()

            Invoke-A17SignIn @{ TenantId = $script:A17Tenant; AuthMethod = 'DeviceCode'; IncludeARM = $true; ForceRefresh = $true }

            Assert-A17TokenCall -Graph 1 -Arm 1 -Force $true -Key 'DeviceCode'
        }

        It 'D5: a claims challenge on a device code session sends one Microsoft Graph token request with Force and the claims' {
            Invoke-A17SignIn @{ TenantId = $script:A17Tenant; AuthMethod = 'DeviceCode' }
            $script:A17Calls.Clear()

            Invoke-A17SignIn @{ TenantId = $script:A17Tenant; AuthMethod = 'DeviceCode'; ClaimsChallenge = $script:A17Claims }

            Assert-A17TokenCall -Graph 1 -Arm 0 -Force $true -Key 'DeviceCode', 'Claim'
        }

        It 'D6: Connect-OER -DeviceCode after Disconnect-OER sends both token requests with Force' {
            Connect-OER -TenantId $script:A17Tenant -DeviceCode -IncludeARM
            Disconnect-OER -Confirm:$false
            # Disconnect-OER really ran: the module's own Graph SDK session was ended and its state cleared.
            Should -Invoke -ModuleName $script:moduleName Disconnect-MgGraph -Times 1 -Exactly
            (InModuleScope $script:moduleName { $null -eq $script:_OERAuthState }) | Should -BeTrue
            $script:A17Calls.Clear()

            Connect-OER -TenantId $script:A17Tenant -DeviceCode -IncludeARM

            Assert-A17TokenCall -Graph 1 -Arm 1 -Force $true -Key 'DeviceCode'
        }

        It 'D7: a device code session whose tokens are still valid answers from the cache, with no token request' {
            Invoke-A17SignIn @{ TenantId = $script:A17Tenant; AuthMethod = 'DeviceCode'; IncludeARM = $true }
            $AfterFirst = $script:A17Calls.Count

            Invoke-A17SignIn @{ TenantId = $script:A17Tenant; AuthMethod = 'DeviceCode'; IncludeARM = $true }

            # The first sign-in's Microsoft Graph and Azure Resource Manager requests, and none for the second.
            $AfterFirst | Should -Be 2
            $script:A17Calls.Count | Should -Be 2 -Because 'a device code session whose tokens are still valid answers from the cache'
            @(Get-A17Call -Kind Graph).Count | Should -Be 1
            @(Get-A17Call -Kind Arm).Count | Should -Be 1
        }
    }

    Context 'every other sign-in type' {
        BeforeEach {
            Mock -ModuleName $script:moduleName Get-AzToken -MockWith $script:A17TokenMock
        }

        It 'N1: the first <Method> sign-in with -IncludeARM sends both token requests without Force' -ForEach @(
            @{ Method = 'Interactive' }
            @{ Method = 'ManagedIdentity' }
            @{ Method = 'ClientSecret' }
            @{ Method = 'ClientCertificate' }
        ) {
            $SignIn = Get-A17SignIn -Method $Method

            Invoke-A17SignIn (@{ TenantId = $script:A17Tenant; IncludeARM = $true } + $SignIn)

            Assert-A17TokenCall -Graph 1 -Arm 1 -Force $false
        }

        It 'N2: renewing the <Method> session at a command''s start sends both token requests without Force' -ForEach @(
            @{ Method = 'Interactive' }
            @{ Method = 'ManagedIdentity' }
            @{ Method = 'ClientSecret' }
            @{ Method = 'ClientCertificate' }
        ) {
            $SignIn = Get-A17SignIn -Method $Method
            Invoke-A17SignIn (@{ TenantId = $script:A17Tenant; IncludeARM = $true } + $SignIn)
            Set-A17Expiry -GraphMinutes 2 -ArmMinutes 2
            $script:A17Calls.Clear()

            Invoke-A17SignIn (@{ TenantId = $script:A17Tenant; IncludeARM = $true } + $SignIn)

            Assert-A17TokenCall -Graph 1 -Arm 1 -Force $false
        }

        It 'N3: a claims challenge on the <Method> session sends one Microsoft Graph token request with the claims and without Force' -ForEach @(
            @{ Method = 'Interactive' }
            @{ Method = 'ManagedIdentity' }
            @{ Method = 'ClientSecret' }
            @{ Method = 'ClientCertificate' }
        ) {
            $SignIn = Get-A17SignIn -Method $Method
            Invoke-A17SignIn (@{ TenantId = $script:A17Tenant } + $SignIn)
            $script:A17Calls.Clear()

            Invoke-A17SignIn (@{ TenantId = $script:A17Tenant; ClaimsChallenge = $script:A17Claims } + $SignIn)

            Assert-A17TokenCall -Graph 1 -Arm 0 -Force $false -Key 'Claim'
        }

        It 'N4: Connect-OER with <Method> after Disconnect-OER sends both token requests without Force' -ForEach @(
            @{ Method = 'Interactive' }
            @{ Method = 'ManagedIdentity' }
            @{ Method = 'ClientSecret' }
            @{ Method = 'ClientCertificate' }
        ) {
            $Connect = Get-A17SignIn -Method $Method -ForConnectOER
            Connect-OER -TenantId $script:A17Tenant -IncludeARM @Connect
            Disconnect-OER -Confirm:$false
            Should -Invoke -ModuleName $script:moduleName Disconnect-MgGraph -Times 1 -Exactly
            (InModuleScope $script:moduleName { $null -eq $script:_OERAuthState }) | Should -BeTrue
            $script:A17Calls.Clear()

            Connect-OER -TenantId $script:A17Tenant -IncludeARM @Connect

            Assert-A17TokenCall -Graph 1 -Arm 1 -Force $false
        }
    }

    Context 'the device code with Force on' {
        It 'D8: a near-expiry renewal with -IncludeARM shows both device codes on the information stream under silenced warnings, with Force bound on both requests' {
            # The pattern of 'surfaces the device code on the information stream even when warnings are
            # silenced' above, and for its reason: a Pester mock body reads $WarningPreference from the
            # global scope only, so only a real advanced function in the module scope drops a warning
            # when warnings are silenced and keeps it under the -WarningAction Continue the module passes.
            # The stub records whether Force was bound and warns with a code per resource. Nothing
            # authenticates: it returns a fabricated token and never loads or calls AzAuth.
            $Captured = InModuleScope $script:moduleName -Parameters @{ T = $script:A17Tenant } {
                param($T)
                function script:Get-AzToken {
                    [CmdletBinding()]
                    param(
                        [string]$Resource, [string]$Tenant, [string]$ClientId, $ClientSecret,
                        [switch]$Interactive, [switch]$DeviceCode, [switch]$ManagedIdentity,
                        $ClientCertificate, [string]$ClientCertificatePath, [string[]]$Scope,
                        [switch]$Force, [string]$Claim
                    )
                    [string]$Code = if ($Resource -like '*management*') { 'A17ARMCODE' } else { 'A17GRAPHCODE' }
                    $script:A17StubCalls.Add([pscustomobject]@{ Resource = $Resource; Force = $Force.IsPresent })
                    Write-Warning "To sign in, use a web browser to open the page https://microsoft.com/devicelogin and enter the code $Code to authenticate."
                    [pscustomobject]@{ Token = 'NOT-A-REAL-TOKEN-a17'; ExpiresOn = [DateTimeOffset]::UtcNow.AddHours(1); Identity = 'admin@contoso.com'; TenantId = $Tenant }
                }
                $script:A17StubCalls = [System.Collections.Generic.List[object]]::new()
                try {
                    Initialize-OERAuth -TenantId $T -AuthMethod 'DeviceCode' -IncludeARM 6>$null
                    $script:_OERAuthState.GraphTokenExpiry = [DateTime]::UtcNow.AddMinutes(2)
                    $script:_OERAuthState.ArmTokenExpiry = [DateTime]::UtcNow.AddMinutes(2)
                    $script:A17StubCalls.Clear()

                    $InfoVar = $null
                    $WarnVar = $null
                    # The automation host: warnings silenced at the scope every callee resolves through,
                    # restored in a finally.
                    $PreviousWarningPreference = $global:WarningPreference
                    $global:WarningPreference = 'SilentlyContinue'
                    try {
                        # A command's start near expiry, inheriting the device code session.
                        Initialize-OERAuth -IncludeARM -InformationVariable InfoVar -WarningVariable WarnVar 6>$null
                    } finally {
                        $global:WarningPreference = $PreviousWarningPreference
                    }
                    [pscustomobject]@{
                        Information = @($InfoVar | ForEach-Object { [string]$_.MessageData })
                        Warning     = @($WarnVar | ForEach-Object { [string]$_.Message })
                        Calls       = @($script:A17StubCalls)
                    }
                } finally {
                    # Unqualified, from the same InModuleScope block, as above: removes the stub, the
                    # nearest definition, and never the tripwire's global replacement.
                    Remove-Item -Path 'function:Get-AzToken' -ErrorAction SilentlyContinue
                    Remove-Variable -Name A17StubCalls -Scope Script -ErrorAction SilentlyContinue
                }
            }

            $Captured.Calls.Count | Should -Be 2 -Because 'the renewal requests the Microsoft Graph and the Azure Resource Manager token'
            @($Captured.Calls | Where-Object { $_.Resource -like '*graph*' }).Count | Should -Be 1
            @($Captured.Calls | Where-Object { $_.Resource -like '*management*' }).Count | Should -Be 1
            foreach ($Call in $Captured.Calls) {
                $Call.Force | Should -BeTrue -Because "the device code token request for '$($Call.Resource)' builds a new credential"
            }
            ($Captured.Information -join "`n") | Should -Match 'A17GRAPHCODE'
            ($Captured.Information -join "`n") | Should -Match 'A17ARMCODE'
            ($Captured.Warning -join "`n") | Should -Not -Match 'A17GRAPHCODE|A17ARMCODE'
        }
    }
}

Describe 'Initialize-OERAuth granted-tenant guard' {
    BeforeEach {
        InModuleScope $script:moduleName {
            $script:_OERAuthState = $null
            $script:_OERSessionUncertain = $null
            $script:_OERLastAuthorityHost = $null
            $script:_OERLastTokenRequest = $null
            $script:_OERInteractiveCredential = $null
            # The resolver's process-wide cache, which one It below reaches through the real resolver.
            $script:_OERTenantDomainCache = $null
        }
    }

    # The defect this guard closes, in one sentence: the module stamped the state with the tenant the
    # caller ASKED for and never looked at the tenant the token was GRANTED for, so a session could be
    # labelled with a tenant its token does not belong to. A live device-code run proved it reachable
    # against a tenant that does not exist at all.
    #
    # The first five Its are a mutation set, not five independent checks. The two refusal Its (a GUID
    # and a domain) fail if the comparison is forced always-false (or deleted outright); the two match
    # Its and the 'organizations' It each fail if it is forced always-true. Neither mutation can pass
    # the whole block. The domain Its compare with the tenant ID the domain resolves to (BL-12): a
    # comparison with the tenant as NAMED fails the domain refusal It, since a domain is never a GUID.
    It 'refuses a Graph token issued for a different GUID tenant than the one requested' {
        Mock -ModuleName $script:moduleName Get-AzToken {
            [pscustomobject]@{
                Token     = 'fake-graph-token'
                ExpiresOn = [DateTimeOffset]::UtcNow.AddHours(1)
                Identity  = 'admin@contoso.com'
                TenantId  = '22222222-2222-2222-2222-222222222222'
            }
        }
        Mock -ModuleName $script:moduleName Connect-MgGraph { }

        InModuleScope $script:moduleName {
            $Caught = $null
            try {
                Initialize-OERAuth -TenantId '11111111-1111-1111-1111-111111111111' -AuthMethod 'Interactive'
            } catch {
                $Caught = $PSItem
            }

            $Caught | Should -Not -BeNullOrEmpty -Because 'a token minted for another tenant must terminate rather than warn'
            $Caught.FullyQualifiedErrorId | Should -Match 'TenantMismatch'
            # Both tenants are named, so an operator can tell which account actually answered.
            $Caught.Exception.Message | Should -Match '22222222-2222-2222-2222-222222222222'
            $Caught.Exception.Message | Should -Match '11111111-1111-1111-1111-111111111111'

            # No usable session left behind. The guard sits above the state rebuild for exactly this,
            # so the refused token leaves nothing a later cmdlet could reuse.
            $script:_OERAuthState | Should -BeNullOrEmpty -Because 'a refused token must leave no cached session'
        }

        # And it never reached the Graph SDK either: the guard is above Connect-MgGraph, so the
        # wrong-tenant token is not wired into a live SDK session the state no longer describes.
        Should -Invoke -ModuleName $script:moduleName Connect-MgGraph -Times 0 -Exactly
    }

    It 'accepts a Graph token whose GUID tenant matches the requested one, and records it' {
        # Hex letters in upper case on the requested side and lower case on the granted side prove
        # the comparison is case-insensitive, which is what PowerShell -ne on strings gives. Entra
        # returns lower case; an operator may paste either.
        Mock -ModuleName $script:moduleName Get-AzToken {
            [pscustomobject]@{
                Token     = 'fake-graph-token'
                ExpiresOn = [DateTimeOffset]::UtcNow.AddHours(1)
                Identity  = 'admin@contoso.com'
                TenantId  = 'aaaaaaaa-1111-1111-1111-111111111111'
            }
        }
        Mock -ModuleName $script:moduleName Connect-MgGraph { }

        InModuleScope $script:moduleName {
            Initialize-OERAuth -TenantId 'AAAAAAAA-1111-1111-1111-111111111111' -AuthMethod 'Interactive'

            $script:_OERAuthState | Should -Not -BeNullOrEmpty
            $script:_OERAuthState.TenantId | Should -Be 'AAAAAAAA-1111-1111-1111-111111111111'
            $script:_OERAuthState.TokenTenantId | Should -Be 'aaaaaaaa-1111-1111-1111-111111111111'
        }
        Should -Invoke -ModuleName $script:moduleName Connect-MgGraph -Times 1 -Exactly
    }

    It 'refuses a Graph token issued for another tenant than the one a domain resolves to' {
        # The failure a domain used to hide: the domain names one tenant, the token comes back from
        # another -- a device code completed by an account of another tenant, a managed identity of
        # another tenant, or a reused client secret credential. The domain is resolved before the token
        # is requested (BL-12), so the comparison is GUID with GUID.
        Mock -ModuleName $script:moduleName Get-AzToken {
            [pscustomobject]@{
                Token     = 'fake-graph-token'
                ExpiresOn = [DateTimeOffset]::UtcNow.AddHours(1)
                Identity  = 'admin@contoso.com'
                TenantId  = '22222222-2222-2222-2222-222222222222'
            }
        }
        Mock -ModuleName $script:moduleName Connect-MgGraph { }
        Mock -ModuleName $script:moduleName Resolve-OERTenantDomain { '11111111-1111-1111-1111-111111111111' }

        InModuleScope $script:moduleName {
            $Caught = $null
            try {
                Initialize-OERAuth -TenantId 'contoso.onmicrosoft.com' -AuthMethod 'Interactive'
            } catch {
                $Caught = $PSItem
            }

            $Caught | Should -Not -BeNullOrEmpty -Because 'a token minted for another tenant than the domain names must terminate'
            $Caught.FullyQualifiedErrorId | Should -BeExactly 'TenantMismatch,Initialize-OERAuth'
            $Caught.TargetObject | Should -BeExactly 'contoso.onmicrosoft.com'
            # The domain as named, the tenant ID it resolved to, and the tenant that actually answered.
            $Caught.Exception.Message | Should -Match ([regex]::Escape(
                "not for the requested tenant 'contoso.onmicrosoft.com' (tenant ID '11111111-1111-1111-1111-111111111111')"))
            $Caught.Exception.Message | Should -Match ([regex]::Escape(
                "The Microsoft Graph token was issued for tenant '22222222-2222-2222-2222-222222222222'"))

            $script:_OERAuthState | Should -BeNullOrEmpty -Because 'a refused token must leave no cached session'
        }

        # Positive proof that the domain was resolved, then the token refused before Connect-MgGraph.
        Should -Invoke -ModuleName $script:moduleName Resolve-OERTenantDomain -Times 1 -Exactly
        Should -Invoke -ModuleName $script:moduleName Get-AzToken -Times 1 -Exactly
        Should -Invoke -ModuleName $script:moduleName Connect-MgGraph -Times 0 -Exactly
    }

    It 'accepts a Graph token issued for the tenant a domain resolves to, and records both' {
        # This is the case that would break most real sign-ins if the comparison were unconditional or
        # compared the tenant as named: a domain can never equal the GUID a token carries. TenantId
        # keeps the domain the caller asked for, since the cache-key predicates compare it, and
        # TokenTenantId records the GUID the token was issued for.
        Mock -ModuleName $script:moduleName Get-AzToken {
            [pscustomobject]@{
                Token     = 'fake-graph-token'
                ExpiresOn = [DateTimeOffset]::UtcNow.AddHours(1)
                Identity  = 'admin@contoso.com'
                TenantId  = '22222222-2222-2222-2222-222222222222'
            }
        }
        Mock -ModuleName $script:moduleName Connect-MgGraph { }
        Mock -ModuleName $script:moduleName Resolve-OERTenantDomain { '22222222-2222-2222-2222-222222222222' }

        InModuleScope $script:moduleName {
            Initialize-OERAuth -TenantId 'contoso.onmicrosoft.com' -AuthMethod 'Interactive'

            $script:_OERAuthState.TenantId | Should -BeExactly 'contoso.onmicrosoft.com'
            $script:_OERAuthState.TokenTenantId | Should -BeExactly '22222222-2222-2222-2222-222222222222'
        }
        Should -Invoke -ModuleName $script:moduleName Resolve-OERTenantDomain -Times 1 -Exactly
        Should -Invoke -ModuleName $script:moduleName Connect-MgGraph -Times 1 -Exactly
    }

    It 'never fires for the tenant-agnostic organizations default' {
        # 'organizations' names no tenant, so it is neither looked up nor compared: the tenant ID the
        # comparison expects is empty for it, and a term of its own excludes it. This It falsifies that
        # term: with the term gone, the token's GUID would be compared with an empty tenant ID and
        # refused.
        Mock -ModuleName $script:moduleName Get-AzToken {
            [pscustomobject]@{
                Token     = 'fake-graph-token'
                ExpiresOn = [DateTimeOffset]::UtcNow.AddHours(1)
                Identity  = 'admin@contoso.com'
                TenantId  = '22222222-2222-2222-2222-222222222222'
            }
        }
        Mock -ModuleName $script:moduleName Connect-MgGraph { }

        InModuleScope $script:moduleName {
            Initialize-OERAuth -AuthMethod 'Interactive'

            $script:_OERAuthState.TenantId | Should -Be 'organizations'
            $script:_OERAuthState.TokenTenantId | Should -Be '22222222-2222-2222-2222-222222222222'
        }
        Should -Invoke -ModuleName $script:moduleName Connect-MgGraph -Times 1 -Exactly
    }

    It 'refuses an ARM token issued for a different GUID tenant, caching nothing' {
        # The ARM half is not redundant with the Graph half: when the Graph token is already cached
        # the ARM branch runs ALONE, which makes it the only place a wrong-tenant ARM token could be
        # caught. The first call below establishes that cached Graph session; the second runs ARM by
        # itself.
        Mock -ModuleName $script:moduleName Get-AzToken {
            param($ClientId, $ClientSecret, $Resource, $Tenant, $ErrorAction, $Interactive,
                  $DeviceCode, $ManagedIdentity, $ClientCertificate, $ClientCertificatePath,
                  $Scope, $Force, $Claim)
            $Granted = if ($Resource -match 'management') {
                '22222222-2222-2222-2222-222222222222'
            }
            else {
                '11111111-1111-1111-1111-111111111111'
            }
            [pscustomobject]@{
                Token     = 'fake-token'
                ExpiresOn = [DateTimeOffset]::UtcNow.AddHours(1)
                Identity  = 'admin@contoso.com'
                TenantId  = $Granted
            }
        }
        Mock -ModuleName $script:moduleName Connect-MgGraph { }

        InModuleScope $script:moduleName {
            Initialize-OERAuth -TenantId '11111111-1111-1111-1111-111111111111' -AuthMethod 'Interactive'
            $script:_OERAuthState.TokenTenantId | Should -Be '11111111-1111-1111-1111-111111111111'

            $Caught = $null
            try {
                Initialize-OERAuth -TenantId '11111111-1111-1111-1111-111111111111' -AuthMethod 'Interactive' -IncludeARM
            } catch {
                $Caught = $PSItem
            }

            $Caught | Should -Not -BeNullOrEmpty -Because 'an ARM token for another tenant must terminate rather than be cached'
            $Caught.FullyQualifiedErrorId | Should -Match 'TenantMismatch'
            $Caught.Exception.Message | Should -Match 'Azure Resource Manager'

            # The refused ARM token is never cached, so Invoke-OERArmRequest has nothing to send.
            $script:_OERAuthState.ArmToken | Should -BeNullOrEmpty
            $script:_OERAuthState.ArmTokenTenantId | Should -BeNullOrEmpty
            # The Graph half of the session, which WAS verified, is untouched.
            $script:_OERAuthState.TenantId | Should -Be '11111111-1111-1111-1111-111111111111'
        }
    }

    It 'refuses an ARM token issued for another tenant than the one a domain resolves to, caching nothing' {
        # Review Focus 3: the Graph token is cached for the domain and the ARM token is acquired alone.
        # That ARM-only sign-in goes past the cached return, so it resolves the domain again and
        # compares the ARM token with the resolved tenant ID, not with the domain.
        Mock -ModuleName $script:moduleName Get-AzToken {
            param($ClientId, $ClientSecret, $Resource, $Tenant, $ErrorAction, $Interactive,
                  $DeviceCode, $ManagedIdentity, $ClientCertificate, $ClientCertificatePath,
                  $Scope, $Force, $Claim)
            $Granted = if ($Resource -match 'management') {
                '22222222-2222-2222-2222-222222222222'
            }
            else {
                '11111111-1111-1111-1111-111111111111'
            }
            [pscustomobject]@{
                Token     = 'fake-token'
                ExpiresOn = [DateTimeOffset]::UtcNow.AddHours(1)
                Identity  = 'admin@contoso.com'
                TenantId  = $Granted
            }
        }
        Mock -ModuleName $script:moduleName Connect-MgGraph { }
        Mock -ModuleName $script:moduleName Resolve-OERTenantDomain { '11111111-1111-1111-1111-111111111111' }

        InModuleScope $script:moduleName {
            Initialize-OERAuth -TenantId 'contoso.onmicrosoft.com' -AuthMethod 'Interactive'
            $script:_OERAuthState.TokenTenantId | Should -BeExactly '11111111-1111-1111-1111-111111111111'

            $Caught = $null
            try {
                Initialize-OERAuth -TenantId 'contoso.onmicrosoft.com' -AuthMethod 'Interactive' -IncludeARM
            } catch {
                $Caught = $PSItem
            }

            $Caught | Should -Not -BeNullOrEmpty -Because 'an ARM token for another tenant than the domain names must terminate rather than be cached'
            $Caught.FullyQualifiedErrorId | Should -BeExactly 'TenantMismatch,Initialize-OERAuth'
            $Caught.Exception.Message | Should -Match ([regex]::Escape(
                "The Azure Resource Manager token was issued for tenant '22222222-2222-2222-2222-222222222222'"))
            $Caught.Exception.Message | Should -Match ([regex]::Escape(
                "for the requested tenant 'contoso.onmicrosoft.com' (tenant ID '11111111-1111-1111-1111-111111111111')"))

            # The refused ARM token is never cached, so Invoke-OERArmRequest has nothing to send.
            $script:_OERAuthState.ArmToken | Should -BeNullOrEmpty
            $script:_OERAuthState.ArmTokenTenantId | Should -BeNullOrEmpty
            # The Graph half of the session, which WAS verified, is untouched.
            $script:_OERAuthState.TenantId | Should -BeExactly 'contoso.onmicrosoft.com'
            $script:_OERAuthState.TokenTenantId | Should -BeExactly '11111111-1111-1111-1111-111111111111'
        }

        # The resolver was asked once per sign-in, and the ARM-only sign-in made exactly one token call,
        # for Azure Resource Manager: the Graph token came from the cache.
        Should -Invoke -ModuleName $script:moduleName Resolve-OERTenantDomain -Times 2 -Exactly
        Should -Invoke -ModuleName $script:moduleName Get-AzToken -Times 2 -Exactly
        Should -Invoke -ModuleName $script:moduleName Get-AzToken -Times 1 -Exactly -ParameterFilter {
            $Resource -match 'management'
        }
        Should -Invoke -ModuleName $script:moduleName Connect-MgGraph -Times 1 -Exactly
    }

    It 'sends one lookup for a domain named by two sign-ins, the second a cache hit inside the resolver' {
        # Review Focus 3, through the REAL resolver: the ARM-only sign-in asks the resolver again, and
        # the resolver answers it from its own cache, so the authority is asked once. The lookup itself
        # is mocked at Invoke-RestMethod; nothing leaves the process.
        Mock -ModuleName $script:moduleName Get-AzToken {
            param($ClientId, $ClientSecret, $Resource, $Tenant, $ErrorAction, $Interactive,
                  $DeviceCode, $ManagedIdentity, $ClientCertificate, $ClientCertificatePath,
                  $Scope, $Force, $Claim)
            $Granted = if ($Resource -match 'management') {
                '22222222-2222-2222-2222-222222222222'
            }
            else {
                '11111111-1111-1111-1111-111111111111'
            }
            [pscustomobject]@{
                Token     = 'fake-token'
                ExpiresOn = [DateTimeOffset]::UtcNow.AddHours(1)
                Identity  = 'admin@contoso.com'
                TenantId  = $Granted
            }
        }
        Mock -ModuleName $script:moduleName Connect-MgGraph { }
        Mock -ModuleName $script:moduleName Invoke-RestMethod {
            [pscustomobject]@{ issuer = 'https://login.microsoftonline.com/11111111-1111-1111-1111-111111111111/v2.0' }
        }

        InModuleScope $script:moduleName {
            Initialize-OERAuth -TenantId 'contoso.onmicrosoft.com' -AuthMethod 'Interactive'

            $Caught = $null
            try {
                Initialize-OERAuth -TenantId 'contoso.onmicrosoft.com' -AuthMethod 'Interactive' -IncludeARM
            } catch {
                $Caught = $PSItem
            }

            # The cached answer still refuses the ARM token: it is compared with the resolved tenant ID.
            $Caught.FullyQualifiedErrorId | Should -BeExactly 'TenantMismatch,Initialize-OERAuth'
            $script:_OERAuthState.ArmToken | Should -BeNullOrEmpty
        }

        Should -Invoke -ModuleName $script:moduleName Invoke-RestMethod -Times 1 -Exactly
        Should -Invoke -ModuleName $script:moduleName Get-AzToken -Times 1 -Exactly -ParameterFilter {
            $Resource -match 'management'
        }
    }

    It 'accepts a matching ARM token and records its granted tenant' {
        Mock -ModuleName $script:moduleName Get-AzToken {
            [pscustomobject]@{
                Token     = 'fake-token'
                ExpiresOn = [DateTimeOffset]::UtcNow.AddHours(1)
                Identity  = 'admin@contoso.com'
                TenantId  = '11111111-1111-1111-1111-111111111111'
            }
        }
        Mock -ModuleName $script:moduleName Connect-MgGraph { }

        InModuleScope $script:moduleName {
            Initialize-OERAuth -TenantId '11111111-1111-1111-1111-111111111111' -AuthMethod 'Interactive' -IncludeARM

            $script:_OERAuthState.ArmToken | Should -Not -BeNullOrEmpty
            $script:_OERAuthState.ArmTokenTenantId | Should -Be '11111111-1111-1111-1111-111111111111'
        }
    }

    It 'never fires on the ARM token for the tenant-agnostic organizations default' {
        # The ARM mirror of the 'organizations' It above: the ARM check carries its own term for the
        # empty tenant ID, and this It falsifies it -- with that term gone, the ARM token's GUID would
        # be compared with an empty tenant ID and refused.
        Mock -ModuleName $script:moduleName Get-AzToken {
            param($ClientId, $ClientSecret, $Resource, $Tenant, $ErrorAction, $Interactive,
                  $DeviceCode, $ManagedIdentity, $ClientCertificate, $ClientCertificatePath,
                  $Scope, $Force, $Claim)
            [pscustomobject]@{
                Token     = 'fake-token'
                ExpiresOn = [DateTimeOffset]::UtcNow.AddHours(1)
                Identity  = 'admin@contoso.com'
                TenantId  = '22222222-2222-2222-2222-222222222222'
            }
        }
        Mock -ModuleName $script:moduleName Connect-MgGraph { }

        InModuleScope $script:moduleName {
            Initialize-OERAuth -AuthMethod 'Interactive' -IncludeARM

            $script:_OERAuthState.TenantId | Should -Be 'organizations'
            $script:_OERAuthState.ArmToken | Should -Not -BeNullOrEmpty
            $script:_OERAuthState.ArmTokenTenantId | Should -Be '22222222-2222-2222-2222-222222222222'
        }
        # Positive proof that the ARM token was requested, and therefore checked.
        Should -Invoke -ModuleName $script:moduleName Get-AzToken -Times 1 -Exactly -ParameterFilter {
            $Resource -match 'management'
        }
    }

    # Final review M1 (Ruling F3): with no tenant named there is no tenant ID to compare the ARM token
    # with, and since BL-77 the sign-in identity's tenant term is the Graph token's tenant. An interactive
    # sign-in that names no tenant can be answered by two accounts -- the Graph prompt by one tenant's,
    # the ARM prompt by another's -- and the session would then act on two tenants under one identity,
    # with no supersession to see it. So the ARM token is compared with the Graph token of the same
    # session (TokenTenantId) when both are GUIDs. (a) and (c) fail with the comparison deleted; (b) and
    # the 'organizations' It above fail with it forced always-true; (d) states the limit.
    It 'F3 (a): refuses an ARM token issued for another tenant than the Graph token of the same sign-in, when no tenant is named' {
        Mock -ModuleName $script:moduleName Get-AzToken {
            param($ClientId, $ClientSecret, $Resource, $Tenant, $ErrorAction, $Interactive,
                  $DeviceCode, $ManagedIdentity, $ClientCertificate, $ClientCertificatePath,
                  $Scope, $Force, $Claim)
            $Granted = if ($Resource -match 'management') {
                '22222222-2222-2222-2222-222222222222'
            }
            else {
                '11111111-1111-1111-1111-111111111111'
            }
            [pscustomobject]@{
                Token     = 'fake-token'
                ExpiresOn = [DateTimeOffset]::UtcNow.AddHours(1)
                Identity  = 'admin@contoso.com'
                TenantId  = $Granted
            }
        }
        Mock -ModuleName $script:moduleName Connect-MgGraph { }

        InModuleScope $script:moduleName {
            $Caught = $null
            try {
                Initialize-OERAuth -AuthMethod 'Interactive' -IncludeARM
            } catch {
                $Caught = $PSItem
            }

            $Caught | Should -Not -BeNullOrEmpty -Because 'an ARM token from another tenant than the Graph token must terminate rather than be cached'
            $Caught.FullyQualifiedErrorId | Should -BeExactly 'TenantMismatch,Initialize-OERAuth'
            $Caught.CategoryInfo.Category | Should -Be 'AuthenticationError'
            $Caught.TargetObject | Should -BeExactly 'organizations'
            $Caught.Exception.Message | Should -Match ([regex]::Escape(
                "The Azure Resource Manager token was issued for tenant '22222222-2222-2222-2222-222222222222'"))
            $Caught.Exception.Message | Should -Match ([regex]::Escape(
                "the Microsoft Graph token of the same session was issued for tenant '11111111-1111-1111-1111-111111111111'"))

            # The refused ARM token is never cached, so Invoke-OERArmRequest has nothing to send.
            $script:_OERAuthState.ArmToken | Should -BeNullOrEmpty
            $script:_OERAuthState.ArmTokenTenantId | Should -BeNullOrEmpty
            # The Graph half of the session, which went the whole way, is kept.
            $script:_OERAuthState.TenantId | Should -BeExactly 'organizations'
            $script:_OERAuthState.TokenTenantId | Should -BeExactly '11111111-1111-1111-1111-111111111111'
        }
        Should -Invoke -ModuleName $script:moduleName Get-AzToken -Times 1 -Exactly -ParameterFilter {
            $Resource -match 'management'
        }
        Should -Invoke -ModuleName $script:moduleName Connect-MgGraph -Times 1 -Exactly
    }

    It 'F3 (b): accepts an ARM token issued for the tenant of the Graph token of the same sign-in, when no tenant is named' {
        Mock -ModuleName $script:moduleName Get-AzToken {
            param($ClientId, $ClientSecret, $Resource, $Tenant, $ErrorAction, $Interactive,
                  $DeviceCode, $ManagedIdentity, $ClientCertificate, $ClientCertificatePath,
                  $Scope, $Force, $Claim)
            [pscustomobject]@{
                Token     = 'fake-token'
                ExpiresOn = [DateTimeOffset]::UtcNow.AddHours(1)
                Identity  = 'admin@contoso.com'
                TenantId  = '11111111-1111-1111-1111-111111111111'
            }
        }
        Mock -ModuleName $script:moduleName Connect-MgGraph { }

        InModuleScope $script:moduleName {
            Initialize-OERAuth -AuthMethod 'Interactive' -IncludeARM

            $script:_OERAuthState.TenantId | Should -BeExactly 'organizations'
            $script:_OERAuthState.TokenTenantId | Should -BeExactly '11111111-1111-1111-1111-111111111111'
            $script:_OERAuthState.ArmToken | Should -Not -BeNullOrEmpty
            $script:_OERAuthState.ArmTokenTenantId | Should -BeExactly '11111111-1111-1111-1111-111111111111'
        }
        Should -Invoke -ModuleName $script:moduleName Get-AzToken -Times 1 -Exactly -ParameterFilter {
            $Resource -match 'management'
        }
    }

    It 'F3 (c): refuses an ARM-only acquisition on an organizations session whose cached Graph token is from another tenant' {
        # The ARM branch runs ALONE here: the Graph token is cached from the first call, so the
        # comparison reads the session's recorded Graph tenant, not a token acquired in the same call.
        Mock -ModuleName $script:moduleName Get-AzToken {
            param($ClientId, $ClientSecret, $Resource, $Tenant, $ErrorAction, $Interactive,
                  $DeviceCode, $ManagedIdentity, $ClientCertificate, $ClientCertificatePath,
                  $Scope, $Force, $Claim)
            $Granted = if ($Resource -match 'management') {
                '22222222-2222-2222-2222-222222222222'
            }
            else {
                '11111111-1111-1111-1111-111111111111'
            }
            [pscustomobject]@{
                Token     = 'fake-token'
                ExpiresOn = [DateTimeOffset]::UtcNow.AddHours(1)
                Identity  = 'admin@contoso.com'
                TenantId  = $Granted
            }
        }
        Mock -ModuleName $script:moduleName Connect-MgGraph { }

        InModuleScope $script:moduleName {
            Initialize-OERAuth -AuthMethod 'Interactive'
            $script:_OERAuthState.TenantId | Should -BeExactly 'organizations'
            $script:_OERAuthState.TokenTenantId | Should -BeExactly '11111111-1111-1111-1111-111111111111'

            $Caught = $null
            try {
                Initialize-OERAuth -IncludeARM
            } catch {
                $Caught = $PSItem
            }

            $Caught | Should -Not -BeNullOrEmpty -Because 'an ARM token from another tenant than the cached Graph token must terminate rather than be cached'
            $Caught.FullyQualifiedErrorId | Should -BeExactly 'TenantMismatch,Initialize-OERAuth'
            $Caught.Exception.Message | Should -Match ([regex]::Escape(
                "the Microsoft Graph token of the same session was issued for tenant '11111111-1111-1111-1111-111111111111'"))
            $script:_OERAuthState.ArmToken | Should -BeNullOrEmpty
            $script:_OERAuthState.ArmTokenTenantId | Should -BeNullOrEmpty
            $script:_OERAuthState.TokenTenantId | Should -BeExactly '11111111-1111-1111-1111-111111111111'
        }
        # One Graph token, from the first call, and the ARM-only acquisition's one ARM token.
        Should -Invoke -ModuleName $script:moduleName Get-AzToken -Times 2 -Exactly
        Should -Invoke -ModuleName $script:moduleName Get-AzToken -Times 1 -Exactly -ParameterFilter {
            $Resource -match 'management'
        }
        Should -Invoke -ModuleName $script:moduleName Connect-MgGraph -Times 1 -Exactly
    }

    It 'F3 (d): does not compare the two tokens when the <Side> token reports no GUID tenant and no tenant is named (the stated limit)' -ForEach @(
        @{ Side = 'Microsoft Graph'; GraphTenant = $null; ArmTenant = '22222222-2222-2222-2222-222222222222' }
        @{ Side = 'Azure Resource Manager'; GraphTenant = '11111111-1111-1111-1111-111111111111'; ArmTenant = $null }
    ) {
        # The limit, stated rather than implied: a token whose tenant AzAuth does not report as a GUID
        # (one without a tid claim) leaves nothing to compare, so the ARM token is accepted, exactly as a
        # named tenant's token without a GUID tenant is not compared.
        $script:F3GraphTenant = $GraphTenant
        $script:F3ArmTenant = $ArmTenant
        Mock -ModuleName $script:moduleName Get-AzToken {
            param($ClientId, $ClientSecret, $Resource, $Tenant, $ErrorAction, $Interactive,
                  $DeviceCode, $ManagedIdentity, $ClientCertificate, $ClientCertificatePath,
                  $Scope, $Force, $Claim)
            $Granted = if ($Resource -match 'management') { $script:F3ArmTenant } else { $script:F3GraphTenant }
            [pscustomobject]@{
                Token     = 'fake-token'
                ExpiresOn = [DateTimeOffset]::UtcNow.AddHours(1)
                Identity  = 'admin@contoso.com'
                TenantId  = $Granted
            }
        }
        Mock -ModuleName $script:moduleName Connect-MgGraph { }

        InModuleScope $script:moduleName -Parameters @{ GraphTenant = $GraphTenant; ArmTenant = $ArmTenant } {
            param($GraphTenant, $ArmTenant)
            Initialize-OERAuth -AuthMethod 'Interactive' -IncludeARM

            $script:_OERAuthState.TokenTenantId | Should -Be $GraphTenant
            $script:_OERAuthState.ArmToken | Should -Not -BeNullOrEmpty
            $script:_OERAuthState.ArmTokenTenantId | Should -Be $ArmTenant
        }
        Should -Invoke -ModuleName $script:moduleName Get-AzToken -Times 1 -Exactly -ParameterFilter {
            $Resource -match 'management'
        }
    }

    It 'F3 (e): compares a named tenant''s ARM token with the tenant named, never with the session''s Graph token' {
        # The new comparison's own scope: it applies only when no tenant is named. A state built by hand
        # whose Graph tenant differs from the tenant it names -- a shape no sign-in builds, since the Graph
        # token was compared with that tenant ID when the state was built -- isolates that term: with it
        # deleted, the ARM token below, issued for the tenant named, would be refused.
        Mock -ModuleName $script:moduleName Get-AzToken {
            param($ClientId, $ClientSecret, $Resource, $Tenant, $ErrorAction, $Interactive,
                  $DeviceCode, $ManagedIdentity, $ClientCertificate, $ClientCertificatePath,
                  $Scope, $Force, $Claim)
            [pscustomobject]@{
                Token     = 'fake-token'
                ExpiresOn = [DateTimeOffset]::UtcNow.AddHours(1)
                Identity  = 'admin@contoso.com'
                TenantId  = '11111111-1111-1111-1111-111111111111'
            }
        }
        Mock -ModuleName $script:moduleName Connect-MgGraph { }

        InModuleScope $script:moduleName {
            # No GraphSessionFingerprint key: a state this function did not build, compared with no
            # Graph SDK session, so the Graph token is a cache hit and the ARM branch runs alone.
            $script:_OERAuthState = @{
                TenantId         = '11111111-1111-1111-1111-111111111111'
                AuthMethod       = 'Interactive'
                ClientId         = ''
                Environment      = 'Global'
                GraphTokenExpiry = [DateTime]::UtcNow.AddHours(1)
                TokenTenantId    = '33333333-3333-3333-3333-333333333333'
            }

            Initialize-OERAuth -TenantId '11111111-1111-1111-1111-111111111111' -IncludeARM

            $script:_OERAuthState.ArmToken | Should -Not -BeNullOrEmpty
            $script:_OERAuthState.ArmTokenTenantId | Should -BeExactly '11111111-1111-1111-1111-111111111111'
        }
        Should -Invoke -ModuleName $script:moduleName Get-AzToken -Times 1 -Exactly -ParameterFilter {
            $Resource -match 'management'
        }
        Should -Invoke -ModuleName $script:moduleName Connect-MgGraph -Times 0
    }

    It 'drops a carried-forward ArmTokenTenantId when the tenant changes' {
        # The evidence field is carried on the SAME condition as the ARM token it describes. If it
        # outlived that token it would report the previous customer's tenant against a state that no
        # longer holds their token -- worse than recording nothing at all.
        Mock -ModuleName $script:moduleName Get-AzToken {
            [pscustomobject]@{
                Token     = 'fake-token'
                ExpiresOn = [DateTimeOffset]::UtcNow.AddHours(1)
                Identity  = 'admin@contoso.com'
                TenantId  = '11111111-1111-1111-1111-111111111111'
            }
        }
        Mock -ModuleName $script:moduleName Connect-MgGraph { }
        # BL-12: the domain is looked up before the token is requested; the mocked lookup answers with
        # the tenant the token above carries, so the guard accepts the token.
        Mock -ModuleName $script:moduleName Resolve-OERTenantDomain { '11111111-1111-1111-1111-111111111111' }

        InModuleScope $script:moduleName {
            Initialize-OERAuth -TenantId '11111111-1111-1111-1111-111111111111' -AuthMethod 'Interactive' -IncludeARM
            $script:_OERAuthState.ArmTokenTenantId | Should -Be '11111111-1111-1111-1111-111111111111'

            # Another tenant label, a domain: the cache-key predicates compare the label, so the
            # identity changed and the state is rebuilt without the ARM token.
            Initialize-OERAuth -TenantId 'other.onmicrosoft.com' -AuthMethod 'Interactive'
            $script:_OERAuthState.TenantId | Should -BeExactly 'other.onmicrosoft.com'
            $script:_OERAuthState.ArmToken | Should -BeNullOrEmpty
            $script:_OERAuthState.ArmTokenTenantId | Should -BeNullOrEmpty
        }
    }

    It 'writes no warning after a domain sign-in issued by the tenant the domain resolves to, whatever the previous session (<Case>)' -ForEach @(
        @{ Case = 'named by its tenant ID'; Previous = '11111111-1111-1111-1111-111111111111' }
        @{ Case = 'named no tenant'; Previous = '' }
        @{ Case = 'named by another of its domains'; Previous = 'fabrikam.onmicrosoft.com' }
    ) {
        # The shapes the retired post-call warning fired on: a previous session issued by tenant X, then
        # a sign-in naming a domain of X, issued by X. After the lookup that is a correct sign-in -- the
        # domain resolves to X and the token is X's -- so nothing is written. A token from another
        # tenant is refused instead (TenantMismatch, above).
        Mock -ModuleName $script:moduleName Get-AzToken {
            [pscustomobject]@{
                Token     = 'fake-graph-token'
                ExpiresOn = [DateTimeOffset]::UtcNow.AddHours(1)
                Identity  = 'admin@contoso.com'
                TenantId  = '11111111-1111-1111-1111-111111111111'
            }
        }
        Mock -ModuleName $script:moduleName Connect-MgGraph { }
        # Every domain here is a name of tenant X.
        Mock -ModuleName $script:moduleName Resolve-OERTenantDomain { '11111111-1111-1111-1111-111111111111' }

        # AZURE_AUTHORITY_HOST is process state: a non-commercial ambient value would add the ambient
        # authority warning to the capture below, so borrow it and hand it back.
        $AmbientAuthorityHost = [System.Environment]::GetEnvironmentVariable('AZURE_AUTHORITY_HOST')
        [System.Environment]::SetEnvironmentVariable('AZURE_AUTHORITY_HOST', [NullString]::Value)
        try {
            InModuleScope $script:moduleName -Parameters @{ Previous = $Previous } {
                param($Previous)
                $First = @{ AuthMethod = 'Interactive' }
                if ($Previous) { $First.TenantId = $Previous }
                Initialize-OERAuth @First
                $script:_OERAuthState.TokenTenantId | Should -BeExactly '11111111-1111-1111-1111-111111111111'

                $Warnings = 'not-run'
                Initialize-OERAuth -TenantId 'contoso.onmicrosoft.com' -AuthMethod 'Interactive' `
                    -WarningVariable Warnings -WarningAction SilentlyContinue

                # The call ran -- the sentinel was replaced and the session names the domain -- and
                # wrote nothing to the warning stream.
                $script:_OERAuthState.TenantId | Should -BeExactly 'contoso.onmicrosoft.com'
                $script:_OERAuthState.TokenTenantId | Should -BeExactly '11111111-1111-1111-1111-111111111111'
                @($Warnings).Count | Should -Be 0
            }
        }
        finally {
            if ($null -eq $AmbientAuthorityHost) {
                [System.Environment]::SetEnvironmentVariable('AZURE_AUTHORITY_HOST', [NullString]::Value)
            }
            else {
                [System.Environment]::SetEnvironmentVariable('AZURE_AUTHORITY_HOST', $AmbientAuthorityHost)
            }
        }

        Should -Invoke -ModuleName $script:moduleName Get-AzToken -Times 2 -Exactly
        Should -Invoke -ModuleName $script:moduleName Connect-MgGraph -Times 2 -Exactly
    }
}

# -------------------------------------------------------------------------------------------------
# Tenant-switch warnings (F12).
#
# AzAuth keeps ONE credential per PowerShell process, and a same-session tenant switch can fail to
# reach the new tenant without any error that says so. The pre-call warning (the P Its) PREDICTS it for
# a client secret sign-in, from the module's own record of the token request that last made AzAuth
# build its credential. Read together, the Its are a mutation set over every term of its predicate.
# What a switch that did not take effect looks like AFTER the call -- a token issued for another tenant
# than the one named -- is refused, not warned about: a tenant named by domain is resolved to its
# tenant ID and compared with the token's (TenantMismatch, Describe 'granted-tenant guard'). The
# post-call warning that used to observe it is retired.
#
# The P Its name tenants by plain labels and their mocked tokens carry no tenant, so the TenantMismatch
# check has no GUID to compare and cannot refuse them by accident.
#
# Warnings are captured with -WarningVariable on the call itself and asserted in the SAME scope as the
# call. Each capture variable is seeded with a sentinel string that the call replaces with a
# (possibly empty) list whenever it runs, and every silent It also proves its call ran -- through the
# session it left behind and an exact Get-AzToken count -- before it trusts a count of zero.
# -------------------------------------------------------------------------------------------------
Describe 'Initialize-OERAuth tenant-switch warnings' {
    BeforeAll {
        # AZURE_AUTHORITY_HOST is process state. A non-commercial ambient value would add the ambient
        # authority warning to every capture below and break the exact counts, so borrow it and hand
        # it back.
        $script:AmbientAuthorityHost = [System.Environment]::GetEnvironmentVariable('AZURE_AUTHORITY_HOST')
        $script:SwitchSecret = ConvertTo-SecureString 'not-a-real-secret' -AsPlainText -Force
    }

    AfterAll {
        if ($null -eq $script:AmbientAuthorityHost) {
            [System.Environment]::SetEnvironmentVariable('AZURE_AUTHORITY_HOST', [NullString]::Value)
        }
        else {
            [System.Environment]::SetEnvironmentVariable('AZURE_AUTHORITY_HOST', $script:AmbientAuthorityHost)
        }
    }

    BeforeEach {
        [System.Environment]::SetEnvironmentVariable('AZURE_AUTHORITY_HOST', [NullString]::Value)
        # Neither tracker is ever cleared by the module -- not even by Disconnect-OER -- so reset them
        # here, or one It's recorded credential build or authority leaks into the next.
        InModuleScope $script:moduleName {
            $script:_OERAuthState = $null
            $script:_OERSessionUncertain = $null
            $script:_OERLastAuthorityHost = $null
            $script:_OERLastTokenRequest = $null
            $script:_OERInteractiveCredential = $null
        }
        # BL-12: a tenant named by anything but a GUID or 'organizations' is looked up before any token
        # is requested. The tokens of the P Its carry no tenant, so the mocked lookup answers with any
        # tenant ID.
        Mock -ModuleName $script:moduleName Resolve-OERTenantDomain { '11111111-1111-1111-1111-111111111111' }
        Mock -ModuleName $script:moduleName Connect-MgGraph { }
    }

    Context 'before the token request: a client secret sign-in AzAuth would answer with its old credential' {
        It 'warns exactly once on a switch to another tenant for the same application without -ForceRefresh (P1)' {
            Mock -ModuleName $script:moduleName Get-AzToken {
                param($ClientId, $ClientSecret, $Resource, $Tenant, $ErrorAction, $Interactive,
                      $DeviceCode, $ManagedIdentity, $ClientCertificate, $ClientCertificatePath,
                      $Scope, $Force, $Claim)
                [pscustomobject]@{ Token = "token-for-$Tenant"; ExpiresOn = [DateTimeOffset]::UtcNow.AddHours(1); Identity = 'sp' }
            }

            InModuleScope $script:moduleName -Parameters @{ Secret = $script:SwitchSecret } {
                param($Secret)
                $FirstWarnings = 'not-run'
                Initialize-OERAuth -TenantId 'tenant-a.example.com' -AuthMethod 'ClientSecret' -ClientId 'app-client-1' `
                    -ClientSecret $Secret -WarningVariable FirstWarnings -WarningAction SilentlyContinue
                $SwitchWarnings = 'not-run'
                Initialize-OERAuth -TenantId 'tenant-b.example.com' -AuthMethod 'ClientSecret' -ClientId 'app-client-1' `
                    -ClientSecret $Secret -WarningVariable SwitchWarnings -WarningAction SilentlyContinue

                # A warning, not a refusal: the sign-in still completes and the session names tenant B.
                $script:_OERAuthState.TenantId | Should -Be 'tenant-b.example.com'
                @($FirstWarnings).Count | Should -Be 0 -Because 'a first sign-in has no recorded credential build to compare with'
                @($SwitchWarnings).Count | Should -Be 1

                $Message = $SwitchWarnings[0].Message
                $Message | Should -Match ([regex]::Escape("names tenant 'tenant-b.example.com'"))
                $Message | Should -Match ([regex]::Escape("was built for tenant 'tenant-a.example.com'"))
                $Message | Should -Match ([regex]::Escape("application 'app-client-1'"))
                $Message | Should -Match ([regex]::Escape('Run Connect-OER again with -Force'))
                # Pinned word for word, so a change to the advice an operator reads is a deliberate one.
                $Message | Should -BeExactly (
                    "This client secret sign-in for application 'app-client-1' names tenant " +
                    "'tenant-b.example.com', but the credential AzAuth holds for that application in this " +
                    "PowerShell session was built for tenant 'tenant-a.example.com'. AzAuth reuses that " +
                    "credential for the same application until it is told to rebuild it, so this sign-in " +
                    "does not reach 'tenant-b.example.com': by default it fails with 'The current " +
                    "credential is not configured to acquire tokens for tenant', and where multi-tenant " +
                    "authentication is disabled (AZURE_IDENTITY_DISABLE_MULTITENANTAUTH) the token is " +
                    "requested from 'tenant-a.example.com' instead. Run Connect-OER again with -Force to " +
                    "rebuild the credential for 'tenant-b.example.com'. Disconnect-OER does not clear it.")
            }

            Should -Invoke -ModuleName $script:moduleName Get-AzToken -Exactly -Times 2
        }

        It 'stays silent when the switch passes -ForceRefresh, which rebuilds the credential for the new tenant (P2)' {
            Mock -ModuleName $script:moduleName Get-AzToken {
                param($ClientId, $ClientSecret, $Resource, $Tenant, $ErrorAction, $Interactive,
                      $DeviceCode, $ManagedIdentity, $ClientCertificate, $ClientCertificatePath,
                      $Scope, $Force, $Claim)
                [pscustomobject]@{ Token = "token-for-$Tenant"; ExpiresOn = [DateTimeOffset]::UtcNow.AddHours(1); Identity = 'sp' }
            }

            InModuleScope $script:moduleName -Parameters @{ Secret = $script:SwitchSecret } {
                param($Secret)
                Initialize-OERAuth -TenantId 'tenant-a.example.com' -AuthMethod 'ClientSecret' -ClientId 'app-client-1' `
                    -ClientSecret $Secret
                $SwitchWarnings = 'not-run'
                Initialize-OERAuth -TenantId 'tenant-b.example.com' -AuthMethod 'ClientSecret' -ClientId 'app-client-1' `
                    -ClientSecret $Secret -ForceRefresh -WarningVariable SwitchWarnings -WarningAction SilentlyContinue

                $script:_OERAuthState.TenantId | Should -Be 'tenant-b.example.com'
                @($SwitchWarnings).Count | Should -Be 0
            }

            # The switch really carried Force, so the silence belongs to the Force term.
            Should -Invoke -ModuleName $script:moduleName Get-AzToken -Exactly -Times 1 -ParameterFilter {
                $Tenant -eq 'tenant-b.example.com' -and $Force
            }
            Should -Invoke -ModuleName $script:moduleName Get-AzToken -Exactly -Times 2
        }

        It 'stays silent when the switch names a different application (P3)' {
            Mock -ModuleName $script:moduleName Get-AzToken {
                param($ClientId, $ClientSecret, $Resource, $Tenant, $ErrorAction, $Interactive,
                      $DeviceCode, $ManagedIdentity, $ClientCertificate, $ClientCertificatePath,
                      $Scope, $Force, $Claim)
                [pscustomobject]@{ Token = "token-for-$Tenant"; ExpiresOn = [DateTimeOffset]::UtcNow.AddHours(1); Identity = 'sp' }
            }

            InModuleScope $script:moduleName -Parameters @{ Secret = $script:SwitchSecret } {
                param($Secret)
                Initialize-OERAuth -TenantId 'tenant-a.example.com' -AuthMethod 'ClientSecret' -ClientId 'app-client-1' `
                    -ClientSecret $Secret
                $SwitchWarnings = 'not-run'
                Initialize-OERAuth -TenantId 'tenant-b.example.com' -AuthMethod 'ClientSecret' -ClientId 'app-client-2' `
                    -ClientSecret $Secret -WarningVariable SwitchWarnings -WarningAction SilentlyContinue

                $script:_OERAuthState.TenantId | Should -Be 'tenant-b.example.com'
                $script:_OERAuthState.ClientId | Should -Be 'app-client-2'
                @($SwitchWarnings).Count | Should -Be 0
            }

            Should -Invoke -ModuleName $script:moduleName Get-AzToken -Exactly -Times 2
        }

        # AzAuth's reuse test is an ordinal string comparison, so a client id that differs only in
        # letter case already gets a NEW credential built for the new tenant.
        It 'stays silent when the client ids differ only by letter case (P4)' {
            Mock -ModuleName $script:moduleName Get-AzToken {
                param($ClientId, $ClientSecret, $Resource, $Tenant, $ErrorAction, $Interactive,
                      $DeviceCode, $ManagedIdentity, $ClientCertificate, $ClientCertificatePath,
                      $Scope, $Force, $Claim)
                [pscustomobject]@{ Token = "token-for-$Tenant"; ExpiresOn = [DateTimeOffset]::UtcNow.AddHours(1); Identity = 'sp' }
            }

            InModuleScope $script:moduleName -Parameters @{ Secret = $script:SwitchSecret } {
                param($Secret)
                Initialize-OERAuth -TenantId 'tenant-a.example.com' -AuthMethod 'ClientSecret' -ClientId 'App-Client-1' `
                    -ClientSecret $Secret
                $SwitchWarnings = 'not-run'
                Initialize-OERAuth -TenantId 'tenant-b.example.com' -AuthMethod 'ClientSecret' -ClientId 'app-client-1' `
                    -ClientSecret $Secret -WarningVariable SwitchWarnings -WarningAction SilentlyContinue

                $script:_OERAuthState.TenantId | Should -Be 'tenant-b.example.com'
                $script:_OERAuthState.ClientId | Should -BeExactly 'app-client-1'
                @($SwitchWarnings).Count | Should -Be 0
            }

            Should -Invoke -ModuleName $script:moduleName Get-AzToken -Exactly -Times 2
        }

        # -Force is the advice, and it is false advice for these types: a device-code or managed
        # identity credential holds no tenant to rebuild, and a client certificate or interactive
        # credential is rebuilt on every call anyway.
        It 'stays silent on a <AuthMethod> switch to another tenant for the same client id (P5)' -ForEach @(
            @{ AuthMethod = 'DeviceCode' }
            @{ AuthMethod = 'ManagedIdentity' }
            @{ AuthMethod = 'Interactive' }
            @{ AuthMethod = 'ClientCertificate' }
        ) {
            Mock -ModuleName $script:moduleName Get-AzToken {
                param($ClientId, $ClientSecret, $Resource, $Tenant, $ErrorAction, $Interactive,
                      $DeviceCode, $ManagedIdentity, $ClientCertificate, $ClientCertificatePath,
                      $Scope, $Force, $Claim)
                [pscustomobject]@{ Token = "token-for-$Tenant"; ExpiresOn = [DateTimeOffset]::UtcNow.AddHours(1); Identity = 'sp' }
            }

            InModuleScope $script:moduleName -Parameters @{ AuthMethod = $AuthMethod } {
                param($AuthMethod)
                $Credential = @{ AuthMethod = $AuthMethod; ClientId = 'app-client-1' }
                if ($AuthMethod -eq 'ClientCertificate') { $Credential.CertificatePath = 'C:\certs\app.pfx' }

                $FirstWarnings = 'not-run'
                Initialize-OERAuth -TenantId 'tenant-a.example.com' @Credential `
                    -WarningVariable FirstWarnings -WarningAction SilentlyContinue
                $SwitchWarnings = 'not-run'
                Initialize-OERAuth -TenantId 'tenant-b.example.com' @Credential `
                    -WarningVariable SwitchWarnings -WarningAction SilentlyContinue

                $script:_OERAuthState.TenantId   | Should -Be 'tenant-b.example.com'
                $script:_OERAuthState.AuthMethod | Should -Be $AuthMethod
                @($FirstWarnings).Count  | Should -Be 0
                @($SwitchWarnings).Count | Should -Be 0
            }

            Should -Invoke -ModuleName $script:moduleName Get-AzToken -Exactly -Times 2
        }

        # The same types on ONE side of the comparison only. A same-type switch cannot tell the two
        # AuthMethod terms apart; these two Its each leave exactly one of them to keep the call silent.
        It 'stays silent when a <AuthMethod> sign-in for another tenant follows a client secret request (P5a)' -ForEach @(
            @{ AuthMethod = 'DeviceCode' }
            @{ AuthMethod = 'ManagedIdentity' }
            @{ AuthMethod = 'Interactive' }
            @{ AuthMethod = 'ClientCertificate' }
        ) {
            Mock -ModuleName $script:moduleName Get-AzToken {
                param($ClientId, $ClientSecret, $Resource, $Tenant, $ErrorAction, $Interactive,
                      $DeviceCode, $ManagedIdentity, $ClientCertificate, $ClientCertificatePath,
                      $Scope, $Force, $Claim)
                [pscustomobject]@{ Token = "token-for-$Tenant"; ExpiresOn = [DateTimeOffset]::UtcNow.AddHours(1); Identity = 'sp' }
            }

            InModuleScope $script:moduleName -Parameters @{ AuthMethod = $AuthMethod; Secret = $script:SwitchSecret } {
                param($AuthMethod, $Secret)
                $Credential = @{ AuthMethod = $AuthMethod; ClientId = 'app-client-1' }
                if ($AuthMethod -eq 'ClientCertificate') { $Credential.CertificatePath = 'C:\certs\app.pfx' }

                Initialize-OERAuth -TenantId 'tenant-a.example.com' -AuthMethod 'ClientSecret' -ClientId 'app-client-1' `
                    -ClientSecret $Secret
                $SwitchWarnings = 'not-run'
                Initialize-OERAuth -TenantId 'tenant-b.example.com' @Credential `
                    -WarningVariable SwitchWarnings -WarningAction SilentlyContinue

                $script:_OERAuthState.TenantId   | Should -Be 'tenant-b.example.com'
                $script:_OERAuthState.AuthMethod | Should -Be $AuthMethod
                @($SwitchWarnings).Count | Should -Be 0
            }

            Should -Invoke -ModuleName $script:moduleName Get-AzToken -Exactly -Times 2
        }

        It 'stays silent when a client secret sign-in for another tenant follows a <AuthMethod> request (P5b)' -ForEach @(
            @{ AuthMethod = 'DeviceCode' }
            @{ AuthMethod = 'ManagedIdentity' }
            @{ AuthMethod = 'Interactive' }
            @{ AuthMethod = 'ClientCertificate' }
        ) {
            Mock -ModuleName $script:moduleName Get-AzToken {
                param($ClientId, $ClientSecret, $Resource, $Tenant, $ErrorAction, $Interactive,
                      $DeviceCode, $ManagedIdentity, $ClientCertificate, $ClientCertificatePath,
                      $Scope, $Force, $Claim)
                [pscustomobject]@{ Token = "token-for-$Tenant"; ExpiresOn = [DateTimeOffset]::UtcNow.AddHours(1); Identity = 'sp' }
            }

            InModuleScope $script:moduleName -Parameters @{ AuthMethod = $AuthMethod; Secret = $script:SwitchSecret } {
                param($AuthMethod, $Secret)
                $Credential = @{ AuthMethod = $AuthMethod; ClientId = 'app-client-1' }
                if ($AuthMethod -eq 'ClientCertificate') { $Credential.CertificatePath = 'C:\certs\app.pfx' }

                Initialize-OERAuth -TenantId 'tenant-a.example.com' @Credential
                $SwitchWarnings = 'not-run'
                Initialize-OERAuth -TenantId 'tenant-b.example.com' -AuthMethod 'ClientSecret' -ClientId 'app-client-1' `
                    -ClientSecret $Secret -WarningVariable SwitchWarnings -WarningAction SilentlyContinue

                $script:_OERAuthState.TenantId   | Should -Be 'tenant-b.example.com'
                $script:_OERAuthState.AuthMethod | Should -Be 'ClientSecret'
                @($SwitchWarnings).Count | Should -Be 0
            }

            Should -Invoke -ModuleName $script:moduleName Get-AzToken -Exactly -Times 2
        }

        It 'stays silent when the same tenant re-acquires an expired token (P6)' {
            Mock -ModuleName $script:moduleName Get-AzToken {
                param($ClientId, $ClientSecret, $Resource, $Tenant, $ErrorAction, $Interactive,
                      $DeviceCode, $ManagedIdentity, $ClientCertificate, $ClientCertificatePath,
                      $Scope, $Force, $Claim)
                [pscustomobject]@{ Token = "token-for-$Tenant"; ExpiresOn = [DateTimeOffset]::UtcNow.AddHours(1); Identity = 'sp' }
            }

            InModuleScope $script:moduleName -Parameters @{ Secret = $script:SwitchSecret } {
                param($Secret)
                Initialize-OERAuth -TenantId 'tenant-a.example.com' -AuthMethod 'ClientSecret' -ClientId 'app-client-1' `
                    -ClientSecret $Secret
                # Past the five-minute floor, so the cache misses and a second request is made.
                $script:_OERAuthState.GraphTokenExpiry = [DateTime]::UtcNow.AddMinutes(-1)

                $RefreshWarnings = 'not-run'
                Initialize-OERAuth -TenantId 'tenant-a.example.com' -AuthMethod 'ClientSecret' -ClientId 'app-client-1' `
                    -ClientSecret $Secret -WarningVariable RefreshWarnings -WarningAction SilentlyContinue

                $script:_OERAuthState.GraphTokenExpiry | Should -BeGreaterThan ([DateTime]::UtcNow)
                @($RefreshWarnings).Count | Should -Be 0
            }

            Should -Invoke -ModuleName $script:moduleName Get-AzToken -Exactly -Times 2 -ParameterFilter {
                $Tenant -eq 'tenant-a.example.com'
            }
        }

        It 'still warns after Disconnect-OER, which does not clear the credential AzAuth keeps (P7)' {
            Mock -ModuleName $script:moduleName Get-AzToken {
                param($ClientId, $ClientSecret, $Resource, $Tenant, $ErrorAction, $Interactive,
                      $DeviceCode, $ManagedIdentity, $ClientCertificate, $ClientCertificatePath,
                      $Scope, $Force, $Claim)
                [pscustomobject]@{ Token = "token-for-$Tenant"; ExpiresOn = [DateTimeOffset]::UtcNow.AddHours(1); Identity = 'sp' }
            }
            # Disconnect-MgGraph is mocked because Disconnect-OER calls it. Disconnect-AzAccount is
            # mocked defensively: Disconnect-OER no longer calls it (Philip's decision, 2026-09-21 --
            # the module establishes no Az context, so the call could only ever reach the operator's
            # own session), but the cmdlet still resolves for real in the test environment, so the
            # mock keeps a reintroduced call from clearing the operator's Az context in a local run.
            Mock -ModuleName $script:moduleName Disconnect-MgGraph { }
            Mock -ModuleName $script:moduleName Disconnect-AzAccount { }

            InModuleScope $script:moduleName -Parameters @{ Secret = $script:SwitchSecret } {
                param($Secret)
                Initialize-OERAuth -TenantId 'tenant-a.example.com' -AuthMethod 'ClientSecret' -ClientId 'app-client-1' `
                    -ClientSecret $Secret
                Disconnect-OER -Confirm:$false
                # The session is gone, so only the token-request tracker can still remember tenant A.
                $script:_OERAuthState | Should -BeNullOrEmpty

                $SwitchWarnings = 'not-run'
                Initialize-OERAuth -TenantId 'tenant-b.example.com' -AuthMethod 'ClientSecret' -ClientId 'app-client-1' `
                    -ClientSecret $Secret -WarningVariable SwitchWarnings -WarningAction SilentlyContinue

                $script:_OERAuthState.TenantId | Should -Be 'tenant-b.example.com'
                @($SwitchWarnings).Count | Should -Be 1
                $SwitchWarnings[0].Message | Should -Match ([regex]::Escape(
                    "names tenant 'tenant-b.example.com', but the credential AzAuth holds for that application in this PowerShell session was built for tenant 'tenant-a.example.com'"))
            }

            Should -Invoke -ModuleName $script:moduleName Disconnect-MgGraph -Exactly -Times 1
            Should -Invoke -ModuleName $script:moduleName Get-AzToken -Exactly -Times 2
        }

        # A FAILED attempt still leaves AzAuth's credential built for the tenant it named, while the
        # session keeps naming the older one. Only a tracker written before the call sees that.
        It 'warns on an ARM-only acquisition for the session tenant after a failed -ForceRefresh switch left the tracker on another tenant (P8)' {
            Mock -ModuleName $script:moduleName Get-AzToken {
                param($ClientId, $ClientSecret, $Resource, $Tenant, $ErrorAction, $Interactive,
                      $DeviceCode, $ManagedIdentity, $ClientCertificate, $ClientCertificatePath,
                      $Scope, $Force, $Claim)
                if ($Tenant -eq 'tenant-b.example.com') { throw 'tenant-b sign-in failed' }
                [pscustomobject]@{ Token = "token-for-$Resource"; ExpiresOn = [DateTimeOffset]::UtcNow.AddHours(1); Identity = 'sp' }
            }

            InModuleScope $script:moduleName -Parameters @{ Secret = $script:SwitchSecret } {
                param($Secret)
                Initialize-OERAuth -TenantId 'tenant-a.example.com' -AuthMethod 'ClientSecret' -ClientId 'app-client-1' `
                    -ClientSecret $Secret

                $Caught = $null
                try {
                    Initialize-OERAuth -TenantId 'tenant-b.example.com' -AuthMethod 'ClientSecret' -ClientId 'app-client-1' `
                        -ClientSecret $Secret -ForceRefresh
                }
                catch {
                    $Caught = $PSItem
                }
                $Caught.FullyQualifiedErrorId | Should -Be 'GraphTokenAcquisitionFailed,Initialize-OERAuth'
                # The session still names tenant A; only the tracker moved to tenant B.
                $script:_OERAuthState.TenantId        | Should -Be 'tenant-a.example.com'
                $script:_OERAuthState.ArmToken        | Should -BeNullOrEmpty
                $script:_OERLastTokenRequest.TenantId | Should -Be 'tenant-b.example.com'

                $ArmWarnings = 'not-run'
                Initialize-OERAuth -TenantId 'tenant-a.example.com' -AuthMethod 'ClientSecret' -ClientId 'app-client-1' `
                    -ClientSecret $Secret -IncludeARM -WarningVariable ArmWarnings -WarningAction SilentlyContinue

                $script:_OERAuthState.ArmToken | Should -BeOfType [System.Security.SecureString]
                @($ArmWarnings).Count | Should -Be 1
                $ArmWarnings[0].Message | Should -Match ([regex]::Escape(
                    "names tenant 'tenant-a.example.com', but the credential AzAuth holds for that application in this PowerShell session was built for tenant 'tenant-b.example.com'"))
            }

            # Graph for A (the first call), Graph for B (the failed switch), then ARM for A ALONE: no
            # second Graph request for A, so the warning came from the ARM-only path.
            Should -Invoke -ModuleName $script:moduleName Get-AzToken -Exactly -Times 3
            Should -Invoke -ModuleName $script:moduleName Get-AzToken -Exactly -Times 1 -ParameterFilter {
                $Resource -eq 'https://management.azure.com/'
            }
            Should -Invoke -ModuleName $script:moduleName Get-AzToken -Exactly -Times 1 -ParameterFilter {
                $Resource -eq 'https://graph.microsoft.com/' -and $Tenant -eq 'tenant-a.example.com'
            }
        }

        It 'stays silent on a first sign-in, and records the request it is about to make (P9)' {
            Mock -ModuleName $script:moduleName Get-AzToken {
                param($ClientId, $ClientSecret, $Resource, $Tenant, $ErrorAction, $Interactive,
                      $DeviceCode, $ManagedIdentity, $ClientCertificate, $ClientCertificatePath,
                      $Scope, $Force, $Claim)
                [pscustomobject]@{ Token = "token-for-$Tenant"; ExpiresOn = [DateTimeOffset]::UtcNow.AddHours(1); Identity = 'sp' }
            }

            InModuleScope $script:moduleName -Parameters @{ Secret = $script:SwitchSecret } {
                param($Secret)
                $Warnings = 'not-run'
                Initialize-OERAuth -TenantId 'tenant-a.example.com' -AuthMethod 'ClientSecret' -ClientId 'app-client-1' `
                    -ClientSecret $Secret -WarningVariable Warnings -WarningAction SilentlyContinue

                $script:_OERAuthState.TenantId | Should -Be 'tenant-a.example.com'
                @($Warnings).Count | Should -Be 0
                $script:_OERLastTokenRequest.AuthMethod | Should -Be 'ClientSecret'
                $script:_OERLastTokenRequest.ClientId   | Should -Be 'app-client-1'
                $script:_OERLastTokenRequest.TenantId   | Should -Be 'tenant-a.example.com'
            }

            Should -Invoke -ModuleName $script:moduleName Get-AzToken -Exactly -Times 1
        }

        # A REFUSED switch builds nothing: AzAuth reuses the credential it built for tenant A, refuses
        # tenant B, and still holds that tenant-A credential afterwards. The record therefore stays on
        # tenant A, and a sign-in back to tenant A -- which works -- must not warn.
        It 'stays silent on a sign-in back to the tenant AzAuth''s credential was built for, after a refused switch (P10)' {
            Mock -ModuleName $script:moduleName Get-AzToken {
                param($ClientId, $ClientSecret, $Resource, $Tenant, $ErrorAction, $Interactive,
                      $DeviceCode, $ManagedIdentity, $ClientCertificate, $ClientCertificatePath,
                      $Scope, $Force, $Claim)
                # The measured refusal of a reused client secret credential, simulated for tenant B.
                if ($Tenant -eq 'tenant-b.example.com') {
                    throw 'The current credential is not configured to acquire tokens for tenant tenant-b.example.com.'
                }
                [pscustomobject]@{ Token = "token-for-$Tenant"; ExpiresOn = [DateTimeOffset]::UtcNow.AddHours(1); Identity = 'sp' }
            }

            InModuleScope $script:moduleName -Parameters @{ Secret = $script:SwitchSecret } {
                param($Secret)
                Initialize-OERAuth -TenantId 'tenant-a.example.com' -AuthMethod 'ClientSecret' -ClientId 'app-client-1' `
                    -ClientSecret $Secret

                $SwitchWarnings = 'not-run'
                $SwitchCaught = $null
                try {
                    Initialize-OERAuth -TenantId 'tenant-b.example.com' -AuthMethod 'ClientSecret' -ClientId 'app-client-1' `
                        -ClientSecret $Secret -WarningVariable SwitchWarnings -WarningAction SilentlyContinue
                }
                catch {
                    $SwitchCaught = $PSItem
                }
                $SwitchCaught.FullyQualifiedErrorId | Should -Be 'GraphTokenAcquisitionFailed,Initialize-OERAuth'
                @($SwitchWarnings).Count | Should -Be 1 -Because 'the switch itself is exactly what the warning exists for'
                $script:_OERAuthState.TenantId | Should -Be 'tenant-a.example.com'

                # Past the five-minute floor, so the sign-in back to tenant A really makes a token request.
                $script:_OERAuthState.GraphTokenExpiry = [DateTime]::UtcNow.AddMinutes(-1)
                $ReturnWarnings = 'not-run'
                Initialize-OERAuth -TenantId 'tenant-a.example.com' -AuthMethod 'ClientSecret' -ClientId 'app-client-1' `
                    -ClientSecret $Secret -WarningVariable ReturnWarnings -WarningAction SilentlyContinue

                $script:_OERAuthState.GraphTokenExpiry | Should -BeGreaterThan ([DateTime]::UtcNow)
                @($ReturnWarnings).Count | Should -Be 0
                $script:_OERLastTokenRequest.TenantId | Should -Be 'tenant-a.example.com'
            }

            Should -Invoke -ModuleName $script:moduleName Get-AzToken -Exactly -Times 3
            Should -Invoke -ModuleName $script:moduleName Get-AzToken -Exactly -Times 2 -ParameterFilter {
                $Tenant -eq 'tenant-a.example.com'
            }
        }

        # The same refusal from the other side: AzAuth still holds the tenant-A credential, so a second
        # switch to tenant B without -ForceRefresh fails exactly like the first and must warn again.
        It 'warns again on a second switch to the refused tenant without -ForceRefresh (P11)' {
            Mock -ModuleName $script:moduleName Get-AzToken {
                param($ClientId, $ClientSecret, $Resource, $Tenant, $ErrorAction, $Interactive,
                      $DeviceCode, $ManagedIdentity, $ClientCertificate, $ClientCertificatePath,
                      $Scope, $Force, $Claim)
                if ($Tenant -eq 'tenant-b.example.com') {
                    throw 'The current credential is not configured to acquire tokens for tenant tenant-b.example.com.'
                }
                [pscustomobject]@{ Token = "token-for-$Tenant"; ExpiresOn = [DateTimeOffset]::UtcNow.AddHours(1); Identity = 'sp' }
            }

            InModuleScope $script:moduleName -Parameters @{ Secret = $script:SwitchSecret } {
                param($Secret)
                Initialize-OERAuth -TenantId 'tenant-a.example.com' -AuthMethod 'ClientSecret' -ClientId 'app-client-1' `
                    -ClientSecret $Secret

                # The first refused switch; its own warning is what P10 asserts.
                $FirstCaught = $null
                try {
                    Initialize-OERAuth -TenantId 'tenant-b.example.com' -AuthMethod 'ClientSecret' -ClientId 'app-client-1' `
                        -ClientSecret $Secret -WarningAction SilentlyContinue
                }
                catch {
                    $FirstCaught = $PSItem
                }
                $FirstCaught.FullyQualifiedErrorId | Should -Be 'GraphTokenAcquisitionFailed,Initialize-OERAuth'

                $RetryWarnings = 'not-run'
                $RetryCaught = $null
                try {
                    Initialize-OERAuth -TenantId 'tenant-b.example.com' -AuthMethod 'ClientSecret' -ClientId 'app-client-1' `
                        -ClientSecret $Secret -WarningVariable RetryWarnings -WarningAction SilentlyContinue
                }
                catch {
                    $RetryCaught = $PSItem
                }
                $RetryCaught.FullyQualifiedErrorId | Should -Be 'GraphTokenAcquisitionFailed,Initialize-OERAuth'
                @($RetryWarnings).Count | Should -Be 1
                $RetryWarnings[0].Message | Should -Match ([regex]::Escape("names tenant 'tenant-b.example.com'"))
                # The literally previous request named tenant B and was refused, but the credential AzAuth
                # holds was still built for tenant A -- and that is the tenant the warning must name.
                $RetryWarnings[0].Message | Should -Match ([regex]::Escape("was built for tenant 'tenant-a.example.com'"))
                $RetryWarnings[0].Message | Should -Not -Match ([regex]::Escape("was built for tenant 'tenant-b.example.com'"))
            }

            Should -Invoke -ModuleName $script:moduleName Get-AzToken -Exactly -Times 3
            Should -Invoke -ModuleName $script:moduleName Get-AzToken -Exactly -Times 2 -ParameterFilter {
                $Tenant -eq 'tenant-b.example.com'
            }
        }

        # A different client id -- including one that differs only in letter case, since AzAuth's test is
        # ordinal -- gets a NEW credential, built for the tenant THAT call names. The record has to follow
        # it: a later call with that client id for another tenant is answered with the credential just
        # built, so it must be compared with that tenant, not with the first application's.
        It 'warns when client id <SecondClientId>, whose credential AzAuth last built for tenant B, names tenant A (P12)' -ForEach @(
            @{ SecondClientId = 'app-client-2' }
            @{ SecondClientId = 'App-Client-1' }
        ) {
            Mock -ModuleName $script:moduleName Get-AzToken {
                param($ClientId, $ClientSecret, $Resource, $Tenant, $ErrorAction, $Interactive,
                      $DeviceCode, $ManagedIdentity, $ClientCertificate, $ClientCertificatePath,
                      $Scope, $Force, $Claim)
                [pscustomobject]@{ Token = "token-for-$Tenant"; ExpiresOn = [DateTimeOffset]::UtcNow.AddHours(1); Identity = 'sp' }
            }

            InModuleScope $script:moduleName -Parameters @{ SecondClientId = $SecondClientId; Secret = $script:SwitchSecret } {
                param($SecondClientId, $Secret)
                Initialize-OERAuth -TenantId 'tenant-a.example.com' -AuthMethod 'ClientSecret' -ClientId 'app-client-1' `
                    -ClientSecret $Secret
                $SecondWarnings = 'not-run'
                Initialize-OERAuth -TenantId 'tenant-b.example.com' -AuthMethod 'ClientSecret' -ClientId $SecondClientId `
                    -ClientSecret $Secret -WarningVariable SecondWarnings -WarningAction SilentlyContinue
                $ThirdWarnings = 'not-run'
                Initialize-OERAuth -TenantId 'tenant-a.example.com' -AuthMethod 'ClientSecret' -ClientId $SecondClientId `
                    -ClientSecret $Secret -WarningVariable ThirdWarnings -WarningAction SilentlyContinue

                $script:_OERAuthState.TenantId | Should -Be 'tenant-a.example.com'
                $script:_OERAuthState.ClientId | Should -BeExactly $SecondClientId
                @($SecondWarnings).Count | Should -Be 0 -Because 'a different client id gets a credential of its own'
                @($ThirdWarnings).Count  | Should -Be 1
                $Message = $ThirdWarnings[0].Message
                $Message | Should -Match ([regex]::Escape("application '$SecondClientId' names tenant 'tenant-a.example.com'"))
                $Message | Should -Match ([regex]::Escape("was built for tenant 'tenant-b.example.com'"))
            }

            Should -Invoke -ModuleName $script:moduleName Get-AzToken -Exactly -Times 3
        }

        # A different credential type replaces AzAuth's credential outright. The record has to follow it,
        # or a later client secret sign-in -- which AzAuth answers with a NEW client secret credential for
        # the tenant it names -- is compared with the tenant of a client secret credential that is already
        # gone, and warns about a sign-in that works.
        It 'stays silent when a client secret sign-in follows a <AuthMethod> sign-in that replaced the client secret credential (P13)' -ForEach @(
            @{ AuthMethod = 'DeviceCode' }
            @{ AuthMethod = 'ManagedIdentity' }
            @{ AuthMethod = 'Interactive' }
            @{ AuthMethod = 'ClientCertificate' }
        ) {
            Mock -ModuleName $script:moduleName Get-AzToken {
                param($ClientId, $ClientSecret, $Resource, $Tenant, $ErrorAction, $Interactive,
                      $DeviceCode, $ManagedIdentity, $ClientCertificate, $ClientCertificatePath,
                      $Scope, $Force, $Claim)
                [pscustomobject]@{ Token = "token-for-$Tenant"; ExpiresOn = [DateTimeOffset]::UtcNow.AddHours(1); Identity = 'sp' }
            }

            InModuleScope $script:moduleName -Parameters @{ AuthMethod = $AuthMethod; Secret = $script:SwitchSecret } {
                param($AuthMethod, $Secret)
                $Credential = @{ AuthMethod = $AuthMethod; ClientId = 'app-client-1' }
                if ($AuthMethod -eq 'ClientCertificate') { $Credential.CertificatePath = 'C:\certs\app.pfx' }

                Initialize-OERAuth -TenantId 'tenant-a.example.com' -AuthMethod 'ClientSecret' -ClientId 'app-client-1' `
                    -ClientSecret $Secret
                Initialize-OERAuth -TenantId 'tenant-c.example.com' @Credential
                $ReturnWarnings = 'not-run'
                Initialize-OERAuth -TenantId 'tenant-b.example.com' -AuthMethod 'ClientSecret' -ClientId 'app-client-1' `
                    -ClientSecret $Secret -WarningVariable ReturnWarnings -WarningAction SilentlyContinue

                $script:_OERAuthState.TenantId   | Should -Be 'tenant-b.example.com'
                $script:_OERAuthState.AuthMethod | Should -Be 'ClientSecret'
                @($ReturnWarnings).Count | Should -Be 0
                $script:_OERLastTokenRequest.AuthMethod | Should -Be 'ClientSecret'
                $script:_OERLastTokenRequest.TenantId   | Should -Be 'tenant-b.example.com'
            }

            Should -Invoke -ModuleName $script:moduleName Get-AzToken -Exactly -Times 3
        }

        # Placement, not only the predicate. A caller running with -WarningAction Stop is stopped AT the
        # warning, so everything below it must be left as it was: the token call, the request record, the
        # authority record and the process AZURE_AUTHORITY_HOST. USGov as well as Global, since there the
        # variable is written above the warning and has to be handed back by the finally on the stop path.
        It 'stops a -WarningAction Stop client secret switch at the pre-call warning, before the token call and both records, in <Environment> (P14)' -ForEach @(
            @{ Environment = 'Global' }
            @{ Environment = 'USGov' }
        ) {
            Mock -ModuleName $script:moduleName Get-AzToken {
                param($ClientId, $ClientSecret, $Resource, $Tenant, $ErrorAction, $Interactive,
                      $DeviceCode, $ManagedIdentity, $ClientCertificate, $ClientCertificatePath,
                      $Scope, $Force, $Claim)
                [pscustomobject]@{ Token = "token-for-$Tenant"; ExpiresOn = [DateTimeOffset]::UtcNow.AddHours(1); Identity = 'sp' }
            }

            InModuleScope $script:moduleName -Parameters @{ Environment = $Environment; Secret = $script:SwitchSecret } {
                param($Environment, $Secret)
                Initialize-OERAuth -TenantId 'tenant-a.example.com' -AuthMethod 'ClientSecret' -ClientId 'app-client-1' `
                    -ClientSecret $Secret -Environment $Environment
                $script:_OERAuthState.TenantId        | Should -Be 'tenant-a.example.com'
                $script:_OERLastTokenRequest.TenantId | Should -Be 'tenant-a.example.com'

                $StateBefore         = $script:_OERAuthState
                $RequestBefore       = $script:_OERLastTokenRequest
                $AuthorityBefore     = $script:_OERLastAuthorityHost
                $AuthorityHostBefore = [System.Environment]::GetEnvironmentVariable('AZURE_AUTHORITY_HOST')

                $StopCaught = $null
                $StopWarnings = 'not-run'
                try {
                    # -WarningVariable captures the warning, which is asserted below; 3>$null keeps it off
                    # the console. Under Stop the warning is written, added to the variable and only then
                    # turned into the stop, so both hold the record (measured: an assignment of a 3>&1
                    # merge gets nothing under Stop, and -WarningVariable with 3>$null keeps the record
                    # and the ActionPreferenceStopException alike).
                    Initialize-OERAuth -TenantId 'tenant-b.example.com' -AuthMethod 'ClientSecret' -ClientId 'app-client-1' `
                        -ClientSecret $Secret -Environment $Environment -WarningAction Stop -WarningVariable StopWarnings 3>$null
                }
                catch {
                    $StopCaught = $PSItem
                }

                $StopCaught | Should -Not -BeNullOrEmpty -Because 'a -WarningAction Stop caller has to be stopped at the warning'
                $StopCaught.Exception | Should -BeOfType [System.Management.Automation.ActionPreferenceStopException]
                $StopCaught.Exception.Message | Should -Match ([regex]::Escape(
                    "names tenant 'tenant-b.example.com', but the credential AzAuth holds for that application in this PowerShell session was built for tenant 'tenant-a.example.com'"))
                @($StopWarnings).Count | Should -Be 1 -Because 'the stopped switch writes exactly one warning, the pre-call one it is stopped at'
                $StopWarnings[0].Message | Should -BeExactly (
                    "This client secret sign-in for application 'app-client-1' names tenant " +
                    "'tenant-b.example.com', but the credential AzAuth holds for that application in this " +
                    "PowerShell session was built for tenant 'tenant-a.example.com'. AzAuth reuses that " +
                    "credential for the same application until it is told to rebuild it, so this sign-in " +
                    "does not reach 'tenant-b.example.com': by default it fails with 'The current " +
                    "credential is not configured to acquire tokens for tenant', and where multi-tenant " +
                    "authentication is disabled (AZURE_IDENTITY_DISABLE_MULTITENANTAUTH) the token is " +
                    "requested from 'tenant-a.example.com' instead. Run Connect-OER again with -Force to " +
                    "rebuild the credential for 'tenant-b.example.com'. Disconnect-OER does not clear it.")

                [object]::ReferenceEquals($script:_OERAuthState, $StateBefore) | Should -BeTrue
                [object]::ReferenceEquals($script:_OERLastTokenRequest, $RequestBefore) | Should -BeTrue
                $script:_OERLastTokenRequest.TenantId | Should -Be 'tenant-a.example.com'
                $script:_OERLastAuthorityHost | Should -BeExactly $AuthorityBefore
                [System.Environment]::GetEnvironmentVariable('AZURE_AUTHORITY_HOST') | Should -Be $AuthorityHostBefore
            }

            # Only the first sign-in reached Get-AzToken; the stopped one never did.
            Should -Invoke -ModuleName $script:moduleName Get-AzToken -Exactly -Times 1
            Should -Invoke -ModuleName $script:moduleName Get-AzToken -Exactly -Times 0 -ParameterFilter {
                $Tenant -eq 'tenant-b.example.com'
            }
        }
    }
}

Describe 'Initialize-OERAuth Graph SDK session fingerprint (A18)' {
    BeforeEach {
        InModuleScope $script:moduleName {
            $script:_OERAuthState = $null
            $script:_OERSessionUncertain = $null
            $script:_OERLastAuthorityHost = $null
            $script:_OERLastTokenRequest = $null
            $script:_OERInteractiveCredential = $null
        }
        $script:CurrentContext = $null
        $script:OwnContext = [pscustomobject]@{
            AuthType = 'UserProvidedAccessToken'; TokenCredentialType = 'UserProvidedAccessToken'
            ClientId = '33333333-3333-3333-3333-333333333333'; TenantId = '44444444-4444-4444-4444-444444444444'
            Account = $null; AppName = 'oer-test-app'; Environment = 'Global'; Scopes = @('Group.ReadWrite.All')
        }
        Mock -ModuleName $script:moduleName Get-AzToken {
            [pscustomobject]@{ Token = 'fake-graph-token-NOT-A-REAL-TOKEN'; ExpiresOn = [DateTimeOffset]::UtcNow.AddHours(1); Identity = 'sp'; TenantId = '44444444-4444-4444-4444-444444444444' }
        }
        # Stateful, like the SDK: no session until Connect-MgGraph, then the module's own. A test swaps
        # the session by assigning $script:CurrentContext (another session, or $null for none).
        Mock -ModuleName $script:moduleName Connect-MgGraph { $script:CurrentContext = $script:OwnContext }
        Mock -ModuleName $script:moduleName Get-MgContext { $script:CurrentContext }
    }

    It 'records the fingerprint of the session its own Connect-MgGraph left, read after the connect' {
        InModuleScope $script:moduleName {
            Initialize-OERAuth -TenantId '44444444-4444-4444-4444-444444444444' -AuthMethod 'Interactive'
        }
        $Recorded = InModuleScope $script:moduleName { $script:_OERAuthState.GraphSessionFingerprint }
        $Expected = InModuleScope $script:moduleName -Parameters @{ C = $script:OwnContext } { param($C) Get-OERGraphSessionFingerprint -Context $C }
        $Recorded | Should -Not -BeNullOrEmpty
        $Recorded | Should -BeExactly $Expected
        Should -Invoke -ModuleName $script:moduleName Connect-MgGraph -Times 1 -Exactly
    }

    It 'stores no token anywhere in the fingerprint' {
        InModuleScope $script:moduleName {
            Initialize-OERAuth -TenantId '44444444-4444-4444-4444-444444444444' -AuthMethod 'Interactive'
        }
        $Recorded = InModuleScope $script:moduleName { $script:_OERAuthState.GraphSessionFingerprint }
        $Recorded | Should -Not -Match 'NOT-A-REAL-TOKEN'
    }

    It 'keeps the fingerprint when only an ARM token is acquired' {
        InModuleScope $script:moduleName {
            Initialize-OERAuth -TenantId '44444444-4444-4444-4444-444444444444' -AuthMethod 'Interactive'
        }
        $Before = InModuleScope $script:moduleName { $script:_OERAuthState.GraphSessionFingerprint }
        InModuleScope $script:moduleName {
            Initialize-OERAuth -TenantId '44444444-4444-4444-4444-444444444444' -AuthMethod 'Interactive' -IncludeARM
        }
        InModuleScope $script:moduleName { $script:_OERAuthState.GraphSessionFingerprint } | Should -BeExactly $Before
        Should -Invoke -ModuleName $script:moduleName Connect-MgGraph -Times 1 -Exactly
    }
}

Describe 'Initialize-OERAuth Graph SDK session check (A18)' {
    BeforeAll {
        # Connects the module once, as its own session, and then replaces the session the mocked SDK
        # holds -- another Connect-MgGraph's context, or $null for none. The module's own reconnect
        # puts $script:OwnContext back through the Connect-MgGraph mock below.
        function script:Connect-OwnThenSwap {
            param([AllowNull()][object]$Context)
            InModuleScope $script:moduleName {
                Initialize-OERAuth -TenantId '44444444-4444-4444-4444-444444444444' -AuthMethod 'Interactive'
            }
            $script:CurrentContext = $Context
        }

        # Calls Initialize-OERAuth with the given parameters and returns the record it raised, or
        # nothing when it raised none.
        function script:Invoke-InitializeCatching {
            param([hashtable]$Parameters = @{})
            InModuleScope $script:moduleName -Parameters @{ P = $Parameters } {
                param($P)
                $Caught = $null
                try { Initialize-OERAuth @P } catch { $Caught = $PSItem }
                $Caught
            }
        }

        function script:Get-RecordedFingerprint {
            InModuleScope $script:moduleName { $script:_OERAuthState.GraphSessionFingerprint }
        }

        function script:Get-ContextFingerprint {
            param([object]$Context)
            InModuleScope $script:moduleName -Parameters @{ C = $Context } { param($C) Get-OERGraphSessionFingerprint -Context $C }
        }
    }

    BeforeEach {
        InModuleScope $script:moduleName {
            $script:_OERAuthState = $null
            $script:_OERSessionUncertain = $null
            $script:_OERLastAuthorityHost = $null
            $script:_OERLastTokenRequest = $null
            $script:_OERInteractiveCredential = $null
        }
        $script:CurrentContext = $null
        $script:OwnContext = [pscustomobject]@{
            AuthType = 'UserProvidedAccessToken'; TokenCredentialType = 'UserProvidedAccessToken'
            ClientId = '33333333-3333-3333-3333-333333333333'; TenantId = '44444444-4444-4444-4444-444444444444'
            Account = $null; AppName = 'oer-test-app'; Environment = 'Global'; Scopes = @('Group.ReadWrite.All')
        }
        # Another Connect-MgGraph's session: a certificate sign-in as another app, in another tenant.
        $script:ForeignContext = [pscustomobject]@{
            AuthType = 'AppOnly'; TokenCredentialType = 'ClientCertificate'
            ClientId = '55555555-5555-5555-5555-555555555555'; TenantId = '66666666-6666-6666-6666-666666666666'
            Account = $null; AppName = 'another-app'; Environment = 'Global'; Scopes = @()
        }
        Mock -ModuleName $script:moduleName Get-AzToken {
            [pscustomobject]@{ Token = 'fake-graph-token-NOT-A-REAL-TOKEN'; ExpiresOn = [DateTimeOffset]::UtcNow.AddHours(1); Identity = 'sp'; TenantId = '44444444-4444-4444-4444-444444444444' }
        }
        # Stateful, like the SDK: no session until Connect-MgGraph, then the module's own.
        Mock -ModuleName $script:moduleName Connect-MgGraph { $script:CurrentContext = $script:OwnContext }
        Mock -ModuleName $script:moduleName Get-MgContext { $script:CurrentContext }
        Mock -ModuleName $script:moduleName Invoke-MgGraphRequest { }
    }

    It 'A1: refuses a cache hit under another session with a terminating GraphSessionChanged' {
        Connect-OwnThenSwap -Context $script:ForeignContext

        $Caught = Invoke-InitializeCatching -Parameters @{ TenantId = '44444444-4444-4444-4444-444444444444'; AuthMethod = 'Interactive' }

        $Caught | Should -Not -BeNullOrEmpty
        $Caught.FullyQualifiedErrorId | Should -BeLike 'GraphSessionChanged*'
        $Caught.CategoryInfo.Category | Should -Be 'AuthenticationError'
        $Caught.TargetObject | Should -Be '44444444-4444-4444-4444-444444444444'
        $Caught.Exception.Message | Should -Match 'Connect-OER'
        $Caught.Exception.Message | Should -Not -Match '66666666-6666-6666-6666-666666666666'
        $Caught.Exception.Message | Should -Not -Match '55555555-5555-5555-5555-555555555555'
        Should -Invoke -ModuleName $script:moduleName Get-AzToken -Times 1 -Exactly
        Should -Invoke -ModuleName $script:moduleName Connect-MgGraph -Times 1 -Exactly
        Should -Invoke -ModuleName $script:moduleName Invoke-MgGraphRequest -Times 0
    }

    It 'A2: connects again with a token of its own when the process holds no session' {
        Connect-OwnThenSwap -Context $null

        $Caught = Invoke-InitializeCatching -Parameters @{ TenantId = '44444444-4444-4444-4444-444444444444'; AuthMethod = 'Interactive' }

        $Caught | Should -BeNullOrEmpty
        Should -Invoke -ModuleName $script:moduleName Get-AzToken -Times 2 -Exactly
        Should -Invoke -ModuleName $script:moduleName Connect-MgGraph -Times 2 -Exactly
        Get-RecordedFingerprint | Should -BeExactly (Get-ContextFingerprint -Context $script:OwnContext)
    }

    It 'A3: carries on from the cache under the same session, reading it once per entry' {
        Connect-OwnThenSwap -Context $script:OwnContext

        $Caught = Invoke-InitializeCatching -Parameters @{ TenantId = '44444444-4444-4444-4444-444444444444'; AuthMethod = 'Interactive' }

        $Caught | Should -BeNullOrEmpty
        Should -Invoke -ModuleName $script:moduleName Get-AzToken -Times 1 -Exactly
        Should -Invoke -ModuleName $script:moduleName Connect-MgGraph -Times 1 -Exactly
        # One read by the rebuild after the connect, one by the second entry. The first entry has no
        # state, so it reads nothing.
        Should -Invoke -ModuleName $script:moduleName Get-MgContext -Times 2 -Exactly
    }

    It 'A4: takes the session back under -ReclaimGraphSession, connecting again' {
        Connect-OwnThenSwap -Context $script:ForeignContext

        $Caught = Invoke-InitializeCatching -Parameters @{
            TenantId = '44444444-4444-4444-4444-444444444444'; AuthMethod = 'Interactive'; ReclaimGraphSession = $true
        }

        $Caught | Should -BeNullOrEmpty
        Should -Invoke -ModuleName $script:moduleName Get-AzToken -Times 2 -Exactly
        Should -Invoke -ModuleName $script:moduleName Connect-MgGraph -Times 2 -Exactly
        # The Connect-MgGraph mock put the module's own session back, and that is what is recorded.
        Get-RecordedFingerprint | Should -BeExactly (Get-ContextFingerprint -Context $script:OwnContext)
    }

    It 'A5: compares nothing for a state it did not build, and returns from the cache as before' {
        InModuleScope $script:moduleName {
            # The hand-built shape the rest of this file uses: no GraphSessionFingerprint key.
            $script:_OERAuthState = @{
                TenantId         = '44444444-4444-4444-4444-444444444444'
                AuthMethod       = 'Interactive'
                ClientId         = ''
                Environment      = 'Global'
                Account          = 'user@contoso'
                GraphTokenExpiry = [DateTime]::UtcNow.AddHours(1)
                ArmToken         = $null
                ArmTokenExpiry   = $null
                ArmResourceUrl   = $null
                ClaimsSatisfied  = $false
            }
        }
        # Even another session in the process: an untracked state is not compared at all.
        $script:CurrentContext = $script:ForeignContext

        $Caught = Invoke-InitializeCatching -Parameters @{ TenantId = '44444444-4444-4444-4444-444444444444'; AuthMethod = 'Interactive' }

        $Caught | Should -BeNullOrEmpty
        Should -Invoke -ModuleName $script:moduleName Get-AzToken -Times 0
        Should -Invoke -ModuleName $script:moduleName Get-MgContext -Times 0
    }

    It 'A6: refuses -ForceRefresh under another session instead of switching the session back' {
        Connect-OwnThenSwap -Context $script:ForeignContext

        $Caught = Invoke-InitializeCatching -Parameters @{
            TenantId = '44444444-4444-4444-4444-444444444444'; AuthMethod = 'Interactive'; ForceRefresh = $true
        }

        $Caught.FullyQualifiedErrorId | Should -BeLike 'GraphSessionChanged*'
        Should -Invoke -ModuleName $script:moduleName Get-AzToken -Times 1 -Exactly
        Should -Invoke -ModuleName $script:moduleName Connect-MgGraph -Times 1 -Exactly
    }

    It 'A7: refuses a claims-challenge step-up under another session, with no new token' {
        Connect-OwnThenSwap -Context $script:ForeignContext

        $Caught = Invoke-InitializeCatching -Parameters @{
            TenantId = '44444444-4444-4444-4444-444444444444'; AuthMethod = 'Interactive'; ClaimsChallenge = '{}'
        }

        $Caught.FullyQualifiedErrorId | Should -BeLike 'GraphSessionChanged*'
        Should -Invoke -ModuleName $script:moduleName Get-AzToken -Times 1 -Exactly
        Should -Invoke -ModuleName $script:moduleName Connect-MgGraph -Times 1 -Exactly
    }

    It 'A8: refuses a renewal inside the five-minute window under another session, with no new token' {
        Connect-OwnThenSwap -Context $script:ForeignContext
        InModuleScope $script:moduleName { $script:_OERAuthState.GraphTokenExpiry = [DateTime]::UtcNow.AddMinutes(2) }

        $Caught = Invoke-InitializeCatching -Parameters @{ TenantId = '44444444-4444-4444-4444-444444444444'; AuthMethod = 'Interactive' }

        $Caught.FullyQualifiedErrorId | Should -BeLike 'GraphSessionChanged*'
        Should -Invoke -ModuleName $script:moduleName Get-AzToken -Times 1 -Exactly
        Should -Invoke -ModuleName $script:moduleName Connect-MgGraph -Times 1 -Exactly
    }

    It 'A9: refuses <Name> under another session, with no new token' -ForEach @(
        @{ Name = 'an ARM-only call (-IncludeARM)'; Parameters = @{ IncludeARM = $true } }
        @{ Name = 'a call naming another tenant'; Parameters = @{ TenantId = '77777777-7777-7777-7777-777777777777' } }
    ) {
        Connect-OwnThenSwap -Context $script:ForeignContext

        $Caught = Invoke-InitializeCatching -Parameters $Parameters

        $Caught.FullyQualifiedErrorId | Should -BeLike 'GraphSessionChanged*'
        # The module's own tenant, never the one the call named.
        $Caught.TargetObject | Should -Be '44444444-4444-4444-4444-444444444444'
        Should -Invoke -ModuleName $script:moduleName Get-AzToken -Times 1 -Exactly
        Should -Invoke -ModuleName $script:moduleName Connect-MgGraph -Times 1 -Exactly
    }

    It 'A10: an inherited app-only identity with no session raises AppOnlySessionCredentialUnavailable naming Disconnect-MgGraph' {
        # Get-AzToken is mocked, so the certificate path is never read.
        InModuleScope $script:moduleName {
            Initialize-OERAuth -TenantId '44444444-4444-4444-4444-444444444444' -AuthMethod 'ClientCertificate' `
                -ClientId '33333333-3333-3333-3333-333333333333' -CertificatePath 'TestDrive:\oer-test.pfx'
        }
        $script:CurrentContext = $null

        $Caught = Invoke-InitializeCatching

        $Caught.FullyQualifiedErrorId | Should -BeLike 'AppOnlySessionCredentialUnavailable*'
        $Caught.Exception.Message | Should -Match 'Disconnect-MgGraph'
        Should -Invoke -ModuleName $script:moduleName Get-AzToken -Times 1 -Exactly
    }

    It 'A11: the module''s own renewal records the new session, and the next call is a cache hit' {
        Connect-OwnThenSwap -Context $script:OwnContext
        InModuleScope $script:moduleName { $script:_OERAuthState.GraphTokenExpiry = [DateTime]::UtcNow.AddMinutes(2) }
        # The renewal's Connect-MgGraph will leave a session with another grant. The SDK still holds
        # the old one until then.
        $script:OwnContext = [pscustomobject]@{
            AuthType = 'UserProvidedAccessToken'; TokenCredentialType = 'UserProvidedAccessToken'
            ClientId = '33333333-3333-3333-3333-333333333333'; TenantId = '44444444-4444-4444-4444-444444444444'
            Account = $null; AppName = 'oer-test-app'; Environment = 'Global'; Scopes = @('Group.ReadWrite.All', 'User.Read')
        }

        $Caught = Invoke-InitializeCatching -Parameters @{ TenantId = '44444444-4444-4444-4444-444444444444'; AuthMethod = 'Interactive' }

        $Caught | Should -BeNullOrEmpty
        Should -Invoke -ModuleName $script:moduleName Get-AzToken -Times 2 -Exactly
        Get-RecordedFingerprint | Should -BeExactly (Get-ContextFingerprint -Context $script:OwnContext)

        # The renewed session is the module's own: the next entry is a cache hit, not a refusal.
        $Next = Invoke-InitializeCatching -Parameters @{ TenantId = '44444444-4444-4444-4444-444444444444'; AuthMethod = 'Interactive' }
        $Next | Should -BeNullOrEmpty
        Should -Invoke -ModuleName $script:moduleName Get-AzToken -Times 2 -Exactly
    }

    # R20: the refused caller carries on outside a try, and Invoke-OERArmRequest sends whatever ARM
    # token the state holds. A request for another tenant, identity or cloud must leave none behind.
    It 'A12: a refused call naming <Name> drops the cached ARM token, keeping the module''s own tenant and session' -ForEach @(
        @{ Name = 'another tenant'; Parameters = @{ TenantId = '77777777-7777-7777-7777-777777777777' } }
        @{ Name = 'another application'; Parameters = @{ ClientId = '88888888-8888-8888-8888-888888888888' } }
        @{ Name = 'another cloud'; Parameters = @{ Environment = 'USGov' } }
    ) {
        InModuleScope $script:moduleName {
            Initialize-OERAuth -TenantId '44444444-4444-4444-4444-444444444444' -AuthMethod 'Interactive' -IncludeARM
        }
        $script:CurrentContext = $script:ForeignContext
        $Before = InModuleScope $script:moduleName {
            @{
                HasArmToken = $null -ne $script:_OERAuthState.ArmToken
                TenantId    = $script:_OERAuthState.TenantId
                Fingerprint = $script:_OERAuthState.GraphSessionFingerprint
            }
        }
        # Not vacuous: the connect above cached an ARM token.
        $Before.HasArmToken | Should -BeTrue

        $Caught = Invoke-InitializeCatching -Parameters $Parameters

        $Caught.FullyQualifiedErrorId | Should -BeLike 'GraphSessionChanged*'
        $After = InModuleScope $script:moduleName {
            @{
                ArmToken         = $script:_OERAuthState.ArmToken
                ArmTokenExpiry   = $script:_OERAuthState.ArmTokenExpiry
                ArmResourceUrl   = $script:_OERAuthState.ArmResourceUrl
                ArmTokenTenantId = $script:_OERAuthState.ArmTokenTenantId
                TenantId         = $script:_OERAuthState.TenantId
                Fingerprint      = $script:_OERAuthState.GraphSessionFingerprint
            }
        }
        $After.ArmToken | Should -BeNullOrEmpty
        $After.ArmTokenExpiry | Should -BeNullOrEmpty
        $After.ArmResourceUrl | Should -BeNullOrEmpty
        $After.ArmTokenTenantId | Should -BeNullOrEmpty
        $After.TenantId | Should -BeExactly $Before.TenantId
        $After.Fingerprint | Should -BeExactly $Before.Fingerprint
        # The Graph token and the ARM token of the first connect, and nothing since.
        Should -Invoke -ModuleName $script:moduleName Get-AzToken -Times 2 -Exactly
        Should -Invoke -ModuleName $script:moduleName Connect-MgGraph -Times 1 -Exactly
    }

    It 'A13: a refused Azure call for the module''s own tenant keeps the cached ARM token' {
        InModuleScope $script:moduleName {
            Initialize-OERAuth -TenantId '44444444-4444-4444-4444-444444444444' -AuthMethod 'Interactive' -IncludeARM
            $script:A13ArmToken = $script:_OERAuthState.ArmToken
            $script:A13ArmTokenExpiry = $script:_OERAuthState.ArmTokenExpiry
            $script:A13ArmResourceUrl = $script:_OERAuthState.ArmResourceUrl
            $script:A13ArmTokenTenantId = $script:_OERAuthState.ArmTokenTenantId
        }
        $script:CurrentContext = $script:ForeignContext

        # An Azure cmdlet that names no tenant: Initialize-OERAuth -IncludeARM alone.
        $Caught = Invoke-InitializeCatching -Parameters @{ IncludeARM = $true }

        $Caught.FullyQualifiedErrorId | Should -BeLike 'GraphSessionChanged*'
        $Kept = InModuleScope $script:moduleName {
            @{
                HadToken     = $null -ne $script:A13ArmToken
                SameToken    = [object]::ReferenceEquals($script:A13ArmToken, $script:_OERAuthState.ArmToken)
                SameExpiry   = $script:A13ArmTokenExpiry -eq $script:_OERAuthState.ArmTokenExpiry
                SameResource = $script:A13ArmResourceUrl -ceq $script:_OERAuthState.ArmResourceUrl
                SameTenant   = $script:A13ArmTokenTenantId -ceq $script:_OERAuthState.ArmTokenTenantId
            }
            Remove-Variable -Scope Script -Name A13ArmToken, A13ArmTokenExpiry, A13ArmResourceUrl, A13ArmTokenTenantId
        }
        $Kept.HadToken | Should -BeTrue
        $Kept.SameToken | Should -BeTrue -Because 'the refused call names the module''s own tenant, identity and cloud'
        $Kept.SameExpiry | Should -BeTrue
        $Kept.SameResource | Should -BeTrue
        $Kept.SameTenant | Should -BeTrue
        Should -Invoke -ModuleName $script:moduleName Get-AzToken -Times 2 -Exactly
    }
}

Describe 'Initialize-OERAuth sign-in latch (A19)' {
    # Outside any try, a command carries on past a terminating error Initialize-OERAuth raises, so a
    # command whose sign-in for another tenant failed would send its calls under the previous tenant's
    # session. Initialize-OERAuth therefore latches the command that called it at entry and releases it
    # only on success. These tests read the latch with Get-OERSignInRefusal from the SAME frame that
    # called Initialize-OERAuth: each probe below is one InModuleScope script block, and that script
    # block is the command Initialize-OERAuth latches.
    BeforeAll {
        # Calls Initialize-OERAuth with the given parameters from one script block, then reads the
        # latch from that same script block. Returns the record it raised (if any) and the refusal.
        function script:Invoke-LatchProbe {
            param([hashtable]$Parameters = @{})
            InModuleScope $script:moduleName -Parameters @{ P = $Parameters } {
                param($P)
                $Caught = $null
                try { Initialize-OERAuth @P } catch { $Caught = $PSItem }
                $Refusal = Get-OERSignInRefusal
                @{ Caught = $Caught; Refusal = $Refusal }
            }
        }

        # Connects the module once, from its own script block, as its own session.
        function script:Connect-OwnSession {
            InModuleScope $script:moduleName {
                Initialize-OERAuth -TenantId '44444444-4444-4444-4444-444444444444' -AuthMethod 'Interactive'
            }
        }
    }

    BeforeEach {
        InModuleScope $script:moduleName {
            $script:_OERAuthState = $null
            $script:_OERSessionUncertain = $null
            $script:_OERLastAuthorityHost = $null
            $script:_OERLastTokenRequest = $null
            $script:_OERInteractiveCredential = $null
        }
        $script:CurrentContext = $null
        $script:OwnContext = [pscustomobject]@{
            AuthType = 'UserProvidedAccessToken'; TokenCredentialType = 'UserProvidedAccessToken'
            ClientId = '33333333-3333-3333-3333-333333333333'; TenantId = '44444444-4444-4444-4444-444444444444'
            Account = $null; AppName = 'oer-test-app'; Environment = 'Global'; Scopes = @('Group.ReadWrite.All')
        }
        $script:ForeignContext = [pscustomobject]@{
            AuthType = 'AppOnly'; TokenCredentialType = 'ClientCertificate'
            ClientId = '55555555-5555-5555-5555-555555555555'; TenantId = '66666666-6666-6666-6666-666666666666'
            Account = $null; AppName = 'another-app'; Environment = 'Global'; Scopes = @()
        }
        Mock -ModuleName $script:moduleName Get-AzToken {
            [pscustomobject]@{ Token = 'fake-graph-token-NOT-A-REAL-TOKEN'; ExpiresOn = [DateTimeOffset]::UtcNow.AddHours(1); Identity = 'admin@contoso.com'; TenantId = '44444444-4444-4444-4444-444444444444' }
        }
        # Stateful, like the SDK: no session until Connect-MgGraph, then the module's own.
        Mock -ModuleName $script:moduleName Connect-MgGraph { $script:CurrentContext = $script:OwnContext }
        Mock -ModuleName $script:moduleName Get-MgContext { $script:CurrentContext }
    }

    Context 'set after each refusal' {
        It 'stays set after GraphSessionChanged' {
            Connect-OwnSession
            $script:CurrentContext = $script:ForeignContext

            $R = Invoke-LatchProbe -Parameters @{ TenantId = '44444444-4444-4444-4444-444444444444'; AuthMethod = 'Interactive' }

            $R.Caught.FullyQualifiedErrorId | Should -BeExactly 'GraphSessionChanged,Initialize-OERAuth'
            $R.Refusal | Should -Not -BeNullOrEmpty
        }

        It 'stays set after AppOnlySessionCredentialUnavailable' {
            InModuleScope $script:moduleName {
                # An app-only session the module did not connect itself, holding no ARM token.
                $script:_OERAuthState = @{
                    TenantId         = '44444444-4444-4444-4444-444444444444'
                    AuthMethod       = 'ClientSecret'
                    ClientId         = '33333333-3333-3333-3333-333333333333'
                    Environment      = 'Global'
                    Account          = 'sp'
                    GraphTokenExpiry = [DateTime]::UtcNow.AddHours(1)
                    ArmToken         = $null
                    ArmTokenExpiry   = $null
                    ArmResourceUrl   = $null
                    ClaimsSatisfied  = $false
                }
            }

            $R = Invoke-LatchProbe -Parameters @{ IncludeARM = $true }

            $R.Caught.FullyQualifiedErrorId | Should -BeExactly 'AppOnlySessionCredentialUnavailable,Initialize-OERAuth'
            $R.Refusal | Should -Not -BeNullOrEmpty
            Should -Invoke -ModuleName $script:moduleName Get-AzToken -Times 0
        }

        It 'stays set after MissingClientSecret' {
            $R = Invoke-LatchProbe -Parameters @{
                TenantId = '44444444-4444-4444-4444-444444444444'; AuthMethod = 'ClientSecret'; ClientId = '33333333-3333-3333-3333-333333333333'
            }

            $R.Caught.FullyQualifiedErrorId | Should -BeExactly 'MissingClientSecret,Initialize-OERAuth'
            $R.Refusal | Should -Not -BeNullOrEmpty
            Should -Invoke -ModuleName $script:moduleName Get-AzToken -Times 0
        }

        It 'stays set after MissingClientCertificate' {
            $R = Invoke-LatchProbe -Parameters @{
                TenantId = '44444444-4444-4444-4444-444444444444'; AuthMethod = 'ClientCertificate'; ClientId = '33333333-3333-3333-3333-333333333333'
            }

            $R.Caught.FullyQualifiedErrorId | Should -BeExactly 'MissingClientCertificate,Initialize-OERAuth'
            $R.Refusal | Should -Not -BeNullOrEmpty
            Should -Invoke -ModuleName $script:moduleName Get-AzToken -Times 0
        }

        It 'stays set after GraphTokenAcquisitionFailed' {
            Mock -ModuleName $script:moduleName Get-AzToken { throw [System.Exception]::new('AADSTS50076: interaction required') }

            $R = Invoke-LatchProbe -Parameters @{ TenantId = '44444444-4444-4444-4444-444444444444'; AuthMethod = 'Interactive' }

            $R.Caught.FullyQualifiedErrorId | Should -BeExactly 'GraphTokenAcquisitionFailed,Initialize-OERAuth'
            $R.Refusal | Should -Not -BeNullOrEmpty
            Should -Invoke -ModuleName $script:moduleName Connect-MgGraph -Times 0
        }

        It 'stays set after TenantMismatch on the Microsoft Graph token' {
            Mock -ModuleName $script:moduleName Get-AzToken {
                [pscustomobject]@{ Token = 'fake-graph-token-NOT-A-REAL-TOKEN'; ExpiresOn = [DateTimeOffset]::UtcNow.AddHours(1); Identity = 'admin@contoso.com'; TenantId = '22222222-2222-2222-2222-222222222222' }
            }

            $R = Invoke-LatchProbe -Parameters @{ TenantId = '11111111-1111-1111-1111-111111111111'; AuthMethod = 'Interactive' }

            $R.Caught.FullyQualifiedErrorId | Should -BeExactly 'TenantMismatch,Initialize-OERAuth'
            $R.Caught.Exception.Message | Should -Match 'Microsoft Graph token'
            $R.Refusal | Should -Not -BeNullOrEmpty
            Should -Invoke -ModuleName $script:moduleName Connect-MgGraph -Times 0
        }

        It 'stays set after GraphConnectFailed' {
            Mock -ModuleName $script:moduleName Connect-MgGraph { throw [System.Exception]::new('handshake failed') }

            $R = Invoke-LatchProbe -Parameters @{ TenantId = '44444444-4444-4444-4444-444444444444'; AuthMethod = 'Interactive' }

            $R.Caught.FullyQualifiedErrorId | Should -BeExactly 'GraphConnectFailed,Initialize-OERAuth'
            $R.Refusal | Should -Not -BeNullOrEmpty
        }

        It 'stays set after ArmTokenAcquisitionFailed''s early return, although the Graph session was connected' {
            Mock -ModuleName $script:moduleName Get-AzToken {
                param($Resource)
                if ($Resource -match 'management') { throw [System.Exception]::new('ARM consent required') }
                [pscustomobject]@{ Token = 'fake-graph-token-NOT-A-REAL-TOKEN'; ExpiresOn = [DateTimeOffset]::UtcNow.AddHours(1); Identity = 'admin@contoso.com'; TenantId = '44444444-4444-4444-4444-444444444444' }
            }

            # Non-terminating: Write-CmdletError without -Terminating, then return.
            $R = InModuleScope $script:moduleName {
                $Err = $null
                $Caught = $null
                try {
                    Initialize-OERAuth -TenantId '44444444-4444-4444-4444-444444444444' -AuthMethod 'Interactive' -IncludeARM -ErrorAction SilentlyContinue -ErrorVariable Err
                } catch { $Caught = $PSItem }
                $Refusal = Get-OERSignInRefusal
                @{ Caught = $Caught; Ids = @($Err | ForEach-Object { $_.FullyQualifiedErrorId }); Refusal = $Refusal }
            }

            $R.Caught | Should -BeNullOrEmpty
            $R.Ids | Should -Contain 'ArmTokenAcquisitionFailed,Initialize-OERAuth'
            $R.Refusal | Should -Not -BeNullOrEmpty
            Should -Invoke -ModuleName $script:moduleName Connect-MgGraph -Times 1 -Exactly
        }

        It 'stays set after TenantMismatch on the Azure Resource Manager token' {
            Mock -ModuleName $script:moduleName Get-AzToken {
                param($Resource)
                $Granted = if ($Resource -match 'management') { '22222222-2222-2222-2222-222222222222' } else { '11111111-1111-1111-1111-111111111111' }
                [pscustomobject]@{ Token = 'fake-token-NOT-A-REAL-TOKEN'; ExpiresOn = [DateTimeOffset]::UtcNow.AddHours(1); Identity = 'admin@contoso.com'; TenantId = $Granted }
            }

            $R = Invoke-LatchProbe -Parameters @{ TenantId = '11111111-1111-1111-1111-111111111111'; AuthMethod = 'Interactive'; IncludeARM = $true }

            $R.Caught.FullyQualifiedErrorId | Should -BeExactly 'TenantMismatch,Initialize-OERAuth'
            $R.Caught.Exception.Message | Should -Match 'Azure Resource Manager token'
            $R.Refusal | Should -Not -BeNullOrEmpty
        }
    }

    Context 'released after a success' {
        It 'is released after a cached return' {
            Connect-OwnSession

            $R = Invoke-LatchProbe -Parameters @{ TenantId = '44444444-4444-4444-4444-444444444444'; AuthMethod = 'Interactive' }

            $R.Caught | Should -BeNullOrEmpty
            $R.Refusal | Should -BeNullOrEmpty
            # The probe was a cache hit: the one token is the connect's.
            Should -Invoke -ModuleName $script:moduleName Get-AzToken -Times 1 -Exactly
            Should -Invoke -ModuleName $script:moduleName Connect-MgGraph -Times 1 -Exactly
        }

        It 'is released after a new connection for Microsoft Graph only' {
            $R = Invoke-LatchProbe -Parameters @{ TenantId = '44444444-4444-4444-4444-444444444444'; AuthMethod = 'Interactive' }

            $R.Caught | Should -BeNullOrEmpty
            $R.Refusal | Should -BeNullOrEmpty
            Should -Invoke -ModuleName $script:moduleName Get-AzToken -Times 1 -Exactly
            Should -Invoke -ModuleName $script:moduleName Connect-MgGraph -Times 1 -Exactly
        }

        It 'is released after a new connection for Microsoft Graph and Azure Resource Manager' {
            $R = Invoke-LatchProbe -Parameters @{ TenantId = '44444444-4444-4444-4444-444444444444'; AuthMethod = 'Interactive'; IncludeARM = $true }

            $R.Caught | Should -BeNullOrEmpty
            $R.Refusal | Should -BeNullOrEmpty
            Should -Invoke -ModuleName $script:moduleName Get-AzToken -Times 2 -Exactly
            Should -Invoke -ModuleName $script:moduleName Connect-MgGraph -Times 1 -Exactly
        }

        It 'is released after an Azure Resource Manager token is added to a cached Microsoft Graph session' {
            Connect-OwnSession

            $R = Invoke-LatchProbe -Parameters @{ TenantId = '44444444-4444-4444-4444-444444444444'; AuthMethod = 'Interactive'; IncludeARM = $true }

            $R.Caught | Should -BeNullOrEmpty
            $R.Refusal | Should -BeNullOrEmpty
            Should -Invoke -ModuleName $script:moduleName Get-AzToken -Times 2 -Exactly
            Should -Invoke -ModuleName $script:moduleName Connect-MgGraph -Times 1 -Exactly
        }

        It 'is released when a sign-in from the same frame succeeds after a refusal' {
            $R = InModuleScope $script:moduleName {
                $Caught = $null
                try {
                    Initialize-OERAuth -TenantId '44444444-4444-4444-4444-444444444444' -AuthMethod 'ClientSecret' -ClientId '33333333-3333-3333-3333-333333333333'
                } catch { $Caught = $PSItem }
                $AfterRefusal = Get-OERSignInRefusal
                Initialize-OERAuth -TenantId '44444444-4444-4444-4444-444444444444' -AuthMethod 'Interactive'
                $AfterSuccess = Get-OERSignInRefusal
                @{ Caught = $Caught; AfterRefusal = $AfterRefusal; AfterSuccess = $AfterSuccess }
            }

            $R.Caught.FullyQualifiedErrorId | Should -BeExactly 'MissingClientSecret,Initialize-OERAuth'
            $R.AfterRefusal | Should -Not -BeNullOrEmpty
            $R.AfterSuccess | Should -BeNullOrEmpty
        }
    }

    Context 'keyed on the refused command' {
        It 'does not refuse a different, later frame' {
            $First = Invoke-LatchProbe -Parameters @{
                TenantId = '44444444-4444-4444-4444-444444444444'; AuthMethod = 'ClientSecret'; ClientId = '33333333-3333-3333-3333-333333333333'
            }
            $Later = InModuleScope $script:moduleName {
                @{ TableExists = $null -ne $script:_OERSignInLatch; Refusal = @(Get-OERSignInRefusal) }
            }

            $First.Caught.FullyQualifiedErrorId | Should -BeExactly 'MissingClientSecret,Initialize-OERAuth'
            $First.Refusal | Should -Not -BeNullOrEmpty
            # The table exists, so the later read walked its own call stack and found nothing held.
            $Later.TableExists | Should -BeTrue
            $Later.Refusal.Count | Should -Be 0
        }

        It 'keeps the refused command latched, and refuses the sign-in of a command it calls (BL-74)' {
            # The apply handlers' shape: Invoke-OERStructure's sign-in is refused, and a public cmdlet it
            # calls then signs in again without -TenantId, where the cache would answer. Since BL-74
            # that nested sign-in is refused before it latches anything, and the outer command stays
            # latched.
            Connect-OwnSession
            $R = InModuleScope $script:moduleName {
                function Invoke-NestedCommand {
                    [CmdletBinding()]
                    param()
                    $NestedCaught = $null
                    try { Initialize-OERAuth } catch { $NestedCaught = $PSItem }
                    @{ Caught = $NestedCaught; Refusal = Get-OERSignInRefusal }
                }
                function Invoke-RefusedCommand {
                    [CmdletBinding()]
                    param()
                    $Caught = $null
                    try {
                        Initialize-OERAuth -TenantId '11111111-1111-1111-1111-111111111111' -AuthMethod 'ClientSecret' -ClientId '33333333-3333-3333-3333-333333333333'
                    } catch { $Caught = $PSItem }
                    $Nested = Invoke-NestedCommand
                    @{ Caught = $Caught; Nested = $Nested; Outer = Get-OERSignInRefusal }
                }
                Invoke-RefusedCommand
            }

            $R.Caught.FullyQualifiedErrorId | Should -BeExactly 'MissingClientSecret,Initialize-OERAuth'
            $R.Nested.Caught.FullyQualifiedErrorId | Should -BeExactly 'SignInRefused,Initialize-OERAuth'
            $R.Nested.Caught.TargetObject | Should -BeExactly 'Invoke-RefusedCommand'
            # Seen from inside the nested command, the innermost latched frame is the refused outer
            # command's: the nested command latched nothing of its own.
            $R.Nested.Refusal | Should -BeExactly 'Invoke-RefusedCommand'
            $R.Outer | Should -BeExactly 'Invoke-RefusedCommand'
            # The one token and the one connect are Connect-OwnSession's: the nested sign-in made neither.
            Should -Invoke -ModuleName $script:moduleName Get-AzToken -Times 1 -Exactly
            Should -Invoke -ModuleName $script:moduleName Connect-MgGraph -Times 1 -Exactly
        }

        It 'releases only its own entry when a sign-in succeeds: a refused command that is not on the call stack stays latched' {
            # The property the nested test above carried before BL-74: a success releases the entry of
            # the command that signed in, never another command's. Shown here with a refused command
            # that has returned, so BL-74 has no latched frame outside the later command's to refuse.
            Connect-OwnSession
            $R = InModuleScope $script:moduleName {
                function Invoke-RefusedCommand {
                    [CmdletBinding()]
                    param()
                    $Caught = $null
                    try {
                        Initialize-OERAuth -TenantId '44444444-4444-4444-4444-444444444444' -AuthMethod 'ClientSecret' -ClientId '33333333-3333-3333-3333-333333333333'
                    } catch { $Caught = $PSItem }
                    @{ Caught = $Caught; Invocation = $MyInvocation }
                }
                function Invoke-LaterCommand {
                    [CmdletBinding()]
                    param()
                    # Names the tenant: after the refused sign-in the session is uncertain (A10), and a
                    # sign-in that names no tenant would be refused before it could release anything.
                    Initialize-OERAuth -TenantId '44444444-4444-4444-4444-444444444444'
                    @(Get-OERSignInRefusal)
                }
                # Held here, so the weak table cannot drop the entry while the later command runs.
                $Refused = Invoke-RefusedCommand
                $Value = $null
                $Before = $script:_OERSignInLatch.TryGetValue($Refused.Invocation, [ref]$Value)
                $Later = @(Invoke-LaterCommand)
                $After = $script:_OERSignInLatch.TryGetValue($Refused.Invocation, [ref]$Value)
                @{ Caught = $Refused.Caught; Before = $Before; Later = $Later; After = $After }
            }

            $R.Caught.FullyQualifiedErrorId | Should -BeExactly 'MissingClientSecret,Initialize-OERAuth'
            $R.Before | Should -BeTrue
            # The later command's sign-in succeeded and released its own entry...
            $R.Later.Count | Should -Be 0
            # ...and only its own: the refused command is still latched.
            $R.After | Should -BeTrue
            # The later sign-in was the cache hit, not a new connection.
            Should -Invoke -ModuleName $script:moduleName Get-AzToken -Times 1 -Exactly
            Should -Invoke -ModuleName $script:moduleName Connect-MgGraph -Times 1 -Exactly
        }
    }

    Context 'refused under a latched outer command (BL-74)' {
        # A command whose own sign-in was refused carries on past the refusal outside any try, and the
        # cmdlets it calls sign in again without -TenantId. Initialize-OERAuth refuses such a nested
        # sign-in before it latches its caller and before any token call. The probe's outer command is
        # latched by its own invocation, as Lock-OERSignIn latches a caller, and calls a nested command
        # that signs in. The state is an interactive session for tenant A whose Microsoft Graph token
        # expires within five minutes, so a nested sign-in that got past the check would renew it with
        # Get-AzToken and Connect-MgGraph.
        BeforeAll {
            function script:Invoke-NestedUnderLatchProbe {
                param([switch]$LatchOuter, [hashtable]$NestedParameters = @{})
                InModuleScope $script:moduleName -Parameters @{ LatchOuter = [bool]$LatchOuter; NestedParameters = $NestedParameters } {
                    param($LatchOuter, $NestedParameters)
                    $Holder = @{ Caught = $null; Nested = $null; OuterRefusal = $null }
                    function Invoke-NestedCommand {
                        [CmdletBinding()]
                        param([hashtable]$AuthParams)
                        $Holder.Nested = $MyInvocation
                        Initialize-OERAuth @AuthParams
                    }
                    function Invoke-OuterCommand {
                        [CmdletBinding()]
                        param([bool]$Latch, [hashtable]$AuthParams)
                        if ($Latch) {
                            if ($null -eq $script:_OERSignInLatch) {
                                $script:_OERSignInLatch = [System.Runtime.CompilerServices.ConditionalWeakTable[object, object]]::new()
                            }
                            $script:_OERSignInLatch.AddOrUpdate($MyInvocation, $true)
                        }
                        try { Invoke-NestedCommand -AuthParams $AuthParams } catch { $Holder.Caught = $PSItem }
                        $Holder.OuterRefusal = Get-OERSignInRefusal
                    }
                    Invoke-OuterCommand -Latch $LatchOuter -AuthParams $NestedParameters
                    $Value = $null
                    $Holder.NestedLatched = $null -ne $script:_OERSignInLatch -and
                        $script:_OERSignInLatch.TryGetValue($Holder.Nested, [ref]$Value)
                    $Holder
                }
            }
        }

        BeforeEach {
            InModuleScope $script:moduleName {
                $script:_OERAuthState = @{
                    TenantId         = '44444444-4444-4444-4444-444444444444'
                    AuthMethod       = 'Interactive'
                    ClientId         = ''
                    Environment      = 'Global'
                    Account          = 'admin@contoso.com'
                    GraphTokenExpiry = [DateTime]::UtcNow.AddMinutes(2)
                    ArmToken         = $null
                    ArmTokenExpiry   = $null
                    ArmResourceUrl   = $null
                    ClaimsSatisfied  = $false
                }
            }
        }

        It 'refuses with SignInRefused naming the outer command, before Get-AzToken and Connect-MgGraph, when a command outside its caller is latched' {
            $R = Invoke-NestedUnderLatchProbe -LatchOuter

            # The token call and the connection first: a nested sign-in that got past the check would
            # make both.
            Should -Invoke -ModuleName $script:moduleName Get-AzToken -Times 0 -Exactly
            Should -Invoke -ModuleName $script:moduleName Connect-MgGraph -Times 0 -Exactly
            $R.Caught.FullyQualifiedErrorId | Should -BeExactly 'SignInRefused,Initialize-OERAuth'
            $R.Caught.CategoryInfo.Category | Should -Be 'AuthenticationError'
            $R.Caught.TargetObject | Should -BeExactly 'Invoke-OuterCommand'

            # Not vacuous: the same nested sign-in under an outer command that is not latched renews
            # the token.
            $Control = Invoke-NestedUnderLatchProbe
            $Control.Caught | Should -BeNullOrEmpty
            Should -Invoke -ModuleName $script:moduleName Get-AzToken -Times 1 -Exactly
            Should -Invoke -ModuleName $script:moduleName Connect-MgGraph -Times 1 -Exactly
        }

        It 'leaves the calling command unlatched when it refuses (the check stands before Lock-OERSignIn)' {
            $R = Invoke-NestedUnderLatchProbe -LatchOuter

            $R.Caught.FullyQualifiedErrorId | Should -BeExactly 'SignInRefused,Initialize-OERAuth'
            $R.Nested | Should -BeOfType ([System.Management.Automation.InvocationInfo])
            $R.NestedLatched | Should -BeFalse
            # The outer command stays latched: it still refuses every request it makes.
            $R.OuterRefusal | Should -BeExactly 'Invoke-OuterCommand'

            # Not vacuous: a nested sign-in refused for a reason of its own, under no latched outer
            # command, is found latched by the same lookup.
            $Control = Invoke-NestedUnderLatchProbe -NestedParameters @{
                TenantId = '44444444-4444-4444-4444-444444444444'; AuthMethod = 'ClientSecret'; ClientId = '33333333-3333-3333-3333-333333333333'
            }
            $Control.Caught.FullyQualifiedErrorId | Should -BeExactly 'MissingClientSecret,Initialize-OERAuth'
            $Control.NestedLatched | Should -BeTrue
        }
    }

    Context 'refused under a superseded outer command (BL-91)' {
        # A command whose sign-in another command has since replaced carries on, and the cmdlets it
        # calls sign in again without -TenantId. Initialize-OERAuth refuses such a nested sign-in before
        # it latches its caller and before any token call (Get-OERSignInSupersession -OutsideCaller). The
        # probe's outer command remembers the identity the state carries (Register-OERSignInIdentity, as
        # Initialize-OERAuth does where it releases the latch) and, with -Supersede, then switches the
        # state's tenant the way a later pipeline command's sign-in would. The state is an interactive
        # session whose Microsoft Graph token expires within five minutes (or in an hour, with
        # -ExpiryMinutes), so a nested sign-in that got past the check would renew it with Get-AzToken and
        # Connect-MgGraph (or answer from the cache).
        BeforeAll {
            function script:Invoke-NestedUnderSupersededProbe {
                param([switch]$Supersede, [switch]$LatchOuter, [int]$ExpiryMinutes = 2, [object]$Marker = $false)
                InModuleScope $script:moduleName -Parameters @{
                    Supersede = [bool]$Supersede; LatchOuter = [bool]$LatchOuter; ExpiryMinutes = $ExpiryMinutes; Marker = $Marker
                } {
                    param($Supersede, $LatchOuter, $ExpiryMinutes, $Marker)
                    # A fresh interactive session for tenant A on every probe: a probe switches the state.
                    $script:_OERAuthState = @{
                        TenantId         = '44444444-4444-4444-4444-444444444444'
                        AuthMethod       = 'Interactive'
                        ClientId         = ''
                        Environment      = 'Global'
                        Account          = 'admin@contoso.com'
                        GraphTokenExpiry = [DateTime]::UtcNow.AddMinutes($ExpiryMinutes)
                        ArmToken         = $null
                        ArmTokenExpiry   = $null
                        ArmResourceUrl   = $null
                        ClaimsSatisfied  = $false
                    }
                    $script:_OERSessionUncertain = $Marker
                    $Holder = @{ Caught = $null; Nested = $null; OuterRefusal = $null; MarkerBefore = $Marker }
                    function Invoke-NestedCommand {
                        [CmdletBinding()]
                        param()
                        $Holder.Nested = $MyInvocation
                        Initialize-OERAuth
                    }
                    function Invoke-OuterCommand {
                        [CmdletBinding()]
                        param([bool]$Supersede, [bool]$Latch)
                        Register-OERSignInIdentity -Invocation $MyInvocation
                        if ($Latch) {
                            if ($null -eq $script:_OERSignInLatch) {
                                $script:_OERSignInLatch = [System.Runtime.CompilerServices.ConditionalWeakTable[object, object]]::new()
                            }
                            $script:_OERSignInLatch.AddOrUpdate($MyInvocation, $true)
                        }
                        if ($Supersede) {
                            # What a later pipeline command's sign-in does to the state.
                            $script:_OERAuthState.TenantId = '55555555-5555-5555-5555-555555555555'
                        }
                        try { Invoke-NestedCommand } catch { $Holder.Caught = $PSItem }
                        $Holder.OuterRefusal = Get-OERSignInRefusal
                    }
                    Invoke-OuterCommand -Supersede $Supersede -Latch $LatchOuter
                    $Value = $null
                    $Holder.NestedLatched = $null -ne $script:_OERSignInLatch -and
                        $script:_OERSignInLatch.TryGetValue($Holder.Nested, [ref]$Value)
                    $Holder.NestedRemembered = $null -ne $script:_OERSignInIdentity -and
                        $script:_OERSignInIdentity.TryGetValue($Holder.Nested, [ref]$Value)
                    $Holder.MarkerAfter = $script:_OERSessionUncertain
                    $Holder
                }
            }
        }

        It 'refuses with SignInSuperseded naming the outer command, before Get-AzToken and Connect-MgGraph, when a command outside its caller remembers another identity' {
            $R = Invoke-NestedUnderSupersededProbe -Supersede

            # The token call and the connection first: a nested sign-in that got past the check would
            # make both.
            Should -Invoke -ModuleName $script:moduleName Get-AzToken -Times 0 -Exactly
            Should -Invoke -ModuleName $script:moduleName Connect-MgGraph -Times 0 -Exactly
            $R.Caught.FullyQualifiedErrorId | Should -BeExactly 'SignInSuperseded,Initialize-OERAuth'
            $R.Caught.CategoryInfo.Category | Should -Be 'AuthenticationError'
            $R.Caught.TargetObject | Should -BeExactly 'Invoke-OuterCommand'
            $R.Caught.Exception.Message | Should -Match 'Invoke-OuterCommand'

            # Not vacuous: the same nested sign-in under an outer command that remembers the identity
            # the state carries renews the token.
            $Control = Invoke-NestedUnderSupersededProbe
            $Control.Caught | Should -BeNullOrEmpty
            Should -Invoke -ModuleName $script:moduleName Get-AzToken -Times 1 -Exactly
            Should -Invoke -ModuleName $script:moduleName Connect-MgGraph -Times 1 -Exactly
        }

        It 'refuses even where the cached return would have answered' {
            $R = Invoke-NestedUnderSupersededProbe -Supersede -ExpiryMinutes 60

            $R.Caught.FullyQualifiedErrorId | Should -BeExactly 'SignInSuperseded,Initialize-OERAuth'
            $R.Caught.TargetObject | Should -BeExactly 'Invoke-OuterCommand'
            Should -Invoke -ModuleName $script:moduleName Get-AzToken -Times 0 -Exactly

            # Not vacuous: with no supersession the same call is answered from the cache, with no token
            # call, and the nested command releases its latch and remembers its identity.
            $Control = Invoke-NestedUnderSupersededProbe -ExpiryMinutes 60
            $Control.Caught | Should -BeNullOrEmpty
            $Control.NestedLatched | Should -BeFalse
            $Control.NestedRemembered | Should -BeTrue
            Should -Invoke -ModuleName $script:moduleName Get-AzToken -Times 0 -Exactly
            Should -Invoke -ModuleName $script:moduleName Connect-MgGraph -Times 0 -Exactly
        }

        It 'leaves the calling command unlatched and unremembered, and the session-uncertain marker as it was (the check stands before Lock-OERSignIn)' {
            $Clear = Invoke-NestedUnderSupersededProbe -Supersede -Marker $false

            $Clear.Caught.FullyQualifiedErrorId | Should -BeExactly 'SignInSuperseded,Initialize-OERAuth'
            $Clear.Nested | Should -BeOfType ([System.Management.Automation.InvocationInfo])
            $Clear.NestedLatched | Should -BeFalse
            $Clear.NestedRemembered | Should -BeFalse
            $Clear.MarkerBefore | Should -BeFalse
            $Clear.MarkerAfter | Should -BeFalse
            # The outer command is not latched either: the transports refuse its requests by the
            # supersession gate, not the latch.
            $Clear.OuterRefusal | Should -BeNullOrEmpty

            # A marker that was set stays set.
            $Set = Invoke-NestedUnderSupersededProbe -Supersede -Marker $true
            $Set.Caught.FullyQualifiedErrorId | Should -BeExactly 'SignInSuperseded,Initialize-OERAuth'
            $Set.MarkerAfter | Should -BeTrue

            # Not vacuous: a nested sign-in refused for a reason of its own is found latched, and
            # sets the marker, by the same lookups.
            $Control = InModuleScope $script:moduleName {
                $script:_OERSessionUncertain = $false
                $Holder = @{ Caught = $null }
                function Invoke-OwnRefusalCommand {
                    [CmdletBinding()]
                    param()
                    try {
                        Initialize-OERAuth -TenantId '44444444-4444-4444-4444-444444444444' -AuthMethod 'ClientSecret' -ClientId '33333333-3333-3333-3333-333333333333'
                    } catch { $Holder.Caught = $PSItem }
                    $Holder.Latched = $null -ne (Get-OERSignInRefusal)
                }
                Invoke-OwnRefusalCommand
                $Holder.Marker = $script:_OERSessionUncertain
                $Holder
            }
            $Control.Caught.FullyQualifiedErrorId | Should -BeExactly 'MissingClientSecret,Initialize-OERAuth'
            $Control.Latched | Should -BeTrue
            $Control.Marker | Should -BeTrue
        }

        It 'refuses with SignInRefused (BL-74 first) when the outer command is both latched and superseded' {
            $R = Invoke-NestedUnderSupersededProbe -Supersede -LatchOuter

            $R.Caught.FullyQualifiedErrorId | Should -BeExactly 'SignInRefused,Initialize-OERAuth'
            $R.Caught.TargetObject | Should -BeExactly 'Invoke-OuterCommand'
            Should -Invoke -ModuleName $script:moduleName Get-AzToken -Times 0 -Exactly
            Should -Invoke -ModuleName $script:moduleName Connect-MgGraph -Times 0 -Exactly
        }

        It 'does not refuse a nested sign-in under an outer command that remembers the identity the state carries' {
            $R = Invoke-NestedUnderSupersededProbe -ExpiryMinutes 60

            $R.Caught | Should -BeNullOrEmpty
            $R.NestedRemembered | Should -BeTrue
            $R.OuterRefusal | Should -BeNullOrEmpty
            # A cache hit: no token call and no connection.
            Should -Invoke -ModuleName $script:moduleName Get-AzToken -Times 0 -Exactly
            Should -Invoke -ModuleName $script:moduleName Connect-MgGraph -Times 0 -Exactly
        }

        It 'does not refuse a command that was itself superseded: its own frame never counts, it signs in again and its memory is replaced' {
            $R = InModuleScope $script:moduleName {
                $script:_OERAuthState = @{
                    TenantId         = '44444444-4444-4444-4444-444444444444'
                    AuthMethod       = 'Interactive'
                    ClientId         = ''
                    Environment      = 'Global'
                    Account          = 'admin@contoso.com'
                    GraphTokenExpiry = [DateTime]::UtcNow.AddMinutes(2)
                    ArmToken         = $null
                    ArmTokenExpiry   = $null
                    ArmResourceUrl   = $null
                    ClaimsSatisfied  = $false
                }
                $Holder = @{ Caught = $null }
                function Invoke-SupersededCaller {
                    [CmdletBinding()]
                    param()
                    Register-OERSignInIdentity -Invocation $MyInvocation
                    $Before = $null
                    $null = $script:_OERSignInIdentity.TryGetValue($MyInvocation, [ref]$Before)
                    # What a later sign-in does to the state: another client.
                    $script:_OERAuthState.ClientId = '33333333-3333-3333-3333-333333333333'
                    $Holder.Before = $Before
                    $Holder.StateBefore = Get-OERSignInIdentity
                    $Holder.Superseded = Get-OERSignInSupersession
                    try {
                        Initialize-OERAuth -TenantId '44444444-4444-4444-4444-444444444444' -AuthMethod 'Interactive'
                    } catch { $Holder.Caught = $PSItem }
                    $After = $null
                    $null = $script:_OERSignInIdentity.TryGetValue($MyInvocation, [ref]$After)
                    $Holder.After = $After
                    $Holder.Identity = Get-OERSignInIdentity
                }
                Invoke-SupersededCaller
                $Holder
            }

            # Not vacuous: before it signs in again, the command IS superseded (the whole-stack read
            # names it), and its remembered identity is not the state's.
            $R.Superseded | Should -BeExactly 'Invoke-SupersededCaller'
            $R.Before | Should -Not -BeExactly $R.StateBefore
            # Then it signed in as a user of that tenant and its memory was replaced.
            $R.Caught | Should -BeNullOrEmpty
            $R.After | Should -BeExactly $R.Identity
            Should -Invoke -ModuleName $script:moduleName Get-AzToken -Times 1 -Exactly
            Should -Invoke -ModuleName $script:moduleName Connect-MgGraph -Times 1 -Exactly
        }
    }

    Context 'a sign-in nested in a superseded command, in a script with no try above it (BL-91)' {
        BeforeAll {
            . "$PSScriptRoot/../TestHelpers/OERConfirmHost.ps1"
            # The real Initialize-OERAuth and the real Get-OERGroup run in a runspace. The outer command
            # signs in as tenant 6666 (a real success, remembered), the log is emptied, and then the state
            # is switched to another tenant with the Graph token near expiry -- what a later pipeline
            # command's sign-in does -- before Get-OERGroup, which signs in again without -TenantId, is
            # called with no try anywhere above it. Every token, connection and request the module could
            # make is replaced by a function that logs a line, so an empty log proves nothing was
            # requested.
            function script:New-SupersededNoTryScenario {
                param([string]$Log, [string]$Supersede)
                [scriptblock]::Create((@'
Import-Module Omnicit.EntraRBAC -Force -ErrorAction Stop
& (Get-Module Omnicit.EntraRBAC) {
    $script:_OERAuthState = $null
    $script:_OERSessionUncertain = $null
    $script:_OERInteractiveCredential = $null
    Set-Item -Path function:script:Test-OERHostNonInteractive -Value { $false }
    Set-Item -Path function:script:Get-AzToken -Value {
        param($ClientId, $Resource, $Tenant, $Scope, $Interactive, $Force, $CredentialPrecedence, $ErrorAction, $WarningAction)
        [System.IO.File]::AppendAllText('#LOG#', "TOKEN $Resource`n")
        [pscustomobject]@{
            Token     = 'NOT-A-REAL-TOKEN-bl91'
            ExpiresOn = [DateTimeOffset]::UtcNow.AddHours(1)
            Identity  = 'admin@contoso.com'
            TenantId  = '66666666-6666-6666-6666-666666666666'
        }
    }
    Set-Item -Path function:script:Get-OERTokenObjectId -Value { '88888888-8888-8888-8888-888888888888' }
    Set-Item -Path function:script:Connect-MgGraph -Value { [System.IO.File]::AppendAllText('#LOG#', "CONNECT`n") }
    Set-Item -Path function:script:Get-MgContext -Value {
        [pscustomobject]@{ AuthType = 'UserProvidedAccessToken'; TokenCredentialType = 'UserProvidedAccessToken'
            ClientId = '11111111-1111-1111-1111-111111111111'; TenantId = '66666666-6666-6666-6666-666666666666'
            Account = 'admin@contoso.com'; AppName = 'oer-test-app'; Environment = 'Global'; Scopes = @('Group.ReadWrite.All') }
    }
    Set-Item -Path function:script:Invoke-MgGraphRequest -Value { [System.IO.File]::AppendAllText('#LOG#', "GRAPH`n") }
    Set-Item -Path function:script:Invoke-WebRequest -Value { [System.IO.File]::AppendAllText('#LOG#', "ARM`n") }
    Set-Item -Path function:script:Resolve-OERTenantDomain -Value { [System.IO.File]::AppendAllText('#LOG#', "LOOKUP`n"); '66666666-6666-6666-6666-666666666666' }
    function script:Invoke-OuterCommand {
        [CmdletBinding()]
        param([bool]$Supersede)
        Initialize-OERAuth -TenantId '66666666-6666-6666-6666-666666666666' -AuthMethod 'Interactive'
        [System.IO.File]::WriteAllText('#LOG#', '')
        if ($Supersede) {
            # The identity's tenant term is the tenant the Graph token was issued for, so both move.
            $script:_OERAuthState.TenantId = '77777777-7777-7777-7777-777777777777'
            $script:_OERAuthState.TokenTenantId = '77777777-7777-7777-7777-777777777777'
        }
        $script:_OERAuthState.GraphTokenExpiry = [DateTime]::UtcNow.AddMinutes(2)
        Get-OERGroup -Group 'g1' -ErrorAction Continue
    }
}
$All = @(& (Get-Module Omnicit.EntraRBAC) { Invoke-OuterCommand -Supersede $#SUPERSEDE# } 2>&1)
foreach ($E in $All) { "ERR:$($E.FullyQualifiedErrorId)" }
# The stubs of a transport name above shadow the tripwire's replacements in this runspace's copy of the
# module, and the tripwire check after the scenario reads that scope: removed here (the nearest definition,
# which is the stub), so the check sees the replacements again.
& (Get-Module Omnicit.EntraRBAC) {
    foreach ($Name in 'Get-AzToken', 'Connect-MgGraph', 'Invoke-MgGraphRequest', 'Invoke-WebRequest') {
        Remove-Item -Path ('function:' + $Name) -ErrorAction SilentlyContinue
    }
}
'END'
'@).Replace('#LOG#', $Log.Replace("'", "''")).Replace('#SUPERSEDE#', $Supersede))
            }
        }

        It 'raises SignInSuperseded for the nested sign-in, then for the command''s own request, requests no token, no connection and nothing else, and carries on' {
            $Log = Join-Path $TestDrive ('{0}.log' -f [guid]::NewGuid())
            $Run = Invoke-OERWithConfirmAnswer -Answer '&Yes' -Script (New-SupersededNoTryScenario -Log $Log -Supersede 'true')

            $Run.Output[-1] | Should -BeExactly 'END'
            @($Run.Output | Where-Object { $_ -like 'ERR:*' }) | Should -Be @(
                'ERR:SignInSuperseded,Initialize-OERAuth'
                'ERR:SignInSuperseded,Get-OERGroup'
            )
            if (Test-Path -LiteralPath $Log) { @(Get-Content -LiteralPath $Log) | Should -BeNullOrEmpty }
            $Run.Warnings | Should -BeNullOrEmpty
        }

        It 'is not raised in an unchanged session: the nested sign-in renews the token and the command sends its request' {
            $Log = Join-Path $TestDrive ('{0}.log' -f [guid]::NewGuid())
            $Run = Invoke-OERWithConfirmAnswer -Answer '&Yes' -Script (New-SupersededNoTryScenario -Log $Log -Supersede 'false')

            $Run.Output[-1] | Should -BeExactly 'END'
            @($Run.Output | Where-Object { $_ -like 'ERR:SignInSuperseded*' }) | Should -BeNullOrEmpty
            # Not vacuous: the sign-in the refusal above prevents does reach the token call, the
            # connection and the request here.
            $Lines = @(Get-Content -LiteralPath $Log)
            ($Lines -join ',') | Should -Match 'TOKEN'
            ($Lines -join ',') | Should -Match 'CONNECT'
            ($Lines -join ',') | Should -Match 'GRAPH'
        }
    }

    Context 'what the latch table stores' {
        # The keys are the commands' own invocation objects, which carry their bound parameters (a
        # tenant among them); what this checks is that every value is $true, every key is an
        # InvocationInfo, and no module variable is added but the two below -- not that a key holds
        # nothing. The latch adds one, _OERSignInLatch; the session-uncertain marker's own helper,
        # Set-OERSessionUncertain, adds the other, _OERSessionUncertain, on its first use. Both are
        # removed before the measurement, so it does not depend on this Describe's BeforeEach, or an
        # earlier test, having created the marker's variable already.
        It 'stores the boolean $true as every value, keys every entry on an InvocationInfo, and adds no module variable but _OERSignInLatch and the session-uncertain marker''s _OERSessionUncertain' {
            Mock -ModuleName $script:moduleName Get-AzToken {
                [pscustomobject]@{ Token = 'fake-graph-token-NOT-A-REAL-TOKEN'; ExpiresOn = [DateTimeOffset]::UtcNow.AddHours(1); Identity = 'admin@contoso.com'; TenantId = '22222222-2222-2222-2222-222222222222' }
            }

            $R = InModuleScope $script:moduleName {
                Remove-Variable -Scope Script -Name _OERSignInLatch -ErrorAction Ignore
                Remove-Variable -Scope Script -Name _OERSessionUncertain -ErrorAction Ignore
                $Before = @((Get-Variable -Scope Script).Name)
                $Caught = $null
                try {
                    Initialize-OERAuth -TenantId '11111111-1111-1111-1111-111111111111' -AuthMethod 'Interactive'
                } catch { $Caught = $PSItem }
                $After = @((Get-Variable -Scope Script).Name)
                $Entries = @(foreach ($Pair in $script:_OERSignInLatch) { $Pair })
                $Refusal = Get-OERSignInRefusal
                @{
                    Caught   = $Caught
                    Refusal  = $Refusal
                    Before   = $Before
                    Added    = @($After | Where-Object { $_ -notin $Before })
                    Values   = @($Entries | ForEach-Object { $_.Value })
                    KeyTypes = @($Entries | ForEach-Object { $_.Key.GetType().FullName })
                }
            }

            # A refusal that names a tenant, after a token the mock issued.
            $R.Caught.FullyQualifiedErrorId | Should -BeExactly 'TenantMismatch,Initialize-OERAuth'
            $R.Caught.Exception.Message | Should -Match '11111111-1111-1111-1111-111111111111'
            $R.Refusal | Should -Not -BeNullOrEmpty
            # Not vacuous: the marker's variable did not exist when the measurement began.
            $R.Before | Should -Not -Contain '_OERSessionUncertain'
            @($R.Added | Sort-Object) | Should -Be @('_OERSessionUncertain', '_OERSignInLatch')
            $R.Values.Count | Should -BeGreaterThan 0
            foreach ($Value in $R.Values) {
                $Value | Should -BeOfType ([bool])
                $Value | Should -BeTrue
            }
            foreach ($KeyType in $R.KeyTypes) {
                $KeyType | Should -BeExactly 'System.Management.Automation.InvocationInfo'
            }
        }
    }
}

Describe 'Initialize-OERAuth sign-in memory (A20)' {
    # In a pipeline every begin block runs first, so a later command's successful sign-in switches the
    # module's state before an earlier command's process block sends anything. Where Initialize-OERAuth
    # releases the latch it therefore also remembers which identity the calling command signed in as,
    # and the transports compare that memory with the state (Get-OERSignInSupersession). These tests
    # read the memory from the SAME frame that called Initialize-OERAuth: each probe below is one
    # InModuleScope script block, whose $MyInvocation is the invocation Lock-OERSignIn returns for it.
    BeforeAll {
        # Calls Initialize-OERAuth with the given parameters from one script block, then reads that
        # script block's own memory. Returns the record it raised (if any), whether the frame is
        # remembered, the remembered value and the identity the state carries afterwards.
        function script:Invoke-MemoryProbe {
            param([hashtable]$Parameters = @{})
            InModuleScope $script:moduleName -Parameters @{ P = $Parameters } {
                param($P)
                $Caught = $null
                try { Initialize-OERAuth @P } catch { $Caught = $PSItem }
                $Remembered = $null
                $Held = $null -ne $script:_OERSignInIdentity -and
                    $script:_OERSignInIdentity.TryGetValue($MyInvocation, [ref]$Remembered)
                @{ Caught = $Caught; Held = $Held; Remembered = $Remembered; Identity = Get-OERSignInIdentity }
            }
        }

        # Connects the module once, from its own script block, as its own session.
        function script:Connect-OwnSession {
            InModuleScope $script:moduleName {
                Initialize-OERAuth -TenantId '44444444-4444-4444-4444-444444444444' -AuthMethod 'Interactive'
            }
        }
    }

    BeforeEach {
        InModuleScope $script:moduleName {
            $script:_OERAuthState = $null
            $script:_OERSessionUncertain = $null
            $script:_OERLastAuthorityHost = $null
            $script:_OERLastTokenRequest = $null
            $script:_OERInteractiveCredential = $null
        }
        $script:CurrentContext = $null
        $script:OwnContext = [pscustomobject]@{
            AuthType = 'UserProvidedAccessToken'; TokenCredentialType = 'UserProvidedAccessToken'
            ClientId = '33333333-3333-3333-3333-333333333333'; TenantId = '44444444-4444-4444-4444-444444444444'
            Account = $null; AppName = 'oer-test-app'; Environment = 'Global'; Scopes = @('Group.ReadWrite.All')
        }
        # Issues each token for the tenant it was requested for, and a distinct string per resource, so
        # a test can show that neither token reaches the memory.
        Mock -ModuleName $script:moduleName Get-AzToken {
            param($ClientId, $ClientSecret, $Resource, $Tenant, $ErrorAction, $Interactive,
                  $DeviceCode, $ManagedIdentity, $ClientCertificate, $ClientCertificatePath,
                  $Scope, $Force, $Claim)
            $Token = if ($Resource -match 'management') { 'fake-arm-token-NOT-A-REAL-TOKEN' } else { 'fake-graph-token-NOT-A-REAL-TOKEN' }
            [pscustomobject]@{ Token = $Token; ExpiresOn = [DateTimeOffset]::UtcNow.AddHours(1); Identity = 'admin@contoso.com'; TenantId = $Tenant }
        }
        # Stateful, like the SDK: no session until Connect-MgGraph, then the module's own.
        Mock -ModuleName $script:moduleName Connect-MgGraph { $script:CurrentContext = $script:OwnContext }
        Mock -ModuleName $script:moduleName Get-MgContext { $script:CurrentContext }
    }

    Context 'remembered after a success' {
        It 'is remembered after a cached return' {
            Connect-OwnSession

            $R = Invoke-MemoryProbe -Parameters @{ TenantId = '44444444-4444-4444-4444-444444444444'; AuthMethod = 'Interactive' }

            $R.Caught | Should -BeNullOrEmpty
            $R.Held | Should -BeTrue
            $R.Remembered | Should -BeOfType ([string])
            $R.Remembered | Should -BeExactly $R.Identity
            $R.Remembered | Should -Match '^44444444-4444-4444-4444-444444444444\n'
            # The probe was a cache hit: the one token is the connect's.
            Should -Invoke -ModuleName $script:moduleName Get-AzToken -Times 1 -Exactly
            Should -Invoke -ModuleName $script:moduleName Connect-MgGraph -Times 1 -Exactly
        }

        It 'is remembered after a new connection for Microsoft Graph only' {
            $R = Invoke-MemoryProbe -Parameters @{ TenantId = '44444444-4444-4444-4444-444444444444'; AuthMethod = 'Interactive' }

            $R.Caught | Should -BeNullOrEmpty
            $R.Held | Should -BeTrue
            $R.Remembered | Should -BeExactly $R.Identity
            $R.Remembered | Should -Match '^44444444-4444-4444-4444-444444444444\n'
            Should -Invoke -ModuleName $script:moduleName Get-AzToken -Times 1 -Exactly
            Should -Invoke -ModuleName $script:moduleName Connect-MgGraph -Times 1 -Exactly
        }

        It 'is remembered after a new connection for Microsoft Graph and Azure Resource Manager' {
            $R = Invoke-MemoryProbe -Parameters @{ TenantId = '44444444-4444-4444-4444-444444444444'; AuthMethod = 'Interactive'; IncludeARM = $true }

            $R.Caught | Should -BeNullOrEmpty
            $R.Held | Should -BeTrue
            $R.Remembered | Should -BeExactly $R.Identity
            $R.Remembered | Should -Match '^44444444-4444-4444-4444-444444444444\n'
            Should -Invoke -ModuleName $script:moduleName Get-AzToken -Times 2 -Exactly
            Should -Invoke -ModuleName $script:moduleName Connect-MgGraph -Times 1 -Exactly
        }

        It 'is remembered after an Azure Resource Manager token is added to a cached Microsoft Graph session, equal to what the Graph-only sign-in remembered' {
            # The Graph-only sign-in, from its own script block, as Connect-OwnSession does; the probe
            # also returns what that frame remembered.
            $Graph = Invoke-MemoryProbe -Parameters @{ TenantId = '44444444-4444-4444-4444-444444444444'; AuthMethod = 'Interactive' }

            $R = Invoke-MemoryProbe -Parameters @{ TenantId = '44444444-4444-4444-4444-444444444444'; AuthMethod = 'Interactive'; IncludeARM = $true }

            $Graph.Caught | Should -BeNullOrEmpty
            $Graph.Held | Should -BeTrue
            $R.Caught | Should -BeNullOrEmpty
            $R.Held | Should -BeTrue
            $R.Remembered | Should -BeExactly $R.Identity
            $R.Remembered | Should -Match '^44444444-4444-4444-4444-444444444444\n'
            # Adding the ARM token changes none of the four terms: a command that adds ARM to a Graph
            # session another command signed in to remembers the same identity.
            $R.Remembered | Should -BeExactly $Graph.Remembered
            Should -Invoke -ModuleName $script:moduleName Get-AzToken -Times 2 -Exactly
            Should -Invoke -ModuleName $script:moduleName Connect-MgGraph -Times 1 -Exactly
        }
    }

    Context 'not remembered after a refusal' {
        # Each refusal below comes after the module's own session is connected, so the state carries an
        # identity throughout: a Register call on a refusal path would have stored it.
        It 'is not remembered after MissingClientSecret' {
            Connect-OwnSession

            $R = Invoke-MemoryProbe -Parameters @{
                TenantId = '44444444-4444-4444-4444-444444444444'; AuthMethod = 'ClientSecret'; ClientId = '33333333-3333-3333-3333-333333333333'
            }

            $R.Caught.FullyQualifiedErrorId | Should -BeExactly 'MissingClientSecret,Initialize-OERAuth'
            $R.Identity | Should -Not -BeNullOrEmpty
            $R.Held | Should -BeFalse
        }

        It 'is not remembered after GraphTokenAcquisitionFailed' {
            Mock -ModuleName $script:moduleName Get-AzToken {
                param($ClientId, $ClientSecret, $Resource, $Tenant, $ErrorAction, $Interactive,
                      $DeviceCode, $ManagedIdentity, $ClientCertificate, $ClientCertificatePath,
                      $Scope, $Force, $Claim)
                if ($Tenant -eq '11111111-1111-1111-1111-111111111111') { throw [System.Exception]::new('AADSTS50076: interaction required') }
                [pscustomobject]@{ Token = 'fake-graph-token-NOT-A-REAL-TOKEN'; ExpiresOn = [DateTimeOffset]::UtcNow.AddHours(1); Identity = 'admin@contoso.com'; TenantId = $Tenant }
            }
            Connect-OwnSession

            $R = Invoke-MemoryProbe -Parameters @{ TenantId = '11111111-1111-1111-1111-111111111111'; AuthMethod = 'Interactive' }

            $R.Caught.FullyQualifiedErrorId | Should -BeExactly 'GraphTokenAcquisitionFailed,Initialize-OERAuth'
            $R.Identity | Should -Not -BeNullOrEmpty
            $R.Held | Should -BeFalse
            Should -Invoke -ModuleName $script:moduleName Connect-MgGraph -Times 1 -Exactly
        }

        It 'is not remembered after ArmTokenAcquisitionFailed''s early return, although the Graph session was connected' {
            Mock -ModuleName $script:moduleName Get-AzToken {
                param($ClientId, $ClientSecret, $Resource, $Tenant, $ErrorAction, $Interactive,
                      $DeviceCode, $ManagedIdentity, $ClientCertificate, $ClientCertificatePath,
                      $Scope, $Force, $Claim)
                if ($Resource -match 'management') { throw [System.Exception]::new('ARM consent required') }
                [pscustomobject]@{ Token = 'fake-graph-token-NOT-A-REAL-TOKEN'; ExpiresOn = [DateTimeOffset]::UtcNow.AddHours(1); Identity = 'admin@contoso.com'; TenantId = $Tenant }
            }

            # Non-terminating: Write-CmdletError without -Terminating, then return.
            $R = InModuleScope $script:moduleName {
                $Err = $null
                $Caught = $null
                try {
                    Initialize-OERAuth -TenantId '44444444-4444-4444-4444-444444444444' -AuthMethod 'Interactive' -IncludeARM -ErrorAction SilentlyContinue -ErrorVariable Err
                } catch { $Caught = $PSItem }
                $Remembered = $null
                $Held = $null -ne $script:_OERSignInIdentity -and
                    $script:_OERSignInIdentity.TryGetValue($MyInvocation, [ref]$Remembered)
                @{ Caught = $Caught; Ids = @($Err | ForEach-Object { $_.FullyQualifiedErrorId }); Held = $Held; Identity = Get-OERSignInIdentity }
            }

            $R.Caught | Should -BeNullOrEmpty
            $R.Ids | Should -Contain 'ArmTokenAcquisitionFailed,Initialize-OERAuth'
            # The state was rebuilt for the connected Graph session before the ARM token failed.
            $R.Identity | Should -Match '^44444444-4444-4444-4444-444444444444\n'
            $R.Held | Should -BeFalse
            Should -Invoke -ModuleName $script:moduleName Connect-MgGraph -Times 1 -Exactly
        }
    }

    Context 'replaced by a later sign-in' {
        It 'replaces the memory when a later sign-in from the same frame succeeds for another tenant' {
            $R = InModuleScope $script:moduleName {
                $Value = $null
                Initialize-OERAuth -TenantId '44444444-4444-4444-4444-444444444444' -AuthMethod 'Interactive'
                $null = $script:_OERSignInIdentity.TryGetValue($MyInvocation, [ref]$Value)
                $First = $Value
                Initialize-OERAuth -TenantId '11111111-1111-1111-1111-111111111111' -AuthMethod 'Interactive'
                $null = $script:_OERSignInIdentity.TryGetValue($MyInvocation, [ref]$Value)
                @{ First = $First; Second = $Value; Identity = Get-OERSignInIdentity; Supersession = @(Get-OERSignInSupersession) }
            }

            $R.First | Should -Match '^44444444-4444-4444-4444-444444444444\n'
            $R.Second | Should -BeExactly $R.Identity
            $R.Second | Should -Match '^11111111-1111-1111-1111-111111111111\n'
            # The frame's own memory now equals the state.
            $R.Supersession.Count | Should -Be 0
            Should -Invoke -ModuleName $script:moduleName Connect-MgGraph -Times 2 -Exactly
        }
    }

    Context 'seen from a nested command' {
        # An outer command signs in, and a command it calls signs in again: to another tenant, to the
        # same one, or adding an ARM token to the same session. Read from inside the nested command,
        # after its own sign-in: only another tenant leaves the outer frame remembering a different
        # identity than the state carries.
        BeforeAll {
            function script:Invoke-NestedProbe {
                param([string]$NestedTenant, [switch]$NestedIncludeARM)
                InModuleScope $script:moduleName -Parameters @{ NestedTenant = $NestedTenant; NestedIncludeARM = [bool]$NestedIncludeARM } {
                    param($NestedTenant, $NestedIncludeARM)
                    function Invoke-NestedCommand {
                        [CmdletBinding()]
                        param([string]$Tenant, [bool]$IncludeARM)
                        Initialize-OERAuth -TenantId $Tenant -AuthMethod 'Interactive' -IncludeARM:$IncludeARM
                        @(Get-OERSignInSupersession)
                    }
                    function Invoke-OuterCommand {
                        [CmdletBinding()]
                        param([string]$Tenant, [bool]$IncludeARM)
                        Initialize-OERAuth -TenantId '44444444-4444-4444-4444-444444444444' -AuthMethod 'Interactive'
                        Invoke-NestedCommand -Tenant $Tenant -IncludeARM $IncludeARM
                    }
                    @{ Supersession = @(Invoke-OuterCommand -Tenant $NestedTenant -IncludeARM $NestedIncludeARM) }
                }
            }
        }

        It 'names the outer command after the nested command signs in to another tenant' {
            $R = Invoke-NestedProbe -NestedTenant '11111111-1111-1111-1111-111111111111'

            $R.Supersession.Count | Should -Be 1
            $R.Supersession[0] | Should -BeExactly 'Invoke-OuterCommand'
            # The nested sign-in was a new connection, not a cache hit.
            Should -Invoke -ModuleName $script:moduleName Connect-MgGraph -Times 2 -Exactly
        }

        It 'returns nothing when the nested command signs in to the same tenant' {
            $R = Invoke-NestedProbe -NestedTenant '44444444-4444-4444-4444-444444444444'

            $R.Supersession.Count | Should -Be 0
            # The nested sign-in was the cache hit.
            Should -Invoke -ModuleName $script:moduleName Get-AzToken -Times 1 -Exactly
        }

        It 'returns nothing when the nested command adds an Azure Resource Manager token for the same tenant' {
            # The apply handlers' shape: an outer command signed in for Microsoft Graph, and an Azure
            # cmdlet it calls adds -IncludeARM to that cached session.
            $R = Invoke-NestedProbe -NestedTenant '44444444-4444-4444-4444-444444444444' -NestedIncludeARM

            $R.Supersession.Count | Should -Be 0
            # The nested sign-in added an ARM token to the cached Graph session: one Graph token, one ARM
            # token, one connect.
            Should -Invoke -ModuleName $script:moduleName Get-AzToken -Times 2 -Exactly
            Should -Invoke -ModuleName $script:moduleName Connect-MgGraph -Times 1 -Exactly
        }
    }

    Context 'what the memory table stores' {
        It 'adds no module variable but _OERSignInIdentity and stores only identity strings that carry no token' {
            # Connected first, so the latch table and every tracker a new connection writes exist
            # before the measurement.
            Connect-OwnSession

            $R = InModuleScope $script:moduleName {
                Remove-Variable -Scope Script -Name _OERSignInIdentity -ErrorAction Ignore
                $Before = @((Get-Variable -Scope Script).Name)
                Initialize-OERAuth -TenantId '11111111-1111-1111-1111-111111111111' -AuthMethod 'Interactive' -IncludeARM
                $After = @((Get-Variable -Scope Script).Name)
                $Entries = @(foreach ($Pair in $script:_OERSignInIdentity) { $Pair })
                @{
                    Added       = @($After | Where-Object { $_ -notin $Before })
                    Values      = @($Entries | ForEach-Object { $_.Value })
                    ValueTypes  = @($Entries | ForEach-Object { $_.Value.GetType().FullName })
                    HasArmToken = $null -ne $script:_OERAuthState.ArmToken
                    Identity    = Get-OERSignInIdentity
                }
            }

            # Not vacuous: the state the identity was read from held an ARM token.
            $R.HasArmToken | Should -BeTrue
            $R.Added | Should -Be @('_OERSignInIdentity')
            $R.Values.Count | Should -Be 1
            $R.Values[0] | Should -BeExactly $R.Identity
            foreach ($ValueType in $R.ValueTypes) {
                $ValueType | Should -BeExactly 'System.String'
            }
            foreach ($Value in $R.Values) {
                $Value | Should -Not -Match 'NOT-A-REAL-TOKEN'
                $Value | Should -Not -Match 'fake-graph-token'
                $Value | Should -Not -Match 'fake-arm-token'
            }
            Should -Invoke -ModuleName $script:moduleName Get-AzToken -Times 3 -Exactly
        }
    }
}

Describe 'Initialize-OERAuth tenant named by domain (BL-12)' {
    # A tenant named by anything but a GUID or 'organizations' is resolved to its tenant ID through
    # Resolve-OERTenantDomain before any token is requested, and a failed lookup refuses the sign-in with
    # a terminating TenantResolutionFailed. Every Context mocks the resolver: no lookup leaves the process.
    BeforeAll {
        # Calls Initialize-OERAuth from one script block and reads the latch from that same script
        # block, the shape of Invoke-LatchProbe in the A19 tests. Returns the record it raised (if any)
        # and the refusal.
        function script:Invoke-DomainProbe {
            param([hashtable]$Parameters = @{})
            InModuleScope $script:moduleName -Parameters @{ P = $Parameters } {
                param($P)
                $Caught = $null
                try { Initialize-OERAuth @P } catch { $Caught = $PSItem }
                $Refusal = Get-OERSignInRefusal
                @{ Caught = $Caught; Refusal = $Refusal }
            }
        }
    }

    BeforeEach {
        InModuleScope $script:moduleName {
            $script:_OERAuthState = $null
            $script:_OERSessionUncertain = $null
            $script:_OERLastAuthorityHost = $null
            $script:_OERLastTokenRequest = $null
            $script:_OERInteractiveCredential = $null
            $script:_OERTenantDomainCache = $null
        }
        $script:ResolverCalls = 0
        $script:CurrentContext = $null
        $script:OwnContext = [pscustomobject]@{
            AuthType = 'UserProvidedAccessToken'; TokenCredentialType = 'UserProvidedAccessToken'
            ClientId = '33333333-3333-3333-3333-333333333333'; TenantId = '11111111-1111-1111-1111-111111111111'
            Account = $null; AppName = 'oer-test-app'; Environment = 'Global'; Scopes = @('Group.ReadWrite.All')
        }
        # Every token is issued for the tenant the resolver mocks below answer with.
        Mock -ModuleName $script:moduleName Get-AzToken {
            param($ClientId, $ClientSecret, $Resource, $Tenant, $ErrorAction, $Interactive,
                  $DeviceCode, $ManagedIdentity, $ClientCertificate, $ClientCertificatePath,
                  $Scope, $Force, $Claim)
            $Token = if ($Resource -match 'management') { 'fake-arm-token-NOT-A-REAL-TOKEN' } else { 'fake-graph-token-NOT-A-REAL-TOKEN' }
            [pscustomobject]@{ Token = $Token; ExpiresOn = [DateTimeOffset]::UtcNow.AddHours(1); Identity = 'admin@contoso.com'; TenantId = '11111111-1111-1111-1111-111111111111' }
        }
        # Stateful, like the SDK: no session until Connect-MgGraph, then the module's own.
        Mock -ModuleName $script:moduleName Connect-MgGraph { $script:CurrentContext = $script:OwnContext }
        Mock -ModuleName $script:moduleName Get-MgContext { $script:CurrentContext }
    }

    Context 'a domain that does not resolve' {
        BeforeEach {
            Mock -ModuleName $script:moduleName Resolve-OERTenantDomain {
                throw [System.InvalidOperationException]::new('did not resolve')
            }
        }

        It 'refuses with TenantResolutionFailed before any token is requested, and builds no AzAuth credential' {
            $R = Invoke-DomainProbe -Parameters @{ TenantId = 'contoso.onmicrosoft.com'; AuthMethod = 'Interactive' }

            $R.Caught.FullyQualifiedErrorId | Should -BeExactly 'TenantResolutionFailed,Initialize-OERAuth'
            $R.Caught.CategoryInfo.Category | Should -Be 'AuthenticationError'
            $R.Caught.TargetObject | Should -BeExactly 'contoso.onmicrosoft.com'
            $R.Caught.Exception.Message | Should -Match ([regex]::Escape("'contoso.onmicrosoft.com'"))
            $R.Caught.Exception.Message | Should -Match 'did not resolve'
            $R.Caught.Exception.InnerException | Should -BeOfType ([System.InvalidOperationException])
            # The positive proof that the lookup was reached, then nothing after it.
            Should -Invoke -ModuleName $script:moduleName Resolve-OERTenantDomain -Times 1 -Exactly
            Should -Invoke -ModuleName $script:moduleName Get-AzToken -Times 0
            Should -Invoke -ModuleName $script:moduleName Connect-MgGraph -Times 0
            InModuleScope $script:moduleName {
                $script:_OERAuthState | Should -BeNullOrEmpty
                # No AzAuth credential was built: the credential-build tracker never moved.
                $script:_OERLastTokenRequest | Should -BeNullOrEmpty
                # Seeded with the commercial authority at entry, before the lookup, and not moved since.
                $script:_OERLastAuthorityHost | Should -BeExactly (Get-OERCloudEndpoint -Environment 'Global').AuthorityHost
            }
        }

        It 'leaves the authority tracker on the commercial authority when a sovereign-cloud lookup fails' {
            # Not vacuous: the sovereign authority differs from the one the entry seeds.
            InModuleScope $script:moduleName {
                (Get-OERCloudEndpoint -Environment 'USGov').AuthorityHost |
                    Should -Not -Be (Get-OERCloudEndpoint -Environment 'Global').AuthorityHost
            }

            $R = Invoke-DomainProbe -Parameters @{ TenantId = 'contoso.onmicrosoft.com'; AuthMethod = 'Interactive'; Environment = 'USGov' }

            $R.Caught.FullyQualifiedErrorId | Should -BeExactly 'TenantResolutionFailed,Initialize-OERAuth'
            Should -Invoke -ModuleName $script:moduleName Resolve-OERTenantDomain -Times 1 -Exactly
            Should -Invoke -ModuleName $script:moduleName Get-AzToken -Times 0
            InModuleScope $script:moduleName {
                $script:_OERLastTokenRequest | Should -BeNullOrEmpty
                $script:_OERLastAuthorityHost | Should -BeExactly (Get-OERCloudEndpoint -Environment 'Global').AuthorityHost
            }
        }

        It 'leaves a cached session for another tenant describing that tenant' {
            Mock -ModuleName $script:moduleName Get-AzToken {
                [pscustomobject]@{ Token = 'fake-graph-token-NOT-A-REAL-TOKEN'; ExpiresOn = [DateTimeOffset]::UtcNow.AddHours(1); Identity = 'admin@contoso.com'; TenantId = '44444444-4444-4444-4444-444444444444' }
            }
            $Before = InModuleScope $script:moduleName {
                Initialize-OERAuth -TenantId '44444444-4444-4444-4444-444444444444' -AuthMethod 'Interactive'
                $script:_OERAuthState.Clone()
            }

            $R = Invoke-DomainProbe -Parameters @{ TenantId = 'contoso.onmicrosoft.com'; AuthMethod = 'Interactive' }

            $R.Caught.FullyQualifiedErrorId | Should -BeExactly 'TenantResolutionFailed,Initialize-OERAuth'
            $After = InModuleScope $script:moduleName { $script:_OERAuthState }
            $Before.TenantId | Should -BeExactly '44444444-4444-4444-4444-444444444444'
            $After.TenantId | Should -BeExactly $Before.TenantId
            $After.TokenTenantId | Should -BeExactly '44444444-4444-4444-4444-444444444444'
            $After.AuthMethod | Should -BeExactly $Before.AuthMethod
            $After.GraphTokenExpiry | Should -Be $Before.GraphTokenExpiry
            $After.GraphSessionFingerprint | Should -BeExactly $Before.GraphSessionFingerprint
            # The one token and the one connect are tenant A's.
            Should -Invoke -ModuleName $script:moduleName Get-AzToken -Times 1 -Exactly
            Should -Invoke -ModuleName $script:moduleName Connect-MgGraph -Times 1 -Exactly
        }

        It 'scrubs the lookup failure from the error list before it reports it' {
            Mock -ModuleName $script:moduleName Remove-OERErrorRecord { }

            $R = Invoke-DomainProbe -Parameters @{ TenantId = 'contoso.onmicrosoft.com'; AuthMethod = 'Interactive' }

            $R.Caught.FullyQualifiedErrorId | Should -BeExactly 'TenantResolutionFailed,Initialize-OERAuth'
            Should -Invoke -ModuleName $script:moduleName Remove-OERErrorRecord -Times 1 -Exactly
            Should -Invoke -ModuleName $script:moduleName Remove-OERErrorRecord -Times 1 -Exactly -ParameterFilter {
                $Record.Exception.Message -eq 'did not resolve'
            }
        }

        It 'leaves the calling command latched' {
            $R = Invoke-DomainProbe -Parameters @{ TenantId = 'contoso.onmicrosoft.com'; AuthMethod = 'Interactive' }

            $R.Caught.FullyQualifiedErrorId | Should -BeExactly 'TenantResolutionFailed,Initialize-OERAuth'
            $R.Refusal | Should -Not -BeNullOrEmpty
        }
    }

    Context 'a domain that resolves' {
        BeforeEach {
            Mock -ModuleName $script:moduleName Resolve-OERTenantDomain {
                $script:ResolverCalls++
                '11111111-1111-1111-1111-111111111111'
            }
        }

        It 'asks the resolver for the domain in the commercial cloud, and still names the domain in the token request' {
            $R = Invoke-DomainProbe -Parameters @{ TenantId = 'contoso.onmicrosoft.com'; AuthMethod = 'Interactive' }

            $R.Caught | Should -BeNullOrEmpty
            Should -Invoke -ModuleName $script:moduleName Resolve-OERTenantDomain -Times 1 -Exactly
            Should -Invoke -ModuleName $script:moduleName Resolve-OERTenantDomain -Times 1 -Exactly -ParameterFilter {
                $Domain -ceq 'contoso.onmicrosoft.com' -and $Environment -ceq 'Global'
            }
            Should -Invoke -ModuleName $script:moduleName Get-AzToken -Times 1 -Exactly -ParameterFilter {
                $Tenant -ceq 'contoso.onmicrosoft.com'
            }
        }

        It 'asks the resolver in the sovereign cloud the sign-in names' {
            $R = Invoke-DomainProbe -Parameters @{ TenantId = 'contoso.onmicrosoft.com'; AuthMethod = 'Interactive'; Environment = 'USGov' }

            $R.Caught | Should -BeNullOrEmpty
            Should -Invoke -ModuleName $script:moduleName Resolve-OERTenantDomain -Times 1 -Exactly
            Should -Invoke -ModuleName $script:moduleName Resolve-OERTenantDomain -Times 1 -Exactly -ParameterFilter {
                $Domain -ceq 'contoso.onmicrosoft.com' -and $Environment -ceq 'USGov'
            }
        }

        It 'asks the resolver for any other label that is not a GUID, ''common'' included' {
            $R = Invoke-DomainProbe -Parameters @{ TenantId = 'common'; AuthMethod = 'Interactive' }

            $R.Caught | Should -BeNullOrEmpty
            Should -Invoke -ModuleName $script:moduleName Resolve-OERTenantDomain -Times 1 -Exactly -ParameterFilter {
                $Domain -ceq 'common' -and $Environment -ceq 'Global'
            }
        }

        It 'releases the latch when the domain resolves and the sign-in succeeds' {
            $R = Invoke-DomainProbe -Parameters @{ TenantId = 'contoso.onmicrosoft.com'; AuthMethod = 'Interactive' }

            $R.Caught | Should -BeNullOrEmpty
            $R.Refusal | Should -BeNullOrEmpty
            Should -Invoke -ModuleName $script:moduleName Resolve-OERTenantDomain -Times 1 -Exactly
        }

        It 'makes no lookup for a tenant named by its GUID' {
            $R = Invoke-DomainProbe -Parameters @{ TenantId = '11111111-1111-1111-1111-111111111111'; AuthMethod = 'Interactive' }

            $R.Caught | Should -BeNullOrEmpty
            Should -Invoke -ModuleName $script:moduleName Resolve-OERTenantDomain -Times 0
            # Not vacuous: the sign-in went past the place of the lookup to its token call.
            Should -Invoke -ModuleName $script:moduleName Get-AzToken -Times 1 -Exactly
        }

        It 'makes no lookup when no tenant is named and there is no session (organizations)' {
            $R = Invoke-DomainProbe -Parameters @{ AuthMethod = 'Interactive' }

            $R.Caught | Should -BeNullOrEmpty
            Should -Invoke -ModuleName $script:moduleName Resolve-OERTenantDomain -Times 0
            Should -Invoke -ModuleName $script:moduleName Get-AzToken -Times 1 -Exactly -ParameterFilter { -not $Tenant }
            InModuleScope $script:moduleName { $script:_OERAuthState.TenantId | Should -BeExactly 'organizations' }
        }

        It 'makes no lookup for -TenantId organizations' {
            $R = Invoke-DomainProbe -Parameters @{ TenantId = 'organizations'; AuthMethod = 'Interactive' }

            $R.Caught | Should -BeNullOrEmpty
            Should -Invoke -ModuleName $script:moduleName Resolve-OERTenantDomain -Times 0
            Should -Invoke -ModuleName $script:moduleName Get-AzToken -Times 1 -Exactly -ParameterFilter { -not $Tenant }
        }

        It 'makes no lookup on a cached return' {
            InModuleScope $script:moduleName { Initialize-OERAuth -TenantId 'contoso.onmicrosoft.com' -AuthMethod 'Interactive' }
            $AfterFirst = $script:ResolverCalls

            InModuleScope $script:moduleName { Initialize-OERAuth -TenantId 'contoso.onmicrosoft.com' -AuthMethod 'Interactive' }

            # Not vacuous: the first, new, sign-in made one lookup.
            $AfterFirst | Should -Be 1
            # The second, identical, sign-in made none.
            ($script:ResolverCalls - $AfterFirst) | Should -Be 0
            # And it was the cached return: the one token is the first sign-in's.
            Should -Invoke -ModuleName $script:moduleName Get-AzToken -Times 1 -Exactly
            Should -Invoke -ModuleName $script:moduleName Connect-MgGraph -Times 1 -Exactly
        }
    }

    Context 'an Azure Resource Manager token added to a cached Microsoft Graph session' {
        # The Microsoft Graph token is cached and only the ARM token is acquired: the sign-in goes past
        # the cached return, so the lookup runs for it too, and a failed lookup stops the ARM token.
        It 'asks the resolver again when only the Azure Resource Manager token is acquired' {
            Mock -ModuleName $script:moduleName Resolve-OERTenantDomain { '11111111-1111-1111-1111-111111111111' }

            InModuleScope $script:moduleName { Initialize-OERAuth -TenantId 'contoso.onmicrosoft.com' -AuthMethod 'Interactive' }
            InModuleScope $script:moduleName { Initialize-OERAuth -TenantId 'contoso.onmicrosoft.com' -AuthMethod 'Interactive' -IncludeARM }

            Should -Invoke -ModuleName $script:moduleName Resolve-OERTenantDomain -Times 2 -Exactly -ParameterFilter {
                $Domain -ceq 'contoso.onmicrosoft.com' -and $Environment -ceq 'Global'
            }
            # One Microsoft Graph token and one ARM token; the Graph session was connected once.
            Should -Invoke -ModuleName $script:moduleName Get-AzToken -Times 2 -Exactly
            Should -Invoke -ModuleName $script:moduleName Connect-MgGraph -Times 1 -Exactly
            InModuleScope $script:moduleName { $script:_OERAuthState.ArmToken | Should -Not -BeNullOrEmpty }
        }

        It 'refuses an ARM-only acquisition with TenantResolutionFailed when its lookup fails, and requests no token' {
            Mock -ModuleName $script:moduleName Resolve-OERTenantDomain {
                $script:ResolverCalls++
                if ($script:ResolverCalls -ge 2) { throw [System.InvalidOperationException]::new('did not resolve') }
                '11111111-1111-1111-1111-111111111111'
            }
            InModuleScope $script:moduleName { Initialize-OERAuth -TenantId 'contoso.onmicrosoft.com' -AuthMethod 'Interactive' }

            $R = Invoke-DomainProbe -Parameters @{ TenantId = 'contoso.onmicrosoft.com'; AuthMethod = 'Interactive'; IncludeARM = $true }

            $R.Caught.FullyQualifiedErrorId | Should -BeExactly 'TenantResolutionFailed,Initialize-OERAuth'
            $R.Refusal | Should -Not -BeNullOrEmpty
            $script:ResolverCalls | Should -Be 2
            # The one token is the first sign-in's Microsoft Graph token: the refused call requested none.
            Should -Invoke -ModuleName $script:moduleName Get-AzToken -Times 1 -Exactly
            Should -Invoke -ModuleName $script:moduleName Get-AzToken -Times 0 -ParameterFilter { $Resource -match 'management' }
            InModuleScope $script:moduleName {
                $script:_OERAuthState.TenantId | Should -BeExactly 'contoso.onmicrosoft.com'
                $script:_OERAuthState.ArmToken | Should -BeNullOrEmpty
            }
        }
    }

    Context 'a sign-in refused before the lookup' {
        # The lookup stands after the app-only refusal and the credential checks, so a sign-in either
        # one refuses sends no lookup: a request that cannot be made is not worth a network call.
        BeforeEach {
            Mock -ModuleName $script:moduleName Resolve-OERTenantDomain {
                $script:ResolverCalls++
                '11111111-1111-1111-1111-111111111111'
            }
        }

        It 'makes no lookup for a domain sign-in refused with MissingClientSecret' {
            $R = Invoke-DomainProbe -Parameters @{
                TenantId = 'contoso.onmicrosoft.com'; AuthMethod = 'ClientSecret'; ClientId = '33333333-3333-3333-3333-333333333333'
            }

            # Positive proof: the sign-in reached the credential check and was refused there.
            $R.Caught.FullyQualifiedErrorId | Should -BeExactly 'MissingClientSecret,Initialize-OERAuth'
            Should -Invoke -ModuleName $script:moduleName Resolve-OERTenantDomain -Times 0
            Should -Invoke -ModuleName $script:moduleName Get-AzToken -Times 0
        }

        It 'makes no lookup for a domain sign-in refused with AppOnlySessionCredentialUnavailable' {
            InModuleScope $script:moduleName {
                # An app-only session for the domain, which the module did not connect itself, holding
                # no ARM token: an -IncludeARM call inherits it and needs a token it cannot acquire.
                $script:_OERAuthState = @{
                    TenantId         = 'contoso.onmicrosoft.com'
                    AuthMethod       = 'ClientSecret'
                    ClientId         = '33333333-3333-3333-3333-333333333333'
                    Environment      = 'Global'
                    Account          = 'sp'
                    GraphTokenExpiry = [DateTime]::UtcNow.AddHours(1)
                    ArmToken         = $null
                    ArmTokenExpiry   = $null
                    ArmResourceUrl   = $null
                    ClaimsSatisfied  = $false
                }
            }

            $R = Invoke-DomainProbe -Parameters @{ TenantId = 'contoso.onmicrosoft.com'; IncludeARM = $true }

            # Positive proof: the sign-in got past the cached return to the app-only refusal.
            $R.Caught.FullyQualifiedErrorId | Should -BeExactly 'AppOnlySessionCredentialUnavailable,Initialize-OERAuth'
            Should -Invoke -ModuleName $script:moduleName Resolve-OERTenantDomain -Times 0
            Should -Invoke -ModuleName $script:moduleName Get-AzToken -Times 0
        }
    }
}

Describe 'Initialize-OERAuth session uncertain after a refused sign-in (A10)' {
    # BL-89: outside any try a script carries on past a refused sign-in, and the module's session still
    # belongs to the tenant before it. In
    # foreach ($T in $Profiles) { Connect-OER -TenantAlias $T; Invoke-OERStructure -Path "$T.json" -Prune }
    # a refused Connect-OER left the previous tenant's session in place, and the next Invoke-OERStructure,
    # which names no tenant, applied X's document there, prune included. A sign-in that does not succeed
    # therefore leaves the session uncertain, and while it is, a sign-in that names no tenant is refused
    # with SignInRefused before it requests a token or sends anything. Each probe below calls
    # Initialize-OERAuth from a command of its own, Invoke-UncertainProbeCommand -- the shape of a
    # public cmdlet -- and reads the latch from that same command. The tenants are invented: A is
    # 4444..., and every token is issued for the tenant it was requested for.
    BeforeAll {
        # Returns the record the sign-in raised (if any), the ids of the errors it wrote (with -Quiet,
        # for the non-terminating ArmTokenAcquisitionFailed) and the probe command's own latch.
        function script:Invoke-UncertainProbe {
            param([hashtable]$Parameters = @{}, [switch]$Quiet)
            InModuleScope $script:moduleName -Parameters @{ P = $Parameters; Quiet = [bool]$Quiet } {
                param($P, $Quiet)
                function Invoke-UncertainProbeCommand {
                    [CmdletBinding()]
                    param([hashtable]$AuthParams, [bool]$Quiet)
                    $Caught = $null
                    $Errs = @()
                    try {
                        if ($Quiet) {
                            Initialize-OERAuth @AuthParams -ErrorAction SilentlyContinue -ErrorVariable Errs
                        }
                        else {
                            Initialize-OERAuth @AuthParams
                        }
                    } catch { $Caught = $PSItem }
                    @{
                        Caught  = $Caught
                        Ids     = @(@($Errs) | ForEach-Object { [string]$_.FullyQualifiedErrorId })
                        Refusal = Get-OERSignInRefusal
                    }
                }
                Invoke-UncertainProbeCommand -AuthParams $P -Quiet $Quiet
            }
        }

        # Connects the module once, from its own script block, as its own session for tenant A.
        function script:Connect-OwnSession {
            InModuleScope $script:moduleName {
                Initialize-OERAuth -TenantId '44444444-4444-4444-4444-444444444444' -AuthMethod 'Interactive'
            }
        }

        # A sign-in refused for a reason of its own after the latch: an explicit client secret sign-in
        # for tenant A with no secret.
        function script:Invoke-RefusedSignIn {
            $Refused = Invoke-UncertainProbe -Parameters @{
                TenantId = '44444444-4444-4444-4444-444444444444'; AuthMethod = 'ClientSecret'; ClientId = '33333333-3333-3333-3333-333333333333'
            }
            $Refused.Caught.FullyQualifiedErrorId | Should -BeExactly 'MissingClientSecret,Initialize-OERAuth'
        }

        # The marker, read through its owner with a round trip that puts back what it found.
        function script:Get-UncertainMarker {
            InModuleScope $script:moduleName {
                $Was = Set-OERSessionUncertain -Value $true
                $null = Set-OERSessionUncertain -Value $Was
                $Was
            }
        }

        function script:Get-UncertainState {
            InModuleScope $script:moduleName {
                @{
                    TenantId         = $script:_OERAuthState.TenantId
                    AuthMethod       = $script:_OERAuthState.AuthMethod
                    GraphTokenExpiry = $script:_OERAuthState.GraphTokenExpiry
                    Fingerprint      = $script:_OERAuthState.GraphSessionFingerprint
                }
            }
        }

        # A sign-in that names no tenant (or 'organizations'), refused for the uncertain session: the A10
        # record, naming the probe command, with the probe command latched, no token call, no connection
        # and the state as it was. Returns the probe.
        function script:Assert-RefusedWhileUncertain {
            param([hashtable]$Parameters = @{})
            $StateBefore = Get-UncertainState
            $TokensBefore = $script:TokenCalls
            $ConnectsBefore = $script:ConnectCalls

            $Probe = Invoke-UncertainProbe -Parameters $Parameters

            $Probe.Caught | Should -Not -BeNullOrEmpty
            $Probe.Caught.FullyQualifiedErrorId | Should -BeExactly 'SignInRefused,Initialize-OERAuth'
            $Probe.Caught.CategoryInfo.Category | Should -Be 'AuthenticationError'
            $Probe.Caught.Exception.Message | Should -Match '^An earlier sign-in'
            $Probe.Caught.TargetObject | Should -BeExactly 'Invoke-UncertainProbeCommand'
            $Probe.Refusal | Should -BeExactly 'Invoke-UncertainProbeCommand'
            $script:TokenCalls | Should -Be $TokensBefore
            $script:ConnectCalls | Should -Be $ConnectsBefore
            $StateAfter = Get-UncertainState
            $StateAfter.TenantId | Should -Be $StateBefore.TenantId
            $StateAfter.AuthMethod | Should -Be $StateBefore.AuthMethod
            $StateAfter.GraphTokenExpiry | Should -Be $StateBefore.GraphTokenExpiry
            $StateAfter.Fingerprint | Should -Be $StateBefore.Fingerprint
            $Probe
        }
    }

    BeforeEach {
        InModuleScope $script:moduleName {
            $script:_OERAuthState = $null
            $script:_OERSessionUncertain = $null
            $script:_OERLastAuthorityHost = $null
            $script:_OERLastTokenRequest = $null
            $script:_OERInteractiveCredential = $null
            $script:_OERTenantDomainCache = $null
        }
        $script:TokenCalls = 0
        $script:ConnectCalls = 0
        $script:CurrentContext = $null
        $script:OwnContext = [pscustomobject]@{
            AuthType = 'UserProvidedAccessToken'; TokenCredentialType = 'UserProvidedAccessToken'
            ClientId = '33333333-3333-3333-3333-333333333333'; TenantId = '44444444-4444-4444-4444-444444444444'
            Account = $null; AppName = 'oer-test-app'; Environment = 'Global'; Scopes = @('Group.ReadWrite.All')
        }
        $script:ForeignContext = [pscustomobject]@{
            AuthType = 'AppOnly'; TokenCredentialType = 'ClientCertificate'
            ClientId = '55555555-5555-5555-5555-555555555555'; TenantId = '66666666-6666-6666-6666-666666666666'
            Account = $null; AppName = 'another-app'; Environment = 'Global'; Scopes = @()
        }
        Mock -ModuleName $script:moduleName Get-AzToken {
            param($ClientId, $ClientSecret, $Resource, $Tenant, $ErrorAction, $Interactive,
                  $DeviceCode, $ManagedIdentity, $ClientCertificate, $ClientCertificatePath,
                  $Scope, $Force, $Claim)
            $script:TokenCalls++
            [pscustomobject]@{ Token = 'fake-graph-token-NOT-A-REAL-TOKEN'; ExpiresOn = [DateTimeOffset]::UtcNow.AddHours(1); Identity = 'admin@contoso.com'; TenantId = $Tenant }
        }
        # Stateful, like the SDK: no session until Connect-MgGraph, then the module's own.
        Mock -ModuleName $script:moduleName Connect-MgGraph { $script:ConnectCalls++; $script:CurrentContext = $script:OwnContext }
        Mock -ModuleName $script:moduleName Get-MgContext { $script:CurrentContext }
        Mock -ModuleName $script:moduleName Resolve-OERTenantDomain { '11111111-1111-1111-1111-111111111111' }
    }

    Context 'a command that names no tenant, after a refused sign-in' {
        It 'is refused with SignInRefused after MissingClientSecret, before any token call, leaving the state as it was and the command latched' {
            Connect-OwnSession
            Invoke-RefusedSignIn

            $null = Assert-RefusedWhileUncertain

            # The session it would have used is tenant A's, connected once.
            (Get-UncertainState).TenantId | Should -BeExactly '44444444-4444-4444-4444-444444444444'
            $script:TokenCalls | Should -Be 1
            $script:ConnectCalls | Should -Be 1
        }

        It 'is refused after GraphTokenAcquisitionFailed' {
            Connect-OwnSession
            Mock -ModuleName $script:moduleName Get-AzToken { $script:TokenCalls++; throw [System.Exception]::new('AADSTS50076: interaction required') }

            $Refused = Invoke-UncertainProbe -Parameters @{ TenantId = '11111111-1111-1111-1111-111111111111'; AuthMethod = 'Interactive' }
            $Refused.Caught.FullyQualifiedErrorId | Should -BeExactly 'GraphTokenAcquisitionFailed,Initialize-OERAuth'

            $null = Assert-RefusedWhileUncertain
        }

        It 'is refused after TenantMismatch on the Microsoft Graph token' {
            Connect-OwnSession
            Mock -ModuleName $script:moduleName Get-AzToken {
                $script:TokenCalls++
                [pscustomobject]@{ Token = 'fake-graph-token-NOT-A-REAL-TOKEN'; ExpiresOn = [DateTimeOffset]::UtcNow.AddHours(1); Identity = 'admin@contoso.com'; TenantId = '22222222-2222-2222-2222-222222222222' }
            }

            $Refused = Invoke-UncertainProbe -Parameters @{ TenantId = '11111111-1111-1111-1111-111111111111'; AuthMethod = 'Interactive' }
            $Refused.Caught.FullyQualifiedErrorId | Should -BeExactly 'TenantMismatch,Initialize-OERAuth'
            $Refused.Caught.Exception.Message | Should -Match 'Microsoft Graph token'

            $null = Assert-RefusedWhileUncertain
        }

        It 'is refused after TenantResolutionFailed' {
            Connect-OwnSession
            Mock -ModuleName $script:moduleName Resolve-OERTenantDomain { throw [System.InvalidOperationException]::new('did not resolve') }

            $Refused = Invoke-UncertainProbe -Parameters @{ TenantId = 'contoso.onmicrosoft.com'; AuthMethod = 'Interactive' }
            $Refused.Caught.FullyQualifiedErrorId | Should -BeExactly 'TenantResolutionFailed,Initialize-OERAuth'

            $null = Assert-RefusedWhileUncertain
        }

        It 'is refused after GraphConnectFailed' {
            Connect-OwnSession
            Mock -ModuleName $script:moduleName Connect-MgGraph { $script:ConnectCalls++; throw [System.Exception]::new('handshake failed') }

            $Refused = Invoke-UncertainProbe -Parameters @{ TenantId = '11111111-1111-1111-1111-111111111111'; AuthMethod = 'Interactive' }
            $Refused.Caught.FullyQualifiedErrorId | Should -BeExactly 'GraphConnectFailed,Initialize-OERAuth'

            $null = Assert-RefusedWhileUncertain
        }

        It 'is refused after ArmTokenAcquisitionFailed, although the sign-in named its tenant and its Microsoft Graph token was cached' {
            Connect-OwnSession
            Mock -ModuleName $script:moduleName Get-AzToken {
                param($ClientId, $ClientSecret, $Resource, $Tenant, $ErrorAction, $Interactive,
                      $DeviceCode, $ManagedIdentity, $ClientCertificate, $ClientCertificatePath,
                      $Scope, $Force, $Claim)
                $script:TokenCalls++
                if ($Resource -match 'management') { throw [System.Exception]::new('ARM consent required') }
                [pscustomobject]@{ Token = 'fake-graph-token-NOT-A-REAL-TOKEN'; ExpiresOn = [DateTimeOffset]::UtcNow.AddHours(1); Identity = 'admin@contoso.com'; TenantId = $Tenant }
            }

            # Non-terminating: Write-CmdletError without -Terminating, then return.
            $Refused = Invoke-UncertainProbe -Quiet -Parameters @{
                TenantId = '44444444-4444-4444-4444-444444444444'; AuthMethod = 'Interactive'; IncludeARM = $true
            }
            $Refused.Caught | Should -BeNullOrEmpty
            $Refused.Ids | Should -Contain 'ArmTokenAcquisitionFailed,Initialize-OERAuth'

            $null = Assert-RefusedWhileUncertain
        }

        It 'is refused after AppOnlySessionCredentialUnavailable, which itself named no tenant' {
            InModuleScope $script:moduleName {
                # An app-only session the module did not connect itself, holding no ARM token.
                $script:_OERAuthState = @{
                    TenantId         = '44444444-4444-4444-4444-444444444444'
                    AuthMethod       = 'ClientSecret'
                    ClientId         = '33333333-3333-3333-3333-333333333333'
                    Environment      = 'Global'
                    Account          = 'sp'
                    GraphTokenExpiry = [DateTime]::UtcNow.AddHours(1)
                    ArmToken         = $null
                    ArmTokenExpiry   = $null
                    ArmResourceUrl   = $null
                    ClaimsSatisfied  = $false
                }
            }

            # No sign-in was refused before this one, so naming no tenant takes it to its own refusal.
            $Refused = Invoke-UncertainProbe -Parameters @{ IncludeARM = $true }
            $Refused.Caught.FullyQualifiedErrorId | Should -BeExactly 'AppOnlySessionCredentialUnavailable,Initialize-OERAuth'

            # A Microsoft Graph sign-in only, which the cached token would otherwise answer.
            $null = Assert-RefusedWhileUncertain
        }

        It 'is refused after GraphSessionChanged, once the module''s own session is back' {
            Connect-OwnSession
            $script:CurrentContext = $script:ForeignContext

            $Refused = Invoke-UncertainProbe -Parameters @{ TenantId = '44444444-4444-4444-4444-444444444444'; AuthMethod = 'Interactive' }
            $Refused.Caught.FullyQualifiedErrorId | Should -BeExactly 'GraphSessionChanged,Initialize-OERAuth'

            # The module's own session back, so the probe gets past the GraphSessionChanged refusal.
            $script:CurrentContext = $script:OwnContext
            $null = Assert-RefusedWhileUncertain
        }

        It 'reads GraphSessionChanged, not SignInRefused, while another session is in place' {
            Connect-OwnSession
            Invoke-RefusedSignIn
            $script:CurrentContext = $script:ForeignContext

            $Changed = Invoke-UncertainProbe

            # The A18 refusal comes first: a changed session is still reported as a changed session.
            $Changed.Caught.FullyQualifiedErrorId | Should -BeExactly 'GraphSessionChanged,Initialize-OERAuth'
            # Not vacuous: with the module's own session back, the same probe is refused for the
            # uncertain session.
            $script:CurrentContext = $script:OwnContext
            $null = Assert-RefusedWhileUncertain
        }

        It 'is refused for -TenantId organizations, which names no tenant (Review Focus 5a)' {
            Connect-OwnSession
            Invoke-RefusedSignIn

            # 'organizations' differs from the session's tenant, so a sign-in that got past the check
            # would request a token.
            $null = Assert-RefusedWhileUncertain -Parameters @{ TenantId = 'organizations'; AuthMethod = 'Interactive' }
        }

        It 'leaves the session uncertain when it is refused itself, so the next one is refused too' {
            Connect-OwnSession
            Invoke-RefusedSignIn

            $null = Assert-RefusedWhileUncertain
            Get-UncertainMarker | Should -BeTrue
            $null = Assert-RefusedWhileUncertain
            Get-UncertainMarker | Should -BeTrue
        }
    }

    Context 'cleared by a sign-in that names its tenant' {
        It 'is cleared by a cached return for a command that names tenant A, and a command that names no tenant is answered again' {
            Connect-OwnSession
            Invoke-RefusedSignIn
            Get-UncertainMarker | Should -BeTrue

            $Named = Invoke-UncertainProbe -Parameters @{ TenantId = '44444444-4444-4444-4444-444444444444' }

            $Named.Caught | Should -BeNullOrEmpty
            $Named.Refusal | Should -BeNullOrEmpty
            # The cached return: the one token and the one connection are Connect-OwnSession's.
            $script:TokenCalls | Should -Be 1
            $script:ConnectCalls | Should -Be 1
            Get-UncertainMarker | Should -BeFalse

            $Later = Invoke-UncertainProbe
            $Later.Caught | Should -BeNullOrEmpty
            $Later.Refusal | Should -BeNullOrEmpty
            $script:TokenCalls | Should -Be 1
        }

        It 'is cleared by a new connection for a command that names another tenant' {
            Connect-OwnSession
            Invoke-RefusedSignIn

            $Named = Invoke-UncertainProbe -Parameters @{ TenantId = '11111111-1111-1111-1111-111111111111'; AuthMethod = 'Interactive' }

            $Named.Caught | Should -BeNullOrEmpty
            $Named.Refusal | Should -BeNullOrEmpty
            # A new connection: the second token and the second connection.
            $script:TokenCalls | Should -Be 2
            $script:ConnectCalls | Should -Be 2
            Get-UncertainMarker | Should -BeFalse

            # Answered from the new session's cache.
            $Later = Invoke-UncertainProbe
            $Later.Caught | Should -BeNullOrEmpty
            $script:TokenCalls | Should -Be 2
            (Get-UncertainState).TenantId | Should -BeExactly '11111111-1111-1111-1111-111111111111'
        }

        It 'is not refused for Connect-OER''s sign-in (-ReclaimGraphSession) that names no tenant, which clears it' {
            Connect-OwnSession
            Invoke-RefusedSignIn

            $Reclaim = Invoke-UncertainProbe -Parameters @{ ReclaimGraphSession = $true }

            $Reclaim.Caught | Should -BeNullOrEmpty
            $Reclaim.Refusal | Should -BeNullOrEmpty
            Get-UncertainMarker | Should -BeFalse
            $Later = Invoke-UncertainProbe
            $Later.Caught | Should -BeNullOrEmpty
            $Later.Refusal | Should -BeNullOrEmpty
        }

        It 'is cleared when a sign-in from the same frame names the tenant and succeeds after a refusal (A19''s retry, Review Focus 5b)' {
            $R = InModuleScope $script:moduleName {
                $Caught = $null
                try {
                    Initialize-OERAuth -TenantId '44444444-4444-4444-4444-444444444444' -AuthMethod 'ClientSecret' -ClientId '33333333-3333-3333-3333-333333333333'
                } catch { $Caught = $PSItem }
                $AfterRefusal = Get-OERSignInRefusal
                $MarkerAfterRefusal = [bool]$script:_OERSessionUncertain
                Initialize-OERAuth -TenantId '44444444-4444-4444-4444-444444444444' -AuthMethod 'Interactive'
                $AfterSuccess = Get-OERSignInRefusal
                @{ Caught = $Caught; AfterRefusal = $AfterRefusal; MarkerAfterRefusal = $MarkerAfterRefusal; AfterSuccess = $AfterSuccess }
            }

            $R.Caught.FullyQualifiedErrorId | Should -BeExactly 'MissingClientSecret,Initialize-OERAuth'
            $R.AfterRefusal | Should -Not -BeNullOrEmpty
            $R.MarkerAfterRefusal | Should -BeTrue
            $R.AfterSuccess | Should -BeNullOrEmpty
            Get-UncertainMarker | Should -BeFalse
        }
    }

    Context 'not cleared by a transport''s own refresh (Review Focus 4)' {
        # The Graph wrapper's token-rejected retry and the ARM wrapper's 401 retry pass -ForceRefresh,
        # and the claims step-up passes -ClaimsChallenge, each naming the state's tenant on the command's
        # behalf. A refresh that succeeds while the session is uncertain must leave it uncertain.
        It 'stays set after a forced refresh (-ForceRefresh) that names the session''s tenant and succeeds' {
            Connect-OwnSession
            Invoke-RefusedSignIn

            $Refresh = Invoke-UncertainProbe -Parameters @{
                TenantId = '44444444-4444-4444-4444-444444444444'; AuthMethod = 'Interactive'; ForceRefresh = $true
            }

            $Refresh.Caught | Should -BeNullOrEmpty
            $Refresh.Refusal | Should -BeNullOrEmpty
            # Positive proof that the refresh went the whole way: a second token, a second connection.
            $script:TokenCalls | Should -Be 2
            $script:ConnectCalls | Should -Be 2
            Get-UncertainMarker | Should -BeTrue
            $null = Assert-RefusedWhileUncertain
        }

        It 'stays set after a claims-challenge step-up (-ClaimsChallenge) that names the session''s tenant and succeeds' {
            Connect-OwnSession
            Invoke-RefusedSignIn

            $StepUp = Invoke-UncertainProbe -Parameters @{
                TenantId = '44444444-4444-4444-4444-444444444444'; AuthMethod = 'Interactive'; ClaimsChallenge = '{}'
            }

            $StepUp.Caught | Should -BeNullOrEmpty
            $StepUp.Refusal | Should -BeNullOrEmpty
            $script:TokenCalls | Should -Be 2
            $script:ConnectCalls | Should -Be 2
            Get-UncertainMarker | Should -BeTrue
            $null = Assert-RefusedWhileUncertain
        }
    }

    Context 'left as it was' {
        It 'stays clear after a sign-in that names no tenant succeeds with no sign-in refused before it' {
            Get-UncertainMarker | Should -BeFalse

            # No session: a new connection for 'organizations', then the cached return.
            $First = Invoke-UncertainProbe -Parameters @{ AuthMethod = 'Interactive' }
            $First.Caught | Should -BeNullOrEmpty
            $First.Refusal | Should -BeNullOrEmpty
            $script:TokenCalls | Should -Be 1
            Get-UncertainMarker | Should -BeFalse

            $Second = Invoke-UncertainProbe
            $Second.Caught | Should -BeNullOrEmpty
            $Second.Refusal | Should -BeNullOrEmpty
            $script:TokenCalls | Should -Be 1
            Get-UncertainMarker | Should -BeFalse
        }

        It 'is neither set nor cleared by the refusal under a latched outer command (BL-74)' {
            Connect-OwnSession
            $Before = Get-UncertainMarker

            $R = InModuleScope $script:moduleName {
                $Holder = @{ Caught = $null }
                function Invoke-NestedCommand {
                    [CmdletBinding()]
                    param()
                    Initialize-OERAuth
                }
                function Invoke-OuterCommand {
                    [CmdletBinding()]
                    param()
                    # Latched by its own invocation, as Lock-OERSignIn latches a refused command.
                    if ($null -eq $script:_OERSignInLatch) {
                        $script:_OERSignInLatch = [System.Runtime.CompilerServices.ConditionalWeakTable[object, object]]::new()
                    }
                    $script:_OERSignInLatch.AddOrUpdate($MyInvocation, $true)
                    try { Invoke-NestedCommand } catch { $Holder.Caught = $PSItem }
                }
                Invoke-OuterCommand
                $Holder
            }

            # Positive proof that the BL-74 refusal was reached: SignInRefused naming the outer command,
            # with BL-74's own message.
            $R.Caught.FullyQualifiedErrorId | Should -BeExactly 'SignInRefused,Initialize-OERAuth'
            $R.Caught.TargetObject | Should -BeExactly 'Invoke-OuterCommand'
            $R.Caught.Exception.Message | Should -Not -Match 'An earlier sign-in'
            $Before | Should -BeFalse
            Get-UncertainMarker | Should -Be $Before
        }
    }
}

Describe 'Initialize-OERAuth renews an interactive session silently (A22, BL-115)' {
    # AzAuth 2.11.0 answers a NON-interactive Get-AzToken from the interactive credential it holds when
    # the request is for the tenant of the last token call (TokenManager.NonInteractive.cs:71). A renewal
    # of an interactive session therefore tries that request first -- no -Interactive, no -ClientId,
    # -CredentialPrecedence Environment -- and accepts its token only for the identity the session
    # already holds; any failure, or a token of another identity, falls back to the interactive request
    # exactly once. This module keeps a tracker of the credential AzAuth holds
    # ($script:_OERInteractiveCredential: the client id and the tenant the interactive call passed).
    #
    # Nothing here reaches AzAuth: Get-AzToken, Connect-MgGraph and Get-MgContext are mocked, and so is
    # Get-OERTokenObjectId (the fake tokens are not JWTs; the object id travels after a '|' in the fake
    # token text). Each token request is recorded as the resource it asked for, whether it was the silent
    # kind (it bound -CredentialPrecedence) and the parameter names it bound. Every assertion counts the
    # requests of each kind exactly, so a "no silent request" can never pass on a request not made.
    BeforeAll {
        $script:A22Tenant = '66666666-6666-6666-6666-666666666666'
        $script:A22OtherTenant = '77777777-7777-7777-7777-777777777777'
        $script:A22Oid = '88888888-8888-8888-8888-888888888888'
        $script:A22OtherOid = '99999999-9999-9999-9999-999999999999'
        $script:A22GraphClient = '14d82eec-204b-4c2f-b7e8-296a70dab67e'
        $script:A22Claims = '{"access_token":{"acrs":{"essential":true,"value":"c1"}}}'

        # How the mocked Get-AzToken answers. Silent: ok | throw | none (writes nothing) | otheroid |
        # othertenant | nooid. Interactive: ok | throw. InteractiveOid and InteractiveTenant override what
        # an interactive-kind token carries ($null keeps the default: the session's oid, the requested
        # tenant, or the tenant above for 'organizations').
        $script:A22TokenMock = {
            param($ClientId, $ClientSecret, $Resource, $Tenant, $ErrorAction, $WarningAction, $Interactive,
                  $DeviceCode, $ManagedIdentity, $ClientCertificate, $ClientCertificatePath,
                  $Scope, $Force, $Claim, $CredentialPrecedence)
            $IsSilent = $PSBoundParameters.ContainsKey('CredentialPrecedence')
            $script:A22Calls.Add([pscustomobject]@{
                Resource   = $Resource
                Silent     = $IsSilent
                Keys       = @($PSBoundParameters.Keys)
                Tenant     = $Tenant
                ClientId   = $ClientId
                Precedence = @($CredentialPrecedence)
            })
            # A tenant named by GUID is the tenant of the token; a domain or none is the tenant above.
            [string]$TokenTenant = if ($Tenant -and $Tenant -match '^[0-9a-f]{8}(-[0-9a-f]{4}){3}-[0-9a-f]{12}$') { $Tenant } else { $script:A22Tenant }
            [string]$Oid = $script:A22Oid
            [string]$Identity = 'interactive@contoso.com'
            if ($IsSilent) {
                $Identity = 'silent@contoso.com'
                switch ($script:A22SilentMode) {
                    'throw'       { throw 'NOT-A-REAL-TOKEN silent request failed' }
                    'none'        { return }
                    'otheroid'    { $Oid = $script:A22OtherOid }
                    'othertenant' { $TokenTenant = $script:A22OtherTenant }
                    'nooid'       { $Oid = '' }
                }
            }
            else {
                if ($script:A22InteractiveMode -eq 'throw' -and
                    (-not $script:A22ThrowFor -or [string]$Resource -like $script:A22ThrowFor)) {
                    throw 'NOT-A-REAL-TOKEN interactive request failed'
                }
                if ($null -ne $script:A22InteractiveOid) { $Oid = $script:A22InteractiveOid }
                if ($script:A22InteractiveTenant) { $TokenTenant = $script:A22InteractiveTenant }
            }
            [pscustomobject]@{
                Token     = "NOT-A-REAL-TOKEN-a22|$Oid"
                ExpiresOn = [DateTimeOffset]::UtcNow.AddHours(1)
                Identity  = $Identity
                TenantId  = $TokenTenant
            }
        }

        # Calls Initialize-OERAuth with -Verbose and keeps the verbose lines in $script:A22Verbose, where
        # Assert-A22Calls counts the silent attempts the function itself reports: a request that never
        # reaches the mocked Get-AzToken (the real command's parameter sets refuse a combination before
        # the mock runs) is still an attempt, and only this line shows it. Returns the other records
        # (warnings, written errors); a terminating error propagates as it does without the redirection.
        function script:Invoke-A22SignIn {
            param([hashtable]$Parameters = @{})
            $Records = InModuleScope $script:moduleName -Parameters @{ P = $Parameters } {
                param($P)
                Initialize-OERAuth @P -Verbose *>&1
            }
            Save-A22Verbose $Records
            @($Records | Where-Object { $_ -isnot [System.Management.Automation.VerboseRecord] })
        }

        function script:Save-A22Verbose {
            param($Records)
            foreach ($Record in @($Records)) {
                if ($Record -is [System.Management.Automation.VerboseRecord]) { $script:A22Verbose.Add([string]$Record.Message) }
            }
        }

        # The first sign-in of a test, with its token requests forgotten afterwards.
        function script:Start-A22Session {
            param([hashtable]$Parameters = @{ TenantId = $script:A22Tenant; AuthMethod = 'Interactive' })
            $null = Invoke-A22SignIn $Parameters
            $script:A22Calls.Clear()
            $script:A22Verbose.Clear()
        }

        function script:Set-A22Expiry {
            param([int]$GraphMinutes, [int]$ArmMinutes)
            InModuleScope $script:moduleName -Parameters @{ G = $GraphMinutes; A = $ArmMinutes } {
                param($G, $A)
                $script:_OERAuthState.GraphTokenExpiry = [DateTime]::UtcNow.AddMinutes($G)
                $script:_OERAuthState.ArmTokenExpiry = [DateTime]::UtcNow.AddMinutes($A)
            }
        }

        function script:Get-A22Tracker {
            InModuleScope $script:moduleName {
                if ($null -eq $script:_OERInteractiveCredential) { return $null }
                [pscustomobject]@{
                    ClientId = $script:_OERInteractiveCredential.ClientId
                    Tenant   = $script:_OERInteractiveCredential.Tenant
                }
            }
        }

        function script:Set-A22Tracker {
            param([string]$ClientId, [string]$Tenant)
            InModuleScope $script:moduleName -Parameters @{ C = $ClientId; T = $Tenant } {
                param($C, $T)
                $script:_OERInteractiveCredential = @{ ClientId = $C; Tenant = $(if ($T) { $T } else { $null }) }
            }
        }

        function script:Get-A22State {
            InModuleScope $script:moduleName { $script:_OERAuthState }
        }

        function script:Get-A22Call {
            param([ValidateSet('Graph', 'Arm')][string]$Kind, [bool]$Silent)
            [string]$Pattern = if ($Kind -eq 'Graph') { '*graph*' } else { '*management*' }
            @($script:A22Calls | Where-Object { [string]$_.Resource -like $Pattern -and $_.Silent -eq $Silent })
        }

        # Exactly this many silent and other token requests per resource and no others. The counts come
        # first, resource by resource, so a failure names what it is about.
        function script:Assert-A22Calls {
            param([int]$GraphSilent = 0, [int]$GraphOther = 0, [int]$ArmSilent = 0, [int]$ArmOther = 0, [switch]$SkipAttemptCheck)
            if (-not $SkipAttemptCheck) {
                # One verbose line per silent attempt, whatever came of it (renewed, no token, another
                # identity, failed) -- the attempts the function reports equal the ones the mock saw.
                @($script:A22Verbose | Where-Object { $_ -match 'The silent renewal|Renewed the interactive session silently' }).Count |
                    Should -Be ($GraphSilent + $ArmSilent) -Because 'every silent attempt reaches the mocked Get-AzToken and is reported once'
            }
            @(Get-A22Call -Kind Graph -Silent $true).Count | Should -Be $GraphSilent -Because 'the silent Microsoft Graph requests are counted exactly'
            @(Get-A22Call -Kind Graph -Silent $false).Count | Should -Be $GraphOther -Because 'the other Microsoft Graph requests are counted exactly'
            @(Get-A22Call -Kind Arm -Silent $true).Count | Should -Be $ArmSilent -Because 'the silent Azure Resource Manager requests are counted exactly'
            @(Get-A22Call -Kind Arm -Silent $false).Count | Should -Be $ArmOther -Because 'the other Azure Resource Manager requests are counted exactly'
            $script:A22Calls.Count | Should -Be ($GraphSilent + $GraphOther + $ArmSilent + $ArmOther) -Because 'every token request is recorded, each for Microsoft Graph or Azure Resource Manager'
        }
    }

    BeforeEach {
        InModuleScope $script:moduleName {
            $script:_OERAuthState = $null
            $script:_OERSessionUncertain = $null
            $script:_OERLastAuthorityHost = $null
            $script:_OERLastTokenRequest = $null
            $script:_OERInteractiveCredential = $null
        }
        $script:A22Calls = [System.Collections.Generic.List[object]]::new()
        $script:A22Verbose = [System.Collections.Generic.List[string]]::new()
        $script:A22SilentMode = 'ok'
        $script:A22InteractiveMode = 'ok'
        $script:A22ThrowFor = $null
        $script:A22InteractiveOid = $null
        $script:A22InteractiveTenant = $null
        Mock -ModuleName $script:moduleName Get-AzToken -MockWith $script:A22TokenMock
        Mock -ModuleName $script:moduleName Connect-MgGraph { }
        Mock -ModuleName $script:moduleName Disconnect-MgGraph { }
        Mock -ModuleName $script:moduleName Resolve-OERTenantDomain { '66666666-6666-6666-6666-666666666666' }
        Mock -ModuleName $script:moduleName Get-OERTokenObjectId {
            param($Token)
            $Plain = [System.Net.NetworkCredential]::new('', $Token).Password
            $Parts = $Plain -split '\|'
            if ($Parts.Count -gt 1 -and $Parts[1]) { $Parts[1] } else { $null }
        }
    }

    Context 'a renewal that is answered silently' {
        It 'sends one silent Microsoft Graph request and no interactive one' {
            Start-A22Session
            Set-A22Expiry -GraphMinutes 2 -ArmMinutes 2

            Invoke-A22SignIn

            Assert-A22Calls -GraphSilent 1 -GraphOther 0
            Should -Invoke -ModuleName $script:moduleName Connect-MgGraph -Times 2 -Exactly
        }

        It 'builds the silent request from the interactive one: no Interactive, no ClientId, CredentialPrecedence Environment, Tenant and Scope as before' {
            Start-A22Session
            Set-A22Expiry -GraphMinutes 2 -ArmMinutes 2

            Invoke-A22SignIn

            $Call = @(Get-A22Call -Kind Graph -Silent $true)[0]
            $Call.Keys | Should -Not -Contain 'Interactive'
            $Call.Keys | Should -Not -Contain 'ClientId'
            $Call.Keys | Should -Not -Contain 'Force'
            $Call.Keys | Should -Not -Contain 'Claim'
            $Call.Keys | Should -Contain 'CredentialPrecedence'
            $Call.Keys | Should -Contain 'Scope'
            @($Call.Precedence).Count | Should -Be 1
            $Call.Precedence[0] | Should -BeExactly 'Environment'
            $Call.Tenant | Should -BeExactly $script:A22Tenant
        }

        It 'renews a session that names no tenant without a Tenant key, since the interactive request named none' {
            Start-A22Session @{ AuthMethod = 'Interactive' }
            (Get-A22Tracker).Tenant | Should -BeNullOrEmpty
            Set-A22Expiry -GraphMinutes 2 -ArmMinutes 2

            Invoke-A22SignIn

            Assert-A22Calls -GraphSilent 1 -GraphOther 0
            @(Get-A22Call -Kind Graph -Silent $true)[0].Keys | Should -Not -Contain 'Tenant'
        }

        It 'names a tenant given as a domain exactly as the interactive request did, and compares the token with the tenant ID it resolved to' {
            Start-A22Session @{ TenantId = 'contoso.onmicrosoft.com'; AuthMethod = 'Interactive' }
            Set-A22Expiry -GraphMinutes 2 -ArmMinutes 2

            Invoke-A22SignIn

            Assert-A22Calls -GraphSilent 1 -GraphOther 0
            @(Get-A22Call -Kind Graph -Silent $true)[0].Tenant | Should -BeExactly 'contoso.onmicrosoft.com'
            (Get-A22State).Account | Should -BeExactly 'silent@contoso.com'
        }

        It 'puts the silent token in the session: the state carries its identity and expiry' {
            Start-A22Session
            Set-A22Expiry -GraphMinutes 2 -ArmMinutes 2

            Invoke-A22SignIn

            $State = Get-A22State
            $State.Account | Should -BeExactly 'silent@contoso.com'
            $State.GraphTokenExpiry | Should -BeGreaterThan ([DateTime]::UtcNow.AddMinutes(30))
            $State.SignedInObjectId | Should -Be $script:A22Oid
            $State.TokenTenantId | Should -Be $script:A22Tenant
        }

        It 'leaves the tracker as it was' {
            Start-A22Session
            Set-A22Expiry -GraphMinutes 2 -ArmMinutes 2

            Invoke-A22SignIn

            (Get-A22Tracker).ClientId | Should -BeExactly $script:A22GraphClient
            (Get-A22Tracker).Tenant | Should -BeExactly $script:A22Tenant
        }

        It 'a second renewal is silent again' {
            Start-A22Session
            Set-A22Expiry -GraphMinutes 2 -ArmMinutes 2
            $null = Invoke-A22SignIn
            Set-A22Expiry -GraphMinutes 2 -ArmMinutes 2
            $script:A22Calls.Clear()
            $script:A22Verbose.Clear()

            $null = Invoke-A22SignIn

            Assert-A22Calls -GraphSilent 1 -GraphOther 0
        }

        It 'a caller-supplied client id is the tracker''s client id, and the renewal is silent for it' {
            Start-A22Session @{ TenantId = $script:A22Tenant; AuthMethod = 'Interactive'; ClientId = 'my-app-id' }
            (Get-A22Tracker).ClientId | Should -BeExactly 'my-app-id'
            Set-A22Expiry -GraphMinutes 2 -ArmMinutes 2

            Invoke-A22SignIn

            Assert-A22Calls -GraphSilent 1 -GraphOther 0
            @(Get-A22Call -Kind Graph -Silent $true)[0].Keys | Should -Not -Contain 'ClientId'
        }

        It 'keeps the cached Azure Resource Manager token over a silent Graph renewal' {
            Start-A22Session @{ TenantId = $script:A22Tenant; AuthMethod = 'Interactive'; IncludeARM = $true }
            # AzAuth holds ONE interactive credential, the one the last interactive request built. Every
            # -IncludeARM sign-in requests Azure Resource Manager last, so in a session using both
            # resources the tracker names ARM and the Graph renewal is not silent (ruling R-3 accepted
            # that cost). This test forces the tracker to Graph to prove what the Graph request does
            # when the tracker names the Graph credential.
            Set-A22Tracker -ClientId $script:A22GraphClient -Tenant $script:A22Tenant
            Set-A22Expiry -GraphMinutes 2 -ArmMinutes 60

            Invoke-A22SignIn @{ IncludeARM = $true }

            Assert-A22Calls -GraphSilent 1 -GraphOther 0 -ArmSilent 0 -ArmOther 0
            $State = Get-A22State
            $State.ArmToken | Should -Not -BeNullOrEmpty
            $State.ArmTokenTenantId | Should -Be $script:A22Tenant
        }
    }

    Context 'a silent request that does not give the session''s identity' {
        It 'falls back to exactly one interactive request when the silent one throws, with no warning and no error record' {
            Start-A22Session
            Set-A22Expiry -GraphMinutes 2 -ArmMinutes 2
            $script:A22SilentMode = 'throw'

            # The streams, not -ErrorVariable: that collects the exception the silent mock throws as it
            # unwinds, caught or not, which is not a record written to anyone.
            $Streams = Invoke-A22SignIn

            Assert-A22Calls -GraphSilent 1 -GraphOther 1
            @($Streams | Where-Object { $_ -is [System.Management.Automation.WarningRecord] }).Count | Should -Be 0
            @($Streams | Where-Object { $_ -is [System.Management.Automation.ErrorRecord] }).Count | Should -Be 0
            $Interactive = @(Get-A22Call -Kind Graph -Silent $false)[0]
            $Interactive.Keys | Should -Contain 'Interactive'
            $Interactive.ClientId | Should -BeExactly $script:A22GraphClient
            (Get-A22State).Account | Should -BeExactly 'interactive@contoso.com'
        }

        It 'sets the tracker again after the interactive fallback' {
            Start-A22Session @{ TenantId = $script:A22Tenant; AuthMethod = 'Interactive'; ClientId = 'my-app-id' }
            Set-A22Expiry -GraphMinutes 2 -ArmMinutes 2
            $script:A22SilentMode = 'throw'

            Invoke-A22SignIn

            Assert-A22Calls -GraphSilent 1 -GraphOther 1
            (Get-A22Tracker).ClientId | Should -BeExactly 'my-app-id'
            (Get-A22Tracker).Tenant | Should -BeExactly $script:A22Tenant
        }

        It 'scrubs the error record of a failed silent request first, and writes only the exception type at the verbose stream' {
            Start-A22Session
            Set-A22Expiry -GraphMinutes 2 -ArmMinutes 2
            $script:A22SilentMode = 'throw'
            Mock -ModuleName $script:moduleName Remove-OERErrorRecord { }

            $null = Invoke-A22SignIn

            Should -Invoke -ModuleName $script:moduleName Remove-OERErrorRecord -Times 1 -Exactly -ParameterFilter {
                $Record.Exception.Message -like '*silent request failed*'
            }
            $Verbose = $script:A22Verbose -join "`n"
            $Verbose | Should -Match 'The silent renewal failed \(\w+\)'
            $Verbose | Should -Not -Match 'NOT-A-REAL-TOKEN'
        }

        It 'falls back when the silent request returns nothing' {
            Start-A22Session
            Set-A22Expiry -GraphMinutes 2 -ArmMinutes 2
            $script:A22SilentMode = 'none'

            $null = Invoke-A22SignIn

            Assert-A22Calls -GraphSilent 1 -GraphOther 1
            (Get-A22State).Account | Should -BeExactly 'interactive@contoso.com'
            # The no-token guard answers by itself; without it the empty answer would fail further down
            # and be reported as a failed request.
            $Verbose = $script:A22Verbose -join "`n"
            $Verbose | Should -Match 'The silent renewal returned no token'
            $Verbose | Should -Not -Match 'The silent renewal failed'
        }

        It 'discards a silent token of another object id and signs in interactively once' {
            Start-A22Session
            Set-A22Expiry -GraphMinutes 2 -ArmMinutes 2
            $script:A22SilentMode = 'otheroid'

            Invoke-A22SignIn

            Assert-A22Calls -GraphSilent 1 -GraphOther 1
            $State = Get-A22State
            $State.Account | Should -BeExactly 'interactive@contoso.com'
            $State.SignedInObjectId | Should -Be $script:A22Oid
        }

        It 'discards a silent token of another tenant and signs in interactively once' {
            Start-A22Session @{ AuthMethod = 'Interactive' }
            Set-A22Expiry -GraphMinutes 2 -ArmMinutes 2
            $script:A22SilentMode = 'othertenant'

            Invoke-A22SignIn

            Assert-A22Calls -GraphSilent 1 -GraphOther 1
            $State = Get-A22State
            $State.Account | Should -BeExactly 'interactive@contoso.com'
            $State.TokenTenantId | Should -Be $script:A22Tenant
        }

        It 'discards a silent token with no readable object id' {
            Start-A22Session
            Set-A22Expiry -GraphMinutes 2 -ArmMinutes 2
            $script:A22SilentMode = 'nooid'

            Invoke-A22SignIn

            Assert-A22Calls -GraphSilent 1 -GraphOther 1
            (Get-A22State).Account | Should -BeExactly 'interactive@contoso.com'
        }

        It 'stops with GraphTokenAcquisitionFailed, and leaves the tracker empty, when the fallback fails too' {
            Start-A22Session
            Set-A22Expiry -GraphMinutes 2 -ArmMinutes 2
            $script:A22SilentMode = 'throw'
            $script:A22InteractiveMode = 'throw'

            $Caught = InModuleScope $script:moduleName {
                try { Initialize-OERAuth; $null } catch { $PSItem }
            }

            $Caught.FullyQualifiedErrorId | Should -BeLike 'GraphTokenAcquisitionFailed*'
            # The verbose lines of a call that ends in a terminating error are lost to the catch above.
            Assert-A22Calls -GraphSilent 1 -GraphOther 1 -SkipAttemptCheck
            Get-A22Tracker | Should -BeNullOrEmpty
        }

        It 'gives the interactive token that follows a discarded silent one the same TenantMismatch check as ever' {
            Start-A22Session
            Set-A22Expiry -GraphMinutes 2 -ArmMinutes 2
            $script:A22SilentMode = 'othertenant'
            $script:A22InteractiveTenant = $script:A22OtherTenant

            $Caught = InModuleScope $script:moduleName {
                try { Initialize-OERAuth; $null } catch { $PSItem }
            }

            $Caught.FullyQualifiedErrorId | Should -BeLike 'TenantMismatch*'
            Assert-A22Calls -GraphSilent 1 -GraphOther 1 -SkipAttemptCheck
        }
    }

    Context 'the identity check reads a real token (a delegating mock wraps the real Get-OERTokenObjectId)' {
        BeforeAll {
            # The real reader's body, taken before any test of this Context mocks the name; a script block of
            # a module function stays bound to the module, so its private helpers resolve when it is called.
            $script:A22RealGetOid = InModuleScope $script:moduleName { (Get-Command Get-OERTokenObjectId -CommandType Function).ScriptBlock }
        }

        BeforeEach {
            # The real reader of the oid claim, through the silent path: the tokens the mocked Get-AzToken
            # returns are JWT-shaped (header.payload.signature, the signature NOT-A-REAL-TOKEN text), the
            # payload carrying the oid and tid claims, so Invoke-SilentRenewal decodes what it compares.
            $script:A22Jwt = @{
                $script:A22Oid      = New-TestToken -Claims @{ oid = $script:A22Oid; tid = $script:A22Tenant }
                $script:A22OtherOid = New-TestToken -Claims @{ oid = $script:A22OtherOid; tid = $script:A22Tenant }
            }
            Mock -ModuleName $script:moduleName Get-OERTokenObjectId {
                param($Token)
                & $script:A22RealGetOid -Token $Token
            }
            Mock -ModuleName $script:moduleName Get-AzToken {
                param($ClientId, $ClientSecret, $Resource, $Tenant, $ErrorAction, $WarningAction, $Interactive,
                      $DeviceCode, $ManagedIdentity, $ClientCertificate, $ClientCertificatePath,
                      $Scope, $Force, $Claim, $CredentialPrecedence)
                $Result = & $script:A22TokenMock @PSBoundParameters
                if ($null -ne $Result) {
                    $Result.Token = $script:A22Jwt[($Result.Token -split '\|')[1]]
                }
                $Result
            }
        }

        It 'accepts a silent JWT whose oid and tid are the session''s, and sends no interactive request' {
            Start-A22Session
            (Get-A22State).SignedInObjectId | Should -Be $script:A22Oid -Because 'the real reader decoded the first token'
            Set-A22Expiry -GraphMinutes 2 -ArmMinutes 2

            Invoke-A22SignIn

            Assert-A22Calls -GraphSilent 1 -GraphOther 0
            (Get-A22State).Account | Should -BeExactly 'silent@contoso.com'
        }

        It 'discards a silent JWT of another oid and sends exactly one interactive request' {
            Start-A22Session
            Set-A22Expiry -GraphMinutes 2 -ArmMinutes 2
            $script:A22SilentMode = 'otheroid'

            Invoke-A22SignIn

            Assert-A22Calls -GraphSilent 1 -GraphOther 1
            $State = Get-A22State
            $State.Account | Should -BeExactly 'interactive@contoso.com'
            $State.SignedInObjectId | Should -Be $script:A22Oid
        }
    }

    Context 'the tracker' {
        It 'names the client id and tenant of an interactive Microsoft Graph request' {
            Invoke-A22SignIn @{ TenantId = $script:A22Tenant; AuthMethod = 'Interactive' }

            (Get-A22Tracker).ClientId | Should -BeExactly $script:A22GraphClient
            (Get-A22Tracker).Tenant | Should -BeExactly $script:A22Tenant
        }

        It 'names the empty client id, as a string, after an interactive Azure Resource Manager request' {
            Invoke-A22SignIn @{ TenantId = $script:A22Tenant; AuthMethod = 'Interactive'; IncludeARM = $true }

            (Get-A22Tracker).ClientId | Should -BeOfType [string]
            (Get-A22Tracker).ClientId | Should -BeExactly ''
            (Get-A22Tracker).Tenant | Should -BeExactly $script:A22Tenant
        }

        It 'is empty after a request that throws' {
            Set-A22Tracker -ClientId $script:A22GraphClient -Tenant $script:A22Tenant
            $script:A22InteractiveMode = 'throw'

            InModuleScope $script:moduleName {
                try { Initialize-OERAuth -TenantId '66666666-6666-6666-6666-666666666666' -AuthMethod Interactive } catch { $null = $PSItem }
            }

            Get-A22Tracker | Should -BeNullOrEmpty
        }

        It 'is cleared before a device code request' {
            Start-A22Session
            Set-A22Expiry -GraphMinutes 2 -ArmMinutes 2

            Invoke-A22SignIn @{ TenantId = $script:A22Tenant; AuthMethod = 'DeviceCode' }

            Get-A22Tracker | Should -BeNullOrEmpty
        }

        It 'is cleared before a managed identity request' {
            Start-A22Session
            Invoke-A22SignIn @{ TenantId = $script:A22Tenant; AuthMethod = 'ManagedIdentity' }

            Get-A22Tracker | Should -BeNullOrEmpty
        }

        It 'is empty after a managed identity sign-in that also acquires an Azure Resource Manager token' {
            Invoke-A22SignIn @{ TenantId = $script:A22Tenant; AuthMethod = 'ManagedIdentity'; IncludeARM = $true }

            Get-A22Tracker | Should -BeNullOrEmpty
        }

        It 'is empty after an Azure Resource Manager request that throws, whatever the tracker named before it' {
            Start-A22Session
            Set-A22Tracker -ClientId $script:A22GraphClient -Tenant $script:A22Tenant
            $script:A22InteractiveMode = 'throw'
            $script:A22ThrowFor = '*management*'

            $null = Invoke-A22SignIn @{ IncludeARM = $true; ErrorAction = 'SilentlyContinue' }

            # The Graph token was cached, so the Azure Resource Manager request was the only one made.
            Assert-A22Calls -ArmSilent 0 -ArmOther 1
            Get-A22Tracker | Should -BeNullOrEmpty
        }

        It 'is cleared before a client secret request' {
            Start-A22Session
            Invoke-A22SignIn @{
                TenantId     = $script:A22Tenant
                AuthMethod   = 'ClientSecret'
                ClientId     = 'app-id'
                ClientSecret = (ConvertTo-SecureString 'not-a-real-secret' -AsPlainText -Force)
            }

            Get-A22Tracker | Should -BeNullOrEmpty
        }

        It 'is cleared before a client certificate request' {
            Start-A22Session
            Invoke-A22SignIn @{
                TenantId        = $script:A22Tenant
                AuthMethod      = 'ClientCertificate'
                ClientId        = 'app-id'
                CertificatePath = 'oer-a22-not-a-real-certificate.pfx'
            }

            Get-A22Tracker | Should -BeNullOrEmpty
        }

        It 'is cleared before an interactive request that falls back, and set again after it' {
            Start-A22Session
            Set-A22Tracker -ClientId 'stale-client' -Tenant $script:A22OtherTenant
            Set-A22Expiry -GraphMinutes 2 -ArmMinutes 2

            Invoke-A22SignIn

            Assert-A22Calls -GraphSilent 0 -GraphOther 1
            (Get-A22Tracker).ClientId | Should -BeExactly $script:A22GraphClient
            (Get-A22Tracker).Tenant | Should -BeExactly $script:A22Tenant
        }

        It 'is not touched by Disconnect-OER: the credential AzAuth holds outlives the state' {
            Start-A22Session

            Disconnect-OER -Confirm:$false

            (Get-A22Tracker).ClientId | Should -BeExactly $script:A22GraphClient
        }
    }

    Context 'a renewal that is never silent' {
        It 'does not try for a first sign-in, whatever the tracker says' {
            Set-A22Tracker -ClientId $script:A22GraphClient -Tenant $script:A22Tenant

            Invoke-A22SignIn @{ TenantId = $script:A22Tenant; AuthMethod = 'Interactive' }

            Assert-A22Calls -GraphSilent 0 -GraphOther 1
        }

        It 'does not try with no tracker (the module was reloaded, or AzAuth was last called by a request that is not interactive)' {
            Start-A22Session
            InModuleScope $script:moduleName { $script:_OERInteractiveCredential = $null }
            Set-A22Expiry -GraphMinutes 2 -ArmMinutes 2

            Invoke-A22SignIn

            Assert-A22Calls -GraphSilent 0 -GraphOther 1
        }

        It 'does not try for Connect-OER''s sign-in (-ReclaimGraphSession), which signs in as before' {
            Start-A22Session
            Set-A22Expiry -GraphMinutes 2 -ArmMinutes 2

            Invoke-A22SignIn @{ ReclaimGraphSession = $true }

            Assert-A22Calls -GraphSilent 0 -GraphOther 1
        }

        It 'does not try under Connect-OER' {
            Start-A22Session
            Set-A22Expiry -GraphMinutes 2 -ArmMinutes 2

            Save-A22Verbose (Connect-OER -TenantId $script:A22Tenant -Interactive -Verbose *>&1)

            Assert-A22Calls -GraphSilent 0 -GraphOther 1
        }

        It 'does not try under -ForceRefresh, which carries Force' {
            Start-A22Session

            Invoke-A22SignIn @{ ForceRefresh = $true }

            Assert-A22Calls -GraphSilent 0 -GraphOther 1
            @(Get-A22Call -Kind Graph -Silent $false)[0].Keys | Should -Contain 'Force'
        }

        It 'does not try for a claims challenge' {
            Start-A22Session

            Invoke-A22SignIn @{ ClaimsChallenge = $script:A22Claims }

            Assert-A22Calls -GraphSilent 0 -GraphOther 1
            @(Get-A22Call -Kind Graph -Silent $false)[0].Keys | Should -Contain 'Claim'
        }

        It 'does not try for a cloud switch' {
            Start-A22Session
            Set-A22Expiry -GraphMinutes 2 -ArmMinutes 2

            Invoke-A22SignIn @{ TenantId = $script:A22Tenant; AuthMethod = 'Interactive'; Environment = 'USGov' }

            Assert-A22Calls -GraphSilent 0 -GraphOther 1
            @(Get-A22Call -Kind Graph -Silent $false)[0].Keys | Should -Contain 'Force'
        }

        It 'does not try for a cloud switch even when no Force is on the request' {
            # The authority tracker already names the sovereign host, so no Force is added: the cloud
            # alone (a state of another cloud, $ArmIdentityUnchanged) keeps the renewal interactive.
            Start-A22Session
            Set-A22Expiry -GraphMinutes 2 -ArmMinutes 2
            InModuleScope $script:moduleName {
                $script:_OERLastAuthorityHost = (Get-OERCloudEndpoint -Environment 'USGov').AuthorityHost
            }

            Invoke-A22SignIn @{ TenantId = $script:A22Tenant; AuthMethod = 'Interactive'; Environment = 'USGov' }

            Assert-A22Calls -GraphSilent 0 -GraphOther 1
            @(Get-A22Call -Kind Graph -Silent $false)[0].Keys | Should -Not -Contain 'Force'
        }

        It 'does not try for another tenant than the session''s' {
            Start-A22Session
            Set-A22Expiry -GraphMinutes 2 -ArmMinutes 2

            Invoke-A22SignIn @{ TenantId = $script:A22OtherTenant; AuthMethod = 'Interactive' }

            Assert-A22Calls -GraphSilent 0 -GraphOther 1
        }

        It 'does not try for another client than the session''s' {
            Start-A22Session
            Set-A22Expiry -GraphMinutes 2 -ArmMinutes 2

            Invoke-A22SignIn @{ TenantId = $script:A22Tenant; AuthMethod = 'Interactive'; ClientId = 'my-app-id' }

            Assert-A22Calls -GraphSilent 0 -GraphOther 1
        }

        It 'does not try when the tracker names another client than the interactive request would pass' {
            Start-A22Session
            Set-A22Tracker -ClientId 'another-client' -Tenant $script:A22Tenant
            Set-A22Expiry -GraphMinutes 2 -ArmMinutes 2

            Invoke-A22SignIn

            Assert-A22Calls -GraphSilent 0 -GraphOther 1
        }

        It 'does not try when the tracker names another tenant than the interactive request would pass' {
            Start-A22Session
            Set-A22Tracker -ClientId $script:A22GraphClient -Tenant $script:A22OtherTenant
            Set-A22Expiry -GraphMinutes 2 -ArmMinutes 2

            Invoke-A22SignIn

            Assert-A22Calls -GraphSilent 0 -GraphOther 1
        }

        It 'does not try when the tracker names a tenant and the request names none' {
            Start-A22Session @{ AuthMethod = 'Interactive' }
            Set-A22Tracker -ClientId $script:A22GraphClient -Tenant $script:A22Tenant
            Set-A22Expiry -GraphMinutes 2 -ArmMinutes 2

            Invoke-A22SignIn

            Assert-A22Calls -GraphSilent 0 -GraphOther 1
        }

        It 'does not try when the tracker differs from the client id only in letter case' {
            Start-A22Session @{ TenantId = $script:A22Tenant; AuthMethod = 'Interactive'; ClientId = 'My-App-Id' }
            Set-A22Tracker -ClientId 'my-app-id' -Tenant $script:A22Tenant
            Set-A22Expiry -GraphMinutes 2 -ArmMinutes 2

            Invoke-A22SignIn

            Assert-A22Calls -GraphSilent 0 -GraphOther 1
        }

        It 'does not try when the tracker differs from the tenant only in letter case' {
            Start-A22Session @{ TenantId = 'Contoso.onmicrosoft.com'; AuthMethod = 'Interactive' }
            Set-A22Tracker -ClientId $script:A22GraphClient -Tenant 'contoso.onmicrosoft.com'
            Set-A22Expiry -GraphMinutes 2 -ArmMinutes 2

            Invoke-A22SignIn

            Assert-A22Calls -GraphSilent 0 -GraphOther 1
        }

        It 'does not try when the session has no object id to compare a token with' {
            $script:A22InteractiveOid = ''
            Start-A22Session
            (Get-A22State).SignedInObjectId | Should -BeNullOrEmpty
            Set-A22Expiry -GraphMinutes 2 -ArmMinutes 2
            $script:A22InteractiveOid = $null

            Invoke-A22SignIn

            Assert-A22Calls -GraphSilent 0 -GraphOther 1
        }

        It 'does not try when the session''s token tenant is not a GUID' {
            $script:A22InteractiveTenant = 'contoso'
            Start-A22Session @{ AuthMethod = 'Interactive' }
            (Get-A22State).TokenTenantId | Should -BeExactly 'contoso'
            Set-A22Expiry -GraphMinutes 2 -ArmMinutes 2
            $script:A22InteractiveTenant = $null

            Invoke-A22SignIn

            Assert-A22Calls -GraphSilent 0 -GraphOther 1
        }

        It 'does not try for a session switched to Interactive from another method' {
            Start-A22Session @{ TenantId = $script:A22Tenant; AuthMethod = 'ManagedIdentity' }
            Set-A22Tracker -ClientId $script:A22GraphClient -Tenant $script:A22Tenant
            Set-A22Expiry -GraphMinutes 2 -ArmMinutes 2

            Invoke-A22SignIn @{ TenantId = $script:A22Tenant; AuthMethod = 'Interactive' }

            Assert-A22Calls -GraphSilent 0 -GraphOther 1
        }

        It 'does not try for a <Method> session, whatever the tracker says' -ForEach @(
            @{ Method = 'DeviceCode' }
            @{ Method = 'ManagedIdentity' }
            @{ Method = 'ClientSecret' }
            @{ Method = 'ClientCertificate' }
        ) {
            $Parameters = @{ TenantId = $script:A22Tenant; AuthMethod = $Method }
            if ($Method -in 'ClientSecret', 'ClientCertificate') { $Parameters.ClientId = 'app-id' }
            if ($Method -eq 'ClientSecret') { $Parameters.ClientSecret = ConvertTo-SecureString 'not-a-real-secret' -AsPlainText -Force }
            if ($Method -eq 'ClientCertificate') { $Parameters.CertificatePath = 'oer-a22-not-a-real-certificate.pfx' }
            Start-A22Session $Parameters
            # A tracker that would match an interactive request, planted: only the method keeps this
            # renewal from being silent.
            [string]$PlantedClient = if ($Method -in 'ClientSecret', 'ClientCertificate') { 'app-id' } else { $script:A22GraphClient }
            Set-A22Tracker -ClientId $PlantedClient -Tenant $script:A22Tenant
            Set-A22Expiry -GraphMinutes 2 -ArmMinutes 2

            Invoke-A22SignIn $Parameters

            Assert-A22Calls -GraphSilent 0 -GraphOther 1
            @(Get-A22Call -Kind Graph -Silent $false)[0].Keys | Should -Not -Contain 'CredentialPrecedence'
        }
    }

    Context 'the Azure Resource Manager token' {
        It 'is renewed silently when the Azure Resource Manager credential is the one AzAuth holds' {
            Start-A22Session @{ TenantId = $script:A22Tenant; AuthMethod = 'Interactive'; IncludeARM = $true }
            (Get-A22Tracker).ClientId | Should -BeExactly ''
            Set-A22Expiry -GraphMinutes 60 -ArmMinutes 2

            Invoke-A22SignIn @{ IncludeARM = $true }

            Assert-A22Calls -ArmSilent 1 -ArmOther 0 -GraphSilent 0 -GraphOther 0
            $Call = @(Get-A22Call -Kind Arm -Silent $true)[0]
            $Call.Keys | Should -Not -Contain 'Interactive'
            $Call.Keys | Should -Not -Contain 'ClientId'
            $Call.Keys | Should -Not -Contain 'Scope'
            $Call.Precedence[0] | Should -BeExactly 'Environment'
            $Call.Tenant | Should -BeExactly $script:A22Tenant
            $State = Get-A22State
            $State.ArmTokenExpiry | Should -BeGreaterThan ([DateTime]::UtcNow.AddMinutes(30))
            $State.ArmTokenTenantId | Should -Be $script:A22Tenant
            (Get-A22Tracker).ClientId | Should -BeExactly ''
        }

        It 'is requested interactively, once, when the Microsoft Graph credential is the one AzAuth holds' {
            Start-A22Session
            Set-A22Tracker -ClientId $script:A22GraphClient -Tenant $script:A22Tenant

            Invoke-A22SignIn @{ IncludeARM = $true }

            Assert-A22Calls -ArmSilent 0 -ArmOther 1 -GraphSilent 0 -GraphOther 0
            (Get-A22Tracker).ClientId | Should -BeExactly ''
        }

        It 'is requested interactively after an interactive Microsoft Graph request, since AzAuth then holds the Graph credential' {
            # The tracker names the Azure Resource Manager credential going in. The Graph request does not
            # match it and is interactive, which makes AzAuth hold the Graph credential, so the Azure
            # Resource Manager request that follows must not be silent: its predicate is read after it.
            Start-A22Session @{ TenantId = $script:A22Tenant; AuthMethod = 'Interactive'; IncludeARM = $true }
            Set-A22Expiry -GraphMinutes 2 -ArmMinutes 2

            Invoke-A22SignIn @{ IncludeARM = $true }

            Assert-A22Calls -GraphSilent 0 -GraphOther 1 -ArmSilent 0 -ArmOther 1
            (Get-A22Tracker).ClientId | Should -BeExactly ''
        }

        It 'is requested interactively after a silent Graph renewal, since the credential AzAuth holds is the Graph one' {
            Start-A22Session
            Set-A22Expiry -GraphMinutes 2 -ArmMinutes 2

            Invoke-A22SignIn @{ IncludeARM = $true }

            Assert-A22Calls -GraphSilent 1 -GraphOther 0 -ArmSilent 0 -ArmOther 1
        }

        It 'falls back to one interactive Azure Resource Manager request when the silent one throws' {
            Start-A22Session @{ TenantId = $script:A22Tenant; AuthMethod = 'Interactive'; IncludeARM = $true }
            Set-A22Expiry -GraphMinutes 60 -ArmMinutes 2
            $script:A22SilentMode = 'throw'

            Invoke-A22SignIn @{ IncludeARM = $true }

            Assert-A22Calls -ArmSilent 1 -ArmOther 1
            @(Get-A22Call -Kind Arm -Silent $false)[0].Keys | Should -Contain 'Interactive'
        }

        It 'discards a silent token of another object id' {
            Start-A22Session @{ TenantId = $script:A22Tenant; AuthMethod = 'Interactive'; IncludeARM = $true }
            Set-A22Expiry -GraphMinutes 60 -ArmMinutes 2
            $script:A22SilentMode = 'otheroid'

            Invoke-A22SignIn @{ IncludeARM = $true }

            Assert-A22Calls -ArmSilent 1 -ArmOther 1
        }

        It 'discards a silent token of another tenant than the session''s' {
            Start-A22Session @{ AuthMethod = 'Interactive'; IncludeARM = $true }
            Set-A22Expiry -GraphMinutes 60 -ArmMinutes 2
            $script:A22SilentMode = 'othertenant'

            Invoke-A22SignIn @{ IncludeARM = $true }

            Assert-A22Calls -ArmSilent 1 -ArmOther 1
            (Get-A22State).ArmTokenTenantId | Should -Be $script:A22Tenant
        }

        It 'is not silent for a session that is not interactive' {
            Start-A22Session @{ TenantId = $script:A22Tenant; AuthMethod = 'ManagedIdentity'; IncludeARM = $true }
            Set-A22Tracker -ClientId '' -Tenant $script:A22Tenant
            Set-A22Expiry -GraphMinutes 60 -ArmMinutes 2

            Invoke-A22SignIn @{ TenantId = $script:A22Tenant; AuthMethod = 'ManagedIdentity'; IncludeARM = $true }

            Assert-A22Calls -ArmSilent 0 -ArmOther 1
        }

        It 'is not silent under -ForceRefresh' {
            Start-A22Session @{ TenantId = $script:A22Tenant; AuthMethod = 'Interactive'; IncludeARM = $true }

            Invoke-A22SignIn @{ IncludeARM = $true; ForceRefresh = $true }

            Assert-A22Calls -GraphSilent 0 -GraphOther 1 -ArmSilent 0 -ArmOther 1
        }

        It 'is not silent for a claims challenge' {
            Start-A22Session @{ TenantId = $script:A22Tenant; AuthMethod = 'Interactive'; IncludeARM = $true }
            Set-A22Expiry -GraphMinutes 60 -ArmMinutes 2

            Invoke-A22SignIn @{ IncludeARM = $true; ClaimsChallenge = $script:A22Claims }

            Assert-A22Calls -ArmSilent 0 -ArmOther 1 -GraphSilent 0 -GraphOther 1
        }

        It 'is not silent for Connect-OER''s sign-in (-ReclaimGraphSession)' {
            Start-A22Session @{ TenantId = $script:A22Tenant; AuthMethod = 'Interactive'; IncludeARM = $true }
            Set-A22Expiry -GraphMinutes 60 -ArmMinutes 2

            Invoke-A22SignIn @{ IncludeARM = $true; ReclaimGraphSession = $true }

            Assert-A22Calls -ArmSilent 0 -ArmOther 1
        }

        It 'is not silent when the tracker names another tenant than the request' {
            Start-A22Session @{ TenantId = $script:A22Tenant; AuthMethod = 'Interactive'; IncludeARM = $true }
            Set-A22Tracker -ClientId '' -Tenant $script:A22OtherTenant
            Set-A22Expiry -GraphMinutes 60 -ArmMinutes 2

            Invoke-A22SignIn @{ IncludeARM = $true }

            Assert-A22Calls -ArmSilent 0 -ArmOther 1
        }

        It 'is not silent when the request carries Force for the authority the credential was not built at' {
            Start-A22Session @{ TenantId = $script:A22Tenant; AuthMethod = 'Interactive'; IncludeARM = $true }
            Set-A22Expiry -GraphMinutes 60 -ArmMinutes 2
            InModuleScope $script:moduleName {
                $script:_OERLastAuthorityHost = (Get-OERCloudEndpoint -Environment 'USGov').AuthorityHost
            }

            Invoke-A22SignIn @{ IncludeARM = $true }

            Assert-A22Calls -ArmSilent 0 -ArmOther 1 -GraphSilent 0 -GraphOther 0
            @(Get-A22Call -Kind Arm -Silent $false)[0].Keys | Should -Contain 'Force'
        }

        It 'is not silent when the session has no object id to compare a token with' {
            $script:A22InteractiveOid = ''
            Start-A22Session @{ TenantId = $script:A22Tenant; AuthMethod = 'Interactive'; IncludeARM = $true }
            Set-A22Expiry -GraphMinutes 60 -ArmMinutes 2
            $script:A22InteractiveOid = $null

            Invoke-A22SignIn @{ IncludeARM = $true }

            Assert-A22Calls -ArmSilent 0 -ArmOther 1
        }

        It 'is not silent when the session''s token tenant is not a GUID' {
            $script:A22InteractiveTenant = 'contoso'
            Start-A22Session @{ AuthMethod = 'Interactive'; IncludeARM = $true }
            Set-A22Expiry -GraphMinutes 60 -ArmMinutes 2
            $script:A22InteractiveTenant = $null

            Invoke-A22SignIn @{ IncludeARM = $true }

            Assert-A22Calls -ArmSilent 0 -ArmOther 1
        }
    }
}

Describe 'Initialize-OERAuth refuses an interactive sign-in in a host started with -NonInteractive (BL-100)' {
    # A host started with pwsh -NonInteractive declares that nobody can answer a prompt (a policy; whether a
    # browser could be completed there is not measured), and AzAuth would still open the browser from the
    # token request. Initialize-OERAuth refuses it with InteractiveSignInUnavailable,
    # after the cached return and the credential checks and before the tenant lookup and every token request
    # (the silent renewal included). Test-OERHostNonInteractive is the single owner of the host question;
    # here it is mocked, so the answer is the test's choice and not the host this file happens to run in.
    # Nothing reaches AzAuth, Microsoft Graph or the tenant lookup: Get-AzToken, Connect-MgGraph,
    # Disconnect-MgGraph and Resolve-OERTenantDomain are mocked, and the root Get-MgContext mock answers.
    BeforeAll {
        $script:NiTenant = '66666666-6666-6666-6666-666666666666'
        $script:NiOid = '88888888-8888-8888-8888-888888888888'

        # Calls Initialize-OERAuth from ONE script block, then reads the latch and the session-uncertain
        # marker from that same script block, as the latch Describe does. Returns the record it raised.
        function script:Invoke-NiProbe {
            param([hashtable]$Parameters = @{})
            InModuleScope $script:moduleName -Parameters @{ P = $Parameters } {
                param($P)
                $Caught = $null
                try { Initialize-OERAuth @P } catch { $Caught = $PSItem }
                $Refusal = Get-OERSignInRefusal
                $Was = Set-OERSessionUncertain -Value $true
                $null = Set-OERSessionUncertain -Value $Was
                @{ Caught = $Caught; Refusal = $Refusal; Marker = $Was }
            }
        }

        function script:Set-NiGraphExpiry {
            param([int]$Minutes)
            InModuleScope $script:moduleName -Parameters @{ M = $Minutes } {
                param($M)
                $script:_OERAuthState.GraphTokenExpiry = [DateTime]::UtcNow.AddMinutes($M)
            }
        }

        function script:Get-NiSilentCallCount {
            @($script:NiCalls | Where-Object { $_.Silent }).Count
        }
    }

    BeforeEach {
        InModuleScope $script:moduleName {
            $script:_OERAuthState = $null
            $script:_OERSessionUncertain = $null
            $script:_OERLastAuthorityHost = $null
            $script:_OERLastTokenRequest = $null
            $script:_OERInteractiveCredential = $null
        }
        $script:NiCalls = [System.Collections.Generic.List[object]]::new()
        Mock -ModuleName $script:moduleName Test-OERHostNonInteractive { $true }
        Mock -ModuleName $script:moduleName Get-AzToken {
            param($ClientId, $ClientSecret, $Resource, $Tenant, $ErrorAction, $WarningAction, $Interactive,
                  $DeviceCode, $ManagedIdentity, $ClientCertificate, $ClientCertificatePath,
                  $Scope, $Force, $Claim, $CredentialPrecedence)
            $script:NiCalls.Add([pscustomobject]@{ Resource = $Resource; Silent = $PSBoundParameters.ContainsKey('CredentialPrecedence') })
            [string]$TokenTenant = if ($Tenant -and $Tenant -match '^[0-9a-f]{8}(-[0-9a-f]{4}){3}-[0-9a-f]{12}$') { $Tenant } else { '66666666-6666-6666-6666-666666666666' }
            [pscustomobject]@{
                Token     = 'NOT-A-REAL-TOKEN-ni|88888888-8888-8888-8888-888888888888'
                ExpiresOn = [DateTimeOffset]::UtcNow.AddHours(1)
                Identity  = 'admin@contoso.com'
                TenantId  = $TokenTenant
            }
        }
        Mock -ModuleName $script:moduleName Connect-MgGraph { }
        Mock -ModuleName $script:moduleName Disconnect-MgGraph { }
        Mock -ModuleName $script:moduleName Resolve-OERTenantDomain { '66666666-6666-6666-6666-666666666666' }
        Mock -ModuleName $script:moduleName Get-OERTokenObjectId {
            param($Token)
            $Plain = [System.Net.NetworkCredential]::new('', $Token).Password
            $Parts = $Plain -split '\|'
            if ($Parts.Count -gt 1 -and $Parts[1]) { $Parts[1] } else { $null }
        }
    }

    Context 'an interactive sign-in in a non-interactive host' {
        It 'is refused with InteractiveSignInUnavailable, naming the host, the tenant and the ways that work' {
            $R = Invoke-NiProbe -Parameters @{ TenantId = $script:NiTenant; AuthMethod = 'Interactive' }

            $R.Caught.FullyQualifiedErrorId | Should -BeExactly 'InteractiveSignInUnavailable,Initialize-OERAuth'
            $R.Caught.CategoryInfo.Category | Should -Be ([System.Management.Automation.ErrorCategory]::AuthenticationError)
            $R.Caught.TargetObject | Should -BeExactly $script:NiTenant
            $R.Caught.Exception.Message | Should -Match '-NonInteractive'
            $R.Caught.Exception.Message | Should -Match 'browser sign-in'
            $R.Caught.Exception.Message | Should -Match 'no token was requested'
            $R.Caught.Exception.Message | Should -Match 'Connect-OER'
            $R.Caught.Exception.Message | Should -Match '-DeviceCode'
            $R.Caught.Exception.Message | Should -Match '-ManagedIdentity'
            $R.Caught.Exception.Message | Should -Match '-CertificatePath'
            $R.Caught.Exception.Message | Should -Match '-ClientSecret'
        }

        It 'requests nothing: no token, no tenant lookup, no Connect-MgGraph, and builds no session' {
            $R = Invoke-NiProbe -Parameters @{ TenantId = 'contoso.onmicrosoft.com'; AuthMethod = 'Interactive'; IncludeARM = $true }

            $R.Caught.FullyQualifiedErrorId | Should -BeExactly 'InteractiveSignInUnavailable,Initialize-OERAuth'
            $R.Caught.TargetObject | Should -BeExactly 'contoso.onmicrosoft.com'
            Should -Invoke -ModuleName $script:moduleName Get-AzToken -Times 0 -Exactly
            Should -Invoke -ModuleName $script:moduleName Resolve-OERTenantDomain -Times 0 -Exactly
            Should -Invoke -ModuleName $script:moduleName Connect-MgGraph -Times 0 -Exactly
            InModuleScope $script:moduleName { $script:_OERAuthState } | Should -BeNullOrEmpty
        }

        It 'refuses a call that names no -AuthMethod, since the default is the interactive sign-in' {
            $R = Invoke-NiProbe -Parameters @{ TenantId = $script:NiTenant }

            $R.Caught.FullyQualifiedErrorId | Should -BeExactly 'InteractiveSignInUnavailable,Initialize-OERAuth'
            Should -Invoke -ModuleName $script:moduleName Get-AzToken -Times 0 -Exactly
        }

        It 'leaves the calling command latched and the session marked uncertain' {
            $R = Invoke-NiProbe -Parameters @{ TenantId = $script:NiTenant; AuthMethod = 'Interactive' }

            $R.Caught.FullyQualifiedErrorId | Should -BeExactly 'InteractiveSignInUnavailable,Initialize-OERAuth'
            $R.Refusal | Should -Not -BeNullOrEmpty
            $R.Marker | Should -BeTrue
        }

        It 'asks the host question once per call' {
            $null = Invoke-NiProbe -Parameters @{ TenantId = $script:NiTenant; AuthMethod = 'Interactive'; IncludeARM = $true }

            Should -Invoke -ModuleName $script:moduleName Test-OERHostNonInteractive -Times 1 -Exactly
        }

        It 'is refused before the silent renewal of a session that would otherwise renew without a prompt' {
            # Control: in a host that can prompt, the same expired session renews silently (one silent request).
            Mock -ModuleName $script:moduleName Test-OERHostNonInteractive { $false }
            $Parameters = @{ TenantId = $script:NiTenant; AuthMethod = 'Interactive' }
            $First = Invoke-NiProbe -Parameters $Parameters
            $First.Caught | Should -BeNullOrEmpty
            (InModuleScope $script:moduleName { $script:_OERInteractiveCredential }) | Should -Not -BeNullOrEmpty
            Set-NiGraphExpiry -Minutes 2
            $script:NiCalls.Clear()
            $Renewed = Invoke-NiProbe -Parameters $Parameters
            $Renewed.Caught | Should -BeNullOrEmpty
            Get-NiSilentCallCount | Should -Be 1 -Because 'the control renews silently, so the refusal below is what stops it'

            # The same session, expired again, in a -NonInteractive host: refused, no token request at all.
            Set-NiGraphExpiry -Minutes 2
            $script:NiCalls.Clear()
            Mock -ModuleName $script:moduleName Test-OERHostNonInteractive { $true }
            $R = Invoke-NiProbe -Parameters $Parameters

            $R.Caught.FullyQualifiedErrorId | Should -BeExactly 'InteractiveSignInUnavailable,Initialize-OERAuth'
            $script:NiCalls.Count | Should -Be 0 -Because 'neither a silent nor an interactive request is made'
            Should -Invoke -ModuleName $script:moduleName Connect-MgGraph -Times 2 -Exactly
        }

        It 'refuses a cached Microsoft Graph session that needs a NEW Azure Resource Manager token, before any token request at all' {
            # The guard stands before the Graph block, not between the Graph and the ARM block: a valid cached
            # Graph session with -IncludeARM falls through the cached return (the ARM token is missing) and must
            # not send even the ARM request.
            Mock -ModuleName $script:moduleName Test-OERHostNonInteractive { $false }
            $First = Invoke-NiProbe -Parameters @{ TenantId = $script:NiTenant; AuthMethod = 'Interactive' }
            $First.Caught | Should -BeNullOrEmpty
            $script:NiCalls.Count | Should -Be 1 -Because 'the control signed in once, for Microsoft Graph only'
            $script:NiCalls.Clear()
            Mock -ModuleName $script:moduleName Test-OERHostNonInteractive { $true }

            $R = Invoke-NiProbe -Parameters @{ TenantId = $script:NiTenant; AuthMethod = 'Interactive'; IncludeARM = $true }

            $R.Caught.FullyQualifiedErrorId | Should -BeExactly 'InteractiveSignInUnavailable,Initialize-OERAuth'
            $script:NiCalls.Count | Should -Be 0 -Because 'neither a Graph nor an ARM token request is made'
            $R.Refusal | Should -Not -BeNullOrEmpty
        }

        It 'refuses -ForceRefresh of a cached interactive session before any token request at all' {
            Mock -ModuleName $script:moduleName Test-OERHostNonInteractive { $false }
            $First = Invoke-NiProbe -Parameters @{ TenantId = $script:NiTenant; AuthMethod = 'Interactive' }
            $First.Caught | Should -BeNullOrEmpty
            $script:NiCalls.Clear()
            Mock -ModuleName $script:moduleName Test-OERHostNonInteractive { $true }

            $R = Invoke-NiProbe -Parameters @{ TenantId = $script:NiTenant; AuthMethod = 'Interactive'; ForceRefresh = $true }

            $R.Caught.FullyQualifiedErrorId | Should -BeExactly 'InteractiveSignInUnavailable,Initialize-OERAuth'
            $script:NiCalls.Count | Should -Be 0 -Because 'the Graph request a forced refresh would send is never made'
            $R.Refusal | Should -Not -BeNullOrEmpty
        }
    }

    Context 'what the refusal does not touch' {
        It 'allows an interactive sign-in in a host that can prompt' {
            Mock -ModuleName $script:moduleName Test-OERHostNonInteractive { $false }

            $R = Invoke-NiProbe -Parameters @{ TenantId = $script:NiTenant; AuthMethod = 'Interactive' }

            $R.Caught | Should -BeNullOrEmpty
            Should -Invoke -ModuleName $script:moduleName Get-AzToken -Times 1 -Exactly
            Should -Invoke -ModuleName $script:moduleName Test-OERHostNonInteractive -Times 1 -Exactly
        }

        It 'answers a session that is still valid from the cache: no refusal, no token request, no host question' {
            Mock -ModuleName $script:moduleName Test-OERHostNonInteractive { $false }
            $Parameters = @{ TenantId = $script:NiTenant; AuthMethod = 'Interactive' }
            $null = Invoke-NiProbe -Parameters $Parameters
            $script:NiCalls.Clear()
            # Counted by the mock itself: a mock set again in the same scope keeps the call history of the one
            # it replaces, so Should -Invoke could not tell the two sign-ins apart.
            $script:NiHostAsked = 0
            Mock -ModuleName $script:moduleName Test-OERHostNonInteractive { $script:NiHostAsked++; $true }

            $R = Invoke-NiProbe -Parameters $Parameters

            $R.Caught | Should -BeNullOrEmpty
            $script:NiCalls.Count | Should -Be 0
            $script:NiHostAsked | Should -Be 0
            Should -Invoke -ModuleName $script:moduleName Get-AzToken -Times 1 -Exactly
        }

        It 'does not ask the host question for <Method>' -ForEach @(
            @{ Method = 'DeviceCode' }
            @{ Method = 'ManagedIdentity' }
            @{ Method = 'ClientSecret' }
            @{ Method = 'ClientCertificate' }
        ) {
            $Parameters = @{ TenantId = $script:NiTenant; AuthMethod = $Method }
            if ($Method -eq 'ClientSecret') {
                $Parameters.ClientId = '33333333-3333-3333-3333-333333333333'
                $Parameters.ClientSecret = ConvertTo-SecureString 'NOT-A-REAL-TOKEN' -AsPlainText -Force
            }
            if ($Method -eq 'ClientCertificate') {
                $Parameters.ClientId = '33333333-3333-3333-3333-333333333333'
                $Parameters.CertificatePath = 'TestDrive:\oer-test.pfx'
            }

            $R = Invoke-NiProbe -Parameters $Parameters

            $R.Caught | Should -BeNullOrEmpty
            Should -Invoke -ModuleName $script:moduleName Get-AzToken -Times 1 -Exactly
            Should -Invoke -ModuleName $script:moduleName Test-OERHostNonInteractive -Times 0 -Exactly
        }
    }

    Context 'a public command in a script with no try above it' {
        BeforeAll {
            . "$PSScriptRoot/../TestHelpers/OERConfirmHost.ps1"
            # Get-OERGroup in a runspace (Invoke-OERWithConfirmAnswer), no session, the host question faked to
            # $true in that runspace's copy of the module. Every token and Graph request the module could make
            # is replaced by a function that logs a line, so an empty log proves nothing was requested.
            function script:New-NiNoTryScenario {
                param([string]$Log)
                [scriptblock]::Create((@'
Import-Module Omnicit.EntraRBAC -Force -ErrorAction Stop
& (Get-Module Omnicit.EntraRBAC) {
    $script:_OERAuthState = $null
    $script:_OERSessionUncertain = $null
    $script:_OERInteractiveCredential = $null
    Set-Item -Path function:script:Test-OERHostNonInteractive -Value { $true }
    Set-Item -Path function:script:Get-AzToken -Value { [System.IO.File]::AppendAllText('#LOG#', "TOKEN`n"); throw 'NOT-A-REAL-TOKEN unexpected' }
    Set-Item -Path function:script:Connect-MgGraph -Value { [System.IO.File]::AppendAllText('#LOG#', "CONNECT`n") }
    Set-Item -Path function:script:Invoke-MgGraphRequest -Value { [System.IO.File]::AppendAllText('#LOG#', "GRAPH`n") }
    Set-Item -Path function:script:Resolve-OERTenantDomain -Value { [System.IO.File]::AppendAllText('#LOG#', "LOOKUP`n"); 'eeee0000-0000-0000-0000-000000000001' }
}
$All = @(Get-OERGroup -Group 'g1' -TenantId 'contoso.onmicrosoft.com' -ErrorAction Continue 2>&1)
foreach ($E in $All) { "ERR:$($E.FullyQualifiedErrorId)" }
# The three stubs of a transport name above shadow the tripwire's replacements in this runspace's copy of the
# module, and the tripwire check after the scenario reads that scope (a name that no longer resolves to a
# replacement is a hit): removed here, the nearest definition being the stub, so the check sees them again.
& (Get-Module Omnicit.EntraRBAC) {
    foreach ($Name in 'Get-AzToken', 'Connect-MgGraph', 'Invoke-MgGraphRequest') {
        Remove-Item -Path ('function:' + $Name) -ErrorAction SilentlyContinue
    }
}
'END'
'@).Replace('#LOG#', $Log.Replace("'", "''")))
            }
        }

        It 'raises one InteractiveSignInUnavailable, refuses the command''s own Graph call, requests nothing and carries on' {
            $Log = Join-Path $TestDrive ('{0}.log' -f [guid]::NewGuid())
            $Run = Invoke-OERWithConfirmAnswer -Answer '&Yes' -Script (New-NiNoTryScenario -Log $Log)

            $Run.Output[-1] | Should -BeExactly 'END'
            @($Run.Output | Where-Object { $_ -like 'ERR:*' }) | Should -Be @(
                'ERR:InteractiveSignInUnavailable,Initialize-OERAuth'
                'ERR:SignInRefused,Get-OERGroup'
            )
            if (Test-Path -LiteralPath $Log) { @(Get-Content -LiteralPath $Log) | Should -BeNullOrEmpty }
            $Run.Warnings | Should -BeNullOrEmpty
        }
    }
}

Describe 'Initialize-OERAuth token failures reach a public command''s caller exactly once (BL-20)' {
    # BL-20 pins what was measured on 2026-10-21 (no code change): a token that cannot be acquired reaches the
    # caller of a public command, with no try above it, as ONE record of Initialize-OERAuth's (the sign-in's
    # own id) followed by ONE SignInRefused of the command itself (its own Graph or ARM call, refused by the
    # latch before anything is sent), and no warning. The real Initialize-OERAuth and the real public command
    # run in a runspace; only what could leave the process is replaced, in that runspace's copy of the module,
    # by functions that log a line. The host question is faked to $false there for certainty: a runspace is the
    # 'Default Host', where the real Test-OERHostNonInteractive answers $false anyway (the interactive sign-in
    # below is therefore not refused as InteractiveSignInUnavailable).
    BeforeAll {
        . "$PSScriptRoot/../TestHelpers/OERConfirmHost.ps1"
        function script:New-TfNoTryScenario {
            param([string]$Log, [string]$Mode, [string]$Call)
            [scriptblock]::Create((@'
Import-Module Omnicit.EntraRBAC -Force -ErrorAction Stop
& (Get-Module Omnicit.EntraRBAC) {
    $script:_OERAuthState = $null
    $script:_OERSessionUncertain = $null
    $script:_OERInteractiveCredential = $null
    Set-Item -Path function:script:Test-OERHostNonInteractive -Value { $false }
    # The Graph token is acquired; the Azure Resource Manager one is not (Mode Arm), or no token at all is (Graph).
    Set-Item -Path function:script:Get-AzToken -Value {
        param($ClientId, $Resource, $Tenant, $Scope, $Interactive, $Force, $CredentialPrecedence, $ErrorAction, $WarningAction)
        [System.IO.File]::AppendAllText('#LOG#', "TOKEN $Resource`n")
        if ('#MODE#' -eq 'Graph' -or ([string]$Resource -match 'management')) { throw 'NOT-A-REAL-TOKEN the token request failed' }
        [pscustomobject]@{
            Token     = 'NOT-A-REAL-TOKEN-tf'
            ExpiresOn = [DateTimeOffset]::UtcNow.AddHours(1)
            Identity  = 'admin@contoso.com'
            TenantId  = '66666666-6666-6666-6666-666666666666'
        }
    }
    Set-Item -Path function:script:Get-OERTokenObjectId -Value { '88888888-8888-8888-8888-888888888888' }
    Set-Item -Path function:script:Connect-MgGraph -Value { [System.IO.File]::AppendAllText('#LOG#', "CONNECT`n") }
    Set-Item -Path function:script:Get-MgContext -Value {
        [pscustomobject]@{ AuthType = 'UserProvidedAccessToken'; TokenCredentialType = 'UserProvidedAccessToken'
            ClientId = '11111111-1111-1111-1111-111111111111'; TenantId = '66666666-6666-6666-6666-666666666666'
            Account = 'admin@contoso.com'; AppName = 'oer-test-app'; Environment = 'Global'; Scopes = @('Group.ReadWrite.All') }
    }
    Set-Item -Path function:script:Invoke-MgGraphRequest -Value { [System.IO.File]::AppendAllText('#LOG#', "GRAPH`n") }
    Set-Item -Path function:script:Invoke-WebRequest -Value { [System.IO.File]::AppendAllText('#LOG#', "ARM`n") }
    Set-Item -Path function:script:Resolve-OERTenantDomain -Value { [System.IO.File]::AppendAllText('#LOG#', "LOOKUP`n"); '66666666-6666-6666-6666-666666666666' }
}
$All = @(#CALL# 2>&1)
foreach ($E in $All) { "ERR:$($E.FullyQualifiedErrorId)" }
# The four stubs of a transport name above shadow the tripwire's replacements in this runspace's copy of the
# module, and the tripwire check after the scenario reads that scope: removed here (the nearest definition,
# which is the stub), so the check sees the replacements again.
& (Get-Module Omnicit.EntraRBAC) {
    foreach ($Name in 'Get-AzToken', 'Connect-MgGraph', 'Invoke-MgGraphRequest', 'Invoke-WebRequest') {
        Remove-Item -Path ('function:' + $Name) -ErrorAction SilentlyContinue
    }
}
'END'
'@).Replace('#LOG#', $Log.Replace("'", "''")).Replace('#MODE#', $Mode).Replace('#CALL#', $Call))
        }
    }

    It 'an Azure Resource Manager token failure reaches Get-OERSubscription''s caller as one ArmTokenAcquisitionFailed and one SignInRefused, with no warning and nothing sent' {
        $Log = Join-Path $TestDrive ('{0}.log' -f [guid]::NewGuid())
        $Run = Invoke-OERWithConfirmAnswer -Answer '&Yes' -Script (New-TfNoTryScenario -Log $Log -Mode 'Arm' -Call "Get-OERSubscription -TenantId '66666666-6666-6666-6666-666666666666' -ErrorAction Continue")

        $Run.Output[-1] | Should -BeExactly 'END'
        @($Run.Output | Where-Object { $_ -like 'ERR:*' }) | Should -Be @(
            'ERR:ArmTokenAcquisitionFailed,Initialize-OERAuth'
            'ERR:SignInRefused,Get-OERSubscription'
        )
        $Run.Warnings | Should -BeNullOrEmpty
        # Reach proof: the Graph token was acquired and connected, and the ARM token request is what failed;
        # no Graph or ARM request left the command.
        @(Get-Content -LiteralPath $Log | Where-Object { $_ -like 'TOKEN*' -or $_ -eq 'CONNECT' }) |
            Should -Be @('TOKEN https://graph.microsoft.com/', 'CONNECT', 'TOKEN https://management.azure.com/')
        @(Get-Content -LiteralPath $Log | Where-Object { $_ -eq 'GRAPH' -or $_ -eq 'ARM' }).Count | Should -Be 0
    }

    It 'a Microsoft Graph token failure reaches Get-OERGroup''s caller as one GraphTokenAcquisitionFailed and one SignInRefused, with no warning and nothing sent' {
        $Log = Join-Path $TestDrive ('{0}.log' -f [guid]::NewGuid())
        $Run = Invoke-OERWithConfirmAnswer -Answer '&Yes' -Script (New-TfNoTryScenario -Log $Log -Mode 'Graph' -Call "Get-OERGroup -Group 'g1' -TenantId '66666666-6666-6666-6666-666666666666' -ErrorAction Continue")

        $Run.Output[-1] | Should -BeExactly 'END'
        @($Run.Output | Where-Object { $_ -like 'ERR:*' }) | Should -Be @(
            'ERR:GraphTokenAcquisitionFailed,Initialize-OERAuth'
            'ERR:SignInRefused,Get-OERGroup'
        )
        $Run.Warnings | Should -BeNullOrEmpty
        @(Get-Content -LiteralPath $Log | Where-Object { $_ -like 'TOKEN*' -or $_ -eq 'CONNECT' }) |
            Should -Be @('TOKEN https://graph.microsoft.com/')
        @(Get-Content -LiteralPath $Log | Where-Object { $_ -eq 'GRAPH' -or $_ -eq 'ARM' }).Count | Should -Be 0
    }
}

Describe 'Initialize-OERAuth never continues a renewal as another account (BL-119)' {
    # A renewal of the module's sign-in -- a Graph token renewed near its expiry, or a transport's
    # refresh -- can be answered in the browser by ANOTHER account of the same tenant. Every command that
    # began under the first account would then carry on under the second one with the same identity
    # string. A renewal whose new Graph token carries an oid that is a GUID differing from the session's
    # (a GUID) is refused for its caller with SignInSuperseded (-AccountChanged) BEFORE Connect-MgGraph
    # and before the state is rebuilt, exactly as the ARM token of a renewal is: the session stays the
    # account it was (state, Graph SDK session, ARM token, identity, memory), the caller stays latched and
    # the session stays uncertain (A31). A renewal whose token carries no oid never replaces the
    # session's SignedInObjectId (D2).
    #
    # Nothing here reaches AzAuth: Get-AzToken, Connect-MgGraph and Get-MgContext are mocked, and so is
    # Get-OERTokenObjectId (the fake tokens are not JWTs; the oid travels after a '|' in the fake token
    # text). The oid the mocked Get-AzToken returns for each resource is set per test.
    BeforeAll {
        $script:A119Tenant = '66666666-6666-6666-6666-666666666666'
        $script:A119OidA = '88888888-8888-8888-8888-888888888888'
        $script:A119OidB = '99999999-9999-9999-9999-999999999999'
        $script:A119OtherTenant = '77777777-7777-7777-7777-777777777777'
        $script:A119Domain = 'contoso.onmicrosoft.com'

        # The mocked Get-AzToken answers each resource with the oid set for it (an empty one is a token
        # with no oid claim), and with the tenant set for it ($script:A119GrantedTenant, the tenant above
        # unless a test moves it): the tenant the token is issued for, whatever the request named.
        $script:A119TokenMock = {
            param($ClientId, $ClientSecret, $Resource, $Tenant, $ErrorAction, $WarningAction, $Interactive,
                  $DeviceCode, $ManagedIdentity, $ClientCertificate, $ClientCertificatePath,
                  $Scope, $Force, $Claim, $CredentialPrecedence)
            $IsArm = [string]$Resource -like '*management*'
            [string]$Oid = if ($IsArm) { $script:A119ArmOid } else { $script:A119GraphOid }
            [pscustomobject]@{
                Token     = "NOT-A-REAL-TOKEN-a119|$Oid"
                ExpiresOn = [DateTimeOffset]::UtcNow.AddHours(1)
                Identity  = "account-$Oid@contoso.com"
                TenantId  = $script:A119GrantedTenant
            }
        }

        # Runs Initialize-OERAuth from a command of its own (so the latch and the memory have a frame to
        # key on, as in a public command) and returns what that command saw: the error it caught, whether
        # it is latched, the marker, whether it remembers an identity, and the identity it remembers.
        function script:Invoke-A119Probe {
            param([hashtable]$Parameters = @{})
            InModuleScope $script:moduleName -Parameters @{ P = $Parameters } {
                param($P)
                $Holder = @{ Caught = $null }
                function Invoke-A119Command {
                    [CmdletBinding()]
                    param()
                    try { Initialize-OERAuth @P } catch { $Holder.Caught = $PSItem }
                    $Holder.Latched = [bool](Get-OERSignInRefusal)
                    $Holder.Marker = $script:_OERSessionUncertain
                    $Remembered = $null
                    $Holder.Remembers = $script:_OERSignInIdentity.TryGetValue($MyInvocation, [ref]$Remembered)
                    $Holder.Remembered = $Remembered
                }
                Invoke-A119Command
                $Holder
            }
        }

        function script:Get-A119Info {
            InModuleScope $script:moduleName {
                $S = $script:_OERAuthState
                if ($null -eq $S) { return $null }
                [pscustomobject]@{
                    AccountId     = $S.SignInAccountId
                    HasChangedKey = $S.ContainsKey('SignInAccountChanged')
                    Oid           = $S.SignedInObjectId
                    Label         = $S.TenantId
                    TokenTenant   = $S.TokenTenantId
                    Account       = $S.Account
                    Expiry        = $S.GraphTokenExpiry
                    HasArm        = [bool]$S.ArmToken
                    ArmTenant     = $S.ArmTokenTenantId
                    Identity      = Get-OERSignInIdentity
                }
            }
        }

        # The first sign-in of a test; its token requests are forgotten afterwards by the caller's
        # Should -Invoke counts being taken relative to the totals the test states.
        function script:Start-A119Session {
            param([string]$Method = 'Interactive', [switch]$Arm, [string]$GraphOid = $script:A119OidA, [string]$ArmOid = $script:A119OidA, [string]$Label)
            $script:A119GraphOid = $GraphOid
            $script:A119ArmOid = $ArmOid
            $Parameters = @{ TenantId = $script:A119Tenant; AuthMethod = $Method }
            # -Label organizations: the sign-in names no tenant, as a bare Connect-OER or a bare command does.
            if ($Label -eq 'organizations') { $Parameters.Remove('TenantId') }
            if ($Arm) { $Parameters.IncludeARM = $true }
            $Probe = Invoke-A119Probe $Parameters
            $Probe.Caught | Should -BeNullOrEmpty -Because 'the first sign-in of the test succeeds'
            $Probe.Latched | Should -BeFalse
        }

        function script:Set-A119Expiry {
            param([int]$GraphMinutes)
            InModuleScope $script:moduleName -Parameters @{ G = $GraphMinutes } {
                param($G)
                $script:_OERAuthState.GraphTokenExpiry = [DateTime]::UtcNow.AddMinutes($G)
            }
        }

        # A session of account A with an ARM token, a Graph token near its expiry, and one renewal answered
        # by account B and refused. $script:A119Before is the state after the expiry was moved and before the
        # renewal, so a comparison with it proves the refusal touched nothing.
        function script:Invoke-A119Refusal {
            param([string]$Method = 'DeviceCode', [hashtable]$Renewal = @{})
            Start-A119Session -Method $Method -Arm
            Set-A119Expiry -GraphMinutes 2
            $script:A119Before = Get-A119Info
            $script:A119Before.HasArm | Should -BeTrue
            $script:A119Before.AccountId | Should -BeExactly $script:A119OidA
            $script:A119GraphOid = $script:A119OidB
            $Probe = Invoke-A119Probe $Renewal
            $Probe.Caught.FullyQualifiedErrorId | Should -BeExactly 'SignInSuperseded,Initialize-OERAuth'
            $Probe.Marker | Should -BeTrue
            $Probe
        }

        # The state is exactly what it was before the refused renewal(s): account A, oid A, the same account
        # name, the same Graph token expiry (a rebuild would carry a new one), the ARM token and its tenant,
        # the same identity, and no key for an account change.
        function script:Assert-A119StateUnchanged {
            $After = Get-A119Info
            $After.AccountId | Should -BeExactly $script:A119OidA
            $After.Oid | Should -BeExactly $script:A119OidA
            $After.Account | Should -BeExactly $script:A119Before.Account
            $After.Expiry | Should -Be $script:A119Before.Expiry
            $After.HasArm | Should -BeTrue
            $After.ArmTenant | Should -Not -BeNullOrEmpty
            $After.ArmTenant | Should -BeExactly $script:A119Before.ArmTenant
            $After.Identity | Should -BeExactly $script:A119Before.Identity
            $After.HasChangedKey | Should -BeFalse
        }

        # A session named by another label (D4) that a refusal left as it was: against $script:A119Before
        # (taken before the refused call) the label, account, oid, account name, Graph token expiry,
        # identity and ARM token are all unchanged, and the account is A.
        function script:Assert-A119SessionHeld {
            param([string]$Label)
            $After = Get-A119Info
            $After.Label | Should -BeExactly $Label
            $After.Label | Should -BeExactly $script:A119Before.Label
            $After.AccountId | Should -BeExactly $script:A119OidA
            $After.Oid | Should -BeExactly $script:A119OidA
            $After.Account | Should -BeExactly $script:A119Before.Account
            $After.Expiry | Should -Be $script:A119Before.Expiry
            $After.Identity | Should -BeExactly $script:A119Before.Identity
            $After.HasArm | Should -Be $script:A119Before.HasArm
            $After.HasChangedKey | Should -BeFalse
        }
    }

    BeforeEach {
        InModuleScope $script:moduleName {
            $script:_OERAuthState = $null
            $script:_OERSessionUncertain = $null
            $script:_OERLastAuthorityHost = $null
            $script:_OERLastTokenRequest = $null
            $script:_OERInteractiveCredential = $null
        }
        $script:A119GraphOid = $script:A119OidA
        $script:A119ArmOid = $script:A119OidA
        $script:A119GrantedTenant = $script:A119Tenant
        Mock -ModuleName $script:moduleName Get-AzToken -MockWith $script:A119TokenMock
        Mock -ModuleName $script:moduleName Connect-MgGraph { }
        Mock -ModuleName $script:moduleName Disconnect-MgGraph { }
        Mock -ModuleName $script:moduleName Resolve-OERTenantDomain { '66666666-6666-6666-6666-666666666666' }
        Mock -ModuleName $script:moduleName Get-OERTokenObjectId {
            param($Token)
            $Plain = [System.Net.NetworkCredential]::new('', $Token).Password
            $Parts = $Plain -split '\|'
            if ($Parts.Count -gt 1 -and $Parts[1]) { $Parts[1] } else { $null }
        }
    }

    Context 'a renewal answered by another account is refused' {
        It 'refuses the caller with SignInSuperseded before Connect-MgGraph, latched and uncertain, and leaves the session the old account''s (<Case>)' -ForEach @(
            @{ Case = 'interactive, near expiry'; Method = 'Interactive'; Renewal = @{} }
            @{ Case = 'device code, near expiry'; Method = 'DeviceCode'; Renewal = @{} }
            @{ Case = 'interactive, a sign-in naming only the tenant'; Method = 'Interactive'; Renewal = @{ TenantId = '66666666-6666-6666-6666-666666666666' } }
            @{ Case = 'interactive, a transport refresh (-ForceRefresh and the state''s -AuthMethod)'; Method = 'Interactive'; Renewal = @{ TenantId = '66666666-6666-6666-6666-666666666666'; AuthMethod = 'Interactive'; ForceRefresh = $true } }
            @{ Case = 'device code, a transport refresh (-ForceRefresh and the state''s -AuthMethod)'; Method = 'DeviceCode'; Renewal = @{ TenantId = '66666666-6666-6666-6666-666666666666'; AuthMethod = 'DeviceCode'; ForceRefresh = $true } }
        ) {
            $Probe = Invoke-A119Refusal -Method $Method -Renewal $Renewal

            $Probe.Caught.FullyQualifiedErrorId | Should -BeExactly 'SignInSuperseded,Initialize-OERAuth'
            $Probe.Caught.CategoryInfo.Category | Should -Be ([System.Management.Automation.ErrorCategory]::AuthenticationError)
            $Probe.Caught.TargetObject | Should -BeExactly 'Invoke-A119Command'
            $Probe.Caught.Exception.Message | Should -BeLike "A renewal of the module's sign-in, or a sign-in of its tenant named another way, returned a token for another account than the one Invoke-A119Command began with,*The token was not used and the session stays the account it was: run the command again and choose that account, or run Connect-OER -Force to sign in as another account."
            $Probe.Latched | Should -BeTrue
            $Probe.Marker | Should -BeTrue
            $Probe.Remembers | Should -BeFalse -Because 'a refused sign-in is not remembered'
            Assert-A119StateUnchanged
            # Not vacuous: the renewal ran its token request, and only the first sign-in connected the session.
            Should -Invoke -ModuleName $script:moduleName Get-AzToken -Times 2 -Exactly -ParameterFilter { [string]$Resource -notlike '*management*' }
            Should -Invoke -ModuleName $script:moduleName Connect-MgGraph -Times 1 -Exactly
        }

        It 'requests no ARM token for a refused renewal, although -IncludeARM is passed, and keeps the cached one' {
            Start-A119Session -Arm
            Set-A119Expiry -GraphMinutes 2
            $script:A119Before = Get-A119Info
            $script:A119GraphOid = $script:A119OidB

            $Probe = Invoke-A119Probe @{ IncludeARM = $true }

            $Probe.Caught.FullyQualifiedErrorId | Should -BeExactly 'SignInSuperseded,Initialize-OERAuth'
            Assert-A119StateUnchanged
            # The first sign-in asked for one ARM token; the refused renewal asked for none.
            Should -Invoke -ModuleName $script:moduleName Get-AzToken -Times 1 -Exactly -ParameterFilter { [string]$Resource -like '*management*' }
        }

        It 'does not supersede an outer command that remembers the old account: it is still the session''s, and nested sign-ins that name the tenant renew again (device code)' {
            Start-A119Session -Method DeviceCode
            $script:A119GraphOid = $script:A119OidB
            $Result = InModuleScope $script:moduleName -Parameters @{ T = $script:A119Tenant; SetOid = { param($O) $script:A119GraphOid = $O }; OidA = $script:A119OidA } {
                param($T, $SetOid, $OidA)
                $Holder = @{}
                function Invoke-A119Inner {
                    [CmdletBinding()]
                    param()
                    try { Initialize-OERAuth } catch { $Holder.InnerCaught = $PSItem }
                }
                function Invoke-A119Inner2 {
                    [CmdletBinding()]
                    param()
                    try { Initialize-OERAuth -TenantId $T } catch { $Holder.Inner2Caught = $PSItem }
                }
                function Invoke-A119Inner3 {
                    [CmdletBinding()]
                    param()
                    try { Initialize-OERAuth -TenantId $T } catch { $Holder.Inner3Caught = $PSItem }
                }
                function Invoke-A119Outer {
                    [CmdletBinding()]
                    param()
                    # The outer command signs in as account A (a cache hit of the session above): remembered.
                    Initialize-OERAuth -TenantId $T -AuthMethod DeviceCode
                    $Remembered = $null
                    $Holder.OuterRemembers = $script:_OERSignInIdentity.TryGetValue($MyInvocation, [ref]$Remembered)
                    $Holder.OuterIdentity = $Remembered
                    $Holder.SupersededBefore = Get-OERSignInSupersession
                    $script:_OERAuthState.GraphTokenExpiry = [DateTime]::UtcNow.AddMinutes(2)
                    Invoke-A119Inner
                    $Holder.SupersededAfter = Get-OERSignInSupersession
                    $Holder.StateIdentity = Get-OERSignInIdentity
                    # A second nested sign-in naming the tenant: the session still renews (a token request), and
                    # B answering again refuses it again.
                    Invoke-A119Inner2
                    $Holder.SupersededAfter2 = Get-OERSignInSupersession
                    # The session's own account answers: not refused.
                    & $SetOid $OidA
                    Invoke-A119Inner3
                    $Holder.SupersededAfter3 = Get-OERSignInSupersession
                    $Holder.FinalIdentity = Get-OERSignInIdentity
                }
                Invoke-A119Outer
                $Holder
            }

            $Result.OuterRemembers | Should -BeTrue
            $Result.SupersededBefore | Should -BeNullOrEmpty -Because 'the outer command remembers the identity the state carried'
            $Result.InnerCaught.FullyQualifiedErrorId | Should -BeExactly 'SignInSuperseded,Initialize-OERAuth'
            $Result.InnerCaught.TargetObject | Should -BeExactly 'Invoke-A119Inner'
            $Result.SupersededAfter | Should -BeNullOrEmpty -Because 'the refused renewal left the identity as it was'
            $Result.StateIdentity | Should -BeExactly $Result.OuterIdentity
            # The next nested sign-in is refused for its own renewal, not as the outer command's superseded session.
            $Result.Inner2Caught.FullyQualifiedErrorId | Should -BeExactly 'SignInSuperseded,Initialize-OERAuth'
            $Result.Inner2Caught.TargetObject | Should -BeExactly 'Invoke-A119Inner2'
            $Result.SupersededAfter2 | Should -BeNullOrEmpty
            $Result.Inner3Caught | Should -BeNullOrEmpty
            $Result.SupersededAfter3 | Should -BeNullOrEmpty
            $Result.FinalIdentity | Should -BeExactly $Result.OuterIdentity
            # The first sign-in, then three renewals that each made a request (two refused, one answered by A).
            Should -Invoke -ModuleName $script:moduleName Get-AzToken -Times 4 -Exactly
            Should -Invoke -ModuleName $script:moduleName Connect-MgGraph -Times 2 -Exactly
        }

        It 'leaves a transport nothing to refuse for an outer command that remembers the old account' {
            Start-A119Session
            Set-A119Expiry -GraphMinutes 2
            $script:A119GraphOid = $script:A119OidB
            $Result = InModuleScope $script:moduleName {
                $Holder = @{}
                function Invoke-A119Renewer {
                    [CmdletBinding()]
                    param()
                    try { Initialize-OERAuth } catch { $Holder.Caught = $PSItem }
                }
                function Invoke-A119Outer {
                    [CmdletBinding()]
                    param()
                    Register-OERSignInIdentity -Invocation $MyInvocation
                    Invoke-A119Renewer
                    $Holder.Superseded = Get-OERSignInSupersession
                }
                Invoke-A119Outer
                $Holder
            }
            $Result.Caught.FullyQualifiedErrorId | Should -BeExactly 'SignInSuperseded,Initialize-OERAuth'
            $Result.Superseded | Should -BeNullOrEmpty -Because 'no transport refuses an outer command for a refused renewal'
        }
    }

    Context 'after a refused renewal the session is still the old account''s (A31)' {
        It 'refuses a later sign-in that names the tenant again when the other account answers again, and still touches nothing' {
            $null = Invoke-A119Refusal

            $Probe = Invoke-A119Probe @{ TenantId = $script:A119Tenant }

            $Probe.Caught.FullyQualifiedErrorId | Should -BeExactly 'SignInSuperseded,Initialize-OERAuth'
            $Probe.Latched | Should -BeTrue
            $Probe.Marker | Should -BeTrue
            Assert-A119StateUnchanged
            Should -Invoke -ModuleName $script:moduleName Connect-MgGraph -Times 1 -Exactly
            # The first sign-in, the refused renewal and the second refused renewal each requested a Graph token.
            Should -Invoke -ModuleName $script:moduleName Get-AzToken -Times 3 -Exactly -ParameterFilter { [string]$Resource -notlike '*management*' }
        }

        It 'lets a later sign-in that names the tenant succeed when the session''s own account answers: the marker is cleared and the identity remembered' {
            $null = Invoke-A119Refusal
            $script:A119GraphOid = $script:A119OidA

            $Probe = Invoke-A119Probe @{ TenantId = $script:A119Tenant }

            $Probe.Caught | Should -BeNullOrEmpty
            $Probe.Latched | Should -BeFalse
            $Probe.Marker | Should -BeFalse
            $Probe.Remembers | Should -BeTrue
            $Probe.Remembered | Should -BeExactly $script:A119Before.Identity
            $After = Get-A119Info
            $After.AccountId | Should -BeExactly $script:A119OidA
            $After.Identity | Should -BeExactly $script:A119Before.Identity
            $After.HasChangedKey | Should -BeFalse
            Should -Invoke -ModuleName $script:moduleName Connect-MgGraph -Times 2 -Exactly
        }

        It 'refuses a later sign-in that names no tenant with SignInRefused (session uncertain) and requests no token' {
            $null = Invoke-A119Refusal

            $Probe = Invoke-A119Probe @{}

            $Probe.Caught.FullyQualifiedErrorId | Should -BeExactly 'SignInRefused,Initialize-OERAuth'
            $Probe.Latched | Should -BeTrue
            $Probe.Marker | Should -BeTrue
            Assert-A119StateUnchanged
            # Not vacuous: the refused renewal's own request is counted, and the later sign-in added none.
            Should -Invoke -ModuleName $script:moduleName Get-AzToken -Times 2 -Exactly -ParameterFilter { [string]$Resource -notlike '*management*' }
            Should -Invoke -ModuleName $script:moduleName Connect-MgGraph -Times 1 -Exactly
        }

        It 'lets Connect-OER''s sign-in (-ReclaimGraphSession) make the session the other account''s: it is not refused and clears the marker' {
            $null = Invoke-A119Refusal
            # B answers Connect-OER's own, deliberate sign-in.
            $Probe = Invoke-A119Probe @{ TenantId = $script:A119Tenant; AuthMethod = 'DeviceCode'; ReclaimGraphSession = $true }

            $Probe.Caught | Should -BeNullOrEmpty
            $Probe.Latched | Should -BeFalse
            $Probe.Marker | Should -BeFalse
            $After = Get-A119Info
            $After.AccountId | Should -BeExactly $script:A119OidB
            $After.Oid | Should -BeExactly $script:A119OidB
            $After.HasChangedKey | Should -BeFalse
            ($After.Identity -eq $script:A119Before.Identity) | Should -BeFalse -Because 'an explicit sign-in as another account moves the identity'
            Should -Invoke -ModuleName $script:moduleName Connect-MgGraph -Times 2 -Exactly
        }
    }

    Context 'a sign-in that continues the session under another tenant label is held to the account too (D4)' {
        # The session's tenant named by another label -- its tenant ID against a domain, or any tenant after
        # a sign-in that named none (label 'organizations') -- is no renewal for the cache, but the same
        # tenant under the same application, method and cloud: another account answering it is refused.
        It 'refuses a sign-in naming the tenant ID after a sign-in that named none when the other account answers, and leaves the session as it was' {
            Start-A119Session -Arm -Label 'organizations'
            $script:A119Before = Get-A119Info
            $script:A119Before.Label | Should -BeExactly 'organizations'
            $script:A119Before.TokenTenant | Should -BeExactly $script:A119Tenant
            $script:A119Before.HasArm | Should -BeTrue
            $script:A119GraphOid = $script:A119OidB

            $Probe = Invoke-A119Probe @{ TenantId = $script:A119Tenant }

            $Probe.Caught.FullyQualifiedErrorId | Should -BeExactly 'SignInSuperseded,Initialize-OERAuth'
            $Probe.Caught.CategoryInfo.Category | Should -Be ([System.Management.Automation.ErrorCategory]::AuthenticationError)
            $Probe.Caught.TargetObject | Should -BeExactly 'Invoke-A119Command'
            $Probe.Latched | Should -BeTrue
            $Probe.Marker | Should -BeTrue
            $Probe.Remembers | Should -BeFalse
            Assert-A119SessionHeld -Label 'organizations'
            # Not vacuous: the second sign-in ran its token request (the label differs, so no cached return),
            # and only the first one connected the session.
            Should -Invoke -ModuleName $script:moduleName Get-AzToken -Times 2 -Exactly -ParameterFilter { [string]$Resource -notlike '*management*' }
            Should -Invoke -ModuleName $script:moduleName Connect-MgGraph -Times 1 -Exactly
        }

        It 'lets the session''s own account answer it: the marker is cleared, the label is the tenant ID and the account stays A' {
            Start-A119Session -Label 'organizations'
            $Before = Get-A119Info

            $Probe = Invoke-A119Probe @{ TenantId = $script:A119Tenant }

            $Probe.Caught | Should -BeNullOrEmpty
            $Probe.Latched | Should -BeFalse
            $Probe.Marker | Should -BeFalse
            $Probe.Remembers | Should -BeTrue
            $After = Get-A119Info
            $After.Label | Should -BeExactly $script:A119Tenant
            $After.AccountId | Should -BeExactly $script:A119OidA
            $After.Oid | Should -BeExactly $script:A119OidA
            $After.Identity | Should -BeExactly $Before.Identity
            Should -Invoke -ModuleName $script:moduleName Connect-MgGraph -Times 2 -Exactly
        }

        It 'refuses a sign-in naming the tenant by its domain after one naming the tenant ID when the other account answers, and leaves the session as it was' {
            Start-A119Session -Arm
            $script:A119Before = Get-A119Info
            $script:A119Before.Label | Should -BeExactly $script:A119Tenant
            $script:A119GraphOid = $script:A119OidB

            $Probe = Invoke-A119Probe @{ TenantId = $script:A119Domain }

            $Probe.Caught.FullyQualifiedErrorId | Should -BeExactly 'SignInSuperseded,Initialize-OERAuth'
            $Probe.Latched | Should -BeTrue
            $Probe.Marker | Should -BeTrue
            Assert-A119SessionHeld -Label $script:A119Tenant
            Should -Invoke -ModuleName $script:moduleName Resolve-OERTenantDomain -Times 1 -Exactly
            Should -Invoke -ModuleName $script:moduleName Get-AzToken -Times 2 -Exactly -ParameterFilter { [string]$Resource -notlike '*management*' }
            Should -Invoke -ModuleName $script:moduleName Connect-MgGraph -Times 1 -Exactly
        }

        It 'lets the session''s own account answer a sign-in naming the tenant by its domain: the label is the domain and the account stays A' {
            Start-A119Session
            $Before = Get-A119Info

            $Probe = Invoke-A119Probe @{ TenantId = $script:A119Domain }

            $Probe.Caught | Should -BeNullOrEmpty
            $Probe.Latched | Should -BeFalse
            $After = Get-A119Info
            $After.Label | Should -BeExactly $script:A119Domain
            $After.AccountId | Should -BeExactly $script:A119OidA
            $After.Identity | Should -BeExactly $Before.Identity
            Should -Invoke -ModuleName $script:moduleName Connect-MgGraph -Times 2 -Exactly
        }

        It 'carries the account and the oid over a sign-in of that kind whose token has no oid, and holds the next one to them' {
            Start-A119Session -Label 'organizations'
            $Before = Get-A119Info
            $script:A119GraphOid = ''

            $First = Invoke-A119Probe @{ TenantId = $script:A119Tenant }

            $First.Caught | Should -BeNullOrEmpty
            $After = Get-A119Info
            $After.Label | Should -BeExactly $script:A119Tenant
            $After.Oid | Should -BeExactly $script:A119OidA -Because 'a token without an oid never replaces the known oid'
            $After.AccountId | Should -BeExactly $script:A119OidA -Because 'the account is carried over'
            $After.Identity | Should -BeExactly $Before.Identity
            # The next sign-in naming the tenant by its domain, answered by B, is compared with the known account.
            $script:A119Before = Get-A119Info
            $script:A119GraphOid = $script:A119OidB

            $Next = Invoke-A119Probe @{ TenantId = $script:A119Domain }

            $Next.Caught.FullyQualifiedErrorId | Should -BeExactly 'SignInSuperseded,Initialize-OERAuth'
            Assert-A119SessionHeld -Label $script:A119Tenant
        }

        It 'refuses the ARM token of such a sign-in when the other account answers it, after the Graph token was the session''s own, and caches no ARM token' {
            Start-A119Session -Arm -Label 'organizations'
            $script:A119ArmOid = $script:A119OidB

            $Probe = Invoke-A119Probe @{ TenantId = $script:A119Tenant; IncludeARM = $true }

            $Probe.Caught.FullyQualifiedErrorId | Should -BeExactly 'SignInSuperseded,Initialize-OERAuth'
            $Probe.Latched | Should -BeTrue
            $Probe.Marker | Should -BeTrue
            $After = Get-A119Info
            $After.HasArm | Should -BeFalse -Because 'a token of another account is never cached'
            $After.ArmTenant | Should -BeNullOrEmpty
            $After.AccountId | Should -BeExactly $script:A119OidA
            $After.Oid | Should -BeExactly $script:A119OidA
            # Not vacuous: the Graph token was accepted (a second connect) and the ARM token was requested twice in all.
            Should -Invoke -ModuleName $script:moduleName Connect-MgGraph -Times 2 -Exactly
            Should -Invoke -ModuleName $script:moduleName Get-AzToken -Times 2 -Exactly -ParameterFilter { [string]$Resource -like '*management*' }
        }

        It 'caches the ARM token of such a sign-in when the session''s own account answers both' {
            Start-A119Session -Label 'organizations'

            $Probe = Invoke-A119Probe @{ TenantId = $script:A119Tenant; IncludeARM = $true }

            $Probe.Caught | Should -BeNullOrEmpty
            $Probe.Latched | Should -BeFalse
            (Get-A119Info).HasArm | Should -BeTrue
        }

        # No false refusal: each of these is a different session for the cache and for the account check.
        It 'does not refuse a sign-in for another tenant answered by another account (a tenant switch)' {
            Start-A119Session -Label 'organizations'
            $script:A119GraphOid = $script:A119OidB
            $script:A119GrantedTenant = $script:A119OtherTenant

            $Probe = Invoke-A119Probe @{ TenantId = $script:A119OtherTenant }

            $Probe.Caught | Should -BeNullOrEmpty
            $Probe.Latched | Should -BeFalse
            $After = Get-A119Info
            $After.Label | Should -BeExactly $script:A119OtherTenant
            $After.TokenTenant | Should -BeExactly $script:A119OtherTenant
            $After.AccountId | Should -BeExactly $script:A119OidB
            Should -Invoke -ModuleName $script:moduleName Connect-MgGraph -Times 2 -Exactly
        }

        It 'does not refuse a sign-in with another -ClientId answered by another account' {
            Start-A119Session -Label 'organizations'
            $script:A119GraphOid = $script:A119OidB

            $Probe = Invoke-A119Probe @{ TenantId = $script:A119Tenant; ClientId = '55555555-5555-5555-5555-555555555555' }

            $Probe.Caught | Should -BeNullOrEmpty
            $Probe.Latched | Should -BeFalse
            (Get-A119Info).AccountId | Should -BeExactly $script:A119OidB
            Should -Invoke -ModuleName $script:moduleName Connect-MgGraph -Times 2 -Exactly
        }

        It 'does not refuse a sign-in in another cloud answered by another account' {
            Start-A119Session -Label 'organizations'
            $script:A119GraphOid = $script:A119OidB

            $Probe = Invoke-A119Probe @{ TenantId = $script:A119Tenant; Environment = 'USGov' }

            $Probe.Caught | Should -BeNullOrEmpty
            $Probe.Latched | Should -BeFalse
            (Get-A119Info).AccountId | Should -BeExactly $script:A119OidB
            Should -Invoke -ModuleName $script:moduleName Connect-MgGraph -Times 2 -Exactly
        }

        It 'does not refuse a sign-in with another method answered by another account' {
            Start-A119Session -Label 'organizations'
            $script:A119GraphOid = $script:A119OidB

            $Probe = Invoke-A119Probe @{ TenantId = $script:A119Tenant; AuthMethod = 'DeviceCode' }

            $Probe.Caught | Should -BeNullOrEmpty
            $Probe.Latched | Should -BeFalse
            (Get-A119Info).AccountId | Should -BeExactly $script:A119OidB
            Should -Invoke -ModuleName $script:moduleName Connect-MgGraph -Times 2 -Exactly
        }

        It 'does not refuse Connect-OER (-ReclaimGraphSession) naming the tenant by the other label, answered by another account: the session becomes that account''s' {
            Start-A119Session -Label 'organizations'
            $Before = Get-A119Info
            $script:A119GraphOid = $script:A119OidB

            $Probe = Invoke-A119Probe @{ TenantId = $script:A119Tenant; ReclaimGraphSession = $true }

            $Probe.Caught | Should -BeNullOrEmpty
            $Probe.Latched | Should -BeFalse
            $Probe.Marker | Should -BeFalse
            $After = Get-A119Info
            $After.AccountId | Should -BeExactly $script:A119OidB
            $After.Oid | Should -BeExactly $script:A119OidB
            ($After.Identity -eq $Before.Identity) | Should -BeFalse -Because 'an explicit sign-in as another account moves the identity'
            Should -Invoke -ModuleName $script:moduleName Connect-MgGraph -Times 2 -Exactly
        }

        It 'still refuses a renewal of the same label answered by another account when the token''s tenant is not a tenant ID' {
            $script:A119GrantedTenant = 'tenant-reported-as-a-name'
            Start-A119Session
            Set-A119Expiry -GraphMinutes 2
            $script:A119Before = Get-A119Info
            $script:A119GraphOid = $script:A119OidB

            $Probe = Invoke-A119Probe @{}

            $Probe.Caught.FullyQualifiedErrorId | Should -BeExactly 'SignInSuperseded,Initialize-OERAuth'
            $Probe.Latched | Should -BeTrue
            Assert-A119SessionHeld -Label $script:A119Tenant
            Should -Invoke -ModuleName $script:moduleName Connect-MgGraph -Times 1 -Exactly
        }

        It 'does not compare a token whose tenant is not a tenant ID (known limit): the other account is accepted' {
            $script:A119GrantedTenant = 'tenant-reported-as-a-name'
            Start-A119Session -Label 'organizations'
            $script:A119GraphOid = $script:A119OidB

            $Probe = Invoke-A119Probe @{ TenantId = $script:A119Tenant }

            $Probe.Caught | Should -BeNullOrEmpty
            $Probe.Latched | Should -BeFalse
            (Get-A119Info).AccountId | Should -BeExactly $script:A119OidB
            Should -Invoke -ModuleName $script:moduleName Connect-MgGraph -Times 2 -Exactly
        }
    }

    Context 'a normal run is not refused' {
        It 'renews as the same account without a refusal, keeps the account and the identity, and carries the ARM token (<Method>)' -ForEach @(
            @{ Method = 'Interactive' }
            @{ Method = 'DeviceCode' }
        ) {
            Start-A119Session -Method $Method -Arm
            $Before = Get-A119Info
            Set-A119Expiry -GraphMinutes 2

            $Probe = Invoke-A119Probe @{}

            $Probe.Caught | Should -BeNullOrEmpty
            $Probe.Latched | Should -BeFalse
            $Probe.Remembers | Should -BeTrue
            $After = Get-A119Info
            $After.HasChangedKey | Should -BeFalse
            $After.AccountId | Should -BeExactly $script:A119OidA
            $After.HasArm | Should -BeTrue -Because 'the same account keeps its ARM token across a renewal'
            $After.Identity | Should -BeExactly $Before.Identity
            Should -Invoke -ModuleName $script:moduleName Connect-MgGraph -Times 2 -Exactly
        }

        It 'does not refuse a renewal whose new token carries no usable oid (<Case>): the session keeps account A, its oid and its identity' -ForEach @(
            @{ Case = 'no oid'; NewOid = '' }
            @{ Case = 'an oid that is not a GUID'; NewOid = 'not-a-guid-NOT-AN-OID' }
        ) {
            Start-A119Session -Method DeviceCode
            $Before = Get-A119Info
            Set-A119Expiry -GraphMinutes 2
            $script:A119GraphOid = $NewOid

            $Probe = Invoke-A119Probe @{}

            $Probe.Caught | Should -BeNullOrEmpty
            $Probe.Latched | Should -BeFalse
            $After = Get-A119Info
            $After.HasChangedKey | Should -BeFalse
            $After.Oid | Should -BeExactly $script:A119OidA -Because 'a renewal never replaces the known oid with a token that carries none'
            $After.AccountId | Should -BeExactly $script:A119OidA -Because 'the account is carried over a renewal'
            $After.Identity | Should -BeExactly $Before.Identity
            Should -Invoke -ModuleName $script:moduleName Connect-MgGraph -Times 2 -Exactly
        }

        It 'compares the next renewal with the known account after a renewal without an oid: another account is still refused' {
            Start-A119Session -Method DeviceCode
            Set-A119Expiry -GraphMinutes 2
            $script:A119GraphOid = ''
            $First = Invoke-A119Probe @{}
            $First.Caught | Should -BeNullOrEmpty
            (Get-A119Info).Oid | Should -BeExactly $script:A119OidA
            Set-A119Expiry -GraphMinutes 2
            $script:A119Before = Get-A119Info
            $script:A119GraphOid = $script:A119OidB

            $Probe = Invoke-A119Probe @{}

            $Probe.Caught.FullyQualifiedErrorId | Should -BeExactly 'SignInSuperseded,Initialize-OERAuth'
            $Probe.Latched | Should -BeTrue
            $After = Get-A119Info
            $After.Oid | Should -BeExactly $script:A119OidA
            $After.AccountId | Should -BeExactly $script:A119OidA
            $After.Identity | Should -BeExactly $script:A119Before.Identity
            # The first sign-in and the renewal without an oid connected; the refused renewal did not.
            Should -Invoke -ModuleName $script:moduleName Connect-MgGraph -Times 2 -Exactly
        }

        It 'records no oid for a new session whose token carries none (a method switch is not a renewal)' {
            Start-A119Session -Method Interactive
            (Get-A119Info).Oid | Should -BeExactly $script:A119OidA
            $script:A119GraphOid = ''

            $Probe = Invoke-A119Probe @{ TenantId = $script:A119Tenant; AuthMethod = 'DeviceCode' }

            $Probe.Caught | Should -BeNullOrEmpty
            $After = Get-A119Info
            $After.Oid | Should -BeNullOrEmpty -Because 'a new session records its own token''s oid, none included'
            $After.AccountId | Should -BeNullOrEmpty
        }

        It 'does not refuse a renewal of a session whose first token carried no oid, and carries the empty account' {
            Start-A119Session -Method DeviceCode -GraphOid ''
            $Before = Get-A119Info
            $Before.AccountId | Should -BeNullOrEmpty
            Set-A119Expiry -GraphMinutes 2
            $script:A119GraphOid = $script:A119OidB

            $Probe = Invoke-A119Probe @{}

            $Probe.Caught | Should -BeNullOrEmpty
            $Probe.Latched | Should -BeFalse
            $After = Get-A119Info
            $After.HasChangedKey | Should -BeFalse
            $After.Oid | Should -BeExactly $script:A119OidB
            $After.AccountId | Should -BeNullOrEmpty -Because 'a session that had no account is not given one by a renewal'
            $After.Identity | Should -BeExactly $Before.Identity
        }

        It 'lets Connect-OER (-ReclaimGraphSession) sign in as another account: the identity moves and nothing is refused' {
            Start-A119Session -Method DeviceCode
            $Before = Get-A119Info
            Set-A119Expiry -GraphMinutes 2
            $script:A119GraphOid = $script:A119OidB

            $Probe = Invoke-A119Probe @{ TenantId = $script:A119Tenant; AuthMethod = 'DeviceCode'; ReclaimGraphSession = $true }

            $Probe.Caught | Should -BeNullOrEmpty
            $Probe.Latched | Should -BeFalse
            $Probe.Marker | Should -BeFalse
            $After = Get-A119Info
            $After.HasChangedKey | Should -BeFalse
            $After.AccountId | Should -BeExactly $script:A119OidB
            ($After.Identity -eq $Before.Identity) | Should -BeFalse -Because 'an explicit sign-in as another account moves the identity'
        }

        It 'treats a switch of method as a new sign-in, not a renewal: another account is not refused' {
            Start-A119Session -Method Interactive
            $script:A119GraphOid = $script:A119OidB

            $Probe = Invoke-A119Probe @{ TenantId = $script:A119Tenant; AuthMethod = 'DeviceCode' }

            $Probe.Caught | Should -BeNullOrEmpty
            $Probe.Latched | Should -BeFalse
            (Get-A119Info).AccountId | Should -BeExactly $script:A119OidB
            (Get-A119Info).HasChangedKey | Should -BeFalse
        }

        It 'sets the account of a first sign-in to the token''s oid when it is a GUID, else leaves it empty' {
            Start-A119Session -Method DeviceCode
            (Get-A119Info).AccountId | Should -BeExactly $script:A119OidA
            (Get-A119Info).HasChangedKey | Should -BeFalse

            InModuleScope $script:moduleName { $script:_OERAuthState = $null }
            Start-A119Session -Method DeviceCode -GraphOid ''
            (Get-A119Info).AccountId | Should -BeNullOrEmpty
            (Get-A119Info).HasChangedKey | Should -BeFalse

            # Get-OERTokenObjectId answers a GUID or nothing; a value that is not a GUID is never taken as the account.
            InModuleScope $script:moduleName { $script:_OERAuthState = $null }
            Start-A119Session -Method DeviceCode -GraphOid 'not-a-guid-NOT-AN-OID'
            (Get-A119Info).AccountId | Should -BeNullOrEmpty
        }

        It 'does not refuse a nested sign-in under an unchanged session, and leaves the outer command unsuperseded' {
            Start-A119Session -Method DeviceCode
            $Result = InModuleScope $script:moduleName -Parameters @{ T = $script:A119Tenant } {
                param($T)
                $Holder = @{ InnerCaught = $null }
                function Invoke-A119Inner {
                    [CmdletBinding()]
                    param()
                    try { Initialize-OERAuth } catch { $Holder.InnerCaught = $PSItem }
                }
                function Invoke-A119Outer {
                    [CmdletBinding()]
                    param()
                    Initialize-OERAuth -TenantId $T -AuthMethod DeviceCode
                    $script:_OERAuthState.GraphTokenExpiry = [DateTime]::UtcNow.AddMinutes(2)
                    Invoke-A119Inner
                    $Holder.Superseded = Get-OERSignInSupersession
                    $Holder.Latched = [bool](Get-OERSignInRefusal)
                }
                Invoke-A119Outer
                $Holder
            }
            $Result.InnerCaught | Should -BeNullOrEmpty
            $Result.Superseded | Should -BeNullOrEmpty
            $Result.Latched | Should -BeFalse
            # The nested sign-in renewed the token (a real request), as the same account.
            Should -Invoke -ModuleName $script:moduleName Get-AzToken -Times 2 -Exactly
        }
    }

    Context 'the Azure Resource Manager token of a renewal' {
        It 'refuses an ARM token of another account, caches nothing and leaves the state as it is' {
            Start-A119Session
            $Before = Get-A119Info
            $Before.HasArm | Should -BeFalse
            $script:A119ArmOid = $script:A119OidB

            $Probe = Invoke-A119Probe @{ IncludeARM = $true }

            $Probe.Caught.FullyQualifiedErrorId | Should -BeExactly 'SignInSuperseded,Initialize-OERAuth'
            $Probe.Caught.TargetObject | Should -BeExactly 'Invoke-A119Command'
            $Probe.Caught.Exception.Message | Should -BeLike "A renewal of the module's sign-in, or a sign-in of its tenant named another way, returned a token for another account than the one Invoke-A119Command began with,*"
            $Probe.Latched | Should -BeTrue
            $Probe.Marker | Should -BeTrue
            $After = Get-A119Info
            $After.HasArm | Should -BeFalse -Because 'a token of another account is never cached'
            $After.ArmTenant | Should -BeNullOrEmpty
            $After.AccountId | Should -BeExactly $script:A119OidA
            $After.Oid | Should -BeExactly $script:A119OidA
            $After.HasChangedKey | Should -BeFalse
            $After.Identity | Should -BeExactly $Before.Identity
            Should -Invoke -ModuleName $script:moduleName Get-AzToken -Times 1 -Exactly -ParameterFilter { [string]$Resource -like '*management*' }
            Should -Invoke -ModuleName $script:moduleName Connect-MgGraph -Times 1 -Exactly
        }

        It 'caches an ARM token of the same account' {
            Start-A119Session

            $Probe = Invoke-A119Probe @{ IncludeARM = $true }

            $Probe.Caught | Should -BeNullOrEmpty
            $Probe.Latched | Should -BeFalse
            (Get-A119Info).HasArm | Should -BeTrue
        }

        It 'caches an ARM token that carries no oid' {
            Start-A119Session
            $script:A119ArmOid = ''

            $Probe = Invoke-A119Probe @{ IncludeARM = $true }

            $Probe.Caught | Should -BeNullOrEmpty
            (Get-A119Info).HasArm | Should -BeTrue
        }

        It 'caches an ARM token of any account when the session''s own token carried no oid' {
            Start-A119Session -GraphOid ''
            $script:A119ArmOid = $script:A119OidB

            $Probe = Invoke-A119Probe @{ IncludeARM = $true }

            $Probe.Caught | Should -BeNullOrEmpty
            (Get-A119Info).HasArm | Should -BeTrue
        }

        It 'does not hold a first sign-in to the rule (known limit): Graph as one account and ARM as another are both cached' {
            $script:A119GraphOid = $script:A119OidA
            $script:A119ArmOid = $script:A119OidB

            $Probe = Invoke-A119Probe @{ TenantId = $script:A119Tenant; AuthMethod = 'DeviceCode'; IncludeARM = $true }

            $Probe.Caught | Should -BeNullOrEmpty
            (Get-A119Info).HasArm | Should -BeTrue
        }

        It 'does not hold Connect-OER (-ReclaimGraphSession) to the rule (known limit)' {
            Start-A119Session -Method DeviceCode
            $script:A119ArmOid = $script:A119OidB

            $Probe = Invoke-A119Probe @{ TenantId = $script:A119Tenant; AuthMethod = 'DeviceCode'; IncludeARM = $true; ReclaimGraphSession = $true }

            $Probe.Caught | Should -BeNullOrEmpty
            $Probe.Latched | Should -BeFalse
            (Get-A119Info).HasArm | Should -BeTrue
        }
    }

    Context 'a public command in a script with no try above it' {
        BeforeAll {
            . "$PSScriptRoot/../TestHelpers/OERConfirmHost.ps1"
            # The real Initialize-OERAuth and the real Get-OERGroup run in a runspace. An outer command signs
            # in as account A (a real success), the Graph token is moved near its expiry, the oid the next
            # token carries is set to account B (or left as A), and Get-OERGroup, which signs in again without
            # -TenantId, is called with no try anywhere above it. Every token, connection and request the
            # module could make is replaced by a function that logs a line. -Steps then run further commands
            # at the top level of the script (each moves the Graph token near its expiry, sets the oid the
            # next token carries and runs its call, with the log cleared first); the output carries each
            # step's error ids as ERR<n>: and its log lines as LOG<n>: (step 0 is the outer command).
            function script:New-AccountNoTryScenario {
                param([string]$Log, [string]$NextOid, [hashtable[]]$Steps = @(),
                    [string]$OuterSignIn = "Initialize-OERAuth -TenantId '66666666-6666-6666-6666-666666666666' -AuthMethod 'DeviceCode'")
                $Head = @'
Import-Module Omnicit.EntraRBAC -Force -ErrorAction Stop
& (Get-Module Omnicit.EntraRBAC) {
    $script:_OERAuthState = $null
    $script:_OERSessionUncertain = $null
    $script:_OERInteractiveCredential = $null
    $script:A119Oid = '88888888-8888-8888-8888-888888888888'
    Set-Item -Path function:script:Test-OERHostNonInteractive -Value { $false }
    Set-Item -Path function:script:Get-AzToken -Value {
        param($ClientId, $Resource, $Tenant, $Scope, $Interactive, $DeviceCode, $Force, $CredentialPrecedence, $ErrorAction, $WarningAction)
        [System.IO.File]::AppendAllText('#LOG#', "TOKEN $Resource`n")
        [pscustomobject]@{
            Token     = 'NOT-A-REAL-TOKEN-a119'
            ExpiresOn = [DateTimeOffset]::UtcNow.AddHours(1)
            Identity  = 'admin@contoso.com'
            TenantId  = '66666666-6666-6666-6666-666666666666'
        }
    }
    Set-Item -Path function:script:Get-OERTokenObjectId -Value { $script:A119Oid }
    Set-Item -Path function:script:Connect-MgGraph -Value { [System.IO.File]::AppendAllText('#LOG#', "CONNECT`n") }
    Set-Item -Path function:script:Get-MgContext -Value {
        [pscustomobject]@{ AuthType = 'UserProvidedAccessToken'; TokenCredentialType = 'UserProvidedAccessToken'
            ClientId = '11111111-1111-1111-1111-111111111111'; TenantId = '66666666-6666-6666-6666-666666666666'
            Account = 'admin@contoso.com'; AppName = 'oer-test-app'; Environment = 'Global'; Scopes = @('Group.ReadWrite.All') }
    }
    Set-Item -Path function:script:Invoke-MgGraphRequest -Value { [System.IO.File]::AppendAllText('#LOG#', "GRAPH`n") }
    Set-Item -Path function:script:Invoke-WebRequest -Value { [System.IO.File]::AppendAllText('#LOG#', "ARM`n") }
    Set-Item -Path function:script:Resolve-OERTenantDomain -Value { [System.IO.File]::AppendAllText('#LOG#', "LOOKUP`n"); '66666666-6666-6666-6666-666666666666' }
    function script:Invoke-OuterCommand {
        [CmdletBinding()]
        param()
        #OUTERSIGNIN#
        [System.IO.File]::WriteAllText('#LOG#', '')
        $script:A119Oid = '#NEXTOID#'
        $script:_OERAuthState.GraphTokenExpiry = [DateTime]::UtcNow.AddMinutes(2)
        Get-OERGroup -Group 'g1' -ErrorAction Continue
    }
}
$All = @(& (Get-Module Omnicit.EntraRBAC) { Invoke-OuterCommand } 2>&1)
foreach ($E in $All) { "ERR:$($E.FullyQualifiedErrorId)" }
foreach ($L in [System.IO.File]::ReadAllLines('#LOG#')) { "LOG0:$L" }

'@
                $StepText = ''
                $Number = 0
                foreach ($Step in $Steps) {
                    $Number++
                    $StepText += @'
& (Get-Module Omnicit.EntraRBAC) { $script:A119Oid = '#OID#'; $script:_OERAuthState.GraphTokenExpiry = [DateTime]::UtcNow.AddMinutes(2) }
[System.IO.File]::WriteAllText('#LOG#', '')
$All = @(& (Get-Module Omnicit.EntraRBAC) { #CALL# } 2>&1)
foreach ($E in $All) { "ERR#N#:$($E.FullyQualifiedErrorId)" }
foreach ($L in [System.IO.File]::ReadAllLines('#LOG#')) { "LOG#N#:$L" }

'@.Replace('#OID#', [string]$Step.Oid).Replace('#CALL#', [string]$Step.Call).Replace('#N#', [string]$Number)
                }
                $Tail = @'
# The stubs of a transport name above shadow the tripwire's replacements in this runspace's copy of the
# module, and the tripwire check after the scenario reads that scope: removed here (the nearest definition,
# which is the stub), so the check sees the replacements again.
& (Get-Module Omnicit.EntraRBAC) {
    foreach ($Name in 'Get-AzToken', 'Connect-MgGraph', 'Invoke-MgGraphRequest', 'Invoke-WebRequest') {
        Remove-Item -Path ('function:' + $Name) -ErrorAction SilentlyContinue
    }
}
'END'
'@
                [scriptblock]::Create(($Head + $StepText + $Tail).Replace('#OUTERSIGNIN#', $OuterSignIn).Replace('#LOG#', $Log.Replace("'", "''")).Replace('#NEXTOID#', $NextOid))
            }

            function script:Get-AccountScenarioLines {
                param($Run, [string]$Prefix)
                @($Run.Output | Where-Object { $_ -like "${Prefix}:*" } | ForEach-Object { $_.Substring($Prefix.Length + 1) })
            }
        }

        It 'raises SignInSuperseded for the renewal answered by another account, refuses the command''s own request, sends no Graph or ARM request and never connects' {
            $Log = Join-Path $TestDrive ('{0}.log' -f [guid]::NewGuid())
            $Run = Invoke-OERWithConfirmAnswer -Answer '&Yes' -Script (New-AccountNoTryScenario -Log $Log -NextOid '99999999-9999-9999-9999-999999999999')

            $Run.Output[-1] | Should -BeExactly 'END'
            @($Run.Output | Where-Object { $_ -like 'ERR:*' }) | Should -Be @(
                'ERR:SignInSuperseded,Initialize-OERAuth'
                'ERR:SignInRefused,Get-OERGroup'
            )
            # Not vacuous: the renewal ran its token request, and the token was refused before Connect-MgGraph.
            $Lines = @(Get-Content -LiteralPath $Log)
            @($Lines | Where-Object { $_ -like 'TOKEN*' }).Count | Should -Be 1
            @($Lines | Where-Object { $_ -eq 'CONNECT' }).Count | Should -Be 0
            @($Lines | Where-Object { $_ -eq 'GRAPH' -or $_ -eq 'ARM' }).Count | Should -Be 0
            $Run.Warnings | Should -BeNullOrEmpty
        }

        It 'is not raised for a renewal answered by the same account: the command sends its request' {
            $Log = Join-Path $TestDrive ('{0}.log' -f [guid]::NewGuid())
            $Run = Invoke-OERWithConfirmAnswer -Answer '&Yes' -Script (New-AccountNoTryScenario -Log $Log -NextOid '88888888-8888-8888-8888-888888888888')

            $Run.Output[-1] | Should -BeExactly 'END'
            @($Run.Output | Where-Object { $_ -like 'ERR:SignIn*' }) | Should -BeNullOrEmpty
            $Lines = @(Get-Content -LiteralPath $Log)
            @($Lines | Where-Object { $_ -like 'TOKEN*' }).Count | Should -Be 1
            @($Lines | Where-Object { $_ -eq 'CONNECT' }).Count | Should -Be 1
            @($Lines | Where-Object { $_ -eq 'GRAPH' }).Count | Should -BeGreaterThan 0
        }

        It 'refuses a top-level command that names the tenant while the other account answers again, sending no request and connecting nothing' {
            $Log = Join-Path $TestDrive ('{0}.log' -f [guid]::NewGuid())
            $Step = @{ Oid = '99999999-9999-9999-9999-999999999999'; Call = "Get-OERGroup -Group 'g1' -TenantId '66666666-6666-6666-6666-666666666666' -ErrorAction Continue" }
            $Run = Invoke-OERWithConfirmAnswer -Answer '&Yes' -Script (New-AccountNoTryScenario -Log $Log -NextOid '99999999-9999-9999-9999-999999999999' -Steps @($Step))

            $Run.Output[-1] | Should -BeExactly 'END'
            Get-AccountScenarioLines -Run $Run -Prefix 'ERR1' | Should -Be @(
                'SignInSuperseded,Initialize-OERAuth'
                'SignInRefused,Get-OERGroup'
            ) -Because "the output was:`n$($Run.Output -join "`n")"
            $Lines = Get-AccountScenarioLines -Run $Run -Prefix 'LOG1'
            # Not vacuous: the second renewal ran its token request.
            @($Lines | Where-Object { $_ -like 'TOKEN*' }).Count | Should -Be 1
            @($Lines | Where-Object { $_ -eq 'CONNECT' -or $_ -eq 'GRAPH' -or $_ -eq 'ARM' }).Count | Should -Be 0
            $Run.Warnings | Should -BeNullOrEmpty
        }

        It 'lets a top-level command that names the tenant run as the session''s own account once that account answers' {
            $Log = Join-Path $TestDrive ('{0}.log' -f [guid]::NewGuid())
            $Step = @{ Oid = '88888888-8888-8888-8888-888888888888'; Call = "Get-OERGroup -Group 'g1' -TenantId '66666666-6666-6666-6666-666666666666' -ErrorAction Continue" }
            $Run = Invoke-OERWithConfirmAnswer -Answer '&Yes' -Script (New-AccountNoTryScenario -Log $Log -NextOid '99999999-9999-9999-9999-999999999999' -Steps @($Step))

            $Run.Output[-1] | Should -BeExactly 'END'
            # No sign-in error (the stubbed Graph answers nothing, so the group itself is not found).
            @(Get-AccountScenarioLines -Run $Run -Prefix 'ERR1' | Where-Object { $_ -like 'SignIn*' }) | Should -BeNullOrEmpty -Because "the output was:`n$($Run.Output -join "`n")"
            $Lines = Get-AccountScenarioLines -Run $Run -Prefix 'LOG1'
            @($Lines | Where-Object { $_ -like 'TOKEN*' }).Count | Should -Be 1
            @($Lines | Where-Object { $_ -eq 'CONNECT' }).Count | Should -Be 1
            @($Lines | Where-Object { $_ -eq 'GRAPH' }).Count | Should -BeGreaterThan 0
        }

        It 'refuses a bare top-level command, which names no tenant, since the session is uncertain, requesting no token' {
            $Log = Join-Path $TestDrive ('{0}.log' -f [guid]::NewGuid())
            $Step = @{ Oid = '88888888-8888-8888-8888-888888888888'; Call = "Get-OERGroup -Group 'g1' -ErrorAction Continue" }
            $Run = Invoke-OERWithConfirmAnswer -Answer '&Yes' -Script (New-AccountNoTryScenario -Log $Log -NextOid '99999999-9999-9999-9999-999999999999' -Steps @($Step))

            $Run.Output[-1] | Should -BeExactly 'END'
            Get-AccountScenarioLines -Run $Run -Prefix 'ERR1' | Should -Be @(
                'SignInRefused,Initialize-OERAuth'
                'SignInRefused,Get-OERGroup'
            ) -Because "the output was:`n$($Run.Output -join "`n")"
            # Not vacuous: the first renewal (step 0) did request a token; this command requested none.
            @(Get-AccountScenarioLines -Run $Run -Prefix 'LOG0' | Where-Object { $_ -like 'TOKEN*' }).Count | Should -Be 1
            Get-AccountScenarioLines -Run $Run -Prefix 'LOG1' | Should -BeNullOrEmpty
        }

        It 'compares the next renewal with the known account after a renewal that carried no oid: the request is sent, then another account is refused and nothing is sent' {
            $Log = Join-Path $TestDrive ('{0}.log' -f [guid]::NewGuid())
            $Step = @{ Oid = '99999999-9999-9999-9999-999999999999'; Call = "Get-OERGroup -Group 'g1' -ErrorAction Continue" }
            $Run = Invoke-OERWithConfirmAnswer -Answer '&Yes' -Script (New-AccountNoTryScenario -Log $Log -NextOid '' -Steps @($Step))

            $Run.Output[-1] | Should -BeExactly 'END'
            # The renewal without an oid is not refused and its request is sent.
            @($Run.Output | Where-Object { $_ -like 'ERR:SignIn*' }) | Should -BeNullOrEmpty -Because "the output was:`n$($Run.Output -join "`n")"
            $Lines0 = Get-AccountScenarioLines -Run $Run -Prefix 'LOG0'
            @($Lines0 | Where-Object { $_ -like 'TOKEN*' }).Count | Should -Be 1
            @($Lines0 | Where-Object { $_ -eq 'CONNECT' }).Count | Should -Be 1
            @($Lines0 | Where-Object { $_ -eq 'GRAPH' }).Count | Should -BeGreaterThan 0
            # The next renewal, answered by B, is refused against the known account A: a token request, nothing else.
            Get-AccountScenarioLines -Run $Run -Prefix 'ERR1' | Should -Be @(
                'SignInSuperseded,Initialize-OERAuth'
                'SignInRefused,Get-OERGroup'
            ) -Because "the output was:`n$($Run.Output -join "`n")"
            $Lines1 = Get-AccountScenarioLines -Run $Run -Prefix 'LOG1'
            @($Lines1 | Where-Object { $_ -like 'TOKEN*' }).Count | Should -Be 1
            @($Lines1 | Where-Object { $_ -eq 'CONNECT' -or $_ -eq 'GRAPH' -or $_ -eq 'ARM' }).Count | Should -Be 0
        }

        # A session from a sign-in that named no tenant (label 'organizations'): the outer command signs in
        # with no -TenantId, its own renewal is answered by B and refused, and a top-level command then
        # names the tenant ID (a different label, so no cached return and no renewal as such).
        It 'refuses a top-level command that names the tenant ID after a session that named none, when the other account answers: no connection and no request' {
            $Log = Join-Path $TestDrive ('{0}.log' -f [guid]::NewGuid())
            $Step = @{ Oid = '99999999-9999-9999-9999-999999999999'; Call = "Get-OERGroup -Group 'g1' -TenantId '66666666-6666-6666-6666-666666666666' -ErrorAction Continue" }
            $Run = Invoke-OERWithConfirmAnswer -Answer '&Yes' -Script (New-AccountNoTryScenario -Log $Log -OuterSignIn 'Initialize-OERAuth' -NextOid '99999999-9999-9999-9999-999999999999' -Steps @($Step))

            $Run.Output[-1] | Should -BeExactly 'END'
            # The outer command's own renewal (no tenant named) was refused too.
            @(Get-AccountScenarioLines -Run $Run -Prefix 'ERR' | Where-Object { $_ -like 'SignInSuperseded*' }).Count | Should -Be 1 -Because "the output was:`n$($Run.Output -join "`n")"
            Get-AccountScenarioLines -Run $Run -Prefix 'ERR1' | Should -Be @(
                'SignInSuperseded,Initialize-OERAuth'
                'SignInRefused,Get-OERGroup'
            ) -Because "the output was:`n$($Run.Output -join "`n")"
            $Lines = Get-AccountScenarioLines -Run $Run -Prefix 'LOG1'
            # Not vacuous: the command requested a token (the label differs, so the cache was not used).
            @($Lines | Where-Object { $_ -like 'TOKEN*' }).Count | Should -BeGreaterThan 0
            @($Lines | Where-Object { $_ -eq 'CONNECT' -or $_ -eq 'GRAPH' -or $_ -eq 'ARM' }).Count | Should -Be 0
            $Run.Warnings | Should -BeNullOrEmpty
        }

        It 'lets a top-level command that names the tenant ID after a session that named none run once the session''s own account answers' {
            $Log = Join-Path $TestDrive ('{0}.log' -f [guid]::NewGuid())
            $Step = @{ Oid = '88888888-8888-8888-8888-888888888888'; Call = "Get-OERGroup -Group 'g1' -TenantId '66666666-6666-6666-6666-666666666666' -ErrorAction Continue" }
            $Run = Invoke-OERWithConfirmAnswer -Answer '&Yes' -Script (New-AccountNoTryScenario -Log $Log -OuterSignIn 'Initialize-OERAuth' -NextOid '99999999-9999-9999-9999-999999999999' -Steps @($Step))

            $Run.Output[-1] | Should -BeExactly 'END'
            @(Get-AccountScenarioLines -Run $Run -Prefix 'ERR1' | Where-Object { $_ -like 'SignIn*' }) | Should -BeNullOrEmpty -Because "the output was:`n$($Run.Output -join "`n")"
            $Lines = Get-AccountScenarioLines -Run $Run -Prefix 'LOG1'
            @($Lines | Where-Object { $_ -like 'TOKEN*' }).Count | Should -BeGreaterThan 0
            @($Lines | Where-Object { $_ -eq 'CONNECT' }).Count | Should -Be 1
            @($Lines | Where-Object { $_ -eq 'GRAPH' }).Count | Should -BeGreaterThan 0
        }
    }
}
