function ConvertTo-OERRoleManagementPolicy {
    <#
    .SYNOPSIS
    Converts an Azure role management policy's rules into a tagged friendly object.

    .DESCRIPTION
    Maps the polymorphic ARM roleManagementPolicy rules (matched by their stable id strings) into a
    flat, readable Omnicit.EntraRBAC.RoleManagementPolicy object: activation window, MFA /
    justification / ticket requirements, approval and approvers, authentication context, eligible
    and active permanence plus max durations, and a notifications summary, alongside the raw
    EffectiveRules. Accepts rules from either the assignment effectiveRules or the policy rules. When
    -ChangedRuleId is supplied (by Set-OERRoleManagementPolicy) a ChangedRuleIds property is added.
    This private helper is the single owner of the friendly policy shape. EligibleDurationDays and
    ActiveDurationDays carry the same maximum lifetimes parsed into whole days (null when the policy
    stores a non-whole-day duration), because Set-OERRoleManagementPolicy and the apply document
    express them in days.

    .PARAMETER Rules
    The policy rules array (effectiveRules from an assignment, or rules from a policy resource).

    .PARAMETER PolicyId
    The full ARM id of the policy.

    .PARAMETER Scope
    The ARM scope of the policy.

    .PARAMETER RoleName
    The role display name (when known; null on a bare policy GET).

    .PARAMETER RoleDefinitionId
    The full ARM role definition id (when known).

    .PARAMETER ChangedRuleId
    The rule ids that were just patched (added as a ChangedRuleIds property on Set output).

    .EXAMPLE
    ConvertTo-OERRoleManagementPolicy -Rules $Rules -PolicyId $PolicyId -Scope $Scope -RoleName 'Reader'
    Returns the tagged friendly policy summary for the Reader role.
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
        [string[]]$ChangedRuleId
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
