BeforeAll {
    $script:moduleName = 'Omnicit.EntraRBAC'
    Get-Module $script:moduleName | Remove-Module -Force -ErrorAction SilentlyContinue
    Import-Module $script:moduleName -Force -ErrorAction Stop
}

Describe 'Remove-OERCatalogResource' {
    BeforeEach {
        InModuleScope $script:moduleName { $script:_OERAuthState = $null }
        Mock -ModuleName $script:moduleName Initialize-OERAuth {}
        Mock -ModuleName $script:moduleName Resolve-OERCatalogId { 'cat-1' }
    }

    It 'posts an adminRemove resourceRequest with both the resource id and the catalog id' {
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest { @{ id = 'req-x' } } -ParameterFilter { $Method -eq 'POST' }
        Remove-OERCatalogResource -ResourceId 'res-1' -Catalog 'CAT-IT-Core' -Confirm:$false
        Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 1 -ParameterFilter {
            $Method -eq 'POST' -and $Uri -like '*resourceRequests' -and
            $Body.requestType -eq 'adminRemove' -and $Body.resource.id -eq 'res-1' -and
            $Body.catalog.id -eq 'cat-1'
        }
    }

    It 'errors with CatalogNotFound when the catalog cannot be resolved and does not POST' {
        Mock -ModuleName $script:moduleName Resolve-OERCatalogId { $null }
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {}
        Remove-OERCatalogResource -ResourceId 'res-1' -Catalog 'nope' -ErrorVariable Err -ErrorAction SilentlyContinue
        $Err[0].FullyQualifiedErrorId | Should -Match 'CatalogNotFound'
        Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 0
    }

    It 'does not POST under -WhatIf' {
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {}
        Remove-OERCatalogResource -ResourceId 'res-1' -Catalog 'CAT-IT-Core' -WhatIf
        Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 0
    }

    It 'accepts the resource id from the pipeline by the Id property' {
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest { @{ id = 'req-x' } } -ParameterFilter { $Method -eq 'POST' }
        [pscustomobject]@{ Id = 'res-1' } | Remove-OERCatalogResource -Catalog 'CAT-IT-Core' -Confirm:$false
        Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 1 -ParameterFilter {
            $Method -eq 'POST' -and $Body.requestType -eq 'adminRemove' -and $Body.resource.id -eq 'res-1' -and
            $Body.catalog.id -eq 'cat-1'
        }
    }

    It 'binds -Catalog from a piped object carrying CatalogId via the CatalogId alias' {
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest { @{ id = 'req-y' } } -ParameterFilter { $Method -eq 'POST' }
        [pscustomobject]@{ Id = 'res-2'; CatalogId = 'CAT-1' } | Remove-OERCatalogResource -Confirm:$false
        Should -Invoke -ModuleName $script:moduleName Resolve-OERCatalogId -Times 1 -ParameterFilter { $DisplayName -eq 'CAT-1' }
        Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 1 -ParameterFilter {
            $Method -eq 'POST' -and $Body.requestType -eq 'adminRemove' -and $Body.resource.id -eq 'res-2'
        }
    }

    It 'piped object with only Id binds -ResourceId and does not cross-bind to -Catalog' {
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest { @{ id = 'req-z' } } -ParameterFilter { $Method -eq 'POST' }
        # Object carries only Id -- should bind -ResourceId (Alias Id), NOT -Catalog (Alias CatalogId only)
        # -Catalog must be supplied explicitly; no ParameterNameConflictsWithAlias should be raised
        [pscustomobject]@{ Id = 'res-3' } | Remove-OERCatalogResource -Catalog 'CAT-IT-Core' -Confirm:$false
        Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 1 -ParameterFilter {
            $Method -eq 'POST' -and $Body.resource.id -eq 'res-3' -and $Body.catalog.id -eq 'cat-1'
        }
    }

    It 'a resource read via Get-OERCatalogResource pipes straight through, with no second display-name lookup' {
        # End-to-end proof for 3a/3b: Get-OERCatalogResource resolves 'CAT-X' once and
        # ConvertTo-OERCatalogResource stamps CatalogId onto every emitted resource. Remove-OERCatalogResource
        # binds -Catalog from that CatalogId via its existing [Alias('CatalogId')], so Resolve-OERCatalogId is
        # called a second time only with the already-resolved GUID -- never asked to re-look-up 'CAT-X'.
        Mock -ModuleName $script:moduleName Resolve-OERCatalogId {
            if ($DisplayName -eq 'CAT-X') { return 'cat-x-resolved-guid' }
            return $DisplayName
        }
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {
            @{ value = @(@{ id = 'res-1'; displayName = 'A'; originSystem = 'AadGroup' }) }
        } -ParameterFilter { $Uri -like '*catalogs/cat-x-resolved-guid/resources*' }
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest { @{ id = 'req-x' } } -ParameterFilter { $Method -eq 'POST' }

        Get-OERCatalogResource -Catalog 'CAT-X' | Remove-OERCatalogResource -Confirm:$false

        Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 1 -Exactly -ParameterFilter {
            $Method -eq 'POST' -and $Body.resource.id -eq 'res-1' -and $Body.catalog.id -eq 'cat-x-resolved-guid'
        }
        Should -Invoke -ModuleName $script:moduleName Resolve-OERCatalogId -Times 2 -Exactly
        Should -Invoke -ModuleName $script:moduleName Resolve-OERCatalogId -Times 1 -Exactly -ParameterFilter { $DisplayName -eq 'CAT-X' }
        Should -Invoke -ModuleName $script:moduleName Resolve-OERCatalogId -Times 1 -Exactly -ParameterFilter { $DisplayName -eq 'cat-x-resolved-guid' }
    }

    It 'refuses a piped Catalog object whose CatalogId alias collides with -ResourceId (mandatory guard)' {
        # Once Omnicit.EntraRBAC.Catalog carries a CatalogId AliasProperty (of Id), a piped Catalog
        # object satisfies BOTH -ResourceId (Alias Id) and -Catalog (Alias CatalogId) from the SAME
        # underlying value, which would otherwise POST resource=@{id=X};catalog=@{id=X} -- a
        # wrong-target adminRemove. A real resource id is never equal to its own catalog id, so this
        # must be refused before any Graph call.
        $CatalogObj = InModuleScope $script:moduleName {
            ConvertTo-OERCatalog -InputObject @{ id = 'aaaaaaaa-0000-0000-0000-000000000042'; displayName = 'CAT-IT-Core' }
        }
        # Echo back whatever was passed, mirroring the real resolver's GUID short-circuit (no Graph call).
        Mock -ModuleName $script:moduleName Resolve-OERCatalogId { $DisplayName }
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {}
        $Err = $null
        $CatalogObj | Remove-OERCatalogResource -Confirm:$false -ErrorAction SilentlyContinue -ErrorVariable Err | Out-Null
        $Err[0].FullyQualifiedErrorId | Should -Be 'ResourceIdEqualsCatalogId,Remove-OERCatalogResource'
        Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 0 -Exactly
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
        } -ParameterFilter { $Method -eq 'POST' }
        Mock -ModuleName $script:moduleName Remove-OERErrorRecord { }
        $Err = $null
        $Result = Remove-OERCatalogResource -ResourceId 'res-1' -Catalog 'CAT-IT-Core' -Confirm:$false -ErrorAction SilentlyContinue -ErrorVariable Err
        $Result | Should -BeNullOrEmpty
        @($Err | Where-Object { $_.FullyQualifiedErrorId -eq 'Authorization_RequestDenied,Remove-OERCatalogResource' }).Count |
            Should -Be 1
        Should -Invoke -ModuleName $script:moduleName Remove-OERErrorRecord -Times 1
    }
}
