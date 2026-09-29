function Get-OERMemberGroupId {
    <#
    .SYNOPSIS
    Emits the ids of every group a directory object is a member of, directly or through nesting.

    .DESCRIPTION
    Reads the transitive group memberships of one directory object -- a user or a service principal
    alike -- with a single POST v1.0/directoryObjects/{id}/getMemberGroups request through
    Invoke-OERGraphRequest. The object is named by its id, never through /me, so the same request
    serves a delegated sign-in and an app-only one (an app-only sign-in has no /me). Microsoft Learn
    (directoryObject: getMemberGroups, "Group memberships for a directory object") asks for
    Directory.Read.All.

    The body is securityEnabledOnly false, on purpose. A role-assignable group is always
    security-enabled (Microsoft Graph requires securityEnabled true on a group whose
    isAssignableToRole is true), so securityEnabledOnly true would return it as well; false is kept
    because it can only return MORE groups, never miss one. The cost is a larger answer: every
    Microsoft 365 or distribution group the object is a member of counts too, and above 11,000 ids
    Microsoft Graph refuses the whole answer with Directory_ResultSizeLimitExceeded, which the caller
    treats as a failed read -- the directoryRoleAssignments prune pass of
    Sync-OERStructureDirectoryRoleAssignment then withholds every group or unknown-type candidate.
    With securityEnabledOnly false the answer can also list the directory roles the object is a
    member of. They are harmless: a directory role's object id never equals a group principal id, so
    a caller looking a group id up in the answer is unaffected by them.

    Emits one lower-cased id per group, each as its own pipeline object, skipping null or blank
    entries, and emits nothing at all when the object is a member of no group. A caller collects the
    ids with @(...). A failure is always a thrown error, never an empty result: nothing is caught
    here, so a refused or failed request propagates to the caller, which decides what an unreadable
    membership means.

    .PARAMETER ObjectId
    The object id of the user or service principal whose group memberships are read.

    .EXAMPLE
    $GroupIds = @(Get-OERMemberGroupId -ObjectId (Get-OERSignedInObjectId) -ErrorAction Stop)
    Collects the lower-cased ids of every group the signed-in identity is a member of, directly or
    through nesting, into an array that is empty when it is a member of none.
    #>
    [OutputType([string])]
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][ValidateNotNullOrEmpty()][string]$ObjectId
    )
    $Response = Invoke-OERGraphRequest -Method POST -Uri "v1.0/directoryObjects/$ObjectId/getMemberGroups" -Body @{ securityEnabledOnly = $false }
    foreach ($Value in @($Response.value)) {
        if ([string]::IsNullOrWhiteSpace([string]$Value)) { continue }
        ([string]$Value).ToLowerInvariant()
    }
}
