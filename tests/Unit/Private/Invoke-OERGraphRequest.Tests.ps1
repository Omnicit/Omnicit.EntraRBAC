BeforeAll {
    $script:moduleName = 'Omnicit.EntraRBAC'
    Get-Module $script:moduleName | Remove-Module -Force -ErrorAction SilentlyContinue
    Import-Module $script:moduleName -Force -ErrorAction Stop
}

Describe 'Invoke-OERGraphRequest' {
    It 'returns the response from Invoke-MgGraphRequest on success' {
        Mock -ModuleName $script:moduleName Invoke-MgGraphRequest { @{ value = @('ok') } }
        InModuleScope $script:moduleName {
            $Result = Invoke-OERGraphRequest -Uri 'v1.0/groups'
            $Result.value | Should -Be 'ok'
        }
        Should -Invoke -ModuleName $script:moduleName Invoke-MgGraphRequest -Times 1
    }

    It 'converts a graph error and removes the bearer-carrying record from the callers $global:Error' {
        # The record Invoke-MgGraphRequest produces carries the raw HttpRequestMessage in
        # TargetObject, and that message holds "Authorization: Bearer <token>" in plain text.
        # Remove-OERErrorRecord matches on Exception REFERENCE identity against $global:Error,
        # so the assertion must be made against $global:Error filtered by ReferenceEquals -- a
        # module-scoped $Error.Count delta would prove nothing (the module's $Error is a private
        # list that never held the record).
        $global:Error.Clear()
        InModuleScope $script:moduleName {
            # NOTE: the fake token below is planted inside the Graph error MESSAGE text, which
            # Convert-GraphHttpException legitimately reuses verbatim as the sanitized record's
            # Detail/Message (see Convert-GraphHttpException.ps1:106-109) -- so the resulting
            # $Caught record still contains the literal "Bearer ...NOT-A-REAL-TOKEN-LEAKED" string below. That is an
            # artifact of this synthetic fixture (a real Graph error body never carries the caller's
            # own bearer token back to it), not a leak. Do not "fix" the converter to strip it.
            $BearerException = [System.Exception]::new(
                '{"error":{"code":"Forbidden","message":"Authorization: Bearer eyJ0eXAiOiJKV1QiLCJhbGciOiJSUzI1NiJ9.NOT-A-REAL-TOKEN-LEAKED"}}')
            Mock Invoke-MgGraphRequest { throw $BearerException }

            $Caught = $null
            try {
                Invoke-OERGraphRequest -Uri 'v1.0/groups'
            } catch {
                Remove-OERErrorRecord -Record $PSItem
                $Caught = $PSItem
            }

            $Caught | Should -Not -BeNullOrEmpty
            $Caught.FullyQualifiedErrorId | Should -Be 'Forbidden'

            @($global:Error | Where-Object { [object]::ReferenceEquals($PSItem.Exception, $BearerException) }) |
                Should -BeNullOrEmpty
        }
    }

    It 'does not chain the bearer-carrying exception into the converted record it throws' {
        # Convert-GraphHttpException builds a NEW exception from the response text only. If it ever
        # chained the original, the token would travel inside the sanitized record's InnerException.
        InModuleScope $script:moduleName {
            $BearerException = [System.Exception]::new(
                '{"error":{"code":"Forbidden","message":"Authorization: Bearer eyJ0eXAiOiJKV1QiLCJhbGciOiJSUzI1NiJ9.NOT-A-REAL-TOKEN-LEAKED"}}')
            Mock Invoke-MgGraphRequest { throw $BearerException }

            $Caught = $null
            try {
                Invoke-OERGraphRequest -Uri 'v1.0/groups'
            } catch {
                Remove-OERErrorRecord -Record $PSItem
                $Caught = $PSItem
            }

            $Caught.Exception.InnerException | Should -BeNullOrEmpty
            [object]::ReferenceEquals($Caught.Exception, $BearerException) | Should -BeFalse
        }
    }

    It 'performs ACRS step-up and retries once on a claims challenge' {
        InModuleScope $script:moduleName {
            $script:_OERAuthState = @{ TenantId = 'contoso'; AuthMethod = 'Interactive'; ClientId = $null }
        }
        $script:Attempt = 0
        Mock -ModuleName $script:moduleName Initialize-OERAuth {}
        Mock -ModuleName $script:moduleName Invoke-MgGraphRequest {
            $script:Attempt++
            if ($script:Attempt -eq 1) {
                throw [System.Exception]::new('WWW-Authenticate: Bearer claims="eyJhY2Nlc3MiOnt9fQ"')
            }
            @{ value = @('after-stepup') }
        }
        InModuleScope $script:moduleName {
            (Invoke-OERGraphRequest -Uri 'v1.0/groups').value | Should -Be 'after-stepup'
        }
        Should -Invoke -ModuleName $script:moduleName Initialize-OERAuth -Times 1 -ParameterFilter { $ClaimsChallenge }
        Should -Invoke -ModuleName $script:moduleName Invoke-MgGraphRequest -Times 2
    }

    It 'forwards the cached ClientId on the ACRS claims-challenge step-up call' {
        InModuleScope $script:moduleName {
            $script:_OERAuthState = @{
                TenantId   = 'contoso.onmicrosoft.com'
                AuthMethod = 'ManagedIdentity'
                ClientId   = 'aaaa0000-0000-0000-0000-000000000099'
            }
        }
        $script:Attempt = 0
        Mock -ModuleName $script:moduleName Invoke-MgGraphRequest {
            $script:Attempt++
            if ($script:Attempt -eq 1) {
                throw [System.Exception]::new('WWW-Authenticate: Bearer claims="eyJhY2Nlc3MiOnt9fQ"')
            }
            @{ value = @('after-stepup') }
        }
        $script:CapturedRefreshParams = $null
        # An explicit param() block is required here: Pester's mock body does not populate
        # $PSBoundParameters unless the scriptblock declares matching parameters (verified --
        # without this, $PSBoundParameters.Keys is empty even though the splat was passed).
        Mock -ModuleName $script:moduleName Initialize-OERAuth {
            param($TenantId, $AuthMethod, $ClientId, $ClientSecret, $Certificate, $CertificatePath, $IncludeARM, $ClaimsChallenge, $ForceRefresh)
            $script:CapturedRefreshParams = $PSBoundParameters
        }

        InModuleScope $script:moduleName {
            $null = Invoke-OERGraphRequest -Uri 'v1.0/groups'
        }

        $script:CapturedRefreshParams.ContainsKey('ClientId') | Should -BeTrue
        $script:CapturedRefreshParams['ClientId'] | Should -Be 'aaaa0000-0000-0000-0000-000000000099'
    }

    It 'forces a refresh and retries once on a 401 without a claims challenge (delegated)' {
        InModuleScope $script:moduleName {
            $script:_OERAuthState = @{ TenantId = 'contoso'; AuthMethod = 'Interactive'; ClientId = $null }
        }
        $script:Attempt = 0
        Mock -ModuleName $script:moduleName Initialize-OERAuth {}
        Mock -ModuleName $script:moduleName Invoke-MgGraphRequest {
            $script:Attempt++
            if ($script:Attempt -eq 1) { throw [System.Exception]::new('InvalidAuthenticationToken: token is expired') }
            @{ value = @('after-refresh') }
        }
        InModuleScope $script:moduleName {
            (Invoke-OERGraphRequest -Uri 'v1.0/groups').value | Should -Be 'after-refresh'
        }
        Should -Invoke -ModuleName $script:moduleName Initialize-OERAuth -Times 1 -ParameterFilter { $ForceRefresh }
    }

    It 'forwards the cached ClientId when force-refreshing after a 401' {
        InModuleScope $script:moduleName {
            $script:_OERAuthState = @{
                TenantId   = 'contoso.onmicrosoft.com'
                AuthMethod = 'ManagedIdentity'
                ClientId   = 'aaaa0000-0000-0000-0000-000000000099'
            }
        }
        $script:Attempt = 0
        Mock -ModuleName $script:moduleName Invoke-MgGraphRequest {
            $script:Attempt++
            if ($script:Attempt -eq 1) { throw [System.Exception]::new('InvalidAuthenticationToken: token is expired') }
            @{ value = @('after-refresh') }
        }
        $script:CapturedRefreshParams = $null
        # An explicit param() block is required here: Pester's mock body does not populate
        # $PSBoundParameters unless the scriptblock declares matching parameters (verified --
        # without this, $PSBoundParameters.Keys is empty even though the splat was passed).
        Mock -ModuleName $script:moduleName Initialize-OERAuth {
            param($TenantId, $AuthMethod, $ClientId, $ClientSecret, $Certificate, $CertificatePath, $IncludeARM, $ClaimsChallenge, $ForceRefresh)
            $script:CapturedRefreshParams = $PSBoundParameters
        }

        InModuleScope $script:moduleName {
            $null = Invoke-OERGraphRequest -Uri 'v1.0/groups'
        }

        $script:CapturedRefreshParams.ContainsKey('ClientId') | Should -BeTrue
        $script:CapturedRefreshParams['ClientId'] | Should -Be 'aaaa0000-0000-0000-0000-000000000099'
    }

    It 'omits ClientId when force-refreshing and the cached state has none' {
        InModuleScope $script:moduleName {
            $script:_OERAuthState = @{ TenantId = 'contoso.onmicrosoft.com'; AuthMethod = 'Interactive'; ClientId = $null }
        }
        $script:Attempt = 0
        Mock -ModuleName $script:moduleName Invoke-MgGraphRequest {
            $script:Attempt++
            if ($script:Attempt -eq 1) { throw [System.Exception]::new('InvalidAuthenticationToken: token is expired') }
            @{ value = @('after-refresh') }
        }
        $script:CapturedRefreshParams = $null
        # An explicit param() block is required here: Pester's mock body does not populate
        # $PSBoundParameters unless the scriptblock declares matching parameters (verified --
        # without this, $PSBoundParameters.Keys is empty even though the splat was passed).
        Mock -ModuleName $script:moduleName Initialize-OERAuth {
            param($TenantId, $AuthMethod, $ClientId, $ClientSecret, $Certificate, $CertificatePath, $IncludeARM, $ClaimsChallenge, $ForceRefresh)
            $script:CapturedRefreshParams = $PSBoundParameters
        }

        InModuleScope $script:moduleName {
            $null = Invoke-OERGraphRequest -Uri 'v1.0/groups'
        }

        $script:CapturedRefreshParams.ContainsKey('ClientId') | Should -BeFalse
    }

    It 'does not attempt an interactive step-up for an app-only (ClientSecret) session' {
        InModuleScope $script:moduleName {
            $script:_OERAuthState = @{ TenantId = 'contoso'; AuthMethod = 'ClientSecret'; ClientId = 'cid' }
        }
        Mock -ModuleName $script:moduleName Initialize-OERAuth {}
        Mock -ModuleName $script:moduleName Invoke-MgGraphRequest {
            throw [System.Exception]::new('WWW-Authenticate: Bearer claims="eyJhY2Nlc3MiOnt9fQ"')
        }
        InModuleScope $script:moduleName {
            { Invoke-OERGraphRequest -Uri 'v1.0/groups' } |
                Should -Throw -ErrorId 'AppOnlyClaimsChallengeUnsatisfiable'
        }
        Should -Invoke -ModuleName $script:moduleName Initialize-OERAuth -Times 0
    }

    It 'short-circuits an app-only 401 with no claims as AppOnlyTokenRefreshUnsatisfiable' {
        InModuleScope $script:moduleName {
            $script:_OERAuthState = @{ TenantId = 'contoso'; AuthMethod = 'ClientSecret'; ClientId = 'cid' }
            Mock Initialize-OERAuth { }
            # No claims= anywhere, so Get-ClaimsFromException returns $null and the TokenInvalid
            # message test fires instead of the claims branch.
            Mock Invoke-MgGraphRequest {
                throw [System.Exception]::new('InvalidAuthenticationToken: token is expired')
            }

            { Invoke-OERGraphRequest -Uri 'v1.0/groups' } |
                Should -Throw -ErrorId 'AppOnlyTokenRefreshUnsatisfiable'
            Should -Invoke Initialize-OERAuth -Times 0
            # -Exactly matters here: without it, Should -Invoke -Times N is only a floor check in
            # Pester v5 (passes on >= N calls), so a regression that called the mock more than once
            # would still satisfy "at least 1" and pass silently.
            Should -Invoke Invoke-MgGraphRequest -Times 1 -Exactly
        }
    }

    It 'honours Retry-After on a 429 and retries, without ever sleeping in the test' {
        InModuleScope $script:moduleName {
            Mock Start-Sleep { }          # MUST be mocked: a real sleep makes the gate slow and flaky
            $script:Attempt = 0
            Mock Invoke-MgGraphRequest {
                $script:Attempt++
                if ($script:Attempt -eq 1) {
                    $Resp = [System.Net.Http.HttpResponseMessage]::new([System.Net.HttpStatusCode]::TooManyRequests)
                    $Resp.Headers.Add('Retry-After', '7')
                    $Ex = [System.Exception]::new('{"error":{"code":"TooManyRequests","message":"throttled"}}')
                    Add-Member -InputObject $Ex -NotePropertyName Response -NotePropertyValue $Resp
                    throw $Ex
                }
                @{ value = @('after-backoff') }
            }

            $Result = Invoke-OERGraphRequest -Uri 'v1.0/identityGovernance/accessReviews/definitions'

            $Result.value | Should -Be 'after-backoff'
            # -Exactly on both: Pester v5 Should -Invoke -Times N is AT-LEAST semantics unless N is
            # 0, so without it a regression that retried more often, or slept 7 s more than once,
            # would still satisfy "at least 2" / "at least 1" and pass silently.
            Should -Invoke Invoke-MgGraphRequest -Times 2 -Exactly
            # The wait came from the header, not from a hardcoded constant.
            Should -Invoke Start-Sleep -Times 1 -Exactly -ParameterFilter { $Seconds -eq 7 }
        }
    }

    It 'bounds 429 retries at the hard cap when the server keeps asking for a one-second wait' {
        # A one-second Retry-After repeated forever is the ONE regime the 300 s wait budget alone
        # does not bound usefully: 300 retries in five minutes against an endpoint that is already
        # throttling us. $ThrottleRetryHardCap exists for exactly this shape and nothing else, and
        # this is the only test that reaches it.
        InModuleScope $script:moduleName {
            Mock Start-Sleep { }
            Mock Invoke-MgGraphRequest {
                $Resp = [System.Net.Http.HttpResponseMessage]::new([System.Net.HttpStatusCode]::TooManyRequests)
                $Resp.Headers.Add('Retry-After', '1')
                $Ex = [System.Exception]::new('{"error":{"code":"TooManyRequests","message":"throttled"}}')
                Add-Member -InputObject $Ex -NotePropertyName Response -NotePropertyValue $Resp
                throw $Ex
            }

            { Invoke-OERGraphRequest -Uri 'v1.0/groups' } | Should -Throw -ErrorId 'TooManyRequests'
            # 1 initial attempt + 10 capped retries. Never unbounded.
            # -Exactly matters here: the mock 429s unconditionally, so nothing but the hard cap
            # bounds the count. Without -Exactly this is only a floor check (Pester v5
            # Should -Invoke -Times N passes on >= N calls unless N is 0), so a regression that
            # LOOSENED the cap would still satisfy "at least 11" / "at least 10" and pass silently.
            Should -Invoke Invoke-MgGraphRequest -Times 11 -Exactly
            Should -Invoke Start-Sleep -Times 10 -Exactly
            # Every wait was the server's own one second -- the cap, not the budget, ended this.
            Should -Invoke Start-Sleep -Times 10 -Exactly -ParameterFilter { $Seconds -eq 1 }
        }
    }

    It 'honours a server-directed Retry-After of 60 s, which the old three-retry ceiling could not' {
        # THE REGRESSION THIS BRANCH EXISTS FOR, on the .Response (secondary) shape. The previous
        # bound was three retries over a 1 + 2 + 4 exponential fallback -- a total tolerance of seven
        # seconds -- so a single 60 s server instruction was unsatisfiable even when it WAS readable.
        InModuleScope $script:moduleName {
            Mock Start-Sleep { }
            $script:Attempt = 0
            Mock Invoke-MgGraphRequest {
                $script:Attempt++
                if ($script:Attempt -le 2) {
                    $Resp = [System.Net.Http.HttpResponseMessage]::new([System.Net.HttpStatusCode]::TooManyRequests)
                    $Resp.Headers.Add('Retry-After', '60')
                    $Ex = [System.Exception]::new('{"error":{"code":"TooManyRequests","message":"throttled"}}')
                    Add-Member -InputObject $Ex -NotePropertyName Response -NotePropertyValue $Resp
                    throw $Ex
                }
                @{ value = @('after-two-minutes') }
            }

            (Invoke-OERGraphRequest -Uri 'v1.0/groups').value | Should -Be 'after-two-minutes'
            Should -Invoke Invoke-MgGraphRequest -Times 3 -Exactly
            Should -Invoke Start-Sleep -Times 2 -Exactly -ParameterFilter { $Seconds -eq 60 }
        }
    }

    It 'gives up once the next server-directed wait no longer fits the remaining budget' {
        # The budget is a DEADLINE, not a clamp-and-continue: retrying earlier than the server asked
        # would only earn another throttle. 300 s budget / 120 s per-sleep clamp means an absurd
        # Retry-After is clamped to 120, slept twice (240 s spent), and the third 120 s no longer
        # fits in the 60 s that remain -- so the call gives up with the Graph error intact.
        InModuleScope $script:moduleName {
            Mock Start-Sleep { }
            Mock Invoke-MgGraphRequest {
                $Resp = [System.Net.Http.HttpResponseMessage]::new([System.Net.HttpStatusCode]::TooManyRequests)
                $Resp.Headers.Add('Retry-After', '3600')
                $Ex = [System.Exception]::new('{"error":{"code":"TooManyRequests","message":"throttled"}}')
                Add-Member -InputObject $Ex -NotePropertyName Response -NotePropertyValue $Resp
                throw $Ex
            }

            { Invoke-OERGraphRequest -Uri 'v1.0/groups' } | Should -Throw -ErrorId 'TooManyRequests'
            Should -Invoke Invoke-MgGraphRequest -Times 3 -Exactly
            Should -Invoke Start-Sleep -Times 2 -Exactly -ParameterFilter { $Seconds -eq 120 }
            # The clamp still holds: an hour-long header never becomes an hour-long sleep.
            Should -Invoke Start-Sleep -Times 0 -ParameterFilter { $Seconds -gt 120 }
        }
    }

    It 'does not back off on a non-429 failure' {
        InModuleScope $script:moduleName {
            Mock Start-Sleep { }
            Mock Invoke-MgGraphRequest {
                throw [System.Exception]::new('{"error":{"code":"Forbidden","message":"denied"}}')
            }

            { Invoke-OERGraphRequest -Uri 'v1.0/groups' } | Should -Throw -ErrorId 'Forbidden'
            Should -Invoke Start-Sleep -Times 0
            # -Exactly: this exception exposes no HTTP status, so it lands on the SAME code/message
            # classification branch the status-less throttle uses. If that branch ever widened to
            # treat any unrecognised failure as retryable, this call count is what catches it.
            Should -Invoke Invoke-MgGraphRequest -Times 1 -Exactly
        }
    }

    It 'does not back off on a 403 whose HTTP status IS reachable' {
        # The other half of the 403 guard: here the status resolves, so classification must stop at
        # the status and never consult the code/message fallback at all.
        InModuleScope $script:moduleName {
            Mock Start-Sleep { }
            Mock Invoke-MgGraphRequest {
                $Resp = [System.Net.Http.HttpResponseMessage]::new([System.Net.HttpStatusCode]::Forbidden)
                $Ex = [System.Exception]::new('{"error":{"code":"Forbidden","message":"denied"}}')
                Add-Member -InputObject $Ex -NotePropertyName Response -NotePropertyValue $Resp
                throw $Ex
            }

            { Invoke-OERGraphRequest -Uri 'v1.0/groups' } | Should -Throw -ErrorId 'Forbidden'
            Should -Invoke Start-Sleep -Times 0
            Should -Invoke Invoke-MgGraphRequest -Times 1 -Exactly
        }
    }
}

