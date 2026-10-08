BeforeAll {
    Import-Module Omnicit.EntraRBAC -Force
    . "$PSScriptRoot/../TestHelpers/OERTransportTripwire.ps1"
    Install-OERTransportTripwire
    . "$PSScriptRoot/../TestHelpers/OERConfirmHost.ps1"
}

AfterAll {
    try { Assert-OERTransportTripwire } finally { Uninstall-OERTransportTripwire }
}

Describe 'Invoke-OERArmRequest' {
    BeforeEach {
        InModuleScope Omnicit.EntraRBAC {
            $script:_OERAuthState = @{
                AuthMethod     = 'Interactive'
                TenantId       = 'organizations'
                ArmToken       = (ConvertTo-SecureString 'fake-arm-token' -AsPlainText -Force)
                ArmResourceUrl = 'https://management.azure.com/'
            }
        }
    }

    It 'returns the parsed JSON body on success' {
        InModuleScope Omnicit.EntraRBAC {
            Mock Invoke-WebRequest {
                [PSCustomObject]@{ StatusCode = 200; Content = '{"value":[{"id":"/subscriptions/abc"}]}' }
            }
            $Result = Invoke-OERArmRequest -Path '/subscriptions?api-version=2022-12-01'
            @($Result.value)[0].id | Should -Be '/subscriptions/abc'
            Should -Invoke Invoke-WebRequest -Times 1 -Exactly -ParameterFilter {
                $Method -eq 'GET' -and
                $Uri -eq 'https://management.azure.com/subscriptions?api-version=2022-12-01' -and
                $Headers.Authorization -like 'Bearer *' -and
                $SkipHttpErrorCheck -eq $true
            }
        }
    }

    It 'sends the cached bearer token to the ARM host' {
        InModuleScope Omnicit.EntraRBAC {
            Mock Invoke-WebRequest { [PSCustomObject]@{ StatusCode = 200; Content = '{}' } }
            $null = Invoke-OERArmRequest -Path '/subscriptions?api-version=2022-12-01'
            Should -Invoke Invoke-WebRequest -Times 1 -Exactly -ParameterFilter {
                $Headers.Authorization -eq 'Bearer fake-arm-token' -and
                $Uri -like 'https://management.azure.com/*'
            }
        }
    }

    It 'serializes -Body to a JSON payload with the json content type' {
        InModuleScope Omnicit.EntraRBAC {
            Mock Invoke-WebRequest { [PSCustomObject]@{ StatusCode = 201; Content = '{"id":"x"}' } }
            $null = Invoke-OERArmRequest -Method PUT -Path '/x?api-version=2022-04-01' -Body @{ properties = @{ principalId = 'p1' } }
            Should -Invoke Invoke-WebRequest -Times 1 -Exactly -ParameterFilter {
                $Method -eq 'PUT' -and
                ($Body | ConvertFrom-Json).properties.principalId -eq 'p1' -and
                $ContentType -eq 'application/json'
            }
        }
    }

    It 'returns $null for an empty 204 response' {
        InModuleScope Omnicit.EntraRBAC {
            Mock Invoke-WebRequest { [PSCustomObject]@{ StatusCode = 204; Content = '' } }
            Invoke-OERArmRequest -Method DELETE -Path '/x?api-version=2022-04-01' | Should -BeNullOrEmpty
        }
    }

    It 'throws a converted ErrorRecord on a non-2xx response' {
        InModuleScope Omnicit.EntraRBAC {
            Mock Invoke-WebRequest {
                [PSCustomObject]@{ StatusCode = 403; Content = '{"error":{"code":"AuthorizationFailed","message":"denied"}}' }
            }
            { Invoke-OERArmRequest -Path '/x?api-version=2022-12-01' } |
                Should -Throw -ErrorId 'AuthorizationFailed'
        }
    }

    It 'forces re-auth and retries once on 401 for interactive sessions' {
        InModuleScope Omnicit.EntraRBAC {
            $script:ArmCallCount = 0
            Mock Initialize-OERAuth { }
            Mock Invoke-WebRequest {
                $script:ArmCallCount++
                if ($script:ArmCallCount -eq 1) { [PSCustomObject]@{ StatusCode = 401; Content = '' } }
                else { [PSCustomObject]@{ StatusCode = 200; Content = '{"value":[]}' } }
            }
            $null = Invoke-OERArmRequest -Path '/subscriptions?api-version=2022-12-01'
            Should -Invoke Invoke-WebRequest -Times 2 -Exactly
            Should -Invoke Initialize-OERAuth -Times 1 -Exactly -ParameterFilter { $ForceRefresh -and $IncludeARM }
        }
    }

    It 'forwards the cached ClientId when force-refreshing after a 401' {
        InModuleScope Omnicit.EntraRBAC {
            $script:_OERAuthState = @{
                TenantId       = 'contoso.onmicrosoft.com'
                AuthMethod     = 'ManagedIdentity'
                ClientId       = 'aaaa0000-0000-0000-0000-000000000099'
                ArmToken       = (ConvertTo-SecureString 'token' -AsPlainText -Force)
                ArmTokenExpiry = [DateTime]::UtcNow.AddHours(1)
                ArmResourceUrl = 'https://management.azure.com'
            }
            $script:ArmCallCount = 0
            Mock Invoke-WebRequest {
                $script:ArmCallCount++
                if ($script:ArmCallCount -eq 1) { [PSCustomObject]@{ StatusCode = 401; Content = '{}' } }
                else { [PSCustomObject]@{ StatusCode = 200; Content = '{"id":"ok"}' } }
            }
            $script:CapturedRefreshParams = $null
            # An explicit param() block is required here: Pester's mock body does not populate
            # $PSBoundParameters unless the scriptblock declares matching parameters (verified --
            # without this, $PSBoundParameters.Keys is empty even though the splat was passed).
            Mock Initialize-OERAuth {
                param($TenantId, $AuthMethod, $ClientId, $ClientSecret, $Certificate, $CertificatePath, $IncludeARM, $ClaimsChallenge, $ForceRefresh)
                $script:CapturedRefreshParams = $PSBoundParameters
            }

            $null = Invoke-OERArmRequest -Path '/subscriptions?api-version=2022-12-01'

            $script:CapturedRefreshParams.ContainsKey('ClientId') | Should -BeTrue
            $script:CapturedRefreshParams['ClientId'] | Should -Be 'aaaa0000-0000-0000-0000-000000000099'
        }
    }

    It 'omits ClientId when the cached state has none' {
        InModuleScope Omnicit.EntraRBAC {
            $script:_OERAuthState = @{
                TenantId       = 'contoso.onmicrosoft.com'
                AuthMethod     = 'Interactive'
                ClientId       = $null
                ArmToken       = (ConvertTo-SecureString 'token' -AsPlainText -Force)
                ArmTokenExpiry = [DateTime]::UtcNow.AddHours(1)
                ArmResourceUrl = 'https://management.azure.com'
            }
            $script:ArmCallCount = 0
            Mock Invoke-WebRequest {
                $script:ArmCallCount++
                if ($script:ArmCallCount -eq 1) { [PSCustomObject]@{ StatusCode = 401; Content = '{}' } }
                else { [PSCustomObject]@{ StatusCode = 200; Content = '{"id":"ok"}' } }
            }
            $script:CapturedRefreshParams = $null
            # An explicit param() block is required here: Pester's mock body does not populate
            # $PSBoundParameters unless the scriptblock declares matching parameters (verified --
            # without this, $PSBoundParameters.Keys is empty even though the splat was passed).
            Mock Initialize-OERAuth {
                param($TenantId, $AuthMethod, $ClientId, $ClientSecret, $Certificate, $CertificatePath, $IncludeARM, $ClaimsChallenge, $ForceRefresh)
                $script:CapturedRefreshParams = $PSBoundParameters
            }

            $null = Invoke-OERArmRequest -Path '/subscriptions?api-version=2022-12-01'

            $script:CapturedRefreshParams.ContainsKey('ClientId') | Should -BeFalse
        }
    }

    It 'does not retry 401 for app-only sessions and throws a clear error' {
        InModuleScope Omnicit.EntraRBAC {
            $script:_OERAuthState.AuthMethod = 'ClientSecret'
            Mock Initialize-OERAuth { }
            Mock Invoke-WebRequest { [PSCustomObject]@{ StatusCode = 401; Content = '' } }
            { Invoke-OERArmRequest -Path '/subscriptions?api-version=2022-12-01' } |
                Should -Throw -ErrorId 'AppOnlyTokenRefreshUnsatisfiable'
            Should -Invoke Invoke-WebRequest -Times 1 -Exactly
            Should -Invoke Initialize-OERAuth -Times 0 -Exactly
        }
    }

    It 'wraps a transport-level exception as ArmTransportError without chaining or leaving the raw record' {
        $global:Error.Clear()
        InModuleScope Omnicit.EntraRBAC {
            $TransportException = [System.Exception]::new('socket failure carrying Authorization: Bearer LEAKED')
            Mock Invoke-WebRequest { throw $TransportException }

            $Caught = $null
            try {
                Invoke-OERArmRequest -Path '/subscriptions?api-version=2022-12-01'
            } catch {
                Remove-OERErrorRecord -Record $PSItem
                $Caught = $PSItem
            }

            $Caught.FullyQualifiedErrorId | Should -Match 'ArmTransportError'
            $Caught.Exception.InnerException | Should -BeNullOrEmpty
            @($global:Error | Where-Object { [object]::ReferenceEquals($PSItem.Exception, $TransportException) }) |
                Should -BeNullOrEmpty
        }
    }

    It 'converts a second 401 after the retry instead of looping' {
        InModuleScope Omnicit.EntraRBAC {
            Mock Initialize-OERAuth { }
            Mock Invoke-WebRequest { [PSCustomObject]@{ StatusCode = 401; Content = '' } }
            { Invoke-OERArmRequest -Path '/subscriptions?api-version=2022-12-01' } |
                Should -Throw -ErrorId 'Unauthorized'
            Should -Invoke Invoke-WebRequest -Times 2 -Exactly
            Should -Invoke Initialize-OERAuth -Times 1 -Exactly
        }
    }

    It 'aggregates pages across nextLink with -All, converting absolute URLs to paths' {
        InModuleScope Omnicit.EntraRBAC {
            $script:ArmCallCount = 0
            Mock Invoke-WebRequest {
                $script:ArmCallCount++
                if ($script:ArmCallCount -eq 1) {
                    [PSCustomObject]@{ StatusCode = 200; Content = '{"value":[{"id":"a"}],"nextLink":"https://management.azure.com/subscriptions?api-version=2022-12-01&$skipToken=t1"}' }
                } else {
                    [PSCustomObject]@{ StatusCode = 200; Content = '{"value":[{"id":"b"}]}' }
                }
            }
            $Result = Invoke-OERArmRequest -Path '/subscriptions?api-version=2022-12-01' -All
            @($Result.value).Count | Should -Be 2
            Should -Invoke Invoke-WebRequest -Times 1 -Exactly -ParameterFilter {
                $Uri -eq 'https://management.azure.com/subscriptions?api-version=2022-12-01&$skipToken=t1'
            }
        }
    }

    It 'throws the converted error when a later page fails during -All paging' {
        InModuleScope Omnicit.EntraRBAC {
            $script:ArmCallCount = 0
            Mock Invoke-WebRequest {
                $script:ArmCallCount++
                if ($script:ArmCallCount -eq 1) {
                    [PSCustomObject]@{ StatusCode = 200; Content = '{"value":[{"id":"a"}],"nextLink":"https://management.azure.com/subscriptions?api-version=2022-12-01&$skipToken=t1"}' }
                } else {
                    [PSCustomObject]@{ StatusCode = 500; Content = '{"error":{"code":"InternalServerError","message":"boom"}}' }
                }
            }
            { Invoke-OERArmRequest -Path '/subscriptions?api-version=2022-12-01' -All } |
                Should -Throw -ErrorId 'InternalServerError'
        }
    }

    It 'follows @nextLink (management group list shape) with -All' {
        InModuleScope Omnicit.EntraRBAC {
            $script:ArmCallCount = 0
            Mock Invoke-WebRequest {
                $script:ArmCallCount++
                if ($script:ArmCallCount -eq 1) {
                    [PSCustomObject]@{ StatusCode = 200; Content = '{"value":[{"id":"mg1"}],"@nextLink":"https://management.azure.com/providers/Microsoft.Management/managementGroups?api-version=2020-05-01&$skiptoken=t2"}' }
                } else {
                    [PSCustomObject]@{ StatusCode = 200; Content = '{"value":[{"id":"mg2"}],"@nextLink":null}' }
                }
            }
            $Result = Invoke-OERArmRequest -Path '/providers/Microsoft.Management/managementGroups?api-version=2020-05-01' -All
            @($Result.value).Count | Should -Be 2
        }
    }

    It 'force-refreshes and retries once when a PAGE fetch 401s, and does not refresh twice' {
        InModuleScope Omnicit.EntraRBAC {
            $script:_OERAuthState = @{
                TenantId       = 'contoso'
                AuthMethod     = 'Interactive'
                ClientId       = ''
                ArmToken       = [System.Net.NetworkCredential]::new('', 'tok').SecurePassword
                ArmTokenExpiry = [DateTime]::UtcNow.AddHours(1)
                ArmResourceUrl = 'https://management.azure.com'
            }
            Mock Initialize-OERAuth { }

            # Page 1 OK (with a nextLink), page 2 401 once, then OK after the refresh.
            $script:Call = 0
            Mock Invoke-WebRequest {
                $script:Call++
                switch ($script:Call) {
                    1 { [PSCustomObject]@{ StatusCode = 200; Content = '{"value":[{"id":"a"}],"nextLink":"https://management.azure.com/subs?api-version=2022-12-01&$skip=1"}' } }
                    2 { [PSCustomObject]@{ StatusCode = 401; Content = '{"error":{"code":"ExpiredAuthenticationToken"}}' } }
                    default { [PSCustomObject]@{ StatusCode = 200; Content = '{"value":[{"id":"b"}]}' } }
                }
            }

            $Result = Invoke-OERArmRequest -Path '/subscriptions?api-version=2022-12-01' -All

            @($Result.value).Count | Should -Be 2
            @($Result.value.id)    | Should -Be @('a', 'b')
            Should -Invoke Initialize-OERAuth -Times 1 -ParameterFilter { $ForceRefresh -and $IncludeARM }
            Should -Invoke Invoke-WebRequest -Times 3
        }
    }

    It 'surfaces an app-only page 401 as AppOnlyTokenRefreshUnsatisfiable instead of refreshing' {
        InModuleScope Omnicit.EntraRBAC {
            $script:_OERAuthState = @{
                TenantId       = 'contoso'
                AuthMethod     = 'ClientSecret'
                ClientId       = 'app-id'
                ArmToken       = [System.Net.NetworkCredential]::new('', 'tok').SecurePassword
                ArmTokenExpiry = [DateTime]::UtcNow.AddHours(1)
                ArmResourceUrl = 'https://management.azure.com'
            }
            Mock Initialize-OERAuth { }
            $script:Call = 0
            Mock Invoke-WebRequest {
                $script:Call++
                if ($script:Call -eq 1) {
                    [PSCustomObject]@{ StatusCode = 200; Content = '{"value":[{"id":"a"}],"nextLink":"https://management.azure.com/subs?api-version=2022-12-01&$skip=1"}' }
                } else {
                    [PSCustomObject]@{ StatusCode = 401; Content = '{"error":{"code":"ExpiredAuthenticationToken"}}' }
                }
            }

            { Invoke-OERArmRequest -Path '/subscriptions?api-version=2022-12-01' -All } |
                Should -Throw -ErrorId 'AppOnlyTokenRefreshUnsatisfiable'
            Should -Invoke Initialize-OERAuth -Times 0
        }
    }

    It 'budgets exactly one refresh across a two-page 401 walk, not one refresh per page' {
        InModuleScope Omnicit.EntraRBAC {
            $script:_OERAuthState = @{
                TenantId       = 'contoso'
                AuthMethod     = 'Interactive'
                ClientId       = ''
                ArmToken       = [System.Net.NetworkCredential]::new('', 'tok').SecurePassword
                ArmTokenExpiry = [DateTime]::UtcNow.AddHours(1)
                ArmResourceUrl = 'https://management.azure.com'
            }
            # Count refresh invocations directly in the mock body. Should -Invoke -Times can make
            # this assertion too, but ONLY with -Exactly: a bare -Times is "at least N" (Pester
            # 5.7.1 Mock.ps1) and would not catch a per-page refresh. Never drop -Exactly from one.
            # (-Times 0 is the single exception: Pester treats a zero count as exact either way.)
            # The counter is kept because it ALSO proves the mock body ran at all, which is the
            # control this test's "exactly one refresh" claim rests on.
            $script:RefreshCount = 0
            Mock Initialize-OERAuth { $script:RefreshCount++ }

            # Page 1 OK (nextLink), page 2 401 once then OK (nextLink), page 3 401 again. The single
            # per-call refresh budget was already spent recovering page 2, so page 3's 401 is NOT
            # retried -- it converts to a thrown error instead of triggering a second refresh.
            $script:Call = 0
            Mock Invoke-WebRequest {
                $script:Call++
                switch ($script:Call) {
                    1 { [PSCustomObject]@{ StatusCode = 200; Content = '{"value":[{"id":"a"}],"nextLink":"https://management.azure.com/subs?api-version=2022-12-01&$skip=1"}' } }
                    2 { [PSCustomObject]@{ StatusCode = 401; Content = '{"error":{"code":"ExpiredAuthenticationToken"}}' } }
                    3 { [PSCustomObject]@{ StatusCode = 200; Content = '{"value":[{"id":"b"}],"nextLink":"https://management.azure.com/subs?api-version=2022-12-01&$skip=2"}' } }
                    default { [PSCustomObject]@{ StatusCode = 401; Content = '{"error":{"code":"ExpiredAuthenticationToken"}}' } }
                }
            }

            { Invoke-OERArmRequest -Path '/subscriptions?api-version=2022-12-01' -All } |
                Should -Throw -ErrorId 'ExpiredAuthenticationToken'
            $script:RefreshCount | Should -Be 1
        }
    }

    It 'carries the response headers through the normalization to the status logic' {
        InModuleScope Omnicit.EntraRBAC {
            # The header value is proved to have SURVIVED by the only observable that depends on it:
            # a 429 whose Retry-After says 7 produces a 7-second wait. Without the Headers property
            # on the normalized shape there is no 7 to find, and the wait would be the exponential
            # fallback of 1 s instead.
            Mock Start-Sleep { }
            $script:ArmCallCount = 0
            Mock Invoke-WebRequest {
                $script:ArmCallCount++
                if ($script:ArmCallCount -eq 1) {
                    [PSCustomObject]@{
                        StatusCode = 429
                        Content    = '{"error":{"code":"TooManyRequests","message":"slow down"}}'
                        Headers    = @{ 'Retry-After' = @('7') }
                    }
                } else {
                    [PSCustomObject]@{ StatusCode = 200; Content = '{"value":[]}'; Headers = @{} }
                }
            }
            $null = Invoke-OERArmRequest -Path '/subscriptions?api-version=2022-12-01'
            Should -Invoke Start-Sleep -Times 1 -Exactly -ParameterFilter { $Seconds -eq 7 }
        }
    }

    It 'still forces re-auth and retries once on 401 when the response carries headers' {
        InModuleScope Omnicit.EntraRBAC {
            Mock Initialize-OERAuth { }
            $script:ArmCallCount = 0
            Mock Invoke-WebRequest {
                $script:ArmCallCount++
                if ($script:ArmCallCount -eq 1) {
                    [PSCustomObject]@{ StatusCode = 401; Content = ''; Headers = @{ 'x-ms-request-id' = @('r1') } }
                } else {
                    [PSCustomObject]@{ StatusCode = 200; Content = '{"value":[]}'; Headers = @{ 'x-ms-request-id' = @('r2') } }
                }
            }
            $null = Invoke-OERArmRequest -Path '/subscriptions?api-version=2022-12-01'
            Should -Invoke Invoke-WebRequest -Times 2 -Exactly
            Should -Invoke Initialize-OERAuth -Times 1 -Exactly -ParameterFilter { $ForceRefresh -and $IncludeARM }
        }
    }

    It 'still converts a non-2xx response that carries headers' {
        InModuleScope Omnicit.EntraRBAC {
            Mock Invoke-WebRequest {
                [PSCustomObject]@{
                    StatusCode = 403
                    Content    = '{"error":{"code":"AuthorizationFailed","message":"denied"}}'
                    Headers    = @{ 'x-ms-request-id' = @('r1'); 'Authorization' = @('Bearer LEAKED') }
                }
            }
            { Invoke-OERArmRequest -Path '/x?api-version=2022-12-01' } |
                Should -Throw -ErrorId 'AuthorizationFailed'
        }
    }

    It 'still aggregates pages when every page carries headers' {
        InModuleScope Omnicit.EntraRBAC {
            $script:ArmCallCount = 0
            Mock Invoke-WebRequest {
                $script:ArmCallCount++
                if ($script:ArmCallCount -eq 1) {
                    [PSCustomObject]@{
                        StatusCode = 200
                        Content    = '{"value":[{"id":"a"}],"nextLink":"https://management.azure.com/subscriptions?api-version=2022-12-01&$skipToken=t1"}'
                        Headers    = @{ 'x-ms-request-id' = @('r1') }
                    }
                } else {
                    [PSCustomObject]@{ StatusCode = 200; Content = '{"value":[{"id":"b"}]}'; Headers = @{ 'x-ms-request-id' = @('r2') } }
                }
            }
            $Result = Invoke-OERArmRequest -Path '/subscriptions?api-version=2022-12-01' -All
            @($Result.value).Count | Should -Be 2
        }
    }

    It 'never writes header material to the verbose stream' {
        InModuleScope Omnicit.EntraRBAC {
            Mock Invoke-WebRequest {
                [PSCustomObject]@{
                    StatusCode = 200
                    Content    = '{}'
                    Headers    = @{
                        'Authorization'              = @('Bearer NOT-A-REAL-TOKEN-super-secret')
                        'x-ms-request-id'            = @('11111111-2222-3333-4444-555555555555')
                        'client-request-id'          = @('66666666-7777-8888-9999-000000000000')
                        'x-ms-correlation-request-id' = @('abcdefab-cdef-abcd-efab-cdefabcdefab')
                    }
                }
            }
            $Verbose = (Invoke-OERArmRequest -Path '/x?api-version=2022-12-01' -Verbose 4>&1) |
                Where-Object { $_ -is [System.Management.Automation.VerboseRecord] }
            $Text = $Verbose.Message -join "`n"
            $Text | Should -Not -Match '(?i)bearer'
            $Text | Should -Not -Match '11111111-2222-3333-4444-555555555555'
            $Text | Should -Not -Match '66666666-7777-8888-9999-000000000000'
            $Text | Should -Not -Match 'abcdefab-cdef-abcd-efab-cdefabcdefab'
            # Control: the verbose stream was NOT empty, so the four negative assertions above had
            # something to be false about. Without this a wrapper that emitted nothing would pass.
            $Text | Should -Match '\[Invoke-OERArmRequest\] GET /x'
        }
    }
}

