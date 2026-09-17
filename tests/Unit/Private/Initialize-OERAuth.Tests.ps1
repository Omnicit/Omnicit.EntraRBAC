BeforeAll {
    $script:moduleName = 'Omnicit.EntraRBAC'
    Get-Module $script:moduleName | Remove-Module -Force -ErrorAction SilentlyContinue
    Import-Module $script:moduleName -Force -ErrorAction Stop
}

Describe 'Initialize-OERAuth' {
    BeforeEach {
        # $script:_OERLastAuthorityHost is deliberately NOT cleared by Disconnect-OER, so nothing in
        # the module ever resets it. Reset it here, or a sovereign test leaks its authority into the
        # next test, which would then silently gain the -Force the public path must never carry.
        InModuleScope $script:moduleName {
            $script:_OERAuthState = $null
            $script:_OERLastAuthorityHost = $null
            $script:_OERLastTokenRequest = $null
            $script:_OERLastIssuedSession = $null
        }
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
            $script:_OERLastAuthorityHost = $null
            $script:_OERLastTokenRequest = $null
            $script:_OERLastIssuedSession = $null
        }
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

Describe 'Initialize-OERAuth error hygiene' {
    BeforeEach {
        # $script:_OERLastAuthorityHost is deliberately NOT cleared by Disconnect-OER, so nothing in
        # the module ever resets it. Reset it here, or a sovereign test leaks its authority into the
        # next test, which would then silently gain the -Force the public path must never carry.
        InModuleScope $script:moduleName {
            $script:_OERAuthState = $null
            $script:_OERLastAuthorityHost = $null
            $script:_OERLastTokenRequest = $null
            $script:_OERLastIssuedSession = $null
        }
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
            $script:_OERLastAuthorityHost = $null
            $script:_OERLastTokenRequest = $null
            $script:_OERLastIssuedSession = $null
        }
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
            $script:_OERLastAuthorityHost = $null
            $script:_OERLastTokenRequest = $null
            $script:_OERLastIssuedSession = $null
        }
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

        InModuleScope $script:moduleName {
            Initialize-OERAuth -TenantId 'contoso' -AuthMethod 'Interactive' -IncludeARM
            $script:_OERAuthState.Environment    | Should -Be 'Global'
            $script:_OERAuthState.ArmResourceUrl | Should -Be 'https://management.azure.com/'
        }

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
            $script:_OERLastAuthorityHost = $null
            $script:_OERLastTokenRequest = $null
            $script:_OERLastIssuedSession = $null
        }
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
            $script:_OERLastAuthorityHost = $null
            $script:_OERLastTokenRequest = $null
            $script:_OERLastIssuedSession = $null
        }
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

            # An ARM cmdlet: Graph is cached, so ONLY the ARM branch runs.
            Initialize-OERAuth -IncludeARM
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
            $script:_OERLastAuthorityHost = $null
            $script:_OERLastTokenRequest = $null
            $script:_OERLastIssuedSession = $null
        }
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
            $script:_OERLastAuthorityHost = $null
            $script:_OERLastTokenRequest = $null
            $script:_OERLastIssuedSession = $null
        }
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
            $script:_OERLastAuthorityHost = $null
            $script:_OERLastTokenRequest = $null
            $script:_OERLastIssuedSession = $null
        }
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
        Mock -ModuleName $script:moduleName Get-AzToken {
            Write-Warning 'some unrelated AzAuth warning'
            [pscustomobject]@{ Token = 'fake'; ExpiresOn = [DateTimeOffset]::UtcNow.AddHours(1); Identity = 'admin@contoso.com'; TenantId = 'contoso' }
        }

        $Captured = InModuleScope $script:moduleName {
            $InfoVar = $null
            $WarnVar = $null
            Initialize-OERAuth -TenantId 'contoso' -AuthMethod 'Interactive' `
                -InformationVariable InfoVar -WarningVariable WarnVar `
                -WarningAction SilentlyContinue 6>$null
            [pscustomobject]@{
                Information = @($InfoVar | ForEach-Object { [string]$_.MessageData })
                Warning     = @($WarnVar | ForEach-Object { [string]$_.Message })
                Account     = $script:_OERAuthState.Account
            }
        }

        ($Captured.Warning -join "`n") | Should -Match 'some unrelated AzAuth warning'
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
                Write-Warning 'To sign in, use a web browser to open the page https://microsoft.com/devicelogin and enter the code ARMCODE99 to authenticate.'
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