Describe 'Invoke-OERGraphRequest throttle detection without a reachable HTTP status' {
    # REGRESSION SUITE. The documented "bounded Retry-After backoff" was structurally inert in
    # production for the shape Microsoft Graph actually produces on a throttle.
    #
    # What really happens: this wrapper never sees a bare 429. Kiota's RetryHandler, installed in
    # Microsoft.Graph.Authentication's HTTP pipeline, consumes the 429, retries it internally, and on
    # exhaustion throws
    #     AggregateException('Too many retries performed. More than {n} retries encountered while
    #                         sending the request.',
    #                        ApiException('HTTP request failed with status code: {status}.{body}'))
    # (verified by disassembling RetryHandler.SendRetryAsync / RetryHandler.GetInnerExceptionAsync in
    # Microsoft.Kiota.Http.HttpClientLibrary and InvokeMgGraphRequest.ProcessRecordAsync in
    # Microsoft.Graph.Authentication 2.36.0). Neither AggregateException nor Kiota's ApiException has
    # a .Response member, so [int]$Err.Exception.Response.StatusCode does NOT throw -- in PowerShell
    # $null.StatusCode is $null and [int]$null is 0 -- and the old status-only test silently saw 0.
    # Result: the throttle delay helper returned $null, the loop broke on the first failure, no
    # Start-Sleep ran, and the caller got TooManyRequests immediately. The error CODE still read
    # correctly because Convert-GraphHttpException falls back to the exception message, which is the
    # asymmetry these tests pin down.
    #
    # SCOPE OF THIS SUITE, and what it deliberately does NOT cover. Every inner exception below is a
    # plain System.Exception carrying only the message text GetInnerExceptionAsync emits verbatim
    # (AggregateException.Message appends each inner message in parentheses, which is how the JSON
    # body reaches the caller). That fixture exercises exactly one thing: classification from the
    # message when NO HTTP fact is reachable at all.
    #
    # It is NOT a fixture for Retry-After. A plain System.Exception has neither .Response nor
    # .ResponseHeaders, so nothing here can prove a header is honoured -- and for a long time these
    # tests asserted the exponential fallback here as though that were the design rather than the
    # bug. The Retry-After contract is proved in
    # 'Invoke-OERGraphRequest Retry-After on the production Kiota exception shape' below, which
    # builds the REAL Microsoft.Kiota.Abstractions.ApiException and sets its ResponseStatusCode and
    # ResponseHeaders. The module itself still takes no dependency on that type: it reads both
    # members by NAME through the PowerShell property bag.

    It 'falls back to exponential backoff when the throttle genuinely carries NO Retry-After' {
        # REWRITTEN. This test used to carry the comment "No Retry-After is reachable on this shape,
        # so the exponential fallback supplies the wait" -- an accurate description of the DEFECT,
        # pinned as though it were the design. The shape below now genuinely carries no header at
        # all (a plain System.Exception has neither .Response nor .ResponseHeaders), so its job is
        # the opposite one: prove the fallback still fires when Graph really said nothing. The
        # companion tests further down prove the header WINS when Graph does send one.
        InModuleScope $script:moduleName {
            Mock Start-Sleep { }          # MUST be mocked: a real sleep makes the gate slow and flaky
            $script:Attempt = 0
            Mock Invoke-MgGraphRequest {
                $script:Attempt++
                if ($script:Attempt -eq 1) {
                    $Inner = [System.Exception]::new(
                        'HTTP request failed with status code: TooManyRequests.{"error":{"code":"TooManyRequests","message":"Too many requests. Please try again later."}}')
                    throw [System.AggregateException]::new(
                        'Too many retries performed. More than 3 retries encountered while sending the request.',
                        [System.Exception[]]@($Inner))
                }
                @{ value = @('after-backoff') }
            }

            $Result = Invoke-OERGraphRequest -Uri 'v1.0/identityGovernance/accessReviews/definitions'

            $Result.value | Should -Be 'after-backoff'
            Should -Invoke Invoke-MgGraphRequest -Times 2 -Exactly
            # Exponential fallback: [Math]::Pow(2, 0) on the first retry.
            Should -Invoke Start-Sleep -Times 1 -Exactly -ParameterFilter { $Seconds -eq 1 }
        }
    }

    It 'spends the whole wait budget on the exponential fallback and still converts to TooManyRequests' {
        # REWRITTEN. This test used to assert "1 initial attempt + 3 bounded retries" with the
        # comment "Exponential fallback, not a constant: 2^0, 2^1, 2^2" -- the 1 + 2 + 4 = 7 second
        # total tolerance that made a real 429 unsurvivable. The bound is now the 300 s WAIT BUDGET.
        # Nothing here carries a Retry-After, so the fallback doubles until the next wait no longer
        # fits: 1 + 2 + 4 + 8 + 16 + 32 + 64 = 127, then 2^7 = 128 clamped to 120 (247 s spent), and
        # 2^8 clamped to 120 does not fit the 53 s that remain. Eight sleeps, nine attempts.
        InModuleScope $script:moduleName {
            Mock Start-Sleep { }
            Mock Invoke-MgGraphRequest {
                $Inner = [System.Exception]::new(
                    'HTTP request failed with status code: TooManyRequests.{"error":{"code":"TooManyRequests","message":"Too many requests. Please try again later."}}')
                throw [System.AggregateException]::new(
                    'Too many retries performed. More than 3 retries encountered while sending the request.',
                    [System.Exception[]]@($Inner))
            }

            { Invoke-OERGraphRequest -Uri 'v1.0/groups' } | Should -Throw -ErrorId 'TooManyRequests'
            Should -Invoke Invoke-MgGraphRequest -Times 9 -Exactly
            Should -Invoke Start-Sleep -Times 8 -Exactly
            # Exponential, not a constant, and clamped at the top end. Written out one per line
            # rather than looped: a -ParameterFilter scriptblock is evaluated LATER, in the mock's
            # own scope, so a loop variable read inside it is not the value the loop meant.
            Should -Invoke Start-Sleep -Times 1 -Exactly -ParameterFilter { $Seconds -eq 1 }
            Should -Invoke Start-Sleep -Times 1 -Exactly -ParameterFilter { $Seconds -eq 2 }
            Should -Invoke Start-Sleep -Times 1 -Exactly -ParameterFilter { $Seconds -eq 4 }
            Should -Invoke Start-Sleep -Times 1 -Exactly -ParameterFilter { $Seconds -eq 8 }
            Should -Invoke Start-Sleep -Times 1 -Exactly -ParameterFilter { $Seconds -eq 16 }
            Should -Invoke Start-Sleep -Times 1 -Exactly -ParameterFilter { $Seconds -eq 32 }
            Should -Invoke Start-Sleep -Times 1 -Exactly -ParameterFilter { $Seconds -eq 64 }
            Should -Invoke Start-Sleep -Times 1 -Exactly -ParameterFilter { $Seconds -eq 120 }
            # The budget, not a retry count, is what stopped it: nothing waited past the clamp.
            Should -Invoke Start-Sleep -Times 0 -ParameterFilter { $Seconds -gt 120 }
        }
    }

    It 'recognises a throttle reported only in prose, with no JSON error code' {
        # Graph gateways and the SDK's own aggregate text do not always carry a parseable
        # error.code. The message is then the only evidence of a throttle there is.
        InModuleScope $script:moduleName {
            Mock Start-Sleep { }
            $script:Attempt = 0
            Mock Invoke-MgGraphRequest {
                $script:Attempt++
                if ($script:Attempt -eq 1) { throw [System.Exception]::new('Too many requests. Please try again later.') }
                @{ value = @('recovered') }
            }

            (Invoke-OERGraphRequest -Uri 'v1.0/groups').value | Should -Be 'recovered'
            Should -Invoke Invoke-MgGraphRequest -Times 2 -Exactly
            Should -Invoke Start-Sleep -Times 1 -Exactly
        }
    }

    It 'still refuses to retry a 503 that carries no Retry-After' {
        # Rule preserved from the status-carrying path: a 503 is retryable ONLY when the service
        # actually asked for a wait. Nothing on this shape can supply one, so it must fail at once.
        InModuleScope $script:moduleName {
            Mock Start-Sleep { }
            Mock Invoke-MgGraphRequest {
                $Inner = [System.Exception]::new(
                    'HTTP request failed with status code: ServiceUnavailable.{"error":{"code":"ServiceUnavailable","message":"Service is unavailable."}}')
                throw [System.AggregateException]::new(
                    'Too many retries performed. More than 3 retries encountered while sending the request.',
                    [System.Exception[]]@($Inner))
            }

            { Invoke-OERGraphRequest -Uri 'v1.0/groups' } | Should -Throw -ErrorId 'ServiceUnavailable'
            Should -Invoke Start-Sleep -Times 0
            Should -Invoke Invoke-MgGraphRequest -Times 1 -Exactly
        }
    }

    It 'does not spend the single-shot claims-challenge retry on the throttle path' {
        # The throttle loop and the ACRS step-up read the same $AttemptError. A throttled request
        # that later hits a claims challenge must still get exactly ONE step-up, and a throttle must
        # never trigger one.
        InModuleScope $script:moduleName {
            $script:_OERAuthState = @{ TenantId = 'contoso'; AuthMethod = 'Interactive'; ClientId = $null }
            Mock Start-Sleep { }
            Mock Initialize-OERAuth { }
            $script:Attempt = 0
            Mock Invoke-MgGraphRequest {
                $script:Attempt++
                if ($script:Attempt -eq 1) {
                    $Inner = [System.Exception]::new(
                        'HTTP request failed with status code: TooManyRequests.{"error":{"code":"TooManyRequests","message":"Too many requests. Please try again later."}}')
                    throw [System.AggregateException]::new(
                        'Too many retries performed. More than 3 retries encountered while sending the request.',
                        [System.Exception[]]@($Inner))
                }
                if ($script:Attempt -eq 2) { throw [System.Exception]::new('WWW-Authenticate: Bearer claims="eyJhY2Nlc3MiOnt9fQ"') }
                @{ value = @('after-stepup') }
            }

            (Invoke-OERGraphRequest -Uri 'v1.0/groups').value | Should -Be 'after-stepup'

            # 1 throttled + 1 claims-challenged + 1 success.
            Should -Invoke Invoke-MgGraphRequest -Times 3 -Exactly
            Should -Invoke Start-Sleep -Times 1 -Exactly
            Should -Invoke Initialize-OERAuth -Times 1 -Exactly -ParameterFilter { $ClaimsChallenge }
        }
    }
}