Describe 'Invoke-OERArmRequest verbose output' {
    BeforeEach {
        InModuleScope Omnicit.EntraRBAC {
            $script:_OERAuthState = @{
                AuthMethod     = 'Interactive'
                TenantId       = 'organizations'
                ArmToken       = (ConvertTo-SecureString 'fake-arm-token' -AsPlainText -Force)
                ArmResourceUrl = 'https://management.azure.com/'
            }
        }
    }

    It 'emits one verbose line naming the method and path' {
        InModuleScope Omnicit.EntraRBAC {
            Mock Invoke-WebRequest {
                [PSCustomObject]@{ StatusCode = 200; Content = '{"value":[]}' }
            }
            $Verbose = (Invoke-OERArmRequest -Method GET -Path '/subscriptions?api-version=2022-12-01' -Verbose 4>&1) |
                Where-Object { $_ -is [System.Management.Automation.VerboseRecord] }
            ($Verbose.Message -join "`n") | Should -Match '\[Invoke-OERArmRequest\] GET /subscriptions\?api-version=2022-12-01'
        }
    }

    It 'never writes the request body or a bearer token to the verbose stream' {
        InModuleScope Omnicit.EntraRBAC {
            $script:_OERAuthState.ArmToken = (ConvertTo-SecureString 'NOT-A-REAL-TOKEN-super-secret' -AsPlainText -Force)
            Mock Invoke-WebRequest {
                [PSCustomObject]@{ StatusCode = 200; Content = '{}' }
            }
            $Verbose = (Invoke-OERArmRequest -Method PUT -Path '/x?api-version=2022-04-01' -Body @{ secretish = 'do-not-log-me' } -Verbose 4>&1) |
                Where-Object { $_ -is [System.Management.Automation.VerboseRecord] }
            $Text = $Verbose.Message -join "`n"
            $Text | Should -Not -Match 'do-not-log-me'
            $Text | Should -Not -Match 'NOT-A-REAL-TOKEN-super-secret'
            $Text | Should -Not -Match '(?i)bearer'
        }
    }

    It 'emits a verbose line per page when paging' {
        InModuleScope Omnicit.EntraRBAC {
            $script:ArmCallCount = 0
            Mock Invoke-WebRequest {
                $script:ArmCallCount++
                if ($script:ArmCallCount -eq 1) {
                    [PSCustomObject]@{ StatusCode = 200; Content = '{"value":[1],"nextLink":"https://management.azure.com/next?api-version=2022-12-01"}' }
                } else {
                    [PSCustomObject]@{ StatusCode = 200; Content = '{"value":[2]}' }
                }
            }
            $Verbose = (Invoke-OERArmRequest -Path '/subscriptions?api-version=2022-12-01' -All -Verbose 4>&1) |
                Where-Object { $_ -is [System.Management.Automation.VerboseRecord] }
            @($Verbose | Where-Object { $_.Message -match '\[Invoke-OERArmRequest\] GET ' }).Count | Should -Be 2
        }
    }
}

