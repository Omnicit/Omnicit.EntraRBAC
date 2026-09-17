BeforeAll { Import-Module Omnicit.EntraRBAC -Force }

Describe 'Remove-OERErrorRecord' {
    BeforeEach { $global:Error.Clear() }
    AfterAll { $global:Error.Clear() }

    It 'removes the global:Error entry whose Exception is reference-identical to the record' {
        InModuleScope Omnicit.EntraRBAC {
            $Exception = [System.Exception]::new('probe-message-1')
            $Record = [System.Management.Automation.ErrorRecord]::new($Exception, 'Id1', 'NotSpecified', $null)
            $global:Error.Add($Record) | Out-Null

            Remove-OERErrorRecord -Record $Record

            $global:Error.Count | Should -Be 0
        }
    }

    It 'matches by Exception reference identity, not by ErrorRecord object identity' {
        InModuleScope Omnicit.EntraRBAC {
            # This is exactly the real-world shape: the ErrorRecord PowerShell appends to
            # $global:Error is a DIFFERENT instance than $PSItem inside the catch, but both wrap the
            # identical Exception object. The helper must match on that Exception, not on the
            # ErrorRecord passed in.
            $Exception = [System.Exception]::new('probe-message-2')
            $LiveRecord = [System.Management.Automation.ErrorRecord]::new($Exception, 'Id2', 'NotSpecified', $null)
            $global:Error.Add($LiveRecord) | Out-Null

            $CaughtRecord = [System.Management.Automation.ErrorRecord]::new($Exception, 'Id2', 'NotSpecified', $null)
            [object]::ReferenceEquals($LiveRecord, $CaughtRecord) | Should -BeFalse
            [object]::ReferenceEquals($LiveRecord.Exception, $CaughtRecord.Exception) | Should -BeTrue

            Remove-OERErrorRecord -Record $CaughtRecord

            $global:Error.Count | Should -Be 0
        }
    }

    It 'scans past a non-matching head entry to remove a match further in the list' {
        InModuleScope Omnicit.EntraRBAC {
            $UnrelatedException = [System.Exception]::new('unrelated')
            $TargetException = [System.Exception]::new('target')
            $UnrelatedRecord = [System.Management.Automation.ErrorRecord]::new($UnrelatedException, 'IdU', 'NotSpecified', $null)
            $TargetRecord = [System.Management.Automation.ErrorRecord]::new($TargetException, 'IdT', 'NotSpecified', $null)
            $global:Error.Add($UnrelatedRecord) | Out-Null
            $global:Error.Add($TargetRecord) | Out-Null

            Remove-OERErrorRecord -Record $TargetRecord

            $global:Error.Count | Should -Be 1
            [object]::ReferenceEquals($global:Error[0], $UnrelatedRecord) | Should -BeTrue
        }
    }

    It 'removes only the first matching entry when the same Exception instance appears twice' {
        InModuleScope Omnicit.EntraRBAC {
            $Exception = [System.Exception]::new('duplicate')
            $First = [System.Management.Automation.ErrorRecord]::new($Exception, 'IdD1', 'NotSpecified', $null)
            $Second = [System.Management.Automation.ErrorRecord]::new($Exception, 'IdD2', 'NotSpecified', $null)
            $global:Error.Add($First) | Out-Null
            $global:Error.Add($Second) | Out-Null

            Remove-OERErrorRecord -Record $First

            $global:Error.Count | Should -Be 1
            [object]::ReferenceEquals($global:Error[0], $Second) | Should -BeTrue
        }
    }

    It 'never matches on message text alone -- two unrelated exceptions sharing text are not confused' {
        InModuleScope Omnicit.EntraRBAC {
            $LiveException = [System.Exception]::new('same text')
            $LiveRecord = [System.Management.Automation.ErrorRecord]::new($LiveException, 'IdSame1', 'NotSpecified', $null)
            $global:Error.Add($LiveRecord) | Out-Null

            $UnrelatedException = [System.Exception]::new('same text')
            $UnrelatedRecord = [System.Management.Automation.ErrorRecord]::new($UnrelatedException, 'IdSame2', 'NotSpecified', $null)

            Remove-OERErrorRecord -Record $UnrelatedRecord

            $global:Error.Count | Should -Be 1
            [object]::ReferenceEquals($global:Error[0], $LiveRecord) | Should -BeTrue
        }
    }

    It 'does nothing and does not throw when -Record is $null' {
        InModuleScope Omnicit.EntraRBAC {
            $global:Error.Add([System.Management.Automation.ErrorRecord]::new([System.Exception]::new('x'), 'Id5', 'NotSpecified', $null)) | Out-Null

            { Remove-OERErrorRecord -Record $null } | Should -Not -Throw

            $global:Error.Count | Should -Be 1
        }
    }

    It 'does not throw when $global:Error is already empty' {
        InModuleScope Omnicit.EntraRBAC {
            $Record = [System.Management.Automation.ErrorRecord]::new([System.Exception]::new('none'), 'Id6', 'NotSpecified', $null)

            { Remove-OERErrorRecord -Record $Record } | Should -Not -Throw

            $global:Error.Count | Should -Be 0
        }
    }

    It 'does nothing when no entry matches' {
        InModuleScope Omnicit.EntraRBAC {
            $LiveRecord = [System.Management.Automation.ErrorRecord]::new([System.Exception]::new('live'), 'Id7', 'NotSpecified', $null)
            $global:Error.Add($LiveRecord) | Out-Null
            $Unmatched = [System.Management.Automation.ErrorRecord]::new([System.Exception]::new('other'), 'Id8', 'NotSpecified', $null)

            Remove-OERErrorRecord -Record $Unmatched

            $global:Error.Count | Should -Be 1
            [object]::ReferenceEquals($global:Error[0], $LiveRecord) | Should -BeTrue
        }
    }

    It 'emits nothing to the pipeline' {
        InModuleScope Omnicit.EntraRBAC {
            $Record = [System.Management.Automation.ErrorRecord]::new([System.Exception]::new('silent'), 'Id9', 'NotSpecified', $null)
            $global:Error.Add($Record) | Out-Null

            # Should -BeNullOrEmpty also passes on an EMITTED $null, which would not prove the
            # "emits nothing" contract (a stray $null written by the catch-block statement form
            # `catch { scrub; $null }` would still pass that assertion). @(...) counts an emitted
            # $null as 1 element, unlike Measure-Object, which is exactly the distinction that matters
            # here.
            (@(Remove-OERErrorRecord -Record $Record)).Count | Should -Be 0
        }
    }
}

