BeforeDiscovery {
    # Cross-cmdlet suite (named after no single function, like AccessReview.Pipeline.Tests.ps1):
    # every public call site swept for MEM-resolve-groupid-first-match-no-uniqueness is exercised
    # here, so a future cmdlet that drops the guard is caught in one place.
    # Pre = resolvers that must SUCCEED before the one under test is reached.
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
            Cmdlet = 'Get-OERCatalogResource'; Resolver = 'Resolve-OERCatalogId'
            ErrorId = 'AmbiguousCatalogName'; Pre = @{}
            Invoke = {
                Get-OERCatalogResource -Catalog 'Dup' -ErrorAction SilentlyContinue -ErrorVariable Err | Out-Null
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
            Cmdlet = 'Set-OERAccessPackage'; Resolver = 'Resolve-OERAccessPackageId'
            ErrorId = 'AmbiguousAccessPackageName'; Pre = @{}
            Invoke = {
                Set-OERAccessPackage -DisplayName 'Dup' -NewDisplayName 'Renamed' -Confirm:$false `
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