Describe 'Invoke-OERGraphRequest Retry-After on the production Kiota exception shape' {
    # THE SHAPE THE MODULE ACTUALLY MEETS IN A TENANT, built from the REAL Graph SDK type.
    #
    # Every other throttle fixture in this file is hand-built: either a synthetic
    # HttpResponseMessage Add-Member'd onto an exception as .Response (a shape Microsoft Graph never
    # produces) or a plain System.Exception carrying only message text. Both are useful, and both
    # are exactly why a green suite and a code review shipped a Retry-After reader that had never
    # once fired: nothing in the suite used the type Kiota really throws.
    #
    # Microsoft.Kiota.Abstractions.ApiException has NO .Response member. Its HTTP facts are
    # ResponseStatusCode ([int]) and ResponseHeaders (IDictionary[string, IEnumerable[string]]).
    # These tests construct that type from the assembly shipped inside the pinned
    # Microsoft.Graph.Authentication, so if a future SDK bump renames either member the extraction
    # goes inert and THESE TESTS GO RED instead of the module silently losing the fix again.
    BeforeAll {
        $ModuleBase = (Get-Module Microsoft.Graph.Authentication | Select-Object -First 1).ModuleBase
        if (-not $ModuleBase) {
            $ModuleBase = (Get-Module Microsoft.Graph.Authentication -ListAvailable |
                Sort-Object Version -Descending | Select-Object -First 1).ModuleBase
        }
        $script:KiotaDll = $null
        if ($ModuleBase) {
            $DllSearch = @{
                LiteralPath = $ModuleBase
                Recurse     = $true
                File        = $true
                Filter      = 'Microsoft.Kiota.Abstractions.dll'
                ErrorAction = 'SilentlyContinue'
            }
            $script:KiotaDll = Get-ChildItem @DllSearch | Select-Object -First 1
        }
        $script:ApiExceptionType = $null
        if ($script:KiotaDll) {
            # LoadFrom is idempotent for a path already loaded, and nothing in this suite makes a
            # real Graph call, so nothing depends on which load context the assembly lands in.
            $script:ApiExceptionType = [System.Reflection.Assembly]::LoadFrom($script:KiotaDll.FullName).
                GetType('Microsoft.Kiota.Abstractions.ApiException')
        }

        # Builds the exception Kiota's RetryHandler throws on retry exhaustion:
        #   AggregateException('Too many retries performed. ...', ApiException(...))
        function New-KiotaThrottleException {
            param(
                [hashtable]$Header,
                [int]$StatusCode = 0,
                [int]$NestingDepth = 1
            )
            $Api = [Activator]::CreateInstance($script:ApiExceptionType, @(
                    'HTTP request failed with status code: TooManyRequests.{"error":{"code":"TooManyRequests","message":"Too many requests. Please try again later."}}'))
            if ($Header) {
                $Headers = [System.Collections.Generic.Dictionary[string, System.Collections.Generic.IEnumerable[string]]]::new()
                foreach ($Key in $Header.Keys) { $Headers[$Key] = [string[]]@($Header[$Key]) }
                $Api.ResponseHeaders = $Headers
            }
            if ($StatusCode) { $Api.ResponseStatusCode = $StatusCode }

            $Wrapped = [System.Exception]$Api
            for ($Level = 0; $Level -lt $NestingDepth; $Level++) {
                $Wrapped = [System.AggregateException]::new(
                    'Too many retries performed. More than 3 retries encountered while sending the request.',
                    [System.Exception[]]@($Wrapped))
            }
            return $Wrapped
        }
    }

    It 'pins the Kiota ApiException member contract the extraction is written against' {
        # If this goes red, Retry-After honouring is inert again -- fix the extraction, do not
        # relax the assertion. The dll lookup failing is itself a failure: a skip here would make
        # every test below vacuous.
        $script:ApiExceptionType | Should -Not -BeNullOrEmpty -Because (
            'Microsoft.Kiota.Abstractions.dll must be resolvable from the installed ' +
            'Microsoft.Graph.Authentication module; without it nothing below proves anything')

        $Names = $script:ApiExceptionType.GetProperties().Name
        $Names | Should -Contain 'ResponseStatusCode'
        $Names | Should -Contain 'ResponseHeaders'
        # The whole defect in one assertion: there is no .Response to read a header off.
        $Names | Should -Not -Contain 'Response'

        $script:ApiExceptionType.GetProperty('ResponseStatusCode').PropertyType.FullName |
            Should -Be 'System.Int32'
        $script:ApiExceptionType.GetProperty('ResponseHeaders').PropertyType.Name |
            Should -Be 'IDictionary`2'
    }

    It 'honours a server-directed Retry-After of 60 s on the real AggregateException/ApiException' {
        $Throttle = New-KiotaThrottleException -Header @{ 'Retry-After' = '60' } -StatusCode 429
        InModuleScope $script:moduleName -Parameters @{ Throttle = $Throttle } {
            # Copied to module scope because a Pester mock body is evaluated later, in the module's
            # own session state, and does not close over this block's locals.
            $script:Throttle = $Throttle
            Mock Start-Sleep { }
            $script:Attempt = 0
            Mock Invoke-MgGraphRequest {
                $script:Attempt++
                if ($script:Attempt -eq 1) { throw $script:Throttle }
                @{ value = @('after-server-directed-wait') }
            }

            (Invoke-OERGraphRequest -Uri 'v1.0/identityGovernance/accessReviews/definitions').value |
                Should -Be 'after-server-directed-wait'

            Should -Invoke Invoke-MgGraphRequest -Times 2 -Exactly
            Should -Invoke Start-Sleep -Times 1 -Exactly -ParameterFilter { $Seconds -eq 60 }
            # The header WON. Before this fix the extraction never reached this shape and the
            # exponential fallback supplied 2^0 = 1 every time.
            Should -Invoke Start-Sleep -Times 0 -ParameterFilter { $Seconds -eq 1 }
        }
    }

    It 'reads Retry-After through more than one level of exception nesting' {
        $Throttle = New-KiotaThrottleException -Header @{ 'Retry-After' = '45' } -StatusCode 429 -NestingDepth 3
        InModuleScope $script:moduleName -Parameters @{ Throttle = $Throttle } {
            $script:Throttle = $Throttle
            Mock Start-Sleep { }
            $script:Attempt = 0
            Mock Invoke-MgGraphRequest {
                $script:Attempt++
                if ($script:Attempt -eq 1) { throw $script:Throttle }
                @{ value = @('deep') }
            }

            (Invoke-OERGraphRequest -Uri 'v1.0/groups').value | Should -Be 'deep'
            Should -Invoke Start-Sleep -Times 1 -Exactly -ParameterFilter { $Seconds -eq 45 }
        }
    }

    It 'still finds the header at a nesting depth of 10, well past anything Graph produces' {
        # REGRESSION PIN for an exponential blow-up in the walk. AggregateException.InnerException
        # IS InnerExceptions[0] (ReferenceEquals-verified), so enqueuing from both members
        # duplicated every level and the queue grew 2^depth against the visit ceiling. Measured
        # before the fix: depth 5 found the header, depth 6 returned $null -- a header that was
        # PRESENT, silently not found, with a green suite, because the deepest fixture was depth 3.
        # That is this branch's own defect reappearing one level down, so the pin is set at a depth
        # nothing realistic will ever reach rather than at the depth that happened to break.
        $Throttle = New-KiotaThrottleException -Header @{ 'Retry-After' = '75' } -StatusCode 429 -NestingDepth 10
        InModuleScope $script:moduleName -Parameters @{ Throttle = $Throttle } {
            $script:Throttle = $Throttle
            Mock Start-Sleep { }
            $script:Attempt = 0
            Mock Invoke-MgGraphRequest {
                $script:Attempt++
                if ($script:Attempt -eq 1) { throw $script:Throttle }
                @{ value = @('very-deep') }
            }

            (Invoke-OERGraphRequest -Uri 'v1.0/groups').value | Should -Be 'very-deep'
            Should -Invoke Start-Sleep -Times 1 -Exactly -ParameterFilter { $Seconds -eq 75 }
            # Not the 2^0 fallback: the header really was read out of the depth-10 chain.
            Should -Invoke Start-Sleep -Times 0 -ParameterFilter { $Seconds -eq 1 }
        }
    }

    It 'surfaces the real Graph error when a chain member carries a non-numeric ResponseStatusCode' {
        # The status is read with -as, never a cast. A cast would THROW here, and because this walk
        # runs on the wrapper's failure path that cast error would escape and REPLACE the Graph
        # error the caller needs -- turning a diagnosable Forbidden into an unrelated type-conversion
        # failure. Nothing about this shape is retryable, so it must also not sleep.
        InModuleScope $script:moduleName {
            Mock Start-Sleep { }
            Mock Invoke-MgGraphRequest {
                $Ex = [System.Exception]::new('{"error":{"code":"Forbidden","message":"denied"}}')
                Add-Member -InputObject $Ex -NotePropertyName ResponseStatusCode -NotePropertyValue 'not-a-number'
                throw $Ex
            }

            { Invoke-OERGraphRequest -Uri 'v1.0/groups' } | Should -Throw -ErrorId 'Forbidden'
            Should -Invoke Start-Sleep -Times 0
            Should -Invoke Invoke-MgGraphRequest -Times 1 -Exactly
        }
    }

    It 'honours Retry-After even when ResponseStatusCode is unset and only the message names the throttle' {
        # Isolates HEADER extraction from STATUS extraction: Kiota leaves ResponseStatusCode at 0
        # when it never saw a response, so classification falls through to Convert-GraphHttpException
        # and the header must still be found and used.
        $Throttle = New-KiotaThrottleException -Header @{ 'Retry-After' = '90' }
        InModuleScope $script:moduleName -Parameters @{ Throttle = $Throttle } {
            $script:Throttle = $Throttle
            Mock Start-Sleep { }
            $script:Attempt = 0
            Mock Invoke-MgGraphRequest {
                $script:Attempt++
                if ($script:Attempt -eq 1) { throw $script:Throttle }
                @{ value = @('status-less') }
            }

            (Invoke-OERGraphRequest -Uri 'v1.0/groups').value | Should -Be 'status-less'
            Should -Invoke Start-Sleep -Times 1 -Exactly -ParameterFilter { $Seconds -eq 90 }
            Should -Invoke Start-Sleep -Times 0 -ParameterFilter { $Seconds -eq 1 }
        }
    }

    It 'accepts the HTTP-date form of Retry-After as well as delta-seconds' {
        # RFC 9110 allows both. The .Response path already handled both; the Kiota path must too.
        $Throttle = New-KiotaThrottleException -Header @{ 'Retry-After' = ([DateTime]::UtcNow.AddSeconds(100).ToString('R')) } -StatusCode 429
        InModuleScope $script:moduleName -Parameters @{ Throttle = $Throttle } {
            $script:Throttle = $Throttle
            Mock Start-Sleep { }
            $script:Attempt = 0
            Mock Invoke-MgGraphRequest {
                $script:Attempt++
                if ($script:Attempt -eq 1) { throw $script:Throttle }
                @{ value = @('dated') }
            }

            (Invoke-OERGraphRequest -Uri 'v1.0/groups').value | Should -Be 'dated'
            # A window, not an equality: the HTTP-date format has one-second resolution and real
            # time passes between building the fixture and reading it.
            Should -Invoke Start-Sleep -Times 1 -Exactly -ParameterFilter { $Seconds -ge 95 -and $Seconds -le 100 }
            Should -Invoke Start-Sleep -Times 0 -ParameterFilter { $Seconds -eq 1 }
        }
    }

    It 'matches Retry-After case-insensitively even though Kiota keys the dictionary ordinally' {
        $Throttle = New-KiotaThrottleException -Header @{ 'retry-after' = '30' } -StatusCode 429
        InModuleScope $script:moduleName -Parameters @{ Throttle = $Throttle } {
            $script:Throttle = $Throttle
            Mock Start-Sleep { }
            $script:Attempt = 0
            Mock Invoke-MgGraphRequest {
                $script:Attempt++
                if ($script:Attempt -eq 1) { throw $script:Throttle }
                @{ value = @('lowercased') }
            }

            (Invoke-OERGraphRequest -Uri 'v1.0/groups').value | Should -Be 'lowercased'
            Should -Invoke Start-Sleep -Times 1 -Exactly -ParameterFilter { $Seconds -eq 30 }
        }
    }

    It 'still falls back exponentially when the real shape carries headers but no Retry-After' {
        $Throttle = New-KiotaThrottleException -Header @{ 'request-id' = 'abc-123' } -StatusCode 429
        InModuleScope $script:moduleName -Parameters @{ Throttle = $Throttle } {
            $script:Throttle = $Throttle
            Mock Start-Sleep { }
            $script:Attempt = 0
            Mock Invoke-MgGraphRequest {
                $script:Attempt++
                if ($script:Attempt -eq 1) { throw $script:Throttle }
                @{ value = @('fell-back') }
            }

            (Invoke-OERGraphRequest -Uri 'v1.0/groups').value | Should -Be 'fell-back'
            Should -Invoke Start-Sleep -Times 1 -Exactly -ParameterFilter { $Seconds -eq 1 }
        }
    }

    It 'reports the wait, its provenance and the remaining budget, and never the header collection' {
        # SECURITY (CLAUDE.md rule 6): this change newly reaches into a response header collection.
        # The fixture plants an Authorization value and a correlation header beside Retry-After;
        # neither may ever reach any stream.
        $Throttle = New-KiotaThrottleException -StatusCode 429 -Header @{
            'Retry-After'   = '60'
            'Authorization' = 'Bearer eyJ0eXAiOiJKV1QiLCJhbGciOiJSUzI1NiJ9.NOT-A-REAL-TOKEN-MUST-NOT-BE-LOGGED'
            'client-request-id' = 'correlation-MUST-NOT-BE-LOGGED'
        }
        $Verbose = InModuleScope $script:moduleName -Parameters @{ Throttle = $Throttle } {
            $script:Throttle = $Throttle
            Mock Start-Sleep { }
            $script:Attempt = 0
            Mock Invoke-MgGraphRequest {
                $script:Attempt++
                if ($script:Attempt -eq 1) { throw $script:Throttle }
                @{ value = @('ok') }
            }
            (Invoke-OERGraphRequest -Uri 'v1.0/groups' -Verbose 4>&1) |
                Where-Object { $_ -is [System.Management.Automation.VerboseRecord] }
        }
        $Text = $Verbose.Message -join "`n"

        # The one observation that proves the fix in a live run: the server's value, named as such,
        # with what is left of the budget after paying it (300 - 60 = 240).
        $Text | Should -Match 'Throttled\. Waiting 60 s \(server-directed\) before retry 1; 240 s of per-REQUEST and 840 s of per-CALL budget remain\.'
        $Text | Should -Not -Match 'MUST-NOT-BE-LOGGED'
        $Text | Should -Not -Match '(?i)authorization'
        $Text | Should -Not -Match '(?i)bearer'
    }

    It 'names the exponential fallback as the source when it supplies the wait' {
        $Throttle = New-KiotaThrottleException -StatusCode 429
        $Verbose = InModuleScope $script:moduleName -Parameters @{ Throttle = $Throttle } {
            $script:Throttle = $Throttle
            Mock Start-Sleep { }
            $script:Attempt = 0
            Mock Invoke-MgGraphRequest {
                $script:Attempt++
                if ($script:Attempt -eq 1) { throw $script:Throttle }
                @{ value = @('ok') }
            }
            (Invoke-OERGraphRequest -Uri 'v1.0/groups' -Verbose 4>&1) |
                Where-Object { $_ -is [System.Management.Automation.VerboseRecord] }
        }
        ($Verbose.Message -join "`n") |
            Should -Match 'Waiting 1 s \(exponential fallback\) before retry 1; 299 s of per-REQUEST and 899 s of per-CALL budget remain\.'
    }

    It 'absorbs a 60 s wait FIVE times over -- the budget the old three-retry ceiling could not buy' {
        # The hard requirement for this branch: one server-directed 60 s wait plus a subsequent
        # retry must fit. 300 s of budget buys five of them, and the sixth does not fit.
        $Throttle = New-KiotaThrottleException -Header @{ 'Retry-After' = '60' } -StatusCode 429
        InModuleScope $script:moduleName -Parameters @{ Throttle = $Throttle } {
            $script:Throttle = $Throttle
            Mock Start-Sleep { }
            Mock Invoke-MgGraphRequest { throw $script:Throttle }

            { Invoke-OERGraphRequest -Uri 'v1.0/groups' } | Should -Throw -ErrorId 'TooManyRequests'
            # 1 initial attempt + 5 retries; the 6th 60 s wait does not fit the 0 s left.
            Should -Invoke Invoke-MgGraphRequest -Times 6 -Exactly
            Should -Invoke Start-Sleep -Times 5 -Exactly -ParameterFilter { $Seconds -eq 60 }
        }
    }
}

