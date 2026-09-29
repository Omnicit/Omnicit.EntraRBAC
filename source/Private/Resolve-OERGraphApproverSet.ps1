function Resolve-OERGraphApproverSet {
    <#
    .SYNOPSIS
    Computes the approvers a Microsoft Graph PIM approval rule will carry after a Set call.

    .DESCRIPTION
    The single owner of the Microsoft Graph approver semantics shared by Set-OERGroupPimPolicy and
    Set-OERDirectoryRoleManagementPolicy. Given the live Approval_EndUser_Assignment rule and what
    the caller bound, it decides the effective approvers and whether approval can be required:

      - Only the FIRST approval stage counts (PIM uses one). Its primary approvers are read through
        ConvertFrom-OERGraphApprover, the single reader of a Graph approver, so a beta-shaped { id }
        approver and a v1.0 userId / groupId approver are both understood (LivePrimary).
      - A bound side replaces that side: EffUser is the resolved user ids when -UserBound, otherwise
        the live user approver ids; EffGroup likewise for groups. An explicit empty list clears its
        side.
      - A live approver of any OTHER kind (a requestorManager, for example) belongs to neither side,
        so no parameter replaces it: it is returned in LiveOther as the very object that was read,
        for the caller to send back unchanged.
      - Supplying approvers on either side implies approval is required (EffRequired $true);
        otherwise -RequireApproval decides when it is bound, and EffRequired is $false when neither
        is bound.
      - ApproverCount is what will be sent: with approvers bound, EffUser + EffGroup + LiveOther;
        otherwise the live primary approvers as they are (every kind counted).
      - NoApprover is $true when approval is required with ApproverCount 0. NoApproverReason says
        why: 'Bound' (the bound approver parameters left none), 'Live' (the live rule has none and
        none was supplied), or '' when NoApprover is $false.

    The ApproverRequired message stays with each caller, chosen by NoApproverReason, because it names
    the caller's own policy. Pure; no Graph call.

    .PARAMETER LiveApprovalRule
    The live Approval_EndUser_Assignment rule as read from Microsoft Graph (hashtable or
    PSCustomObject). $null, or a rule without a setting or stage, has no approvers.

    .PARAMETER UserBound
    Whether the caller bound -ApproverUser (even to an empty list).

    .PARAMETER GroupBound
    Whether the caller bound -ApproverGroup (even to an empty list).

    .PARAMETER ResolvedUser
    The user object ids the caller resolved (Resolve-OERApproverInput); used only when -UserBound.

    .PARAMETER ResolvedGroup
    The group object ids the caller resolved (Resolve-OERApproverInput); used only when -GroupBound.

    .PARAMETER RequireApprovalBound
    Whether the caller bound -RequireApproval.

    .PARAMETER RequireApproval
    The bound -RequireApproval value; used only when -RequireApprovalBound and no approver is bound.

    .EXAMPLE
    Resolve-OERGraphApproverSet -LiveApprovalRule $Rule -UserBound $true -GroupBound $false -ResolvedUser $Ids -RequireApprovalBound $false -RequireApproval $false
    Returns the bound users as EffUser, the live group approvers as EffGroup, the live approvers of
    any other kind in LiveOther, and EffRequired $true.
    #>
    [OutputType([PSCustomObject])]
    [CmdletBinding()]
    param(
        [AllowNull()]
        [object]$LiveApprovalRule,

        [bool]$UserBound,

        [bool]$GroupBound,

        [AllowNull()]
        [AllowEmptyCollection()]
        [string[]]$ResolvedUser,

        [AllowNull()]
        [AllowEmptyCollection()]
        [string[]]$ResolvedGroup,

        [bool]$RequireApprovalBound,

        [bool]$RequireApproval
    )

    $LiveStage = $null
    if ($null -ne $LiveApprovalRule -and $null -ne $LiveApprovalRule.setting) {
        $LiveStage = @($LiveApprovalRule.setting.approvalStages) | Where-Object { $null -ne $_ } | Select-Object -First 1
    }
    $LivePrimary = @()
    $LiveOther = @()
    if ($null -ne $LiveStage) {
        $LivePrimary = @(@($LiveStage.primaryApprovers) | ForEach-Object { ConvertFrom-OERGraphApprover -Approver $_ })
        $LiveOther = @(@($LiveStage.primaryApprovers) | Where-Object {
                $null -ne $_ -and (ConvertFrom-OERGraphApprover -Approver $_).UserType -eq ''
            })
    }

    $BoundUserIds = @(@($ResolvedUser) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    $BoundGroupIds = @(@($ResolvedGroup) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    $EffUser = @(if ($UserBound) { $BoundUserIds } else { $LivePrimary | Where-Object { $_.UserType -eq 'User' -and $_.Id } | ForEach-Object { $_.Id } })
    $EffGroup = @(if ($GroupBound) { $BoundGroupIds } else { $LivePrimary | Where-Object { $_.UserType -eq 'Group' -and $_.Id } | ForEach-Object { $_.Id } })

    $ApproversBound = $UserBound -or $GroupBound
    $EffRequired = if ($ApproversBound) { $true } elseif ($RequireApprovalBound) { $RequireApproval } else { $false }
    $ApproverCount = if ($ApproversBound) { $EffUser.Count + $EffGroup.Count + $LiveOther.Count } else { $LivePrimary.Count }
    $NoApprover = [bool]($EffRequired -and $ApproverCount -eq 0)
    $NoApproverReason = if (-not $NoApprover) { '' } elseif ($ApproversBound) { 'Bound' } else { 'Live' }

    [PSCustomObject]@{
        EffUser          = [string[]]$EffUser
        EffGroup         = [string[]]$EffGroup
        LiveOther        = $LiveOther
        LivePrimary      = $LivePrimary
        EffRequired      = [bool]$EffRequired
        ApproverCount    = $ApproverCount
        NoApprover       = $NoApprover
        NoApproverReason = $NoApproverReason
    }
}
