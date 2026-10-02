BeforeDiscovery {
    # Cross-cmdlet suite (named after no single function, like AccessReview.Pipeline.Tests.ps1):
    # every public call site swept for MEM-resolve-groupid-first-match-no-uniqueness is exercised
    # here, so a future cmdlet that drops the guard is caught in one place.
    # Pre = resolvers that must SUCCEED before the one under test is reached.
    # FailureId = only on a case whose cmdlet reports a failed lookup under an id of its OWN instead of
    # re-publishing the resolver's record. Today that is the eight directory role cmdlets, which go
    # through Resolve-OERDirectoryRoleInput and report RoleDefinitionReadFailed, and the five access
    # review cmdlets that read a definition by name or id (Get-OERAccessReviewInstance,
    # Get-OERAccessReviewInstanceDecision, Invoke-OERAccessReviewInstanceDecision,
    # Send-OERAccessReviewReminder, Stop-OERAccessReviewInstance), which report
    # AccessReviewDefinitionResolveFailed with the cause in the message. The second Describe expects
    # that id there and expects the resolver's own id (Authorization_RequestDenied) everywhere else --
    # Remove-OERAccessReviewDefinition and Set-OERAccessReviewDefinition re-publish the record as is.
    $script:GuardCases = @(
        @{
            Cmdlet = 'Add-OERAccessPackageResourceRole'; Resolver = 'Resolve-OERAccessPackageId'
            ErrorId = 'AmbiguousAccessPackageName'; Pre = @{}
            Invoke = {
                Add-OERAccessPackageResourceRole -AccessPackage 'Dup' -Catalog 'cat-1' -ResourceOriginId 'grp-guid' `
                    -Role 'Member' -ErrorAction SilentlyContinue -ErrorVariable Err | Out-Null
                $Err
            }
        }
        @{
            Cmdlet = 'Add-OERAccessPackageResourceRole'; Resolver = 'Resolve-OERCatalogId'
            ErrorId = 'AmbiguousCatalogName'; Pre = @{ 'Resolve-OERAccessPackageId' = 'ap-1' }
            Invoke = {
                Add-OERAccessPackageResourceRole -AccessPackage 'AP-Sales' -Catalog 'Dup' -ResourceOriginId 'grp-guid' `
                    -Role 'Member' -ErrorAction SilentlyContinue -ErrorVariable Err | Out-Null
                $Err
            }
        }
        @{
            Cmdlet = 'Add-OERAccessPackageResourceRole'; Resolver = 'Resolve-OERGroupId'
            ErrorId = 'AmbiguousGroupName'; Pre = @{ 'Resolve-OERAccessPackageId' = 'ap-1'; 'Resolve-OERCatalogId' = 'cat-1' }
            Invoke = {
                Add-OERAccessPackageResourceRole -AccessPackage 'AP-Sales' -Catalog 'CAT-IT-Core' -Group 'Dup' `
                    -Role 'Member' -ErrorAction SilentlyContinue -ErrorVariable Err | Out-Null
                $Err
            }
        }
        @{
            Cmdlet = 'Add-OERAccessPackageResourceRole'; Resolver = 'Resolve-OERApplicationId'
            ErrorId = 'AmbiguousApplicationName'; Pre = @{ 'Resolve-OERAccessPackageId' = 'ap-1'; 'Resolve-OERCatalogId' = 'cat-1' }
            Invoke = {
                Add-OERAccessPackageResourceRole -AccessPackage 'AP-Sales' -Catalog 'CAT-IT-Core' -Application 'Dup' `
                    -Role 'Member' -ErrorAction SilentlyContinue -ErrorVariable Err | Out-Null
                $Err
            }
        }
        @{
            Cmdlet = 'Add-OERCatalogResource'; Resolver = 'Resolve-OERCatalogId'
            ErrorId = 'AmbiguousCatalogName'; Pre = @{}
            Invoke = {
                Add-OERCatalogResource -Catalog 'Dup' -Group 'Sales Team' -ErrorAction SilentlyContinue -ErrorVariable Err | Out-Null
                $Err
            }
        }
        @{
            Cmdlet = 'Add-OERCatalogResource'; Resolver = 'Resolve-OERGroupId'
            ErrorId = 'AmbiguousGroupName'; Pre = @{ 'Resolve-OERCatalogId' = 'cat-1' }
            Invoke = {
                Add-OERCatalogResource -Catalog 'CAT-IT-Core' -Group 'Dup' -ErrorAction SilentlyContinue -ErrorVariable Err | Out-Null
                $Err
            }
        }
        @{
            Cmdlet = 'Add-OERCatalogResource'; Resolver = 'Resolve-OERApplicationId'
            ErrorId = 'AmbiguousApplicationName'; Pre = @{ 'Resolve-OERCatalogId' = 'cat-1' }
            Invoke = {
                Add-OERCatalogResource -Catalog 'CAT-IT-Core' -Application 'Dup' -ErrorAction SilentlyContinue -ErrorVariable Err | Out-Null
                $Err
            }
        }
        @{
            Cmdlet = 'Add-OERGroupEligibility'; Resolver = 'Resolve-OERGroupId'
            ErrorId = 'AmbiguousGroupName'; Pre = @{}
            Invoke = {
                Add-OERGroupEligibility -Group 'Dup' -PrincipalId 'aaaa0000-0000-0000-0000-000000000001' `
                    -Confirm:$false -ErrorAction SilentlyContinue -ErrorVariable Err | Out-Null
                $Err
            }
        }
        @{
            Cmdlet = 'Add-OERGroupMember'; Resolver = 'Resolve-OERGroupId'
            ErrorId = 'AmbiguousGroupName'; Pre = @{}
            Invoke = {
                Add-OERGroupMember -Group 'Dup' -PrincipalId 'aaaa0000-0000-0000-0000-000000000001' `
                    -Confirm:$false -ErrorAction SilentlyContinue -ErrorVariable Err | Out-Null
                $Err
            }
        }
        @{
            Cmdlet = 'Get-OERAccessPackage'; Resolver = 'Resolve-OERCatalogId'
            ErrorId = 'AmbiguousCatalogName'; Pre = @{}
            Invoke = {
                Get-OERAccessPackage -Catalog 'Dup' -ErrorAction SilentlyContinue -ErrorVariable Err | Out-Null
                $Err
            }
        }
        @{
            Cmdlet = 'Get-OERAccessPackageAssignment'; Resolver = 'Resolve-OERAccessPackageId'
            ErrorId = 'AmbiguousAccessPackageName'; Pre = @{}
            Invoke = {
                Get-OERAccessPackageAssignment -AccessPackage 'Dup' -ErrorAction SilentlyContinue -ErrorVariable Err | Out-Null
                $Err
            }
        }
        @{
            Cmdlet = 'Get-OERAccessPackageAssignmentPolicy'; Resolver = 'Resolve-OERAccessPackageId'
            ErrorId = 'AmbiguousAccessPackageName'; Pre = @{}
            Invoke = {
                Get-OERAccessPackageAssignmentPolicy -AccessPackage 'Dup' -ErrorAction SilentlyContinue -ErrorVariable Err | Out-Null
                $Err
            }
        }
        @{
            Cmdlet = 'Get-OERAccessPackageResourceRole'; Resolver = 'Resolve-OERAccessPackageId'
            ErrorId = 'AmbiguousAccessPackageName'; Pre = @{}
            Invoke = {
                Get-OERAccessPackageResourceRole -AccessPackage 'Dup' -ErrorAction SilentlyContinue -ErrorVariable Err | Out-Null
                $Err
            }
        }
        @{
            Cmdlet = 'Get-OERAccessReviewInstance'; Resolver = 'Resolve-OERAccessReviewDefinitionId'
            ErrorId = 'AmbiguousName'; FailureId = 'AccessReviewDefinitionResolveFailed'; Pre = @{}
            Invoke = {
                Get-OERAccessReviewInstance -Definition 'Dup' -ErrorAction SilentlyContinue -ErrorVariable Err | Out-Null
                $Err
            }
        }
        @{
            Cmdlet = 'Get-OERAccessReviewInstanceDecision'; Resolver = 'Resolve-OERAccessReviewDefinitionId'
            ErrorId = 'AmbiguousName'; FailureId = 'AccessReviewDefinitionResolveFailed'; Pre = @{}
            Invoke = {
                Get-OERAccessReviewInstanceDecision -Definition 'Dup' -Instance 'inst-1' `
                    -ErrorAction SilentlyContinue -ErrorVariable Err | Out-Null
                $Err
            }
        }
        @{
            Cmdlet = 'Get-OERCatalogResource'; Resolver = 'Resolve-OERCatalogId'
            ErrorId = 'AmbiguousCatalogName'; Pre = @{}
            Invoke = {
                Get-OERCatalogResource -Catalog 'Dup' -ErrorAction SilentlyContinue -ErrorVariable Err | Out-Null
                $Err
            }
        }
        @{
            Cmdlet = 'Get-OERActiveDirectoryRoleAssignment'; Resolver = 'Resolve-OERDirectoryRoleDefinitionId'
            ErrorId = 'AmbiguousRoleName'; FailureId = 'RoleDefinitionReadFailed'; Pre = @{}
            Invoke = {
                Get-OERActiveDirectoryRoleAssignment -Role 'Dup' -ErrorAction SilentlyContinue -ErrorVariable Err | Out-Null
                $Err
            }
        }
        @{
            Cmdlet = 'Get-OERDirectoryRoleManagementPolicy'; Resolver = 'Resolve-OERDirectoryRoleDefinitionId'
            ErrorId = 'AmbiguousRoleName'; FailureId = 'RoleDefinitionReadFailed'; Pre = @{}
            Invoke = {
                Get-OERDirectoryRoleManagementPolicy -Role 'Dup' -ErrorAction SilentlyContinue -ErrorVariable Err | Out-Null
                $Err
            }
        }
        @{
            Cmdlet = 'Get-OEREligibleDirectoryRoleAssignment'; Resolver = 'Resolve-OERDirectoryRoleDefinitionId'
            ErrorId = 'AmbiguousRoleName'; FailureId = 'RoleDefinitionReadFailed'; Pre = @{}
            Invoke = {
                Get-OEREligibleDirectoryRoleAssignment -Role 'Dup' -ErrorAction SilentlyContinue -ErrorVariable Err | Out-Null
                $Err
            }
        }
        @{
            Cmdlet = 'Get-OERGroupEligibility'; Resolver = 'Resolve-OERGroupId'
            ErrorId = 'AmbiguousGroupName'; Pre = @{}
            Invoke = {
                Get-OERGroupEligibility -Group 'Dup' -ErrorAction SilentlyContinue -ErrorVariable Err | Out-Null
                $Err
            }
        }
        @{
            Cmdlet = 'Get-OERGroupMember'; Resolver = 'Resolve-OERGroupId'
            ErrorId = 'AmbiguousGroupName'; Pre = @{}
            Invoke = {
                Get-OERGroupMember -Group 'Dup' -ErrorAction SilentlyContinue -ErrorVariable Err | Out-Null
                $Err
            }
        }
        @{
            Cmdlet = 'Get-OERGroupPimPolicy'; Resolver = 'Resolve-OERGroupId'
            ErrorId = 'AmbiguousGroupName'; Pre = @{}
            Invoke = {
                Get-OERGroupPimPolicy -Group 'Dup' -ErrorAction SilentlyContinue -ErrorVariable Err | Out-Null
                $Err
            }
        }
        @{
            Cmdlet = 'Invoke-OERAccessReviewInstanceDecision'; Resolver = 'Resolve-OERAccessReviewDefinitionId'
            ErrorId = 'AmbiguousName'; FailureId = 'AccessReviewDefinitionResolveFailed'; Pre = @{}
            Invoke = {
                Invoke-OERAccessReviewInstanceDecision -Definition 'Dup' -Instance 'inst-1' -Confirm:$false `
                    -ErrorAction SilentlyContinue -ErrorVariable Err | Out-Null
                $Err
            }
        }
        @{
            Cmdlet = 'New-OERAccessPackageAssignment'; Resolver = 'Resolve-OERAccessPackageId'
            ErrorId = 'AmbiguousAccessPackageName'; Pre = @{}
            Invoke = {
                New-OERAccessPackageAssignment -AccessPackage 'Dup' -Policy 'pol-1' `
                    -TargetId 'aaaa0000-0000-0000-0000-000000000001' -Confirm:$false `
                    -ErrorAction SilentlyContinue -ErrorVariable Err | Out-Null
                $Err
            }
        }
        @{
            Cmdlet = 'New-OERAccessPackageAssignmentPolicy'; Resolver = 'Resolve-OERAccessPackageId'
            ErrorId = 'AmbiguousAccessPackageName'; Pre = @{}
            Invoke = {
                $Scope = New-OERAccessPackageRequestorScope -Scope AllMemberUsers
                New-OERAccessPackageAssignmentPolicy -AccessPackage 'Dup' -DisplayName 'Default' `
                    -RequestorScope $Scope -DurationInDays 30 -Confirm:$false `
                    -ErrorAction SilentlyContinue -ErrorVariable Err | Out-Null
                $Err
            }
        }
        @{
            Cmdlet = 'New-OERActiveDirectoryRoleAssignment'; Resolver = 'Resolve-OERDirectoryRoleDefinitionId'
            ErrorId = 'AmbiguousRoleName'; FailureId = 'RoleDefinitionReadFailed'; Pre = @{}
            Invoke = {
                New-OERActiveDirectoryRoleAssignment -Role 'Dup' -PrincipalId 'aaaa0000-0000-0000-0000-000000000001' `
                    -DurationDays 30 -Confirm:$false -ErrorAction SilentlyContinue -ErrorVariable Err | Out-Null
                $Err
            }
        }
        @{
            Cmdlet = 'New-OEREligibleDirectoryRoleAssignment'; Resolver = 'Resolve-OERDirectoryRoleDefinitionId'
            ErrorId = 'AmbiguousRoleName'; FailureId = 'RoleDefinitionReadFailed'; Pre = @{}
            Invoke = {
                New-OEREligibleDirectoryRoleAssignment -Role 'Dup' -PrincipalId 'aaaa0000-0000-0000-0000-000000000001' `
                    -DurationDays 30 -Confirm:$false -ErrorAction SilentlyContinue -ErrorVariable Err | Out-Null
                $Err
            }
        }
        @{
            Cmdlet = 'Remove-OERAccessPackage'; Resolver = 'Resolve-OERAccessPackageId'
            ErrorId = 'AmbiguousAccessPackageName'; Pre = @{}
            Invoke = {
                Remove-OERAccessPackage -DisplayName 'Dup' -Confirm:$false -ErrorAction SilentlyContinue -ErrorVariable Err | Out-Null
                $Err
            }
        }
        @{
            Cmdlet = 'Remove-OERAccessPackageResourceRole'; Resolver = 'Resolve-OERAccessPackageId'
            ErrorId = 'AmbiguousAccessPackageName'; Pre = @{}
            Invoke = {
                Remove-OERAccessPackageResourceRole -AccessPackage 'Dup' -ResourceRoleScopeId 'scope-1' `
                    -Confirm:$false -ErrorAction SilentlyContinue -ErrorVariable Err | Out-Null
                $Err
            }
        }
        @{
            Cmdlet = 'Remove-OERAccessReviewDefinition'; Resolver = 'Resolve-OERAccessReviewDefinitionId'
            ErrorId = 'AmbiguousName'; Pre = @{}
            Invoke = {
                Remove-OERAccessReviewDefinition -DisplayName 'Dup' -Confirm:$false `
                    -ErrorAction SilentlyContinue -ErrorVariable Err | Out-Null
                $Err
            }
        }
        @{
            Cmdlet = 'Remove-OERActiveDirectoryRoleAssignment'; Resolver = 'Resolve-OERDirectoryRoleDefinitionId'
            ErrorId = 'AmbiguousRoleName'; FailureId = 'RoleDefinitionReadFailed'; Pre = @{}
            Invoke = {
                Remove-OERActiveDirectoryRoleAssignment -Role 'Dup' -PrincipalId 'aaaa0000-0000-0000-0000-000000000001' `
                    -Confirm:$false -ErrorAction SilentlyContinue -ErrorVariable Err | Out-Null
                $Err
            }
        }
        @{
            Cmdlet = 'Remove-OERCatalog'; Resolver = 'Resolve-OERCatalogId'
            ErrorId = 'AmbiguousCatalogName'; Pre = @{}
            Invoke = {
                Remove-OERCatalog -DisplayName 'Dup' -Confirm:$false -ErrorAction SilentlyContinue -ErrorVariable Err | Out-Null
                $Err
            }
        }
        @{
            Cmdlet = 'Remove-OERCatalogResource'; Resolver = 'Resolve-OERCatalogId'
            ErrorId = 'AmbiguousCatalogName'; Pre = @{}
            Invoke = {
                Remove-OERCatalogResource -ResourceId 'res-1' -Catalog 'Dup' -Confirm:$false `
                    -ErrorAction SilentlyContinue -ErrorVariable Err | Out-Null
                $Err
            }
        }
        @{
            Cmdlet = 'Remove-OEREligibleDirectoryRoleAssignment'; Resolver = 'Resolve-OERDirectoryRoleDefinitionId'
            ErrorId = 'AmbiguousRoleName'; FailureId = 'RoleDefinitionReadFailed'; Pre = @{}
            Invoke = {
                Remove-OEREligibleDirectoryRoleAssignment -Role 'Dup' -PrincipalId 'aaaa0000-0000-0000-0000-000000000001' `
                    -Confirm:$false -ErrorAction SilentlyContinue -ErrorVariable Err | Out-Null
                $Err
            }
        }
        @{
            Cmdlet = 'Remove-OERGroup'; Resolver = 'Resolve-OERGroupId'
            ErrorId = 'AmbiguousGroupName'; Pre = @{}
            Invoke = {
                Remove-OERGroup -Group 'Dup' -Confirm:$false -ErrorAction SilentlyContinue -ErrorVariable Err | Out-Null
                $Err
            }
        }
        @{
            Cmdlet = 'Remove-OERGroupEligibility'; Resolver = 'Resolve-OERGroupId'
            ErrorId = 'AmbiguousGroupName'; Pre = @{}
            Invoke = {
                Remove-OERGroupEligibility -Group 'Dup' -PrincipalId 'aaaa0000-0000-0000-0000-000000000001' `
                    -Confirm:$false -ErrorAction SilentlyContinue -ErrorVariable Err | Out-Null
                $Err
            }
        }
        @{
            Cmdlet = 'Remove-OERGroupMember'; Resolver = 'Resolve-OERGroupId'
            ErrorId = 'AmbiguousGroupName'; Pre = @{}
            Invoke = {
                Remove-OERGroupMember -Group 'Dup' -PrincipalId 'aaaa0000-0000-0000-0000-000000000001' `
                    -Confirm:$false -ErrorAction SilentlyContinue -ErrorVariable Err | Out-Null
                $Err
            }
        }
        @{
            Cmdlet = 'Send-OERAccessReviewReminder'; Resolver = 'Resolve-OERAccessReviewDefinitionId'
            ErrorId = 'AmbiguousName'; FailureId = 'AccessReviewDefinitionResolveFailed'; Pre = @{}
            Invoke = {
                Send-OERAccessReviewReminder -Definition 'Dup' -Instance 'inst-1' -Confirm:$false `
                    -ErrorAction SilentlyContinue -ErrorVariable Err | Out-Null
                $Err
            }
        }
        @{
            Cmdlet = 'Set-OERAccessPackage'; Resolver = 'Resolve-OERAccessPackageId'
            ErrorId = 'AmbiguousAccessPackageName'; Pre = @{}
            Invoke = {
                Set-OERAccessPackage -DisplayName 'Dup' -NewDisplayName 'Renamed' -Confirm:$false `
                    -ErrorAction SilentlyContinue -ErrorVariable Err | Out-Null
                $Err
            }
        }
        @{
            Cmdlet = 'Set-OERAccessReviewDefinition'; Resolver = 'Resolve-OERAccessReviewDefinitionId'
            ErrorId = 'AmbiguousName'; Pre = @{}
            Invoke = {
                Set-OERAccessReviewDefinition -Id 'Dup' -DisplayName 'Renamed' -Confirm:$false `
                    -ErrorAction SilentlyContinue -ErrorVariable Err | Out-Null
                $Err
            }
        }
        @{
            Cmdlet = 'Set-OERCatalog'; Resolver = 'Resolve-OERCatalogId'
            ErrorId = 'AmbiguousCatalogName'; Pre = @{}
            Invoke = {
                Set-OERCatalog -DisplayName 'Dup' -NewDisplayName 'Renamed' -Confirm:$false `
                    -ErrorAction SilentlyContinue -ErrorVariable Err | Out-Null
                $Err
            }
        }
        @{
            Cmdlet = 'Set-OERDirectoryRoleManagementPolicy'; Resolver = 'Resolve-OERDirectoryRoleDefinitionId'
            ErrorId = 'AmbiguousRoleName'; FailureId = 'RoleDefinitionReadFailed'; Pre = @{}
            Invoke = {
                Set-OERDirectoryRoleManagementPolicy -Role 'Dup' -ActivationMaxHours 8 -Confirm:$false `
                    -ErrorAction SilentlyContinue -ErrorVariable Err | Out-Null
                $Err
            }
        }
        @{
            Cmdlet = 'Set-OERGroup'; Resolver = 'Resolve-OERGroupId'
            ErrorId = 'AmbiguousGroupName'; Pre = @{}
            Invoke = {
                Set-OERGroup -Group 'Dup' -Description 'x' -Confirm:$false `
                    -ErrorAction SilentlyContinue -ErrorVariable Err | Out-Null
                $Err
            }
        }
        @{
            Cmdlet = 'Set-OERGroupPimPolicy'; Resolver = 'Resolve-OERGroupId'
            ErrorId = 'AmbiguousGroupName'; Pre = @{}
            Invoke = {
                Set-OERGroupPimPolicy -Group 'Dup' -ActivationMaxHours 8 -Confirm:$false `
                    -ErrorAction SilentlyContinue -ErrorVariable Err | Out-Null
                $Err
            }
        }
        @{
            Cmdlet = 'Stop-OERAccessReviewInstance'; Resolver = 'Resolve-OERAccessReviewDefinitionId'
            ErrorId = 'AmbiguousName'; FailureId = 'AccessReviewDefinitionResolveFailed'; Pre = @{}
            Invoke = {
                Stop-OERAccessReviewInstance -Definition 'Dup' -Instance 'inst-1' -Confirm:$false `
                    -ErrorAction SilentlyContinue -ErrorVariable Err | Out-Null
                $Err
            }
        }
    )
}

BeforeAll {
    $script:moduleName = 'Omnicit.EntraRBAC'
    Get-Module $script:moduleName | Remove-Module -Force -ErrorAction SilentlyContinue
    Import-Module $script:moduleName -Force -ErrorAction Stop
}

Describe 'An ambiguous display name is refused at every swept call site' {
    BeforeEach {
        InModuleScope $script:moduleName { $script:_OERAuthState = $null }
    }

    It '<Cmdlet> reports <ErrorId> and issues no Graph request when <Resolver> refuses an ambiguous name' -ForEach $script:GuardCases {
        Mock -ModuleName $script:moduleName Initialize-OERAuth {}
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {}
        foreach ($PreName in @($Pre.Keys)) {
            Mock -ModuleName $script:moduleName -CommandName $PreName -MockWith ([scriptblock]::Create("'$($Pre[$PreName])'"))
        }
        Mock -ModuleName $script:moduleName -CommandName $Resolver -MockWith {
            throw [System.Management.Automation.ErrorRecord]::new(
                [System.Exception]::new(
                    "Display name 'Dup' matches 2 objects (11111111-1111-1111-1111-111111111111, 22222222-2222-2222-2222-222222222222)."),
                'AmbiguousName', [System.Management.Automation.ErrorCategory]::InvalidArgument, 'Dup')
        }

        $Err = & $Invoke

        # The mutation is refused: nothing reached Graph at all.
        Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 0
        # Cmdlet-qualified id: a bare-code match would pass even with the WriteError deleted, because
        # PowerShell re-records the mock's thrown record into -ErrorVariable at every call boundary.
        @($Err | Where-Object { $_.FullyQualifiedErrorId -eq "$ErrorId,$Cmdlet" }).Count | Should -Be 1
        # The guard must RETURN, not fall through: without the return the cmdlet also emits its
        # misleading <Noun>NotFound record. A -Times 0 assertion on the Graph call cannot see that,
        # because the fall-through lands in the not-found branch, which also returns before the call.
        @($Err | Where-Object { $_.FullyQualifiedErrorId -like "*,$Cmdlet" }).Count | Should -Be 1
        # The candidate ids the operator needs in order to disambiguate survive into the message.
        $Reported = @($Err | Where-Object { $_.FullyQualifiedErrorId -eq "$ErrorId,$Cmdlet" })[0]
        $Reported.Exception.Message | Should -Match '11111111-1111-1111-1111-111111111111'
        $Reported.Exception.Message | Should -Match '22222222-2222-2222-2222-222222222222'
    }
}

Describe 'A failed resolver lookup is reported as itself at every swept call site, never as not found' {
    BeforeEach {
        InModuleScope $script:moduleName { $script:_OERAuthState = $null }
    }

    # The other half of the contract above. A resolver that THROWS something other than an ambiguous
    # name -- a 403, an exhausted 429, a 5xx -- has not shown that nothing by that name exists, so no
    # call site may book it as <Noun>NotFound. Only a $null return (a display name that matched
    # nothing) reaches the not-found branch. This Describe does not exercise that branch -- it covers
    # the failure side only, and makes no claim about which cmdlets' own unit tests cover the $null side.
    It '<Cmdlet> reports a 403 out of <Resolver> as a failure, never as *NotFound' -ForEach $script:GuardCases {
        Mock -ModuleName $script:moduleName Initialize-OERAuth {}
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {}
        foreach ($PreName in @($Pre.Keys)) {
            Mock -ModuleName $script:moduleName -CommandName $PreName -MockWith ([scriptblock]::Create("'$($Pre[$PreName])'"))
        }
        Mock -ModuleName $script:moduleName -CommandName $Resolver -MockWith {
            throw [System.Management.Automation.ErrorRecord]::new(
                [System.Exception]::new('Authorization_RequestDenied: Insufficient privileges to complete the operation.'),
                'Authorization_RequestDenied', [System.Management.Automation.ErrorCategory]::PermissionDenied, 'Dup')
        }
        # Computed per It, from this case's own FailureId: a case without the key reads $null here and
        # expects the resolver's own id, so nothing carries over from the directory role cases.
        $ExpectedId = if ($FailureId) { $FailureId } else { 'Authorization_RequestDenied' }

        $Err = & $Invoke

        # NARROWED ON PURPOSE, and the narrowing is the whole guard. -ErrorVariable also collects the
        # engine's own capture of the INNER throw, whose FullyQualifiedErrorId is the bare
        # 'Authorization_RequestDenied' whether or not this cmdlet re-published it -- measured, not
        # assumed (see the issue #71 Describe in Add-OERAccessPackageResourceRole.Tests.ps1). An
        # unnarrowed match would therefore pass with the catch reverted. Only the record this cmdlet
        # itself published carries its own name in InvocationInfo. Exactly one is the positive proof
        # the catch was reached; a cmdlet that falls through publishes its <Noun>NotFound instead, and
        # one that publishes both fails on the count.
        $Published = @(@($Err) | Where-Object {
                $_.InvocationInfo -and $_.InvocationInfo.MyCommand -and $_.InvocationInfo.MyCommand.Name -eq $Cmdlet
            })
        $Published.Count | Should -Be 1
        $Published[0].FullyQualifiedErrorId | Should -Match "^$ExpectedId"
        $Published[0].FullyQualifiedErrorId | Should -Not -Match 'NotFound' -Because (
            'a permission failure booked as a missing object is the failed-read-as-an-empty-fact defect')
        # The operator still learns WHY: the resolver's own text survives into what the cmdlet reports.
        $Published[0].Exception.Message | Should -Match 'Insufficient privileges'
        # Nothing reached Graph after the failed lookup. Only meaningful beside the count above, which
        # proves the catch was reached: a not-found fall-through also returns before any Graph call.
        Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 0
    }
}
