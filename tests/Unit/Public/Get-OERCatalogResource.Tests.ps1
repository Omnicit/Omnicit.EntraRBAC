BeforeAll {
    $script:moduleName = 'Omnicit.EntraRBAC'
    Get-Module $script:moduleName | Remove-Module -Force -ErrorAction SilentlyContinue
    Import-Module $script:moduleName -Force -ErrorAction Stop
}

Describe 'Get-OERCatalogResource' {
    BeforeEach {
        InModuleScope $script:moduleName { $script:_OERAuthState = $null }
        Mock -ModuleName $script:moduleName Initialize-OERAuth {}
        Mock -ModuleName $script:moduleName Resolve-OERCatalogId { 'cat-1' }
    }

    It 'lists catalog resources' {
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {
            @{ value = @(@{ id = 'r1'; displayName = 'A'; originSystem = 'AadGroup' }) }
        }
        $R = Get-OERCatalogResource -Catalog 'CAT-IT-Core'
        $R[0].PSObject.TypeNames[0] | Should -Be 'Omnicit.EntraRBAC.CatalogResource'
        Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 1 -ParameterFilter { $Uri -like '*catalogs/cat-1/resources*' }
    }

    It 'reads roles from the resourceRoles endpoint with -IncludeRoles' {
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {
            @{ value = @(@{ id = 'res-1'; displayName = 'SomeGroup'; originSystem = 'AadGroup' }) }
        } -ParameterFilter { $Uri -like '*catalogs/cat-1/resources*' -and $Uri -notlike '*resourceRoles*' }
        Mock -ModuleName $script:moduleName Get-OERCatalogResourceRole { @(@{ displayName = 'Member'; id = 'role-1'; originId = 'Member_grp' }) }
        $R = Get-OERCatalogResource -Catalog 'CAT-IT-Core' -IncludeRoles
        $R[0].Roles[0].DisplayName | Should -Be 'Member'
        Should -Invoke -ModuleName $script:moduleName Get-OERCatalogResourceRole -Times 1
    }

    It 'errors CatalogNotFound when the catalog cannot be resolved' {
        Mock -ModuleName $script:moduleName Resolve-OERCatalogId { $null }
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {}
        Get-OERCatalogResource -Catalog 'nope' -ErrorVariable Err -ErrorAction SilentlyContinue | Out-Null
        $Err[0].FullyQualifiedErrorId | Should -Match 'CatalogNotFound'
        Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 0
    }

    It 'returns an empty result when the catalog has no resources' {
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest { @{ value = @() } }
        $R = Get-OERCatalogResource -Catalog 'CAT-IT-Core'
        $R | Should -BeNullOrEmpty
    }

    It 'still returns the resource (no roles) when role read fails, with a warning' {
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {
            @{ value = @(@{ id = 'res-1'; displayName = 'SomeGroup'; originSystem = 'AadGroup' }) }
        } -ParameterFilter { $Uri -like '*catalogs/cat-1/resources*' -and $Uri -notlike '*resourceRoles*' }
        Mock -ModuleName $script:moduleName Get-OERCatalogResourceRole { throw 'boom' }
        $R = Get-OERCatalogResource -Catalog 'CAT-IT-Core' -IncludeRoles -WarningAction SilentlyContinue
        $R[0].DisplayName | Should -Be 'SomeGroup'
        $R[0].Roles | Should -BeNullOrEmpty
    }

    It 'maps resource properties to typed output' {
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {
            @{
                value = @(
                    @{
                        id           = 'res-99'
                        displayName  = 'SomeGroup'
                        resourceType = 'AadGroup'
                        originId     = 'grp-guid'
                        originSystem = 'AadGroup'
                        url          = $null
                    }
                )
            }
        }
        $R = Get-OERCatalogResource -Catalog 'CAT-IT-Core'
        $R.Id          | Should -Be 'res-99'
        $R.DisplayName | Should -Be 'SomeGroup'
        $R.OriginSystem | Should -Be 'AadGroup'
    }

    It 'binds -Catalog from a piped Catalog object via the Id alias' {
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {
            @{ value = @(@{ id = 'res-pipe'; displayName = 'PipeGroup'; originSystem = 'AadGroup' }) }
        }
        $CatalogObj = [pscustomobject]@{ Id = 'CAT-1'; DisplayName = 'CAT Core' }
        $CatalogObj.PSObject.TypeNames.Insert(0, 'Omnicit.EntraRBAC.Catalog')
        $R = $CatalogObj | Get-OERCatalogResource
        $R[0].PSObject.TypeNames[0] | Should -Be 'Omnicit.EntraRBAC.CatalogResource'
        Should -Invoke -ModuleName $script:moduleName Resolve-OERCatalogId -Times 1 -ParameterFilter { $DisplayName -eq 'CAT-1' }
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
        } -ParameterFilter { $Uri -like '*catalogs/cat-1/resources*' }
        Mock -ModuleName $script:moduleName Remove-OERErrorRecord { }
        $Err = $null
        $Result = Get-OERCatalogResource -Catalog 'CAT-IT-Core' -ErrorAction SilentlyContinue -ErrorVariable Err
        $Result | Should -BeNullOrEmpty
        @($Err | Where-Object { $_.FullyQualifiedErrorId -eq 'Authorization_RequestDenied,Get-OERCatalogResource' }).Count |
            Should -Be 1
        Should -Invoke -ModuleName $script:moduleName Remove-OERErrorRecord -Times 1
    }

    It 'passes -All to the /resources read (closes rt-graph-list-reads-first-page-only)' {
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {
            @{ value = @(@{ id = 'r1'; displayName = 'A'; originSystem = 'AadGroup' }) }
        }
        Get-OERCatalogResource -Catalog 'CAT-IT-Core' | Out-Null
        Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 1 -Exactly -ParameterFilter {
            $Uri -like '*catalogs/cat-1/resources*' -and $All
        }
    }

    It 'stamps the resolved CatalogId onto every emitted resource' {
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {
            @{ value = @(@{ id = 'r1'; displayName = 'A'; originSystem = 'AadGroup' }) }
        }
        $R = Get-OERCatalogResource -Catalog 'CAT-IT-Core'
        $R.CatalogId | Should -Be 'cat-1'
    }
}
