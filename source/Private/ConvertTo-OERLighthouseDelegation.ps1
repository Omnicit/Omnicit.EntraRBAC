function ConvertTo-OERLighthouseDelegation {
    <#
    .SYNOPSIS
    Converts one Azure Lighthouse registration assignment and its registration definition into the row
    written to lighthouseDelegations.json.

    .DESCRIPTION
    Single owner of the row shape of Export-OERInventory's lighthouseDelegations.json (Sprint 11 step
    6b, BL-133; docs/development/rationale.md#lighthouse-delegations). Pure: no request, no error
    record. The row carries, in this property order: scope, subscriptionId, resourceGroup (null for a
    delegation at a subscription), managedByTenantId, managedByTenantName, offerName,
    registrationAssignmentId, registrationDefinitionId, authorizations and eligibleAuthorizations.

    The delegated scope is the part of the assignment id before
    '/providers/Microsoft.ManagedServices/registrationAssignments/'; an id without that part falls
    back to the scope whose list returned the assignment (-ReadAt). The subscription and the resource
    group are read from that scope, letter case ignored, and the scope is written as the id spells it.
    The managing tenant and the offer come from the definition's properties
    (managedByTenantId, managedByTenantName, registrationDefinitionName). The registration definition
    id is the one the assignment names, or the definition's own id when the assignment names none.

    Each authorization becomes principalId, principalDisplayName (ARM's principalIdDisplayName),
    roleDefinitionId, roleName (always null here; the caller resolves the name) and
    delegatedRoleDefinitionIds (the non-blank entries, an array). Each eligible authorization (a
    just-in-time one) becomes the first four of those. A blank string is written as null for every
    scalar field, and authorizations, eligibleAuthorizations and delegatedRoleDefinitionIds are always
    arrays, empty when there is none, so ConvertTo-Json writes [] and never null.

    .PARAMETER Assignment
    One registration assignment as Azure Resource Manager returns it: id and properties
    (registrationDefinitionId, registrationDefinition when the list was read with the definition
    expanded).

    .PARAMETER Definition
    The registration definition of that assignment, with its properties: registrationDefinitionName,
    managedByTenantId, managedByTenantName, authorizations and eligibleAuthorizations.

    .PARAMETER ReadAt
    The scope whose list returned the assignment, for example '/subscriptions/11111111-1111-1111-1111-111111111111'.
    It is used for the delegated scope only when the assignment id does not name it.

    .EXAMPLE
    ConvertTo-OERLighthouseDelegation -Assignment $Assignment -Definition $Definition -ReadAt '/subscriptions/11111111-1111-1111-1111-111111111111'
    Returns the lighthouseDelegations.json row of the assignment.
    #>
    [OutputType([PSCustomObject])]
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object]$Assignment,
        [Parameter(Mandatory)][object]$Definition,
        [Parameter(Mandatory)][string]$ReadAt
    )

    # A blank value is written as null, never as an empty string, so a consumer tests one thing.
    function Get-TextOrNull {
        param([object]$Value)
        $Text = [string]$Value
        if ([string]::IsNullOrWhiteSpace($Text)) { $null } else { $Text }
    }

    $Marker = '/providers/Microsoft.ManagedServices/registrationAssignments/'
    $Id = [string]$Assignment.id
    $At = $Id.IndexOf($Marker, [System.StringComparison]::OrdinalIgnoreCase)
    # The delegated scope is the part of the assignment id before the marker; an id without it falls
    # back to the scope whose list returned the assignment.
    $DelegatedScope = if ($At -gt 0) { $Id.Substring(0, $At) } else { $ReadAt.TrimEnd('/') }
    $ScopeMatch = [regex]::Match($DelegatedScope, '^/subscriptions/([^/]+)(?:/resourceGroups/([^/]+))?', 'IgnoreCase')

    $DefinitionProperties = $Definition.properties
    $DefinitionId = [string]$Assignment.properties.registrationDefinitionId
    if ([string]::IsNullOrWhiteSpace($DefinitionId)) { $DefinitionId = [string]$Definition.id }

    $Authorizations = @(foreach ($Authorization in @($DefinitionProperties.authorizations)) {
            if ($null -eq $Authorization) { continue }
            [PSCustomObject][ordered]@{
                principalId                = Get-TextOrNull -Value $Authorization.principalId
                principalDisplayName       = Get-TextOrNull -Value $Authorization.principalIdDisplayName
                roleDefinitionId           = Get-TextOrNull -Value $Authorization.roleDefinitionId
                roleName                   = $null
                delegatedRoleDefinitionIds = [string[]]@(foreach ($Delegated in @($Authorization.delegatedRoleDefinitionIds)) {
                        if (-not [string]::IsNullOrWhiteSpace([string]$Delegated)) { [string]$Delegated }
                    })
            }
        })
    $EligibleAuthorizations = @(foreach ($Authorization in @($DefinitionProperties.eligibleAuthorizations)) {
            if ($null -eq $Authorization) { continue }
            [PSCustomObject][ordered]@{
                principalId          = Get-TextOrNull -Value $Authorization.principalId
                principalDisplayName = Get-TextOrNull -Value $Authorization.principalIdDisplayName
                roleDefinitionId     = Get-TextOrNull -Value $Authorization.roleDefinitionId
                roleName             = $null
            }
        })

    [PSCustomObject][ordered]@{
        scope                    = Get-TextOrNull -Value $DelegatedScope
        subscriptionId           = if ($ScopeMatch.Success) { Get-TextOrNull -Value $ScopeMatch.Groups[1].Value } else { $null }
        resourceGroup            = if ($ScopeMatch.Success -and $ScopeMatch.Groups[2].Success) { Get-TextOrNull -Value $ScopeMatch.Groups[2].Value } else { $null }
        managedByTenantId        = Get-TextOrNull -Value $DefinitionProperties.managedByTenantId
        managedByTenantName      = Get-TextOrNull -Value $DefinitionProperties.managedByTenantName
        offerName                = Get-TextOrNull -Value $DefinitionProperties.registrationDefinitionName
        registrationAssignmentId = Get-TextOrNull -Value $Id
        registrationDefinitionId = Get-TextOrNull -Value $DefinitionId
        authorizations           = $Authorizations
        eligibleAuthorizations   = $EligibleAuthorizations
    }
}
