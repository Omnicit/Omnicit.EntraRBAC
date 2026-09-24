function Test-OERStructureSchema {
    <#
    .SYNOPSIS
    Validates an orchestration document offline and returns a tagged validation result.

    .DESCRIPTION
    Performs the shared, tenant-free schema validation used by both Test-OERStructure and
    Invoke-OERStructure. Checks the required version key, rejects unknown top-level keys, requires each
    present section to be an array, and validates the per-item shape of every section (required fields,
    enum values (including eligibility accessType member/owner and membershipRuleProcessingState On/Paused, shared by administrative units and groups), mutually exclusive displayName/template, numeric ranges). A catalog's externallyVisible must be a boolean. A roleAssignments
    item's conditionVersion without a condition is an Error (a version alone has no effect); a condition
    without a conditionVersion is a Warning (Azure Resource Manager defaults it to 2.0). A catalog
    resource's url, when present, must be a non-empty string (Error); a SharePointSite resource with
    neither a url nor a URL-shaped name is a Warning, since the site cannot be onboarded from a
    display name alone. Intra-document
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
    enforces it here. An unknown per-item key in the roleAssignments or roleManagementPolicies section
    is reported as a Warning naming the key, because the apply handlers for those two sections read a
    fixed field list and would otherwise drop it silently. Other sections keep accepting unknown keys
    without comment. An accessPackages assignmentPolicies entry declaring requireApproval true together
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
    principalType) is accepted in any casing, but a non-canonically cased value is reported as a
    Warning naming the canonical spelling Get-OERStructureSchemaJson declares, because draft-07 matches
    "enum" case-sensitively. An accessReviews item validates reviewers/fallbackReviewers as string arrays,
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
    self review needs no fallback. A groups[] entry declaring a non-empty administrativeUnit whose
    matching administrativeUnits[] entry (by displayName, case-insensitively) exists in the same
    document but does not name the group in its members is a Warning (issue #59): administrativeUnit
    is applied only when the group is created and never round-trips, so without the reciprocal members
    entry -Prune removes the membership in the SAME apply run -- Invoke-OERStructure dispatches
    administrativeUnits after groups, so the create and the prune happen in one call -- and again on
    every later apply, and nothing self-heals it. Nothing is reported when the referenced unit is not
    declared in the document (it may be managed elsewhere), when the unit declares members as an
    explicit null (the documented signal that skips reconciling that collection entirely), or when
    the group is template-based (its real displayName is
    computed by the naming engine at apply time and cannot be resolved offline). An OMITTED
    groups[].members, administrativeUnits[].members, administrativeUnits[].scopedRoles,
    catalogs[].resources or accessPackages[].resourceRoles key is a Warning naming the collection:
    each of those is still reconciled against an empty declared set when its key is omitted, so
    Invoke-OERStructure -Prune removes every live entry in it. Get-OEROmittedPruneCollection owns
    which keys those are; an explicit null (the "leave it untouched" signal), a declared array (an
    empty one included) and the members of a group or unit declared "dynamic": true are not
    reported. The exclusion trusts the document's dynamic flag: a group declared dynamic whose live
    group is static (Set-OERGroup cannot convert it), or an administrative unit whose conversion to
    dynamic is not applied in this run (-WhatIf, a declined prompt, a failed update, or no
    membershipRule available), still has its omitted members pruned, and is not reported. Returns a tagged Omnicit.EntraRBAC.StructureValidation object with a Valid flag and an
    Errors collection of records carrying Section, Item, Path, Message, and Severity. No Graph or ARM
    calls are made and no authentication occurs.
    .PARAMETER Document
    The parsed document object (from Read-OERStructureDocument or ConvertFrom-Json) to validate.
    .EXAMPLE
    Test-OERStructureSchema -Document ($json | ConvertFrom-Json)
    Returns a StructureValidation describing any schema problems in the document.
    #>
    [OutputType([PSCustomObject])]
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][PSCustomObject]$Document
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
    # existing document starts failing) in the two Azure Resource Manager sections, where the apply
    # handlers read a fixed field list and ignore everything else.
    function Add-UnknownKeyWarning {
        param([object]$Node, [string]$Section, [string]$Item, [string]$Path, [string[]]$KnownKey)
        if ($null -eq $Node) { return }
        foreach ($Key in $Node.PSObject.Properties.Name) {
            if ($KnownKey -inotcontains $Key) {
                Add-Finding -Section $Section -Item $Item -Path "$Path.$Key" `
                    -Message "Unknown key '$Key' at $Path is not applied by Invoke-OERStructure and will be ignored." `
                    -Severity 'Warning'
            }
        }
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

    $KnownTop = @('version', 'tenantAlias', 'groups', 'administrativeUnits', 'catalogs',
        'accessPackages', 'accessReviews', 'roleAssignments', 'roleManagementPolicies')

    # Rule 1: version must be present and a non-empty string
    if (-not (Test-HasProp -Node $Document -Name 'version') -or
        [string]::IsNullOrEmpty($Document.version)) {
        Add-Finding -Section '(root)' -Item 'version' -Path 'version' `
            -Message 'Required key "version" is missing or empty.'
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
            for ($I = 0; $I -lt $Groups.Count; $I++) {
                $G = $Groups[$I]
                $GPath = "groups[$I]"
                $HasDN = Test-HasProp -Node $G -Name 'displayName'
                $HasTpl = Test-HasProp -Node $G -Name 'template'
                $GItem = if ($HasDN) { $G.displayName } else { "groups[$I]" }

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

                foreach ($GStringProp in @('mailNickname', 'administrativeUnit')) {
                    if (Test-HasProp -Node $G -Name $GStringProp) {
                        if ($G.$GStringProp -isnot [string]) {
                            Add-Finding -Section 'groups' -Item $GItem -Path "$GPath.$GStringProp" `
                                -Message "'$GStringProp' at $GPath must be a string."
                        }
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
                    $HasFlat   = (Test-HasProp -Node $Pp -Name 'activationMaxHours') -or
                                 (Test-HasProp -Node $Pp -Name 'authenticationContextId') -or
                                 (Test-HasProp -Node $Pp -Name 'allowPermanentEligibility')

                    if (($HasMember -or $HasOwner) -and $HasFlat) {
                        Add-Finding -Section 'groups' -Item $GItem -Path "$GPath.pimPolicy" `
                            -Message "pimPolicy at $GPath mixes flat and nested (member/owner) forms; the flat fields are ignored." `
                            -Severity 'Warning'
                    }

                    if ($HasMember) { & $ValidatePimBlock $Pp.member "$GPath.pimPolicy.member" }
                    if ($HasOwner)  { & $ValidatePimBlock $Pp.owner  "$GPath.pimPolicy.owner" }
                    if (-not $HasMember -and -not $HasOwner) { & $ValidatePimBlock $Pp "$GPath.pimPolicy" }
                }
            }
        }
    }

    # Rule 5: administrativeUnits
    if (Test-HasProp -Node $Document -Name 'administrativeUnits') {
        if (Test-SectionIsArray -SectionName 'administrativeUnits') {
            $AUs = @($Document.administrativeUnits)
            for ($I = 0; $I -lt $AUs.Count; $I++) {
                $AU = $AUs[$I]
                $AUPath = "administrativeUnits[$I]"
                $AUItem = if (Test-HasProp -Node $AU -Name 'displayName') { $AU.displayName } else { "administrativeUnits[$I]" }

                if (-not (Test-HasProp -Node $AU -Name 'displayName')) {
                    Add-Finding -Section 'administrativeUnits' -Item $AUItem -Path $AUPath `
                        -Message "'displayName' is required at $AUPath."
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
                            }
                            if (-not (Test-HasProp -Node $SR -Name 'principal')) {
                                Add-Finding -Section 'administrativeUnits' -Item $AUItem `
                                    -Path "$SRPath.principal" `
                                    -Message "'principal' is required at $SRPath."
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
            for ($I = 0; $I -lt $Cats.Count; $I++) {
                $Cat = $Cats[$I]
                $CatPath = "catalogs[$I]"
                $CatItem = if (Test-HasProp -Node $Cat -Name 'displayName') { $Cat.displayName } else { "catalogs[$I]" }

                if (-not (Test-HasProp -Node $Cat -Name 'displayName')) {
                    Add-Finding -Section 'catalogs' -Item $CatItem -Path $CatPath `
                        -Message "'displayName' is required at $CatPath."
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
                            }
                            if (-not (Test-HasProp -Node $RR -Name 'role')) {
                                Add-Finding -Section 'accessPackages' -Item $APItem `
                                    -Path "$RRPath.role" `
                                    -Message "'role' is required at $RRPath."
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
                        for ($J = 0; $J -lt $Pols.Count; $J++) {
                            $Pol = $Pols[$J]
                            $PolPath = "$APPath.assignmentPolicies[$J]"
                            if (-not (Test-HasProp -Node $Pol -Name 'displayName')) {
                                Add-Finding -Section 'accessPackages' -Item $APItem `
                                    -Path "$PolPath.displayName" `
                                    -Message "'displayName' is required at $PolPath."
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

    # Rule 9: roleAssignments
    if (Test-HasProp -Node $Document -Name 'roleAssignments') {
        if (Test-SectionIsArray -SectionName 'roleAssignments') {
            $RAs = @($Document.roleAssignments)
            for ($I = 0; $I -lt $RAs.Count; $I++) {
                $RA = $RAs[$I]
                $RAPath = "roleAssignments[$I]"
                $RAItem = if (Test-HasProp -Node $RA -Name 'role') { $RA.role } else { "roleAssignments[$I]" }

                Add-UnknownKeyWarning -Node $RA -Section 'roleAssignments' -Item $RAItem -Path $RAPath `
                    -KnownKey @('scope', 'role', 'principal', 'principalType', 'description',
                        'condition', 'conditionVersion', 'id')

                foreach ($Req in @('scope', 'role', 'principal')) {
                    if (-not (Test-HasProp -Node $RA -Name $Req)) {
                        Add-Finding -Section 'roleAssignments' -Item $RAItem `
                            -Path "$RAPath.$Req" `
                            -Message "'$Req' is required at $RAPath."
                    }
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

    # Rule 10: roleManagementPolicies
    if (Test-HasProp -Node $Document -Name 'roleManagementPolicies') {
        if (Test-SectionIsArray -SectionName 'roleManagementPolicies') {
            $RMPs = @($Document.roleManagementPolicies)
            for ($I = 0; $I -lt $RMPs.Count; $I++) {
                $RMP = $RMPs[$I]
                $RMPPath = "roleManagementPolicies[$I]"
                $RMPItem = if (Test-HasProp -Node $RMP -Name 'role') { $RMP.role } else { "roleManagementPolicies[$I]" }

                Add-UnknownKeyWarning -Node $RMP -Section 'roleManagementPolicies' -Item $RMPItem -Path $RMPPath `
                    -KnownKey @('scope', 'role', 'allowPermanentEligibility', 'eligibleDurationDays',
                        'allowPermanentActiveAssignment', 'activeDurationDays', 'activationMaxHours',
                        'requireMfaOnActivation', 'requireJustificationOnActivation',
                        'requireTicketOnActivation', 'requireApproval', 'approvers',
                        'authenticationContextId', 'requireMfaOnActiveAssignment',
                        'requireJustificationOnActiveAssignment', 'id')

                foreach ($Req in @('scope', 'role')) {
                    if (-not (Test-HasProp -Node $RMP -Name $Req)) {
                        Add-Finding -Section 'roleManagementPolicies' -Item $RMPItem `
                            -Path "$RMPPath.$Req" `
                            -Message "'$Req' is required at $RMPPath."
                    }
                }

                foreach ($RmpBoolProp in @('allowPermanentEligibility', 'allowPermanentActiveAssignment',
                        'requireMfaOnActivation', 'requireJustificationOnActivation',
                        'requireTicketOnActivation', 'requireApproval',
                        'requireMfaOnActiveAssignment', 'requireJustificationOnActiveAssignment')) {
                    if (Test-HasProp -Node $RMP -Name $RmpBoolProp) {
                        if ($RMP.$RmpBoolProp -isnot [bool]) {
                            Add-Finding -Section 'roleManagementPolicies' -Item $RMPItem `
                                -Path "$RMPPath.$RmpBoolProp" `
                                -Message "'$RmpBoolProp' at $RMPPath must be a boolean."
                        }
                    }
                }

                if (Test-HasProp -Node $RMP -Name 'activationMaxHours') {
                    if (-not (Test-IsInt -Value $RMP.activationMaxHours -Min 1 -Max 24)) {
                        Add-Finding -Section 'roleManagementPolicies' -Item $RMPItem `
                            -Path "$RMPPath.activationMaxHours" `
                            -Message "'activationMaxHours' at $RMPPath must be an integer between 1 and 24."
                    }
                }

                foreach ($RmpDurProp in @('eligibleDurationDays', 'activeDurationDays')) {
                    if (Test-HasProp -Node $RMP -Name $RmpDurProp) {
                        if (-not (Test-IsInt -Value $RMP.$RmpDurProp -Min 1 -Max 3650)) {
                            Add-Finding -Section 'roleManagementPolicies' -Item $RMPItem `
                                -Path "$RMPPath.$RmpDurProp" `
                                -Message "'$RmpDurProp' at $RMPPath must be an integer between 1 and 3650."
                        }
                    }
                }

                # Approvers only take effect when approval is required. Resolve-OERPolicyRulePatch sets
                # isApprovalRequired = true unconditionally whenever approvers are sent, so the apply
                # engine drops the approvers rather than silently re-enabling approval on a policy the
                # document says must have it off. Warn (never Error -- such a document is still valid,
                # and Get-OERInventory itself can produce one) so the precedence is visible up front.
                if ((Test-HasProp -Node $RMP -Name 'requireApproval') -and ($RMP.requireApproval -eq $false)) {
                    $DeclaredApproverCount = 0
                    foreach ($ApproverKind in @('users', 'groups')) {
                        if (Test-HasProp -Node $RMP.approvers -Name $ApproverKind) {
                            $DeclaredApproverCount += @($RMP.approvers.$ApproverKind).Count
                        }
                    }
                    if ($DeclaredApproverCount -gt 0) {
                        Add-Finding -Section 'roleManagementPolicies' -Item $RMPItem `
                            -Path "$RMPPath.approvers" `
                            -Message "'requireApproval' is false at $RMPPath, so the declared 'approvers' are ignored; requireApproval takes precedence and the approvers are not written. Set 'requireApproval' to true to apply them, or drop the approvers block." `
                            -Severity 'Warning'
                    }
                }

                if (Test-HasProp -Node $RMP -Name 'approvers') {
                    $Approvers = $RMP.approvers
                    if ($Approvers -isnot [PSCustomObject]) {
                        Add-Finding -Section 'roleManagementPolicies' -Item $RMPItem `
                            -Path "$RMPPath.approvers" `
                            -Message "'approvers' at $RMPPath must be an object with optional users and groups arrays."
                    } else {
                        foreach ($ApproverKind in @('users', 'groups')) {
                            if (Test-HasProp -Node $Approvers -Name $ApproverKind) {
                                $ApproverVal = $Approvers.$ApproverKind
                                if ($ApproverVal -isnot [System.Collections.IEnumerable] -or $ApproverVal -is [string]) {
                                    Add-Finding -Section 'roleManagementPolicies' -Item $RMPItem `
                                        -Path "$RMPPath.approvers.$ApproverKind" `
                                        -Message "'approvers.$ApproverKind' at $RMPPath must be an array."
                                }
                            }
                        }
                    }
                }

                # An empty string is the documented "disable the authentication context" value; any
                # other non-c<digits> value is rejected by Set-OERRoleManagementPolicy at runtime, so
                # catch it offline instead.
                if (Test-HasProp -Node $RMP -Name 'authenticationContextId') {
                    $AuthCtx = [string]$RMP.authenticationContextId
                    if ($AuthCtx -and $AuthCtx -notmatch '^c\d+$') {
                        Add-Finding -Section 'roleManagementPolicies' -Item $RMPItem `
                            -Path "$RMPPath.authenticationContextId" `
                            -Message "'authenticationContextId' at $RMPPath must look like 'c1', or be an empty string to disable it. Got: '$AuthCtx'."
                    }
                    # Azure PIM treats MFA on activation and an authentication context as mutually
                    # exclusive; asking for both in one apply is rejected by ARM, so fail offline.
                    if ($AuthCtx -and (Test-HasProp -Node $RMP -Name 'requireMfaOnActivation') -and
                        ($RMP.requireMfaOnActivation -eq $true)) {
                        Add-Finding -Section 'roleManagementPolicies' -Item $RMPItem `
                            -Path $RMPPath `
                            -Message "'requireMfaOnActivation' and 'authenticationContextId' at $RMPPath are mutually exclusive in Azure PIM; declare only one."
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
        if ((Test-HasProp -Node $Document -Name 'catalogs') -and
            ($Document.catalogs -is [System.Collections.IEnumerable]) -and
            ($Document.catalogs -isnot [string])) {
            $DeclaredCatalogs = @($Document.catalogs | Where-Object {
                Test-HasProp -Node $_ -Name 'displayName'
            } | ForEach-Object { $_.displayName })
        }

        $APArr = @($Document.accessPackages)
        for ($I = 0; $I -lt $APArr.Count; $I++) {
            $AP = $APArr[$I]
            if (Test-HasProp -Node $AP -Name 'catalog') {
                $CatRef = $AP.catalog
                if ($DeclaredCatalogs -inotcontains $CatRef) {
                    $APItem = if (Test-HasProp -Node $AP -Name 'displayName') { $AP.displayName } else { "accessPackages[$I]" }
                    Add-Finding -Section 'accessPackages' -Item $APItem `
                        -Path "accessPackages[$I].catalog" `
                        -Message "Catalog '$CatRef' is not declared in this document. It may already exist in the tenant." `
                        -Severity 'Warning'
                }
            }
        }
    }

    # Rule 12: cross-reference warning -- groups[].administrativeUnit placement (issue #59)
    #
    # administrativeUnit on a group is create-path only (Sync-OERStructureGroup) and never round-trips,
    # so the ONLY way a document keeps a group inside a unit across repeated applies is by also naming
    # the group in that unit's own administrativeUnits[].members. Without it, Sync-OERStructureAdministrativeUnit
    # sees an undeclared member and, under -Prune, removes the very membership the groups section just
    # created -- in the SAME apply run, not merely a later one: Invoke-OERStructure's hardcoded section
    # order is groups -> administrativeUnits, New-OERGroup -AdministrativeUnit creates the group
    # straight into the unit (POST .../administrativeUnits/{id}/members), and the -EnsureOnly pre-pass
    # reconciles no members. Every later apply repeats it, and nothing here self-heals it, since the
    # create-only field never fires again once the group exists. This is a Warning, never an Error (spec Foerhandsbeslut
    # option A+B, not C): the prune pass itself deliberately stays independent of the groups section, so
    # this validator only documents the trap offline rather than reaching into that handler's logic.
    if ((Test-HasProp -Node $Document -Name 'groups') -and
        ($Document.groups -is [System.Collections.IEnumerable]) -and
        ($Document.groups -isnot [string]) -and
        (Test-HasProp -Node $Document -Name 'administrativeUnits') -and
        ($Document.administrativeUnits -is [System.Collections.IEnumerable]) -and
        ($Document.administrativeUnits -isnot [string])) {

        $AuPlacementUnits = @($Document.administrativeUnits)
        $AuPlacementGroups = @($Document.groups)
        for ($I = 0; $I -lt $AuPlacementGroups.Count; $I++) {
            $PGroup = $AuPlacementGroups[$I]
            if (-not (Test-HasProp -Node $PGroup -Name 'administrativeUnit')) { continue }
            $PAuName = [string]$PGroup.administrativeUnit
            if ([string]::IsNullOrEmpty($PAuName)) { continue }

            # A template-based group's real displayName is produced by Resolve-OERName at apply time
            # (token substitution); this offline validator has no naming engine to compute it against
            # and cannot resolve the eventual name, so it emits nothing here rather than risk a false
            # positive against the raw template placeholder text.
            if (-not (Test-HasProp -Node $PGroup -Name 'displayName')) { continue }
            $PGroupName = [string]$PGroup.displayName

            $PMatchedAuIndex = -1
            for ($K = 0; $K -lt $AuPlacementUnits.Count; $K++) {
                if ((Test-HasProp -Node $AuPlacementUnits[$K] -Name 'displayName') -and
                    ([string]$AuPlacementUnits[$K].displayName -ieq $PAuName)) {
                    $PMatchedAuIndex = $K
                    break
                }
            }
            # No administrativeUnits[] entry for this unit in the SAME document: the unit is managed
            # elsewhere (or already exists in the tenant with this group already a member), and this
            # document makes no claim about its membership either way.
            if ($PMatchedAuIndex -lt 0) { continue }
            $PMatchedAu = $AuPlacementUnits[$PMatchedAuIndex]

            # An explicit null on the unit's members is the documented "hands off" signal
            # (Test-OERDeclaredNull): Sync-OERStructureAdministrativeUnit skips the whole
            # reconcile/prune pass for that collection, so no undeclared-member removal can happen.
            if (Test-OERDeclaredNull -Node $PMatchedAu -Name 'members') { continue }

            # An OMITTED members key is not the same signal -- it still reconciles (against an empty
            # declared set) and still prunes, so it is read here as an empty list, not skipped.
            $PAuMembers = if (Test-HasProp -Node $PMatchedAu -Name 'members') { @($PMatchedAu.members) } else { @() }
            $PGroupIsNamed = @($PAuMembers | Where-Object { [string]$_ -ieq $PGroupName }).Count -gt 0
            if (-not $PGroupIsNamed) {
                $PGPath = "groups[$I]"
                Add-Finding -Section 'groups' -Item $PGroupName -Path "$PGPath.administrativeUnit" -Severity 'Warning' `
                    -Message ("Group '$PGroupName' at $PGPath declares administrativeUnit '$PAuName', but " +
                        "administrativeUnits[$PMatchedAuIndex].members does not list '$PGroupName'. " +
                        'administrativeUnit is applied only when the group is created and never round-trips, ' +
                        "so unless this document's administrativeUnits[$PMatchedAuIndex] entry also names the " +
                        'group in members, -Prune removes the membership the create just added in the SAME ' +
                        'apply run -- the administrativeUnits section is dispatched after groups -- and again ' +
                        'on every later apply.')
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

    $Out = [PSCustomObject]@{
        Valid  = -not ($Findings | Where-Object { $_.Severity -eq 'Error' })
        Errors = @($Findings)
    }
    $Out.PSObject.TypeNames.Insert(0, 'Omnicit.EntraRBAC.StructureValidation')
    $Out
}
