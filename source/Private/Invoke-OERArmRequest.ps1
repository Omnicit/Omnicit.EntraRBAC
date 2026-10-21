function Invoke-OERArmRequest {
    <#
    .SYNOPSIS
    Sends Azure Resource Manager requests directly with the cached bearer token, adding 401 re-auth
    retry, paging, and consistent error conversion for all ARM calls in Omnicit.EntraRBAC.

    .DESCRIPTION
    The single ARM call site of the module: nothing else issues ARM requests. The caller supplies the
    ARM path INCLUDING the pinned api-version query parameter; the wrapper prepends the ARM host and
    sends the request with Invoke-WebRequest, attaching the cached ARM token from
    $script:_OERAuthState as an Authorization: Bearer header. The host is, in this order:
    $script:_OERAuthState.ArmResourceUrl when the session has one; otherwise, for a session that has
    none, the ARM host of the session's cloud (the state's Environment, Global when it names none),
    read from Get-OERCloudEndpoint; and https://management.azure.com when there is no session state
    at all. The module deliberately does NOT use Connect-AzAccount / Invoke-AzRestMethod:
    Az.Accounts cannot reliably reuse an externally acquired (AzAuth) access token, so the bearer
    token is sent directly.

    A request is never sent without an ARM token. When the session holds none -- no state, no
    ArmToken, or an empty or blank one -- the request is refused after the sign-in latch and
    supersession gates and before anything is sent, with ArmTokenAcquisitionFailed. Run
    Connect-OER -IncludeARM to acquire the token.

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
    one per page. With -All, list results are aggregated across pages following either the nextLink
    or the @nextLink property (management group lists use @nextLink); absolute next-page URLs are
    converted back to paths via Uri.PathAndQuery. Every page is requested with the call's own
    method and body, so a POST that returns a list, such as Entities - List (getEntities), is paged
    the same way as a GET list.

    A -All walk that cannot be completed FAILS; it never returns the pages read so far as though they
    were the whole collection. A page after the first with an empty body, a JSON null body or no value
    member, a next link that is not an absolute http or https URI, a next link naming a path already
    requested in this walk, and a walk past the page limit (Get-OERPageWalkLimit) are all refused with
    ArmPagingIncomplete, and no page is ever requested twice. A page after the first whose value is an
    empty array is a normal page. A 2xx body that cannot be read as JSON, on a single request or on any
    page, is refused with ArmResponseUnreadable; the message names the request path and never the
    body. Under -All every failure of a page (a refusal above, a non-2xx answer, a transport failure)
    carries PartialValue (the items aggregated before it, an empty array for the first page), NextLink
    (the link, or the -Path for the first page; for ArmResponseUnreadable on a later page, the path of
    the failing page, not the absolute link) and PageNumber (1-based) as note properties on the
    thrown error's EXCEPTION, never on the ErrorRecord, the way Invoke-OERGraphRequest does. A single
    request carries none of them. A single request whose 2xx body is empty (204) still returns $null,
    and so does a FIRST page of a -All walk with an empty body. Get-OERPageWalkLimit owns the page
    limit (100000 pages).

    Under -ErrorAction SilentlyContinue, with no try up the call stack, a failed call returns
    NOTHING (no partial list, and not $null as an answer) and the record is kept in $Error and in the
    caller's -ErrorVariable: a caller that asks for silence must read it and never read "no output" as
    an empty collection. Under -ErrorAction Ignore the call also returns nothing and leaves no record
    at all.

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
    Follow nextLink/@nextLink paging on list responses and return a single object whose value
    property contains all aggregated items. Every page is requested with the call's own -Method and
    -Body, so a POST list (Entities - List) is paged as well as a GET list. A walk that cannot
    complete (a later page that is empty, JSON null or without a value member, a repeated path, a next
    link that is not an absolute URI, a walk past the page limit) fails with ArmPagingIncomplete, and
    an unreadable 2xx body with ArmResponseUnreadable; neither returns a partial list.

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

    # ARM host. The session's own resource url when it has one. A state without one takes the host of
    # the session's cloud (BL-65), never the public cloud for a sovereign session; defence in depth,
    # since no state the module builds holds a token without a url. With no state at all the
    # documented public-cloud fallback stays, so the request is refused for its missing token below
    # rather than failing on a null host (docs/development/rationale.md#arm-transport). The else
    # literal is gate 7's exemption by shape.
    $ArmBaseUrl = if ($script:_OERAuthState -and $script:_OERAuthState.ArmResourceUrl) {
        ([string]$script:_OERAuthState.ArmResourceUrl).TrimEnd('/')
    } elseif ($script:_OERAuthState) {
        $SessionCloud = if ($script:_OERAuthState.Environment) { [string]$script:_OERAuthState.Environment } else { 'Global' }
        ([string](Get-OERCloudEndpoint -Environment $SessionCloud).ArmResource).TrimEnd('/')
    } else {
        'https://management.azure.com'
    }

    function Invoke-ArmCall ([string]$CallPath, [string]$CallMethod, [hashtable]$CallBody, [string]$BaseUrl) {
        # SECURITY: method and path only. Never the Authorization header and never the body, which can
        # carry principal ids and role definition ids.
        Write-Verbose "[Invoke-OERArmRequest] $CallMethod $CallPath"

        # SEC (A19): never an ARM request for a command whose sign-in was refused. Initialize-OERAuth
        # latches the command that called it at entry and releases it only when the sign-in succeeds.
        # Its refusal does not stop that command: measured 2026-10-05, a caller carries on past a
        # nested function's terminating error unless a try or trap is active up the call stack, and every
        # public cmdlet but one leaves its Initialize-OERAuth call unwrapped (Export-OERInventory wraps
        # its call in a try since Sprint 11 step 10, BL-101, catches the refusal and writes nothing) -- so
        # the command would send the ARM token an earlier sign-in left, for another tenant when it named
        # -TenantId. A cmdlet that command calls, or that runs inside its output, is refused at its own
        # sign-in (BL-74); a downstream command whose begin block signed in while the refused command
        # was on no call stack -- every begin block runs before any process block -- is not, and runs
        # inside the refused command's output with its own latch released. So Get-OERSignInRefusal
        # looks for a latched command anywhere on the call stack: that pipeline case, and defence in
        # depth for a nested call.
        #
        # Here, once, before the bearer token is materialized and before Invoke-WebRequest: every
        # request of this wrapper passes through this function -- the first, each throttled retry, the
        # 401 retry (a refresh whose sign-in is refused latches its caller, Invoke-ArmCallWithRefresh)
        # and every page. The return is load-bearing, not tidiness: measured 2026-10-05, under
        # -ErrorAction SilentlyContinue or Ignore, with no try up the call stack, a function carries on
        # past its OWN throw to its next statement -- which here would build the bearer and send it.
        $SignInRefusal = Get-OERSignInRefusal
        if ($null -ne $SignInRefusal) {
            throw (New-OERSignInRefusedError -Command $SignInRefusal)
            return
        }

        # SEC (A20): never an ARM request while a command runs whose sign-in another command has since
        # replaced. In a pipeline every begin block runs first, and almost every public cmdlet signs in
        # in its begin block, so the upstream command's process block acts under the state the
        # downstream command's sign-in switched to -- and would send the ARM token that sign-in cached,
        # for the downstream command's tenant (F-E). Both sign-ins succeed, so the latch gate above does
        # not see it. Initialize-OERAuth remembers which identity each command signed in as, and
        # Get-OERSignInSupersession compares every frame on the call stack with the state, not only the
        # nearest: a nested cmdlet signs in again without -TenantId, inherits the switched state and
        # remembers it, so its own frame matches while the outer command's does not. A command that
        # runs inside such a command's output -- the next command in its pipeline, or one in a
        # ForEach-Object over it -- has that command's frame on its call stack (measured), so its
        # requests are refused too. After the latch gate, so a command whose sign-in was refused is
        # still reported as SignInRefused, and here, for the same requests as that gate -- the 401
        # retry included, which reaches this gate when the refresh's sign-in changed the state's
        # identity -- before the bearer token is materialized. The return is load-bearing for the same
        # reason as the latch gate's: without it this function would carry on past its own throw to
        # build the bearer and send it.
        $SignInSupersession = Get-OERSignInSupersession
        if ($null -ne $SignInSupersession) {
            throw (New-OERSignInSupersededError -Command $SignInSupersession)
            return
        }

        # Materialize the bearer token only at the request boundary; clear it in the finally block.
        $Plain = [System.Net.NetworkCredential]::new('', $script:_OERAuthState.ArmToken).Password
        # SEC (BL-65, BL-96): never an ARM request without an ARM token. No state, no ArmToken and an
        # empty or blank SecureString all materialize to an empty string (measured), and the request
        # went out with "Bearer " -- to the public cloud when there was no state. Refused here, after
        # the last gate and before anything is sent, with the existing ArmTokenAcquisitionFailed (A8).
        # Read from $Plain, not from the state, so no second token read stands in this function.
        # The return is load-bearing, as after each gate above.
        if ([string]::IsNullOrWhiteSpace($Plain)) {
            $Plain = $null
            throw [System.Management.Automation.ErrorRecord]::new(
                [System.Exception]::new(("No Azure Resource Manager request was sent: the module's session holds no " +
                    'Azure Resource Manager token. Run Connect-OER -IncludeARM to acquire one -- for an app-only ' +
                    'session with its certificate or client secret -- and run the command again.')),
                'ArmTokenAcquisitionFailed',
                [System.Management.Automation.ErrorCategory]::AuthenticationError,
                $CallPath)
            return
        }
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
        $TransportFailed = $false
        try {
            $Raw = Invoke-WebRequest @InvokeParams
        } catch {
            # Security hygiene: the failed request (carrying the Authorization: Bearer header) lives in
            # $Error -- remove it FIRST, before anything else, uniformly with the Graph wrapper.
            Remove-OERErrorRecord -Record $PSItem
            # Read straight after this try statement; see the check there.
            $TransportFailed = $true
            throw [System.Management.Automation.ErrorRecord]::new(
                [System.Exception]::new("Azure Resource Manager request failed before a response was received: $($PSItem.Exception.Message)"),
                'ArmTransportError',
                [System.Management.Automation.ErrorCategory]::ConnectionError,
                $CallPath)
        } finally {
            $Plain = $null
        }
        # The throw above does not always end this function. Measured 2026-10-05 in PowerShell 7: under
        # -ErrorAction SilentlyContinue or Ignore, with no try up the call stack, a throw inside a CATCH
        # block resumes AFTER the whole try statement -- here, once the finally has run -- so a return
        # placed after that throw would never run. Carrying on built a status-0 response out of a
        # request that never got one, and the wrapper raised a second record for it (ArmError). No
        # object at all goes back instead; every caller above hands that on without sending anything,
        # and the top of the wrapper ends the call on it.
        if ($TransportFailed) { return }
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
    # -All walk against a genuinely broken token into a refresh storm. The refresh signs in again,
    # as in Invoke-OERGraphRequest: an interactive session opens the browser and a device code
    # session prints a new code; see about_Omnicit.EntraRBAC, LONG RUNS.
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
            # Load-bearing: under -ErrorAction SilentlyContinue or Ignore, with no try up the call
            # stack, this function carried on past its own throw to the forced refresh an app-only
            # session cannot satisfy, and sent the retry after it.
            return
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

    # -- Helper: the ONE record for a -All walk that cannot be completed (BL-71, P0 family) --
    # Mirror of Invoke-OERGraphRequest's Get-GraphPagingIncompleteRecord. Six causes, one record: a
    # later page with an empty body, a later page whose body is JSON null, a later page with no value
    # member, a next link that is not an absolute URI, a next link naming a path already requested in
    # this walk, and a walk past the page limit. The helper only BUILDS the record; each throw stands
    # in the loop with its own return (see the rule above the first-response checks). The facts ride
    # on the EXCEPTION, never on the ErrorRecord (F1, docs/development/rationale.md#graph-wrapper).
    function Get-ArmPagingIncompleteRecord ([string]$Cause, [int]$AtPage, [string]$AtLink, [object[]]$Aggregated) {
        $Count = @($Aggregated).Count
        $IncompleteException = [System.Exception]::new(
            ("Azure Resource Manager page $AtPage of this enumeration cannot be read as part of a complete walk: $Cause. " +
            "$Count item(s) had already been aggregated from earlier pages; the partial collection is " +
            "refused rather than returned as though it were complete."))
        $IncompleteException | Add-Member -NotePropertyName PartialValue -NotePropertyValue @($Aggregated) -Force
        $IncompleteException | Add-Member -NotePropertyName NextLink -NotePropertyValue $AtLink -Force
        $IncompleteException | Add-Member -NotePropertyName PageNumber -NotePropertyValue $AtPage -Force
        # SECURITY: page number and item COUNT only; the next link can carry a $skiptoken.
        Write-Verbose ("[Invoke-OERArmRequest] Page $AtPage cannot complete the walk ($Cause) with $Count " +
            "item(s) already aggregated from earlier pages. PartialValue, NextLink and PageNumber are " +
            "attached to the thrown error's Exception for a caller that opts in; the call still fails.")
        return [System.Management.Automation.ErrorRecord]::new(
            $IncompleteException,
            'ArmPagingIncomplete',
            [System.Management.Automation.ErrorCategory]::InvalidResult,
            $AtLink)
    }

    # -- Helper: the ONE record for a 2xx body that cannot be read as JSON (BL-73) --
    # The message names the request path and says the body was unreadable; it never carries the body
    # or ConvertFrom-Json's own message, which quotes a fragment of the text it could not parse. With
    # -WithFacts (a -All walk) the three facts ride on the exception, as for any failed page.
    function Get-ArmUnreadableBodyRecord ([string]$AtPath, [int]$AtPage, [object[]]$Aggregated, [switch]$WithFacts) {
        $UnreadableException = [System.Exception]::new(
            "The body of the 2xx answer from Azure Resource Manager to $AtPath could not be read as JSON.")
        if ($WithFacts) {
            $UnreadableException | Add-Member -NotePropertyName PartialValue -NotePropertyValue @($Aggregated) -Force
            $UnreadableException | Add-Member -NotePropertyName NextLink -NotePropertyValue $AtPath -Force
            $UnreadableException | Add-Member -NotePropertyName PageNumber -NotePropertyValue $AtPage -Force
        }
        return [System.Management.Automation.ErrorRecord]::new(
            $UnreadableException,
            'ArmResponseUnreadable',
            [System.Management.Automation.ErrorCategory]::InvalidData,
            $AtPath)
    }

    # -- Helper: attach the three failure facts to an exception (BL-24) --
    # F1, MEASURED (docs/development/rationale.md#graph-wrapper): a note property on an ErrorRecord does
    # not survive a throw, one on the EXCEPTION does. Used on the record a non-2xx page converts to and
    # in the catch of a page fetch.
    function Add-ArmPageFailureFact ([System.Exception]$FailedException, [object[]]$Aggregated, [string]$AtLink, [int]$AtPage) {
        $FailedException | Add-Member -NotePropertyName PartialValue -NotePropertyValue @($Aggregated) -Force
        $FailedException | Add-Member -NotePropertyName NextLink -NotePropertyValue $AtLink -Force
        $FailedException | Add-Member -NotePropertyName PageNumber -NotePropertyValue $AtPage -Force
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

    # The first request. Under -All it stands in a try, so a failure of it carries the three facts
    # too (PartialValue @(), NextLink the -Path, PageNumber 1), like any later page (BL-24). With a try
    # up the call stack a throw in a nested function is terminating even under -ErrorAction
    # SilentlyContinue, so after a refused sign-in the walk's 401 retry is not attempted and nothing is
    # sent after the refusal: the latch gate never has to refuse it. A SINGLE request stays outside the
    # try on purpose and is unchanged: without one the nested throw does not stop the caller, the 401
    # retry is still attempted and the latch gate refuses it. The catch scrubs first, like every catch
    # that can see a transport failure, and rethrows the record it caught.
    $FirstFailed = $false
    if ($All) {
        try {
            $Response = Invoke-ArmCallWithBackoff -CallPath $Path -CallMethod $Method -CallBody $Body `
                -BaseUrl $ArmBaseUrl -RefreshBudget $RefreshBudget -CallBudget $CallBudget
        } catch {
            Remove-OERErrorRecord -Record $PSItem
            # Read straight after this try statement; see the check there.
            $FirstFailed = $true
            Add-ArmPageFailureFact -FailedException $PSItem.Exception -Aggregated @() -AtLink $Path -AtPage 1
            throw
        }
    } else {
        $Response = Invoke-ArmCallWithBackoff -CallPath $Path -CallMethod $Method -CallBody $Body `
            -BaseUrl $ArmBaseUrl -RefreshBudget $RefreshBudget -CallBudget $CallBudget
    }

    # EVERY THROW IN THIS FUNCTION IS FOLLOWED BY A RETURN (one inside a catch, by a flag read straight
    # after its try), and none of them is tidiness. Measured 2026-10-05 in PowerShell 7: under
    # -ErrorAction SilentlyContinue or Ignore, with no try up the call stack, a function carries on
    # past its OWN throw to its next statement -- and so does every caller of a nested function that threw,
    # since a return there ends only that nested function. A throw inside a CATCH resumes after the
    # whole try statement, so the return that follows it is a flag set in the catch and read here.
    if ($FirstFailed) { return }
    #
    # No response object at all means a nested function already raised and returned: the latch gate,
    # the supersession gate, the missing-token refusal or the transport failure in Invoke-ArmCall, or
    # the app-only refusal in Invoke-ArmCallWithRefresh.
    # Its record is the call's answer. Converting the missing response would add a parameter-binding
    # record of its own, since Convert-ArmHttpException requires one.
    if ($null -eq $Response) { return }
    if ([int]$Response.StatusCode -lt 200 -or [int]$Response.StatusCode -gt 299) {
        $Err = Convert-ArmHttpException -Response $Response -Path $Path
        if ($All) { Add-ArmPageFailureFact -FailedException $Err.Exception -Aggregated @() -AtLink $Path -AtPage 1 }
        throw $Err
        # Carrying on parsed the error body and returned it as data.
        return
    }

    # An empty FIRST body is an empty answer (204), under -All and for a single request alike.
    if (-not $Response.Content) { return $null }
    # BL-73: a 2xx body that cannot be parsed is neither $null nor an empty collection. It is refused
    # as itself, on a single request and on page one of a walk alike.
    $ParseFailed = $false
    try {
        $Parsed = $Response.Content | ConvertFrom-Json -ErrorAction Stop
    } catch {
        Remove-OERErrorRecord -Record $PSItem
        $ParseFailed = $true
        throw (Get-ArmUnreadableBodyRecord -AtPath $Path -AtPage 1 -Aggregated @() -WithFacts:$All)
    }
    if ($ParseFailed) { return }

    if (-not $All) { return $Parsed }

    # -- Paging: aggregate value arrays across nextLink / @nextLink --
    $AllValues = [System.Collections.Generic.List[object]]::new()
    if ($null -ne $Parsed.value) { foreach ($Item in $Parsed.value) { $AllValues.Add($Item) } }
    $NextLink = if ($Parsed.PSObject.Properties['nextLink']) { $Parsed.nextLink }
    elseif ($Parsed.PSObject.Properties['@nextLink']) { $Parsed.'@nextLink' }
    else { $null }

    # A -ALL WALK THAT CANNOT BE COMPLETED FAILS; IT NEVER HANDS BACK WHAT IT HAS (BL-71, P0 family).
    # Mirror of Invoke-OERGraphRequest's loop. Read ONCE per call, before the loop: Get-OERPageWalkLimit
    # owns the number. $RequestedPaths holds every path this walk has requested, the first request's
    # -Path included. Ordinal: a skiptoken is case-sensitive.
    [int]$PageLimit = Get-OERPageWalkLimit
    $RequestedPaths = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
    $null = $RequestedPaths.Add($Path)
    [int]$PageNumber = 1

    while ($NextLink) {
        $PageNumber++
        # The bound fails the walk; it never truncates it. A legitimate enumeration is far below it.
        if ($PageNumber -gt $PageLimit) {
            throw (Get-ArmPagingIncompleteRecord -Cause "the walk reached its limit of $PageLimit page(s) and the page after it was not requested" `
                -AtPage $PageNumber -AtLink ([string]$NextLink) -Aggregated $AllValues.ToArray())
            # Outside any catch, a throw can be suppressed (-ErrorAction SilentlyContinue/Ignore with no
            # try up the stack) and the loop would carry on: return, never break.
            return
        }
        # nextLink is an absolute URL; convert it back to a path so sovereign-cloud hosts keep working.
        # One that is not absolute has no PathAndQuery to read. On Linux and macOS a rooted path such as
        # '/subscriptions?...' also parses as an absolute (file) URI, so the scheme must be http or https.
        $NextUri = $null
        if (-not [System.Uri]::TryCreate([string]$NextLink, [System.UriKind]::Absolute, [ref]$NextUri) -or
            $NextUri.Scheme -notin 'http', 'https') {
            throw (Get-ArmPagingIncompleteRecord -Cause 'its next link is not an absolute http or https URI, so no path could be requested from it' `
                -AtPage $PageNumber -AtLink ([string]$NextLink) -Aggregated $AllValues.ToArray())
            return
        }
        $NextPath = $NextUri.PathAndQuery
        # Never request the same page twice: a next link that names a path already requested would loop.
        if (-not $RequestedPaths.Add($NextPath)) {
            throw (Get-ArmPagingIncompleteRecord -Cause 'its next link repeats a page already requested in this walk, so it was not requested again' `
                -AtPage $PageNumber -AtLink ([string]$NextLink) -Aggregated $AllValues.ToArray())
            return
        }
        # Each page gets its own per-REQUEST wait budget and shares the per-CALL deadline. A long
        # inventory walk is the most likely place to be throttled in the first place, so the paging
        # path must back off exactly like the single-request path -- it is not the exception.
        $PageFailed = $false
        try {
            $PageResponse = Invoke-ArmCallWithBackoff -CallPath $NextPath -CallMethod $Method -CallBody $Body `
                -BaseUrl $ArmBaseUrl -RefreshBudget $RefreshBudget -CallBudget $CallBudget
        } catch {
            # Security: scrub first, in this separate catch clause (the gate counts it per catch).
            Remove-OERErrorRecord -Record $PSItem
            # Read straight after this try statement; see the check there.
            $PageFailed = $true
            # BL-24, F1 as in Invoke-OERGraphRequest: the facts go on the EXCEPTION, which survives a
            # throw; the call still fails. SECURITY: the next link can carry a skiptoken, so verbose
            # output names the page number and the item count only.
            Add-ArmPageFailureFact -FailedException $PSItem.Exception -Aggregated $AllValues.ToArray() -AtLink ([string]$NextLink) -AtPage $PageNumber
            Write-Verbose ("[Invoke-OERArmRequest] Page $PageNumber failed with $($AllValues.Count) item(s) " +
                "already aggregated from earlier pages. PartialValue, NextLink and PageNumber are attached " +
                "to the thrown error's Exception for a caller that opts in; the call still fails.")
            throw
        }
        # A throw in a catch resumes after the whole try statement: this is the return that ends the
        # walk. return, never break: break would hand back the pages so far as though they were the
        # whole collection.
        if ($PageFailed) { return }
        # The same two checks as for the first page above.
        if ($null -eq $PageResponse) { return }
        if ([int]$PageResponse.StatusCode -lt 200 -or [int]$PageResponse.StatusCode -gt 299) {
            $Err = Convert-ArmHttpException -Response $PageResponse -Path $NextPath
            Add-ArmPageFailureFact -FailedException $Err.Exception -Aggregated $AllValues.ToArray() -AtLink ([string]$NextLink) -AtPage $PageNumber
            throw $Err
            # Carrying on read the error body as a page with no next link, so the walk ended and
            # returned the pages before it as the whole collection.
            return
        }
        # A LATER page is not the first: page one carried a next link, so the answer to the request
        # that link names is "there is more". An empty body in reply is a read that did not complete,
        # and ending the walk there would hand back the pages before it as though they were the whole
        # collection (BL-71: an empty body left the previous page in $Page, and the walk requested
        # its next link again for ever).
        if (-not $PageResponse.Content) {
            throw (Get-ArmPagingIncompleteRecord -Cause 'it answered with an empty body although the page before it carried a next link' `
                -AtPage $PageNumber -AtLink ([string]$NextLink) -Aggregated $AllValues.ToArray())
            return
        }
        $ParseFailed = $false
        try {
            $Page = $PageResponse.Content | ConvertFrom-Json -ErrorAction Stop
        } catch {
            Remove-OERErrorRecord -Record $PSItem
            $ParseFailed = $true
            throw (Get-ArmUnreadableBodyRecord -AtPath $NextPath -AtPage $PageNumber -Aggregated $AllValues.ToArray() -WithFacts)
        }
        if ($ParseFailed) { return }
        # JSON null parses to nothing; a page with no value member is not a page of the collection (a
        # page whose value is an empty array IS one, and falls through).
        if ($null -eq $Page) {
            throw (Get-ArmPagingIncompleteRecord -Cause 'its body is JSON null' `
                -AtPage $PageNumber -AtLink ([string]$NextLink) -Aggregated $AllValues.ToArray())
            return
        }
        if ($null -eq $Page.PSObject.Properties['value']) {
            throw (Get-ArmPagingIncompleteRecord -Cause 'it has no value member' `
                -AtPage $PageNumber -AtLink ([string]$NextLink) -Aggregated $AllValues.ToArray())
            return
        }
        if ($null -ne $Page.value) { foreach ($Item in $Page.value) { $AllValues.Add($Item) } }
        $NextLink = if ($Page.PSObject.Properties['nextLink']) { $Page.nextLink }
        elseif ($Page.PSObject.Properties['@nextLink']) { $Page.'@nextLink' }
        else { $null }
    }

    # The walk is bounded, and the bound FAILS it rather than truncating it: the page limit above
    # (Get-OERPageWalkLimit) refuses the page after it with ArmPagingIncomplete, and a next link that
    # repeats a page already requested is refused the same way. A silent cap would hand back a prefix
    # as the whole collection, the defect class -All exists to prevent.
    return [PSCustomObject]@{ value = $AllValues.ToArray() }
}
