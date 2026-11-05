function Resolve-OERAccessReviewGroupScope {
    <#
    .SYNOPSIS
    Classifies an access review definition's scope query as a group-members review, another group
    form, or not a group scope at all.

    .DESCRIPTION
    Single owner of which access review scope query is a review of a group's members that this module
    can write back. The scope this module writes for a group review is
    '/groups/{id}/transitiveMembers' (New-OERAccessReviewScopeQuery -GroupId). Microsoft Graph
    normalizes the query on read, measured live (2026-11-05, Sprint 12 step 6) against the test tenant:

    - '/groups/{id}/transitiveMembers' reads back as '/v1.0/groups/{id}/transitiveMembers/microsoft.graph.user'.
    - The guest form '/groups/{id}/transitiveMembers/?$filter=(userType eq ''Guest'')' reads back as
      '/v1.0/groups/{id}/transitiveMembers/microsoft.graph.user/?$count=true&$filter=(userType eq ''Guest'')'.
    - Direct members '/groups/{id}/members' reads back as '/v1.0/groups/{id}/members'.

    The scope forms are those of Microsoft Learn, "Configure access review scope by using Microsoft
    Graph APIs".

    Kind is one of:

    - 'Members': the whole query is the group-members form, with an optional leading Graph API version
      segment ('/v1.0', '/beta', and the same shape for a future version) and an optional trailing
      '/microsoft.graph.user' cast, the group id is a GUID, and the scope type (-ScopeType) is absent
      or the plain query scope. This is the only form the module writes, so it is the only one that
      may be exported as a declared 'group'.
    - 'OtherForm': the query addresses a group with a GUID id but is not the Members form -- the guest
      filter, direct '/members', '/owners', a trailing slash, a scope of another type or anything else.
      Reading such a review as a members review would widen it to all transitive members on apply, so
      it is never 'Members'. A review of a group's INACTIVE users is the case that needs the scope
      type: Microsoft Learn ("Configure access review scope by using Microsoft Graph APIs", Example 2)
      writes it with the same query '/groups/{id}/transitiveMembers' under the scope type
      '#microsoft.graph.accessReviewInactiveUsersQueryScope' (with inactiveDuration), so the query
      alone cannot tell it from a review of all members.
    - 'NotGroup': anything else, including a group id that is not a GUID, an invented root such as
      '/tenants/x/groups/{id}/transitiveMembers', and a $null or empty query.

    GroupId is the captured id for 'Members' and 'OtherForm', and $null for 'NotGroup'.

    Pure: no Graph, ARM, or authentication occurs.

    .PARAMETER Query
    The raw scope query string, read from an access review definition's scope query property. A $null
    or an empty value is accepted and reported as 'NotGroup' rather than rejected.

    .PARAMETER ScopeType
    The scope's '@odata.type', as ConvertTo-OERAccessReviewDefinition surfaces it in ScopeType. $null
    and an empty value are accepted and read as the plain query scope (an older caller, or a definition
    that does not report the type). '#microsoft.graph.accessReviewQueryScope' (the type Microsoft Graph
    reads back for the scope this module writes, measured 2026-11-05) is the plain query scope too,
    compared without regard to letter case. Any other type, such as the inactive users scope
    '#microsoft.graph.accessReviewInactiveUsersQueryScope', makes a group query 'OtherForm'.

    .EXAMPLE
    Resolve-OERAccessReviewGroupScope -Query '/v1.0/groups/00000000-0000-0000-0000-000000000011/transitiveMembers/microsoft.graph.user'
    Returns Kind 'Members' and the group id.

    .EXAMPLE
    Resolve-OERAccessReviewGroupScope -Query '/v1.0/groups/00000000-0000-0000-0000-000000000011/members'
    Returns Kind 'OtherForm' with the group id: a direct-members review is not a members review.
    #>
    [OutputType([PSCustomObject])]
    [CmdletBinding()]
    param(
        [Parameter(Position = 0)]
        [AllowNull()]
        [AllowEmptyString()]
        [string]$Query,

        [Parameter()]
        [AllowNull()]
        [AllowEmptyString()]
        [string]$ScopeType
    )

    $VersionPrefix = '(?:/(?:v\d+(?:\.\d+)?|beta))?'
    $Text   = [string]$Query
    $Kind   = 'NotGroup'
    $GroupId = $null

    if ($Text) {
        if ($Text -match ('^' + $VersionPrefix + '/groups/([^/?#]+)') -and (Test-OERGuid -Value $Matches[1])) {
            $GroupId = $Matches[1]
            $PlainScope = [string]::IsNullOrEmpty($ScopeType) -or
                $ScopeType.Equals('#microsoft.graph.accessReviewQueryScope', [System.StringComparison]::OrdinalIgnoreCase)
            if ($PlainScope -and $Text -match ('^' + $VersionPrefix + '/groups/[^/?#]+/transitiveMembers(?:/microsoft\.graph\.user)?$')) {
                $Kind = 'Members'
            }
            else {
                $Kind = 'OtherForm'
            }
        }
    }

    $Out = [PSCustomObject]@{
        Query   = $Text
        Kind    = $Kind
        GroupId = $GroupId
    }
    $Out.PSObject.TypeNames.Insert(0, 'Omnicit.EntraRBAC.AccessReviewGroupScope')
    $Out
}