Describe 'Invoke-OERArmRequest throttling' {
    BeforeEach {
        InModuleScope Omnicit.EntraRBAC {
            $script:_OERAuthState = @{
                AuthMethod     = 'Interactive'
                TenantId       = 'organizations'
                ArmToken       = (ConvertTo-SecureString 'fake-arm-token' -AsPlainText -Force)
                ArmResourceUrl = 'https://management.azure.com/'
            }
        }
    }

    It 'retries a 429 and honours Retry-After in seconds' {
        InModuleScope Omnicit.EntraRBAC {
            Mock Start-Sleep { }          # MUST be mocked: a real sleep makes the gate slow and flaky
            $script:Call = 0
            Mock Invoke-WebRequest {
                $script:Call++
                if ($script:Call -eq 1) {
                    [PSCustomObject]@{ StatusCode = 429; Content = '{"error":{"code":"TooManyRequests"}}'; Headers = @{ 'Retry-After' = @('60') } }
                } else {
                    [PSCustomObject]@{ StatusCode = 200; Content = '{"value":[{"id":"a"}]}'; Headers = @{} }
                }
            }
            $Result = Invoke-OERArmRequest -Path '/subscriptions?api-version=2022-12-01'
            @($Result.value)[0].id | Should -Be 'a'
            Should -Invoke Invoke-WebRequest -Times 2 -Exactly
            Should -Invoke Start-Sleep -Times 1 -Exactly -ParameterFilter { $Seconds -eq 60 }
        }
    }

    It 'reads Retry-After case-insensitively' {
        InModuleScope Omnicit.EntraRBAC {
            Mock Start-Sleep { }
            $script:Call = 0
            Mock Invoke-WebRequest {
                $script:Call++
                if ($script:Call -eq 1) {
                    [PSCustomObject]@{ StatusCode = 429; Content = '{}'; Headers = @{ 'retry-after' = @('11') } }
                } else {
                    [PSCustomObject]@{ StatusCode = 200; Content = '{}'; Headers = @{} }
                }
            }
            $null = Invoke-OERArmRequest -Path '/x?api-version=2022-12-01'
            Should -Invoke Start-Sleep -Times 1 -Exactly -ParameterFilter { $Seconds -eq 11 }
        }
    }

    It 'honours an HTTP-date Retry-After rather than reading it as zero seconds' {
        InModuleScope Omnicit.EntraRBAC {
            Mock Start-Sleep { }
            $HttpDate = [DateTime]::UtcNow.AddSeconds(45).ToString('R')
            $script:Call = 0
            Mock Invoke-WebRequest {
                $script:Call++
                if ($script:Call -eq 1) {
                    [PSCustomObject]@{ StatusCode = 429; Content = '{}'; Headers = @{ 'Retry-After' = @($HttpDate) } }
                } else {
                    [PSCustomObject]@{ StatusCode = 200; Content = '{}'; Headers = @{} }
                }
            }
            $null = Invoke-OERArmRequest -Path '/x?api-version=2022-12-01'
            # A ~45 s date, allowing for clock drift and rounding across the call.
            Should -Invoke Start-Sleep -Times 1 -Exactly -ParameterFilter { $Seconds -ge 40 -and $Seconds -le 46 }
        }
    }

    It 'falls back to exponential backoff when a 429 carries no Retry-After' {
        InModuleScope Omnicit.EntraRBAC {
            Mock Start-Sleep { }
            $script:Call = 0
            Mock Invoke-WebRequest {
                $script:Call++
                if ($script:Call -le 2) {
                    [PSCustomObject]@{ StatusCode = 429; Content = '{}'; Headers = @{} }
                } else {
                    [PSCustomObject]@{ StatusCode = 200; Content = '{}'; Headers = @{} }
                }
            }
            $null = Invoke-OERArmRequest -Path '/x?api-version=2022-12-01'
            # 2^0 = 1, then 2^1 = 2.
            Should -Invoke Start-Sleep -Times 2 -Exactly
            Should -Invoke Start-Sleep -Times 1 -Exactly -ParameterFilter { $Seconds -eq 1 }
            Should -Invoke Start-Sleep -Times 1 -Exactly -ParameterFilter { $Seconds -eq 2 }
        }
    }

    It 'falls back to exponential backoff when Retry-After cannot be parsed, never to zero' {
        InModuleScope Omnicit.EntraRBAC {
            Mock Start-Sleep { }
            $script:Call = 0
            Mock Invoke-WebRequest {
                $script:Call++
                if ($script:Call -eq 1) {
                    [PSCustomObject]@{ StatusCode = 429; Content = '{}'; Headers = @{ 'Retry-After' = @('not-a-number') } }
                } else {
                    [PSCustomObject]@{ StatusCode = 200; Content = '{}'; Headers = @{} }
                }
            }
            $null = Invoke-OERArmRequest -Path '/x?api-version=2022-12-01'
            Should -Invoke Start-Sleep -Times 1 -Exactly -ParameterFilter { $Seconds -eq 1 }
            Should -Invoke Start-Sleep -Times 0 -ParameterFilter { $Seconds -le 0 }
        }
    }

    It 'clamps a single wait to 120 seconds' {
        InModuleScope Omnicit.EntraRBAC {
            Mock Start-Sleep { }
            $script:Call = 0
            Mock Invoke-WebRequest {
                $script:Call++
                if ($script:Call -eq 1) {
                    [PSCustomObject]@{ StatusCode = 429; Content = '{}'; Headers = @{ 'Retry-After' = @('100000') } }
                } else {
                    [PSCustomObject]@{ StatusCode = 200; Content = '{}'; Headers = @{} }
                }
            }
            $null = Invoke-OERArmRequest -Path '/x?api-version=2022-12-01'
            # Unfiltered TOTAL first. Without it the two filtered assertions below only say "one wait
            # of 120 s happened and none over 120 s", which a path that ALSO slept some third, smaller
            # value would satisfy. Pinning the total to one closes that.
            Should -Invoke Start-Sleep -Times 1 -Exactly
            Should -Invoke Start-Sleep -Times 1 -Exactly -ParameterFilter { $Seconds -eq 120 }
            Should -Invoke Start-Sleep -Times 0 -ParameterFilter { $Seconds -gt 120 }
        }
    }

    It 'clamps a Retry-After of 0 up to one second so the budget is always spent' {
        InModuleScope Omnicit.EntraRBAC {
            Mock Start-Sleep { }
            $script:Call = 0
            Mock Invoke-WebRequest {
                $script:Call++
                if ($script:Call -eq 1) {
                    [PSCustomObject]@{ StatusCode = 429; Content = '{}'; Headers = @{ 'Retry-After' = @('0') } }
                } else {
                    [PSCustomObject]@{ StatusCode = 200; Content = '{}'; Headers = @{} }
                }
            }
            $null = Invoke-OERArmRequest -Path '/x?api-version=2022-12-01'
            # Unfiltered TOTAL first, for the same reason as the 120 s clamp above: a filtered
            # assertion alone cannot see a second sleep at some other value.
            Should -Invoke Start-Sleep -Times 1 -Exactly
            Should -Invoke Start-Sleep -Times 1 -Exactly -ParameterFilter { $Seconds -eq 1 }
        }
    }

    It 'retries a 503 that carries Retry-After' {
        InModuleScope Omnicit.EntraRBAC {
            Mock Start-Sleep { }
            $script:Call = 0
            Mock Invoke-WebRequest {
                $script:Call++
                if ($script:Call -eq 1) {
                    [PSCustomObject]@{ StatusCode = 503; Content = '{}'; Headers = @{ 'Retry-After' = @('5') } }
                } else {
                    [PSCustomObject]@{ StatusCode = 200; Content = '{"ok":true}'; Headers = @{} }
                }
            }
            $Result = Invoke-OERArmRequest -Path '/x?api-version=2022-12-01'
            $Result.ok | Should -BeTrue
            Should -Invoke Start-Sleep -Times 1 -Exactly -ParameterFilter { $Seconds -eq 5 }
        }
    }

    It 'does NOT retry a 503 with no Retry-After' {
        InModuleScope Omnicit.EntraRBAC {
            Mock Start-Sleep { }
            Mock Invoke-WebRequest {
                [PSCustomObject]@{ StatusCode = 503; Content = '{"error":{"code":"ServiceUnavailable","message":"down"}}'; Headers = @{} }
            }
            { Invoke-OERArmRequest -Path '/x?api-version=2022-12-01' } |
                Should -Throw -ErrorId 'ServiceUnavailable'
            Should -Invoke Invoke-WebRequest -Times 1 -Exactly
            Should -Invoke Start-Sleep -Times 0
        }
    }

    It 'does not retry an ordinary failure such as 403' {
        InModuleScope Omnicit.EntraRBAC {
            Mock Start-Sleep { }
            Mock Invoke-WebRequest {
                [PSCustomObject]@{ StatusCode = 403; Content = '{"error":{"code":"AuthorizationFailed","message":"denied"}}'; Headers = @{ 'Retry-After' = @('30') } }
            }
            { Invoke-OERArmRequest -Path '/x?api-version=2022-12-01' } |
                Should -Throw -ErrorId 'AuthorizationFailed'
            Should -Invoke Invoke-WebRequest -Times 1 -Exactly
            Should -Invoke Start-Sleep -Times 0
        }
    }

    It 'gives up when the per-REQUEST wait budget cannot cover the next wait, and says so' {
        InModuleScope Omnicit.EntraRBAC {
            Mock Start-Sleep { }
            # 120 s per wait (clamped from 300). 300 s of budget buys exactly two waits; the third
            # request's 120 s wait does not fit in the 60 s left, so the loop gives up.
            Mock Invoke-WebRequest {
                [PSCustomObject]@{ StatusCode = 429; Content = '{"error":{"code":"TooManyRequests"}}'; Headers = @{ 'Retry-After' = @('300') } }
            }
            # No -Verbose 4>&1 here on purpose: nothing reads the verbose stream in this test, and a
            # redirection inside a { } | Should -Throw scriptblock discards the records it captures,
            # so leaving it in would read as a capture that is not one.
            { Invoke-OERArmRequest -Path '/x?api-version=2022-12-01' } |
                Should -Throw -ErrorId 'TooManyRequests'
            Should -Invoke Start-Sleep -Times 2 -Exactly
            Should -Invoke Invoke-WebRequest -Times 3 -Exactly
        }
    }

    It 'names the per-REQUEST budget in the give-up verbose line' {
        InModuleScope Omnicit.EntraRBAC {
            Mock Start-Sleep { }
            Mock Invoke-WebRequest {
                [PSCustomObject]@{ StatusCode = 429; Content = '{"error":{"code":"TooManyRequests"}}'; Headers = @{ 'Retry-After' = @('300') } }
            }
            # Accumulate into a List as the records STREAM out, never with "$Records = <expr>":
            # the command ends by throwing, and an assignment whose right-hand side throws never
            # completes, so every verbose record emitted before the throw would be discarded and
            # the assertion below would run against an empty string -- passing only for -Not
            # matches and failing for real ones. The List is mutated in place, so what arrived
            # before the throw survives.
            $Records = [System.Collections.Generic.List[object]]::new()
            try { Invoke-OERArmRequest -Path '/x?api-version=2022-12-01' -Verbose 4>&1 | ForEach-Object { $Records.Add($PSItem) } }
            catch { Remove-OERErrorRecord -Record $PSItem }
            $Text = (@($Records | Where-Object { $_ -is [System.Management.Automation.VerboseRecord] }).Message) -join "`n"
            # Control first, so the give-up assertion below cannot pass on an empty capture.
            $Text | Should -Match 'Throttled'
            $Text | Should -Match 'per-REQUEST budget remain'
        }
    }

    It 'stops at the hard cap of 10 retries when Retry-After stays small' {
        InModuleScope Omnicit.EntraRBAC {
            Mock Start-Sleep { }
            Mock Invoke-WebRequest {
                [PSCustomObject]@{ StatusCode = 429; Content = '{"error":{"code":"TooManyRequests"}}'; Headers = @{ 'Retry-After' = @('1') } }
            }
            { Invoke-OERArmRequest -Path '/x?api-version=2022-12-01' } |
                Should -Throw -ErrorId 'TooManyRequests'
            # 10 waits of 1 s spends only 10 s of the 300 s budget: the cap is what binds, and
            # without it this server would be hammered ~300 times.
            Should -Invoke Start-Sleep -Times 10 -Exactly
            Should -Invoke Invoke-WebRequest -Times 11 -Exactly
        }
    }

    It 'backs off on the -All paging path too' {
        InModuleScope Omnicit.EntraRBAC {
            Mock Start-Sleep { }
            $script:Call = 0
            Mock Invoke-WebRequest {
                $script:Call++
                switch ($script:Call) {
                    1 { [PSCustomObject]@{ StatusCode = 200; Content = '{"value":[{"id":"a"}],"nextLink":"https://management.azure.com/subs?api-version=2022-12-01&$skip=1"}'; Headers = @{} } }
                    2 { [PSCustomObject]@{ StatusCode = 429; Content = '{}'; Headers = @{ 'Retry-After' = @('9') } } }
                    default { [PSCustomObject]@{ StatusCode = 200; Content = '{"value":[{"id":"b"}]}'; Headers = @{} } }
                }
            }
            $Result = Invoke-OERArmRequest -Path '/subscriptions?api-version=2022-12-01' -All
            @($Result.value.id) | Should -Be @('a', 'b')
            Should -Invoke Start-Sleep -Times 1 -Exactly -ParameterFilter { $Seconds -eq 9 }
        }
    }

    It 'gives each PAGE its own per-request budget while sharing the per-call deadline' {
        InModuleScope Omnicit.EntraRBAC {
            Mock Start-Sleep { }
            # Two pages, each throttled once for 120 s. A shared per-request budget would still
            # allow both; what this proves is that page 2 is not refused merely since page 1 spent
            # 120 s -- the per-REQUEST budget resets per page.
            $script:Call = 0
            Mock Invoke-WebRequest {
                $script:Call++
                switch ($script:Call) {
                    1 { [PSCustomObject]@{ StatusCode = 429; Content = '{}'; Headers = @{ 'Retry-After' = @('120') } } }
                    2 { [PSCustomObject]@{ StatusCode = 200; Content = '{"value":[{"id":"a"}],"nextLink":"https://management.azure.com/subs?api-version=2022-12-01&$skip=1"}'; Headers = @{} } }
                    3 { [PSCustomObject]@{ StatusCode = 429; Content = '{}'; Headers = @{ 'Retry-After' = @('120') } } }
                    default { [PSCustomObject]@{ StatusCode = 200; Content = '{"value":[{"id":"b"}]}'; Headers = @{} } }
                }
            }
            $Result = Invoke-OERArmRequest -Path '/subscriptions?api-version=2022-12-01' -All
            @($Result.value.id) | Should -Be @('a', 'b')
            Should -Invoke Start-Sleep -Times 2 -Exactly -ParameterFilter { $Seconds -eq 120 }
        }
    }

    It 'enforces the per-CALL deadline across pages and never returns a truncated collection' {
        InModuleScope Omnicit.EntraRBAC {
            Mock Start-Sleep { }
            # Every page answers 429 with a 120 s Retry-After forever. The per-request budget lets
            # each page spend at most 240 s (two waits; the third does not fit in the 60 s left), so
            # the 900 s per-CALL deadline binds on page 4 and the whole call fails. It must THROW,
            # not return the pages already aggregated.
            $script:Call = 0
            Mock Invoke-WebRequest {
                $script:Call++
                # Odd calls: a page that succeeds and points at the next. Even calls: a throttle.
                if ($script:Call % 2 -eq 1) {
                    [PSCustomObject]@{ StatusCode = 200; Content = '{"value":[{"id":"p"}],"nextLink":"https://management.azure.com/subs?api-version=2022-12-01&$skip=1"}'; Headers = @{} }
                } else {
                    [PSCustomObject]@{ StatusCode = 429; Content = '{"error":{"code":"TooManyRequests"}}'; Headers = @{ 'Retry-After' = @('120') } }
                }
            }
            { Invoke-OERArmRequest -Path '/subscriptions?api-version=2022-12-01' -All } |
                Should -Throw -ErrorId 'TooManyRequests'
            # 900 s of per-CALL deadline at 120 s a wait: 7 waits fit (840 s), the 8th does not.
            Should -Invoke Start-Sleep -Times 7 -Exactly
        }
    }

    It 'names the per-CALL deadline in the give-up verbose line' {
        InModuleScope Omnicit.EntraRBAC {
            Mock Start-Sleep { }
            $script:Call = 0
            Mock Invoke-WebRequest {
                $script:Call++
                if ($script:Call % 2 -eq 1) {
                    [PSCustomObject]@{ StatusCode = 200; Content = '{"value":[{"id":"p"}],"nextLink":"https://management.azure.com/subs?api-version=2022-12-01&$skip=1"}'; Headers = @{} }
                } else {
                    [PSCustomObject]@{ StatusCode = 429; Content = '{"error":{"code":"TooManyRequests"}}'; Headers = @{ 'Retry-After' = @('120') } }
                }
            }
            # Streamed into a List for the same reason as the per-REQUEST test above: the call ends
            # by throwing, so "$Records = <expr>" would leave $Records empty.
            $Records = [System.Collections.Generic.List[object]]::new()
            try { Invoke-OERArmRequest -Path '/subscriptions?api-version=2022-12-01' -All -Verbose 4>&1 | ForEach-Object { $Records.Add($PSItem) } }
            catch { Remove-OERErrorRecord -Record $PSItem }
            $Text = (@($Records | Where-Object { $_ -is [System.Management.Automation.VerboseRecord] }).Message) -join "`n"
            $Text | Should -Match 'per-CALL budget remain|per-CALL'
            # The line above also matches an ordinary retry line, which names both budgets. Pin the
            # GIVE-UP line the test is named for as well: only that one ends with "Giving up."
            $Text | Should -Match 'per-CALL budget remain\. Giving up\.'
        }
    }

    It 'emits one verbose line per retry naming the delay, the attempt and the value source' {
        InModuleScope Omnicit.EntraRBAC {
            Mock Start-Sleep { }
            $script:Call = 0
            Mock Invoke-WebRequest {
                $script:Call++
                if ($script:Call -eq 1) {
                    [PSCustomObject]@{ StatusCode = 429; Content = '{}'; Headers = @{ 'Retry-After' = @('30') } }
                } elseif ($script:Call -eq 2) {
                    [PSCustomObject]@{ StatusCode = 429; Content = '{}'; Headers = @{} }
                } else {
                    [PSCustomObject]@{ StatusCode = 200; Content = '{}'; Headers = @{} }
                }
            }
            $Verbose = (Invoke-OERArmRequest -Path '/x?api-version=2022-12-01' -Verbose 4>&1) |
                Where-Object { $_ -is [System.Management.Automation.VerboseRecord] }
            $Lines = @($Verbose.Message | Where-Object { $_ -match 'Throttled' })
            $Lines.Count | Should -Be 2
            $Lines[0] | Should -Match 'Waiting 30 s \(server-directed\) before retry 1'
            # Attempt 1 already spent, so the fallback exponent is 2^1 = 2.
            $Lines[1] | Should -Match 'Waiting 2 s \(exponential fallback\) before retry 2'
        }
    }

    It 'never writes header material to the verbose stream while backing off' {
        InModuleScope Omnicit.EntraRBAC {
            Mock Start-Sleep { }
            $script:Call = 0
            Mock Invoke-WebRequest {
                $script:Call++
                if ($script:Call -eq 1) {
                    [PSCustomObject]@{
                        StatusCode = 429
                        Content    = '{}'
                        Headers    = @{
                            'Retry-After'                 = @('3')
                            'Authorization'               = @('Bearer NOT-A-REAL-TOKEN-super-secret')
                            'x-ms-request-id'             = @('11111111-2222-3333-4444-555555555555')
                            'client-request-id'           = @('66666666-7777-8888-9999-000000000000')
                            'x-ms-ratelimit-remaining-subscription-reads' = @('11999')
                        }
                    }
                } else {
                    [PSCustomObject]@{ StatusCode = 200; Content = '{}'; Headers = @{} }
                }
            }
            $Verbose = (Invoke-OERArmRequest -Path '/x?api-version=2022-12-01' -Verbose 4>&1) |
                Where-Object { $_ -is [System.Management.Automation.VerboseRecord] }
            $Text = $Verbose.Message -join "`n"
            # Control first: the backoff DID run, so the negatives below are not vacuous.
            $Text | Should -Match 'Waiting 3 s'
            $Text | Should -Not -Match '(?i)bearer'
            $Text | Should -Not -Match '11111111-2222-3333-4444-555555555555'
            $Text | Should -Not -Match '66666666-7777-8888-9999-000000000000'
            $Text | Should -Not -Match 'x-ms-ratelimit'
            $Text | Should -Not -Match '11999'
        }
    }

    It 'does not let a throttled response consume the 401 refresh budget' {
        InModuleScope Omnicit.EntraRBAC {
            Mock Start-Sleep { }
            $script:RefreshCount = 0
            Mock Initialize-OERAuth { $script:RefreshCount++ }
            $script:Call = 0
            Mock Invoke-WebRequest {
                $script:Call++
                if ($script:Call -le 3) {
                    [PSCustomObject]@{ StatusCode = 429; Content = '{}'; Headers = @{ 'Retry-After' = @('2') } }
                } else {
                    [PSCustomObject]@{ StatusCode = 200; Content = '{}'; Headers = @{} }
                }
            }
            $null = Invoke-OERArmRequest -Path '/x?api-version=2022-12-01'
            $script:RefreshCount | Should -Be 0
            Should -Invoke Start-Sleep -Times 3 -Exactly
        }
    }

    It 'still allows exactly one 401 refresh after a throttle, and does not compound the two loops' {
        InModuleScope Omnicit.EntraRBAC {
            Mock Start-Sleep { }
            $script:RefreshCount = 0
            Mock Initialize-OERAuth { $script:RefreshCount++ }
            # 429 -> retry -> 401 -> refresh -> 401 again (budget spent) -> converts and throws.
            # If the refresh budget were per-throttle-attempt, or the throttle loop restarted the
            # refresh, this would spin.
            $script:Call = 0
            Mock Invoke-WebRequest {
                $script:Call++
                if ($script:Call -eq 1) {
                    [PSCustomObject]@{ StatusCode = 429; Content = '{}'; Headers = @{ 'Retry-After' = @('2') } }
                } else {
                    [PSCustomObject]@{ StatusCode = 401; Content = '{"error":{"code":"ExpiredAuthenticationToken"}}'; Headers = @{} }
                }
            }
            { Invoke-OERArmRequest -Path '/x?api-version=2022-12-01' } |
                Should -Throw -ErrorId 'ExpiredAuthenticationToken'
            $script:RefreshCount | Should -Be 1
            Should -Invoke Start-Sleep -Times 1 -Exactly
            # 1 (429) + 1 (401) + 1 (retry after refresh) = 3. Bounded.
            Should -Invoke Invoke-WebRequest -Times 3 -Exactly
        }
    }
}

