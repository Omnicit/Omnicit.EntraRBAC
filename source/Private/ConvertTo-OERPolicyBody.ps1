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
    supplied, the corresponding value is carried forward from it; otherwise a New-default is applied.
    -Existing is the raw Graph hashtable and is read by key/dot access, never via .PSObject.Properties.
    The description is always emitted: an explicit -Description wins, otherwise it is carried forward
    from -Existing, and only on New (no -Existing) does it default to the display name. Expiration is
    afterDuration when -DurationInDays or -DurationInHours is given, afterDateTime
    when -ExpirationDateTime is given, the carried-forward -Existing expiration when present, otherwise
    noExpiration. reviewSettings and questions are preserved verbatim from -Existing when present and are
    omitted entirely on New. -RequestorScope follows the same overlay: when supplied its
    allowedTargetScope and specificAllowedTargets win; when omitted, both are carried forward from
    -Existing together as a single unit (never mixed from different sources), so a read-modify-write Set
    that only changes an unrelated field never resets a live SpecificDirectoryUsers scope back to a
    default. Omitting -RequestorScope with no -Existing baseline (New, with no scope supplied) is a
    caller error and throws.

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
    Values not provided as parameters are carried forward from it, and reviewSettings and questions are
    preserved verbatim. Absent on New.

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
            throw '-RequestorScope must be an object from New-OERAccessPackageRequestorScope.'
        }
    } elseif (-not $Existing) {
        throw '-RequestorScope is required when no -Existing policy is supplied.'
    }
    if ($PSBoundParameters.ContainsKey('RequestorSettings') -and
        $RequestorSettings.PSObject.TypeNames -notcontains 'Omnicit.EntraRBAC.RequestorSettings') {
        throw '-RequestorSettings must be an object from New-OERAccessPackageRequestorSettings.'
    }

    $Stages = @()
    foreach ($Stage in @($ApprovalStage)) {
        if ($null -eq $Stage) { continue }
        if ($Stage.PSObject.TypeNames -notcontains 'Omnicit.EntraRBAC.ApprovalStage') {
            throw '-ApprovalStage entries must be objects from New-OERAccessPackageApprovalStage.'
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
    } elseif ($Existing -and $Existing.expiration) {
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

    $ExistingApproval = if ($Existing) { $Existing.requestApprovalSettings } else { $null }

    # stages: provided ApprovalStage wins, else carry from Existing, else empty.
    $ResolvedStages = if ($PSBoundParameters.ContainsKey('ApprovalStage')) {
        @($Stages)
    } elseif ($ExistingApproval -and $ExistingApproval.stages) {
        @($ExistingApproval.stages)
    } else {
        @()
    }

    # isApprovalRequiredForAdd: explicit flag wins, else derived from provided stages, else carry, else false.
    $ResolvedRequireApproval = if ($PSBoundParameters.ContainsKey('RequireApproval')) {
        [bool]$RequireApproval
    } elseif ($PSBoundParameters.ContainsKey('ApprovalStage')) {
        [bool]($Stages.Count -gt 0)
    } elseif ($ExistingApproval) {
        [bool]$ExistingApproval.isApprovalRequiredForAdd
    } else {
        $false
    }

    $ResolvedRequireJustification = if ($PSBoundParameters.ContainsKey('RequireRequestorJustification')) {
        [bool]$RequireRequestorJustification
    } elseif ($ExistingApproval) {
        [bool]$ExistingApproval.isRequestorJustificationRequired
    } else {
        $false
    }

    $ResolvedRequireApprovalForUpdate = if ($PSBoundParameters.ContainsKey('RequireApprovalForUpdate')) {
        [bool]$RequireApprovalForUpdate
    } elseif ($ExistingApproval) {
        [bool]$ExistingApproval.isApprovalRequiredForUpdate
    } else {
        $false
    }

    # notificationSettings: explicit flag wins, else carry from Existing, else not-disabled New-default.
    $ResolvedNotificationSettings = if ($PSBoundParameters.ContainsKey('DisableAssignmentNotifications')) {
        @{ isAssignmentNotificationDisabled = [bool]$DisableAssignmentNotifications }
    } elseif ($Existing -and $Existing.notificationSettings) {
        $Existing.notificationSettings
    } else {
        @{ isAssignmentNotificationDisabled = $false }
    }

    # requestorScope: provided builder wins, else carry the live scope AND its specific targets from
    # Existing as a unit. Rewriting them from a default would silently reset a live
    # SpecificDirectoryUsers scope whenever an unrelated field is updated.
    $ResolvedAllowedTargetScope = if ($PSBoundParameters.ContainsKey('RequestorScope')) {
        $RequestorScope.AllowedTargetScope
    } elseif ($Existing -and $Existing.allowedTargetScope) {
        $Existing.allowedTargetScope
    } else {
        $null
    }
    $ResolvedSpecificTargets = if ($PSBoundParameters.ContainsKey('RequestorScope')) {
        @($RequestorScope.SpecificAllowedTargets)
    } elseif ($Existing -and $Existing.specificAllowedTargets) {
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
    if ($Existing -and $Existing.reviewSettings) { $Body.reviewSettings = $Existing.reviewSettings }
    if ($Existing -and $Existing.questions) { $Body.questions = $Existing.questions }

    $Body
}
