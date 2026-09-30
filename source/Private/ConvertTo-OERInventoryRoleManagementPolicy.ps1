function ConvertTo-OERInventoryRoleManagementPolicy {
    <#
    .SYNOPSIS
    Projects one PIM role management policy into its inventory document entry.

    .DESCRIPTION
    The single owner of both inventory policy entry shapes Get-OERInventory emits: a
    roleManagementPolicies entry (the PIM policy of an Azure role at an Azure scope) and, with
    -Directory, a directoryRoleManagementPolicies entry (the PIM policy of a Microsoft Entra
    directory role, always at tenant scope). Both read the same Omnicit.EntraRBAC.RoleManagementPolicy
    object, which Get-OERRoleManagementPolicy and Get-OERDirectoryRoleManagementPolicy both return.

    Without -Directory the entry starts with scope, role, allowPermanentEligibility and
    activationMaxHours, emitted even when null so an existing document keeps its shape. With
    -Directory there is no scope key, and allowPermanentEligibility and activationMaxHours are
    emitted only when the live policy carries a value. role is the role name, or the role definition
    id when there is no name. Every other field is emitted the same way on both sides: the eligible
    and active durations and active permanence only when set, the activation and active-assignment
    toggles always, and the authentication context only when one is enabled -- in which case
    requireMfaOnActivation is left out, since PIM treats the two as mutually exclusive and the
    offline validator refuses a document declaring both.

    Approvers are emitted as object ids (users and groups), since an id resolves verbatim on apply
    and a display name may not. Without -Directory they are emitted whenever the live policy lists
    any, exactly as before this helper existed. With -Directory they are emitted only while approval
    is required: the apply engine ignores declared approvers when requireApproval is false, and the
    offline validator would otherwise warn on every exported document holding a stale approver.

    The entry is a plain ordered PSCustomObject with no type name of its own and no id; the caller
    stamps id when -IncludeId asks for it. Pure; no Graph or ARM call.

    .PARAMETER Policy
    One Omnicit.EntraRBAC.RoleManagementPolicy object, from Get-OERRoleManagementPolicy or
    Get-OERDirectoryRoleManagementPolicy.

    .PARAMETER Directory
    Project the directoryRoleManagementPolicies entry (no scope, approvers only while approval is
    required, allowPermanentEligibility and activationMaxHours only when set) instead of the
    roleManagementPolicies entry.

    .EXAMPLE
    ConvertTo-OERInventoryRoleManagementPolicy -Policy $AzurePolicy
    Returns the roleManagementPolicies entry for an Azure role policy, scope first.

    .EXAMPLE
    ConvertTo-OERInventoryRoleManagementPolicy -Policy $DirectoryPolicy -Directory
    Returns the directoryRoleManagementPolicies entry for a Microsoft Entra directory role policy.
    #>
    [OutputType([PSCustomObject])]
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object]$Policy,
        [switch]$Directory
    )

    $Role = $(if ($Policy.RoleName) { $Policy.RoleName } else { $Policy.RoleDefinitionId })
    if ($Directory) {
        # A directory role policy always lives at tenant scope, so the entry has no scope. The two
        # fields the Azure entry emits unconditionally are emitted here only when set: a null would
        # be a value the apply engine and the validator both have to interpret.
        $Proj = [ordered]@{ role = $Role }
        if ($null -ne $Policy.AllowPermanentEligibility) { $Proj.allowPermanentEligibility = $Policy.AllowPermanentEligibility }
        if ($null -ne $Policy.ActivationMaxHours) { $Proj.activationMaxHours = $Policy.ActivationMaxHours }
    } else {
        # scope/role/allowPermanentEligibility/activationMaxHours keep their original
        # unconditional emission so an existing document keeps its shape.
        $Proj = [ordered]@{
            scope                     = $Policy.Scope
            role                      = $Role
            allowPermanentEligibility = $Policy.AllowPermanentEligibility
            activationMaxHours        = $Policy.ActivationMaxHours
        }
    }
    # Everything else is emitted only when the live policy actually carries a value, so a policy
    # whose rule set omits an optional field does not produce a null the apply must interpret.
    if ($null -ne $Policy.EligibleDurationDays) { $Proj.eligibleDurationDays = [int]$Policy.EligibleDurationDays }
    if ($null -ne $Policy.AllowPermanentActiveAssignment) { $Proj.allowPermanentActiveAssignment = [bool]$Policy.AllowPermanentActiveAssignment }
    if ($null -ne $Policy.ActiveDurationDays) { $Proj.activeDurationDays = [int]$Policy.ActiveDurationDays }
    # PIM treats MFA on activation and an authentication context as mutually exclusive -- ARM
    # rejects both at once, Set-OERDirectoryRoleManagementPolicy refuses both, and
    # Test-OERStructureSchema raises an Error on a document carrying both. A live policy can still
    # report MultiFactorAuthentication in Enablement_EndUser_Assignment while the context is enabled,
    # so emitting both would produce an inventory that fails its own validation (and the
    # Export-OERInventory schema self-check). The authentication context is the authoritative, more
    # specific control, so it is the one carried; requireMfaOnActivation is omitted in that case.
    $HasAuthContext = [bool]$Policy.AuthenticationContextId
    if (-not $HasAuthContext) {
        $Proj.requireMfaOnActivation             = [bool]$Policy.RequireMfaOnActivation
    }
    $Proj.requireJustificationOnActivation       = [bool]$Policy.RequireJustificationOnActivation
    $Proj.requireTicketOnActivation              = [bool]$Policy.RequireTicketOnActivation
    $Proj.requireApproval                        = [bool]$Policy.RequireApproval
    $Proj.requireMfaOnActiveAssignment           = [bool]$Policy.RequireMfaOnActiveAssignment
    $Proj.requireJustificationOnActiveAssignment = [bool]$Policy.RequireJustificationOnActiveAssignment
    if ($HasAuthContext) { $Proj.authenticationContextId = [string]$Policy.AuthenticationContextId }
    # Approvers project as object IDS: they resolve verbatim through the apply engine's declared
    # approver resolution, whereas an approver description is a display name a lookup cannot
    # resolve. The directory entry carries them only while approval is required (see .DESCRIPTION);
    # the Azure entry keeps its original, ungated emission.
    if (-not $Directory -or $Policy.RequireApproval -eq $true) {
        $ApproverUser  = @(@($Policy.Approvers) | Where-Object { $_ -and [string]$_.UserType -eq 'User' } | ForEach-Object { [string]$_.Id } | Where-Object { $_ })
        $ApproverGroup = @(@($Policy.Approvers) | Where-Object { $_ -and [string]$_.UserType -eq 'Group' } | ForEach-Object { [string]$_.Id } | Where-Object { $_ })
        if ($ApproverUser.Count -gt 0 -or $ApproverGroup.Count -gt 0) {
            $ApproverProj = [ordered]@{}
            if ($ApproverUser.Count -gt 0)  { $ApproverProj.users = $ApproverUser }
            if ($ApproverGroup.Count -gt 0) { $ApproverProj.groups = $ApproverGroup }
            $Proj.approvers = [PSCustomObject]$ApproverProj
        }
    }
    [PSCustomObject]$Proj
}
