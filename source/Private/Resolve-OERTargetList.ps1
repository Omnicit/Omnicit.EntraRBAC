function Resolve-OERTargetList {
    <#
    .SYNOPSIS
    Resolves user and group names or ids into Microsoft Graph approver/target objects.

    .DESCRIPTION
    Shared by the access package policy builder cmdlets. For each value in -User and -Group, a GUID
    is treated as an object id and any other value is resolved (users via Resolve-OERUserId by user
    principal name, groups via Resolve-OERGroupId by display name) into the corresponding Graph
    approver object using New-OERApproverObject. Authentication is lazy: Initialize-OERAuth is called
    only when at least one value is a non-GUID name, so a pure-GUID input performs no auth and no
    Graph call. Resolution stops at the first value that cannot be resolved. Returns a hashtable with
    keys Approvers (the resolved approver objects), FailedKind ('User', 'Group', or $null), and
    FailedValue (the offending value, or $null). The caller routes a non-null FailedValue as a
    non-terminating error.

    FailedErrorId and FailedMessage are optional companions to FailedKind/FailedValue, mirroring the
    channel Resolve-OERAccessReviewScopeTarget already exposes. They are $null for a plain not-found,
    so the caller's existing "<Kind> '<Value>' not found." error is unchanged, and are populated for an
    AMBIGUOUS group display name, where the resolver's own message naming the candidate object ids is
    far more actionable than a not-found. A caller prefers them whenever they are present. This is why
    an ambiguity is reported through the descriptor rather than thrown: a bare throw out of this helper
    would terminate the calling public cmdlet and defeat -ErrorAction SilentlyContinue.

    .PARAMETER User
    Zero or more user principal names or user object ids (GUIDs) to resolve to singleUser approver
    objects.

    .PARAMETER Group
    Zero or more group display names or group object ids (GUIDs) to resolve to groupMembers approver
    objects.

    .PARAMETER TenantId
    Optional tenant id or domain forwarded to Initialize-OERAuth when authentication is needed.

    .EXAMPLE
    Resolve-OERTargetList -User 'anna.berg@contoso.com' -Group 'Sales Team'
    Resolves the user and group to approver objects, authenticating once because names are present.
    #>
    [OutputType([hashtable])]
    [CmdletBinding()]
    param(
        [string[]]$User,
        [string[]]$Group,
        [string]$TenantId
    )

    $HasName = @(@($User) + @($Group) | Where-Object { $_ -and -not (Test-OERGuid -Value $_) }).Count -gt 0
    if ($HasName) {
        $AuthParams = @{}
        if ($TenantId) { $AuthParams.TenantId = $TenantId }
        Initialize-OERAuth @AuthParams
    }

    # Same failure-descriptor shape as Resolve-OERAccessReviewScopeTarget: the optional ErrId/Msg
    # companions let a caller report what actually failed instead of its generic not-found text.
    $Fail = {
        param($Kind, $Value, $ErrId, $Msg)
        @{
            Approvers     = @()
            FailedKind    = $Kind
            FailedValue   = $Value
            FailedErrorId = $ErrId
            FailedMessage = $Msg
        }
    }

    $Approvers = @()
    foreach ($U in @($User)) {
        if (-not $U) { continue }
        $UserId = try { Resolve-OERUserId -UserPrincipalName $U } catch { Remove-OERErrorRecord -Record $PSItem; $null }
        if (-not $UserId) {
            return (& $Fail 'User' $U)
        }
        $Approvers += New-OERApproverObject -Spec @{ User = $UserId }
    }
    foreach ($G in @($Group)) {
        if (-not $G) { continue }
        # An ambiguous display name travels through the descriptor's ErrorId/message companions so the
        # calling cmdlet reports it as a non-terminating error naming the candidate ids, rather than
        # flattening it into the misleading "Group '<name>' not found.".
        $GroupId = $null
        try {
            $GroupId = Resolve-OERGroupId -DisplayName $G
        } catch {
            Remove-OERErrorRecord -Record $PSItem
            if (Test-OERAmbiguousNameError -Record $PSItem) {
                return (& $Fail 'Group' $G 'AmbiguousGroupName' $PSItem.Exception.Message)
            }
        }
        if (-not $GroupId) {
            return (& $Fail 'Group' $G)
        }
        $Approvers += New-OERApproverObject -Spec @{ Group = $GroupId }
    }
    return @{
        Approvers     = @($Approvers)
        FailedKind    = $null
        FailedValue   = $null
        FailedErrorId = $null
        FailedMessage = $null
    }
}