Describe 'Initialize-OERAuth granted-tenant guard' {
    BeforeEach {
        InModuleScope $script:moduleName {
            $script:_OERAuthState = $null
            $script:_OERLastAuthorityHost = $null
            $script:_OERLastTokenRequest = $null
            $script:_OERLastIssuedSession = $null
        }
    }

    # The defect this guard closes, in one sentence: the module stamped the state with the tenant the
    # caller ASKED for and never looked at the tenant the token was GRANTED for, so a session could be
    # labelled with a tenant its token does not belong to. A live device-code run proved it reachable
    # against a tenant that does not exist at all.
    #
    # The first four Its are a mutation set, not four independent checks. The mismatch It fails if the
    # comparison is forced always-false (or deleted outright); the match, domain and 'organizations'
    # Its each fail if it is forced always-true. Neither mutation can pass the whole block.
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

    It 'never fires when the requested tenant is a verified domain, and still records the granted tenant' {
        # This is the case that would break most real sign-ins if the comparison were unconditional:
        # a domain can never equal the GUID a token carries, so an always-true comparison rejects
        # every ordinary Connect-OER. The mismatch is not detectable from the token alone here, so
        # nothing is inferred -- the granted value is recorded and left to speak for itself.
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
            Initialize-OERAuth -TenantId 'contoso.onmicrosoft.com' -AuthMethod 'Interactive'

            $script:_OERAuthState.TenantId | Should -Be 'contoso.onmicrosoft.com'
            $script:_OERAuthState.TokenTenantId | Should -Be '22222222-2222-2222-2222-222222222222'
        }
        Should -Invoke -ModuleName $script:moduleName Connect-MgGraph -Times 1 -Exactly
    }

    It 'never fires for the tenant-agnostic organizations default' {
        # 'organizations' is excluded structurally rather than by a term of its own: it is not a
        # GUID, so Test-OERGuid already refuses it. A dedicated term would be one no input could
        # falsify, and an unfalsifiable term cannot be mutation-proved.
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

        InModuleScope $script:moduleName {
            Initialize-OERAuth -TenantId '11111111-1111-1111-1111-111111111111' -AuthMethod 'Interactive' -IncludeARM
            $script:_OERAuthState.ArmTokenTenantId | Should -Be '11111111-1111-1111-1111-111111111111'

            # A different tenant, named as a domain so the guard has nothing comparable to compare.
            # The mock issues the same GUID tenant again, so the tenant-switch post-call warning fires by design; it is asserted in its own Describe.
            Initialize-OERAuth -TenantId 'other.onmicrosoft.com' -AuthMethod 'Interactive' -WarningAction SilentlyContinue
            $script:_OERAuthState.ArmToken | Should -BeNullOrEmpty
            $script:_OERAuthState.ArmTokenTenantId | Should -BeNullOrEmpty
        }
    }
}

