# Type data for tagged output objects, registered inline with Update-TypeData -Force. -Force makes
# this idempotent: re-importing in the same session (Remove-Module does not clear type data) or a
# cross-path collision (the built module and a from-source import register the same member from
# different file paths) simply overwrites the member instead of failing with "member already
# present". TypesToProcess in the manifest is intentionally empty.
Update-TypeData -TypeName 'Omnicit.EntraRBAC.Group' -MemberType ScriptProperty -MemberName 'Summary' `
    -Value { '{0} [{1}]' -f $this.DisplayName, $this.GroupType } -Force -ErrorAction SilentlyContinue

# Back-compat alias: the administrative-unit member shape used to store the directory object kind as
# Type while the sibling group-member shape stored it as ObjectType. ObjectType is now the single
# stored value on both, and Type survives as an alias so an existing script or pipeline that reads
# .Type keeps working. AliasProperty members bind through ValueFromPipelineByPropertyName, appear in
# PSObject.Properties, and serialize with ConvertTo-Json, so nothing that worked stops working.
Update-TypeData -TypeName 'Omnicit.EntraRBAC.AdministrativeUnitMember' -MemberType AliasProperty `
    -MemberName 'Type' -Value 'ObjectType' -Force -ErrorAction SilentlyContinue

# Back-compat aliases for the display-name vocabulary sweep. Every 'who' and 'what' concept is now
# stored as <Noun>Id plus <Noun>DisplayName; the older bare-noun spellings that held a display name
# survive as aliases of the stored value so no existing script, format view or pipeline breaks.
Update-TypeData -TypeName 'Omnicit.EntraRBAC.AccessReviewDecision' -MemberType AliasProperty `
    -MemberName 'Principal' -Value 'PrincipalDisplayName' -Force -ErrorAction SilentlyContinue
Update-TypeData -TypeName 'Omnicit.EntraRBAC.AccessReviewDecision' -MemberType AliasProperty `
    -MemberName 'Resource' -Value 'ResourceDisplayName' -Force -ErrorAction SilentlyContinue
Update-TypeData -TypeName 'Omnicit.EntraRBAC.AccessReviewDecision' -MemberType AliasProperty `
    -MemberName 'ReviewedBy' -Value 'ReviewedByDisplayName' -Force -ErrorAction SilentlyContinue
Update-TypeData -TypeName 'Omnicit.EntraRBAC.AccessReviewDecision' -MemberType AliasProperty `
    -MemberName 'AppliedBy' -Value 'AppliedByDisplayName' -Force -ErrorAction SilentlyContinue
Update-TypeData -TypeName 'Omnicit.EntraRBAC.Assignment' -MemberType AliasProperty `
    -MemberName 'AccessPackageName' -Value 'AccessPackageDisplayName' -Force -ErrorAction SilentlyContinue

# CatalogId is an alias of Id on the Catalog shape, so a piped Omnicit.EntraRBAC.Catalog object binds
# directly to any -Catalog parameter that accepts a CatalogId property (Get-OERAccessPackage,
# Remove-OERCatalogResource) without a second display-name lookup.
Update-TypeData -TypeName 'Omnicit.EntraRBAC.Catalog' -MemberType AliasProperty `
    -MemberName 'CatalogId' -Value 'Id' -Force -ErrorAction SilentlyContinue

# The role shapes each used to store their ARM id twice -- once as Id and once under the
# domain-specific name that the -Id parameters bind through. The domain-specific name is now the only
# stored value and Id is an alias of it, so the two can no longer drift apart while every existing
# .Id read and every Get-* | Set/Remove-* pipe keeps binding exactly as before.
Update-TypeData -TypeName 'Omnicit.EntraRBAC.RoleAssignment' -MemberType AliasProperty `
    -MemberName 'Id' -Value 'RoleAssignmentId' -Force -ErrorAction SilentlyContinue
Update-TypeData -TypeName 'Omnicit.EntraRBAC.ActiveRoleAssignment' -MemberType AliasProperty `
    -MemberName 'Id' -Value 'RoleAssignmentScheduleId' -Force -ErrorAction SilentlyContinue
Update-TypeData -TypeName 'Omnicit.EntraRBAC.EligibleRoleAssignment' -MemberType AliasProperty `
    -MemberName 'Id' -Value 'RoleEligibilityScheduleId' -Force -ErrorAction SilentlyContinue

# Task 8a alias-property sweep. Each of these shapes used to store the same value TWICE -- once
# under a generic name (Id, Name, DefinitionId) and once under the domain-specific name a pipeline
# parameter's alias actually binds through. The domain-specific name is now the only stored value
# and the generic spelling survives as an AliasProperty, so the two can no longer drift apart while
# every existing .Id/.Name/.DefinitionId read and every downstream pipeline bind keeps working
# exactly as before -- this is a storage change, not a new binding surface: the generic property
# name already existed in PSObject.Properties on every one of these types.
#
# RoleDefinition deliberately does NOT get an 'Id' alias here (unlike the role-ASSIGNMENT shapes
# above): 'Id' would collide with -PolicyId/-RoleEligibilityScheduleId's own Id alias on
# Get-/Set-OERRoleManagementPolicy and Enable-OEREligibleRoleAssignment. Its ResourceId/
# RoleDefinitionId pair is the ARM-path duplicate Task 2d left behind; ResourceId becomes the alias
# and RoleDefinitionId stays the stored value because -Role's own alias is RoleDefinitionId, not Id.
Update-TypeData -TypeName 'Omnicit.EntraRBAC.AccessReviewDefinition' -MemberType AliasProperty `
    -MemberName 'Id' -Value 'AccessReviewDefinitionId' -Force -ErrorAction SilentlyContinue
