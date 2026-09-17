function Resolve-OERReviewerScopeQuery {
    <#
    .SYNOPSIS
    Parses one access review reviewer scope query into the reviewer kind and object id it names.

    .DESCRIPTION
    Single owner of the access review reviewer scope query grammar. Every read-side site that has to
    turn a live accessReviewReviewerScope back into a reviewer -- Get-OERInventory's projection and
    Resolve-OERAccessReviewChange's live-state diff -- routes through this helper instead of carrying
    its own copy of the regex pair. Ten copies of that pair is what let a single Graph normalization
    break the export and the apply engine at the same time.

    Recognized forms, in the order they are tested:

    - './manager' (case-insensitive) is the manager reviewer. It is matched FIRST so it can never be
      mistaken for a user or group scope.
    - '/users/{id}' is a single user reviewer.
    - '/groups/{id}' and '/groups/{id}/transitiveMembers' are a group reviewer. The trailing segment
      is deliberately left open, because Resolve-OERReviewerScope writes the transitiveMembers form.

    The user and group forms additionally tolerate a leading Microsoft Graph API version segment.
    Graph NORMALIZES a reviewer scope query on read: a scope this module writes as '/users/{id}' with
    no prefix comes back from a GET as '/v1.0/users/{id}'. That was confirmed live against a real
    tenant, on a review created through the v1.0 endpoint AND on a review created through the beta
    endpoint -- both read back with the '/v1.0' prefix. A parser anchored on '/users/' alone therefore
    fails on every live review, which is the defect this helper exists to close. The optional prefix
    is bounded to the Graph version vocabulary ('/v1.0', '/beta', and the same shape for a future
    version); it is NOT a general "skip anything before /users/" relaxation. The match stays anchored
    at the start of the string, so an invented root such as '/tenants/x/users/{id}' is still reported
    Unparsed rather than silently accepted.

    Anything else -- './owners', '/servicePrincipals/{id}/owners', a filtered owners query, a $null
    or empty string -- is reported as Kind 'Unparsed' with a $null Id.

    Unparsed is NOT the same condition as "the review carries no reviewer scopes at all". An empty
    reviewers collection is the documented self-review shape ("To create a self-review ... the
    reviewers property should be an empty collection"), while an unparsed scope means a real named
    reviewer exists that this module's vocabulary cannot express. Callers MUST keep the two apart:
    collapsing an unparsed scope into an absent one asserts a self review over a review that has
    named reviewers, which on the write path replaces those reviewers with the requestor.

    Pure: no Graph, ARM, or authentication occurs.

    .PARAMETER Query
    The raw reviewer scope query string, read from an accessReviewReviewerScope's query property. A
    $null or an empty value is accepted and reported as Unparsed rather than rejected.

    .EXAMPLE
    Resolve-OERReviewerScopeQuery -Query '/v1.0/users/00000000-0000-0000-0000-000000000049'
    Returns Kind 'User' and Id '00000000-0000-0000-0000-000000000049', ignoring the API version
    prefix Graph adds when it normalizes the query on read.

    .EXAMPLE
    Resolve-OERReviewerScopeQuery -Query './manager'
    Returns Kind 'Manager' with a $null Id.

    .EXAMPLE
    @($Definition.Reviewers).query | ForEach-Object { Resolve-OERReviewerScopeQuery -Query $_ } |
        Where-Object { $_.Kind -eq 'Unparsed' }
    Lists the live reviewer scopes on a definition that this module cannot express.
    #>
    [OutputType([PSCustomObject])]
    [CmdletBinding()]
    param(
        [Parameter(Position = 0)]
        [AllowNull()]
        [AllowEmptyString()]
        [string]$Query
    )

    # Optional leading Graph API version segment. Kept as one named constant so the two patterns below
    # can never drift apart, and so the tolerated vocabulary is visible in one place.
    $VersionPrefix = '(?:/(?:v\d+(?:\.\d+)?|beta))?'

    $Text = [string]$Query
    $Kind = 'Unparsed'
    $Id   = $null

    if ($Text) {
        if ($Text -ieq './manager') {
            # First, always. A manager scope carries no object id and must never fall through to the
            # user or group branches.
            $Kind = 'Manager'
        }
        elseif ($Text -match ('^' + $VersionPrefix + '/users/([^/]+)$')) {
            $Kind = 'User'
            $Id   = $Matches[1]
        }
        elseif ($Text -match ('^' + $VersionPrefix + '/groups/([^/]+)')) {
            # Intentionally not end-anchored: the module writes '/groups/{id}/transitiveMembers'.
            $Kind = 'Group'
            $Id   = $Matches[1]
        }
    }

    $Out = [PSCustomObject]@{
        Query = $Text
        Kind  = $Kind
        Id    = $Id
    }
    $Out.PSObject.TypeNames.Insert(0, 'Omnicit.EntraRBAC.ReviewerScopeQuery')
    $Out
}