Describe 'Invoke-OERArmRequest sign-in latch gate (A19)' {
    # A command whose sign-in was refused carries on past the refusal when no try is active up the
    # call stack, and would send the ARM token an earlier sign-in left. Initialize-OERAuth latches the
    # command that called it, and the wrapper refuses every request made while a latched command is on
    # the call stack. These tests latch a command the way Initialize-OERAuth does, through a stand-in
    # function that calls Lock-OERSignIn.
    BeforeAll {
        # Latches the innermost frame of the named command on the current call stack, as
        # Lock-OERSignIn latches the command that called Initialize-OERAuth. The 401 refresh calls
        # Initialize-OERAuth from Invoke-ArmCallWithRefresh, so a refused refresh latches that frame
        # (Ruling R5). A Pester mock body runs several frames further in than that caller, so a mock of
        # Initialize-OERAuth cannot call Lock-OERSignIn itself.
        function script:Lock-NamedFrame {
            param([Parameter(Mandatory)][string]$Name)
            $Frame = @(Get-PSCallStack | Where-Object { $null -ne $_.InvocationInfo -and $_.InvocationInfo.MyCommand.Name -eq $Name })[0]
            if ($null -eq $Frame) { throw "Lock-NamedFrame: no frame of '$Name' is on the call stack." }
            & (Get-Module Omnicit.EntraRBAC) {
                param($Invocation)
                if ($null -eq $script:_OERSignInLatch) {
                    $script:_OERSignInLatch = [System.Runtime.CompilerServices.ConditionalWeakTable[object, object]]::new()
                }
                $script:_OERSignInLatch.AddOrUpdate($Invocation, $true)
            } $Frame.InvocationInfo
        }
    }

    BeforeEach {
        InModuleScope Omnicit.EntraRBAC {
            $script:_OERAuthState = @{
                AuthMethod     = 'Interactive'
                TenantId       = '44444444-4444-4444-4444-444444444444'
                ArmToken       = (ConvertTo-SecureString 'NOT-A-REAL-TOKEN-arm' -AsPlainText -Force)
                ArmResourceUrl = 'https://management.azure.com/'
            }
        }
    }

    AfterEach {
        InModuleScope Omnicit.EntraRBAC { $script:_OERAuthState = $null }
    }

    It 'A1: refuses a request made for a latched command with SignInRefused, sending nothing' {
        Mock -ModuleName Omnicit.EntraRBAC Invoke-WebRequest { [PSCustomObject]@{ StatusCode = 200; Content = '{}' } }

        $Caught = InModuleScope Omnicit.EntraRBAC {
            function Initialize-StandIn { $null = Lock-OERSignIn }
            function Invoke-RefusedCommand {
                [CmdletBinding()]
                param()
                Initialize-StandIn
                $Caught = $null
                try { $null = Invoke-OERArmRequest -Path '/subscriptions?api-version=2022-12-01' } catch { $Caught = $PSItem }
                $Caught
            }
            Invoke-RefusedCommand
        }

        $Caught | Should -Not -BeNullOrEmpty
        $Caught.FullyQualifiedErrorId | Should -BeLike 'SignInRefused*'
        $Caught.CategoryInfo.Category | Should -Be 'AuthenticationError'
        $Caught.TargetObject | Should -BeExactly 'Invoke-RefusedCommand'
        Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-WebRequest -Times 0
    }

    It 'A2: refuses a request a latched command makes through a nested command whose own sign-in succeeded' {
        # The apply handlers' shape (Ruling R1): Get-OERRoleAssignment signs in again from the cache
        # and releases its OWN latch only.
        Mock -ModuleName Omnicit.EntraRBAC Invoke-WebRequest { [PSCustomObject]@{ StatusCode = 200; Content = '{}' } }

        $Caught = InModuleScope Omnicit.EntraRBAC {
            function Initialize-StandIn { Lock-OERSignIn }
            function Invoke-NestedCommand {
                [CmdletBinding()]
                param()
                $Own = Initialize-StandIn
                Unlock-OERSignIn -Invocation $Own
                $Caught = $null
                try { $null = Invoke-OERArmRequest -Path '/subscriptions?api-version=2022-12-01' } catch { $Caught = $PSItem }
                $Caught
            }
            function Invoke-RefusedCommand {
                [CmdletBinding()]
                param()
                $null = Initialize-StandIn
                Invoke-NestedCommand
            }
            Invoke-RefusedCommand
        }

        $Caught.FullyQualifiedErrorId | Should -BeLike 'SignInRefused*'
        $Caught.TargetObject | Should -BeExactly 'Invoke-RefusedCommand'
        Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-WebRequest -Times 0
    }

    It 'A3: sends the request when the latch table was never created' {
        Mock -ModuleName Omnicit.EntraRBAC Invoke-WebRequest { [PSCustomObject]@{ StatusCode = 200; Content = '{"id":"sent"}' } }

        $Result = InModuleScope Omnicit.EntraRBAC {
            Remove-Variable -Scope Script -Name _OERSignInLatch -ErrorAction Ignore
            Invoke-OERArmRequest -Path '/subscriptions?api-version=2022-12-01'
        }

        $Result.id | Should -Be 'sent'
        Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-WebRequest -Times 1 -Exactly
    }

    It 'A4: sends the request when the table holds only a command that is not on the call stack' {
        Mock -ModuleName Omnicit.EntraRBAC Invoke-WebRequest { [PSCustomObject]@{ StatusCode = 200; Content = '{"id":"sent"}' } }

        $R = InModuleScope Omnicit.EntraRBAC {
            function Initialize-StandIn { Lock-OERSignIn }
            function Invoke-RefusedCommand {
                [CmdletBinding()]
                param()
                Initialize-StandIn
            }
            function Invoke-LaterCommand {
                [CmdletBinding()]
                param()
                Invoke-OERArmRequest -Path '/subscriptions?api-version=2022-12-01'
            }
            # Held here, so the weak table cannot drop the entry before the call below.
            $Other = Invoke-RefusedCommand
            $Value = $null
            $Held = $script:_OERSignInLatch.TryGetValue($Other, [ref]$Value)
            @{ Held = $Held; Result = (Invoke-LaterCommand) }
        }

        # Not vacuous: the table holds the other command while the later one sends.
        $R.Held | Should -BeTrue
        $R.Result.id | Should -Be 'sent'
        Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-WebRequest -Times 1 -Exactly
    }

    It 'A5: refuses the 401 retry when the refresh leaves the wrapper latched' {
        Mock -ModuleName Omnicit.EntraRBAC Invoke-WebRequest { [PSCustomObject]@{ StatusCode = 401; Content = '{}' } }
        # The refresh's sign-in is refused: Initialize-OERAuth latches its caller, and that caller
        # carries on past the refusal when no try is active up the call stack.
        Mock -ModuleName Omnicit.EntraRBAC Initialize-OERAuth { Lock-NamedFrame -Name 'Invoke-ArmCallWithRefresh' }

        $Caught = InModuleScope Omnicit.EntraRBAC {
            $Caught = $null
            try { $null = Invoke-OERArmRequest -Path '/subscriptions?api-version=2022-12-01' } catch { $Caught = $PSItem }
            $Caught
        }

        $Caught.FullyQualifiedErrorId | Should -BeLike 'SignInRefused*'
        $Caught.TargetObject | Should -BeExactly 'Invoke-ArmCallWithRefresh'
        Should -Invoke -ModuleName Omnicit.EntraRBAC Initialize-OERAuth -Times 1 -Exactly -ParameterFilter { $ForceRefresh -and $IncludeARM }
        Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-WebRequest -Times 1 -Exactly
    }

    It 'A6: reads no ARM token from the state for a refused request, before the bearer would be built' {
        Mock -ModuleName Omnicit.EntraRBAC Invoke-WebRequest { [PSCustomObject]@{ StatusCode = 200; Content = '{}' } }

        $R = InModuleScope Omnicit.EntraRBAC {
            # The ARM token is read through a counting property, so the test sees whether the bearer
            # was materialized for a request that is never sent.
            $State = [pscustomobject]@{
                AuthMethod     = 'Interactive'
                TenantId       = '44444444-4444-4444-4444-444444444444'
                ArmResourceUrl = 'https://management.azure.com/'
                TokenReads     = 0
            }
            $State | Add-Member -MemberType ScriptProperty -Name ArmToken -Value {
                $this.TokenReads = $this.TokenReads + 1
                ConvertTo-SecureString 'NOT-A-REAL-TOKEN-arm' -AsPlainText -Force
            }
            $script:_OERAuthState = $State
            function Initialize-StandIn { $null = Lock-OERSignIn }
            function Invoke-RefusedCommand {
                [CmdletBinding()]
                param()
                Initialize-StandIn
                $Caught = $null
                try { $null = Invoke-OERArmRequest -Path '/subscriptions?api-version=2022-12-01' } catch { $Caught = $PSItem }
                $Caught
            }
            function Invoke-OpenCommand {
                [CmdletBinding()]
                param()
                $null = Invoke-OERArmRequest -Path '/subscriptions?api-version=2022-12-01'
            }
            $Caught = Invoke-RefusedCommand
            $ReadsRefused = $State.TokenReads
            Invoke-OpenCommand
            @{ Caught = $Caught; ReadsRefused = $ReadsRefused; ReadsOpen = $State.TokenReads - $ReadsRefused }
        }

        $R.Caught.FullyQualifiedErrorId | Should -BeLike 'SignInRefused*'
        $R.ReadsRefused | Should -Be 0
        # Not vacuous: the same state's token is read once for a request that is sent.
        $R.ReadsOpen | Should -Be 1
        Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-WebRequest -Times 1 -Exactly
    }

    It 'A7: refuses before any ARM request, outside any try, when a latched command runs the wrapper under -ErrorAction SilentlyContinue' {
        # The hit list is shared by the whole file, so each runspace test counts its own delta.
        $HitsBefore = @($global:OERTransportTripwireHits).Count
        $R = Invoke-OERWithConfirmAnswer -Answer '&No' -Script {
            Import-Module Omnicit.EntraRBAC
            & (Get-Module Omnicit.EntraRBAC) {
                $script:_OERAuthState = @{
                    AuthMethod     = 'Interactive'
                    TenantId       = '44444444-4444-4444-4444-444444444444'
                    ArmToken       = (ConvertTo-SecureString 'NOT-A-REAL-TOKEN-arm' -AsPlainText -Force)
                    ArmResourceUrl = 'https://management.azure.com/'
                }
            }
            # Under SilentlyContinue, with no try up the call stack, a function carries on past its own
            # throw: only the gate's return keeps the request from going out. No stub answers it, so a
            # request that went out would reach the tripwire.
            $Result = & (Get-Module Omnicit.EntraRBAC) {
                function Initialize-StandIn { $null = Lock-OERSignIn }
                function Invoke-RefusedCommand {
                    [CmdletBinding()]
                    param()
                    Initialize-StandIn
                    Invoke-OERArmRequest -Path '/subscriptions?api-version=2022-12-01' -ErrorAction SilentlyContinue
                }
                Invoke-RefusedCommand
            }
            'RESULT IS NULL: {0}' -f ($null -eq $Result)
            'ERROR IDS: {0}' -f ((@($Error) | ForEach-Object { [string]$_.FullyQualifiedErrorId }) -join ' | ')
            'END OF SCRIPT REACHED'
        }
        $R.Output | Should -Contain 'END OF SCRIPT REACHED'
        $R.Output | Should -Contain 'RESULT IS NULL: True'
        # The gate was reached: SilentlyContinue keeps the refusal off the error stream, not out of $Error.
        @($R.Output | Where-Object { "$_" -like 'ERROR IDS: *' })[0] | Should -Match 'SignInRefused'
        (@($global:OERTransportTripwireHits).Count - $HitsBefore) | Should -Be 0 -Because 'no ARM request may leave for a command whose sign-in was refused'
    }

    It 'A8: refuses the 401 retry, outside any try, when the refresh''s own sign-in fails, under -ErrorAction SilentlyContinue' {
        $HitsBefore = @($global:OERTransportTripwireHits).Count
        $R = Invoke-OERWithConfirmAnswer -Answer '&No' -Script {
            Import-Module Omnicit.EntraRBAC
            # An interactive state: a 401 takes the forced refresh through the real Initialize-OERAuth,
            # which latches its caller -- the wrapper's Invoke-ArmCallWithRefresh -- before the token call.
            & (Get-Module Omnicit.EntraRBAC) {
                $script:_OERAuthState = @{
                    TenantId = '44444444-4444-4444-4444-444444444444'; AuthMethod = 'Interactive'
                    ClientId = ''; Environment = 'Global'; GraphTokenExpiry = [DateTime]::UtcNow.AddHours(1)
                    ArmToken = ConvertTo-SecureString 'NOT-A-REAL-TOKEN-arm' -AsPlainText -Force
                    ArmTokenExpiry = [DateTime]::UtcNow.AddHours(1)
                    ArmResourceUrl = 'https://management.azure.com/'
                    ArmTokenTenantId = '44444444-4444-4444-4444-444444444444'
                }
            }
            $global:OERLatchArmCalls = 0
            $global:OERLatchTokenCalls = 0
            # MODULE-scope stubs, so neither call reaches the tripwire's global function; both are
            # removed again below, before the runspace check reads the module scope. Every request is
            # answered 401, and the token call fails, so the refresh's sign-in is refused. Hang guards:
            # exit past five calls.
            & (Get-Module Omnicit.EntraRBAC) {
                function script:Invoke-WebRequest {
                    [CmdletBinding()]
                    param($Method, $Uri, $Headers, [switch]$SkipHttpErrorCheck, $Body, $ContentType)
                    $global:OERLatchArmCalls++
                    if ($global:OERLatchArmCalls -gt 5) { exit }
                    [pscustomobject]@{ StatusCode = 401; Content = '{}'; Headers = @{} }
                }
                function script:Get-AzToken {
                    $global:OERLatchTokenCalls++
                    if ($global:OERLatchTokenCalls -gt 5) { exit }
                    throw [System.Exception]::new('AADSTS50076: interaction required.')
                }
            }
            $Result = & (Get-Module Omnicit.EntraRBAC) { Invoke-OERArmRequest -Path '/subscriptions?api-version=2022-12-01' -ErrorAction SilentlyContinue }
            # Unqualified, from the module scope: removes the nearest definition, which is the stub.
            & (Get-Module Omnicit.EntraRBAC) {
                Remove-Item -Path function:Invoke-WebRequest
                Remove-Item -Path function:Get-AzToken
            }
            $Restored = foreach ($Name in 'Invoke-WebRequest', 'Get-AzToken') {
                $Resolved = & (Get-Module Omnicit.EntraRBAC) { param($N) Get-Command -Name $N -CommandType Function -ErrorAction Ignore } $Name
                [bool]$Resolved -and $Resolved.ScriptBlock.ToString().Contains('OER-TRANSPORT-TRIPWIRE')
            }
            'TRIPWIRE RESTORED: {0}' -f (@($Restored) -notcontains $false)
            'RESULT IS NULL: {0}' -f ($null -eq $Result)
            'ARM CALLS: {0}' -f $global:OERLatchArmCalls
            'TOKEN CALLS: {0}' -f $global:OERLatchTokenCalls
            'ERROR IDS: {0}' -f ((@($Error) | ForEach-Object { [string]$_.FullyQualifiedErrorId }) -join ' | ')
            'END OF SCRIPT REACHED'
        }
        $R.Output | Should -Contain 'END OF SCRIPT REACHED'
        $R.Output | Should -Contain 'TRIPWIRE RESTORED: True'
        $R.Output | Should -Contain 'TOKEN CALLS: 1'
        # One request, the rejected one: the retry after the refused refresh never goes out.
        $R.Output | Should -Contain 'ARM CALLS: 1'
        $Ids = @($R.Output | Where-Object { "$_" -like 'ERROR IDS: *' })[0]
        $Ids | Should -Match 'GraphTokenAcquisitionFailed'
        $Ids | Should -Match 'SignInRefused'
        (@($global:OERTransportTripwireHits).Count - $HitsBefore) | Should -Be 0 -Because 'no request may leave over a refused refresh'
    }
}