Describe 'Invoke-OERGraphRequest -All paging' {
    It 'follows @odata.nextLink and aggregates every page when -All is set' {
        InModuleScope $script:moduleName {
            $script:Page = 0
            Mock Invoke-MgGraphRequest {
                $script:Page++
                switch ($script:Page) {
                    1 { @{ value = @('a', 'b'); '@odata.nextLink' = 'https://graph.microsoft.com/v1.0/groups?$skiptoken=X' } }
                    2 { @{ value = @('c');      '@odata.nextLink' = 'https://graph.microsoft.com/v1.0/groups?$skiptoken=Y' } }
                    default { @{ value = @('d') } }
                }
            }

            $Result = Invoke-OERGraphRequest -Uri 'v1.0/groups' -All

            @($Result.value) | Should -Be @('a', 'b', 'c', 'd')
            Should -Invoke Invoke-MgGraphRequest -Times 3 -Exactly
        }
    }

    It 'feeds the absolute nextLink URL straight back as the next -Uri' {
        InModuleScope $script:moduleName {
            $script:Uris = [System.Collections.Generic.List[string]]::new()
            $script:Page = 0
            Mock Invoke-MgGraphRequest {
                param($Uri)
                $script:Uris.Add([string]$Uri)
                $script:Page++
                if ($script:Page -eq 1) {
                    @{ value = @('a'); '@odata.nextLink' = 'https://graph.microsoft.com/v1.0/groups?$skiptoken=ABC' }
                } else {
                    @{ value = @('b') }
                }
            }

            $null = Invoke-OERGraphRequest -Uri 'v1.0/groups' -All

            $script:Uris[0] | Should -Be 'v1.0/groups'
            $script:Uris[1] | Should -Be 'https://graph.microsoft.com/v1.0/groups?$skiptoken=ABC'
        }
    }

    It 'reads only the first page WITHOUT -All (the switch is strictly opt-in)' {
        InModuleScope $script:moduleName {
            Mock Invoke-MgGraphRequest {
                @{ value = @('a'); '@odata.nextLink' = 'https://graph.microsoft.com/v1.0/groups?$skiptoken=X' }
            }

            $Result = Invoke-OERGraphRequest -Uri 'v1.0/groups'

            @($Result.value) | Should -Be @('a')
            Should -Invoke Invoke-MgGraphRequest -Times 1 -Exactly
        }
    }

    It 'gives each page its own bounded throttle backoff' {
        # The paging loop must wrap the single-request logic, not sit inside it: each page fetch
        # gets a fresh ThrottleWaitBudgetSeconds budget. This mock makes every page need 2 throttled
        # retries before it succeeds (3 calls per page). If the retry budget were instead shared
        # across pages (e.g. the paging loop nested inside the retry loop, or the throttle counter
        # otherwise carried over), page 2's retries would exhaust the shared budget and the call
        # would throw TooManyRequests instead of returning both pages.
        InModuleScope $script:moduleName {
            Mock Start-Sleep { }
            $script:PageNum = 1
            $script:AttemptInPage = 0
            Mock Invoke-MgGraphRequest {
                $script:AttemptInPage++
                if ($script:AttemptInPage -le 2) {
                    $Resp = [System.Net.Http.HttpResponseMessage]::new([System.Net.HttpStatusCode]::TooManyRequests)
                    $Resp.Headers.Add('Retry-After', '1')
                    $Ex = [System.Exception]::new('{"error":{"code":"TooManyRequests","message":"throttled"}}')
                    Add-Member -InputObject $Ex -NotePropertyName Response -NotePropertyValue $Resp
                    throw $Ex
                }
                $script:AttemptInPage = 0
                if ($script:PageNum -eq 1) {
                    $script:PageNum = 2
                    @{ value = @('a'); '@odata.nextLink' = 'https://graph.microsoft.com/v1.0/groups?$skiptoken=X' }
                } else {
                    @{ value = @('b') }
                }
            }

            $Result = Invoke-OERGraphRequest -Uri 'v1.0/groups' -All

            @($Result.value) | Should -Be @('a', 'b')
            # 2 failed attempts + 1 success, per page, times 2 pages.
            Should -Invoke Invoke-MgGraphRequest -Times 6 -Exactly
        }
    }

    It 'bounds a throttled paged read by the per-CALL budget, not by page count' {
        # THE REASON THE PER-PAGE BUDGET IS NOT ENOUGH ON ITS OWN. Invoke-GraphSingle throws out of
        # the paging loop and $AllValues is discarded, so a paged read is all-or-nothing: a per-page
        # budget alone would buy a LONGER WAIT FOR THE SAME TOTAL FAILURE, and the 61-request
        # Get-OERAccessReviewInstance fan-out could pin a session past an hour before throwing.
        #
        # Every page here is throttled twice (Retry-After 3600, clamped to 120) and then succeeds,
        # and the nextLink never runs out, so nothing but the per-call budget can stop it. 900 s
        # buys seven 120 s waits (840 s); the eighth does not fit the 60 s left, so the fourth page
        # gives up on its SECOND attempt. Page count never enters the arithmetic.
        InModuleScope $script:moduleName {
            Mock Start-Sleep { }
            $script:AttemptInPage = 0
            $script:PageNum = 0
            Mock Invoke-MgGraphRequest {
                $script:AttemptInPage++
                if ($script:AttemptInPage -le 2) {
                    $Resp = [System.Net.Http.HttpResponseMessage]::new([System.Net.HttpStatusCode]::TooManyRequests)
                    $Resp.Headers.Add('Retry-After', '3600')
                    $Ex = [System.Exception]::new('{"error":{"code":"TooManyRequests","message":"throttled"}}')
                    Add-Member -InputObject $Ex -NotePropertyName Response -NotePropertyValue $Resp
                    throw $Ex
                }
                $script:AttemptInPage = 0
                $script:PageNum++
                @{ value = @("page$($script:PageNum)"); '@odata.nextLink' = 'https://graph.microsoft.com/v1.0/groups?$skiptoken=X' }
            }

            { Invoke-OERGraphRequest -Uri 'v1.0/groups' -All } | Should -Throw -ErrorId 'TooManyRequests'

            # 3 + 3 + 3 attempts for the three pages that recover, then 2 for the page that cannot.
            Should -Invoke Invoke-MgGraphRequest -Times 11 -Exactly
            # 7 waits of 120 s = 840 s, inside the 900 s ceiling; the 8th is refused.
            Should -Invoke Start-Sleep -Times 7 -Exactly -ParameterFilter { $Seconds -eq 120 }
            Should -Invoke Start-Sleep -Times 7 -Exactly
        }
    }

    It 'names the per-CALL budget, not the per-request one, when the call budget is what stopped it' {
        # "Why did this take fifteen minutes" is the question an operator actually asks, so the two
        # budgets must be distinguishable in the verbose stream. In this scenario the per-request
        # budget never runs out -- each page recovers well inside its 300 s -- so a per-REQUEST
        # give-up line appearing here would mean the wrong bound was reported.
        $Verbose = InModuleScope $script:moduleName {
            Mock Start-Sleep { }
            $script:AttemptInPage = 0
            $script:PageNum = 0
            Mock Invoke-MgGraphRequest {
                $script:AttemptInPage++
                if ($script:AttemptInPage -le 2) {
                    $Resp = [System.Net.Http.HttpResponseMessage]::new([System.Net.HttpStatusCode]::TooManyRequests)
                    $Resp.Headers.Add('Retry-After', '3600')
                    $Ex = [System.Exception]::new('{"error":{"code":"TooManyRequests","message":"throttled"}}')
                    Add-Member -InputObject $Ex -NotePropertyName Response -NotePropertyValue $Resp
                    throw $Ex
                }
                $script:AttemptInPage = 0
                $script:PageNum++
                @{ value = @("page$($script:PageNum)"); '@odata.nextLink' = 'https://graph.microsoft.com/v1.0/groups?$skiptoken=X' }
            }
            # Collected into a List rather than captured from a parenthesised subexpression: this
            # call is EXPECTED to end in a terminating TooManyRequests, and a parenthesised
            # ( ... 4>&1 ) must complete before it yields, so the throw would discard every verbose
            # record and leave the assertions below matching against an empty string -- passing or
            # failing for reasons that have nothing to do with the budget. A List is mutated as the
            # records stream past and survives the throw intact.
            $Records = [System.Collections.Generic.List[object]]::new()
            try {
                Invoke-OERGraphRequest -Uri 'v1.0/groups' -All -Verbose 4>&1 |
                    ForEach-Object { if ($_ -is [System.Management.Automation.VerboseRecord]) { $Records.Add($_) } }
            } catch {
                # Expected: the per-call budget gives up and the Graph error surfaces. The verbose
                # stream, not the error, is what this test is about.
            }
            $Records
        }
        @($Verbose).Count | Should -BeGreaterThan 0 -Because 'an empty verbose capture would make every match below vacuous'
        $Text = $Verbose.Message -join "`n"

        $Text | Should -Match 'only 60 s of the 900 s per-CALL budget remain\. Giving up\.'
        $Text | Should -Not -Match 'per-REQUEST budget remain\. Giving up\.'
        # Each wait line reports both budgets so the remaining call time is visible as it drains.
        $Text | Should -Match 's of per-REQUEST and \d+ s of per-CALL budget remain\.'
    }

    It 'treats a null page (empty GET body) as the end of the collection instead of throwing' {
        # A -All GET can come back with an empty body once paging is underway (the reachable
        # production shape: page 1 carries a real nextLink, a later page has nothing left to return).
        # Without the guard, indexing into that $null page with the bracket operator the loop uses
        # for '@odata.nextLink' raises a non-terminating InvalidOperation ("Cannot index into a null
        # array") that becomes TERMINATING under a caller's -ErrorAction Stop.
        # NOTE: `{ } | Should -Not -Throw` opens a NEW scope and silently drops -ErrorVariable, so
        # this uses try/catch plus an explicit $global:Error check instead of that idiom.
        $global:Error.Clear()
        InModuleScope $script:moduleName {
            $script:Page = 0
            Mock Invoke-MgGraphRequest {
                $script:Page++
                if ($script:Page -eq 1) {
                    @{ value = @('a', 'b'); '@odata.nextLink' = 'https://graph.microsoft.com/v1.0/groups?$skiptoken=X' }
                } else {
                    $null
                }
            }

            $Caught = $null
            $Result = $null
            try {
                $Result = Invoke-OERGraphRequest -Uri 'v1.0/groups' -All
            } catch {
                $Caught = $PSItem
            }

            $Caught | Should -BeNullOrEmpty
            @($Result.value) | Should -Be @('a', 'b')
            Should -Invoke Invoke-MgGraphRequest -Times 2 -Exactly
            $global:Error.Count | Should -Be 0
        }
    }
}

Describe 'Invoke-OERGraphRequest verbose output' {
    It 'emits one verbose line naming the method and uri' {
        Mock -ModuleName $script:moduleName Invoke-MgGraphRequest { @{ value = @() } }
        $Verbose = InModuleScope $script:moduleName {
            (Invoke-OERGraphRequest -Method POST -Uri 'v1.0/groups' -Body @{ displayName = 'x' } -Verbose 4>&1) |
                Where-Object { $_ -is [System.Management.Automation.VerboseRecord] }
        }
        ($Verbose.Message -join "`n") | Should -Match '\[Invoke-OERGraphRequest\] POST v1\.0/groups'
    }

    It 'never writes the request body or an authorization header to the verbose stream' {
        Mock -ModuleName $script:moduleName Invoke-MgGraphRequest { @{ value = @() } }
        $Verbose = InModuleScope $script:moduleName {
            (Invoke-OERGraphRequest -Method POST -Uri 'v1.0/groups' -Body @{ secretish = 'do-not-log-me' } -Verbose 4>&1) |
                Where-Object { $_ -is [System.Management.Automation.VerboseRecord] }
        }
        $Text = $Verbose.Message -join "`n"
        $Text | Should -Not -Match 'do-not-log-me'
        $Text | Should -Not -Match '(?i)bearer'
        $Text | Should -Not -Match '(?i)authorization'
    }

    It 'emits no verbose line when -Verbose is not requested' {
        Mock -ModuleName $script:moduleName Invoke-MgGraphRequest { @{ value = @() } }
        $Verbose = InModuleScope $script:moduleName {
            (Invoke-OERGraphRequest -Uri 'v1.0/groups' 4>&1) |
                Where-Object { $_ -is [System.Management.Automation.VerboseRecord] }
        }
        $Verbose | Should -BeNullOrEmpty
    }

    It 'still returns the response unchanged when verbose is on' {
        Mock -ModuleName $script:moduleName Invoke-MgGraphRequest { @{ value = @('a', 'b') } }
        $Result = InModuleScope $script:moduleName {
            Invoke-OERGraphRequest -Uri 'v1.0/groups' -Verbose 4>$null
        }
        $Result.value.Count | Should -Be 2
    }
}

