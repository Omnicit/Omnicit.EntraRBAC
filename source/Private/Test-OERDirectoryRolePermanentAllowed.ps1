function Test-OERDirectoryRolePermanentAllowed {
    <#
    .SYNOPSIS
    Reads whether a Microsoft Entra directory role's PIM policy allows a permanent eligible or active
    assignment.

    .DESCRIPTION
    Ruling R7: reads the role's governing policy through Get-OERDirectoryRolePolicyAssignment and
    converts its rules with the shared ConvertTo-OERRoleManagementPolicy, then returns
    AllowPermanentEligibility (-Kind Eligible) or AllowPermanentActiveAssignment (-Kind Active).
    Returns $null when no policy assignment is found for the role, or when the policy carries no
    expiration rule for that kind (an unreadable answer, not a refusal -- the caller proceeds and
    lets Microsoft Graph enforce the policy). A read failure is not caught here and propagates to the
    caller unchanged.

    .PARAMETER RoleDefinitionId
    The Microsoft Entra directory role definition id whose policy is read.

    .PARAMETER Kind
    Eligible reads the Expiration_Admin_Eligibility rule; Active reads Expiration_Admin_Assignment.

    .OUTPUTS
    System.Boolean or $null. The [OutputType([bool])] attribute below is PowerShell metadata and has
    no way to express a nullable/tri-state return; the real contract is three-valued: $true (the
    policy allows a permanent assignment of this -Kind), $false (it does not -- the caller refuses
    the request), or $null (unreadable: no policy assignment was found, or the policy carries no
    expiration rule for this -Kind -- the caller proceeds and lets Microsoft Graph enforce it).

    .EXAMPLE
    Test-OERDirectoryRolePermanentAllowed -RoleDefinitionId $RoleDefinitionId -Kind Eligible
    Returns $true, $false, or $null.
    #>
    [OutputType([bool])]
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$RoleDefinitionId,

        [Parameter(Mandatory)]
        [ValidateSet('Eligible', 'Active')]
        [string]$Kind
    )
    # Direct assignment, not @(...): Get-OERDirectoryRolePolicyAssignment emits with -NoEnumerate.
    $Assignments = Get-OERDirectoryRolePolicyAssignment -RoleDefinitionId $RoleDefinitionId
    $Assignment = $Assignments | Select-Object -First 1
    if (-not $Assignment) { return $null }
    $Policy = ConvertTo-OERRoleManagementPolicy -Rules @($Assignment.policy.rules) -PolicyId ([string]$Assignment.policyId) `
        -Scope '/' -RoleDefinitionId $RoleDefinitionId -ApproverShape Graph
    if ($Kind -eq 'Eligible') { return $Policy.AllowPermanentEligibility }
    $Policy.AllowPermanentActiveAssignment
}
