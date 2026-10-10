function Get-OERInventoryAzureEligibility {
    <#
    .SYNOPSIS
    Reads the Azure PIM eligible role assignments of an inventory's Azure scopes as read-only context.

    .DESCRIPTION
    Single owner of the bounded eligibility read behind Export-OERInventory's azurePimEligibility.json.
    Exactly one paged Get-OEREligibleRoleAssignment read per scope: a management group scope is read
    with -AtScope (eligibilities at or above it), every other scope without a filter, EXPECTED to
    return eligibilities at, above and below it -- Microsoft documents no semantics at all for an
    unfiltered read, so the below-scope half is to be verified live, not assumed
    (docs/development/rationale.md#inventory-azure-eligibility). The results are deduplicated on the
    schedule id, so an eligibility seen from several scopes appears once -- for example a management
    group's own eligibility, read once directly at the management group and again, inherited, from
    each subscription below it. A scope whose read fails is warned about, left out and listed in
    SkippedScopes -- a failed read is never presented as a scope without eligibility. The projection
    is read-only context, not an apply-document section: scope, role, principal, principalType,
    memberType, status, startDateTime and endDateTime (null for a permanent eligibility).

    RoleScopes carries one object with the Scope and RoleDefinitionId of every row read, duplicates
    included and before the deduplication above, for Export-OERInventory's role policy selection
    (Select-OERInventoryRolePolicy keeps a policy whose role has an eligibility exactly at the policy's
    scope). It is never written to a bundle file.

    .PARAMETER Scope
    The ARM scopes to read, as Resolve-OERInventoryScopeTree returns them.

    .EXAMPLE
    Get-OERInventoryAzureEligibility -Scope '/subscriptions/11111111-1111-1111-1111-111111111111'
    Returns the eligibilities at and above that subscription, and is expected (pending live
    verification) to also return the ones below it.
    #>
    [OutputType([PSCustomObject])]
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][AllowEmptyCollection()][string[]]$Scope
    )
    $Seen = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    $Items = [System.Collections.Generic.List[object]]::new()
    $Skipped = [System.Collections.Generic.List[string]]::new()
    $RoleScopes = [System.Collections.Generic.List[object]]::new()
    foreach ($S in @($Scope)) {
        if ([string]::IsNullOrWhiteSpace($S)) { continue }
        $ReadParams = @{ Scope = $S; ErrorAction = 'Stop' }
        if ($S -match '^/providers/Microsoft\.Management/managementGroups/') { $ReadParams.AtScope = $true }
        try {
            $Rows = @(Get-OEREligibleRoleAssignment @ReadParams)
        } catch {
            Remove-OERErrorRecord -Record $PSItem
            Write-Warning "Skipping scope '$S' for azurePimEligibility.json: $($PSItem.Exception.Message)"
            $Skipped.Add($S)
            continue
        }
        foreach ($Row in $Rows) {
            if ($null -eq $Row) { continue }
            # Every row read, before the deduplication: the selection only needs where each role
            # is eligible, and a duplicate costs nothing.
            $RoleScopes.Add([PSCustomObject]@{ Scope = [string]$Row.Scope; RoleDefinitionId = [string]$Row.RoleDefinitionId })
            $Key = if ($Row.RoleEligibilityScheduleId) { [string]$Row.RoleEligibilityScheduleId }
                   else { '{0}|{1}|{2}' -f $Row.Scope, $Row.RoleDefinitionId, $Row.PrincipalId }
            if (-not $Seen.Add($Key)) { continue }
            $Items.Add([PSCustomObject][ordered]@{
                scope         = [string]$Row.Scope
                role          = $(if ($Row.RoleName) { [string]$Row.RoleName } else { [string]$Row.RoleDefinitionId })
                principal     = $(if ($Row.PrincipalDisplayName) { [string]$Row.PrincipalDisplayName } else { [string]$Row.PrincipalId })
                principalType = [string]$Row.PrincipalType
                memberType    = [string]$Row.MemberType
                status        = [string]$Row.Status
                startDateTime = $Row.StartDateTime
                endDateTime   = $Row.EndDateTime
            })
        }
    }
    $Sorted = @($Items | Sort-Object -Property scope, role, principal)
    $Out = [PSCustomObject]@{ Eligibilities = $Sorted; SkippedScopes = $Skipped.ToArray(); RoleScopes = $RoleScopes.ToArray() }
    $Out.PSObject.TypeNames.Insert(0, 'Omnicit.EntraRBAC.InventoryAzureEligibility')
    $Out
}
