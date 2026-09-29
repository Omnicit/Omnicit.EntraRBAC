function Get-OERRoleAssignableState {
    <#
    .SYNOPSIS
    Reads whether a principal is a role-assignable Microsoft Entra group.

    .DESCRIPTION
    A read-only helper (Ruling R6) that GETs the group's isAssignableToRole property directly, in its
    own private function so the requiredscope gate attributes this Graph read to whichever public
    cmdlet calls it. A 404 (the principal is not a group at all -- a user or service principal) is
    not an error: Invoke-OERGraphRequest is called with -ExpectedErrorCode so Microsoft Graph's
    Request_ResourceNotFound / ResourceNotFound answer comes back as an
    Omnicit.EntraRBAC.GraphExpectedError marker object instead of being raised, and is reported here
    as IsGroup $false, IsAssignableToRole $false. Any other failure (permission denied, transport
    failure, an unrecognised error code) propagates unchanged to the caller, which decides how to
    proceed. Never call this with a non-GUID -PrincipalId: it throws before any request, since the
    caller must resolve a friendly name to an object id first.

    .PARAMETER PrincipalId
    The object id (GUID) of the principal to check.

    .EXAMPLE
    Get-OERRoleAssignableState -PrincipalId 'aaaaaaaa-0000-0000-0000-000000000001'
    Returns IsGroup/IsAssignableToRole for that object id.
    #>
    [OutputType([PSCustomObject])]
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$PrincipalId
    )
    if (-not (Test-OERGuid -Value $PrincipalId)) {
        throw "'$PrincipalId' is not an object id (GUID)."
    }
    $Response = Invoke-OERGraphRequest -Uri "v1.0/groups/$PrincipalId`?`$select=id,isAssignableToRole" `
        -ExpectedErrorCode 'Request_ResourceNotFound', 'ResourceNotFound'
    if (@($Response.PSObject.TypeNames) -contains 'Omnicit.EntraRBAC.GraphExpectedError') {
        return [PSCustomObject]@{ IsGroup = $false; IsAssignableToRole = $false }
    }
    [PSCustomObject]@{ IsGroup = $true; IsAssignableToRole = [bool]$Response.isAssignableToRole }
}
