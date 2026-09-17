function Resolve-OERAccessPackageId {
    <#
    .SYNOPSIS
    Resolves an access package to its id, accepting either an id or a display name, and refuses an
    id that does not exist.

    .DESCRIPTION
    Returns the access package id. When -Id is supplied it is returned unchanged without any Graph
    call: the only two cmdlets that use that parameter (Remove-OERAccessPackage and
    Set-OERAccessPackage, both in their ById parameter set) immediately issue a DELETE or a PATCH
    against the value, which fails loudly on its own when the id is wrong, so a second read would
    buy nothing.

    When -DisplayName is supplied and the value is a GUID it is treated as an id, but it is no
    longer returned blind: one existence read
    (GET accessPackages/{id}?$select=id) confirms the package is really there. A GUID that does not
    resolve throws an ErrorRecord with ErrorId 'AccessPackageNotFound'. It deliberately does NOT
    return $null, since $null from this helper means "this display name is free" to
    New-OERAccessPackage (which uses this helper as its duplicate probe) and to
    Sync-OERStructureAccessPackage (which takes $null as "create it") -- a stale GUID answered with
    $null would make the apply engine create an access package whose display name is that GUID.
    Before this check a stale or mistyped GUID produced no output and no error at every caller,
    because each of them went on to query Graph with the bad id and got an empty collection back
    (issue #71). The cost of the guarantee is ONE existence read per GUID.

    THAT COST MULTIPLIES, and callers passing ids in a loop should know the shape of it. Every
    -AccessPackage parameter in the module funnels through this helper, so each id-addressed call
    now issues ONE extra request on top of whatever it already issued. Measured on the three paths
    that matter:

      * The documented pipeline Get-OERAccessPackage | Get-OERAccessPackageResourceRole goes from
        2N requests to 3N, of which exactly N is the probe added here. Measured live on 2026-09-11:
        Packages = 6, ExistenceReads = 6, RoleReadRequests = 18. Get-OERAccessPackage emits an Id
        per package, -AccessPackage binds it by property name, and each package then costs three
        requests -- the existence probe below (GET accessPackages/{id}?$select=id), the resource
        role read itself (GET accessPackages/{id}?$expand=resourceRoleScopes(...),catalog), and the
        best-effort Get-OERCatalogResource -Catalog join Get-OERAccessPackageResourceRole issues to
        fill ResourceDisplayName. That catalog read is an -All walk, so on a large catalog it is
        itself more than one request and the per-package cost rises above three. ExistenceReads
        equalling Packages is exactly what issue #71's cost model claims -- one probe per
        id-addressed call, never more -- and the measurement confirms it held.
      * One accessPackages[] entry applied by Sync-OERStructureAccessPackage costs 1 + A + D + C
        extra probes, where A is the number of MISSING declared resource-role bindings it adds, D
        the number of undeclared bindings it prunes (only under -Prune), and C the number of
        assignment policies it creates -- one probe each, plus one for the assignment-policy read
        that always runs. With R declared roles all missing, R live bindings all pruned and P
        policies created, that upper bound is 1 + 2R + P. An entry that is already converged pays
        only the 1.
      * Get-OERInventory is the highest-volume id-addressed caller in the module. It reads every
        access package twice by id -- Get-OERAccessPackageResourceRole -AccessPackage $Ap.Id and
        Get-OERAccessPackageAssignmentPolicy -AccessPackage $Ap.Id, both in the accessPackages
        projection loop -- so each package goes from 3 requests to 5, and an inventory covering P
        access packages issues 2P probes it did not issue before. The 3 and the 5 are the bullet
        above counted twice, not a second cost model: the resource-role read is three of the five
        (its probe, the $expand read, and the Get-OERCatalogResource join, which is rebuilt inside
        that cmdlet's process block and so is paid per package rather than cached) and the
        assignment-policy read is the other two (its probe plus the filtered list). Two of the five
        are the new probes, which is the 2P.

    THE ONE PLACE THAT IS NOT PURELY A COST is that same inventory loop, and the exposure must be
    stated rather than softened. At every caller that SURFACES a resolver failure, extra requests
    cannot turn into a wrong answer: a probe that fails on a 403 or an exhausted 429 is reported as
    that failure, never as a not-found. Get-OERInventory's resource-role read is the exception --
    it is called with -ErrorAction SilentlyContinue, which suppresses the non-terminating error
    Get-OERAccessPackageResourceRole publishes for exactly that failure, and the projection then
    books resourceRoles = @() for the package. That array is what Invoke-OERStructure -Prune diffs
    against, so a failed read is recorded as the empty fact "this package has no resource roles",
    which is issue #76's defect class. The SWALLOW is pre-existing and is not changed here; what IS
    new is that the same suppressed path now issues a SECOND, independent request per package, so
    the probability that the projection is empty-by-failure rather than empty-in-fact roughly
    doubles -- against entitlement management endpoints Microsoft documents as heavily throttled.
    The assignment-policy read beside it passes no -ErrorAction, so its failure does reach the
    caller's error stream, but that package's assignmentPolicies is still booked as @(). Whether
    that -ErrorAction SilentlyContinue should change at all is a separate design question with its
    own blast radius, deliberately not decided here. Narrowing the cost itself (an internal
    id-trusted entry point, or caching probed ids for the life of a call) is likewise a design
    change with its own tests, deliberately not made here.

    When -DisplayName is not a GUID a filtered query against the entitlement management
    accessPackages collection is issued through Invoke-OERGraphRequest. Exactly one match returns
    that package's id and no match returns $null; more than one match throws an ErrorRecord with
    ErrorId 'AmbiguousName' listing the candidate ids, because access package display names are not
    unique across catalogs and picking the first match would silently act on an arbitrary package.
    The display name is escaped through
    ConvertTo-OERODataFilterValue, which doubles embedded single quotes and percent-encodes the value
    so reserved characters survive transport. This private helper is the single access-package-lookup
    entry point used by the access-package cmdlets.

    .PARAMETER Id
    The access package id (GUID) to return verbatim. Takes precedence over -DisplayName; no Graph call is made.

    .PARAMETER DisplayName
    The access package display name to resolve to an id via a filtered query when -Id is not supplied.
    If the value is a GUID it is treated as an id and confirmed with a single existence read, which
    throws 'AccessPackageNotFound' when the package does not exist rather than handing the bad id on
    to the caller.

    .EXAMPLE
    Resolve-OERAccessPackageId -DisplayName 'AP-Sales'
    Returns the id of the access package with that display name, or $null when it does not exist.

    .EXAMPLE
    Resolve-OERAccessPackageId -DisplayName '22222222-2222-2222-2222-222222222222'
    Confirms the id exists and returns it, or throws AccessPackageNotFound when it does not.
    #>
    [OutputType([string])]
    [CmdletBinding()]
    param(
        [string]$Id,
        [string]$DisplayName
    )
    if ($Id) { return $Id }
    if (-not $DisplayName) {
        throw 'Resolve-OERAccessPackageId requires either -Id or -DisplayName.'
    }
    if (Test-OERGuid -Value $DisplayName) {
        # The declared codes are MEASURED, not guessed. A live run on 2026-09-11 issued exactly this
        # GET for an access package id that does not exist, and entitlement management answered
        # 'AccessPackageNotFound' -- so that is the code declared first. 'NotFound' stands beside it
        # for one reason, and it is not caution: it is Convert-GraphHttpException's STATUS-derived
        # label for a 404 whose body carried no parseable code, so it is the honest fallback
        # whenever the body is unreadable, and it is what the same run measured on the access review
        # decisions path.
        # 'ResourceNotFound', 'ObjectNotFound' and 'Request_ResourceNotFound' used to stand here too,
        # as a deliberate superset declared while the real code was unknown. They were never
        # observed on this endpoint and are gone -- unobserved codes are what made the set a guess,
        # and the guess was wrong: the real code fell outside it, so the marker was never produced
        # and the tailored ErrorRecord below never fired. This call surfaced Graph's own terse
        # "The access package was not found." with Category OperationStopped instead.
        # Get-ExpectedGraphErrorMatch compares WHOLE, trimmed tokens (never a prefix), so neither
        # declared code can over-match a longer code that means something else. It also reads the
        # message text only when the error id is status-derived, so a 403 carrying the real Graph
        # code 'Authorization_RequestDenied' can NEVER be softened into "not found" here -- its id is
        # not status-derived, so its message is never even looked at. A 429 is a weaker guarantee,
        # not an impossibility: 'TooManyRequests' IS one of Test-StatusDerivedErrorId's labels, so a
        # throttle whose body carried no parseable code does have its message text consulted, and
        # would be softened by a colon-delimited 'NotFound' token appearing in that prose. No Graph
        # throttle message is known to carry one, but the mechanism gives improbability here, not
        # impossibility. Either way this is issue #76's defect class and it must not come back
        # through this door.
        # A third, still undocumented code on this endpoint would throw its own Graph error instead
        # of the tailored one: still loud, still no silent empty answer, which is the safe direction
        # to be wrong in -- exactly how the old superset's wrong guess surfaced.
        $ExistsUri = ('v1.0/identityGovernance/entitlementManagement/accessPackages/{0}?$select=id' -f $DisplayName)
        $Probe = Invoke-OERGraphRequest -Uri $ExistsUri -ExpectedErrorCode 'AccessPackageNotFound', 'NotFound'
        if (@($Probe.PSObject.TypeNames) -contains 'Omnicit.EntraRBAC.GraphExpectedError') {
            # THE MESSAGE'S THREE REASONS ARE NOT EXHAUSTIVE: there is a fourth, a READ-YOUR-WRITE
            # window. Sync-OERStructureAccessPackage sets $ApId from New-OERAccessPackage's response
            # (line 223) and then passes it straight back in as -AccessPackage seconds later, at the
            # Add-OERAccessPackageResourceRole call and again at the New-OERAccessPackageAssignmentPolicy
            # call. If entitlement management has not yet made the new package readable, this probe
            # answers not-found and the operator is told the id may be stale, mistyped or from
            # another tenant about a package their own run just created. No retry machinery is added
            # for it on purpose: the POST that follows the probe is exposed to exactly the same lag,
            # so retrying here would narrow one window while leaving an equal one open, and a retry
            # loop in the single lookup helper every access-package cmdlet funnels through is a far
            # larger change than the window justifies. Recorded here so the message's limits are
            # discoverable from the throw site rather than only from the apply engine.
            throw [System.Management.Automation.ErrorRecord]::new(
                [System.Exception]::new(
                    "The access package id '$DisplayName' does not resolve to an access package in this tenant. " +
                    'It was accepted as an id because it is a GUID, but entitlement management has no access ' +
                    'package with that id -- it may be stale, mistyped, or belong to another tenant. Re-run with ' +
                    'the access package display name, or with an id from Get-OERAccessPackage.'),
                'AccessPackageNotFound',
                [System.Management.Automation.ErrorCategory]::ObjectNotFound,
                $DisplayName)
        }
        # The CALLER's GUID is returned, not $Probe.id. $select=id makes them the same value, but a
        # response that unexpectedly carried no id would turn this into a $null return -- and $null
        # from this helper means "this name is free", the one answer a stale id must never produce.
        return $DisplayName
    }
    $Escaped = ConvertTo-OERODataFilterValue -Value $DisplayName
    $Uri = "v1.0/identityGovernance/entitlementManagement/accessPackages?`$filter=displayName eq '$Escaped'&`$select=id,displayName"
    $Response = Invoke-OERGraphRequest -Uri $Uri
    $Candidates = @($Response.value | Where-Object { $null -ne $_ })
    if ($Candidates.Count -gt 1) {
        $Ids = ($Candidates | ForEach-Object { [string]$_.id }) -join ', '
        throw [System.Management.Automation.ErrorRecord]::new(
            [System.Exception]::new(
                "Access package display name '$DisplayName' matches $($Candidates.Count) access packages ($Ids). " +
                'Entitlement management does not enforce unique access package display names across ' +
                'catalogs, so this name cannot identify a single access package. Re-run with the ' +
                'access package id instead of the display name.'),
            'AmbiguousName',
            [System.Management.Automation.ErrorCategory]::InvalidArgument,
            $DisplayName)
    }
    if ($Candidates.Count -eq 1) {
        return [string]$Candidates[0].id
    }
    return $null
}
