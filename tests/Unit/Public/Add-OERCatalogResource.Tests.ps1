BeforeAll {
    $script:moduleName = 'Omnicit.EntraRBAC'
    Get-Module $script:moduleName | Remove-Module -Force -ErrorAction SilentlyContinue
    Import-Module $script:moduleName -Force -ErrorAction Stop
}

Describe 'Add-OERCatalogResource' {
    BeforeEach {
        InModuleScope $script:moduleName { $script:_OERAuthState = $null }
        Mock -ModuleName $script:moduleName Initialize-OERAuth {}
        Mock -ModuleName $script:moduleName Resolve-OERCatalogId { 'cat-1' }
        Mock -ModuleName $script:moduleName Resolve-OERCatalogResource { $null }
        Mock -ModuleName $script:moduleName Resolve-OERGroupId { 'grp-resolved' }
        Mock -ModuleName $script:moduleName Resolve-OERApplicationId { 'sp-resolved' }
    }

    It 'onboards a group by object id with AadGroup originSystem and no lookup' {
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {
            @{ id = 'req-1'; resource = @{ id = 'res-1'; displayName = 'Grp'; originSystem = 'AadGroup'; originId = 'grp-guid' } }
        } -ParameterFilter { $Method -eq 'POST' }
        $R = Add-OERCatalogResource -Catalog 'CAT-IT-Core' -GroupId 'grp-guid'
        $R.PSObject.TypeNames[0] | Should -Be 'Omnicit.EntraRBAC.CatalogResource'
        Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 1 -ParameterFilter {
            $Method -eq 'POST' -and $Uri -like '*resourceRequests' -and
            $Body.requestType -eq 'adminAdd' -and $Body.resource.originSystem -eq 'AadGroup' -and
            $Body.resource.originId -eq 'grp-guid'
        }
        Should -Invoke -ModuleName $script:moduleName Resolve-OERGroupId -Times 0
    }

    It 'onboards a group by name: resolves the display name to an id via Resolve-OERGroupId' {
        Mock -ModuleName $script:moduleName Resolve-OERGroupId { 'grp-from-name' }
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {
            @{ id = 'req-1'; resource = @{ id = 'res-1'; originSystem = 'AadGroup'; originId = 'grp-from-name' } }
        } -ParameterFilter { $Method -eq 'POST' }
        Add-OERCatalogResource -Catalog 'CAT-IT-Core' -Group 'Sales Team' | Out-Null
        Should -Invoke -ModuleName $script:moduleName Resolve-OERGroupId -Times 1 -ParameterFilter { $DisplayName -eq 'Sales Team' }
        Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 1 -ParameterFilter {
            $Method -eq 'POST' -and $Body.resource.originSystem -eq 'AadGroup' -and $Body.resource.originId -eq 'grp-from-name'
        }
    }

    It 'onboards an application by service principal id with AadApplication originSystem and no lookup' {
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {
            @{ id = 'req-1'; resource = @{ id = 'res-1'; originSystem = 'AadApplication'; originId = 'sp-guid' } }
        } -ParameterFilter { $Method -eq 'POST' }
        Add-OERCatalogResource -Catalog 'CAT-IT-Core' -ApplicationId 'sp-guid' | Out-Null
        Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 1 -ParameterFilter {
            $Method -eq 'POST' -and $Body.resource.originSystem -eq 'AadApplication' -and $Body.resource.originId -eq 'sp-guid'
        }
        Should -Invoke -ModuleName $script:moduleName Resolve-OERApplicationId -Times 0
    }

    It 'onboards an application by name: resolves via Resolve-OERApplicationId (servicePrincipals)' {
        Mock -ModuleName $script:moduleName Resolve-OERApplicationId { 'sp-from-name' }
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {
            @{ id = 'req-1'; resource = @{ id = 'res-1'; originSystem = 'AadApplication'; originId = 'sp-from-name' } }
        } -ParameterFilter { $Method -eq 'POST' }
        Add-OERCatalogResource -Catalog 'CAT-IT-Core' -Application 'Contoso Expense Portal' | Out-Null
        Should -Invoke -ModuleName $script:moduleName Resolve-OERApplicationId -Times 1 -ParameterFilter { $DisplayName -eq 'Contoso Expense Portal' }
        Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 1 -ParameterFilter {
            $Method -eq 'POST' -and $Body.resource.originSystem -eq 'AadApplication' -and $Body.resource.originId -eq 'sp-from-name'
        }
    }

    It 'onboards a SharePoint site: the URL goes in originId with no url field in the body' {
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {
            @{ id = 'req-2'; resource = @{ id = 'res-2'; originSystem = 'SharePointOnline' } }
        } -ParameterFilter { $Method -eq 'POST' }
        Add-OERCatalogResource -Catalog 'CAT-IT-Core' -SharePointSite 'https://contoso.sharepoint.com/sites/x' | Out-Null
        Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 1 -ParameterFilter {
            $Method -eq 'POST' -and $Body.resource.originSystem -eq 'SharePointOnline' -and
            $Body.resource.originId -eq 'https://contoso.sharepoint.com/sites/x' -and
            (-not $Body.resource.ContainsKey('url'))
        }
    }

    It 'errors GroupNotFound when -Group cannot be resolved and does not POST' {
        Mock -ModuleName $script:moduleName Resolve-OERGroupId { $null }
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {}
        Add-OERCatalogResource -Catalog 'CAT-IT-Core' -Group 'nope' -ErrorVariable err -ErrorAction SilentlyContinue | Out-Null
        $err.FullyQualifiedErrorId | Should -Match 'GroupNotFound'
        Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 0 -ParameterFilter { $Method -eq 'POST' }
    }

    It 'errors ApplicationNotFound when -Application cannot be resolved and does not POST' {
        Mock -ModuleName $script:moduleName Resolve-OERApplicationId { $null }
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {}
        Add-OERCatalogResource -Catalog 'CAT-IT-Core' -Application 'nope' -ErrorVariable err -ErrorAction SilentlyContinue | Out-Null
        $err.FullyQualifiedErrorId | Should -Match 'ApplicationNotFound'
        Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 0 -ParameterFilter { $Method -eq 'POST' }
    }

    It 'is idempotent: skips POST when the resource is already in the catalog' {
        Mock -ModuleName $script:moduleName Resolve-OERCatalogResource { @{ id = 'res-1'; originId = 'grp-guid'; displayName = 'Grp' } }
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {}
        $R = Add-OERCatalogResource -Catalog 'CAT-IT-Core' -GroupId 'grp-guid'
        $R.Id | Should -Be 'res-1'
        Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 0 -ParameterFilter { $Method -eq 'POST' }
    }

    It 'stamps CatalogId onto the idempotent already-exists return' {
        Mock -ModuleName $script:moduleName Resolve-OERCatalogResource { @{ id = 'res-1'; originId = 'grp-guid'; displayName = 'Grp' } }
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {}
        $R = Add-OERCatalogResource -Catalog 'CAT-IT-Core' -GroupId 'grp-guid'
        $R.CatalogId | Should -Be 'cat-1'
    }

    It 'stamps CatalogId onto the resource created inline in the POST response' {
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {
            @{ id = 'req-1'; resource = @{ id = 'res-1'; originSystem = 'AadGroup'; originId = 'grp-guid' } }
        } -ParameterFilter { $Method -eq 'POST' }
        $R = Add-OERCatalogResource -Catalog 'CAT-IT-Core' -GroupId 'grp-guid'
        $R.CatalogId | Should -Be 'cat-1'
    }

    It 'stamps CatalogId onto the fallback re-resolved resource when the POST response has no inline resource' {
        $script:FallbackResolveCallCount = 0
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {
            @{ id = 'req-1' }
        } -ParameterFilter { $Method -eq 'POST' }
        Mock -ModuleName $script:moduleName Resolve-OERCatalogResource {
            if ($script:FallbackResolveCallCount) { return @{ id = 'res-1'; originId = 'grp-guid'; displayName = 'Grp' } }
            $script:FallbackResolveCallCount = 1
            return $null
        }
        $R = Add-OERCatalogResource -Catalog 'CAT-IT-Core' -GroupId 'grp-guid'
        $R.Id | Should -Be 'res-1'
        $R.CatalogId | Should -Be 'cat-1'
    }

    It 'errors CatalogNotFound when the catalog cannot be resolved' {
        Mock -ModuleName $script:moduleName Resolve-OERCatalogId { $null }
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {}
        Add-OERCatalogResource -Catalog 'nope' -GroupId 'g-1' -ErrorVariable err -ErrorAction SilentlyContinue | Out-Null
        $err.FullyQualifiedErrorId | Should -Match 'CatalogNotFound'
        Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 0 -ParameterFilter { $Method -eq 'POST' }
    }

    It 'binds -Catalog from a piped Catalog object via the Id alias' {
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {
            @{ id = 'req-pipe'; resource = @{ id = 'res-pipe'; originSystem = 'AadGroup'; originId = 'grp-1' } }
        } -ParameterFilter { $Method -eq 'POST' }
        $CatalogObj = [pscustomobject]@{ Id = 'CAT-1'; DisplayName = 'CAT Core' }
        $CatalogObj.PSObject.TypeNames.Insert(0, 'Omnicit.EntraRBAC.Catalog')
        $R = $CatalogObj | Add-OERCatalogResource -GroupId 'grp-1'
        $R.PSObject.TypeNames[0] | Should -Be 'Omnicit.EntraRBAC.CatalogResource'
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
        } -ParameterFilter { $Method -eq 'POST' }
        Mock -ModuleName $script:moduleName Remove-OERErrorRecord { }
        $Err = $null
        $Result = Add-OERCatalogResource -Catalog 'CAT-IT-Core' -GroupId 'grp-guid' -Confirm:$false -ErrorAction SilentlyContinue -ErrorVariable Err
        $Result | Should -BeNullOrEmpty
        @($Err | Where-Object { $_.FullyQualifiedErrorId -eq 'Authorization_RequestDenied,Add-OERCatalogResource' }).Count |
            Should -Be 1
        Should -Invoke -ModuleName $script:moduleName Remove-OERErrorRecord -Times 1
    }
}
