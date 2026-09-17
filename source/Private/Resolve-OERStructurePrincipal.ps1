function Resolve-OERStructurePrincipal {
    <#
    .SYNOPSIS
    Resolves a friendly principal reference (user, group, or service principal -- name or GUID) to
    its object id.

    .DESCRIPTION
    The orchestration engine's principal resolver. Several add cmdlets (Add-OERGroupMember,
    Add-OERGroupEligibility, Add-OERAdministrativeUnitMember, Add-OERAdministrativeUnitScopedRole) take a
    raw object id rather than a friendly name, so the engine resolves document references itself. A GUID
    is returned verbatim with no Graph call. When -Type is supplied the resolution is type-directed:
    ServicePrincipal -> Resolve-OERApplicationId; User -> Resolve-OERUserId; Group -> Resolve-OERGroupId.
    Without -Type the existing heuristic applies: a value containing an at sign is treated as a user
    principal name and resolved via Resolve-OERUserId; any other value is treated as a group display name
    and resolved via Resolve-OERGroupId, falling back to a user lookup if no group matches. Returns $null
    when the reference cannot be resolved, so the caller can record a Failed result.

    .PARAMETER Reference
    The principal reference from the document: a user principal name, a group display name, a service
    principal display name, or an object id (GUID).

    .PARAMETER Type
    Optional principal type hint. When supplied, resolution is type-directed rather than heuristic-based.
    Accepted values: User, Group, ServicePrincipal. A GUID reference is always returned verbatim regardless
    of this parameter.

    .EXAMPLE
    Resolve-OERStructurePrincipal -Reference 'person9@example.com'
    Returns the user's object id, or $null when not found.

    .EXAMPLE
    Resolve-OERStructurePrincipal -Reference 'Contoso App' -Type ServicePrincipal
    Returns the service principal object id resolved via Resolve-OERApplicationId, or $null when not found.
    #>
    [OutputType([string])]
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Reference,
        [ValidateSet('User', 'Group', 'ServicePrincipal')][string]$Type
    )
    if (Test-OERGuid -Value $Reference) { return $Reference }

    if ($Type -eq 'ServicePrincipal') {
        $Id = Resolve-OERApplicationId -DisplayName $Reference
        if ($Id) { return [string]$Id }
        return $null
    }
    if ($Type -eq 'User') {
        $Id = Resolve-OERUserId -UserPrincipalName $Reference
        if ($Id) { return [string]$Id }
        return $null
    }
    if ($Type -eq 'Group') {
        $Id = Resolve-OERGroupId -DisplayName $Reference
        if ($Id) { return [string]$Id }
        return $null
    }

    if ($Reference -like '*@*') {
        $Id = Resolve-OERUserId -UserPrincipalName $Reference
        if ($Id) { return [string]$Id }
        return $null
    }
    $Id = Resolve-OERGroupId -DisplayName $Reference
    if ($Id) { return [string]$Id }
    $Id = Resolve-OERUserId -UserPrincipalName $Reference
    if ($Id) { return [string]$Id }
    return $null
}