Describe 'Invoke-OERGraphRequest header-collection shapes (live-run regression)' {
    # A live Get-OERInventory read of 100 groups returned 288 error records. One in three was this:
    #
    #   MethodInvocationException: Exception calling "GetValues" with "1" argument(s):
    #   "The given header was not found."
    #
    # System.Net.Http.Headers.HttpResponseHeaders.GetValues(name) THROWS when the header is absent,
    # and absent is the normal case on every non-throttled failure. The throw was caught, but
    # -ErrorVariable is populated by the ENGINE from the error stream and captures records raised
    # inside nested calls even when an inner catch swallowed them, so it still reached the caller.
    # That half of the defect is proved end to end in Get-OERGroup.Tests.ps1, where the live read
    # actually happened.
    #
    # The second half is silent, and is what this Describe pins. HttpResponseHeaders has NO .Keys
    # member: '$Headers.Keys' neither throws nor enumerates header names -- PowerShell member
    # enumeration simply yields nothing -- so the old 'foreach ($Key in @($Headers.Keys))' walk in
    # Get-ResponseFactFromException iterated once over $null and MISSED a Retry-After that was
    # genuinely present. Every fixture in the suite above used either the Kiota dictionary (which
    # does have .Keys) or the strongly typed .Response.Headers.RetryAfter property, so the suite was
    # green while the walk was inert on the remaining shape. Both shapes now go through the single
    # owner Get-RetryAfterHeaderValue, which discriminates on PSObject.Properties['Keys'].
    BeforeAll {
        Mock -ModuleName $script:moduleName Initialize-OERAuth { }
    }

    It 'honours a Retry-After carried on an HttpResponseHeaders reached through .ResponseHeaders' {
        InModuleScope $script:moduleName {
            Mock Start-Sleep { }          # MUST be mocked: a real sleep makes the gate slow and flaky
            $script:HeaderShapeAttempt = 0
            Mock Invoke-MgGraphRequest {
                $script:HeaderShapeAttempt++
                if ($script:HeaderShapeAttempt -eq 1) {
                    $Headers = [System.Net.Http.HttpResponseMessage]::new([System.Net.HttpStatusCode]::TooManyRequests).Headers
                    $Headers.TryAddWithoutValidation('Retry-After', '9') | Out-Null
                    $Ex = [System.Exception]::new('HTTP request failed with status code: TooManyRequests.')
                    Add-Member -InputObject $Ex -NotePropertyName ResponseStatusCode -NotePropertyValue 429
                    Add-Member -InputObject $Ex -NotePropertyName ResponseHeaders -NotePropertyValue $Headers
                    throw $Ex
                }
                @{ value = @('recovered') }
            }

            $Result = Invoke-OERGraphRequest -Uri 'v1.0/groups'

            $Result.value | Should -Be 'recovered'
            # -Exactly on both: Should -Invoke -Times N is at-least semantics in Pester v5.
            Should -Invoke Invoke-MgGraphRequest -Times 2 -Exactly
            # 9, not 1. A 1 here means the header was missed and the exponential fallback ran
            # instead -- which is exactly what the .Keys walk did on this shape.
            Should -Invoke Start-Sleep -Times 1 -Exactly -ParameterFilter { $Seconds -eq 9 }
        }
    }

    It 'still honours a Retry-After carried on the documented Kiota dictionary shape' {
        # The other half of the pair, and the reason the reader cannot simply be rewritten to
        # enumerate: PowerShell's foreach does NOT enumerate a dictionary element-by-element -- a
        # dictionary is a single item to foreach -- so a reader written only for HttpResponseHeaders
        # would break the shape the module was originally fixed for.
        InModuleScope $script:moduleName {
            Mock Start-Sleep { }
            $script:DictShapeAttempt = 0
            Mock Invoke-MgGraphRequest {
                $script:DictShapeAttempt++
                if ($script:DictShapeAttempt -eq 1) {
                    $Headers = [System.Collections.Generic.Dictionary[string, System.Collections.Generic.IEnumerable[string]]]::new(
                        [System.StringComparer]::Ordinal)
                    $Headers['Retry-After'] = [string[]]@('11')
                    $Ex = [System.Exception]::new('HTTP request failed with status code: TooManyRequests.')
                    Add-Member -InputObject $Ex -NotePropertyName ResponseStatusCode -NotePropertyValue 429
                    Add-Member -InputObject $Ex -NotePropertyName ResponseHeaders -NotePropertyValue $Headers
                    throw $Ex
                }
                @{ value = @('recovered') }
            }

            $Result = Invoke-OERGraphRequest -Uri 'v1.0/groups'

            $Result.value | Should -Be 'recovered'
            Should -Invoke Invoke-MgGraphRequest -Times 2 -Exactly
            Should -Invoke Start-Sleep -Times 1 -Exactly -ParameterFilter { $Seconds -eq 11 }
        }
    }

    It 'reads Retry-After case-insensitively on the ordinal-comparer dictionary, as HTTP requires' {
        # Kiota builds its dictionary with the ORDINAL comparer, so an indexer lookup by literal
        # name would be casing-sensitive; HTTP header names are not.
        InModuleScope $script:moduleName {
            Mock Start-Sleep { }
            $script:CasingAttempt = 0
            Mock Invoke-MgGraphRequest {
                $script:CasingAttempt++
                if ($script:CasingAttempt -eq 1) {
                    $Headers = [System.Collections.Generic.Dictionary[string, System.Collections.Generic.IEnumerable[string]]]::new(
                        [System.StringComparer]::Ordinal)
                    $Headers['retry-after'] = [string[]]@('13')
                    $Ex = [System.Exception]::new('HTTP request failed with status code: TooManyRequests.')
                    Add-Member -InputObject $Ex -NotePropertyName ResponseStatusCode -NotePropertyValue 429
                    Add-Member -InputObject $Ex -NotePropertyName ResponseHeaders -NotePropertyValue $Headers
                    throw $Ex
                }
                @{ value = @('recovered') }
            }

            $null = Invoke-OERGraphRequest -Uri 'v1.0/groups'

            Should -Invoke Start-Sleep -Times 1 -Exactly -ParameterFilter { $Seconds -eq 13 }
        }
    }

    It 'returns no Retry-After, and does not throw, on a header collection of neither shape' {
        # The reader runs on the wrapper's FAILURE path, where an escaping exception would REPLACE
        # the real Graph error the caller needs to see. A string is neither a dictionary nor an
        # HttpResponseHeaders; it must yield nothing and stay silent. A 503 is retried ONLY when it
        # carries a Retry-After, so "no sleep, real error surfaced" is the observable proof.
        InModuleScope $script:moduleName {
            Mock Start-Sleep { }
            Mock Invoke-MgGraphRequest {
                $Ex = [System.Exception]::new('{"error":{"code":"ServiceUnavailable","message":"down"}}')
                Add-Member -InputObject $Ex -NotePropertyName ResponseStatusCode -NotePropertyValue 503
                Add-Member -InputObject $Ex -NotePropertyName ResponseHeaders -NotePropertyValue 'not-a-header-collection'
                throw $Ex
            }
            { Invoke-OERGraphRequest -Uri 'v1.0/groups' } | Should -Throw -ErrorId 'ServiceUnavailable'
            Should -Invoke Start-Sleep -Times 0 -Exactly
        }
    }
}

Describe 'Invoke-OERGraphRequest -ExpectedErrorCode' {
    # WHY THE TRANSPORT IS A PLAIN FUNCTION STUB HERE AND NOT A PESTER MOCK.
    #
    # -StatusCodeVariable and -ResponseHeadersVariable are set by the SDK in the scope that INVOKED
    # the cmdlet -- a binary cmdlet pushes no scope of its own. A Pester mock body runs several
    # frames below the module function, so nothing it sets with Set-Variable can land where the
    # wrapper reads. A plain function declared in this block is resolved through the same dynamic
    # scope chain the real cmdlet would be, so "-Scope 1" from inside it is exactly one frame up --
    # Invoke-GraphAttempt -- which is where the real cmdlet writes.
    #
    # The stub is declared WITHOUT a script: or global: qualifier, so it lives only for the
    # InModuleScope block that declares it. A leaked stub of a real cmdlet name shadows that cmdlet
    # for the rest of the Pester process; do not "tidy" these into a shared BeforeAll.
    #
    # Every Remove-Item sits in a FINALLY rather than after the assertions. Measured, that is
    # belt-and-braces today and not a bug fix: an It whose assertion fails before reaching its
    # Remove-Item still leaves the cmdlet name bound to the real Cmdlet, in the same Describe and in
    # a later one, so the unqualified declaration really is block-scoped. The finally is here so the
    # line MEANS what it reads as -- cleanup that a failing assertion cannot skip -- and so that a
    # stub written with a script:/global: qualifier some day cannot quietly outlive its block.
    BeforeAll {
        $script:NotOnboardedBody =
        '{"error":{"code":"ResourceTypeNotSupported","message":"Resource type not supported for onboarding"}}'
    }

    It 'returns a marker and raises NOTHING into the caller''s -ErrorVariable for a declared code' {
        # The headline assertion, and the whole point of the parameter. A live
        # Get-OERInventory -Include Groups read of 100 groups, 96 of them not onboarded, put 261
        # records into the caller's -ErrorVariable for an entirely normal read. Counting the
        # collection is the only proof that holds: -ErrorVariable is filled by the ENGINE and
        # collects records raised inside nested calls even when an inner catch swallowed them, so
        # asserting on what this function PUBLISHED would pass with the whole feature deleted.
        $Body = $script:NotOnboardedBody
        InModuleScope $script:moduleName -Parameters @{ Body = $Body } {
            param($Body)
            try {
                function Invoke-MgGraphRequest {
                    [CmdletBinding()]
                    param([string]$Method, [string]$Uri, $Body, [switch]$SkipHttpErrorCheck,
                        [string]$StatusCodeVariable, [string]$ResponseHeadersVariable)
                    # Both halves of InvokeMgGraphRequest.cs, so removing the switch from the wrapper
                    # restores the raising behaviour and this test moves for the right reason.
                    if (-not $SkipHttpErrorCheck) { throw [System.Exception]::new($script:ExpectedBody) }
                    Set-Variable -Name $StatusCodeVariable -Value 400 -Scope 1
                    return ($script:ExpectedBody | ConvertFrom-Json -AsHashtable)
                }
                $script:ExpectedBody = $Body

                $Err = $null
                $Result = Invoke-OERGraphRequest -Uri 'beta/x' -ExpectedErrorCode 'ResourceTypeNotSupported' `
                    -ErrorAction SilentlyContinue -ErrorVariable Err

                @($Result.PSObject.TypeNames) -contains 'Omnicit.EntraRBAC.GraphExpectedError' |
                    Should -BeTrue -Because 'a declared code is an answer and must come back as data'
                $Result.ExpectedErrorCode | Should -Be 'ResourceTypeNotSupported'
                $Result.StatusCode | Should -Be 400
                @($Err).Count | Should -Be 0 -Because 'an expected answer must leave the caller''s error collection untouched'
            } finally {
                Remove-Item 'function:Invoke-MgGraphRequest'
            }
        }
    }

    It 'asks the SDK to skip its HTTP error check ONLY when a code is declared' {
        # -SkipHttpErrorCheck is what stops the SDK's own ThrowTerminatingError, and that throw is
        # the source of the two records no catch in this module can suppress. Measured: without it
        # the best a swallowed error can do is 2 records per failure; with it, 0.
        InModuleScope $script:moduleName {
            try {
                $Seen = [System.Collections.Generic.List[bool]]::new()
                function Invoke-MgGraphRequest {
                    [CmdletBinding()]
                    param([string]$Method, [string]$Uri, $Body, [switch]$SkipHttpErrorCheck,
                        [string]$StatusCodeVariable, [string]$ResponseHeadersVariable)
                    $Seen.Add([bool]$SkipHttpErrorCheck)
                    return @{ value = @('ok') }
                }

                $null = Invoke-OERGraphRequest -Uri 'v1.0/groups'
                $null = Invoke-OERGraphRequest -Uri 'beta/x' -ExpectedErrorCode 'ResourceTypeNotSupported'

                @($Seen).Count | Should -Be 2
                $Seen[0] | Should -BeFalse -Because 'every existing call site must keep the exact -ErrorAction Stop transport it has always had'
                $Seen[1] | Should -BeTrue
            } finally {
                Remove-Item 'function:Invoke-MgGraphRequest'
            }
        }
    }

    It 'still throws a DIFFERENT Graph code on the very same call' {
        # An over-broad softening here would hide real failures across the whole module. Only the
        # codes the caller named may be answered as data.
        InModuleScope $script:moduleName {
            try {
                function Invoke-MgGraphRequest {
                    [CmdletBinding()]
                    param([string]$Method, [string]$Uri, $Body, [switch]$SkipHttpErrorCheck,
                        [string]$StatusCodeVariable, [string]$ResponseHeadersVariable)
                    Set-Variable -Name $StatusCodeVariable -Value 403 -Scope 1
                    return ('{"error":{"code":"Authorization_RequestDenied","message":"Insufficient privileges"}}' |
                            ConvertFrom-Json -AsHashtable)
                }

                { Invoke-OERGraphRequest -Uri 'beta/x' -ExpectedErrorCode 'ResourceTypeNotSupported' } |
                    Should -Throw -ErrorId 'Authorization_RequestDenied'
            } finally {
                Remove-Item 'function:Invoke-MgGraphRequest'
            }
        }
    }

    It 'refuses a longer code that merely STARTS with the declared text' {
        # ResourceTypeNotSupportedInThisTenant is a different failure. A prefix match would report
        # it as "no eligibility" and turn a failed read into a silent empty fact -- issue #76.
        InModuleScope $script:moduleName {
            try {
                function Invoke-MgGraphRequest {
                    [CmdletBinding()]
                    param([string]$Method, [string]$Uri, $Body, [switch]$SkipHttpErrorCheck,
                        [string]$StatusCodeVariable, [string]$ResponseHeadersVariable)
                    Set-Variable -Name $StatusCodeVariable -Value 400 -Scope 1
                    return ('{"error":{"code":"ResourceTypeNotSupportedInThisTenant","message":"different failure"}}' |
                            ConvertFrom-Json -AsHashtable)
                }

                { Invoke-OERGraphRequest -Uri 'beta/x' -ExpectedErrorCode 'ResourceTypeNotSupported' } |
                    Should -Throw -ErrorId 'ResourceTypeNotSupportedInThisTenant'
            } finally {
                Remove-Item 'function:Invoke-MgGraphRequest'
            }
        }
    }

    It 'still honours Retry-After and retries a 429 that arrives as DATA' {
        # The soft-failure path must feed the SAME throttle machinery, not bypass it. Under
        # -SkipHttpErrorCheck a 429 is no longer an exception, so a wrapper that only inspected
        # thrown records would hand the caller a throttle body as though it were a result.
        InModuleScope $script:moduleName {
            try {
                Mock Start-Sleep { }
                $Calls = [System.Collections.Generic.List[int]]::new()
                function Invoke-MgGraphRequest {
                    [CmdletBinding()]
                    param([string]$Method, [string]$Uri, $Body, [switch]$SkipHttpErrorCheck,
                        [string]$StatusCodeVariable, [string]$ResponseHeadersVariable)
                    $Calls.Add(1)
                    if ($Calls.Count -eq 1) {
                        $Headers = [System.Collections.Generic.Dictionary[string, System.Collections.Generic.IEnumerable[string]]]::new(
                            [System.StringComparer]::OrdinalIgnoreCase)
                        $Headers['Retry-After'] = [string[]]@('17')
                        Set-Variable -Name $StatusCodeVariable -Value 429 -Scope 1
                        Set-Variable -Name $ResponseHeadersVariable -Value $Headers -Scope 1
                        return ('{"error":{"code":"TooManyRequests","message":"Too many requests"}}' |
                                ConvertFrom-Json -AsHashtable)
                    }
                    Set-Variable -Name $StatusCodeVariable -Value 200 -Scope 1
                    return @{ value = @('recovered') }
                }

                $Result = Invoke-OERGraphRequest -Uri 'beta/x' -ExpectedErrorCode 'ResourceTypeNotSupported'
                $Result.value | Should -Be 'recovered'
                @($Calls).Count | Should -Be 2
                Should -Invoke Start-Sleep -Times 1 -Exactly -ParameterFilter { $Seconds -eq 17 }
            } finally {
                Remove-Item 'function:Invoke-MgGraphRequest'
            }
        }
    }

    It 'returns an ordinary response unchanged when the status variable never resolves' {
        # $null -as [int] is 0, NOT $null, so a naive read makes an unset status look like the
        # literal status 0 and rebuilds EVERY answer -- successes included -- as a failure.
        InModuleScope $script:moduleName {
            try {
                function Invoke-MgGraphRequest {
                    [CmdletBinding()]
                    param([string]$Method, [string]$Uri, $Body, [switch]$SkipHttpErrorCheck,
                        [string]$StatusCodeVariable, [string]$ResponseHeadersVariable)
                    return @{ value = @('ok') }   # sets NO status variable at all
                }

                $Err = $null
                $Result = Invoke-OERGraphRequest -Uri 'beta/x' -ExpectedErrorCode 'ResourceTypeNotSupported' `
                    -ErrorAction SilentlyContinue -ErrorVariable Err
                $Result.value | Should -Be 'ok'
                @($Err).Count | Should -Be 0
            } finally {
                Remove-Item 'function:Invoke-MgGraphRequest'
            }
        }
    }

    It 'refuses to hand back a Graph ERROR BODY as data when the status variable never resolves' {
        # The failure direction that matters. If the status could not be read, treating the answer
        # as a success would return an error body as though it were a result -- a silent wrong
        # answer, far worse than the noisy one this parameter removes. A Graph error response always
        # carries a top-level 'error' object; an ordinary response never does.
        InModuleScope $script:moduleName {
            try {
                function Invoke-MgGraphRequest {
                    [CmdletBinding()]
                    param([string]$Method, [string]$Uri, $Body, [switch]$SkipHttpErrorCheck,
                        [string]$StatusCodeVariable, [string]$ResponseHeadersVariable)
                    return ('{"error":{"code":"Authorization_RequestDenied","message":"Insufficient privileges"}}' |
                            ConvertFrom-Json -AsHashtable)   # sets NO status variable
                }

                { Invoke-OERGraphRequest -Uri 'beta/x' -ExpectedErrorCode 'ResourceTypeNotSupported' } |
                    Should -Throw -ErrorId 'Authorization_RequestDenied'
            } finally {
                Remove-Item 'function:Invoke-MgGraphRequest'
            }
        }
    }

    It 'still answers with the marker when the SDK raises despite the switch' {
        # Graceful degradation, and the reason the catch keeps its own expected-code test. A
        # connection-level failure has no HTTP response to skip, and an SDK build that ignored
        # -SkipHttpErrorCheck would land here too. The caller still gets its answer; only the two
        # records the SDK itself raises, which no code in this module can suppress, remain.
        InModuleScope $script:moduleName {
            try {
                function Invoke-MgGraphRequest {
                    [CmdletBinding()]
                    param([string]$Method, [string]$Uri, $Body, [switch]$SkipHttpErrorCheck,
                        [string]$StatusCodeVariable, [string]$ResponseHeadersVariable)
                    throw [System.Exception]::new(
                        '{"error":{"code":"ResourceTypeNotSupported","message":"Resource type not supported for onboarding"}}')
                }

                $Result = Invoke-OERGraphRequest -Uri 'beta/x' -ExpectedErrorCode 'ResourceTypeNotSupported'
                @($Result.PSObject.TypeNames) -contains 'Omnicit.EntraRBAC.GraphExpectedError' | Should -BeTrue
                $Result.ExpectedErrorCode | Should -Be 'ResourceTypeNotSupported'
            } finally {
                Remove-Item 'function:Invoke-MgGraphRequest'
            }
        }
    }

    It 'hands the marker back from -All instead of aggregating it as a page' {
        # The marker has no value property. Aggregating it would append @($null) and report one
        # phantom item -- a failed read recorded as a one-element fact.
        InModuleScope $script:moduleName {
            try {
                function Invoke-MgGraphRequest {
                    [CmdletBinding()]
                    param([string]$Method, [string]$Uri, $Body, [switch]$SkipHttpErrorCheck,
                        [string]$StatusCodeVariable, [string]$ResponseHeadersVariable)
                    Set-Variable -Name $StatusCodeVariable -Value 400 -Scope 1
                    return ('{"error":{"code":"ResourceTypeNotSupported","message":"nope"}}' |
                            ConvertFrom-Json -AsHashtable)
                }

                $Result = Invoke-OERGraphRequest -Uri 'beta/x' -All -ExpectedErrorCode 'ResourceTypeNotSupported'
                @($Result.PSObject.TypeNames) -contains 'Omnicit.EntraRBAC.GraphExpectedError' | Should -BeTrue
                $Result.PSObject.Properties.Name -contains 'value' |
                    Should -BeFalse -Because 'the marker is an answer about the read, never a page of it'
            } finally {
                Remove-Item 'function:Invoke-MgGraphRequest'
            }
        }
    }

    It 'matches a declared code carried only in a status-derived record''s detail text' {
        # Convert-GraphHttpException falls back to a STATUS-derived id ('BadRequest') whenever it
        # cannot extract error.code from the body, leaving the code only in the "<code>: <message>"
        # detail. Reading the id alone would miss it there.
        InModuleScope $script:moduleName {
            try {
                function Invoke-MgGraphRequest {
                    [CmdletBinding()]
                    param([string]$Method, [string]$Uri, $Body, [switch]$SkipHttpErrorCheck,
                        [string]$StatusCodeVariable, [string]$ResponseHeadersVariable)
                    Set-Variable -Name $StatusCodeVariable -Value 400 -Scope 1
                    # A body with an 'error' object but no extractable code, so the converter falls back
                    # to 'BadRequest' and the code survives only in the message text.
                    return @{ error = @{ message = 'ResourceTypeNotSupported: not onboarded' } }
                }

                $Result = Invoke-OERGraphRequest -Uri 'beta/x' -ExpectedErrorCode 'ResourceTypeNotSupported'
                @($Result.PSObject.TypeNames) -contains 'Omnicit.EntraRBAC.GraphExpectedError' | Should -BeTrue
            } finally {
                Remove-Item 'function:Invoke-MgGraphRequest'
            }
        }
    }
}

