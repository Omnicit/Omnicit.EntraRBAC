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
    role assignment bodies to avoid replication-delay failures.

    Three outcomes other than a match leave this function as three different throws, so a caller can
    tell them apart. A value that matches nothing throws an ErrorRecord with ErrorId
    PrincipalUnresolved, category ObjectNotFound, the value as its TargetObject, and the message
    "User 'x' was not found.", "Group 'x' was not found." or "Service principal 'x' was not found.".
    PrincipalUnresolved is internal: no cmdlet publishes it. The approver resolvers
    (Resolve-OERApproverInput, Resolve-OERDeclaredApprover) and Set-OERRoleManagementPolicy read the
    id to report only a missing approver as ApproverNotFound; every other caller reads only the
    message, which is why its text never changes. A group or service principal display name that
    matches more than one object is never resolved to one of them: the underlying resolver's
    AmbiguousName ErrorRecord, which lists the candidate ids, propagates unchanged, so a caller can
    tell it apart with Test-OERAmbiguousNameError. A lookup that fails -- a 403, an exhausted 429, a
    5xx -- propagates unchanged as well; it is never a principal that matches nothing. Supplying none
    or more than one of the three parameters is a caller error and throws a plain message.

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

    # A value that matches nothing is a typed record, never a bare string: a bare string could not be
    # told apart from a lookup that failed. The message is the one callers have always published.
    if ($User) {
        $Id = Resolve-OERUserId -UserPrincipalName $User
        if (-not $Id) {
            throw [System.Management.Automation.ErrorRecord]::new(
                [System.Exception]::new("User '$User' was not found."), 'PrincipalUnresolved',
                [System.Management.Automation.ErrorCategory]::ObjectNotFound, $User)
        }
        $Out = [PSCustomObject]@{ PrincipalId = $Id; PrincipalType = 'User' }
        return $Out
    }
    if ($Group) {
        $Id = Resolve-OERGroupId -DisplayName $Group
        if (-not $Id) {
            throw [System.Management.Automation.ErrorRecord]::new(
                [System.Exception]::new("Group '$Group' was not found."), 'PrincipalUnresolved',
                [System.Management.Automation.ErrorCategory]::ObjectNotFound, $Group)
        }
        $Out = [PSCustomObject]@{ PrincipalId = $Id; PrincipalType = 'Group' }
        return $Out
    }

    if (Test-OERGuid -Value $ServicePrincipal) {
        return [PSCustomObject]@{ PrincipalId = $ServicePrincipal; PrincipalType = 'ServicePrincipal' }
    }
    $Id = Resolve-OERApplicationId -DisplayName $ServicePrincipal
    if (-not $Id) {
        throw [System.Management.Automation.ErrorRecord]::new(
            [System.Exception]::new("Service principal '$ServicePrincipal' was not found."), 'PrincipalUnresolved',
            [System.Management.Automation.ErrorCategory]::ObjectNotFound, $ServicePrincipal)
    }
    return [PSCustomObject]@{ PrincipalId = $Id; PrincipalType = 'ServicePrincipal' }
}