Describe 'Invoke-OERArmRequest sign-in supersession gate (A20)' {
    # In a pipeline every begin block runs first, so a command's process block acts under the state a
    # later command's sign-in switched to -- with the ARM token that sign-in cached, for another tenant.
    # Initialize-OERAuth therefore remembers which identity each command signed in as, and the wrapper
    # refuses every request made while a command on the call stack remembers another identity than the
    # state carries. These tests remember an identity the way Initialize-OERAuth does, from a stand-in
    # command that calls Register-OERSignInIdentity with its own invocation, and then change the state
    # the way a later sign-in would.
    BeforeAll {
        # What a later command's successful sign-in leaves behind: the state names another tenant.
        function script:Switch-SupersessionTenant {
            & (Get-Module Omnicit.EntraRBAC) { $script:_OERAuthState.TenantId = '77777777-7777-7777-7777-777777777777' }
        }

        # Runs one probe in a runspace with no try: a stand-in command remembers the identity of an
        # interactive state, so a 401 takes the forced refresh, and calls the wrapper under
        # -ErrorAction SilentlyContinue. The fresh import holds no latch table, so only the
        # supersession gate can refuse.
        #   -Respond is pasted into a MODULE-scope Invoke-WebRequest stub, after its counter
        #     ($global:OERSupArmCalls) and its hang guard (exit past five calls). The stub is removed
        #     again, unqualified from the module scope, before the runspace check reads the module scope.
        #   -BeforeCall runs in the stand-in after it remembered its identity and before the request.
        # Initialize-OERAuth is replaced in the module scope by a sign-in that succeeds and changes the
        # state's identity: it latches its caller (the wrapper's Invoke-ArmCallWithRefresh), switches
        # the tenant, then releases and remembers that caller, exactly where the real function does.
        # Hang guard: exit past five calls. It is not a transport name, so the runspace check does not
        # read it, and the runspace is discarded with it. The records are read from $Error, cleared just
        # before the call: SilentlyContinue keeps a suppressed throw off the error stream, not out of
        # $Error.
        function script:Invoke-SupersessionArmProbe {
            param(
                [Parameter(Mandatory)][scriptblock]$Respond,
                [scriptblock]$BeforeCall = {}
            )
            $Text = @'
Import-Module Omnicit.EntraRBAC
& (Get-Module Omnicit.EntraRBAC) {
    $script:_OERAuthState = @{
        TenantId = '44444444-4444-4444-4444-444444444444'; AuthMethod = 'Interactive'
        ClientId = ''; Environment = 'Global'; GraphTokenExpiry = [DateTime]::UtcNow.AddHours(1)
        ArmToken = ConvertTo-SecureString 'NOT-A-REAL-TOKEN-arm' -AsPlainText -Force
        ArmTokenExpiry = [DateTime]::UtcNow.AddHours(1)
        ArmResourceUrl = 'https://management.azure.com/'
        ArmTokenTenantId = '44444444-4444-4444-4444-444444444444'
    }
}
$global:OERSupArmCalls = 0
$global:OERSupInitCalls = 0
& (Get-Module Omnicit.EntraRBAC) {
    function script:Invoke-WebRequest {
        [CmdletBinding()]
        param($Method, $Uri, $Headers, [switch]$SkipHttpErrorCheck, $Body, $ContentType)
        $global:OERSupArmCalls++
        if ($global:OERSupArmCalls -gt 5) { exit }
__RESPOND__
    }
    function script:Initialize-OERAuth {
        [CmdletBinding()]
        param($TenantId, $AuthMethod, $ClientId, $ClaimsChallenge, [switch]$ForceRefresh, [switch]$IncludeARM)
        $global:OERSupInitCalls++
        if ($global:OERSupInitCalls -gt 5) { exit }
        $Caller = Lock-OERSignIn
        $script:_OERAuthState.TenantId = '77777777-7777-7777-7777-777777777777'
        Unlock-OERSignIn -Invocation $Caller
        Register-OERSignInIdentity -Invocation $Caller
    }
}
$Error.Clear()
$Result = @(& (Get-Module Omnicit.EntraRBAC) {
    function Invoke-SignedInCommand {
        [CmdletBinding()]
        param()
        Register-OERSignInIdentity -Invocation $MyInvocation
__BEFORECALL__
        Invoke-OERArmRequest -Path '/subscriptions?api-version=2022-12-01' -ErrorAction SilentlyContinue
    }
    Invoke-SignedInCommand
})
$Records = @($Error | ForEach-Object { '{0} | {1}' -f [string]$_.FullyQualifiedErrorId, [string]$_.TargetObject })
# Unqualified, from the module scope: removes the nearest definition, which is the stub.
& (Get-Module Omnicit.EntraRBAC) { Remove-Item -Path function:Invoke-WebRequest }
$Resolved = & (Get-Module Omnicit.EntraRBAC) { Get-Command -Name Invoke-WebRequest -CommandType Function -ErrorAction Ignore }
'TRIPWIRE RESTORED: {0}' -f ([bool]$Resolved -and $Resolved.ScriptBlock.ToString().Contains('OER-TRANSPORT-TRIPWIRE'))
'RESULT COUNT: {0}' -f $Result.Count
'ARM CALLS: {0}' -f $global:OERSupArmCalls
'INIT CALLS: {0}' -f $global:OERSupInitCalls
foreach ($Record in $Records) { 'ERROR: {0}' -f $Record }
'END OF SCRIPT REACHED'
'@
            $Text = $Text.Replace('__RESPOND__', $Respond.ToString()).Replace('__BEFORECALL__', $BeforeCall.ToString())
            Invoke-OERWithConfirmAnswer -Answer '&No' -Script ([scriptblock]::Create($Text))
        }

        # The 'id | target' of every record a probe found in $Error.
        function script:Get-SupersessionProbeRecord {
            param([Parameter(Mandatory)]$Probe)
            @($Probe.Output | Where-Object { "$_" -like 'ERROR: *' } | ForEach-Object { "$_" -replace '^ERROR: ', '' })
        }
    }

    BeforeEach {
        InModuleScope Omnicit.EntraRBAC {
            $script:_OERAuthState = @{
                AuthMethod     = 'Interactive'
                TenantId       = '44444444-4444-4444-4444-444444444444'
                ClientId       = ''
                Environment    = 'Global'
                ArmToken       = (ConvertTo-SecureString 'NOT-A-REAL-TOKEN-arm' -AsPlainText -Force)
                ArmResourceUrl = 'https://management.azure.com/'
            }
        }
    }

    AfterEach {
        InModuleScope Omnicit.EntraRBAC {
            $script:_OERAuthState = $null
            Remove-Variable -Scope Script -Name _OERSignInIdentity -ErrorAction Ignore
        }
    }

    It 'B1: refuses a request made while a command runs whose remembered identity differs from the state, with SignInSuperseded, sending nothing' {
        Mock -ModuleName Omnicit.EntraRBAC Invoke-WebRequest { [PSCustomObject]@{ StatusCode = 200; Content = '{}' } }

        $Caught = InModuleScope Omnicit.EntraRBAC {
            function Invoke-SupersededCommand {
                [CmdletBinding()]
                param()
                Register-OERSignInIdentity -Invocation $MyInvocation
                # A later command's sign-in switches the state to another tenant.
                $script:_OERAuthState.TenantId = '77777777-7777-7777-7777-777777777777'
                $Caught = $null
                try { $null = Invoke-OERArmRequest -Path '/subscriptions?api-version=2022-12-01' } catch { $Caught = $PSItem }
                $Caught
            }
            Invoke-SupersededCommand
        }

        $Caught | Should -Not -BeNullOrEmpty
        $Caught.FullyQualifiedErrorId | Should -BeLike 'SignInSuperseded*'
        $Caught.CategoryInfo.Category | Should -Be 'AuthenticationError'
        $Caught.TargetObject | Should -BeExactly 'Invoke-SupersededCommand'
        $Caught.Exception.Message | Should -Match 'Run the commands as separate statements'
        Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-WebRequest -Times 0
    }

    It 'B2: refuses a request a nested command makes, naming the outer command whose remembered identity differs' {
        # The nested command signs in again without -TenantId, inherits the switched state and
        # remembers it, so its own frame matches the state and the walk must go on past it.
        Mock -ModuleName Omnicit.EntraRBAC Invoke-WebRequest { [PSCustomObject]@{ StatusCode = 200; Content = '{}' } }

        $R = InModuleScope Omnicit.EntraRBAC {
            function Invoke-NestedCommand {
                [CmdletBinding()]
                param()
                Register-OERSignInIdentity -Invocation $MyInvocation
                $Value = $null
                $Held = $script:_OERSignInIdentity.TryGetValue($MyInvocation, [ref]$Value)
                $Caught = $null
                try { $null = Invoke-OERArmRequest -Path '/subscriptions?api-version=2022-12-01' } catch { $Caught = $PSItem }
                @{ NestedHeld = $Held; NestedEquals = $Value -eq (Get-OERSignInIdentity); Caught = $Caught }
            }
            function Invoke-OuterCommand {
                [CmdletBinding()]
                param()
                Register-OERSignInIdentity -Invocation $MyInvocation
                $script:_OERAuthState.TenantId = '77777777-7777-7777-7777-777777777777'
                Invoke-NestedCommand
            }
            Invoke-OuterCommand
        }

        $R.NestedHeld | Should -BeTrue
        $R.NestedEquals | Should -BeTrue
        $R.Caught.FullyQualifiedErrorId | Should -BeLike 'SignInSuperseded*'
        $R.Caught.TargetObject | Should -BeExactly 'Invoke-OuterCommand'
        Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-WebRequest -Times 0
    }

    It 'B3: sends the request when the identity table was never created' {
        Mock -ModuleName Omnicit.EntraRBAC Invoke-WebRequest { [PSCustomObject]@{ StatusCode = 200; Content = '{"id":"sent"}' } }

        $R = InModuleScope Omnicit.EntraRBAC {
            Remove-Variable -Scope Script -Name _OERSignInIdentity -ErrorAction Ignore
            $Result = Invoke-OERArmRequest -Path '/subscriptions?api-version=2022-12-01'
            @{ Result = $Result; TableExists = $null -ne $script:_OERSignInIdentity }
        }

        $R.Result.id | Should -Be 'sent'
        $R.TableExists | Should -BeFalse
        Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-WebRequest -Times 1 -Exactly
    }

    It 'B4: sends the request when the remembering command''s identity equals the state' {
        Mock -ModuleName Omnicit.EntraRBAC Invoke-WebRequest { [PSCustomObject]@{ StatusCode = 200; Content = '{"id":"sent"}' } }

        $R = InModuleScope Omnicit.EntraRBAC {
            function Invoke-SignedInCommand {
                [CmdletBinding()]
                param()
                Register-OERSignInIdentity -Invocation $MyInvocation
                $Value = $null
                $Held = $script:_OERSignInIdentity.TryGetValue($MyInvocation, [ref]$Value)
                @{ Held = $Held; Result = (Invoke-OERArmRequest -Path '/subscriptions?api-version=2022-12-01') }
            }
            Invoke-SignedInCommand
        }

        # Not vacuous: the command remembers an identity, so it was compared.
        $R.Held | Should -BeTrue
        $R.Result.id | Should -Be 'sent'
        Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-WebRequest -Times 1 -Exactly
    }

    It 'B5: refuses the 401 retry when the refresh''s sign-in changes the state''s identity' {
        Mock -ModuleName Omnicit.EntraRBAC Invoke-WebRequest { [PSCustomObject]@{ StatusCode = 401; Content = '{}' } }
        Mock -ModuleName Omnicit.EntraRBAC Initialize-OERAuth { Switch-SupersessionTenant }

        $Caught = InModuleScope Omnicit.EntraRBAC {
            function Invoke-SignedInCommand {
                [CmdletBinding()]
                param()
                Register-OERSignInIdentity -Invocation $MyInvocation
                $Caught = $null
                try { $null = Invoke-OERArmRequest -Path '/subscriptions?api-version=2022-12-01' } catch { $Caught = $PSItem }
                $Caught
            }
            Invoke-SignedInCommand
        }

        $Caught.FullyQualifiedErrorId | Should -BeLike 'SignInSuperseded*'
        $Caught.TargetObject | Should -BeExactly 'Invoke-SignedInCommand'
        Should -Invoke -ModuleName Omnicit.EntraRBAC Initialize-OERAuth -Times 1 -Exactly -ParameterFilter { $ForceRefresh -and $IncludeARM }
        # The first request, the rejected one: the retry never goes out.
        Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-WebRequest -Times 1 -Exactly
    }

    It 'B6: reads no ARM token from the state for a refused request, before the bearer would be built' {
        Mock -ModuleName Omnicit.EntraRBAC Invoke-WebRequest { [PSCustomObject]@{ StatusCode = 200; Content = '{}' } }

        $R = InModuleScope Omnicit.EntraRBAC {
            # The ARM token is read through a counting property, so the test sees whether the bearer
            # was materialized for a request that is never sent.
            $State = [pscustomobject]@{
                AuthMethod     = 'Interactive'
                TenantId       = '44444444-4444-4444-4444-444444444444'
                ClientId       = ''
                Environment    = 'Global'
                ArmResourceUrl = 'https://management.azure.com/'
                TokenReads     = 0
            }
            $State | Add-Member -MemberType ScriptProperty -Name ArmToken -Value {
                $this.TokenReads = $this.TokenReads + 1
                ConvertTo-SecureString 'NOT-A-REAL-TOKEN-arm' -AsPlainText -Force
            }
            $script:_OERAuthState = $State
            function Invoke-SupersededCommand {
                [CmdletBinding()]
                param()
                Register-OERSignInIdentity -Invocation $MyInvocation
                $script:_OERAuthState.TenantId = '77777777-7777-7777-7777-777777777777'
                $Caught = $null
                try { $null = Invoke-OERArmRequest -Path '/subscriptions?api-version=2022-12-01' } catch { $Caught = $PSItem }
                $Caught
            }
            function Invoke-OpenCommand {
                [CmdletBinding()]
                param()
                $null = Invoke-OERArmRequest -Path '/subscriptions?api-version=2022-12-01'
            }
            $Caught = Invoke-SupersededCommand
            $ReadsRefused = $State.TokenReads
            Invoke-OpenCommand
            @{ Caught = $Caught; ReadsRefused = $ReadsRefused; ReadsOpen = $State.TokenReads - $ReadsRefused }
        }

        $R.Caught.FullyQualifiedErrorId | Should -BeLike 'SignInSuperseded*'
        $R.ReadsRefused | Should -Be 0
        # Not vacuous: the same state's token is read once for a request that is sent.
        $R.ReadsOpen | Should -Be 1
        Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-WebRequest -Times 1 -Exactly
    }

    It 'B7: reports a command that is latched as well as superseded as SignInRefused' {
        Mock -ModuleName Omnicit.EntraRBAC Invoke-WebRequest { [PSCustomObject]@{ StatusCode = 200; Content = '{}' } }

        $R = InModuleScope Omnicit.EntraRBAC {
            function Initialize-StandIn { $null = Lock-OERSignIn }
            function Invoke-RefusedCommand {
                [CmdletBinding()]
                param()
                Register-OERSignInIdentity -Invocation $MyInvocation
                Initialize-StandIn
                $script:_OERAuthState.TenantId = '77777777-7777-7777-7777-777777777777'
                $Caught = $null
                try { $null = Invoke-OERArmRequest -Path '/subscriptions?api-version=2022-12-01' } catch { $Caught = $PSItem }
                @{ Caught = $Caught; Supersession = Get-OERSignInSupersession }
            }
            Invoke-RefusedCommand
        }

        # Not vacuous: the supersession gate alone would refuse this command.
        $R.Supersession | Should -BeExactly 'Invoke-RefusedCommand'
        $R.Caught.FullyQualifiedErrorId | Should -BeLike 'SignInRefused*'
        Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-WebRequest -Times 0
    }

    It 'B8: refuses before any ARM request, outside any try, when a superseded command runs the wrapper under -ErrorAction SilentlyContinue' {
        # The hit list is shared by the whole file, so each runspace test counts its own delta.
        $HitsBefore = @($global:OERTransportTripwireHits).Count
        $R = Invoke-SupersessionArmProbe -Respond {
            [pscustomobject]@{ StatusCode = 200; Content = '{"id":"sent"}'; Headers = @{} }
        } -BeforeCall {
            # A later command's sign-in switches the state to another tenant.
            $script:_OERAuthState.TenantId = '77777777-7777-7777-7777-777777777777'
        }
        $R.Output | Should -Contain 'END OF SCRIPT REACHED'
        $R.Output | Should -Contain 'TRIPWIRE RESTORED: True'
        # Under SilentlyContinue, with no try up the call stack, a function carries on past its own
        # throw: only the gate's return keeps the bearer from being built and sent.
        $R.Output | Should -Contain 'ARM CALLS: 0'
        $R.Output | Should -Contain 'RESULT COUNT: 0'
        # The gate was reached: SilentlyContinue keeps the refusal off the error stream, not out of $Error.
        Get-SupersessionProbeRecord -Probe $R | Should -Be @('SignInSuperseded | Invoke-SignedInCommand')
        (@($global:OERTransportTripwireHits).Count - $HitsBefore) | Should -Be 0
    }

    It 'B9: refuses the 401 retry, outside any try, when the refresh''s sign-in changes the identity, under -ErrorAction SilentlyContinue' {
        $HitsBefore = @($global:OERTransportTripwireHits).Count
        $R = Invoke-SupersessionArmProbe -Respond {
            if ($global:OERSupArmCalls -eq 1) { return [pscustomobject]@{ StatusCode = 401; Content = '{}'; Headers = @{} } }
            [pscustomobject]@{ StatusCode = 200; Content = '{"id":"after-refresh"}'; Headers = @{} }
        }
        $R.Output | Should -Contain 'END OF SCRIPT REACHED'
        $R.Output | Should -Contain 'TRIPWIRE RESTORED: True'
        $R.Output | Should -Contain 'INIT CALLS: 1'
        # One request, the rejected one: the retry after the refresh never goes out.
        $R.Output | Should -Contain 'ARM CALLS: 1'
        $R.Output | Should -Contain 'RESULT COUNT: 0'
        # The refresh remembered the new identity for the wrapper's own frame; the walk went on past it.
        Get-SupersessionProbeRecord -Probe $R | Should -Be @('SignInSuperseded | Invoke-SignedInCommand')
        (@($global:OERTransportTripwireHits).Count - $HitsBefore) | Should -Be 0
    }
}