Describe 'Remove-OERErrorRecord (module-scope proof)' {
    # This is the entire point of the helper (task-5 investigation): a bare $Error inside module
    # code is a private, module-scoped list that never held the swallowed record in the first place,
    # and the ErrorRecord bound to $PSItem inside a catch is not the same object PowerShell appended
    # to the caller's real list. Only $global:Error plus Exception-reference matching can reach and
    # remove the record that actually matters.
    BeforeEach { $global:Error.Clear() }
    AfterAll { $global:Error.Clear() }

    It 'removes the swallowed record from the callers $global:Error even though the modules own $Error never held it' {
        InModuleScope Omnicit.EntraRBAC {
            function Test-OERRemoveErrorRecordModuleScopeProbe {
                [CmdletBinding()]
                param()
                $ModuleErrorCountAtCatch = -1
                try {
                    throw [System.Exception]::new('distinctive-module-scope-probe-message')
                } catch {
                    $ModuleErrorCountAtCatch = $Error.Count
                    Remove-OERErrorRecord -Record $PSItem
                }
                $ModuleErrorCountAtCatch
            }

            $ModuleErrorCountAtCatch = Test-OERRemoveErrorRecordModuleScopeProbe

            # Fact 1: $Error resolved inside the module function is a different, private list -- the
            # record the catch just swallowed was never in it.
            $ModuleErrorCountAtCatch | Should -Be 0

            # Fact 3: the removal genuinely reached the one list that matters to the caller.
            @($global:Error).Exception.Message -join ';' | Should -Not -Match 'distinctive-module-scope-probe-message'
        }
    }
}

