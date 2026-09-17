BeforeAll {
    $script:moduleName = 'Omnicit.EntraRBAC'
    Get-Module $script:moduleName | Remove-Module -Force -ErrorAction SilentlyContinue
    Import-Module $script:moduleName -Force -ErrorAction Stop
}

Describe 'Get-OERAccessPackageResourceRole' {
    BeforeEach {
        InModuleScope $script:moduleName { $script:_OERAuthState = $null }
        Mock -ModuleName $script:moduleName Initialize-OERAuth {}
        Mock -ModuleName $script:moduleName Resolve-OERAccessPackageId { 'ap-1' }
    }

    It 'lists resource roles using the expand-on-GET shape' {
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {
            @{ resourceRoleScopes = @(@{ id = 'rrs-1'; role = @{ displayName = 'Member' }; scope = @{ originId = 'g'; originSystem = 'AadGroup'; displayName = 'Root' } }) }
        }
        $R = Get-OERAccessPackageResourceRole -AccessPackage 'AP-Sales'
        $R[0].PSObject.TypeNames[0] | Should -Be 'Omnicit.EntraRBAC.AccessPackageResourceRole'
        $R[0].RoleName | Should -Be 'Member'
        # Shape of a real Graph payload (identifiers are placeholders): the scope label is 'Root', not the resource name -- must be preserved as
        # ScopeDisplayName, not ResourceDisplayName.
        $R[0].ScopeDisplayName | Should -Be 'Root'
        Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 1 -ParameterFilter {
            $Uri -like '*accessPackages/ap-1*' -and $Uri -like '*expand=resourceRoleScopes*'
        }
    }

    It 'errors AccessPackageNotFound when the package cannot be resolved' {
        Mock -ModuleName $script:moduleName Resolve-OERAccessPackageId { $null }
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {}
        Get-OERAccessPackageResourceRole -AccessPackage 'nope' -ErrorVariable Err -ErrorAction SilentlyContinue | Out-Null
        $Err[0].FullyQualifiedErrorId | Should -Match 'AccessPackageNotFound'
        Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 0
    }

    It 'returns nothing when the package has no bindings' {
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest { @{ resourceRoleScopes = @() } }
        Get-OERAccessPackageResourceRole -AccessPackage 'AP-Sales' | Should -BeNullOrEmpty
    }

    It 'returns nothing when the response has no resourceRoleScopes property' {
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest { @{ id = 'ap-1' } }
        Get-OERAccessPackageResourceRole -AccessPackage 'AP-Sales' | Should -BeNullOrEmpty
    }

    It 'surfaces a Graph failure as a non-terminating error and emits nothing' {
        # Guards two things the cmdlet must do on a Graph failure: call Remove-OERErrorRecord (the
        # mandatory bearer-token-hygiene line -- asserted via Should -Invoke, since a deleted line
        # would otherwise pass unnoticed) and write its OWN non-terminating record. Match the
        # cmdlet-QUALIFIED ErrorId: PowerShell auto-records the mock's throw into -ErrorVariable a
        # dozen times before the catch runs, so matching the bare Graph code would pass even with
        # WriteError deleted.
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {
            throw [System.Management.Automation.ErrorRecord]::new(
                [System.Exception]::new('Authorization_RequestDenied: Insufficient privileges.'),
                'Authorization_RequestDenied',
                [System.Management.Automation.ErrorCategory]::PermissionDenied,
                $null)
        }
        Mock -ModuleName $script:moduleName Remove-OERErrorRecord { }
        $Err = $null
        $Result = Get-OERAccessPackageResourceRole -AccessPackage 'AP-Sales' -ErrorAction SilentlyContinue -ErrorVariable Err
        $Result | Should -BeNullOrEmpty
        @($Err | Where-Object { $_.FullyQualifiedErrorId -eq 'Authorization_RequestDenied,Get-OERAccessPackageResourceRole' }).Count |
            Should -Be 1
        Should -Invoke -ModuleName $script:moduleName Remove-OERErrorRecord -Times 1
    }

    Context 'ResourceDisplayName join against the catalog resources' {
        BeforeEach {
            # Shape of a real payload (identifiers are placeholders): two DIFFERENT group bindings on the same access package. Both
            # scope.displayName values are the literal string 'Root' -- a single-binding fixture could
            # not catch the "everything says Root" regression, so this fixture always carries two
            # bindings whose scope.originId differ.
            Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {
                @{
                    catalog            = @{ id = 'cat-1' }
                    resourceRoleScopes = @(
                        @{
                            id    = 'rrs-role0001_scope001'
                            scope = @{ isRootScope = $true; originId = '00000000-0000-0000-0000-000000000050'; displayName = 'Root'; originSystem = 'AadGroup' }
                            role  = @{ originSystem = 'AadGroup'; displayName = 'Member'; originId = 'Member_00000000-0000-0000-0000-000000000050' }
                        },
                        @{
                            id    = 'rrs-role0002_scope002'
                            scope = @{ isRootScope = $true; originId = '00000000-0000-0000-0000-000000000054'; displayName = 'Root'; originSystem = 'AadGroup' }
                            role  = @{ originSystem = 'AadGroup'; displayName = 'Member'; originId = 'Member_00000000-0000-0000-0000-000000000054' }
                        }
                    )
                }
            }
            Mock -ModuleName $script:moduleName Get-OERCatalogResource {
                @(
                    [PSCustomObject]@{ OriginId = '00000000-0000-0000-0000-000000000050'; DisplayName = 'role_sec_finance'; OriginSystem = 'AadGroup' }
                    [PSCustomObject]@{ OriginId = '00000000-0000-0000-0000-000000000054'; DisplayName = 'role_sec_hr'; OriginSystem = 'AadGroup' }
                )
            }
        }

        It 'resolves two different group bindings to two different resource display names' {
            $R = @(Get-OERAccessPackageResourceRole -AccessPackage 'AP-Sales')
            $R.Count | Should -Be 2

            $First = $R | Where-Object { $_.OriginId -eq '00000000-0000-0000-0000-000000000050' }
            $Second = $R | Where-Object { $_.OriginId -eq '00000000-0000-0000-0000-000000000054' }

            $First.ResourceDisplayName | Should -Be 'role_sec_finance'
            $Second.ResourceDisplayName | Should -Be 'role_sec_hr'
            # The regression guard: both bindings must NOT collapse onto the same reported name.
            $First.ResourceDisplayName | Should -Not -Be $Second.ResourceDisplayName
            # And neither reported name is the raw scope label both bindings actually share.
            $First.ResourceDisplayName | Should -Not -Be $First.ScopeDisplayName
            $Second.ResourceDisplayName | Should -Not -Be $Second.ScopeDisplayName
        }

        It 'reads the catalog resources once, keyed by the package catalog id' {
            Get-OERAccessPackageResourceRole -AccessPackage 'AP-Sales' | Out-Null
            Should -Invoke -ModuleName $script:moduleName Get-OERCatalogResource -Times 1 -ParameterFilter {
                $Catalog -eq 'cat-1'
            }
        }

        It 'still returns every binding with ResourceDisplayName null when the catalog resource read throws' {
            Mock -ModuleName $script:moduleName Get-OERCatalogResource { throw 'Simulated catalog read failure' }
            # The failure is reported via Write-Verbose only -- never a warning and never an error on
            # the cmdlet's own output stream. -WarningVariable proves the "not a warning" half; the
            # bindings still coming back with the expected count and shape proves the read did not fail.
            $R = @(Get-OERAccessPackageResourceRole -AccessPackage 'AP-Sales' -WarningVariable Warn -WarningAction SilentlyContinue)
            $R.Count | Should -Be 2
            $Warn | Should -BeNullOrEmpty
            foreach ($Binding in $R) {
                $Binding.PSObject.Properties.Name | Should -Contain 'ResourceDisplayName'
                $Binding.ResourceDisplayName | Should -BeNullOrEmpty
                # ScopeDisplayName is unaffected by the failed join -- it comes straight off the binding.
                $Binding.ScopeDisplayName | Should -Be 'Root'
            }
        }
    }
}

