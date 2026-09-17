BeforeAll {
    $script:moduleName = 'Omnicit.EntraRBAC'
    Get-Module $script:moduleName | Remove-Module -Force -ErrorAction SilentlyContinue
    Import-Module $script:moduleName -Force -ErrorAction Stop
}

Describe 'Connect-OER' {
    It 'forwards interactive auth to Initialize-OERAuth' {
        Mock -ModuleName $script:moduleName Initialize-OERAuth {}
        Connect-OER -TenantId 'contoso' -Interactive
        Should -Invoke -ModuleName $script:moduleName Initialize-OERAuth -Times 1 -ParameterFilter {
            $TenantId -eq 'contoso' -and $AuthMethod -eq 'Interactive'
        }
    }

    It 'forwards client secret auth to Initialize-OERAuth' {
        Mock -ModuleName $script:moduleName Initialize-OERAuth {}
        $Secret = ConvertTo-SecureString 'sek-basic' -AsPlainText -Force
        Connect-OER -TenantId 'contoso' -ClientId 'cid' -ClientSecret $Secret
        # The secret VALUE is asserted, not just the parameter set: without the last two operands,
        # deleting the "if ($ClientSecret) { $AuthParams.ClientSecret = $ClientSecret }" forward in
        # Connect-OER leaves this test green, because AuthMethod and ClientId travel independently.
        # -is [securestring] is placed before the value comparison so -and short-circuits and the
        # plaintext is never materialized when the parameter did not arrive at all.
        Should -Invoke -ModuleName $script:moduleName Initialize-OERAuth -Times 1 -ParameterFilter {
            $AuthMethod -eq 'ClientSecret' -and $ClientId -eq 'cid' -and
            $ClientSecret -is [securestring] -and
            [System.Net.NetworkCredential]::new('', $ClientSecret).Password -eq 'sek-basic'
        }
    }

    It 'resolves a TenantAlias to a TenantId from a profile' {
        Mock -ModuleName $script:moduleName Initialize-OERAuth {}
        $Base = Join-Path $TestDrive 'ConnProfiles'
        New-OERConfiguration -TenantAlias corp -TenantId 'tid-corp' -BasePath $Base | Out-Null
        Connect-OER -TenantAlias corp -ProfileBasePath $Base
        Should -Invoke -ModuleName $script:moduleName Initialize-OERAuth -Times 1 -ParameterFilter {
            $TenantId -eq 'tid-corp'
        }
    }

    It 'forwards a custom ClientId for interactive sign-in (dedicated app)' {
        Mock -ModuleName $script:moduleName Initialize-OERAuth {}
        Connect-OER -TenantId 'contoso' -Interactive -ClientId 'my-app-id'
        Should -Invoke -ModuleName $script:moduleName Initialize-OERAuth -Times 1 -ParameterFilter {
            $AuthMethod -eq 'Interactive' -and $ClientId -eq 'my-app-id'
        }
    }

    It 'forwards certificate-path auth to Initialize-OERAuth' {
        Mock -ModuleName $script:moduleName Initialize-OERAuth {}
        Connect-OER -TenantId 'contoso' -ClientId 'cid' -CertificatePath 'C:\certs\app.pfx'
        Should -Invoke -ModuleName $script:moduleName Initialize-OERAuth -Times 1 -ParameterFilter {
            $AuthMethod -eq 'ClientCertificate' -and $CertificatePath -eq 'C:\certs\app.pfx'
        }
    }

    It 'forwards the certificate object on the ClientCertificate parameter set' {
        # The ClientCertificate (in-memory X509) parameter set had no test at all, so the
        # "if ($Certificate) { $AuthParams.Certificate = $Certificate }" forward in Connect-OER was
        # uncovered -- the ClientCertificatePath It above exercises a different set. The certificate is
        # generated in-process with an ephemeral key: no tenant call, no file on disk, no certificate
        # store write. The filter pins a property of the FORWARDED object, not merely that the call
        # happened, so dropping the forward makes this It fail.
        Mock -ModuleName $script:moduleName Initialize-OERAuth {}
        $Key = [System.Security.Cryptography.ECDsa]::Create(
            [System.Security.Cryptography.ECCurve+NamedCurves]::nistP256)
        try {
            $Request = [System.Security.Cryptography.X509Certificates.CertificateRequest]::new(
                'CN=oer-test', $Key, [System.Security.Cryptography.HashAlgorithmName]::SHA256)
            $Cert = $Request.CreateSelfSigned(
                [System.DateTimeOffset]::UtcNow.AddDays(-1), [System.DateTimeOffset]::UtcNow.AddDays(1))

            Connect-OER -TenantId 'contoso' -ClientId 'cid' -Certificate $Cert

            Should -Invoke -ModuleName $script:moduleName Initialize-OERAuth -Times 1 -ParameterFilter {
                $AuthMethod -eq 'ClientCertificate' -and $ClientId -eq 'cid' -and
                $Certificate -is [System.Security.Cryptography.X509Certificates.X509Certificate2] -and
                $Certificate.Subject -eq 'CN=oer-test'
            }
        }
        finally {
            if ($Cert) { $Cert.Dispose() }
            $Key.Dispose()
        }
    }

    It 'forwards device-code auth to Initialize-OERAuth' {
        Mock -ModuleName $script:moduleName Initialize-OERAuth {}
        Connect-OER -TenantId 'contoso' -DeviceCode
        Should -Invoke -ModuleName $script:moduleName Initialize-OERAuth -Times 1 -ParameterFilter { $AuthMethod -eq 'DeviceCode' }
    }

    It 'forwards managed-identity auth to Initialize-OERAuth' {
        Mock -ModuleName $script:moduleName Initialize-OERAuth {}
        Connect-OER -ManagedIdentity
        Should -Invoke -ModuleName $script:moduleName Initialize-OERAuth -Times 1 -ParameterFilter { $AuthMethod -eq 'ManagedIdentity' }
    }

    It 'errors and skips auth when the tenant alias is not found' {
        Mock -ModuleName $script:moduleName Initialize-OERAuth {}
        $Base = Join-Path $TestDrive 'NoProfiles'
        Connect-OER -TenantAlias missing -ProfileBasePath $Base -ErrorVariable err -ErrorAction SilentlyContinue
        $err.FullyQualifiedErrorId | Should -Match 'TenantAliasNotFound'
        Should -Invoke -ModuleName $script:moduleName Initialize-OERAuth -Times 0
    }

    It 'binds -TenantAlias from the pipeline by property name (Get-OERConfiguration | Connect-OER)' {
        Mock -ModuleName $script:moduleName Initialize-OERAuth {}
        $Base = Join-Path $TestDrive 'PipeProfiles'
        New-OERConfiguration -TenantAlias pipe_corp -TenantId 'tid-pipe' -BasePath $Base | Out-Null
        [pscustomobject]@{ TenantAlias = 'pipe_corp' } | Connect-OER -ProfileBasePath $Base
        Should -Invoke -ModuleName $script:moduleName Initialize-OERAuth -Times 1 -ParameterFilter {
            $TenantId -eq 'tid-pipe'
        }
    }

    Context 'BasePath naming (audit PR6)' {
        It 'accepts -BasePath and forwards it to Get-OERConfiguration' {
            Mock -ModuleName $script:moduleName Initialize-OERAuth {}
            Mock -ModuleName $script:moduleName Get-OERConfiguration {
                [pscustomobject]@{ TenantAlias = 'contoso'; TenantId = 'tid-contoso' }
            }
            Connect-OER -TenantAlias 'contoso' -BasePath 'TestDrive:\Profiles' | Out-Null
            Should -Invoke -ModuleName $script:moduleName Get-OERConfiguration -Times 1 -ParameterFilter {
                $BasePath -eq 'TestDrive:\Profiles'
            }
        }

        It 'still accepts the historical -ProfileBasePath name' {
            Mock -ModuleName $script:moduleName Initialize-OERAuth {}
            Mock -ModuleName $script:moduleName Get-OERConfiguration {
                [pscustomobject]@{ TenantAlias = 'contoso'; TenantId = 'tid-contoso' }
            }
            Connect-OER -TenantAlias 'contoso' -ProfileBasePath 'TestDrive:\Profiles' | Out-Null
            Should -Invoke -ModuleName $script:moduleName Get-OERConfiguration -Times 1 -ParameterFilter {
                $BasePath -eq 'TestDrive:\Profiles'
            }
        }
    }

    It 'rejects a traversal tenant alias before reading any profile' {
        Mock -ModuleName Omnicit.EntraRBAC Get-OERConfiguration { }
        Mock -ModuleName Omnicit.EntraRBAC Initialize-OERAuth { }
        Connect-OER -TenantAlias '../../../evil' -ErrorAction SilentlyContinue -ErrorVariable Err
        @($Err).FullyQualifiedErrorId -join ';' | Should -Match 'InvalidTenantAlias'
        Should -Invoke -ModuleName Omnicit.EntraRBAC Get-OERConfiguration -Times 0
        Should -Invoke -ModuleName Omnicit.EntraRBAC Initialize-OERAuth -Times 0
    }

    Context '-TenantAlias combines with any credential selector (A-connect-byalias-no-authmethod)' {
        Context 'Preserved invocations (backward compatibility)' {
            It 'Connect-OER -TenantAlias corp resolves to the Interactive set' {
                Mock -ModuleName $script:moduleName Initialize-OERAuth { }
                Mock -ModuleName $script:moduleName Get-OERConfiguration {
                    [PSCustomObject]@{ TenantAlias = 'corp'; TenantId = 'tenant-guid' }
                }

                Connect-OER -TenantAlias corp

                Should -Invoke -ModuleName $script:moduleName Initialize-OERAuth -Times 1 -ParameterFilter {
                    $AuthMethod -eq 'Interactive' -and $TenantId -eq 'tenant-guid'
                }
            }

            It 'Get-OERConfiguration | Connect-OER resolves to the Interactive set' {
                Mock -ModuleName $script:moduleName Initialize-OERAuth { }
                Mock -ModuleName $script:moduleName Get-OERConfiguration {
                    [PSCustomObject]@{ TenantAlias = 'corp'; TenantId = 'tenant-guid' }
                }
                # The -ModuleName mock above answers only Connect-OER's own lookup. The left-hand
                # Get-OERConfiguration below runs in TEST scope, where it resolved to the real cmdlet
                # and enumerated the real profile directory, so it needs a test-scope mock of its own.
                # -Exactly matters too: at-least -Times 1 passed for any number of real profiles
                # (docs/development/rationale.md#bearer-scrub-tests).
                Mock Get-OERConfiguration {
                    [PSCustomObject]@{ TenantAlias = 'corp'; TenantId = 'tenant-guid' }
                }

                Get-OERConfiguration | Connect-OER

                Should -Invoke Get-OERConfiguration -Exactly -Times 1
                Should -Invoke -ModuleName $script:moduleName Initialize-OERAuth -Exactly -Times 1 -ParameterFilter {
                    $AuthMethod -eq 'Interactive' -and $TenantId -eq 'tenant-guid'
                }
            }

            It 'Connect-OER -TenantId x resolves to the Interactive set' {
                Mock -ModuleName $script:moduleName Initialize-OERAuth { }

                Connect-OER -TenantId 'x'

                Should -Invoke -ModuleName $script:moduleName Initialize-OERAuth -Times 1 -ParameterFilter {
                    $AuthMethod -eq 'Interactive' -and $TenantId -eq 'x'
                }
            }

            It 'Connect-OER -TenantId x -Interactive resolves to the Interactive set' {
                Mock -ModuleName $script:moduleName Initialize-OERAuth { }

                Connect-OER -TenantId 'x' -Interactive

                Should -Invoke -ModuleName $script:moduleName Initialize-OERAuth -Times 1 -ParameterFilter {
                    $AuthMethod -eq 'Interactive' -and $TenantId -eq 'x'
                }
            }

            It 'Connect-OER -TenantId x -DeviceCode resolves to the DeviceCode set' {
                Mock -ModuleName $script:moduleName Initialize-OERAuth { }

                Connect-OER -TenantId 'x' -DeviceCode

                Should -Invoke -ModuleName $script:moduleName Initialize-OERAuth -Times 1 -ParameterFilter {
                    $AuthMethod -eq 'DeviceCode' -and $TenantId -eq 'x'
                }
            }

            It 'Connect-OER -ManagedIdentity resolves to the ManagedIdentity set' {
                Mock -ModuleName $script:moduleName Initialize-OERAuth { }

                Connect-OER -ManagedIdentity

                Should -Invoke -ModuleName $script:moduleName Initialize-OERAuth -Times 1 -ParameterFilter {
                    $AuthMethod -eq 'ManagedIdentity'
                }
            }

            It 'Connect-OER -TenantId x -ClientId a -ClientSecret $s resolves to the ClientSecret set' {
                Mock -ModuleName $script:moduleName Initialize-OERAuth { }
                $Secret = ConvertTo-SecureString 'sek-tenantid' -AsPlainText -Force

                Connect-OER -TenantId 'x' -ClientId 'a' -ClientSecret $Secret

                Should -Invoke -ModuleName $script:moduleName Initialize-OERAuth -Times 1 -ParameterFilter {
                    $AuthMethod -eq 'ClientSecret' -and $TenantId -eq 'x' -and $ClientId -eq 'a' -and
                    $ClientSecret -is [securestring] -and
                    [System.Net.NetworkCredential]::new('', $ClientSecret).Password -eq 'sek-tenantid'
                }
            }

            It 'Connect-OER -TenantId x -ClientId a -CertificatePath p resolves to the ClientCertificatePath set' {
                Mock -ModuleName $script:moduleName Initialize-OERAuth { }

                Connect-OER -TenantId 'x' -ClientId 'a' -CertificatePath 'p'

                Should -Invoke -ModuleName $script:moduleName Initialize-OERAuth -Times 1 -ParameterFilter {
                    $AuthMethod -eq 'ClientCertificate' -and $TenantId -eq 'x' -and $ClientId -eq 'a'
                }
            }
        }

        Context 'Newly enabled invocations' {
            It 'combines -TenantAlias with -DeviceCode' {
                Mock -ModuleName $script:moduleName Initialize-OERAuth { }
                Mock -ModuleName $script:moduleName Get-OERConfiguration {
                    [PSCustomObject]@{ TenantAlias = 'corp'; TenantId = 'tenant-guid' }
                }

                Connect-OER -TenantAlias corp -DeviceCode

                Should -Invoke -ModuleName $script:moduleName Initialize-OERAuth -Times 1 -ParameterFilter {
                    $AuthMethod -eq 'DeviceCode' -and $TenantId -eq 'tenant-guid'
                }
            }

            It 'combines -TenantAlias with -ManagedIdentity' {
                Mock -ModuleName $script:moduleName Initialize-OERAuth { }
                Mock -ModuleName $script:moduleName Get-OERConfiguration {
                    [PSCustomObject]@{ TenantAlias = 'corp'; TenantId = 'tenant-guid' }
                }

                Connect-OER -TenantAlias corp -ManagedIdentity

                Should -Invoke -ModuleName $script:moduleName Initialize-OERAuth -Times 1 -ParameterFilter {
                    $AuthMethod -eq 'ManagedIdentity' -and $TenantId -eq 'tenant-guid'
                }
            }

            It 'combines -TenantAlias with -ClientId and -ClientSecret' {
                Mock -ModuleName $script:moduleName Initialize-OERAuth { }
                Mock -ModuleName $script:moduleName Get-OERConfiguration {
                    [PSCustomObject]@{ TenantAlias = 'corp'; TenantId = 'tenant-guid' }
                }
                $Secret = ConvertTo-SecureString 'sek-alias' -AsPlainText -Force

                Connect-OER -TenantAlias corp -ClientId 'a' -ClientSecret $Secret

                Should -Invoke -ModuleName $script:moduleName Initialize-OERAuth -Times 1 -ParameterFilter {
                    $AuthMethod -eq 'ClientSecret' -and $TenantId -eq 'tenant-guid' -and $ClientId -eq 'a' -and
                    $ClientSecret -is [securestring] -and
                    [System.Net.NetworkCredential]::new('', $ClientSecret).Password -eq 'sek-alias'
                }
            }

            It 'combines -TenantAlias with -ClientId and -CertificatePath' {
                Mock -ModuleName $script:moduleName Initialize-OERAuth { }
                Mock -ModuleName $script:moduleName Get-OERConfiguration {
                    [PSCustomObject]@{ TenantAlias = 'corp'; TenantId = 'tenant-guid' }
                }

                Connect-OER -TenantAlias corp -ClientId 'a' -CertificatePath 'p'

                Should -Invoke -ModuleName $script:moduleName Initialize-OERAuth -Times 1 -ParameterFilter {
                    $AuthMethod -eq 'ClientCertificate' -and $TenantId -eq 'tenant-guid' -and $ClientId -eq 'a'
                }
            }
        }

        It 'rejects -TenantId together with -TenantAlias' {
            Mock -ModuleName $script:moduleName Initialize-OERAuth { }
            $Err = $null
            Connect-OER -TenantId 'x' -TenantAlias 'corp' -ErrorVariable Err -ErrorAction SilentlyContinue

            @($Err | Where-Object { $_.FullyQualifiedErrorId -eq 'AmbiguousTenant,Connect-OER' }).Count |
                Should -Be 1
            Should -Invoke -ModuleName $script:moduleName Initialize-OERAuth -Times 0
        }
    }

    Context 'a bare Connect-OER targets the current session tenant (Finding 1: SEC-connect-oer-inherits-session-tenant)' {
        # These two tests exercise the REAL Initialize-OERAuth (not mocked) so the session-inheritance
        # logic actually runs. This is deliberate, pinned behaviour, not a regression:
        #   1. The pre-branch code re-stamped TenantId = 'organizations' over a real tenant id on every
        #      call that omitted -TenantId, including a second bare Connect-OER for the SAME tenant.
        #      That mislabelled-state defect is exactly what this branch fixes; inheriting the session's
        #      tenant instead is strictly more correct on the state-label axis.
        #   2. Connect-OER -TenantId A -Interactive called twice was ALREADY a silent no-op via
        #      $GraphCached before this branch (same tenant, same method, valid token). A bare
        #      Connect-OER -Interactive after that now simply behaves the same way instead of resetting
        #      to an unlabelled tenant.
        BeforeEach {
            InModuleScope $script:moduleName {
                $script:_OERAuthState = $null
                $script:_OERLastAuthorityHost = $null
                $script:_OERLastTokenRequest = $null
                $script:_OERLastIssuedSession = $null
            }
        }

        It 'reuses the cached tenant-A session from cache instead of resetting to organizations' {
            Mock -ModuleName $script:moduleName Get-AzToken { }
            Mock -ModuleName $script:moduleName Connect-MgGraph { }

            InModuleScope $script:moduleName {
                # Equivalent to a prior Connect-OER -TenantId 'tenant-a' -Interactive: a valid Graph
                # token well inside the 5-minute floor.
                $script:_OERAuthState = @{
                    TenantId         = 'tenant-a'
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

            Connect-OER -Interactive

            Should -Invoke -ModuleName $script:moduleName Get-AzToken -Exactly -Times 0
            InModuleScope $script:moduleName {
                $script:_OERAuthState.TenantId | Should -Be 'tenant-a'
            }
        }

        It 'RE-authenticates against tenant A, not organizations, when the cached credential differs' {
            Mock -ModuleName $script:moduleName Get-AzToken {
                [pscustomobject]@{ Token = 'fake'; ExpiresOn = [DateTimeOffset]::UtcNow.AddHours(1); Identity = 'user@contoso' }
            }
            Mock -ModuleName $script:moduleName Connect-MgGraph { }

            InModuleScope $script:moduleName {
                # Equivalent to a prior Connect-OER -TenantId 'tenant-a' -ClientId 'app-c' -ClientSecret $s.
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
            }

            Connect-OER -Interactive

            Should -Invoke -ModuleName $script:moduleName Get-AzToken -Exactly -Times 1 -ParameterFilter {
                $Interactive -and $Tenant -eq 'tenant-a'
            }
            InModuleScope $script:moduleName {
                $script:_OERAuthState.TenantId   | Should -Be 'tenant-a'
                $script:_OERAuthState.AuthMethod | Should -Be 'Interactive'
            }
        }
    }
}

# -------------------------------------------------------------------------------------------------
# Sovereign clouds (Sprint 1.5, issue #81).
# -------------------------------------------------------------------------------------------------
Describe 'Connect-OER -Environment' {
    It 'forwards -Environment to Initialize-OERAuth when supplied' {
        Mock -ModuleName $script:moduleName Initialize-OERAuth {
            param($TenantId, $AuthMethod, $ClientId, $ClientSecret, $Certificate, $CertificatePath,
                  $IncludeARM, $ClaimsChallenge, $ForceRefresh, $Environment)
            $script:ConnectSuppliedKeys        = @($PSBoundParameters.Keys)
            $script:ConnectSuppliedEnvironment = $Environment
        }

        Connect-OER -TenantId 'contoso' -Interactive -Environment 'USGov'

        $script:ConnectSuppliedKeys        | Should -Contain 'Environment'
        $script:ConnectSuppliedEnvironment | Should -Be 'USGov'
    }

    # The key must be ABSENT, not present-and-empty and not present-and-Global. Initialize-OERAuth
    # reads an absent -Environment as "inherit the session's cloud"; a forwarded 'Global' default
    # would stamp the public cloud over a sovereign session on every bare Connect-OER, which is the
    # same defect shape the -AuthMethod default once had.
    It 'does NOT forward an Environment key at all when -Environment is omitted' {
        Mock -ModuleName $script:moduleName Initialize-OERAuth {
            param($TenantId, $AuthMethod, $ClientId, $ClientSecret, $Certificate, $CertificatePath,
                  $IncludeARM, $ClaimsChallenge, $ForceRefresh, $Environment)
            $script:ConnectOmittedKeys = @($PSBoundParameters.Keys)
        }

        Connect-OER -TenantId 'contoso' -Interactive

        $script:ConnectOmittedKeys | Should -Not -BeNullOrEmpty -Because 'the mock must have run, or the assertion below is vacuous'
        $script:ConnectOmittedKeys | Should -Not -Contain 'Environment'
    }

    It 'accepts -Environment on every credential parameter set' {
        # Compared against -TenantId rather than a literal list, so adding a seventh parameter set
        # without extending -Environment fails here instead of shipping a set that cannot pick a
        # cloud. -TenantId is declared on all six sets today.
        $Command = Get-Command -Name Connect-OER -Module $script:moduleName
        $EnvironmentSets = @($Command.Parameters['Environment'].ParameterSets.Keys | Sort-Object)
        $TenantIdSets    = @($Command.Parameters['TenantId'].ParameterSets.Keys | Sort-Object)

        $EnvironmentSets      | Should -Not -BeNullOrEmpty
        $EnvironmentSets.Count | Should -Be 6
        ($EnvironmentSets -join ',') | Should -Be ($TenantIdSets -join ',')
    }

    # Positional binding follows DECLARATION order. A new parameter inserted above an existing one
    # silently changes what an existing positional argument binds to, so the newest parameter is
    # declared last -- the same rule the two alias-order cohort suites machine-check elsewhere. A
    # switch is never bound positionally, so -Force (declared after -Environment) disturbs no
    # positional argument regardless of where it lands -- it is still declared last on the same
    # "newest parameter last" convention.
    It 'declares the newest parameters last: -Environment, then -Force' {
        $CommandAst = (Get-Command -Name Connect-OER -Module $script:moduleName).ScriptBlock.Ast
        $ParamBlock = if ($CommandAst -is [System.Management.Automation.Language.FunctionDefinitionAst]) {
            $CommandAst.Body.ParamBlock
        }
        else {
            $CommandAst.ParamBlock
        }
        $Names = @($ParamBlock.Parameters.Name.VariablePath.ForEach({ $_.ToString() }))

        $Names | Should -Contain 'Environment'
        $Names | Should -Contain 'Force'
        $Names[-1] | Should -Be 'Force'
        $Names[-2] | Should -Be 'Environment'
    }

    It 'rejects a cloud that Get-OERCloudEndpoint has no row for' {
        Mock -ModuleName $script:moduleName Initialize-OERAuth { }

        { Connect-OER -TenantId 'contoso' -Interactive -Environment 'Germany' } | Should -Throw '*Germany*'
        Should -Invoke -ModuleName $script:moduleName Initialize-OERAuth -Exactly -Times 0
    }

    # ---------------------------------------------------------------------------------------------
    # Task 5 (issue #81): a Tenant Profile can carry its own Environment, so -TenantAlias selects
    # the right cloud automatically. Get-OERConfiguration is deliberately NOT mocked in these three
    # tests -- a real profile is written under -BasePath so the resolution runs end to end, matching
    # the existing (unmocked) "resolves a TenantAlias to a TenantId from a profile" It above.
    # ---------------------------------------------------------------------------------------------
    It 'uses the Tenant Profile Environment when -Environment is not supplied on the command line' {
        Mock -ModuleName $script:moduleName Initialize-OERAuth {
            param($TenantId, $AuthMethod, $ClientId, $ClientSecret, $Certificate, $CertificatePath,
                  $IncludeARM, $ClaimsChallenge, $ForceRefresh, $Environment)
            $script:ConnectProfileEnvironment = $Environment
        }
        $Base = Join-Path $TestDrive 'ConnectEnvProfiles'
        New-OERConfiguration -TenantAlias usgov -TenantId 'tid-usgov' -Environment USGov -BasePath $Base | Out-Null

        Connect-OER -TenantAlias usgov -BasePath $Base

        $script:ConnectProfileEnvironment | Should -Be 'USGov'
    }

    It 'lets an explicit -Environment on the command line win over the profile stored value' {
        Mock -ModuleName $script:moduleName Initialize-OERAuth {
            param($TenantId, $AuthMethod, $ClientId, $ClientSecret, $Certificate, $CertificatePath,
                  $IncludeARM, $ClaimsChallenge, $ForceRefresh, $Environment)
            $script:ConnectOverrideEnvironment = $Environment
        }
        $Base = Join-Path $TestDrive 'ConnectEnvOverride'
        New-OERConfiguration -TenantAlias usgov -TenantId 'tid-usgov' -Environment USGov -BasePath $Base | Out-Null

        Connect-OER -TenantAlias usgov -Environment China -BasePath $Base

        $script:ConnectOverrideEnvironment | Should -Be 'China'
    }

    # The key must be ABSENT, matching the existing "omitted on the command line" It far above --
    # not merely null, since Initialize-OERAuth reads an absent -Environment as "inherit the
    # session's cloud" and a forwarded null could be read differently by a future implementation.
    It 'forwards no Environment key at all when the resolved profile carries none' {
        Mock -ModuleName $script:moduleName Initialize-OERAuth {
            param($TenantId, $AuthMethod, $ClientId, $ClientSecret, $Certificate, $CertificatePath,
                  $IncludeARM, $ClaimsChallenge, $ForceRefresh, $Environment)
            $script:ConnectProfileNoEnvKeys = @($PSBoundParameters.Keys)
        }
        $Base = Join-Path $TestDrive 'ConnectEnvNone'
        New-OERConfiguration -TenantAlias contoso -TenantId 'tid-contoso' -BasePath $Base | Out-Null

        Connect-OER -TenantAlias contoso -BasePath $Base

        $script:ConnectProfileNoEnvKeys | Should -Not -BeNullOrEmpty -Because 'the mock must have run, or the assertion below is vacuous'
        $script:ConnectProfileNoEnvKeys | Should -Not -Contain 'Environment'
    }
}

# -------------------------------------------------------------------------------------------------
# -Force (F12 tenant-switch-warning, Task 2): AzAuth keeps ONE credential per PowerShell process, and
# only Get-AzToken -Force rebuilds it. Initialize-OERAuth already exposes -ForceRefresh for that;
# this lever is the public way to ask for it from Connect-OER.
# -------------------------------------------------------------------------------------------------
Describe 'Connect-OER -Force' {
    It 'forwards -Force as ForceRefresh = $true to Initialize-OERAuth' {
        Mock -ModuleName $script:moduleName Initialize-OERAuth {
            param($TenantId, $AuthMethod, $ClientId, $ClientSecret, $Certificate, $CertificatePath,
                  $IncludeARM, $ClaimsChallenge, $ForceRefresh, $Environment)
            $script:ConnectForceSuppliedKeys         = @($PSBoundParameters.Keys)
            $script:ConnectForceSuppliedForceRefresh = $ForceRefresh
        }

        Connect-OER -TenantId 'contoso' -Interactive -Force

        # The key AND its value are asserted, not just that the mock ran: without the value
        # comparison, forwarding $Force itself (a [switch], not a [bool] $true) under the
        # ForceRefresh key would still satisfy a Contain-only assertion.
        $script:ConnectForceSuppliedKeys         | Should -Contain 'ForceRefresh'
        $script:ConnectForceSuppliedForceRefresh | Should -Be $true
    }

    # The key must be ABSENT, not present-and-$false, matching how -Environment is handled: the
    # "mock must have run" non-emptiness guard comes first so a silently-skipped mock cannot pass
    # this vacuously.
    It 'does NOT forward a ForceRefresh key at all when -Force is omitted' {
        Mock -ModuleName $script:moduleName Initialize-OERAuth {
            param($TenantId, $AuthMethod, $ClientId, $ClientSecret, $Certificate, $CertificatePath,
                  $IncludeARM, $ClaimsChallenge, $ForceRefresh, $Environment)
            $script:ConnectForceOmittedKeys = @($PSBoundParameters.Keys)
        }

        Connect-OER -TenantId 'contoso' -Interactive

        $script:ConnectForceOmittedKeys | Should -Not -BeNullOrEmpty -Because 'the mock must have run, or the assertion below is vacuous'
        $script:ConnectForceOmittedKeys | Should -Not -Contain 'ForceRefresh'
    }

    It 'accepts -Force on every credential parameter set' {
        # -Force carries NO [Parameter()] attribute, so unlike -Environment its OWN ParameterSets
        # metadata reports a single '__AllParameterSets' entry rather than one row per named set.
        # $Command.ParameterSets expands that membership per named set instead, which is what
        # actually proves "-Force binds together with every one of -TenantId's sets" -- the same
        # thing the -Environment test above proves for a parameter that IS declared per set.
        $Command = Get-Command -Name Connect-OER -Module $script:moduleName
        $TenantIdSets = @($Command.Parameters['TenantId'].ParameterSets.Keys | Sort-Object)
        $ForceSets = @(
            $Command.ParameterSets |
                Where-Object { $_.Name -in $TenantIdSets -and $_.Parameters.Name -contains 'Force' } |
                ForEach-Object { $_.Name } |
                Sort-Object
        )

        $ForceSets             | Should -Not -BeNullOrEmpty
        $ForceSets.Count       | Should -Be 6
        ($ForceSets -join ',') | Should -Be ($TenantIdSets -join ',')
    }

    It 'is a switch' {
        $Command = Get-Command -Name Connect-OER -Module $script:moduleName
        $Command.Parameters['Force'].ParameterType | Should -Be ([switch])
    }
}