Describe 'Invoke-OERArmRequest stops at each of its own throws, outside any try (F3)' {
    # Under -ErrorAction SilentlyContinue or Ignore, with no try up the call stack, a function carries
    # on past its own throw to its next statement, and a throw inside a CATCH block resumes after the
    # whole try statement. Pester's It is a try, so each test runs the wrapper in a runspace with no
    # try and observes what the statement after the throw would do: send a second request, hand back
    # an error body or a partial collection as the answer, or raise a second record for the failure.
    #
    # None of the nested functions here is called inside a try, so a suppressed throw in one of them
    # also lets every caller above it carry on. A request that got no response therefore reaches the
    # top of the wrapper as no object at all, and the wrapper ends there instead of converting it.
    BeforeAll {
        # Runs one probe in a runspace with no try, on an ARM state Initialize-OERAuth did not build
        # (the fresh import holds no latch table, so the latch gate refuses nothing).
        #   -Respond is pasted into a MODULE-scope Invoke-WebRequest stub, after its counter
        #     ($global:OERStopArmCalls) and its hang guard (exit past five calls). The stub is removed
        #     again, unqualified from the module scope, before the runspace check reads the module
        #     scope.
        #   -Call runs in the module scope inside @(), so an explicit $null on the success channel
        #     counts as one item and nothing counts as none.
        # Initialize-OERAuth is replaced in the module scope by a counter that succeeds without signing
        # anything in (hang guard: exit past five calls): the retry after it would be sent. It is not a
        # transport name, so the runspace check does not read it, and the runspace is discarded with it.
        # The error ids are read from $Error, cleared just before the call: SilentlyContinue keeps a
        # suppressed throw off the error stream, not out of $Error.
        function script:Invoke-ArmStopProbe {
            param(
                [Parameter(Mandatory)][ValidateSet('Interactive', 'ClientCertificate')][string]$AuthMethod,
                [Parameter(Mandatory)][scriptblock]$Respond,
                [Parameter(Mandatory)][scriptblock]$Call
            )
            $Text = @'
Import-Module Omnicit.EntraRBAC
& (Get-Module Omnicit.EntraRBAC) {
    param($Method)
    $script:_OERAuthState = @{
        TenantId = '44444444-4444-4444-4444-444444444444'; AuthMethod = $Method
        ClientId = '33333333-3333-3333-3333-333333333333'; Environment = 'Global'
        ArmToken = ConvertTo-SecureString 'NOT-A-REAL-TOKEN-arm' -AsPlainText -Force
        ArmTokenExpiry = [DateTime]::UtcNow.AddHours(1)
        ArmResourceUrl = 'https://management.azure.com/'
    }
} '__AUTHMETHOD__'
$global:OERStopArmCalls = 0
$global:OERStopInitCalls = 0
& (Get-Module Omnicit.EntraRBAC) {
    function script:Invoke-WebRequest {
        [CmdletBinding()]
        param($Method, $Uri, $Headers, [switch]$SkipHttpErrorCheck, $Body, $ContentType)
        $global:OERStopArmCalls++
        if ($global:OERStopArmCalls -gt 5) { exit }
__RESPOND__
    }
    function script:Initialize-OERAuth {
        [CmdletBinding()]
        param($TenantId, $AuthMethod, $ClientId, $ClaimsChallenge, [switch]$ForceRefresh, [switch]$IncludeARM)
        $global:OERStopInitCalls++
        if ($global:OERStopInitCalls -gt 5) { exit }
    }
}
$Error.Clear()
$Result = @(& (Get-Module Omnicit.EntraRBAC) {
__CALL__
})
$Ids = @($Error | ForEach-Object { [string]$_.FullyQualifiedErrorId })
# Unqualified, from the module scope: removes the nearest definition, which is the stub.
& (Get-Module Omnicit.EntraRBAC) { Remove-Item -Path function:Invoke-WebRequest }
$Resolved = & (Get-Module Omnicit.EntraRBAC) { Get-Command -Name Invoke-WebRequest -CommandType Function -ErrorAction Ignore }
'TRIPWIRE RESTORED: {0}' -f ([bool]$Resolved -and $Resolved.ScriptBlock.ToString().Contains('OER-TRANSPORT-TRIPWIRE'))
'RESULT COUNT: {0}' -f $Result.Count
'ARM CALLS: {0}' -f $global:OERStopArmCalls
'INIT CALLS: {0}' -f $global:OERStopInitCalls
foreach ($Id in $Ids) { 'ERROR ID: {0}' -f $Id }
'END OF SCRIPT REACHED'
'@
            $Text = $Text.Replace('__AUTHMETHOD__', $AuthMethod).Replace('__RESPOND__', $Respond.ToString()).Replace('__CALL__', $Call.ToString())
            Invoke-OERWithConfirmAnswer -Answer '&No' -Script ([scriptblock]::Create($Text))
        }

        # The FullyQualifiedErrorId of every record a probe found in $Error.
        function script:Get-StopProbeErrorId {
            param([Parameter(Mandatory)]$Probe)
            @($Probe.Output | Where-Object { "$_" -like 'ERROR ID: *' } | ForEach-Object { "$_" -replace '^ERROR ID: ', '' })
        }
    }

    It 'S1: a request that gets no response leaves ArmTransportError as the only record, and nothing returned' {
        # Carrying on past the throw in Invoke-ArmCall's catch built a status-0 response out of the
        # request that never got one, and the wrapper converted that into a second record (ArmError).
        # Ending Invoke-ArmCall there hands its callers no object; converting THAT at the top of the
        # wrapper would raise a parameter-binding record instead.
        $HitsBefore = @($global:OERTransportTripwireHits).Count
        $R = Invoke-ArmStopProbe -AuthMethod Interactive -Respond {
            throw [System.Exception]::new('No such host is known.')
        } -Call {
            Invoke-OERArmRequest -Path '/subscriptions?api-version=2022-12-01' -ErrorAction SilentlyContinue
        }
        $R.Output | Should -Contain 'END OF SCRIPT REACHED'
        $R.Output | Should -Contain 'TRIPWIRE RESTORED: True'
        Get-StopProbeErrorId -Probe $R | Should -Be @('ArmTransportError')
        $R.Output | Should -Contain 'ARM CALLS: 1'
        $R.Output | Should -Contain 'RESULT COUNT: 0'
        (@($global:OERTransportTripwireHits).Count - $HitsBefore) | Should -Be 0
    }

    It 'S2: an app-only rejected token ends the call: one request, no refresh, nothing returned' {
        $HitsBefore = @($global:OERTransportTripwireHits).Count
        $R = Invoke-ArmStopProbe -AuthMethod ClientCertificate -Respond {
            if ($global:OERStopArmCalls -eq 1) { return [pscustomobject]@{ StatusCode = 401; Content = '{}'; Headers = @{} } }
            [pscustomobject]@{ StatusCode = 200; Content = '{"value":["after-refresh"]}'; Headers = @{} }
        } -Call {
            Invoke-OERArmRequest -Path '/subscriptions?api-version=2022-12-01' -ErrorAction SilentlyContinue
        }
        $R.Output | Should -Contain 'END OF SCRIPT REACHED'
        $R.Output | Should -Contain 'TRIPWIRE RESTORED: True'
        Get-StopProbeErrorId -Probe $R | Should -Be @('AppOnlyTokenRefreshUnsatisfiable')
        $R.Output | Should -Contain 'INIT CALLS: 0'
        $R.Output | Should -Contain 'ARM CALLS: 1'
        $R.Output | Should -Contain 'RESULT COUNT: 0'
        (@($global:OERTransportTripwireHits).Count - $HitsBefore) | Should -Be 0
    }

    It 'S3: a non-2xx answer ends the call without handing back its error body as data' {
        $HitsBefore = @($global:OERTransportTripwireHits).Count
        $R = Invoke-ArmStopProbe -AuthMethod Interactive -Respond {
            [pscustomobject]@{ StatusCode = 403; Content = '{"error":{"code":"AuthorizationFailed","message":"denied"}}'; Headers = @{} }
        } -Call {
            Invoke-OERArmRequest -Path '/subscriptions?api-version=2022-12-01' -ErrorAction SilentlyContinue
        }
        $R.Output | Should -Contain 'END OF SCRIPT REACHED'
        $R.Output | Should -Contain 'TRIPWIRE RESTORED: True'
        Get-StopProbeErrorId -Probe $R | Should -Be @('AuthorizationFailed')
        $R.Output | Should -Contain 'ARM CALLS: 1'
        $R.Output | Should -Contain 'RESULT COUNT: 0'
        (@($global:OERTransportTripwireHits).Count - $HitsBefore) | Should -Be 0
    }

    It 'S4: a non-2xx later page ends the paged read without the partial collection' {
        $HitsBefore = @($global:OERTransportTripwireHits).Count
        $R = Invoke-ArmStopProbe -AuthMethod Interactive -Respond {
            if ($global:OERStopArmCalls -eq 1) {
                return [pscustomobject]@{
                    StatusCode = 200; Headers = @{}
                    Content    = '{"value":["a","b"],"nextLink":"https://management.azure.com/subscriptions?api-version=2022-12-01&$skiptoken=p2"}'
                }
            }
            [pscustomobject]@{ StatusCode = 500; Content = '{"error":{"code":"InternalServerError","message":"boom"}}'; Headers = @{} }
        } -Call {
            Invoke-OERArmRequest -Path '/subscriptions?api-version=2022-12-01' -All -ErrorAction SilentlyContinue
        }
        $R.Output | Should -Contain 'END OF SCRIPT REACHED'
        $R.Output | Should -Contain 'TRIPWIRE RESTORED: True'
        Get-StopProbeErrorId -Probe $R | Should -Be @('InternalServerError')
        $R.Output | Should -Contain 'ARM CALLS: 2'
        # Nothing on the success channel: two items must never read as the whole collection.
        $R.Output | Should -Contain 'RESULT COUNT: 0'
        (@($global:OERTransportTripwireHits).Count - $HitsBefore) | Should -Be 0
    }

    It 'S5: a later page that gets no response leaves ArmTransportError as the only record, and nothing returned' {
        $HitsBefore = @($global:OERTransportTripwireHits).Count
        $R = Invoke-ArmStopProbe -AuthMethod Interactive -Respond {
            if ($global:OERStopArmCalls -eq 1) {
                return [pscustomobject]@{
                    StatusCode = 200; Headers = @{}
                    Content    = '{"value":["a","b"],"nextLink":"https://management.azure.com/subscriptions?api-version=2022-12-01&$skiptoken=p2"}'
                }
            }
            throw [System.Exception]::new('The response ended prematurely.')
        } -Call {
            Invoke-OERArmRequest -Path '/subscriptions?api-version=2022-12-01' -All -ErrorAction SilentlyContinue
        }
        $R.Output | Should -Contain 'END OF SCRIPT REACHED'
        $R.Output | Should -Contain 'TRIPWIRE RESTORED: True'
        Get-StopProbeErrorId -Probe $R | Should -Be @('ArmTransportError')
        $R.Output | Should -Contain 'ARM CALLS: 2'
        $R.Output | Should -Contain 'RESULT COUNT: 0'
        (@($global:OERTransportTripwireHits).Count - $HitsBefore) | Should -Be 0
    }
}

