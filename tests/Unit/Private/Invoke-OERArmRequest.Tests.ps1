BeforeAll {
    Import-Module Omnicit.EntraRBAC -Force
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