Update-TypeData -TypeName 'Omnicit.EntraRBAC.AccessReviewInstance' -MemberType AliasProperty `
    -MemberName 'Id' -Value 'AccessReviewInstanceId' -Force -ErrorAction SilentlyContinue
Update-TypeData -TypeName 'Omnicit.EntraRBAC.AccessReviewInstance' -MemberType AliasProperty `
    -MemberName 'DefinitionId' -Value 'AccessReviewDefinitionId' -Force -ErrorAction SilentlyContinue
Update-TypeData -TypeName 'Omnicit.EntraRBAC.AccessReviewStage' -MemberType AliasProperty `
    -MemberName 'Id' -Value 'AccessReviewStageId' -Force -ErrorAction SilentlyContinue
Update-TypeData -TypeName 'Omnicit.EntraRBAC.GroupMember' -MemberType AliasProperty `
    -MemberName 'Id' -Value 'PrincipalId' -Force -ErrorAction SilentlyContinue
Update-TypeData -TypeName 'Omnicit.EntraRBAC.AdministrativeUnitMember' -MemberType AliasProperty `
    -MemberName 'Id' -Value 'PrincipalId' -Force -ErrorAction SilentlyContinue
Update-TypeData -TypeName 'Omnicit.EntraRBAC.ManagementGroup' -MemberType AliasProperty `
    -MemberName 'Name' -Value 'ManagementGroupName' -Force -ErrorAction SilentlyContinue
Update-TypeData -TypeName 'Omnicit.EntraRBAC.Resource' -MemberType AliasProperty `
    -MemberName 'Name' -Value 'ResourceName' -Force -ErrorAction SilentlyContinue
Update-TypeData -TypeName 'Omnicit.EntraRBAC.ResourceGroup' -MemberType AliasProperty `
    -MemberName 'Name' -Value 'ResourceGroup' -Force -ErrorAction SilentlyContinue
Update-TypeData -TypeName 'Omnicit.EntraRBAC.RoleDefinition' -MemberType AliasProperty `
    -MemberName 'ResourceId' -Value 'RoleDefinitionId' -Force -ErrorAction SilentlyContinue

# Argument completer for the -Role parameter on every cmdlet that takes an Azure RBAC role name --
# reads, writes and the PIM lifecycle alike, since completing a role name matters most when creating a
# high-consequence assignment. Registered here (in the suffix appended to the built psm1, and mirrored
# in the dev-mode psm1) rather than as an IArgumentCompleter class: a scriptblock authored inside the
# module retains module session-state affinity, so it can call the private Resolve-OERRoleCompletion in
# both the built and from-source load paths. The completer is purely additive -- free-text role names
# and role definition GUIDs are still accepted because no ValidateSet is attached. Deliberately absent:
# Add-OERAccessPackageResourceRole, whose -Role is an entitlement-management resource role (for example
# Member/Owner on a catalog group), not an Azure RBAC role.
Register-ArgumentCompleter -CommandName 'Get-OERRoleDefinition', 'Get-OERRoleManagementPolicy', 'Set-OERRoleManagementPolicy', 'Get-OERInventory', 'New-OERRoleAssignment', 'New-OEREligibleRoleAssignment', 'Remove-OEREligibleRoleAssignment', 'Enable-OEREligibleRoleAssignment', 'Disable-OEREligibleRoleAssignment', 'New-OERActiveRoleAssignment', 'Remove-OERActiveRoleAssignment' -ParameterName 'Role' -ScriptBlock {
    param($CommandName, $ParameterName, $WordToComplete, $CommandAst, $FakeBoundParameters)
    Resolve-OERRoleCompletion -WordToComplete $WordToComplete
}

# Argument completer for the -TenantAlias parameter on the Tenant Profile cmdlets. Same scriptblock
# mechanism (and the same module session-state affinity reason) as the -Role completer above. The
# scriptblock forwards whichever profile base path the user has already typed -- -BasePath on the
# *-OERConfiguration cmdlets and on Connect-OER -- so completion follows the directory
# the command will actually read. New-OERConfiguration is deliberately absent: it creates an alias that
# must NOT already exist, so completing existing aliases there would only ever offer invalid values.
Register-ArgumentCompleter -CommandName 'Connect-OER', 'Get-OERConfiguration', 'Set-OERConfiguration', 'Remove-OERConfiguration' -ParameterName 'TenantAlias' -ScriptBlock {
    param($CommandName, $ParameterName, $WordToComplete, $CommandAst, $FakeBoundParameters)
    $CompletionParams = @{ WordToComplete = $WordToComplete }
    if ($FakeBoundParameters -and $FakeBoundParameters['BasePath']) {
        $CompletionParams.BasePath = [string]$FakeBoundParameters['BasePath']
    } elseif ($FakeBoundParameters -and $FakeBoundParameters['ProfileBasePath']) {
        $CompletionParams.BasePath = [string]$FakeBoundParameters['ProfileBasePath']
    }
    Resolve-OERTenantAliasCompletion @CompletionParams
}

# Argument completer for the -RoleName parameter (also spelled -Role via its alias) on the
# administrative-unit scoped-role cmdlets. Backed by the curated offline set in
# Get-OERCommonDirectoryRoleName rather than Get-OERDirectoryRoleNameMap, which is a live Graph call --
# completion must stay fast and must never block the prompt. Purely additive: custom directory-role
# names and role ids still bind because no ValidateSet is attached.
Register-ArgumentCompleter -CommandName 'Add-OERAdministrativeUnitScopedRole', 'Remove-OERAdministrativeUnitScopedRole' -ParameterName 'RoleName' -ScriptBlock {
    param($CommandName, $ParameterName, $WordToComplete, $CommandAst, $FakeBoundParameters)
    Resolve-OERDirectoryRoleCompletion -WordToComplete $WordToComplete
}
