function Get-OERDirectoryRoleManagementPolicy {
    <#
    .SYNOPSIS
    Reads the PIM role management policy of a Microsoft Entra directory role.

    .DESCRIPTION
    Resolves the role management policy that governs HOW PIM behaves for a Microsoft Entra
    directory role (activation length, MFA / justification / ticket on activation, approval,
    authentication context, eligible and active permanence plus max durations, and notifications)
    and returns a tagged Omnicit.EntraRBAC.RoleManagementPolicy object -- the same type and shape
    Get-OERRoleManagementPolicy returns for an Azure role, since both are read through the shared
    ConvertTo-OERRoleManagementPolicy projection. Directory role policies live at tenant scope,
    so Scope is always '/'. Every call goes through Microsoft Graph v1.0
    (policies/roleManagementPolicyAssignments and policies/roleManagementPolicies), never the beta
    endpoint PIM for Groups is pinned to, and approvers are read through the Graph approver reader
    (ConvertFrom-OERGraphApprover) rather than the Azure Resource Manager shape. No ARM token is
    acquired: Initialize-OERAuth is called without -IncludeARM. Identify the policy either by
    -Role (a display name or role definition id, resolved through
    Resolve-OERDirectoryRoleDefinitionId) or directly by -PolicyId (the Microsoft Graph policy id,
    which also binds from the pipeline so this cmdlet's own output round-trips into
    Set-OERDirectoryRoleManagementPolicy). Pass -All to read every directory role's policy in a
    single paged assignment list plus one role-definition-name lookup, rather than one call per
    role. A PIM for Groups policy id passed to -PolicyId is refused (InvalidPolicyId) rather than
    read as if it were a directory-role policy: Microsoft Graph serves every roleManagementPolicy
    from the same collection regardless of what it governs, so Get-OERDirectoryRolePolicy checks
    the policy's own scopeId and scopeType after reading it and this cmdlet reports the refusal.

    For least privilege, RoleManagement.Read.Directory is enough to read a policy; the module's
    default sign-in scope list already requests the broader RoleManagement.ReadWrite.Directory, so
    no separate consent step is needed before writing with Set-OERDirectoryRoleManagementPolicy
    later in the same session.

    .PARAMETER Role
    The directory role: display name (e.g. 'Reports Reader') or role definition GUID. A GUID is
    used as the id, lower-cased, with no lookup; a name is resolved through
    Resolve-OERDirectoryRoleDefinitionId, where a name is matched without regard to letter case and
    a match that is ambiguous in either exact or case-insensitive form refuses (AmbiguousRoleName).
    No match is RoleDefinitionNotFound; a refused lookup is RoleDefinitionReadFailed. Each is a
    non-terminating error, and nothing is returned for that role. The returned RoleName is the name
    as typed, or empty when a GUID was given. Tab-completion offers the built-in Microsoft Entra
    directory roles; any other built-in or custom role name is still accepted.

    .PARAMETER PolicyId
    The Microsoft Graph roleManagementPolicy id to read directly, for example
    'DirectoryRole_00000000-0000-0000-0000-000000000064_00000000-0000-0000-0000-000000000065'.
    Binds from the pipeline by property name, so this cmdlet's own output pipes directly into
    Set-OERDirectoryRoleManagementPolicy. A value that starts with '/' looks like an Azure Resource
    Manager policy id instead and is refused before any Graph call, naming
    Get-OERRoleManagementPolicy as the cmdlet for that id; a value containing an embedded '/', '?',
    '#' or whitespace is refused the same way, as simply not a valid directory-role policy id. A
    syntactically valid id that Microsoft Graph answers with a scopeType other than 'Directory' or
    'DirectoryRole' -- a PIM for Groups policy id, for example -- is also refused as InvalidPolicyId,
    after being read, naming Get-OERGroupPimPolicy and Set-OERGroupPimPolicy as the cmdlets for
    that id instead.

    .PARAMETER All
    Read the policy for every Microsoft Entra directory role in a single paged
    roleManagementPolicyAssignments list call, plus one paged role-definitions list to supply each
    policy's RoleName. A failure reading the names is reported with Write-Warning and leaves
    RoleName empty on every returned object; the policies themselves still come from the
    authoritative assignment read, whose own failure is a non-terminating PolicyReadFailed error
    that returns no policy at all.

    .PARAMETER TenantId
    Optional tenant id or domain forwarded to Initialize-OERAuth.

    .EXAMPLE
    Get-OERDirectoryRoleManagementPolicy -Role 'Reports Reader'
    Reads the PIM policy governing the built-in Reports Reader directory role.

    .EXAMPLE
    Get-OERDirectoryRoleManagementPolicy -Role '00000000-0000-0000-0000-000000000063'
    Reads the PIM policy for the directory role identified by its role definition id instead of
    its display name.

    .EXAMPLE
    Get-OERDirectoryRoleManagementPolicy -Role 'Reports Reader' | Set-OERDirectoryRoleManagementPolicy -RequireApproval $true -ApproverGroup 'PIM Approvers'
    Reads a directory role policy and pipes its PolicyId into Set-OERDirectoryRoleManagementPolicy.

    .EXAMPLE
    Get-OERDirectoryRoleManagementPolicy -PolicyId 'DirectoryRole_00000000-0000-0000-0000-000000000064_00000000-0000-0000-0000-000000000065'
    Reads the policy directly by its Microsoft Graph policy id.

    .EXAMPLE
    Get-OERDirectoryRoleManagementPolicy -All
    Reads the PIM policy for every Microsoft Entra directory role in a single paged list call.
    #>
    [CmdletBinding(DefaultParameterSetName = 'ByRole')]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(ParameterSetName = 'ByRole', Mandatory)]
        [Alias('RoleDefinitionId')]
        [string]$Role,

        [Parameter(ParameterSetName = 'ByPolicyId', Mandatory, ValueFromPipelineByPropertyName)]
        [Alias('Id')]
        [string]$PolicyId,

        [Parameter(ParameterSetName = 'All', Mandatory)]
        [switch]$All,

        [string]$TenantId
    )
    begin {
        $AuthParams = @{}
        if ($TenantId) { $AuthParams.TenantId = $TenantId }
        Initialize-OERAuth @AuthParams
    }
    process {
        if ($PSCmdlet.ParameterSetName -eq 'ByPolicyId') {
            if ($PolicyId -match '[/?#\s]') {
                if ($PolicyId.StartsWith('/', [System.StringComparison]::Ordinal)) {
                    Write-CmdletError -Message ([System.Exception]::new(
                            "The policy id '$PolicyId' looks like an Azure Resource Manager role " +
                            'management policy id, not a Microsoft Graph directory-role policy id. ' +
                            'Use Get-OERRoleManagementPolicy to read an Azure role policy by ARM id, ' +
                            'or pass the Microsoft Graph policy id (for example ' +
                            "'DirectoryRole_<tenantId>_<policyGuid>') to this cmdlet.")) `
                        -ErrorId 'InvalidPolicyId' -Category InvalidArgument -TargetObject $PolicyId -Cmdlet $PSCmdlet
                } else {
                    Write-CmdletError -Message ([System.Exception]::new(
                            "The policy id '$PolicyId' is not a valid Microsoft Graph directory-role " +
                            'policy id. Pass the Microsoft Graph policy id (for example ' +
                            "'DirectoryRole_<tenantId>_<policyGuid>') to this cmdlet.")) `
                        -ErrorId 'InvalidPolicyId' -Category InvalidArgument -TargetObject $PolicyId -Cmdlet $PSCmdlet
                }
                return
            }
            try {
                $Policy = Get-OERDirectoryRolePolicy -PolicyId $PolicyId
            } catch {
                Remove-OERErrorRecord -Record $PSItem
                if (([string]$PSItem.FullyQualifiedErrorId).StartsWith('NotDirectoryRolePolicy', [System.StringComparison]::Ordinal)) {
                    Write-CmdletError -Message ([System.Exception]::new($PSItem.Exception.Message)) `
                        -ErrorId 'InvalidPolicyId' -Category InvalidArgument -TargetObject $PolicyId -Cmdlet $PSCmdlet `
                        -InnerException $PSItem.Exception
                    return
                }
                Write-CmdletError -Message ([System.Exception]::new($PSItem.Exception.Message)) `
                    -ErrorId 'PolicyReadFailed' -Category ReadError -TargetObject $PolicyId -Cmdlet $PSCmdlet `
                    -InnerException $PSItem.Exception
                return
            }
            ConvertTo-OERRoleManagementPolicy -Rules @($Policy.rules) -PolicyId $PolicyId -Scope '/' -ApproverShape Graph
            return
        }

        if ($All) {
            try {
                # Direct assignment, not @(...) around the call: Get-OERDirectoryRolePolicyAssignment
                # emits its result via Write-Output -NoEnumerate, so it always delivers exactly one
                # pipeline object -- the array itself, even when empty. Wrapping a call to a
                # -NoEnumerate function in @() double-wraps that single object into a 1-element outer
                # array instead of unwrapping it, which is the opposite of what @() is for elsewhere.
                $Assignments = Get-OERDirectoryRolePolicyAssignment
            } catch {
                Remove-OERErrorRecord -Record $PSItem
                Write-CmdletError -Message ([System.Exception]::new($PSItem.Exception.Message)) `
                    -ErrorId 'PolicyReadFailed' -Category ReadError -TargetObject $null -Cmdlet $PSCmdlet `
                    -InnerException $PSItem.Exception
                return
            }

            $NameById = @{}
            try {
                $Response = Invoke-OERGraphRequest -Uri 'v1.0/roleManagement/directory/roleDefinitions?$select=id,displayName' -All
                foreach ($Definition in @($Response.value)) {
                    if ($Definition.id) { $NameById[[string]$Definition.id] = [string]$Definition.displayName }
                }
            } catch {
                Remove-OERErrorRecord -Record $PSItem
                Write-Warning "Could not read Microsoft Entra directory role definition names: $($PSItem.Exception.Message)"
            }

            foreach ($Assignment in $Assignments) {
                $AssignmentRoleDefinitionId = [string]$Assignment.roleDefinitionId
                ConvertTo-OERRoleManagementPolicy -Rules @($Assignment.policy.rules) `
                    -PolicyId ([string]$Assignment.policyId) -Scope '/' `
                    -RoleName $NameById[$AssignmentRoleDefinitionId] -RoleDefinitionId $AssignmentRoleDefinitionId `
                    -ApproverShape Graph
            }
            return
        }

        # ByRole: a single explicit role -- granular non-terminating errors.
        try {
            $RoleDefinitionId = Resolve-OERDirectoryRoleDefinitionId -Role $Role
        } catch {
            Remove-OERErrorRecord -Record $PSItem
            if (Test-OERAmbiguousNameError -Record $PSItem) {
                Write-CmdletError -Message ([System.Exception]::new($PSItem.Exception.Message)) `
                    -ErrorId 'AmbiguousRoleName' -Category InvalidArgument -TargetObject $Role -Cmdlet $PSCmdlet `
                    -InnerException $PSItem.Exception
                return
            }
            Write-CmdletError -Message ([System.Exception]::new(
                    "Looking up the Microsoft Entra directory role '$Role' failed, so whether it " +
                    "exists could not be determined: $($PSItem.Exception.Message)")) `
                -ErrorId 'RoleDefinitionReadFailed' -Category ReadError -TargetObject $Role -Cmdlet $PSCmdlet `
                -InnerException $PSItem.Exception
            return
        }
        if (-not $RoleDefinitionId) {
            Write-CmdletError -Message ([System.Exception]::new(
                    "No Microsoft Entra directory role definition named '$Role' was found. Use Tab " +
                    'completion on -Role, or pass the role definition id directly.')) `
                -ErrorId 'RoleDefinitionNotFound' -Category ObjectNotFound -TargetObject $Role -Cmdlet $PSCmdlet
            return
        }

        $RoleNameOut = $(if (Test-OERGuid -Value $Role) { $null } else { $Role })

        try {
            # Same direct-assignment reasoning as the -All branch above; piping the resulting
            # array VARIABLE into Select-Object -First 1 (rather than the live call) enumerates it
            # normally and returns $null when it has no elements.
            $Assignments = Get-OERDirectoryRolePolicyAssignment -RoleDefinitionId $RoleDefinitionId
            $Assignment = $Assignments | Select-Object -First 1
        } catch {
            Remove-OERErrorRecord -Record $PSItem
            Write-CmdletError -Message ([System.Exception]::new($PSItem.Exception.Message)) `
                -ErrorId 'PolicyReadFailed' -Category ReadError -TargetObject $RoleDefinitionId -Cmdlet $PSCmdlet `
                -InnerException $PSItem.Exception
            return
        }
        if (-not $Assignment) {
            Write-CmdletError -Message ([System.Exception]::new(
                    "No role management policy assignment was found for Microsoft Entra directory " +
                    "role '$RoleDefinitionId'.")) `
                -ErrorId 'PolicyNotFound' -Category ObjectNotFound -TargetObject $RoleDefinitionId -Cmdlet $PSCmdlet
            return
        }

        ConvertTo-OERRoleManagementPolicy -Rules @($Assignment.policy.rules) -PolicyId ([string]$Assignment.policyId) `
            -Scope '/' -RoleName $RoleNameOut -RoleDefinitionId $RoleDefinitionId -ApproverShape Graph
    }
}
