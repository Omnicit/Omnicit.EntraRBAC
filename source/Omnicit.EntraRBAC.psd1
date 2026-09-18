@{
    RootModule           = 'Omnicit.EntraRBAC.psm1'
    ModuleVersion        = '0.0.1'
    CompatiblePSEditions = @('Core')
    GUID                 = '7b9e4a1c-2d6f-4f3a-9c8b-1e5d0a7c3f42'
    Author               = 'Omnicit AB / Philip Haglund'
    CompanyName          = 'Omnicit'
    Copyright            = '(c) 2026 Omnicit AB'
    Description          = 'Manage Entra ID and Azure RBAC building blocks across tenants: Entra ID groups, PIM, Administrative Units, Entitlement Management, Access Reviews, Azure resources and RBAC, plus a JSON inventory and declarative apply engine.'
    PowerShellVersion    = '7.2'

    RequiredModules = @(
        @{ ModuleName = 'AzAuth'; ModuleVersion = '2.9.0' }
        @{ ModuleName = 'Microsoft.Graph.Authentication'; ModuleVersion = '2.36.0' }
        @{ ModuleName = 'Az.Resources'; ModuleVersion = '9.0.3' }
    )

    # Loaded via Update-TypeData in suffix.ps1 (Remove-Module does not clean type data).
    TypesToProcess   = @()
    FormatsToProcess = @('Formats/Omnicit.EntraRBAC.Format.ps1xml')

    FunctionsToExport = @(
        'Connect-OER'
        'Disconnect-OER'
        'New-OERConfiguration'
        'Get-OERConfiguration'
        'Set-OERConfiguration'
        'Remove-OERConfiguration'
        'New-OERGroup'
        'Get-OERGroup'
        'Set-OERGroup'
        'Remove-OERGroup'
        'Add-OERGroupMember'
        'Remove-OERGroupMember'
        'Get-OERGroupMember'
        'Add-OERGroupEligibility'
        'Remove-OERGroupEligibility'
        'Get-OERGroupEligibility'
        'Get-OERGroupPimPolicy'
        'Set-OERGroupPimPolicy'
        'New-OERAdministrativeUnit'
        'Get-OERAdministrativeUnit'
        'Set-OERAdministrativeUnit'
        'Remove-OERAdministrativeUnit'
        'Add-OERAdministrativeUnitMember'
        'Remove-OERAdministrativeUnitMember'
        'Add-OERAdministrativeUnitScopedRole'
        'Get-OERAdministrativeUnitScopedRole'
        'Remove-OERAdministrativeUnitScopedRole'
        'New-OERCatalog'
        'Get-OERCatalog'
        'Set-OERCatalog'
        'Remove-OERCatalog'
        'Add-OERCatalogResource'
        'Get-OERCatalogResource'
        'Remove-OERCatalogResource'
        'Get-OERAccessPackageResourceRole'
        'New-OERAccessPackage'
        'Get-OERAccessPackage'
        'Set-OERAccessPackage'
        'Remove-OERAccessPackage'
        'Add-OERAccessPackageResourceRole'
        'Remove-OERAccessPackageResourceRole'
        'New-OERAccessPackageApprovalStage'
        'New-OERAccessPackageRequestorScope'
        'New-OERAccessPackageRequestorSettings'
        'New-OERAccessPackageAssignmentPolicy'
        'Get-OERAccessPackageAssignmentPolicy'
        'Set-OERAccessPackageAssignmentPolicy'
        'Remove-OERAccessPackageAssignmentPolicy'
        'New-OERAccessPackageAssignment'
        'Get-OERAccessPackageAssignment'
        'Remove-OERAccessPackageAssignment'
        'New-OERAccessReviewStage'
        'New-OERAccessReviewDefinition'
        'Get-OERAccessReviewDefinition'
        'Set-OERAccessReviewDefinition'
        'Remove-OERAccessReviewDefinition'
        'Get-OERAccessReviewInstance'
        'Get-OERAccessReviewInstanceDecision'
        'Stop-OERAccessReviewInstance'
        'Invoke-OERAccessReviewInstanceDecision'
        'Send-OERAccessReviewReminder'
        'Get-OERManagementGroup'
        'Get-OERSubscription'
        'Get-OERRoleDefinition'
        'Get-OERRoleAssignment'
        'New-OERRoleAssignment'
        'Set-OERRoleAssignment'
        'Remove-OERRoleAssignment'
        # Azure Resource Groups
        'New-OERResourceGroup'
        'Get-OERResourceGroup'
        'Set-OERResourceGroup'
        'Remove-OERResourceGroup'
        # Azure Resources
        'Get-OERResource'
        # Azure PIM (Phase 4b)
        'New-OEREligibleRoleAssignment'
        'New-OERActiveRoleAssignment'
        'Get-OEREligibleRoleAssignment'
        'Get-OERActiveRoleAssignment'
        'Remove-OEREligibleRoleAssignment'
        'Remove-OERActiveRoleAssignment'
        'Disable-OEREligibleRoleAssignment'
        'Enable-OEREligibleRoleAssignment'
        # Azure PIM policy (Phase 4b-2)
        'Get-OERRoleManagementPolicy'
        'New-OERPolicyNotificationRule'
        'Set-OERRoleManagementPolicy'
        # JSON orchestration (Phase 5)
        'Get-OERInventory'
        'Test-OERStructure'
        'Invoke-OERStructure'
        'Export-OERInventory'
        # Permission discovery
        'Get-OERRequiredScope'
        # Conditional Access authentication contexts
        'Get-OERAuthenticationContext'
    )
    CmdletsToExport   = @()
    VariablesToExport = @()
    AliasesToExport   = @()

    PrivateData = @{
        PSData = @{
            Tags                     = @('EntraID', 'Azure', 'RBAC', 'PIM', 'Identity', 'Governance',
                                          'PSEdition_Core', 'Windows', 'Linux', 'MacOS')
            ProjectUri               = 'https://github.com/Omnicit/Omnicit.EntraRBAC'
            LicenseUri               = 'https://github.com/Omnicit/Omnicit.EntraRBAC/blob/main/LICENSE'
            RequireLicenseAcceptance = $false
            ReleaseNotes             = ''
            Prerelease               = ''
        }
    }
}
