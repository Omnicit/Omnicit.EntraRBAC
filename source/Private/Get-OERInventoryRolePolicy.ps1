function Get-OERInventoryRolePolicy {
    <#
    .SYNOPSIS
    Reads every Azure role management policy at one scope as inventory entries, with what Export-OERInventory needs to select them.

    .DESCRIPTION
    Export-OERInventory's per-scope policy read when it selects the role management policies it
    exports (without -AllRolePolicies). It sends exactly what Get-OERInventory -Include
    RoleManagementPolicies -AllRolesAtScope sends for the scope -- ONE paged
    roleManagementPolicyAssignments list, through Get-OERRoleManagementPolicyForScope, and no request
    per policy -- and builds each entry with the same two converters, ConvertTo-OERRoleManagementPolicy
    and ConvertTo-OERInventoryRoleManagementPolicy, dropping a second row of the same scope and role
    as that path does. So the Entry of each result is the entry Get-OERInventory would have written.

    Beside the entry, each result carries the facts the selection (Select-OERInventoryRolePolicy)
    needs and the entry does not hold: Scope, the scope in its canonical form
    (ConvertTo-OERCanonicalScope); RoleDefinitionId, the full role definition id the list row names;
    and Modified, whether the policy has been changed, decided by Test-OERRolePolicyModified from the
    row's policy metadata ($null when the row carries none, so it cannot be judged).

    A scope that does not start with '/' throws the Resolve-OERScope message, and a list that cannot
    be read throws, both to the caller: Export-OERInventory then skips the scope exactly as it skips a
    failed policy read with -AllRolePolicies. This function never signs in (the caller's role
    assignment read, made just before it, renews the token) and never writes an error record.

    .PARAMETER Scope
    The ARM scope whose role management policies are read, as Resolve-OERInventoryScopeTree returns
    it (a management group or subscription id path).

    .EXAMPLE
    Get-OERInventoryRolePolicy -Scope '/subscriptions/11111111-1111-1111-1111-111111111111'
    Returns one object per role at the subscription: Entry (the roleManagementPolicies entry), Scope,
    RoleDefinitionId and Modified.
    #>
    [OutputType([PSCustomObject])]
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Scope
    )
    $TargetScope = Resolve-OERScope -Scope $Scope
    $Infos = @(Get-OERRoleManagementPolicyForScope -Scope $TargetScope)
    $CanonicalScope = ConvertTo-OERCanonicalScope -Scope $TargetScope
    # The duplicate rule Get-OERInventory's RoleManagementPolicies section applies: the scope compared
    # in the canonical form the validator uses, the role without regard to letter case.
    $Seen = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($Info in $Infos) {
        # Exactly the call Get-OERRoleManagementPolicy -AllRolesAtScope makes for each row.
        $Policy = ConvertTo-OERRoleManagementPolicy -Rules @($Info.EffectiveRules) -PolicyId $Info.PolicyId -Scope $TargetScope -RoleName $Info.RoleName -RoleDefinitionId $Info.RoleDefinitionId
        $Entry = ConvertTo-OERInventoryRoleManagementPolicy -Policy $Policy
        if (-not $Seen.Add("$(ConvertTo-OERCanonicalScope -Scope ([string]$Entry.scope))|$($Entry.role)")) { continue }
        [PSCustomObject]@{
            Entry            = $Entry
            Scope            = $CanonicalScope
            RoleDefinitionId = [string]$Info.RoleDefinitionId
            Modified         = (Test-OERRolePolicyModified -Metadata $Info.PolicyMetadata)
        }
    }
}
