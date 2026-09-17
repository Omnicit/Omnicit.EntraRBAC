function Get-OERPermanentPolicyState {
    <#
    .SYNOPSIS
    Reports whether an Azure role management policy currently allows permanent assignments.

    .DESCRIPTION
    Reads the role management policy governing a role at a scope (via the private
    Get-OERRoleManagementPolicyId, which returns the policy id and effective rules from a single ARM
    list call) and inspects the expiration rule selected by -Kind: Expiration_Admin_Eligibility for
    eligible permanence or Expiration_Admin_Assignment for active permanence. It returns the governing
    PolicyId, the RoleName, the inspected RuleId, and a PermanentAllowed flag. PermanentAllowed is true
    only when the rule does NOT require expiration; a missing rule is treated as PermanentAllowed true
    so no unjustified policy write is attempted. This is a pure read used by the permanent self-heal in
    New-OEREligibleRoleAssignment and New-OERActiveRoleAssignment; any Get-OERRoleManagementPolicyId
    failure propagates to the caller, which degrades gracefully.

    .PARAMETER Scope
    The resolved ARM scope (e.g. '/subscriptions/{id}') whose policy governs the role.

    .PARAMETER RoleDefinitionId
    The FULL ARM role definition id (from Resolve-OERRoleDefinitionId) whose governing policy is read.

    .PARAMETER Kind
    Which permanence to inspect: 'Eligible' for the eligibility expiration rule, 'Active' for the
    active-assignment expiration rule.

    .EXAMPLE
    Get-OERPermanentPolicyState -Scope '/subscriptions/s1' -RoleDefinitionId '/subscriptions/s1/providers/Microsoft.Authorization/roleDefinitions/rd1' -Kind 'Eligible'
    Returns the governing policy id and whether permanent eligible assignments are allowed for the role.
    #>
    [OutputType([PSCustomObject])]
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Scope,

        [Parameter(Mandatory)]
        [string]$RoleDefinitionId,

        [Parameter(Mandatory)]
        [ValidateSet('Eligible', 'Active')]
        [string]$Kind
    )

    $RuleId = if ($Kind -eq 'Active') { 'Expiration_Admin_Assignment' } else { 'Expiration_Admin_Eligibility' }
    $Info = Get-OERRoleManagementPolicyId -Scope $Scope -RoleDefinitionId $RoleDefinitionId
    $Rule = @($Info.EffectiveRules) | Where-Object { $PSItem.id -eq $RuleId } | Select-Object -First 1

    [PSCustomObject]@{
        PolicyId         = [string]$Info.PolicyId
        RoleName         = [string]$Info.RoleName
        RuleId           = $RuleId
        PermanentAllowed = -not [bool]$Rule.isExpirationRequired
    }
}
