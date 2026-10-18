function Test-OERStructureSchema {
    <#
    .SYNOPSIS
    Validates an orchestration document offline and returns a tagged validation result.

    .DESCRIPTION
    Performs the shared, tenant-free schema validation used by both Test-OERStructure and
    Invoke-OERStructure. Checks the required version key, checks that a top-level tenantId, when
    present, is a string holding a canonical GUID (an explicit null, a value that is not a string, such
    as an array, or any other value is an Error; a document without the key is valid), rejects
    unknown top-level keys, requires each present section to be an array, and validates the per-item shape of every section (required fields,
    enum values (including eligibility accessType member/owner and membershipRuleProcessingState On/Paused, shared by administrative units and groups), mutually exclusive displayName/template, numeric ranges). A catalog's externallyVisible must be a boolean. A roleAssignments
    item's conditionVersion without a condition is an Error (a version alone has no effect); a condition
    without a conditionVersion is a Warning (Azure Resource Manager defaults it to 2.0). A catalog
    resource's url, when present, must be a non-empty string (Error); a SharePointSite resource with
    neither a url nor a URL-shaped name is a Warning, since the site cannot be onboarded from a
    display name alone. The five names an entry is identified by -- an administrative unit
    scopedRoles entry's role and principal, a catalog resource's name, and an access package
    resourceRoles entry's resource and role -- must be non-empty strings: one that is present but
    empty or only whitespace is an Error at its own path ("must be a non-empty string"), while an
    absent one is still reported as required, since an empty name identifies nothing and would
    throw at apply (Get-OERInventory never writes one). An administrative unit scopedRoles entry
    may also carry principalType, which Get-OERInventory writes for a principal the directory
    returned and the apply engine never reads: when present it must be User, Group or
    ServicePrincipal (in any casing, with the casing Warning described below), and an entry without
    it is valid. Intra-document
    cross-reference gaps (for example an access package whose catalog is not declared) are reported as
    Warning-severity entries that do not fail validation, since the referenced object may already exist
    in the tenant. A roleManagementPolicies item validates the settable Azure PIM policy surface except
    notification rules, which are readable and writable through Get-/Set-OERRoleManagementPolicy but
    are not part of this schema and are not validated here: boolean toggles (allowPermanentEligibility,
    allowPermanentActiveAssignment, requireMfaOnActivation,
    requireJustificationOnActivation, requireTicketOnActivation, requireApproval,
    requireMfaOnActiveAssignment, requireJustificationOnActiveAssignment), day-count ranges
    (eligibleDurationDays, activeDurationDays: 1-3650), an approvers object with optional users/groups
    string arrays, and authenticationContextId (a c<digits> claim value, or an empty string to disable
    it; an explicit null means "not declared -- leave the live setting untouched", the same rule
    Test-HasProp applies to every field here and the apply-layer diffs apply in lockstep). A
    requireApproval of false declared together with a non-empty approvers block is a Warning naming
    the precedence: the apply engine drops the approvers, because supplying them to Azure Resource
    Manager would force approval back on. A groups pimPolicy block (flat or nested member/owner)
    validates requireApproval and approvers the same way a roleManagementPolicies item does: a boolean
    toggle, an approvers object with optional users/groups string arrays, and requireApproval false
    declared together with a non-empty approvers block is the same Warning naming the precedence, at
    the pimPolicy block's own path. requireMfaOnActivation together with a non-empty authenticationContextId is an Error -- Azure
    PIM rejects both being set at once, a rule draft-07 cannot express, so the offline validator
    enforces it here. A directoryRoleManagementPolicies item (the PIM policy of a Microsoft Entra
    directory role, which always lives at tenant scope) is validated by exactly the same rules as a
    roleManagementPolicies item, through one shared nested helper so the two cannot drift, except that
    it takes no scope: only role is required, a scope key is reported as an unknown key, and the
    MFA/authentication-context Error names PIM rather than Azure PIM. A directoryRoleAssignments
    item (an eligible or active assignment of a Microsoft Entra directory role at tenant scope)
    requires role, principal and assignmentType; assignmentType must be Eligible or Active and
    principalType, when present, User, Group or ServicePrincipal (either in any casing, with the casing
    Warning described below); durationDays must be an integer 1-3650, permanent a boolean and
    justification a string. durationDays together with permanent true is an Error (the two contradict
    each other), and so is permanent false without durationDays (the time-bound window it asks for is
    not declared); an entry with neither is permanent. A second entry naming the same role, principal
    and assignmentType as an earlier one, compared as written without regard to letter case, is an
    Error at the later entry's path naming the earlier index, since applying both would re-issue the
    one live assignment's window on every run. An entry whose principalType is ServicePrincipal (in
    any casing) and whose principal is not a GUID is a Warning at its principal path: service
    principal display names are not unique, and an apply run refuses an ambiguous one (the entry
    reports Failed), so a service principal is named by its object id. An unknown per-item key in the
    roleAssignments, roleManagementPolicies, directoryRoleManagementPolicies or directoryRoleAssignments section, a
    groups[] item, or a groups[] pimPolicy block (root, or a nested member/owner block) is reported as a
    Warning naming the key, because the apply handlers for those sections and blocks read a fixed field
    list and would otherwise drop it silently. A pimPolicy key matching one of the five field names the
    inventory README used to document before they were renamed (activationEnabledRules,
    activeEnabledRules, eligibleAlertRecipients, activeAlertRecipients, activationAlertRecipients) gets a
    "Did you mean '<current name>'?" suffix pointing at its replacement. Other sections keep accepting
    unknown keys without comment. previousDisplayName is accepted on a groups, administrativeUnits,
    catalogs, accessPackages, accessPackages assignmentPolicies and accessReviews entry alike, with the
    rules described below (BL-128). An accessPackages assignmentPolicies entry declaring requireApproval true together
    with an empty approvalStages array is a Warning naming the measured outcome: Microsoft Graph refuses
    the write with InvalidApprovalStages ("If approval is required, a valid list of stages must be
    provided."), so the assignment policy is reported Failed and left completely unchanged and the
    document never converges -- it reports Failed on every run. An entry declaring an empty
    approvalStages array WITHOUT declaring both requireApproval false and requireApprovalForUpdate false
    is a second, mutually exclusive Warning for the same refusal reached without a self-contradictory
    document: ConvertTo-OERPolicyBody derives isApprovalRequiredForAdd false from the declared stage
    count, but isApprovalRequiredForUpdate falls to its Existing carry-forward branch and re-sends the
    live policy's value, so an undeclared flag is not an absent one and Graph refuses the emptied stage
    list while approval is still required for update. Exactly one of the two fires for any one policy.
    A requestorScope declaring a non-empty users or
    groups array with no scope is a Warning (issue #69): Invoke-OERStructure infers scope as
    SpecificDirectoryUsers for that shape, so the document is no longer refused. The shape it
    replaces was an Error here, and Invoke-OERStructure refuses any document carrying one with no
    -SkipValidation escape, so the AllMemberUsers default this inference displaces was never actually
    applied to a tenant through the public entry point -- what changes is that the document is now
    accepted, not what an accepted document did. Only a requestorScope with no scope AND no non-empty
    users/groups keeps the Error, since nothing is inferable there. A
    requestorScope declaring a non-empty users or groups array together with an explicit scope other
    than SpecificDirectoryUsers is also a Warning: the explicit scope always wins over inference, so
    those users/groups are silently unused. An approvalStages entry with no declared durationDays
    (absent or explicit null) is a Warning naming the real outcome: Build-OERPolicyParts keeps the
    applied value at 0 since -DurationDays on New-OERAccessPackageApprovalStage is Mandatory and the
    splat key cannot be dropped, and New-OERAccessPackageApprovalStage's own duration encoder rejects
    a value below 1, so the build throws and the whole assignmentPolicy is reported Failed instead of
    being created or updated (issue #70).
    Every closed enum value (accessType, enablement, membershipRuleProcessingState,
    catalogResourceType, approverInfoVisibility, accessReviewRecurrence, accessReviewDefaultDecision,
    principalType, directoryRoleAssignmentType, principalStatus) is accepted in any casing, but a non-canonically cased
    value is reported as a Warning naming the canonical spelling Get-OERStructureSchemaJson declares,
    because draft-07 matches "enum" case-sensitively. An accessReviews item validates
    reviewers/fallbackReviewers as string arrays,
    descriptionForAdmins/descriptionForReviewers as strings, the five review settings booleans
    (mailNotification, reminderNotification, requireJustification, recommendationsEnabled,
    autoApplyDecisions), defaultDecision against the None/Approve/Deny/Recommendation enum,
    durationInDays as an integer 1-365, occurrences as an integer >= 1, and startDate/endDate as
    parseable date/time strings. endDate and occurrences are mutually exclusive (Error); either one
    declared alongside an absent or OneTime recurrence has no effect and is a Warning, since
    New-OERAccessReviewRecurrence never builds a recurrence object for a OneTime review. A manager
    reviewer -- declared explicitly in reviewers, or the handler's default when reviewers is omitted or
    present with an explicit null -- without a fallbackReviewers entry is a Warning, since Microsoft
    Graph rejects a manager reviewer with no fallback. A fallbackReviewers key DECLARED but EMPTY is no
    fallback and warns the same way: Sync-OERStructureAccessReview collects no fallback from it and
    reports Failed without creating the review. A DECLARED but EMPTY reviewers array is not that
    case and is never flagged: it means a self review on both the create and the update path, and a
    self review needs no fallback. A groups[] entry's previousDisplayName (the group's current display
    name or object id, when displayName declares a new one and the apply engine is to rename the
    group) must be a non-empty string (Error); one equal to displayName, ignoring case, is a
    Warning, since both names then find the same group and a case-only rename is not possible
    through the document (Set-OERGroup -NewDisplayName does it). An explicit null is not declared,
    as for every other key, and that Warning does not compare a template-based group's computed name.
    An administrativeUnits, catalogs or accessPackages entry's previousDisplayName (Sprint 11 step 4),
    and the previousDisplayName of an accessPackages assignmentPolicies entry or of an accessReviews
    entry (Sprint 11 step 4b), follow the groups' rules: it must be a non-empty string (Error
    otherwise); one equal to the entry's displayName ignoring case is a Warning naming
    Set-OERAdministrativeUnit, Set-OERCatalog or Set-OERAccessPackage -NewDisplayName, for a policy
    Set-OERAccessPackageAssignmentPolicy -DisplayName together with another property (its -DisplayName
    alone reports NothingToUpdate when only the case differs), and for a review
    Set-OERAccessReviewDefinition -DisplayName. For those kinds but the policy the Warning says that a
    case-only rename is not possible through the document; for a policy it says that such a rename is
    applied only together with another changed field of the policy, since the access package handler
    sends the declared displayName on every update of a policy. An explicit null is not declared. It
    is a claimed key of the duplicate check (below), and a reference to it is warned about (Rule 14,
    below).
    A group's onPremisesSynced, when present, must be a boolean (Error); it is information only.
    A groups[] entry's mailNickname, when present, must be a string (Error) of 1 to 64 characters
    (BL-132): an empty one is an Error, one longer than 64 characters is an Error naming its length, and
    one containing any of @ ( ) \ [ ] " ; : < > , white space or a control character is an Error naming
    each such character (white space and control characters by code point). Microsoft Graph was measured
    (2026-10-13) to refuse the printable set, a space, a tab, the empty string and 65 characters; the
    validator refuses any other white space and any other control character too, which was not
    measured. A non-ASCII letter is accepted, as Microsoft Graph accepts it. A mail alias does not
    follow a rename and none is derived again, so a groups[] entry that declares a previousDisplayName
    different from its displayName (ignoring case) is a Warning at its
    mailNickname path when it declares no mailNickname (it keeps its current alias) or declares one that
    equals, ignoring case, the alias Get-OERDerivedMailNickname derives from the previousDisplayName.
    A groups[] entry declaring a non-empty administrativeUnit whose matching administrativeUnits[]
    entry exists in the same document but does not name the group in its members is a Warning
    (issue #59, BL-07): administrativeUnit is applied only when the group is created and never
    round-trips, so without the reciprocal members entry every later apply with -Prune removes the
    membership, and nothing self-heals it. The run that creates the group withholds that prune
    (Skipped, "prune withheld"), since the apply engine records the membership it created. The unit
    is matched the way New-OERGroup reads administrativeUnit: a value that parses as a GUID (braced
    and dash-less forms included) is an object id and matches the entry that declares that id,
    compared as a GUID; any other value is a display name and matches the entry of that displayName,
    case-insensitively. The group's name is its displayName or, for a template-based group, the name
    Resolve-OERName computes from template and tokens, as the duplicate check below computes it (an
    entry whose name cannot be computed is not checked). The members name the group when they list
    its name or its declared id, ignoring case; when the group declares no id, a member that is an
    object id may be the group, and nothing is reported -- unless that object id is the id another
    groups[] entry declares, which names that other group. Nothing is reported when the unit is
    named by a display name no entry declares (it may be managed elsewhere), or when the matching
    unit declares members as an explicit null (the documented signal that skips reconciling that
    collection entirely). An administrativeUnit that is an object id no entry declares as its id
    names a unit this check cannot identify offline: that is a Warning when at least one
    administrativeUnits[] entry that declares no id of its own (one that does is another unit)
    reconciles its members (members not an explicit null) without naming the group, naming those
    entries and what to do -- name the group in that unit's members, or declare the unit's id on its
    entry. A reference that still names a renamed object by its previous name is a Warning at the
    reference (Rule 14, Sprint 11 step 4): a groups[] entry whose administrativeUnit, an accessPackages[]
    entry whose catalog, or an accessReviews[] entry whose accessPackage equals, ignoring case, the
    previousDisplayName of an entry of that section that renames the object (a non-empty string that
    differs from the entry's displayName ignoring case). Once the rename is applied no object carries
    the previous name, so the Warning says to name the object by its new name (the unit and access
    package Warnings add: or its object id). The first entry that renames from the name is the one
    named. A previousDisplayName that is an object id is skipped, since a reference by id stays valid
    after a rename, and so is an entry without a displayName. For an access package's catalog this
    Warning replaces Rule 11's "Catalog is not declared" Warning, which is not written for a catalog
    that is a renamed catalog's previousDisplayName (an object id included). Rule 14 has a second
    half for policies (Sprint 11 step 4b): an accessReviews[] entry whose assignmentPolicy equals,
    ignoring case, the previousDisplayName of an assignmentPolicies entry that renames its policy (the
    same reading, an object id and an entry without a displayName skipped) of the access package its
    accessPackage names -- by the package's displayName, or by the name or object id it renames from --
    is a Warning at accessReviews[i].assignmentPolicy: once the rename is applied no policy of the
    package carries the old name, so the review's target check fails, and the Warning says to name the
    policy by its new name or its object id. The first policy entry that renames from the name is the
    one named. An accessReviews[] entry whose accessPackage is a string that is not an object id, and
    that equals, ignoring case, the displayName or the previousDisplayName (read as Rule 14 reads it: a
    non-empty string that differs from the entry's displayName ignoring case) of two or more
    accessPackages[] entries is an Error at accessReviews[i].accessPackage naming those entries (Rule 15,
    Sprint 11 step 4b, widened by BL-147): the same name in two catalogs is two packages, but the run's
    rename map keys a package, and the policies within it, by the package's name, without its catalog,
    and every accessPackages entry registers its package there, so the run cannot tell which package the
    review means; the Error says to name the access package by its object id, and says that one of the
    entries is renamed through previousDisplayName only when one is. A second top-level entry
    whose key matches an earlier one, compared without regard to letter case, is an Error at the later
    entry's path that names the earlier entry's index, since the two describe one live object and
    applying both makes each undo the other, or through a child collection removes what the other
    declared, on every run. The keys are: for groups, the group name (displayName, or for a template-based entry
    the name Resolve-OERName computes from template and tokens; an entry whose name cannot be
    computed, for instance through an unknown token, claims no name) together with a declared
    previousDisplayName, which is compared against the names and previous names of every earlier
    entry; for administrativeUnits and catalogs, displayName together with a declared
    previousDisplayName, compared the same way (a previousDisplayName that is not a non-empty string,
    or equals the entry's own displayName ignoring case, claims nothing); for accessReviews,
    displayName together with a declared previousDisplayName, compared the same way; for accessPackages,
    catalog together with displayName, and catalog together with a
    declared previousDisplayName (the same previous name in another catalog is another package, and a
    package that declares no catalog claims nothing); for the assignmentPolicies of one access package
    (Sprint 11 step 4b, Ruling P4; Sprint 11 step 5), displayName together with a declared
    previousDisplayName, compared among the policies of that package only and the same way, so two
    policies declaring the same displayName are reported too: a collision is an Error through the same
    helper, at the later claim's path (accessPackages[i].assignmentPolicies[k], or its
    previousDisplayName) naming the earlier policy as accessPackages[i].assignmentPolicies[n], whether
    the two claims are two displayNames, a displayName and a previousDisplayName or two
    previousDisplayNames (the same name in two packages is two policies, and is not reported); for
    roleAssignments, scope, role and principal; for
    roleManagementPolicies, scope and role; for directoryRoleManagementPolicies, role. A scope is
    compared in the canonical form ConvertTo-OERCanonicalScope owns, a pure helper that the apply
    engine shares, so sub: and subscription: with an id, and mg:, are spellings of the scope's path;
    the comparison never resolves a scope online. A role or principal is compared as written. An
    entry missing a key part is not compared. directoryRoleAssignments keeps its own check, described
    above. A roleAssignments or roleManagementPolicies scope that breaks one of the two scope
    spelling rules -- the trailing or doubled '/' rule (A15) and, for a scope written as an Azure path,
    the segment rules (A13, BL-141) -- is an Error at the entry's scope path, once for each rule it
    breaks, with the message Get-OERScopeSpellingProblem gives for it. That helper owns the rules,
    their order and their texts; its help is the reference list and says why each rule exists
    (docs/development/rationale.md#role-assignment-key). This validator decides no spelling itself:
    Add-ScopeSlashFinding and Add-ScopeSegmentFinding add one Error per problem the helper returns.
    The slash rule applies to every scope; a scope in the mg:, sub: or subscription: form is exempt
    from the segment rules, as the helper decides through ConvertTo-OERScopeSplat, since a lookup
    resolves it and it is never sent as written. A role assignment at a resource whose name breaks a
    rule cannot be declared, and the message says to remove the entry; one or more spaces between
    other characters of a segment are accepted, since an Azure resource name can hold them, so a role
    assignment at such a resource, as Get-OERInventory exports it, is valid. A roleAssignments scope
    that is the Azure root scope '/' (Test-OERAzureRootScope decides, so '//' is reported this
    way too, beside its Error, and so is a spelling the Azure Resource Manager transport sends to the
    root, such as '/.' or '/%2e', beside its A13 Error) is a Warning at the entry's scope path (BL-126): a role assignment
    there is elevated access, which Invoke-OERStructure never creates or removes, so the entry is
    reported Skipped and the root scope is never pruned. A roleManagementPolicies scope '/' is not reported,
    and neither is the '/' of the directory role sections, the Microsoft Entra tenant scope. A
    roleAssignments entry's principalStatus (A18), which Get-OERInventory and Export-OERInventory write
    for a role assignment whose principal the directory did not return, must be the string Deleted or
    Unresolved (any other value, or a value that is not a string, is an Error at its path; a
    non-canonical letter case is a Warning, as for principalType), and the entry's principal must then
    be an object id (Test-OERGuid decides): a principal that is not one is an Error at the principal's
    path, since Invoke-OERStructure looks no principal up for such an entry and never creates a role
    assignment for it. An explicit null principalStatus is not declared, so neither rule applies to it.
    principalStatus is a known key of roleAssignments only: in a directoryRoleAssignments entry it is an
    unknown key. An OMITTED
    groups[].members, administrativeUnits[].members, administrativeUnits[].scopedRoles,
    catalogs[].resources or accessPackages[].resourceRoles key is a Warning naming the collection:
    each of those is still reconciled against an empty declared set when its key is omitted, so
    Invoke-OERStructure -Prune removes every live entry in it. Get-OEROmittedPruneCollection owns
    which keys those are; an explicit null (the "leave it untouched" signal), a declared array (an
    empty one included) and the members of a group or unit declared "dynamic": true are not
    reported. The exclusion trusts the document's dynamic flag: a group declared dynamic whose live
    group is static (Set-OERGroup cannot convert it), or an administrative unit whose conversion to
    dynamic is not applied in this run (-WhatIf, a declined prompt, a failed update, or no
    membershipRule available), still has its omitted members pruned, and is not reported. A
    groups[] entry with a non-empty eligibility or a pimPolicy that names, by displayName (ignoring case)
    or by the id its entry declares, an administrativeUnits[] entry whose restricted is true, or that such
    a unit lists in its members by the group's name or declared id, is a Warning, never an Error (Rule
    16, Sprint 11 step 6, BL-134): the Warning is raised at groups[i].administrativeUnit for the first
    shape and at groups[i] for the second, once for each such unit. A group uses PIM for Groups here when
    it declares a pimPolicy (not null) or an eligibility array with at least one entry. Microsoft Learn
    states that Privileged Identity Management does not support a group in a restricted management
    administrative unit; Invoke-OERStructure still sends the PIM settings and eligibility the document
    declares for such a group, and what Microsoft Graph answers to those writes has not been measured,
    so the finding is a Warning and never an Error. The unit is matched as the administrativeUnit
    placement check above matches it; the members name the group when they list its name (a
    template-based group's computed name included) or its declared id, ignoring case. An exported
    document raises neither shape, since an exported group carries no object id and no
    administrativeUnit and its units list a group member by object id: Export-OERInventory names such
    groups in its own warning and README section. Returns a tagged
    Omnicit.EntraRBAC.StructureValidation object with a Valid flag and an
    Errors collection of records carrying Section, Item, Path, Message, and Severity. No Graph or ARM
    calls are made and no authentication occurs.
    Rule 17 (Sprint 11 step 7) runs only when -NamingStandard is given, which Test-OERStructure passes
    for its -NamingStandard parameter and Invoke-OERStructure never does, so applying a document is
    unchanged. It checks the names of the sections the standard lists (groups, administrativeUnits,
    catalogs, accessPackages, the assignmentPolicies of an access package, accessReviews) and adds one
    Warning per object and broken rule, after every other finding, with Section the top-level section
    (a policy's is accessPackages), Item the name, Path the node that holds it and a Message that says
    which rule the name breaks and what was expected. Test-OERNamingStandardName owns the rules and
    their texts. The name checked is the one an object carries after the step: its displayName, or for
    a group without displayName and with a template the name Resolve-OERName computes from template and
    tokens (a template that cannot be computed gets one Warning saying it was not checked). A
    previousDisplayName is never checked. A group with onPremisesSynced true is skipped, with a Warning
    that says so, unless the standard includes synced groups; then it is checked and each finding says
    its name can only change in the on-premises directory. Every finding is a Warning and never an
    Error, so Valid does not change, and a node that is not the shape it should be (a section that is
    not an array, a null or non-object item, a displayName that is not a non-empty string) is left to
    the findings the validator already raises for it and adds no naming row.
    .PARAMETER Document
    The parsed document object (from Read-OERStructureDocument or ConvertFrom-Json) to validate.
    .PARAMETER NamingStandard
    The naming standard object Read-OERNamingStandard returns. When given, Rule 17 checks the names of
    the sections it lists and adds one Warning for each rule a name breaks. When omitted, no name is
    checked and the findings are exactly what they were without Rule 17.
    .EXAMPLE
    Test-OERStructureSchema -Document ($json | ConvertFrom-Json)
    Returns a StructureValidation describing any schema problems in the document.
    .EXAMPLE
    Test-OERStructureSchema -Document ($json | ConvertFrom-Json) -NamingStandard (Read-OERNamingStandard -Path ./naming-standard.json)
    Returns the same StructureValidation with a Warning for every name that does not follow the standard.
    #>
    [OutputType([PSCustomObject])]
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][PSCustomObject]$Document,
        [Parameter()][PSCustomObject]$NamingStandard
    )

    $Findings = [System.Collections.Generic.List[object]]::new()

    function Add-Finding {
        param([string]$Section, [string]$Item, [string]$Path, [string]$Message, [string]$Severity = 'Error')
        $Findings.Add([PSCustomObject]@{
            Section  = $Section
            Item     = $Item
            Path     = $Path
            Message  = $Message
            Severity = $Severity
        })
    }

    # Delegates to Test-OERDeclaredProperty, the module's one owner of this rule.
    function Test-HasProp {
        param([object]$Node, [string]$Name)
        Test-OERDeclaredProperty -Node $Node -Name $Name
    }

    function Test-IsInt {
        param([object]$Value, [int]$Min, [int]$Max)
        $N = 0
        if (-not [int]::TryParse([string]$Value, [ref]$N)) { return $false }
        return ($N -ge $Min -and $N -le $Max)
    }

    # Per-item objects are intentionally open in schema.json, so an unsupported key passes draft-07
    # validation and is then silently dropped on apply. Surface it as a Warning (never an Error, so no
    # existing document starts failing) in the sections and blocks where the apply handlers read a
    # fixed field list and ignore everything else. The optional -Hint maps a known-obsolete key
    # (case-insensitive) to the current key it was renamed to, so a document still carrying an old
    # inventory README field name gets a did-you-mean pointer instead of a bare "unknown key". Existing
    # callers pass no -Hint, so their messages are unchanged.
    function Add-UnknownKeyWarning {
        param([object]$Node, [string]$Section, [string]$Item, [string]$Path, [string[]]$KnownKey, [hashtable]$Hint)
        if ($null -eq $Node) { return }
        foreach ($Key in $Node.PSObject.Properties.Name) {
            if ($KnownKey -inotcontains $Key) {
                $UnknownKeyMessage = "Unknown key '$Key' at $Path is not applied by Invoke-OERStructure and will be ignored."
                if ($Hint -and $Hint.ContainsKey($Key)) {
                    $UnknownKeyMessage += " Did you mean '$($Hint[$Key])'?"
                }
                Add-Finding -Section $Section -Item $Item -Path "$Path.$Key" `
                    -Message $UnknownKeyMessage `
                    -Severity 'Warning'
            }
        }
    }

    # BL-128 (A5): the one reading of what an administrativeUnits, catalogs, accessPackages,
    # assignmentPolicies (of an access package) or accessReviews entry declares as previousDisplayName,
    # shared by the finding and by the cross-reference rules (11 and 14) so they cannot disagree. Pure:
    # it adds no finding. State is
    #   None      the key is absent or an explicit null (not declared);
    #   Invalid   not a string, or an empty one -- it names no object;
    #   CaseOnly  equal to the entry's own displayName ignoring case -- Graph matches names without
    #             regard to case, so both names find one object and nothing is renamed;
    #   Rename    a non-empty string that differs from displayName ignoring case; Previous holds it.
    function Get-RenameDeclaration {
        param([object]$Node)
        if (-not (Test-HasProp -Node $Node -Name 'previousDisplayName')) {
            return [PSCustomObject]@{ State = 'None'; Previous = $null }
        }
        $Prev = $Node.previousDisplayName
        if ($Prev -isnot [string] -or $Prev.Length -eq 0) {
            return [PSCustomObject]@{ State = 'Invalid'; Previous = $null }
        }
        if ((Test-HasProp -Node $Node -Name 'displayName') -and ([string]$Node.displayName -ieq $Prev)) {
            return [PSCustomObject]@{ State = 'CaseOnly'; Previous = $null }
        }
        [PSCustomObject]@{ State = 'Rename'; Previous = $Prev }
    }

    # BL-128 (A5): administrativeUnits, catalogs, accessPackages, the assignmentPolicies of an access
    # package and accessReviews rename the object found under previousDisplayName, with the groups'
    # rules. A non-string or empty value names nothing (Error); one equal to displayName ignoring case
    # finds the same object, so nothing is renamed (Warning naming the cmdlet and parameter that make a
    # case-only rename). -CaseOnlyClause is the Warning's text before that cmdlet: by default that a
    # case-only rename is not possible through the document. A policy passes its own, since the access
    # package handler sends the declared displayName on every update of a policy, so the declared letter
    # case is applied whenever another declared field of the policy differs. The parameter is
    # -NewDisplayName unless the caller names another; -NameQualifier is the text appended to it as
    # passed, so it carries its own leading space (' together with another property' for a policy,
    # whose -DisplayName alone is NothingToUpdate when only the case differs).
    # Returns the previous name to claim in the duplicate check, or $null when there is none to claim.
    function Test-SupportedRename {
        param(
            [object]$Node, [string]$Section, [string]$Item, [string]$Path, [string]$SetCommand,
            [string]$NameParameter = '-NewDisplayName', [string]$NameQualifier = '',
            [string]$CaseOnlyClause = 'a case-only rename is not possible through the document -- use'
        )
        $Declaration = Get-RenameDeclaration -Node $Node
        switch ($Declaration.State) {
            'Invalid' {
                Add-Finding -Section $Section -Item $Item -Path "$Path.previousDisplayName" `
                    -Message "'previousDisplayName' at $Path must be a non-empty string."
            }
            'CaseOnly' {
                Add-Finding -Section $Section -Item $Item -Path "$Path.previousDisplayName" -Severity 'Warning' `
                    -Message "'previousDisplayName' at $Path equals displayName ignoring case; $CaseOnlyClause $SetCommand $NameParameter$NameQualifier."
            }
        }
        $Declaration.Previous
    }

    # Enum casing has a single owner: Resolve-OERStructureEnumCasing. This validator deliberately
    # keeps ACCEPTING any casing so no document that passes today starts failing -- but schema.json is
    # draft-07, where "enum" matching is case-sensitive, so the same document is rejected by any
    # validator outside the module. Report that as a Warning naming the canonical spelling rather than
    # letting the two artifacts quietly disagree. Read-OERStructureDocument does the normalization.
    function Add-EnumCasingWarning {
        param([string]$EnumName, [string]$Key, [object]$Value, [string]$Section, [string]$Item, [string]$Path)
        $Canonical = Resolve-OERStructureEnumCasing -EnumName $EnumName -Value ([string]$Value)
        if ($null -eq $Canonical -or $Canonical -ceq [string]$Value) { return }
        Add-Finding -Section $Section -Item $Item -Path $Path -Severity 'Warning' `
            -Message ("'$Key' at $Path is '$Value'; the canonical spelling is '$Canonical'. " +
                'Invoke-OERStructure normalizes the casing before it applies the document, but schema.json ' +
                'declares this enum case-sensitively (draft-07), so a validator outside the module rejects it.')
    }

    # BL-02: a second top-level entry whose key matches an earlier one (without regard to letter case)
    # describes the same live object twice, and applying both makes each undo the other -- or, through
    # a child collection, remove what the other declared -- on every run. One rule, one message shape,
    # for every section; directoryRoleAssignments keeps its own older check (Rule 10c).
    # -Seen maps a key to the index of the first entry that claimed it and must be built with
    # StringComparer.OrdinalIgnoreCase; a second claim is reported against that first index and is
    # never recorded, so every later copy names the same earlier entry. The earlier entry is named as
    # <Section>[<index>] unless -EarlierCollection says where the indexes count: the assignment policies
    # of one access package are numbered inside that package, so their findings name
    # accessPackages[i].assignmentPolicies[k].
    function Add-DuplicateEntryFinding {
        param(
            [System.Collections.Generic.Dictionary[string, int]]$Seen,
            [string]$Key, [int]$Index, [string]$Section, [string]$Item, [string]$Path,
            [string]$What, [string]$Consequence, [string]$EarlierCollection = $Section
        )
        if ($Seen.ContainsKey($Key)) {
            Add-Finding -Section $Section -Item $Item -Path $Path `
                -Message ("$Path declares the same $What as $($EarlierCollection)[$($Seen[$Key])] (compared without regard to letter case). " +
                    "$Consequence Keep one entry.")
            return
        }
        $Seen[$Key] = $Index
    }

    # The name a groups[] entry claims: its displayName, or for a template-based entry the name the
    # naming engine computes from template and tokens, with the token conversion Sync-OERStructureGroup
    # applies. Returns $null when the entry declares neither, or when the name cannot be computed --
    # an unknown token, or any other refusal, makes Resolve-OERName throw -- since the apply engine
    # reports such an entry Failed on its own. The one owner of that computation here: the duplicate
    # check (BL-02) and the administrativeUnit placement rule (Rule 12) both call it.
    function Get-GroupEntryName {
        param([object]$Group)
        if (Test-HasProp -Node $Group -Name 'displayName') { return [string]$Group.displayName }
        if (-not (Test-HasProp -Node $Group -Name 'template') -or [string]::IsNullOrEmpty([string]$Group.template)) { return $null }
        $TokenHash = @{}
        if ((Test-HasProp -Node $Group -Name 'tokens') -and $Group.tokens -is [PSCustomObject]) {
            foreach ($TokenProp in $Group.tokens.PSObject.Properties) {
                $TokenHash[$TokenProp.Name] = $TokenProp.Value
            }
        }
        try {
            return Resolve-OERName -Template ([string]$Group.template) -Tokens $TokenHash
        } catch {
            return $null
        }
    }

    $KnownTop = @('version', 'tenantId', 'tenantAlias', 'groups', 'administrativeUnits', 'catalogs',
        'accessPackages', 'accessReviews', 'directoryRoleManagementPolicies', 'directoryRoleAssignments',
        'roleAssignments', 'roleManagementPolicies')

    # Rule 1: version must be present and a non-empty string
    if (-not (Test-HasProp -Node $Document -Name 'version') -or
        [string]::IsNullOrEmpty($Document.version)) {
        Add-Finding -Section '(root)' -Item 'version' -Path 'version' `
            -Message 'Required key "version" is missing or empty.'
    }

    # Rule 1b (BL-88, A14): tenantId, when the key is present at all, is the tenant ID the document was
    # exported from, and Invoke-OERStructure refuses to apply the document in any other tenant. It must
    # therefore be a canonical GUID: an explicit null, an empty string, a domain or any other value names
    # no tenant the engine could compare with, and is refused here rather than read as "no tenantId" --
    # a document that is meant to carry no tenant check omits the key. Test-OERGuid is the predicate.
    # A value that is not a string -- a JSON array holding one GUID, a number, an object -- is refused
    # too, as the schema's "type": "string" refuses it; cast to a string, a one-element array read as
    # its element and passed (BL-101).
    if ($Document.PSObject.Properties.Name -contains 'tenantId' -and
        ($Document.tenantId -isnot [string] -or -not (Test-OERGuid -Value $Document.tenantId))) {
        $TenantIdFound = if ($Document.tenantId -is [string]) {
            "found '$($Document.tenantId)'"
        } elseif ($null -eq $Document.tenantId) {
            'found null'
        } else {
            "found a value that is not a string ($($Document.tenantId.GetType().Name))"
        }
        Add-Finding -Section '(root)' -Item 'tenantId' -Path 'tenantId' `
            -Message ("'tenantId' must be the tenant ID the document was exported from, a string in the " +
                "canonical GUID form (8-4-4-4-12 hexadecimal digits); $TenantIdFound. Omit the key to " +
                'apply the document without a tenant check.')
    }

    # Rule 2: unknown top-level keys
    foreach ($Key in $Document.PSObject.Properties.Name) {
        if ($KnownTop -inotcontains $Key) {
            Add-Finding -Section '(root)' -Item $Key -Path $Key `
                -Message "Unknown top-level key '$Key'."
        }
    }

    # Helper: verify a section exists and is an array; returns $true if callers should proceed
    function Test-SectionIsArray {
        param([string]$SectionName)
        $Val = $Document.$SectionName
        if ($Val -is [System.Collections.IEnumerable] -and $Val -isnot [string]) {
            return $true
        }
        Add-Finding -Section $SectionName -Item $SectionName -Path $SectionName `
            -Message "Section '$SectionName' must be an array."
        return $false
    }

    # Rule 3 + Rule 4: groups
    if (Test-HasProp -Node $Document -Name 'groups') {
        if (Test-SectionIsArray -SectionName 'groups') {
            $Groups = @($Document.groups)

            # Shared across the whole groups[] rule: the pimPolicy vocabulary (flat and nested member/
            # owner blocks alike), and the five field names the inventory README used to document before
            # they were renamed. A document still carrying one of those old names gets a did-you-mean
            # hint pointing at its replacement instead of a bare "unknown key".
            $PimBlockKeys = @('activationMaxHours', 'authenticationContextId', 'activationEnablement',
                'allowPermanentEligibility', 'eligibleDurationDays', 'allowPermanentActive', 'activeDurationDays',
                'activeEnablement', 'notifications', 'requireApproval', 'approvers')
            $LegacyPimKeyHint = @{
                activationEnabledRules    = 'activationEnablement'
                activeEnabledRules        = 'activeEnablement'
                eligibleAlertRecipients   = 'notifications.eligibleAlert'
                activeAlertRecipients     = 'notifications.activeAlert'
                activationAlertRecipients = 'notifications.activationAlert'
            }

            # One dictionary for both kinds of name an entry claims (its own name and its
            # previousDisplayName): either one finds the same live group as another entry's.
            $GroupNameSeen = [System.Collections.Generic.Dictionary[string, int]]::new([System.StringComparer]::OrdinalIgnoreCase)
            $GroupConsequence = 'Both entries reconcile one group, so each would undo the other''s settings and, under -Prune, remove the members the other declares.'

            for ($I = 0; $I -lt $Groups.Count; $I++) {
                $G = $Groups[$I]
                $GPath = "groups[$I]"
                $HasDN = Test-HasProp -Node $G -Name 'displayName'
                $HasTpl = Test-HasProp -Node $G -Name 'template'
                $GItem = if ($HasDN) { $G.displayName } else { "groups[$I]" }

                Add-UnknownKeyWarning -Node $G -Section 'groups' -Item $GItem -Path $GPath `
                    -KnownKey @('displayName', 'previousDisplayName', 'template', 'tokens', 'roleAssignable',
                        'dynamic', 'description', 'onPremisesSynced', 'membershipRule', 'membershipRuleProcessingState',
                        'mailNickname', 'administrativeUnit', 'members', 'owners', 'eligibility', 'pimPolicy', 'id')

                if ($HasDN -and $HasTpl) {
                    Add-Finding -Section 'groups' -Item $GItem -Path $GPath `
                        -Message "Group at $GPath must have either 'displayName' or 'template', not both."
                } elseif (-not $HasDN -and -not $HasTpl) {
                    Add-Finding -Section 'groups' -Item $GItem -Path $GPath `
                        -Message "Group at $GPath must have either 'displayName' or 'template'."
                } elseif ($HasTpl) {
                    if (-not (Test-HasProp -Node $G -Name 'tokens') -or
                        $G.tokens -isnot [PSCustomObject]) {
                        Add-Finding -Section 'groups' -Item $GItem -Path "$GPath.tokens" `
                            -Message "Group at $GPath with 'template' must also have a 'tokens' object."
                    }
                }

                # previousDisplayName renames the group found under it to displayName. An empty or
                # non-string value names no group at all; one equal to displayName (Graph matches
                # display names case-insensitively) resolves to the same group, so nothing is renamed
                # -- which also means a case-only rename cannot be expressed through the document.
                # This Warning does not compare a template-based group's computed name (the duplicate
                # check below does).
                if (Test-HasProp -Node $G -Name 'previousDisplayName') {
                    $PrevDN = $G.previousDisplayName
                    if ($PrevDN -isnot [string] -or $PrevDN.Length -eq 0) {
                        Add-Finding -Section 'groups' -Item $GItem -Path "$GPath.previousDisplayName" `
                            -Message "'previousDisplayName' at $GPath must be a non-empty string."
                    } elseif ($HasDN -and ([string]$G.displayName -eq $PrevDN)) {
                        Add-Finding -Section 'groups' -Item $GItem -Path "$GPath.previousDisplayName" -Severity 'Warning' `
                            -Message "'previousDisplayName' at $GPath equals displayName ignoring case; a case-only rename is not possible through the document -- use Set-OERGroup -NewDisplayName."
                    }
                }

                # BL-02: the names this entry claims are its own name and its previousDisplayName. A
                # template-based entry's name is computed with the naming engine (Get-GroupEntryName);
                # an entry whose name cannot be computed claims no name here -- the apply engine
                # reports that entry Failed on its own. Each claim is checked against the
                # EARLIER entries' claims only: the previousDisplayName is not claimed at all when it
                # equals this entry's own name, so an entry whose displayName equals its own
                # previousDisplayName (already a Warning above) is not a duplicate of itself.
                $GroupNameKey = Get-GroupEntryName -Group $G
                if ($null -ne $GroupNameKey) {
                    Add-DuplicateEntryFinding -Seen $GroupNameSeen -Key $GroupNameKey -Index $I -Section 'groups' `
                        -Item $GItem -Path $GPath -What "group name '$GroupNameKey'" -Consequence $GroupConsequence
                }
                if ((Test-HasProp -Node $G -Name 'previousDisplayName') -and
                    $G.previousDisplayName -is [string] -and $G.previousDisplayName.Length -gt 0 -and
                    ($null -eq $GroupNameKey -or $G.previousDisplayName -ine $GroupNameKey)) {
                    Add-DuplicateEntryFinding -Seen $GroupNameSeen -Key $G.previousDisplayName -Index $I -Section 'groups' `
                        -Item $GItem -Path "$GPath.previousDisplayName" -What "group name '$($G.previousDisplayName)'" `
                        -Consequence $GroupConsequence
                }

                foreach ($GStringProp in @('mailNickname', 'administrativeUnit')) {
                    if (Test-HasProp -Node $G -Name $GStringProp) {
                        if ($G.$GStringProp -isnot [string]) {
                            Add-Finding -Section 'groups' -Item $GItem -Path "$GPath.$GStringProp" `
                                -Message "'$GStringProp' at $GPath must be a string."
                        }
                    }
                }

                # BL-132: Microsoft Graph was measured (2026-10-13, PATCH on a security group) to refuse
                # @ ( ) \ [ ] " ; : < > , a space, a tab, the empty string and 65 characters; Microsoft
                # Learn's group resource lists the same printable set. The validator also refuses any other
                # white space and any other control character, which was not measured (no alias needs them).
                # A non-ASCII letter was accepted by Graph, so it is not refused here. A non-string value
                # was reported above.
                if ((Test-HasProp -Node $G -Name 'mailNickname') -and $G.mailNickname -is [string]) {
                    $Nick = [string]$G.mailNickname
                    if ($Nick.Length -eq 0) {
                        Add-Finding -Section 'groups' -Item $GItem -Path "$GPath.mailNickname" `
                            -Message "'mailNickname' at $GPath must not be empty."
                    } elseif ($Nick.Length -gt 64) {
                        Add-Finding -Section 'groups' -Item $GItem -Path "$GPath.mailNickname" `
                            -Message "'mailNickname' at $GPath is $($Nick.Length) characters long; Microsoft Graph accepts at most 64."
                    }
                    $Bad = @($Nick.ToCharArray() | Where-Object {
                            '@()\[]";:<>,'.Contains($_) -or [char]::IsWhiteSpace($_) -or [char]::IsControl($_)
                        } | Select-Object -Unique)
                    if ($Bad.Count -gt 0) {
                        $Shown = ($Bad | ForEach-Object {
                                if ([char]::IsWhiteSpace($_) -or [char]::IsControl($_)) { 'U+{0:X4}' -f [int]$_ } else { "'$_'" }
                            }) -join ', '
                        Add-Finding -Section 'groups' -Item $GItem -Path "$GPath.mailNickname" `
                            -Message ("'mailNickname' at $GPath contains $Shown, which the validator refuses in a mail alias " +
                                '(Microsoft Graph was measured to refuse @ ( ) \ [ ] " ; : < > , a space and a tab; ' +
                                'other white space and control characters are refused too).')
                    }
                }

                # BL-132 (A5): a mail alias does not follow a rename, and none is derived again. Warn when a
                # renamed group keeps the alias derived from its previous name, or declares none and so keeps
                # whatever alias it has. Not reported when previousDisplayName is not declared, is not a
                # non-empty string (reported above), or equals displayName ignoring case (nothing is renamed).
                if ((Test-HasProp -Node $G -Name 'previousDisplayName') -and $G.previousDisplayName -is [string] -and
                    $G.previousDisplayName.Length -gt 0 -and
                    -not ($HasDN -and [string]$G.displayName -ieq $G.previousDisplayName)) {
                    $OldAlias = Get-OERDerivedMailNickname -DisplayName $G.previousDisplayName
                    if (-not (Test-HasProp -Node $G -Name 'mailNickname')) {
                        Add-Finding -Section 'groups' -Item $GItem -Path "$GPath.mailNickname" -Severity 'Warning' `
                            -Message ("Group at $GPath is renamed from '$($G.previousDisplayName)' and declares no mailNickname, so it keeps " +
                                'its current mail alias: the alias does not follow a rename. If that alias was derived from the old ' +
                                'name, declare mailNickname with the alias the new name should carry.')
                    } elseif ($G.mailNickname -is [string] -and $G.mailNickname -ieq $OldAlias) {
                        Add-Finding -Section 'groups' -Item $GItem -Path "$GPath.mailNickname" -Severity 'Warning' `
                            -Message ("Group at $GPath is renamed from '$($G.previousDisplayName)' but its mailNickname '$($G.mailNickname)' " +
                                'is the alias derived from the old name: the alias does not follow a rename. Declare the alias the new ' +
                                'name should carry, or keep this one on purpose.')
                    }
                }

                # A15: onPremisesSynced is information the export writes for a group synchronized
                # from on-premises. The apply engine never sends it and decides nothing on it; only
                # its type is checked, as schema.json does.
                if (Test-HasProp -Node $G -Name 'onPremisesSynced') {
                    if ($G.onPremisesSynced -isnot [bool]) {
                        Add-Finding -Section 'groups' -Item $GItem -Path "$GPath.onPremisesSynced" `
                            -Message "'onPremisesSynced' at $GPath must be a boolean."
                    }
                }

                if (Test-HasProp -Node $G -Name 'membershipRuleProcessingState') {
                    $ValidGroupProcessingStates = @(Resolve-OERStructureEnumCasing -EnumName 'membershipRuleProcessingState' -List)
                    if ($ValidGroupProcessingStates -inotcontains [string]$G.membershipRuleProcessingState) {
                        Add-Finding -Section 'groups' -Item $GItem `
                            -Path "$GPath.membershipRuleProcessingState" `
                            -Message "'membershipRuleProcessingState' at $GPath must be one of: $($ValidGroupProcessingStates -join ', '). Got: '$($G.membershipRuleProcessingState)'."
                    } else {
                        Add-EnumCasingWarning -EnumName 'membershipRuleProcessingState' -Key 'membershipRuleProcessingState' `
                            -Value $G.membershipRuleProcessingState -Section 'groups' -Item $GItem `
                            -Path "$GPath.membershipRuleProcessingState"
                    }
                }

                # members must be array if present
                if (Test-HasProp -Node $G -Name 'members') {
                    $Mem = $G.members
                    if ($Mem -isnot [System.Collections.IEnumerable] -or $Mem -is [string]) {
                        Add-Finding -Section 'groups' -Item $GItem -Path "$GPath.members" `
                            -Message "groups[$I].members must be an array."
                    }
                }

                # owners must be array if present
                if (Test-HasProp -Node $G -Name 'owners') {
                    $Own = $G.owners
                    if ($Own -isnot [System.Collections.IEnumerable] -or $Own -is [string]) {
                        Add-Finding -Section 'groups' -Item $GItem -Path "$GPath.owners" `
                            -Message "groups[$I].owners must be an array."
                    }
                }

                # eligibility must be array if present; then validate each entry
                if (Test-HasProp -Node $G -Name 'eligibility') {
                    $Elig = $G.eligibility
                    if ($Elig -isnot [System.Collections.IEnumerable] -or $Elig -is [string]) {
                        Add-Finding -Section 'groups' -Item $GItem -Path "$GPath.eligibility" `
                            -Message "groups[$I].eligibility must be an array."
                    } else {
                        $EligArr = @($Elig)
                        for ($J = 0; $J -lt $EligArr.Count; $J++) {
                            $E = $EligArr[$J]
                            $EPath = "$GPath.eligibility[$J]"
                            if (-not (Test-HasProp -Node $E -Name 'principal')) {
                                Add-Finding -Section 'groups' -Item $GItem `
                                    -Path "$EPath.principal" `
                                    -Message "'principal' is required at $EPath."
                            }
                            if (Test-HasProp -Node $E -Name 'durationDays') {
                                if (-not (Test-IsInt -Value $E.durationDays -Min 1 -Max 3650)) {
                                    Add-Finding -Section 'groups' -Item $GItem `
                                        -Path "$EPath.durationDays" `
                                        -Message "'durationDays' at $EPath must be an integer between 1 and 3650."
                                }
                            }
                            if (Test-HasProp -Node $E -Name 'accessType') {
                                $ValidAccessTypes = @(Resolve-OERStructureEnumCasing -EnumName 'accessType' -List)
                                if ($ValidAccessTypes -inotcontains [string]$E.accessType) {
                                    Add-Finding -Section 'groups' -Item $GItem `
                                        -Path "$EPath.accessType" `
                                        -Message "'accessType' at $EPath must be one of: $($ValidAccessTypes -join ', '). Got: '$($E.accessType)'."
                                } else {
                                    Add-EnumCasingWarning -EnumName 'accessType' -Key 'accessType' -Value $E.accessType `
                                        -Section 'groups' -Item $GItem -Path "$EPath.accessType"
                                }
                            }
                        }
                    }
                }

                # pimPolicy validation (flat back-compat, or nested member/owner)
                if (Test-HasProp -Node $G -Name 'pimPolicy') {
                    $Pp = $G.pimPolicy
                    $EnabValues = @(Resolve-OERStructureEnumCasing -EnumName 'enablement' -List)

                    $ValidatePimBlock = {
                        param($Block, $BlockPath)
                        if (Test-HasProp -Node $Block -Name 'activationMaxHours') {
                            if (-not (Test-IsInt -Value $Block.activationMaxHours -Min 1 -Max 24)) {
                                Add-Finding -Section 'groups' -Item $GItem -Path "$BlockPath.activationMaxHours" `
                                    -Message "'activationMaxHours' at $BlockPath must be an integer between 1 and 24."
                            }
                        }
                        foreach ($DurKey in @('eligibleDurationDays', 'activeDurationDays')) {
                            if (Test-HasProp -Node $Block -Name $DurKey) {
                                if (-not (Test-IsInt -Value $Block.$DurKey -Min 1 -Max 3650)) {
                                    Add-Finding -Section 'groups' -Item $GItem -Path "$BlockPath.$DurKey" `
                                        -Message "'$DurKey' at $BlockPath must be an integer between 1 and 3650."
                                }
                            }
                        }
                        foreach ($EnabKey in @('activationEnablement', 'activeEnablement')) {
                            if (Test-HasProp -Node $Block -Name $EnabKey) {
                                $Arr = $Block.$EnabKey
                                if ($Arr -isnot [System.Collections.IEnumerable] -or $Arr -is [string]) {
                                    Add-Finding -Section 'groups' -Item $GItem -Path "$BlockPath.$EnabKey" `
                                        -Message "'$EnabKey' at $BlockPath must be an array."
                                } else {
                                    foreach ($V in @($Arr)) {
                                        if ($EnabValues -inotcontains [string]$V) {
                                            Add-Finding -Section 'groups' -Item $GItem -Path "$BlockPath.$EnabKey" `
                                                -Message "'$EnabKey' at $BlockPath must contain only: $($EnabValues -join ', '). Got: '$V'."
                                        } else {
                                            Add-EnumCasingWarning -EnumName 'enablement' -Key $EnabKey -Value $V `
                                                -Section 'groups' -Item $GItem -Path "$BlockPath.$EnabKey"
                                        }
                                    }
                                }
                            }
                        }
                        if (Test-HasProp -Node $Block -Name 'notifications') {
                            $Nf = $Block.notifications
                            foreach ($AlertKey in @('eligibleAlert', 'activeAlert', 'activationAlert')) {
                                if (Test-HasProp -Node $Nf -Name $AlertKey) {
                                    $AArr = $Nf.$AlertKey
                                    if ($AArr -isnot [System.Collections.IEnumerable] -or $AArr -is [string]) {
                                        Add-Finding -Section 'groups' -Item $GItem -Path "$BlockPath.notifications.$AlertKey" `
                                            -Message "'notifications.$AlertKey' at $BlockPath must be an array of strings."
                                    }
                                }
                            }
                        }

                        if (Test-HasProp -Node $Block -Name 'requireApproval') {
                            if ($Block.requireApproval -isnot [bool]) {
                                Add-Finding -Section 'groups' -Item $GItem -Path "$BlockPath.requireApproval" `
                                    -Message "'requireApproval' at $BlockPath must be a boolean."
                            }
                        }

                        # Approvers only take effect when approval is required -- mirrors the
                        # roleManagementPolicies precedence rule: the apply engine (Resolve-OERDeclaredApprover)
                        # does not resolve declared approvers when requireApproval is explicitly false, and
                        # writing them anyway would risk re-enabling approval. Warn (never Error), the same
                        # way the roleManagementPolicies section does, so a document that validates today
                        # keeps validating and Get-OERInventory itself can still produce this shape.
                        if ((Test-HasProp -Node $Block -Name 'requireApproval') -and ($Block.requireApproval -eq $false)) {
                            $PimDeclaredApproverCount = 0
                            foreach ($PimApproverKind in @('users', 'groups')) {
                                if (Test-HasProp -Node $Block.approvers -Name $PimApproverKind) {
                                    $PimDeclaredApproverCount += @($Block.approvers.$PimApproverKind).Count
                                }
                            }
                            if ($PimDeclaredApproverCount -gt 0) {
                                Add-Finding -Section 'groups' -Item $GItem -Path "$BlockPath.approvers" -Severity 'Warning' `
                                    -Message "'requireApproval' is false at $BlockPath, so the declared 'approvers' are ignored; requireApproval takes precedence and the approvers are not written. Set 'requireApproval' to true to apply them, or drop the approvers block."
                            }
                        }

                        if (Test-HasProp -Node $Block -Name 'approvers') {
                            $PimApprovers = $Block.approvers
                            if ($PimApprovers -isnot [PSCustomObject]) {
                                Add-Finding -Section 'groups' -Item $GItem -Path "$BlockPath.approvers" `
                                    -Message "'approvers' at $BlockPath must be an object with optional users and groups arrays."
                            } else {
                                foreach ($PimApproverKind in @('users', 'groups')) {
                                    if (Test-HasProp -Node $PimApprovers -Name $PimApproverKind) {
                                        $PimApproverVal = $PimApprovers.$PimApproverKind
                                        if ($PimApproverVal -isnot [System.Collections.IEnumerable] -or $PimApproverVal -is [string]) {
                                            Add-Finding -Section 'groups' -Item $GItem -Path "$BlockPath.approvers.$PimApproverKind" `
                                                -Message "'approvers.$PimApproverKind' at $BlockPath must be an array."
                                        }
                                    }
                                }
                            }
                        }

                        # PIM treats an enabled authentication context and MultiFactorAuthentication on
                        # activation as mutually exclusive. Unlike the roleManagementPolicies section --
                        # which raises an Error for the same collision -- this is only a Warning: group
                        # documents declaring both already validate today, and the apply engine now
                        # reconciles them (Resolve-OERGroupPimPolicyChange), so failing here would break
                        # documents that work.
                        # Why: docs/development/rationale.md#mfa-authcontext-exclusion
                        if ((Test-HasProp -Node $Block -Name 'authenticationContextId') -and
                            -not [string]::IsNullOrEmpty([string]$Block.authenticationContextId) -and
                            (Test-HasProp -Node $Block -Name 'activationEnablement') -and
                            (@($Block.activationEnablement) -contains 'MultiFactorAuthentication')) {
                            Add-Finding -Section 'groups' -Item $GItem -Path $BlockPath -Severity 'Warning' `
                                -Message "'activationEnablement' contains 'MultiFactorAuthentication' while 'authenticationContextId' is set at $BlockPath; PIM treats them as mutually exclusive, so the MFA requirement will be cleared when this is applied."
                        }
                    }

                    $HasMember = Test-HasProp -Node $Pp -Name 'member'
                    $HasOwner  = Test-HasProp -Node $Pp -Name 'owner'
                    $HasFlat   = $false
                    foreach ($PimBlockKey in $PimBlockKeys) {
                        if (Test-HasProp -Node $Pp -Name $PimBlockKey) { $HasFlat = $true; break }
                    }

                    Add-UnknownKeyWarning -Node $Pp -Section 'groups' -Item $GItem -Path "$GPath.pimPolicy" `
                        -KnownKey ($PimBlockKeys + @('member', 'owner', 'id')) -Hint $LegacyPimKeyHint

                    if (($HasMember -or $HasOwner) -and $HasFlat) {
                        Add-Finding -Section 'groups' -Item $GItem -Path "$GPath.pimPolicy" `
                            -Message "pimPolicy at $GPath mixes flat and nested (member/owner) forms; the flat fields are ignored." `
                            -Severity 'Warning'
                    }

                    if ($HasMember) {
                        Add-UnknownKeyWarning -Node $Pp.member -Section 'groups' -Item $GItem -Path "$GPath.pimPolicy.member" `
                            -KnownKey ($PimBlockKeys + @('id')) -Hint $LegacyPimKeyHint
                        & $ValidatePimBlock $Pp.member "$GPath.pimPolicy.member"
                    }
                    if ($HasOwner) {
                        Add-UnknownKeyWarning -Node $Pp.owner -Section 'groups' -Item $GItem -Path "$GPath.pimPolicy.owner" `
                            -KnownKey ($PimBlockKeys + @('id')) -Hint $LegacyPimKeyHint
                        & $ValidatePimBlock $Pp.owner "$GPath.pimPolicy.owner"
                    }
                    if (-not $HasMember -and -not $HasOwner) { & $ValidatePimBlock $Pp "$GPath.pimPolicy" }
                }
            }
        }
    }

    # Rule 5: administrativeUnits
    if (Test-HasProp -Node $Document -Name 'administrativeUnits') {
        if (Test-SectionIsArray -SectionName 'administrativeUnits') {
            $AUs = @($Document.administrativeUnits)
            $AUSeen = [System.Collections.Generic.Dictionary[string, int]]::new([System.StringComparer]::OrdinalIgnoreCase)
            for ($I = 0; $I -lt $AUs.Count; $I++) {
                $AU = $AUs[$I]
                $AUPath = "administrativeUnits[$I]"
                $AUItem = if (Test-HasProp -Node $AU -Name 'displayName') { $AU.displayName } else { "administrativeUnits[$I]" }

                $AUConsequence = 'Both entries reconcile one administrative unit, so each would undo the other''s settings and, ' +
                    'under -Prune, remove the members and scoped roles the other declares.'
                if (-not (Test-HasProp -Node $AU -Name 'displayName')) {
                    Add-Finding -Section 'administrativeUnits' -Item $AUItem -Path $AUPath `
                        -Message "'displayName' is required at $AUPath."
                } else {
                    Add-DuplicateEntryFinding -Seen $AUSeen -Key ([string]$AU.displayName) -Index $I `
                        -Section 'administrativeUnits' -Item $AUItem -Path $AUPath `
                        -What "display name '$($AU.displayName)'" `
                        -Consequence $AUConsequence
                }
                # A unit renamed through the document is found under its previousDisplayName too, so that
                # name is a claim of its own, checked after the displayName claim just as the groups' is.
                $AUPrev = Test-SupportedRename -Node $AU -Section 'administrativeUnits' -Item $AUItem -Path $AUPath `
                    -SetCommand 'Set-OERAdministrativeUnit'
                if ($AUPrev) {
                    Add-DuplicateEntryFinding -Seen $AUSeen -Key $AUPrev -Index $I `
                        -Section 'administrativeUnits' -Item $AUItem -Path "$AUPath.previousDisplayName" `
                        -What "display name '$AUPrev'" `
                        -Consequence $AUConsequence
                }

                foreach ($AUBoolProp in @('dynamic', 'restricted', 'hiddenMembership')) {
                    if (Test-HasProp -Node $AU -Name $AUBoolProp) {
                        if ($AU.$AUBoolProp -isnot [bool]) {
                            Add-Finding -Section 'administrativeUnits' -Item $AUItem -Path "$AUPath.$AUBoolProp" `
                                -Message "'$AUBoolProp' at $AUPath must be a boolean."
                        }
                    }
                }

                if (Test-HasProp -Node $AU -Name 'membershipRuleProcessingState') {
                    $ValidProcessingStates = @(Resolve-OERStructureEnumCasing -EnumName 'membershipRuleProcessingState' -List)
                    if ($ValidProcessingStates -inotcontains [string]$AU.membershipRuleProcessingState) {
                        Add-Finding -Section 'administrativeUnits' -Item $AUItem `
                            -Path "$AUPath.membershipRuleProcessingState" `
                            -Message "'membershipRuleProcessingState' at $AUPath must be one of: $($ValidProcessingStates -join ', '). Got: '$($AU.membershipRuleProcessingState)'."
                    } else {
                        Add-EnumCasingWarning -EnumName 'membershipRuleProcessingState' -Key 'membershipRuleProcessingState' `
                            -Value $AU.membershipRuleProcessingState -Section 'administrativeUnits' -Item $AUItem `
                            -Path "$AUPath.membershipRuleProcessingState"
                    }
                }

                # A dynamic unit must have a rule, and the apply cannot invent one: creating the unit is
                # rejected by New-OERAdministrativeUnit (MembershipRuleRequired) and converting an
                # existing assigned unit is reported as Failed. It stays a Warning rather than an Error
                # for the one case that DOES apply cleanly -- a unit that is already dynamic, whose rule
                # is deliberately managed outside the document -- because an Error aborts the whole
                # document before any section is written, and the validator cannot tell the cases apart
                # offline.
                if ((Test-HasProp -Node $AU -Name 'dynamic') -and ($AU.dynamic -eq $true) -and
                    -not (Test-HasProp -Node $AU -Name 'membershipRule')) {
                    Add-Finding -Section 'administrativeUnits' -Item $AUItem `
                        -Path "$AUPath.membershipRule" `
                        -Message "Administrative unit at $AUPath declares 'dynamic' but no 'membershipRule'. Creating the unit fails, and converting an existing assigned unit to dynamic is reported as Failed; this only applies cleanly when the unit is already dynamic and its rule is managed outside the document." `
                        -Severity 'Warning'
                }

                if (Test-HasProp -Node $AU -Name 'scopedRoles') {
                    $RolesVal = $AU.scopedRoles
                    if ($RolesVal -isnot [System.Collections.IEnumerable] -or $RolesVal -is [string]) {
                        Add-Finding -Section 'administrativeUnits' -Item $AUItem -Path "$AUPath.scopedRoles" `
                            -Message "'scopedRoles' at $AUPath must be an array."
                    } else {
                        $Roles = @($RolesVal)
                        for ($J = 0; $J -lt $Roles.Count; $J++) {
                            $SR = $Roles[$J]
                            $SRPath = "$AUPath.scopedRoles[$J]"
                            if (-not (Test-HasProp -Node $SR -Name 'role')) {
                                Add-Finding -Section 'administrativeUnits' -Item $AUItem `
                                    -Path "$SRPath.role" `
                                    -Message "'role' is required at $SRPath."
                            } elseif ([string]::IsNullOrWhiteSpace([string]$SR.role)) {
                                Add-Finding -Section 'administrativeUnits' -Item $AUItem `
                                    -Path "$SRPath.role" `
                                    -Message "'role' at $SRPath must be a non-empty string."
                            }
                            if (-not (Test-HasProp -Node $SR -Name 'principal')) {
                                Add-Finding -Section 'administrativeUnits' -Item $AUItem `
                                    -Path "$SRPath.principal" `
                                    -Message "'principal' is required at $SRPath."
                            } elseif ([string]::IsNullOrWhiteSpace([string]$SR.principal)) {
                                Add-Finding -Section 'administrativeUnits' -Item $AUItem `
                                    -Path "$SRPath.principal" `
                                    -Message "'principal' at $SRPath must be a non-empty string."
                            }
                            # Sprint 11 step 8 (R-7): principalType, which Get-OERInventory writes for a principal
                            # the directory returned, is held to the enum roleAssignments uses, as there: a value
                            # outside it is an Error, and one in another letter case is the casing Warning, since
                            # schema.json declares the enum case-sensitively. An entry without it is valid as
                            # before, and the apply engine never reads it.
                            if (Test-HasProp -Node $SR -Name 'principalType') {
                                $ValidSrPrincipalTypes = @(Resolve-OERStructureEnumCasing -EnumName 'principalType' -List)
                                if ($ValidSrPrincipalTypes -inotcontains $SR.principalType) {
                                    Add-Finding -Section 'administrativeUnits' -Item $AUItem `
                                        -Path "$SRPath.principalType" `
                                        -Message "'principalType' at $SRPath must be one of: $($ValidSrPrincipalTypes -join ', '). Got: '$($SR.principalType)'."
                                } else {
                                    Add-EnumCasingWarning -EnumName 'principalType' -Key 'principalType' -Value $SR.principalType `
                                        -Section 'administrativeUnits' -Item $AUItem -Path "$SRPath.principalType"
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    # Rule 6: catalogs
    if (Test-HasProp -Node $Document -Name 'catalogs') {
        if (Test-SectionIsArray -SectionName 'catalogs') {
            $ValidResourceTypes = @(Resolve-OERStructureEnumCasing -EnumName 'catalogResourceType' -List)
            $Cats = @($Document.catalogs)
            $CatSeen = [System.Collections.Generic.Dictionary[string, int]]::new([System.StringComparer]::OrdinalIgnoreCase)
            for ($I = 0; $I -lt $Cats.Count; $I++) {
                $Cat = $Cats[$I]
                $CatPath = "catalogs[$I]"
                $CatItem = if (Test-HasProp -Node $Cat -Name 'displayName') { $Cat.displayName } else { "catalogs[$I]" }

                $CatConsequence = 'Both entries reconcile one catalog, so each would undo the other''s settings and, ' +
                    'under -Prune, remove the resources the other declares.'
                if (-not (Test-HasProp -Node $Cat -Name 'displayName')) {
                    Add-Finding -Section 'catalogs' -Item $CatItem -Path $CatPath `
                        -Message "'displayName' is required at $CatPath."
                } else {
                    Add-DuplicateEntryFinding -Seen $CatSeen -Key ([string]$Cat.displayName) -Index $I `
                        -Section 'catalogs' -Item $CatItem -Path $CatPath `
                        -What "display name '$($Cat.displayName)'" `
                        -Consequence $CatConsequence
                }
                # The previous name is a claim of its own, as for administrative units.
                $CatPrev = Test-SupportedRename -Node $Cat -Section 'catalogs' -Item $CatItem -Path $CatPath `
                    -SetCommand 'Set-OERCatalog'
                if ($CatPrev) {
                    Add-DuplicateEntryFinding -Seen $CatSeen -Key $CatPrev -Index $I `
                        -Section 'catalogs' -Item $CatItem -Path "$CatPath.previousDisplayName" `
                        -What "display name '$CatPrev'" `
                        -Consequence $CatConsequence
                }

                if (Test-HasProp -Node $Cat -Name 'externallyVisible') {
                    if ($Cat.externallyVisible -isnot [bool]) {
                        Add-Finding -Section 'catalogs' -Item $CatItem -Path "$CatPath.externallyVisible" `
                            -Message "'externallyVisible' at $CatPath must be a boolean."
                    }
                }

                if (Test-HasProp -Node $Cat -Name 'resources') {
                    $ResVal = $Cat.resources
                    if ($ResVal -isnot [System.Collections.IEnumerable] -or $ResVal -is [string]) {
                        Add-Finding -Section 'catalogs' -Item $CatItem -Path "$CatPath.resources" `
                            -Message "'resources' at $CatPath must be an array."
                    } else {
                        $Res = @($ResVal)
                        for ($J = 0; $J -lt $Res.Count; $J++) {
                            $R = $Res[$J]
                            $RPath = "$CatPath.resources[$J]"
                            if (-not (Test-HasProp -Node $R -Name 'name')) {
                                Add-Finding -Section 'catalogs' -Item $CatItem `
                                    -Path "$RPath.name" `
                                    -Message "'name' is required at $RPath."
                            } elseif ([string]::IsNullOrWhiteSpace([string]$R.name)) {
                                Add-Finding -Section 'catalogs' -Item $CatItem `
                                    -Path "$RPath.name" `
                                    -Message "'name' at $RPath must be a non-empty string."
                            }
                            if (Test-HasProp -Node $R -Name 'type') {
                                if ($ValidResourceTypes -inotcontains $R.type) {
                                    Add-Finding -Section 'catalogs' -Item $CatItem `
                                        -Path "$RPath.type" `
                                        -Message "'type' at $RPath must be one of: $($ValidResourceTypes -join ', '). Got: '$($R.type)'."
                                } else {
                                    Add-EnumCasingWarning -EnumName 'catalogResourceType' -Key 'type' -Value $R.type `
                                        -Section 'catalogs' -Item $CatItem -Path "$RPath.type"
                                }
                            }
                            if (Test-HasProp -Node $R -Name 'url') {
                                if ([string]::IsNullOrWhiteSpace([string]$R.url) -or $R.url -isnot [string]) {
                                    Add-Finding -Section 'catalogs' -Item $CatItem `
                                        -Path "$RPath.url" `
                                        -Message "'url' at $RPath must be a non-empty string."
                                }
                            }
                            # A SharePoint site is onboarded by URL. Without one -- and without a
                            # URL-shaped name -- the apply would feed a site title to
                            # Add-OERCatalogResource -SharePointSite and onboard the wrong originId.
                            if ((Test-HasProp -Node $R -Name 'type') -and
                                ([string]$R.type -eq 'SharePointSite') -and
                                -not (Test-HasProp -Node $R -Name 'url') -and
                                ([string]$R.name -notmatch '^(?i)https?://')) {
                                Add-Finding -Section 'catalogs' -Item $CatItem `
                                    -Path "$RPath.url" `
                                    -Message "SharePointSite resource at $RPath has no 'url' and its 'name' is not a site URL; the site cannot be onboarded from a display name." `
                                    -Severity 'Warning'
                            }
                        }
                    }
                }
            }
        }
    }

    # Rule 7: accessPackages
    if (Test-HasProp -Node $Document -Name 'accessPackages') {
        if (Test-SectionIsArray -SectionName 'accessPackages') {
            $APs = @($Document.accessPackages)
            $APSeen = [System.Collections.Generic.Dictionary[string, int]]::new([System.StringComparer]::OrdinalIgnoreCase)
            for ($I = 0; $I -lt $APs.Count; $I++) {
                $AP = $APs[$I]
                $APPath = "accessPackages[$I]"
                $APItem = if (Test-HasProp -Node $AP -Name 'displayName') { $AP.displayName } else { "accessPackages[$I]" }

                if (-not (Test-HasProp -Node $AP -Name 'displayName')) {
                    Add-Finding -Section 'accessPackages' -Item $APItem -Path $APPath `
                        -Message "'displayName' is required at $APPath."
                }
                if (-not (Test-HasProp -Node $AP -Name 'catalog')) {
                    Add-Finding -Section 'accessPackages' -Item $APItem -Path $APPath `
                        -Message "'catalog' is required at $APPath."
                }
                $APConsequence = 'Both entries reconcile one access package, so each would undo the other''s settings and, ' +
                    'under -Prune, remove the resource role bindings the other declares.'
                if ((Test-HasProp -Node $AP -Name 'displayName') -and (Test-HasProp -Node $AP -Name 'catalog')) {
                    # A package is identified by its catalog together with its display name: the same
                    # name in two catalogs is two packages.
                    Add-DuplicateEntryFinding -Seen $APSeen -Key "$($AP.catalog)|$($AP.displayName)" -Index $I `
                        -Section 'accessPackages' -Item $APItem -Path $APPath `
                        -What "catalog '$($AP.catalog)' and display name '$($AP.displayName)'" `
                        -Consequence $APConsequence
                }
                # The previous name is a claim of its own, within the package's catalog just as the
                # display name is: it is looked up in that catalog's list, so the same previous name in
                # another catalog is another package. A package that declares no catalog claims nothing
                # (the missing catalog is an Error already).
                $APPrev = Test-SupportedRename -Node $AP -Section 'accessPackages' -Item $APItem -Path $APPath `
                    -SetCommand 'Set-OERAccessPackage'
                if ($APPrev -and (Test-HasProp -Node $AP -Name 'catalog')) {
                    Add-DuplicateEntryFinding -Seen $APSeen -Key "$($AP.catalog)|$APPrev" -Index $I `
                        -Section 'accessPackages' -Item $APItem -Path "$APPath.previousDisplayName" `
                        -What "catalog '$($AP.catalog)' and display name '$APPrev'" `
                        -Consequence $APConsequence
                }

                if (Test-HasProp -Node $AP -Name 'hidden') {
                    if ($AP.hidden -isnot [bool]) {
                        Add-Finding -Section 'accessPackages' -Item $APItem -Path "$APPath.hidden" `
                            -Message "'hidden' at $APPath must be a boolean."
                    }
                }

                if (Test-HasProp -Node $AP -Name 'resourceRoles') {
                    $RRolesVal = $AP.resourceRoles
                    if ($RRolesVal -isnot [System.Collections.IEnumerable] -or $RRolesVal -is [string]) {
                        Add-Finding -Section 'accessPackages' -Item $APItem -Path "$APPath.resourceRoles" `
                            -Message "'resourceRoles' at $APPath must be an array."
                    } else {
                        $RRoles = @($RRolesVal)
                        for ($J = 0; $J -lt $RRoles.Count; $J++) {
                            $RR = $RRoles[$J]
                            $RRPath = "$APPath.resourceRoles[$J]"
                            if (-not (Test-HasProp -Node $RR -Name 'resource')) {
                                Add-Finding -Section 'accessPackages' -Item $APItem `
                                    -Path "$RRPath.resource" `
                                    -Message "'resource' is required at $RRPath."
                            } elseif ([string]::IsNullOrWhiteSpace([string]$RR.resource)) {
                                Add-Finding -Section 'accessPackages' -Item $APItem `
                                    -Path "$RRPath.resource" `
                                    -Message "'resource' at $RRPath must be a non-empty string."
                            }
                            if (-not (Test-HasProp -Node $RR -Name 'role')) {
                                Add-Finding -Section 'accessPackages' -Item $APItem `
                                    -Path "$RRPath.role" `
                                    -Message "'role' is required at $RRPath."
                            } elseif ([string]::IsNullOrWhiteSpace([string]$RR.role)) {
                                Add-Finding -Section 'accessPackages' -Item $APItem `
                                    -Path "$RRPath.role" `
                                    -Message "'role' at $RRPath must be a non-empty string."
                            }
                        }
                    }
                }

                if (Test-HasProp -Node $AP -Name 'assignmentPolicies') {
                    $PolsVal = $AP.assignmentPolicies
                    if ($PolsVal -isnot [System.Collections.IEnumerable] -or $PolsVal -is [string]) {
                        Add-Finding -Section 'accessPackages' -Item $APItem -Path "$APPath.assignmentPolicies" `
                            -Message "'assignmentPolicies' at $APPath must be an array."
                    } else {
                        $Pols = @($PolsVal)
                        # Sprint 11 step 4b: the policies of one package are matched by name within it, and a
                        # policy renamed through the document is found under its previousDisplayName too, so
                        # both names are claims of the package. Two claims of one name that collide are an
                        # Error through the same helper as the other sections (Ruling P4). Sprint 11 step 5
                        # (BL-131) dropped the exception of step 4b that left two equal displayNames
                        # unreported: the apply engine refuses an ambiguous policy name, and the export no
                        # longer writes two policies of one name. $PolSeen holds the first claim of a name,
                        # displayName or previousDisplayName alike, so a claim that meets a LATER-recorded
                        # one is caught at the later claim.
                        $PolSeen = [System.Collections.Generic.Dictionary[string, int]]::new([System.StringComparer]::OrdinalIgnoreCase)
                        $PolConsequence = 'Both entries reconcile one assignment policy of the access package, so each would undo the ' +
                            'other''s settings.'
                        for ($J = 0; $J -lt $Pols.Count; $J++) {
                            $Pol = $Pols[$J]
                            $PolPath = "$APPath.assignmentPolicies[$J]"
                            if (-not (Test-HasProp -Node $Pol -Name 'displayName')) {
                                Add-Finding -Section 'accessPackages' -Item $APItem `
                                    -Path "$PolPath.displayName" `
                                    -Message "'displayName' is required at $PolPath."
                            } else {
                                $PolName = [string]$Pol.displayName
                                Add-DuplicateEntryFinding -Seen $PolSeen -Key $PolName -Index $J `
                                    -Section 'accessPackages' -Item $APItem -Path $PolPath `
                                    -What "display name '$PolName'" `
                                    -Consequence $PolConsequence -EarlierCollection "$APPath.assignmentPolicies"
                            }
                            $PolPrev = Test-SupportedRename -Node $Pol -Section 'accessPackages' -Item $APItem -Path $PolPath `
                                -SetCommand 'Set-OERAccessPackageAssignmentPolicy' -NameParameter '-DisplayName' `
                                -NameQualifier ' together with another property' `
                                -CaseOnlyClause 'a case-only rename is applied only together with another changed field of the policy -- or use'
                            if ($PolPrev) {
                                Add-DuplicateEntryFinding -Seen $PolSeen -Key $PolPrev -Index $J `
                                    -Section 'accessPackages' -Item $APItem -Path "$PolPath.previousDisplayName" `
                                    -What "display name '$PolPrev'" `
                                    -Consequence $PolConsequence -EarlierCollection "$APPath.assignmentPolicies"
                            }

                            if (Test-HasProp -Node $Pol -Name 'requestorScope') {
                                $RScope = $Pol.requestorScope

                                # Issue #69: a requestorScope declaring users/groups but no scope no longer
                                # refuses the document outright -- Build-OERPolicyParts infers
                                # SpecificDirectoryUsers for exactly this shape (users/groups declared,
                                # scope not), so an Error here would refuse the document the fix exists to
                                # support. The declared/non-empty facts below are read with Test-HasProp,
                                # the single owner of the module's declared rule, so this validator
                                # classifies a document identically to the handler that applies it.
                                $ScopeIsDeclared = Test-HasProp -Node $RScope -Name 'scope'
                                $ScopeVal = if ($ScopeIsDeclared) { [string]$RScope.scope } else { $null }
                                $HasNonEmptyTarget = $false
                                foreach ($RSArrayProp in @('users', 'groups')) {
                                    if (Test-HasProp -Node $RScope -Name $RSArrayProp) {
                                        $RSVal = $RScope.$RSArrayProp
                                        if (($RSVal -is [System.Collections.IEnumerable]) -and ($RSVal -isnot [string]) -and (@($RSVal).Count -gt 0)) {
                                            $HasNonEmptyTarget = $true
                                        }
                                    }
                                }

                                if ($ScopeIsDeclared -and [string]::IsNullOrEmpty($ScopeVal)) {
                                    # Declared but empty: the scope value itself is invalid regardless of
                                    # users/groups -- New-OERAccessPackageRequestorScope's -Scope ValidateSet
                                    # rejects "" outright, so nothing is inferable here either. Unchanged
                                    # from before this task.
                                    Add-Finding -Section 'accessPackages' -Item $APItem `
                                        -Path "$PolPath.requestorScope.scope" `
                                        -Message "'requestorScope.scope' at $PolPath must be a non-empty string."
                                } elseif (-not $ScopeIsDeclared) {
                                    if ($HasNonEmptyTarget) {
                                        # Case 1 (relaxation): nothing here fails Invoke-OERStructure any
                                        # more, since the handler infers SpecificDirectoryUsers.
                                        Add-Finding -Section 'accessPackages' -Item $APItem `
                                            -Path "$PolPath.requestorScope.scope" -Severity 'Warning' `
                                            -Message ("'requestorScope' at $PolPath declares 'users' or 'groups' with no 'scope'; " +
                                                "Invoke-OERStructure infers 'scope' as 'SpecificDirectoryUsers'. Declare 'scope' " +
                                                'explicitly instead of relying on the inference.')
                                    } else {
                                        # Case 2 (unchanged Error): nothing is inferable, the block names no
                                        # target and no scope -- this document fails today and still does.
                                        Add-Finding -Section 'accessPackages' -Item $APItem `
                                            -Path "$PolPath.requestorScope.scope" `
                                            -Message "'requestorScope.scope' at $PolPath must be a non-empty string."
                                    }
                                } elseif (($ScopeVal -ne 'SpecificDirectoryUsers') -and $HasNonEmptyTarget) {
                                    # Case 3 (Ruling R-3, new diagnostics only): the explicit scope stands
                                    # and Build-OERPolicyParts never infers over it, so the declared
                                    # users/groups are simply unused.
                                    Add-Finding -Section 'accessPackages' -Item $APItem `
                                        -Path "$PolPath.requestorScope.scope" -Severity 'Warning' `
                                        -Message ("'requestorScope' at $PolPath declares 'users' or 'groups' with 'scope' set to " +
                                            "'$ScopeVal'; they are applied only when 'scope' is 'SpecificDirectoryUsers' and are " +
                                            'otherwise ignored.')
                                }
                                foreach ($RSArrayProp in @('users', 'groups')) {
                                    if (Test-HasProp -Node $RScope -Name $RSArrayProp) {
                                        $RSVal = $RScope.$RSArrayProp
                                        if ($RSVal -isnot [System.Collections.IEnumerable] -or $RSVal -is [string]) {
                                            Add-Finding -Section 'accessPackages' -Item $APItem `
                                                -Path "$PolPath.requestorScope.$RSArrayProp" `
                                                -Message "'requestorScope.$RSArrayProp' at $PolPath must be an array."
                                        }
                                    }
                                }
                            }

                            if (Test-HasProp -Node $Pol -Name 'requestorSettings') {
                                $RSettings = $Pol.requestorSettings
                                if ($RSettings -isnot [PSCustomObject]) {
                                    Add-Finding -Section 'accessPackages' -Item $APItem `
                                        -Path "$PolPath.requestorSettings" `
                                        -Message "'requestorSettings' at $PolPath must be an object."
                                } else {
                                    foreach ($RSBoolProp in @('allowSelfRequest', 'allowManagerRequest', 'allowCustomSchedule', 'allowSelfExtend', 'allowSelfRemove', 'allowOnBehalfUpdate', 'allowOnBehalfRemove')) {
                                        if (Test-HasProp -Node $RSettings -Name $RSBoolProp) {
                                            if ($RSettings.$RSBoolProp -isnot [bool]) {
                                                Add-Finding -Section 'accessPackages' -Item $APItem `
                                                    -Path "$PolPath.requestorSettings.$RSBoolProp" `
                                                    -Message "'requestorSettings.$RSBoolProp' at $PolPath must be a boolean."
                                            }
                                        }
                                    }
                                    if (Test-HasProp -Node $RSettings -Name 'managerLevel') {
                                        if (-not (Test-IsInt -Value $RSettings.managerLevel -Min 1 -Max ([int]::MaxValue))) {
                                            Add-Finding -Section 'accessPackages' -Item $APItem `
                                                -Path "$PolPath.requestorSettings.managerLevel" `
                                                -Message "'requestorSettings.managerLevel' at $PolPath must be an integer >= 1."
                                        }
                                    }
                                }
                            }

                            foreach ($PolBoolProp in @('requireApproval', 'requireRequestorJustification', 'requireApprovalForUpdate', 'notificationsDisabled')) {
                                if (Test-HasProp -Node $Pol -Name $PolBoolProp) {
                                    if ($Pol.$PolBoolProp -isnot [bool]) {
                                        Add-Finding -Section 'accessPackages' -Item $APItem `
                                            -Path "$PolPath.$PolBoolProp" `
                                            -Message "'$PolBoolProp' at $PolPath must be a boolean."
                                    }
                                }
                            }

                            if (Test-HasProp -Node $Pol -Name 'approvalStages') {
                                $StagesVal = $Pol.approvalStages
                                if ($StagesVal -isnot [System.Collections.IEnumerable] -or $StagesVal -is [string]) {
                                    Add-Finding -Section 'accessPackages' -Item $APItem `
                                        -Path "$PolPath.approvalStages" `
                                        -Message "'approvalStages' at $PolPath must be an array."
                                } else {
                                    $ValidVisibility = @(Resolve-OERStructureEnumCasing -EnumName 'approverInfoVisibility' -List)
                                    $StageArr = @($StagesVal)
                                    for ($K = 0; $K -lt $StageArr.Count; $K++) {
                                        $Stg = $StageArr[$K]
                                        $StgPath = "$PolPath.approvalStages[$K]"
                                        if (Test-HasProp -Node $Stg -Name 'durationDays') {
                                            if (-not (Test-IsInt -Value $Stg.durationDays -Min 1 -Max 365)) {
                                                Add-Finding -Section 'accessPackages' -Item $APItem `
                                                    -Path "$StgPath.durationDays" `
                                                    -Message "'durationDays' at $StgPath must be an integer between 1 and 365."
                                            }
                                        } else {
                                            # Issue #70 site 3: -DurationDays on New-OERAccessPackageApprovalStage
                                            # is Mandatory, so Build-OERPolicyParts cannot omit the splat key --
                                            # an absent or explicit-null durationDays keeps the applied value at
                                            # 0. Measured, not assumed: that does NOT quietly become a P0D
                                            # stage -- New-OERAccessPackageApprovalStage's own duration encoder
                                            # (ConvertTo-OERDuration) rejects a value below 1, so the stage build
                                            # throws and the WHOLE assignmentPolicy is reported Failed instead
                                            # of being created or updated. Warn rather than error, since a
                                            # document that validates today must keep validating; Test-HasProp
                                            # already treats a declared null the same as an omitted key, so both
                                            # shapes land here.
                                            Add-Finding -Section 'accessPackages' -Item $APItem `
                                                -Path "$StgPath.durationDays" -Severity 'Warning' `
                                                -Message "'durationDays' is not declared at $StgPath; the applied value defaults to 0, and New-OERAccessPackageApprovalStage requires at least 1 -- applying this document fails to create or update this assignmentPolicy (reported Failed) instead of silently taking effect. Declare 'durationDays' explicitly."
                                        }
                                        if (Test-HasProp -Node $Stg -Name 'managerLevel') {
                                            if (-not (Test-IsInt -Value $Stg.managerLevel -Min 1 -Max ([int]::MaxValue))) {
                                                Add-Finding -Section 'accessPackages' -Item $APItem `
                                                    -Path "$StgPath.managerLevel" `
                                                    -Message "'managerLevel' at $StgPath must be an integer >= 1."
                                            }
                                        }
                                        if (Test-HasProp -Node $Stg -Name 'escalationDays') {
                                            if (-not (Test-IsInt -Value $Stg.escalationDays -Min 1 -Max 365)) {
                                                Add-Finding -Section 'accessPackages' -Item $APItem `
                                                    -Path "$StgPath.escalationDays" `
                                                    -Message "'escalationDays' at $StgPath must be an integer between 1 and 365."
                                            }
                                        }
                                        foreach ($StgArrayProp in @('users', 'groups', 'alternateUsers', 'alternateGroups', 'fallbackUsers', 'fallbackGroups')) {
                                            if (Test-HasProp -Node $Stg -Name $StgArrayProp) {
                                                $StgArrVal = $Stg.$StgArrayProp
                                                if ($StgArrVal -isnot [System.Collections.IEnumerable] -or $StgArrVal -is [string]) {
                                                    Add-Finding -Section 'accessPackages' -Item $APItem `
                                                        -Path "$StgPath.$StgArrayProp" `
                                                        -Message "'$StgArrayProp' at $StgPath must be an array."
                                                }
                                            }
                                        }
                                        foreach ($StgBoolProp in @('internalSponsor', 'externalSponsor', 'requireApproverJustification')) {
                                            if (Test-HasProp -Node $Stg -Name $StgBoolProp) {
                                                if ($Stg.$StgBoolProp -isnot [bool]) {
                                                    Add-Finding -Section 'accessPackages' -Item $APItem `
                                                        -Path "$StgPath.$StgBoolProp" `
                                                        -Message "'$StgBoolProp' at $StgPath must be a boolean."
                                                }
                                            }
                                        }
                                        if (Test-HasProp -Node $Stg -Name 'approverInfoVisibility') {
                                            if ($ValidVisibility -inotcontains $Stg.approverInfoVisibility) {
                                                Add-Finding -Section 'accessPackages' -Item $APItem `
                                                    -Path "$StgPath.approverInfoVisibility" `
                                                    -Message "'approverInfoVisibility' at $StgPath must be one of: $($ValidVisibility -join ', '). Got: '$($Stg.approverInfoVisibility)'."
                                            } else {
                                                Add-EnumCasingWarning -EnumName 'approverInfoVisibility' -Key 'approverInfoVisibility' `
                                                    -Value $Stg.approverInfoVisibility -Section 'accessPackages' -Item $APItem `
                                                    -Path "$StgPath.approverInfoVisibility"
                                            }
                                        }
                                    }
                                }
                            }

                            # A declared-empty approvalStages CLEARS the live approval stages (issue #56),
                            # and ConvertTo-OERPolicyBody takes isApprovalRequiredForAdd from the explicitly
                            # bound -RequireApproval flag rather than from the stage count, so the body sent
                            # is isApprovalRequiredForAdd = true with stages = [].
                            #
                            # MEASURED LIVE, superseding the outcome this Warning used to describe: that body
                            # is never written. Microsoft Graph REFUSES the PUT with
                            #   InvalidApprovalStages: If approval is required, a valid list of stages must
                            #   be provided.
                            # and the policy is left completely unchanged -- a read-back confirmed the
                            # pre-existing stage still present, with no partial write. The apply reports the
                            # assignmentPolicy Failed, and repeats that on every subsequent run, so the
                            # document never converges. The "approval required with no approvers" policy the
                            # earlier wording described cannot be created at all.
                            #
                            # Still a Warning, never an Error: the document validates today and must keep
                            # validating (the apply still runs and reports Failed for this one policy).
                            $EmptyStagesDeclared = (Test-HasProp -Node $Pol -Name 'approvalStages') -and (@($Pol.approvalStages).Count -eq 0)
                            $RequireApprovalTrue = (Test-HasProp -Node $Pol -Name 'requireApproval') -and ($Pol.requireApproval -eq $true)
                            if ($EmptyStagesDeclared -and $RequireApprovalTrue) {
                                Add-Finding -Section 'accessPackages' -Item $APItem `
                                    -Path "$PolPath.approvalStages" `
                                    -Message "'requireApproval' is true at $PolPath while 'approvalStages' is declared as an empty array; Microsoft Graph refuses the write with 'InvalidApprovalStages: If approval is required, a valid list of stages must be provided.', so the assignment policy is reported Failed and left completely unchanged -- the document never converges and reports Failed on every run. Add at least one entry to 'approvalStages', or set 'requireApproval' to false." `
                                    -Severity 'Warning'
                            }

                            # Clearing every approval stage without also clearing BOTH approval flags is the
                            # same refusal, reached without the document ever contradicting itself. Measured
                            # live: a document declaring ONLY "approvalStages": [] failed with the identical
                            # InvalidApprovalStages on all three runs against an existing policy.
                            #
                            # Why it fails when the ADD flag is derived correctly: with -ApprovalStage @()
                            # bound, ConvertTo-OERPolicyBody does derive isApprovalRequiredForAdd = false from
                            # the declared stage count -- that half is right. isApprovalRequiredForUpdate then
                            # falls through to its -Existing carry-forward branch and is re-sent as the LIVE
                            # policy's value, which was true. So Graph's InvalidApprovalStages covers the
                            # UPDATE approval flag too, not only the ADD one, and an UNDECLARED flag is not an
                            # absent one. Clearing it in ConvertTo-OERPolicyBody instead would silently turn
                            # off a live setting the document never mentioned -- exactly the composite-field
                            # carry-forward hazard that file's -Existing design exists to prevent -- so the
                            # gap is reported here, offline, and the transport is left alone.
                            #
                            # EVIDENCE STILL OUTSTANDING, named as the QUESTION rather than as a checklist
                            # section, since no tracked checklist carries the check yet: does Graph still
                            # refuse the emptied stage list when the document declares 'requireApproval'
                            # false and the only approval left in force is the carried-forward
                            # 'requireApprovalForUpdate' = true? What was MEASURED is one step short of
                            # that -- a document declaring ONLY "approvalStages": [], with neither flag
                            # declared, so both were carried forward. Applying
                            # {approvalStages: [], requireApproval: false} against a live policy whose
                            # requireApprovalForUpdate is true is the check that settles it. A refusal
                            # confirms this Warning as written; an acceptance means it over-warns for that
                            # one shape and the condition below must narrow to requireApprovalForUpdate
                            # alone. Until then the Warning takes the conservative reading of the measured
                            # refusal, which costs a false warning at worst and never blocks a document.
                            #
                            # Gated on -not $RequireApprovalTrue so exactly one of the two Warnings fires for
                            # any one policy.
                            if ($EmptyStagesDeclared -and -not $RequireApprovalTrue) {
                                $ApprovalOffForAdd = (Test-HasProp -Node $Pol -Name 'requireApproval') -and ($Pol.requireApproval -eq $false)
                                $ApprovalOffForUpdate = (Test-HasProp -Node $Pol -Name 'requireApprovalForUpdate') -and ($Pol.requireApprovalForUpdate -eq $false)
                                if (-not ($ApprovalOffForAdd -and $ApprovalOffForUpdate)) {
                                    Add-Finding -Section 'accessPackages' -Item $APItem `
                                        -Path "$PolPath.approvalStages" `
                                        -Message "'approvalStages' at $PolPath clears every approval stage while the policy is not declared to stop requiring approval; Microsoft Graph refuses that write with 'InvalidApprovalStages: If approval is required, a valid list of stages must be provided.' whenever approval is still required -- for ADD or for UPDATE. 'requireApprovalForUpdate' is carried forward from the live policy when the document does not declare it, so an undeclared flag is not an absent one: a live true value is re-sent with the emptied stage list and the assignment policy is reported Failed and left unchanged on every run. Declare 'requireApproval' false AND 'requireApprovalForUpdate' false alongside the empty 'approvalStages'. This applies to an EXISTING policy; on a create there is no live policy to carry a flag from." `
                                        -Severity 'Warning'
                                }
                            }

                            if (Test-HasProp -Node $Pol -Name 'durationInDays') {
                                if (-not (Test-IsInt -Value $Pol.durationInDays -Min 1 -Max 3650)) {
                                    Add-Finding -Section 'accessPackages' -Item $APItem `
                                        -Path "$PolPath.durationInDays" `
                                        -Message "'durationInDays' at $PolPath must be an integer between 1 and 3650."
                                }
                            }

                            if (Test-HasProp -Node $Pol -Name 'durationInHours') {
                                if (-not (Test-IsInt -Value $Pol.durationInHours -Min 1 -Max 999999)) {
                                    Add-Finding -Section 'accessPackages' -Item $APItem `
                                        -Path "$PolPath.durationInHours" `
                                        -Message "'durationInHours' at $PolPath must be an integer >= 1."
                                }
                            }

                            if (Test-HasProp -Node $Pol -Name 'expirationDateTime') {
                                $DtParsed = [datetime]::MinValue
                                if (-not [datetime]::TryParse([string]$Pol.expirationDateTime, [ref]$DtParsed)) {
                                    Add-Finding -Section 'accessPackages' -Item $APItem `
                                        -Path "$PolPath.expirationDateTime" `
                                        -Message "'expirationDateTime' at $PolPath is not a valid date/time string."
                                }
                            }

                            $ExpirationCount = 0
                            if (Test-HasProp -Node $Pol -Name 'durationInDays')     { $ExpirationCount++ }
                            if (Test-HasProp -Node $Pol -Name 'durationInHours')    { $ExpirationCount++ }
                            if (Test-HasProp -Node $Pol -Name 'expirationDateTime') { $ExpirationCount++ }
                            if ($ExpirationCount -gt 1) {
                                Add-Finding -Section 'accessPackages' -Item $APItem `
                                    -Path $PolPath `
                                    -Message "At most one of 'durationInDays', 'durationInHours', 'expirationDateTime' may be present at $PolPath (mutual exclusion)."
                            }
                        }
                    }
                }
            }
        }
    }

    # Rule 8: accessReviews
    if (Test-HasProp -Node $Document -Name 'accessReviews') {
        if (Test-SectionIsArray -SectionName 'accessReviews') {
            $ValidRecurrence = @(Resolve-OERStructureEnumCasing -EnumName 'accessReviewRecurrence' -List)
            $ARs = @($Document.accessReviews)
            $ARSeen = [System.Collections.Generic.Dictionary[string, int]]::new([System.StringComparer]::OrdinalIgnoreCase)
            $ARConsequence = 'Both entries reconcile one access review, so applying the document would rewrite its settings on every run.'
            for ($I = 0; $I -lt $ARs.Count; $I++) {
                $AR = $ARs[$I]
                $ARPath = "accessReviews[$I]"
                $ARItem = if (Test-HasProp -Node $AR -Name 'displayName') { $AR.displayName } else { "accessReviews[$I]" }

                foreach ($Req in @('displayName', 'accessPackage', 'assignmentPolicy')) {
                    if (-not (Test-HasProp -Node $AR -Name $Req)) {
                        Add-Finding -Section 'accessReviews' -Item $ARItem `
                            -Path "$ARPath.$Req" `
                            -Message "'$Req' is required at $ARPath."
                    }
                }
                if (Test-HasProp -Node $AR -Name 'displayName') {
                    Add-DuplicateEntryFinding -Seen $ARSeen -Key ([string]$AR.displayName) -Index $I `
                        -Section 'accessReviews' -Item $ARItem -Path $ARPath `
                        -What "display name '$($AR.displayName)'" `
                        -Consequence $ARConsequence
                }
                # A review renamed through the document is found under its previousDisplayName too (tenant-wide,
                # as its displayName is), so that name is a claim of its own, checked after the displayName
                # claim just as the units' and catalogs' is.
                $ARPrev = Test-SupportedRename -Node $AR -Section 'accessReviews' -Item $ARItem -Path $ARPath `
                    -SetCommand 'Set-OERAccessReviewDefinition' -NameParameter '-DisplayName'
                if ($ARPrev) {
                    Add-DuplicateEntryFinding -Seen $ARSeen -Key $ARPrev -Index $I `
                        -Section 'accessReviews' -Item $ARItem -Path "$ARPath.previousDisplayName" `
                        -What "display name '$ARPrev'" `
                        -Consequence $ARConsequence
                }

                if (Test-HasProp -Node $AR -Name 'recurrence') {
                    if ($ValidRecurrence -inotcontains $AR.recurrence) {
                        Add-Finding -Section 'accessReviews' -Item $ARItem `
                            -Path "$ARPath.recurrence" `
                            -Message "'recurrence' at $ARPath must be one of: $($ValidRecurrence -join ', '). Got: '$($AR.recurrence)'."
                    } else {
                        Add-EnumCasingWarning -EnumName 'accessReviewRecurrence' -Key 'recurrence' -Value $AR.recurrence `
                            -Section 'accessReviews' -Item $ARItem -Path "$ARPath.recurrence"
                    }
                }

                foreach ($ArArrayProp in @('reviewers', 'fallbackReviewers')) {
                    if (Test-HasProp -Node $AR -Name $ArArrayProp) {
                        $ArArrVal = $AR.$ArArrayProp
                        if ($ArArrVal -isnot [System.Collections.IEnumerable] -or $ArArrVal -is [string]) {
                            Add-Finding -Section 'accessReviews' -Item $ARItem `
                                -Path "$ARPath.$ArArrayProp" `
                                -Message "'$ArArrayProp' at $ARPath must be an array of strings."
                        }
                    }
                }

                foreach ($ArStringProp in @('descriptionForAdmins', 'descriptionForReviewers')) {
                    if (Test-HasProp -Node $AR -Name $ArStringProp) {
                        if ($AR.$ArStringProp -isnot [string]) {
                            Add-Finding -Section 'accessReviews' -Item $ARItem `
                                -Path "$ARPath.$ArStringProp" `
                                -Message "'$ArStringProp' at $ARPath must be a string."
                        }
                    }
                }

                foreach ($ArBoolProp in @('mailNotification', 'reminderNotification',
                        'requireJustification', 'recommendationsEnabled', 'autoApplyDecisions')) {
                    if (Test-HasProp -Node $AR -Name $ArBoolProp) {
                        if ($AR.$ArBoolProp -isnot [bool]) {
                            Add-Finding -Section 'accessReviews' -Item $ARItem `
                                -Path "$ARPath.$ArBoolProp" `
                                -Message "'$ArBoolProp' at $ARPath must be a boolean."
                        }
                    }
                }

                if (Test-HasProp -Node $AR -Name 'defaultDecision') {
                    $ValidDecision = @(Resolve-OERStructureEnumCasing -EnumName 'accessReviewDefaultDecision' -List)
                    if ($ValidDecision -inotcontains [string]$AR.defaultDecision) {
                        Add-Finding -Section 'accessReviews' -Item $ARItem `
                            -Path "$ARPath.defaultDecision" `
                            -Message "'defaultDecision' at $ARPath must be one of: $($ValidDecision -join ', '). Got: '$($AR.defaultDecision)'."
                    } else {
                        Add-EnumCasingWarning -EnumName 'accessReviewDefaultDecision' -Key 'defaultDecision' `
                            -Value $AR.defaultDecision -Section 'accessReviews' -Item $ARItem `
                            -Path "$ARPath.defaultDecision"
                    }
                }

                if (Test-HasProp -Node $AR -Name 'durationInDays') {
                    if (-not (Test-IsInt -Value $AR.durationInDays -Min 1 -Max 365)) {
                        Add-Finding -Section 'accessReviews' -Item $ARItem `
                            -Path "$ARPath.durationInDays" `
                            -Message "'durationInDays' at $ARPath must be an integer between 1 and 365."
                    }
                }

                if (Test-HasProp -Node $AR -Name 'occurrences') {
                    if (-not (Test-IsInt -Value $AR.occurrences -Min 1 -Max ([int]::MaxValue))) {
                        Add-Finding -Section 'accessReviews' -Item $ARItem `
                            -Path "$ARPath.occurrences" `
                            -Message "'occurrences' at $ARPath must be an integer >= 1."
                    }
                }

                foreach ($ArDateProp in @('startDate', 'endDate')) {
                    if (Test-HasProp -Node $AR -Name $ArDateProp) {
                        $ArDate = [datetime]::MinValue
                        if (-not [datetime]::TryParse([string]$AR.$ArDateProp, [ref]$ArDate)) {
                            Add-Finding -Section 'accessReviews' -Item $ARItem `
                                -Path "$ARPath.$ArDateProp" `
                                -Message "'$ArDateProp' at $ARPath is not a valid date/time string."
                        }
                    }
                }

                # New-OERAccessReviewRecurrence encodes EITHER an endDate range or a numbered range.
                $HasEndDate     = Test-HasProp -Node $AR -Name 'endDate'
                $HasOccurrences = Test-HasProp -Node $AR -Name 'occurrences'
                if ($HasEndDate -and $HasOccurrences) {
                    Add-Finding -Section 'accessReviews' -Item $ARItem -Path $ARPath `
                        -Message "'endDate' and 'occurrences' at $ARPath are mutually exclusive; declare at most one."
                }
                # A OneTime review has no recurrence object at all, so a range is silently inert.
                if (($HasEndDate -or $HasOccurrences) -and
                    (-not (Test-HasProp -Node $AR -Name 'recurrence') -or [string]$AR.recurrence -ieq 'OneTime')) {
                    $RangePath = if ($HasEndDate) { "$ARPath.endDate" } else { "$ARPath.occurrences" }
                    Add-Finding -Section 'accessReviews' -Item $ARItem -Path $RangePath `
                        -Message "A recurrence range at $ARPath has no effect on a OneTime review; set 'recurrence' to a repeating cadence or drop the range." `
                        -Severity 'Warning'
                }

                # Microsoft Graph rejects a manager reviewer without a fallback ("Policy is invalid due
                # to invalid criteria"), and Sync-OERStructureAccessReview defaults to manager when
                # reviewers is ABSENT -- or present with an explicit null, which Test-HasProp counts as
                # absent for exactly that reason. A DECLARED but EMPTY reviewers list is a different
                # thing one line away: on both the create and the update path it means a SELF review,
                # which needs no fallback, so it must NOT be classified as using the manager default.
                # Do not restore a 'Count -eq 0' clause here -- it would demand a fallback for the
                # self review the document deliberately asked for. It never caught the absent case
                # either: @($AR.reviewers) on a node with no such property is @($null), whose Count is
                # 1, not 0, so the first clause is what carries both absent and explicit null.
                $ArReviewerList = @($AR.reviewers)
                $ArUsesManager  = (-not (Test-HasProp -Node $AR -Name 'reviewers')) -or
                                  (@($ArReviewerList | Where-Object { [string]$_ -ieq 'manager' }).Count -gt 0)
                # The fallback side is the MIRROR IMAGE of the reviewers side above, and it NEEDS the
                # 'Count -gt 0' clause that side must not have. Test-HasProp is Test-OERDeclaredProperty,
                # so a DECLARED but EMPTY fallbackReviewers array counts as declared -- but
                # Sync-OERStructureAccessReview collects its fallback reviewers under a bare truthiness
                # test, and [bool]@() is $false, so it collects NONE from an empty array, reports Failed
                # and creates nothing, on every run, forever. Presence alone therefore cannot answer
                # "does this document supply a fallback": an empty list genuinely is no fallback, Graph
                # rejects a manager reviewer that has none, so the document IS invalid and the offline
                # gate has to say so. Keep Test-HasProp in FRONT of the count -- @($AR.fallbackReviewers)
                # on a node with no such property is @($null), whose Count is 1 and not 0, so a
                # count-only gate would read an absent key as a declared one-element list and silence
                # the warning for exactly the case it exists to catch.
                $ArFallbackList = @($AR.fallbackReviewers)
                $ArHasFallback  = (Test-HasProp -Node $AR -Name 'fallbackReviewers') -and
                                  ($ArFallbackList.Count -gt 0)
                if ($ArUsesManager -and -not $ArHasFallback) {
                    Add-Finding -Section 'accessReviews' -Item $ARItem `
                        -Path "$ARPath.fallbackReviewers" `
                        -Message "A manager reviewer at $ARPath (declared, or the default when 'reviewers' is omitted or explicitly null) requires 'fallbackReviewers'; Microsoft Graph rejects the review otherwise. A declared-empty list counts as no fallback." `
                        -Severity 'Warning'
                }
            }
        }
    }

    # Rules 9 and 10 share two scope spelling rules, and Get-OERScopeSpellingProblem owns both: their
    # checks, their order and their message texts, which Get-OERInventory applies to every role
    # assignment it reads too, leaving one at a scope that breaks either rule out of the document
    # (docs/development/rationale.md#undeclarable-scope). The two functions below add one Error at the
    # entry's scope path per problem the owner returns for that rule, and never decide a spelling
    # themselves. The owner's help is the reference list of the rules and says why each exists
    # (docs/development/rationale.md#role-assignment-key); this file keeps no copy of it.
    # Add-ScopeSlashFinding reports the first rule (A15, the trailing or doubled '/'), every problem
    # whose Rule is Slash.
    function Add-ScopeSlashFinding {
        param([object]$Node, [string]$Section, [string]$Item, [string]$Path)
        if (-not (Test-HasProp -Node $Node -Name 'scope')) { return }
        foreach ($Problem in @(Get-OERScopeSpellingProblem -Scope ([string]$Node.scope) -Path $Path)) {
            if ($Problem.Rule -cne 'Slash') { continue }
            Add-Finding -Section $Section -Item $Item -Path "$Path.scope" -Message $Problem.Message
        }
    }

    # Add-ScopeSegmentFinding reports the second rule (A13, BL-141, narrowed 2026-10-14), every problem
    # whose Rule is not Slash, in the order the owner returns them; one scope can draw several. The
    # owner exempts the mg:, sub: and subscription: forms from it through ConvertTo-OERScopeSplat, so
    # the prefix pattern is never repeated here.
    function Add-ScopeSegmentFinding {
        param([object]$Node, [string]$Section, [string]$Item, [string]$Path)
        if (-not (Test-HasProp -Node $Node -Name 'scope')) { return }
        foreach ($Problem in @(Get-OERScopeSpellingProblem -Scope ([string]$Node.scope) -Path $Path)) {
            if ($Problem.Rule -ceq 'Slash') { continue }
            Add-Finding -Section $Section -Item $Item -Path "$Path.scope" -Message $Problem.Message
        }
    }

    # Rule 9: roleAssignments
    if (Test-HasProp -Node $Document -Name 'roleAssignments') {
        if (Test-SectionIsArray -SectionName 'roleAssignments') {
            $RAs = @($Document.roleAssignments)
            $RASeen = [System.Collections.Generic.Dictionary[string, int]]::new([System.StringComparer]::OrdinalIgnoreCase)
            for ($I = 0; $I -lt $RAs.Count; $I++) {
                $RA = $RAs[$I]
                $RAPath = "roleAssignments[$I]"
                $RAItem = if (Test-HasProp -Node $RA -Name 'role') { $RA.role } else { "roleAssignments[$I]" }

                Add-UnknownKeyWarning -Node $RA -Section 'roleAssignments' -Item $RAItem -Path $RAPath `
                    -KnownKey @('scope', 'role', 'principal', 'principalType', 'principalStatus', 'description',
                        'condition', 'conditionVersion', 'id')

                foreach ($Req in @('scope', 'role', 'principal')) {
                    if (-not (Test-HasProp -Node $RA -Name $Req)) {
                        Add-Finding -Section 'roleAssignments' -Item $RAItem `
                            -Path "$RAPath.$Req" `
                            -Message "'$Req' is required at $RAPath."
                    }
                }
                Add-ScopeSlashFinding -Node $RA -Section 'roleAssignments' -Item $RAItem -Path $RAPath
                Add-ScopeSegmentFinding -Node $RA -Section 'roleAssignments' -Item $RAItem -Path $RAPath
                # BL-126: a role assignment at the Azure root scope '/' (Test-OERAzureRootScope owns the
                # rule, so '//' is it too, beside its slash Error, and so are '/.', '/..' and '/%2e',
                # which the ARM transport's URI sends to the root, each beside its A13 segment Error:
                # the Warning no longer stands alone for them) is elevated access, which a document
                # never carries and the apply engine never creates, removes or prunes: it reports the
                # entry Skipped. A Warning, not an Error, so an older export that holds one still applies
                # for the rest (docs/development/rationale.md#root-scope-is-not-in-the-document). Never
                # applied to roleManagementPolicies, nor to the directory role sections, whose '/' is the
                # Microsoft Entra tenant scope.
                if ((Test-HasProp -Node $RA -Name 'scope') -and (Test-OERAzureRootScope -Scope ([string]$RA.scope))) {
                    Add-Finding -Section 'roleAssignments' -Item $RAItem -Path "$RAPath.scope" -Severity 'Warning' `
                        -Message "'scope' at $RAPath is the root scope '/', which grants access over every management group and subscription in the tenant (elevated access). Invoke-OERStructure never creates or removes a role assignment there: the entry is reported Skipped and the root scope is never pruned. Remove the entry and manage elevated access outside the document."
                }
                # The scope is compared in the canonical form ConvertTo-OERCanonicalScope owns (a pure
                # helper shared with the apply engine; the validator must never resolve a scope online).
                # A role is compared as written: a role by name in one entry and by id in another cannot
                # be told apart offline, and the apply engine's own check catches that pair.
                if ((Test-HasProp -Node $RA -Name 'scope') -and (Test-HasProp -Node $RA -Name 'role') -and
                    (Test-HasProp -Node $RA -Name 'principal')) {
                    $RACanonicalScope = ConvertTo-OERCanonicalScope -Scope ([string]$RA.scope)
                    Add-DuplicateEntryFinding -Seen $RASeen -Key "$RACanonicalScope|$($RA.role)|$($RA.principal)" -Index $I `
                        -Section 'roleAssignments' -Item $RAItem -Path $RAPath `
                        -What 'scope, role and principal' `
                        -Consequence ('Both entries describe one role assignment (the scope is compared in its canonical form: ' +
                            'sub: and subscription: with an id, and mg:, are spellings of the scope''s path), so applying ' +
                            'the document would rewrite its condition and description on every run.')
                }

                if (Test-HasProp -Node $RA -Name 'principalType') {
                    $ValidPrincipalTypes = @(Resolve-OERStructureEnumCasing -EnumName 'principalType' -List)
                    if ($ValidPrincipalTypes -inotcontains $RA.principalType) {
                        Add-Finding -Section 'roleAssignments' -Item $RAItem `
                            -Path "$RAPath.principalType" `
                            -Message "'principalType' at $RAPath must be one of: $($ValidPrincipalTypes -join ', '). Got: '$($RA.principalType)'."
                    } else {
                        Add-EnumCasingWarning -EnumName 'principalType' -Key 'principalType' -Value $RA.principalType `
                            -Section 'roleAssignments' -Item $RAItem -Path "$RAPath.principalType"
                    }
                }

                # A18 (Sprint 11 step 6): principalStatus marks an entry whose principal the directory did not
                # return when the document was exported (Get-OERInventory and Export-OERInventory write it,
                # with the principal's object id). Only Deleted and Unresolved, and only as a string: an
                # array holding one of them is not a status. A non-canonical letter case is a Warning, as
                # for principalType. The entry names its principal by object id (Test-OERGuid), since
                # Sync-OERStructureRoleAssignment looks no principal up for it and never creates the
                # assignment; an explicit null is not declared, so neither rule applies to it.
                if (Test-HasProp -Node $RA -Name 'principalStatus') {
                    $ValidPrincipalStatuses = @(Resolve-OERStructureEnumCasing -EnumName 'principalStatus' -List)
                    if ($RA.principalStatus -isnot [string] -or $ValidPrincipalStatuses -inotcontains $RA.principalStatus) {
                        # A value that is not a string is named by its type, as the principal rule below does,
                        # so an array holding 'Deleted' is never shown as if it were the string 'Deleted'.
                        $StatusFound = if ($RA.principalStatus -is [string]) {
                            "'$($RA.principalStatus)'"
                        } else {
                            "a value that is not a string ($($RA.principalStatus.GetType().Name))"
                        }
                        Add-Finding -Section 'roleAssignments' -Item $RAItem `
                            -Path "$RAPath.principalStatus" `
                            -Message "'principalStatus' at $RAPath must be one of: $($ValidPrincipalStatuses -join ', '). Got: $StatusFound."
                    } else {
                        Add-EnumCasingWarning -EnumName 'principalStatus' -Key 'principalStatus' -Value $RA.principalStatus `
                            -Section 'roleAssignments' -Item $RAItem -Path "$RAPath.principalStatus"
                    }
                    if ((Test-HasProp -Node $RA -Name 'principal') -and
                        ($RA.principal -isnot [string] -or -not (Test-OERGuid -Value $RA.principal))) {
                        $PrincipalFound = if ($RA.principal -is [string]) {
                            "'$($RA.principal)'"
                        } else {
                            "a value that is not a string ($($RA.principal.GetType().Name))"
                        }
                        Add-Finding -Section 'roleAssignments' -Item $RAItem `
                            -Path "$RAPath.principal" `
                            -Message ("'principal' at $RAPath must be an object id (a GUID) when 'principalStatus' is declared: the entry stands for a " +
                                'principal the directory did not return when the document was exported, so the engine looks no principal up for it. ' +
                                "Got: $PrincipalFound. Name the principal by its object id, or remove 'principalStatus' to have the principal looked up by name.")
                    }
                }

                $HasCondition        = Test-HasProp -Node $RA -Name 'condition'
                $HasConditionVersion = Test-HasProp -Node $RA -Name 'conditionVersion'
                if ($HasConditionVersion -and -not $HasCondition) {
                    Add-Finding -Section 'roleAssignments' -Item $RAItem `
                        -Path "$RAPath.conditionVersion" `
                        -Message "'conditionVersion' at $RAPath requires a 'condition'; a version alone has no effect."
                }
                if ($HasCondition -and -not $HasConditionVersion) {
                    Add-Finding -Section 'roleAssignments' -Item $RAItem `
                        -Path "$RAPath.conditionVersion" `
                        -Message "'condition' at $RAPath has no 'conditionVersion'; Azure Resource Manager defaults it to 2.0." `
                        -Severity 'Warning'
                }
            }
        }
    }

    # Rules 10 and 10b share one item rule set. A roleManagementPolicies item (the PIM policy of an
    # Azure role at an Azure scope) and a directoryRoleManagementPolicies item (the PIM policy of a
    # Microsoft Entra directory role, always at tenant scope) declare the same policy fields, apart
    # from scope, so both sections run this one nested helper and the rules cannot drift between
    # them. Every message is built from -Path, so the roleManagementPolicies wording is unchanged;
    # -PimLabel only names the product in the MFA/authentication-context message ('Azure PIM' for the
    # Azure section, 'PIM' for the directory section).
    function Test-PimPolicySectionItem {
        param(
            [object]$Node, [string]$Section, [string]$Path, [string]$Item,
            [string[]]$KnownKey, [string[]]$RequiredKey, [string]$PimLabel
        )

        Add-UnknownKeyWarning -Node $Node -Section $Section -Item $Item -Path $Path -KnownKey $KnownKey

        foreach ($Req in $RequiredKey) {
            if (-not (Test-HasProp -Node $Node -Name $Req)) {
                Add-Finding -Section $Section -Item $Item `
                    -Path "$Path.$Req" `
                    -Message "'$Req' is required at $Path."
            }
        }

        foreach ($RmpBoolProp in @('allowPermanentEligibility', 'allowPermanentActiveAssignment',
                'requireMfaOnActivation', 'requireJustificationOnActivation',
                'requireTicketOnActivation', 'requireApproval',
                'requireMfaOnActiveAssignment', 'requireJustificationOnActiveAssignment')) {
            if (Test-HasProp -Node $Node -Name $RmpBoolProp) {
                if ($Node.$RmpBoolProp -isnot [bool]) {
                    Add-Finding -Section $Section -Item $Item `
                        -Path "$Path.$RmpBoolProp" `
                        -Message "'$RmpBoolProp' at $Path must be a boolean."
                }
            }
        }

        if (Test-HasProp -Node $Node -Name 'activationMaxHours') {
            if (-not (Test-IsInt -Value $Node.activationMaxHours -Min 1 -Max 24)) {
                Add-Finding -Section $Section -Item $Item `
                    -Path "$Path.activationMaxHours" `
                    -Message "'activationMaxHours' at $Path must be an integer between 1 and 24."
            }
        }

        foreach ($RmpDurProp in @('eligibleDurationDays', 'activeDurationDays')) {
            if (Test-HasProp -Node $Node -Name $RmpDurProp) {
                if (-not (Test-IsInt -Value $Node.$RmpDurProp -Min 1 -Max 3650)) {
                    Add-Finding -Section $Section -Item $Item `
                        -Path "$Path.$RmpDurProp" `
                        -Message "'$RmpDurProp' at $Path must be an integer between 1 and 3650."
                }
            }
        }

        # Approvers only take effect when approval is required. Both write paths turn approval on
        # whenever approvers are sent -- Resolve-OERPolicyRulePatch sets isApprovalRequired = true
        # unconditionally for the Azure section, and Set-OERDirectoryRoleManagementPolicy treats
        # supplied approvers as implying approval -- so the apply engine drops the approvers rather
        # than silently re-enabling approval on a policy the document says must have it off. Warn
        # (never Error -- such a document is still valid, and Get-OERInventory itself can produce
        # one) so the precedence is visible up front.
        if ((Test-HasProp -Node $Node -Name 'requireApproval') -and ($Node.requireApproval -eq $false)) {
            $DeclaredApproverCount = 0
            foreach ($ApproverKind in @('users', 'groups')) {
                if (Test-HasProp -Node $Node.approvers -Name $ApproverKind) {
                    $DeclaredApproverCount += @($Node.approvers.$ApproverKind).Count
                }
            }
            if ($DeclaredApproverCount -gt 0) {
                Add-Finding -Section $Section -Item $Item `
                    -Path "$Path.approvers" `
                    -Message "'requireApproval' is false at $Path, so the declared 'approvers' are ignored; requireApproval takes precedence and the approvers are not written. Set 'requireApproval' to true to apply them, or drop the approvers block." `
                    -Severity 'Warning'
            }
        }

        if (Test-HasProp -Node $Node -Name 'approvers') {
            $Approvers = $Node.approvers
            if ($Approvers -isnot [PSCustomObject]) {
                Add-Finding -Section $Section -Item $Item `
                    -Path "$Path.approvers" `
                    -Message "'approvers' at $Path must be an object with optional users and groups arrays."
            } else {
                foreach ($ApproverKind in @('users', 'groups')) {
                    if (Test-HasProp -Node $Approvers -Name $ApproverKind) {
                        $ApproverVal = $Approvers.$ApproverKind
                        if ($ApproverVal -isnot [System.Collections.IEnumerable] -or $ApproverVal -is [string]) {
                            Add-Finding -Section $Section -Item $Item `
                                -Path "$Path.approvers.$ApproverKind" `
                                -Message "'approvers.$ApproverKind' at $Path must be an array."
                        }
                    }
                }
            }
        }

        # An empty string is the documented "disable the authentication context" value; any other
        # non-c<digits> value is rejected at runtime by Set-OERRoleManagementPolicy and
        # Set-OERDirectoryRoleManagementPolicy alike, so catch it offline instead.
        if (Test-HasProp -Node $Node -Name 'authenticationContextId') {
            $AuthCtx = [string]$Node.authenticationContextId
            if ($AuthCtx -and $AuthCtx -notmatch '^c\d+$') {
                Add-Finding -Section $Section -Item $Item `
                    -Path "$Path.authenticationContextId" `
                    -Message "'authenticationContextId' at $Path must look like 'c1', or be an empty string to disable it. Got: '$AuthCtx'."
            }
            # PIM treats MFA on activation and an authentication context as mutually exclusive;
            # asking for both in one apply is rejected (by ARM for an Azure role, and by
            # Set-OERDirectoryRoleManagementPolicy's InvalidPolicyChange refusal for a directory
            # role), so fail offline.
            if ($AuthCtx -and (Test-HasProp -Node $Node -Name 'requireMfaOnActivation') -and
                ($Node.requireMfaOnActivation -eq $true)) {
                Add-Finding -Section $Section -Item $Item `
                    -Path $Path `
                    -Message "'requireMfaOnActivation' and 'authenticationContextId' at $Path are mutually exclusive in $PimLabel; declare only one."
            }
        }
    }

    # The item fields both PIM policy sections declare, apart from scope. 'id' is the key
    # Get-OERInventory -IncludeId stamps on an exported entry, accepted so a captured document
    # re-applies without an unknown-key warning.
    $PimPolicyItemKey = @('role', 'allowPermanentEligibility', 'eligibleDurationDays',
        'allowPermanentActiveAssignment', 'activeDurationDays', 'activationMaxHours',
        'requireMfaOnActivation', 'requireJustificationOnActivation',
        'requireTicketOnActivation', 'requireApproval', 'approvers',
        'authenticationContextId', 'requireMfaOnActiveAssignment',
        'requireJustificationOnActiveAssignment', 'id')

    # Rule 10: roleManagementPolicies
    if (Test-HasProp -Node $Document -Name 'roleManagementPolicies') {
        if (Test-SectionIsArray -SectionName 'roleManagementPolicies') {
            $RMPs = @($Document.roleManagementPolicies)
            $RMPSeen = [System.Collections.Generic.Dictionary[string, int]]::new([System.StringComparer]::OrdinalIgnoreCase)
            for ($I = 0; $I -lt $RMPs.Count; $I++) {
                $RMP = $RMPs[$I]
                $RMPPath = "roleManagementPolicies[$I]"
                $RMPItem = if (Test-HasProp -Node $RMP -Name 'role') { $RMP.role } else { "roleManagementPolicies[$I]" }
                Test-PimPolicySectionItem -Node $RMP -Section 'roleManagementPolicies' -Path $RMPPath -Item $RMPItem `
                    -KnownKey (@('scope') + $PimPolicyItemKey) -RequiredKey @('scope', 'role') -PimLabel 'Azure PIM'
                Add-ScopeSlashFinding -Node $RMP -Section 'roleManagementPolicies' -Item $RMPItem -Path $RMPPath
                Add-ScopeSegmentFinding -Node $RMP -Section 'roleManagementPolicies' -Item $RMPItem -Path $RMPPath
                if ((Test-HasProp -Node $RMP -Name 'scope') -and (Test-HasProp -Node $RMP -Name 'role')) {
                    $RMPCanonicalScope = ConvertTo-OERCanonicalScope -Scope ([string]$RMP.scope)
                    Add-DuplicateEntryFinding -Seen $RMPSeen -Key "$RMPCanonicalScope|$($RMP.role)" -Index $I `
                        -Section 'roleManagementPolicies' -Item $RMPItem -Path $RMPPath `
                        -What 'scope and role' `
                        -Consequence ('Both entries describe one policy (the scope is compared in its canonical form), so applying ' +
                            'the document would rewrite its settings on every run.')
                }
            }
        }
    }

    # Rule 10b: directoryRoleManagementPolicies -- the same item rules without scope. A directory
    # role policy always lives at tenant scope, so role is the only required key and a declared
    # scope key is reported as an unknown key that the apply handler ignores.
    if (Test-HasProp -Node $Document -Name 'directoryRoleManagementPolicies') {
        if (Test-SectionIsArray -SectionName 'directoryRoleManagementPolicies') {
            $DRMPs = @($Document.directoryRoleManagementPolicies)
            $DRMPSeen = [System.Collections.Generic.Dictionary[string, int]]::new([System.StringComparer]::OrdinalIgnoreCase)
            for ($I = 0; $I -lt $DRMPs.Count; $I++) {
                $DRMP = $DRMPs[$I]
                $DRMPPath = "directoryRoleManagementPolicies[$I]"
                $DRMPItem = if (Test-HasProp -Node $DRMP -Name 'role') { $DRMP.role } else { "directoryRoleManagementPolicies[$I]" }
                Test-PimPolicySectionItem -Node $DRMP -Section 'directoryRoleManagementPolicies' -Path $DRMPPath -Item $DRMPItem `
                    -KnownKey $PimPolicyItemKey -RequiredKey @('role') -PimLabel 'PIM'
                if (Test-HasProp -Node $DRMP -Name 'role') {
                    Add-DuplicateEntryFinding -Seen $DRMPSeen -Key ([string]$DRMP.role) -Index $I `
                        -Section 'directoryRoleManagementPolicies' -Item $DRMPItem -Path $DRMPPath `
                        -What "role '$($DRMP.role)'" `
                        -Consequence 'Both entries describe one policy, so applying the document would rewrite its settings on every run.'
                }
            }
        }
    }

    # Rule 10c: directoryRoleAssignments -- eligible and active assignments of Microsoft Entra
    # directory roles at tenant scope. role, principal and assignmentType are required and are the
    # match key. durationDays makes an entry time-bound and permanent true makes it permanent, so the
    # two may not contradict each other, and an entry with neither is permanent. Two entries naming the
    # same role, principal and assignmentType would describe one live assignment twice; the handler
    # would re-issue its window for each of them on every run, so the second is an Error. The key is
    # compared as written, without regard to letter case: a role written by name in one entry and by
    # id in another cannot be told apart offline. (The other sections share the newer
    # Add-DuplicateEntryFinding helper and its message shape; this older rule keeps its own wording.)
    # A service principal named by display name rather than object id is a Warning: display names are
    # not unique, and an apply run refuses an ambiguous one (AmbiguousName; the entry reports Failed).
    if (Test-HasProp -Node $Document -Name 'directoryRoleAssignments') {
        if (Test-SectionIsArray -SectionName 'directoryRoleAssignments') {
            $DRAs = @($Document.directoryRoleAssignments)
            $DraSeen = @{}
            for ($I = 0; $I -lt $DRAs.Count; $I++) {
                $DRA = $DRAs[$I]
                $DRAPath = "directoryRoleAssignments[$I]"
                $DRAItem = if (Test-HasProp -Node $DRA -Name 'role') { [string]$DRA.role } else { $DRAPath }

                Add-UnknownKeyWarning -Node $DRA -Section 'directoryRoleAssignments' -Item $DRAItem -Path $DRAPath `
                    -KnownKey @('role', 'principal', 'principalType', 'assignmentType', 'durationDays',
                        'permanent', 'justification', 'id')

                foreach ($Req in @('role', 'principal', 'assignmentType')) {
                    if (-not (Test-HasProp -Node $DRA -Name $Req)) {
                        Add-Finding -Section 'directoryRoleAssignments' -Item $DRAItem `
                            -Path "$DRAPath.$Req" `
                            -Message "'$Req' is required at $DRAPath."
                    }
                }

                if (Test-HasProp -Node $DRA -Name 'assignmentType') {
                    $ValidDraTypes = @(Resolve-OERStructureEnumCasing -EnumName 'directoryRoleAssignmentType' -List)
                    if ($ValidDraTypes -inotcontains [string]$DRA.assignmentType) {
                        Add-Finding -Section 'directoryRoleAssignments' -Item $DRAItem `
                            -Path "$DRAPath.assignmentType" `
                            -Message "'assignmentType' at $DRAPath must be one of: $($ValidDraTypes -join ', '). Got: '$($DRA.assignmentType)'."
                    } else {
                        Add-EnumCasingWarning -EnumName 'directoryRoleAssignmentType' -Key 'assignmentType' -Value $DRA.assignmentType `
                            -Section 'directoryRoleAssignments' -Item $DRAItem -Path "$DRAPath.assignmentType"
                    }
                }

                if (Test-HasProp -Node $DRA -Name 'principalType') {
                    $ValidDraPrincipalTypes = @(Resolve-OERStructureEnumCasing -EnumName 'principalType' -List)
                    if ($ValidDraPrincipalTypes -inotcontains [string]$DRA.principalType) {
                        Add-Finding -Section 'directoryRoleAssignments' -Item $DRAItem `
                            -Path "$DRAPath.principalType" `
                            -Message "'principalType' at $DRAPath must be one of: $($ValidDraPrincipalTypes -join ', '). Got: '$($DRA.principalType)'."
                    } else {
                        Add-EnumCasingWarning -EnumName 'principalType' -Key 'principalType' -Value $DRA.principalType `
                            -Section 'directoryRoleAssignments' -Item $DRAItem -Path "$DRAPath.principalType"
                        # A service principal named by display name: display names are not unique, and
                        # the shared lookup refuses a name that matches more than one service principal
                        # (AmbiguousName), so the entry reports Failed at apply time and withholds the
                        # prune of its pair. A name that is unique today can become ambiguous later;
                        # the object id cannot.
                        if ([string]$DRA.principalType -ieq 'ServicePrincipal' -and
                            (Test-HasProp -Node $DRA -Name 'principal') -and
                            -not (Test-OERGuid -Value ([string]$DRA.principal))) {
                            Add-Finding -Section 'directoryRoleAssignments' -Item $DRAItem `
                                -Path "$DRAPath.principal" -Severity 'Warning' `
                                -Message ("'principal' at $DRAPath names a service principal by display name ('$($DRA.principal)'): " +
                                    'service principal display names are not unique, and an ambiguous name is refused at apply time (the entry fails); ' +
                                    'name a service principal by its object id.')
                        }
                    }
                }

                $DraHasDays = Test-HasProp -Node $DRA -Name 'durationDays'
                if ($DraHasDays -and -not (Test-IsInt -Value $DRA.durationDays -Min 1 -Max 3650)) {
                    Add-Finding -Section 'directoryRoleAssignments' -Item $DRAItem `
                        -Path "$DRAPath.durationDays" `
                        -Message "'durationDays' at $DRAPath must be an integer between 1 and 3650."
                }

                # The window rules only read a real boolean: a non-boolean permanent is its own Error
                # here and would otherwise be coerced into a second, misleading one.
                $DraPermanent = $null
                if (Test-HasProp -Node $DRA -Name 'permanent') {
                    if ($DRA.permanent -is [bool]) {
                        $DraPermanent = $DRA.permanent
                    } else {
                        Add-Finding -Section 'directoryRoleAssignments' -Item $DRAItem `
                            -Path "$DRAPath.permanent" `
                            -Message "'permanent' at $DRAPath must be a boolean."
                    }
                }
                if ($DraHasDays -and $DraPermanent -eq $true) {
                    Add-Finding -Section 'directoryRoleAssignments' -Item $DRAItem -Path $DRAPath `
                        -Message "'durationDays' and 'permanent' true at $DRAPath are mutually exclusive; declare durationDays for a time-bound assignment, or permanent true (or neither) for a permanent one."
                }
                if (-not $DraHasDays -and $DraPermanent -eq $false) {
                    Add-Finding -Section 'directoryRoleAssignments' -Item $DRAItem -Path "$DRAPath.durationDays" `
                        -Message "'permanent' is false at $DRAPath but no 'durationDays' is declared; a time-bound assignment needs durationDays, and an entry without it is permanent."
                }

                if ((Test-HasProp -Node $DRA -Name 'justification') -and $DRA.justification -isnot [string]) {
                    Add-Finding -Section 'directoryRoleAssignments' -Item $DRAItem `
                        -Path "$DRAPath.justification" `
                        -Message "'justification' at $DRAPath must be a string."
                }

                if ((Test-HasProp -Node $DRA -Name 'role') -and (Test-HasProp -Node $DRA -Name 'principal') -and
                    (Test-HasProp -Node $DRA -Name 'assignmentType')) {
                    $DraKey = "$($DRA.role)|$($DRA.principal)|$($DRA.assignmentType)".ToLowerInvariant()
                    if ($DraSeen.ContainsKey($DraKey)) {
                        $DraFirst = $DraSeen[$DraKey]
                        Add-Finding -Section 'directoryRoleAssignments' -Item $DRAItem -Path $DRAPath `
                            -Message ("$DRAPath declares the same role, principal and assignmentType as " +
                                "directoryRoleAssignments[$DraFirst] (compared without regard to letter case). " +
                                'Both entries describe one live assignment, and applying the document would re-issue ' +
                                'its window for each of them on every run; keep one entry.')
                    } else {
                        $DraSeen[$DraKey] = $I
                    }
                }
            }
        }
    }

    # Rule 11: cross-reference warning -- accessPackages[].catalog vs declared catalogs[].displayName
    if ((Test-HasProp -Node $Document -Name 'accessPackages') -and
        ($Document.accessPackages -is [System.Collections.IEnumerable]) -and
        ($Document.accessPackages -isnot [string])) {

        $DeclaredCatalogs = @()
        # R11 (Sprint 11 step 4): a catalog that the document renames is declared under its previous name
        # too -- the name a package may still use for it. Rule 14 gives that package its own Warning,
        # which replaces this one (two Warnings on one path would say the same thing twice). The rename is
        # read with Get-RenameDeclaration, as the duplicate check and Rule 14 read it: a non-empty string
        # that differs from the catalog's own displayName ignoring case. An object id counts here, since a
        # package may name the catalog by the id it is renamed from, although Rule 14 skips it (R10).
        $RenamedCatalogPrev = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
        if ((Test-HasProp -Node $Document -Name 'catalogs') -and
            ($Document.catalogs -is [System.Collections.IEnumerable]) -and
            ($Document.catalogs -isnot [string])) {
            $DeclaredCatalogs = @($Document.catalogs | Where-Object {
                Test-HasProp -Node $_ -Name 'displayName'
            } | ForEach-Object { $_.displayName })
            foreach ($RenamedCatalog in @($Document.catalogs)) {
                $CatDeclaration = Get-RenameDeclaration -Node $RenamedCatalog
                if ($CatDeclaration.State -eq 'Rename') { $null = $RenamedCatalogPrev.Add($CatDeclaration.Previous) }
            }
        }

        $APArr = @($Document.accessPackages)
        for ($I = 0; $I -lt $APArr.Count; $I++) {
            $AP = $APArr[$I]
            if (Test-HasProp -Node $AP -Name 'catalog') {
                $CatRef = $AP.catalog
                if ($DeclaredCatalogs -inotcontains $CatRef -and
                    -not ($CatRef -is [string] -and $RenamedCatalogPrev.Contains($CatRef))) {
                    $APItem = if (Test-HasProp -Node $AP -Name 'displayName') { $AP.displayName } else { "accessPackages[$I]" }
                    Add-Finding -Section 'accessPackages' -Item $APItem `
                        -Path "accessPackages[$I].catalog" `
                        -Message "Catalog '$CatRef' is not declared in this document. It may already exist in the tenant." `
                        -Severity 'Warning'
                }
            }
        }
    }

    # Rule 12: cross-reference warning -- groups[].administrativeUnit placement (issue #59, BL-07)
    #
    # administrativeUnit on a group is create-path only (Sync-OERStructureGroup) and never round-trips,
    # so the ONLY way a document keeps a group inside a unit across repeated applies is by also naming
    # the group in that unit's own administrativeUnits[].members. The run that creates the group keeps
    # the membership: Sync-OERStructureGroup records it, and Sync-OERStructureAdministrativeUnit --
    # dispatched after groups -- withholds its prune in that run (Skipped, "prune withheld"). Every
    # later apply with -Prune sees an undeclared member and removes it, and nothing self-heals it,
    # since the create-only field never fires again once the group exists. This is a Warning, never an
    # Error (spec Foerhandsbeslut option A+B, not C), so no document that validates today starts failing.
    #
    # The group's name is the one Get-GroupEntryName computes, a template-based group's included; an
    # entry whose name cannot be computed is skipped. The unit reference is read the way New-OERGroup
    # reads it: one that parses as a GUID (-as [guid], so braced and dash-less forms too -- the wider
    # cast New-OERGroup uses, deliberately not Test-OERGuid) is an object id and matches the entry that
    # declares that id, compared as a GUID; any other reference is a display name and matches the
    # entry of that displayName, ignoring case. A unit's members name the group when they hold its name
    # or its declared id, ignoring case. When the group declares no id, a member that is an object id
    # may be this group -- an exported inventory lists a group member by its id -- so the unit counts
    # as naming it (ruling R9), unless that object id is the declared id of another groups[] entry,
    # which names that other group and so cannot be this one.
    function Test-UnitMayNameGroup {
        param([object]$Unit, [string]$GroupName, [object]$GroupId, [System.Collections.Generic.HashSet[string]]$DeclaredGroupId)
        $UnitMembers = if (Test-HasProp -Node $Unit -Name 'members') { @($Unit.members) } else { @() }
        foreach ($UnitMember in $UnitMembers) {
            $MemberText = [string]$UnitMember
            if ($MemberText -ieq $GroupName) { return $true }
            if ($null -ne $GroupId) {
                if ($MemberText -ieq [string]$GroupId) { return $true }
            } elseif ((Test-OERGuid -Value $MemberText) -and -not $DeclaredGroupId.Contains($MemberText)) {
                return $true
            }
        }
        return $false
    }

    # Whether an administrativeUnits[] entry is the unit a groups[] administrativeUnit reference names, read
    # the way New-OERGroup reads it (Rule 12 and Rule 16 share it): a reference that parses as a GUID
    # (-as [guid], so braced and dash-less forms too) is an object id and matches the entry that declares
    # that id, compared as a GUID; any other reference is a display name and matches the entry of that
    # displayName, ignoring case. -ReferenceGuid is the reference parsed, $null when it is not a GUID, so
    # two values that are not object ids never match as two nulls.
    function Test-UnitNamedByReference {
        param([object]$Unit, [string]$Reference, [object]$ReferenceGuid)
        if ($null -ne $ReferenceGuid) {
            return (Test-HasProp -Node $Unit -Name 'id') -and (([string]$Unit.id -as [guid]) -eq $ReferenceGuid)
        }
        (Test-HasProp -Node $Unit -Name 'displayName') -and ([string]$Unit.displayName -ieq $Reference)
    }

    if ((Test-HasProp -Node $Document -Name 'groups') -and
        ($Document.groups -is [System.Collections.IEnumerable]) -and
        ($Document.groups -isnot [string]) -and
        (Test-HasProp -Node $Document -Name 'administrativeUnits') -and
        ($Document.administrativeUnits -is [System.Collections.IEnumerable]) -and
        ($Document.administrativeUnits -isnot [string])) {

        $AuPlacementUnits = @($Document.administrativeUnits)
        $AuPlacementGroups = @($Document.groups)
        # The ids the groups[] entries declare, for the R9 refinement above: a unit member that is one
        # of them names that group.
        $AuPlacementGroupId = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
        foreach ($IdGroup in $AuPlacementGroups) {
            if (Test-HasProp -Node $IdGroup -Name 'id') { $null = $AuPlacementGroupId.Add([string]$IdGroup.id) }
        }
        for ($I = 0; $I -lt $AuPlacementGroups.Count; $I++) {
            $PGroup = $AuPlacementGroups[$I]
            if (-not (Test-HasProp -Node $PGroup -Name 'administrativeUnit')) { continue }
            $PAuName = [string]$PGroup.administrativeUnit
            if ([string]::IsNullOrEmpty($PAuName)) { continue }
            $PAuGuid = $PAuName -as [guid]

            # A template-based group's name is computed offline, exactly as the duplicate check does;
            # an entry whose name cannot be computed is reported Failed by the apply engine on its own.
            $PGroupName = Get-GroupEntryName -Group $PGroup
            if ($null -eq $PGroupName) { continue }
            $PGroupId = if (Test-HasProp -Node $PGroup -Name 'id') { [string]$PGroup.id } else { $null }
            $PNamedAs = if ($null -ne $PGroupId) { "'$PGroupName' or its id '$PGroupId'" } else { "'$PGroupName'" }
            $PGPath = "groups[$I]"

            # An object id matches only by the id an entry declares, and a display name only by
            # displayName, as New-OERGroup decides between the two. Comparing as a GUID only when the
            # reference parses as one keeps two unparseable values from matching as two nulls.
            $PMatchedAuIndex = -1
            for ($K = 0; $K -lt $AuPlacementUnits.Count; $K++) {
                $PUnit = $AuPlacementUnits[$K]
                if (Test-UnitNamedByReference -Unit $PUnit -Reference $PAuName -ReferenceGuid $PAuGuid) {
                    $PMatchedAuIndex = $K
                    break
                }
            }

            if ($PMatchedAuIndex -lt 0) {
                # No administrativeUnits[] entry for this unit by name: the unit is managed elsewhere (or
                # already exists in the tenant with this group already a member), and this document
                # makes no claim about its membership either way. An object id that no entry declares as
                # its id is the exception: the unit may be one of the entries, and offline nothing tells
                # which. Warn when an entry that reconciles its members (an explicit null does not) does
                # not name the group, since that entry may be the unit (ruling R9). An entry that declares
                # an id of its own was compared above and is another unit, so it is never listed.
                if ($null -eq $PAuGuid) { continue }
                $PUnnamingIndex = @(for ($K = 0; $K -lt $AuPlacementUnits.Count; $K++) {
                        if ((-not (Test-HasProp -Node $AuPlacementUnits[$K] -Name 'id')) -and
                            (-not (Test-OERDeclaredNull -Node $AuPlacementUnits[$K] -Name 'members')) -and
                            (-not (Test-UnitMayNameGroup -Unit $AuPlacementUnits[$K] -GroupName $PGroupName -GroupId $PGroupId -DeclaredGroupId $AuPlacementGroupId))) {
                            $K
                        }
                    })
                if ($PUnnamingIndex.Count -eq 0) { continue }
                $PUnnamingList = ($PUnnamingIndex | ForEach-Object { "administrativeUnits[$_]" }) -join ', '
                Add-Finding -Section 'groups' -Item $PGroupName -Path "$PGPath.administrativeUnit" -Severity 'Warning' `
                    -Message ("Group '$PGroupName' at $PGPath declares administrativeUnit '$PAuName', an object id that no " +
                        'administrativeUnits[] entry declares as its id, so this check cannot tell offline whether it names ' +
                        "a unit whose members do not list $PNamedAs ($PUnnamingList). " +
                        'administrativeUnit is applied only when the group is created and never round-trips: if it names ' +
                        'one of them, the run that creates the group withholds the prune of that membership (Skipped, ' +
                        '"prune withheld"), and every later apply with -Prune removes it. Name the group in that ' +
                        "unit's members, or declare the unit's id on its administrativeUnits[] entry.")
                continue
            }
            $PMatchedAu = $AuPlacementUnits[$PMatchedAuIndex]

            # An explicit null on the unit's members is the documented "hands off" signal
            # (Test-OERDeclaredNull): Sync-OERStructureAdministrativeUnit skips the whole
            # reconcile/prune pass for that collection, so no undeclared-member removal can happen.
            if (Test-OERDeclaredNull -Node $PMatchedAu -Name 'members') { continue }

            # An OMITTED members key is not the same signal -- it still reconciles (against an empty
            # declared set) and still prunes, so Test-UnitMayNameGroup reads it as an empty list.
            if (-not (Test-UnitMayNameGroup -Unit $PMatchedAu -GroupName $PGroupName -GroupId $PGroupId -DeclaredGroupId $AuPlacementGroupId)) {
                Add-Finding -Section 'groups' -Item $PGroupName -Path "$PGPath.administrativeUnit" -Severity 'Warning' `
                    -Message ("Group '$PGroupName' at $PGPath declares administrativeUnit '$PAuName', but " +
                        "administrativeUnits[$PMatchedAuIndex].members does not list $PNamedAs. " +
                        'administrativeUnit is applied only when the group is created and never round-trips: ' +
                        'the run that creates the group withholds the prune of that membership (Skipped, ' +
                        '"prune withheld"), but every later apply with -Prune removes it unless this ' +
                        "document's administrativeUnits[$PMatchedAuIndex] entry names the group in members.")
            }
        }
    }

    # Rule 13: an omitted collection key that -Prune still reconciles. Get-OEROmittedPruneCollection owns
    # which keys those are (and the null, declared-array and dynamic-members exclusions); this rule only
    # turns each record into a Warning, never an Error, so no document that validates today starts
    # failing.
    foreach ($OmittedCollection in @(Get-OEROmittedPruneCollection -Document $Document)) {
        $OmittedKey = $OmittedCollection.Collection
        $OmittedAt = $OmittedCollection.Path
        Add-Finding -Section $OmittedCollection.Section -Item $OmittedCollection.Item -Path "$OmittedAt.$OmittedKey" -Severity 'Warning' `
            -Message ("'$OmittedKey' is omitted at $OmittedAt. An omitted $OmittedKey key is still reconciled, against an " +
                "empty declared set, so Invoke-OERStructure -Prune removes every live entry in it. Declare the key (an " +
                'empty array removes them deliberately), or set it to null to leave the collection untouched.')
    }

    # Rule 14: cross-reference warning -- a reference that still names a renamed object by its previous
    # name (BL-128, A5; Sprint 11 step 4). A group's administrativeUnit, an access package's catalog and an
    # access review's accessPackage each name another entry of the document by display name; once that
    # entry's rename is applied no object carries the previous name any more, so the reference finds
    # nothing -- the new name, or an object id, is the form that survives. The rename is read as Rule 11
    # reads it (Get-RenameDeclaration: a non-empty string that differs from the entry's own displayName
    # ignoring case), and an object id is skipped (R10): a reference by id stays valid after a rename. An
    # entry with no displayName is skipped too, since it is an Error already and has no new name to point
    # to. The first entry that renames from the name is the one named. A Warning, never an Error, so no
    # document that validates today starts failing; for an access package's catalog it REPLACES Rule 11's
    # "not declared" Warning (R11).
    function Get-RenamedFrom {
        param([object]$Document, [string]$Section)
        $Renamed = [System.Collections.Generic.Dictionary[string, object]]::new([System.StringComparer]::OrdinalIgnoreCase)
        if ((Test-HasProp -Node $Document -Name $Section) -and
            ($Document.$Section -is [System.Collections.IEnumerable]) -and
            ($Document.$Section -isnot [string])) {
            $Entries = @($Document.$Section)
            for ($K = 0; $K -lt $Entries.Count; $K++) {
                $Declaration = Get-RenameDeclaration -Node $Entries[$K]
                if ($Declaration.State -ne 'Rename') { continue }
                if (Test-OERGuid -Value $Declaration.Previous) { continue }
                if (-not (Test-HasProp -Node $Entries[$K] -Name 'displayName')) { continue }
                if (-not $Renamed.ContainsKey($Declaration.Previous)) {
                    $Renamed[$Declaration.Previous] = [PSCustomObject]@{ Index = $K; DisplayName = [string]$Entries[$K].displayName }
                }
            }
        }
        , $Renamed
    }

    $RenamedUnitFrom = Get-RenamedFrom -Document $Document -Section 'administrativeUnits'
    $RenamedCatalogFrom = Get-RenamedFrom -Document $Document -Section 'catalogs'
    $RenamedPackageFrom = Get-RenamedFrom -Document $Document -Section 'accessPackages'

    if ($RenamedUnitFrom.Count -gt 0 -and
        (Test-HasProp -Node $Document -Name 'groups') -and
        ($Document.groups -is [System.Collections.IEnumerable]) -and
        ($Document.groups -isnot [string])) {
        $RefGroups = @($Document.groups)
        for ($I = 0; $I -lt $RefGroups.Count; $I++) {
            if (-not (Test-HasProp -Node $RefGroups[$I] -Name 'administrativeUnit')) { continue }
            $RefUnit = $RefGroups[$I].administrativeUnit
            if ($RefUnit -isnot [string] -or -not $RenamedUnitFrom.ContainsKey($RefUnit)) { continue }
            $RefRename = $RenamedUnitFrom[$RefUnit]
            $RefGroupName = Get-GroupEntryName -Group $RefGroups[$I]
            if ($null -eq $RefGroupName) { $RefGroupName = "groups[$I]" }
            Add-Finding -Section 'groups' -Item $RefGroupName -Path "groups[$I].administrativeUnit" -Severity 'Warning' `
                -Message ("Group '$RefGroupName' at groups[$I] declares administrativeUnit '$RefUnit', the previousDisplayName of " +
                    "administrativeUnits[$($RefRename.Index)], which renames that unit to '$($RefRename.DisplayName)'. " +
                    "Name the unit by its new name '$($RefRename.DisplayName)' or its object id: once the rename is applied " +
                    "no unit carries '$RefUnit'.")
        }
    }

    if ($RenamedCatalogFrom.Count -gt 0 -and
        (Test-HasProp -Node $Document -Name 'accessPackages') -and
        ($Document.accessPackages -is [System.Collections.IEnumerable]) -and
        ($Document.accessPackages -isnot [string])) {
        $RefPackages = @($Document.accessPackages)
        for ($I = 0; $I -lt $RefPackages.Count; $I++) {
            if (-not (Test-HasProp -Node $RefPackages[$I] -Name 'catalog')) { continue }
            $RefCatalog = $RefPackages[$I].catalog
            if ($RefCatalog -isnot [string] -or -not $RenamedCatalogFrom.ContainsKey($RefCatalog)) { continue }
            $RefRename = $RenamedCatalogFrom[$RefCatalog]
            $RefPackageName = if (Test-HasProp -Node $RefPackages[$I] -Name 'displayName') { [string]$RefPackages[$I].displayName } else { "accessPackages[$I]" }
            Add-Finding -Section 'accessPackages' -Item $RefPackageName -Path "accessPackages[$I].catalog" -Severity 'Warning' `
                -Message ("Access package '$RefPackageName' at accessPackages[$I] declares catalog '$RefCatalog', the previousDisplayName of " +
                    "catalogs[$($RefRename.Index)], which renames that catalog to '$($RefRename.DisplayName)'. " +
                    "Name the catalog by its new name '$($RefRename.DisplayName)': once the rename is applied no catalog carries " +
                    "'$RefCatalog', and the package is neither found nor created in it.")
        }
    }

    if ($RenamedPackageFrom.Count -gt 0 -and
        (Test-HasProp -Node $Document -Name 'accessReviews') -and
        ($Document.accessReviews -is [System.Collections.IEnumerable]) -and
        ($Document.accessReviews -isnot [string])) {
        $RefReviews = @($Document.accessReviews)
        for ($I = 0; $I -lt $RefReviews.Count; $I++) {
            if (-not (Test-HasProp -Node $RefReviews[$I] -Name 'accessPackage')) { continue }
            $RefPackage = $RefReviews[$I].accessPackage
            if ($RefPackage -isnot [string] -or -not $RenamedPackageFrom.ContainsKey($RefPackage)) { continue }
            $RefRename = $RenamedPackageFrom[$RefPackage]
            $RefReviewName = if (Test-HasProp -Node $RefReviews[$I] -Name 'displayName') { [string]$RefReviews[$I].displayName } else { "accessReviews[$I]" }
            Add-Finding -Section 'accessReviews' -Item $RefReviewName -Path "accessReviews[$I].accessPackage" -Severity 'Warning' `
                -Message ("Access review '$RefReviewName' at accessReviews[$I] declares accessPackage '$RefPackage', the previousDisplayName of " +
                    "accessPackages[$($RefRename.Index)], which renames that access package to '$($RefRename.DisplayName)'. " +
                    "Name the access package by its new name '$($RefRename.DisplayName)' or its object id: once the rename is applied " +
                    "no access package carries '$RefPackage', and the review's target check fails.")
        }
    }

    # Rule 14, the policy half (Sprint 11 step 4b): an access review names its assignment policy by display
    # name within the package it names, so a review whose assignmentPolicy is the previousDisplayName of a
    # policy entry of that package finds nothing once the rename is applied, and its target check fails. The
    # package is the entry whose displayName, or the previous name it renames from, equals the review's
    # accessPackage (a previous name that is an object id included: the review may name the package by that
    # id). The policy's rename is read as above: Get-RenameDeclaration, an object id skipped (R10), an
    # entry without a displayName skipped. The first policy entry that renames from the name is the one
    # named. A Warning at the review's assignmentPolicy, never an Error.
    if ((Test-HasProp -Node $Document -Name 'accessPackages') -and
        ($Document.accessPackages -is [System.Collections.IEnumerable]) -and
        ($Document.accessPackages -isnot [string]) -and
        (Test-HasProp -Node $Document -Name 'accessReviews') -and
        ($Document.accessReviews -is [System.Collections.IEnumerable]) -and
        ($Document.accessReviews -isnot [string])) {
        $PolRefPackages = @($Document.accessPackages)
        $PolRefReviews = @($Document.accessReviews)
        for ($I = 0; $I -lt $PolRefReviews.Count; $I++) {
            if (-not (Test-HasProp -Node $PolRefReviews[$I] -Name 'accessPackage')) { continue }
            if (-not (Test-HasProp -Node $PolRefReviews[$I] -Name 'assignmentPolicy')) { continue }
            $PolRefPackage = $PolRefReviews[$I].accessPackage
            $PolRefPolicy = $PolRefReviews[$I].assignmentPolicy
            if ($PolRefPackage -isnot [string] -or $PolRefPolicy -isnot [string]) { continue }

            $PolRefHit = $null
            for ($P = 0; $P -lt $PolRefPackages.Count -and $null -eq $PolRefHit; $P++) {
                $PolRefPkg = $PolRefPackages[$P]
                if (-not (Test-HasProp -Node $PolRefPkg -Name 'displayName')) { continue }
                $PkgRename = Get-RenameDeclaration -Node $PolRefPkg
                $PkgIsNamed = ([string]$PolRefPkg.displayName -ieq $PolRefPackage) -or
                    ($PkgRename.State -eq 'Rename' -and $PkgRename.Previous -ieq $PolRefPackage)
                if (-not $PkgIsNamed) { continue }
                if (-not (Test-HasProp -Node $PolRefPkg -Name 'assignmentPolicies') -or
                    $PolRefPkg.assignmentPolicies -isnot [System.Collections.IEnumerable] -or
                    $PolRefPkg.assignmentPolicies -is [string]) { continue }
                $PkgPolicies = @($PolRefPkg.assignmentPolicies)
                for ($K = 0; $K -lt $PkgPolicies.Count -and $null -eq $PolRefHit; $K++) {
                    $PolRename = Get-RenameDeclaration -Node $PkgPolicies[$K]
                    if ($PolRename.State -ne 'Rename') { continue }
                    if (Test-OERGuid -Value $PolRename.Previous) { continue }
                    if (-not (Test-HasProp -Node $PkgPolicies[$K] -Name 'displayName')) { continue }
                    if ($PolRename.Previous -ine $PolRefPolicy) { continue }
                    $PolRefHit = [PSCustomObject]@{ Package = $P; Index = $K; DisplayName = [string]$PkgPolicies[$K].displayName }
                }
            }
            if ($null -eq $PolRefHit) { continue }

            $PolRefReviewName = if (Test-HasProp -Node $PolRefReviews[$I] -Name 'displayName') { [string]$PolRefReviews[$I].displayName } else { "accessReviews[$I]" }
            Add-Finding -Section 'accessReviews' -Item $PolRefReviewName -Path "accessReviews[$I].assignmentPolicy" -Severity 'Warning' `
                -Message ("Access review '$PolRefReviewName' at accessReviews[$I] declares assignmentPolicy '$PolRefPolicy', the previousDisplayName of " +
                    "accessPackages[$($PolRefHit.Package)].assignmentPolicies[$($PolRefHit.Index)], which renames that assignment policy to '$($PolRefHit.DisplayName)'. " +
                    "Name the assignment policy by its new name '$($PolRefHit.DisplayName)' or its object id: once the rename is applied no assignment policy of the " +
                    "access package carries '$PolRefPolicy', and the review's target check fails.")
        }
    }

    # Rule 15 (Sprint 11 step 4b; widened by BL-147): a review that names by display name a package two or
    # more accessPackages entries declare. A package is identified by its
    # catalog together with its name, so the same name in two catalogs is two packages (the duplicate
    # check above does not refuse it), but Invoke-OERStructure's run-scoped rename map keys a package --
    # and a policy within it -- by the package's name, without its catalog ('accessPackages|<name>',
    # 'assignmentPolicies|<package name>|<policy>'; a policy also under the package's id once the access
    # package handler knows it). A review reads that map for a package name that is not
    # an object id, so it would reach whichever entry registered the name last; and one entry's mark or
    # decision would overwrite another's refusal. The run cannot tell which package the review means, so
    # the document is refused offline: an Error at the review's accessPackage, naming every entry that
    # declares the name as its displayName or (Get-RenameDeclaration, Rename state) its
    # previousDisplayName, when there are two or more. Before BL-147 only a rename registered a package, so
    # the Error needed one of those entries in the Rename state; since every accessPackages entry registers
    # its package (R-8, docs/development/rationale.md#review-package-in-the-same-run), it stands whether or
    # not one renames, and the message names the rename only when there is one. A reference that is an
    # object id is never read in the map, so it is never reported.
    if ((Test-HasProp -Node $Document -Name 'accessPackages') -and
        ($Document.accessPackages -is [System.Collections.IEnumerable]) -and
        ($Document.accessPackages -isnot [string]) -and
        (Test-HasProp -Node $Document -Name 'accessReviews') -and
        ($Document.accessReviews -is [System.Collections.IEnumerable]) -and
        ($Document.accessReviews -isnot [string])) {
        $AmbPackages = @($Document.accessPackages)
        $AmbReviews = @($Document.accessReviews)
        for ($I = 0; $I -lt $AmbReviews.Count; $I++) {
            if (-not (Test-HasProp -Node $AmbReviews[$I] -Name 'accessPackage')) { continue }
            $AmbRef = $AmbReviews[$I].accessPackage
            if ($AmbRef -isnot [string] -or (Test-OERGuid -Value $AmbRef)) { continue }

            $AmbPaths = [System.Collections.Generic.List[string]]::new()
            $AmbRenamed = $false
            for ($P = 0; $P -lt $AmbPackages.Count; $P++) {
                $AmbRename = Get-RenameDeclaration -Node $AmbPackages[$P]
                $AmbByName = (Test-HasProp -Node $AmbPackages[$P] -Name 'displayName') -and ([string]$AmbPackages[$P].displayName -ieq $AmbRef)
                # Previous is set in the Rename state only, so this compares a rename's previous name alone.
                $AmbByPrevious = $AmbRename.Previous -ieq $AmbRef
                if (-not ($AmbByName -or $AmbByPrevious)) { continue }
                $AmbPaths.Add("accessPackages[$P]")
                if ($AmbRename.State -eq 'Rename') { $AmbRenamed = $true }
            }
            if ($AmbPaths.Count -lt 2) { continue }

            # The message says that one of the entries renames only when one does.
            $AmbRenameClause = if ($AmbRenamed) { ' while at least one of them is renamed through previousDisplayName' } else { '' }
            $AmbReviewName = if (Test-HasProp -Node $AmbReviews[$I] -Name 'displayName') { [string]$AmbReviews[$I].displayName } else { "accessReviews[$I]" }
            Add-Finding -Section 'accessReviews' -Item $AmbReviewName -Path "accessReviews[$I].accessPackage" `
                -Message ("Access review '$AmbReviewName' at accessReviews[$I] declares accessPackage '$AmbRef', which $($AmbPaths.Count) " +
                    "accessPackages entries declare as displayName or previousDisplayName ($($AmbPaths -join ', '))$AmbRenameClause, " +
                    'so the run cannot tell which access package the review means. Name the access package by its object id.')
        }
    }

    # Rule 16 (Sprint 11 step 6, BL-134): a group that uses PIM for Groups in a restricted management unit.
    # Microsoft Learn states that Privileged Identity Management does not support a group in a restricted
    # management administrative unit (an administrativeUnits[] entry whose restricted is the boolean true).
    # Invoke-OERStructure still sends the PIM settings and eligibility a document declares for such a
    # group, and what Microsoft Graph answers to those writes is not measured, so this is a Warning and
    # never an Error (docs/development/rationale.md#restricted-unit-pim). A group uses PIM for Groups when
    # it declares a pimPolicy (a present key that is not null) or an eligibility array with at least one
    # entry. Two shapes, each raised at most once per unit:
    #   - the group names a restricted unit (its administrativeUnit, read as Rule 12 reads it: an object id
    #     matches the entry that declares that id, any other value the entry of that displayName, ignoring
    #     case) -- a Warning at groups[i].administrativeUnit;
    #   - a restricted unit's members list the group, by its name (ignoring case, the name Rule 12 computes
    #     for a template-based group) or by the id the group declares -- a Warning at groups[i].
    # An exported document raises neither: its groups carry no object id and no administrativeUnit, and its
    # units list a group member by object id, which the document does not declare anywhere. Export-OERInventory
    # names those groups in its own warning and README section instead.
    function Test-UnitRestricted {
        param([object]$Unit)
        (Test-HasProp -Node $Unit -Name 'restricted') -and ($Unit.restricted -is [bool]) -and $Unit.restricted
    }

    if ((Test-HasProp -Node $Document -Name 'groups') -and
        ($Document.groups -is [System.Collections.IEnumerable]) -and
        ($Document.groups -isnot [string]) -and
        (Test-HasProp -Node $Document -Name 'administrativeUnits') -and
        ($Document.administrativeUnits -is [System.Collections.IEnumerable]) -and
        ($Document.administrativeUnits -isnot [string])) {
        $RestrictedGroups = @($Document.groups)
        $RestrictedUnits = @($Document.administrativeUnits)
        $RestrictedRisk = ('Microsoft Learn states that Privileged Identity Management does not support a group in a restricted management administrative unit. ' +
            'Invoke-OERStructure still sends the PIM settings and eligibility the document declares for the group; what Microsoft Graph answers to those writes ' +
            'has not been measured. Review it before applying the document.')
        for ($I = 0; $I -lt $RestrictedGroups.Count; $I++) {
            $RestrictedGroup = $RestrictedGroups[$I]
            $UsesPim = (Test-HasProp -Node $RestrictedGroup -Name 'pimPolicy') -or
                ((Test-HasProp -Node $RestrictedGroup -Name 'eligibility') -and
                ($RestrictedGroup.eligibility -is [System.Collections.IEnumerable]) -and
                ($RestrictedGroup.eligibility -isnot [string]) -and
                (@($RestrictedGroup.eligibility | Where-Object { $null -ne $_ }).Count -gt 0))
            if (-not $UsesPim) { continue }

            $RestrictedName = Get-GroupEntryName -Group $RestrictedGroup
            $RestrictedId = if (Test-HasProp -Node $RestrictedGroup -Name 'id') { [string]$RestrictedGroup.id } else { $null }
            $RestrictedItem = if ($null -ne $RestrictedName) { $RestrictedName } else { "groups[$I]" }
            $RestrictedLabel = if ($null -ne $RestrictedName) { "Group '$RestrictedName' at groups[$I]" } else { "Group at groups[$I]" }

            # The group names a restricted unit.
            if (Test-HasProp -Node $RestrictedGroup -Name 'administrativeUnit') {
                $RestrictedRef = [string]$RestrictedGroup.administrativeUnit
                if (-not [string]::IsNullOrEmpty($RestrictedRef)) {
                    $RestrictedRefGuid = $RestrictedRef -as [guid]
                    for ($K = 0; $K -lt $RestrictedUnits.Count; $K++) {
                        if (-not (Test-UnitRestricted -Unit $RestrictedUnits[$K])) { continue }
                        if (-not (Test-UnitNamedByReference -Unit $RestrictedUnits[$K] -Reference $RestrictedRef -ReferenceGuid $RestrictedRefGuid)) { continue }
                        Add-Finding -Section 'groups' -Item $RestrictedItem -Path "groups[$I].administrativeUnit" -Severity 'Warning' `
                            -Message ("$RestrictedLabel declares PIM for Groups settings (an eligibility or a pimPolicy) and administrativeUnit '$RestrictedRef', " +
                                "which names administrativeUnits[$K], a restricted management unit. $RestrictedRisk")
                    }
                }
            }

            # A restricted unit's members list the group.
            for ($K = 0; $K -lt $RestrictedUnits.Count; $K++) {
                $RestrictedUnit = $RestrictedUnits[$K]
                if (-not (Test-UnitRestricted -Unit $RestrictedUnit)) { continue }
                # An omitted or null members lists nobody.
                $ListedAs = $null
                foreach ($UnitMember in @($RestrictedUnit.members)) {
                    $MemberText = [string]$UnitMember
                    if ((-not [string]::IsNullOrEmpty($RestrictedName) -and $MemberText -ieq $RestrictedName) -or
                        (-not [string]::IsNullOrEmpty($RestrictedId) -and $MemberText -ieq $RestrictedId)) {
                        $ListedAs = $MemberText
                        break
                    }
                }
                if ($null -eq $ListedAs) { continue }
                $RestrictedUnitName = if (Test-HasProp -Node $RestrictedUnit -Name 'displayName') { [string]$RestrictedUnit.displayName } else { "administrativeUnits[$K]" }
                Add-Finding -Section 'groups' -Item $RestrictedItem -Path "groups[$I]" -Severity 'Warning' `
                    -Message ("$RestrictedLabel declares PIM for Groups settings (an eligibility or a pimPolicy), and administrativeUnits[$K] ('$RestrictedUnitName'), " +
                        "a restricted management unit, lists the group in its members as '$ListedAs'. $RestrictedRisk")
            }
        }
    }

    # Rule 17 (Sprint 11 step 7, A6): the names of the sections the naming standard lists, against the
    # standard. Runs only when -NamingStandard is given (Test-OERStructure passes it; Invoke-OERStructure
    # never does), after every other rule, so a document that is invalid without it keeps exactly its
    # findings and the naming Warnings follow them. Every finding is a Warning -- a name is advice, not a
    # reason to refuse a document -- and Test-OERNamingStandardName owns the rules and the texts. The name
    # checked is the one the object carries after the step: displayName, or for a group without
    # displayName and with a template the name Get-GroupEntryName computes (Rule 12's reading). A
    # previousDisplayName is never read. A node that is not the shape it should be (a section that is not
    # an array, an item that is not an object, a displayName that is not a non-empty string) adds no row:
    # the rules above already report what is wrong with it, and the walk must not stop on it.
    function Get-NamingItem {
        param([object]$Node, [string]$Name)
        if ((Test-HasProp -Node $Node -Name $Name) -and
            ($Node.$Name -is [System.Collections.IEnumerable]) -and ($Node.$Name -isnot [string])) {
            return , @($Node.$Name)
        }
        , @()
    }

    # One name against the standard: a Warning per broken rule at -Path. A synced group (-Synced) is
    # skipped with one Warning that says so unless the standard includes synced groups; when it does, each
    # finding says where the name can be changed.
    function Add-NamingFinding {
        param([string]$Section, [string]$Name, [string]$Path, [bool]$Synced = $false)
        if ($Synced -and -not $NamingStandard.IncludeSyncedGroups) {
            Add-Finding -Section $Section -Item $Name -Path $Path -Severity 'Warning' `
                -Message ("Name '$Name' at $Path was not checked against the naming standard: the group is synchronized from on-premises " +
                    '(onPremisesSynced true), and the standard does not include synced groups. Set includeSyncedGroups to true to check it.')
            return
        }
        $SyncedClause = ''
        if ($Synced) {
            $SyncedClause = ' The group is synchronized from on-premises (onPremisesSynced true), and Invoke-OERStructure writes nothing to it: change its name in the on-premises directory.'
        }
        foreach ($NameFinding in @(Test-OERNamingStandardName -Name $Name -Standard $NamingStandard)) {
            $SegmentClause = ''
            if ($null -ne $NameFinding.Segment) { $SegmentClause = ", segment $($NameFinding.Segment) '$($NameFinding.SegmentName)'" }
            Add-Finding -Section $Section -Item $Name -Path $Path -Severity 'Warning' `
                -Message "Name '$Name' at $Path does not follow the naming standard (rule '$($NameFinding.Rule)'$SegmentClause): $($NameFinding.Detail)$SyncedClause"
        }
    }

    # The displayName of one node, when it is a non-empty string, checked at -Path (the node's own path).
    # -Section is the name the finding carries.
    function Add-NamingDisplayNameFinding {
        param([string]$Section, [string]$Path, [object]$Node)
        if (-not (Test-HasProp -Node $Node -Name 'displayName')) { return }
        $DisplayName = $Node.displayName
        if ($DisplayName -isnot [string] -or $DisplayName.Length -eq 0) { return }
        Add-NamingFinding -Section $Section -Name $DisplayName -Path "$Path.displayName"
    }

    # Every item of a top-level section that carries a displayName.
    function Add-NamingSectionFinding {
        param([string]$Section)
        $Items = Get-NamingItem -Node $Document -Name $Section
        for ($I = 0; $I -lt $Items.Count; $I++) {
            Add-NamingDisplayNameFinding -Section $Section -Path "$Section[$I]" -Node $Items[$I]
        }
    }

    if ($null -ne $NamingStandard) {
        $NamingSections = @($NamingStandard.Sections)

        if ($NamingSections -ccontains 'groups') {
            $NamingGroups = Get-NamingItem -Node $Document -Name 'groups'
            for ($I = 0; $I -lt $NamingGroups.Count; $I++) {
                $NamingGroup = $NamingGroups[$I]
                $NamingSynced = (Test-HasProp -Node $NamingGroup -Name 'onPremisesSynced') -and
                    ($NamingGroup.onPremisesSynced -is [bool]) -and $NamingGroup.onPremisesSynced
                if (Test-HasProp -Node $NamingGroup -Name 'displayName') {
                    $GroupDisplayName = $NamingGroup.displayName
                    if ($GroupDisplayName -is [string] -and $GroupDisplayName.Length -gt 0) {
                        Add-NamingFinding -Section 'groups' -Name $GroupDisplayName -Path "groups[$I].displayName" -Synced $NamingSynced
                    }
                    continue
                }
                if ((Test-HasProp -Node $NamingGroup -Name 'template') -and
                    ($NamingGroup.template -is [string]) -and $NamingGroup.template.Length -gt 0) {
                    $TemplateName = Get-GroupEntryName -Group $NamingGroup
                    if ([string]::IsNullOrEmpty($TemplateName)) {
                        Add-Finding -Section 'groups' -Item "groups[$I]" -Path "groups[$I].template" -Severity 'Warning' `
                            -Message "Group at groups[$I].template was not checked against the naming standard: its name could not be computed from 'template' and 'tokens'."
                        continue
                    }
                    Add-NamingFinding -Section 'groups' -Name $TemplateName -Path "groups[$I].template" -Synced $NamingSynced
                }
            }
        }

        foreach ($NamingSection in 'administrativeUnits', 'catalogs') {
            if ($NamingSections -ccontains $NamingSection) { Add-NamingSectionFinding -Section $NamingSection }
        }

        # An access package, then its own assignment policies, so the findings follow the document. The
        # policies are walked for a standard that lists assignmentPolicies alone as well.
        if (($NamingSections -ccontains 'accessPackages') -or ($NamingSections -ccontains 'assignmentPolicies')) {
            $NamingPackages = Get-NamingItem -Node $Document -Name 'accessPackages'
            for ($I = 0; $I -lt $NamingPackages.Count; $I++) {
                if ($NamingSections -ccontains 'accessPackages') {
                    Add-NamingDisplayNameFinding -Section 'accessPackages' -Path "accessPackages[$I]" -Node $NamingPackages[$I]
                }
                if ($NamingSections -ccontains 'assignmentPolicies') {
                    $NamingPolicies = Get-NamingItem -Node $NamingPackages[$I] -Name 'assignmentPolicies'
                    for ($K = 0; $K -lt $NamingPolicies.Count; $K++) {
                        Add-NamingDisplayNameFinding -Section 'accessPackages' -Path "accessPackages[$I].assignmentPolicies[$K]" -Node $NamingPolicies[$K]
                    }
                }
            }
        }

        if ($NamingSections -ccontains 'accessReviews') { Add-NamingSectionFinding -Section 'accessReviews' }
    }

    $Out = [PSCustomObject]@{
        Valid  = -not ($Findings | Where-Object { $_.Severity -eq 'Error' })
        Errors = @($Findings)
    }
    $Out.PSObject.TypeNames.Insert(0, 'Omnicit.EntraRBAC.StructureValidation')
    $Out
}
