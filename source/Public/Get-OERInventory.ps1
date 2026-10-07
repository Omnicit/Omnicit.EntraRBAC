function Get-OERInventory {
    <#
    .SYNOPSIS
    Reads the current state of a tenant's RBAC building blocks into a serializable inventory object.

    .DESCRIPTION
    Composes the existing Get-OER* cmdlets into a single tagged Omnicit.EntraRBAC.Inventory object whose
    shape matches the Phase 5 JSON document schema, so the output round-trips into the orchestration
    apply engine. Select which building blocks to read with -Include (default: Groups,
    AdministrativeUnits, Catalogs and AccessPackages).
    Azure sections (RoleAssignments, RoleManagementPolicies) need an ARM token: pass -IncludeARM to
    acquire it up front (the Azure sections otherwise acquire it on first use) and supply their
    targeting parameters. Names are emitted by default for portability;
    -IncludeId additionally stamps each top-level object with its id.
    The Groups section is SECURITY-ENABLED-SCOPED unless you say otherwise: with no -GroupFilter it
    reads 'securityEnabled eq true', so a distribution group and a Microsoft 365 group whose
    securityEnabled is false are not in the inventory at all -- their absence from the document is
    not evidence of their absence from the tenant. That default is deliberate, since this document
    feeds Invoke-OERStructure and widening it widens what the apply engine reconciles and, under
    -Prune, deletes. -GroupFilter is the supported lever for widening it: pass the OData filter you
    want (Export-OERInventory's groupsRoster.json, by contrast, is an unfiltered read-only roster of
    every group in the tenant).
    The Groups eligibility projection carries accessType (member or owner) and, for a time-bound
    eligibility, durationDays reconstructed from the schedule window, so a re-applied inventory keeps
    a time-bound eligibility time-bound and an owner eligibility on the owner access type. The Groups
    owners projection carries the group's owners (a privilege path distinct from members, since an
    owner can add members) so a re-applied inventory keeps them, and is emitted only when the group
    has at least one owner. A group's members and owners include its service principals, written by
    object id. A document exported by an earlier version lacks them: Invoke-OERStructure reports them
    Extra, and -Prune leaves them in place, since the group prune never removes a service principal.
    The Groups pimPolicy projection is emitted only for a group found to use
    PIM for Groups: one with PIM eligibility, or one whose PIM-for-Groups policy has been modified (it
    carries a lastModifiedDateTime or a lastModifiedBy). Microsoft Graph lists those policies for
    every group, including one never used with PIM for Groups, and applying a changed pimPolicy to
    such a group onboards it to PIM for Groups, which cannot be undone -- so a group not found to use
    PIM for Groups carries no pimPolicy, and none of its policies is read. A group used only through
    PIM active assignments, with untouched policies, is not found to use it either. When that
    question cannot be answered for a group -- its policies could not be listed, or no modified
    policy was found while its PIM eligibility could not be read -- its pimPolicy is omitted and
    reported through the InventoryPartial error below. The projection carries requireApproval and,
    only while it is true, approvers as object ids (a display name is not guaranteed to resolve) --
    approvers are omitted while requireApproval is false, since the apply engine ignores declared
    approvers in that case and the offline validator would otherwise warn on every exported document.
    A collection whose LIVE READ FAILED is never stated as a fact. How that is expressed depends on
    what an omitted key means to the apply engine, which is not uniform: groups[].members,
    administrativeUnits[].members, administrativeUnits[].scopedRoles, catalogs[].resources and
    accessPackages[].resourceRoles still reconcile and still prune when their key is merely
    omitted, so an unread one is emitted as an EXPLICIT null -- the schema's documented "leave it
    untouched" signal. groups[].owners and groups[].eligibility are never reconciled or pruned
    from an omitted key, so an unread one is simply left out. Either way the gap is reported:
    after the inventory object is emitted, a non-terminating InventoryPartial error names every
    affected section/displayName/key, so a caller using -ErrorAction Stop or a try/catch finds out
    instead of treating a document with holes in it as a full tenant snapshot. Do not hand-edit
    such a null to an empty array -- that turns "unknown" into "declared empty", which
    Invoke-OERStructure -Prune acts on by deleting every live member (a group's service principals
    excepted), binding or resource. The
    catalog list itself, the resource names an access package's bindings are written under, a
    catalog's access packages and their assignment policies are reported through the same
    InventoryPartial error when their read fails, and are written as far as they were read: a
    failed catalog list leaves the catalogs and accessPackages sections empty, a failed package
    list leaves a catalog with no access packages, a failed policy read leaves a package with no
    assignment policies, and when the names cannot be read a group's or an application's binding is
    written under its object id and any other binding under the name the access package reader
    could join (the name the catalog recorded; a binding with no name at all makes the package's
    resourceRoles null, as described below). Invoke-OERStructure never removes a catalog, access
    package or assignment policy that is absent from the document.
    An entry is never written with an empty name, since the validator and schema.json refuse one. A
    binding, catalog resource or scoped role whose name is blank is written under an object id the
    apply engine accepts when it has one: a group's or an application's binding by its object id,
    and a catalog resource by its origin id (a SharePoint site's URL). When it has none -- a
    SharePoint binding with no name, a binding with no role, a catalog resource with neither a
    title nor an origin id, a scoped role with no role or no principal -- the whole collection (the
    package's resourceRoles, the catalog's resources or the unit's scopedRoles) is written as an
    explicit null and named in the InventoryPartial error, the way an unread collection is, since
    a declared set that quietly left the entry out would have Invoke-OERStructure -Prune remove it.
    A group, administrative unit or access review LIST that could not be read at all is reported
    through the same InventoryPartial error by the section's own name alone (groups,
    administrativeUnits or accessReviews) and is written as an empty array, which does not mean the
    tenant has none: the section is never null, so the error is the only thing that tells the two
    apart. The warning the read already wrote stays. A list that answered "none" (a not-found
    answer) is a fact about the tenant and is not reported.
    A dynamic group's membershipRuleProcessingState (On or Paused) is carried
    alongside its membershipRule so a paused rule round-trips paused. The Catalogs projection carries
    externallyVisible so a catalog whose access packages are requestable by connected-organization
    users does not silently re-create as internal-only. A Group or Application catalog resource, and
    an access package resourceRoles entry on one, is written under the group's or application's
    CURRENT display name, looked up by the resource's originId (its object id when the lookup returns
    nothing) -- never under the name the catalog recorded when the resource was added, which Graph
    keeps after a rename, except as described above when the names cannot be read.
    Invoke-OERStructure identifies such a resource by the object id its name resolves to.
    Only access-package-scoped, single-stage review definitions are captured: a group, application,
    directory-role or multi-stage review is skipped, with an aggregate warning naming how many were
    skipped. The AccessReviews projection carries accessPackage, assignmentPolicy, reviewers and
    recurrence so a captured review round-trips through Invoke-OERStructure (create-or-update: a
    review is matched by displayName, created when it does not exist and reconciled field by field
    when it does, with the immutable scope reported as a skipped drift rather than a misleading
    Unchanged). A multi-stage review (StageCount greater than zero) is skipped with a warning
    instead of being exported, because its reviewers live in stageSettings -- which the apply
    schema does not model -- and the top-level reviewers collection Graph returns for it is
    empty by construction, which would otherwise be misreported as a configured self review. A
    live recurrence interval outside the module's cadence vocabulary (for example an
    absoluteMonthly interval other than 1, 3 or 12) is exported as the nearest coarser cadence
    with a warning naming the true pattern, rather than silently. durationInDays is emitted only
    when the live settings.instanceDurationInDays is an integer the apply schema accepts (1-365):
    Graph reports 0 when that field does not drive the review's duration, and exporting the 0 made
    the bundle fail the schema.json written beside it. An omitted durationInDays means "leave
    untouched" on apply, which is the correct reading of that sentinel; a positive value above 365
    is dropped with a warning, because that is real configuration the schema cannot carry.
    A review's accessPackage and assignmentPolicy are written under their display names, read by
    id. A package or policy that no longer exists is written by its id: that is a fact about the
    review, so nothing is reported for it. A name that could not be read -- a refused, throttled
    or failed read -- is written by id too, and is reported as an unread collection (accessReviews,
    the review's display name, then accessPackage or assignmentPolicy) in the InventoryPartial
    error, so a document written by id for that reason is never mistaken for one whose target was
    deleted.
    The AccessPackages projection
    carries the hidden flag so a hidden package stays
    hidden across a round-trip. The RoleAssignments projection carries the ABAC condition,
    conditionVersion and description so a condition-scoped assignment is not exported as an
    unconditioned one. The RoleManagementPolicies projection carries activation window and
    enablement, approval and approvers, authentication context, and eligible and active permanence
    plus their day counts, so a policy round-trips instead of losing everything but permanence and
    the activation window. Notification rules are excluded from that projection: they are readable
    through Get-OERRoleManagementPolicy and writable through Set-OERRoleManagementPolicy
    -NotificationRule, but are not part of this document and do not round-trip. Azure PIM eligible
    and active ROLE ASSIGNMENTS (as opposed to the policy that governs them) remain outside every
    APPLY section here: neither roleAssignments (permanent Azure RBAC only) nor
    roleManagementPolicies (the governing policy) grants, captures or removes one, and this cmdlet
    itself still does not read them. Export-OERInventory writes the eligible ones into
    azurePimEligibility.json as read-only context, outside the apply document -- active assignments
    are not captured there either. Manage them directly with New-OEREligibleRoleAssignment,
    Get-OEREligibleRoleAssignment, New-OERActiveRoleAssignment and Get-OERActiveRoleAssignment.
    The DirectoryRoleAssignments and DirectoryRoleManagementPolicies sections cover Microsoft Entra
    directory roles. DirectoryRoleAssignments exports only the eligible and active assignments the
    apply engine manages: direct and at tenant scope, and for an active one a standing assignment --
    an activation of an eligible assignment, an assignment a principal holds through a group, and one
    scoped to an administrative unit are never exported, by the same rule Invoke-OERStructure matches
    and prunes by (Select-OERManagedDirectoryRoleAssignment). A user is named by its user principal
    name and a group by its display name, each falling back to the object id when no name can be
    read; a service principal, or a principal of unknown type, is named by its object id, and
    principalType is carried whenever the type is known. Entra does not keep group display names
    unique, so a group whose display name matches, without regard to letter case, that of another
    principal holding the same role and assignment type is named by its object id instead (still with
    principalType Group): two entries with the same role, principal and assignmentType would be
    refused by the validator. A time-bound assignment carries durationDays reconstructed from the
    schedule window the same way the apply engine measures it, so a re-applied export is Unchanged; a
    permanent one carries neither durationDays nor permanent. Two live schedules for one role,
    principal and kind export only the first this read returns, with a warning: Invoke-OERStructure
    compares against the first schedule Microsoft Graph returns for that role and principal, which is
    not guaranteed to be the same one, so such an entry may report a change when applied.
    DirectoryRoleManagementPolicies exports the policy of every directory role that has at least one
    row in the tenant-scope eligibility or assignment schedules -- any member type, activations
    included -- or, with -AllDirectoryRolePolicies, of every directory role; a directory policy
    carries approvers only while approval is required. A failed read of either schedule list or of
    the policies is reported through the InventoryPartial error and never stated as a fact: the kind
    whose read failed exports no entry, and a role selection made from an incomplete read is
    reported as partial.
    The export never writes two entries that the validator would refuse as duplicates, so a document
    it emits is not refused by Invoke-OERStructure for that reason. Live groups, administrative
    units, catalogs, access reviews, or access packages of one catalog whose names match, without
    regard to letter case, are left out of the document -- all of them -- and each such name is
    reported through the InventoryPartial error, since the apply engine refuses an ambiguous name and
    neither entry could be applied; leaving a top-level entry out removes nothing, because -Prune acts
    on child collections only. Role assignments whose scope (compared in its canonical form), role
    and principal collide are written with the principal's object id and, when the principal is
    already an id, with the role's full definition id; principalType is then written for a user,
    group or service principal. A role management policy read twice, for example by naming the same
    role twice in -Role, is written once.

    The inventory carries a top-level tenantId, directly after its version: the tenant ID the session's
    Microsoft Graph token was issued for, never the tenant as named with -TenantId (a domain, or
    organizations, names no tenant ID). Invoke-OERStructure applies the document only in that tenant
    and refuses it anywhere else with DocumentTenantMismatch. When the token reports no tenant ID, or
    the module holds no session, the key is left out, with no warning, and the document carries no
    tenant check. To use the inventory as a template for another tenant, change its tenantId to that
    tenant's ID or remove the key.

    .PARAMETER Include
    The building-block sections to read. Defaults to Groups, AdministrativeUnits, Catalogs and
    AccessPackages. AccessReviews captures only access-package-scoped, single-stage review
    definitions (optionally narrowed by -AccessReviewFilter); a group, application, directory-role
    or multi-stage review is skipped with a warning. DirectoryRoleManagementPolicies and
    DirectoryRoleAssignments read Microsoft Entra directory roles through Microsoft Graph and need no
    ARM token. RoleAssignments and RoleManagementPolicies require -IncludeARM plus their targeting
    parameters.

    .PARAMETER GroupFilter
    An OData filter (without the $filter= prefix) selecting which groups to read. When omitted,
    defaults to 'securityEnabled eq true' -- every security group, and nothing else: a distribution
    group and a Microsoft 365 group whose securityEnabled is false are excluded. This parameter is
    the supported way to widen that scope; weigh it against Invoke-OERStructure -Prune, which acts
    on whatever the resulting document declares.

    .PARAMETER Catalog
    A catalog id or display name that narrows the Catalogs and AccessPackages sections to one catalog.

    .PARAMETER AccessReviewFilter
    An optional display-name pattern (wildcards supported, e.g. 'AR*') narrowing which access review
    definitions to capture. Matching is performed CLIENT-SIDE over the full (paged) list, because the
    accessReviews endpoint does not reliably support server-side name filtering. When omitted, every
    definition is captured. This endpoint is heavily throttled, so a full capture may hit a 429 --
    the section then warns and is skipped without failing the rest of the run.

    .PARAMETER Scope
    A raw ARM scope for the Azure sections (e.g. '/subscriptions/{id}').

    .PARAMETER Subscription
    A subscription GUID or display name for the Azure sections.

    .PARAMETER ManagementGroup
    A management group name or display name for the Azure sections.

    .PARAMETER Role
    One or more roles (display name, GUID, or full ARM id) whose role management policy to read.
    Required to populate the RoleManagementPolicies section when neither -CommonRoles nor
    -AllRolesAtScope is used. Use -CommonRoles or -AllRolesAtScope instead of -Role to read the
    curated set or every role at the scope. Tab-completion offers the five curated common Azure RBAC
    roles; any other built-in or custom role name is still accepted.

    .PARAMETER CommonRoles
    For the RoleManagementPolicies section, read the curated common-role set (Reader, Contributor,
    Owner, User Access Administrator, Role Based Access Control Administrator) at the target scope
    instead of an explicit -Role list. Mutually exclusive with -Role and -AllRolesAtScope.

    .PARAMETER AllRolesAtScope
    For the RoleManagementPolicies section, read the policy for every role at the target scope from a
    single roleManagementPolicyAssignments list-for-scope call (one paged ARM list, not one lookup per
    role). Mutually exclusive with -Role and -CommonRoles.

    .PARAMETER AllDirectoryRolePolicies
    For the DirectoryRoleManagementPolicies section, export the policy of every Microsoft Entra
    directory role, instead of only the roles that have at least one row in the tenant-scope
    eligibility or assignment schedules. The schedules are then not read for the policy section at
    all; they are still read, once, when DirectoryRoleAssignments is included too.

    .PARAMETER IncludeId
    Stamp each top-level object with its id property (handy for same-tenant round-trips).

    .PARAMETER IncludeARM
    Acquire an ARM token and read the Azure sections. Forwarded to Initialize-OERAuth.

    .PARAMETER TenantId
    Optional tenant id or domain to authenticate against, forwarded to Initialize-OERAuth. The
    inventory's tenantId is the tenant ID the session's Microsoft Graph token was issued for, not this
    value.

    .EXAMPLE
    Get-OERInventory -Include Groups,Catalogs,AccessPackages
    Reads the core Entra ID building blocks into an inventory object.

    .EXAMPLE
    Get-OERInventory -Include RoleAssignments -Subscription 'Prod' -IncludeARM
    Reads the Azure role assignments at the Prod subscription.

    .EXAMPLE
    Get-OERInventory -Include RoleManagementPolicies -Subscription 'Prod' -CommonRoles -IncludeARM
    Reads the PIM policy for each curated common role on the Prod subscription into the inventory.

    .EXAMPLE
    Get-OERInventory -Include DirectoryRoleManagementPolicies, DirectoryRoleAssignments
    Reads the Microsoft Entra directory role assignments the apply engine manages, and the PIM policy
    of every directory role in use, through Microsoft Graph only.
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [ValidateSet('Groups', 'AdministrativeUnits', 'Catalogs', 'AccessPackages', 'AccessReviews',
            'DirectoryRoleManagementPolicies', 'DirectoryRoleAssignments', 'RoleAssignments', 'RoleManagementPolicies')]
        [string[]]$Include = @('Groups', 'AdministrativeUnits', 'Catalogs', 'AccessPackages'),

        [string]$GroupFilter,
        [string]$Catalog,
        [string]$AccessReviewFilter,
        [string]$Scope,
        [string]$Subscription,
        [string]$ManagementGroup,
        [string[]]$Role,
        [switch]$CommonRoles,
        [switch]$AllRolesAtScope,
        [switch]$AllDirectoryRolePolicies,
        [switch]$IncludeId,
        [switch]$IncludeARM,
        [ValidateNotNullOrEmpty()]
        [string]$TenantId
    )
    begin {
        $AuthParams = @{}
        if ($TenantId) { $AuthParams.TenantId = $TenantId }
        if ($IncludeARM) { $AuthParams.IncludeARM = $true }
        Initialize-OERAuth @AuthParams
        # BL-88 (A14): the tenant this inventory names, captured here under the session this command
        # signed in under, never read again where the document is assembled.
        $DocumentTenantId = Get-OERInventoryTenantId
    }
    process {
        $PrincipalNameCache = @{}   # per-invocation id -> name cache (Groups eligibility + AccessReviews reviewers)
        $Groups                 = [System.Collections.Generic.List[object]]::new()
        $AdministrativeUnits    = [System.Collections.Generic.List[object]]::new()
        $Catalogs               = [System.Collections.Generic.List[object]]::new()
        $AccessPackages         = [System.Collections.Generic.List[object]]::new()
        $AccessReviews          = [System.Collections.Generic.List[object]]::new()
        $DirectoryRoleManagementPolicies = [System.Collections.Generic.List[object]]::new()
        $DirectoryRoleAssignments        = [System.Collections.Generic.List[object]]::new()
        $RoleAssignments        = [System.Collections.Generic.List[object]]::new()
        $RoleManagementPolicies = [System.Collections.Generic.List[object]]::new()
        # Collections a section asked for and did not get back. An inventory document must never
        # state as a fact something the export failed to read (issue #76), so each entry here both
        # steers the projection below and feeds the InventoryPartial error at the end.
        $UnreadCollections = [System.Collections.Generic.List[string]]::new()
        # The distinct underlying failure messages behind those unread collections. The triples in
        # $UnreadCollections say WHICH collection is missing; only these say WHY -- and the reason
        # is what tells an operator to retry (429) rather than grant a scope (403). Get-OERGroup and
        # Get-OERAdministrativeUnit compose it into their per-collection records, and -ErrorAction
        # SilentlyContinue below keeps those records off the caller's stream, so without this the
        # cause would be discarded entirely. DEDUPLICATED: a throttle produces the identical message
        # for every affected group, and repeating it once per group would bury the signal.
        $UnreadCauses = [System.Collections.Generic.List[string]]::new()
        # The dedupe KEYS for the list above, and the count of distinct causes the cap dropped.
        # The dedupe used to compare whole messages and could therefore never fire: Get-OERGroup and
        # Get-OERAdministrativeUnit both interpolate the failing object's id into the message, so
        # seven units failing for one identical reason produced seven distinct strings (measured on a
        # live tenant). The key normalises that id away; the list still stores the FIRST full message
        # per key, so one concrete id survives as an example.
        $UnreadCauseKeys = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
        # Cap on the DISTINCT causes named in the InventoryPartial message. The module emits
        # twenty-three cause message shapes (group members, group owners, group PIM eligibility,
        # group PIM-in-use criterion, group PIM policy, AU members, AU scoped roles, directory role
        # eligibility schedules, directory role assignment schedules, directory role policies,
        # access package resource role bindings, catalog resources, the catalog resource-name map,
        # the catalog list, a catalog's package list, an access package's assignment policies, an
        # access review's access package name, an access review's assignment policy name, objects
        # not written because two of them share a name, the group list, the administrative unit
        # list, the access review list and an entry written as null because it has no name), so
        # twenty-three admits one of each
        # and a normal partial run is still reported in full; only a genuinely heterogeneous
        # large-tenant failure is truncated, and the dropped count is stated rather than silently
        # lost. Nothing is discarded either way -- every cause is written to the verbose stream as
        # it is seen. Raise this with the shape count when a twenty-fourth cause message is added, or
        # one shape starts crowding out another purely by ordering.
        $UnreadCauseCap = 23

        # Records one read-failure cause, normalised, deduplicated and capped. Local to this cmdlet
        # rather than repeated at the group and administrative-unit call sites, so the normalisation
        # rule has a single owner. -Target is the record's own TargetObject (the failing object's
        # id), which is why the normalisation needs no id-shaped pattern matching. The suppressed
        # count is derived at the end as $UnreadCauseKeys.Count - $UnreadCauses.Count, so this
        # function never has to write back through the enclosing scope.
        function Add-UnreadCause {
            param(
                [string]$Cause,
                [string]$Target
            )
            if ([string]::IsNullOrWhiteSpace($Cause)) { return }
            $Key = $Cause
            if (-not [string]::IsNullOrWhiteSpace($Target)) { $Key = $Key.Replace($Target, '<id>') }
            if (-not $UnreadCauseKeys.Add($Key)) { return }
            if ($UnreadCauses.Count -lt $UnreadCauseCap) { $UnreadCauses.Add($Cause) }
        }

        # A section whose LIST could not be read at all is written as [] (a top-level section is never null),
        # so the partial signal is the only thing that tells it from a tenant that has none. The key is the
        # section's own name, added once however many records the failed read produced. NotFound records and
        # foreign strays never reach this: the callers below skip them first.
        function Add-UnreadSection {
            param([string]$Key, [string]$Cause)
            Write-Verbose "Get-OERInventory: $Cause"
            Add-UnreadCause -Cause $Cause
            if (-not $UnreadCollections.Contains($Key)) { $UnreadCollections.Add($Key) }
        }

        # An entry the export can name by nothing the apply engine accepts is never written with an empty
        # name: '' is refused by the validator (A10) and would throw at apply. Its collection is written as
        # an explicit null instead -- the documented "leave untouched" signal -- and named here, the
        # mechanism an unread collection uses. -Path is the collection's own path ('<section>/<name>/<key>').
        function Add-NamelessCollection {
            param([string]$Path)
            $NamelessCause = "An entry of $Path has no name, and no object id the apply engine accepts, so the collection is written as null rather than with an empty name."
            Write-Verbose "Get-OERInventory: $NamelessCause"
            Add-UnreadCause -Cause $NamelessCause -Target $Path
            $UnreadCollections.Add($Path)
        }

        # Two live objects whose names match without regard to letter case would be two document entries
        # the validator refuses as a duplicate -- and the apply engine refuses an ambiguous name anyway, so
        # neither entry could be applied. Neither is written. Each such name is reported through
        # InventoryPartial (the unread entry is '<section>/<name>', the cause says why), so the document is
        # never mistaken for a full snapshot. A top-level entry left out of the document removes nothing:
        # Invoke-OERStructure prunes child collections only.
        #
        # -KeyOf must build the SAME key the validator (Test-OERStructureSchema) refuses a duplicate on,
        # or a pair the validator refuses is written. An access package is keyed '<catalog>|<name>'
        # there, so it is keyed that way here. -NameOf, when given, builds the name that is REPORTED
        # for an entry ('<catalog>/<name>', the path an operator reads); without it the key is the name.
        function Select-UniqueNamedEntry {
            param([object[]]$Entry, [string]$Section, [scriptblock]$KeyOf, [scriptblock]$NameOf)
            $Count = [System.Collections.Generic.Dictionary[string, int]]::new([System.StringComparer]::OrdinalIgnoreCase)
            foreach ($E in $Entry) {
                $K = [string](& $KeyOf $E)
                $Count[$K] = 1 + $(if ($Count.ContainsKey($K)) { $Count[$K] } else { 0 })
            }
            $Reported = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
            foreach ($E in $Entry) {
                $K = [string](& $KeyOf $E)
                if ($Count[$K] -gt 1) {
                    if ($Reported.Add($K)) {
                        $ReportedName = if ($NameOf) { [string](& $NameOf $E) } else { $K }
                        $Unread = "$Section/$ReportedName"
                        $UnreadCollections.Add($Unread)
                        $NameCause = "Two or more live objects share the name $Unread (compared without regard to letter case), " +
                            'so none of them is written: the apply engine refuses an ambiguous name.'
                        # Every cause is written to the verbose stream as it is seen, like at every other
                        # Add-UnreadCause site: this one is added last, so it is the first the cap drops.
                        Write-Verbose "Get-OERInventory: $NameCause"
                        Add-UnreadCause -Cause $NameCause -Target $Unread
                    }
                    continue
                }
                $E
            }
        }

        # Reads the display name of the access package or assignment policy an access review points
        # at, and returns it -- or the id, which is a safe reference and is what the document carries
        # whenever no name is to be had. Local to this cmdlet for the same reason as Add-UnreadCause:
        # the two lookups share one rule, and the rule needs the cause list and the unread collections.
        #
        # THE READ IS A TRANSPORT READ WITH THE NOT-FOUND CODES DECLARED, NOT A CALL TO
        # Get-OERAccessPackage / Get-OERAccessPackageAssignmentPolicy. Those cmdlets publish what they
        # catch, and -ErrorVariable is filled by the ENGINE before any catch runs, so a lookup through
        # them left about ten records per lookup in the caller's error variable -- identical for a
        # deleted package and for a 403 -- and nothing that told the two apart. Declaring the codes
        # makes a deleted package or policy an ANSWER: the wrapper returns a marker instead of raising,
        # so nothing is deposited anywhere. Measured offline against the real wrapper: 20 records
        # for a review whose package and policy were deleted through the two readers, 0 through this
        # read. A 403, an exhausted 429, a 5xx, or a not-found code that was not declared still
        # raises (and still leaves its own strays, which is acceptable: it is a real failure, and the
        # partial names it). -Uri is the by-id URI the two readers send, so no request shape is
        # introduced that was not already live.
        #
        # THE THREE OUTCOMES:
        #   a name       -> the name; an answer with no name in it (null or blank) -> the id, and
        #                   nothing is reported
        #   the marker   -> the id; a deleted package or policy is a fact about the review, so no
        #                   partial is added and no record is left
        #   a throw      -> the id; the record is scrubbed first, then the read is counted as unread
        #                   (the cause AND the collection), so the run ends in InventoryPartial
        function Get-AccessReviewReferenceName {
            param(
                [string]$Uri,
                [string[]]$NotFoundCode,
                [string]$Id,
                [string]$ReviewName,
                [string]$Part,
                [string]$Label
            )
            try {
                $Response = Invoke-OERGraphRequest -Uri $Uri -ExpectedErrorCode $NotFoundCode
            } catch {
                Remove-OERErrorRecord -Record $PSItem
                $LookupCause = "Could not read an access review's $Label name: $($PSItem.Exception.Message)"
                Write-Verbose "Get-OERInventory: $LookupCause"
                Add-UnreadCause -Cause $LookupCause -Target $Id
                $UnreadCollections.Add("accessReviews/$ReviewName/$Part")
                return $Id
            }
            if (@($Response.PSObject.TypeNames) -contains 'Omnicit.EntraRBAC.GraphExpectedError') { return $Id }
            # An answer that carries no name is no name: '' would be a DECLARED value, so it would
            # pass the schema and fail only at apply, where the id (a safe reference) applies cleanly.
            # Not a failed read either, so nothing is reported. Graph requires displayName, so this is
            # a guard against an odd body, not an expected path.
            $Name = [string]$Response.displayName
            if ([string]::IsNullOrWhiteSpace($Name)) { return $Id }
            return $Name
        }

        if ($Include -contains 'Groups') {
            $GroupParams = @{ IncludeMembers = $true; IncludePimEligibility = $true; IncludeOwners = $true }
            if ($GroupFilter) { $GroupParams.Filter = $GroupFilter } else { $GroupParams.Filter = 'securityEnabled eq true' }
            $GroupItems = @()
            # -ErrorAction SilentlyContinue + -ErrorVariable, not -ErrorAction Stop: Get-OERGroup now
            # writes a non-terminating error per group whose members, owners or eligibility read
            # failed, and Stop would abort the whole enumeration on the first one -- losing every
            # remaining group instead of losing one collection. The errors are inspected below, so
            # nothing is suppressed; SilentlyContinue here means "captured", not "ignored".
            $GroupReadErrors = $null
            # The try/catch still guards a genuinely TERMINATING failure of the whole read (auth,
            # a dead transport, an -ErrorAction Stop upstream); the inner loop handles the
            # NON-terminating per-group records. Both are needed: neither subsumes the other.
            try {
                $GroupItems = @(Get-OERGroup @GroupParams -ErrorAction SilentlyContinue -ErrorVariable GroupReadErrors)
                foreach ($GErr in @($GroupReadErrors)) {
                    if ($null -eq $GErr) { continue }
                    # No Remove-OERErrorRecord here: these records were WRITTEN deliberately by
                    # Get-OERGroup (which already scrubbed the raw transport record behind each one),
                    # not swallowed by a catch. Scrubbing a reported diagnostic would hide it.
                    if ($GErr.FullyQualifiedErrorId -like 'GroupNotFound*') { continue }
                    # Per-collection failures are accounted for at the projection below, where the
                    # affected group is known by name; only anything else warrants a section warning.
                    if ($GErr.FullyQualifiedErrorId -like 'GroupMemberReadFailed*' -or
                        $GErr.FullyQualifiedErrorId -like 'GroupOwnerReadFailed*' -or
                        $GErr.FullyQualifiedErrorId -like 'GroupPimEligibilityReadFailed*') {
                        # Keep the CAUSE. Get-OERGroup composed the transport reason into this
                        # message and it lives nowhere else once the record is dropped here.
                        $GroupCause = [string]$GErr.Exception.Message
                        Write-Verbose "Get-OERInventory: $GroupCause"
                        Add-UnreadCause -Cause $GroupCause -Target ([string]$GErr.TargetObject)
                        continue
                    }
                    # Warn only for a record Get-OERGroup itself PUBLISHED. -ErrorVariable is filled
                    # by the ENGINE and also collects records raised inside nested calls -- the Graph
                    # SDK's own, several of them empty, one of them the raw bearer-carrying request
                    # record -- even when an inner catch swallowed them. Warning on those produced
                    # eight spurious lines per failed read on a live tenant (about 72 in one run) and
                    # buried the real signal. A published record carries the calling cmdlet's name as
                    # a comma-separated segment of the FullyQualifiedErrorId; a stray does not.
                    # Filtering on the error id instead would need widening for every id ever added
                    # and would still admit every stray, so the test is the publisher, not the id.
                    # Membership, not a suffix match: Write-Error appends a further name when a
                    # record is republished, so the cmdlet's name is not always the last segment.
                    if (@(([string]$GErr.FullyQualifiedErrorId) -split ',') -contains 'Get-OERGroup') {
                        Write-Warning "Could not read groups: $($GErr.Exception.Message)"
                        # The warning stays; the section is ALSO counted unread, since the groups array
                        # below is [] whether the tenant has none or the list could not be read.
                        Add-UnreadSection -Key 'groups' -Cause "Could not read groups: $($GErr.Exception.Message)"
                    } else {
                        # Routed to verbose rather than dropped: a stray is still evidence when a read
                        # misbehaves, it just is not a section-level finding the operator must act on.
                        Write-Verbose ("Get-OERInventory: ignoring a foreign error record seen while reading groups " +
                            "($($GErr.FullyQualifiedErrorId)): $($GErr.Exception.Message)")
                    }
                }
            } catch {
                Remove-OERErrorRecord -Record $PSItem
                if ($PSItem.FullyQualifiedErrorId -notlike 'GroupNotFound*') {
                    Write-Warning "Could not read groups: $($PSItem.Exception.Message)"
                    Add-UnreadSection -Key 'groups' -Cause "Could not read groups: $($PSItem.Exception.Message)"
                }
            }
            # Project one access-type policy object from a Get-OERGroupPimPolicy result, or $null when
            # the group carries no policy for that access type. The block is emitted whenever ANY
            # meaningful field is present -- gating it on activationMaxHours alone used to discard a
            # policy that was customized only for permanence, expiration, enablement or notifications.
            function Convert-PimAccessProjection {
                param([object]$Policy)
                if (-not $Policy) { return $null }
                $Block = [ordered]@{}
                if ($null -ne $Policy.ActivationMaxHours) { $Block.activationMaxHours = $Policy.ActivationMaxHours }
                if ($Policy.AuthenticationContextId) { $Block.authenticationContextId = $Policy.AuthenticationContextId }
                # ConvertTo-OERGroupPimPolicy wraps ActivationEnabledRules/ActiveEnabledRules with a
                # null-filter (its own comment at ConvertTo-OERGroupPimPolicy.ps1:67-73), so a rule
                # the tenant never configured and a rule that is genuinely empty BOTH read back as
                # @() here -- $null -ne cannot tell "unread" from "read and empty" on these two
                # properties, and neither can Count -gt 0 alone. Fall back to the raw rule set
                # carried on Rules: when the canonical rule id IS present the policy was actually
                # read and the list is genuinely empty, so emit an explicit [] (security-relevant:
                # no MFA, justification or ticket is required on activation). When the rule id is
                # absent too, the policy never carried it -- omit, same as before.
                $HasActivationRule = @($Policy.Rules |
                    Where-Object { $_.id -eq 'Enablement_EndUser_Assignment' }).Count -gt 0
                if (@($Policy.ActivationEnabledRules).Count -gt 0 -or $HasActivationRule) {
                    $Block.activationEnablement = @($Policy.ActivationEnabledRules)
                }
                if ($null -ne $Policy.AllowPermanentEligibility) { $Block.allowPermanentEligibility = [bool]$Policy.AllowPermanentEligibility }
                if ($Policy.EligibleDurationDays) { $Block.eligibleDurationDays = [int]$Policy.EligibleDurationDays }
                if ($null -ne $Policy.AllowPermanentActive) { $Block.allowPermanentActive = [bool]$Policy.AllowPermanentActive }
                if ($Policy.ActiveDurationDays) { $Block.activeDurationDays = [int]$Policy.ActiveDurationDays }
                $HasActiveRule = @($Policy.Rules |
                    Where-Object { $_.id -eq 'Enablement_Admin_Assignment' }).Count -gt 0
                if (@($Policy.ActiveEnabledRules).Count -gt 0 -or $HasActiveRule) {
                    $Block.activeEnablement = @($Policy.ActiveEnabledRules)
                }
                if ($null -ne $Policy.RequireApproval) { $Block.requireApproval = [bool]$Policy.RequireApproval }
                # Approvers project as object ids, the same as the roleManagementPolicies projection:
                # an id resolves verbatim through the apply engine's declared-approver resolution,
                # whereas a display name may not. Exported only while approval is required, since the
                # apply engine ignores declared approvers whenever requireApproval is false and
                # Test-OERStructureSchema would otherwise warn about that combination on every
                # exported document that carries an approval-gated policy.
                if ($Policy.RequireApproval -eq $true) {
                    $PimApproverUser  = @(@($Policy.Approvers) | Where-Object { $_ -and [string]$_.UserType -eq 'User' } | ForEach-Object { [string]$_.Id } | Where-Object { $_ })
                    $PimApproverGroup = @(@($Policy.Approvers) | Where-Object { $_ -and [string]$_.UserType -eq 'Group' } | ForEach-Object { [string]$_.Id } | Where-Object { $_ })
                    if ($PimApproverUser.Count -gt 0 -or $PimApproverGroup.Count -gt 0) {
                        $PimApproverProj = [ordered]@{}
                        if ($PimApproverUser.Count -gt 0)  { $PimApproverProj.users = $PimApproverUser }
                        if ($PimApproverGroup.Count -gt 0) { $PimApproverProj.groups = $PimApproverGroup }
                        $Block.approvers = [PSCustomObject]$PimApproverProj
                    }
                }
                $Notif = [ordered]@{}
                if ($Policy.Notifications) {
                    if (@($Policy.Notifications.EligibleAlert).Count -gt 0)   { $Notif.eligibleAlert = @($Policy.Notifications.EligibleAlert) }
                    if (@($Policy.Notifications.ActiveAlert).Count -gt 0)     { $Notif.activeAlert = @($Policy.Notifications.ActiveAlert) }
                    if (@($Policy.Notifications.ActivationAlert).Count -gt 0) { $Notif.activationAlert = @($Policy.Notifications.ActivationAlert) }
                }
                if ($Notif.Count -gt 0) { $Block.notifications = [PSCustomObject]$Notif }
                if ($Block.Count -eq 0) { return $null }
                [PSCustomObject]$Block
            }

            foreach ($G in $GroupItems) {
                $Proj = [ordered]@{
                    displayName    = $G.DisplayName
                    roleAssignable = [bool]$G.IsAssignableToRole
                    dynamic        = ($G.GroupType -eq 'Dynamic')
                    description    = $G.Description
                }
                if ($G.GroupType -eq 'Dynamic') {
                    $Proj.membershipRule = $G.MembershipRule
                    if ($G.MembershipRuleProcessingState) {
                        $Proj.membershipRuleProcessingState = [string]$G.MembershipRuleProcessingState
                    }
                }
                # mailNickname is writable on create AND diffed on update by the apply engine, so it
                # must be readable here or a custom nickname is silently replaced by the Graph-generated
                # one on the next round-trip. Emitted only when set, so a document for a group without
                # one stays clean and the apply leaves it untouched.
                if ($G.MailNickname) { $Proj.mailNickname = [string]$G.MailNickname }
                if ($IncludeId) { $Proj.id = $G.Id }
                # An OMITTED members key still reconciles in the apply engine and still prunes under
                # -Prune (Get-OERStructureSchemaJson: "An omitted key still reconciles"), so omitting
                # it here would leave issue #76's chain wide open. An EXPLICIT null is the schema's
                # documented "leave membership untouched" signal, and that is what an unread
                # membership has to be.
                if ($G.PSObject.Properties.Name -contains 'Members') {
                    # Project each member as a reference the apply engine can resolve back to its object id:
                    # a user as its userPrincipalName (friendly and resolvable), and every other member type
                    # (group, device, service principal, ...) as its object id, which Resolve-OERStructurePrincipal
                    # returns verbatim. A member display name is NOT resolvable (it is not a UPN), so it is only a
                    # last-resort fallback when neither a UPN nor an id is present.
                    $Proj.members = @(foreach ($M in @($G.Members)) {
                        if (-not $M) { continue }
                        if ($M.userPrincipalName) { [string]$M.userPrincipalName }
                        elseif ($M.id)            { [string]$M.id }
                        else                      { [string]$M.displayName }
                    })
                } else {
                    $Proj.members = $null
                    $UnreadCollections.Add("groups/$($G.DisplayName)/members")
                }
                if ($G.PSObject.Properties.Name -contains 'Owners') {
                    # Owners are writable through Add-/Remove-OERGroupMember -AccessType owner and a group
                    # owner can add members, so an unprojected owner is a privilege path that disappears from
                    # the captured posture. Emitted only when the group has any, so a document for an
                    # owner-less group stays clean and the apply leaves owners untouched.
                    $OwnerRefs = @(foreach ($O in @($G.Owners)) {
                        if (-not $O) { continue }
                        if ($O.userPrincipalName) { [string]$O.userPrincipalName }
                        elseif ($O.id)            { [string]$O.id }
                        else                      { [string]$O.displayName }
                    })
                    if ($OwnerRefs.Count -gt 0) { $Proj.owners = $OwnerRefs }
                } else {
                    # An omitted owners key is ALREADY never reconciled or pruned, so omission is the
                    # correct hands-off form here -- no explicit null needed. The read failure is
                    # still accounted for, so the document is not silently short an owner set.
                    $UnreadCollections.Add("groups/$($G.DisplayName)/owners")
                }
                if ($G.PSObject.Properties.Name -contains 'PimEligibility') {
                    $EligIds = @(@($G.PimEligibility) | ForEach-Object { [string]$_.principalId } | Where-Object { $_ })
                    $MissingEligIds = @($EligIds | Where-Object { -not $PrincipalNameCache.ContainsKey($_) } | Select-Object -Unique)
                    if ($MissingEligIds.Count -gt 0) {
                        $Resolved = Resolve-OERPrincipalName -Id $MissingEligIds
                        foreach ($K in $Resolved.Keys) { $PrincipalNameCache[$K] = $Resolved[$K] }
                    }
                    # Project each eligibility so a re-apply reproduces it faithfully: accessType is always
                    # emitted (member or owner) and durationDays is emitted only for a time-bound window --
                    # its absence is how the apply document expresses a permanent eligibility.
                    $Proj.eligibility = @(foreach ($E in @($G.PimEligibility)) {
                        if (-not $E) { continue }
                        $PrincipalId = [string]$E.principalId
                        $Name = if ($PrincipalNameCache.ContainsKey($PrincipalId)) { $PrincipalNameCache[$PrincipalId] } else { $PrincipalId }
                        $EligProj = [ordered]@{ principal = $Name }
                        $EligProj.accessType = $(if ($E.accessId) { [string]$E.accessId } else { 'member' })
                        $EligDays = Resolve-OEREligibilityDuration -StartDateTime $E.startDateTime -EndDateTime $E.endDateTime
                        if ($null -ne $EligDays) { $EligProj.durationDays = [int]$EligDays }
                        if ($IncludeId) { $EligProj.id = $PrincipalId }
                        [PSCustomObject]$EligProj
                    })
                } else {
                    # Same as owners: an omitted OR explicitly null eligibility key is never reconciled
                    # or pruned, so omission is already hands-off. No principal-name lookup is issued
                    # for a collection that was never read.
                    $UnreadCollections.Add("groups/$($G.DisplayName)/eligibility")
                }

                $MemberPim = $null
                $OwnerPim  = $null
                # ASK FIRST WHETHER THE GROUP USES PIM FOR GROUPS AT ALL. Microsoft Graph lists
                # PIM-for-Groups policies for every group, including one never used with PIM for
                # Groups (measured live 2026-09-28), so reading and exporting them used to put a
                # default pimPolicy on EVERY group -- and a proposal that changes one of those blocks
                # onboards the group on apply, which cannot be undone (Microsoft Graph documentation,
                # "Onboarding groups to PIM for Groups"). Test-OERGroupPimInUse owns the rule: the
                # eligibility this section already read, or one listing of the group's policies for a
                # modified one (docs/development/rationale.md#pim-in-use-criterion, ruling R2). A group
                # the criterion does not find in use gets no pimPolicy key and none of the four reads
                # below. A criterion that could not be read is never guessed in either direction:
                # pimPolicy is omitted AND the collection is reported unread, with its cause, exactly
                # like a failed policy read. The null-filter on the count is load-bearing:
                # @($null).Count is 1.
                $EligibilityRead = $G.PSObject.Properties.Name -contains 'PimEligibility'
                $EligCount = if ($EligibilityRead) {
                    @($G.PimEligibility | Where-Object { $null -ne $_ }).Count
                } else { 0 }
                $Usage = $null
                try {
                    $Usage = Test-OERGroupPimInUse -GroupId $G.Id -EligibilityCount $EligCount
                } catch {
                    Remove-OERErrorRecord -Record $PSItem
                    $CriterionCause = "Could not determine whether group '$($G.Id)' uses PIM for Groups: $($PSItem.Exception.Message)"
                    Write-Verbose "Get-OERInventory: $CriterionCause"
                    Add-UnreadCause -Cause $CriterionCause -Target ([string]$G.Id)
                    $UnreadCollections.Add("groups/$($G.DisplayName)/pimPolicy")
                    $Usage = $null
                }
                $PimInUse = ($null -ne $Usage -and [bool]$Usage.InUse)
                if ($null -ne $Usage -and -not $PimInUse) {
                    if ($EligibilityRead) {
                        Write-Verbose "Get-OERInventory: group '$($G.DisplayName)': pimPolicy not exported -- $($Usage.Reason)."
                    } else {
                        # HALF AN ANSWER. The eligibility read failed, so the count above was 0 by
                        # default, not by measurement: "not in use" was decided on the policies alone
                        # and is a guess. pimPolicy is omitted and reported unread too. The eligibility
                        # read's own cause is already on the cause list (it is what omitted
                        # PimEligibility), so this adds the COLLECTION only, never a second cause. A
                        # modified policy, by contrast, decides "in use" on its own and never gets here.
                        Write-Verbose "Get-OERInventory: group '$($G.DisplayName)': pimPolicy not exported and not decided -- $($Usage.Reason), and its PIM eligibility could not be read."
                        $UnreadCollections.Add("groups/$($G.DisplayName)/pimPolicy")
                    }
                }

                # ASK NEXT WHETHER THERE IS A POLICY AT ALL, rather than reading one and swallowing
                # the answer. For a group whose policy Graph does not list (an empty assignments
                # collection, or 400 ResourceTypeNotSupported) Get-OERGroupPimPolicy correctly
                # reports a non-terminating PimPolicyNotFound -- which -ErrorAction Stop turns into
                # TWO records per call, four per group, in the CALLER's -ErrorVariable. That
                # collection is filled by the ENGINE from the error stream, so neither the catch
                # below nor any other catch in this module can reach those records: the only way not
                # to have them is not to provoke them. Measured offline on 100 groups, 96 of them
                # answering with no listed policy, driving the real wrapper and the real cmdlets with
                # only the transport stubbed: 384 records for an entirely clean read -- it does not
                # depend on whether the assignments call answers 200-empty or 400, since
                # Get-OERPimGroupPolicyId returns $null either way. A group the criterion above does
                # not find to use PIM for Groups (no PIM eligibility and no modified policy) never
                # gets this far: Graph lists a group's policies before it is onboarded (measured live
                # 2026-09-28), which is exactly why the criterion runs first, and a group it does not
                # find in use -- or could not decide -- makes none of the four calls below and
                # carries no pimPolicy. That finding is the criterion's, not a measured fact about
                # the tenant: a group used only through PIM ACTIVE assignments, with untouched
                # policies, is not found in use either (rationale.md#pim-in-use-criterion).
                #
                # NOT -ErrorAction Ignore on the reads below. That would silence a genuine 403 or 429
                # along with the not-listed case and leave the operator with a document quietly
                # missing PIM policy it had no permission to read. Get-OERPimGroupPolicyId declares
                # ResourceTypeNotSupported to the transport, so it comes back as a silent $null with
                # nothing raised anywhere, while every OTHER failure still throws.
                # A throw here is therefore NOT an answer: the read runs anyway and reports through
                # the path below. Only a confident $null skips it.
                #
                # AND THE PATH BELOW HAS TO TELL THE TWO APART, which is the whole point of the pair
                # of ids Get-OERGroupPimPolicy now emits. Suppressing PimPolicyNotFound is right --
                # a policy Graph does not list is not a finding -- but the same cmdlet used to
                # answer PimPolicyNotFound for a refusal as well, so this suppression swallowed the
                # refusal with it. Measured: a 403 on the policy-id lookup for 96 of 100 groups
                # produced 0 error records, 0 warnings, and pimPolicy absent from all 96 -- an
                # inventory that looked complete and was not, issue #76's defect class in a new
                # place. A failure now arrives as PimPolicyReadFailed and is accounted for exactly
                # like a failed members, owners or eligibility read: the CAUSE to verbose and the
                # deduplicated cause list, the COLLECTION to $UnreadCollections, and the run ends in
                # the InventoryPartial error that names it -- which Export-OERInventory in turn folds
                # into the bundle's IncompleteReads. No per-group warning, for the reason stated at
                # the enumeration loop above: a per-collection failure is reported at the projection,
                # where the group is known by name, and 96 refused groups would otherwise print 192
                # near-identical lines and bury the one signal an operator can act on.
                #
                # pimPolicy stays OMITTED for that access type either way, never present and empty --
                # exactly as Get-OERGroup omits PimEligibility on a failed read.
                $ReadMemberPim = $false
                $ReadOwnerPim  = $false
                if ($PimInUse) {
                    $ReadMemberPim = $true
                    $ReadOwnerPim  = $true
                    try { $ReadMemberPim = [bool](Get-OERPimGroupPolicyId -GroupId $G.Id -AccessType member) }
                    catch { Remove-OERErrorRecord -Record $PSItem; $ReadMemberPim = $true }
                    try { $ReadOwnerPim = [bool](Get-OERPimGroupPolicyId -GroupId $G.Id -AccessType owner) }
                    catch { Remove-OERErrorRecord -Record $PSItem; $ReadOwnerPim = $true }
                }
                foreach ($PimAccessType in @('member', 'owner')) {
                    if ($PimAccessType -eq 'member' -and -not $ReadMemberPim) { continue }
                    if ($PimAccessType -eq 'owner' -and -not $ReadOwnerPim) { continue }
                    try {
                        $PimRead = Get-OERGroupPimPolicy -Id $G.Id -AccessType $PimAccessType -ErrorAction Stop
                        if ($PimAccessType -eq 'member') { $MemberPim = $PimRead } else { $OwnerPim = $PimRead }
                    } catch {
                        Remove-OERErrorRecord -Record $PSItem
                        if ($PSItem.FullyQualifiedErrorId -like 'PimPolicyNotFound*') { continue }
                        # Keep the CAUSE. Get-OERGroupPimPolicy composed the transport reason into
                        # this message and it lives nowhere else once the record is dropped here.
                        $PimCause = [string]$PSItem.Exception.Message
                        Write-Verbose "Get-OERInventory: $PimCause"
                        $UnreadCollections.Add("groups/$($G.DisplayName)/pimPolicy/$PimAccessType")
                        Add-UnreadCause -Cause $PimCause -Target ([string]$G.Id)
                    }
                }
                $MemberProj = Convert-PimAccessProjection -Policy $MemberPim
                $OwnerProj  = Convert-PimAccessProjection -Policy $OwnerPim
                if ($MemberProj -or $OwnerProj) {
                    $PimProj = [ordered]@{}
                    if ($MemberProj) { $PimProj.member = $MemberProj }
                    if ($OwnerProj)  { $PimProj.owner = $OwnerProj }
                    $Proj.pimPolicy = [PSCustomObject]$PimProj
                }
                $Groups.Add([PSCustomObject]$Proj)
            }
        }

        if ($Include -contains 'AdministrativeUnits') {
            $AuItems = @()
            # Same shape as the group read above: Get-OERAdministrativeUnit now writes a
            # non-terminating error per unit whose members or scoped-role read failed, and
            # -ErrorAction Stop would abort the whole enumeration on the first one. The records
            # are inspected below rather than discarded.
            $AuReadErrors = $null
            try {
                $AuItems = @(Get-OERAdministrativeUnit -IncludeMembers -IncludeScopedRoles -ErrorAction SilentlyContinue -ErrorVariable AuReadErrors)
                foreach ($AErr in @($AuReadErrors)) {
                    if ($null -eq $AErr) { continue }
                    if ($AErr.FullyQualifiedErrorId -like 'AdministrativeUnitNotFound*') { continue }
                    # Per-collection failures are accounted for at the projection below, where the
                    # affected unit is known by name; only anything else warrants a section warning.
                    if ($AErr.FullyQualifiedErrorId -like 'AdministrativeUnitMemberReadFailed*' -or
                        $AErr.FullyQualifiedErrorId -like 'AdministrativeUnitScopedRoleReadFailed*') {
                        # Keep the CAUSE, same reasoning as the group loop above.
                        $AuCause = [string]$AErr.Exception.Message
                        Write-Verbose "Get-OERInventory: $AuCause"
                        Add-UnreadCause -Cause $AuCause -Target ([string]$AErr.TargetObject)
                        continue
                    }
                    # Same publisher test as the group loop above, and for the same measured reason:
                    # seven failing units produced 56 section-level warnings, 49 of them foreign
                    # records the engine had collected from nested calls. See that comment for why
                    # the PUBLISHER named in the FullyQualifiedErrorId, not the error id, is the
                    # discriminator.
                    if (@(([string]$AErr.FullyQualifiedErrorId) -split ',') -contains 'Get-OERAdministrativeUnit') {
                        Write-Warning "Could not read administrative units: $($AErr.Exception.Message)"
                        # Counted unread as well as warned, for the same reason as the groups read above.
                        Add-UnreadSection -Key 'administrativeUnits' -Cause "Could not read administrative units: $($AErr.Exception.Message)"
                    } else {
                        Write-Verbose ("Get-OERInventory: ignoring a foreign error record seen while reading " +
                            "administrative units ($($AErr.FullyQualifiedErrorId)): $($AErr.Exception.Message)")
                    }
                }
            } catch {
                Remove-OERErrorRecord -Record $PSItem
                if ($PSItem.FullyQualifiedErrorId -notlike 'AdministrativeUnitNotFound*') {
                    Write-Warning "Could not read administrative units: $($PSItem.Exception.Message)"
                    Add-UnreadSection -Key 'administrativeUnits' -Cause "Could not read administrative units: $($PSItem.Exception.Message)"
                }
            }
            foreach ($Au in $AuItems) {
                $Proj = [ordered]@{
                    displayName = $Au.DisplayName
                    description = $Au.Description
                    restricted  = [bool]$Au.IsMemberManagementRestricted
                }
                # Dynamic membership and hidden membership are writable on New/Set-OERAdministrativeUnit,
                # so project them or a re-applied inventory silently degrades a dynamic unit to static
                # and a HiddenMembership unit to public. membershipRule/processing state are meaningless
                # on an assigned unit, so they are emitted only for a dynamic one.
                $Proj.dynamic = ([string]$Au.MembershipType -eq 'Dynamic')
                if ($Proj.dynamic) {
                    $Proj.membershipRule = $Au.MembershipRule
                    if ($Au.MembershipRuleProcessingState) {
                        $Proj.membershipRuleProcessingState = [string]$Au.MembershipRuleProcessingState
                    }
                }
                $Proj.hiddenMembership = ([string]$Au.Visibility -eq 'HiddenMembership')
                if ($IncludeId) { $Proj.id = $Au.Id }
                # A dynamic unit's membership is rule-derived, so projecting it produces a member list
                # the apply handler can only skip. Omit it, matching membershipRule above.
                if (-not $Proj.dynamic) {
                    if ($Au.PSObject.Properties.Name -contains 'Members') {
                        # Same rule as group members: a user as its UPN (resolvable + friendly), every other
                        # member type as its object id (which the apply resolves verbatim); display name is
                        # not resolvable so it is only a last-resort fallback.
                        $Proj.members = @(foreach ($M in @($Au.Members)) {
                            if (-not $M) { continue }
                            if ($M.UserPrincipalName) { [string]$M.UserPrincipalName }
                            elseif ($M.Id)            { [string]$M.Id }
                            else                      { [string]$M.DisplayName }
                        })
                    } else {
                        # Explicit null, not an omitted key: an omitted administrativeUnits[].members
                        # key still reconciles and still prunes.
                        $Proj.members = $null
                        $UnreadCollections.Add("administrativeUnits/$($Au.DisplayName)/members")
                    }
                }
                if ($Au.PSObject.Properties.Name -contains 'ScopedRoles') {
                    # Scoped-role principals project as the object id: the Graph scopedRoleMembership carries
                    # no UPN for the role member, and the id resolves verbatim (a display name does not).
                    # The role projects as its friendly name when the directory-role name map has one for
                    # it, and otherwise falls back to the role id -- emitting role:null would fail schema
                    # validation and make the unit un-appliable. A role name that is only whitespace counts
                    # as missing, so it falls back to the role id too. A name map that could not be READ at all
                    # never gets here: Get-OERAdministrativeUnit then omits ScopedRoles, and the branch
                    # below reports it unread. A role or principal that is STILL blank after those
                    # fallbacks cannot be written either (an empty name is refused by the validator), so
                    # the collection is written as an explicit null and named, never with an empty name.
                    $SrNameless = $false
                    $SrProjected = @(foreach ($S in @($Au.ScopedRoles)) {
                        if (-not $S) { continue }
                        $SrPrincipal = if ($S.PrincipalId) { [string]$S.PrincipalId } else { [string]$S.PrincipalDisplayName }
                        $SrRole = if (-not [string]::IsNullOrWhiteSpace([string]$S.RoleName)) { [string]$S.RoleName } else { [string]$S.RoleId }
                        if ([string]::IsNullOrWhiteSpace($SrRole) -or [string]::IsNullOrWhiteSpace($SrPrincipal)) {
                            $SrNameless = $true
                            continue
                        }
                        [PSCustomObject]@{ role = $SrRole; principal = $SrPrincipal }
                    })
                    if ($SrNameless) {
                        $Proj.scopedRoles = $null
                        Add-NamelessCollection -Path "administrativeUnits/$($Au.DisplayName)/scopedRoles"
                    } else {
                        $Proj.scopedRoles = $SrProjected
                    }
                } else {
                    # Explicit null for the same reason as members: an omitted scopedRoles key prunes.
                    $Proj.scopedRoles = $null
                    $UnreadCollections.Add("administrativeUnits/$($Au.DisplayName)/scopedRoles")
                }
                $AdministrativeUnits.Add([PSCustomObject]$Proj)
            }
        }

        # Both the Catalogs and AccessPackages sections filter by the same -Catalog value and need
        # catalog OBJECTS (DisplayName/Description/Id read below), not a bare id -- Resolve-OERCatalogId
        # returns only a [string] id and cannot substitute here. Resolve once so the default -Include
        # (which contains both sections) does not issue the catalog list/read call twice.
        $ResolvedCatalogList = $null
        # The CURRENT display name of each Group and Application resource of a catalog, keyed by
        # originId: a catalog keeps the name a resource had when it was added, also after the group or
        # application is renamed (measured live 2026-09-30), and the apply engine identifies a Group or
        # Application resource by the object id its declared name resolves to. One getByIds call per
        # catalog through Resolve-OERPrincipalName, shared by both sections; an object the directory
        # does not return (deleted, unreadable, or a failed call) falls back to its id, which the apply
        # engine takes as the object id itself.
        $CatalogResourceNames = @{}
        $GetCatalogResourceNames = {
            param([string]$ForCatalogId, [object[]]$Resources)
            if (-not $CatalogResourceNames.ContainsKey($ForCatalogId)) {
                $Ids = @($Resources | Where-Object { [string]$_.OriginSystem -in @('AadGroup', 'AadApplication') -and $_.OriginId } |
                        ForEach-Object { [string]$_.OriginId })
                $CatalogResourceNames[$ForCatalogId] = if ($Ids.Count -gt 0) { Resolve-OERPrincipalName -Id $Ids -PreferDisplayName } else { @{} }
            }
            $CatalogResourceNames[$ForCatalogId]
        }
        if ($Include -contains 'Catalogs' -or $Include -contains 'AccessPackages') {
            # A catalog list that could not be read leaves BOTH sections empty, which is what the
            # document has always said. No handler removes a catalog or an access package that is
            # absent from the document ("Prune is child-scope only", Invoke-OERStructure), so the
            # projection stays as it was -- but an absent entry is not a fact, so the failure is
            # reported through InventoryPartial for every section that needed the list. Before this
            # the read had no error handling: under a caller's Stop it ended the whole call with no
            # document at all, and under Continue it left one stray record and no partial.
            # The one exception is a FACT about the caller's own -Catalog filter rather than a gap in
            # the export (spec G3: only a null from a name search, or a 404 on an id, is NotFound):
            # a missing catalog id is answered by Graph with CatalogNotFound (measured live,
            # 2026-10-02), which Get-OERCatalog republishes by id, so that arm is the one that fires
            # in production. It, AmbiguousCatalogName and the module's generic not-found codes on a
            # by-id read are all facts about the caller's filter; by name a non-match returns
            # nothing at all. Such a record is republished as itself and counted as nothing. A 404
            # on a NAME or on the unfiltered list is not a missing object, so it stays unread.
            try {
                $ResolvedCatalogList = if ($Catalog) {
                    if ($Catalog -as [guid]) { @(Get-OERCatalog -Id $Catalog -ErrorAction Stop) } else { @(Get-OERCatalog -DisplayName $Catalog -ErrorAction Stop) }
                } else { @(Get-OERCatalog -ErrorAction Stop) }
            } catch {
                Remove-OERErrorRecord -Record $PSItem
                # The module's own not-found vocabulary (Get-OERAccessReviewInstance). Every comma
                # separated segment of the id is compared WHOLE, never as a prefix, since a composed
                # id ('ResourceNotFound,Get-OERCatalog') can carry the code outside the first slot.
                $CatListIdSegment = @(([string]$PSItem.FullyQualifiedErrorId) -split ',' | ForEach-Object { $_.Trim() })
                $CatListByIdNotFound = $Catalog -and ($null -ne ($Catalog -as [guid])) -and
                    (@($CatListIdSegment | Where-Object { $_ -in @('ResourceNotFound', 'Request_ResourceNotFound', 'ItemNotFound', 'NotFound') }).Count -gt 0)
                if ($PSItem.FullyQualifiedErrorId -like 'CatalogNotFound*' -or $PSItem.FullyQualifiedErrorId -like 'AmbiguousCatalogName*' -or $CatListByIdNotFound) {
                    $PSCmdlet.WriteError($PSItem)
                } else {
                    $CatListCause = "Could not read the catalogs: $($PSItem.Exception.Message)"
                    Write-Verbose "Get-OERInventory: $CatListCause"
                    Add-UnreadCause -Cause $CatListCause -Target ([string]$Catalog)
                    if ($Include -contains 'Catalogs') { $UnreadCollections.Add('catalogs') }
                    if ($Include -contains 'AccessPackages') { $UnreadCollections.Add('accessPackages') }
                }
                $ResolvedCatalogList = @()
            }
        }

        if ($Include -contains 'Catalogs') {
            foreach ($Cat in $ResolvedCatalogList) {
                $Proj = [ordered]@{
                    displayName       = $Cat.DisplayName
                    description       = $Cat.Description
                    # Cheap deterministic boolean -- always emitted, exactly like the administrative
                    # unit's restricted flag, so a catalog whose access packages are requestable by
                    # connected-organization users never silently re-creates as internal-only.
                    externallyVisible = [bool]$Cat.ExternallyVisible
                }
                if ($IncludeId) { $Proj.id = $Cat.Id }
                # A FAILED read is never projected as []: under -Prune an empty declared resource set
                # removes every resource of the catalog, and an omitted key still reconciles the same
                # way. An explicit null is the documented "leave the resources untouched" signal.
                # Before this, the read had no error handling at all: its record reached the caller's
                # stream, but the document still said "resources": [] and no InventoryPartial named it.
                # The shared name map is consulted only for a catalog that WAS read, so a failure never
                # caches an empty map for the access package section to reuse (see below).
                $CatRes = $null
                try {
                    $CatRes = @(Get-OERCatalogResource -Catalog $Cat.Id -ErrorAction Stop)
                } catch {
                    Remove-OERErrorRecord -Record $PSItem
                    $CatResCause = "Could not read a catalog's resources: $($PSItem.Exception.Message)"
                    Write-Verbose "Get-OERInventory: $CatResCause"
                    Add-UnreadCause -Cause $CatResCause -Target ([string]$Cat.Id)
                    $UnreadCollections.Add("catalogs/$($Cat.DisplayName)/resources")
                    $CatRes = $null
                }
                if ($null -eq $CatRes) {
                    $Proj.resources = $null
                } else {
                    $CurrentNames = & $GetCatalogResourceNames ([string]$Cat.Id) $CatRes
                    $CatResNameless = $false
                    $CatResProjected = @(foreach ($R in $CatRes) {
                        # Map the resource type to the schema enum from the stable originSystem (the raw
                        # Graph resourceType is a display label, e.g. 'SharePoint Online Site', that the
                        # schema/apply do not accept). Falls back to the raw value for unknown systems.
                        $ResType = switch ($R.OriginSystem) {
                            'AadGroup'         { 'Group' }
                            'AadApplication'   { 'Application' }
                            'SharePointOnline' { 'SharePointSite' }
                            default            { $R.ResourceType }
                        }
                        # A SharePoint Online site is onboarded by its URL, which Graph stores as the
                        # resource originId -- the display name is only the site title and cannot be fed
                        # back into Add-OERCatalogResource -SharePointSite. Emit the URL as a distinct
                        # 'url' field so the apply engine has the real identifier while the human-readable
                        # name is preserved. A Group or Application resource is written under the group's
                        # or application's CURRENT name (looked up by originId, the id when it cannot be),
                        # never the name the catalog recorded when it was added.
                        $ResName = if ([string]$R.OriginSystem -in @('AadGroup', 'AadApplication') -and $R.OriginId -and $CurrentNames.ContainsKey([string]$R.OriginId)) {
                            $CurrentNames[[string]$R.OriginId]
                        } else {
                            $R.DisplayName
                        }
                        # A resource whose name is blank is written under its origin id when it has one
                        # (a site URL, or a group's or application's object id -- the validator accepts
                        # both as a name and the apply engine resolves them), since an empty name is
                        # refused. With no origin id either it cannot be named at all: see below.
                        if ([string]::IsNullOrWhiteSpace([string]$ResName) -and $R.OriginId) { $ResName = [string]$R.OriginId }
                        if ([string]::IsNullOrWhiteSpace([string]$ResName)) {
                            $CatResNameless = $true
                            continue
                        }
                        $ResProj = [ordered]@{ type = $ResType; name = $ResName }
                        if ($ResType -eq 'SharePointSite' -and $R.OriginId) {
                            $ResProj.url = [string]$R.OriginId
                        }
                        [PSCustomObject]$ResProj
                    })
                    if ($CatResNameless) {
                        # All or nothing, as for an unread set: a declared set that quietly left the
                        # unnamed resource out would have -Prune remove it. An explicit null is the
                        # documented "leave the resources untouched" signal.
                        $Proj.resources = $null
                        Add-NamelessCollection -Path "catalogs/$($Cat.DisplayName)/resources"
                    } else {
                        $Proj.resources = $CatResProjected
                    }
                }
                $Catalogs.Add([PSCustomObject]$Proj)
            }
        }

        if ($Include -contains 'AccessPackages') {
            # On v1.0 the accessPackage resource has no catalogId scalar -- catalog is a relationship
            # that a plain list does not return -- so iterate catalogs and read each catalog's packages.
            # This yields the catalog DISPLAY NAME for each package (round-trippable: New-OERAccessPackage
            # -Catalog and the schema's catalogs[].displayName cross-reference both take the name).
            # $ResolvedCatalogList is hoisted above (shared with the Catalogs section) so an unqualified
            # Get-OERInventory does not resolve the -Catalog filter twice.
            foreach ($ApCat in $ResolvedCatalogList) {
                # Build an OriginId -> resource display-name map ONCE per catalog. A resource role
                # binding's scope carries the resource OriginId plus a scope LABEL (commonly 'Root'
                # for the whole-resource scope) -- not the resource name. The apply engine resolves
                # the binding's resource against Get-OERCatalogResource display names, so project that
                # same name here (joined on OriginId) instead of the scope label, or the binding will
                # not round-trip.
                # A Group or Application resource is named by its CURRENT name, exactly as the Catalogs
                # section names it, so a binding resolves to the same object id on apply.
                $ApCatResMap = @{}
                # This read only NAMES the bindings below, and the failure is reported through
                # InventoryPartial like any other unread collection. When it cannot be read the map
                # stays empty and $ApCatResRead is $false, which changes what a binding falls back to
                # (see the projection below): the name a binding carries then is the one the catalog
                # RECORDED when the resource was added, Graph keeps that after a rename, and the apply
                # engine resolves a declared name FIRST as a group name -- so after a rename that name
                # can resolve to ANOTHER group that now carries it, binding the wrong group and, under
                # -Prune, removing the real binding. A group's object id cannot name another group.
                # It used to be -ErrorAction SilentlyContinue, which hid the failure from every caller.
                $ApCatResRead = $true
                $ApCatRes = @()
                try {
                    $ApCatRes = @(Get-OERCatalogResource -Catalog $ApCat.Id -ErrorAction Stop)
                } catch {
                    Remove-OERErrorRecord -Record $PSItem
                    $ApCatResRead = $false
                    $ApCatResCause = "Could not read a catalog's resources to name its access packages' bindings: $($PSItem.Exception.Message)"
                    Write-Verbose "Get-OERInventory: $ApCatResCause"
                    Add-UnreadCause -Cause $ApCatResCause -Target ([string]$ApCat.Id)
                    $UnreadCollections.Add("accessPackages/$($ApCat.DisplayName)/catalogResourceNames")
                    $ApCatRes = @()
                }
                $ApCurrentNames = & $GetCatalogResourceNames ([string]$ApCat.Id) $ApCatRes
                foreach ($Cr in $ApCatRes) {
                    if (-not $Cr.OriginId) { continue }
                    $ApCatResMap[[string]$Cr.OriginId] = if ([string]$Cr.OriginSystem -in @('AadGroup', 'AadApplication') -and $ApCurrentNames.ContainsKey([string]$Cr.OriginId)) {
                        [string]$ApCurrentNames[[string]$Cr.OriginId]
                    } else {
                        [string]$Cr.DisplayName
                    }
                }
                # A package list that could not be read projects the catalog with no packages, as it
                # always has: no handler removes an access package that is absent from the document
                # ("Prune is child-scope only", Invoke-OERStructure). An absent package is not a fact
                # though, so the failure is reported through InventoryPartial against the catalog.
                # It used to have no error handling: under a caller's Stop it ended the whole call
                # with no document at all, and under Continue it left one stray record and no partial.
                $ApList = @()
                try {
                    $ApList = @(Get-OERAccessPackage -Catalog $ApCat.Id -ErrorAction Stop)
                } catch {
                    Remove-OERErrorRecord -Record $PSItem
                    $ApListCause = "Could not list a catalog's access packages: $($PSItem.Exception.Message)"
                    Write-Verbose "Get-OERInventory: $ApListCause"
                    Add-UnreadCause -Cause $ApListCause -Target ([string]$ApCat.Id)
                    $UnreadCollections.Add("accessPackages/$($ApCat.DisplayName)/packages")
                    $ApList = @()
                }
                foreach ($Ap in $ApList) {
                    $Proj = [ordered]@{
                        displayName = $Ap.DisplayName
                        catalog     = $ApCat.DisplayName
                        description = $Ap.Description
                        # Cheap boolean -- always emitted so a hidden package stays hidden across a
                        # round-trip and a visible one is never silently re-hidden.
                        hidden      = [bool]$Ap.IsHidden
                    }
                    if ($IncludeId) { $Proj.id = $Ap.Id }

                    # D4: resource role bindings via M1. Recover the resource's real display name by
                    # joining the binding OriginId to the catalog resource map (the apply engine matches
                    # on that name). A group or application binding is written under its OriginId -- the
                    # object id, which the apply engine resolves verbatim (Resolve-OERGroupId returns a
                    # GUID as it is) and matches against the catalog resource's OriginId -- both when
                    # the map was NOT read, since the only name left is the one the catalog recorded and
                    # that can name another object after a rename, and when the name it has is blank,
                    # since an empty name is refused by the validator (A10). Any other binding falls
                    # back to the name the access package reader could join, which is the name the
                    # catalog recorded or none. A binding with no usable name and no such id (a
                    # SharePoint site, whose OriginId is its URL, a group with no OriginId, or a blank
                    # role) cannot be named at all, so the package's resourceRoles is written as an
                    # explicit null and named in InventoryPartial: all or nothing, since a declared set
                    # that quietly left the binding out would have -Prune remove it.
                    # A FAILED read is never projected as []: under -Prune an empty declared binding set
                    # removes every binding of the package, and an omitted key still reconciles the
                    # same way. An explicit null is the documented "leave the bindings untouched"
                    # signal, so that is what an unread set is, and the gap is reported through
                    # InventoryPartial like the group and administrative-unit collections above.
                    # -ErrorAction Stop inside try/catch, the shape the directory-role sections below
                    # use: one reader per package, so a failure is attributed to exactly this package,
                    # and a record a reader swallowed internally (a retried 429) never counts as one.
                    $ApRoles = $null
                    try {
                        $ApRoles = @(Get-OERAccessPackageResourceRole -AccessPackage $Ap.Id -ErrorAction Stop)
                    } catch {
                        Remove-OERErrorRecord -Record $PSItem
                        $ApRolesCause = "Could not read an access package's resource role bindings: $($PSItem.Exception.Message)"
                        Write-Verbose "Get-OERInventory: $ApRolesCause"
                        Add-UnreadCause -Cause $ApRolesCause -Target ([string]$Ap.Id)
                        $UnreadCollections.Add("accessPackages/$($Ap.DisplayName)/resourceRoles")
                        $ApRoles = $null
                    }
                    if ($null -eq $ApRoles) {
                        $Proj.resourceRoles = $null
                    } else {
                        $RrNameless = $false
                        $RrProjected = @(foreach ($Rr in $ApRoles) {
                            $IsDirectoryObject = [string]$Rr.OriginSystem -in @('AadGroup', 'AadApplication')
                            $ResName = if ($Rr.OriginId -and $ApCatResMap.ContainsKey([string]$Rr.OriginId)) {
                                [string]$ApCatResMap[[string]$Rr.OriginId]
                            } elseif (-not $ApCatResRead -and $IsDirectoryObject -and $Rr.OriginId) {
                                [string]$Rr.OriginId
                            } else {
                                [string]$Rr.ResourceDisplayName
                            }
                            if ([string]::IsNullOrWhiteSpace($ResName) -and $IsDirectoryObject -and $Rr.OriginId) {
                                $ResName = [string]$Rr.OriginId
                            }
                            if ([string]::IsNullOrWhiteSpace($ResName) -or [string]::IsNullOrWhiteSpace([string]$Rr.RoleName)) {
                                $RrNameless = $true
                                continue
                            }
                            [PSCustomObject]@{ resource = $ResName; role = [string]$Rr.RoleName }
                        })
                        if ($RrNameless) {
                            $Proj.resourceRoles = $null
                            Add-NamelessCollection -Path "accessPackages/$($Ap.DisplayName)/resourceRoles"
                        } else {
                            $Proj.resourceRoles = $RrProjected
                        }
                    }

                    # D5: assignment policy internals -- full granular projection for round-trip fidelity.
                    # A policy set that could not be read projects [] exactly as it always has:
                    # Sync-OERStructureAccessPackage never removes an assignment policy (it reports an
                    # undeclared one as still in force), so [] deletes nothing. An absent policy is not
                    # a fact though, so the failure is reported through InventoryPartial. It used to have
                    # no error handling: under a caller's Stop it ended the whole call with no document
                    # at all, and under Continue it left one stray record and no partial.
                    $ApPolicies = @()
                    try {
                        $ApPolicies = @(Get-OERAccessPackageAssignmentPolicy -AccessPackage $Ap.Id -ErrorAction Stop)
                    } catch {
                        Remove-OERErrorRecord -Record $PSItem
                        $ApPoliciesCause = "Could not read an access package's assignment policies: $($PSItem.Exception.Message)"
                        Write-Verbose "Get-OERInventory: $ApPoliciesCause"
                        Add-UnreadCause -Cause $ApPoliciesCause -Target ([string]$Ap.Id)
                        $UnreadCollections.Add("accessPackages/$($Ap.DisplayName)/assignmentPolicies")
                        $ApPolicies = @()
                    }
                    $Proj.assignmentPolicies = @(foreach ($P in $ApPolicies) {
                        $PolProj = [ordered]@{ displayName = $P.DisplayName }
                        if ($P.Description) { $PolProj.description = $P.Description }
                        # requestorScope: always emit scope; emit users/groups only when non-empty.
                        if ($P.RequestorScope) {
                            $RsProj = [ordered]@{ scope = $P.RequestorScope.scope }
                            if ($P.RequestorScope.users -and @($P.RequestorScope.users).Count -gt 0) {
                                $RsProj.users = @($P.RequestorScope.users)
                            }
                            if ($P.RequestorScope.groups -and @($P.RequestorScope.groups).Count -gt 0) {
                                $RsProj.groups = @($P.RequestorScope.groups)
                            }
                            $PolProj.requestorScope = [PSCustomObject]$RsProj
                        }
                        # requestorSettings: always emit (cheap booleans; deterministic round-trip even
                        # when RequestorSettings is null -- [bool]$null -> $false). managerLevel only
                        # when allowManagerRequest is true.
                        $RstProj = [ordered]@{
                            allowSelfRequest    = [bool]$P.RequestorSettings.AllowSelfRequest
                            allowManagerRequest = [bool]$P.RequestorSettings.AllowManagerRequest
                        }
                        if ($P.RequestorSettings.AllowManagerRequest) {
                            $RstProj.managerLevel = $P.RequestorSettings.ManagerLevel
                        }
                        $RstProj.allowCustomSchedule = [bool]$P.RequestorSettings.AllowCustomSchedule
                        $RstProj.allowSelfExtend     = [bool]$P.RequestorSettings.AllowSelfExtend
                        $RstProj.allowSelfRemove     = [bool]$P.RequestorSettings.AllowSelfRemove
                        $RstProj.allowOnBehalfUpdate = [bool]$P.RequestorSettings.AllowOnBehalfUpdate
                        $RstProj.allowOnBehalfRemove = [bool]$P.RequestorSettings.AllowOnBehalfRemove
                        $PolProj.requestorSettings = [PSCustomObject]$RstProj
                        # Cheap booleans -- always emit for deterministic round-trip.
                        $PolProj.requireApproval               = [bool]$P.RequireApproval
                        $PolProj.requireRequestorJustification = [bool]$P.RequireRequestorJustification
                        $PolProj.requireApprovalForUpdate      = [bool]$P.RequireApprovalForUpdate
                        # approvalStages: emit each stage when list is non-empty.
                        if ($P.ApprovalStages -and @($P.ApprovalStages).Count -gt 0) {
                            $PolProj.approvalStages = @(foreach ($S in @($P.ApprovalStages)) {
                                $StProj = [ordered]@{
                                    durationDays = $S.durationDays
                                    manager      = [bool]$S.manager
                                }
                                if ($null -ne $S.managerLevel) { $StProj.managerLevel = $S.managerLevel }
                                if ($S.users -and @($S.users).Count -gt 0) { $StProj.users = @($S.users) }
                                if ($S.groups -and @($S.groups).Count -gt 0) { $StProj.groups = @($S.groups) }
                                if ($S.internalSponsor) { $StProj.internalSponsor = $true }
                                if ($S.externalSponsor) { $StProj.externalSponsor = $true }
                                if ($S.alternateUsers -and @($S.alternateUsers).Count -gt 0) { $StProj.alternateUsers = @($S.alternateUsers) }
                                if ($S.alternateGroups -and @($S.alternateGroups).Count -gt 0) { $StProj.alternateGroups = @($S.alternateGroups) }
                                if ($S.fallbackUsers -and @($S.fallbackUsers).Count -gt 0) { $StProj.fallbackUsers = @($S.fallbackUsers) }
                                if ($S.fallbackGroups -and @($S.fallbackGroups).Count -gt 0) { $StProj.fallbackGroups = @($S.fallbackGroups) }
                                if ($null -ne $S.escalationDays) { $StProj.escalationDays = $S.escalationDays }
                                if ($S.requireApproverJustification) { $StProj.requireApproverJustification = $true }
                                if ($S.approverInfoVisibility -and $S.approverInfoVisibility -ne 'Default') {
                                    $StProj.approverInfoVisibility = $S.approverInfoVisibility
                                }
                                [PSCustomObject]$StProj
                            })
                        }
                        # Expiration: emit exactly one form -- durationInDays preferred, then hours, then datetime.
                        if ($null -ne $P.DurationInDays) { $PolProj.durationInDays = $P.DurationInDays }
                        elseif ($null -ne $P.DurationInHours) { $PolProj.durationInHours = $P.DurationInHours }
                        elseif ($P.ExpirationDateTime) { $PolProj.expirationDateTime = $P.ExpirationDateTime }
                        # notificationsDisabled -- always emit for deterministic round-trip.
                        $PolProj.notificationsDisabled = [bool]$P.NotificationsDisabled
                        [PSCustomObject]$PolProj
                    })
                    $AccessPackages.Add([PSCustomObject]$Proj)
                }
            }
        }

        if ($Include -contains 'RoleAssignments') {
            if (-not ($Scope -or $Subscription -or $ManagementGroup)) {
                Write-Warning 'RoleAssignments requires a target scope (-Scope, -Subscription or -ManagementGroup); section skipped.'
            }
            else {
                $RaParams = @{ ResolveNames = $true }
                if ($Scope) { $RaParams.Scope = $Scope }
                if ($Subscription) { $RaParams.Subscription = $Subscription }
                if ($ManagementGroup) { $RaParams.ManagementGroup = $ManagementGroup }
                $RaItems = @(Get-OERRoleAssignment @RaParams)

                # Resolve principal object ids to names (UPN for users so the apply @-heuristic routes
                # them to -User; displayName for groups / service principals). Batched into the shared
                # per-invocation cache.
                $RaPrincipalIds = @($RaItems | ForEach-Object { [string]$_.PrincipalId } | Where-Object { $_ })
                $MissingRaIds = @($RaPrincipalIds | Where-Object { -not $PrincipalNameCache.ContainsKey($_) } | Select-Object -Unique)
                if ($MissingRaIds.Count -gt 0) {
                    $ResolvedRa = Resolve-OERPrincipalName -Id $MissingRaIds
                    foreach ($K in $ResolvedRa.Keys) { $PrincipalNameCache[$K] = $ResolvedRa[$K] }
                }

                # Projected first and added to the section below: whether two principals collide can
                # only be decided once every row has its name.
                $RaProjected = [System.Collections.Generic.List[object]]::new()
                foreach ($Ra in $RaItems) {
                    $PrincipalName = if ($Ra.PrincipalId -and $PrincipalNameCache.ContainsKey([string]$Ra.PrincipalId)) {
                        $PrincipalNameCache[[string]$Ra.PrincipalId]
                    } elseif ($Ra.PrincipalDisplayName) {
                        $Ra.PrincipalDisplayName
                    } else {
                        $Ra.PrincipalId
                    }
                    $Proj = [ordered]@{
                        scope     = $Ra.Scope
                        role      = $(if ($Ra.RoleName) { $Ra.RoleName } else { $Ra.RoleDefinitionId })
                        principal = $PrincipalName
                    }
                    # Normalize the ARM principal type to the apply schema enum
                    # (User|Group|ServicePrincipal). A user UPN / group name routes via the apply
                    # @-heuristic, so principalType is emitted only for a service principal (a name
                    # cannot disambiguate one). ForeignGroup -- a B2B / cross-tenant group -- maps to
                    # Group; any other ARM type (e.g. Device) is omitted rather than emitting an invalid
                    # enum value that would fail Test-OERStructure validation.
                    $PrincipalType = if ($Ra.PrincipalType -eq 'ForeignGroup') { 'Group' } else { [string]$Ra.PrincipalType }
                    if ($PrincipalType -eq 'ServicePrincipal') {
                        $Proj.principalType = $PrincipalType
                    }
                    # ABAC condition and the free-text description are writable by New-OERRoleAssignment
                    # and readable here, so project them or a condition-scoped assignment would be
                    # exported as an unconditioned one. conditionVersion is only meaningful alongside a
                    # condition (ARM defaults it to 2.0), so it is emitted only with one.
                    if ($Ra.Description) { $Proj.description = [string]$Ra.Description }
                    if ($Ra.Condition) {
                        $Proj.condition = [string]$Ra.Condition
                        $Proj.conditionVersion = $(if ($Ra.ConditionVersion) { [string]$Ra.ConditionVersion } else { '2.0' })
                    }
                    if ($IncludeId) { $Proj.id = $Ra.RoleAssignmentId }
                    $RaProjected.Add([PSCustomObject]@{ Ra = $Ra; Proj = $Proj; Type = $PrincipalType })
                }

                # Entra does not keep display names unique, a group can carry a user's user principal
                # name as its display name, and Azure may return one scope in two spellings -- so two
                # rows can export the same (scope, role, principal), which the validator refuses as a
                # duplicate and so invalidates the whole document. The key is the validator's: the
                # canonical scope, the role and the principal, compared without regard to letter case.
                # Every row whose key collides moves its principal to the object id, the one name
                # that is unique, and, when the type is known (ForeignGroup is a Group), stamps
                # principalType so an id-named user or group is created as the right type on a
                # re-apply. Users move too: a user's fallback name can be a display name, and a group
                # can carry a user principal name. A colliding row whose principal already is its id
                # then moves its role to the full role definition id, for two role definitions that
                # share a display name. Repeated until nothing changes, since an object id can in turn
                # equal another principal's name. Each change moves a field to its id, and a field
                # moves only once, so it ends; what is left is one assignment read twice, which
                # Azure does not return.
                do {
                    $RaKeyCount = [System.Collections.Generic.Dictionary[string, int]]::new([System.StringComparer]::OrdinalIgnoreCase)
                    foreach ($Row in $RaProjected) {
                        $RaKey = "$(ConvertTo-OERCanonicalScope -Scope ([string]$Row.Proj.scope))|$($Row.Proj.role)|$($Row.Proj.principal)"
                        $RaKeyCount[$RaKey] = 1 + $(if ($RaKeyCount.ContainsKey($RaKey)) { $RaKeyCount[$RaKey] } else { 0 })
                    }
                    $RaMoved = $false
                    foreach ($Row in $RaProjected) {
                        $RaKey = "$(ConvertTo-OERCanonicalScope -Scope ([string]$Row.Proj.scope))|$($Row.Proj.role)|$($Row.Proj.principal)"
                        if ($RaKeyCount[$RaKey] -le 1) { continue }
                        if ($Row.Ra.PrincipalId -and [string]$Row.Proj.principal -ne [string]$Row.Ra.PrincipalId) {
                            $Row.Proj.principal = [string]$Row.Ra.PrincipalId
                            if ($Row.Type -in @('User', 'Group', 'ServicePrincipal')) {
                                # principalType belongs directly after principal, where it sits for a
                                # service principal, so the entry keeps its key order.
                                if ($Row.Proj.Contains('principalType')) { $Row.Proj.principalType = $Row.Type }
                                else { $Row.Proj.Insert(3, 'principalType', $Row.Type) }
                            }
                            $RaMoved = $true
                        } elseif ($Row.Ra.RoleDefinitionId -and [string]$Row.Proj.role -ne [string]$Row.Ra.RoleDefinitionId) {
                            $Row.Proj.role = [string]$Row.Ra.RoleDefinitionId
                            $RaMoved = $true
                        }
                    }
                } while ($RaMoved)
                foreach ($Row in $RaProjected) { $RoleAssignments.Add([PSCustomObject]$Row.Proj) }
            }
        }

        if ($Include -contains 'AccessReviews') {
            $ArItems = @()
            $SkippedReviewCount = 0
            # -ErrorAction SilentlyContinue + a LOCAL -ErrorVariable, not -ErrorAction Stop -- the
            # same fix, for the same mechanism, as the existence probe in
            # Sync-OERStructureAccessReview. Get-OERAccessReviewDefinition reports "nothing matched"
            # on -DisplayName by WRITING a non-terminating AccessReviewDefinitionNotFound record, and
            # $PSCmdlet.WriteError() deposits that record into every -ErrorVariable/$Error collector
            # already listening on the call stack the instant it runs. The catch below stops the
            # resulting exception from becoming a hard stop, but it can never retract a deposit
            # already made, so an inventory read that SUCCEEDED still left ghost
            # AccessReviewDefinitionNotFound records in the operator's own $Error.
            # The pipe into Where-Object is load-bearing, not tidying. Measured, one written record:
            # @(call -ErrorAction Stop) inside a try/catch leaks 3 to the caller; $Var = call
            # -SilentlyContinue -ErrorVariable leaks 1; @(call -SilentlyContinue -ErrorVariable)
            # leaks 1 (the array subexpression runs the call as its own nested pipeline and
            # re-deposits on the way out); only piping the call onward before the @( ) closes leaks
            # 0. Do not "simplify" the filter away.
            # SilentlyContinue here means "captured", not "ignored": the records are inspected below.
            $ArReadErrors = $null
            $ArParams = if ($AccessReviewFilter) {
                # -AccessReviewFilter is a display-name pattern (wildcards supported), matched
                # client-side -- the accessReviews endpoint does not reliably support server-side
                # name filtering.
                @{ DisplayName = $AccessReviewFilter }
            }
            else {
                # No filter supplied: capture every definition via the unfiltered list-all mode.
                @{ All = $true }
            }
            # The try/catch still guards a genuinely TERMINATING failure of the whole read; the loop
            # handles the NON-terminating records. Both are needed: neither subsumes the other.
            try {
                $ArItems = @(Get-OERAccessReviewDefinition @ArParams -ErrorAction SilentlyContinue -ErrorVariable ArReadErrors |
                        Where-Object { $null -ne $_ })
                foreach ($ArErr in @($ArReadErrors)) {
                    if ($null -eq $ArErr) { continue }
                    # No Remove-OERErrorRecord here, same as the group and administrative-unit loops
                    # above: a record Get-OERAccessReviewDefinition PUBLISHED was already scrubbed by
                    # that cmdlet's own catch, and scrubbing a reported diagnostic again would only
                    # strip it from $global:Error.
                    if ($ArErr.FullyQualifiedErrorId -like 'AccessReviewDefinitionNotFound*') { continue }
                    # Warn only for a record Get-OERAccessReviewDefinition itself PUBLISHED. Same
                    # publisher test, same measured reason, as the two loops above: -ErrorVariable is
                    # filled by the ENGINE and also collects records raised inside nested calls even
                    # when an inner catch swallowed them, and Invoke-OERGraphRequest swallows and
                    # retries a 429, a 503 carrying Retry-After, and an ACRS claims challenge -- one
                    # retried-then-successful throttle measured three stray TooManyRequests records
                    # plus a bare, message-less RuntimeException. Membership, not a suffix match:
                    # Write-Error appends a further name when a record is republished.
                    if (@(([string]$ArErr.FullyQualifiedErrorId) -split ',') -contains 'Get-OERAccessReviewDefinition') {
                        Write-Warning "Could not read access reviews: $($ArErr.Exception.Message)"
                        # Counted unread as well as warned, for the same reason as the groups read above.
                        Add-UnreadSection -Key 'accessReviews' -Cause "Could not read access reviews: $($ArErr.Exception.Message)"
                    } else {
                        # Routed to verbose rather than dropped: a stray is still evidence when a read
                        # misbehaves, it just is not a section-level finding the operator must act on.
                        Write-Verbose ("Get-OERInventory: ignoring a foreign error record seen while reading " +
                            "access reviews ($($ArErr.FullyQualifiedErrorId)): $($ArErr.Exception.Message)")
                    }
                }
            } catch {
                Remove-OERErrorRecord -Record $PSItem
                if ($PSItem.FullyQualifiedErrorId -notlike 'AccessReviewDefinitionNotFound*') {
                    Write-Warning "Could not read access reviews: $($PSItem.Exception.Message)"
                    Add-UnreadSection -Key 'accessReviews' -Cause "Could not read access reviews: $($PSItem.Exception.Message)"
                }
            }
            foreach ($Ar in $ArItems) {
                # Only access-package-scoped reviews round-trip: the apply schema requires both
                # accessPackage and assignmentPolicy, and Invoke-OERStructure models access-package
                # reviews only. A review without both (for example a directory-role or group review)
                # cannot be applied and would make the inventory fail apply-schema validation, so skip it.
                if (-not $Ar.AccessPackageId -or -not $Ar.AssignmentPolicyId) {
                    Write-Verbose "Skipping access review '$($Ar.DisplayName)': not access-package-scoped (does not round-trip)."
                    $SkippedReviewCount++
                    continue
                }

                # A multi-stage review's reviewers live in stageSettings; the definition's top-level
                # reviewers collection is empty by construction and Microsoft Learn states it is ignored
                # when stageSettings is present. Projecting it would emit reviewers ["self"] below --
                # asserting a self review that was never configured. The apply schema models no stages,
                # so such a review cannot round-trip at all; skip it visibly rather than fabricate it.
                # Warned separately from the not-access-package-scoped skip above: the two have
                # different causes and different remedies, so folding them into one count could name
                # neither.
                if ([int]$Ar.StageCount -gt 0) {
                    Write-Warning "Get-OERInventory: skipping multi-stage access review '$($Ar.DisplayName)' ($($Ar.StageCount) stages). Its reviewers live in stageSettings, which the apply document does not model -- exporting it would misreport it as a single-stage self review. Manage it with New-OERAccessReviewStage."
                    continue
                }

                $Proj = [ordered]@{ displayName = $Ar.DisplayName }

                # accessPackage + assignmentPolicy: resolve ids to names (fallback to the id). Both ids
                # are present here (the skip above requires them). A deleted target is written by id
                # and reported nowhere; a FAILED read is written by id too and reported as an unread
                # collection -- see Get-AccessReviewReferenceName, which owns the rule and the reason
                # these are transport reads rather than calls to the Get-OER* readers.
                $Proj.accessPackage = Get-AccessReviewReferenceName `
                    -Uri ('v1.0/identityGovernance/entitlementManagement/accessPackages/{0}?$expand=catalog' -f $Ar.AccessPackageId) `
                    -NotFoundCode 'AccessPackageNotFound', 'NotFound' `
                    -Id ([string]$Ar.AccessPackageId) -ReviewName ([string]$Ar.DisplayName) `
                    -Part 'accessPackage' -Label 'access package'
                $Proj.assignmentPolicy = Get-AccessReviewReferenceName `
                    -Uri ('v1.0/identityGovernance/entitlementManagement/assignmentPolicies/{0}?$expand=accessPackage' -f $Ar.AssignmentPolicyId) `
                    -NotFoundCode 'PolicyNotFound', 'NotFound' `
                    -Id ([string]$Ar.AssignmentPolicyId) -ReviewName ([string]$Ar.DisplayName) `
                    -Part 'assignmentPolicy' -Label 'assignment policy'

                # reviewers -> friendly tokens (manager / self / resolved name). Every query is parsed
                # through Resolve-OERReviewerScopeQuery, the module's single owner of that grammar. It
                # is also what tolerates the API version prefix Graph adds when it NORMALIZES a reviewer
                # scope on read: a scope written as '/users/{id}' reads back as '/v1.0/users/{id}'.
                # Filtered: @($null).Count is 1, so an absent Reviewers property would otherwise read
                # as ONE scope -- a scope with no query, which would then count as an unparsed one and
                # both suppress the self default and raise a warning naming an empty string.
                $RawReviewers = @($Ar.Reviewers | Where-Object { $_ })
                $ParsedReviewers = @(foreach ($Rv in $RawReviewers) { Resolve-OERReviewerScopeQuery -Query ([string]$Rv.query) })
                $ReviewerIds = [System.Collections.Generic.List[string]]::new()
                foreach ($Parsed in $ParsedReviewers) {
                    if ($Parsed.Id) { $ReviewerIds.Add([string]$Parsed.Id) }
                }
                $MissingRevIds = @($ReviewerIds | Where-Object { -not $PrincipalNameCache.ContainsKey($_) } | Select-Object -Unique)
                if ($MissingRevIds.Count -gt 0) {
                    $ResolvedRev = Resolve-OERPrincipalName -Id $MissingRevIds
                    foreach ($K in $ResolvedRev.Keys) { $PrincipalNameCache[$K] = $ResolvedRev[$K] }
                }
                $Reviewers = [System.Collections.Generic.List[string]]::new()
                $UnparsedReviewers = [System.Collections.Generic.List[string]]::new()
                foreach ($Parsed in $ParsedReviewers) {
                    if ($Parsed.Kind -eq 'Manager') { $Reviewers.Add('manager'); continue }
                    # A scope object carrying no query at all names no reviewer, so it is dropped
                    # rather than reported -- naming an empty string in the warning helps nobody.
                    if ($Parsed.Kind -eq 'Unparsed') {
                        if ($Parsed.Query) { $UnparsedReviewers.Add([string]$Parsed.Query) }
                        continue
                    }
                    $RvId = [string]$Parsed.Id
                    $Reviewers.Add($(if ($PrincipalNameCache.ContainsKey($RvId)) { $PrincipalNameCache[$RvId] } else { $RvId }))
                }
                if ($RawReviewers.Count -eq 0) { $Reviewers.Add('self') }
                elseif ($UnparsedReviewers.Count -gt 0) {
                    # An UNPARSED scope is not an ABSENT one. No scope at all is the documented
                    # self-review shape (Learn: "To configure a self-review, don't specify the reviewers
                    # property or supply an empty object"); an unparsed scope means a real reviewer
                    # exists that this module's vocabulary cannot express. Microsoft Learn documents
                    # forms a portal-created review can carry that this module never emits -- './owners',
                    # '/servicePrincipals/{id}/owners', a filtered owners query. Dropping one silently
                    # would either fabricate a self review (when it was the only scope) or quietly shrink
                    # the reviewer set (when it was not), so name the offending queries in both cases.
                    # This warning is what surfaced the version-prefix defect -- keep it, and keep it
                    # naming the queries.
                    $UnparsedDetail = "Get-OERInventory: access review '$($Ar.DisplayName)' has $($UnparsedReviewers.Count) live reviewer scope(s) that this module's vocabulary cannot express ($($UnparsedReviewers -join ', '))"
                    if ($Reviewers.Count -eq 0) {
                        Write-Warning "$UnparsedDetail; exporting an empty reviewers list, which reads as a self review."
                    }
                    else {
                        Write-Warning "$UnparsedDetail; they are omitted from the exported reviewers list, which therefore names fewer reviewers than the live review."
                    }
                }
                $Proj.reviewers = @($Reviewers)

                # fallbackReviewers -> friendly tokens (resolved user/group name; manager is never a
                # fallback). A manager review carries a required fallback, so project it for round-trip.
                # Filtered for the same @($null).Count is 1 reason as the primary half above.
                $RawFallback = @($Ar.FallbackReviewers | Where-Object { $_ })
                if ($RawFallback.Count -gt 0) {
                    $ParsedFallback = @(foreach ($Fb in $RawFallback) { Resolve-OERReviewerScopeQuery -Query ([string]$Fb.query) })
                    $FbIds = [System.Collections.Generic.List[string]]::new()
                    foreach ($Parsed in $ParsedFallback) {
                        if ($Parsed.Id) { $FbIds.Add([string]$Parsed.Id) }
                    }
                    $MissingFbIds = @($FbIds | Where-Object { -not $PrincipalNameCache.ContainsKey($_) } | Select-Object -Unique)
                    if ($MissingFbIds.Count -gt 0) {
                        $ResolvedFb = Resolve-OERPrincipalName -Id $MissingFbIds
                        foreach ($K in $ResolvedFb.Keys) { $PrincipalNameCache[$K] = $ResolvedFb[$K] }
                    }
                    $Fallbacks = [System.Collections.Generic.List[string]]::new()
                    $UnparsedFallback = [System.Collections.Generic.List[string]]::new()
                    foreach ($Parsed in $ParsedFallback) {
                        # Anything with no object id is unexpressible HERE, including a './manager'
                        # scope: the document's fallbackReviewers vocabulary is user and group only.
                        if ($Parsed.Id) {
                            $FbId = [string]$Parsed.Id
                            $Fallbacks.Add($(if ($PrincipalNameCache.ContainsKey($FbId)) { $PrincipalNameCache[$FbId] } else { $FbId }))
                        }
                        elseif ($Parsed.Query) { $UnparsedFallback.Add([string]$Parsed.Query) }
                    }
                    # Same rule as the primary half: a silently dropped fallback is data loss, and a
                    # manager review whose only fallback did not parse exports with no fallbackReviewers
                    # at all -- which Microsoft Graph rejects on the way back in.
                    if ($UnparsedFallback.Count -gt 0) {
                        Write-Warning "Get-OERInventory: access review '$($Ar.DisplayName)' has $($UnparsedFallback.Count) live fallback reviewer scope(s) that this module's vocabulary cannot express ($($UnparsedFallback -join ', ')); they are omitted from the exported fallbackReviewers list."
                    }
                    if ($Fallbacks.Count -gt 0) { $Proj.fallbackReviewers = @($Fallbacks) }
                }

                # recurrence -> friendly cadence.
                $Cadence = 'OneTime'
                $Rec = $Ar.Recurrence
                if ($Rec -and $Rec.pattern) {
                    $PType = [string]$Rec.pattern.type
                    $Interval = [int]$Rec.pattern.interval
                    # New-OERAccessReviewRecurrence can only emit weekly interval 1 and absoluteMonthly
                    # interval 1/3/12 (mirrors Resolve-OERAccessReviewChange's representable check), so
                    # every other live interval collapses onto a coarser cadence below. Warn before the
                    # collapse rather than exporting a semi-annual or n-weekly review as Monthly/Weekly
                    # with no sign anything was lost.
                    $PatternRepresentable = switch ($PType) {
                        'weekly'          { $Interval -eq 1 }
                        'absoluteMonthly' { $Interval -in 1, 3, 12 }
                        default           { $false }
                    }
                    if (-not $PatternRepresentable) {
                        Write-Warning "Get-OERInventory: access review '$($Ar.DisplayName)' has a live recurrence pattern ($PType interval $Interval) that the module's cadence vocabulary cannot represent; exporting the nearest coarser cadence instead of the true interval."
                    }
                    $Cadence = switch ($PType) {
                        'weekly' { 'Weekly' }
                        'absoluteMonthly' { switch ($Interval) { 1 { 'Monthly' } 3 { 'Quarterly' } 12 { 'Annually' } default { 'Monthly' } } }
                        default { 'OneTime' }
                    }
                }
                $Proj.recurrence = $Cadence

                if ($Ar.DescriptionForAdmins)    { $Proj.descriptionForAdmins    = $Ar.DescriptionForAdmins }
                if ($Ar.DescriptionForReviewers) { $Proj.descriptionForReviewers = $Ar.DescriptionForReviewers }
                # settings.instanceDurationInDays is NOT always a usable duration on the read side.
                # Microsoft's own list-definitions example response carries "instanceDurationInDays": 0
                # for a live review (learn.microsoft.com/graph/api/accessreviewset-list-definitions), and
                # accessReviewScheduleSettings documents the field as superseded whenever stageSettings
                # defines durationInDays -- so 0 is Graph's "this field does not drive the duration"
                # report, not a duration of zero days. The apply schema requires an integer 1-365, so
                # passing the live 0 straight through is what made the exported inventory fail the
                # schema.json shipped beside it. A bare "$null -ne" guard cannot catch it: the value is
                # a real 0, not a missing key. Omitting the key instead is the correct round-trip --
                # absent means "leave untouched" to Sync-OERStructureAccessReview -- and is the same
                # treatment the numbered-range occurrences below already gets for a live zero.
                $LiveDurationInDays = $Ar.DurationInDays -as [int]
                if ($LiveDurationInDays -ge 1 -and $LiveDurationInDays -le 365) {
                    $Proj.durationInDays = $LiveDurationInDays
                }
                elseif ($LiveDurationInDays -gt 365) {
                    # A configured-but-unrepresentable duration is dropped data, unlike the 0 sentinel
                    # above which represents nothing. Warn before dropping it rather than exporting a
                    # review whose duration silently reverts to the create-path default on apply.
                    Write-Warning "Get-OERInventory: access review '$($Ar.DisplayName)' reports a live instance duration of $LiveDurationInDays day(s), which the apply schema (1-365) cannot represent; exporting no durationInDays for it."
                }
                $StartDate = $Ar.Recurrence.range.startDate
                if ($StartDate) { $Proj.startDate = [string]$StartDate }

                # Settings the apply schema declares and Sync-OERStructureAccessReview already applies.
                # Emitted unconditionally: they are cheap deterministic booleans, and omitting one means
                # "leave untouched", which would silently reset it when the document creates the review
                # in another tenant.
                $Proj.mailNotification       = [bool]$Ar.MailNotificationsEnabled
                $Proj.reminderNotification   = [bool]$Ar.ReminderNotificationsEnabled
                $Proj.requireJustification   = [bool]$Ar.JustificationRequired
                $Proj.recommendationsEnabled = [bool]$Ar.RecommendationsEnabled
                $Proj.autoApplyDecisions     = [bool]$Ar.AutoApplyDecisionsEnabled
                # Unlike the five booleans above, defaultDecision is presence-gated rather than
                # unconditional: it is a string, so the guard below excludes only a genuinely null/empty
                # value, not the specific value 'None' -- 'None' is truthy in PowerShell like any other
                # non-empty string and IS emitted when the live setting reports it (which round-trips
                # cleanly, since 'None' is also New-OERAccessReviewDefinition's own default). The guard
                # exists only to avoid writing an explicit-but-meaningless key when Settings itself did
                # not carry the field at all.
                if ($Ar.DefaultDecision) { $Proj.defaultDecision = [string]$Ar.DefaultDecision }

                # Recurrence range: emit at most one of endDate / occurrences (the schema and
                # Test-OERStructureSchema treat them as mutually exclusive) and neither for a OneTime
                # review, which carries no recurrence object at all. A live numbered range can report
                # zero occurrences, which the schema forbids -- emit nothing rather than an invalid value.
                if ($Cadence -ne 'OneTime') {
                    $RangeType = [string]$Ar.Recurrence.range.type
                    if ($RangeType -ieq 'endDate' -and $Ar.Recurrence.range.endDate) {
                        $Proj.endDate = [string]$Ar.Recurrence.range.endDate
                    } elseif ($RangeType -ieq 'numbered' -and [int]$Ar.Recurrence.range.numberOfOccurrences -ge 1) {
                        $Proj.occurrences = [int]$Ar.Recurrence.range.numberOfOccurrences
                    }
                }

                if ($IncludeId) { $Proj.id = $Ar.Id }
                $AccessReviews.Add([PSCustomObject]$Proj)
            }
            if ($SkippedReviewCount -gt 0) {
                Write-Warning "Get-OERInventory: skipped $SkippedReviewCount access review definition(s) that are not access-package-scoped. Only access-package reviews round-trip through Invoke-OERStructure; group, application and directory-role reviews are not captured."
            }
        }

        # Microsoft Entra directory roles, read through Microsoft Graph only. The two tenant-wide
        # schedule reads are shared by both sections and issued at most once per call: the
        # assignments section exports from them, and the policy section selects the roles in use from
        # them -- unless -AllDirectoryRolePolicies asks for every role, when they are read only if the
        # assignments section needs them.
        $IncludeDirectoryAssignments = $Include -contains 'DirectoryRoleAssignments'
        $IncludeDirectoryPolicies = $Include -contains 'DirectoryRoleManagementPolicies'
        # Per kind: the rows read, and whether the read succeeded. A failed read is not an empty one,
        # so the flag -- never the row count -- decides what the document may state.
        $DirectoryRows = @{ Eligible = @(); Active = @() }
        $DirectoryRead = @{ Eligible = $false; Active = $false }
        if ($IncludeDirectoryAssignments -or ($IncludeDirectoryPolicies -and -not $AllDirectoryRolePolicies)) {
            # Unfiltered: every tenant-scope schedule, direct and group-inherited, activations
            # included. -ErrorAction Stop, each read in its own try/catch, so a refused read lands in
            # the catch and is reported, never mistaken for an empty list.
            try {
                $DirectoryRows.Eligible = @(Get-OEREligibleDirectoryRoleAssignment -ErrorAction Stop)
                $DirectoryRead.Eligible = $true
            } catch {
                Remove-OERErrorRecord -Record $PSItem
                $DirectoryCause = "Could not read the Microsoft Entra directory role eligibility schedules: $($PSItem.Exception.Message)"
                Write-Verbose "Get-OERInventory: $DirectoryCause"
                Add-UnreadCause -Cause $DirectoryCause
                if ($IncludeDirectoryAssignments) { $UnreadCollections.Add('directoryRoleAssignments/Eligible') }
            }
            try {
                $DirectoryRows.Active = @(Get-OERActiveDirectoryRoleAssignment -ErrorAction Stop)
                $DirectoryRead.Active = $true
            } catch {
                Remove-OERErrorRecord -Record $PSItem
                $DirectoryCause = "Could not read the Microsoft Entra directory role assignment schedules: $($PSItem.Exception.Message)"
                Write-Verbose "Get-OERInventory: $DirectoryCause"
                Add-UnreadCause -Cause $DirectoryCause
                if ($IncludeDirectoryAssignments) { $UnreadCollections.Add('directoryRoleAssignments/Active') }
            }
        }

        if ($IncludeDirectoryAssignments) {
            $DirectoryKept = [System.Collections.Generic.List[object]]::new()
            foreach ($DirectoryKind in @('Eligible', 'Active')) {
                if (-not $DirectoryRead[$DirectoryKind]) { continue }
                $DirectorySeen = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
                # Only the rows the apply engine may match or prune -- tenant scope, direct, and for
                # Active an Assigned schedule, never an activation -- decided by the same single owner
                # Sync-OERStructureDirectoryRoleAssignment uses, so the export can never emit a row
                # the apply engine would not match.
                foreach ($DirectoryRow in @(Select-OERManagedDirectoryRoleAssignment -Assignment $DirectoryRows[$DirectoryKind] -Kind $DirectoryKind)) {
                    # Two schedules for one role, principal and kind (a future-dated second one, for
                    # example) would be two entries the validator refuses as a duplicate. Keep the
                    # first this read returned and say so. The handler compares against the first
                    # schedule ITS filtered read returns, and Microsoft Graph does not promise the two
                    # reads the same order, so the warning says the entry may then report a change.
                    if (-not $DirectorySeen.Add("$($DirectoryRow.RoleDefinitionId)|$($DirectoryRow.PrincipalId)")) {
                        $DuplicateRole = if ($DirectoryRow.RoleName) { [string]$DirectoryRow.RoleName } else { [string]$DirectoryRow.RoleDefinitionId }
                        Write-Warning ("Get-OERInventory: directory role '$DuplicateRole' has more than one $($DirectoryKind.ToLowerInvariant()) " +
                            "schedule for principal '$($DirectoryRow.PrincipalId)'; exporting the first. Invoke-OERStructure compares against " +
                            'the first schedule Microsoft Graph returns for that role and principal, so if the two differ it may report a change for this entry.')
                        continue
                    }
                    $DirectoryKept.Add([PSCustomObject]@{ Kind = $DirectoryKind; Row = $DirectoryRow })
                }
            }

            # Users and groups are named in ONE batched lookup through the shared per-invocation
            # cache. A service principal is never looked up: it is exported by object id, since its
            # display name is not unique and an ambiguous one fails on apply.
            $DirectoryNameIds = @($DirectoryKept |
                    Where-Object { [string]$_.Row.PrincipalType -in @('User', 'Group') } |
                    ForEach-Object { [string]$_.Row.PrincipalId } |
                    Where-Object { $_ -and -not $PrincipalNameCache.ContainsKey($_) } |
                    Select-Object -Unique)
            if ($DirectoryNameIds.Count -gt 0) {
                $ResolvedDirectory = Resolve-OERPrincipalName -Id $DirectoryNameIds
                foreach ($K in $ResolvedDirectory.Keys) { $PrincipalNameCache[$K] = $ResolvedDirectory[$K] }
            }

            # A user by its UPN and a group by its display name, each falling back to the object id
            # when no name was read; a service principal, or a principal of unknown type, by its
            # object id, which the apply engine resolves verbatim.
            $DirectoryPrincipals = [string[]]::new($DirectoryKept.Count)
            for ($Index = 0; $Index -lt $DirectoryKept.Count; $Index++) {
                $DirectoryRow = $DirectoryKept[$Index].Row
                $DirectoryPrincipalId = [string]$DirectoryRow.PrincipalId
                $DirectoryPrincipals[$Index] = if ([string]$DirectoryRow.PrincipalType -in @('User', 'Group') -and $PrincipalNameCache.ContainsKey($DirectoryPrincipalId)) {
                    [string]$PrincipalNameCache[$DirectoryPrincipalId]
                } else {
                    $DirectoryPrincipalId
                }
            }
            # Entra does not keep group display names unique, so two groups holding one role and kind
            # can carry the same name -- or a group can carry another principal's name -- and export
            # two identical (role, principal, assignmentType) entries, which the validator refuses as
            # a duplicate and so invalidates the whole document. Every GROUP row whose name collides,
            # without regard to letter case, with another row of the same role definition id and kind
            # is named by its object id instead; principalType stays Group. Repeated until nothing
            # changes, since a group's id can in turn equal another group's display name. Each pass
            # moves at least one group to its id, so it ends; only groups ever move.
            do {
                $DirectoryNameCount = [System.Collections.Generic.Dictionary[string, int]]::new([System.StringComparer]::OrdinalIgnoreCase)
                for ($Index = 0; $Index -lt $DirectoryKept.Count; $Index++) {
                    $CollisionKey = "$($DirectoryKept[$Index].Row.RoleDefinitionId)|$($DirectoryKept[$Index].Kind)|$($DirectoryPrincipals[$Index])"
                    $DirectoryNameCount[$CollisionKey] = 1 + $(if ($DirectoryNameCount.ContainsKey($CollisionKey)) { $DirectoryNameCount[$CollisionKey] } else { 0 })
                }
                $DirectoryRenamed = $false
                for ($Index = 0; $Index -lt $DirectoryKept.Count; $Index++) {
                    $DirectoryRow = $DirectoryKept[$Index].Row
                    if ([string]$DirectoryRow.PrincipalType -ne 'Group') { continue }
                    if ($DirectoryPrincipals[$Index] -eq [string]$DirectoryRow.PrincipalId) { continue }
                    $CollisionKey = "$($DirectoryRow.RoleDefinitionId)|$($DirectoryKept[$Index].Kind)|$($DirectoryPrincipals[$Index])"
                    if ($DirectoryNameCount[$CollisionKey] -gt 1) {
                        $DirectoryPrincipals[$Index] = [string]$DirectoryRow.PrincipalId
                        $DirectoryRenamed = $true
                    }
                }
            } while ($DirectoryRenamed)

            $DirectoryEntries = [System.Collections.Generic.List[object]]::new()
            for ($Index = 0; $Index -lt $DirectoryKept.Count; $Index++) {
                $Kept = $DirectoryKept[$Index]
                $DirectoryRow = $Kept.Row
                $DirectoryPrincipalType = [string]$DirectoryRow.PrincipalType
                $Proj = [ordered]@{
                    role      = $(if ($DirectoryRow.RoleName) { [string]$DirectoryRow.RoleName } else { [string]$DirectoryRow.RoleDefinitionId })
                    principal = $DirectoryPrincipals[$Index]
                }
                if ($DirectoryPrincipalType) { $Proj.principalType = $DirectoryPrincipalType }
                $Proj.assignmentType = $Kept.Kind
                # DurationDays is the schedule window in whole days as the reader reconstructed it
                # through Resolve-OEREligibilityDuration -- the measure the apply engine compares
                # against -- so a re-applied export is Unchanged. A permanent assignment carries
                # neither durationDays nor permanent: the absence is how the document says permanent.
                if ($null -ne $DirectoryRow.DurationDays) { $Proj.durationDays = [int]$DirectoryRow.DurationDays }
                if ($IncludeId) { $Proj.id = [string]$DirectoryRow.ScheduleId }
                $DirectoryEntries.Add([PSCustomObject]$Proj)
            }
            # Role, then Eligible before Active, then principal -- ordinal, ignoring letter case, so
            # the document reads the same on every run and every machine.
            $DirectoryEntries.Sort([System.Comparison[object]] {
                    param($Left, $Right)
                    $Order = [System.StringComparer]::OrdinalIgnoreCase.Compare([string]$Left.role, [string]$Right.role)
                    if ($Order -eq 0) {
                        $LeftRank = if ($Left.assignmentType -eq 'Eligible') { 0 } else { 1 }
                        $RightRank = if ($Right.assignmentType -eq 'Eligible') { 0 } else { 1 }
                        $Order = $LeftRank.CompareTo($RightRank)
                    }
                    if ($Order -eq 0) {
                        $Order = [System.StringComparer]::OrdinalIgnoreCase.Compare([string]$Left.principal, [string]$Right.principal)
                    }
                    $Order
                })
            foreach ($DirectoryEntry in $DirectoryEntries) { $DirectoryRoleAssignments.Add($DirectoryEntry) }
        }

        if ($IncludeDirectoryPolicies) {
            $DirectoryPolicies = @()
            $DirectoryPoliciesRead = $false
            try {
                $DirectoryPolicies = @(Get-OERDirectoryRoleManagementPolicy -All -ErrorAction Stop)
                $DirectoryPoliciesRead = $true
            } catch {
                Remove-OERErrorRecord -Record $PSItem
                $DirectoryCause = "Could not read the Microsoft Entra directory role management policies: $($PSItem.Exception.Message)"
                Write-Verbose "Get-OERInventory: $DirectoryCause"
                Add-UnreadCause -Cause $DirectoryCause
                $UnreadCollections.Add('directoryRoleManagementPolicies')
            }
            if ($DirectoryPoliciesRead) {
                if (-not $AllDirectoryRolePolicies) {
                    # The policy of every role that has at least one row in the tenant-scope schedule
                    # reads -- the UNFILTERED rows, so a role held only through a group or only as an
                    # activation still counts. A policy customized on a role nobody holds is exported
                    # only by -AllDirectoryRolePolicies.
                    $DirectoryRolesInUse = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
                    foreach ($DirectoryKind in @('Eligible', 'Active')) {
                        foreach ($DirectoryRow in @($DirectoryRows[$DirectoryKind])) {
                            if ($DirectoryRow -and $DirectoryRow.RoleDefinitionId) { $null = $DirectoryRolesInUse.Add([string]$DirectoryRow.RoleDefinitionId) }
                        }
                    }
                    # A selection made from an incomplete read still exports the roles the read that
                    # succeeded found, but is reported as partial, never presented as complete.
                    if (-not ($DirectoryRead.Eligible -and $DirectoryRead.Active)) {
                        $UnreadCollections.Add('directoryRoleManagementPolicies/role selection')
                    }
                    $DirectoryPolicies = @($DirectoryPolicies | Where-Object { $_ -and $DirectoryRolesInUse.Contains([string]$_.RoleDefinitionId) })
                }
                $DirectoryPolicyEntries = [System.Collections.Generic.List[object]]::new()
                foreach ($DirectoryPolicy in $DirectoryPolicies) {
                    if ($null -eq $DirectoryPolicy) { continue }
                    $DirectoryPolicyEntry = ConvertTo-OERInventoryRoleManagementPolicy -Policy $DirectoryPolicy -Directory
                    if ($IncludeId) { $DirectoryPolicyEntry | Add-Member -NotePropertyName 'id' -NotePropertyValue ([string]$DirectoryPolicy.PolicyId) }
                    $DirectoryPolicyEntries.Add($DirectoryPolicyEntry)
                }
                $DirectoryPolicyEntries.Sort([System.Comparison[object]] {
                        param($Left, $Right)
                        [System.StringComparer]::OrdinalIgnoreCase.Compare([string]$Left.role, [string]$Right.role)
                    })
                foreach ($DirectoryPolicyEntry in $DirectoryPolicyEntries) { $DirectoryRoleManagementPolicies.Add($DirectoryPolicyEntry) }
            }
        }

        if ($Include -contains 'RoleManagementPolicies') {
            $RoleSources = @()
            if ($Role) { $RoleSources += 'Role' }
            if ($CommonRoles) { $RoleSources += 'CommonRoles' }
            if ($AllRolesAtScope) { $RoleSources += 'AllRolesAtScope' }
            $HasScope = [bool]($Scope -or $Subscription -or $ManagementGroup)

            if ($RoleSources.Count -gt 1) {
                Write-Warning 'RoleManagementPolicies: specify only one of -Role, -CommonRoles, or -AllRolesAtScope; section skipped.'
            }
            elseif ($RoleSources.Count -eq 0) {
                Write-Warning 'RoleManagementPolicies requires -Role, -CommonRoles, or -AllRolesAtScope; section skipped.'
            }
            elseif (-not $HasScope) {
                Write-Warning "RoleManagementPolicies: -$($RoleSources[0]) requires a target scope (-Scope, -Subscription or -ManagementGroup); section skipped."
            }
            else {
                $ScopeParams = @{}
                if ($Scope) { $ScopeParams.Scope = $Scope }
                if ($Subscription) { $ScopeParams.Subscription = $Subscription }
                if ($ManagementGroup) { $ScopeParams.ManagementGroup = $ManagementGroup }

                $Policies = @(
                    if ($CommonRoles) { Get-OERRoleManagementPolicy -CommonRoles @ScopeParams }
                    elseif ($AllRolesAtScope) { Get-OERRoleManagementPolicy -AllRolesAtScope @ScopeParams }
                    else { foreach ($R in $Role) { Get-OERRoleManagementPolicy -Role $R @ScopeParams } }
                )
                $RmpSeen = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
                foreach ($Rmp in $Policies) {
                    # ConvertTo-OERInventoryRoleManagementPolicy owns the entry shape, shared with the
                    # directoryRoleManagementPolicies section; without -Directory it is the Azure
                    # roleManagementPolicies entry, scope first.
                    $RmpEntry = ConvertTo-OERInventoryRoleManagementPolicy -Policy $Rmp
                    # The same policy read twice (-Role Reader,Reader, for one) would be two entries
                    # the validator refuses as a duplicate. The scope is compared in the canonical
                    # form the validator uses, the role without regard to letter case. Dropping the
                    # second loses nothing, since it is the one policy, so nothing is reported.
                    if (-not $RmpSeen.Add("$(ConvertTo-OERCanonicalScope -Scope ([string]$RmpEntry.scope))|$($RmpEntry.role)")) { continue }
                    if ($IncludeId) { $RmpEntry | Add-Member -NotePropertyName 'id' -NotePropertyValue $Rmp.PolicyId }
                    $RoleManagementPolicies.Add($RmpEntry)
                }
            }
        }

        # Select-UniqueNamedEntry runs while these arguments are evaluated, which is before the
        # InventoryPartial check below, so the objects it leaves out are reported with the rest.
        ConvertTo-OERInventory `
            -TenantId $DocumentTenantId `
            -Groups @(Select-UniqueNamedEntry -Entry $Groups.ToArray() -Section 'groups' -KeyOf { param($E) $E.displayName }) `
            -AdministrativeUnits @(Select-UniqueNamedEntry -Entry $AdministrativeUnits.ToArray() -Section 'administrativeUnits' -KeyOf { param($E) $E.displayName }) `
            -Catalogs @(Select-UniqueNamedEntry -Entry $Catalogs.ToArray() -Section 'catalogs' -KeyOf { param($E) $E.displayName }) `
            -AccessPackages @(Select-UniqueNamedEntry -Entry $AccessPackages.ToArray() -Section 'accessPackages' -KeyOf { param($E) "$($E.catalog)|$($E.displayName)" } -NameOf { param($E) "$($E.catalog)/$($E.displayName)" }) `
            -AccessReviews @(Select-UniqueNamedEntry -Entry $AccessReviews.ToArray() -Section 'accessReviews' -KeyOf { param($E) $E.displayName }) `
            -DirectoryRoleManagementPolicies $DirectoryRoleManagementPolicies.ToArray() `
            -DirectoryRoleAssignments $DirectoryRoleAssignments.ToArray() `
            -RoleAssignments $RoleAssignments.ToArray() `
            -RoleManagementPolicies $RoleManagementPolicies.ToArray()

        # Emitted AFTER the inventory object so a caller still receives the document it has to
        # inspect, then learns that part of it was never read -- the same ordering
        # Export-OERInventory already uses for its own InventoryPartial.
        if ($UnreadCollections.Count -gt 0) {
            # Appended, not substituted: the triples stay exactly as they are (Export-OERInventory
            # folds -TargetObject into IncompleteReads verbatim). This clause only adds the WHY, so
            # an operator can tell a 429 (retry the export) from a 403 (grant a scope).
            # Capped, and the truncation is STATED. The causes are deduplicated on a normalised key
            # (see Add-UnreadCause), so this clause only grows when the failures genuinely differ --
            # but a large tenant can still differ in many ways, and an error message thousands of
            # causes long is unreadable and unloggable. The suppressed count is derived rather than
            # counted, so it can never disagree with what the list actually holds.
            $SuppressedCauses = $UnreadCauseKeys.Count - $UnreadCauses.Count
            $CauseClause = if ($UnreadCauses.Count -gt 0) {
                $MoreClause = if ($SuppressedCauses -gt 0) { ", plus $SuppressedCauses more distinct cause(s) not shown -- rerun with -Verbose for all of them" } else { '' }
                " Causes: $($UnreadCauses -join '; ')$MoreClause."
            } else { '' }
            Write-CmdletError `
                -Message ([System.Exception]::new(
                    "This inventory is PARTIAL: $($UnreadCollections.Count) collection(s) or object(s) could not be read, could not be written without an empty name, or were left out because two or more live objects share a name, and are not stated as facts in the document (an accessReviews entry named as unread may still carry an id where a name could not be read). " +
                    "Unread: $($UnreadCollections -join ', '). A section reported here by its name alone could not be read at all and is written as an empty array, which does not mean the tenant has none. A members, scopedRoles, resources or resourceRoles key reported here is an explicit null, which the apply engine reads as " +
                    'leave untouched; do not hand-edit it to an empty array, and do not treat this document as a full tenant snapshot.' +
                    $CauseClause)) `
                -ErrorId 'InventoryPartial' `
                -Category LimitsExceeded `
                -TargetObject ($UnreadCollections -join ', ') `
                -Cmdlet $PSCmdlet
        }
    }
}
