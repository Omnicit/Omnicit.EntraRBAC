function Invoke-OERGraphRequest {
    <#
    .SYNOPSIS
    Wraps Invoke-MgGraphRequest with bearer-token security, ACRS claims-challenge handling,
    and consistent error conversion.

    .DESCRIPTION
    Drop-in replacement for Invoke-MgGraphRequest used by every public and private function in
    Omnicit.EntraRBAC. Adds five layers on top of the raw Graph SDK call:

    1. Bearer token security: the $Error record that contains the raw HttpRequestMessage
       (which carries the Authorization: Bearer header in plain text) is removed from $Error
       immediately in every catch block.

    2. ACRS claims-challenge retry: when Microsoft Graph returns a 401 response whose
       WWW-Authenticate header contains a claims="<base64url>" challenge, this function:
         a. Base64url-decodes the challenge to a JSON string.
         b. Calls Initialize-OERAuth -ClaimsChallenge to perform a one-time interactive
            step-up authentication.
         c. Retries the original request exactly once.
       A second 401 (after a successful step-up) is surfaced as a normal error.

    3. Error conversion: non-claims errors are run through Convert-GraphHttpException to
       produce structured ErrorRecord objects with the Graph error.code as the
       FullyQualifiedErrorId. The caller receives either a response or a thrown ErrorRecord --
       no _AcrsError hashtable protocol.

    4. Throttling backoff: a 429 (or a 503 that carries a Retry-After header) is retried until a
       WAIT BUDGET is exhausted, waiting the number of seconds the Retry-After header asks
       for, or an exponential fallback when the header is absent. There are two nested budgets:
       300 seconds per request, and 900 seconds for the whole call however many pages it fetches,
       so a paged read against a throttled tenant has a ceiling the caller can predict. Each
       individual wait is capped at 120 seconds and is logged with Write-Verbose, which names
       which budget stopped the retrying. The throttle is recognised from the HTTP status
       when that status is reachable and, when it is not, from the Graph error code or message that
       Convert-GraphHttpException extracts -- the Graph SDK's own retry handler consumes the 429
       response and reports the exhaustion as an AggregateException whose HTTP facts live on the
       Kiota ApiException it wraps, not on a .Response member, so a status-only test never fires in
       production. The claims-challenge and token-rejected retries above are unaffected and still
       fire at most once each.

    5. Opt-in paging: passing -All follows @odata.nextLink on a GET list response and aggregates
       every page's value array into a single result. Each page fetch gets its own bounded
       throttle backoff and its own single-shot claims-challenge/401 retry, because the paging
       loop wraps repeated calls to the same single-request logic rather than sharing state
       across pages. The one thing pages DO share is the 900-second per-call wait budget, so the
       per-page budget cannot be multiplied by the page count into an unbounded wait. A failure on
       page 2 or later still fails the call -- a partial page set is never returned on the success
       channel, since the apply engine diffs against what it reads and a short list reads as drift
       and provokes a write -- but the pages already fetched are no longer silently discarded with
       it. ONLY UNDER -ALL: the thrown error's Exception carries three note properties a caller can
       opt into reading -- PartialValue (an object[] of every item aggregated before the failure,
       @() when page 1 itself failed), NextLink (the URI of the failing request: the original -Uri
       for page 1, the followed @odata.nextLink for a later page), and PageNumber (the 1-based page
       that failed). The single-page (without -All) path returns on the first failure exactly as
       before and attaches nothing.

    6. Expected-answer codes: -ExpectedErrorCode lets a caller declare that one or more Graph error
       codes are an ANSWER to its question rather than a failure of it. A declared code is returned
       as an Omnicit.EntraRBAC.GraphExpectedError marker object instead of being raised, and the
       request is issued with the Graph SDK's -SkipHttpErrorCheck so the HTTP failure never becomes
       a PowerShell error in the first place. Nothing else is softened: any OTHER status on the same
       call is converted and thrown exactly as it is without the switch, and the throttle,
       claims-challenge and token-rejected retries above all still run against it. The code must be
       the one Graph NAMED (the error body's code); a failure Graph named differently is raised even
       when its message text happens to mention a declared code. Under -All the softening applies to
       the FIRST page only -- a declared code on a later page is a failed read partway through an
       enumeration, not an empty collection, and is raised so the pages already aggregated are never
       silently discarded. That raised error carries the same PartialValue/NextLink/PageNumber facts
       described in item 5, since this is the other way a paged read can fail partway through.

    .PARAMETER Method
    HTTP method for the Graph request. Defaults to GET.

    .PARAMETER Uri
    Graph API URI, e.g. 'v1.0/roleManagement/directory/roleEligibilitySchedules'.

    .PARAMETER Body
    Optional request body hashtable (for POST/PATCH requests).

    .PARAMETER All
    Follow @odata.nextLink on a GET list response and return a single object whose value property
    holds every item across all pages. Strictly opt-in: without this switch the wrapper returns the
    first page exactly as before. The next link is an absolute URL and is re-sent verbatim, per the
    Microsoft Graph paging guidance.

    .PARAMETER ExpectedErrorCode
    Graph error codes this caller considers an expected ANSWER rather than a failure -- for example
    'ResourceTypeNotSupported' on the PIM-for-Groups eligibility endpoint, which is simply how Graph
    says a group is not onboarded. When one of these codes comes back the request returns a marker
    object (see OUTPUTS) instead of raising, and no error record is produced anywhere in the chain.
    Matching is case-insensitive and on the WHOLE code token, never a prefix, so a longer code that
    merely starts with the same text is still raised. The code Graph itself named is what is
    matched; the failure's message text is consulted only when Graph named no code at all, so a
    genuine failure whose prose merely mentions a declared code is still raised. With -All, only the
    FIRST page may answer with a declared code. Any code NOT named here behaves exactly as it does
    without this parameter.

    .OUTPUTS
    The Graph API response hashtable on success. With -All, a hashtable shaped @{ value = <array> }
    holding the aggregated items from every page. When -ExpectedErrorCode is supplied and Graph
    answers with one of those codes, a PSCustomObject tagged Omnicit.EntraRBAC.GraphExpectedError
    carrying ExpectedErrorCode, StatusCode, Message and Uri. Test for it by type name; it is never
    shaped like a Graph response and has no value property. When a -All enumeration fails on page 2
    or later, the thrown error's Exception carries PartialValue, NextLink and PageNumber -- see the
    paging paragraph above (item 5) and the final .EXAMPLE below.

    .EXAMPLE
    $Items = (Invoke-OERGraphRequest -Uri 'v1.0/roleManagement/directory/roleEligibilitySchedules/filterByCurrentUser(on=''principal'')').value

    .EXAMPLE
    $Response = Invoke-OERGraphRequest -Method POST -Uri 'v1.0/roleManagement/directory/roleAssignmentScheduleRequests' -Body $Request

    .EXAMPLE
    $AllGroups = (Invoke-OERGraphRequest -Uri 'v1.0/groups' -All).value

    .EXAMPLE
    $Result = Invoke-OERGraphRequest -Uri $EligibilityUri -All -ExpectedErrorCode 'ResourceTypeNotSupported'
    if (@($Result.PSObject.TypeNames) -contains 'Omnicit.EntraRBAC.GraphExpectedError') { $Items = @() }
    else { $Items = @($Result.value) }

    Reads PIM eligibility for a group that may not be onboarded. A not-onboarded group answers 400
    ResourceTypeNotSupported, which arrives as the marker rather than as an error record.

    .EXAMPLE
    try {
        $AllGroups = (Invoke-OERGraphRequest -Uri 'v1.0/groups' -All).value
    } catch {
        Write-Warning ("Read failed on page $($_.Exception.PageNumber) after " +
            "$($_.Exception.PartialValue.Count) item(s); resume from $($_.Exception.NextLink).")
        throw
    }

    Opts into the partial-read facts a failed -All enumeration attaches to its Exception (issue #73).
    The call still fails -- $AllGroups is never assigned -- but a caller that wants what was already
    fetched can read it from the caught error instead of it being lost with the exception.
    #>
    [OutputType([object])]
    param(
        [string]$Method = 'GET',
        [Parameter(Mandatory)]
        [string]$Uri,
        [hashtable]$Body,
        [switch]$All,
        [string[]]$ExpectedErrorCode
    )

    # -- Helper: extract claims from a Graph failure --
    # Two distinct encodings must be handled:
    #   1. 401 WWW-Authenticate step-up: claims="<base64url-encoded JSON>" (quoted).
    #   2. PIM 400 RoleAssignmentRequestAcrsValidationFailed: the response body carries
    #      &claims=<URL-encoded JSON> (unquoted, e.g. &claims=%7B%22access_token%22...).
    # The decoded result is always the MSAL claims-request JSON, e.g.
    #   {"access_token":{"acrs":{"essential":true,"value":"c1"}}}
    function Get-ClaimsFromException ([System.Management.Automation.ErrorRecord]$ErrorRecord) {
        # Gather every place the challenge might live, most-reliable first.
        $Candidates = [System.Collections.Generic.List[string]]::new()
        try {
            $WwwAuthenticate = $ErrorRecord.Exception.Response.Headers.WwwAuthenticate
            if ($WwwAuthenticate) { $Candidates.Add($WwwAuthenticate.ToString()) }
        } catch { Remove-OERErrorRecord -Record $PSItem }
        try {
            if ($ErrorRecord.Exception.Response -and $ErrorRecord.Exception.Response.Content) {
                $Candidates.Add($ErrorRecord.Exception.Response.Content.ReadAsStringAsync().GetAwaiter().GetResult())
            }
        } catch { Remove-OERErrorRecord -Record $PSItem }
        $Candidates.Add($ErrorRecord.Exception.Message)

        foreach ($Text in $Candidates) {
            # Capture quoted ("...") or unquoted (stop at & / whitespace / quote) value.
            if (-not ($Text -and ($Text -match 'claims=(?:"([^"]+)"|([^"&\s]+))'))) { continue }
            $Encoded = if ($Matches[1]) { $Matches[1] } else { $Matches[2] }

            # 1. URL-encoded JSON (PIM body form).
            if ($Encoded -match '%') {
                $Decoded = [System.Uri]::UnescapeDataString($Encoded)
                if ($Decoded -match '^\s*\{') { return $Decoded }
            }

            # 2. Base64url-encoded JSON (WWW-Authenticate step-up form).
            $Padded = $Encoded.Replace('-', '+').Replace('_', '/')
            switch ($Padded.Length % 4) {
                2 { $Padded += '==' }
                3 { $Padded += '='  }
            }
            try {
                $Decoded = [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($Padded))
                if ($Decoded -match '^\s*\{') { return $Decoded }
            } catch { Remove-OERErrorRecord -Record $PSItem }

            # 3. Already raw JSON.
            if ($Encoded -match '^\s*\{') { return $Encoded }
        }
        return $null
    }

    # -- Helper: turn one raw Retry-After header VALUE into whole seconds --
    # SINGLE OWNER of raw Retry-After parsing. RFC 9110 allows two forms and Microsoft Graph uses
    # both: delta-seconds ("60") and an HTTP-date ("Wed, 21 Oct 2015 07:28:00 GMT"). Every path that
    # obtains the header as a STRING routes through here; the only other reader is the strongly
    # typed HttpResponseHeaders.RetryAfter property below, which the framework has already parsed
    # into .Delta / .Date. Returns $null when the value is absent or is neither form -- never a
    # guess. A date already in the past yields a negative number here and is clamped by the caller.
    function ConvertFrom-RetryAfterHeader ([string]$RawValue) {
        if ([string]::IsNullOrWhiteSpace($RawValue)) { return $null }
        $Trimmed = $RawValue.Trim()

        [int]$DeltaSeconds = 0
        if ([int]::TryParse($Trimmed, [ref]$DeltaSeconds)) { return $DeltaSeconds }

        $HttpDate = [System.DateTimeOffset]::MinValue
        $Styles = [System.Globalization.DateTimeStyles]::AssumeUniversal -bor
                  [System.Globalization.DateTimeStyles]::AdjustToUniversal
        if ([System.DateTimeOffset]::TryParse($Trimmed, [System.Globalization.CultureInfo]::InvariantCulture, $Styles, [ref]$HttpDate)) {
            return [int][Math]::Ceiling(($HttpDate.UtcDateTime - [DateTime]::UtcNow).TotalSeconds)
        }
        return $null
    }

    # -- Helper: pull Retry-After out of a header collection, whatever shape it arrives in --
    # SINGLE OWNER of that read. Both the Kiota walk below and the .Response.Headers fallback in
    # Get-ThrottleDelay call this; do not add a third reader.
    #
    # TWO SHAPES REACH THIS, and the obvious code for one is silently wrong on the other. Both
    # measured on this machine, PowerShell 7 / .NET 10:
    #
    #   1. System.Collections.Generic.IDictionary[string, IEnumerable[string]] -- what Kiota's
    #      ApiException.ResponseHeaders is. It exposes .Keys and an indexer, and PowerShell's foreach
    #      does NOT enumerate it element-by-element (a dictionary is a single item to foreach), so
    #      .Keys plus the indexer is the only read that works.
    #
    #   2. System.Net.Http.Headers.HttpResponseHeaders -- what an exception's .Response.Headers is,
    #      and the shape a real tenant produced. It has NO .Keys member at all: '$Headers.Keys' does
    #      not throw and does not enumerate header names either -- PowerShell member enumeration
    #      returns nothing -- so a 'foreach ($Key in @($Headers.Keys))' walk pointed at THIS shape
    #      would iterate once over $null and miss a Retry-After header that was genuinely PRESENT.
    #      That never actually happened: the .Keys walk lived only over shape 1, and the
    #      .Response.Headers path asked for the header BY NAME instead. Two reads, each correct only
    #      for its own collection and silently wrong on the other, is precisely the arrangement this
    #      single owner replaces. This collection MUST be enumerated directly; each element is a
    #      KeyValuePair with .Key and .Value. Its .GetValues(name) accessor is not an option: it
    #      THROWS InvalidOperationException 'The given header was not found.' when the header is
    #      absent, which is the normal case on every non-throttled failure. That throw was landing
    #      in the caller's -ErrorVariable as one of three noise records per failed read.
    #
    # PSObject.Properties['Keys'] is the discriminator -- present on the dictionary, absent on
    # HttpResponseHeaders -- rather than a type test, so no Graph SDK type has to be loaded to
    # decide. Header names are compared with PowerShell's case-insensitive -eq: HTTP header names
    # are case-insensitive and Kiota builds its dictionary with the ORDINAL comparer, so an indexer
    # lookup by literal name would be casing-sensitive.
    #
    # NEVER THROWS. This runs inside the wrapper's failure path, where an escaping exception would
    # REPLACE the real Graph error the caller needs to see -- the same hazard the -as [int] cast in
    # the status read below already guards against.
    #
    # SECURITY: only the single Retry-After entry is ever returned. The collection itself is never
    # returned, written to any stream, or logged; response headers can carry correlation and, on
    # some shapes, authentication material.
    function Get-RetryAfterHeaderValue ($HeaderCollection) {
        if ($null -eq $HeaderCollection) { return $null }
        try {
            $KeysMember = $HeaderCollection.PSObject.Properties['Keys']
            if ($null -ne $KeysMember) {
                foreach ($Key in @($KeysMember.Value)) {
                    if ([string]$Key -ne 'Retry-After') { continue }
                    return [string](@($HeaderCollection[$Key]) | Select-Object -First 1)
                }
                return $null
            }
            foreach ($Entry in $HeaderCollection) {
                if ($null -eq $Entry) { continue }
                $NameMember = $Entry.PSObject.Properties['Key']
                if ($null -eq $NameMember -or [string]$NameMember.Value -ne 'Retry-After') { continue }
                $ValueMember = $Entry.PSObject.Properties['Value']
                if ($null -eq $ValueMember) { return $null }
                return [string](@($ValueMember.Value) | Select-Object -First 1)
            }
        } catch {
            Remove-OERErrorRecord -Record $PSItem
        }
        return $null
    }

    # -- Helper: read the HTTP facts Microsoft Graph actually buries in the exception chain --
    # SINGLE OWNER of that walk. Do not add a second one anywhere.
    #
    # WHY THIS EXISTS. Invoke-MgGraphRequest never surfaces a bare 429. The Graph SDK pipeline
    # installs Kiota's RetryHandler, which swallows the 429 response, retries it internally, and on
    # exhaustion throws
    #   AggregateException('Too many retries performed. More than {n} retries encountered while
    #                       sending the request.',
    #                      ApiException('HTTP request failed with status code: TooManyRequests.<body>'))
    # Microsoft.Kiota.Abstractions.ApiException has NO .Response member at all. Its HTTP facts are
    # two plain properties -- ResponseStatusCode ([int]) and ResponseHeaders
    # (IDictionary[string, IEnumerable[string]]) -- verified by reflection against the
    # Microsoft.Kiota.Abstractions.dll that ships inside the pinned Microsoft.Graph.Authentication
    # 2.36.0, and machine-checked by the "Kiota ApiException member contract" test so a future SDK
    # bump that renames them fails loudly instead of making this extraction silently inert again.
    # Reading only .Response.Headers is exactly why the documented Retry-After honouring never once
    # fired in production: $null.Headers.RetryAfter is $null and does NOT throw, so nothing failed.
    #
    # The members are read BY NAME through the PowerShell property bag rather than by casting to the
    # Kiota type, so the module keeps no compile-time dependency on a Graph SDK type (which is not
    # even loaded until the first real Graph call) and a missing member yields $null instead of an
    # exception -- no catch clause needed, and none added.
    #
    # SECURITY: only the single Retry-After entry is ever read out of the header collection, and the
    # collection itself is never returned, written to any stream, or logged. Response headers can
    # carry correlation and, on some shapes, authentication material.
    function Get-ResponseFactFromException ([System.Exception]$Exception) {
        $Fact = @{ Status = $null; RetryAfter = $null }

        # Breadth-first: an AggregateException hides the real cause in InnerExceptions (PLURAL) while
        # everything else uses InnerException (singular). Both are followed, to any depth. The visit
        # ceiling is a cycle/runaway guard only -- a real Graph chain is two or three deep.
        #
        # THE elseif BELOW IS LOAD-BEARING. AggregateException.InnerException IS InnerExceptions[0]
        # (verified by ReferenceEquals), so enqueuing from both members duplicates every level and
        # the queue grows 2^depth. Against the visit ceiling that silently stopped the walk at depth
        # 6: the header was PRESENT and this helper returned $null, which is precisely the
        # inert-extraction failure this whole change exists to end. Do not "simplify" it back to two
        # independent ifs.
        $Pending = [System.Collections.Generic.Queue[System.Exception]]::new()
        if ($null -ne $Exception) { $Pending.Enqueue($Exception) }
        [int]$Visited = 0
        while ($Pending.Count -gt 0 -and $Visited -lt 32) {
            $Current = $Pending.Dequeue()
            $Visited++
            if ($null -eq $Current) { continue }

            if ($null -eq $Fact.Status) {
                $StatusProperty = $Current.PSObject.Properties['ResponseStatusCode']
                # -as, never a [int] cast. A chain member carrying a non-numeric
                # ResponseStatusCode makes a cast THROW, and because this helper runs inside the
                # wrapper's failure path that cast error would escape and REPLACE the real Graph
                # error the caller needs to see. -as yields $null and the walk simply moves on.
                $StatusValue = if ($StatusProperty) { $StatusProperty.Value -as [int] } else { $null }
                # Kiota leaves ResponseStatusCode at 0 when it never saw a response, so 0 means
                # "unknown" here and must not be mistaken for a real HTTP status.
                if ($null -ne $StatusValue -and $StatusValue -gt 0) {
                    $Fact.Status = $StatusValue
                }
            }

            if ($null -eq $Fact.RetryAfter) {
                $HeadersProperty = $Current.PSObject.Properties['ResponseHeaders']
                if ($HeadersProperty -and $null -ne $HeadersProperty.Value) {
                    # Shape-tolerant by design. This member is documented as a Kiota dictionary and
                    # the live noise came from the .Response.Headers fallback in Get-ThrottleDelay,
                    # not from here -- but the old .Keys read was measurably inert on an
                    # HttpResponseHeaders, so nothing but the exception's own type stood between a
                    # present Retry-After and a missed one. Both readers now share one owner rather
                    # than each trusting a member's documented type. See Get-RetryAfterHeaderValue.
                    $Fact.RetryAfter = Get-RetryAfterHeaderValue $HeadersProperty.Value
                }
            }

            if ($null -ne $Fact.Status -and $null -ne $Fact.RetryAfter) { break }

            if ($Current -is [System.AggregateException]) {
                foreach ($Nested in $Current.InnerExceptions) {
                    if ($null -ne $Nested) { $Pending.Enqueue($Nested) }
                }
            } elseif ($null -ne $Current.InnerException) {
                $Pending.Enqueue($Current.InnerException)
            }
        }

        return $Fact
    }

    # -- Helper: how long does Graph want us to wait before retrying? --
    # Returns $null when the failure is not a retryable throttle, otherwise a hashtable
    # @{ Seconds = <int>; Source = 'server-directed' | 'exponential fallback' }. The Source is what
    # the verbose line reports, so an operator can tell at a glance whether the wait is Graph's own
    # instruction or this module guessing. Microsoft Learn (graph/throttling): detect with HTTP 429,
    # honour the Retry-After header (seconds); when a 429 carries no header, fall back to exponential
    # backoff. A 503 is retried ONLY when it carries a Retry-After.
    #
    # WHY THIS IS NOT A STATUS-ONLY TEST. The HTTP status is frequently unreachable on a real
    # throttle -- see Get-ResponseFactFromException above for the exception shape. In PowerShell
    # $null.StatusCode is $null and [int]$null is 0, so the .Response cast below does NOT throw and
    # the try/catch cannot save it: $Status silently becomes 0. A status-only test therefore never
    # matched in production, which left this whole backoff structurally dead while still being
    # documented as shipping.
    #
    # PRIMARY vs SECONDARY: the Kiota walk is the shape Graph really produces and is consulted
    # first. The .Response reads that follow are the SECONDARY path and are kept deliberately -- a
    # raw HttpRequestException, and the synthetic fixtures in the unit suite, do carry .Response.
    #
    # SINGLE OWNER: when the status is unreachable the error code and message are read back from
    # Convert-GraphHttpException instead of re-implementing body/message parsing here. That
    # converter is the module's only implementation of "what did Graph actually say" -- it reads the
    # response body and falls back to the exception message. Two copies of that extraction is
    # exactly how this bug happened: one copy learned to read the body and the other did not. Do not
    # inline a second copy here.
    function Get-ThrottleDelay ([System.Management.Automation.ErrorRecord]$ErrorRecord, [int]$Attempt) {
        $Fact = Get-ResponseFactFromException $ErrorRecord.Exception

        $Status = $Fact.Status
        if ($null -eq $Status) {
            try { $Status = [int]$ErrorRecord.Exception.Response.StatusCode } catch { Remove-OERErrorRecord -Record $PSItem }
        }

        $HeaderSeconds = ConvertFrom-RetryAfterHeader $Fact.RetryAfter
        if ($null -eq $HeaderSeconds) {
            try {
                $RetryAfter = $ErrorRecord.Exception.Response.Headers.RetryAfter
                if ($RetryAfter -and $RetryAfter.Delta) { $HeaderSeconds = [int]$RetryAfter.Delta.TotalSeconds }
                elseif ($RetryAfter -and $RetryAfter.Date) {
                    $HeaderSeconds = [int][Math]::Ceiling(($RetryAfter.Date.UtcDateTime - [DateTime]::UtcNow).TotalSeconds)
                }
            } catch { Remove-OERErrorRecord -Record $PSItem }
        }
        if ($null -eq $HeaderSeconds) {
            # NOT .Headers.GetValues('Retry-After'). That accessor THROWS
            # InvalidOperationException 'The given header was not found.' whenever the header is
            # absent -- which is every ordinary non-throttled failure -- and PowerShell wraps it as a
            # MethodInvocationException. The try/catch here caught it, but -ErrorVariable is
            # populated by the ENGINE from the error stream and captures records raised inside
            # nested calls even when an inner catch swallowed them (see Remove-OERErrorRecord), so
            # one bogus record per failed read still reached the caller. A single clean
            # Get-OERInventory read of 100 groups shipped 96 of them. Get-RetryAfterHeaderValue asks
            # the collection what it holds instead of asking for a header that is not there.
            $RawHeaders = $null
            try { $RawHeaders = $ErrorRecord.Exception.Response.Headers } catch { Remove-OERErrorRecord -Record $PSItem }
            $HeaderSeconds = ConvertFrom-RetryAfterHeader (Get-RetryAfterHeaderValue $RawHeaders)
        }

        # Classify the failure. The status wins whenever it resolved to a real HTTP code, so a 403 or
        # a 404 is still refused here and fails immediately; only a missing/zero status falls through
        # to the converter.
        [bool]$ThrottleDetected    = $false
        [bool]$UnavailableDetected = $false
        if ($Status -eq 429) {
            $ThrottleDetected = $true
        } elseif ($Status -eq 503) {
            $UnavailableDetected = $true
        } elseif (-not $Status) {
            $Converted = $null
            try { $Converted = Convert-GraphHttpException $ErrorRecord } catch { Remove-OERErrorRecord -Record $PSItem }
            $Code = [string]$Converted.FullyQualifiedErrorId
            # The converted record's message is "<code>: <message>", so this covers the case where
            # Graph reported the throttle only in prose and no code could be extracted.
            $Text = [string]$Converted.Exception.Message
            if (($Code -in 'TooManyRequests', 'activityLimitReached') -or
                ($Text -match '(?i)\bTooManyRequests\b|\bactivityLimitReached\b|too many requests')) {
                $ThrottleDetected = $true
            } elseif ($Code -eq 'ServiceUnavailable') {
                $UnavailableDetected = $true
            }
        }

        [string]$Source = 'server-directed'
        if ($ThrottleDetected) {
            # No header: exponential fallback, per Learn's guidance.
            if ($null -ne $HeaderSeconds) {
                $Seconds = $HeaderSeconds
            } else {
                $Seconds = [Math]::Pow(2, $Attempt)
                $Source  = 'exponential fallback'
            }
        } elseif ($UnavailableDetected -and $null -ne $HeaderSeconds) {
            $Seconds = $HeaderSeconds
        } else {
            return $null
        }

        # Clamp. The lower bound is ONE second, not zero: the retry loop below is bounded by a wait
        # BUDGET rather than a retry count, so a zero-second wait would let a server that keeps
        # answering "Retry-After: 0" spin the loop without ever spending budget.
        # The upper bound is unchanged at 120 s and remains the guard against a hostile or absurd
        # header: the budget bounds the TOTAL wait, this bounds any SINGLE unresponsive interval.
        if ($Seconds -lt 1)   { $Seconds = 1 }
        if ($Seconds -gt 120) { $Seconds = 120 }
        return @{ Seconds = [int]$Seconds; Source = $Source }
    }

    # -- Helper: how much of the per-CALL budget has this Invoke-OERGraphRequest call already used? --
    # Whole seconds, deliberately the LARGER of two measures:
    #   1. Real wall-clock time since the call started. This is the honest measure and the one that
    #      binds in production: it counts time spent IN the requests as well as time spent waiting,
    #      so a call cannot creep past its ceiling through slow responses rather than sleeps.
    #   2. The seconds this call has asked Start-Sleep to wait. In production this is always the
    #      SMALLER of the two, because every sleep is also wall-clock time, so it never loosens the
    #      real bound. It exists so the bound is deterministic under test: the unit suite mocks
    #      Start-Sleep, which pins measure 1 near zero, and a bound no test can drive is a bound no
    #      test can prove -- which is how the inert Retry-After read survived review in the first
    #      place.
    function Get-CallElapsed ([hashtable]$CallBudget) {
        if (-not $CallBudget) { return 0 }
        $WallClockSecond = ([DateTime]::UtcNow - $CallBudget.StartUtc).TotalSeconds
        return [int][Math]::Floor([Math]::Max($WallClockSecond, [double]$CallBudget.WaitSpent))
    }

    # -- Helper: did the CONVERTER read this ErrorId from the Graph error body, or invent it? --
    # Convert-GraphHttpException uses the body's error.code as the ErrorId whenever it can extract
    # one. Only when it cannot does it fall back to a label it derived from the HTTP status: one of
    # its own $StatusLabels entries, 'HTTP<status>' for a status it has no label for, or
    # 'GraphError' when even the status is unknown. This pattern is that fallback vocabulary and
    # NOTHING else -- keep it in step with Convert-GraphHttpException's $StatusLabels table.
    # A status-derived id means "the code, if any, is only in the message text"; any other id means
    # Graph named the failure itself and that name is authoritative.
    function Test-StatusDerivedErrorId ([string]$ErrorId) {
        return [bool]($ErrorId -match ('^(?:BadRequest|Unauthorized|Forbidden|NotFound|Conflict|TooManyRequests|' +
                'InternalServerError|ServiceUnavailable|GraphError|HTTP\d+)$'))
    }

    # -- Helper: does this record NAME one of the codes the caller declared expected? --
    # SINGLE OWNER of the expected-code token rule inside this wrapper. Returns the matched
    # DECLARED code (so the marker can report which one answered) or $null.
    #
    # WHOLE-TOKEN, never a prefix. A prefix test would OVER-match:
    # ResourceTypeNotSupportedInThisTenant is a DIFFERENT failure and softening it would turn a
    # failed read into a silent empty answer -- the exact defect class issue #76 exists to prevent.
    # Splitting and comparing whole, trimmed segments with -eq (case-insensitive on strings) refuses
    # that.
    #
    # THE ID IS READ ALWAYS; THE MESSAGE TEXT ONLY WHEN THE ID IS STATUS-DERIVED, and that
    # distinction is the whole guard. Convert-GraphHttpException puts the Graph error.code in the
    # ErrorId, so the id alone answers the normal case -- but a FullyQualifiedErrorId is COMPOSED
    # from every frame that re-raises the record and the code is not always the first comma-separated
    # segment ('PathNotFound,Get-ItemCommand' is the engine's own shape), so every segment is
    # compared. The record's "<code>: <message>" detail text is a SECOND-CHOICE source, needed only
    # for the case where the body could not be parsed and the converter fell back to a status label,
    # leaving the code in the message alone.
    #
    # Reading that text unconditionally was a defect: a GENUINE failure whose prose merely mentions
    # the declared code as a colon-delimited token was softened into an expected answer. Measured,
    #   {"code":"Authorization_RequestDenied","message":"Insufficient privileges: ResourceTypeNotSupported"}
    # came back as the marker with StatusCode 403 and Get-OERGroup then recorded PimEligibility = @()
    # -- a failed read stored as an empty fact, issue #76's own defect class reintroduced through the
    # softening. Graph named that failure Authorization_RequestDenied; when Graph has named the
    # failure, its name is the answer and the prose is not consulted.
    #
    # Get-OERGroup carries the same TOKEN RULE inline, but for a DIFFERENT ARRIVAL SHAPE, and
    # NEITHER GUARD BACKS UP THE OTHER. This gate answers a record that arrives as a MARKER, which
    # is the only shape a live read produces once a code is declared here; the inline copy answers
    # one that arrives THROWN, which happens when this wrapper is mocked or a frame between the two
    # re-raises. Measured in both directions rather than reasoned: softening THIS gate to an
    # unconditional match with the inline copy fully intact brought the defect back completely and
    # SILENTLY -- PimEligibility present, Count 0, zero error records -- since a softened failure
    # never throws and the inline copy therefore never runs. Softening only the inline copy instead
    # leaves PimEligibility = @() with 5 records. This gate is the one that fires in production.
    # Keep the two rules in step, and never delete either one on the strength of the other.
    function Get-ExpectedGraphErrorMatch ([System.Management.Automation.ErrorRecord]$Record, [string[]]$Expected) {
        if ($null -eq $Record -or -not $Expected) { return $null }
        [string[]]$IdSegment = @(([string]$Record.FullyQualifiedErrorId) -split ',') |
            ForEach-Object { $PSItem.Trim() }
        [string[]]$Candidate = $IdSegment
        # ANY segment, not just the first: composition can put the status label anywhere in the id,
        # and a composed id such as 'BadRequest,Get-OERGroup' is still an id the converter derived
        # from the status. A real Graph code in ANY segment blocks the message text.
        if (@($IdSegment | Where-Object { Test-StatusDerivedErrorId $PSItem }).Count -gt 0) {
            $Candidate = @(
                $IdSegment
                ([string]$Record.ErrorDetails.Message) -split ':'
                ([string]$Record.Exception.Message) -split ':'
            ) | ForEach-Object { $PSItem.Trim() }
        }
        foreach ($Code in $Expected) {
            if ([string]::IsNullOrWhiteSpace($Code)) { continue }
            foreach ($Segment in $Candidate) {
                if ($Segment -eq $Code) { return $Code }
            }
        }
        return $null
    }

    # -- Helper: the object a caller gets INSTEAD of a raised error --
    # A typed marker rather than $null, deliberately. $null is already this wrapper's "empty body"
    # value in the paging loop, and a caller reading .value off $null gets @($null) -- a one-element
    # collection holding nothing, which is precisely the "failed read recorded as an empty fact"
    # shape issue #76 is about. A distinct type name cannot be confused with a Graph response
    # hashtable, and carrying the code lets a caller that declared several tell them apart.
    # Module-internal: it never reaches a user, so it needs no format view.
    function Get-ExpectedGraphErrorResult ([string]$Code, $StatusValue, [string]$Detail, [string]$RequestUri) {
        $Marker = [PSCustomObject]@{
            ExpectedErrorCode = $Code
            StatusCode        = $StatusValue
            Message           = $Detail
            Uri               = $RequestUri
        }
        $Marker.PSObject.TypeNames.Insert(0, 'Omnicit.EntraRBAC.GraphExpectedError')
        return $Marker
    }

    # -- Helper: turn a NON-raised HTTP failure back into the ErrorRecord shape this function
    #    already knows how to handle --
    # Under -SkipHttpErrorCheck the SDK hands back the error BODY and sets the status/header
    # variables instead of throwing, so there is no ErrorRecord for the throttle, claims-challenge
    # and conversion logic below to read. This rebuilds one, and it deliberately hangs the facts on
    # the member names those readers ALREADY understand rather than teaching them a third shape:
    #   .Response          -- an HttpResponseMessage, what Convert-GraphHttpException and
    #                         Get-ClaimsFromException read (body, status, WWW-Authenticate).
    #   .ResponseStatusCode and .ResponseHeaders -- the Kiota member names
    #                         Get-ResponseFactFromException walks for, so Retry-After honouring works
    #                         unchanged. That header collection is a
    #                         Dictionary[string, IEnumerable[string]] with an ordinal-ignore-case
    #                         comparer (Microsoft.Graph.PowerShell's WebResponseHelper), which is
    #                         exactly shape 1 of Get-RetryAfterHeaderValue.
    # SECURITY: no HttpRequestMessage is attached, and none exists on this path -- the SDK never
    # built an exception, so no "Authorization: Bearer <token>" object is created that could leak.
    # Do not add one here to make the record look more realistic.
    function ConvertTo-SoftFailureRecord ([int]$StatusValue, $HeaderMap, $BodyObject, [string]$RequestUri) {
        $BodyText = ''
        $Http = $null
        try {
            $BodyText = if ($BodyObject -is [string]) { $BodyObject }
            elseif ($null -ne $BodyObject) { $BodyObject | ConvertTo-Json -Depth 10 -Compress }
            else { '' }
            # [System.Net.HttpStatusCode]$StatusValue would THROW UndefinedIntegerToEnum for the
            # unknown-status value 0 -- PowerShell refuses an int with no matching enum member --
            # and that throw would land in the catch below, leaving .Response null on a record whose
            # body did carry a usable Graph code. [Enum]::ToObject performs no such check.
            $Http = [System.Net.Http.HttpResponseMessage]::new(
                [System.Net.HttpStatusCode][Enum]::ToObject([System.Net.HttpStatusCode], $StatusValue))
            $Http.Content = [System.Net.Http.StringContent]::new([string]$BodyText)
            if ($null -ne $HeaderMap) {
                foreach ($Key in @($HeaderMap.Keys)) {
                    [void]$Http.Headers.TryAddWithoutValidation([string]$Key, [string[]]@($HeaderMap[$Key]))
                }
            }
        } catch {
            # Same never-throw contract as every other helper on this failure path: an escaping
            # exception here would REPLACE the Graph error the caller needs to see. A record with a
            # null .Response still converts -- Convert-GraphHttpException falls back to the message.
            Remove-OERErrorRecord -Record $PSItem
        }
        $Exception = [System.Exception]::new(
            ("Response status code does not indicate success: {0}." -f $StatusValue))
        if ($null -ne $Http) { $Exception | Add-Member -NotePropertyName Response -NotePropertyValue $Http -Force }
        $Exception | Add-Member -NotePropertyName ResponseStatusCode -NotePropertyValue ([int]$StatusValue) -Force
        if ($null -ne $HeaderMap) {
            $Exception | Add-Member -NotePropertyName ResponseHeaders -NotePropertyValue $HeaderMap -Force
        }
        return [System.Management.Automation.ErrorRecord]::new(
            $Exception, 'GraphHttpError',
            [System.Management.Automation.ErrorCategory]::InvalidOperation, $RequestUri)
    }

    # -- Helper: ONE transport call, plus the soft-failure translation -ExpectedErrorCode needs --
    # Returns @{ Kind = 'Response' | 'Expected' | 'Failure'; Value = ... }. Throws nothing of its
    # own: a genuinely raised SDK error propagates to the CALLER's catch, which still scrubs first.
    # All three transport call sites below route through here, so a -SkipHttpErrorCheck response can
    # never be mistaken for a success on the claims-challenge and token-rejected retry paths either.
    #
    # THE STATUS-VARIABLE NAME IS A CONTRACT with the $InvokeParams built in Invoke-GraphSingle.
    # -StatusCodeVariable and -ResponseHeadersVariable set the named variable in the scope that
    # INVOKED the cmdlet, which is this function's scope, so both are pre-cleared here and read back
    # straight after the call.
    #
    # WHEN THE STATUS DOES NOT RESOLVE the body is consulted instead. That fallback is load-bearing,
    # not defensive decoration: if the status variable were ever missing, treating the answer as a
    # success would hand the caller a Graph ERROR BODY as though it were data -- a silent wrong
    # answer, far worse than the noisy one this whole change removes. A Graph error response always
    # carries a top-level 'error' object and an ordinary response never does. A 2xx is a success
    # whatever the body holds, so a legitimate payload can never be re-read as a failure.
    function Invoke-GraphAttempt ([hashtable]$Parameters, [string[]]$Expected, [string]$RequestUri) {
        $OERSoftStatus = $null
        $OERSoftHeaders = $null
        $Response = Invoke-MgGraphRequest @Parameters
        if (-not $Expected) { return @{ Kind = 'Response'; Value = $Response } }

        # NOT "$OERSoftStatus -as [int]" on its own. $null -as [int] is 0, NOT $null (measured), so
        # a status variable the SDK never set would read as the literal status 0 -- the unknown-status
        # branch below would never run and EVERY answer, success included, would be rebuilt as a soft
        # failure. The raw variable is tested for null first, and only then converted.
        $Status = $null
        if ($null -ne $OERSoftStatus) { $Status = $OERSoftStatus -as [int] }
        if ($null -ne $Status -and $Status -ge 200 -and $Status -lt 300) {
            return @{ Kind = 'Response'; Value = $Response }
        }
        if ($null -eq $Status) {
            $LooksLikeError = $false
            if ($Response -is [System.Collections.IDictionary]) { $LooksLikeError = $Response.Contains('error') }
            elseif ($null -ne $Response) { $LooksLikeError = @($Response.PSObject.Properties.Name) -contains 'error' }
            if (-not $LooksLikeError) { return @{ Kind = 'Response'; Value = $Response } }
            # Zero, not a guess: Get-ResponseFactFromException already reads 0 as "status unknown",
            # and Convert-GraphHttpException still extracts the code from the body.
            $Status = 0
        }

        $Record = ConvertTo-SoftFailureRecord -StatusValue $Status -HeaderMap $OERSoftHeaders `
            -BodyObject $Response -RequestUri $RequestUri
        $Converted = Convert-GraphHttpException $Record
        $Matched = Get-ExpectedGraphErrorMatch -Record $Converted -Expected $Expected
        if ($Matched) {
            return @{
                Kind  = 'Expected'
                Value = (Get-ExpectedGraphErrorResult -Code $Matched -StatusValue $Status `
                        -Detail ([string]$Converted.Exception.Message) -RequestUri $RequestUri)
            }
        }
        return @{ Kind = 'Failure'; Value = $Record }
    }

    # -- Single-request logic: one attempt, its bounded Retry-After backoff, and its single-shot
    # claims-challenge / 401 retries. Everything below was the whole function body before -All was
    # added. It is now a nested function so the -All paging loop (further down) can call it once
    # per page -- each page fetch gets its own bounded backoff and its own single-shot retries,
    # rather than sharing a single budget across every page. PSSA's PSReviewUnusedParameter does not
    # follow closures into nested functions, so every value this needs is an explicit named
    # parameter instead of a read of the outer $Method/$Uri/$Body.
    function Invoke-GraphSingle ([string]$SingleMethod, [string]$SingleUri, [hashtable]$SingleBody, [hashtable]$CallBudget, [string[]]$SingleExpectedErrorCode) {
        $InvokeParams = @{
            Method      = $SingleMethod
            Uri         = $SingleUri
            Verbose     = $false
            ErrorAction = 'Stop'
        }
        if ($SingleBody) { $InvokeParams.Body = $SingleBody }
        if ($SingleExpectedErrorCode) {
            # -SkipHttpErrorCheck is the ONLY lever that keeps an expected answer out of the caller's
            # -ErrorVariable, and it is added ONLY when a caller declared one. Measured on the live
            # shape (400 ResourceTypeNotSupported, 96 of 100 groups): a single failed read put SEVEN
            # records into the caller's collection -- the SDK's own terminating record and the
            # CmdletInvocationException carrying it, four copies of the converted record, and the
            # RuntimeException from re-throwing it. Returning a value instead of throwing removes
            # five of the seven; only skipping the SDK's own ThrowTerminatingError removes the other
            # two. -ErrorAction Ignore does NOT: ThrowTerminatingError is not preference-governed,
            # and Ignore measured identical to Stop, SilentlyContinue and Continue. Neither does
            # 2>$null on the call: redirecting the error stream measured EQUAL, not better -- the
            # same record count with it as without. Measured twice, on two harnesses: 3 with and 3
            # without on one, 7 with and 7 without on the other. The ABSOLUTE figure depends on how
            # many frames re-raise the record and is not a constant of this code; the EQUALITY is
            # the finding, and it holds because -ErrorVariable is filled by the engine from the
            # error stream before any redirection of that stream applies. Redirection is not a lever
            # here; -SkipHttpErrorCheck is, and with it declared the same read measures 0.
            #
            # In the SDK (InvokeMgGraphRequest.cs) the switch reads
            #   if (ShouldCheckHttpStatus && !isSuccess) { ThrowTerminatingError(...) }
            #   await ProcessResponseAsync(httpResponseMessage);
            # with ShouldCheckHttpStatus => !SkipHttpErrorCheck, so the failure body is written to
            # the pipeline and the two variables below are set instead of an error being raised.
            # Every OTHER call site is untouched and keeps the exact -ErrorAction Stop behaviour it
            # has always had.
            $InvokeParams.SkipHttpErrorCheck      = $true
            $InvokeParams.StatusCodeVariable      = 'OERSoftStatus'
            $InvokeParams.ResponseHeadersVariable = 'OERSoftHeaders'
        }

        # SECURITY: method and uri only. The body can carry principal ids and policy rules, and the
        # request itself carries the Authorization: Bearer header -- neither is ever written to any
        # stream.
        Write-Verbose "[Invoke-OERGraphRequest] $SingleMethod $SingleUri"

        # The Access Reviews and inventory reads are documented as heavily throttled; a 429 used to
        # lose the whole section. The claims-challenge and 401 retries below are unchanged and still
        # fire at most once each.
        #
        # WHY A BUDGET AND NOT A RETRY COUNT. Microsoft Learn's throttling guidance is "wait the
        # number of seconds specified in the Retry-After header ... and retry the request until it
        # succeeds". A retry COUNT cannot express that: the previous ceiling of three retries over a
        # 1 + 2 + 4 exponential fallback gave this module a total throttle tolerance of SEVEN
        # seconds, so a single server-directed "Retry-After: 60" could never be honoured even once.
        # The bound is therefore a total WAIT BUDGET. An unbounded loop is not an option either --
        # every cmdlet in this module runs interactively as well as in automation, and a session
        # that never returns is worse than a clean error.
        #
        # TWO NESTED BOUNDS. A per-page budget alone is NOT enough, and the reason is specific to how
        # this function fails: when Invoke-GraphSingle finally throws for page N the exception still
        # propagates out of the paging loop and the call still fails -- a paged read is all-or-nothing
        # ON THE SUCCESS CHANNEL, by design (issue #73). What changed under #73 is that $AllValues is
        # no longer silently DISCARDED when that happens: the paging loop's own catch (further down
        # this file) attaches what was aggregated so far to the thrown exception as PartialValue,
        # alongside NextLink and PageNumber, for a caller that opts in to read them. The call keeps
        # throwing either way, so the arithmetic below is unchanged. A per-page budget therefore buys
        # a LONGER WAIT FOR THE SAME TOTAL FAILURE -- 61 paged requests (the
        # Get-OERAccessReviewInstance -IncludeStages -IncludeDecisions fan-out over 30 instances)
        # could pin a session for over an hour and still throw. The per-page budget stays, because it
        # stops one slow page from starving the pages after it, but it is now nested inside a bound
        # on the WHOLE call.
        #
        # THE NUMBERS, and why these values (internal constants on purpose -- no public parameter):
        #   ThrottleWaitBudgetSeconds = 300, per REQUEST (per PAGE under -All). Five minutes absorbs
        #     a server-directed "Retry-After: 60" FIVE times over, which satisfies the hard
        #     requirement (one 60 s wait plus at least one further retry) with real headroom, while
        #     still being a wait an operator watching a verbose stream will sit through.
        #   CallDeadlineSeconds = 900, per CALL, however many pages that call fetches. It is a
        #     DEADLINE, not a wait allowance: TIME SPENT IN THE REQUESTS THEMSELVES COUNTS TOWARD IT,
        #     not just time spent sleeping (see Get-CallElapsed), so a call cannot creep past its
        #     ceiling through slow responses rather than sleeps. Size it as "how long may this
        #     command keep BACKING OFF", NOT as "how long may this whole command run" -- the second
        #     overstates what this number bounds, and this comment used to say it. The deadline is
        #     only ever CONSULTED at a decision to WAIT, so it caps a THROTTLED call and nothing
        #     else: an -All walk that is never throttled follows @odata.nextLink for as long as Graph
        #     keeps handing out pages and never reads this number at all. Bounding THAT is a
        #     separate, pre-existing gap, deliberately not closed here -- closing it would mean
        #     ending a paging loop mid-enumeration, which the paragraph below rules out for a
        #     stronger reason. Invoke-OERArmRequest carries the same correction, worded the same way;
        #     keep the mirrored pair in step.
        #     What it DOES bound has a deliberate consequence worth knowing: a long, legitimately
        #     slow -All enumeration that has already run past 900 s will refuse ANY further throttle
        #     backoff, turning a recoverable 429 into a hard failure. That is the intended trade --
        #     an unbounded backoff is worse -- but it is why the name says deadline.
        #     Three times the per-page budget: enough that three fully-throttled pages can still be
        #     ridden out, which is the realistic recoverable case, but a ceiling the operator can
        #     predict from the cmdlet alone rather than from a page count they cannot see. Fifteen
        #     minutes is also about the longest an interactive operator will wait before concluding a
        #     session is hung, and past that a clean error beats a longer wait for the same
        #     all-or-nothing failure.
        #   ThrottleRetryHardCap = 10, per request. A runaway guard, not a primary bound. It is
        #     unreachable in both realistic regimes (server-directed 60 s waits exhaust the page
        #     budget after five retries; the exponential fallback exhausts it after eight), and only
        #     binds when a server answers with a very small Retry-After over and over -- the one
        #     shape where a budget alone would allow hundreds of requests against an already
        #     throttled endpoint.
        #
        # The per-call bound is enforced ONLY at the decision to wait, never by stopping the paging
        # loop between pages. Truncating an enumeration on a deadline would silently return a partial
        # collection as though it were complete, which is the exact defect class -All exists to fix.
        [int]$ThrottleWaitBudgetSeconds = 300
        [int]$CallDeadlineSeconds = 900
        [int]$ThrottleRetryHardCap = 10
        [int]$ThrottleWaitSpent = 0
        [int]$ThrottleAttempt = 0
        $AttemptError = $null
        while ($true) {
            $Attempt = $null
            try {
                if (-not $SingleExpectedErrorCode) { return Invoke-MgGraphRequest @InvokeParams }
                $Attempt = Invoke-GraphAttempt -Parameters $InvokeParams -Expected $SingleExpectedErrorCode -RequestUri $SingleUri
            } catch {
                # Security: remove the raw error record before anything else.
                # The TargetObject (HttpRequestMessage) contains "Authorization: Bearer <token>".
                Remove-OERErrorRecord -Record $PSItem
                $AttemptError = $PSItem
                # The SDK raised anyway -- a connection-level failure has no HTTP response to skip,
                # and a build that ignored -SkipHttpErrorCheck would land here too. The declared code
                # is still honoured, from the CONVERTED record, so the caller gets its answer either
                # way; only the two SDK-raised records this path cannot suppress remain. Scrub first,
                # always: this branch handles a record that CAN carry a bearer token.
                if ($SingleExpectedErrorCode) {
                    $ThrownConverted = Convert-GraphHttpException $PSItem
                    $ThrownMatch = Get-ExpectedGraphErrorMatch -Record $ThrownConverted -Expected $SingleExpectedErrorCode
                    if ($ThrownMatch) {
                        return (Get-ExpectedGraphErrorResult -Code $ThrownMatch `
                                -StatusValue (Get-ResponseFactFromException $PSItem.Exception).Status `
                                -Detail ([string]$ThrownConverted.Exception.Message) -RequestUri $SingleUri)
                    }
                }
            }
            if ($null -ne $Attempt) {
                # 'Response' is the ordinary answer and 'Expected' is a declared code the caller
                # asked to receive as data; neither is a failure, so both are handed straight back.
                if ($Attempt.Kind -ne 'Failure') { return $Attempt.Value }
                # A non-2xx that arrived as DATA. It becomes the attempt error so the throttle,
                # claims-challenge and token-rejected paths below judge it exactly as they judge a
                # raised one -- a 429 is still retried, a 403 still fails.
                $AttemptError = $Attempt.Value
            }

            $Delay = Get-ThrottleDelay -ErrorRecord $AttemptError -Attempt $ThrottleAttempt
            if ($null -eq $Delay) { break }

            [int]$PageRemaining = $ThrottleWaitBudgetSeconds - $ThrottleWaitSpent
            [int]$CallRemaining = $CallDeadlineSeconds - (Get-CallElapsed -CallBudget $CallBudget)

            # The per-CALL bound is checked FIRST so that when both are gone the operator is told
            # about the one that actually ends the command rather than the one that ends this page.
            if ($Delay.Seconds -gt $CallRemaining) {
                Write-Verbose ("[Invoke-OERGraphRequest] Throttled. The next wait needs $($Delay.Seconds) s " +
                    "($($Delay.Source)) but only $CallRemaining s of the $CallDeadlineSeconds s per-CALL budget remain. Giving up.")
                break
            }
            if ($Delay.Seconds -gt $PageRemaining) {
                # Honouring a wait this module cannot afford would mean retrying EARLY, which just
                # earns another throttle. Give up cleanly and let the caller see the Graph error.
                Write-Verbose ("[Invoke-OERGraphRequest] Throttled. The next wait needs $($Delay.Seconds) s " +
                    "($($Delay.Source)) but only $PageRemaining s of the $ThrottleWaitBudgetSeconds s per-REQUEST budget remain. Giving up.")
                break
            }
            if ($ThrottleAttempt -ge $ThrottleRetryHardCap) {
                Write-Verbose ("[Invoke-OERGraphRequest] Throttled. Reached the hard cap of $ThrottleRetryHardCap " +
                    "throttle retries with $PageRemaining s of per-REQUEST budget still unspent. Giving up.")
                break
            }

            $ThrottleAttempt++
            $ThrottleWaitSpent += $Delay.Seconds
            if ($CallBudget) { $CallBudget.WaitSpent += $Delay.Seconds }
            $PageRemaining = $ThrottleWaitBudgetSeconds - $ThrottleWaitSpent
            $CallRemaining = $CallDeadlineSeconds - (Get-CallElapsed -CallBudget $CallBudget)
            # SECURITY: the delay and its provenance only. The header COLLECTION this value was read
            # from is never written to any stream -- see Get-ResponseFactFromException.
            Write-Verbose ("[Invoke-OERGraphRequest] Throttled. Waiting $($Delay.Seconds) s ($($Delay.Source)) " +
                "before retry $ThrottleAttempt; $PageRemaining s of per-REQUEST and $CallRemaining s of per-CALL budget remain.")
            Start-Sleep -Seconds $Delay.Seconds
        }

        # -- Check for ACRS claims challenge on the last attempt's failure --
        # $AttemptError holds the error from the most recent attempt (the throttle loop above may
        # have retried several times); it is the only one relevant once the loop has given up.
        # No session-sticky guard: this function retries at most once per call (the retry block
        # below has no loop and a second failure throws), so each command can step up as needed.
        $ClaimsJson = Get-ClaimsFromException $AttemptError

        if ($ClaimsJson) {
            # App-only sessions (ClientSecret/ClientCertificate) cannot perform an interactive ACRS
            # step-up, and the module deliberately does not cache the secret/certificate material to
            # replay it (SECURITY: never store a plain-text secret). Surface a clear, actionable
            # error instead of calling Initialize-OERAuth, whose credential-material validation
            # would throw.
            if ($script:_OERAuthState.AuthMethod -in 'ClientSecret', 'ClientCertificate') {
                throw [System.Management.Automation.ErrorRecord]::new(
                    [System.Exception]::new(
                        "Microsoft Graph returned an authentication-context (ACRS) claims challenge, but the " +
                        "current session is app-only ($($script:_OERAuthState.AuthMethod)) and cannot interactively " +
                        "step up. Grant the required application permission/authentication context to the app " +
                        "registration, or re-run interactively with Connect-OER -Interactive."),
                    'AppOnlyClaimsChallengeUnsatisfiable',
                    [System.Management.Automation.ErrorCategory]::AuthenticationError,
                    $SingleUri)
            }

            Write-Verbose "[Invoke-OERGraphRequest] ACRS claims challenge detected. Performing step-up authentication..."
            Write-Verbose "[Invoke-OERGraphRequest] Claims: $ClaimsJson"

            $TenantId = $script:_OERAuthState.TenantId
            # Forward the cached ClientId (see Invoke-OERArmRequest for the rationale): a
            # user-assigned managed identity must re-acquire as the same principal, not the
            # system-assigned one.
            $ClaimsParams = @{
                TenantId        = $TenantId
                AuthMethod      = $script:_OERAuthState.AuthMethod
                ClaimsChallenge = $ClaimsJson
            }
            if ($script:_OERAuthState.ClientId) { $ClaimsParams.ClientId = $script:_OERAuthState.ClientId }
            Initialize-OERAuth @ClaimsParams

            # -- Retry once with the upgraded token --
            # Routed through Invoke-GraphAttempt like the first attempt: under -SkipHttpErrorCheck a
            # second failure comes back as DATA, and returning it here would hand the caller a Graph
            # error body as though the step-up had worked.
            $RetryAttempt = $null
            try {
                if (-not $SingleExpectedErrorCode) { return Invoke-MgGraphRequest @InvokeParams }
                $RetryAttempt = Invoke-GraphAttempt -Parameters $InvokeParams -Expected $SingleExpectedErrorCode -RequestUri $SingleUri
            } catch {
                Remove-OERErrorRecord -Record $PSItem
                throw Convert-GraphHttpException $PSItem
            }
            if ($RetryAttempt.Kind -ne 'Failure') { return $RetryAttempt.Value }
            throw Convert-GraphHttpException $RetryAttempt.Value
        }

        # -- Token rejected/expired (not a claims challenge) -- re-auth and retry --
        # A 401 here means the bearer token is invalid or expired (claims challenges were already
        # handled above). Force a token refresh (MSAL refresh-token path, usually no prompt) and
        # retry once instead of surfacing the failure.
        #
        # STATUS READ: PRIMARY vs SECONDARY, same split as Get-ThrottleDelay above and via the SAME
        # single helper -- not a second inlined extraction (issue #75). The Kiota walk is primary
        # because a 401 that survives Kiota's own RetryHandler exhaustion (for example a token that
        # expires mid-retry-storm) arrives as an AggregateException/ApiException with no .Response
        # member, exactly like the 429/503 shape Get-ThrottleDelay was written against.
        #
        # The .Response.StatusCode read below is kept as the SECONDARY path, not a leftover: issue
        # #75 was originally filed on the assumption that this read is as dead here as it was on the
        # throttle path, and that assumption was corrected on the issue itself after review against
        # the SDK. Microsoft.Graph.PowerShell.Authentication.Helpers.HttpResponseException -- the
        # type an ORDINARY 401 actually arrives as -- derives from HttpRequestException and DOES
        # expose Response : HttpResponseMessage. The Kiota ApiException shape (no .Response) is
        # specific to RetryHandler EXHAUSTION, i.e. the 429/503 path, not a plain 401. Deleting this
        # secondary read would break the ordinary 401 case it still primarily serves.
        $Fact = Get-ResponseFactFromException $AttemptError.Exception
        $StatusCode = $Fact.Status
        if ($null -eq $StatusCode) {
            try { $StatusCode = [int]$AttemptError.Exception.Response.StatusCode } catch { Remove-OERErrorRecord -Record $PSItem }
        }
        [bool]$TokenInvalid = $StatusCode -eq 401 -or
            $AttemptError.Exception.Message -match 'InvalidAuthenticationToken|CompactToken|token is expired|Lifetime validation failed'

        if ($TokenInvalid -and $script:_OERAuthState) {
            # App-only sessions cannot silently force-refresh without the original credential
            # material, which is intentionally not cached. Emit a clear error rather than calling
            # Initialize-OERAuth (which would throw on the missing -ClientSecret/-Certificate).
            if ($script:_OERAuthState.AuthMethod -in 'ClientSecret', 'ClientCertificate') {
                throw [System.Management.Automation.ErrorRecord]::new(
                    [System.Exception]::new(
                        "Microsoft Graph rejected the access token (status=$StatusCode) for an app-only " +
                        "($($script:_OERAuthState.AuthMethod)) session. Re-authenticate with Connect-OER using the " +
                        "client secret or certificate to acquire a fresh token."),
                    'AppOnlyTokenRefreshUnsatisfiable',
                    [System.Management.Automation.ErrorCategory]::AuthenticationError,
                    $SingleUri)
            }

            Write-Verbose "[Invoke-OERGraphRequest] Token rejected (status=$StatusCode). Forcing re-authentication and retrying once..."
            # Forward the cached ClientId (see Invoke-OERArmRequest for the rationale): a
            # user-assigned managed identity must re-acquire as the same principal, not the
            # system-assigned one.
            $RefreshParams = @{
                TenantId     = $script:_OERAuthState.TenantId
                AuthMethod   = $script:_OERAuthState.AuthMethod
                ForceRefresh = $true
            }
            if ($script:_OERAuthState.ClientId) { $RefreshParams.ClientId = $script:_OERAuthState.ClientId }
            Initialize-OERAuth @RefreshParams
            # Same reason as the claims retry above: a soft failure must not read as a success.
            $RefreshAttempt = $null
            try {
                if (-not $SingleExpectedErrorCode) { return Invoke-MgGraphRequest @InvokeParams }
                $RefreshAttempt = Invoke-GraphAttempt -Parameters $InvokeParams -Expected $SingleExpectedErrorCode -RequestUri $SingleUri
            } catch {
                Remove-OERErrorRecord -Record $PSItem
                throw Convert-GraphHttpException $PSItem
            }
            if ($RefreshAttempt.Kind -ne 'Failure') { return $RefreshAttempt.Value }
            throw Convert-GraphHttpException $RefreshAttempt.Value
        }

        # -- Not recoverable -- convert and re-throw --
        throw Convert-GraphHttpException $AttemptError
    }

    # -- Per-CALL wait budget, shared by every page of a -All enumeration --
    # A hashtable rather than two scalars so the nested function mutates THIS state by reference; a
    # value type would give each page its own copy and the per-call bound would never bind. The
    # single-page path gets one too, so both paths run identical code.
    #
    # THE PER-CALL BOUND CAN STILL BIND ON THE SINGLE-PAGE PATH. This comment used to assert the
    # opposite -- that 900 s "can never be reached inside a 300 s page budget" -- and that is false.
    # Get-CallElapsed returns the LARGER of wall-clock time and seconds slept, and wall-clock counts
    # time spent IN the request, so one slow or hung Graph request can carry a single call past 900 s
    # with WaitSpent still at 0. The per-call check is then the one that fires, which is the intended
    # behaviour: the deadline exists precisely so slow responses cannot creep past the ceiling that
    # sleeps alone would respect. Invoke-OERArmRequest carried the same false sentence, copied from
    # here, and was corrected in the same change -- keep the pair in step.
    $CallBudget = @{ StartUtc = [DateTime]::UtcNow; WaitSpent = 0 }

    if (-not $All) {
        return Invoke-GraphSingle -SingleMethod $Method -SingleUri $Uri -SingleBody $Body -CallBudget $CallBudget `
            -SingleExpectedErrorCode $ExpectedErrorCode
    }

    # -- Paging: follow @odata.nextLink and aggregate the value arrays --
    # Invoke-MgGraphRequest returns a Hashtable, so the next link is read with the INDEXER. This
    # matches the convention the original hand-rolled paging loop in Get-OERAccessReviewDefinition
    # used -- the loop this -All switch was lifted from and later replaced. The form that genuinely
    # does NOT work on a Hashtable is property-bag reflection such as
    # $Page.PSObject.Properties['@odata.nextLink']: PSObject.Properties on a Hashtable exposes the
    # .NET Hashtable type's own members (Count, Keys, Values, ...), not its dictionary entries, so
    # that lookup always misses. The [string] cast below makes an absent key collapse to '' and end
    # the loop. The link is an absolute URL and is re-sent verbatim (unlike the ARM wrapper, which
    # converts it back to a path).
    # The loop lives outside Invoke-GraphSingle so every page gets its own bounded throttle backoff
    # and its own single-shot claims/401 retry, rather than sharing a budget across all pages.
    $AllValues = [System.Collections.Generic.List[object]]::new()
    $NextUri = $Uri
    [int]$PageNumber = 0
    while ($NextUri) {
        $PageNumber++
        Write-Verbose "[Invoke-OERGraphRequest] Fetching page $PageNumber..."
        try {
            $Page = Invoke-GraphSingle -SingleMethod $Method -SingleUri $NextUri -SingleBody $Body -CallBudget $CallBudget `
                -SingleExpectedErrorCode $ExpectedErrorCode
        } catch {
            # Security: remove the raw error record before anything else, same as every other catch
            # in this file (Global Constraint 3 / CLAUDE.md SECURITY rule 6). Invoke-GraphSingle
            # already scrubbed on its own internal catch paths, but this is a SEPARATE catch clause
            # and the source-hygiene gate counts scrub-first PER CATCH, not per call chain.
            Remove-OERErrorRecord -Record $PSItem

            # -- Issue #73: a failure on page N no longer discards what pages 1..N-1 already read --
            # F1, MEASURED (docs/development/rationale.md#graph-wrapper): a note property attached to
            # an ErrorRecord does NOT survive a `throw` -- PowerShell rebuilds the ErrorRecord on the
            # way out and the catching frame sees nothing. A note property attached to the EXCEPTION
            # DOES survive a `throw`, including across a module boundary, because the exception
            # instance is carried by reference rather than rebuilt. Attach to $PSItem.Exception,
            # NEVER to $PSItem itself -- the same idiom ConvertTo-SoftFailureRecord already uses
            # above for ResponseStatusCode/ResponseHeaders. Attaching to the ErrorRecord is the
            # obvious form and is the one that silently loses the data.
            #
            # The call still FAILS here -- nothing on the success channel changes, and the apply
            # engine's own reason for that (a short list reads as drift and provokes a write) is
            # unaffected. This only lets an OPTED-IN caller recover what was already fetched instead
            # of having it vanish along with the exception.
            $PartialSnapshot = $AllValues.ToArray()
            $PSItem.Exception | Add-Member -NotePropertyName PartialValue -NotePropertyValue $PartialSnapshot -Force
            $PSItem.Exception | Add-Member -NotePropertyName NextLink -NotePropertyValue $NextUri -Force
            $PSItem.Exception | Add-Member -NotePropertyName PageNumber -NotePropertyValue $PageNumber -Force

            # SECURITY: page number and item COUNT only, to -Verbose and nothing else. NextLink can
            # carry a $skiptoken/continuation value and is deliberately not printed here; an opted-in
            # caller reads it from $Err.Exception.NextLink instead.
            Write-Verbose ("[Invoke-OERGraphRequest] Page $PageNumber failed with $($PartialSnapshot.Count) " +
                "item(s) already aggregated from earlier pages. PartialValue, NextLink and PageNumber are " +
                "attached to the thrown error's Exception for a caller that opts in; the call still fails.")
            throw
        }
        # A -All GET can return an empty body (e.g. no results at all); indexing into a $null page
        # would otherwise throw a non-terminating InvalidOperation that becomes TERMINATING under a
        # caller's -ErrorAction Stop. Treat it as the end of the collection instead.
        if ($null -eq $Page) { break }
        # An expected-code marker is an ANSWER about the whole read, not a page of it, so it is
        # returned verbatim rather than aggregated. It has no value property, so falling through
        # would append @($null) and report one phantom item.
        #
        # ONLY ON PAGE ONE. A declared code means "there is nothing here to read" -- an answer the
        # first request can honestly give. It cannot be the answer to a request that has ALREADY
        # returned items: pages 1..N-1 exist, and returning the marker discards every one of them
        # while telling the caller the collection was empty. Measured before this gate: page 1
        # yielded 3 items, page 2 answered the declared code, and Get-OERGroup reported the group as
        # having no eligibility at all -- three real items silently lost, which is the same "failed
        # read recorded as an empty fact" the softening exists to avoid. Past page one the code is
        # therefore a FAILURE and is raised.
        #
        # ITS ERROR ID IS DELIBERATELY NOT THE GRAPH CODE. Naming it 'ResourceTypeNotSupported'
        # would let the caller's own last-line-of-defence test (Get-OERGroup's inline match) read it
        # back as the expected answer and re-create the very loss this raise exists to report.
        if (@($Page.PSObject.TypeNames) -contains 'Omnicit.EntraRBAC.GraphExpectedError') {
            if ($PageNumber -eq 1) { return $Page }
            $PartialSnapshot = $AllValues.ToArray()
            $LaterPageException = [System.Exception]::new(
                ("Microsoft Graph answered page $PageNumber of this enumeration with '$([string]$Page.ExpectedErrorCode)', " +
                "a code declared as an expected answer, after $($AllValues.Count) item(s) had already been " +
                "aggregated. A declared code is only an answer to the FIRST request of an enumeration; here it " +
                "is a failed read partway through one, so the partial collection is refused rather than " +
                "returned as though it were complete. Detail: $([string]$Page.Message)"))
            # Issue #73: the OTHER way a paged read fails partway through -- see the paging catch
            # above for the F1 measurement (attach to the Exception, never the ErrorRecord) and the
            # reader contract. A caller must be able to read the same three facts however the walk
            # died, so this path attaches them exactly like the catch does.
            $LaterPageException | Add-Member -NotePropertyName PartialValue -NotePropertyValue $PartialSnapshot -Force
            $LaterPageException | Add-Member -NotePropertyName NextLink -NotePropertyValue $NextUri -Force
            $LaterPageException | Add-Member -NotePropertyName PageNumber -NotePropertyValue $PageNumber -Force
            Write-Verbose ("[Invoke-OERGraphRequest] Page $PageNumber answered a declared expected code with " +
                "$($PartialSnapshot.Count) item(s) already aggregated from earlier pages. PartialValue, " +
                "NextLink and PageNumber are attached to the thrown error's Exception for a caller that opts in.")
            throw [System.Management.Automation.ErrorRecord]::new(
                $LaterPageException,
                'GraphExpectedCodeOnLaterPage',
                [System.Management.Automation.ErrorCategory]::OperationStopped,
                $NextUri)
        }
        foreach ($Item in @($Page.value)) { if ($null -ne $Item) { $AllValues.Add($Item) } }
        $NextUri = [string]$Page['@odata.nextLink']
    }
    # NOTE: deliberately no page-count cap or loop detection here. A hard cap risks silently
    # truncating a legitimate large enumeration, which is the exact defect class this switch exists
    # to fix. Do not add one without a design discussion.
    return @{ value = $AllValues.ToArray() }
}
