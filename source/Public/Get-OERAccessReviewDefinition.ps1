function Get-OERAccessReviewDefinition {
    <#
    .SYNOPSIS
    Reads one or more access review schedule definitions by id, display name, or OData filter.

    .DESCRIPTION
    Retrieves access review schedule definitions through Microsoft Graph and returns them as tagged
    Omnicit.EntraRBAC.AccessReviewDefinition objects. Supply -Id for a direct read, -DisplayName for a
    display-name match (a wildcard-free name is looked up server-side, a wildcard is matched
    client-side), or -Filter for a server-side OData
    filter expression. With -IncludeInstances the definition's instances are attached as an Instances
    property (tagged Omnicit.EntraRBAC.AccessReviewInstance). A named definition that does not exist
    produces a non-terminating AccessReviewDefinitionNotFound error.
    Supply -All to list every definition without a filter (paged).

    .PARAMETER Id
    The object id of a single access review definition to read.

    .PARAMETER DisplayName
    The display name to match. Wildcards are supported (e.g. 'AR*', '*demo*'). A name carrying NO
    wildcard character (* ? [ ]) is looked up with a single SERVER-SIDE
    $filter=displayName eq '...' request, so an exact-name lookup no longer reads the whole
    collection. A name carrying a wildcard -- or an exact name the server returns nothing for --
    falls back to the paged read of every definition, narrowed CLIENT-SIDE with -like.
    Measured against a live tenant: this endpoint DOES honor displayName eq (a filter for a name
    that does not exist comes back with @odata.count 0 and an empty value collection), but it
    SILENTLY IGNORES startswith(displayName,...) and returns the whole collection instead. Do not
    widen the eq result to other name filters.
    ONE behavior difference, stated honestly: the fallback arms when the server returns NOTHING, so
    it does not cover a case-only near-match. -like is case-insensitive while OData eq may not be,
    and Graph does not enforce a unique displayName, so where two definitions differ only in case
    this can return the one the server matched where the client-side walk returned both. If you
    rely on case-insensitive name matching, pass a wildcard (for example 'ar-*') to force the
    client-side walk.
    No match produces a non-terminating AccessReviewDefinitionNotFound error.

    .PARAMETER Filter
    A server-side OData filter expression (without the $filter= prefix). Measured against a live
    tenant, this endpoint honors the documented
    contains(scope/microsoft.graph.accessReviewQueryScope/query, '...') form and displayName eq
    '...', but silently IGNORES startswith(displayName,...) -- an ignored filter returns every
    definition rather than an error, so an unexpectedly large result set is the only signal. Other
    expressions are untested. For name matching use -DisplayName, which issues the displayName eq
    form itself and falls back to a client-side match.

    .PARAMETER All
    Lists every access review definition in the tenant using an unfiltered, paged GET
    (default page size 100, following @odata.nextLink until exhausted). Note: callers without at
    least the Global Reader directory role see only definitions they created (a Graph-side
    behavior), and this endpoint is heavily throttled. The throttle is a low request RATE bucket,
    not a result-size limit: it was measured on a tenant holding six definitions, where $top made no
    consistent difference. When it trips, the Graph SDK's own retry handler retries the 429
    internally before this module's bounded backoff ever sees it, so the command emits NO output at
    all for roughly 85 to 140 seconds (86 to 136 measured) before the first "Throttled. Waiting
    ... s" verbose line appears. It has not hung -- do not interrupt it. If every retry is exhausted the 429
    surfaces as a TooManyRequests error.

    .PARAMETER IncludeInstances
    When set, attaches the definition's review instances as an Instances property on the returned object.

    .PARAMETER TenantId
    Optional tenant id or domain to authenticate against, forwarded to Initialize-OERAuth.

    .EXAMPLE
    Get-OERAccessReviewDefinition -DisplayName 'Q3 AP Review' -IncludeInstances
    Returns the access review definition with its instances attached. The name carries no wildcard,
    so it is resolved with one server-side displayName eq request rather than a full list read.

    .EXAMPLE
    Get-OERAccessReviewDefinition -DisplayName 'AR*'
    Returns every access review definition whose display name starts with 'AR' (client-side match).

    .EXAMPLE
    Get-OERAccessReviewDefinition -Filter "contains(scope/microsoft.graph.accessReviewQueryScope/query, '/groups')"
    Returns every access review definition scoped to a group, using the one server-side OData filter
    form the endpoint supports.

    .EXAMPLE
    Get-OERAccessReviewDefinition -All
    Returns every access review definition in the tenant.
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', 'All',
        Justification = 'Switch is a parameter-set discriminator; ParameterSetName is used instead.')]
    [CmdletBinding(DefaultParameterSetName = 'ByName')]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(ParameterSetName = 'ById', Mandatory, ValueFromPipelineByPropertyName)]
        [Alias('AccessReviewDefinitionId')]
        [string]$Id,

        [Parameter(ParameterSetName = 'ByName', Mandatory)]
        [string]$DisplayName,

        [Parameter(ParameterSetName = 'ByFilter', Mandatory)]
        [string]$Filter,

        [Parameter(ParameterSetName = 'All', Mandatory)]
        [switch]$All,

        [switch]$IncludeInstances,
        [string]$TenantId
    )
    begin {
        $AuthParams = @{}
        if ($TenantId) { $AuthParams.TenantId = $TenantId }
        Initialize-OERAuth @AuthParams
    }
    process {
        try {
            if ($PSCmdlet.ParameterSetName -in 'All', 'ByName') {
                $Raw = $null
                if ($PSCmdlet.ParameterSetName -eq 'ByName' -and $DisplayName -notmatch '[\*\?\[\]]') {
                    # A wildcard-free name is resolved SERVER-SIDE first. Measured live: this endpoint
                    # honors displayName eq (a filter for a name that does not exist returns
                    # @odata.count 0), even though it silently ignores startswith(displayName,...).
                    # That matters here more than anywhere else in the module: the definitions
                    # collection sits in a very low request-RATE bucket, and a name lookup that pages
                    # the whole collection spends that budget for one row.
                    # No $select on purpose. The converter reads eleven top-level fields plus the
                    # nested settings bag, and a $select that dropped one would null the property
                    # silently instead of failing -- the defect class PR #45 fixed. Six definitions
                    # cost nothing extra to fetch whole, and the risk is not worth the bytes.
                    $Escaped = ConvertTo-OERODataFilterValue -Value $DisplayName
                    $NameUri = "v1.0/identityGovernance/accessReviews/definitions?`$filter=displayName eq '$Escaped'"
                    # -All costs nothing when the filter matches a single definition -- with no
                    # @odata.nextLink the wrapper makes exactly one request -- and it removes the
                    # possibility of silently truncating a multi-page result if several definitions
                    # ever share one display name (Graph does not enforce displayName uniqueness).
                    $NameResponse = Invoke-OERGraphRequest -Uri $NameUri -All
                    $Raw = @($NameResponse.value | Where-Object { $_ })
                    # Zero rows is NOT proof the definition is absent, so it is not treated as one:
                    # -like is case-insensitive while OData eq may not be. This fallback is
                    # load-bearing, not decoration -- but note EXACTLY what it does and does not
                    # cover. It arms on an EMPTY server result only, so a name that the server
                    # matches case-SENSITIVELY still short-circuits here: two definitions whose
                    # names differ only in case would both come back from the -like walk but only
                    # one from eq, and that narrower result is returned without a fallback. That is
                    # the one behavior difference this path carries, and it is documented on
                    # -DisplayName. Do not restate the guarantee as "can never return fewer".
                    if ($Raw.Count -eq 0) { $Raw = $null }
                }
                if ($null -eq $Raw) {
                    # 'All', a wildcard -DisplayName, and the empty-server-result fallback all page the
                    # unfiltered definitions list and narrow CLIENT-SIDE. $top=100 is a deliberate
                    # page-size choice for this heavily throttled endpoint; the wrapper's -All switch
                    # follows @odata.nextLink and aggregates every page.
                    $Response = Invoke-OERGraphRequest -Uri 'v1.0/identityGovernance/accessReviews/definitions?$top=100' -All
                    $Raw = if ($PSCmdlet.ParameterSetName -eq 'ByName') {
                        @($Response.value | Where-Object { $_.displayName -like $DisplayName })
                    }
                    else {
                        @($Response.value)
                    }
                }
            }
            else {
                $Raw = switch ($PSCmdlet.ParameterSetName) {
                    'ById'     { , @(Invoke-OERGraphRequest -Uri ("v1.0/identityGovernance/accessReviews/definitions/{0}" -f $Id)) }
                    'ByFilter' {
                        $Encoded = [System.Uri]::EscapeDataString($Filter)
                        @((Invoke-OERGraphRequest -Uri "v1.0/identityGovernance/accessReviews/definitions?`$filter=$Encoded" -All).value)
                    }
                }
            }
        }
        catch {
            Remove-OERErrorRecord -Record $PSItem
            $PSCmdlet.WriteError($PSItem)
            return
        }

        $Raw = @($Raw | Where-Object { $_ })
        if ($Raw.Count -eq 0) {
            if ($PSCmdlet.ParameterSetName -eq 'All') { return }
            Write-CmdletError `
                -Message ([System.Exception]::new("No access review definition found for the $($PSCmdlet.ParameterSetName) query.")) `
                -ErrorId 'AccessReviewDefinitionNotFound' `
                -Category ObjectNotFound `
                -TargetObject $PSCmdlet.ParameterSetName `
                -Cmdlet $PSCmdlet
            return
        }

        foreach ($GraphDef in $Raw) {
            $Def = ConvertTo-OERAccessReviewDefinition -InputObject $GraphDef
            if ($IncludeInstances) {
                try {
                    $Instances = @((Invoke-OERGraphRequest -Uri ("v1.0/identityGovernance/accessReviews/definitions/{0}/instances" -f $Def.Id) -All).value)
                    $Instances = @($Instances | Where-Object { $_ } | ForEach-Object {
                        ConvertTo-OERAccessReviewInstance -InputObject $_ -DefinitionId $Def.Id
                    })
                }
                catch {
                    Remove-OERErrorRecord -Record $PSItem
                    $Instances = @()
                    Write-Warning "Could not read instances for access review definition $($Def.Id): $($PSItem.Exception.Message)"
                }
                $Def | Add-Member -NotePropertyName Instances -NotePropertyValue $Instances -Force
            }
            $Def
        }
    }
}
