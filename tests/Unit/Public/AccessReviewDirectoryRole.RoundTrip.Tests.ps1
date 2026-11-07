BeforeAll {
    $script:moduleName = 'Omnicit.EntraRBAC'
    Get-Module $script:moduleName | Remove-Module -Force -ErrorAction SilentlyContinue
    Import-Module $script:moduleName -Force -ErrorAction Stop
    . "$PSScriptRoot/../TestHelpers/OERTransportTripwire.ps1"
    Install-OERTransportTripwire
}

AfterAll {
    try { Assert-OERTransportTripwire } finally { Uninstall-OERTransportTripwire }
}

# A cross-cutting suite named after no single function: ONE mocked live state holding a review of all
# assignments of a directory role. The real Get-OERInventory exports it as directoryRole by NAME, and
# the real Invoke-OERStructure applies that exported JSON back: the validator as the engine calls it,
# the name-to-id step (the real Resolve-OERDirectoryRoleInput and Resolve-OERDirectoryRoleDefinitionId,
# answered at the transport by the roleDefinitions name lookup) and the target check run for real.
# Every row is Unchanged and no write request is sent. The transport throws on any request the
# fixture does not answer. No id below is version-4 shaped.
Describe 'Access review of a directory role, export and apply round trip (Sprint 13 step 4, Task 6)' {
    BeforeAll {
        $script:RtRoleId = '00000000-0000-0000-0000-000000000031'
        $script:RtRoleUri = 'v1.0/roleManagement/directory/roleDefinitions/00000000-0000-0000-0000-000000000031?$select=id,displayName'
    }

    BeforeEach {
        InModuleScope $script:moduleName { $script:_OERAuthState = $null }
        $Inner = '#microsoft.graph.accessReviewQueryScope'
        $script:RtLive = [PSCustomObject]@{
            Id = 'ar-rt'; DisplayName = 'Role review'; Scope = $null
            ScopeType = '#microsoft.graph.principalResourceMembershipsScope'
            PrincipalScopes = @([PSCustomObject]@{ Query = '/v1.0/users'; QueryType = 'MicrosoftGraph'; QueryRoot = $null; ScopeType = $Inner })
            ResourceScopes = @([PSCustomObject]@{ Query = "/beta/roleManagement/directory/roleDefinitions/$($script:RtRoleId)"; QueryType = 'MicrosoftGraph'; QueryRoot = $null; ScopeType = $Inner })
            AccessPackageId = $null; AssignmentPolicyId = $null
            Reviewers = @(@{ query = '/users/usr-1' }); FallbackReviewers = @()
            StageCount = 0; DurationInDays = 14
            MailNotificationsEnabled = $false; ReminderNotificationsEnabled = $false
            JustificationRequired = $false; RecommendationsEnabled = $false; AutoApplyDecisionsEnabled = $false
            Settings = @{
                instanceDurationInDays = 14; mailNotificationsEnabled = $false; reminderNotificationsEnabled = $false
                justificationRequiredOnApproval = $false; recommendationsEnabled = $false; autoApplyDecisionsEnabled = $false
            }
            Recurrence = [PSCustomObject]@{
                pattern = [PSCustomObject]@{ type = 'absoluteMonthly'; interval = 3 }
                range   = [PSCustomObject]@{ type = 'noEnd'; startDate = '2026-07-01' }
            }
        }
        Mock -ModuleName $script:moduleName Initialize-OERAuth { }
        Mock -ModuleName $script:moduleName Get-OERAccessReviewDefinition { $script:RtLive }
        Mock -ModuleName $script:moduleName Resolve-OERPrincipalName { @{ 'usr-1' = 'person1@example.com' } }
        Mock -ModuleName $script:moduleName Resolve-OERStructurePrincipal { 'usr-1' }
        Mock -ModuleName $script:moduleName Resolve-OERStructureDefault { $null }
        Mock -ModuleName $script:moduleName Set-OERAccessReviewDefinition { }
        Mock -ModuleName $script:moduleName New-OERAccessReviewDefinition { }
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest { throw "unexpected transport call: $Method $Uri" }
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest { @{ id = $script:RtRoleId; displayName = 'Reports Reader' } } -ParameterFilter { $Uri -eq $script:RtRoleUri }
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {
            @{ value = @(@{ id = $script:RtRoleId; displayName = 'Reports Reader' }) }
        } -ParameterFilter { $Uri -match "^v1\.0/roleManagement/directory/roleDefinitions\?\`$filter=displayName eq 'Reports(%20| )Reader'&" }
    }

    It 'applies the exported document with every row Unchanged and no write request' {
        $Inv = Get-OERInventory -Include AccessReviews -ErrorAction Stop -WarningAction SilentlyContinue
        $Json = [PSCustomObject][ordered]@{ version = '1.0'; accessReviews = @($Inv.AccessReviews) } | ConvertTo-Json -Depth 12
        $Rows = @(Invoke-OERStructure -Json $Json -Confirm:$false -ErrorAction Stop -WarningAction SilentlyContinue)
        # Reach proof: the review was applied, and its name went through the roleDefinitions lookup.
        @($Rows | Where-Object { $_.Section -eq 'accessReviews' -and $_.Item -eq 'Role review' }).Count | Should -BeGreaterThan 0
        @($Rows | Where-Object { $_.Action -ne 'Unchanged' }) | Should -BeNullOrEmpty
        @($Inv.AccessReviews)[0].directoryRole | Should -BeExactly 'Reports Reader'
        Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -ParameterFilter { $Uri -like 'v1.0/roleManagement/directory/roleDefinitions?$filter=displayName eq *' }
        Should -Invoke -ModuleName $script:moduleName Set-OERAccessReviewDefinition -Times 0 -Exactly
        Should -Invoke -ModuleName $script:moduleName New-OERAccessReviewDefinition -Times 0 -Exactly
        Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 0 -Exactly -ParameterFilter { $Method -and $Method -in 'POST', 'PUT', 'PATCH', 'DELETE' }
    }
}
