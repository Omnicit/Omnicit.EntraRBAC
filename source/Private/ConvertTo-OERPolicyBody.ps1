function ConvertTo-OERPolicyBody {
    <#
    .SYNOPSIS
    Assembles a Microsoft Graph access package assignment policy body from builder objects and parameters.

    .DESCRIPTION
    Builds the v1.0 accessPackageAssignmentPolicy request body shared by New- and
    Set-OERAccessPackageAssignmentPolicy. Takes a RequestorScope object (from
    New-OERAccessPackageRequestorScope), an optional RequestorSettings object (from
    New-OERAccessPackageRequestorSettings), zero or more ApprovalStage objects (from
    New-OERAccessPackageApprovalStage), and the lifecycle scalars. This private helper is the single
    owner of the policy Graph schema.

    Each piece of the body is resolved with overlay precedence: a value passed by the caller wins;
    otherwise, when -Existing (the current raw Graph policy, used by Set's read-modify-write) is
    supplied, the corresponding value is carried forward from it as it is, an empty string, false or an
    empty list included; otherwise a New-default is applied, written only when the read has no value for
    the key and the call names none.
    -Existing is the raw Graph hashtable and is read by key/dot access, never via .PSObject.Properties.
    The description is always emitted: an explicit -Description wins, otherwise it is carried forward
    from -Existing, and only on New (no -Existing) does it default to the display name. Expiration is
    afterDuration when -DurationInDays or -DurationInHours is given, afterDateTime
    when -ExpirationDateTime is given, the carried-forward -Existing expiration when present, otherwise
    noExpiration. reviewSettings and questions are preserved verbatim from -Existing when it has a value for them and are
    omitted entirely on New. -RequestorScope follows the same overlay: when supplied its
    allowedTargetScope and specificAllowedTargets win; when omitted, both are carried forward from
    -Existing together as a single unit (never mixed from different sources), so a read-modify-write Set
    that only changes an unrelated field never resets a live SpecificDirectoryUsers scope back to a
    default. Omitting -RequestorScope with no -Existing baseline (New, with no scope supplied) is a
    caller error and throws.

    Custom extension stages are carried forward from -Existing in the documented update shape, per stage
    the stage name and a customExtension holding the extension's type and id and nothing else, since
    Microsoft Graph removes a policy's custom extension stages on an update that does not send them
    (measured). A stage whose custom extension id was not read cannot be carried, and dropping it would
    disconnect the extension, so the function throws instead; an empty or absent list adds no key.
    automaticRequestSettings is carried forward from -Existing together with the carried scope, and only
    while -RequestorScope is omitted: a declared scope replaces the allowed targets and never inherits
    automatic assignment. Without them an update of an automatic assignment policy is refused by
    Microsoft Graph (measured).

    With -Existing supplied, an Existing policy that has no expiration (or a null one) throws unless
    -DurationInDays, -DurationInHours or -ExpirationDateTime is given, and one with no
    requestApprovalSettings throws unless -ApprovalStage, -RequireRequestorJustification and
    -RequireApprovalForUpdate are all given, one with no requestorSettings throws unless
    -RequestorSettings is given, and one with no notificationSettings throws unless
    -DisableAssignmentNotifications is given (a backstop for the refusal
    Set-OERAccessPackageAssignmentPolicy makes first); for those four keys the builder default is never
    written over a live value. Without -Existing (New) the defaults stay.

    .PARAMETER DisplayName
    The policy display name.

    .PARAMETER Description
    Optional policy description. When omitted or empty the description is carried forward from
    -Existing, and defaults to the display name only when no -Existing baseline is supplied.

    .PARAMETER AccessPackageId
    The id of the access package the policy belongs to.

    .PARAMETER RequestorScope
    An optional tagged Omnicit.EntraRBAC.RequestorScope object supplying allowedTargetScope and
    specificAllowedTargets. When omitted, both are carried forward from -Existing as a unit instead of
    being reset to a default scope; omitting -RequestorScope with no -Existing baseline is an error.

    .PARAMETER RequestorSettings
    An optional tagged Omnicit.EntraRBAC.RequestorSettings object whose GraphRequestorSettings member is
    used as the policy requestorSettings. When omitted the value is carried from -Existing, or a
    self-service New-default is applied.

    .PARAMETER ApprovalStage
    Zero or more tagged Omnicit.EntraRBAC.ApprovalStage objects, in order. When omitted the stages are
    carried from -Existing, or an empty stage list is used.

    .PARAMETER RequireApproval
    Whether approval is required to add an assignment (requestApprovalSettings.isApprovalRequiredForAdd).
    When omitted it is derived from -ApprovalStage, carried from -Existing, or defaults to false.

    .PARAMETER RequireRequestorJustification
    Whether the requestor must supply a justification when requesting access. When omitted the value is
    carried from -Existing, or defaults to false.

    .PARAMETER RequireApprovalForUpdate
    Whether approval is required to update an existing assignment. When omitted the value is carried from
    -Existing, or defaults to false.

    .PARAMETER DurationInDays
    Assignment lifetime in days (afterDuration expiration). Mutually exclusive with -DurationInHours and
    -ExpirationDateTime.

    .PARAMETER DurationInHours
    Assignment lifetime in hours (afterDuration expiration). Mutually exclusive with -DurationInDays and
    -ExpirationDateTime.

    .PARAMETER ExpirationDateTime
    Fixed assignment expiry (afterDateTime expiration). Mutually exclusive with -DurationInDays and
    -DurationInHours.

    .PARAMETER DisableAssignmentNotifications
    Whether assignment notification emails are suppressed (notificationSettings.isAssignmentNotificationDisabled).
    When omitted the value is carried from -Existing, or defaults to false (notifications enabled).

    .PARAMETER Existing
    The current raw Graph accessPackageAssignmentPolicy hashtable, supplied by Set for read-modify-write.
    Values not provided as parameters are carried forward from it as they are (an empty string, false or an
    empty list included; the builder default is written only when the read has no value for the key and the
    call names none), and reviewSettings and questions are
    preserved verbatim. Its customExtensionStageSettings must hold each custom extension's id (read with
    $expand=customExtensionStageSettings($expand=customExtension)) or the function throws, and its
    automaticRequestSettings is carried only while -RequestorScope is omitted. Absent on New.

    .EXAMPLE
    ConvertTo-OERPolicyBody -DisplayName 'Default' -AccessPackageId 'ap-1' -RequestorScope $s -ApprovalStage $stage -DurationInDays 30

    Returns the Graph policy body hashtable.
    #>
    [OutputType([hashtable])]
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$DisplayName,

        [string]$Description,

        [Parameter(Mandatory)]
        [string]$AccessPackageId,

        [PSCustomObject]$RequestorScope,

        [PSCustomObject]$RequestorSettings,

        [PSCustomObject[]]$ApprovalStage,

        [bool]$RequireApproval,

        [bool]$RequireRequestorJustification,

        [bool]$RequireApprovalForUpdate,

        [int]$DurationInDays,

        [int]$DurationInHours,

        [datetime]$ExpirationDateTime,

        [bool]$DisableAssignmentNotifications,

        [hashtable]$Existing
    )
    if ($PSBoundParameters.ContainsKey('RequestorScope')) {
        if ($RequestorScope.PSObject.TypeNames -notcontains 'Omnicit.EntraRBAC.RequestorScope') {
            throw [System.Management.Automation.ErrorRecord]::new(
                [System.Exception]::new('-RequestorScope must be an object from New-OERAccessPackageRequestorScope.'),
                'PolicyBuilderObjectRequired',
                [System.Management.Automation.ErrorCategory]::InvalidArgument,
                $RequestorScope)
        }
    } elseif (-not $Existing) {
        throw [System.Management.Automation.ErrorRecord]::new(
            [System.Exception]::new('-RequestorScope is required when no -Existing policy is supplied.'),
            'RequestorScopeRequired',
            [System.Management.Automation.ErrorCategory]::InvalidArgument,
            $null)
    }
    if ($PSBoundParameters.ContainsKey('RequestorSettings') -and
        $RequestorSettings.PSObject.TypeNames -notcontains 'Omnicit.EntraRBAC.RequestorSettings') {
        throw [System.Management.Automation.ErrorRecord]::new(
            [System.Exception]::new('-RequestorSettings must be an object from New-OERAccessPackageRequestorSettings.'),
            'PolicyBuilderObjectRequired',
            [System.Management.Automation.ErrorCategory]::InvalidArgument,
            $RequestorSettings)
    }

    # BL-161a backstop: with -Existing, a read lacking expiration, requestApprovalSettings,
    # requestorSettings or notificationSettings must not fall to the builder default. Set-OERAccessPackageAssignmentPolicy refuses first; this throws.
    if ($Existing) {
        $ExistingPolicyId = $Existing['id']
        if ($null -eq $Existing.expiration -and
            -not ($PSBoundParameters.ContainsKey('DurationInDays') -or
                $PSBoundParameters.ContainsKey('DurationInHours') -or
                $PSBoundParameters.ContainsKey('ExpirationDateTime'))) {
            throw [System.Management.Automation.ErrorRecord]::new(
                [System.Exception]::new('The existing policy has no expiration and no -DurationInDays, -DurationInHours or -ExpirationDateTime was given; writing the default would replace it.'),
                'AssignmentPolicyValueUnknown',
                [System.Management.Automation.ErrorCategory]::InvalidData,
                $ExistingPolicyId)
        }
        if ($null -eq $Existing.requestApprovalSettings -and
            -not ($PSBoundParameters.ContainsKey('ApprovalStage') -and
                $PSBoundParameters.ContainsKey('RequireRequestorJustification') -and
                $PSBoundParameters.ContainsKey('RequireApprovalForUpdate'))) {
            throw [System.Management.Automation.ErrorRecord]::new(
                [System.Exception]::new('The existing policy has no requestApprovalSettings and -ApprovalStage, -RequireRequestorJustification and -RequireApprovalForUpdate were not all given; writing the default would replace it.'),
                'AssignmentPolicyValueUnknown',
                [System.Management.Automation.ErrorCategory]::InvalidData,
                $ExistingPolicyId)
        }
        if ($null -eq $Existing.requestorSettings -and -not $PSBoundParameters.ContainsKey('RequestorSettings')) {
            throw [System.Management.Automation.ErrorRecord]::new(
                [System.Exception]::new('The existing policy has no requestorSettings and no -RequestorSettings was given; writing the default would replace it.'),
                'AssignmentPolicyValueUnknown',
                [System.Management.Automation.ErrorCategory]::InvalidData,
                $ExistingPolicyId)
        }
        if ($null -eq $Existing.notificationSettings -and -not $PSBoundParameters.ContainsKey('DisableAssignmentNotifications')) {
            throw [System.Management.Automation.ErrorRecord]::new(
                [System.Exception]::new('The existing policy has no notificationSettings and no -DisableAssignmentNotifications was given; writing the default would replace it.'),
                'AssignmentPolicyValueUnknown',
                [System.Management.Automation.ErrorCategory]::InvalidData,
                $ExistingPolicyId)
        }
    }

    $Stages = @()
    foreach ($Stage in @($ApprovalStage)) {
        if ($null -eq $Stage) { continue }
        if ($Stage.PSObject.TypeNames -notcontains 'Omnicit.EntraRBAC.ApprovalStage') {
            throw [System.Management.Automation.ErrorRecord]::new(
                [System.Exception]::new('-ApprovalStage entries must be objects from New-OERAccessPackageApprovalStage.'),
                'PolicyBuilderObjectRequired',
                [System.Management.Automation.ErrorCategory]::InvalidArgument,
                $Stage)
        }
        $Stages += $Stage.GraphStage
    }

    # description: always emit. An explicitly supplied value wins -- INCLUDING an empty string, which
    # is how a caller clears a description; gating on truthiness instead silently ignored that and made
    # the apply non-idempotent. An OMITTED -Description carries forward from -Existing -- by
    # PRESENCE, not truthiness, so an already-empty live description (reachable now that this
    # function itself can write one) is carried forward unchanged instead of being coerced back to
    # the display name -- and only falls back to the display name when -Existing carries no
    # description key at all (or no -Existing was supplied, i.e. New).
    $ResolvedDescription = if ($PSBoundParameters.ContainsKey('Description')) {
        $Description
    } elseif ($null -ne $Existing -and $Existing.ContainsKey('description') -and $null -ne $Existing['description']) {
        $Existing['description']
    } else {
        $DisplayName
    }

    # expiration: provided duration/hours/date wins, else carry from Existing, else noExpiration.
    $Expiration = if ($PSBoundParameters.ContainsKey('DurationInDays')) {
        @{ type = 'afterDuration'; duration = ConvertTo-OERDuration -Days $DurationInDays }
    } elseif ($PSBoundParameters.ContainsKey('DurationInHours')) {
        @{ type = 'afterDuration'; duration = ConvertTo-OERDuration -Hours $DurationInHours }
    } elseif ($PSBoundParameters.ContainsKey('ExpirationDateTime')) {
        @{ type = 'afterDateTime'; endDateTime = $ExpirationDateTime.ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ') }
    } elseif ($null -ne $Existing -and $null -ne $Existing.expiration) {
        $Existing.expiration
    } else {
        @{ type = 'noExpiration' }
    }

    # requestorSettings: the builder's keys are MERGED onto a copy of the existing settings rather than
    # replacing them. The PUT is a full-object write and Microsoft Learn does not state that an omitted
    # member of this complex type is preserved, so a wholesale replace silently resets every member the
    # builder does not model. A key the builder DOES emit always wins -- it is an explicit statement,
    # including when it is false.
    $ExistingRs = if ($null -ne $Existing -and $Existing.ContainsKey('requestorSettings')) {
        $Existing['requestorSettings']
    } else {
        $null
    }

    $ResolvedRequestorSettings = if ($PSBoundParameters.ContainsKey('RequestorSettings')) {
        $Merged = @{}
        # $ExistingRs arrives from Graph as a nested HASHTABLE, not a PSCustomObject, so it has to be
        # enumerated by Keys. PSObject.Properties does NOT see hashtable keys -- a merge written that
        # way copies nothing and the whole stop-loss is silently inert. Both shapes are handled because
        # a caller (and every unit test) may pass a PSCustomObject instead.
        if ($ExistingRs -is [System.Collections.IDictionary]) {
            foreach ($K in $ExistingRs.Keys) { $Merged[$K] = $ExistingRs[$K] }
        } elseif ($null -ne $ExistingRs) {
            foreach ($Prop in $ExistingRs.PSObject.Properties) { $Merged[$Prop.Name] = $Prop.Value }
        }
        foreach ($K in $RequestorSettings.GraphRequestorSettings.Keys) {
            $Merged[$K] = $RequestorSettings.GraphRequestorSettings[$K]
        }
        $Merged
    } elseif ($null -ne $ExistingRs) {
        $ExistingRs
    } else {
        @{
            enableTargetsToSelfAddAccess           = $true
            enableTargetsToSelfUpdateAccess        = $false
            enableTargetsToSelfRemoveAccess        = $false
            allowCustomAssignmentSchedule          = $false
            enableOnBehalfRequestorsToAddAccess    = $false
            enableOnBehalfRequestorsToUpdateAccess = $false
            enableOnBehalfRequestorsToRemoveAccess = $false
            onBehalfRequestors                     = @()
        }
    }

    $ExistingApproval = if ($null -ne $Existing) { $Existing.requestApprovalSettings } else { $null }

    # stages: provided ApprovalStage wins, else carry from Existing, else empty.
    $ResolvedStages = if ($PSBoundParameters.ContainsKey('ApprovalStage')) {
        @($Stages)
    } elseif ($null -ne $ExistingApproval -and $null -ne $ExistingApproval.stages) {
        @($ExistingApproval.stages)
    } else {
        @()
    }

    # isApprovalRequiredForAdd: explicit flag wins, else derived from provided stages, else carry, else false.
    $ResolvedRequireApproval = if ($PSBoundParameters.ContainsKey('RequireApproval')) {
        [bool]$RequireApproval
    } elseif ($PSBoundParameters.ContainsKey('ApprovalStage')) {
        [bool]($Stages.Count -gt 0)
    } elseif ($null -ne $ExistingApproval) {
        [bool]$ExistingApproval.isApprovalRequiredForAdd
    } else {
        $false
    }

    $ResolvedRequireJustification = if ($PSBoundParameters.ContainsKey('RequireRequestorJustification')) {
        [bool]$RequireRequestorJustification
    } elseif ($null -ne $ExistingApproval) {
        [bool]$ExistingApproval.isRequestorJustificationRequired
    } else {
        $false
    }

    $ResolvedRequireApprovalForUpdate = if ($PSBoundParameters.ContainsKey('RequireApprovalForUpdate')) {
        [bool]$RequireApprovalForUpdate
    } elseif ($null -ne $ExistingApproval) {
        [bool]$ExistingApproval.isApprovalRequiredForUpdate
    } else {
        $false
    }

    # notificationSettings: explicit flag wins, else carry from Existing, else not-disabled New-default.
    $ResolvedNotificationSettings = if ($PSBoundParameters.ContainsKey('DisableAssignmentNotifications')) {
        @{ isAssignmentNotificationDisabled = [bool]$DisableAssignmentNotifications }
    } elseif ($null -ne $Existing -and $null -ne $Existing.notificationSettings) {
        $Existing.notificationSettings
    } else {
        @{ isAssignmentNotificationDisabled = $false }
    }

    # requestorScope: provided builder wins, else carry the live scope AND its specific targets from
    # Existing as a unit. Rewriting them from a default would silently reset a live
    # SpecificDirectoryUsers scope whenever an unrelated field is updated.
    $ResolvedAllowedTargetScope = if ($PSBoundParameters.ContainsKey('RequestorScope')) {
        $RequestorScope.AllowedTargetScope
    } elseif ($null -ne $Existing -and $null -ne $Existing.allowedTargetScope) {
        $Existing.allowedTargetScope
    } else {
        $null
    }
    $ResolvedSpecificTargets = if ($PSBoundParameters.ContainsKey('RequestorScope')) {
        @($RequestorScope.SpecificAllowedTargets)
    } elseif ($null -ne $Existing -and $null -ne $Existing.specificAllowedTargets) {
        @($Existing.specificAllowedTargets)
    } else {
        @()
    }

    $Body = @{
        displayName             = $DisplayName
        description             = $ResolvedDescription
        accessPackage           = @{ id = $AccessPackageId }
        allowedTargetScope      = $ResolvedAllowedTargetScope
        specificAllowedTargets  = @($ResolvedSpecificTargets)
        expiration              = $Expiration
        requestorSettings       = $ResolvedRequestorSettings
        requestApprovalSettings = @{
            isApprovalRequiredForAdd         = $ResolvedRequireApproval
            isApprovalRequiredForUpdate      = $ResolvedRequireApprovalForUpdate
            isRequestorJustificationRequired = $ResolvedRequireJustification
            stages                           = @($ResolvedStages)
        }
        notificationSettings    = $ResolvedNotificationSettings
    }

    # Preserve carry-forward-only collections verbatim from Existing; omitted entirely on New.
    # A value the read carries is carried as it is (BL-169a): the test is $null, never truthiness, so
    # $false, an empty string and an empty list are sent back. A list stays an array, a lone question too.
    if ($null -ne $Existing -and $null -ne $Existing.reviewSettings) { $Body.reviewSettings = $Existing.reviewSettings }
    if ($null -ne $Existing -and $null -ne $Existing.questions) {
        $ExistingQuestions = $Existing.questions
        if ($ExistingQuestions -is [System.Collections.IList] -or $ExistingQuestions -is [System.Collections.IDictionary]) {
            $Body.questions = @($ExistingQuestions)
        } else {
            $Body.questions = $ExistingQuestions
        }
    }

    # Custom extension stages (measured 2026-10-13, Sprint 11 step 3): Microsoft Graph REMOVES a
    # policy's customExtensionStageSettings on a PUT that omits them, so a read-modify-write must send
    # them back. Carried in the documented update shape -- the stage and the custom extension's type and
    # id -- never the expanded extension object the read returns. A stage whose extension id was not
    # read cannot be carried, and dropping it would disconnect the extension: refuse instead.
    # The outer @() keeps a lone stage an array: an if-expression unrolls a one-element array, and a
    # lone hashtable's Count is its key count, so an empty entry would otherwise be dropped unseen.
    $ExistingStages = @(if ($null -ne $Existing -and $Existing.ContainsKey('customExtensionStageSettings')) {
            @($Existing['customExtensionStageSettings'] | Where-Object { $null -ne $_ })
        })
    if ($ExistingStages.Count -gt 0) {
        $Body.customExtensionStageSettings = @(foreach ($StageSetting in $ExistingStages) {
                $Extension = $StageSetting['customExtension']
                $ExtensionId = if ($Extension -is [System.Collections.IDictionary]) { [string]$Extension['id'] } else { '' }
                if ([string]::IsNullOrWhiteSpace($ExtensionId)) {
                    throw [System.Management.Automation.ErrorRecord]::new(
                        [System.Exception]::new("The existing policy has a custom extension stage '$([string]$StageSetting['stage'])' whose custom extension id was not read, so it cannot be carried forward and the update would remove it. No update was sent; read the policy with its custom extension stages (or remove the stage) before updating it."),
                        'CustomExtensionStageUnread',
                        [System.Management.Automation.ErrorCategory]::InvalidData,
                        [string]$StageSetting['stage'])
                }
                $Ref = @{ id = $ExtensionId }
                if ($Extension['@odata.type']) { $Ref['@odata.type'] = [string]$Extension['@odata.type'] }
                @{ stage = [string]$StageSetting['stage']; customExtension = $Ref }
            })
    }

    # Automatic assignment (measured): an update of an automatic assignment policy that omits
    # automaticRequestSettings is refused (400 InvalidSpecificAllowedTargets); with it the update is
    # accepted and the settings are kept. Carried only together with the carried scope: a declared
    # -RequestorScope replaces the allowed targets, and must never inherit automatic assignment.
    if ($null -ne $Existing -and -not $PSBoundParameters.ContainsKey('RequestorScope') -and
        $Existing.ContainsKey('automaticRequestSettings') -and $null -ne $Existing['automaticRequestSettings']) {
        $Body.automaticRequestSettings = $Existing['automaticRequestSettings']
    }

    $Body
}