Describe 'Invoke-OERArmRequest sends nothing without an ARM token (BL-65, BL-96)' {
    # The wrapper sent "Authorization: Bearer " when the session held no ARM token: no state, no
    # ArmToken key, a null token and an empty or blank SecureString all materialize to an empty string.
    # A request without a token is refused after the two gates and before the send, with the existing
    # ArmTokenAcquisitionFailed (decision A8). These tests build each shape of "no token" by hand and
    # call the wrapper through the module scope, with Invoke-WebRequest mocked at the module boundary.
    BeforeAll {
        $script:NoTokenMessage = 'No Azure Resource Manager request was sent: the module''s session holds no Azure Resource Manager token. Run Connect-OER -IncludeARM to acquire one -- for an app-only session with its certificate or client secret -- and run the command again.'
        $script:NoTokenPath = '/subscriptions?api-version=2022-12-01'

        function script:New-ArmTestState {
            param([Parameter(Mandatory)][string]$Shape)
            $State = @{
                AuthMethod     = 'Interactive'
                TenantId       = '44444444-4444-4444-4444-444444444444'
                ClientId       = ''
                Environment    = 'Global'
                ArmResourceUrl = 'https://management.azure.com/'
            }
            switch ($Shape) {
                'NoKey' { }
                'Null' { $State.ArmToken = $null }
                'Empty' { $State.ArmToken = [securestring]::new() }
                'Blank' { $State.ArmToken = ConvertTo-SecureString '   ' -AsPlainText -Force }
                'WithToken' { $State.ArmToken = ConvertTo-SecureString 'NOT-A-REAL-TOKEN-arm' -AsPlainText -Force }
                'NoState' { return $null }
            }
            $State
        }

        function script:Set-ArmTestState {
            param([AllowNull()]$State)
            & (Get-Module Omnicit.EntraRBAC) { param($S) $script:_OERAuthState = $S } $State
        }

        # The record the wrapper throws, caught in the module scope; $null when it threw nothing.
        function script:Get-ArmRequestError {
            & (Get-Module Omnicit.EntraRBAC) {
                param($P)
                try { $null = Invoke-OERArmRequest -Path $P } catch { $PSItem }
            } $script:NoTokenPath
        }
    }

    AfterEach {
        InModuleScope Omnicit.EntraRBAC {
            $script:_OERAuthState = $null
            Remove-Variable -Scope Script -Name _OERSignInIdentity -ErrorAction Ignore
        }
    }

    It 'refuses a session with <Shape> as its ARM token before any request, with ArmTokenAcquisitionFailed' -ForEach @(
        @{ Shape = 'NoKey' }
        @{ Shape = 'Null' }
        @{ Shape = 'Empty' }
        @{ Shape = 'Blank' }
        @{ Shape = 'NoState' }
    ) {
        Mock -ModuleName Omnicit.EntraRBAC Invoke-WebRequest { [PSCustomObject]@{ StatusCode = 200; Content = '{}' } }
        Set-ArmTestState -State (New-ArmTestState -Shape $Shape)

        $Caught = Get-ArmRequestError

        Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-WebRequest -Times 0
        $Caught | Should -Not -BeNullOrEmpty
        $Caught.FullyQualifiedErrorId | Should -BeExactly 'ArmTokenAcquisitionFailed'
        $Caught.CategoryInfo.Category | Should -Be 'AuthenticationError'
        $Caught.TargetObject | Should -BeExactly $script:NoTokenPath
        $Caught.Exception.Message | Should -BeExactly $script:NoTokenMessage
    }

    It 'sends the request with its Bearer header, once, when the session holds a token' {
        Mock -ModuleName Omnicit.EntraRBAC Invoke-WebRequest { [PSCustomObject]@{ StatusCode = 200; Content = '{"id":"sent"}' } }
        Set-ArmTestState -State (New-ArmTestState -Shape 'WithToken')

        $Result = & (Get-Module Omnicit.EntraRBAC) { param($P) Invoke-OERArmRequest -Path $P } $script:NoTokenPath

        $Result.id | Should -Be 'sent'
        Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-WebRequest -Times 1 -Exactly -ParameterFilter {
            $Headers.Authorization -eq 'Bearer NOT-A-REAL-TOKEN-arm' -and
            $Uri -eq 'https://management.azure.com/subscriptions?api-version=2022-12-01'
        }
    }

    It 'reads SignInRefused, not ArmTokenAcquisitionFailed, for a latched command without a token (the gates come first)' {
        Mock -ModuleName Omnicit.EntraRBAC Invoke-WebRequest { [PSCustomObject]@{ StatusCode = 200; Content = '{}' } }
        Set-ArmTestState -State (New-ArmTestState -Shape 'NoKey')

        $Caught = InModuleScope Omnicit.EntraRBAC {
            function Initialize-StandIn { $null = Lock-OERSignIn }
            function Invoke-RefusedCommand {
                [CmdletBinding()]
                param()
                Initialize-StandIn
                $Caught = $null
                try { $null = Invoke-OERArmRequest -Path '/subscriptions?api-version=2022-12-01' } catch { $Caught = $PSItem }
                $Caught
            }
            Invoke-RefusedCommand
        }

        Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-WebRequest -Times 0
        $Caught | Should -Not -BeNullOrEmpty
        $Caught.FullyQualifiedErrorId | Should -BeLike 'SignInRefused*'
        $Caught.TargetObject | Should -BeExactly 'Invoke-RefusedCommand'
    }

    It 'reads SignInSuperseded, not ArmTokenAcquisitionFailed, for a superseded command without a token (the gates come first)' {
        Mock -ModuleName Omnicit.EntraRBAC Invoke-WebRequest { [PSCustomObject]@{ StatusCode = 200; Content = '{}' } }
        Set-ArmTestState -State (New-ArmTestState -Shape 'NoKey')

        $Caught = InModuleScope Omnicit.EntraRBAC {
            function Invoke-SupersededCommand {
                [CmdletBinding()]
                param()
                Register-OERSignInIdentity -Invocation $MyInvocation
                # A later command's sign-in switches the state to another tenant.
                $script:_OERAuthState.TenantId = '77777777-7777-7777-7777-777777777777'
                $Caught = $null
                try { $null = Invoke-OERArmRequest -Path '/subscriptions?api-version=2022-12-01' } catch { $Caught = $PSItem }
                $Caught
            }
            Invoke-SupersededCommand
        }

        Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-WebRequest -Times 0
        $Caught | Should -Not -BeNullOrEmpty
        $Caught.FullyQualifiedErrorId | Should -BeLike 'SignInSuperseded*'
        $Caught.TargetObject | Should -BeExactly 'Invoke-SupersededCommand'
    }

    It 'sends one request, then refuses the 401 retry, when the refresh leaves the session without an ARM token' {
        Mock -ModuleName Omnicit.EntraRBAC Invoke-WebRequest { [PSCustomObject]@{ StatusCode = 401; Content = '{}' } }
        # An interactive session whose forced refresh succeeds but leaves no ARM token behind: the
        # retry has nothing to send. Initialize-OERAuth is mocked, so nothing signs in.
        Mock -ModuleName Omnicit.EntraRBAC Initialize-OERAuth { & (Get-Module Omnicit.EntraRBAC) { $script:_OERAuthState.Remove('ArmToken') } }
        Set-ArmTestState -State (New-ArmTestState -Shape 'WithToken')

        $Caught = Get-ArmRequestError

        Should -Invoke -ModuleName Omnicit.EntraRBAC Initialize-OERAuth -Times 1 -Exactly -ParameterFilter { $ForceRefresh -and $IncludeARM }
        # The rejected first request only: the retry is never sent.
        Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-WebRequest -Times 1 -Exactly
        $Caught | Should -Not -BeNullOrEmpty
        $Caught.FullyQualifiedErrorId | Should -BeExactly 'ArmTokenAcquisitionFailed'
        $Caught.CategoryInfo.Category | Should -Be 'AuthenticationError'
        $Caught.TargetObject | Should -BeExactly $script:NoTokenPath
    }
}

