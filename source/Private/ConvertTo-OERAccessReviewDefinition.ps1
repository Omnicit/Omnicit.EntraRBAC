function ConvertTo-OERAccessReviewDefinition {
    <#
    .SYNOPSIS
    Converts a raw Graph accessReviewScheduleDefinition into a tagged Omnicit.EntraRBAC.AccessReviewDefinition.

    .DESCRIPTION
    Maps the relevant properties of a Graph access review schedule definition into a [PSCustomObject]
    tagged Omnicit.EntraRBAC.AccessReviewDefinition. The raw scope query, the scope's '@odata.type'
    (ScopeType, $null when the answer carries none), settings and stage count are surfaced for
    inspection. ScopeType tells a review of a group's members from one of its inactive users, which
    share the query (see Resolve-OERAccessReviewGroupScope). ReviewerCount reflects the number of top-level reviewer scope entries, and
    StageCount reflects the number of stageSettings entries (non-zero for multi-stage reviews). Seven
    settings fields are also surfaced as flat, typed members -- MailNotificationsEnabled,
    ReminderNotificationsEnabled, JustificationRequired, RecommendationsEnabled,
    AutoApplyDecisionsEnabled, DefaultDecision and DefaultDecisionEnabled -- read from the raw settings
    bag via a local Get-SettingValue helper. See that helper's own comment for why it exists: it is not
    a workaround for a named-key lookup bug (PowerShell's IDictionary member adapter already resolves
    '.' access correctly on the Hashtable/Dictionary/OrderedDictionary shapes this bag can arrive as),
    it is for consistency with Resolve-OERAccessReviewChange's identical helper. The raw Settings bag is
    still exposed as an escape hatch; the flat members are additive.

    StageSettings surfaces the per-stage escalation config (StageId, DependsOn, DurationInDays,
    RecommendationsEnabled, DecisionsThatMoveToNextStage, Reviewers, FallbackReviewers) that a
    multi-stage definition's stageSettings array carries. DependsOn and DecisionsThatMoveToNextStage
    live ONLY here, on accessReviewStageSettings (a property of the definition) -- the
    accessReviewStage resource returned per-instance does not carry either, so they can never be read
    from ConvertTo-OERAccessReviewStage. Deliberately not projected: recommendationInsightsSettings.
    accessReviewStageSettings spells it plural ("Insights"), while accessReviewScheduleSettings spells
    the sibling key singular ("Insight") -- sharing one member name between the two projections would
    be a trap for no benefit here.
    PrincipalScopes and ResourceScopes surface the inner scopes (Query, QueryType, QueryRoot, ScopeType)
    of a principal resource memberships scope, which is the scope of a directory role review and has no
    top-level query (see Resolve-OERAccessReviewRoleScope); each is an empty array for any other scope.
    This private converter is the single owner of the definition output shape and is used by
    New/Get/Set-OERAccessReviewDefinition.

    .PARAMETER InputObject
    The raw Graph access review schedule definition (hashtable or PSObject) to convert.

    .EXAMPLE
    ConvertTo-OERAccessReviewDefinition -InputObject $definition
    Converts a single access review definition into a tagged object.

    .EXAMPLE
    $definitions | ConvertTo-OERAccessReviewDefinition
    Converts each raw Graph access review definition in the pipeline into a tagged object.
    #>
    [OutputType([PSCustomObject])]
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
        $InputObject
    )
    process {
        $ScopeQuery = $InputObject.scope.query
        # The scope's '@odata.type', read dictionary-safely: a raw Graph answer is a hashtable whose
        # '@odata.type' key is not a member name, and a PSCustomObject fixture carries it as a property.
        $ScopeNode = $InputObject.scope
        $ScopeType = $null
        if ($ScopeNode -is [System.Collections.IDictionary]) {
            if ($ScopeNode.Contains('@odata.type')) { $ScopeType = $ScopeNode['@odata.type'] }
        }
        elseif ($null -ne $ScopeNode -and $null -ne $ScopeNode.PSObject.Properties['@odata.type']) {
            $ScopeType = $ScopeNode.PSObject.Properties['@odata.type'].Value
        }
        if ($null -ne $ScopeType) { $ScopeType = [string]$ScopeType }
        # The inner scopes of a principal resource memberships scope (a role review has no top-level
        # query), read dictionary-safely; an array, empty when absent, never one $null.
        $ReadScopeList = {
            param([object]$Node, [string]$Name)
            $List = $null
            if ($Node -is [System.Collections.IDictionary]) {
                if ($Node.Contains($Name)) { $List = $Node[$Name] }
            }
            elseif ($null -ne $Node -and $null -ne $Node.PSObject.Properties[$Name]) {
                $List = $Node.PSObject.Properties[$Name].Value
            }
            $Read = {
                param([object]$Item, [string]$Key)
                if ($Item -is [System.Collections.IDictionary]) {
                    if ($Item.Contains($Key)) { return $Item[$Key] }
                    return $null
                }
                if ($null -ne $Item.PSObject.Properties[$Key]) { return $Item.PSObject.Properties[$Key].Value }
                return $null
            }
            , @(foreach ($Item in @($List | Where-Object { $null -ne $_ })) {
                    [PSCustomObject]@{
                        Query     = & $Read $Item 'query'
                        QueryType = & $Read $Item 'queryType'
                        QueryRoot = & $Read $Item 'queryRoot'
                        ScopeType = & $Read $Item '@odata.type'
                    }
                })
        }
        $PrincipalScopes = & $ReadScopeList $ScopeNode 'principalScopes'
        $ResourceScopes = & $ReadScopeList $ScopeNode 'resourceScopes'
        $AccessPackageId = $null
        $AssignmentPolicyId = $null
        if ($ScopeQuery) {
            # Match both the v1.0 relationship form (accessPackage/id eq '...') and the legacy beta
            # scalar form (accessPackageId eq '...') so reviews created before the v1.0 fix still parse.
            if ([string]$ScopeQuery -match "accessPackage(?:/id|Id) eq '([^']+)'")   { $AccessPackageId = $Matches[1] }
            if ([string]$ScopeQuery -match "assignmentPolicy(?:/id|Id) eq '([^']+)'") { $AssignmentPolicyId = $Matches[1] }
        }
        # NOT a workaround for a named-key lookup bug: $Settings.$Key already resolves correctly on a
        # Hashtable, a Dictionary[string,object] and an OrderedDictionary alike -- PowerShell's built-in
        # IDictionary member adapter handles single named-key '.' access on all three the same way it
        # handles a PSCustomObject, so this helper changes nothing about what a plain property read
        # would return here. It exists so this file reads settings the exact same way as
        # Resolve-OERAccessReviewChange's identical Get-SettingValue helper (copied from there, not
        # reinvented), which itself exists because a DIFFERENT access pattern -- PSObject.Properties
        # ENUMERATION, walking every key rather than looking one up by name -- silently enumerates
        # nothing over a raw Graph IDictionary. Nothing in this file enumerates settings today, so that
        # failure mode does not apply here either; the helper is kept anyway so the two files can never
        # drift on how they read a live settings bag, and so a future enumeration-style read added to
        # either file already has a dictionary-safe helper in place. Do not delete this as redundant and
        # do not read it as a guard against a lookup regression -- there isn't one to guard against.
        function Get-SettingValue {
            param([object]$Settings, [string]$Key)
            if ($null -eq $Settings) { return $null }
            if ($Settings -is [System.Collections.IDictionary]) {
                if ($Settings.ContainsKey($Key)) { return $Settings[$Key] }
                return $null
            }
            return $Settings.$Key
        }

        $Settings = $InputObject.settings
        $Out = [PSCustomObject]@{
            AccessReviewDefinitionId      = $InputObject.id
            DisplayName                   = $InputObject.displayName
            Status                        = $InputObject.status
            DescriptionForAdmins          = $InputObject.descriptionForAdmins
            DescriptionForReviewers       = $InputObject.descriptionForReviewers
            Scope                         = $ScopeQuery
            ScopeType                     = $ScopeType
            PrincipalScopes               = $PrincipalScopes
            ResourceScopes                = $ResourceScopes
            AccessPackageId               = $AccessPackageId
            AssignmentPolicyId            = $AssignmentPolicyId
            Reviewers                     = @($InputObject.reviewers | Where-Object { $_ })
            FallbackReviewers             = @($InputObject.fallbackReviewers | Where-Object { $_ })
            Recurrence                    = Get-SettingValue -Settings $Settings -Key 'recurrence'
            DurationInDays                = Get-SettingValue -Settings $Settings -Key 'instanceDurationInDays'
            ReviewerCount                 = @($InputObject.reviewers | Where-Object { $_ }).Count
            StageCount                    = @($InputObject.stageSettings | Where-Object { $_ }).Count
            # accessReviewStageSettings carries the escalation config (dependsOn,
            # decisionsThatWillMoveToNextStage) that does NOT exist on the accessReviewStage resource
            # itself -- that is the only place it can be read from. Whether a bare GET of a definition
            # returns stageSettings at all is undocumented, and $InputObject.stageSettings is $null on a
            # single-stage definition, so every array read below is wrapped in Where-Object { $_ }:
            # @($NullVar.someProperty) yields a one-element array containing $null, not an empty array.
            StageSettings                 = @(foreach ($S in @($InputObject.stageSettings | Where-Object { $_ })) {
                    [PSCustomObject]@{
                        StageId                      = [string]$S.stageId
                        DependsOn                    = @($S.dependsOn | Where-Object { $_ })
                        DurationInDays               = $S.durationInDays
                        RecommendationsEnabled       = $S.recommendationsEnabled
                        DecisionsThatMoveToNextStage = @($S.decisionsThatWillMoveToNextStage | Where-Object { $_ })
                        Reviewers                    = @($S.reviewers | Where-Object { $_ })
                        FallbackReviewers            = @($S.fallbackReviewers | Where-Object { $_ })
                    }
                })
            CreatedDateTime               = $InputObject.createdDateTime
            MailNotificationsEnabled      = Get-SettingValue -Settings $Settings -Key 'mailNotificationsEnabled'
            ReminderNotificationsEnabled  = Get-SettingValue -Settings $Settings -Key 'reminderNotificationsEnabled'
            JustificationRequired         = Get-SettingValue -Settings $Settings -Key 'justificationRequiredOnApproval'
            RecommendationsEnabled        = Get-SettingValue -Settings $Settings -Key 'recommendationsEnabled'
            AutoApplyDecisionsEnabled     = Get-SettingValue -Settings $Settings -Key 'autoApplyDecisionsEnabled'
            DefaultDecision               = Get-SettingValue -Settings $Settings -Key 'defaultDecision'
            DefaultDecisionEnabled        = Get-SettingValue -Settings $Settings -Key 'defaultDecisionEnabled'
            Settings                      = $Settings
        }
        $Out.PSObject.TypeNames.Insert(0, 'Omnicit.EntraRBAC.AccessReviewDefinition')
        $Out
    }
}
