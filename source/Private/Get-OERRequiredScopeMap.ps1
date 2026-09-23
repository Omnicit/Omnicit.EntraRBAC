function Get-OERRequiredScopeMap {
    <#
    .SYNOPSIS
    Returns the reviewed per-cmdlet table of Graph permissions and Azure RBAC roles.

    .DESCRIPTION
    The single source of truth behind Get-OERRequiredScope. One entry per exported cmdlet, holding
    the Microsoft Graph permissions and the Azure RBAC built-in role display names that cmdlet needs.
    Every value was confirmed against Microsoft Learn -- the per-API permission tables for the Graph
    scopes, and the built-in role and PIM references for the Azure roles. An entry whose values could
    not be confirmed sets Verified to false and explains why in Note. Note that the AzureRole column
    is NOT machine-checked: tests/QA/requiredscope.tests.ps1 gates the Graph column against the call
    graph, and nothing derives an Azure role from source, so that column rests on the reference above.

    Each requirement is TRANSITIVE: it is the union of the cmdlet''s own transport calls and every
    call its private helpers make on its behalf. Add-OERAdministrativeUnitScopedRole, for one, makes
    no directoryRoles call itself -- it reaches that endpoint only through Resolve-OERDirectoryRoleId,
    which activates a directory role from its template and therefore needs a role-management write
    permission rather than an administrative-unit one. A per-file reading of the source gets this
    wrong, which is why tests/QA/requiredscope.tests.ps1 re-derives the call graph and gates the table
    against it.

    Transport records which transports the cmdlet reaches, so that an empty GraphScope on an
    ARM-only cmdlet reads as "no Graph permission needed" rather than "nobody filled this in".
    The values are Graph, Arm, GraphAndArm and None.

    This helper performs no network call and no authentication.

    .EXAMPLE
    Get-OERRequiredScopeMap
    Returns the full reviewed table, one entry per exported cmdlet.
    #>
    [OutputType([PSCustomObject])]
    [CmdletBinding()]
    param()

    <#
        Compact rows: GraphScope, AzureRole, Verified and Note are omitted where they take their
        default (empty, empty, true, empty). Normalising in one place below keeps the exceptions
        visible instead of burying them in repeated boilerplate.
    #>
    $Rows = @(
        @{
            Cmdlet = 'Add-OERAccessPackageResourceRole'; Transport = 'Graph'
            GraphScope = 'Application.Read.All', 'EntitlementManagement.ReadWrite.All', 'Group.Read.All'
            Note = '-Group and -Application resolve through Resolve-OERGroupId/Resolve-OERApplicationId (reads); the underlying resource role bind itself only needs EntitlementManagement.ReadWrite.All.'
        }
        @{
            Cmdlet = 'Add-OERAdministrativeUnitMember'; Transport = 'Graph'
            GraphScope = 'AdministrativeUnit.ReadWrite.All', 'Application.Read.All', 'Group.Read.All',
                         'User.ReadBasic.All'
        }
        @{
            Cmdlet = 'Add-OERAdministrativeUnitScopedRole'; Transport = 'Graph'
            GraphScope = 'AdministrativeUnit.Read.All', 'Application.Read.All', 'Group.Read.All',
                         'RoleManagement.ReadWrite.Directory', 'User.ReadBasic.All'
            Note = 'Writes scopedRoleMembers, which is directory role membership rather than administrative-unit membership: the write permission is the role-management one. The unit itself is only READ, to resolve its id.'
        }
        @{
            Cmdlet = 'Add-OERCatalogResource'; Transport = 'Graph'
            GraphScope = 'Application.Read.All', 'EntitlementManagement.ReadWrite.All', 'Group.Read.All'
            Note = 'App-only callers adding a SharePoint site additionally need Sites.FullControl.All, and adding an application additionally needs Application.ReadWrite.All. Delegated callers need the SharePoint Administrator role instead.'
        }
        @{
            Cmdlet = 'Add-OERGroupEligibility'; Transport = 'Graph'
            GraphScope = 'Application.Read.All', 'Group.Read.All',
                         'PrivilegedEligibilitySchedule.ReadWrite.AzureADGroup',
                         'RoleManagementPolicy.ReadWrite.AzureADGroup', 'User.ReadBasic.All'
            Note = 'RoleManagementPolicy.ReadWrite.AzureADGroup is needed because a permanent eligibility first opens the governing PIM policy.'
        }
        @{
            Cmdlet = 'Add-OERGroupMember'; Transport = 'Graph'
            GraphScope = 'Application.Read.All', 'Group.ReadWrite.All', 'User.ReadBasic.All'
            Note = 'GroupMember.ReadWrite.All is the least privileged permission for members alone; Group.ReadWrite.All is required because -Owner writes owners too. Membership of a role-assignable group additionally needs RoleManagement.ReadWrite.Directory.'
        }
        @{
            Cmdlet = 'Connect-OER'; Transport = 'None'
            Note = 'Acquires the tokens every other cmdlet reuses; it makes no Graph or ARM data call of its own. Consent to the scopes of the cmdlets you intend to run.'
        }
        @{
            Cmdlet = 'Disable-OEREligibleRoleAssignment'; Transport = 'GraphAndArm'
            GraphScope = 'Application.Read.All', 'Group.Read.All', 'User.ReadBasic.All'
            AzureRole = 'Reader'
            Note = 'Sends requestType SelfDeactivate, so the DEACTIVATION itself is authorised by the callers own active assignment rather than by an administrator role -- User Access Administrator is not required. Reader is still needed, because the role definition is resolved by reading it first.'
        }
        @{
            Cmdlet = 'Disconnect-OER'; Transport = 'None'
            Note = 'Clears the cached session. No tenant call.'
        }
        @{
            Cmdlet = 'Enable-OEREligibleRoleAssignment'; Transport = 'GraphAndArm'
            GraphScope = 'Application.Read.All', 'Group.Read.All', 'User.ReadBasic.All'
            AzureRole = 'Reader'
            Note = 'Sends requestType SelfActivate, so the ACTIVATION itself is authorised by the callers own eligibility rather than by an administrator role -- User Access Administrator is not required. Reader is still needed, because activating reads the eligibility and the role definition first: Microsoft Learn lists Microsoft.Authorization/roleAssignments/read as a prerequisite for activating your own role.'
        }
        @{
            Cmdlet = 'Export-OERInventory'; Transport = 'GraphAndArm'
            GraphScope = 'AccessReview.Read.All', 'AdministrativeUnit.Read.All', 'Directory.Read.All',
                         'EntitlementManagement.Read.All', 'PrivilegedEligibilitySchedule.Read.AzureADGroup',
                         'RoleManagement.Read.Directory', 'RoleManagementPolicy.Read.AzureADGroup'
            AzureRole = 'Reader'
            Note = 'The scopes listed are the union over every -Include area; a narrower -Include needs only the corresponding subset. Directory.Read.All is required outright, to name principals through directoryObjects/getByIds, and it already covers the user, group and service-principal reads behind the friendly-name lookups.'
        }
        @{
            Cmdlet = 'Get-OERAccessPackage'; Transport = 'Graph'
            GraphScope = 'EntitlementManagement.Read.All'
        }
        @{
            Cmdlet = 'Get-OERAccessPackageAssignment'; Transport = 'Graph'
            GraphScope = 'Application.Read.All', 'EntitlementManagement.Read.All', 'Group.Read.All',
                         'User.ReadBasic.All'
        }
        @{
            Cmdlet = 'Get-OERAccessPackageAssignmentPolicy'; Transport = 'Graph'
            GraphScope = 'EntitlementManagement.Read.All'
        }
        @{
            Cmdlet = 'Get-OERAccessPackageResourceRole'; Transport = 'Graph'
            GraphScope = 'EntitlementManagement.Read.All'
        }
        @{
            Cmdlet = 'Get-OERAccessReviewDefinition'; Transport = 'Graph'
            GraphScope = 'AccessReview.Read.All'
        }
        @{
            Cmdlet = 'Get-OERAccessReviewInstance'; Transport = 'Graph'
            GraphScope = 'AccessReview.Read.All'
        }
        @{
            Cmdlet = 'Get-OERAccessReviewInstanceDecision'; Transport = 'Graph'
            GraphScope = 'AccessReview.Read.All'
        }
        @{
            Cmdlet = 'Get-OERActiveRoleAssignment'; Transport = 'GraphAndArm'
            GraphScope = 'Application.Read.All', 'Group.Read.All', 'User.ReadBasic.All'
            AzureRole = 'Reader'
        }
        @{
            Cmdlet = 'Get-OERAdministrativeUnit'; Transport = 'Graph'
            GraphScope = 'AdministrativeUnit.Read.All', 'RoleManagement.Read.Directory'
        }
        @{
            Cmdlet = 'Get-OERAdministrativeUnitScopedRole'; Transport = 'Graph'
            GraphScope = 'AdministrativeUnit.Read.All', 'RoleManagement.Read.Directory'
        }
        @{
            Cmdlet = 'Get-OERAuthenticationContext'; Transport = 'Graph'
            GraphScope = 'AuthenticationContext.Read.All'
        }
        @{
            Cmdlet = 'Get-OERCatalog'; Transport = 'Graph'
            GraphScope = 'EntitlementManagement.Read.All'
        }
        @{
            Cmdlet = 'Get-OERCatalogResource'; Transport = 'Graph'
            GraphScope = 'EntitlementManagement.Read.All'
        }
        @{
            Cmdlet = 'Get-OERConfiguration'; Transport = 'None'
            Note = 'Tenant Profile PSD1 files on local disk only. No tenant call.'
        }
        @{
            Cmdlet = 'Get-OEREligibleRoleAssignment'; Transport = 'GraphAndArm'
            GraphScope = 'Application.Read.All', 'Group.Read.All', 'User.ReadBasic.All'
            AzureRole = 'Reader'
        }
        @{
            Cmdlet = 'Get-OERGroup'; Transport = 'Graph'
            GraphScope = 'Group.Read.All', 'PrivilegedEligibilitySchedule.Read.AzureADGroup'
        }
        @{
            Cmdlet = 'Get-OERGroupEligibility'; Transport = 'Graph'
            GraphScope = 'Group.Read.All', 'PrivilegedEligibilitySchedule.Read.AzureADGroup'
        }
        @{
            Cmdlet = 'Get-OERGroupMember'; Transport = 'Graph'
            GraphScope = 'Group.Read.All'
        }
        @{
            Cmdlet = 'Get-OERGroupPimPolicy'; Transport = 'Graph'
            GraphScope = 'Group.Read.All', 'RoleManagementPolicy.Read.AzureADGroup'
        }
        @{
            Cmdlet = 'Get-OERInventory'; Transport = 'GraphAndArm'
            GraphScope = 'AccessReview.Read.All', 'AdministrativeUnit.Read.All', 'Directory.Read.All',
                         'EntitlementManagement.Read.All', 'PrivilegedEligibilitySchedule.Read.AzureADGroup',
                         'RoleManagement.Read.Directory', 'RoleManagementPolicy.Read.AzureADGroup'
            AzureRole = 'Reader'
            Note = 'The scopes listed are the union over every -Include area; a narrower -Include needs only the corresponding subset. Directory.Read.All is required outright, to name principals through directoryObjects/getByIds, and it already covers the user, group and service-principal reads behind the friendly-name lookups.'
        }
        @{
            Cmdlet = 'Get-OERManagementGroup'; Transport = 'Arm'
            AzureRole = 'Reader'
        }
        @{
            Cmdlet = 'Get-OERRequiredScope'; Transport = 'None'
            Note = 'Reads this static table. No tenant call, and no permission of any kind.'
        }
        @{
            Cmdlet = 'Get-OERResource'; Transport = 'GraphAndArm'
            GraphScope = 'Directory.Read.All'
            AzureRole = 'Reader'
            Note = 'Graph is reached only to name principals for -ResolveNames, which reads directoryObjects and accepts no permission narrower than Directory.Read.All. Without -ResolveNames no Graph permission is used at all.'
        }
        @{
            Cmdlet = 'Get-OERResourceGroup'; Transport = 'GraphAndArm'
            GraphScope = 'Directory.Read.All'
            AzureRole = 'Reader'
            Note = 'Graph is reached only to name principals for -ResolveNames, which reads directoryObjects and accepts no permission narrower than Directory.Read.All. Without -ResolveNames no Graph permission is used at all.'
        }
        @{
            Cmdlet = 'Get-OERRoleAssignment'; Transport = 'GraphAndArm'
            GraphScope = 'Directory.Read.All'
            AzureRole = 'Reader'
            Note = 'Directory.Read.All covers both jobs Graph does here and accepts nothing narrower for one of them: resolving the -User, -Group and -ServicePrincipal filters, and naming assignment principals for -ResolveNames, which reads directoryObjects. Using neither needs no Graph permission.'
        }
        @{
            Cmdlet = 'Get-OERRoleDefinition'; Transport = 'Arm'
            AzureRole = 'Reader'
        }
        @{
            Cmdlet = 'Get-OERRoleManagementPolicy'; Transport = 'Arm'
            AzureRole = 'Reader'
        }
        @{
            Cmdlet = 'Get-OERSubscription'; Transport = 'Arm'
            AzureRole = 'Reader'
        }
        @{
            Cmdlet = 'Invoke-OERAccessReviewInstanceDecision'; Transport = 'Graph'
            GraphScope = 'AccessReview.ReadWrite.All'
        }
        @{
            Cmdlet = 'Invoke-OERStructure'; Transport = 'GraphAndArm'
            GraphScope = 'AccessReview.ReadWrite.All', 'AdministrativeUnit.ReadWrite.All',
                         'AuthenticationContext.Read.All',
                         'Directory.Read.All', 'EntitlementManagement.ReadWrite.All',
                         'Group.ReadWrite.All',
                         'PrivilegedEligibilitySchedule.ReadWrite.AzureADGroup',
                         'RoleManagement.ReadWrite.Directory',
                         'RoleManagementPolicy.ReadWrite.AzureADGroup'
            AzureRole = 'User Access Administrator', 'Owner', 'Role Based Access Control Administrator'
            Note = 'The scopes listed are the union over every document section; a document touching fewer sections needs only the corresponding subset. Directory.Read.All is required outright, to name principals through directoryObjects/getByIds, and it already covers the user and service-principal reads behind the friendly-name lookups.'
        }
        @{
            Cmdlet = 'New-OERAccessPackage'; Transport = 'Graph'
            GraphScope = 'EntitlementManagement.ReadWrite.All'
        }
        @{
            Cmdlet = 'New-OERAccessPackageApprovalStage'; Transport = 'Graph'
            GraphScope = 'Group.Read.All', 'User.ReadBasic.All'
        }
        @{
            Cmdlet = 'New-OERAccessPackageAssignment'; Transport = 'Graph'
            GraphScope = 'Application.Read.All', 'EntitlementManagement.ReadWrite.All', 'Group.Read.All',
                         'User.ReadBasic.All'
        }
        @{
            Cmdlet = 'New-OERAccessPackageAssignmentPolicy'; Transport = 'Graph'
            GraphScope = 'EntitlementManagement.ReadWrite.All'
        }
        @{
            Cmdlet = 'New-OERAccessPackageRequestorScope'; Transport = 'Graph'
            GraphScope = 'Group.Read.All', 'User.ReadBasic.All'
        }
        @{
            Cmdlet = 'New-OERAccessPackageRequestorSettings'; Transport = 'None'
            Note = 'Composes a settings object in memory. No tenant call.'
        }
        @{
            Cmdlet = 'New-OERAccessReviewDefinition'; Transport = 'Graph'
            GraphScope = 'AccessReview.ReadWrite.All', 'EntitlementManagement.Read.All', 'Group.Read.All',
                         'User.ReadBasic.All'
        }
        @{
            Cmdlet = 'New-OERAccessReviewStage'; Transport = 'Graph'
            GraphScope = 'Group.Read.All', 'User.ReadBasic.All'
        }
        @{
            Cmdlet = 'New-OERActiveRoleAssignment'; Transport = 'GraphAndArm'
            GraphScope = 'Application.Read.All', 'Group.Read.All', 'User.ReadBasic.All'
            AzureRole = 'User Access Administrator', 'Owner', 'Role Based Access Control Administrator'
        }
        @{
            Cmdlet = 'New-OERAdministrativeUnit'; Transport = 'Graph'
            GraphScope = 'AdministrativeUnit.ReadWrite.All'
        }
        @{
            Cmdlet = 'New-OERCatalog'; Transport = 'Graph'
            GraphScope = 'EntitlementManagement.ReadWrite.All'
        }
        @{
            Cmdlet = 'New-OERConfiguration'; Transport = 'None'
            Note = 'Tenant Profile PSD1 files on local disk only. No tenant call.'
        }
        @{
            Cmdlet = 'New-OEREligibleRoleAssignment'; Transport = 'GraphAndArm'
            GraphScope = 'Application.Read.All', 'Group.Read.All', 'User.ReadBasic.All'
            AzureRole = 'User Access Administrator', 'Owner', 'Role Based Access Control Administrator'
        }
        @{
            Cmdlet = 'New-OERGroup'; Transport = 'Graph'
            GraphScope = 'AdministrativeUnit.ReadWrite.All', 'Group.ReadWrite.All',
                         'RoleManagement.ReadWrite.Directory'
            Note = 'RoleManagement.ReadWrite.Directory is needed only with -RoleAssignable; Group.ReadWrite.All alone cannot set isAssignableToRole. AdministrativeUnit.ReadWrite.All is needed only with -AdministrativeUnit.'
        }
        @{
            Cmdlet = 'New-OERPolicyNotificationRule'; Transport = 'None'
            Note = 'Composes a notification rule in memory. No tenant call.'
        }
        @{
            Cmdlet = 'New-OERResourceGroup'; Transport = 'Arm'
            AzureRole = 'Contributor'
        }
        @{
            Cmdlet = 'New-OERRoleAssignment'; Transport = 'GraphAndArm'
            GraphScope = 'Application.Read.All', 'Group.Read.All', 'User.ReadBasic.All'
            AzureRole = 'User Access Administrator', 'Owner', 'Role Based Access Control Administrator'
        }
        @{
            Cmdlet = 'Remove-OERAccessPackage'; Transport = 'Graph'
            GraphScope = 'EntitlementManagement.ReadWrite.All'
        }
        @{
            Cmdlet = 'Remove-OERAccessPackageAssignment'; Transport = 'Graph'
            GraphScope = 'EntitlementManagement.ReadWrite.All'
        }
        @{
            Cmdlet = 'Remove-OERAccessPackageAssignmentPolicy'; Transport = 'Graph'
            GraphScope = 'EntitlementManagement.ReadWrite.All'
        }
        @{
            Cmdlet = 'Remove-OERAccessPackageResourceRole'; Transport = 'Graph'
            GraphScope = 'EntitlementManagement.ReadWrite.All'
        }
        @{
            Cmdlet = 'Remove-OERAccessReviewDefinition'; Transport = 'Graph'
            GraphScope = 'AccessReview.ReadWrite.All'
        }
        @{
            Cmdlet = 'Remove-OERActiveRoleAssignment'; Transport = 'GraphAndArm'
            GraphScope = 'Application.Read.All', 'Group.Read.All', 'User.ReadBasic.All'
            AzureRole = 'User Access Administrator', 'Owner', 'Role Based Access Control Administrator'
        }
        @{
            Cmdlet = 'Remove-OERAdministrativeUnit'; Transport = 'Graph'
            GraphScope = 'AdministrativeUnit.ReadWrite.All'
        }
        @{
            Cmdlet = 'Remove-OERAdministrativeUnitMember'; Transport = 'Graph'
            GraphScope = 'AdministrativeUnit.ReadWrite.All', 'Application.Read.All', 'Group.Read.All',
                         'User.ReadBasic.All'
        }
        @{
            Cmdlet = 'Remove-OERAdministrativeUnitScopedRole'; Transport = 'Graph'
            GraphScope = 'AdministrativeUnit.Read.All', 'Application.Read.All', 'Group.Read.All',
                         'RoleManagement.ReadWrite.Directory', 'User.ReadBasic.All'
            Note = 'Writes scopedRoleMembers, which is directory role membership rather than administrative-unit membership: the write permission is the role-management one. The unit itself is only READ, to resolve its id.'
        }
        @{
            Cmdlet = 'Remove-OERCatalog'; Transport = 'Graph'
            GraphScope = 'EntitlementManagement.ReadWrite.All'
        }
        @{
            Cmdlet = 'Remove-OERCatalogResource'; Transport = 'Graph'
            GraphScope = 'EntitlementManagement.ReadWrite.All'
        }
        @{
            Cmdlet = 'Remove-OERConfiguration'; Transport = 'None'
            Note = 'Tenant Profile PSD1 files on local disk only. No tenant call.'
        }
        @{
            Cmdlet = 'Remove-OEREligibleRoleAssignment'; Transport = 'GraphAndArm'
            GraphScope = 'Application.Read.All', 'Group.Read.All', 'User.ReadBasic.All'
            AzureRole = 'User Access Administrator', 'Owner', 'Role Based Access Control Administrator'
        }
        @{
            Cmdlet = 'Remove-OERGroup'; Transport = 'Graph'
            GraphScope = 'Group.ReadWrite.All'
        }
        @{
            Cmdlet = 'Remove-OERGroupEligibility'; Transport = 'Graph'
            GraphScope = 'Application.Read.All', 'Group.Read.All',
                         'PrivilegedEligibilitySchedule.ReadWrite.AzureADGroup', 'User.ReadBasic.All'
        }
        @{
            Cmdlet = 'Remove-OERGroupMember'; Transport = 'Graph'
            GraphScope = 'Application.Read.All', 'Group.ReadWrite.All', 'User.ReadBasic.All'
            Note = 'GroupMember.ReadWrite.All is the least privileged permission for members alone; Group.ReadWrite.All is required because -Owner writes owners too. Membership of a role-assignable group additionally needs RoleManagement.ReadWrite.Directory.'
        }
        @{
            Cmdlet = 'Remove-OERResourceGroup'; Transport = 'Arm'
            AzureRole = 'Contributor'
        }
        @{
            Cmdlet = 'Remove-OERRoleAssignment'; Transport = 'Arm'
            AzureRole = 'User Access Administrator', 'Owner', 'Role Based Access Control Administrator'
        }
        @{
            Cmdlet = 'Send-OERAccessReviewReminder'; Transport = 'Graph'
            GraphScope = 'AccessReview.ReadWrite.All'
        }
        @{
            Cmdlet = 'Set-OERAccessPackage'; Transport = 'Graph'
            GraphScope = 'EntitlementManagement.ReadWrite.All'
        }
        @{
            Cmdlet = 'Set-OERAccessPackageAssignmentPolicy'; Transport = 'Graph'
            GraphScope = 'EntitlementManagement.ReadWrite.All'
        }
        @{
            Cmdlet = 'Set-OERAccessReviewDefinition'; Transport = 'Graph'
            GraphScope = 'AccessReview.ReadWrite.All', 'Group.Read.All', 'User.ReadBasic.All'
        }
        @{
            Cmdlet = 'Set-OERAdministrativeUnit'; Transport = 'Graph'
            GraphScope = 'AdministrativeUnit.ReadWrite.All'
        }
        @{
            Cmdlet = 'Set-OERCatalog'; Transport = 'Graph'
            GraphScope = 'EntitlementManagement.ReadWrite.All'
        }
        @{
            Cmdlet = 'Set-OERConfiguration'; Transport = 'None'
            Note = 'Tenant Profile PSD1 files on local disk only. No tenant call.'
        }
        @{
            Cmdlet = 'Set-OERGroup'; Transport = 'Graph'
            GraphScope = 'Group.ReadWrite.All', 'RoleManagement.ReadWrite.Directory'
            Note = 'RoleManagement.ReadWrite.Directory is needed only when the group is role-assignable (isAssignableToRole); Group.ReadWrite.All alone cannot update such a group. The Update group permission table does not list it: Microsoft Learn states it in the role-assignable group guidance and the Entra role reference, where the microsoft.directory/groups update actions exclude role-assignable groups.'
        }
        @{
            Cmdlet = 'Set-OERGroupPimPolicy'; Transport = 'Graph'
            GraphScope = 'AuthenticationContext.Read.All', 'Group.Read.All', 'RoleManagementPolicy.ReadWrite.AzureADGroup'
            Note = 'AuthenticationContext.Read.All is used only to validate a supplied -AuthenticationContextId against the tenant. Without it, that validation degrades to a warning and the write still succeeds.'
        }
        @{
            Cmdlet = 'Set-OERResourceGroup'; Transport = 'Arm'
            AzureRole = 'Contributor'
        }
        @{
            Cmdlet = 'Set-OERRoleAssignment'; Transport = 'Arm'
            AzureRole = 'User Access Administrator', 'Owner', 'Role Based Access Control Administrator'
        }
        @{
            Cmdlet = 'Set-OERRoleManagementPolicy'; Transport = 'GraphAndArm'
            GraphScope = 'Application.Read.All', 'Group.Read.All', 'User.ReadBasic.All'
            AzureRole = 'User Access Administrator', 'Owner', 'Role Based Access Control Administrator'
        }
        @{
            Cmdlet = 'Stop-OERAccessReviewInstance'; Transport = 'Graph'
            GraphScope = 'AccessReview.ReadWrite.All'
        }
        @{
            Cmdlet = 'Test-OERStructure'; Transport = 'None'
            Note = 'Validates a structure document offline. Applying it needs the Invoke-OERStructure scopes.'
        }
    )

    foreach ($Row in $Rows) {
        <#
            Filter rather than cast: @($null).Count is 1 in PowerShell, so a missing key would
            otherwise produce a single-element array holding $null instead of an empty one.
        #>
        [PSCustomObject]@{
            Cmdlet     = [string]$Row['Cmdlet']
            Transport  = [string]$Row['Transport']
            GraphScope = [string[]]@($Row['GraphScope'] | Where-Object { $_ })
            AzureRole  = [string[]]@($Row['AzureRole'] | Where-Object { $_ })
            Verified   = if ($Row.ContainsKey('Verified')) { [bool]$Row['Verified'] } else { $true }
            Note       = [string]$Row['Note']
        }
    }
}
