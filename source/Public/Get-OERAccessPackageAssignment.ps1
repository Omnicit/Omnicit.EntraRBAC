function Get-OERAccessPackageAssignment {
    <#
    .SYNOPSIS
    Lists access package assignments.

    .DESCRIPTION
    Retrieves access package assignments through Microsoft Graph, optionally filtered by access package
    (-AccessPackage, id or display name), target user (-Target, object id), and/or assignment state
    (-State). With no filter, all assignments are listed. On accessPackageAssignment, target and
    accessPackage are navigation properties, not scalar fields, so every request sends
    $expand=target,accessPackage -- without it, the nested target and access package objects come back
    null. The -Target filter matches the real v1.0 field target/objectId (the directory object id of the
    subject; target/id is the subject record's own id and is not filterable). The -State filter matches
    the real v1.0 field state (assignmentState is not a v1.0 property). Output is zero or more tagged
    Omnicit.EntraRBAC.Assignment objects.

    .PARAMETER AccessPackage
    An access package id or display name to filter assignments by package. Accepts pipeline input by
    property name (binds AccessPackageId first, then Id, then DisplayName). An object carrying an
    AccessPackageId, such as an assignment policy, a resource role, an assignment or an assignment
    request, binds its access package id, never its own Id. An access package from
    Get-OERAccessPackage carries no AccessPackageId, so it binds its Id as before. A piped object
    whose AccessPackageId is empty is refused with EmptyAccessPackageId and nothing is read; a typed
    empty -AccessPackage without pipeline input still lists every assignment. An access package name
    is unique only within its catalog: use -Catalog for a name several catalogs share.

    .PARAMETER Catalog
    A catalog name or id. With it the -AccessPackage name is looked up only in that catalog, and an
    access package id that is not in it is refused with AccessPackageNotInCatalog before anything is
    read. An ambiguous catalog name is AmbiguousCatalogName and an unknown one CatalogNotFound.
    Supplying -Catalog without -AccessPackage is refused with CatalogWithoutAccessPackage. Does not
    bind from the pipeline.

    .PARAMETER Target
    A user object id (GUID) to filter assignments by target. A non-GUID value yields an
    InvalidTargetId error directing you to -User. The value is percent-encoded before it is placed
    in the Graph $filter URI. Mutually exclusive with -User; supply at most one.

    .PARAMETER State
    An assignment state to filter by. Must be one of the documented accessPackageAssignmentState
    values: delivering, partiallyDelivered, delivered, expired, deliveryFailed. Matching is
    case-insensitive, so any casing of a valid value binds (for example 'Delivered' or 'delivered'),
    and whichever casing you type is sent to Graph verbatim, unchanged. The entitlement management
    service compares the value case-insensitively too -- verified live on 2026-09-11 for the
    delivered/Delivered pair, which returned identical results -- so either spelling works.
    partiallyDelivered and deliveryFailed could not be produced on the verification tenant and are
    covered by that result only by assumption.

    .PARAMETER TenantId
    Optional tenant id or domain to authenticate against, forwarded to Initialize-OERAuth.

    .PARAMETER User
    The user to filter assignments by target, given as a user principal name or object id (GUID)
    and resolved via Resolve-OERPrincipal. Mutually exclusive with -Target; supply at most one.

    .EXAMPLE
    Get-OERAccessPackageAssignment -AccessPackage 'AP-Sales' -State Delivered
    Lists delivered assignments for the access package named AP-Sales.

    .EXAMPLE
    Get-OERAccessPackageAssignment -AccessPackage 'AP-Sales' -Catalog 'CAT-IT-Core'
    Lists the assignments of the access package named AP-Sales in the catalog CAT-IT-Core only.

    .EXAMPLE
    Get-OERAccessPackageAssignment -Target '00000000-0000-0000-0000-000000000001'
    Lists all assignments where the target is the given user object id.

    .EXAMPLE
    Get-OERAccessPackageAssignment -User 'anna.berg@contoso.com'
    Lists all assignments where the target is the user resolved from the given UPN.

    .EXAMPLE
    Get-OERAccessPackageAssignment
    Lists all access package assignments in the tenant.
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(ValueFromPipelineByPropertyName)]
        [Alias('AccessPackageId', 'Id', 'DisplayName')]
        [string]$AccessPackage,
        [string]$Target,

        # Issue #72: [ValidateSet] is case-insensitive by default (IgnoreCase = True; not overridden
        # here), so 'delivered' and 'Delivered' -- any casing of a valid value -- both bind, and
        # PowerShell passes the bound value through VERBATIM: whichever spelling the caller typed is
        # exactly what gets interpolated into the "state eq '...'" filter below, unchanged. Microsoft
        # Learn's "List assignments" $filter example writes state eq 'Delivered', capitalised.
        # VERIFIED on 2026-09-11 against a live tenant: entitlement management compares this value
        # case-INSENSITIVELY. Both spellings were run against a package holding exactly one
        # delivered assignment and both returned that one assignment (lowercase filter 1, uppercase
        # filter 1, unfiltered delivered count 1), with the verbose request URIs showing 'delivered'
        # and 'Delivered' reaching the wire unchanged. So no normalisation is needed here, and none
        # is added: the caller's casing is sent as typed and the service accepts either.
        # THE MEASUREMENT COVERS ONE PAIR ONLY -- delivered/Delivered. partiallyDelivered and
        # deliveryFailed could not be produced on the tenant (no assignment can be driven into
        # either state on demand), so those spellings are unverified by the same evidence; the
        # service behaviour is assumed uniform across the enum, not proven per value.
        # Do not widen this ValidateSet to carry both casings: it would only double the
        # tab-completion list without changing a single byte sent over the wire.
        [ValidateSet('delivering', 'partiallyDelivered', 'delivered', 'expired', 'deliveryFailed')]
        [string]$State,
        [ValidateNotNullOrEmpty()]
        [string]$TenantId,

        # Declared after the pre-existing parameters so their positional binding is unchanged.
        [string]$User,

        [ValidateNotNullOrEmpty()]
        [string]$Catalog
    )
    begin {
        $AuthParams = @{}
        if ($TenantId) { $AuthParams.TenantId = $TenantId }
        Initialize-OERAuth @AuthParams
    }
    process {
        # A piped object that carries an AccessPackageId property with no value binds '' (the alias
        # binds first, so its own Id is never tried). Reading every assignment for it would be the
        # opposite of what the caller piped, so it is refused before anything is read. A typed
        # -AccessPackage '' without pipeline input keeps listing everything.
        if ($MyInvocation.ExpectingInput -and $PSBoundParameters.ContainsKey('AccessPackage') -and
            [string]::IsNullOrWhiteSpace($AccessPackage)) {
            Write-CmdletError `
                -Message ([System.Exception]::new('The piped object names no access package: its AccessPackageId is empty, so nothing was read. Pipe an object that names an access package, or call Get-OERAccessPackageAssignment without pipeline input to list every assignment.')) `
                -ErrorId 'EmptyAccessPackageId' -Category InvalidArgument `
                -TargetObject $PSItem -Cmdlet $PSCmdlet
            return
        }
        if ($PSBoundParameters.ContainsKey('Catalog') -and -not $AccessPackage) {
            Write-CmdletError `
                -Message ([System.Exception]::new('-Catalog scopes the -AccessPackage lookup and filters nothing on its own: supply -AccessPackage with -Catalog, or omit -Catalog.')) `
                -ErrorId 'CatalogWithoutAccessPackage' -Category InvalidArgument `
                -TargetObject $Catalog -Cmdlet $PSCmdlet
            return
        }
        $Filters = @()
        if ($AccessPackage) {
            # Refuse an ambiguous display name loudly, and surface any other throw as itself. Only
            # a $null return (a display name that matched nothing) reaches the not-found branch.
            $PackageId = $null
            $ResolveParams = @{ DisplayName = $AccessPackage }
            if ($PSBoundParameters.ContainsKey('Catalog')) { $ResolveParams.Catalog = $Catalog }
            try {
                $PackageId = Resolve-OERAccessPackageId @ResolveParams
            } catch {
                Remove-OERErrorRecord -Record $PSItem
                if (Test-OERAmbiguousNameError -Record $PSItem) {
                    Write-CmdletError `
                        -Message ([System.Exception]::new($PSItem.Exception.Message)) `
                        -ErrorId 'AmbiguousAccessPackageName' -Category InvalidArgument `
                        -TargetObject $AccessPackage -Cmdlet $PSCmdlet
                    return
                }
                # Anything else the resolver raised is surfaced AS ITSELF, never folded into the
                # not-found branch below. Its own AccessPackageNotFound already names the id and why it
                # may be wrong, and a 403 or an exhausted 429 from its existence read is not evidence
                # that no such package exists -- reporting either as not found is the failed-read-as-an-
                # empty-fact defect of issue #76. A display name matching nothing still returns $null
                # rather than throwing, so the not-found branch below is unchanged for it.
                $PSCmdlet.WriteError($PSItem)
                return
            }
            if (-not $PackageId) {
                $NotFoundText = "Access package '$AccessPackage' not found."
                if ($PSBoundParameters.ContainsKey('Catalog')) { $NotFoundText = "Access package '$AccessPackage' not found in catalog '$Catalog'." }
                Write-CmdletError -Message ([System.Exception]::new($NotFoundText)) `
                    -ErrorId 'AccessPackageNotFound' -Category ObjectNotFound -TargetObject $AccessPackage -Cmdlet $PSCmdlet
                return
            }
            $Filters += "accessPackage/id eq '$PackageId'"
        }
        if ($Target -or $User) {
            $Principal = Resolve-OERPrincipalOrId -PrincipalId $Target -User $User `
                -IdParameterName 'Target' -InvalidIdErrorId 'InvalidTargetId' `
                -FriendlyParameterHint '-User'
            if ($Principal.ErrorId) {
                Write-CmdletError -Message ([System.Exception]::new($Principal.Message)) `
                    -ErrorId $Principal.ErrorId -Category $Principal.Category `
                    -TargetObject $Principal.TargetObject -Cmdlet $PSCmdlet
                return
            }
            $Filters += "target/objectId eq '$(ConvertTo-OERODataFilterValue -Value $Principal.PrincipalId)'"
        }
        if ($State) { $Filters += "state eq '$(ConvertTo-OERODataFilterValue -Value $State)'" }

        $Base = 'v1.0/identityGovernance/entitlementManagement/assignments'
        $QueryParts = @('$expand=target,accessPackage')
        if ($Filters.Count -gt 0) {
            $QueryParts += "`$filter=$([string]::Join(' and ', $Filters))"
        }
        $Uri = "$Base`?$([string]::Join('&', $QueryParts))"

        try {
            $Response = Invoke-OERGraphRequest -Uri $Uri -All
        } catch {
            Remove-OERErrorRecord -Record $PSItem
            $PSCmdlet.WriteError($PSItem)
            return
        }
        foreach ($Item in @($Response.value)) {
            ConvertTo-OERAssignment -InputObject $Item
        }
    }
}