Describe 'Get-OERAccessPackageResourceRole -- a failed resolver read is not a not-found (issue #71, fix round 1)' {
    BeforeEach {
        InModuleScope 'Omnicit.EntraRBAC' { $script:_OERAuthState = $null }
        Mock -ModuleName 'Omnicit.EntraRBAC' Initialize-OERAuth {}
        Mock -ModuleName 'Omnicit.EntraRBAC' Invoke-OERGraphRequest {}
    }

    It 'surfaces a 403 out of Resolve-OERAccessPackageId as itself, never as AccessPackageNotFound' {
        Mock -ModuleName 'Omnicit.EntraRBAC' Resolve-OERAccessPackageId {
            throw [System.Management.Automation.ErrorRecord]::new(
                [System.Exception]::new('Authorization_RequestDenied: Insufficient privileges to complete the operation.'),
                'Authorization_RequestDenied',
                [System.Management.Automation.ErrorCategory]::PermissionDenied,
                'ap-target')
        }
        $Err = $null
        Get-OERAccessPackageResourceRole -AccessPackage 'AP-Sales' -ErrorAction SilentlyContinue -ErrorVariable Err | Out-Null

        # NARROWED ON PURPOSE, and the narrowing is the whole guard. -ErrorVariable also collects
        # the engine's own capture of the INNER throw, whose FullyQualifiedErrorId is the bare
        # 'Authorization_RequestDenied' whether or not this cmdlet re-published it -- measured, not
        # assumed. An unnarrowed $Err[0] or -join match therefore passes with the fix reverted.
        # Only the record this cmdlet published carries its own name in InvocationInfo.
        $Published = @($Err) | Where-Object {
            $_.InvocationInfo -and $_.InvocationInfo.MyCommand -and
            $_.InvocationInfo.MyCommand.Name -eq 'Get-OERAccessPackageResourceRole'
        }
        @($Published).Count | Should -Be 1
        $Published[0].FullyQualifiedErrorId | Should -Match '^Authorization_RequestDenied'
        $Published[0].FullyQualifiedErrorId | Should -Not -Match 'AccessPackageNotFound' -Because (
            'a permission failure booked as a missing object is the failed-read-as-an-empty-fact defect of issue #76')
        $Published[0].CategoryInfo.Category | Should -Be 'PermissionDenied'
        Should -Invoke -ModuleName 'Omnicit.EntraRBAC' Invoke-OERGraphRequest -Times 0 -Exactly
    }
}
