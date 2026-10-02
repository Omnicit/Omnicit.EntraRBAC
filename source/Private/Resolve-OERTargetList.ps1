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
    Graph call. Resolution stops at the first value that does not resolve or whose lookup fails.
    Returns a hashtable with keys Approvers (the resolved approver objects), FailedKind ('User',
    'Group', or $null), FailedValue (the offending value, or $null) and the three optional companions
    FailedErrorId, FailedMessage and FailedRecord, described below. The caller routes a non-null
    FailedValue as a non-terminating error.

    FailedErrorId and FailedMessage are optional companions to FailedKind/FailedValue, mirroring the
    channel Resolve-OERAccessReviewScopeTarget already exposes. They are $null for a plain not-found,
    so the caller's existing "<Kind> '<Value>' not found." error is unchanged, and are populated for an
    AMBIGUOUS group display name, where the resolver's own message naming the candidate object ids is
    far more actionable than a not-found. A caller prefers them whenever they are present. This is why
    an ambiguity is reported through the descriptor rather than thrown: a bare throw out of this helper
    would terminate the calling public cmdlet and defeat -ErrorAction SilentlyContinue.

    FailedRecord is the carrier for a lookup that FAILED rather than found nothing. It holds the caught
    ErrorRecord when Resolve-OERUserId or Resolve-OERGroupId throws anything other than an ambiguous
    group display name -- a 403, an exhausted 429, a 5xx -- and is $null on every other descriptor,
    success included, so a caller can test it without a property check. A refused read is not evidence
    that no such user or group exists, so FailedKind/FailedValue still name the lookup but the caller
    re-publishes FailedRecord as itself instead of "<Kind> '<Value>' not found." FailedErrorId and
    FailedMessage stay $null on that path on purpose: a caller reads the mere presence of FailedErrorId
    as a bad argument, which would label a refused read InvalidArgument. Only a $null return (a name
    that matched nothing) is a not-found.

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
    # companions let a caller report what actually failed instead of its generic not-found text, and
    # Rec carries the caught ErrorRecord of a lookup that threw (see FailedRecord in the help).
    $Fail = {
        param($Kind, $Value, $ErrId, $Msg, $Rec)
        @{
            Approvers     = @()
            FailedKind    = $Kind
            FailedValue   = $Value
            FailedErrorId = $ErrId
            FailedMessage = $Msg
            FailedRecord  = $Rec
        }
    }

    $Approvers = @()
    foreach ($U in @($User)) {
        if (-not $U) { continue }
        # A lookup that THROWS has not shown that no such user exists: hand the record out in
        # FailedRecord for the caller to re-publish as itself. Only a $null return is a not-found.
        $UserId = $null
        try {
            $UserId = Resolve-OERUserId -UserPrincipalName $U
        } catch {
            Remove-OERErrorRecord -Record $PSItem
            return (& $Fail 'User' $U $null $null $PSItem)
        }
        if (-not $UserId) {
            return (& $Fail 'User' $U)
        }
        $Approvers += New-OERApproverObject -Spec @{ User = $UserId }
    }
    foreach ($G in @($Group)) {
        if (-not $G) { continue }
        # An ambiguous display name travels through the descriptor's ErrorId/message companions so the
        # calling cmdlet reports it as a non-terminating error naming the candidate ids, rather than
        # flattening it into the misleading "Group '<name>' not found.". Any other throw -- a 403, an
        # exhausted 429, a 5xx -- travels in FailedRecord, never as the not-found below.
        $GroupId = $null
        try {
            $GroupId = Resolve-OERGroupId -DisplayName $G
        } catch {
            Remove-OERErrorRecord -Record $PSItem
            if (Test-OERAmbiguousNameError -Record $PSItem) {
                return (& $Fail 'Group' $G 'AmbiguousGroupName' $PSItem.Exception.Message)
            }
            return (& $Fail 'Group' $G $null $null $PSItem)
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
        FailedRecord  = $null
    }
}