Describe 'Invoke-OERArmRequest takes its host from the session''s cloud (BL-65)' {
    # A state that records no ArmResourceUrl used to send to the public cloud, whatever cloud the
    # session was in. The host now comes from the state's Environment. This is defence in depth: no
    # state the module builds holds a token without a url (Initialize-OERAuth clears ArmToken and
    # ArmResourceUrl together, and a state without a token is refused before the host matters), so
    # every state here is hand-built, with a token and without a recorded host.
    BeforeAll {
        function script:New-HostTestState {
            param([hashtable]$Extra = @{})
            $State = @{
                AuthMethod = 'Interactive'
                TenantId   = '44444444-4444-4444-4444-444444444444'
                ArmToken   = (ConvertTo-SecureString 'NOT-A-REAL-TOKEN-arm' -AsPlainText -Force)
            }
            foreach ($Key in $Extra.Keys) { $State[$Key] = $Extra[$Key] }
            $State
        }

        # The Uri the wrapper sent for a state, captured by the Invoke-WebRequest mock. A mock body does
        # not run in the module's script scope, so it hands the Uri over through a global of its own.
        function script:Get-SentArmUri {
            param([Parameter(Mandatory)]$State)
            $global:OERArmHostTestUri = $null
            & (Get-Module Omnicit.EntraRBAC) {
                param($S)
                $script:_OERAuthState = $S
                $null = Invoke-OERArmRequest -Path '/subscriptions?api-version=2022-12-01'
            } $State
            $global:OERArmHostTestUri
        }

        # The ARM resource url the cloud table holds for a cloud, read here and never hardcoded twice.
        function script:Get-CloudArmResource {
            param([Parameter(Mandatory)][string]$Cloud)
            & (Get-Module Omnicit.EntraRBAC) { param($C) (Get-OERCloudEndpoint -Environment $C).ArmResource } $Cloud
        }
    }

    BeforeEach {
        Mock -ModuleName Omnicit.EntraRBAC Invoke-WebRequest {
            $global:OERArmHostTestUri = [string]$Uri
            [PSCustomObject]@{ StatusCode = 200; Content = '{}' }
        }
    }

    AfterEach {
        Remove-Variable -Scope Global -Name OERArmHostTestUri -ErrorAction Ignore
        InModuleScope Omnicit.EntraRBAC { $script:_OERAuthState = $null }
    }

    It 'uses the USGov ARM host for a USGov session without ArmResourceUrl' {
        $Sent = Get-SentArmUri -State (New-HostTestState -Extra @{ Environment = 'USGov' })
        $Sent | Should -BeExactly 'https://management.usgovcloudapi.net/subscriptions?api-version=2022-12-01'
        Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-WebRequest -Times 1 -Exactly
    }

    It 'uses the China ARM host for a China session without ArmResourceUrl' {
        $Sent = Get-SentArmUri -State (New-HostTestState -Extra @{ Environment = 'China' })
        $Sent | Should -BeExactly 'https://management.chinacloudapi.cn/subscriptions?api-version=2022-12-01'
        Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-WebRequest -Times 1 -Exactly
    }

    It 'uses the table''s ARM host for a USGovDoD session without ArmResourceUrl' {
        $Expected = (Get-CloudArmResource -Cloud 'USGovDoD').TrimEnd('/')
        $Expected | Should -Not -BeNullOrEmpty
        $Sent = Get-SentArmUri -State (New-HostTestState -Extra @{ Environment = 'USGovDoD' })
        $Sent | Should -BeExactly "$Expected/subscriptions?api-version=2022-12-01"
        Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-WebRequest -Times 1 -Exactly
    }

    It 'uses the cloud''s host for a state with a token and an ArmResourceUrl key holding null (no recorded host)' {
        $Sent = Get-SentArmUri -State (New-HostTestState -Extra @{ Environment = 'USGov'; ArmResourceUrl = $null })
        $Sent | Should -BeExactly 'https://management.usgovcloudapi.net/subscriptions?api-version=2022-12-01'
    }

    It 'uses the public-cloud host for a session with <Case> as its Environment, never an exception' -ForEach @(
        @{ Case = 'no key'; Extra = @{} }
        @{ Case = 'an empty value'; Extra = @{ Environment = '' } }
        @{ Case = 'a null value'; Extra = @{ Environment = $null } }
    ) {
        $Sent = Get-SentArmUri -State (New-HostTestState -Extra $Extra)
        $Sent | Should -BeExactly 'https://management.azure.com/subscriptions?api-version=2022-12-01'
        Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-WebRequest -Times 1 -Exactly
    }

    It 'prefers the session''s own ArmResourceUrl over the cloud table' {
        $Sent = Get-SentArmUri -State (New-HostTestState -Extra @{ Environment = 'USGov'; ArmResourceUrl = 'https://management.chinacloudapi.cn/' })
        $Sent | Should -BeExactly 'https://management.chinacloudapi.cn/subscriptions?api-version=2022-12-01'
    }

    It 'sends nothing, and never falls back to the public cloud, for a cloud the table does not know' {
        $Caught = & (Get-Module Omnicit.EntraRBAC) {
            param($S)
            $script:_OERAuthState = $S
            try { $null = Invoke-OERArmRequest -Path '/subscriptions?api-version=2022-12-01' } catch { $PSItem }
        } (New-HostTestState -Extra @{ Environment = 'Germany' })

        Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-WebRequest -Times 0
        $Caught | Should -Not -BeNullOrEmpty
        $Caught.Exception.Message | Should -BeLike "*no endpoint table entry for cloud environment 'Germany'*"
    }
}

Describe 'Invoke-OERArmRequest sends nothing without an ARM token, outside any try (BL-65, BL-96)' {
    # Under -ErrorAction SilentlyContinue or Ignore, with no try up the call stack, a function carries
    # on past its own throw to its next statement, so the refusal's own return is what keeps the request
    # from going out with an empty bearer. Pester's It is a try, so the wrapper runs in a runspace with
    # no try. The probe is the F3 probe's twin, with the state under test pasted in; the shared probe
    # above is left as it is.
    BeforeAll {
        # Runs one probe in a runspace with no try. -State is pasted into a module-scope block that
        # sets the session state; a MODULE-scope Invoke-WebRequest stub counts its calls
        # ($global:OERNoTokenArmCalls), answers 200 (hang guard: exit past five calls) and is removed
        # again, unqualified from the module scope, before the runspace check reads the module scope.
        # The error ids are read from $Error, cleared just before the call: SilentlyContinue keeps a
        # suppressed throw off the error stream, not out of $Error.
        function script:Invoke-ArmNoTokenProbe {
            param([Parameter(Mandatory)][scriptblock]$State)
            $Text = @'
Import-Module Omnicit.EntraRBAC
& (Get-Module Omnicit.EntraRBAC) {
__STATE__
}
$global:OERNoTokenArmCalls = 0
& (Get-Module Omnicit.EntraRBAC) {
    function script:Invoke-WebRequest {
        [CmdletBinding()]
        param($Method, $Uri, $Headers, [switch]$SkipHttpErrorCheck, $Body, $ContentType)
        $global:OERNoTokenArmCalls++
        if ($global:OERNoTokenArmCalls -gt 5) { exit }
        [pscustomobject]@{ StatusCode = 200; Content = '{"value":["sent"]}'; Headers = @{} }
    }
}
$Error.Clear()
$Result = @(& (Get-Module Omnicit.EntraRBAC) {
    Invoke-OERArmRequest -Path '/subscriptions?api-version=2022-12-01' -ErrorAction SilentlyContinue
})
$Ids = @($Error | ForEach-Object { [string]$_.FullyQualifiedErrorId })
# Unqualified, from the module scope: removes the nearest definition, which is the stub.
& (Get-Module Omnicit.EntraRBAC) { Remove-Item -Path function:Invoke-WebRequest }
$Resolved = & (Get-Module Omnicit.EntraRBAC) { Get-Command -Name Invoke-WebRequest -CommandType Function -ErrorAction Ignore }
'TRIPWIRE RESTORED: {0}' -f ([bool]$Resolved -and $Resolved.ScriptBlock.ToString().Contains('OER-TRANSPORT-TRIPWIRE'))
'RESULT COUNT: {0}' -f $Result.Count
'ARM CALLS: {0}' -f $global:OERNoTokenArmCalls
foreach ($Id in $Ids) { 'ERROR ID: {0}' -f $Id }
'END OF SCRIPT REACHED'
'@
            $Text = $Text.Replace('__STATE__', $State.ToString())
            Invoke-OERWithConfirmAnswer -Answer '&No' -Script ([scriptblock]::Create($Text))
        }

        # The FullyQualifiedErrorId of every record a probe found in $Error.
        function script:Get-NoTokenProbeErrorId {
            param([Parameter(Mandatory)]$Probe)
            @($Probe.Output | Where-Object { "$_" -like 'ERROR ID: *' } | ForEach-Object { "$_" -replace '^ERROR ID: ', '' })
        }
    }

    It 'N1: a session with no ARM token key sends no request and leaves ArmTokenAcquisitionFailed as the only record' {
        $HitsBefore = @($global:OERTransportTripwireHits).Count
        $R = Invoke-ArmNoTokenProbe -State {
            $script:_OERAuthState = @{
                TenantId = '44444444-4444-4444-4444-444444444444'; AuthMethod = 'Interactive'
                ClientId = ''; Environment = 'Global'
                ArmTokenExpiry = [DateTime]::UtcNow.AddHours(1)
                ArmResourceUrl = 'https://management.azure.com/'
            }
        }
        $R.Output | Should -Contain 'END OF SCRIPT REACHED'
        $R.Output | Should -Contain 'TRIPWIRE RESTORED: True'
        $R.Output | Should -Contain 'ARM CALLS: 0'
        $R.Output | Should -Contain 'RESULT COUNT: 0'
        Get-NoTokenProbeErrorId -Probe $R | Should -Be @('ArmTokenAcquisitionFailed')
        (@($global:OERTransportTripwireHits).Count - $HitsBefore) | Should -Be 0
    }

    It 'N2: a session whose ARM token is blank sends no request and leaves ArmTokenAcquisitionFailed as the only record' {
        $HitsBefore = @($global:OERTransportTripwireHits).Count
        $R = Invoke-ArmNoTokenProbe -State {
            $script:_OERAuthState = @{
                TenantId = '44444444-4444-4444-4444-444444444444'; AuthMethod = 'Interactive'
                ClientId = ''; Environment = 'Global'
                ArmToken = ConvertTo-SecureString '   ' -AsPlainText -Force
                ArmTokenExpiry = [DateTime]::UtcNow.AddHours(1)
                ArmResourceUrl = 'https://management.azure.com/'
            }
        }
        $R.Output | Should -Contain 'END OF SCRIPT REACHED'
        $R.Output | Should -Contain 'TRIPWIRE RESTORED: True'
        $R.Output | Should -Contain 'ARM CALLS: 0'
        $R.Output | Should -Contain 'RESULT COUNT: 0'
        Get-NoTokenProbeErrorId -Probe $R | Should -Be @('ArmTokenAcquisitionFailed')
        (@($global:OERTransportTripwireHits).Count - $HitsBefore) | Should -Be 0
    }

    It 'N3: a call with no session state at all sends no request to the public-cloud fallback and leaves ArmTokenAcquisitionFailed as the only record' {
        $HitsBefore = @($global:OERTransportTripwireHits).Count
        $R = Invoke-ArmNoTokenProbe -State {
            $script:_OERAuthState = $null
        }
        $R.Output | Should -Contain 'END OF SCRIPT REACHED'
        $R.Output | Should -Contain 'TRIPWIRE RESTORED: True'
        $R.Output | Should -Contain 'ARM CALLS: 0'
        $R.Output | Should -Contain 'RESULT COUNT: 0'
        Get-NoTokenProbeErrorId -Probe $R | Should -Be @('ArmTokenAcquisitionFailed')
        (@($global:OERTransportTripwireHits).Count - $HitsBefore) | Should -Be 0
    }
}
