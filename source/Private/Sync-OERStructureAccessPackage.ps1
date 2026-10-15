function Sync-OERStructureAccessPackage {
    <#
    .SYNOPSIS
    Reconciles one accessPackages[] document entry against the live Entra ID tenant.

    .DESCRIPTION
    The orchestration handler for a single access package entry from the structure document. It is
    called by the Invoke-OERStructure engine and emits one or more ConvertTo-OERStructureResult
    records describing what was created, updated, removed, skipped, or left unchanged.

    displayName is the match key within the declared catalog (names are unique per catalog, not
    tenant-wide): an existing package is matched and updated by it. To rename a package, the
    document declares its new name as displayName and its current name as previousDisplayName, and
    both names are matched in the declared catalog's package list on every run, before anything
    else is read or written (Resolve-OERStructureRename owns the decision, its error ids and its
    texts; BL-128, A5):
    - Both match DIFFERENT packages of the catalog: the item emits exactly one Failed row and a
      non-terminating AccessPackageRenameConflict error (category ResourceExists, target the new
      name), and nothing else is read or written for it -- the document never merges two packages.
    - Only previousDisplayName matches: that package takes the existing-package path, and the rename
      is folded into the step-1 property update (Set-OERAccessPackage -NewDisplayName, in the same
      call as every other changed property), reported as one Updated row "renamed access package
      '<previous>' to '<new>'", or under -WhatIf one Skipped row "would rename access package
      '<previous>' to '<new>'" with the resource roles and assignment policies planned against the
      package found under its previous name. When that update fails, the Failed row is the last
      one: no resource role or assignment policy is reconciled.
    - Both match the SAME package, or only displayName matches: the item is applied normally (the
      rename is already done; a second run reports Unchanged).
    - Neither matches: the item emits exactly one Failed row and a non-terminating
      AccessPackageRenameNotFound error (category ObjectNotFound, target the new name), and nothing
      is created, read further or written for it, under -WhatIf too. A document that declares a
      rename names a package that already exists; a package is created only by an entry WITHOUT
      previousDisplayName.
    previousDisplayName also accepts the package's object id, matched only against the Id of a
    package in the declared catalog's list, which is already read (no request of its own): an id of
    a package in another catalog, or of a deleted one, counts as not matching. A previous name that
    several packages of the catalog carry is refused like a displayName several carry: one Failed
    row naming every id, nothing written; declare previousDisplayName as the object id then. A
    changed displayName WITHOUT previousDisplayName still creates a new package under the new name
    and leaves the old one in place; there is no top-level Extra reporting for access packages, so
    that one is left in place silently. With -RenameMap the decision is registered in the run's rename
    map, under 'accessPackages|<new name>', so a reference to the package's new name later in the same
    run, read through Get-OERStructureRenameTarget, reaches the package found under its previous name,
    or is refused when its rename was; see .PARAMETER RenameMap. An entry that renames nothing is
    registered there too (BL-147): the package it found in its catalog, or created there, by its id, and
    refused until then, so an access review in the same run that names the package by name reaches that
    package, or is refused, and never one of that name in another catalog.

    A catalog the same document renames (a catalogs[] entry with previousDisplayName) is addressed
    through the run's rename map (-RenameMap): Microsoft Graph's name lookup may not find the
    catalog's new name yet, and under -WhatIf the rename is not even sent, so every call that names
    the catalog -- the package list, the package create, the catalog resource read and the resource
    role add -- passes the id the catalogs handler registered for it. The rows still name the
    catalog as the document does. A catalog whose rename was refused (a conflict, or neither name
    found), or that this run could not decide (one of its names could not be looked up, or -Include
    leaves the catalogs section out), is not the catalog the document means, whatever now carries its
    new name: the package gets one Failed row naming the refused rename and why (its error id, or what
    kept the run from deciding it), and nothing is created, read or written for it. That row
    publishes no error record of its own; a refused rename's error is on the catalog's own row.

    Once the package has been resolved (or created), every downstream call that has to identify it --
    the property re-read, the resourceRoleScopes read, the resource role add and prune, the assignment
    policy read, and the assignment policy create -- passes the resolved access package ID, never the
    display name. Passing the display name would send those calls through Resolve-OERAccessPackageId,
    whose lookup is TENANT-WIDE, discarding the catalog scoping and either acting on an identically
    named package in another catalog or failing with AmbiguousName. Resolve-OERAccessPackageId treats
    a GUID as an id and returns it unchanged, so an id binds through every -AccessPackage parameter;
    since issue #71 that costs one existence read rather than no Graph call at all, which does not
    change the binding, only its price.

    Processing order within a single access package entry:

    1. Create the access package when absent, or diff and update the mutable description and the
       hidden flag when it already exists (and its displayName, when previousDisplayName renames
       it). The catalog property is creation-only and is never changed on an existing package.
       New-OERAccessPackage looks for an existing package by name in the whole tenant, so when the
       package has to be created while a package of that name exists in another catalog, it returns
       that package: the entry is then one Failed row, and nothing is written to that package or for
       the entry.

    2. Reconcile declared resourceRoles (add missing bindings; emit Extra or prune undeclared
       bindings with -Prune, or report them Skipped while a declared resource cannot be resolved --
       see "Withheld prune" below). Each binding is identified by the resource's OriginId and the
       role display name. The declared resource name resolves to an OriginId in this order: the
       group Resolve-OERGroupId finds under that name (or object id) when that group is a resource of
       the catalog -- so a renamed group is found under its CURRENT name, and never confused with
       another GROUP the catalog recorded under that name; else the catalog resource recorded
       under that display name (Get-OERCatalogResource; applications, SharePoint sites, and a group
       under the name the catalog recorded); else the group's id. A name that SEVERAL catalog
       resources carry is refused rather than resolved to the first of them (a catalog does not
       enforce unique resource display names), and so is a name a group resolves to while a resource
       that is not a group (an application, a site) is recorded under the same name in the catalog:
       that entry gets one Failed row and one AmbiguousName error naming every candidate origin id,
       no binding is added for it, and it counts as unresolved for the withheld prune below. The same
       goes for a name that a group OUTSIDE the catalog carries now while the one catalog resource
       recorded under it is another group (the catalog keeps the name a group had when it was
       added, so that group may since have been renamed): both ids are named. Declare a group or an
       application by one of the origin ids listed, or refresh or remove and re-add one of the
       resources in the catalog so their recorded names differ (renaming a resource at its source
       does not change the name the catalog recorded; a SharePoint site's origin id is its URL, which
       a document cannot name). A group id that is not a resource of the catalog is still tried, so the
       add fails with the real reason, but that entry counts as unresolved too: no live binding can
       belong to it. Under -WhatIf a group that the same run would add to the catalog is not in the
       catalog yet when this handler reads it, so it reads as that case and the plan withholds the
       binding prune, while the real run (the group then in the catalog) prunes -- the engine's
       existing precedent for objects the same run would create.
       Existing bindings are read via a raw Graph call against resourceRoleScopes.
       NOTE: the $expand shape used for resourceRoleScopes is a live-verify item -- the mock tests
       fix the shape and live testing confirms it.

    3. Reconcile declared assignmentPolicies (UPSERT). When a declared policy's displayName matches
       an existing policy, the handler builds the desired policy parts from the declared entry fields
       (requestor scope, requestor settings, the full per-stage approver set, the approval toggles, the
       expiration, and the notification toggle), assembles a desired body with ConvertTo-OERPolicyBody,
       projects it with ConvertTo-OERAssignmentPolicy, and diffs that desired projection against the
       current policy projection (read via Get-OERAccessPackageAssignmentPolicy) with
       Resolve-OERAssignmentPolicyChange, comparing only the fields the entry actually declares. On a
       difference it calls Set-OERAccessPackageAssignmentPolicy with the declared sub-objects and
       scalars and reports Updated (with the changed field names); no difference reports Unchanged. An
       undeclared requestorScope is never sent on update -- the live scope (including any
       SpecificDirectoryUsers targets) is preserved by Set-OERAccessPackageAssignmentPolicy instead of
       being reset to the AllMemberUsers default. Three requestor scopes are refused rather than
       written, each as a Failed row for that policy reached before ShouldProcess, so also under
       -WhatIf, with nothing written for it: a live policy whose allowedTargetScope reads as
       unknownFutureValue (whatever the entry declares; the module never sends the
       'Prefer: include-unknown-enum-members' header that would name it); a declared
       SpecificDirectoryServicePrincipals scope (New-OERAccessPackageRequestorScope refuses it with
       InvalidPolicyInput, since its service principal targets are not modelled -- on create too); and
       an UPDATE that would send a declared SpecificConnectedOrganizationUsers scope, whose
       connected organization targets are not modelled either, so the write would drop them. Omit
       requestorScope from such an entry to update the other fields while keeping the live scope. A
       declared SpecificConnectedOrganizationUsers that does not differ reports Unchanged, and a
       create with it is not refused. An absent policy is created from the same desired
       parts with New-OERAccessPackageAssignmentPolicy. Explicit per-approver identities ARE now
       diffed: -User/-Group, -Manager/-ManagerLevel,
       -InternalSponsor/-ExternalSponsor, -AlternateUser/-AlternateGroup, -EscalationDays,
       -RequireJustification, and -ApproverInfoVisibility all flow from the declared stage. The
       back-compat approver fallback is retained: ONLY for a stage that declares manager:false/absent
       AND no explicit users/groups/sponsors, the Tenant Profile PrimaryApprovers (primary) and
       EscalationApprovers (alternate) defaults are used. A stage with no manager, no explicit
       approvers, and no PrimaryApprovers default emits Failed for that policy and is skipped. A
       live policy whose displayName is not declared is reported as Extra and is NEVER removed by
       this handler, regardless of -Prune -- use Remove-OERAccessPackageAssignmentPolicy directly.
       A displayName that SEVERAL live policies of the package share is refused rather than resolved
       to the first of them (Microsoft Graph does not enforce unique policy names within a package):
       that declared policy gets one Failed row and one AmbiguousName error naming every candidate id,
       nothing is created or updated for it, and the package's other declared policies are processed
       as before. Rename one of the duplicates in the tenant to clear it.
       To rename a policy, the entry declares its new name as displayName and its current name as
       previousDisplayName (BL-128). Both names are matched in the package's policy list, which is
       already read, before anything is built or written for the policy, and Resolve-OERStructureRename
       decides exactly as it does for the package (its error ids and texts):
       - Both match DIFFERENT policies of the package: one Failed row and a non-terminating
         AssignmentPolicyRenameConflict error (category ResourceExists, target the new name).
       - Neither matches: one Failed row and a non-terminating AssignmentPolicyRenameNotFound error
         (category ObjectNotFound, target the new name); nothing is created for it. That includes every
         policy that declares previousDisplayName in a package this call creates, and under -WhatIf in
         a package it would create (planned as that refusal, never as a create).
       - Only previousDisplayName matches: that policy takes the existing-policy path, and the rename is
         -DisplayName in its one Set-OERAccessPackageAssignmentPolicy call, with every declared field;
         the call is sent even when no declared field differs. It is reported as one Updated row
         "renamed assignmentPolicy '<previous>' to '<new>'", followed by "; updated assignmentPolicy
         fields (<fields>)" when fields differ, or under -WhatIf one Skipped row "would rename
         assignmentPolicy '<previous>' to '<new>'" (and "; would update assignmentPolicy fields
         (<fields>)"); a failed call is one Failed row "failed to rename assignmentPolicy '<previous>'
         to '<new>': <error>". When previousDisplayName is an object id, these texts and the
         ShouldProcess prompt name the policy by its current name and id instead: '<current name>'
         (<id>).
       - Both match the SAME policy, or only displayName matches: applied normally (a second run
         reports Unchanged).
       Each Failed row is a row of the package, with a Detail starting "assignmentPolicy '<new name>': ",
       and nothing is built, created or written for that policy; the package's other declared policies
       carry on. previousDisplayName also accepts the policy's object id, matched only against the Id of
       a policy of this package, without regard to letter case: an id of another package's policy, or of
       a deleted one, matches nothing. A previous name that several policies of the package carry is
       refused like an ambiguous displayName: one Failed row and one AmbiguousName error (target the
       previous name) naming every id, nothing written; declare previousDisplayName as the object id
       then. A live policy that a declared previousDisplayName names is not reported as Extra, unless
       the entry's own displayName was refused first as one several policies share (that refusal names
       only the displayName's policies). A changed displayName WITHOUT previousDisplayName still creates
       a new policy under the new name and reports the old one as Extra.

    When -Prune is set, current resource role bindings whose (role.displayName, scope.originId)
    pair is not declared are removed (with Write-Warning) after a ShouldProcess gate. Without
    -Prune those extras are reported as Extra (informational) and left alone. -Prune is scoped to
    resource role bindings only -- it never removes an undeclared assignment policy (see above).

    Withheld prune: a declared resourceRoles entry is unresolved when its resource name matches no
    resource in the catalog by display name and Resolve-OERGroupId finds no group by that name
    either, when it matches SEVERAL catalog resources, a group plus a non-group resource, or a group
    outside the catalog plus another group the catalog recorded under that name (refused, see
    above), and when it resolves to a group that is not in the catalog (its add fails; under -WhatIf
    that includes a group the same run would add to the catalog, so the plan withholds a prune the
    real run performs). Such an
    entry carries no origin id of a live binding, so the pass cannot tell which live binding it names,
    and its live counterpart would otherwise look undeclared. While any declared entry is unresolved,
    every undeclared live binding of the package is reported Skipped, with a Detail that starts
    "prune withheld: declared entry '<resource>' could not be resolved" (several unresolved entries:
    "declared entries '<resource1>', '<resource2>' could not be resolved"), with or without -Prune;
    no warning is written, no ShouldProcess prompt is issued, and no binding is removed until the
    entry is fixed or removed from the document (ConvertTo-OERPruneWithheldResult owns the rule and
    the text). The unresolved entry keeps its own record: Failed when it was refused or could not be
    resolved, and for a group outside the catalog whatever its attempted add reports (Failed
    normally, Skipped under -WhatIf, Unchanged when that binding is already live, Created if the add
    succeeds) -- the record is lost only when the
    handler later throws for the same item, see below. A Resolve-OERGroupId lookup that THROWS, rather than
    finding nothing, is not caught by this handler (a name matching several groups, once no catalog
    resource carries that name either): it ends the item where it is thrown, neither the
    resource role prune nor the assignment policy step runs, and the engine reports the item as one
    Failed ("handler error") record, discarding every record the handler had already emitted for it
    (a Created package or an added binding stands with no row).

    A failed read of the package's live state -- the resource role bindings, the assignment policies,
    or the declared catalog's resources -- reports Failed with the underlying ErrorRecord and
    reconciles nothing further for that item, so a Created row is never derived from a read that did
    not succeed; an empty read that SUCCEEDED still reconciles normally.

    Every write is gated by $Caller.ShouldProcess. Under -WhatIf that returns $false; the handler
    emits Skipped records instead of calling child cmdlets. When the access package itself does not
    exist and its creation is skipped under -WhatIf, no child read or write calls are made: the plan
    is one "would create access package" row, a "would configure resourceRole" row for each declared
    resource role and a "would create assignmentPolicy ... after access package is created" row for
    each declared assignment policy that declares no previousDisplayName (one that declares it gets
    its AssignmentPolicyRenameNotFound row and error instead, see step 3).

    A package declared in a catalog the same -WhatIf plan would create (-PlannedCatalog) is planned
    that way without any read: the catalog does not exist yet, so the catalog-scoped lookup of the
    package would fail with CatalogNotFound and report the package Failed ("the access package was NOT
    created") while the real run creates the catalog and then the package. An entry in a catalog
    the plan would create that declares previousDisplayName is not planned as created: nothing can
    be renamed in a catalog that does not exist yet, so it fails with AccessPackageRenameNotFound, as
    an entry neither of whose names matches. A catalog that is neither in -PlannedCatalog nor in the
    tenant still fails the package, with or without -WhatIf.

    .PARAMETER Item
    One element from the accessPackages[] array in the structure document, as a PSCustomObject
    produced by ConvertFrom-Json.

    .PARAMETER Caller
    The engine's $PSCmdlet reference, used to gate writes with ShouldProcess and to route errors
    with WriteError. The engine passes its own $PSCmdlet here.

    .PARAMETER Prune
    When set, current resource role bindings not in the declared set are removed after a
    ShouldProcess gate. Without this switch, extra bindings are only reported as Extra and never
    deleted. An omitted resourceRoles key still reconciles this way; an explicit
    "resourceRoles": null does not reconcile at all -- null, not an omitted key, is how a package
    is declared without touching its resource role bindings. Scoped to resource role bindings
    only: an undeclared assignment policy is always reported as Extra and is never removed, with
    or without -Prune -- call Remove-OERAccessPackageAssignmentPolicy directly to delete one.
    While a declared resourceRoles entry cannot be resolved (its resource matches no catalog
    resource and no group, several catalog resources, a group plus a same-named non-group resource,
    or a group outside the catalog), no binding is removed or reported Extra: every undeclared live binding
    is reported Skipped with a Detail starting "prune withheld:", with or without this switch. A
    lookup that throws aborts the item instead, before the resource role prune.

    .PARAMETER TenantAlias
    Optional Tenant Profile alias forwarded to Resolve-OERStructureDefault so that omitted
    assignmentPolicy approver fields can be resolved from the stored tenant defaults.

    .PARAMETER PlannedCatalog
    Optional list of the catalog names a -WhatIf plan would create in this run, filled by
    Sync-OERStructureCatalog (only under -WhatIf, when it reports "would create catalog") and passed
    on by Invoke-OERStructure. A package whose catalog is in the list (compared without regard to
    letter case) skips the catalog-scoped lookup and is planned as created, with its resource roles
    and assignment policies. When the list is omitted, empty or does not hold the catalog, the lookup
    runs as it always has. A real run never fills the list, so it is not affected.

    .PARAMETER RenameMap
    Optional run-scoped rename map Invoke-OERStructure creates once per document. The catalogs handler
    fills it (through Resolve-OERStructureRename) for every catalogs[] entry whose previousDisplayName
    renames the catalog, is refused or cannot be decided, and Invoke-OERStructure marks every such
    entry undecided when -Include leaves the catalogs section out. This handler reads it, through
    Get-OERStructureRenameTarget, for the entry's catalog: an entry naming the id of a catalog the run
    renames makes every call that names the catalog pass that id, and an entry naming a refused or
    undecided rename fails the package with nothing created, read or written. When the map is omitted
    or does not hold the catalog, the catalog is named as the document names it, as it always has been.
    This handler also fills it for its own entry (R12). First of all, before the catalog is read from
    the map, it marks the package, when the entry declares previousDisplayName, and every assignment
    policy that declares one as undecided: refused with no id, the reason "the accessPackages entry did
    not reach a decision in this run; see that entry's rows". A policy's mark is registered under
    'assignmentPolicies|<package>|<policy>' (the package as this entry's displayName names it). Every
    such policy is marked again under the same key with a package's id as well, as soon as the entry
    knows the id of a package it may mean: the existing package found, before anything else is read or
    written for it; both packages of a refused rename conflict; and every package of the catalog that
    carries the entry's displayName, or its previousDisplayName together with the one that carries the
    displayName, when that name is refused as ambiguous. So a reference that names any of them by
    object id is refused too while the policy is undecided. Each decision replaces its
    mark through Resolve-OERStructureRename: the package under 'accessPackages|<name>', a policy under
    both of its keys; a rename registers the object's id, a refusal registers it refused with its error
    id, and a name that already finds the object removes the mark. The registration is made when the
    decision is, so under -WhatIf too and before the rename is sent. A mark that no decision replaces --
    the entry stopped first: the catalog refused, a failed or ambiguous lookup, a refused package
    rename, a create that returned another catalog's package, a failed package re-read, a failed
    package update that renames it, a failed read of its resource role bindings, of the catalog's
    resources or of its policies, an ambiguous policy name -- stays, so a reference to the new name
    later in this run, read through Get-OERStructureRenameTarget, is refused instead of being looked
    up by name. A policy of an entry that stopped before it knew any package id -- the catalog
    refused, a failed package list read, a package rename that found neither name, a create that
    returned another catalog's package -- is marked under the package's name only, so a reference
    that names a package by object id then looks the policy up by name within that package, as
    before this map existed. Without the map nothing is registered.
    Every entry with a displayName that is not empty registers its package, not only a rename (BL-147,
    R-8; docs/development/rationale.md#review-package-in-the-same-run). An entry that renames nothing
    -- no previousDisplayName, or one that is empty -- is marked first of all, through
    Resolve-OERStructureRename -Unidentified, as refused with no previous name and the reason "the
    accessPackages entry did not find or create it; see that entry's rows". It registers the package's
    id (-Identified) as soon as it has the package: the existing package found in the declared catalog,
    before anything else is read or written for it (also after a Current rename outcome, which removed
    the mark), or the package it created there, once the created package is shown not to be another
    catalog's. A rename keeps its own registration. A stop before that -- the catalog refused, a failed
    or ambiguous lookup, a refused rename, a failed create, a create that returned another catalog's
    package -- leaves the refusal, and a failure after it (an update, the resource role bindings, the
    assignment policies) does not take the id back. A package that the -WhatIf plan would create, or
    whose creation a declined confirmation skipped, is registered refused with the reason "the
    accessPackages entry would create it, and the create was not carried out: -WhatIf, or a declined
    confirmation": it has no id yet, so a review of it is Failed in the plan where the real run creates
    the package (an accepted limit).

    .EXAMPLE
    Sync-OERStructureAccessPackage -Item $DocItem -Caller $PSCmdlet -Prune -TenantAlias 'omnicit'
    Reconciles one access package entry from the document, pruning undeclared resource role
    bindings and resolving approver defaults from the omnicit Tenant Profile.
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute(
        'PSShouldProcess', '',
        Justification = 'ShouldProcess is delegated to $Caller (the engine PSCmdlet) via $Caller.ShouldProcess(); this private handler does not carry its own SupportsShouldProcess because it never creates its own $PSCmdlet.'
    )]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute(
        'PSUseSingularNouns', 'Build-OERPolicyParts',
        Justification = 'Build-OERPolicyParts is a private nested helper whose plural noun accurately describes the composite parts object it returns; renaming would obscure intent.'
    )]
    [OutputType([PSCustomObject])]
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][PSCustomObject]$Item,
        [Parameter(Mandatory)][System.Management.Automation.PSCmdlet]$Caller,
        [switch]$Prune,
        [string]$TenantAlias,
        [System.Collections.Generic.List[string]]$PlannedCatalog,
        [System.Collections.Generic.Dictionary[string, object]]$RenameMap
    )
    process {
        # -- Resolve the display name -------------------------------------------------------
        $Name = $Item.displayName

        # R12 (BL-128): before anything else -- the catalog check and every lookup included -- the
        # package, when the entry declares previousDisplayName, and each assignment policy that declares
        # one are marked undecided in the run's rename map. Each decision below replaces its mark
        # (Resolve-OERStructureRename owns the keys); every early return leaves the marks that were not
        # yet decided, so a reference to a new name later in the same run, read through
        # Get-OERStructureRenameTarget, is refused instead of being looked up by name, which could reach
        # another object that carries that name. A name that is empty after string conversion (an empty
        # string, or a missing or null value) is not marked -- the package's displayName, its
        # previousDisplayName, a policy's displayName or its previousDisplayName: the validator refuses
        # such an entry, and the helper's parameter binding would otherwise end the item in this block.
        # BL-147 (R-8): an entry that renames nothing is marked too, as refused with no previous name until
        # it registers the id of the package it found or created (below), so a review that names the package
        # by its name is refused instead of looking it up in the whole tenant, where a package of that name
        # in another catalog would be found. docs/development/rationale.md#review-package-in-the-same-run
        if ($null -ne $RenameMap -and -not [string]::IsNullOrEmpty([string]$Name)) {
            $UndecidedReason = "the accessPackages entry did not reach a decision in this run; see that entry's rows"
            if ((Test-OERDeclaredProperty -Node $Item -Name 'previousDisplayName') -and
                -not [string]::IsNullOrEmpty([string]$Item.previousDisplayName)) {
                $null = Resolve-OERStructureRename -Section 'accessPackages' -Name ([string]$Name) `
                    -PreviousName ([string]$Item.previousDisplayName) -Undecided -Reason $UndecidedReason -RenameMap $RenameMap
            } else {
                $null = Resolve-OERStructureRename -Section 'accessPackages' -Name ([string]$Name) -Unidentified `
                    -Reason "the accessPackages entry did not find or create it; see that entry's rows" -RenameMap $RenameMap
            }
            if (Test-OERDeclaredProperty -Node $Item -Name 'assignmentPolicies') {
                foreach ($MarkPol in @($Item.assignmentPolicies)) {
                    if (-not (Test-OERDeclaredProperty -Node $MarkPol -Name 'previousDisplayName')) { continue }
                    if ([string]::IsNullOrEmpty([string]$MarkPol.displayName) -or [string]::IsNullOrEmpty([string]$MarkPol.previousDisplayName)) { continue }
                    $null = Resolve-OERStructureRename -Section 'assignmentPolicies' -AccessPackage ([string]$Name) `
                        -Name ([string]$MarkPol.displayName) -PreviousName ([string]$MarkPol.previousDisplayName) `
                        -Undecided -Reason $UndecidedReason -RenameMap $RenameMap
                }
            }
        }

        # R12 (BL-128): a review that names the package by an object id reads a policy's map entry under
        # the key built with that id, which only the policy's decision in Step 3 registers. Once this entry
        # knows the id of a package it may mean, a stop before that decision would leave the key empty, and
        # the review would look the policy's new name up by name within that package, where another policy
        # may carry it. So each renaming policy is marked undecided again under every such id: the package
        # found (Step 1), the two packages of a refused rename conflict, and every candidate of an ambiguous
        # name or previous name. Same reason and same skips as the first marks above; each decision in
        # Step 3 replaces the mark under its keys. It reads this entry's $Item, $Name, $RenameMap and
        # $UndecidedReason; without the map, or with a package name that is empty after string
        # conversion, the first marks were not made and it does nothing either.
        function Register-OERPolicyUndecidedMark {
            param([string[]]$PackageId)
            if ($null -eq $RenameMap -or [string]::IsNullOrEmpty([string]$Name) -or
                -not (Test-OERDeclaredProperty -Node $Item -Name 'assignmentPolicies')) { return }
            foreach ($MarkId in $PackageId) {
                foreach ($MarkPol in @($Item.assignmentPolicies)) {
                    if (-not (Test-OERDeclaredProperty -Node $MarkPol -Name 'previousDisplayName')) { continue }
                    if ([string]::IsNullOrEmpty([string]$MarkPol.displayName) -or [string]::IsNullOrEmpty([string]$MarkPol.previousDisplayName)) { continue }
                    $null = Resolve-OERStructureRename -Section 'assignmentPolicies' -AccessPackage ([string]$Name) `
                        -AccessPackageId $MarkId -Name ([string]$MarkPol.displayName) `
                        -PreviousName ([string]$MarkPol.previousDisplayName) -Undecided -Reason $UndecidedReason -RenameMap $RenameMap
                }
            }
        }

        # BL-128 (A5): a catalog the document renames in this run is found under its previous name, and
        # Graph's name lookup may not find the new name yet (under -WhatIf the rename is not even sent).
        # The catalogs handler registered it in the run's rename map, so this package addresses the
        # catalog by that id. A catalog whose rename was refused (a conflict, or neither name found) is
        # not the catalog the document means, whatever now carries its new name: nothing is read or
        # written for this package. Get-OERStructureRenameTarget owns the map's key.
        $CatalogRef = $Item.catalog
        # A rename this run could not decide (R12: one of the catalog's names could not be looked up, or
        # -Include leaves the catalogs section out) is refused the same way; Reason is the error id, or
        # what kept the run from deciding.
        $CatalogTarget = Get-OERStructureRenameTarget -Section 'catalogs' -Name ([string]$Item.catalog) -RenameMap $RenameMap
        if ($CatalogTarget -and $CatalogTarget.Refused) {
            ConvertTo-OERStructureResult -Section 'accessPackages' -Item $Name -Action 'Failed' `
                -Detail "catalog '$($Item.catalog)' was not reconciled in this run: its rename from '$($CatalogTarget.PreviousName)' was refused ($($CatalogTarget.Reason)), so the catalog this access package belongs to cannot be identified; nothing was created, read or written for it"
            return
        }
        if ($CatalogTarget) { $CatalogRef = $CatalogTarget.Id }

        # -- Check existence ----------------------------------------------------------------
        # Access package display names are unique per CATALOG, not per tenant, so resolve inside the
        # declared catalog. Get-OERAccessPackage's -DisplayName and -Catalog are mutually exclusive
        # parameter sets, so list by catalog and match the name client-side.
        # A declared previousDisplayName is resolved by every branch below, before anything else is
        # read or written, into $PrevId ($null when it matches nothing); Resolve-OERStructureRename
        # then decides once for all three branches.
        $ApId = $null
        $HasPrev = Test-OERDeclaredProperty -Node $Item -Name 'previousDisplayName'
        $PrevName = if ($HasPrev) { [string]$Item.previousDisplayName } else { $null }
        $PrevId = $null
        $RenameFrom = $null
        # BL-128 (A5): under -WhatIf a catalog the same document creates does not exist yet, so the
        # catalog-scoped lookup below would fail with CatalogNotFound and report the package Failed,
        # NOT created, while the real run creates it. Plan it as created instead. Only a name the
        # catalogs handler planned in this run is trusted; a missing catalog the document does not
        # declare still fails below.
        $CatalogPlanned = ($null -ne $PlannedCatalog) -and (@($PlannedCatalog) -icontains [string]$Item.catalog)
        if ($CatalogPlanned) {
            # $ApId stays $null: the package cannot exist in a catalog that does not exist yet, so
            # Step 1 takes its create branch, which under -WhatIf reports the plan and returns. $PrevId
            # stays $null too, so an entry that declares previousDisplayName fails below with
            # AccessPackageRenameNotFound instead: nothing can be renamed in a catalog that does not
            # exist yet, and such an entry is never planned as created.
            Write-Verbose "Access package '$Name': catalog '$($Item.catalog)' is created by this plan, so the catalog lookup is skipped."
        } elseif (Test-OERDeclaredProperty -Node $Item -Name 'catalog') {
            # A throw here (forced by -ErrorAction Stop) is a transport/permission/throttling failure on
            # the catalog-scoped read itself, or the catalog failing to resolve -- NOT evidence that no
            # package exists. Get-OERAccessPackage -Catalog reports every one of those (catalog not
            # found, ambiguous catalog name, or the underlying Graph list call failing) as its own
            # non-terminating WriteError and simply emits no objects, so without -ErrorAction Stop this
            # read is indistinguishable from a genuine "no match" and would fall through to CREATE a
            # duplicate high-privilege access package. Catch it and stop instead of ever creating.
            # The list is read once and matched for both names: displayName, and previousDisplayName
            # when the entry declares one.
            $InCatalogAll = $null
            $InCatalog = $null
            try {
                $InCatalogAll = @(Get-OERAccessPackage -Catalog $CatalogRef -ErrorAction Stop)
                $InCatalog = @($InCatalogAll | Where-Object { [string]$_.DisplayName -ieq $Name })
            } catch {
                Remove-OERErrorRecord -Record $PSItem
                $Caller.WriteError($PSItem)
                ConvertTo-OERStructureResult -Section 'accessPackages' -Item $Name -Action 'Failed' `
                    -Detail "failed to look up access packages in catalog '$($Item.catalog)': $($PSItem.Exception.Message); the access package was NOT created" `
                    -ErrorRecord $PSItem
                return
            }
            if ($InCatalog.Count -gt 1) {
                # Each package that carries the name may be the one the entry means (R12, see
                # Register-OERPolicyUndecidedMark).
                Register-OERPolicyUndecidedMark -PackageId @($InCatalog | ForEach-Object { [string]$_.Id })
                $Ids = ($InCatalog | ForEach-Object { [string]$_.Id }) -join ', '
                ConvertTo-OERStructureResult -Section 'accessPackages' -Item $Name -Action 'Failed' `
                    -Detail "catalog '$($Item.catalog)' holds $($InCatalog.Count) access packages named '$Name' ($Ids); the display name cannot identify one"
                return
            }
            if ($InCatalog.Count -eq 1) { $ApId = [string]$InCatalog[0].Id }
            if ($HasPrev) {
                # An object id matches only the Id of a package in THIS catalog's list (R5): a probe by
                # id would also find a package of another catalog and rename it. An id the list does
                # not hold -- another catalog's package, or a deleted one -- matches nothing, so it is
                # never a conflict and never a create. The match takes the id as the list spells it.
                $PrevMatch = if (Test-OERGuid -Value $PrevName) {
                    @($InCatalogAll | Where-Object { [string]$_.Id -ieq $PrevName })
                } else {
                    @($InCatalogAll | Where-Object { [string]$_.DisplayName -ieq $PrevName })
                }
                if ($PrevMatch.Count -gt 1) {
                    # Every package the previous name finds, and the one that already carries the new name
                    # (at most one here), may be the one the entry means (R12, see
                    # Register-OERPolicyUndecidedMark).
                    Register-OERPolicyUndecidedMark -PackageId @(@($InCatalog) + @($PrevMatch) | ForEach-Object { [string]$_.Id })
                    $PrevIds = ($PrevMatch | ForEach-Object { [string]$_.Id }) -join ', '
                    ConvertTo-OERStructureResult -Section 'accessPackages' -Item $Name -Action 'Failed' `
                        -Detail "catalog '$($Item.catalog)' holds $($PrevMatch.Count) access packages named '$PrevName' ($PrevIds), the previousDisplayName of this entry; the name cannot identify one -- declare previousDisplayName as the object id of the package to rename"
                    return
                }
                if ($PrevMatch.Count -eq 1) { $PrevId = [string]$PrevMatch[0].Id }
            }
        } else {
            # THIS BRANCH IS UNREACHABLE THROUGH Invoke-OERStructure, and that is deliberate.
            # Get-OERStructureSchemaJson declares "required": [ "displayName", "catalog" ] on every
            # accessPackages item, Invoke-OERStructure refuses a document that fails validation, and
            # there is no -SkipValidation escape -- so no document applied through the public entry
            # point can reach a no-catalog accessPackages entry. Confirmed by tracing the schema and
            # the entry point on 2026-09-11.
            # The schema is NOT being relaxed to make it reachable. The catalog is what SCOPES the
            # resolution; without it the lookup is tenant-wide and throws AmbiguousName whenever a
            # display name is reused across catalogs, which is the exact problem the catalog-scoped
            # branch above exists to avoid. Relaxing a schema so a branch becomes testable is
            # backwards.
            # The branch is NOT deleted either: Sync-OERStructureAccessPackage is a private helper
            # the unit suite calls directly, and for that entry point the code below is correct and
            # is exercised. Keep both facts in view before changing either side.
            # A throw here is NOT "no such package": the resolver throws AmbiguousName when the name
            # matches several packages, AccessPackageNotFound when a GUID-shaped displayName does not
            # exist (issue #71), and re-raises any transport/permission/throttling failure of its own
            # lookup. Every one of those must land in the Failed channel, because the ONLY other exit
            # from here is $ApId = $null, which Step 1 reads as "create it" -- and creating on a
            # stale GUID would produce a live access package whose display name is that GUID. A
            # genuine no-match still returns $null and still creates, exactly as before.
            # A declared previousDisplayName is resolved in the same try, tenant-wide like displayName:
            # a stale object id throws AccessPackageNotFound there, so the item fails with nothing
            # created or renamed (the safe direction), and an ambiguous name throws AmbiguousName.
            try {
                $ApId = Resolve-OERAccessPackageId -DisplayName $Name
                if ($HasPrev) { $PrevId = Resolve-OERAccessPackageId -DisplayName $PrevName }
            } catch {
                Remove-OERErrorRecord -Record $PSItem
                $Caller.WriteError($PSItem)
                ConvertTo-OERStructureResult -Section 'accessPackages' -Item $Name -Action 'Failed' `
                    -Detail "failed to resolve access package '$Name': $($PSItem.Exception.Message); the access package was NOT created" `
                    -ErrorRecord $PSItem
                return
            }
        }

        # -- Rename through previousDisplayName -------------------------------------------
        # Decided once both names are resolved and before anything else is read or written.
        # Resolve-OERStructureRename owns the decision, the two refusals (AccessPackageRenameConflict
        # when both names are different packages, AccessPackageRenameNotFound when neither matches)
        # and their texts. With the rename map, the decision replaces the package's undecided mark
        # (R12): a Rename registers the package's id, a refusal registers it refused and Current removes
        # the mark, so a reference to the package's new name later in this run, read through
        # Get-OERStructureRenameTarget, reaches it or is refused.
        if ($HasPrev) {
            $Rename = Resolve-OERStructureRename -Section 'accessPackages' -Name $Name -PreviousName $PrevName `
                -Id $ApId -PreviousId $PrevId -Catalog ([string]$Item.catalog) -RenameMap $RenameMap
            if ($Rename.ErrorRecord) {
                # A conflict names two packages, either of which the entry may mean (R12, see
                # Register-OERPolicyUndecidedMark); a rename that found neither name has no id to mark.
                if ($Rename.Outcome -eq 'Conflict') { Register-OERPolicyUndecidedMark -PackageId @($ApId, $PrevId) }
                $Caller.WriteError($Rename.ErrorRecord)
                $Rename.Result
                return
            }
            $ApId = $Rename.Id
            $RenameFrom = $Rename.RenameFrom
        }

        # -- Step 1: Create or update the access package object ----------------------------
        if (-not $ApId) {
            # Access package does not exist -- create it.
            if (-not $Caller.ShouldProcess($Name, 'Create access package')) {
                # Under -WhatIf: emit Skipped for the AP and all declared children, then return.
                ConvertTo-OERStructureResult -Section 'accessPackages' -Item $Name -Action 'Skipped' -Detail "would create access package $Name"

                # BL-147 (R-8): the package the plan would create has no id yet, so a review that names it
                # in this run is refused with that reason (in a plan where the real run creates it, an
                # accepted limit), never looked up by name in the whole tenant.
                if ($null -ne $RenameMap -and -not [string]::IsNullOrEmpty([string]$Name)) {
                    $null = Resolve-OERStructureRename -Section 'accessPackages' -Name ([string]$Name) -Unidentified `
                        -Reason 'the accessPackages entry would create it, and the create was not carried out: -WhatIf, or a declined confirmation' `
                        -RenameMap $RenameMap
                }

                if (Test-OERDeclaredProperty -Node $Item -Name 'resourceRoles') {
                    foreach ($Rr in @($Item.resourceRoles)) {
                        $RrRef = if (Test-OERDeclaredProperty -Node $Rr -Name 'resource') { $Rr.resource } else { '?' }
                        ConvertTo-OERStructureResult -Section 'accessPackages' -Item $Name -Action 'Skipped' -Detail "would configure resourceRole '$RrRef' after access package is created"
                    }
                }

                if (Test-OERDeclaredProperty -Node $Item -Name 'assignmentPolicies') {
                    foreach ($Pol in @($Item.assignmentPolicies)) {
                        $PolRef = if (Test-OERDeclaredProperty -Node $Pol -Name 'displayName') { $Pol.displayName } else { '?' }
                        # A policy that declares previousDisplayName names a policy that already exists,
                        # and a package this plan would create has none: it is planned as its decision,
                        # AssignmentPolicyRenameNotFound (the record, the row, and the rename map entry),
                        # never as a create -- the real run reaches the same decision in Step 3 below,
                        # on the empty policy list of the package it created.
                        if (Test-OERDeclaredProperty -Node $Pol -Name 'previousDisplayName') {
                            $PlannedRename = Resolve-OERStructureRename -Section 'assignmentPolicies' -AccessPackage ([string]$Name) `
                                -Name ([string]$PolRef) -PreviousName ([string]$Pol.previousDisplayName) -Id $null -PreviousId $null -RenameMap $RenameMap
                            $Caller.WriteError($PlannedRename.ErrorRecord)
                            $PlannedRename.Result
                            continue
                        }
                        ConvertTo-OERStructureResult -Section 'accessPackages' -Item $Name -Action 'Skipped' -Detail "would create assignmentPolicy '$PolRef' after access package is created"
                    }
                }
                return
            }

            # Build creation params
            $NewParams = @{ DisplayName = $Name; Catalog = $CatalogRef; Confirm = $false }
            if (Test-OERDeclaredProperty -Node $Item -Name 'description') { $NewParams.Description = $Item.description }
            if ((Test-OERDeclaredProperty -Node $Item -Name 'hidden') -and $Item.hidden -eq $true) { $NewParams.Hidden = $true }

            $Created = $null
            try {
                $Created = New-OERAccessPackage @NewParams -ErrorAction Stop
            } catch {
                Remove-OERErrorRecord -Record $PSItem
                $Caller.WriteError($PSItem)
                ConvertTo-OERStructureResult -Section 'accessPackages' -Item $Name -Action 'Failed' -Detail "access package creation failed: $($PSItem.Exception.Message)" -ErrorRecord $PSItem
                return
            }

            if (-not $Created) {
                ConvertTo-OERStructureResult -Section 'accessPackages' -Item $Name -Action 'Failed' -Detail 'New-OERAccessPackage returned no object'
                return
            }

            # New-OERAccessPackage looks for an existing package by name in the WHOLE tenant, and returns
            # the one package of that name it finds, whichever catalog holds it. The declared catalog's
            # list above did not hold the name, so a package it returns from another catalog -- a twin
            # catalog's, for example -- was not created here: writing the declared resource roles and
            # assignment policies to it would change another catalog's package. So the entry fails, with
            # nothing written to that package or for the entry. The catalogs are compared as ids, without
            # regard to letter case: Resolve-OERCatalogId returns a catalog id as it is, with no request,
            # and looks a name up once (a name several catalogs carry was refused when the package list
            # above was read). An empty CatalogId is a package the create POSTed into the declared
            # catalog, whose confirmation read did not answer: created there, as before.
            if (-not [string]::IsNullOrEmpty([string]$Created.CatalogId)) {
                $DeclaredCatalogId = $null
                try {
                    $DeclaredCatalogId = Resolve-OERCatalogId -DisplayName ([string]$CatalogRef)
                } catch {
                    Remove-OERErrorRecord -Record $PSItem
                    $Caller.WriteError($PSItem)
                    ConvertTo-OERStructureResult -Section 'accessPackages' -Item $Name -Action 'Failed' `
                        -Detail "failed to look up catalog '$($Item.catalog)' to confirm that access package '$Name' ($($Created.Id)), which New-OERAccessPackage returned, belongs to it: $($PSItem.Exception.Message); nothing further was written for it" `
                        -ErrorRecord $PSItem
                    return
                }
                if ([string]$DeclaredCatalogId -ine [string]$Created.CatalogId) {
                    ConvertTo-OERStructureResult -Section 'accessPackages' -Item $Name -Action 'Failed' `
                        -Detail "access package '$Name' was not created in catalog '$($Item.catalog)': a package of that name already exists in another catalog ($($Created.CatalogId)), and New-OERAccessPackage returned it ($($Created.Id)); nothing was written to it"
                    return
                }
            }

            $ApId = $Created.Id
            # BL-147 (R-8): the package created in the declared catalog is the one a review that names it in
            # this run reaches, by this id. An answer with no id leaves the refusal in place.
            if ($null -ne $RenameMap -and -not [string]::IsNullOrEmpty([string]$Name) -and -not [string]::IsNullOrEmpty([string]$ApId)) {
                $null = Resolve-OERStructureRename -Section 'accessPackages' -Name ([string]$Name) -Identified -Id ([string]$ApId) -RenameMap $RenameMap
            }
            ConvertTo-OERStructureResult -Section 'accessPackages' -Item $Name -Action 'Created' -Detail "created access package $Name ($ApId)"

            # After create: current resourceRoles and policies are empty
            $CurrentBindings = @()
            $CurrentPolicies = @()

        } else {
            # R12 (BL-128): the package exists and its id is known now, before anything else is read or
            # written for it. A stop of this entry before Step 3 decides a policy (a failed re-read below,
            # a failed update that renames the package, a failed read of its resource role bindings, of
            # the catalog's resources or of its policies, a lookup that throws) would otherwise leave the
            # policy's key with the package id empty, so every renaming policy is marked undecided again
            # under that id (see Register-OERPolicyUndecidedMark). Each decision in Step 3 replaces the
            # mark under both keys. A package this call creates needs no such mark: no document can name
            # its id, and its policies are decided under both keys after the create.
            Register-OERPolicyUndecidedMark -PackageId @([string]$ApId)

            # BL-147 (R-8): the package found in the declared catalog -- also after a Current rename outcome,
            # which removed the entry's mark -- is the one a review that names it in this run reaches, by its
            # id, whatever fails for the entry after this point. A rename keeps its own registration, which
            # names the package it renames from.
            if ($null -ne $RenameMap -and -not $RenameFrom -and -not [string]::IsNullOrEmpty([string]$Name)) {
                $null = Resolve-OERStructureRename -Section 'accessPackages' -Name ([string]$Name) -Identified -Id ([string]$ApId) -RenameMap $RenameMap
            }

            # Access package exists -- diff mutable properties (description and the hidden flag;
            # catalog is creation-only and is never changed on an existing package). $ApId is already
            # resolved above (either catalog-scoped or tenant-wide), so read by id directly rather than
            # by -DisplayName, whose ByName parameter set is tenant-wide and would emit every match.
            # A throw here (forced by -ErrorAction Stop) is a transport/permission/throttling failure on
            # the re-read, NOT evidence the properties match -- without it, a failed read silently
            # returns $null and the fall-through below would misreport a false Unchanged (or crash the
            # later Set-OERAccessPackage call on a null -Id) instead of surfacing the failure.
            try {
                $Cur = Get-OERAccessPackage -Id $ApId -ErrorAction Stop
            } catch {
                Remove-OERErrorRecord -Record $PSItem
                $Caller.WriteError($PSItem)
                ConvertTo-OERStructureResult -Section 'accessPackages' -Item $Name -Action 'Failed' `
                    -Detail "failed to re-read access package '$Name' ($ApId): $($PSItem.Exception.Message)" `
                    -ErrorRecord $PSItem
                return
            }

            $ApUpdateParams = @{}
            # A rename through previousDisplayName travels in the same Set-OERAccessPackage call as
            # every other changed property, so the package is renamed and updated in one call.
            if ($RenameFrom) { $ApUpdateParams.NewDisplayName = $Name }
            if (Test-OERDeclaredProperty -Node $Item -Name 'description') {
                if ($Cur.Description -ne $Item.description) { $ApUpdateParams.Description = $Item.description }
            }
            if (Test-OERDeclaredProperty -Node $Item -Name 'hidden') {
                if ([bool]$Cur.IsHidden -ne [bool]$Item.hidden) { $ApUpdateParams.Hidden = [bool]$Item.hidden }
            }

            if ($ApUpdateParams.Count -gt 0) {
                # The rename is reported on its own terms; the other changed keys keep the wording
                # every property update has always had.
                $PropertyKeys = @($ApUpdateParams.Keys | Where-Object { $_ -ne 'NewDisplayName' })
                $PropertyList = $PropertyKeys -join ', '
                if ($RenameFrom) {
                    $UpdateAction = "Rename access package '$RenameFrom' to '$Name'"
                    $UpdatedDetail = "renamed access package '$RenameFrom' to '$Name'"
                    $PlannedDetail = "would rename access package '$RenameFrom' to '$Name'"
                    if ($PropertyKeys.Count -gt 0) {
                        $UpdateAction += " and update access package properties ($PropertyList)"
                        $UpdatedDetail += "; updated access package properties ($PropertyList)"
                        $PlannedDetail += "; would update access package properties ($PropertyList)"
                    }
                } else {
                    $UpdateAction = "Update access package properties ($PropertyList)"
                    $UpdatedDetail = "updated access package properties ($PropertyList)"
                    $PlannedDetail = "would update access package properties ($PropertyList)"
                }
                if ($Caller.ShouldProcess($Name, $UpdateAction)) {
                    try {
                        Set-OERAccessPackage -Id $Cur.Id @ApUpdateParams -Confirm:$false -ErrorAction Stop | Out-Null
                        ConvertTo-OERStructureResult -Section 'accessPackages' -Item $Name -Action 'Updated' -Detail $UpdatedDetail
                    } catch {
                        Remove-OERErrorRecord -Record $PSItem
                        $Caller.WriteError($PSItem)
                        ConvertTo-OERStructureResult -Section 'accessPackages' -Item $Name -Action 'Failed' -Detail "access package update failed: $($PSItem.Exception.Message)" -ErrorRecord $PSItem
                        # The package still carries its previous name, not the one the document
                        # declares, so none of its resource roles or assignment policies is reconciled
                        # under the new name (R8).
                        if ($RenameFrom) { return }
                    }
                } else {
                    ConvertTo-OERStructureResult -Section 'accessPackages' -Item $Name -Action 'Skipped' -Detail $PlannedDetail
                }
            } else {
                ConvertTo-OERStructureResult -Section 'accessPackages' -Item $Name -Action 'Unchanged' -Detail 'access package properties match'
            }

            # Read current resource role bindings for reconciliation.
            # NOTE: the $expand shape (scope,role) is a live-verify item -- the mock tests fix
            # the shape returned and live testing against the real Graph confirms whether
            # role.displayName and scope.originId are populated at this expand depth.
            # A failed read is NOT an empty set of bindings. Substituting @() here made the add loop
            # below re-add every declared binding against a package that already has them -- a
            # duplicate-create attempt reported as Created (issue #60).
            $RrsResponse = $null
            try {
                $RrsResponse = Invoke-OERGraphRequest -Uri ("v1.0/identityGovernance/entitlementManagement/accessPackages/{0}/resourceRoleScopes?`$expand=scope,role" -f $ApId) -All
            } catch {
                Remove-OERErrorRecord -Record $PSItem
                $Caller.WriteError($PSItem)
                ConvertTo-OERStructureResult -Section 'accessPackages' -Item $Name -Action 'Failed' `
                    -Detail "failed to read the current resource role bindings of access package '$Name': $($PSItem.Exception.Message); no resourceRole or assignmentPolicy was created, updated or removed" `
                    -ErrorRecord $PSItem
                return
            }
            $CurrentBindings = if ($RrsResponse.value) { @($RrsResponse.value) } else { @() }

            # Read current assignment policies for reconciliation. Pass the RESOLVED $ApId, never
            # $Name: -AccessPackage funnels a non-GUID value into Resolve-OERAccessPackageId, whose
            # display-name lookup is TENANT-WIDE and throws AmbiguousName when the same name exists
            # in another catalog -- which would discard the catalog scoping the resolution above
            # just established. Resolve-OERAccessPackageId treats a GUID (Test-OERGuid) as an id and
            # returns it unchanged, so an id binds straight through. Since issue #71 that path costs
            # one existence read instead of no Graph call at all; the REASON for passing $ApId is
            # unchanged -- it is the tenant-wide display-name lookup that must be avoided, not the
            # read.
            # -ErrorAction Stop plus a catch, never SilentlyContinue: Get-OERAccessPackageAssignmentPolicy
            # reports a failed read as a non-terminating error and emits nothing, so suppressing it made
            # a 403, a transient 5xx or a resolve failure indistinguishable from "this package genuinely
            # has no policies" -- and Step 3 then took the CREATE branch against policies that already
            # exist (issue #60). An empty read that SUCCEEDED still reconciles normally.
            $CurrentPolicies = @()
            try {
                $CurrentPolicies = @(Get-OERAccessPackageAssignmentPolicy -AccessPackage $ApId -ErrorAction Stop)
            } catch {
                Remove-OERErrorRecord -Record $PSItem
                $Caller.WriteError($PSItem)
                ConvertTo-OERStructureResult -Section 'accessPackages' -Item $Name -Action 'Failed' `
                    -Detail "failed to read the current assignment policies of access package '$Name': $($PSItem.Exception.Message); no assignmentPolicy was created or updated" `
                    -ErrorRecord $PSItem
                return
            }
        }

        # -- Step 2: resourceRoles ---------------------------------------------------------
        # Track declared (originId, roleDisplayName) pairs for prune comparison.
        $DeclaredBindingKeys = [System.Collections.Generic.List[string]]::new()
        # Declared resources that could not be resolved to an origin id carry no binding key, so they
        # cannot protect their live bindings; while this list is non-empty the Extra/prune loop below
        # withholds every candidate (ConvertTo-OERPruneWithheldResult owns the rule).
        $ResourceRoleUnresolved = [System.Collections.Generic.List[string]]::new()
        # An omitted 'resourceRoles' key has always meant "no add-list, but the prune/Extra loop
        # below still runs against whatever it finds" -- that is intentional, existing, tested
        # behavior (an absent collection is not an instruction to leave live state alone; only an
        # EXPLICIT null is). So the add loop is gated on Test-OERDeclaredProperty (skips on both
        # absent and null), while the prune/Extra loop below is gated on the narrower
        # $ResourceRolesDeclaredNull so it keeps running when the key is merely absent and only
        # backs off on an explicit null.
        $ResourceRolesDeclaredNull = Test-OERDeclaredNull -Node $Item -Name 'resourceRoles'

        if (Test-OERDeclaredProperty -Node $Item -Name 'resourceRoles') {
            # Read the catalog's resources ONCE for the whole resourceRoles set (not per entry).
            # -ErrorAction Stop plus a catch: a suppressed failure left $CatResources empty, which
            # both sent every declared resource down the Resolve-OERGroupId fallback AND left
            # $DeclaredBindingKeys short -- so the Extra/prune pass below reported every live binding
            # as Extra, or removed them all under -Prune (issue #60).
            # Gated on there being at least one declared entry. "resourceRoles": [] enters this branch
            # (an empty array IS declared) but consumes $CatResources nowhere -- the foreach below runs
            # zero times -- while $ResourceRolesDeclaredNull stays false, so the Extra/prune pass still
            # runs and correctly prunes every live binding. Reading the catalog anyway turned that
            # correct outcome into a Failed row whenever the catalog read broke. A declared-null
            # resourceRoles never reaches this code at all, so the @($null).Count -eq 1 trap does not
            # apply to this count.
            $CatResources = @()
            if (@($Item.resourceRoles).Count -gt 0) {
                try {
                    $CatResources = @(Get-OERCatalogResource -Catalog $CatalogRef -ErrorAction Stop)
                } catch {
                    Remove-OERErrorRecord -Record $PSItem
                    $Caller.WriteError($PSItem)
                    ConvertTo-OERStructureResult -Section 'accessPackages' -Item $Name -Action 'Failed' `
                        -Detail "failed to read the resources of catalog '$($Item.catalog)': $($PSItem.Exception.Message); no resourceRole binding was added, reported Extra or removed" `
                        -ErrorRecord $PSItem
                    return
                }
            }
            foreach ($RrEntry in @($Item.resourceRoles)) {
                $ResName  = $RrEntry.resource
                $RoleName = $RrEntry.role

                # Resolve resource name to OriginId:
                # 1. The group the name (or object id) resolves to, when that group is a resource of
                #    the catalog. A catalog keeps the display name a resource had when it was added,
                #    also after the group is renamed, so the group's CURRENT name must win over a name
                #    the catalog recorded for another resource -- or the binding would be matched to
                #    the wrong resource and the right one read as undeclared. It decides only while no
                #    resource that is not a group is recorded under that name too: see the refusal below.
                # 2. The catalog resource recorded under that display name (an application, a
                #    SharePoint site, or a group under the name the catalog recorded), when exactly
                #    one resource carries it. Several do not decide: see the refusal below. Nor does
                #    one other GROUP while a group outside the catalog carries the name now.
                # 3. The group's id even when it is not in the catalog (adding the binding then fails,
                #    so the entry counts as unresolved and the prune is withheld).
                # A name matching several groups is set aside while step 2 can still decide; it is
                # thrown when step 2 cannot. Any other failure of the lookup throws at once.
                $OriginId = $null
                $GroupOriginId = $null
                $GroupLookupError = $null
                try {
                    $GroupOriginId = Resolve-OERGroupId -DisplayName $ResName
                } catch {
                    Remove-OERErrorRecord -Record $PSItem
                    if (-not (Test-OERAmbiguousNameError -Record $PSItem)) { throw }
                    $GroupLookupError = $PSItem
                }
                # The origin ids of the catalog resources this name cannot choose between (decisions D4
                # and D5). Empty while the name identifies at most one; the refusal below reads it.
                $AmbiguousIds = @()
                if ($GroupOriginId -and @($CatResources | Where-Object { [string]$_.OriginId -eq [string]$GroupOriginId }).Count -gt 0) {
                    $OriginId = $GroupOriginId
                    # Step 1 does not end the search (decision D5). The group's CURRENT name beats a name
                    # the catalog recorded for ANOTHER GROUP -- that is the rename case step 1 exists
                    # for -- but it must not beat a resource that is not a group and is recorded under
                    # this very name: an application (or a site) and a group sharing one display name in
                    # one catalog are both genuine candidates. Taking the group would bind the role to
                    # the wrong resource or fail in the add, and either way the binding of the resource
                    # the entry really names would read as undeclared and be removed under -Prune. So
                    # a non-group resource recorded under the declared name, with another origin id,
                    # makes the name ambiguous exactly as several same-named resources do (the group is
                    # listed with them). A recorded originSystem other than AadGroup is what counts: a
                    # resource with no originSystem is not assumed to be a group.
                    $SameNamedOthers = @($CatResources | Where-Object {
                            $_.DisplayName -eq $ResName -and
                            [string]$_.OriginId -ne [string]$GroupOriginId -and
                            [string]$_.OriginSystem -ne 'AadGroup'
                        })
                    if ($SameNamedOthers.Count -gt 0) {
                        $AmbiguousIds = @([string]$GroupOriginId) + @($SameNamedOthers | ForEach-Object { [string]$_.OriginId })
                    }
                }

                if (-not $OriginId) {
                    # Every match is kept, never just the first (decision D4). A catalog does NOT enforce
                    # unique resource display names -- two same-named groups, an application and a group,
                    # two sites -- so taking the first of several would bind the role to an arbitrary one,
                    # and under -Prune the binding of the right one would read as undeclared and be
                    # removed. More than one match makes the name ambiguous, which refuses THIS entry
                    # below. It also holds while a name matching several groups is set aside: the catalog
                    # cannot decide either, and that case used to bind the first resource. One match and
                    # no match are exactly what they were.
                    $MatchedCatRes = @($CatResources | Where-Object { $_.DisplayName -eq $ResName })
                    if ($MatchedCatRes.Count -gt 1) {
                        $AmbiguousIds = @($MatchedCatRes | ForEach-Object { [string]$_.OriginId })
                    }
                    if ($MatchedCatRes.Count -eq 1) {
                        # A group that currently carries the declared name but is NOT a resource of the
                        # catalog (step 1 would have decided otherwise) is a second candidate when the one
                        # catalog resource under that name is ANOTHER GROUP: the catalog keeps the name a
                        # group had when it was added, so that group may since have been renamed, and the
                        # name now belongs to the group outside the catalog. Binding the role to the
                        # catalog's group would be a silent wrong write, so this is refused like the
                        # others, listing both ids. Only a positively identified AadGroup counts: widening
                        # it to a non-group match would refuse an application that shares its name with
                        # any group of the tenant, which the inventory round trip produces. The match can
                        # never carry the group's own id here, since that group would have decided at
                        # step 1.
                        if ($GroupOriginId -and [string]$MatchedCatRes[0].OriginSystem -eq 'AadGroup') {
                            $AmbiguousIds = @([string]$GroupOriginId, [string]$MatchedCatRes[0].OriginId)
                        } else {
                            $OriginId = $MatchedCatRes[0].OriginId
                        }
                    }
                }

                if ($AmbiguousIds.Count -gt 0) {
                    # The refusal (decisions D4 and D5): the entry counts as unresolved, exactly as a name
                    # that matches no resource at all. It carries no binding key, so the prune pass below
                    # withholds every live binding of the package until the document is fixed
                    # (ConvertTo-OERPruneWithheldResult owns that rule, and this refusal does not touch
                    # it). It sits before ShouldProcess, so it reads the same under -WhatIf, and the
                    # package's other declared entries carry on. The last sentence of the message has to
                    # be followable for every resource type, and renaming a resource at its source is not
                    # a way out: a catalog keeps the name a resource had when it was added. A group or an
                    # application can be declared by one of the origin ids listed (a SharePoint site's
                    # origin id is its URL, which a document cannot name), and any resource can be
                    # refreshed, or removed and added again, so that the recorded names differ.
                    $AmbiguousList = $AmbiguousIds -join ', '
                    $AmbiguousRecord = [System.Management.Automation.ErrorRecord]::new(
                        [System.Exception]::new(
                            "Resource name '$ResName' matches $($AmbiguousIds.Count) resources of catalog '$($Item.catalog)' ($AmbiguousList). " +
                            'A catalog does not enforce unique resource display names, so this name ' +
                            'cannot identify a single resource. Declare a group or an application by one of the origin ids listed above, ' +
                            'or refresh or remove and re-add one of the resources in the catalog so their recorded names differ.'),
                        'AmbiguousName',
                        [System.Management.Automation.ErrorCategory]::InvalidArgument,
                        $ResName)
                    $Caller.WriteError($AmbiguousRecord)
                    ConvertTo-OERStructureResult -Section 'accessPackages' -Item $Name -Action 'Failed' `
                        -Detail "$($AmbiguousIds.Count) resources of catalog '$($Item.catalog)' are named '$ResName' ($AmbiguousList); no resourceRole was added for it" `
                        -ErrorRecord $AmbiguousRecord
                    $ResourceRoleUnresolved.Add($ResName)
                    continue
                }

                if (-not $OriginId) {
                    if ($GroupLookupError) { throw $GroupLookupError }
                    $OriginId = $GroupOriginId
                    # Step 3 (decision D5): a group that is NOT a resource of the catalog. Its id is used
                    # only so the add can fail with the real reason (CatalogResourceNotFound); it can
                    # never name a live binding, since a binding exists only for a resource of the
                    # catalog. So the entry counts as unresolved and keeps its own Failed row from that
                    # add: without this, a renamed application and a same-named group outside the catalog
                    # made the application's live binding read as undeclared and be removed under -Prune.
                    # An id of $null is left to the unresolved path just below, which counts it itself.
                    if ($OriginId) { $ResourceRoleUnresolved.Add($ResName) }
                }

                if (-not $OriginId) {
                    ConvertTo-OERStructureResult -Section 'accessPackages' -Item $Name -Action 'Failed' -Detail "could not resolve resource '$ResName' to an origin id in catalog '$($Item.catalog)'"
                    $ResourceRoleUnresolved.Add($ResName)
                    continue
                }

                # Build a lookup key for prune comparison.
                $BindingKey = "$RoleName|$OriginId"
                $DeclaredBindingKeys.Add($BindingKey)

                # Check if already present.
                $AlreadyBound = $CurrentBindings | Where-Object {
                    $_.role.displayName -eq $RoleName -and $_.scope.originId -eq $OriginId
                } | Select-Object -First 1

                if ($AlreadyBound) {
                    ConvertTo-OERStructureResult -Section 'accessPackages' -Item $Name -Action 'Unchanged' -Detail "resourceRole '$RoleName' on '$ResName' already bound"
                } else {
                    if ($Caller.ShouldProcess($Name, "Add resourceRole '$RoleName' on '$ResName'")) {
                        try {
                            # -AccessPackage takes the RESOLVED $ApId, not $Name -- see the note on
                            # the assignment policy read above: a display name here is resolved
                            # tenant-wide and ignores the declared catalog.
                            Add-OERAccessPackageResourceRole -AccessPackage $ApId -Catalog $CatalogRef -ResourceOriginId $OriginId -Role $RoleName -Confirm:$false -ErrorAction Stop | Out-Null
                            ConvertTo-OERStructureResult -Section 'accessPackages' -Item $Name -Action 'Created' -Detail "added resourceRole '$RoleName' on '$ResName'"
                        } catch {
                            Remove-OERErrorRecord -Record $PSItem
                            $Caller.WriteError($PSItem)
                            ConvertTo-OERStructureResult -Section 'accessPackages' -Item $Name -Action 'Failed' -Detail "failed to add resourceRole '$RoleName' on '$ResName': $($PSItem.Exception.Message)" -ErrorRecord $PSItem
                            continue
                        }
                    } else {
                        ConvertTo-OERStructureResult -Section 'accessPackages' -Item $Name -Action 'Skipped' -Detail "would add resourceRole '$RoleName' on '$ResName'"
                    }
                }
            }
        }

        # Extra/prune undeclared current resource role bindings. Skipped ONLY when 'resourceRoles'
        # is explicitly null -- an omitted key still reconciles against an empty declared set
        # (existing behavior), but an explicit null is a distinct "leave bindings alone" signal and
        # must not report every live binding as Extra or, worse under -Prune, remove them all.
        if (-not $ResourceRolesDeclaredNull) {
            foreach ($CurBinding in $CurrentBindings) {
                $CurKey = "$($CurBinding.role.displayName)|$($CurBinding.scope.originId)"
                if ($DeclaredBindingKeys -notcontains $CurKey) {
                    $Withheld = ConvertTo-OERPruneWithheldResult -Section 'accessPackages' -Item $Name -Unresolved $ResourceRoleUnresolved -Candidate "undeclared resourceRole binding '$CurKey'"
                    if ($Withheld) { $Withheld; continue }
                    if ($Prune) {
                        $PruneVerb = if ($WhatIfPreference) { 'would remove' } else { 'removing' }
                        Write-Warning "Sync-OERStructureAccessPackage: $PruneVerb undeclared resourceRole binding '$CurKey' from access package '$Name'."
                        if ($Caller.ShouldProcess($Name, "Remove undeclared resourceRole binding '$CurKey'")) {
                            try {
                                # -AccessPackage takes the RESOLVED $ApId, not $Name. This one is a
                                # DELETE: a tenant-wide display-name resolve could target a binding
                                # on an identically named package in another catalog.
                                Remove-OERAccessPackageResourceRole -AccessPackage $ApId -ResourceRoleScopeId $CurBinding.id -Confirm:$false -ErrorAction Stop
                                ConvertTo-OERStructureResult -Section 'accessPackages' -Item $Name -Action 'Removed' -Detail "removed undeclared resourceRole binding '$CurKey'"
                            } catch {
                                Remove-OERErrorRecord -Record $PSItem
                                $Caller.WriteError($PSItem)
                                ConvertTo-OERStructureResult -Section 'accessPackages' -Item $Name -Action 'Failed' -Detail "failed to remove resourceRole binding '$CurKey': $($PSItem.Exception.Message)" -ErrorRecord $PSItem
                                continue
                            }
                        } else {
                            ConvertTo-OERStructureResult -Section 'accessPackages' -Item $Name -Action 'Skipped' -Detail "would remove undeclared resourceRole binding '$CurKey'"
                        }
                    } else {
                        ConvertTo-OERStructureResult -Section 'accessPackages' -Item $Name -Action 'Extra' -Detail "undeclared resourceRole binding '$CurKey' (use -Prune to remove)"
                    }
                }
            }
        }

        # -- Step 3: assignmentPolicies (UPSERT) -------------------------------------------
        # An existing policy (matched by displayName) is reconciled by building the desired body from
        # the DECLARED entry fields, projecting it the same way the live policy is projected, and
        # diffing the two projections over only the declared fields (Resolve-OERAssignmentPolicyChange).
        # On a difference it calls Set with the declared sub-objects/scalars and reports Updated; no
        # difference reports Unchanged. An absent policy is created from the same desired parts. The
        # full per-approver set is now part of the diff; the only fallback is the back-compat Tenant
        # Profile PrimaryApprovers/EscalationApprovers default for a stage that declares no manager and
        # no explicit approvers.

        # Nested helper: build the desired requestor scope, requestor settings, approval stages, the
        # ConvertTo-OERPolicyBody scalar params, and the declared-field list -- shared by CREATE and
        # UPDATE. Returns
        #   @{ Success=[bool]; RequestorScope=<obj>; RequestorSettings=<obj>; Stages=<obj[]>;
        #      BodyScalars=<hashtable>; DeclaredFields=<string[]>; FailDetail=<string>; ErrorRecord=<er> }.
        function Build-OERPolicyParts {
            param(
                [PSCustomObject]$PolicyEntry,
                [string]$PolicyName,
                [string]$Alias
            )
            $DeclaredFields = [System.Collections.Generic.List[string]]::new()
            $BodyScalars = @{}

            # requestorScope: always built (defaults to AllMemberUsers). Declared when the entry carries
            # a requestorScope object (scope/users/groups).
            $HasRequestorScope = Test-OERDeclaredProperty -Node $PolicyEntry -Name 'requestorScope'
            $ScopeValue = 'AllMemberUsers'
            $ScopeUsers = @()
            $ScopeGroups = @()
            if ($HasRequestorScope) {
                $DeclaredFields.Add('requestorScope')
                $RsEntry = $PolicyEntry.requestorScope
                $HasScopeValue = Test-OERDeclaredProperty -Node $RsEntry -Name 'scope'
                if ($HasScopeValue) { $ScopeValue = $RsEntry.scope }
                if (Test-OERDeclaredProperty -Node $RsEntry -Name 'users') { $ScopeUsers = @($RsEntry.users) }
                if (Test-OERDeclaredProperty -Node $RsEntry -Name 'groups') { $ScopeGroups = @($RsEntry.groups) }

                # Issue #69: a requestorScope that declares users/groups but no scope WOULD have
                # defaulted to AllMemberUsers, discarding the users/groups entirely --
                # New-OERAccessPackageRequestorScope only splats -User/-Group under -Scope
                # SpecificDirectoryUsers. That never actually reached a tenant: Test-OERStructureSchema
                # raised an ERROR for the shape and Invoke-OERStructure refuses any document with one,
                # with no -SkipValidation escape, so this handler was never handed such a document
                # through the public entry point. No live tenant carries a widened requestor scope
                # written by an earlier release; what the fix changes is that the document is now
                # ACCEPTED (with a Warning) and applied as intended. An explicit scope always
                # wins (this branch never runs when $HasScopeValue is true); only when scope is
                # undeclared AND the users/groups list is non-empty do we infer SpecificDirectoryUsers, so
                # a declared-empty list still falls back to AllMemberUsers instead of naming nobody.
                if ((-not $HasScopeValue) -and (($ScopeUsers.Count -gt 0) -or ($ScopeGroups.Count -gt 0))) {
                    $ScopeValue = 'SpecificDirectoryUsers'
                }
            }

            # description scalar.
            if (Test-OERDeclaredProperty -Node $PolicyEntry -Name 'description') {
                $DeclaredFields.Add('description')
                $BodyScalars.Description = [string]$PolicyEntry.description
            }

            # approval toggles.
            if (Test-OERDeclaredProperty -Node $PolicyEntry -Name 'requireApproval') {
                $DeclaredFields.Add('requireApproval')
                $BodyScalars.RequireApproval = [bool]$PolicyEntry.requireApproval
            }
            if (Test-OERDeclaredProperty -Node $PolicyEntry -Name 'requireRequestorJustification') {
                $DeclaredFields.Add('requireRequestorJustification')
                $BodyScalars.RequireRequestorJustification = [bool]$PolicyEntry.requireRequestorJustification
            }
            if (Test-OERDeclaredProperty -Node $PolicyEntry -Name 'requireApprovalForUpdate') {
                $DeclaredFields.Add('requireApprovalForUpdate')
                $BodyScalars.RequireApprovalForUpdate = [bool]$PolicyEntry.requireApprovalForUpdate
            }

            # expiration: at most one of durationInDays / durationInHours / expirationDateTime.
            if (Test-OERDeclaredProperty -Node $PolicyEntry -Name 'durationInDays') {
                $DeclaredFields.Add('expiration')
                $BodyScalars.DurationInDays = [int]$PolicyEntry.durationInDays
            } elseif (Test-OERDeclaredProperty -Node $PolicyEntry -Name 'durationInHours') {
                $DeclaredFields.Add('expiration')
                $BodyScalars.DurationInHours = [int]$PolicyEntry.durationInHours
            } elseif (Test-OERDeclaredProperty -Node $PolicyEntry -Name 'expirationDateTime') {
                $DeclaredFields.Add('expiration')
                $BodyScalars.ExpirationDateTime = [datetime]$PolicyEntry.expirationDateTime
            }

            # notificationsDisabled scalar.
            if (Test-OERDeclaredProperty -Node $PolicyEntry -Name 'notificationsDisabled') {
                $DeclaredFields.Add('notificationsDisabled')
                $BodyScalars.DisableAssignmentNotifications = [bool]$PolicyEntry.notificationsDisabled
            }

            $BuiltSettings = $null
            $BuiltStages = [System.Collections.Generic.List[PSCustomObject]]::new()
            try {
                # requestorScope builder (pass users/groups only for SpecificDirectoryUsers).
                $ScopeParams = @{ Scope = $ScopeValue; ErrorAction = 'Stop' }
                if ($ScopeValue -eq 'SpecificDirectoryUsers') {
                    if ($ScopeUsers.Count -gt 0) { $ScopeParams.User = $ScopeUsers }
                    if ($ScopeGroups.Count -gt 0) { $ScopeParams.Group = $ScopeGroups }
                }
                $BuiltScope = New-OERAccessPackageRequestorScope @ScopeParams

                # requestorSettings builder (only when declared).
                if (Test-OERDeclaredProperty -Node $PolicyEntry -Name 'requestorSettings') {
                    $DeclaredFields.Add('requestorSettings')
                    $RsObj = $PolicyEntry.requestorSettings
                    $SettingsParams = @{}
                    if ((Test-OERDeclaredProperty -Node $RsObj -Name 'allowSelfRequest') -and ([bool]$RsObj.allowSelfRequest)) { $SettingsParams.AllowSelfRequest = $true }
                    $HasManagerRequest = (Test-OERDeclaredProperty -Node $RsObj -Name 'allowManagerRequest') -and ([bool]$RsObj.allowManagerRequest)
                    if ($HasManagerRequest) {
                        $SettingsParams.AllowManagerRequest = $true
                        if (Test-OERDeclaredProperty -Node $RsObj -Name 'managerLevel') { $SettingsParams.ManagerLevel = [int]$RsObj.managerLevel }
                    }
                    if ((Test-OERDeclaredProperty -Node $RsObj -Name 'allowCustomSchedule') -and ([bool]$RsObj.allowCustomSchedule)) { $SettingsParams.AllowCustomSchedule = $true }
                    if ((Test-OERDeclaredProperty -Node $RsObj -Name 'allowSelfExtend') -and ([bool]$RsObj.allowSelfExtend)) { $SettingsParams.AllowSelfExtend = $true }
                    if ((Test-OERDeclaredProperty -Node $RsObj -Name 'allowSelfRemove') -and ([bool]$RsObj.allowSelfRemove)) { $SettingsParams.AllowSelfRemove = $true }
                    if ((Test-OERDeclaredProperty -Node $RsObj -Name 'allowOnBehalfUpdate') -and ([bool]$RsObj.allowOnBehalfUpdate)) { $SettingsParams.AllowOnBehalfUpdate = $true }
                    if ((Test-OERDeclaredProperty -Node $RsObj -Name 'allowOnBehalfRemove') -and ([bool]$RsObj.allowOnBehalfRemove)) { $SettingsParams.AllowOnBehalfRemove = $true }
                    $BuiltSettings = New-OERAccessPackageRequestorSettings @SettingsParams -ErrorAction Stop
                }

                # approval stages (full declared approver set; back-compat default fallback retained).
                if (Test-OERDeclaredProperty -Node $PolicyEntry -Name 'approvalStages') {
                    $DeclaredFields.Add('approvalStages')
                    $StageIndex = 0
                    foreach ($StageEntry in @($PolicyEntry.approvalStages)) {
                        $StageIndex++

                        # Issue #70 site 3: route the read through Test-OERDeclaredProperty instead of
                        # casting $StageEntry.durationDays unguarded. -DurationDays on
                        # New-OERAccessPackageApprovalStage is a Mandatory [int], so the splat key can
                        # never be dropped -- the applied value stays 0 for an absent or explicit-null
                        # durationDays, unchanged from the prior [int]$null/[int]<missing> coercion.
                        # Measured, not assumed (a null does not always coerce the way it looks like it
                        # should): 0 is NOT a quiet "P0D" stage. New-OERAccessPackageApprovalStage's own
                        # ConvertTo-OERDuration -Days call carries [ValidateRange(1, ...)], so a
                        # DurationDays of 0 throws there, the throw is caught by this function's own try
                        # below, and the WHOLE assignmentPolicy is reported Failed instead of being
                        # created or updated. Test-OERStructureSchema below now warns offline about that
                        # outcome instead of the document silently discovering it at apply time.
                        $HasDurationDays = Test-OERDeclaredProperty -Node $StageEntry -Name 'durationDays'
                        $StageDurationDays = if ($HasDurationDays) { [int]$StageEntry.durationDays } else { 0 }
                        $StageParams = @{ DurationDays = $StageDurationDays; ErrorAction = 'Stop' }

                        $StageUsers = if (Test-OERDeclaredProperty -Node $StageEntry -Name 'users') { @($StageEntry.users) } else { @() }
                        $StageGroups = if (Test-OERDeclaredProperty -Node $StageEntry -Name 'groups') { @($StageEntry.groups) } else { @() }
                        $UseManager = (Test-OERDeclaredProperty -Node $StageEntry -Name 'manager') -and ([bool]$StageEntry.manager)
                        $UseInternal = (Test-OERDeclaredProperty -Node $StageEntry -Name 'internalSponsor') -and ([bool]$StageEntry.internalSponsor)
                        $UseExternal = (Test-OERDeclaredProperty -Node $StageEntry -Name 'externalSponsor') -and ([bool]$StageEntry.externalSponsor)
                        $HasExplicitApprover = ($StageUsers.Count -gt 0) -or ($StageGroups.Count -gt 0) -or $UseManager -or $UseInternal -or $UseExternal

                        if ($StageUsers.Count -gt 0) { $StageParams.User = $StageUsers }
                        if ($StageGroups.Count -gt 0) { $StageParams.Group = $StageGroups }
                        if ($UseManager) {
                            $StageParams.Manager = $true
                            if (Test-OERDeclaredProperty -Node $StageEntry -Name 'managerLevel') { $StageParams.ManagerLevel = [int]$StageEntry.managerLevel }
                        }
                        if ($UseInternal) { $StageParams.InternalSponsor = $true }
                        if ($UseExternal) { $StageParams.ExternalSponsor = $true }

                        $AltUsers = if (Test-OERDeclaredProperty -Node $StageEntry -Name 'alternateUsers') { @($StageEntry.alternateUsers) } else { @() }
                        $AltGroups = if (Test-OERDeclaredProperty -Node $StageEntry -Name 'alternateGroups') { @($StageEntry.alternateGroups) } else { @() }
                        if ($AltUsers.Count -gt 0) { $StageParams.AlternateUser = $AltUsers }
                        if ($AltGroups.Count -gt 0) { $StageParams.AlternateGroup = $AltGroups }

                        # fallbackUsers/fallbackGroups feed New-OERAccessPackageApprovalStage's -FallbackUser/
                        # -FallbackGroup, which both land on fallbackPrimaryApprovers only. There is no
                        # document-authorable equivalent for fallbackEscalationApprovers -- Learn documents
                        # the fallback mechanism in terms of a missing manager/sponsor on the PRIMARY
                        # approver, and the Entra UI exposes a single "Add fallback" control, so a second
                        # parameter pair would be surface without a verified use. This is a LOSS, not a
                        # tidy carve-out: fallbackEscalationApprovers is neither read into the projection
                        # nor authorable here, and every stage is rebuilt as a whole on update (Microsoft
                        # Graph takes the full approvalStages array, not a per-stage patch), so a stage
                        # rebuilt through this handler sends an empty escalation fallback and CLEARS a
                        # portal-set one. The exposure is narrow: -AlternateUser/-AlternateGroup (declared
                        # here as alternateUsers/alternateGroups) build user/group escalation approvers,
                        # which need no fallback -- the case that bites is a manager or sponsor escalation
                        # configured in the portal.
                        $FbUsers = if (Test-OERDeclaredProperty -Node $StageEntry -Name 'fallbackUsers') { @($StageEntry.fallbackUsers) } else { @() }
                        $FbGroups = if (Test-OERDeclaredProperty -Node $StageEntry -Name 'fallbackGroups') { @($StageEntry.fallbackGroups) } else { @() }
                        if ($FbUsers.Count -gt 0) { $StageParams.FallbackUser = $FbUsers }
                        if ($FbGroups.Count -gt 0) { $StageParams.FallbackGroup = $FbGroups }

                        if (Test-OERDeclaredProperty -Node $StageEntry -Name 'escalationDays') { $StageParams.EscalationDays = [int]$StageEntry.escalationDays }
                        if ((Test-OERDeclaredProperty -Node $StageEntry -Name 'requireApproverJustification') -and ([bool]$StageEntry.requireApproverJustification)) { $StageParams.RequireJustification = $true }
                        if (Test-OERDeclaredProperty -Node $StageEntry -Name 'approverInfoVisibility') { $StageParams.ApproverInfoVisibility = [string]$StageEntry.approverInfoVisibility }

                        if (-not $HasExplicitApprover) {
                            # Back-compat: fall back to the Tenant Profile approver defaults.
                            $Pa = Resolve-OERStructureDefault -TenantAlias $Alias -Name 'PrimaryApprovers'
                            $Ea = Resolve-OERStructureDefault -TenantAlias $Alias -Name 'EscalationApprovers'
                            if (-not $Pa) {
                                return @{ Success = $false; FailDetail = "assignmentPolicy '$PolicyName': an approval stage has no manager, no explicit approvers, and no Tenant Profile PrimaryApprovers default"; ErrorRecord = $null }
                            }

                            # Issue #68: this branch is reached by two different document shapes that mean
                            # different things to an operator, so distinguish them in the warning rather
                            # than documenting the substitution away:
                            #   - no approver keys declared at all -- the back-compat path, expected;
                            #   - approver keys declared but all empty -- the author tried to express "no
                            #     approvers" and got the Tenant Profile default instead, since
                            #     New-OERAccessPackageApprovalStage hard-rejects a zero-approver stage
                            #     (NoApprover) and there is no way to author a true zero-approver stage.
                            # The distinguishing clause is read with Test-OERDeclaredProperty, never an
                            # inline PSObject.Properties check, per the module's single "declared" owner.
                            $HasAnyApproverKey = (Test-OERDeclaredProperty -Node $StageEntry -Name 'users') -or
                                (Test-OERDeclaredProperty -Node $StageEntry -Name 'groups') -or
                                (Test-OERDeclaredProperty -Node $StageEntry -Name 'manager') -or
                                (Test-OERDeclaredProperty -Node $StageEntry -Name 'internalSponsor') -or
                                (Test-OERDeclaredProperty -Node $StageEntry -Name 'externalSponsor')
                            # $PaCount is safe as a bare @($Pa).Count: the guard two lines above already
                            # returned when $Pa was falsy, so $Pa is guaranteed non-null/non-empty here.
                            # $Ea carries no such guard -- Resolve-OERStructureDefault returns a bare $null
                            # when the profile has no EscalationApprovers default, and @($null).Count is 1,
                            # not 0 (a repeat offender in this module's own history). Route it through an
                            # explicit truthiness check so a genuinely empty default can never be
                            # misreported as "1 EscalationApprovers". $EaCount is now only ever RENDERED on
                            # the branch below that actually substituted the escalation default (which
                            # already requires $Ea to be truthy), so the guard is belt-and-braces -- keep it
                            # anyway, so the count cannot regress if that branch condition ever changes.
                            $PaCount = @($Pa).Count
                            $EaCount = if ($Ea) { @($Ea).Count } else { 0 }

                            # Issue #68: only substitute the escalation default when the document declared
                            # NO alternateUsers at all -- gated on Test-OERDeclaredProperty, not on
                            # $AltUsers.Count -eq 0 and not on -not $StageParams.ContainsKey('AlternateUser').
                            # Both rejected forms also hold true for a document that declared
                            # "alternateUsers": [] (an explicit "no escalation approvers"), because the
                            # -AlternateUser splat key above is only added when the array is non-empty; either
                            # rejected form would let this fallback silently override that explicit statement.
                            #
                            # The decision is taken HERE, above the warning, and the warning reads it --
                            # measured live: a stage declaring "users": [] with its own alternateUsers kept
                            # the document's escalation approver (issue #68's fix working), while the warning
                            # still printed the profile's EscalationApprovers count, naming a substitution
                            # that never happened and reading exactly like the pre-#68 behaviour it was added
                            # to make visible. The message names only what was actually substituted.
                            $SubstituteEscalation = [bool]($Ea -and -not (Test-OERDeclaredProperty -Node $StageEntry -Name 'alternateUsers'))
                            $Substituted = if ($SubstituteEscalation) {
                                "$PaCount PrimaryApprovers, $EaCount EscalationApprovers"
                            } else {
                                "$PaCount PrimaryApprovers"
                            }
                            if ($HasAnyApproverKey) {
                                Write-Warning "Sync-OERStructureAccessPackage: assignmentPolicy '$PolicyName' stage $StageIndex declared approver keys (users/groups/manager/internalSponsor/externalSponsor) that are all empty; substituting Tenant Profile '$Alias' defaults ($Substituted) instead of the zero-approver stage the document tried to express."
                            } else {
                                Write-Warning "Sync-OERStructureAccessPackage: assignmentPolicy '$PolicyName' stage $StageIndex declared no approver keys at all; substituting Tenant Profile '$Alias' defaults ($Substituted) (back-compat)."
                            }

                            $StageParams.User = @($Pa)
                            if ($SubstituteEscalation) {
                                $StageParams.AlternateUser = @($Ea)
                            }
                        }

                        $BuiltStages.Add((New-OERAccessPackageApprovalStage @StageParams))
                    }
                }
            } catch {
                Remove-OERErrorRecord -Record $PSItem
                return @{ Success = $false; FailDetail = "failed to build assignmentPolicy '$PolicyName': $($PSItem.Exception.Message)"; ErrorRecord = $PSItem }
            }

            return @{
                Success           = $true
                RequestorScope    = $BuiltScope
                RequestorSettings = $BuiltSettings
                Stages            = $BuiltStages.ToArray()
                BodyScalars       = $BodyScalars
                DeclaredFields    = $DeclaredFields.ToArray()
                FailDetail        = $null
                ErrorRecord       = $null
            }
        }

        $DeclaredPolicyNames = [System.Collections.Generic.List[string]]::new()
        # The ids of the live policies an entry's previousDisplayName names, once the entry's displayName
        # has passed its own duplicate refusal. The Extra pass below never reports one of them: the policy
        # an entry renames was read under its previous name, and a policy a refused rename names is named
        # by that entry's own Failed row (the conflict row by its name, the ambiguous previous name row by
        # its id), not an undeclared policy. An entry stopped by the duplicate refusal of its displayName
        # names none, so the policy under its previous name is still reported Extra there. The name check
        # stays as it was for every other live policy.
        $PreviousPolicyIds = [System.Collections.Generic.List[string]]::new()
        if (Test-OERDeclaredProperty -Node $Item -Name 'assignmentPolicies') {
            foreach ($PolEntry in @($Item.assignmentPolicies)) {
                $PolName = $PolEntry.displayName
                $DeclaredPolicyNames.Add(([string]$PolName).ToLowerInvariant())

                # Every match is kept, never just the first (decision D3). Assignment policy display
                # names are NOT unique within an access package in Microsoft Graph, and the reconcile
                # below writes by the matched policy's id (requestor scope, approval), so taking the
                # first of several would silently update an arbitrary one. More than one match
                # refuses this policy and moves on to the next declared one: nothing is created or
                # updated for it, and the package's other declared policies are processed as before
                # (its resource role bindings were reconciled in an earlier step). One match and no
                # match are exactly what they were. The refusal sits BEFORE the policy parts are
                # built, so a policy that will not be touched raises no approver-default warnings.
                $MatchingPolicies = @($CurrentPolicies | Where-Object { $_.DisplayName -eq $PolName })
                if ($MatchingPolicies.Count -gt 1) {
                    # The message follows the text Resolve-OERAccessReviewScopeTarget publishes for the
                    # review scope (decision D3) and Sync-OERStructureAccessReview for a definition
                    # (decision D2), with ONE deliberate difference: its last sentence. displayName is an
                    # assignmentPolicies entry's match key and has no id form (only previousDisplayName
                    # takes an object id, and this refusal comes first), so this one says to rename a
                    # policy instead of re-running with an id. Keep the texts in step by hand.
                    $AmbiguousIds = ($MatchingPolicies | ForEach-Object { [string]$_.Id }) -join ', '
                    $AmbiguousRecord = [System.Management.Automation.ErrorRecord]::new(
                        [System.Exception]::new(
                            "Assignment policy display name '$PolName' matches $($MatchingPolicies.Count) policies ($AmbiguousIds) in access package '$Name'. " +
                            'Access packages do not enforce unique policy display names, so this name ' +
                            'cannot identify a single policy. Rename one of them so the display name is unique.'),
                        'AmbiguousName',
                        [System.Management.Automation.ErrorCategory]::InvalidArgument,
                        $PolName)
                    $Caller.WriteError($AmbiguousRecord)
                    ConvertTo-OERStructureResult -Section 'accessPackages' -Item $Name -Action 'Failed' `
                        -Detail "$($MatchingPolicies.Count) assignment policies of '$Name' are named '$PolName' ($AmbiguousIds); nothing was written for it" `
                        -ErrorRecord $AmbiguousRecord
                    continue
                }
                $ExistingPol = $MatchingPolicies | Select-Object -First 1

                # -- Rename through previousDisplayName (BL-128 part 2) --------------------------
                # Decided once both names are matched and before anything is built, diffed or written
                # for the policy, under -WhatIf too. A previous name several policies of the package
                # carry is refused first, as an ambiguous displayName is: one AmbiguousName record whose
                # target is the previous name, one Failed row, nothing written for the policy.
                # Resolve-OERStructureRename then owns the decision, the two refusals
                # (AssignmentPolicyRenameConflict, AssignmentPolicyRenameNotFound), their texts and the
                # rename map entry that replaces the policy's undecided mark -- under the package's
                # declared name and, since the package's id is known here, under its id as well.
                # previousDisplayName is matched in the package's policy list, which is already read, and
                # needs no request of its own. An object id matches only the Id of a policy of THIS
                # package (R5), without regard to letter case; a name matches DisplayName without regard
                # to letter case, as displayName does.
                $PolHasPrev = Test-OERDeclaredProperty -Node $PolEntry -Name 'previousDisplayName'
                $PolPrev = $null
                $PolPrevMatches = @()
                $PolRenameFrom = $null
                $PolRenameLabel = $null
                if ($PolHasPrev) {
                    $PolPrev = [string]$PolEntry.previousDisplayName
                    $PolPrevMatches = if (Test-OERGuid -Value $PolPrev) {
                        @($CurrentPolicies | Where-Object { [string]$_.Id -ieq $PolPrev })
                    } else {
                        @($CurrentPolicies | Where-Object { [string]$_.DisplayName -ieq $PolPrev })
                    }
                    foreach ($PrevPol in $PolPrevMatches) { $PreviousPolicyIds.Add([string]$PrevPol.Id) }
                    if ($PolPrevMatches.Count -gt 1) {
                        $PrevAmbiguousIds = ($PolPrevMatches | ForEach-Object { [string]$_.Id }) -join ', '
                        $PrevAmbiguousRecord = [System.Management.Automation.ErrorRecord]::new(
                            [System.Exception]::new(
                                "Assignment policy display name '$PolPrev', the previousDisplayName of assignment policy '$PolName', matches $($PolPrevMatches.Count) policies ($PrevAmbiguousIds) in access package '$Name'. " +
                                'Access packages do not enforce unique policy display names, so this name ' +
                                'cannot identify a single policy. Declare previousDisplayName as the object id of the policy to rename.'),
                            'AmbiguousName',
                            [System.Management.Automation.ErrorCategory]::InvalidArgument,
                            $PolPrev)
                        $Caller.WriteError($PrevAmbiguousRecord)
                        ConvertTo-OERStructureResult -Section 'accessPackages' -Item $Name -Action 'Failed' `
                            -Detail "assignmentPolicy '$PolName': $($PolPrevMatches.Count) assignment policies of '$Name' are named '$PolPrev' ($PrevAmbiguousIds), the previousDisplayName of this entry; the name cannot identify one, so nothing was written for it -- declare previousDisplayName as the object id of the policy to rename" `
                            -ErrorRecord $PrevAmbiguousRecord
                        continue
                    }
                    $PolPrevId = if ($PolPrevMatches.Count -eq 1) { [string]$PolPrevMatches[0].Id } else { $null }
                    $PolCurId = if ($ExistingPol) { [string]$ExistingPol.Id } else { $null }
                    # Reset first: a call that fails to bind must never leave the previous entry's
                    # decision in use for this one. Under Invoke-OERStructure such a failure ends the item
                    # in the engine's catch; with no try anywhere on the stack it only skips the assignment
                    # and execution carries on, so a missing decision stops this policy, nothing written
                    # for it -- the binding error is its report (an empty name, which the validator
                    # refuses).
                    $PolRename = $null
                    $PolRename = Resolve-OERStructureRename -Section 'assignmentPolicies' -AccessPackage ([string]$Name) `
                        -AccessPackageId ([string]$ApId) -Name ([string]$PolName) -PreviousName $PolPrev `
                        -Id $PolCurId -PreviousId $PolPrevId -RenameMap $RenameMap
                    if ($null -eq $PolRename) { continue }
                    if ($PolRename.ErrorRecord) {
                        # Conflict or NotFound: nothing is built, created or updated for this policy, and
                        # the package's other declared policies carry on.
                        $Caller.WriteError($PolRename.ErrorRecord)
                        $PolRename.Result
                        continue
                    }
                    if ($PolRename.Outcome -eq 'Rename') {
                        # The policy found under its previous name takes the existing-policy path below,
                        # and the rename travels in its one Set-OERAccessPackageAssignmentPolicy call.
                        # The texts name it by the previous name the entry declares, or, when that is an
                        # object id, by its current name and its id: '<current name>' (<id>).
                        $ExistingPol = $PolPrevMatches[0]
                        $PolRenameFrom = $PolRename.RenameFrom
                        $PolRenameLabel = if (Test-OERGuid -Value $PolRenameFrom) {
                            "'$([string]$ExistingPol.DisplayName)' ($([string]$ExistingPol.Id))"
                        } else {
                            "'$PolRenameFrom'"
                        }
                    }
                }

                # A live policy whose allowedTargetScope reads as unknownFutureValue carries a scope
                # Microsoft Graph only names when asked with 'Prefer: include-unknown-enum-members',
                # which this module never sends. Its real scope (and any targets that go with it) is
                # therefore unreadable here, and a full-PUT update would overwrite it with whatever the
                # entry declares or carry the placeholder back. Refuse the policy whatever the entry
                # declares, before the parts are built, the diff runs or ShouldProcess is asked -- so
                # it reads the same under -WhatIf -- as a Failed row without an ErrorRecord, the same
                # form as the missing tenant default in Build-OERPolicyParts (no Graph error to carry).
                if ($ExistingPol -and [string]$ExistingPol.RequestorScope.scope -eq 'unknownFutureValue') {
                    ConvertTo-OERStructureResult -Section 'accessPackages' -Item $Name -Action 'Failed' `
                        -Detail ("Microsoft Graph returned allowedTargetScope 'unknownFutureValue', a value this module " +
                            "cannot read without the 'Prefer: include-unknown-enum-members' header, so nothing was " +
                            "written for assignmentPolicy '$PolName'.")
                    continue
                }

                # Build the desired parts once (used by the diff and by the Set/New call).
                $Parts = Build-OERPolicyParts -PolicyEntry $PolEntry -PolicyName $PolName -Alias $TenantAlias
                if (-not $Parts.Success) {
                    if ($Parts.ErrorRecord) { $Caller.WriteError($Parts.ErrorRecord) }
                    ConvertTo-OERStructureResult -Section 'accessPackages' -Item $Name -Action 'Failed' -Detail $Parts.FailDetail -ErrorRecord $Parts.ErrorRecord
                    continue
                }

                if ($ExistingPol) {
                    # -- Project the desired body and diff it over the declared fields only. --
                    $BodyParams = @{
                        DisplayName     = $PolName
                        AccessPackageId = $ApId
                        RequestorScope  = $Parts.RequestorScope
                    }
                    if ($Parts.RequestorSettings) { $BodyParams.RequestorSettings = $Parts.RequestorSettings }
                    # Declared-gate (issue #56). Behaviour-neutral here -- ConvertTo-OERPolicyBody is
                    # called without -Existing, so an omitted key and a declared [] both resolve to no
                    # stages -- but a count-based gate is the wrong predicate everywhere. See the Set
                    # splat below for the site where it actually changed behaviour.
                    if (@($Parts.DeclaredFields) -contains 'approvalStages') { $BodyParams.ApprovalStage = $Parts.Stages }
                    foreach ($K in $Parts.BodyScalars.Keys) { $BodyParams[$K] = $Parts.BodyScalars[$K] }

                    $Change = $null
                    try {
                        $DesiredBody = ConvertTo-OERPolicyBody @BodyParams -ErrorAction Stop
                        $DesiredProj = ConvertTo-OERAssignmentPolicy -InputObject $DesiredBody -AccessPackageId $ApId
                        $Change = Resolve-OERAssignmentPolicyChange -Desired $DesiredProj -Current $ExistingPol -DeclaredFields @($Parts.DeclaredFields)
                    } catch {
                        Remove-OERErrorRecord -Record $PSItem
                        $Caller.WriteError($PSItem)
                        ConvertTo-OERStructureResult -Section 'accessPackages' -Item $Name -Action 'Failed' -Detail "failed to diff assignmentPolicy '$PolName': $($PSItem.Exception.Message)" -ErrorRecord $PSItem
                        continue
                    }

                    # A rename is a difference of its own: the declared fields may all match, and the
                    # policy still has to be renamed, so the Set call below is sent for it alone
                    # (Set-OERAccessPackageAssignmentPolicy takes a -DisplayName that differs from the live
                    # name as an update, A16).
                    if (-not $Change.Differs -and -not $PolRenameFrom) {
                        ConvertTo-OERStructureResult -Section 'accessPackages' -Item $Name -Action 'Unchanged' -Detail "assignmentPolicy '$PolName' matches"
                        continue
                    }
                    # A declared requestorScope is sent whole: the builder's specificAllowedTargets
                    # REPLACE the live ones. For SpecificConnectedOrganizationUsers the builder has no
                    # targets to give -- this module does not model connected organization targets (the
                    # projection and the diff know users and groups only) -- so the update would send
                    # the scope with an empty target list and drop every connected organization the live
                    # policy names (measured: the PUT body carried specificAllowedTargets []). Refuse
                    # that write before ShouldProcess, so it reads the same under -WhatIf. Omitting
                    # requestorScope from the entry leaves -RequestorScope off the Set call, which
                    # carries the live scope and its targets forward as one unit. A diff with no
                    # difference and no rename already returned Unchanged above (nothing written, nothing
                    # lost), and create is not refused (no live target to lose). A rename sends the
                    # declared scope too, so it is refused the same way.
                    if ((@($Parts.DeclaredFields) -contains 'requestorScope') -and
                        [string]$Parts.RequestorScope.AllowedTargetScope -eq 'specificConnectedOrganizationUsers') {
                        ConvertTo-OERStructureResult -Section 'accessPackages' -Item $Name -Action 'Failed' `
                            -Detail ("assignmentPolicy '$PolName' declares requestorScope SpecificConnectedOrganizationUsers, " +
                                'but this module does not model connected organization targets, so the update would ' +
                                'drop any the live policy names; nothing was written for it. Omit requestorScope ' +
                                'from the entry to update the other fields while keeping the live scope.')
                        continue
                    }
                    # The rename is reported on its own terms; the changed fields keep the wording every
                    # policy update has always had. Without a rename every text is what it always was.
                    $PolicyFieldList = $Change.ChangedFields -join ', '
                    if ($PolRenameFrom) {
                        $PolicyAction = "Rename assignmentPolicy $PolRenameLabel to '$PolName'"
                        $PolicyUpdatedDetail = "renamed assignmentPolicy $PolRenameLabel to '$PolName'"
                        $PolicyPlannedDetail = "would rename assignmentPolicy $PolRenameLabel to '$PolName'"
                        $PolicyFailedPrefix = "failed to rename assignmentPolicy $PolRenameLabel to '$PolName'"
                        if ($Change.Differs) {
                            $PolicyAction += ' and update it'
                            $PolicyUpdatedDetail += "; updated assignmentPolicy fields ($PolicyFieldList)"
                            $PolicyPlannedDetail += "; would update assignmentPolicy fields ($PolicyFieldList)"
                        }
                    } else {
                        $PolicyAction = "Update assignmentPolicy '$PolName'"
                        $PolicyUpdatedDetail = "updated assignmentPolicy '$PolName' ($PolicyFieldList)"
                        $PolicyPlannedDetail = "would update assignmentPolicy '$PolName'"
                        $PolicyFailedPrefix = "failed to update assignmentPolicy '$PolName'"
                    }
                    if (-not $Caller.ShouldProcess($Name, $PolicyAction)) {
                        ConvertTo-OERStructureResult -Section 'accessPackages' -Item $Name -Action 'Skipped' -Detail $PolicyPlannedDetail
                        continue
                    }

                    # requestorScope is written ONLY when the document entry declared it; otherwise the
                    # policy keeps its live scope. Sending the AllMemberUsers default here used to reset
                    # a live SpecificDirectoryUsers scope whenever an unrelated field changed.
                    # -DisplayName is the declared name on every call, so a policy found under its
                    # previous name (-Id) is renamed in this same call as every other declared field.
                    $SetParams = @{ Id = $ExistingPol.Id; DisplayName = $PolName; Confirm = $false }
                    if (@($Parts.DeclaredFields) -contains 'requestorScope') { $SetParams.RequestorScope = $Parts.RequestorScope }
                    if ($Parts.RequestorSettings) { $SetParams.RequestorSettings = $Parts.RequestorSettings }
                    # approvalStages is written ONLY when the document entry declared it, and this is the
                    # LOAD-BEARING one of the three declared-gates (issue #56).
                    # Set-OERAccessPackageAssignmentPolicy GETs the live policy and hands it to
                    # ConvertTo-OERPolicyBody as -Existing, so an OMITTED -ApprovalStage carries the live
                    # stages forward. The old count-based gate therefore made a declared
                    # "approvalStages": [] indistinguishable from an omitted key: the stages were carried
                    # forward every run and the document never converged. An empty $Parts.Stages binds
                    # fine -- there is no ValidateNotNullOrEmpty on -ApprovalStage and the per-entry type
                    # check iterates zero times -- so do NOT "simplify" this back to a Count check, and do
                    # not wrap $Parts.Stages in @() here without re-checking that the empty case binds.
                    if (@($Parts.DeclaredFields) -contains 'approvalStages') { $SetParams.ApprovalStage = $Parts.Stages }
                    foreach ($K in $Parts.BodyScalars.Keys) {
                        # Switch-typed cmdlet params take a [bool] value when declared; ints/datetime pass through.
                        $SetParams[$K] = $Parts.BodyScalars[$K]
                    }
                    try {
                        Set-OERAccessPackageAssignmentPolicy @SetParams -ErrorAction Stop | Out-Null
                        ConvertTo-OERStructureResult -Section 'accessPackages' -Item $Name -Action 'Updated' -Detail $PolicyUpdatedDetail
                    } catch {
                        Remove-OERErrorRecord -Record $PSItem
                        $Caller.WriteError($PSItem)
                        ConvertTo-OERStructureResult -Section 'accessPackages' -Item $Name -Action 'Failed' -Detail "${PolicyFailedPrefix}: $($PSItem.Exception.Message)" -ErrorRecord $PSItem
                    }
                    continue
                }

                # -- CREATE (absent) -- use the same desired parts.
                if ($Caller.ShouldProcess($Name, "Create assignmentPolicy '$PolName'")) {
                    # AccessPackage takes the RESOLVED $ApId, not $Name -- matching the UPDATE path
                    # above, which already identifies the package by id. A display name here is
                    # resolved tenant-wide and would create the policy on the wrong package (or
                    # fail with AmbiguousName) whenever the name is reused across catalogs.
                    $PolicyParams = @{ AccessPackage = $ApId; DisplayName = $PolName; RequestorScope = $Parts.RequestorScope; Confirm = $false }
                    if ($Parts.RequestorSettings) { $PolicyParams.RequestorSettings = $Parts.RequestorSettings }
                    # Declared-gate (issue #56). Behaviour-neutral on create -- there is no live policy to
                    # carry stages forward from -- but a count-based gate is the wrong predicate everywhere.
                    if (@($Parts.DeclaredFields) -contains 'approvalStages') { $PolicyParams.ApprovalStage = $Parts.Stages }
                    foreach ($K in $Parts.BodyScalars.Keys) { $PolicyParams[$K] = $Parts.BodyScalars[$K] }
                    try {
                        New-OERAccessPackageAssignmentPolicy @PolicyParams -ErrorAction Stop | Out-Null
                        ConvertTo-OERStructureResult -Section 'accessPackages' -Item $Name -Action 'Created' -Detail "created assignmentPolicy '$PolName'"
                    } catch {
                        Remove-OERErrorRecord -Record $PSItem
                        $Caller.WriteError($PSItem)
                        ConvertTo-OERStructureResult -Section 'accessPackages' -Item $Name -Action 'Failed' -Detail "failed to create assignmentPolicy '$PolName': $($PSItem.Exception.Message)" -ErrorRecord $PSItem
                        continue
                    }
                } else {
                    ConvertTo-OERStructureResult -Section 'accessPackages' -Item $Name -Action 'Skipped' -Detail "would create assignmentPolicy '$PolName'"
                }
            }

            # Undeclared live policies are reported, never deleted. -Prune is scoped to resource role
            # bindings on this handler (see .PARAMETER Prune): removing a self-service request policy is
            # a different blast radius, and Microsoft Learn does not state whether a package's last
            # policy may be deleted at all. Report it so it is visible instead of silently in force.
            # A policy an entry's previousDisplayName names is not undeclared (see $PreviousPolicyIds).
            foreach ($CurPol in $CurrentPolicies) {
                $CurPolName = [string]$CurPol.DisplayName
                if ($DeclaredPolicyNames -contains $CurPolName.ToLowerInvariant()) { continue }
                if ($PreviousPolicyIds -contains [string]$CurPol.Id) { continue }
                ConvertTo-OERStructureResult -Section 'accessPackages' -Item $Name -Action 'Extra' `
                    -Detail "undeclared assignmentPolicy '$CurPolName' is still in force (the engine never removes assignment policies; use Remove-OERAccessPackageAssignmentPolicy)"
            }
        }
    }
}
