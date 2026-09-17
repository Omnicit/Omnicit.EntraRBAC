function ConvertTo-OERAssignmentPolicy {
    <#
    .SYNOPSIS
    Converts a raw Graph accessPackageAssignmentPolicy into a tagged Omnicit.EntraRBAC.AssignmentPolicy.

    .DESCRIPTION
    Maps every relevant property of a Graph assignment policy into a [PSCustomObject] tagged
    Omnicit.EntraRBAC.AssignmentPolicy. This is the single read-normalizer used by
    Get-OERAccessPackageAssignmentPolicy and Get-OERInventory, and -- re-run over a freshly built body
    from ConvertTo-OERPolicyBody (same camelCase shape) -- by the apply-time diff, so it must produce an
    identical projection from either a raw Graph hashtable or a built body. All inputs are read via
    dot/key access (which works on both hashtables and PSObjects); .PSObject.Properties is never used on
    the input.

    The projection surfaces the description, the requestor scope (friendly scope plus the specific target
    user/group ids), the requestor settings (self-service and on-behalf toggles plus manager level), the
    approval toggles, the full per-stage approver sets (manager, users, groups, internal/external
    sponsors, escalation approvers, escalation days, approver-justification flag and approver-information
    visibility), the expiration (days, hours, or a fixed date-time), and the notification toggle. All
    GUID lists are lowercased and sorted so a downstream set comparison is order- and case-insensitive.

    DurationInDays is parsed from an afterDuration expiration's ISO 8601 duration when it is a whole-day
    multiple, otherwise DurationInHours is set. The access package id is read from the expanded
    accessPackage relationship (accessPackage.id); on v1.0 the policy resource has no scalar
    accessPackageId property, so a GET must request $expand=accessPackage for this to be populated. The
    create/update paths, which already know the package id but receive a response without the expanded
    relationship, can supply it via -AccessPackageId.

    .PARAMETER InputObject
    The raw Graph assignment policy object (hashtable or PSObject) to convert.

    .PARAMETER AccessPackageId
    Optional explicit access package id used to populate the output when the input object does not carry
    an expanded accessPackage relationship (for example a create or update response). When omitted the id
    is read from InputObject.accessPackage.id.

    .EXAMPLE
    ConvertTo-OERAssignmentPolicy -InputObject $policy
    Converts a single assignment policy into a tagged object.

    .EXAMPLE
    $Policies | ConvertTo-OERAssignmentPolicy
    Converts each raw Graph assignment policy in the pipeline into a tagged object.
    #>
    [OutputType([PSCustomObject])]
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
        $InputObject,

        [string]$AccessPackageId
    )
    process {
        # -- Local helpers (closures over $InputObject not needed; pure transforms) --------
        # Collect lowercased+sorted ids of a given odata subjectSet type from a target list.
        $CollectIds = {
            param($Targets, $TypeMatch, $IdKey)
            $Ids = foreach ($Target in @($Targets)) {
                if ($null -eq $Target) { continue }
                if ([string]$Target.'@odata.type' -match $TypeMatch) {
                    $Id = [string]$Target.$IdKey
                    if (-not [string]::IsNullOrEmpty($Id)) { $Id.ToLowerInvariant() }
                }
            }
            @($Ids | Sort-Object)
        }

        # -- Expiration (days / hours / date-time) -----------------------------------------
        $DurationInDays = $null
        $DurationInHours = $null
        $ExpirationDateTime = $null
        $Expiration = $InputObject.expiration
        if ($Expiration -and $Expiration.type -eq 'afterDuration' -and $Expiration.duration) {
            try {
                $Span = [System.Xml.XmlConvert]::ToTimeSpan([string]$Expiration.duration)
                if ($Span.TotalDays -ge 1 -and [Math]::Floor($Span.TotalDays) -eq $Span.TotalDays) {
                    $DurationInDays = [int]$Span.TotalDays
                } else {
                    $DurationInHours = [int]$Span.TotalHours
                }
            } catch {
                Remove-OERErrorRecord -Record $PSItem
                $DurationInDays = $null
                $DurationInHours = $null
            }
        } elseif ($Expiration -and $Expiration.type -eq 'afterDateTime' -and $Expiration.endDateTime) {
            $ExpirationDateTime = [string]$Expiration.endDateTime
        }
        # A non-positive day count (a degenerate value) is not a meaningful lifetime -- treat it as no
        # duration so it omits cleanly and round-trips (the schema requires durationInDays >= 1).
        if ($null -ne $DurationInDays -and $DurationInDays -le 0) { $DurationInDays = $null }
        # A sub-day duration that truncates to 0 hours is likewise not meaningful.
        if ($null -ne $DurationInHours -and $DurationInHours -le 0) { $DurationInHours = $null }

        $PackageId = if ($AccessPackageId) { $AccessPackageId } else { $InputObject.accessPackage.id }

        # -- Requestor scope (friendly inverse of allowedTargetScope + specific targets) ----
        $ScopeFriendlyMap = @{
            allMemberUsers                          = 'AllMemberUsers'
            allDirectoryUsers                       = 'AllDirectoryUsers'
            specificDirectoryUsers                  = 'SpecificDirectoryUsers'
            specificConnectedOrganizationUsers      = 'SpecificConnectedOrganizationUsers'
            allConfiguredConnectedOrganizationUsers = 'AllConfiguredConnectedOrganizationUsers'
            # Dead in practice, kept deliberately: Graph cannot return an allowedTargetScope its own
            # v1.0 enum does not contain, so this row never fires. Do NOT "restore symmetry" by
            # mirroring it back into New-OERAccessPackageRequestorScope's WRITE map -- that map
            # sends NoSubjects as notSpecified on purpose (issue #86), since noSubjects on the wire
            # is rejected with 'InvalidModel: The model is invalid.'
            noSubjects                              = 'NoSubjects'
            notSpecified                            = 'NotSpecified'
        }
        $RawScope = [string]$InputObject.allowedTargetScope
        $RequestorScope = $null
        if (-not [string]::IsNullOrEmpty($RawScope)) {
            $FriendlyScope = if ($ScopeFriendlyMap.ContainsKey($RawScope)) { $ScopeFriendlyMap[$RawScope] } else { $RawScope }
            $RequestorScope = [PSCustomObject]@{
                scope  = $FriendlyScope
                users  = @(& $CollectIds $InputObject.specificAllowedTargets 'singleUser' 'userId')
                groups = @(& $CollectIds $InputObject.specificAllowedTargets 'groupMembers' 'groupId')
            }
        }

        # -- Requestor settings (self-service + on-behalf toggles) -------------------------
        $Rs = $InputObject.requestorSettings
        $ManagerLevel = 1
        foreach ($OnBehalf in @($Rs.onBehalfRequestors)) {
            if ($null -eq $OnBehalf) { continue }
            if ([string]$OnBehalf.'@odata.type' -match 'requestorManager') {
                if ($null -ne $OnBehalf.managerLevel) { $ManagerLevel = [int]$OnBehalf.managerLevel }
                break
            }
        }
        $RequestorSettings = [PSCustomObject]@{
            allowSelfRequest    = [bool]$Rs.enableTargetsToSelfAddAccess
            allowManagerRequest = [bool]$Rs.enableOnBehalfRequestorsToAddAccess
            managerLevel        = $ManagerLevel
            allowCustomSchedule = [bool]$Rs.allowCustomAssignmentSchedule
            allowSelfExtend     = [bool]$Rs.enableTargetsToSelfUpdateAccess
            allowSelfRemove     = [bool]$Rs.enableTargetsToSelfRemoveAccess
            allowOnBehalfUpdate = [bool]$Rs.enableOnBehalfRequestorsToUpdateAccess
            allowOnBehalfRemove = [bool]$Rs.enableOnBehalfRequestorsToRemoveAccess
        }

        # -- Approval toggles --------------------------------------------------------------
        $Approval = $InputObject.requestApprovalSettings
        $RequireApproval = [bool]$Approval.isApprovalRequiredForAdd
        $RequireRequestorJustification = [bool]$Approval.isRequestorJustificationRequired
        $RequireApprovalForUpdate = [bool]$Approval.isApprovalRequiredForUpdate

        # -- Approval stages (full approver projection) ------------------------------------
        $VisibilityMap = @{
            default    = 'Default'
            visible    = 'Visible'
            notvisible = 'NotVisible'
        }
        $ApprovalStages = [System.Collections.Generic.List[object]]::new()
        foreach ($Stage in @($Approval.stages)) {
            if ($null -eq $Stage) { continue }

            $StageDays = $null
            if ($Stage.durationBeforeAutomaticDenial) {
                try {
                    $StageDays = [int][System.Xml.XmlConvert]::ToTimeSpan([string]$Stage.durationBeforeAutomaticDenial).TotalDays
                } catch {
                    Remove-OERErrorRecord -Record $PSItem
                    $StageDays = $null
                }
            }

            $HasManager = $false
            $HasInternalSponsor = $false
            $HasExternalSponsor = $false
            $StageManagerLevel = 1
            foreach ($Approver in @($Stage.primaryApprovers)) {
                if ($null -eq $Approver) { continue }
                $OdataType = [string]$Approver.'@odata.type'
                if ($OdataType -match 'requestorManager') {
                    $HasManager = $true
                    if ($null -ne $Approver.managerLevel) { $StageManagerLevel = [int]$Approver.managerLevel }
                } elseif ($OdataType -match 'internalSponsors') {
                    $HasInternalSponsor = $true
                } elseif ($OdataType -match 'externalSponsors') {
                    $HasExternalSponsor = $true
                }
            }

            $EscalationDays = $null
            if ([bool]$Stage.isEscalationEnabled -and $Stage.durationBeforeEscalation) {
                try {
                    $EscalationDays = [int][System.Xml.XmlConvert]::ToTimeSpan([string]$Stage.durationBeforeEscalation).TotalDays
                } catch {
                    Remove-OERErrorRecord -Record $PSItem
                    $EscalationDays = $null
                }
            }

            $RawVisibility = [string]$Stage.approverInformationVisibility
            $Visibility = if (-not [string]::IsNullOrEmpty($RawVisibility) -and $VisibilityMap.ContainsKey($RawVisibility.ToLowerInvariant())) {
                $VisibilityMap[$RawVisibility.ToLowerInvariant()]
            } else {
                'Default'
            }

            $ApprovalStages.Add([PSCustomObject]@{
                    durationDays                 = $StageDays
                    manager                      = $HasManager
                    managerLevel                 = $StageManagerLevel
                    users                        = @(& $CollectIds $Stage.primaryApprovers 'singleUser' 'userId')
                    groups                       = @(& $CollectIds $Stage.primaryApprovers 'groupMembers' 'groupId')
                    internalSponsor              = $HasInternalSponsor
                    externalSponsor              = $HasExternalSponsor
                    alternateUsers               = @(& $CollectIds $Stage.escalationApprovers 'singleUser' 'userId')
                    alternateGroups              = @(& $CollectIds $Stage.escalationApprovers 'groupMembers' 'groupId')
                    fallbackUsers                = @(& $CollectIds $Stage.fallbackPrimaryApprovers 'singleUser' 'userId')
                    fallbackGroups               = @(& $CollectIds $Stage.fallbackPrimaryApprovers 'groupMembers' 'groupId')
                    escalationDays               = $EscalationDays
                    requireApproverJustification = [bool]$Stage.isApproverJustificationRequired
                    approverInfoVisibility       = $Visibility
                })
        }

        $Out = [PSCustomObject]@{
            Id                            = $InputObject.id
            DisplayName                   = $InputObject.displayName
            AccessPackageId               = $PackageId
            AllowedTargetScope            = $InputObject.allowedTargetScope
            Description                   = $InputObject.description
            RequestorScope                = $RequestorScope
            RequestorSettings             = $RequestorSettings
            RequireApproval               = $RequireApproval
            RequireRequestorJustification = $RequireRequestorJustification
            RequireApprovalForUpdate      = $RequireApprovalForUpdate
            ApprovalStages                = $ApprovalStages.ToArray()
            DurationInDays                = $DurationInDays
            DurationInHours               = $DurationInHours
            ExpirationDateTime            = $ExpirationDateTime
            NotificationsDisabled         = [bool]$InputObject.notificationSettings.isAssignmentNotificationDisabled
        }
        $Out.PSObject.TypeNames.Insert(0, 'Omnicit.EntraRBAC.AssignmentPolicy')
        $Out
    }
}
