BeforeAll {
    Import-Module Omnicit.EntraRBAC -Force
    . "$PSScriptRoot/../TestHelpers/OERTransportTripwire.ps1"
    Install-OERTransportTripwire
}

AfterAll {
    try { Assert-OERTransportTripwire } finally { Uninstall-OERTransportTripwire }
}

# The helper makes the module's one network call outside the Microsoft Graph and Azure Resource Manager
# transports, and its one deliberately unauthenticated call: an OpenID discovery GET that turns a
# tenant named by domain into its tenant ID. Every test mocks Invoke-RestMethod at the module boundary
# (the transport tripwire refuses the real one), so no request is ever sent.
Describe 'Resolve-OERTenantDomain' {
    BeforeEach {
        InModuleScope Omnicit.EntraRBAC { $script:_OERTenantDomainCache = $null }
    }

    It 'returns the tenant ID from the issuer of the discovery document and asks the authority once' {
        Mock -ModuleName Omnicit.EntraRBAC Invoke-RestMethod {
            [pscustomobject]@{ issuer = 'https://login.microsoftonline.com/aaaaaaaa-1111-1111-1111-111111111111/v2.0' }
        }

        $Result = InModuleScope Omnicit.EntraRBAC {
            Resolve-OERTenantDomain -Domain 'contoso.onmicrosoft.com' -Environment 'Global'
        }

        $Result | Should -BeOfType ([string])
        $Result | Should -Be 'aaaaaaaa-1111-1111-1111-111111111111'
        Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-RestMethod -Times 1 -Exactly -ParameterFilter {
            $Uri -eq 'https://login.microsoftonline.com/contoso.onmicrosoft.com/v2.0/.well-known/openid-configuration' -and $Method -eq 'Get'
        }
    }

    It 'sends the lookup with no credential: Uri, Method, TimeoutSec and ErrorAction are the only parameters' {
        $script:CapturedBound = $null
        # No param() block on purpose. Measured on PowerShell 7.6.6 with Pester 6.2: a mock block with a
        # param() block binds only the parameters it declares and drops the rest without a word (a
        # [CmdletBinding()] one refuses them), so it cannot prove that a parameter was NOT passed. A
        # block with none receives every bound parameter in $args, each name as '-Name:' followed by its
        # value, whatever the cmdlet declares.
        Mock -ModuleName Omnicit.EntraRBAC Invoke-RestMethod {
            $Bound = [ordered]@{}
            for ($Index = 0; $Index -lt $args.Count; $Index++) {
                if ($args[$Index] -is [string] -and $args[$Index] -match '^-(?<Name>.+):$') {
                    $Bound[$Matches['Name']] = $args[$Index + 1]
                    $Index++
                }
            }
            $script:CapturedBound = $Bound
            [pscustomobject]@{ issuer = 'https://login.microsoftonline.com/aaaaaaaa-1111-1111-1111-111111111111/v2.0' }
        }
        # The parameter a bound -TimeoutSec is recorded under depends on the runtime: PowerShell 7.4 made
        # it an alias of ConnectionTimeoutSeconds, so ask the real cmdlet which name that is here.
        $TimeoutName = (Get-Command -Name Invoke-RestMethod -CommandType Cmdlet).ResolveParameter('TimeoutSec').Name

        InModuleScope Omnicit.EntraRBAC {
            $null = Resolve-OERTenantDomain -Domain 'contoso.onmicrosoft.com' -Environment 'Global'
        }

        $script:CapturedBound | Should -Not -BeNullOrEmpty -Because 'the mock must have recorded the call, or the comparison below proves nothing'
        (@($script:CapturedBound.Keys) | Sort-Object) -join ',' | Should -Be ((@('ErrorAction', 'Method', $TimeoutName, 'Uri') | Sort-Object) -join ',')
        $script:CapturedBound[$TimeoutName] | Should -Be 30
        [string]$script:CapturedBound['ErrorAction'] | Should -Be 'Stop'
    }

    It 'asks the authority once for the same domain named twice, the second time in upper case' {
        Mock -ModuleName Omnicit.EntraRBAC Invoke-RestMethod {
            [pscustomobject]@{ issuer = 'https://login.microsoftonline.com/aaaaaaaa-1111-1111-1111-111111111111/v2.0' }
        }

        $Results = InModuleScope Omnicit.EntraRBAC {
            @(
                Resolve-OERTenantDomain -Domain 'contoso.onmicrosoft.com' -Environment 'Global'
                Resolve-OERTenantDomain -Domain 'CONTOSO.ONMICROSOFT.COM' -Environment 'Global'
            )
        }

        @($Results).Count | Should -Be 2
        $Results[0] | Should -Be 'aaaaaaaa-1111-1111-1111-111111111111'
        $Results[1] | Should -Be $Results[0]
        Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-RestMethod -Times 1 -Exactly
    }

    It 'keeps one cache entry per cloud and domain, keyed with the domain in lower case' {
        Mock -ModuleName Omnicit.EntraRBAC Invoke-RestMethod {
            [pscustomobject]@{ issuer = 'https://login.microsoftonline.com/aaaaaaaa-1111-1111-1111-111111111111/v2.0' }
        }

        # The first call names the domain in mixed case: the key is built from that call, so a key that
        # kept the caller's case would show here (the cache itself ignores case, so a lookup alone would not).
        $Keys = @(InModuleScope Omnicit.EntraRBAC {
                $null = Resolve-OERTenantDomain -Domain 'Contoso.OnMicrosoft.com' -Environment 'Global'
                $null = Resolve-OERTenantDomain -Domain 'contoso.onmicrosoft.com' -Environment 'Global'
                $script:_OERTenantDomainCache.Keys
            })

        $Keys.Count | Should -Be 1
        # The two terms of the key are separated by a line feed.
        $Keys[0] | Should -BeExactly ('Global{0}contoso.onmicrosoft.com' -f [char]10)
        Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-RestMethod -Times 1 -Exactly
    }

    It 'asks the authority of the named sovereign cloud, and caches per cloud' {
        $Hosts = InModuleScope Omnicit.EntraRBAC {
            @{
                USGov  = (Get-OERCloudEndpoint -Environment 'USGov').AuthorityHost
                Global = (Get-OERCloudEndpoint -Environment 'Global').AuthorityHost
            }
        }
        $UsGovHost = [string]$Hosts.USGov
        $GlobalHost = [string]$Hosts.Global
        $UsGovHost | Should -Not -BeNullOrEmpty
        $UsGovHost | Should -Not -Be $GlobalHost -Because 'the two clouds must have different authorities, or the assertions below prove nothing'

        Mock -ModuleName Omnicit.EntraRBAC Invoke-RestMethod {
            [pscustomobject]@{ issuer = 'https://login.microsoftonline.com/aaaaaaaa-1111-1111-1111-111111111111/v2.0' }
        }

        InModuleScope Omnicit.EntraRBAC {
            $null = Resolve-OERTenantDomain -Domain 'contoso.onmicrosoft.com' -Environment 'USGov'
            $null = Resolve-OERTenantDomain -Domain 'contoso.onmicrosoft.com' -Environment 'USGov'
        }
        Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-RestMethod -Times 1 -Exactly -ParameterFilter {
            $Uri.OriginalString.StartsWith($UsGovHost) -and $Uri.OriginalString.EndsWith('/contoso.onmicrosoft.com/v2.0/.well-known/openid-configuration')
        }
        Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-RestMethod -Times 0 -ParameterFilter {
            $Uri.OriginalString.StartsWith($GlobalHost)
        }

        InModuleScope Omnicit.EntraRBAC {
            $null = Resolve-OERTenantDomain -Domain 'contoso.onmicrosoft.com' -Environment 'Global'
        }
        Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-RestMethod -Times 1 -Exactly -ParameterFilter {
            $Uri.OriginalString.StartsWith($GlobalHost)
        }
        Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-RestMethod -Times 2 -Exactly
    }

    It 'throws an InvalidOperationException naming the domain on a 400 answer, and caches no failure' {
        Mock -ModuleName Omnicit.EntraRBAC Invoke-RestMethod {
            throw [System.Exception]::new('Response status code does not indicate success: 400 (Bad Request).')
        }

        $Thrown = InModuleScope Omnicit.EntraRBAC {
            try { Resolve-OERTenantDomain -Domain 'contoso.onmicrosoft.com' -Environment 'Global'; $null } catch { $PSItem.Exception }
        }

        $Thrown | Should -BeOfType ([System.InvalidOperationException])
        $Thrown.Message | Should -BeLike "*'contoso.onmicrosoft.com'*"
        $Thrown.Message | Should -BeLike '*400*'
        $Thrown.InnerException | Should -Not -BeNullOrEmpty
        $Thrown.InnerException.Message | Should -BeLike '*400 (Bad Request)*'

        $Again = InModuleScope Omnicit.EntraRBAC {
            try { Resolve-OERTenantDomain -Domain 'contoso.onmicrosoft.com' -Environment 'Global'; $null } catch { $PSItem.Exception }
        }
        $Again | Should -BeOfType ([System.InvalidOperationException])
        Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-RestMethod -Times 2 -Exactly
    }

    It 'resolves the domain on the next call after a failure, since a failure is not cached' {
        Mock -ModuleName Omnicit.EntraRBAC Invoke-RestMethod {
            throw [System.Exception]::new('Response status code does not indicate success: 503 (Service Unavailable).')
        }
        $Failed = InModuleScope Omnicit.EntraRBAC {
            try { Resolve-OERTenantDomain -Domain 'contoso.onmicrosoft.com' -Environment 'Global'; $null } catch { $PSItem.Exception }
        }
        $Failed | Should -BeOfType ([System.InvalidOperationException])

        Mock -ModuleName Omnicit.EntraRBAC Invoke-RestMethod {
            [pscustomobject]@{ issuer = 'https://login.microsoftonline.com/aaaaaaaa-1111-1111-1111-111111111111/v2.0' }
        }
        $Result = InModuleScope Omnicit.EntraRBAC {
            Resolve-OERTenantDomain -Domain 'contoso.onmicrosoft.com' -Environment 'Global'
        }

        $Result | Should -Be 'aaaaaaaa-1111-1111-1111-111111111111'
        Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-RestMethod -Times 2 -Exactly
    }

    It 'throws when the document carries the template issuer that names no tenant' {
        Mock -ModuleName Omnicit.EntraRBAC Invoke-RestMethod {
            [pscustomobject]@{ issuer = 'https://login.microsoftonline.com/{tenantid}/v2.0' }
        }

        $Thrown = InModuleScope Omnicit.EntraRBAC {
            try { Resolve-OERTenantDomain -Domain 'common' -Environment 'Global'; $null } catch { $PSItem.Exception }
        }

        $Thrown | Should -BeOfType ([System.InvalidOperationException])
        $Thrown.Message | Should -BeLike '*names no tenant ID*'
        $Thrown.Message | Should -BeLike "*'common'*"
        Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-RestMethod -Times 1 -Exactly
    }

    It 'throws when the document has no issuer' {
        Mock -ModuleName Omnicit.EntraRBAC Invoke-RestMethod {
            [pscustomobject]@{ authorization_endpoint = 'https://login.microsoftonline.com/common/oauth2/v2.0/authorize' }
        }

        $Thrown = InModuleScope Omnicit.EntraRBAC {
            try { Resolve-OERTenantDomain -Domain 'contoso.onmicrosoft.com' -Environment 'Global'; $null } catch { $PSItem.Exception }
        }

        $Thrown | Should -BeOfType ([System.InvalidOperationException])
        $Thrown.Message | Should -BeLike '*names no tenant ID*'
    }

    It 'throws when the answer is empty' {
        Mock -ModuleName Omnicit.EntraRBAC Invoke-RestMethod { $null }

        $Thrown = InModuleScope Omnicit.EntraRBAC {
            try { Resolve-OERTenantDomain -Domain 'contoso.onmicrosoft.com' -Environment 'Global'; $null } catch { $PSItem.Exception }
        }

        $Thrown | Should -BeOfType ([System.InvalidOperationException])
        $Thrown.Message | Should -BeLike '*names no tenant ID*'
    }

    It 'throws when the first segment of the issuer is not a tenant ID' {
        Mock -ModuleName Omnicit.EntraRBAC Invoke-RestMethod {
            [pscustomobject]@{ issuer = 'https://login.microsoftonline.com/contoso.onmicrosoft.com/v2.0' }
        }

        $Thrown = InModuleScope Omnicit.EntraRBAC {
            try { Resolve-OERTenantDomain -Domain 'contoso.onmicrosoft.com' -Environment 'Global'; $null } catch { $PSItem.Exception }
        }

        $Thrown | Should -BeOfType ([System.InvalidOperationException])
        $Thrown.Message | Should -BeLike '*names no tenant ID*'
    }

    It 'throws when the issuer is not an absolute URI' {
        Mock -ModuleName Omnicit.EntraRBAC Invoke-RestMethod {
            [pscustomobject]@{ issuer = 'not-a-uri' }
        }

        $Thrown = InModuleScope Omnicit.EntraRBAC {
            try { Resolve-OERTenantDomain -Domain 'contoso.onmicrosoft.com' -Environment 'Global'; $null } catch { $PSItem.Exception }
        }

        $Thrown | Should -BeOfType ([System.InvalidOperationException])
        $Thrown.Message | Should -BeLike '*names no tenant ID*'
    }

    It 'scrubs the failed request record first in its catch' {
        Mock -ModuleName Omnicit.EntraRBAC Remove-OERErrorRecord { }
        Mock -ModuleName Omnicit.EntraRBAC Invoke-RestMethod {
            throw [System.Exception]::new('Response status code does not indicate success: 400 (Bad Request).')
        }

        $Thrown = InModuleScope Omnicit.EntraRBAC {
            try { Resolve-OERTenantDomain -Domain 'contoso.onmicrosoft.com' -Environment 'Global'; $null } catch { $PSItem.Exception }
        }

        $Thrown | Should -BeOfType ([System.InvalidOperationException]) -Because 'the failing request path must have been reached, or the scrub assertion below proves nothing'
        Should -Invoke -ModuleName Omnicit.EntraRBAC Remove-OERErrorRecord -Times 1 -Exactly
    }

    It 'escapes a domain that would change the path into one path segment' {
        Mock -ModuleName Omnicit.EntraRBAC Invoke-RestMethod {
            [pscustomobject]@{ issuer = 'https://login.microsoftonline.com/aaaaaaaa-1111-1111-1111-111111111111/v2.0' }
        }

        InModuleScope Omnicit.EntraRBAC {
            $null = Resolve-OERTenantDomain -Domain 'contoso.onmicrosoft.com/../x' -Environment 'Global'
        }

        # The positive assertion comes first: it proves the request was made, so the negative one after
        # it cannot pass for want of a request.
        Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-RestMethod -Times 1 -Exactly -ParameterFilter {
            $Uri.OriginalString.EndsWith('/contoso.onmicrosoft.com%2F..%2Fx/v2.0/.well-known/openid-configuration')
        }
        Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-RestMethod -Times 0 -ParameterFilter {
            $Uri.OriginalString -like '*onmicrosoft.com/..*'
        }
    }

    Context 'when the authority answers with a JSON body' {
        It 'names the error and the AADSTS code of a refused lookup in the message' {
            Mock -ModuleName Omnicit.EntraRBAC Invoke-RestMethod {
                $Err = [System.Management.Automation.ErrorRecord]::new(
                    [System.Exception]::new('Response status code does not indicate success: 400 (Bad Request).'),
                    'WebCmdletWebResponseException', [System.Management.Automation.ErrorCategory]::InvalidOperation, $null)
                $Err.ErrorDetails = [System.Management.Automation.ErrorDetails]::new('{"error":"invalid_tenant","error_description":"AADSTS90002: Tenant not found.","error_codes":[90002]}')
                throw $Err
            }

            $Thrown = InModuleScope Omnicit.EntraRBAC {
                try { Resolve-OERTenantDomain -Domain 'contoso.onmicrosoft.com' -Environment 'Global'; $null } catch { $PSItem.Exception }
            }

            $Thrown | Should -BeOfType ([System.InvalidOperationException])
            $Thrown.Message | Should -BeLike '*400 (Bad Request)*'
            $Thrown.Message | Should -BeLike '*invalid_tenant*'
            $Thrown.Message | Should -BeLike '*AADSTS90002*'
            $Thrown.InnerException.Message | Should -BeLike '*400 (Bad Request)*'
        }

        It 'names the error alone when the body carries no error code' {
            Mock -ModuleName Omnicit.EntraRBAC Invoke-RestMethod {
                $Err = [System.Management.Automation.ErrorRecord]::new(
                    [System.Exception]::new('Response status code does not indicate success: 400 (Bad Request).'),
                    'WebCmdletWebResponseException', [System.Management.Automation.ErrorCategory]::InvalidOperation, $null)
                $Err.ErrorDetails = [System.Management.Automation.ErrorDetails]::new('{"error":"invalid_request"}')
                throw $Err
            }

            $Thrown = InModuleScope Omnicit.EntraRBAC {
                try { Resolve-OERTenantDomain -Domain 'contoso.onmicrosoft.com' -Environment 'Global'; $null } catch { $PSItem.Exception }
            }

            $Thrown | Should -BeOfType ([System.InvalidOperationException])
            $Thrown.Message | Should -BeLike '*(invalid_request)*'
            $Thrown.Message | Should -Not -BeLike '*AADSTS*'
        }

        It 'keeps the plain message when the body is JSON without an error' {
            Mock -ModuleName Omnicit.EntraRBAC Invoke-RestMethod {
                $Err = [System.Management.Automation.ErrorRecord]::new(
                    [System.Exception]::new('Response status code does not indicate success: 400 (Bad Request).'),
                    'WebCmdletWebResponseException', [System.Management.Automation.ErrorCategory]::InvalidOperation, $null)
                $Err.ErrorDetails = [System.Management.Automation.ErrorDetails]::new('{"detail":"none of the usual fields"}')
                throw $Err
            }

            $Thrown = InModuleScope Omnicit.EntraRBAC {
                try { Resolve-OERTenantDomain -Domain 'contoso.onmicrosoft.com' -Environment 'Global'; $null } catch { $PSItem.Exception }
            }

            $Thrown | Should -BeOfType ([System.InvalidOperationException])
            $Thrown.Message | Should -BeLike '*400 (Bad Request)*'
            $Thrown.Message | Should -Not -BeLike '*none of the usual fields*'
        }

        It 'keeps the plain message, and scrubs first again, when the body is not JSON' {
            Mock -ModuleName Omnicit.EntraRBAC Remove-OERErrorRecord { }
            Mock -ModuleName Omnicit.EntraRBAC Invoke-RestMethod {
                $Err = [System.Management.Automation.ErrorRecord]::new(
                    [System.Exception]::new('Response status code does not indicate success: 502 (Bad Gateway).'),
                    'WebCmdletWebResponseException', [System.Management.Automation.ErrorCategory]::InvalidOperation, $null)
                $Err.ErrorDetails = [System.Management.Automation.ErrorDetails]::new('this is not JSON {')
                throw $Err
            }

            $Thrown = InModuleScope Omnicit.EntraRBAC {
                try { Resolve-OERTenantDomain -Domain 'contoso.onmicrosoft.com' -Environment 'Global'; $null } catch { $PSItem.Exception }
            }

            $Thrown | Should -BeOfType ([System.InvalidOperationException])
            $Thrown.Message | Should -BeLike '*502 (Bad Gateway)*'
            $Thrown.InnerException.Message | Should -BeLike '*502 (Bad Gateway)*'
            # One scrub for the request's own catch and one for the catch around the body parse.
            Should -Invoke -ModuleName Omnicit.EntraRBAC Remove-OERErrorRecord -Times 2 -Exactly
        }
    }
}