# -------------------------------------------------------------------------------------------------
# Tenant-switch warnings (F12).
#
# AzAuth keeps ONE credential per PowerShell process, and a same-session tenant switch can fail to
# reach the new tenant without any error that says so. Two warnings cover it. The pre-call warning
# (the P Its) PREDICTS it for a client secret sign-in, from the module's own record of the token
# request that last made AzAuth build its credential. The post-call warning (the Q Its) OBSERVES it for
# any credential type, from the tenant the new Graph token was issued by. Read together, the Its are a
# mutation set over every term of both predicates.
#
# The P Its name tenants by plain labels and their mocked tokens carry no tenant, so the post-call
# warning has nothing to compare and cannot fire by accident. The Q Its use DeviceCode, for which the
# pre-call warning never fires.
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
        # None of these trackers is ever cleared by the module -- not even by Disconnect-OER -- so reset
        # them all here, or one It's recorded credential build or established session leaks into the next.
        InModuleScope $script:moduleName {
            $script:_OERAuthState = $null
            $script:_OERLastAuthorityHost = $null
            $script:_OERLastTokenRequest = $null
            $script:_OERLastIssuedSession = $null
        }
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
            # Both mocked: Disconnect-AzAccount resolves for real in the test environment and would
            # clear the operator's own Az context.
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
                try {
                    Initialize-OERAuth -TenantId 'tenant-b.example.com' -AuthMethod 'ClientSecret' -ClientId 'app-client-1' `
                        -ClientSecret $Secret -Environment $Environment -WarningAction Stop
                }
                catch {
                    $StopCaught = $PSItem
                }

                $StopCaught | Should -Not -BeNullOrEmpty -Because 'a -WarningAction Stop caller has to be stopped at the warning'
                $StopCaught.Exception | Should -BeOfType [System.Management.Automation.ActionPreferenceStopException]
                $StopCaught.Exception.Message | Should -Match ([regex]::Escape(
                    "names tenant 'tenant-b.example.com', but the credential AzAuth holds for that application in this PowerShell session was built for tenant 'tenant-a.example.com'"))

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

    Context 'after the Graph token: a sign-in issued by the tenant the previous session was issued by' {
        It 'warns exactly once when a device-code sign-in naming another domain is issued the previous session''s tenant (Q1)' {
            Mock -ModuleName $script:moduleName Get-AzToken {
                param($ClientId, $ClientSecret, $Resource, $Tenant, $ErrorAction, $Interactive,
                      $DeviceCode, $ManagedIdentity, $ClientCertificate, $ClientCertificatePath,
                      $Scope, $Force, $Claim)
                # Whatever tenant is named, the signed-in account's own tenant answers.
                [pscustomobject]@{
                    Token     = 'fake-graph-token'
                    ExpiresOn = [DateTimeOffset]::UtcNow.AddHours(1)
                    Identity  = 'admin@contoso.com'
                    TenantId  = '11111111-1111-1111-1111-111111111111'
                }
            }

            InModuleScope $script:moduleName {
                $FirstWarnings = 'not-run'
                Initialize-OERAuth -TenantId 'tenant-a.example.com' -AuthMethod 'DeviceCode' `
                    -WarningVariable FirstWarnings -WarningAction SilentlyContinue
                $SwitchWarnings = 'not-run'
                Initialize-OERAuth -TenantId 'tenant-b.example.com' -AuthMethod 'DeviceCode' `
                    -WarningVariable SwitchWarnings -WarningAction SilentlyContinue

                # A warning, not a refusal: the sign-in completes, and the evidence field shows who answered.
                $script:_OERAuthState.TenantId      | Should -Be 'tenant-b.example.com'
                $script:_OERAuthState.TokenTenantId | Should -Be '11111111-1111-1111-1111-111111111111'
                @($FirstWarnings).Count  | Should -Be 0 -Because 'a first sign-in has no previous session to compare with'
                @($SwitchWarnings).Count | Should -Be 1

                $Message = $SwitchWarnings[0].Message
                $Message | Should -Match ([regex]::Escape("token for tenant 'tenant-b.example.com'"))
                $Message | Should -Match ([regex]::Escape("issued by tenant '11111111-1111-1111-1111-111111111111'"))
                $Message | Should -Match ([regex]::Escape("previous session, which named 'tenant-a.example.com'"))
                $Message | Should -Match ([regex]::Escape("If 'tenant-b.example.com' is a name of tenant '11111111-1111-1111-1111-111111111111', this is expected."))
                # Pinned word for word, so a change to the explanation an operator reads is a deliberate one.
                $Message | Should -BeExactly (
                    "The Microsoft Graph token for tenant 'tenant-b.example.com' was issued by tenant " +
                    "'11111111-1111-1111-1111-111111111111', the same tenant that issued the token for the " +
                    "previous session, which named 'tenant-a.example.com'. If 'tenant-b.example.com' is a " +
                    "name of tenant '11111111-1111-1111-1111-111111111111', this is expected. Otherwise this " +
                    "sign-in did not switch tenants, and every call in this session acts on " +
                    "'11111111-1111-1111-1111-111111111111' while reporting 'tenant-b.example.com' -- Azure " +
                    "Resource Manager calls, including the ones that write role assignments, as well as " +
                    "Microsoft Graph calls. AzAuth " +
                    "does not send the named tenant with a new device code sign-in or with a managed identity " +
                    "request, so those tokens normally come from the signed-in account's or the identity's " +
                    "own tenant, and a client secret sign-in for the same application needs Connect-OER " +
                    "-Force to move to another tenant. Name the tenant by its tenant ID (a GUID) and " +
                    "Omnicit.EntraRBAC refuses a token issued for any other tenant instead of warning.")
            }

            Should -Invoke -ModuleName $script:moduleName Connect-MgGraph -Exactly -Times 2
        }

        It 'stays silent when the new token is issued by a different tenant than the previous one (Q2)' {
            Mock -ModuleName $script:moduleName Get-AzToken {
                param($ClientId, $ClientSecret, $Resource, $Tenant, $ErrorAction, $Interactive,
                      $DeviceCode, $ManagedIdentity, $ClientCertificate, $ClientCertificatePath,
                      $Scope, $Force, $Claim)
                $Granted = if ($Tenant -eq 'tenant-b.example.com') {
                    '22222222-2222-2222-2222-222222222222'
                }
                else {
                    '11111111-1111-1111-1111-111111111111'
                }
                [pscustomobject]@{ Token = 'fake-graph-token'; ExpiresOn = [DateTimeOffset]::UtcNow.AddHours(1); Identity = 'admin@contoso.com'; TenantId = $Granted }
            }

            InModuleScope $script:moduleName {
                Initialize-OERAuth -TenantId 'tenant-a.example.com' -AuthMethod 'DeviceCode'
                $SwitchWarnings = 'not-run'
                Initialize-OERAuth -TenantId 'tenant-b.example.com' -AuthMethod 'DeviceCode' `
                    -WarningVariable SwitchWarnings -WarningAction SilentlyContinue

                $script:_OERAuthState.TenantId      | Should -Be 'tenant-b.example.com'
                $script:_OERAuthState.TokenTenantId | Should -Be '22222222-2222-2222-2222-222222222222'
                @($SwitchWarnings).Count | Should -Be 0
            }

            Should -Invoke -ModuleName $script:moduleName Get-AzToken -Exactly -Times 2
        }

        # The TenantMismatch guard already verifies a GUID request, and a domain-to-GUID respelling of
        # the same tenant is a correct sign-in, not a failed switch.
        It 'stays silent when the new request names, as a GUID, the tenant the previous session was issued (Q3)' {
            Mock -ModuleName $script:moduleName Get-AzToken {
                param($ClientId, $ClientSecret, $Resource, $Tenant, $ErrorAction, $Interactive,
                      $DeviceCode, $ManagedIdentity, $ClientCertificate, $ClientCertificatePath,
                      $Scope, $Force, $Claim)
                [pscustomobject]@{ Token = 'fake-graph-token'; ExpiresOn = [DateTimeOffset]::UtcNow.AddHours(1); Identity = 'admin@contoso.com'; TenantId = '11111111-1111-1111-1111-111111111111' }
            }

            InModuleScope $script:moduleName {
                Initialize-OERAuth -TenantId 'tenant-a.example.com' -AuthMethod 'DeviceCode'
                $SwitchWarnings = 'not-run'
                Initialize-OERAuth -TenantId '11111111-1111-1111-1111-111111111111' -AuthMethod 'DeviceCode' `
                    -WarningVariable SwitchWarnings -WarningAction SilentlyContinue

                $script:_OERAuthState.TenantId | Should -Be '11111111-1111-1111-1111-111111111111'
                @($SwitchWarnings).Count | Should -Be 0
            }

            Should -Invoke -ModuleName $script:moduleName Get-AzToken -Exactly -Times 2
        }

        It 'stays silent with no previous session (Q4)' {
            Mock -ModuleName $script:moduleName Get-AzToken {
                param($ClientId, $ClientSecret, $Resource, $Tenant, $ErrorAction, $Interactive,
                      $DeviceCode, $ManagedIdentity, $ClientCertificate, $ClientCertificatePath,
                      $Scope, $Force, $Claim)
                [pscustomobject]@{ Token = 'fake-graph-token'; ExpiresOn = [DateTimeOffset]::UtcNow.AddHours(1); Identity = 'admin@contoso.com'; TenantId = '11111111-1111-1111-1111-111111111111' }
            }

            InModuleScope $script:moduleName {
                # "No previous session" means the issued-session tracker is empty, not merely the state.
                $script:_OERLastIssuedSession | Should -BeNullOrEmpty
                $Warnings = 'not-run'
                Initialize-OERAuth -TenantId 'tenant-b.example.com' -AuthMethod 'DeviceCode' `
                    -WarningVariable Warnings -WarningAction SilentlyContinue

                $script:_OERAuthState.TenantId      | Should -Be 'tenant-b.example.com'
                $script:_OERAuthState.TokenTenantId | Should -Be '11111111-1111-1111-1111-111111111111'
                @($Warnings).Count | Should -Be 0
            }

            Should -Invoke -ModuleName $script:moduleName Get-AzToken -Exactly -Times 1
        }

        # The new token carries the SAME value as the previous session's TokenTenantId, so only the GUID
        # term on that previous value keeps these silent. An absent tenant on both tokens is exactly what
        # every older mock in this file returns, and an equal non-GUID is not evidence of a tenant at all.
        It 'stays silent when the previous session''s TokenTenantId is <Case> (Q5)' -ForEach @(
            @{ Case = 'absent'; Granted = $null }
            @{ Case = 'not a GUID'; Granted = 'contoso' }
        ) {
            $script:TenantSwitchGranted = $Granted
            Mock -ModuleName $script:moduleName Get-AzToken {
                param($ClientId, $ClientSecret, $Resource, $Tenant, $ErrorAction, $Interactive,
                      $DeviceCode, $ManagedIdentity, $ClientCertificate, $ClientCertificatePath,
                      $Scope, $Force, $Claim)
                [pscustomobject]@{ Token = 'fake-graph-token'; ExpiresOn = [DateTimeOffset]::UtcNow.AddHours(1); Identity = 'admin@contoso.com'; TenantId = $script:TenantSwitchGranted }
            }

            InModuleScope $script:moduleName -Parameters @{ Granted = $Granted } {
                param($Granted)
                Initialize-OERAuth -TenantId 'tenant-a.example.com' -AuthMethod 'DeviceCode'
                $script:_OERAuthState.TokenTenantId | Should -Be $Granted

                $SwitchWarnings = 'not-run'
                Initialize-OERAuth -TenantId 'tenant-b.example.com' -AuthMethod 'DeviceCode' `
                    -WarningVariable SwitchWarnings -WarningAction SilentlyContinue

                $script:_OERAuthState.TenantId | Should -Be 'tenant-b.example.com'
                @($SwitchWarnings).Count | Should -Be 0
            }

            Should -Invoke -ModuleName $script:moduleName Get-AzToken -Exactly -Times 2
        }

        It 'stays silent when the same tenant label re-acquires an expired token (Q6)' {
            Mock -ModuleName $script:moduleName Get-AzToken {
                param($ClientId, $ClientSecret, $Resource, $Tenant, $ErrorAction, $Interactive,
                      $DeviceCode, $ManagedIdentity, $ClientCertificate, $ClientCertificatePath,
                      $Scope, $Force, $Claim)
                [pscustomobject]@{ Token = 'fake-graph-token'; ExpiresOn = [DateTimeOffset]::UtcNow.AddHours(1); Identity = 'admin@contoso.com'; TenantId = '11111111-1111-1111-1111-111111111111' }
            }

            InModuleScope $script:moduleName {
                Initialize-OERAuth -TenantId 'tenant-a.example.com' -AuthMethod 'DeviceCode'
                # Past the five-minute floor, so the cache misses and a second request is made.
                $script:_OERAuthState.GraphTokenExpiry = [DateTime]::UtcNow.AddMinutes(-1)

                $RefreshWarnings = 'not-run'
                Initialize-OERAuth -TenantId 'tenant-a.example.com' -AuthMethod 'DeviceCode' `
                    -WarningVariable RefreshWarnings -WarningAction SilentlyContinue

                $script:_OERAuthState.GraphTokenExpiry | Should -BeGreaterThan ([DateTime]::UtcNow)
                @($RefreshWarnings).Count | Should -Be 0
            }

            Should -Invoke -ModuleName $script:moduleName Get-AzToken -Exactly -Times 2
        }

        # The second benign shape: a sign-in that named no tenant is recorded as 'organizations', and
        # naming that same tenant's own domain next is issued the same tenant. 'organizations' is
        # deliberately NOT excluded -- a device-code sign-in naming no tenant, followed by a customer's
        # domain still issued by the home tenant, is the same shape and is the real failure -- so the
        # warning fires, and its "is a name of tenant" sentence tells the operator when that is expected.
        It 'warns exactly once when a session that named no tenant is followed by a domain issued the same tenant (Q7)' {
            Mock -ModuleName $script:moduleName Get-AzToken {
                param($ClientId, $ClientSecret, $Resource, $Tenant, $ErrorAction, $Interactive,
                      $DeviceCode, $ManagedIdentity, $ClientCertificate, $ClientCertificatePath,
                      $Scope, $Force, $Claim)
                # The signed-in account's home tenant answers both sign-ins.
                [pscustomobject]@{
                    Token     = 'fake-graph-token'
                    ExpiresOn = [DateTimeOffset]::UtcNow.AddHours(1)
                    Identity  = 'admin@contoso.com'
                    TenantId  = '11111111-1111-1111-1111-111111111111'
                }
            }

            InModuleScope $script:moduleName {
                # No -TenantId and no session: the request targets 'organizations'.
                $FirstWarnings = 'not-run'
                Initialize-OERAuth -AuthMethod 'Interactive' `
                    -WarningVariable FirstWarnings -WarningAction SilentlyContinue
                $script:_OERAuthState.TenantId      | Should -Be 'organizations'
                $script:_OERAuthState.TokenTenantId | Should -Be '11111111-1111-1111-1111-111111111111'

                $SwitchWarnings = 'not-run'
                Initialize-OERAuth -TenantId 'contoso.onmicrosoft.com' -AuthMethod 'Interactive' `
                    -WarningVariable SwitchWarnings -WarningAction SilentlyContinue

                $script:_OERAuthState.TenantId      | Should -Be 'contoso.onmicrosoft.com'
                $script:_OERAuthState.TokenTenantId | Should -Be '11111111-1111-1111-1111-111111111111'
                @($FirstWarnings).Count  | Should -Be 0 -Because 'a first sign-in has no previous session to compare with'
                @($SwitchWarnings).Count | Should -Be 1

                $Message = $SwitchWarnings[0].Message
                $Message | Should -Match ([regex]::Escape("which named 'organizations'"))
                $Message | Should -Match ([regex]::Escape("token for tenant 'contoso.onmicrosoft.com'"))
                $Message | Should -Match ([regex]::Escape("issued by tenant '11111111-1111-1111-1111-111111111111'"))
                $Message | Should -Match ([regex]::Escape('is a name of tenant'))
                $Message | Should -Match ([regex]::Escape(
                    "If 'contoso.onmicrosoft.com' is a name of tenant '11111111-1111-1111-1111-111111111111', this is expected."))
                # The consequence names the ARM half, not Graph alone, since ARM is the transport that
                # writes role assignments. Measured live on 2026-09-16 in a MANAGED IDENTITY sign-in with
                # -IncludeARM (not in this test's Interactive shape): a switch that did not take effect
                # left the ARM token issued by the same wrong tenant as the Graph one. The message claims
                # no shared credential -- Graph and ARM share one only where the client ids match -- so
                # what is guarded here is that ARM is NAMED, not that the two tokens must agree. Guarded
                # HERE and not only by Q1's word-for-word pin, so the clause survives a later relaxation
                # of that pin, and asserted as one span so that dropping either half fails.
                $Message | Should -Match ([regex]::Escape(
                    'Azure Resource Manager calls, including the ones that write role assignments')) `
                    -Because 'an operator told only about Microsoft Graph would believe the role assignment writes were unaffected'
            }

            Should -Invoke -ModuleName $script:moduleName Get-AzToken -Exactly -Times 2
        }

        # The most natural switch of all: disconnect, then connect to the next customer. Disconnect-OER
        # clears $script:_OERAuthState, so the check compares with the last session ESTABLISHED in this
        # process instead, which Disconnect-OER leaves alone.
        It 'still warns after Disconnect-OER when a sign-in naming another domain is issued the same tenant (Q8)' {
            Mock -ModuleName $script:moduleName Get-AzToken {
                param($ClientId, $ClientSecret, $Resource, $Tenant, $ErrorAction, $Interactive,
                      $DeviceCode, $ManagedIdentity, $ClientCertificate, $ClientCertificatePath,
                      $Scope, $Force, $Claim)
                [pscustomobject]@{
                    Token     = 'fake-graph-token'
                    ExpiresOn = [DateTimeOffset]::UtcNow.AddHours(1)
                    Identity  = 'admin@contoso.com'
                    TenantId  = '11111111-1111-1111-1111-111111111111'
                }
            }
            # Both mocked: Disconnect-AzAccount resolves for real in the test environment and would
            # clear the operator's own Az context.
            Mock -ModuleName $script:moduleName Disconnect-MgGraph { }
            Mock -ModuleName $script:moduleName Disconnect-AzAccount { }

            InModuleScope $script:moduleName {
                Initialize-OERAuth -TenantId 'a.example.com' -AuthMethod 'DeviceCode'
                $script:_OERAuthState.TokenTenantId | Should -Be '11111111-1111-1111-1111-111111111111'

                Disconnect-OER -Confirm:$false
                $script:_OERAuthState | Should -BeNullOrEmpty -Because 'the session is gone, so only the issued-session tracker can still remember a.example.com'

                $SwitchWarnings = 'not-run'
                Initialize-OERAuth -TenantId 'b.example.com' -AuthMethod 'DeviceCode' `
                    -WarningVariable SwitchWarnings -WarningAction SilentlyContinue

                $script:_OERAuthState.TenantId      | Should -Be 'b.example.com'
                $script:_OERAuthState.TokenTenantId | Should -Be '11111111-1111-1111-1111-111111111111'
                @($SwitchWarnings).Count | Should -Be 1

                $Message = $SwitchWarnings[0].Message
                $Message | Should -Match ([regex]::Escape("token for tenant 'b.example.com'"))
                $Message | Should -Match ([regex]::Escape("issued by tenant '11111111-1111-1111-1111-111111111111'"))
                $Message | Should -Match ([regex]::Escape("which named 'a.example.com'"))
            }

            Should -Invoke -ModuleName $script:moduleName Disconnect-MgGraph -Exactly -Times 1
            Should -Invoke -ModuleName $script:moduleName Get-AzToken -Exactly -Times 2
        }

        # A request that names no tenant asks for no particular tenant, so no switch can have failed.
        # Through the tracker that case is reachable right after Disconnect-OER, since with no session
        # left there is nothing for the request to inherit a tenant from.
        It 'stays silent when a sign-in after Disconnect-OER names no tenant (Q9)' {
            Mock -ModuleName $script:moduleName Get-AzToken {
                param($ClientId, $ClientSecret, $Resource, $Tenant, $ErrorAction, $Interactive,
                      $DeviceCode, $ManagedIdentity, $ClientCertificate, $ClientCertificatePath,
                      $Scope, $Force, $Claim)
                [pscustomobject]@{
                    Token     = 'fake-graph-token'
                    ExpiresOn = [DateTimeOffset]::UtcNow.AddHours(1)
                    Identity  = 'admin@contoso.com'
                    TenantId  = '11111111-1111-1111-1111-111111111111'
                }
            }
            Mock -ModuleName $script:moduleName Disconnect-MgGraph { }
            Mock -ModuleName $script:moduleName Disconnect-AzAccount { }

            InModuleScope $script:moduleName {
                Initialize-OERAuth -TenantId 'a.example.com' -AuthMethod 'DeviceCode'
                Disconnect-OER -Confirm:$false
                $script:_OERAuthState | Should -BeNullOrEmpty
                # The tracker still names a.example.com and its GUID, so every other term holds and the
                # silence below belongs to the no-tenant exclusion alone.
                $script:_OERLastIssuedSession.TenantId      | Should -Be 'a.example.com'
                $script:_OERLastIssuedSession.TokenTenantId | Should -Be '11111111-1111-1111-1111-111111111111'

                $Warnings = 'not-run'
                Initialize-OERAuth -AuthMethod 'DeviceCode' `
                    -WarningVariable Warnings -WarningAction SilentlyContinue

                $script:_OERAuthState.TenantId      | Should -Be 'organizations'
                $script:_OERAuthState.TokenTenantId | Should -Be '11111111-1111-1111-1111-111111111111'
                @($Warnings).Count | Should -Be 0
            }

            Should -Invoke -ModuleName $script:moduleName Disconnect-MgGraph -Exactly -Times 1
            Should -Invoke -ModuleName $script:moduleName Get-AzToken -Exactly -Times 2
        }

        # Placement, not only the predicate. The warning is evaluated after the token call, so a caller
        # running with -WarningAction Stop is stopped there -- above Connect-MgGraph, the state rebuild and
        # the issued-session record. The previous session survives untouched and still describes its own
        # token, and nothing is left naming the domain the stopped sign-in asked for.
        It 'stops a -WarningAction Stop sign-in at the post-call warning, before Connect-MgGraph, the state rebuild and the session record (Q10)' {
            Mock -ModuleName $script:moduleName Get-AzToken {
                param($ClientId, $ClientSecret, $Resource, $Tenant, $ErrorAction, $Interactive,
                      $DeviceCode, $ManagedIdentity, $ClientCertificate, $ClientCertificatePath,
                      $Scope, $Force, $Claim)
                [pscustomobject]@{
                    Token     = 'fake-graph-token'
                    ExpiresOn = [DateTimeOffset]::UtcNow.AddHours(1)
                    Identity  = 'admin@contoso.com'
                    TenantId  = '11111111-1111-1111-1111-111111111111'
                }
            }

            InModuleScope $script:moduleName {
                Initialize-OERAuth -TenantId 'a.example.com' -AuthMethod 'DeviceCode'
                $script:_OERAuthState.TenantId              | Should -Be 'a.example.com'
                $script:_OERLastIssuedSession.TenantId      | Should -Be 'a.example.com'
                $script:_OERLastIssuedSession.TokenTenantId | Should -Be '11111111-1111-1111-1111-111111111111'

                $StateBefore   = $script:_OERAuthState
                $SessionBefore = $script:_OERLastIssuedSession

                $StopCaught = $null
                try {
                    Initialize-OERAuth -TenantId 'b.example.com' -AuthMethod 'DeviceCode' -WarningAction Stop
                }
                catch {
                    $StopCaught = $PSItem
                }

                $StopCaught | Should -Not -BeNullOrEmpty -Because 'a -WarningAction Stop caller has to be stopped at the warning'
                $StopCaught.Exception | Should -BeOfType [System.Management.Automation.ActionPreferenceStopException]
                $StopCaught.Exception.Message | Should -Match ([regex]::Escape(
                    "The Microsoft Graph token for tenant 'b.example.com' was issued by tenant '11111111-1111-1111-1111-111111111111', the same tenant that issued the token for the previous session, which named 'a.example.com'."))

                [object]::ReferenceEquals($script:_OERAuthState, $StateBefore) | Should -BeTrue
                $script:_OERAuthState.TenantId | Should -Be 'a.example.com'
                [object]::ReferenceEquals($script:_OERLastIssuedSession, $SessionBefore) | Should -BeTrue
                $script:_OERLastIssuedSession.TenantId      | Should -Be 'a.example.com'
                $script:_OERLastIssuedSession.TokenTenantId | Should -Be '11111111-1111-1111-1111-111111111111'
            }

            # The stopped sign-in DID reach its token call, since the warning is post-call, and it never
            # reached Connect-MgGraph: the one invocation is the first sign-in's.
            Should -Invoke -ModuleName $script:moduleName Get-AzToken -Exactly -Times 2
            Should -Invoke -ModuleName $script:moduleName Connect-MgGraph -Exactly -Times 1
        }
    }
}