Describe 'Invoke-OERGraphRequest -ExpectedErrorCode refuses to soften a failure Graph named differently' {
    # THE DEFECT. The expected-code match used to read the record's detail text unconditionally and
    # split it on ':'. A genuine 403 whose PROSE happens to mention the declared code as a
    # colon-delimited token was therefore reported as the expected answer -- measured, this exact
    # body came back as the marker with StatusCode 403, and Get-OERGroup then recorded
    # PimEligibility = @(). That is a failed read stored as an empty fact: issue #76's own defect
    # class, reintroduced through the softening that was meant to be harmless.
    #
    # Graph NAMED this failure Authorization_RequestDenied. When Graph has named the failure, that
    # name is the answer and the message prose is not consulted; the detail text is read only when
    # the converter had to derive the id from the HTTP status instead.
    #
    # The stub is removed in a finally, not after the assertions, so a failing assertion cannot skip
    # the removal -- see the Describe above for what that is and is not worth.
    It 'throws a 403 whose message merely mentions the declared code as a colon-delimited token' {
        InModuleScope $script:moduleName {
            try {
                function Invoke-MgGraphRequest {
                    [CmdletBinding()]
                    param([string]$Method, [string]$Uri, $Body, [switch]$SkipHttpErrorCheck,
                        [string]$StatusCodeVariable, [string]$ResponseHeadersVariable)
                    Set-Variable -Name $StatusCodeVariable -Value 403 -Scope 1
                    return ('{"error":{"code":"Authorization_RequestDenied","message":"Insufficient privileges: ResourceTypeNotSupported"}}' |
                            ConvertFrom-Json -AsHashtable)
                }

                # The exact payload the reviewer measured being softened into an empty fact.
                { Invoke-OERGraphRequest -Uri 'beta/x' -ExpectedErrorCode 'ResourceTypeNotSupported' } |
                    Should -Throw -ErrorId 'Authorization_RequestDenied'
            } finally {
                Remove-Item 'function:Invoke-MgGraphRequest'
            }
        }
    }

    It 'returns no marker for that 403 under -All either' {
        InModuleScope $script:moduleName {
            try {
                function Invoke-MgGraphRequest {
                    [CmdletBinding()]
                    param([string]$Method, [string]$Uri, $Body, [switch]$SkipHttpErrorCheck,
                        [string]$StatusCodeVariable, [string]$ResponseHeadersVariable)
                    Set-Variable -Name $StatusCodeVariable -Value 403 -Scope 1
                    return ('{"error":{"code":"Authorization_RequestDenied","message":"Insufficient privileges: ResourceTypeNotSupported"}}' |
                            ConvertFrom-Json -AsHashtable)
                }

                $Thrown = $null
                $Result = $null
                try { $Result = Invoke-OERGraphRequest -Uri 'beta/x' -All -ExpectedErrorCode 'ResourceTypeNotSupported' }
                catch { $Thrown = $PSItem }

                $Thrown | Should -Not -BeNullOrEmpty -Because 'a genuine 403 must still terminate the read'
                $Thrown.FullyQualifiedErrorId | Should -Match 'Authorization_RequestDenied'
                @($Result.PSObject.TypeNames) -contains 'Omnicit.EntraRBAC.GraphExpectedError' |
                    Should -BeFalse -Because 'a failure Graph named itself is never an expected answer'
            } finally {
                Remove-Item 'function:Invoke-MgGraphRequest'
            }
        }
    }

    It 'still matches a declared code in the detail text when the id IS status-derived' {
        # The allowance the guard above must not break: the converter falls back to a status-derived
        # id whenever it cannot read error.code from the body, and the code then lives only in the
        # "<code>: <message>" detail. That is the one case where the prose is authoritative.
        InModuleScope $script:moduleName {
            try {
                function Invoke-MgGraphRequest {
                    [CmdletBinding()]
                    param([string]$Method, [string]$Uri, $Body, [switch]$SkipHttpErrorCheck,
                        [string]$StatusCodeVariable, [string]$ResponseHeadersVariable)
                    Set-Variable -Name $StatusCodeVariable -Value 400 -Scope 1
                    return @{ error = @{ message = 'ResourceTypeNotSupported: not onboarded' } }
                }

                $Result = Invoke-OERGraphRequest -Uri 'beta/x' -ExpectedErrorCode 'ResourceTypeNotSupported'
                @($Result.PSObject.TypeNames) -contains 'Omnicit.EntraRBAC.GraphExpectedError' | Should -BeTrue
            } finally {
                Remove-Item 'function:Invoke-MgGraphRequest'
            }
        }
    }
}