Describe 'Remove-OERErrorRecord (bearer scrub through the real transport)' {
    # WHY THIS DESCRIBE EXISTS AT ALL. Every other test of this helper -- and every unit test in the
    # suite that touches Graph -- mocks Invoke-OERGraphRequest, the WRAPPER. That means the SDK call
    # which actually builds the bearer-carrying HttpRequestMessage never runs, so no test ever
    # observed the one property that matters: that a plain-text access token stops being reachable
    # from the records a failed read leaves behind. A live run against a real tenant found NINE
    # records reaching the caller for ONE failed read, one of them rendering
    # "Authorization: Bearer <jwt>" in full. Mocking Invoke-MgGraphRequest instead runs the REAL
    # wrapper, its real retry loop and its real Remove-OERErrorRecord call.
    BeforeAll {
        $script:moduleName = 'Omnicit.EntraRBAC'
        Import-Module $script:moduleName -Force
    }
    BeforeEach { $global:Error.Clear() }
    AfterAll { $global:Error.Clear() }

    It 'leaves no plain-text bearer token reachable from the callers -ErrorVariable or global Error' {
        $script:LeakToken = 'eyJ0eXAiOiJKV1QiLCJhbGciOiJSUzI1NiJ9.NOT-A-REAL-TOKEN-DO-NOT-SHIP'
        Mock -ModuleName $script:moduleName Initialize-OERAuth {}
        Mock -ModuleName $script:moduleName Invoke-MgGraphRequest {
            $Request = [System.Net.Http.HttpRequestMessage]::new(
                [System.Net.Http.HttpMethod]::Get,
                'https://graph.microsoft.com/v1.0/directory/administrativeUnits')
            $Request.Headers.Authorization =
                [System.Net.Http.Headers.AuthenticationHeaderValue]::new('Bearer', $script:LeakToken)
            # The token is planted ONLY on the request object, never in the message text. That is how
            # a real failure looks -- Graph does not echo the caller's own bearer back in the error
            # body -- and it keeps this test measuring the scrub rather than the converter's
            # separate, deliberate reuse of the message string.
            throw [System.Management.Automation.ErrorRecord]::new(
                [System.Exception]::new('{"error":{"code":"Authorization_RequestDenied","message":"Insufficient privileges to complete the operation."}}'),
                'Authorization_RequestDenied',
                [System.Management.Automation.ErrorCategory]::PermissionDenied,
                $Request)
        }

        $Captured = $null
        # A GUID on purpose: a non-GUID value sends Get-OERAdministrativeUnit down the display-name
        # lookup branch instead of the direct read this fixture is written for.
        Get-OERAdministrativeUnit -AdministrativeUnit '11111111-2222-3333-4444-555555555555' `
            -ErrorAction SilentlyContinue -ErrorVariable Captured | Out-Null

        # -- Non-vacuity, asserted BEFORE the security property. "The token appears nowhere" is also
        # true when nothing was captured at all, and true when the record carrying the request
        # object never reached the caller -- either would make the assertion below a guard that
        # cannot fail. Prove the fixture actually delivered the dangerous shape first.
        @($Captured).Count | Should -BeGreaterThan 0 -Because 'the failed read must reach the caller'
        $Carriers = @(@($Captured) | Where-Object { $_.TargetObject -is [System.Net.Http.HttpRequestMessage] })
        @($Carriers).Count | Should -BeGreaterThan 0 -Because (
            'the record pointing at the request object is the one that leaked; if it never reaches the caller this test proves nothing')
        @($Carriers)[0].TargetObject.RequestUri.AbsoluteUri |
            Should -Be 'https://graph.microsoft.com/v1.0/directory/administrativeUnits' -Because 'the carrier must be the real request object this fixture built'

        # -- The security property itself, over every record in both collections.
        $Render = {
            param($Records)
            $Rendered = [System.Collections.Generic.List[string]]::new()
            foreach ($Record in @($Records)) {
                if ($null -eq $Record) { continue }
                $Text = [string]$Record.FullyQualifiedErrorId
                $Ex = $Record.Exception
                $Depth = 0
                while ($null -ne $Ex -and $Depth -lt 10) {
                    $Text = $Text + ' ' + [string]$Ex.Message
                    $Ex = $Ex.InnerException
                    $Depth++
                }
                # BOTH renderings. PowerShell's default formatting of an HttpRequestMessage prints
                # "Headers : {[Authorization, System.String[]]}" and hides the value, so an
                # Out-String-only check would pass with the token still on the object -- a guard
                # that cannot fail. ToString() is what prints the header VALUES, and it is also
                # what a bare "$record" in a transcript or a log line produces.
                $Text = $Text + ' ' + (([string]$Record.TargetObject) -replace '\s+', ' ')
                $Text = $Text + ' ' + (($Record.TargetObject | Out-String) -replace '\s+', ' ')
                $Rendered.Add($Text)
            }
            $Rendered
        }

        $RenderedCaptured = & $Render @($Captured)
        @($RenderedCaptured).Count | Should -BeGreaterThan 0 -Because 'the rendering itself must not be empty, or the match below is vacuous'
        @($RenderedCaptured | Where-Object { $_ -like "*$($script:LeakToken)*" }).Count |
            Should -Be 0 -Because 'no record handed to the caller may render the access token in its id, its message chain or its TargetObject'

        $RenderedGlobal = & $Render @($global:Error)
        @($RenderedGlobal | Where-Object { $_ -like "*$($script:LeakToken)*" }).Count |
            Should -Be 0 -Because 'the caller global Error list is the other collection that survives the call'

        Should -Invoke -ModuleName $script:moduleName Invoke-MgGraphRequest -Times 1 -Exactly
    }

    It 'clears the Authorization header on a request reached through an HttpResponseMessage' {
        # The second reachable shape: some SDK exceptions expose the RESPONSE, and the bearer sits on
        # its .RequestMessage. Exercised directly rather than through a transport fixture, since no
        # single mocked call can produce every SDK exception variant.
        InModuleScope Omnicit.EntraRBAC {
            $Token = 'FAKE-RESPONSE-PATH-TOKEN'
            $Request = [System.Net.Http.HttpRequestMessage]::new(
                [System.Net.Http.HttpMethod]::Get, 'https://graph.microsoft.com/v1.0/groups')
            $Request.Headers.Authorization =
                [System.Net.Http.Headers.AuthenticationHeaderValue]::new('Bearer', $Token)
            $Response = [System.Net.Http.HttpResponseMessage]::new([System.Net.HttpStatusCode]::Forbidden)
            $Response.RequestMessage = $Request
            $Record = [System.Management.Automation.ErrorRecord]::new(
                [System.Exception]::new('forbidden'), 'ResponsePath', 'PermissionDenied', $Response)

            ([string]$Request) | Should -Match ([regex]::Escape($Token)) -Because 'the fixture must start out carrying the token, or the assertion after the call is vacuous'

            Remove-OERErrorRecord -Record $Record

            ([string]$Request) | Should -Not -Match ([regex]::Escape($Token))
            ([string]$Record.TargetObject) | Should -Not -Match ([regex]::Escape($Token))
        }
    }

    It 'clears the Authorization header on a request reached through the exception chain' {
        # The third reachable shape: the request hangs off the exception rather than off
        # TargetObject, one level down the InnerException chain, so only the walk can find it.
        InModuleScope Omnicit.EntraRBAC {
            $Token = 'FAKE-INNER-EXCEPTION-TOKEN'
            $Request = [System.Net.Http.HttpRequestMessage]::new(
                [System.Net.Http.HttpMethod]::Get, 'https://graph.microsoft.com/v1.0/groups')
            $Request.Headers.Authorization =
                [System.Net.Http.Headers.AuthenticationHeaderValue]::new('Bearer', $Token)

            $Inner = [System.Exception]::new('inner')
            $Inner.PSObject.Properties.Add(
                [System.Management.Automation.PSNoteProperty]::new('Request', $Request))
            $Outer = [System.Exception]::new('outer', $Inner)
            $Record = [System.Management.Automation.ErrorRecord]::new(
                $Outer, 'ChainPath', 'PermissionDenied', 'not-a-request-object')

            ([string]$Request) | Should -Match ([regex]::Escape($Token)) -Because 'the fixture must start out carrying the token'

            Remove-OERErrorRecord -Record $Record

            ([string]$Request) | Should -Not -Match ([regex]::Escape($Token))
        }
    }

    It 'clears the Authorization header on a request held behind a wrapper object' {
        # The fourth reachable shape, and the one the exact-type check walked straight past: the
        # exception exposes a Response that is NOT an HttpResponseMessage but a plain object whose
        # own .RequestMessage IS the real request. Measured against the pre-fix helper this rendered
        # the token in full (wrapper-response-still-leaks=True). Members of TargetObject itself were
        # never inspected either, which is why TargetObject here is the wrapper rather than a request.
        InModuleScope Omnicit.EntraRBAC {
            $Token = 'FAKE-WRAPPER-PATH-TOKEN'
            $Request = [System.Net.Http.HttpRequestMessage]::new(
                [System.Net.Http.HttpMethod]::Get, 'https://graph.microsoft.com/v1.0/groups')
            $Request.Headers.Authorization =
                [System.Net.Http.Headers.AuthenticationHeaderValue]::new('Bearer', $Token)

            $Wrapper = [PSCustomObject]@{ StatusCode = 403; RequestMessage = $Request }
            $Exception = [System.Exception]::new('forbidden')
            $Exception.PSObject.Properties.Add(
                [System.Management.Automation.PSNoteProperty]::new('Response', $Wrapper))
            $Record = [System.Management.Automation.ErrorRecord]::new(
                $Exception, 'WrapperPath', 'PermissionDenied', $Wrapper)

            # [string], never Out-String. Measured on this exact fixture: "$Wrapper" renders
            # "Authorization: Bearer <token>" in full, while ($Wrapper | Out-String) renders the
            # header collection summary and hides the value -- so an Out-String assertion here is a
            # guard that cannot fail. Both renderings are pinned as non-vacuous before the call.
            ([string]$Record.TargetObject) | Should -Match ([regex]::Escape($Token)) -Because 'the fixture must start out rendering the token through TargetObject'
            ([string]$Request) | Should -Match ([regex]::Escape($Token))

            Remove-OERErrorRecord -Record $Record

            ([string]$Record.TargetObject) | Should -Not -Match ([regex]::Escape($Token))
            ([string]$Request) | Should -Not -Match ([regex]::Escape($Token))
            ([string]$Record.Exception.Response.RequestMessage) | Should -Not -Match ([regex]::Escape($Token))
        }
    }

    It 'clears the Authorization header on a request carried by the SECOND inner exception of an AggregateException' {
        # AggregateException.InnerException returns InnerExceptions[0] and nothing else, so an
        # .InnerException-only walk stops at the wrong exception and the real transport failure at
        # index 1 keeps its token (measured against the pre-fix helper: still-leaks=True). This is
        # the Graph SDK's own retry shape -- Convert-GraphHttpException already special-cases its
        # "Too many retries performed... (HTTP request failed...)" message -- not a contrived one.
        InModuleScope Omnicit.EntraRBAC {
            $Token = 'FAKE-AGGREGATE-INDEX-ONE-TOKEN'
            $Request = [System.Net.Http.HttpRequestMessage]::new(
                [System.Net.Http.HttpMethod]::Get, 'https://graph.microsoft.com/v1.0/groups')
            $Request.Headers.Authorization =
                [System.Net.Http.Headers.AuthenticationHeaderValue]::new('Bearer', $Token)

            $Unrelated = [System.Exception]::new('unrelated retry attempt')
            $Transport = [System.Exception]::new('HTTP request failed')
            $Transport.PSObject.Properties.Add(
                [System.Management.Automation.PSNoteProperty]::new('Request', $Request))
            $Aggregate = [System.AggregateException]::new(
                'Too many retries performed', [System.Exception[]]@($Unrelated, $Transport))
            # TargetObject is deliberately NOT the request: were it the request, the direct-type
            # branch would scrub it and this test would pass with the aggregate walk removed.
            $Record = [System.Management.Automation.ErrorRecord]::new(
                $Aggregate, 'AggregatePath', 'LimitsExceeded', 'not-a-request-object')

            # Pin the shape the walk has to defeat, so a future AggregateException whose
            # .InnerException happened to be the right one could not make this pass by accident.
            [object]::ReferenceEquals($Record.Exception.InnerException, $Unrelated) |
                Should -BeTrue -Because 'the aggregate must hand back the WRONG inner exception first, or the walk is not being tested'
            ([string]$Record.Exception.InnerExceptions[1].Request) |
                Should -Match ([regex]::Escape($Token)) -Because 'the fixture must start out rendering the token off the second inner exception'

            Remove-OERErrorRecord -Record $Record

            ([string]$Record.Exception.InnerExceptions[1].Request) | Should -Not -Match ([regex]::Escape($Token))
            ([string]$Request) | Should -Not -Match ([regex]::Escape($Token))
        }
    }

    It 'terminates on a self-referencing object graph and still scrubs it' {
        # Widening the walk buys a cycle risk the exact-type check never had. The wrapper below
        # points at ITSELF through .Response and the exception lists ITSELF in .InnerExceptions --
        # both loops the helper now follows. The real proof of termination is that this It returns
        # at all; the elapsed bound below only catches a walk that is merely pathological rather
        # than infinite. The scrub assertion is the other half: a cycle guard that bailed out of the
        # whole walk would also never loop, and would leave the token in place.
        InModuleScope Omnicit.EntraRBAC {
            $Token = 'FAKE-SELF-REFERENCE-TOKEN'
            $Request = [System.Net.Http.HttpRequestMessage]::new(
                [System.Net.Http.HttpMethod]::Get, 'https://graph.microsoft.com/v1.0/groups')
            $Request.Headers.Authorization =
                [System.Net.Http.Headers.AuthenticationHeaderValue]::new('Bearer', $Token)

            $Cycle = [PSCustomObject]@{ RequestMessage = $Request; Response = $null }
            $Cycle.Response = $Cycle
            $Exception = [System.Exception]::new('cyclic')
            $Exception.PSObject.Properties.Add(
                [System.Management.Automation.PSNoteProperty]::new('InnerExceptions', @($Exception)))
            $Record = [System.Management.Automation.ErrorRecord]::new(
                $Exception, 'CyclePath', 'NotSpecified', $Cycle)

            ([string]$Request) | Should -Match ([regex]::Escape($Token)) -Because 'the fixture must start out carrying the token'

            $Watch = [System.Diagnostics.Stopwatch]::StartNew()
            { Remove-OERErrorRecord -Record $Record } | Should -Not -Throw
            $Watch.Stop()

            $Watch.Elapsed.TotalSeconds |
                Should -BeLessThan 5 -Because 'the walk is bounded by a visit cap and a single non-recursive expansion pass'
            ([string]$Request) | Should -Not -Match ([regex]::Escape($Token))
            ([string]$Record.TargetObject) | Should -Not -Match ([regex]::Escape($Token))
        }
    }

    It 'still emits nothing to the pipeline on the widened walk' {
        # The helper runs as a bare statement at roughly 40 catch sites, where a stray emitted value
        # would land in the caller's own output. @() counts an emitted $null as one element, unlike
        # Measure-Object, so this fails on a stray $null where -BeNullOrEmpty would not.
        InModuleScope Omnicit.EntraRBAC {
            $Request = [System.Net.Http.HttpRequestMessage]::new(
                [System.Net.Http.HttpMethod]::Get, 'https://graph.microsoft.com/v1.0/groups')
            $Request.Headers.Authorization =
                [System.Net.Http.Headers.AuthenticationHeaderValue]::new('Bearer', 'FAKE-SILENCE-TOKEN')
            $Wrapper = [PSCustomObject]@{ RequestMessage = $Request }
            $Exception = [System.Exception]::new('quiet')
            $Exception.PSObject.Properties.Add(
                [System.Management.Automation.PSNoteProperty]::new('InnerExceptions', @([System.Exception]::new('a'))))
            $Record = [System.Management.Automation.ErrorRecord]::new(
                $Exception, 'Silence', 'NotSpecified', $Wrapper)

            (@(Remove-OERErrorRecord -Record $Record)).Count | Should -Be 0
            ([string]$Request) | Should -Not -Match 'FAKE-SILENCE-TOKEN' -Because 'the silence assertion must sit on a walk that actually did the work'
        }
    }
}
