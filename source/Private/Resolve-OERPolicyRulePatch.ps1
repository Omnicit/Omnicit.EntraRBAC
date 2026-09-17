function Resolve-OERPolicyRulePatch {
    <#
    .SYNOPSIS
    Overlays the supplied PIM policy settings onto the current rules and returns the full updated set.

    .DESCRIPTION
    The read-modify-write engine for Set-OERRoleManagementPolicy (the ARM analogue of the from-scratch
    New-OERPimRuleSet). For each supplied setting it locates the current rule by its stable id,
    clones it (a JSON round-trip so the original is never mutated and target/ruleType/id and sibling
    fields are preserved), and overlays only the changed field(s). Enablement toggles (MFA /
    justification / ticketing) compose on the shared rule. At assembly time each touched clone is
    compared, field by field, against the rule it was cloned from (Test-RuleEquivalent); a clone that
    ends up materially identical to its source -- for example a caller re-asserting a value the policy
    already has -- is dropped back to the original rule object and its id is left out of
    ChangedRuleId, so a genuine no-op never triggers an ARM write. It returns a single object with two
    members: Rules -- the COMPLETE rules set in original order (genuinely changed rules replaced by
    their modified clones, everything else -- including a touched-but-unchanged rule -- passed through
    as the original) -- and ChangedRuleId -- the ids that actually changed. The full set is returned
    because ARM's roleManagementPolicies PATCH validates the submitted rules as a whole and rejects a
    partial array on a default policy with "InvalidPolicy"; sending the complete set is the
    verified-working shape, and returning one object (not a bare array) avoids array-unwrap nesting at
    the call site. Pure in-memory; no network or state change.

    .PARAMETER CurrentRule
    The policy's current rules array (from a GET of the policy).

    .PARAMETER Setting
    A hashtable of the supplied settings. Recognized keys: ActivationMaxHours, RequireMfaOnActivation,
    RequireJustificationOnActivation, RequireTicketOnActivation, RequireApproval, PrimaryApprovers
    (resolved approver objects), AuthenticationContextId, AllowPermanentEligibility, EligibleDuration,
    AllowPermanentActiveAssignment, ActiveDuration, RequireMfaOnActiveAssignment,
    RequireJustificationOnActiveAssignment, NotificationRule (builder objects).
    PrimaryApprovers must already be resolved approver objects ({ id; userType; isBackup }) -- the
    caller resolves names via Resolve-OERPrincipal. EligibleDuration and ActiveDuration each accept
    either a whole day count (for example 365) or a raw ISO 8601 duration (for example 'P365D'),
    normalized through Resolve-OERDurationInput so a day count from an apply document and an ISO
    string read back from Get-OERRoleManagementPolicy both work.

    .EXAMPLE
    Resolve-OERPolicyRulePatch -CurrentRule $Rules -Setting @{ AllowPermanentEligibility = $true }
    Returns an object whose Rules is the full set with Expiration_Admin_Eligibility.isExpirationRequired
    set to false, and whose ChangedRuleId is @('Expiration_Admin_Eligibility').
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '',
        Justification = 'Pure in-memory rule-overlay builder; returns an object and performs no state change, so ShouldProcess does not apply.')]
    [OutputType([PSCustomObject])]
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [object[]]$CurrentRule,

        [Parameter(Mandatory)]
        [hashtable]$Setting
    )

    # Index the current rules by id.
    $ById = @{}
    foreach ($Rule in $CurrentRule) { if ($Rule.id) { $ById[[string]$Rule.id] = $Rule } }

    # Cache of clones keyed by rule id (the set of rules that will be returned).
    $Touched = @{}

    # Nested helper: get (and cache) an independent clone of a rule by id. Throws if the rule is
    # absent. Takes everything via named parameters so nothing relies on closure-captured outer
    # locals (which PSReviewUnusedParameter cannot follow into nested functions).
    function Get-RuleClone ([hashtable]$Source, [hashtable]$Cache, [string]$Id) {
        if ($Cache.ContainsKey($Id)) { return $Cache[$Id] }
        if (-not $Source.ContainsKey($Id)) { throw "The policy has no '$Id' rule to update." }
        $Clone = $Source[$Id] | ConvertTo-Json -Depth 100 | ConvertFrom-Json
        $Cache[$Id] = $Clone
        $Clone
    }

    # Nested helper: return a new enabledRules array with $Flag added or removed.
    function Get-ToggledList ([object]$List, [string]$Flag, [bool]$On) {
        $Set = [System.Collections.Generic.List[string]]::new()
        foreach ($Entry in @($List)) { if ($Entry) { $Set.Add([string]$Entry) } }
        if ($On -and -not $Set.Contains($Flag)) { $Set.Add($Flag) }
        elseif (-not $On -and $Set.Contains($Flag)) { [void]$Set.Remove($Flag) }
        , $Set.ToArray()
    }

    # Nested helper: set a property on a (cloned) rule object, ADDING it when the source policy
    # omitted it. A default/uncustomized policy leaves optional fields off the object entirely (no
    # claimValue, no notificationRecipients, no primaryApprovers), so a plain assignment throws
    # "The property ... cannot be found". Add-Member -Force adds-or-replaces uniformly. ("Add" is a
    # non-state-changing verb so the nested function needs no ShouldProcess.)
    function Add-RuleField ([object]$Object, [string]$Name, [object]$Value) {
        $Object | Add-Member -NotePropertyName $Name -NotePropertyValue $Value -Force
    }

    # Nested helpers for value-aware change detection (used at assembly time below): is a touched
    # clone materially identical to the rule it was cloned from? A caller re-asserting a value the
    # policy already has must not produce an ARM write, a misleading -WhatIf line, or an over-stated
    # ChangedRuleId. Get-RuleFieldName/-Value read property names/values from EITHER a PSCustomObject
    # (ConvertFrom-Json's default shape, which is what both the clone and a rule read from ARM/Graph
    # normally are) or a hashtable, because PSObject.Properties does not enumerate hashtable keys --
    # relying on it alone would silently compare nothing and report everything as equal. Test-RuleEquivalent
    # recurses field by field over the union of both sides' property names so a difference nested under
    # .setting or .approvalStages is still caught, applying the comparison BY FIELD NAME wherever it
    # occurs: maximumDuration/claimValue compare ordinally case-insensitive; isExpirationRequired/
    # isEnabled/isApprovalRequired/isDefaultRecipientsEnabled compare as [bool]; enabledRules and
    # notificationRecipients compare as order-insensitive string sets; primaryApprovers and
    # escalationApprovers compare as order-insensitive sets keyed on approver id (ARM does not preserve
    # the order of any of these). Every other array compares element by element in order; every other
    # object recurses; every other scalar compares with -eq.
    function Get-RuleFieldName ([object]$Rule) {
        if ($null -eq $Rule) { return @() }
        if ($Rule -is [System.Collections.IDictionary]) { return @($Rule.Keys) }
        return @($Rule.PSObject.Properties.Name)
    }

    function Get-RuleFieldValue ([object]$Rule, [string]$Name) {
        if ($null -eq $Rule) { return $null }
        if ($Rule -is [System.Collections.IDictionary]) { return $Rule[$Name] }
        $Prop = $Rule.PSObject.Properties[$Name]
        if ($Prop) { return $Prop.Value }
        return $null
    }

    function Test-StringSetEqual ([object[]]$Left, [object[]]$Right) {
        $LeftSorted = @(@($Left) | Where-Object { $null -ne $_ } | ForEach-Object { [string]$_ } | Sort-Object)
        $RightSorted = @(@($Right) | Where-Object { $null -ne $_ } | ForEach-Object { [string]$_ } | Sort-Object)
        if ($LeftSorted.Count -ne $RightSorted.Count) { return $false }
        for ($Index = 0; $Index -lt $LeftSorted.Count; $Index++) {
            if ($LeftSorted[$Index] -ne $RightSorted[$Index]) { return $false }
        }
        return $true
    }

    function Test-ApproverSetEqual ([object[]]$Left, [object[]]$Right) {
        $Describe = { param($Approver) ('{0}|{1}|{2}' -f [string](Get-RuleFieldValue $Approver 'id'), [string](Get-RuleFieldValue $Approver 'userType'), [bool](Get-RuleFieldValue $Approver 'isBackup')) }
        $LeftSorted = @(@($Left) | Where-Object { $null -ne $_ } | ForEach-Object { & $Describe $_ } | Sort-Object)
        $RightSorted = @(@($Right) | Where-Object { $null -ne $_ } | ForEach-Object { & $Describe $_ } | Sort-Object)
        if ($LeftSorted.Count -ne $RightSorted.Count) { return $false }
        for ($Index = 0; $Index -lt $LeftSorted.Count; $Index++) {
            if ($LeftSorted[$Index] -ne $RightSorted[$Index]) { return $false }
        }
        return $true
    }

    function Test-RuleEquivalent ([object]$Left, [object]$Right) {
        if ($null -eq $Left -and $null -eq $Right) { return $true }
        if ($null -eq $Left -or $null -eq $Right) { return $false }

        if ($Left -is [array] -or $Left -is [System.Collections.IList]) {
            $LeftItem = @($Left)
            $RightItem = @($Right)
            if ($LeftItem.Count -ne $RightItem.Count) { return $false }
            for ($Index = 0; $Index -lt $LeftItem.Count; $Index++) {
                if (-not (Test-RuleEquivalent -Left $LeftItem[$Index] -Right $RightItem[$Index])) { return $false }
            }
            return $true
        }

        $IsComplex = ($Left -is [System.Collections.IDictionary]) -or ($Left -is [System.Management.Automation.PSCustomObject])
        if (-not $IsComplex) {
            # A hand-built rule (as every test in this suite constructs one) holds native PowerShell
            # [int] literals, while the SAME value on the clone has been through ConvertTo-Json |
            # ConvertFrom-Json and comes back as [long]. [object]::Equals on two different boxed value
            # types returns $false even when the numbers are equal, which would misreport an untouched
            # numeric field (for example an approval stage's escalationTimeInMinutes) as changed.
            # Compare numerically-typed scalars (excluding [bool], which is its own IsComplex-adjacent
            # case handled by name above and must never widen to a number) as [double]; everything else
            # falls back to plain equality.
            $LeftIsNumber = ($Left -isnot [bool]) -and ($Left -is [byte] -or $Left -is [int16] -or $Left -is [int32] -or $Left -is [int64] -or $Left -is [single] -or $Left -is [double] -or $Left -is [decimal])
            $RightIsNumber = ($Right -isnot [bool]) -and ($Right -is [byte] -or $Right -is [int16] -or $Right -is [int32] -or $Right -is [int64] -or $Right -is [single] -or $Right -is [double] -or $Right -is [decimal])
            if ($LeftIsNumber -and $RightIsNumber) { return ([double]$Left -eq [double]$Right) }
            return [object]::Equals($Left, $Right)
        }

        $Name = @(@(Get-RuleFieldName $Left) + @(Get-RuleFieldName $Right) | Select-Object -Unique)
        foreach ($Field in $Name) {
            $LeftValue = Get-RuleFieldValue $Left $Field
            $RightValue = Get-RuleFieldValue $Right $Field
            switch -Regex ($Field) {
                '^(maximumDuration|claimValue)$' {
                    if (-not [string]::Equals([string]$LeftValue, [string]$RightValue, [System.StringComparison]::OrdinalIgnoreCase)) { return $false }
                }
                '^(isExpirationRequired|isEnabled|isApprovalRequired|isDefaultRecipientsEnabled)$' {
                    if ([bool]$LeftValue -ne [bool]$RightValue) { return $false }
                }
                '^(enabledRules|notificationRecipients)$' {
                    if (-not (Test-StringSetEqual -Left @($LeftValue) -Right @($RightValue))) { return $false }
                }
                '^(primaryApprovers|escalationApprovers)$' {
                    if (-not (Test-ApproverSetEqual -Left @($LeftValue) -Right @($RightValue))) { return $false }
                }
                default {
                    if (-not (Test-RuleEquivalent -Left $LeftValue -Right $RightValue)) { return $false }
                }
            }
        }
        return $true
    }

    if ($Setting.ContainsKey('ActivationMaxHours')) {
        # ConvertTo-OERDuration -Hours has ValidateRange(1, [int]::MaxValue) and throws on 0; this is
        # safe only because the sole caller, Set-OERRoleManagementPolicy -ActivationMaxHours, already
        # enforces ValidateRange(1, 24) -- 0 can never reach here.
        Add-RuleField -Object (Get-RuleClone -Source $ById -Cache $Touched -Id 'Expiration_EndUser_Assignment') -Name 'maximumDuration' -Value (ConvertTo-OERDuration -Hours ([int]$Setting.ActivationMaxHours))
    }
    if ($Setting.ContainsKey('RequireMfaOnActivation')) {
        $Rule = Get-RuleClone -Source $ById -Cache $Touched -Id 'Enablement_EndUser_Assignment'
        Add-RuleField -Object $Rule -Name 'enabledRules' -Value (Get-ToggledList -List $Rule.enabledRules -Flag 'MultiFactorAuthentication' -On ([bool]$Setting.RequireMfaOnActivation))
    }
    if ($Setting.ContainsKey('RequireJustificationOnActivation')) {
        $Rule = Get-RuleClone -Source $ById -Cache $Touched -Id 'Enablement_EndUser_Assignment'
        Add-RuleField -Object $Rule -Name 'enabledRules' -Value (Get-ToggledList -List $Rule.enabledRules -Flag 'Justification' -On ([bool]$Setting.RequireJustificationOnActivation))
    }
    if ($Setting.ContainsKey('RequireTicketOnActivation')) {
        $Rule = Get-RuleClone -Source $ById -Cache $Touched -Id 'Enablement_EndUser_Assignment'
        Add-RuleField -Object $Rule -Name 'enabledRules' -Value (Get-ToggledList -List $Rule.enabledRules -Flag 'Ticketing' -On ([bool]$Setting.RequireTicketOnActivation))
    }
    if ($Setting.ContainsKey('RequireMfaOnActiveAssignment')) {
        $Rule = Get-RuleClone -Source $ById -Cache $Touched -Id 'Enablement_Admin_Assignment'
        Add-RuleField -Object $Rule -Name 'enabledRules' -Value (Get-ToggledList -List $Rule.enabledRules -Flag 'MultiFactorAuthentication' -On ([bool]$Setting.RequireMfaOnActiveAssignment))
    }
    if ($Setting.ContainsKey('RequireJustificationOnActiveAssignment')) {
        $Rule = Get-RuleClone -Source $ById -Cache $Touched -Id 'Enablement_Admin_Assignment'
        Add-RuleField -Object $Rule -Name 'enabledRules' -Value (Get-ToggledList -List $Rule.enabledRules -Flag 'Justification' -On ([bool]$Setting.RequireJustificationOnActiveAssignment))
    }
    if ($Setting.ContainsKey('AllowPermanentEligibility')) {
        Add-RuleField -Object (Get-RuleClone -Source $ById -Cache $Touched -Id 'Expiration_Admin_Eligibility') -Name 'isExpirationRequired' -Value (-not [bool]$Setting.AllowPermanentEligibility)
    }
    if ($Setting.ContainsKey('EligibleDuration')) {
        Add-RuleField -Object (Get-RuleClone -Source $ById -Cache $Touched -Id 'Expiration_Admin_Eligibility') -Name 'maximumDuration' -Value (Resolve-OERDurationInput -Value ([string]$Setting.EligibleDuration) -Unit Days)
    }
    if ($Setting.ContainsKey('AllowPermanentActiveAssignment')) {
        Add-RuleField -Object (Get-RuleClone -Source $ById -Cache $Touched -Id 'Expiration_Admin_Assignment') -Name 'isExpirationRequired' -Value (-not [bool]$Setting.AllowPermanentActiveAssignment)
    }
    if ($Setting.ContainsKey('ActiveDuration')) {
        Add-RuleField -Object (Get-RuleClone -Source $ById -Cache $Touched -Id 'Expiration_Admin_Assignment') -Name 'maximumDuration' -Value (Resolve-OERDurationInput -Value ([string]$Setting.ActiveDuration) -Unit Days)
    }
    if ($Setting.ContainsKey('AuthenticationContextId')) {
        $Rule = Get-RuleClone -Source $ById -Cache $Touched -Id 'AuthenticationContext_EndUser_Assignment'
        $Value = [string]$Setting.AuthenticationContextId
        $Enabled = -not [string]::IsNullOrEmpty($Value)
        Add-RuleField -Object $Rule -Name 'isEnabled' -Value $Enabled
        Add-RuleField -Object $Rule -Name 'claimValue' -Value $(if ($Enabled) { $Value } else { '' })
    }
    if ($Setting.ContainsKey('RequireApproval') -or $Setting.ContainsKey('PrimaryApprovers')) {
        $Rule = Get-RuleClone -Source $ById -Cache $Touched -Id 'Approval_EndUser_Assignment'
        if ($Setting.ContainsKey('RequireApproval')) { Add-RuleField -Object $Rule.setting -Name 'isApprovalRequired' -Value ([bool]$Setting.RequireApproval) }
        if ($Setting.ContainsKey('PrimaryApprovers')) {
            # Supplying approvers implies approval is required (overrides any RequireApproval = $false).
            Add-RuleField -Object $Rule.setting -Name 'isApprovalRequired' -Value $true
            if (-not $Rule.setting.approvalMode -or $Rule.setting.approvalMode -eq 'NoApproval') { Add-RuleField -Object $Rule.setting -Name 'approvalMode' -Value 'SingleStage' }
            $Stage = @($Rule.setting.approvalStages) | Select-Object -First 1
            if (-not $Stage) {
                $Stage = [PSCustomObject]@{
                    approvalStageTimeOutInDays      = 1
                    isApproverJustificationRequired = $true
                    escalationTimeInMinutes         = 0
                    primaryApprovers                = @()
                    isEscalationEnabled             = $false
                    escalationApprovers             = @()
                }
                Add-RuleField -Object $Rule.setting -Name 'approvalStages' -Value (@($Stage))
            }
            Add-RuleField -Object $Stage -Name 'primaryApprovers' -Value (@($Setting.PrimaryApprovers))
        }
    }
    if ($Setting.ContainsKey('NotificationRule')) {
        foreach ($Note in @($Setting.NotificationRule)) {
            $Rule = Get-RuleClone -Source $ById -Cache $Touched -Id ([string]$Note.RuleId)
            if ($Note.PSObject.Properties['NotificationLevel'] -and $null -ne $Note.NotificationLevel) { Add-RuleField -Object $Rule -Name 'notificationLevel' -Value ([string]$Note.NotificationLevel) }
            if ($Note.PSObject.Properties['IsDefaultRecipientsEnabled'] -and $null -ne $Note.IsDefaultRecipientsEnabled) { Add-RuleField -Object $Rule -Name 'isDefaultRecipientsEnabled' -Value ([bool]$Note.IsDefaultRecipientsEnabled) }
            if ($Note.PSObject.Properties['NotificationRecipients'] -and $null -ne $Note.NotificationRecipients) { Add-RuleField -Object $Rule -Name 'notificationRecipients' -Value (@($Note.NotificationRecipients)) }
        }
    }

    # Cross-rule reconciliation: PIM forbids MFA-on-activation and an enabled authentication context
    # at the same time. The DECISION is owned by Resolve-OERPimActivationConflict, shared with the
    # Graph PIM-for-groups write path; only the mutation idiom below is ARM-specific.
    # -ResolveUnrequestedConflict is passed because this transport PATCHes the FULL rule set, so ARM
    # rejects a pre-existing invalid combination even on an unrelated change.
    $AcrsRule = if ($Touched.ContainsKey('AuthenticationContext_EndUser_Assignment')) { $Touched['AuthenticationContext_EndUser_Assignment'] }
    elseif ($ById.ContainsKey('AuthenticationContext_EndUser_Assignment')) { $ById['AuthenticationContext_EndUser_Assignment'] }
    $EnablementRule = if ($Touched.ContainsKey('Enablement_EndUser_Assignment')) { $Touched['Enablement_EndUser_Assignment'] }
    elseif ($ById.ContainsKey('Enablement_EndUser_Assignment')) { $ById['Enablement_EndUser_Assignment'] }

    $ConflictParams = @{
        EffectiveAuthContextEnabled     = [bool]$AcrsRule.isEnabled
        EffectiveAuthContextId          = [string]$AcrsRule.claimValue
        EffectiveActivationEnabledRules = @($EnablementRule.enabledRules)
        ResolveUnrequestedConflict      = $true
    }
    if ($Setting.ContainsKey('AuthenticationContextId') -and -not [string]::IsNullOrEmpty([string]$Setting.AuthenticationContextId)) {
        $ConflictParams.CallerRequestsAuthContext = $true
    }
    if ($Setting.ContainsKey('RequireMfaOnActivation') -and [bool]$Setting.RequireMfaOnActivation) {
        $ConflictParams.CallerRequestsMfa = $true
    }
    $Resolution = Resolve-OERPimActivationConflict @ConflictParams

    switch ($Resolution.Action) {
        'Conflict' {
            throw 'Cannot enable both multi-factor authentication and an authentication context on activation; Azure PIM treats them as mutually exclusive. Set only one.'
        }
        'DisableAuthContext' {
            $Rule = Get-RuleClone -Source $ById -Cache $Touched -Id 'AuthenticationContext_EndUser_Assignment'
            Add-RuleField -Object $Rule -Name 'isEnabled' -Value $false
            Add-RuleField -Object $Rule -Name 'claimValue' -Value ''
        }
        'ClearMfa' {
            $Rule = Get-RuleClone -Source $ById -Cache $Touched -Id 'Enablement_EndUser_Assignment'
            Add-RuleField -Object $Rule -Name 'enabledRules' -Value (Get-ToggledList -List $Rule.enabledRules -Flag 'MultiFactorAuthentication' -On $false)
        }
    }

    # Assemble the FULL rules set (every current rule in order, genuinely changed ones replaced by
    # their modified clone) plus the list of ids that actually changed. Returning one object -- not a
    # bare array -- keeps the rules array flat through ConvertTo-Json at the call site (a
    # bare/unary-comma array return gets re-wrapped by an @() at the caller and serializes as a nested
    # [[...]], which ARM rejects as InvalidPolicy).
    $ChangedRuleId = [System.Collections.Generic.List[string]]::new()
    $FullRule = [System.Collections.Generic.List[object]]::new()
    foreach ($Rule in $CurrentRule) {
        $Id = [string]$Rule.id
        if ($Id -and $Touched.ContainsKey($Id)) {
            $Clone = $Touched[$Id]
            if (Test-RuleEquivalent -Left $Clone -Right $Rule) {
                # Touched but not actually changed (e.g. the caller re-asserted a value the policy
                # already had): pass the ORIGINAL rule through and leave the id out of ChangedRuleId,
                # so Set-OERRoleManagementPolicy's NoChange guard can see a genuine no-op. The full
                # rule set is still returned -- ARM validates it as a whole.
                $FullRule.Add($Rule)
            } else {
                $FullRule.Add($Clone)
                $ChangedRuleId.Add($Id)
            }
        } else {
            $FullRule.Add($Rule)
        }
    }

    [PSCustomObject]@{
        Rules         = $FullRule.ToArray()
        ChangedRuleId = $ChangedRuleId.ToArray()
    }
}