Describe 'Invoke-OERGraphRequest -All refuses to answer a partly-read enumeration with the marker' {
    # A declared code means "there is nothing here to read", which only the FIRST request of an
    # enumeration can honestly answer. Measured before the page gate: page 1 yielded 3 items, page 2
    # answered the declared code, and the marker went back to the caller verbatim -- Get-OERGroup
    # then reported the group as having no eligibility at all and three real items vanished. That is
    # the same "failed read recorded as an empty fact" the softening exists to avoid.
    It 'raises instead of discarding the pages already aggregated' {
        InModuleScope $script:moduleName {
            try {
                $Pages = [System.Collections.Generic.List[int]]::new()
                function Invoke-MgGraphRequest {
                    [CmdletBinding()]
                    param([string]$Method, [string]$Uri, $Body, [switch]$SkipHttpErrorCheck,
                        [string]$StatusCodeVariable, [string]$ResponseHeadersVariable)
                    $Pages.Add(1)
                    if ($Pages.Count -eq 1) {
                        Set-Variable -Name $StatusCodeVariable -Value 200 -Scope 1
                        return @{ value = @('a', 'b', 'c'); '@odata.nextLink' = 'https://graph.microsoft.com/beta/x?skip=3' }
                    }
                    Set-Variable -Name $StatusCodeVariable -Value 400 -Scope 1
                    return ('{"error":{"code":"ResourceTypeNotSupported","message":"nope"}}' |
                            ConvertFrom-Json -AsHashtable)
                }

                $Thrown = $null
                $Result = $null
                try { $Result = Invoke-OERGraphRequest -Uri 'beta/x' -All -ExpectedErrorCode 'ResourceTypeNotSupported' }
                catch { $Thrown = $PSItem }

                $Result | Should -BeNullOrEmpty -Because 'three real items must never be reported as an empty answer'
                $Thrown | Should -Not -BeNullOrEmpty
                $Thrown.FullyQualifiedErrorId | Should -Match 'GraphExpectedCodeOnLaterPage'
                # Deliberately NOT the Graph code. A caller's own last-line-of-defence match reads
                # the error id, so naming this record 'ResourceTypeNotSupported' would let the very
                # loss it reports be re-read as the expected answer.
                $Thrown.FullyQualifiedErrorId | Should -Not -Match 'ResourceTypeNotSupported'
                $Thrown.Exception.Message | Should -Match '3 item'
                @($Pages).Count | Should -Be 2
            } finally {
                Remove-Item 'function:Invoke-MgGraphRequest'
            }
        }
    }

    It 'still returns the marker when the very first page answers with the declared code' {
        # The other half of the gate. Page one HAS no aggregated items to lose, so the code is a
        # genuine "nothing here" answer and must stay soft -- this is the not-onboarded case the
        # whole parameter exists for.
        InModuleScope $script:moduleName {
            try {
                $Pages = [System.Collections.Generic.List[int]]::new()
                function Invoke-MgGraphRequest {
                    [CmdletBinding()]
                    param([string]$Method, [string]$Uri, $Body, [switch]$SkipHttpErrorCheck,
                        [string]$StatusCodeVariable, [string]$ResponseHeadersVariable)
                    $Pages.Add(1)
                    Set-Variable -Name $StatusCodeVariable -Value 400 -Scope 1
                    return ('{"error":{"code":"ResourceTypeNotSupported","message":"nope"}}' |
                            ConvertFrom-Json -AsHashtable)
                }

                $Err = $null
                $Result = Invoke-OERGraphRequest -Uri 'beta/x' -All -ExpectedErrorCode 'ResourceTypeNotSupported' `
                    -ErrorAction SilentlyContinue -ErrorVariable Err
                @($Result.PSObject.TypeNames) -contains 'Omnicit.EntraRBAC.GraphExpectedError' | Should -BeTrue
                @($Err).Count | Should -Be 0
                @($Pages).Count | Should -Be 1
            } finally {
                Remove-Item 'function:Invoke-MgGraphRequest'
            }
        }
    }
}

Describe 'Invoke-OERGraphRequest token-rejected 401 detection reads the real Kiota exception shape' {
    # Issue #75: the token-rejected/401 branch used to read
    # [int]$AttemptError.Exception.Response.StatusCode directly, a member
    # Microsoft.Kiota.Abstractions.ApiException does not have, so $StatusCode stayed $null against a
    # 401 wrapped in that shape and only the message-text regex could still recognize it. The fix
    # routes the status read through Get-ResponseFactFromException first (the SAME single helper
    # Get-ThrottleDelay uses), falling back to .Response.StatusCode only when the primary walk
    # returns $null.
    #
    # This Describe builds a REAL ApiException from the shipped DLL, the same technique as the
    # throttle Describe above (~line 545), but with its OWN BeforeAll and its OWN factory: per this
    # task's brief, it does not reach into that Describe's scope and does not modify it.
    BeforeAll {
        $ModuleBase = (Get-Module Microsoft.Graph.Authentication | Select-Object -First 1).ModuleBase
        if (-not $ModuleBase) {
            $ModuleBase = (Get-Module Microsoft.Graph.Authentication -ListAvailable |
                Sort-Object Version -Descending | Select-Object -First 1).ModuleBase
        }
        $script:TokenRejectedKiotaDll = $null
        if ($ModuleBase) {
            $DllSearch = @{
                LiteralPath = $ModuleBase
                Recurse     = $true
                File        = $true
                Filter      = 'Microsoft.Kiota.Abstractions.dll'
                ErrorAction = 'SilentlyContinue'
            }
            $script:TokenRejectedKiotaDll = Get-ChildItem @DllSearch | Select-Object -First 1
        }
        $script:TokenRejectedApiExceptionType = $null
        if ($script:TokenRejectedKiotaDll) {
            # LoadFrom is idempotent for a path already loaded, and nothing in this suite makes a
            # real Graph call, so nothing depends on which load context the assembly lands in.
            $script:TokenRejectedApiExceptionType = [System.Reflection.Assembly]::LoadFrom($script:TokenRejectedKiotaDll.FullName).
                GetType('Microsoft.Kiota.Abstractions.ApiException')
        }

        # Builds a real Microsoft.Kiota.Abstractions.ApiException carrying ResponseStatusCode -- the
        # shape a 401 arrives in when it survives Kiota's own RetryHandler (see the source comment at
        # the token-rejected branch for why that narrow case, not the ordinary 401, is the one this
        # fix closes). -NestingDepth 0 (default) returns the ApiException itself, which is also what
        # a claims-challenge fixture needs: Get-ClaimsFromException reads only the TOP-level
        # exception's Message, so wrapping would hide a challenge text planted on the inner instance.
        # -NestingDepth 1 wraps it in an AggregateException carrying the SAME message text, mirroring
        # AggregateException(ApiException(...)) -- the shape Kiota's RetryHandler actually throws on
        # exhaustion -- while keeping the top-level Message under the caller's control.
        function New-KiotaTokenRejectedException {
            param(
                [Parameter(Mandatory)]
                [string]$Message,
                [int]$StatusCode = 0,
                [int]$NestingDepth = 0
            )
            $Api = [Activator]::CreateInstance($script:TokenRejectedApiExceptionType, @($Message))
            if ($StatusCode) { $Api.ResponseStatusCode = $StatusCode }

            $Wrapped = [System.Exception]$Api
            for ($Level = 0; $Level -lt $NestingDepth; $Level++) {
                $Wrapped = [System.AggregateException]::new($Message, [System.Exception[]]@($Wrapped))
            }
            return $Wrapped
        }
    }

    It '2f: pins the Kiota ApiException member contract this Describe is written against' {
        # Non-vacuity first, same shape as the throttle Describe's own pin: the DLL/type lookup
        # failing is itself a failure, not a skip -- a skip here would make every test below vacuous.
        $script:TokenRejectedApiExceptionType | Should -Not -BeNullOrEmpty -Because (
            'Microsoft.Kiota.Abstractions.dll must be resolvable from the installed ' +
            'Microsoft.Graph.Authentication module; without it nothing below proves anything')

        $Names = $script:TokenRejectedApiExceptionType.GetProperties().Name
        $Names | Should -Contain 'ResponseStatusCode'
        $Names | Should -Contain 'ResponseHeaders'
        # The whole defect in one assertion: there is no .Response to read a status code off.
        $Names | Should -Not -Contain 'Response'
    }

    It '2a: recognizes a real AggregateException(ApiException(401)) whose message matches none of the four regex patterns' {
        # This is the regression the fix closes. Before the fix $StatusCode stayed $null (no
        # .Response member on ApiException) and the message-only regex was the sole detector; a
        # message naming none of the four patterns left TokenInvalid $false and the failure fell
        # straight through to the final "not recoverable" throw instead of refreshing and retrying.
        $Rejected = New-KiotaTokenRejectedException -NestingDepth 1 -StatusCode 401 -Message (
            'HTTP request failed with status code: Unauthorized.' +
            '{"error":{"code":"InvalidToken","message":"The presented access token is not from a trusted issuer."}}')

        InModuleScope $script:moduleName -Parameters @{ Rejected = $Rejected } {
            $script:_OERAuthState = @{ TenantId = 'contoso'; AuthMethod = 'Interactive'; ClientId = $null }
            $script:Rejected = $Rejected
            Mock Initialize-OERAuth { }
            $script:Attempt = 0
            Mock Invoke-MgGraphRequest {
                $script:Attempt++
                if ($script:Attempt -eq 1) { throw $script:Rejected }
                @{ value = @('after-status-refresh') }
            }

            (Invoke-OERGraphRequest -Uri 'v1.0/groups').value | Should -Be 'after-status-refresh'

            # -Exactly matters: without it, -Times N is a floor in Pester v5 and a regression that
            # refreshed repeatedly would still pass.
            Should -Invoke Initialize-OERAuth -Times 1 -Exactly -ParameterFilter { $ForceRefresh }
            Should -Invoke Invoke-MgGraphRequest -Times 2 -Exactly
        }
    }

    It '2b: an app-only (ClientSecret) session throws AppOnlyTokenRefreshUnsatisfiable on the same shape, without calling Initialize-OERAuth' {
        $Rejected = New-KiotaTokenRejectedException -NestingDepth 1 -StatusCode 401 -Message (
            'HTTP request failed with status code: Unauthorized.' +
            '{"error":{"code":"InvalidToken","message":"The presented access token is not from a trusted issuer."}}')

        InModuleScope $script:moduleName -Parameters @{ Rejected = $Rejected } {
            $script:_OERAuthState = @{ TenantId = 'contoso'; AuthMethod = 'ClientSecret'; ClientId = 'cid' }
            $script:Rejected = $Rejected
            Mock Initialize-OERAuth { }
            Mock Invoke-MgGraphRequest { throw $script:Rejected }

            { Invoke-OERGraphRequest -Uri 'v1.0/groups' } |
                Should -Throw -ErrorId 'AppOnlyTokenRefreshUnsatisfiable'
            Should -Invoke Initialize-OERAuth -Times 0 -Exactly
            Should -Invoke Invoke-MgGraphRequest -Times 1 -Exactly
        }
    }

    It '2b: an app-only (ClientCertificate) session throws AppOnlyTokenRefreshUnsatisfiable on the same shape, without calling Initialize-OERAuth' {
        $Rejected = New-KiotaTokenRejectedException -NestingDepth 1 -StatusCode 401 -Message (
            'HTTP request failed with status code: Unauthorized.' +
            '{"error":{"code":"InvalidToken","message":"The presented access token is not from a trusted issuer."}}')

        InModuleScope $script:moduleName -Parameters @{ Rejected = $Rejected } {
            $script:_OERAuthState = @{ TenantId = 'contoso'; AuthMethod = 'ClientCertificate'; ClientId = 'cid' }
            $script:Rejected = $Rejected
            Mock Initialize-OERAuth { }
            Mock Invoke-MgGraphRequest { throw $script:Rejected }

            { Invoke-OERGraphRequest -Uri 'v1.0/groups' } |
                Should -Throw -ErrorId 'AppOnlyTokenRefreshUnsatisfiable'
            Should -Invoke Initialize-OERAuth -Times 0 -Exactly
            Should -Invoke Invoke-MgGraphRequest -Times 1 -Exactly
        }
    }

    It '2c: a claims challenge on the real ApiException shape still takes the claims path, not the token-rejected path' {
        # The claims block sits earlier in the same function and returns/throws before the
        # token-rejected code is reached. This proves the status fix did not pull a claims challenge
        # into the token-rejected branch. Un-wrapped (NestingDepth 0, the default): Get-ClaimsFromException
        # reads only the TOP-level exception's Message, so the challenge text has to live on the
        # object $AttemptError actually throws.
        $Challenge = New-KiotaTokenRejectedException -StatusCode 401 -Message (
            'HTTP request failed with status code: Unauthorized. WWW-Authenticate: Bearer ' +
            'authorization_uri="https://login.microsoftonline.com/common/oauth2/authorize", ' +
            'error="insufficient_claims", claims="eyJhY2Nlc3MiOnt9fQ"')

        InModuleScope $script:moduleName -Parameters @{ Challenge = $Challenge } {
            $script:_OERAuthState = @{ TenantId = 'contoso'; AuthMethod = 'Interactive'; ClientId = $null }
            $script:Challenge = $Challenge
            Mock Initialize-OERAuth { }
            $script:Attempt = 0
            Mock Invoke-MgGraphRequest {
                $script:Attempt++
                if ($script:Attempt -eq 1) { throw $script:Challenge }
                @{ value = @('after-claims-stepup') }
            }

            (Invoke-OERGraphRequest -Uri 'v1.0/groups').value | Should -Be 'after-claims-stepup'

            Should -Invoke Initialize-OERAuth -Times 1 -Exactly -ParameterFilter { $ClaimsChallenge }
            Should -Invoke Initialize-OERAuth -Times 0 -ParameterFilter { $ForceRefresh }
        }
    }

    It '2d: the secondary .Response.StatusCode path still fires the refresh (guards a future cleanup deleting the fallback)' {
        # The synthetic HttpResponseMessage shape, not the Kiota type: this pins the FALLBACK read
        # that a plain HttpResponseException (which really does expose .Response) relies on.
        InModuleScope $script:moduleName {
            $script:_OERAuthState = @{ TenantId = 'contoso'; AuthMethod = 'Interactive'; ClientId = $null }
            Mock Initialize-OERAuth { }
            $script:Attempt = 0
            Mock Invoke-MgGraphRequest {
                $script:Attempt++
                if ($script:Attempt -eq 1) {
                    $Ex = [System.Exception]::new('Response status code does not indicate success: 401 (Unauthorized).')
                    $Resp = [System.Net.Http.HttpResponseMessage]::new([System.Net.HttpStatusCode]::Unauthorized)
                    Add-Member -InputObject $Ex -NotePropertyName Response -NotePropertyValue $Resp
                    throw $Ex
                }
                @{ value = @('after-secondary-refresh') }
            }

            (Invoke-OERGraphRequest -Uri 'v1.0/groups').value | Should -Be 'after-secondary-refresh'
            Should -Invoke Initialize-OERAuth -Times 1 -Exactly -ParameterFilter { $ForceRefresh }
            Should -Invoke Invoke-MgGraphRequest -Times 2 -Exactly
        }
    }

    It '2e: a non-401 real ApiException (403) does not trigger a refresh and is surfaced to the caller' {
        $Forbidden = New-KiotaTokenRejectedException -StatusCode 403 -Message (
            'HTTP request failed with status code: Forbidden.' +
            '{"error":{"code":"Forbidden","message":"Access denied by Conditional Access policy."}}')

        InModuleScope $script:moduleName -Parameters @{ Forbidden = $Forbidden } {
            $script:_OERAuthState = @{ TenantId = 'contoso'; AuthMethod = 'Interactive'; ClientId = $null }
            $script:Forbidden = $Forbidden
            Mock Initialize-OERAuth { }
            Mock Invoke-MgGraphRequest { throw $script:Forbidden }

            { Invoke-OERGraphRequest -Uri 'v1.0/groups' } | Should -Throw -ErrorId 'Forbidden'
            Should -Invoke Initialize-OERAuth -Times 0 -Exactly
            Should -Invoke Invoke-MgGraphRequest -Times 1 -Exactly
        }
    }
}

Describe 'Invoke-OERGraphRequest -All attaches partial-read facts to a failure partway through paging (issue #73)' {
    # Before this, a failure on page N propagated straight out of the paging loop and $AllValues --
    # everything pages 1..N-1 had already fetched -- was discarded with it: a re-run started over at
    # page 1 with nothing carried forward. The call still fails, deliberately and unchanged -- the
    # apply engine diffs against what it reads, and a short list reads as drift and provokes a write
    # -- so no partial collection is ever returned on the success channel and no resume mechanism is
    # built. What changed is that the thrown error's Exception now carries PartialValue, NextLink and
    # PageNumber for a caller that opts in to read them.
    #
    # F1 (docs/development/rationale.md#graph-wrapper), measured: a note property attached to an
    # ErrorRecord does NOT survive a `throw` -- PowerShell rebuilds the ErrorRecord and the catching
    # frame sees nothing. A note property attached to the EXCEPTION DOES survive a `throw`, including
    # across a module boundary, since the exception instance is carried by reference. That is why
    # every assertion below reads $Caught.Exception.<Member>, never $Caught.<Member>.

    It '3a: page 3 throws -- PartialValue holds pages 1 and 2 in order, NextLink is the page-3 URI, PageNumber is 3' {
        InModuleScope $script:moduleName {
            $script:_OERAuthState = $null
            $script:Page = 0
            Mock Invoke-MgGraphRequest {
                $script:Page++
                switch ($script:Page) {
                    1 { @{ value = @('a', 'b'); '@odata.nextLink' = 'https://graph.microsoft.com/v1.0/groups?$skiptoken=P2' } }
                    2 { @{ value = @('c');      '@odata.nextLink' = 'https://graph.microsoft.com/v1.0/groups?$skiptoken=P3' } }
                    default {
                        $Ex = [System.Exception]::new('{"error":{"code":"InternalServerError","message":"boom"}}')
                        $Resp = [System.Net.Http.HttpResponseMessage]::new([System.Net.HttpStatusCode]::InternalServerError)
                        Add-Member -InputObject $Ex -NotePropertyName Response -NotePropertyValue $Resp
                        throw $Ex
                    }
                }
            }

            $Caught = $null
            try { Invoke-OERGraphRequest -Uri 'v1.0/groups' -All } catch { $Caught = $PSItem }

            $Caught | Should -Not -BeNullOrEmpty
            @($Caught.Exception.PartialValue) | Should -Be @('a', 'b', 'c')
            $Caught.Exception.NextLink | Should -Be 'https://graph.microsoft.com/v1.0/groups?$skiptoken=P3'
            $Caught.Exception.PageNumber | Should -Be 3
        }
    }

    It '3b: page 1 throws -- PartialValue is an empty array (never null), NextLink is the original -Uri, PageNumber is 1' {
        InModuleScope $script:moduleName {
            $script:_OERAuthState = $null
            Mock Invoke-MgGraphRequest {
                $Ex = [System.Exception]::new('{"error":{"code":"InternalServerError","message":"boom"}}')
                $Resp = [System.Net.Http.HttpResponseMessage]::new([System.Net.HttpStatusCode]::InternalServerError)
                Add-Member -InputObject $Ex -NotePropertyName Response -NotePropertyValue $Resp
                throw $Ex
            }

            $Caught = $null
            try { Invoke-OERGraphRequest -Uri 'v1.0/groups' -All } catch { $Caught = $PSItem }

            $Caught | Should -Not -BeNullOrEmpty
            # Deliberately NOT -BeNullOrEmpty: an empty array IS "empty" to that assertion, and the
            # whole point of 3b is that PartialValue is an empty ARRAY, never $null.
            ($null -eq $Caught.Exception.PartialValue) | Should -BeFalse -Because (
                'PartialValue must be an empty array, never null, when the FIRST page itself fails')
            @($Caught.Exception.PartialValue).Count | Should -Be 0
            $Caught.Exception.NextLink | Should -Be 'v1.0/groups'
            $Caught.Exception.PageNumber | Should -Be 1
        }
    }

    It '3d: a partial read never reaches the success channel -- the call throws and nothing is returned' {
        InModuleScope $script:moduleName {
            $script:_OERAuthState = $null
            $script:Page = 0
            Mock Invoke-MgGraphRequest {
                $script:Page++
                if ($script:Page -eq 1) {
                    @{ value = @('a', 'b'); '@odata.nextLink' = 'https://graph.microsoft.com/v1.0/groups?$skiptoken=P2' }
                } else {
                    $Ex = [System.Exception]::new('{"error":{"code":"InternalServerError","message":"boom"}}')
                    $Resp = [System.Net.Http.HttpResponseMessage]::new([System.Net.HttpStatusCode]::InternalServerError)
                    Add-Member -InputObject $Ex -NotePropertyName Response -NotePropertyValue $Resp
                    throw $Ex
                }
            }

            $Output = [System.Collections.Generic.List[object]]::new()
            $Caught = $null
            try {
                Invoke-OERGraphRequest -Uri 'v1.0/groups' -All | ForEach-Object { $Output.Add($PSItem) }
            } catch {
                $Caught = $PSItem
            }

            $Caught | Should -Not -BeNullOrEmpty
            @($Output).Count | Should -Be 0 -Because (
                'nothing may reach the success channel when a paged read fails partway through')
        }
    }

    It '3e: GraphExpectedCodeOnLaterPage also carries PartialValue, NextLink and PageNumber' {
        # Same technique as the "-All refuses to answer a partly-read enumeration" Describe above: a
        # real function override rather than Mock, because -ExpectedErrorCode drives
        # -SkipHttpErrorCheck/-StatusCodeVariable, and Set-Variable -Scope 1 is how the fixture answers
        # those out-parameters.
        InModuleScope $script:moduleName {
            try {
                $Pages = [System.Collections.Generic.List[int]]::new()
                function Invoke-MgGraphRequest {
                    [CmdletBinding()]
                    param([string]$Method, [string]$Uri, $Body, [switch]$SkipHttpErrorCheck,
                        [string]$StatusCodeVariable, [string]$ResponseHeadersVariable)
                    $Pages.Add(1)
                    if ($Pages.Count -eq 1) {
                        Set-Variable -Name $StatusCodeVariable -Value 200 -Scope 1
                        return @{ value = @('a', 'b', 'c'); '@odata.nextLink' = 'https://graph.microsoft.com/beta/x?skip=3' }
                    }
                    Set-Variable -Name $StatusCodeVariable -Value 400 -Scope 1
                    return ('{"error":{"code":"ResourceTypeNotSupported","message":"nope"}}' |
                            ConvertFrom-Json -AsHashtable)
                }

                $Thrown = $null
                try { Invoke-OERGraphRequest -Uri 'beta/x' -All -ExpectedErrorCode 'ResourceTypeNotSupported' }
                catch { $Thrown = $PSItem }

                $Thrown | Should -Not -BeNullOrEmpty
                @($Thrown.Exception.PartialValue) | Should -Be @('a', 'b', 'c')
                $Thrown.Exception.NextLink | Should -Be 'https://graph.microsoft.com/beta/x?skip=3'
                $Thrown.Exception.PageNumber | Should -Be 2
            } finally {
                Remove-Item 'function:Invoke-MgGraphRequest'
            }
        }
    }

    It '3f: a successful multi-page read is unchanged -- no members attached anywhere, items returned in order' {
        InModuleScope $script:moduleName {
            $script:Page = 0
            Mock Invoke-MgGraphRequest {
                $script:Page++
                switch ($script:Page) {
                    1 { @{ value = @('a', 'b'); '@odata.nextLink' = 'https://graph.microsoft.com/v1.0/groups?$skiptoken=P2' } }
                    2 { @{ value = @('c');      '@odata.nextLink' = 'https://graph.microsoft.com/v1.0/groups?$skiptoken=P3' } }
                    default { @{ value = @('d') } }
                }
            }

            $Result = Invoke-OERGraphRequest -Uri 'v1.0/groups' -All

            @($Result.value) | Should -Be @('a', 'b', 'c', 'd')
            # The success path returns a plain hashtable, never an ErrorRecord/Exception, so there is
            # nothing for PartialValue/NextLink/PageNumber to attach TO. Pinning the negative case
            # anyway: a future change that started decorating the SUCCESS path too would be caught
            # here.
            @($Result.Keys) | Should -Not -Contain 'PartialValue'
            @($Result.Keys) | Should -Not -Contain 'NextLink'
            @($Result.Keys) | Should -Not -Contain 'PageNumber'
        }
    }
}

Describe 'Invoke-OERGraphRequest -All -- a 401 arriving on a LATER page (issues #75 and #73 composed)' {
    # The two fixes meet here and nowhere else in the suite. The #75 Describe above proves the status
    # read against a real Kiota ApiException, but only on a single-page call; the #73 Describe above
    # proves the partial-read facts, but it sets $script:_OERAuthState = $null so the refresh branch
    # can never run inside it. Neither one exercises the composition -- a 401 on page 3 of an -All
    # walk -- which is precisely where the two interact: Invoke-GraphSingle's refresh-and-retry
    # re-issues THAT PAGE's own URI, so a successful refresh must resume the walk from page 3's next
    # link (not restart at the original -Uri, and not skip page 3), while a refresh that FAILS must
    # leave the paging loop's catch to attach PartialValue/NextLink/PageNumber for page 3.
    #
    # The 401 is a REAL Microsoft.Kiota.Abstractions.ApiException, built the same way the #75
    # Describe builds one, with its own BeforeAll and its own factory (that Describe's BeforeAll
    # scope is not visible here). A [pscustomobject] stand-in would prove nothing: the whole point of
    # #75 is that this shape has no .Response member to read a status off, so the message text below
    # deliberately matches NONE of the four token-rejected regex patterns
    # ('InvalidAuthenticationToken|CompactToken|token is expired|Lifetime validation failed'). The
    # status walk is then the only thing that can recognize it as a 401.
    BeforeAll {
        $ModuleBase = (Get-Module Microsoft.Graph.Authentication | Select-Object -First 1).ModuleBase
        if (-not $ModuleBase) {
            $ModuleBase = (Get-Module Microsoft.Graph.Authentication -ListAvailable |
                Sort-Object Version -Descending | Select-Object -First 1).ModuleBase
        }
        $script:LaterPageKiotaDll = $null
        if ($ModuleBase) {
            $DllSearch = @{
                LiteralPath = $ModuleBase
                Recurse     = $true
                File        = $true
                Filter      = 'Microsoft.Kiota.Abstractions.dll'
                ErrorAction = 'SilentlyContinue'
            }
            $script:LaterPageKiotaDll = Get-ChildItem @DllSearch | Select-Object -First 1
        }
        $script:LaterPageApiExceptionType = $null
        if ($script:LaterPageKiotaDll) {
            $script:LaterPageApiExceptionType = [System.Reflection.Assembly]::LoadFrom($script:LaterPageKiotaDll.FullName).
                GetType('Microsoft.Kiota.Abstractions.ApiException')
        }

        function New-KiotaLaterPage401 {
            param(
                [Parameter(Mandatory)]
                [string]$Message,
                [int]$StatusCode = 401
            )
            $Api = [Activator]::CreateInstance($script:LaterPageApiExceptionType, @($Message))
            if ($StatusCode) { $Api.ResponseStatusCode = $StatusCode }
            # AggregateException(ApiException(...)) -- the shape Kiota's own RetryHandler throws on
            # exhaustion, and the shape #75 was filed against.
            return [System.AggregateException]::new($Message, [System.Exception[]]@([System.Exception]$Api))
        }

        # No wording from the four token-rejected regex patterns appears in this text on purpose.
        $script:LaterPage401Message = 'HTTP request failed with status code: Unauthorized.' +
            '{"error":{"code":"InvalidToken","message":"The presented access token is not from a trusted issuer."}}'
    }

    It '5a: pins the ApiException member contract these two tests are written against' {
        # Non-vacuity first: a failed DLL/type lookup is a failure, not a skip -- a skip would make
        # both tests below prove nothing at all.
        $script:LaterPageApiExceptionType | Should -Not -BeNullOrEmpty -Because (
            'Microsoft.Kiota.Abstractions.dll must be resolvable from the installed ' +
            'Microsoft.Graph.Authentication module; without it neither test below proves anything')
        $Names = $script:LaterPageApiExceptionType.GetProperties().Name
        $Names | Should -Contain 'ResponseStatusCode'
        $Names | Should -Not -Contain 'Response'
    }

    It '5b: page 3 answers 401, the refresh succeeds, and the walk resumes from page 3 own next link with every item in order' {
        $Rejected = New-KiotaLaterPage401 -Message $script:LaterPage401Message

        InModuleScope $script:moduleName -Parameters @{ Rejected = $Rejected } {
            $script:_OERAuthState = @{ TenantId = 'contoso'; AuthMethod = 'Interactive'; ClientId = $null }
            $script:Rejected = $Rejected
            $script:P2 = 'https://graph.microsoft.com/v1.0/groups?$skiptoken=P2'
            $script:P3 = 'https://graph.microsoft.com/v1.0/groups?$skiptoken=P3'
            $script:P4 = 'https://graph.microsoft.com/v1.0/groups?$skiptoken=P4'
            Mock Initialize-OERAuth { }
            $script:Uris = [System.Collections.Generic.List[string]]::new()
            $script:Call = 0
            Mock Invoke-MgGraphRequest {
                param($Uri)
                $script:Uris.Add([string]$Uri)
                $script:Call++
                switch ($script:Call) {
                    1 { @{ value = @('a', 'b'); '@odata.nextLink' = $script:P2 } }
                    2 { @{ value = @('c');      '@odata.nextLink' = $script:P3 } }
                    3 { throw $script:Rejected }
                    4 { @{ value = @('d');      '@odata.nextLink' = $script:P4 } }
                    default { @{ value = @('e') } }
                }
            }

            $Result = Invoke-OERGraphRequest -Uri 'v1.0/groups' -All

            # The walk completes with every item from every page, in order: nothing was dropped by
            # the failed page and nothing was re-read into a duplicate.
            @($Result.value) | Should -Be @('a', 'b', 'c', 'd', 'e')
            # RESUMED, not restarted: the retry after the refresh re-issues page 3's OWN next link,
            # and page 4 follows from page 3's response.
            $script:Uris.Count | Should -Be 5
            $script:Uris[0] | Should -Be 'v1.0/groups'
            $script:Uris[1] | Should -Be $script:P2
            $script:Uris[2] | Should -Be $script:P3
            $script:Uris[3] | Should -Be $script:P3 -Because (
                'the refresh retry must re-issue the FAILING page, not restart the walk at the original -Uri')
            $script:Uris[4] | Should -Be $script:P4
            # -Exactly on both: -Times N alone is at-least semantics, so a regression that refreshed
            # once per page, or looped, would still pass without it.
            Should -Invoke Initialize-OERAuth -Times 1 -Exactly -ParameterFilter { $ForceRefresh }
            Should -Invoke Invoke-MgGraphRequest -Times 5 -Exactly
        }
    }

    It '5c: page 3 answers 401 and the refresh FAILS -- the error still carries PartialValue, NextLink and PageNumber for page 3' {
        $Rejected = New-KiotaLaterPage401 -Message $script:LaterPage401Message

        InModuleScope $script:moduleName -Parameters @{ Rejected = $Rejected } {
            $script:_OERAuthState = @{ TenantId = 'contoso'; AuthMethod = 'Interactive'; ClientId = $null }
            $script:Rejected = $Rejected
            $script:P2 = 'https://graph.microsoft.com/v1.0/groups?$skiptoken=P2'
            $script:P3 = 'https://graph.microsoft.com/v1.0/groups?$skiptoken=P3'
            # Initialize-OERAuth is called UNGUARDED on the refresh path, so its throw propagates out
            # of Invoke-GraphSingle and into the paging loop's own catch -- the catch that attaches
            # the three facts. This is the composition's failure half.
            Mock Initialize-OERAuth { throw [System.Exception]::new('AADSTS50076: refresh failed.') }
            $script:Call = 0
            Mock Invoke-MgGraphRequest {
                $script:Call++
                switch ($script:Call) {
                    1 { @{ value = @('a', 'b'); '@odata.nextLink' = $script:P2 } }
                    2 { @{ value = @('c');      '@odata.nextLink' = $script:P3 } }
                    default { throw $script:Rejected }
                }
            }

            $Caught = $null
            try { Invoke-OERGraphRequest -Uri 'v1.0/groups' -All } catch { $Caught = $PSItem }

            $Caught | Should -Not -BeNullOrEmpty
            # Read off the EXCEPTION, never the ErrorRecord: a note property attached to an
            # ErrorRecord does not survive a throw (docs/development/rationale.md#graph-wrapper).
            @($Caught.Exception.PartialValue) | Should -Be @('a', 'b', 'c')
            $Caught.Exception.NextLink | Should -Be $script:P3
            $Caught.Exception.PageNumber | Should -Be 3
            Should -Invoke Initialize-OERAuth -Times 1 -Exactly -ParameterFilter { $ForceRefresh }
            Should -Invoke Invoke-MgGraphRequest -Times 3 -Exactly
        }
    }
}
