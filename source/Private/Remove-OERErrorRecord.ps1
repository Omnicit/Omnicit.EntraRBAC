function Remove-OERErrorRecord {
    <#
    .SYNOPSIS
    Strips the bearer token off a swallowed error record and removes the record from the caller's
    $global:Error list.

    .DESCRIPTION
    Does two things, in this order, and BOTH are load-bearing.

    1. SCRUB. The raw Graph/ARM SDK error record points, through .TargetObject and through the
    exception chain, at the very System.Net.Http.HttpRequestMessage the failing call built -- and
    that message carries "Authorization: Bearer <token>" in plain text. This helper clears the
    Authorization header ON that object. Because the request message is a single instance shared by
    every reference to it, clearing the header there removes the token RETROACTIVELY from every
    copy of the record that already escaped: the caller's -ErrorVariable collection, $global:Error,
    and any record a nested frame republished. Nothing else can achieve that. -ErrorVariable is
    populated by the ENGINE from the error stream, captures records raised inside nested calls even
    when an inner catch swallowed them, and is a separate collection this module cannot edit -- a
    live run measured NINE records reaching the caller for ONE failed read, one of them carrying the
    token. Removing a list entry (step 2) never touched them; mutating the shared object does.

    2. REMOVE. Replaces the module-wide bearer-hygiene idiom that discarded the result of calling
    the ArrayList .Remove() method with $PSItem against the automatic $Error variable, which never
    actually worked from module scope. Inside module code, the automatic $Error variable resolves to
    the module's own private list -- the record a catch block just swallowed is never in it. Even
    against $global:Error (the caller's real list, and the one that can genuinely carry a
    bearer-token-bearing HttpRequestMessage in TargetObject), the ErrorRecord instance bound to
    $PSItem inside a catch block is a DIFFERENT object than the one PowerShell appended to
    $global:Error, so a reference-equality Remove($PSItem) silently no-ops. The one part of the
    record that IS reference-stable across that boundary is its Exception object. This helper scans
    $global:Error for the first entry whose .Exception is reference-identical (never message-equal --
    two unrelated failures can share the same text, and removing the wrong record would be worse than
    removing none) to the supplied record's .Exception, and removes only that entry.

    Call this as the first statement in a catch block, exactly where the old $Error-based removal
    line used to be. Emits nothing to the pipeline (so a stray
    return value can never corrupt a cmdlet's own output), never throws, and makes no network call,
    because it runs on the failure path where a throw here would mask the original error being
    handled.

    .PARAMETER Record
    The ErrorRecord caught in a catch block (normally $PSItem). Its .TargetObject and exception
    chain -- following .InnerException AND an AggregateException's .InnerExceptions, since the
    Graph SDK's retry path throws the latter and its real transport failure is not always at index
    0 -- are searched for an HttpRequestMessage (directly, as the .RequestMessage of an
    HttpResponseMessage, or one hop further behind a wrapper object carrying a Request,
    RequestMessage or Response member) whose Authorization header is cleared, and its matching entry in
    $global:Error -- found by Exception reference identity, not ErrorRecord object identity -- is
    removed. Safe to pass $null; the helper then does nothing. A record whose Exception is $null is
    still scrubbed, but nothing is removed from $global:Error, since Exception identity is the only
    key that can find the entry.

    .EXAMPLE
    try {
        Invoke-MgGraphRequest @InvokeParams
    } catch {
        Remove-OERErrorRecord -Record $PSItem
        throw Convert-GraphHttpException $PSItem
    }

    Clears "Authorization: Bearer <token>" off the HttpRequestMessage the record points at -- which
    also disarms every copy of that record already sitting in the caller's -ErrorVariable -- and
    strips the record from the caller's $global:Error, before re-throwing a sanitized exception.
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidGlobalVars', '',
        Justification = 'The caller''s global $Error list is precisely the list that must be scrubbed of a bearer-carrying record; a module-scoped $Error is a private, different list that cannot reach the record needing removal.')]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '',
        Justification = 'Private helper only strips an already-emitted diagnostic record from $global:Error for bearer-token hygiene. It is not a user-facing state change and must run unconditionally as the first statement of a catch block, so ShouldProcess would be wrong here.')]
    [CmdletBinding()]
    [OutputType([void])]
    param(
        [AllowNull()]
        [System.Management.Automation.ErrorRecord]
        $Record
    )

    if ($null -eq $Record) {
        return
    }

    # -- 1. Scrub the bearer token off the shared HttpRequestMessage --------------------------
    # This runs BEFORE the $global:Error walk on purpose: it is the only step that can reach a
    # record which already escaped into the caller's -ErrorVariable, and it must not be skipped
    # if the removal below finds nothing to remove.
    try {
        # Collects the three member names that ever hold a request off ANY object -- an exception,
        # or a wrapper standing between the exception and the request. Each read is guarded
        # individually: reading a property can itself throw on some SDK exception shapes (Kiota's
        # ApiException is the known one), and losing the whole walk to one bad member would leave
        # the token in place on every other candidate.
        function Add-RequestCandidate {
            param($Source, $Sink)
            if ($null -eq $Source) { return }
            foreach ($MemberName in @('Request', 'RequestMessage', 'Response')) {
                try {
                    $Property = $Source.PSObject.Properties[$MemberName]
                    if ($null -ne $Property) { $Sink.Add($Property.Value) }
                } catch { $null = $PSItem }
            }
        }

        $Candidates = [System.Collections.Generic.List[object]]::new()
        $Candidates.Add($Record.TargetObject)

        # Walk the exception chain BREADTH-first, following .InnerException AND .InnerExceptions.
        # An .InnerException-only walk cannot reach an AggregateException's second inner exception:
        # AggregateException.InnerException returns InnerExceptions[0] and nothing else, so a
        # transport failure at index 1 keeps its token. That is not hypothetical here -- the Graph
        # SDK's retry path throws exactly that aggregate ("Too many retries performed... (HTTP
        # request failed... )"), which Convert-GraphHttpException already has to special-case.
        #
        # TERMINATION. $Seen holds every exception already walked, compared by REFERENCE, so a chain
        # or aggregate that points back at itself is dequeued once and never re-enqueued. $Visited is
        # a second, unconditional bound covering the case where a property getter hands back a fresh
        # wrapper object on every read, which reference identity alone would never catch. No real SDK
        # exception nests anywhere near 32 deep.
        $Seen = [System.Collections.Generic.List[object]]::new()
        $Pending = [System.Collections.Generic.Queue[object]]::new()
        if ($null -ne $Record.Exception) { $Pending.Enqueue($Record.Exception) }
        $Visited = 0
        while ($Pending.Count -gt 0 -and $Visited -lt 32) {
            $Exception = $Pending.Dequeue()
            if ($null -eq $Exception) { continue }
            $AlreadySeen = $false
            foreach ($Walked in $Seen) {
                if ([object]::ReferenceEquals($Walked, $Exception)) { $AlreadySeen = $true; break }
            }
            if ($AlreadySeen) { continue }
            $Seen.Add($Exception)
            $Visited++

            Add-RequestCandidate -Source $Exception -Sink $Candidates

            try { $Pending.Enqueue($Exception.InnerException) } catch { $null = $PSItem }
            try {
                $Aggregate = $Exception.PSObject.Properties['InnerExceptions']
                if ($null -ne $Aggregate) {
                    foreach ($Inner in @($Aggregate.Value)) { $Pending.Enqueue($Inner) }
                }
            } catch { $null = $PSItem }
        }

        # ONE extra pass, deliberately not recursive. A candidate that is neither known type may
        # still be a WRAPPER around the real request: a measured shape has an exception whose
        # .Response is not an HttpResponseMessage at all but a custom object carrying the real
        # .RequestMessage, and the two-type check below walked straight past it. The same pass is
        # what reaches the members of TargetObject itself, which nothing else inspects. Values
        # collected here are scrubbed but never expanded again, so this cannot crawl an arbitrary
        # object graph however deeply it self-references.
        $Indirect = [System.Collections.Generic.List[object]]::new()
        foreach ($Candidate in $Candidates) {
            if ($null -eq $Candidate) { continue }
            if ($Candidate -is [System.Net.Http.HttpRequestMessage] -or
                $Candidate -is [System.Net.Http.HttpResponseMessage]) {
                continue
            }
            Add-RequestCandidate -Source $Candidate -Sink $Indirect
        }
        foreach ($Extra in $Indirect) { $Candidates.Add($Extra) }

        foreach ($Candidate in $Candidates) {
            if ($null -eq $Candidate) { continue }
            $Request = $null
            if ($Candidate -is [System.Net.Http.HttpRequestMessage]) {
                $Request = $Candidate
            } elseif ($Candidate -is [System.Net.Http.HttpResponseMessage]) {
                $Request = $Candidate.RequestMessage
            }
            if ($null -eq $Request) { continue }
            try {
                # ORDER MATTERS, and the two calls are not the same call twice.
                #
                # The typed setter is the one that does the work. Measured on .NET 10 / PowerShell
                # 7.6.5 across every shape that could be produced -- typed-set, TryAddWithoutValidation
                # with a well-formed value, with a value the typed parser rejects, and two values on
                # the one header -- it cleared the rendering in ALL of them, including on an already
                # disposed request. So do not delete this line thinking Remove() covers it.
                #
                # Remove() is a deliberate second, parser-independent clear, and Remove() ALONE also
                # cleared every one of those shapes. Right after the typed setter it measured as a
                # no-op (it returned $false, meaning nothing was left to remove) -- it is kept because
                # the two reach the header by different routes: the typed property goes through the
                # known-header descriptor and its parser, Remove() goes at the raw store by name. A
                # bearer token surviving here is a security failure, and the cost of the second route
                # is one no-op call on a path that has already failed.
                #
                # An earlier version of this comment claimed the typed accessor reports a
                # TryAddWithoutValidation header as absent while the collection still renders it. Half
                # true and not the reason: the GETTER does return $null for a value the parser rejects,
                # but the SETTER clears that value anyway. The measurement above is the reason.
                $Request.Headers.Authorization = $null
                [void]$Request.Headers.Remove('Authorization')
            } catch { $null = $PSItem }
        }
    } catch {
        # Same best-effort contract as the removal below: never let bearer hygiene throw out of
        # someone else's catch block. See the comment on that catch for the full reasoning.
        $null = $PSItem
    }

    # -- 2. Remove the matching entry from the caller's $global:Error -------------------------
    if ($null -eq $Record.Exception) {
        return
    }

    try {
        for ($Index = 0; $Index -lt $global:Error.Count; $Index++) {
            $Candidate = $global:Error[$Index]
            if ($null -ne $Candidate -and [object]::ReferenceEquals($Candidate.Exception, $Record.Exception)) {
                $global:Error.RemoveAt($Index)
                break
            }
        }
    } catch {
        # Intentionally swallowed: this scrub is best-effort bearer-hygiene running on a failure
        # path inside someone else's catch block. A concurrent/odd $global:Error state must never
        # bubble an exception out here -- that would mask the original error being handled, which is
        # worse than leaving a record unscrubbed. An assignment (rather than a bare $null statement
        # VALUE) satisfies PSAvoidUsingEmptyCatchBlock without emitting anything to the pipeline if
        # this branch ever actually runs -- this helper is called as a bare statement at ~40
        # `catch { scrub; ... }` sites, where a stray emitted value would corrupt the caller's output.
        $null = $PSItem
    }
}
