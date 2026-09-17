function Invoke-OERArmRequest {
    <#
    .SYNOPSIS
    Sends Azure Resource Manager requests directly with the cached bearer token, adding 401 re-auth
    retry, paging, and consistent error conversion for all ARM calls in Omnicit.EntraRBAC.

    .DESCRIPTION
    The single ARM call site of the module: nothing else issues ARM requests. The caller supplies the
    ARM path INCLUDING the pinned api-version query parameter; the wrapper prepends the ARM host
    (taken from $script:_OERAuthState.ArmResourceUrl, default https://management.azure.com) and sends
    the request with Invoke-WebRequest, attaching the cached ARM token from $script:_OERAuthState as
    an Authorization: Bearer header. The module deliberately does NOT use Connect-AzAccount /
    Invoke-AzRestMethod: Az.Accounts cannot reliably reuse an externally acquired (AzAuth) access
    token, so the bearer token is sent directly.

    Invoke-WebRequest is called with -SkipHttpErrorCheck so HTTP errors do not throw. Each response is
    normalized to a { StatusCode; Content; Headers } object before the status logic runs; the header
    collection stays inside this wrapper and only its Retry-After entry is ever read. The wrapper
    returns the parsed JSON content for 2xx responses ($null when the body is empty, e.g. 204);
    on 401 for interactive-class sessions calls Initialize-OERAuth -IncludeARM -ForceRefresh and
    retries exactly once (app-only sessions get a clear AppOnlyTokenRefreshUnsatisfiable error
    because credential material is never cached); throws the Convert-ArmHttpException ErrorRecord
    for any other non-2xx status. The same detect/refresh/retry-once logic covers every page fetch
    under -All, not just the first request, but the refresh budget is shared across the whole call:
    a token that expires mid-pagination gets exactly one forced refresh for the entire walk, not
    one per page. With -All, GET results are aggregated across pages following either the nextLink
    or the @nextLink property (management group lists use @nextLink); absolute next-page URLs are
    converted back to paths via Uri.PathAndQuery.

    A 429, and a 503 that carries a Retry-After header, are retried with a bounded backoff: the
    Retry-After value is honoured in either RFC 9110 form (delta-seconds or an HTTP-date), with an
    exponential fallback when the header is absent or unparseable, each single wait clamped to
    1..120 seconds. Two nested bounds hold, named and sized identically to Invoke-OERGraphRequest's:
    a 300-second wait budget per REQUEST (per PAGE under -All) and a 900-second DEADLINE for the
    whole call, which counts time spent in the requests themselves, plus a hard cap of 10 throttle
    retries per request as a runaway guard. Both bounds are enforced at the decision to WAIT and
    never by stopping a paging loop part-way, so a throttled enumeration fails cleanly instead of
    returning a partial collection as though it were complete. One Write-Verbose line is emitted per
    retry, naming the delay, the attempt number and whether the value came from the server or from
    the exponential fallback. The backoff wraps the 401 refresh rather than nesting inside it, so a
    throttled response can never consume the single per-call refresh budget and the two retry paths
    cannot compound.

    .PARAMETER Method
    HTTP method for the ARM request. Defaults to GET.

    .PARAMETER Path
    ARM path including the api-version query parameter, e.g. '/subscriptions?api-version=2022-12-01'.
    Never includes the hostname.

    .PARAMETER Body
    Optional request body hashtable, serialized with ConvertTo-Json -Depth 100 into the request body
    with content type application/json.

    .PARAMETER All
    Follow nextLink/@nextLink paging on GET list responses and return a single object whose value
    property contains all aggregated items.

    .EXAMPLE
    $Subs = (Invoke-OERArmRequest -Path '/subscriptions?api-version=2022-12-01' -All).value
    Lists all subscriptions across pages.

    .EXAMPLE
    Invoke-OERArmRequest -Method PUT -Path "$Scope/providers/Microsoft.Authorization/roleAssignments/$Name`?api-version=2022-04-01" -Body $Body
    Creates a role assignment at the given scope.
    #>
    [OutputType([object])]
    param(
        [string]$Method = 'GET',

        [Parameter(Mandatory)]
        [string]$Path,

        [hashtable]$Body,

        [switch]$All
    )

    # Suppress the Invoke-WebRequest progress bar for the lifetime of this call.
    $ProgressPreference = 'SilentlyContinue'

    # ARM host: from the cached resource url (so sovereign clouds work once that is configurable),
    # defaulting to public-cloud ARM.
    $ArmBaseUrl = if ($script:_OERAuthState -and $script:_OERAuthState.ArmResourceUrl) {
        ([string]$script:_OERAuthState.ArmResourceUrl).TrimEnd('/')
    } else {
        'https://management.azure.com'
    }

    function Invoke-ArmCall ([string]$CallPath, [string]$CallMethod, [hashtable]$CallBody, [string]$BaseUrl) {
        # SECURITY: method and path only. Never the Authorization header and never the body, which can
        # carry principal ids and role definition ids.
        Write-Verbose "[Invoke-OERArmRequest] $CallMethod $CallPath"

        # Materialize the bearer token only at the request boundary; clear it in the finally block.
        $Plain = [System.Net.NetworkCredential]::new('', $script:_OERAuthState.ArmToken).Password
        $InvokeParams = @{
            Method             = $CallMethod
            Uri                = "$BaseUrl$CallPath"
            Headers            = @{ Authorization = "Bearer $Plain" }
            SkipHttpErrorCheck = $true
            ErrorAction        = 'Stop'
            Verbose            = $false
        }
        if ($CallBody) {
            $InvokeParams.Body        = ($CallBody | ConvertTo-Json -Depth 100)
            $InvokeParams.ContentType = 'application/json'
        }
        try {
            $Raw = Invoke-WebRequest @InvokeParams
        } catch {
            # Security hygiene: the failed request (carrying the Authorization: Bearer header) lives in
            # $Error -- remove it FIRST, before anything else, uniformly with the Graph wrapper.
            Remove-OERErrorRecord -Record $PSItem
            throw [System.Management.Automation.ErrorRecord]::new(
                [System.Exception]::new("Azure Resource Manager request failed before a response was received: $($PSItem.Exception.Message)"),
                'ArmTransportError',
                [System.Management.Automation.ErrorCategory]::ConnectionError,
                $CallPath)
        } finally {
            $Plain = $null
        }
        # Normalize to a { StatusCode; Content; Headers } shape for the status logic, the throttle
        # backoff and Convert-ArmHttpException.
        #
        # HEADERS ARE PART OF THE SHAPE, and they were not always. Dropping them here is exactly why
        # this wrapper had no throttle handling at all (issue #57): whatever Retry-After ARM sent was
        # destroyed before any status logic could read it, so a 429 fell straight through to
        # Convert-ArmHttpException as a plain failure. Unlike Graph -- where Kiota's RetryHandler
        # swallows the 429 and re-raises it as an AggregateException with no .Response -- ARM's 429
        # arrives here as an ordinary response object with a real status code and real headers.
        # Nothing is swallowed on this transport; the headers only had to survive this line.
        #
        # In production $Raw.Headers is a Dictionary[string, IEnumerable[string]] (the declared
        # property type of Microsoft.PowerShell.Commands.WebResponseObject.Headers); under test it is
        # whatever the Invoke-WebRequest mock returned, usually a hashtable, and $null when the mock
        # supplies none. Get-ArmRetryAfterHeaderValue tolerates all three.
        #
        # SECURITY: this collection stays INSIDE the wrapper. It is never returned to a caller,
        # written to any stream, put into an error message, or logged. Only the single Retry-After
        # entry is ever read out of it, and only by Get-ArmRetryAfterHeaderValue. ARM response
        # headers carry correlation ids (x-ms-request-id, x-ms-correlation-request-id) and quota
        # telemetry, and a response echoing a request header would carry authentication material.
        [PSCustomObject]@{
            StatusCode = [int]$Raw.StatusCode
            Content    = [string]$Raw.Content
            Headers    = $Raw.Headers
        }
    }

    # -- Helper: turn one raw Retry-After header VALUE into whole seconds --
    # SINGLE OWNER of raw Retry-After parsing on the ARM side. RFC 9110 allows two forms and both are
    # handled: delta-seconds ("60") and an HTTP-date ("Wed, 21 Oct 2015 07:28:00 GMT"). The date form
    # is rare against ARM but legal, and reading it as zero would retry IMMEDIATELY against an
    # endpoint that just asked for a pause -- the worst possible response to a throttle. Returns
    # $null when the value is absent or is neither form, never a guess; the caller then falls back to
    # exponential backoff. A date already in the past yields a negative number here and is clamped by
    # the caller.
    function ConvertFrom-ArmRetryAfterHeader ([string]$RawValue) {
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

    # -- Helper: pull Retry-After out of an ARM response's header collection --
    # SINGLE OWNER of that read on the ARM side. Do not add a second reader.
    #
    # THE SHAPE. Invoke-WebRequest's response exposes .Headers as a
    # Dictionary[string, IEnumerable[string]] -- the declared property type of
    # Microsoft.PowerShell.Commands.WebResponseObject.Headers. PowerShell's foreach treats a
    # dictionary as ONE item, so it is walked by .Keys plus the indexer, never element-by-element.
    # The unit suite's Invoke-WebRequest mocks hand back a plain hashtable, which exposes the same
    # two members, so one reader serves both and no test-only path exists.
    #
    # Header names are compared with PowerShell's case-insensitive string comparison rather than by
    # an indexer lookup on the literal name: HTTP header names are case-insensitive and nothing in
    # the contract guarantees the dictionary's comparer is. The loop writes that comparison as -ne
    # plus continue rather than -eq plus a nested block -- same semantics, one less level of
    # indentation around the return.
    #
    # NEVER THROWS. This runs on the failure path, where an escaping exception would REPLACE the ARM
    # error the caller needs to see.
    #
    # SECURITY: only the single Retry-After entry is ever returned. The collection itself is never
    # returned, written to any stream, or logged.
    function Get-ArmRetryAfterHeaderValue ($HeaderCollection) {
        if ($null -eq $HeaderCollection) { return $null }
        try {
            $KeysMember = $HeaderCollection.PSObject.Properties['Keys']
            if ($null -eq $KeysMember) { return $null }
            foreach ($Key in @($KeysMember.Value)) {
                if ([string]$Key -ne 'Retry-After') { continue }
                return [string](@($HeaderCollection[$Key]) | Select-Object -First 1)
            }
        } catch {
            Remove-OERErrorRecord -Record $PSItem
        }
        return $null
    }

    # -- Helper: how long does ARM want us to wait before retrying? --
    # Returns $null when the response is not a retryable throttle, otherwise
    # @{ Seconds = <int>; Source = 'server-directed' | 'exponential fallback' }. The Source is what
    # the verbose line reports, so an operator can tell at a glance whether the wait is ARM's own
    # instruction or this module guessing -- the diagnostic whose ABSENCE is what exposed the Graph
    # bug in PR #77.
    #
    # WHY THIS IS A PLAIN STATUS TEST AND THE GRAPH SIDE'S IS NOT. Invoke-WebRequest is called with
    # -SkipHttpErrorCheck, so a 429 arrives as an ordinary response object with a real status code
    # and real headers: nothing is swallowed and nothing has to be dug out of an exception chain. The
    # Graph wrapper cannot do this -- Kiota's RetryHandler consumes the 429 and re-raises it as an
    # AggregateException wrapping an ApiException with no .Response, so its equivalent helper has to
    # walk the exception chain and fall back to the converted error code. That difference in ERROR
    # SHAPE is exactly why the two transports mirror each other's CONTRACT rather than share code:
    # a helper abstract enough to cover both would fit neither. Keep the two in step deliberately.
    #
    # -as [int], never a cast: a StatusCode that is not numeric would make a cast THROW from inside
    # the failure path and replace the real ARM error. -as yields $null and the caller moves on.
    function Get-ArmThrottleDelay ($CallResult, [int]$Attempt) {
        $Status = $CallResult.StatusCode -as [int]
        if ($null -eq $Status) { return $null }
        if ($Status -ne 429 -and $Status -ne 503) { return $null }

        $HeaderSeconds = ConvertFrom-ArmRetryAfterHeader (Get-ArmRetryAfterHeaderValue $CallResult.Headers)

        [string]$Source = 'server-directed'
        if ($null -ne $HeaderSeconds) {
            $Seconds = $HeaderSeconds
        } elseif ($Status -eq 429) {
            # No usable header: exponential fallback, per Microsoft Learn's throttling guidance.
            $Seconds = [Math]::Pow(2, $Attempt)
            $Source = 'exponential fallback'
        } else {
            # A 503 with no Retry-After is not a throttle signal. It is ARM saying it is unwell, and
            # retrying it blind turns a transient outage into a hammering. Only a 503 that NAMES a
            # wait is retried -- same rule as the Graph side.
            return $null
        }

        # Clamp. The lower bound is ONE second, not zero: the loop is bounded by a wait BUDGET rather
        # than a retry count alone, so a zero-second wait would let a server answering "Retry-After: 0"
        # spin without ever spending budget. The upper bound of 120 s guards a hostile or absurd
        # header: the budget bounds the TOTAL wait, this bounds any SINGLE unresponsive interval.
        if ($Seconds -lt 1) { $Seconds = 1 }
        if ($Seconds -gt 120) { $Seconds = 120 }
        return @{ Seconds = [int]$Seconds; Source = $Source }
    }

    # -- Helper: how much of the per-CALL budget has this Invoke-OERArmRequest call already used? --
    # Whole seconds, deliberately the LARGER of two measures:
    #   1. Real wall-clock time since the call started. This is the honest measure and the one that
    #      binds in production: it counts time spent IN the requests as well as time spent waiting,
    #      so a call cannot creep past its ceiling through slow responses rather than sleeps.
    #   2. The seconds this call has asked Start-Sleep to wait. In production this is always the
    #      SMALLER of the two, since every sleep is also wall-clock time, so it never loosens the real
    #      bound. It exists so the bound is deterministic under test: the unit suite mocks
    #      Start-Sleep, which pins measure 1 near zero, and a bound no test can drive is a bound no
    #      test can prove.
    function Get-ArmCallElapsed ([hashtable]$CallBudget) {
        if (-not $CallBudget) { return 0 }
        $WallClockSecond = ([DateTime]::UtcNow - $CallBudget.StartUtc).TotalSeconds
        return [int][Math]::Floor([Math]::Max($WallClockSecond, [double]$CallBudget.WaitSpent))
    }

    # -- 401: token rejected/expired -> force refresh and retry once --
    # One forced refresh serves the WHOLE call, pages included. Per-page budgets would turn a long
    # -All walk against a genuinely broken token into a refresh storm.
    $RefreshBudget = [ref]$false
    function Invoke-ArmCallWithRefresh ([string]$CallPath, [string]$CallMethod, [hashtable]$CallBody, [string]$BaseUrl, [ref]$RefreshBudget) {
        $CallResult = Invoke-ArmCall -CallPath $CallPath -CallMethod $CallMethod -CallBody $CallBody -BaseUrl $BaseUrl
        if ([int]$CallResult.StatusCode -ne 401 -or -not $script:_OERAuthState -or $RefreshBudget.Value) {
            return $CallResult
        }
        if ($script:_OERAuthState.AuthMethod -in 'ClientSecret', 'ClientCertificate') {
            throw [System.Management.Automation.ErrorRecord]::new(
                [System.Exception]::new(
                    "Azure Resource Manager rejected the access token (status=401) for an app-only " +
                    "($($script:_OERAuthState.AuthMethod)) session. Re-authenticate with Connect-OER using the " +
                    "client secret or certificate to acquire a fresh token."),
                'AppOnlyTokenRefreshUnsatisfiable',
                [System.Management.Automation.ErrorCategory]::AuthenticationError,
                $CallPath)
        }
        Write-Verbose "[Invoke-OERArmRequest] ARM token rejected (status=401). Forcing re-authentication and retrying once..."
        # Forward the cached ClientId so the SAME principal is re-acquired. Without it a user-assigned
        # managed-identity session force-refreshes as the system-assigned identity (a different
        # principal), so the retried call would silently run as the wrong identity or fail outright.
        $RefreshParams = @{
            TenantId     = $script:_OERAuthState.TenantId
            AuthMethod   = $script:_OERAuthState.AuthMethod
            IncludeARM   = $true
            ForceRefresh = $true
        }
        if ($script:_OERAuthState.ClientId) { $RefreshParams.ClientId = $script:_OERAuthState.ClientId }
        Initialize-OERAuth @RefreshParams
        $RefreshBudget.Value = $true
        Invoke-ArmCall -CallPath $CallPath -CallMethod $CallMethod -CallBody $CallBody -BaseUrl $BaseUrl
    }

    # -- Throttle backoff: bounded retry around ONE request, pages included --
    # THE LOOP SITS OUTSIDE THE 401 REFRESH, and that ordering is the design.
    #   * A 429 or 503 is never a 401, so Invoke-ArmCallWithRefresh hands it straight back and the
    #     refresh branch is not entered at all. A throttled response therefore CANNOT spend the
    #     refresh budget -- structurally, not by a check that could rot.
    #   * $RefreshBudget is one [ref] shared by the whole call, so however many times this loop
    #     re-enters, at most one forced refresh happens for the entire call, pages included. The two
    #     retry paths cannot multiply: the throttle side is bounded by the wait budget and the hard
    #     cap, the refresh side by a budget of one.
    #
    # THE NUMBERS mirror Invoke-OERGraphRequest's, name for name and meaning for meaning, so an
    # operator debugging one transport recognises the other (internal constants on purpose -- no
    # public parameter):
    #   ThrottleWaitBudgetSeconds = 300, per REQUEST (per PAGE under -All). Five minutes absorbs a
    #     server-directed "Retry-After: 60" five times over.
    #   CallDeadlineSeconds = 900, per CALL, however many pages that call fetches. It is a DEADLINE,
    #     not a wait allowance: TIME SPENT IN THE REQUESTS THEMSELVES COUNTS TOWARD IT (see
    #     Get-ArmCallElapsed), so a call cannot creep past its ceiling through slow responses rather
    #     than sleeps. Size it as "how long may this command keep BACKING OFF", NOT as "how long may
    #     this whole command run" -- the second overstates what this number bounds, and this comment
    #     used to say it. The deadline is only ever CONSULTED at a decision to WAIT, so it caps a
    #     THROTTLED call and nothing else: an -All walk that is never throttled follows nextLink for
    #     as long as ARM keeps handing out pages and never reads this number at all. Bounding THAT is
    #     a separate, pre-existing gap, deliberately not closed here -- closing it would mean ending
    #     a paging loop mid-enumeration, which the paragraph below rules out for a stronger reason.
    #     What it DOES bound has a deliberate consequence worth knowing: a long, legitimately slow
    #     -All enumeration that has already run past 900 s will refuse ANY further throttle backoff,
    #     turning a recoverable 429 on its last pages into a hard failure. Elapsed REQUEST time
    #     counts, so a slow-but-healthy walk can spend the whole budget without ever having waited.
    #     WHICH walk can reach that is worth being precise about, since the obvious guess is wrong:
    #     $CallBudget is created once per Invoke-OERArmRequest call and covers that call's own pages
    #     only, so it is a single deeply-paged read -- Get-OERResource over a large subscription --
    #     that is exposed. Export-OERInventory issues one call per scope and each gets a FRESH 900 s,
    #     so a long inventory run is NOT the shape at risk however long it takes in total. That is
    #     the intended trade -- an unbounded backoff is worse -- but it is why the name says deadline.
    #     Three times the per-page budget: enough that three fully-throttled pages can still be
    #     ridden out, which is the realistic recoverable case, but a ceiling the operator can
    #     predict from the cmdlet alone rather than from a page count they cannot see. Fifteen
    #     minutes is also about the longest an interactive operator will wait before concluding a
    #     session is hung, and past that a clean error beats a longer wait for the same
    #     all-or-nothing failure.
    #   ThrottleRetryHardCap = 10, per request. A runaway guard, not a primary bound. It binds only
    #     when a server answers with a very small Retry-After over and over -- the one shape where a
    #     budget alone would allow hundreds of requests against an already throttled endpoint. That
    #     is not hypothetical: with the per-call bound neutralized in a Graph test, a paged read
    #     issued 1,250 requests instead of 11.
    #
    # BOTH BOUNDS ARE ENFORCED AT THE DECISION TO WAIT, never by stopping the paging loop between
    # pages. Truncating an enumeration on a deadline returns a partial collection as though it were
    # complete, and the apply engine reads a short list as drift and writes on it. When the budget is
    # gone this returns the throttled response and lets the caller's existing non-2xx check convert
    # and THROW it. The cost is deliberate: a call may overrun the deadline by the last request's own
    # duration.
    function Invoke-ArmCallWithBackoff ([string]$CallPath, [string]$CallMethod, [hashtable]$CallBody, [string]$BaseUrl, [ref]$RefreshBudget, [hashtable]$CallBudget) {
        [int]$ThrottleWaitBudgetSeconds = 300
        [int]$CallDeadlineSeconds = 900
        [int]$ThrottleRetryHardCap = 10
        [int]$ThrottleWaitSpent = 0
        [int]$ThrottleAttempt = 0

        while ($true) {
            $CallResult = Invoke-ArmCallWithRefresh -CallPath $CallPath -CallMethod $CallMethod `
                -CallBody $CallBody -BaseUrl $BaseUrl -RefreshBudget $RefreshBudget

            $Delay = Get-ArmThrottleDelay $CallResult $ThrottleAttempt
            if ($null -eq $Delay) { return $CallResult }

            [int]$RequestRemaining = $ThrottleWaitBudgetSeconds - $ThrottleWaitSpent
            [int]$CallRemaining = $CallDeadlineSeconds - (Get-ArmCallElapsed -CallBudget $CallBudget)

            # The per-CALL bound is checked FIRST so that when both are gone the operator is told
            # about the one that actually ends the command rather than the one that ends this page.
            if ($Delay.Seconds -gt $CallRemaining) {
                Write-Verbose ("[Invoke-OERArmRequest] Throttled. The next wait needs $($Delay.Seconds) s " +
                    "($($Delay.Source)) but only $CallRemaining s of the $CallDeadlineSeconds s per-CALL budget remain. Giving up.")
                return $CallResult
            }
            if ($Delay.Seconds -gt $RequestRemaining) {
                # Honouring a wait this module cannot afford would mean retrying EARLY, which just
                # earns another throttle. Give up cleanly and let the caller see the ARM error.
                Write-Verbose ("[Invoke-OERArmRequest] Throttled. The next wait needs $($Delay.Seconds) s " +
                    "($($Delay.Source)) but only $RequestRemaining s of the $ThrottleWaitBudgetSeconds s per-REQUEST budget remain. Giving up.")
                return $CallResult
            }
            if ($ThrottleAttempt -ge $ThrottleRetryHardCap) {
                Write-Verbose ("[Invoke-OERArmRequest] Throttled. Reached the hard cap of $ThrottleRetryHardCap " +
                    "throttle retries with $RequestRemaining s of per-REQUEST budget still unspent. Giving up.")
                return $CallResult
            }

            $ThrottleAttempt++
            $ThrottleWaitSpent += $Delay.Seconds
            if ($CallBudget) { $CallBudget.WaitSpent += $Delay.Seconds }
            $RequestRemaining = $ThrottleWaitBudgetSeconds - $ThrottleWaitSpent
            $CallRemaining = $CallDeadlineSeconds - (Get-ArmCallElapsed -CallBudget $CallBudget)
            # SECURITY: the status, the delay and its provenance only. The header COLLECTION this
            # value came from is never written to any stream -- see Get-ArmRetryAfterHeaderValue.
            Write-Verbose ("[Invoke-OERArmRequest] Throttled (status=$([int]$CallResult.StatusCode)). " +
                "Waiting $($Delay.Seconds) s ($($Delay.Source)) before retry $ThrottleAttempt; " +
                "$RequestRemaining s of per-REQUEST and $CallRemaining s of per-CALL budget remain.")
            Start-Sleep -Seconds $Delay.Seconds
        }
    }

    # -- Per-CALL deadline state, shared by every page of a -All enumeration --
    # A hashtable rather than two scalars so the nested function mutates THIS state by reference; a
    # value type would give each page its own copy and the per-call bound would never bind. The
    # single-page path gets one too, so both paths run identical code.
    #
    # THE PER-CALL BOUND CAN STILL BIND ON THE SINGLE-PAGE PATH. This comment used to assert the
    # opposite -- that 900 s "cannot be reached inside a 300 s per-request budget" -- and that is
    # false. Get-ArmCallElapsed returns the LARGER of wall-clock time and seconds slept, and
    # wall-clock counts time spent IN the request, so one slow or hung ARM request can carry a single
    # call past 900 s with WaitSpent still at 0. The per-call check is then the one that fires, which
    # is the intended behaviour: the deadline exists precisely so slow responses cannot creep past
    # the ceiling that sleeps alone would respect.
    $CallBudget = @{ StartUtc = [DateTime]::UtcNow; WaitSpent = 0 }

    $Response = Invoke-ArmCallWithBackoff -CallPath $Path -CallMethod $Method -CallBody $Body `
        -BaseUrl $ArmBaseUrl -RefreshBudget $RefreshBudget -CallBudget $CallBudget

    if ([int]$Response.StatusCode -lt 200 -or [int]$Response.StatusCode -gt 299) {
        throw (Convert-ArmHttpException -Response $Response -Path $Path)
    }

    if (-not $Response.Content) { return $null }
    $Parsed = $Response.Content | ConvertFrom-Json -ErrorAction Stop

    if (-not $All) { return $Parsed }

    # -- Paging: aggregate value arrays across nextLink / @nextLink --
    $AllValues = [System.Collections.Generic.List[object]]::new()
    if ($null -ne $Parsed.value) { foreach ($Item in $Parsed.value) { $AllValues.Add($Item) } }
    $NextLink = if ($Parsed.PSObject.Properties['nextLink']) { $Parsed.nextLink }
    elseif ($Parsed.PSObject.Properties['@nextLink']) { $Parsed.'@nextLink' }
    else { $null }

    while ($NextLink) {
        # nextLink is an absolute URL; convert it back to a path so sovereign-cloud hosts keep working.
        $NextPath = ([System.Uri]$NextLink).PathAndQuery
        # Each page gets its own per-REQUEST wait budget and shares the per-CALL deadline. A long
        # inventory walk is the most likely place to be throttled in the first place, so the paging
        # path must back off exactly like the single-request path -- it is not the exception.
        $PageResponse = Invoke-ArmCallWithBackoff -CallPath $NextPath -CallMethod $Method -CallBody $Body `
            -BaseUrl $ArmBaseUrl -RefreshBudget $RefreshBudget -CallBudget $CallBudget
        if ([int]$PageResponse.StatusCode -lt 200 -or [int]$PageResponse.StatusCode -gt 299) {
            throw (Convert-ArmHttpException -Response $PageResponse -Path $NextPath)
        }
        $Page = $PageResponse.Content | ConvertFrom-Json -ErrorAction Stop
        if ($null -ne $Page.value) { foreach ($Item in $Page.value) { $AllValues.Add($Item) } }
        $NextLink = if ($Page.PSObject.Properties['nextLink']) { $Page.nextLink }
        elseif ($Page.PSObject.Properties['@nextLink']) { $Page.'@nextLink' }
        else { $null }
    }

    return [PSCustomObject]@{ value = $AllValues.ToArray() }
}
