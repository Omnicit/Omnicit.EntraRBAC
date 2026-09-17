function Resolve-OERPrincipal {
    <#
    .SYNOPSIS
    Resolves a friendly principal reference into its object id and ARM principal type.

    .DESCRIPTION
    The single principal-resolution entry point for the Azure RBAC cmdlets. Exactly one of -User,
    -Group, or -ServicePrincipal must be supplied. Users resolve via Resolve-OERUserId (UPN or GUID),
    groups via Resolve-OERGroupId (display name or GUID), and service principals via
    Resolve-OERApplicationId (display name; a GUID value is treated as the service principal OBJECT
    id and returned without a Graph call -- never as the appId). The returned object carries
    PrincipalId and PrincipalType (User/Group/ServicePrincipal); PrincipalType is always sent in
    role assignment bodies to avoid replication-delay failures. Throws on not-found or invalid
    parameter combinations -- the public cmdlets catch and route the message.

    .PARAMETER User
    A user principal name or user object id (GUID).

    .PARAMETER Group
    A group display name or group object id (GUID).

    .PARAMETER ServicePrincipal
    A service principal display name or service principal object id (GUID).

    .EXAMPLE
    Resolve-OERPrincipal -User 'anna.berg@contoso.com'
    Returns an object with PrincipalId set to the user's object id and PrincipalType User.
    #>
    [OutputType([PSCustomObject])]
    [CmdletBinding()]
    param(
        [string]$User,
        [string]$Group,
        [string]$ServicePrincipal
    )

    $Supplied = @()
    if ($User) { $Supplied += '-User' }
    if ($Group) { $Supplied += '-Group' }
    if ($ServicePrincipal) { $Supplied += '-ServicePrincipal' }
    if ($Supplied.Count -eq 0) {
        throw 'Resolve-OERPrincipal requires one of -User, -Group or -ServicePrincipal.'
    }
    if ($Supplied.Count -gt 1) {
        throw "Supply only one of -User, -Group or -ServicePrincipal (got: $($Supplied -join ', '))."
    }

    if ($User) {
        $Id = Resolve-OERUserId -UserPrincipalName $User
        if (-not $Id) { throw "User '$User' was not found." }
        $Out = [PSCustomObject]@{ PrincipalId = $Id; PrincipalType = 'User' }
        return $Out
    }
    if ($Group) {
        $Id = Resolve-OERGroupId -DisplayName $Group
        if (-not $Id) { throw "Group '$Group' was not found." }
        $Out = [PSCustomObject]@{ PrincipalId = $Id; PrincipalType = 'Group' }
        return $Out
    }

    if (Test-OERGuid -Value $ServicePrincipal) {
        return [PSCustomObject]@{ PrincipalId = $ServicePrincipal; PrincipalType = 'ServicePrincipal' }
    }
    $Id = Resolve-OERApplicationId -DisplayName $ServicePrincipal
    if (-not $Id) { throw "Service principal '$ServicePrincipal' was not found." }
    return [PSCustomObject]@{ PrincipalId = $Id; PrincipalType = 'ServicePrincipal' }
}
