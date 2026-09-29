function Get-OERMemberGroupId {
    <#
    .SYNOPSIS
    Returns the ids of every group a directory object is a member of, directly or through nesting.

    .DESCRIPTION
    Reads the transitive group memberships of one directory object -- a user or a service principal
    alike -- with a single POST v1.0/directoryObjects/{id}/getMemberGroups request through
    Invoke-OERGraphRequest. The object is named by its id, never through /me, so the same request
    serves a delegated sign-in and an app-only one (an app-only sign-in has no /me). The body is
    securityEnabledOnly false, so a role-assignable Microsoft 365 group, which can hold a directory
    role as well as a security group can, is returned too. Microsoft Learn (directoryObject:
    getMemberGroups, "Group memberships for a directory object") asks for Directory.Read.All.

    Returns the answer's value entries as lower-cased strings, skipping null or blank entries, as a
    [string[]] that is empty (never $null) when the object is a member of no group. With
    securityEnabledOnly false Microsoft Graph also lists the directory roles the object is a member
    of; a directory role's object id is never a group's object id, so a caller looking a group id up
    in the answer is unaffected by them.

    Nothing is caught here: a refused or failed request -- Microsoft Graph also refuses an answer of
    more than 11,000 ids with Directory_ResultSizeLimitExceeded -- propagates to the caller, which
    decides what an unreadable membership means. The directoryRoleAssignments prune pass of
    Sync-OERStructureDirectoryRoleAssignment withholds every group or unknown-type candidate then.

    .PARAMETER ObjectId
    The object id of the user or service principal whose group memberships are read.

    .EXAMPLE
    Get-OERMemberGroupId -ObjectId (Get-OERSignedInObjectId)
    Returns the lower-cased ids of every group the signed-in identity is a member of, directly or
    through nesting.
    #>
    [OutputType([string[]])]
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][ValidateNotNullOrEmpty()][string]$ObjectId
    )
    $Response = Invoke-OERGraphRequest -Method POST -Uri "v1.0/directoryObjects/$ObjectId/getMemberGroups" -Body @{ securityEnabledOnly = $false }
    $Ids = [System.Collections.Generic.List[string]]::new()
    foreach ($Value in @($Response.value)) {
        if ([string]::IsNullOrWhiteSpace([string]$Value)) { continue }
        $Ids.Add(([string]$Value).ToLowerInvariant())
    }
    # -NoEnumerate keeps the [string[]] one object, so an empty answer stays an empty array instead of
    # being unrolled to nothing. A caller therefore assigns the result; @() around the call would wrap
    # the whole array as a single element.
    Write-Output -NoEnumerate -InputObject $Ids.ToArray()
}
