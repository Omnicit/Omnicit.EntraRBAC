function Resolve-OERReviewerScope {
    <#
    .SYNOPSIS
    Resolves friendly reviewer and fallback-reviewer inputs into accessReviewReviewerScope objects.

    .DESCRIPTION
    Shared by the access review definition and stage builders. Users (UPN or GUID) map to
    /users/{id}, groups (display name or GUID) map to /groups/{id}/transitiveMembers, -Manager maps to
    ./manager with queryRoot decisions, and -SelfReview (or no reviewer inputs) leaves the reviewers
    collection empty (a self-review). Authentication is lazy: Initialize-OERAuth is called only when at
    least one non-GUID name is present, so a pure-GUID or switch-only input performs no auth and no
    Graph call. Resolution stops at the first value that cannot be resolved. Returns a hashtable with
    keys Reviewers, FallbackReviewers (the resolved scope objects), FailedKind ('User', 'Group', or
    $null) and FailedValue (the offending value, or $null). The caller routes a non-null FailedValue as
    a non-terminating error.

    FailedErrorId and FailedMessage are optional companions to FailedKind/FailedValue, mirroring the
    channel Resolve-OERAccessReviewScopeTarget already exposes. They are $null for a plain not-found,
    so the caller's existing "<Kind> '<Value>' not found." error is unchanged, and are populated for an
    AMBIGUOUS group display name, where the resolver's own message naming the candidate object ids is
    far more actionable than a not-found. A caller prefers them whenever they are present. This is why
    an ambiguity is reported through the descriptor rather than thrown: a bare throw out of this helper
    would terminate the calling public cmdlet and defeat -ErrorAction SilentlyContinue.

    .PARAMETER Reviewer
    Zero or more primary reviewer user principal names or user object ids (GUIDs).

    .PARAMETER ReviewerGroup
    Zero or more primary reviewer group display names or group object ids (GUIDs); members review.

    .PARAMETER Manager
    Add the reviewed principal's manager as a primary reviewer (./manager, queryRoot decisions).

    .PARAMETER SelfReview
    Configure a self-review: the reviewers collection is left empty.

    .PARAMETER FallbackReviewer
    Zero or more fallback reviewer user principal names or user object ids (GUIDs).

    .PARAMETER FallbackReviewerGroup
    Zero or more fallback reviewer group display names or group object ids (GUIDs).

    .PARAMETER TenantId
    Optional tenant id or domain forwarded to Initialize-OERAuth when authentication is needed.

    .EXAMPLE
    Resolve-OERReviewerScope -Reviewer 'anna@contoso.com' -FallbackReviewerGroup 'IT-Owners'
    Resolves a named user reviewer and a fallback group, authenticating once because names are present.
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', 'SelfReview',
        Justification = 'Switch documents intent (empty reviewers); presence is validated by the caller.')]
    [OutputType([hashtable])]
    [CmdletBinding()]
    param(
        [string[]]$Reviewer,
        [string[]]$ReviewerGroup,
        [switch]$Manager,
        [switch]$SelfReview,
        [string[]]$FallbackReviewer,
        [string[]]$FallbackReviewerGroup,
        [string]$TenantId
    )
    $AllNames = @($Reviewer) + @($ReviewerGroup) + @($FallbackReviewer) + @($FallbackReviewerGroup)
    $HasName = @($AllNames | Where-Object { $_ -and -not (Test-OERGuid -Value $_) }).Count -gt 0
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
            Reviewers         = @()
            FallbackReviewers = @()
            FailedKind        = $Kind
            FailedValue       = $Value
            FailedErrorId     = $ErrId
            FailedMessage     = $Msg
        }
    }

    function Resolve-One {
        param([string[]]$Users, [string[]]$Groups)
        $Scopes = @()
        foreach ($U in @($Users)) {
            if (-not $U) { continue }
            $Uid = try { Resolve-OERUserId -UserPrincipalName $U } catch { Remove-OERErrorRecord -Record $PSItem; $null }
            if (-not $Uid) {
                return @{ Scopes = @(); FailedKind = 'User'; FailedValue = $U; FailedErrorId = $null; FailedMessage = $null }
            }
            $Scopes += @{ query = "/users/$Uid"; queryType = 'MicrosoftGraph' }
        }
        foreach ($G in @($Groups)) {
            if (-not $G) { continue }
            # An ambiguous display name travels through the descriptor's ErrorId/message companions so
            # the calling cmdlet reports it as a non-terminating error naming the candidate ids, rather
            # than flattening it into the misleading "Group '<name>' not found.".
            $Gid = $null
            try {
                $Gid = Resolve-OERGroupId -DisplayName $G
            } catch {
                Remove-OERErrorRecord -Record $PSItem
                if (Test-OERAmbiguousNameError -Record $PSItem) {
                    return @{
                        Scopes        = @()
                        FailedKind    = 'Group'
                        FailedValue   = $G
                        FailedErrorId = 'AmbiguousGroupName'
                        FailedMessage = $PSItem.Exception.Message
                    }
                }
            }
            if (-not $Gid) {
                return @{ Scopes = @(); FailedKind = 'Group'; FailedValue = $G; FailedErrorId = $null; FailedMessage = $null }
            }
            $Scopes += @{ query = "/groups/$Gid/transitiveMembers"; queryType = 'MicrosoftGraph' }
        }
        return @{ Scopes = @($Scopes); FailedKind = $null; FailedValue = $null; FailedErrorId = $null; FailedMessage = $null }
    }

    $Primary = Resolve-One -Users $Reviewer -Groups $ReviewerGroup
    if ($Primary.FailedValue) {
        return (& $Fail $Primary.FailedKind $Primary.FailedValue $Primary.FailedErrorId $Primary.FailedMessage)
    }
    $Reviewers = @($Primary.Scopes)
    if ($Manager) { $Reviewers += @{ query = './manager'; queryType = 'MicrosoftGraph'; queryRoot = 'decisions' } }

    $Fallback = Resolve-One -Users $FallbackReviewer -Groups $FallbackReviewerGroup
    if ($Fallback.FailedValue) {
        return (& $Fail $Fallback.FailedKind $Fallback.FailedValue $Fallback.FailedErrorId $Fallback.FailedMessage)
    }

    return @{
        Reviewers         = @($Reviewers)
        FallbackReviewers = @($Fallback.Scopes)
        FailedKind        = $null
        FailedValue       = $null
        FailedErrorId     = $null
        FailedMessage     = $null
    }
}
