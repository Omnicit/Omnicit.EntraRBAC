function ConvertTo-OERRoleManagementPolicy {
    <#
    .SYNOPSIS
    Converts a role management policy's rules (Azure or Microsoft Entra directory role) into a tagged
    friendly object.

    .DESCRIPTION
    Maps the polymorphic roleManagementPolicy rules (matched by their stable id strings) into a
    flat, readable Omnicit.EntraRBAC.RoleManagementPolicy object: activation window, MFA /
    justification / ticket requirements, approval and approvers, authentication context, eligible
    and active permanence plus max durations, and a notifications summary, alongside the raw
    EffectiveRules. Accepts rules from either the assignment effectiveRules or the policy rules. When
    -ChangedRuleId is supplied (by a Set cmdlet) a ChangedRuleIds property is added.
    This private helper is the single owner of the friendly policy shape for BOTH transports: Azure
    Resource Manager policies and Microsoft Entra directory-role policies read from Microsoft Graph
    v1.0, which share the rule ids and field names. Only the approver shape differs, which
    -ApproverShape selects; everything else, the type name included, is the same object.
    EligibleDurationDays and ActiveDurationDays carry the same maximum lifetimes parsed into whole
    days (null when the policy stores a non-whole-day duration), because Set-OERRoleManagementPolicy
    and the apply document express them in days.

    .PARAMETER Rules
    The policy rules array (effectiveRules from an assignment, or rules from a policy resource).

    .PARAMETER PolicyId
    The id of the policy: the full ARM id for an Azure policy, the Graph policy id for a directory
    role.

    .PARAMETER Scope
    The scope of the policy: the ARM scope for an Azure policy, '/' for a directory role.

    .PARAMETER RoleName
    The role display name (when known; null on a bare policy GET).

    .PARAMETER RoleDefinitionId
    The role definition id (when known): the full ARM role definition id for an Azure policy.

    .PARAMETER ChangedRuleId
    The rule ids that were just patched (added as a ChangedRuleIds property on Set output).

    .PARAMETER ApproverShape
    Which approver shape the approval rule carries. Arm (the default) reads each primary approver's
    id, userType and description. Graph reads each one through ConvertFrom-OERGraphApprover, the
    single reader of a Graph approver (v1.0 userId / groupId, with a beta-style id as the fallback,
    and the kind from @odata.type); the projected approver has the same DisplayName, Id and UserType
    properties either way. A v1.0 approver carries no id or userType, so read with the ARM default
    it would project with an empty Id.

    .EXAMPLE
    ConvertTo-OERRoleManagementPolicy -Rules $Rules -PolicyId $PolicyId -Scope $Scope -RoleName 'Reader'
    Returns the tagged friendly policy summary for the Reader role.

    .EXAMPLE
    ConvertTo-OERRoleManagementPolicy -Rules $Rules -PolicyId $PolicyId -Scope '/' -ApproverShape Graph
    Returns the tagged friendly summary of a directory-role policy read from Microsoft Graph, with its
    approvers projected from the Graph approver shape.
    #>
    [OutputType([PSCustomObject])]
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [object[]]$Rules,

        [Parameter(Mandatory)]
        [string]$PolicyId,

        [string]$Scope,
        [string]$RoleName,
        [string]$RoleDefinitionId,
        [string[]]$ChangedRuleId,

        [ValidateSet('Arm', 'Graph')]
        [string]$ApproverShape = 'Arm'
    )
    $ById = @{}
    foreach ($Rule in $Rules) { if ($Rule.id) { $ById[[string]$Rule.id] = $Rule } }

    $Activation = $ById['Expiration_EndUser_Assignment']
    $ActivationMaxHours = $null
    if ($Activation -and $Activation.maximumDuration -match '^PT(\d+)H$') { $ActivationMaxHours = [int]$Matches[1] }

    $EndUserEnable  = $ById['Enablement_EndUser_Assignment']
    $AdminAsgEnable = $ById['Enablement_Admin_Assignment']
    $EligExp        = $ById['Expiration_Admin_Eligibility']
    $ActiveExp      = $ById['Expiration_Admin_Assignment']
    $Approval       = $ById['Approval_EndUser_Assignment']
    $Ctx            = $ById['AuthenticationContext_EndUser_Assignment']

    $Approvers = [System.Collections.Generic.List[object]]::new()
    if ($Approval -and $Approval.setting.approvalStages) {
        foreach ($Stage in @($Approval.setting.approvalStages)) {
            foreach ($Approver in @($Stage.primaryApprovers)) {
                if ($null -eq $Approver) { continue }
                if ($ApproverShape -eq 'Graph') {
                    # Same DisplayName / Id / UserType properties, read from the Graph shape.
                    $Approvers.Add((ConvertFrom-OERGraphApprover -Approver $Approver))
                    continue
                }
                $Approvers.Add([PSCustomObject]@{
                    DisplayName = [string]$Approver.description
                    Id          = [string]$Approver.id
                    UserType    = [string]$Approver.userType
                })
            }
        }
    }

    $Notifications = [System.Collections.Generic.List[object]]::new()
    foreach ($Rule in $Rules) {
        if ([string]$Rule.id -like 'Notification_*') {
            $Notifications.Add([PSCustomObject]@{
                Id                       = [string]$Rule.id
                RecipientType            = [string]$Rule.recipientType
                Level                    = [string]$Rule.notificationLevel
                DefaultRecipientsEnabled = [bool]$Rule.isDefaultRecipientsEnabled
                Recipients               = @($Rule.notificationRecipients)
            })
        }
    }

    # Set-OERRoleManagementPolicy and the apply document both speak whole days, while ARM stores an
    # ISO 8601 duration. Surface the parsed day count alongside the raw string (the same pairing
    # Get-OERGroupPimPolicy exposes) so a Get result can be diffed against a declared day count
    # without every caller re-parsing. Parsed through the single read-side owner ConvertFrom-OERDuration
    # (the mirror of the write-side ConvertTo-OERDuration) rather than an anchored whole-day regex, so a
    # policy holding P1Y or P6M is read as a day count instead of silently becoming null. Only a value
    # that amounts to a WHOLE number of days is reported; a fractional day (for example PT12H) still
    # stays null rather than being truncated.
    $EligibleDurationDays = ConvertFrom-OERDuration -Duration ([string]$EligExp.maximumDuration) -Unit Days
    $ActiveDurationDays = ConvertFrom-OERDuration -Duration ([string]$ActiveExp.maximumDuration) -Unit Days

    $Out = [PSCustomObject]@{
        PolicyId                               = $PolicyId
        Scope                                  = $Scope
        RoleName                               = $RoleName
        RoleDefinitionId                       = $RoleDefinitionId
        ActivationMaxHours                     = $ActivationMaxHours
        RequireMfaOnActivation                 = [bool](@($EndUserEnable.enabledRules) -contains 'MultiFactorAuthentication')
        RequireJustificationOnActivation       = [bool](@($EndUserEnable.enabledRules) -contains 'Justification')
        RequireTicketOnActivation              = [bool](@($EndUserEnable.enabledRules) -contains 'Ticketing')
        RequireApproval                        = [bool]$Approval.setting.isApprovalRequired
        Approvers                              = $Approvers.ToArray()
        AuthenticationContextId                = $(if ($Ctx -and $Ctx.isEnabled) { [string]$Ctx.claimValue } else { $null })
        AllowPermanentEligibility              = $(if ($EligExp) { -not [bool]$EligExp.isExpirationRequired } else { $null })
        EligibleDuration                       = $(if ($EligExp) { [string]$EligExp.maximumDuration } else { $null })
        EligibleDurationDays                   = $EligibleDurationDays
        AllowPermanentActiveAssignment         = $(if ($ActiveExp) { -not [bool]$ActiveExp.isExpirationRequired } else { $null })
        ActiveDuration                         = $(if ($ActiveExp) { [string]$ActiveExp.maximumDuration } else { $null })
        ActiveDurationDays                     = $ActiveDurationDays
        RequireMfaOnActiveAssignment           = [bool](@($AdminAsgEnable.enabledRules) -contains 'MultiFactorAuthentication')
        RequireJustificationOnActiveAssignment = [bool](@($AdminAsgEnable.enabledRules) -contains 'Justification')
        Notifications                          = $Notifications.ToArray()
        EffectiveRules                         = $Rules
    }
    if ($PSBoundParameters.ContainsKey('ChangedRuleId')) {
        $Out | Add-Member -NotePropertyName ChangedRuleIds -NotePropertyValue $ChangedRuleId
    }
    $Out.PSObject.TypeNames.Insert(0, 'Omnicit.EntraRBAC.RoleManagementPolicy')
    $Out
}
