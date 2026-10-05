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

Describe 'Add-OERCatalogResource -- a failed catalog resource read is not an empty fact' {
    BeforeEach {
        InModuleScope 'Omnicit.EntraRBAC' { $script:_OERAuthState = $null }
        # The read-back mock below counts its own calls in the TEST file's script scope (a mock body
        # defined here sees that scope, not the module's), so the reset belongs here and not in
        # InModuleScope: a counter left at 2 by the previous test would make the first call throw.
        $script:ReadBackCallCount = 0
        Mock -ModuleName 'Omnicit.EntraRBAC' Initialize-OERAuth {}
        Mock -ModuleName 'Omnicit.EntraRBAC' Resolve-OERCatalogId { 'cat-1' }
        Mock -ModuleName 'Omnicit.EntraRBAC' Invoke-OERGraphRequest {}
    }

    Context 'the idempotency read' {
        BeforeEach {
            Mock -ModuleName 'Omnicit.EntraRBAC' Resolve-OERCatalogResource {
                throw [System.Management.Automation.ErrorRecord]::new(
                    [System.Exception]::new('Authorization_RequestDenied: Insufficient privileges to complete the operation.'),
                    'Authorization_RequestDenied',
                    [System.Management.Automation.ErrorCategory]::PermissionDenied,
                    'cat-1')
            }
        }

        It 'surfaces a 403 on the idempotency read as itself and issues no POST (no adminAdd)' {
            $Err = $null
            $Result = Add-OERCatalogResource -Catalog 'cat-1' -GroupId 'grp-guid' -Confirm:$false `
                -ErrorAction SilentlyContinue -ErrorVariable Err

            # NARROWED ON PURPOSE: -ErrorVariable also holds the engine's own capture of the INNER
            # throw, so an unnarrowed match passes with the fix reverted (measured, issue #71 Describe
            # in Add-OERAccessPackageResourceRole.Tests.ps1).
            $Published = @($Err) | Where-Object {
                $_.InvocationInfo -and $_.InvocationInfo.MyCommand -and
                $_.InvocationInfo.MyCommand.Name -eq 'Add-OERCatalogResource'
            }
            $Result | Should -BeNullOrEmpty
            @($Published).Count | Should -Be 1
            $Published[0].FullyQualifiedErrorId | Should -Match '^Authorization_RequestDenied'
            $Published[0].CategoryInfo.Category | Should -Be 'PermissionDenied'
            # The counting proof, asserted first so that it is what fails when the return before the
            # POST is removed: a failed idempotency read must never lead to an adminAdd.
            Should -Invoke -ModuleName 'Omnicit.EntraRBAC' Invoke-OERGraphRequest -Times 0 -ParameterFilter { $Method -eq 'POST' }
            Should -Invoke -ModuleName 'Omnicit.EntraRBAC' Invoke-OERGraphRequest -Times 0 -Exactly
            # The positive half: the read was attempted exactly once and failed, so the zeros above are
            # not just a cmdlet that never got that far.
            Should -Invoke -ModuleName 'Omnicit.EntraRBAC' Resolve-OERCatalogResource -Times 1 -Exactly
        }

        It 'scrubs the failed idempotency read record before re-publishing it (bearer hygiene)' {
            # The catch re-publishes with $PSCmdlet.WriteError($PSItem): an $Error-based proof passes
            # with the Remove-OERErrorRecord line deleted. Guard the call directly instead
            # (rationale.md, #bearer-scrub-tests); the filtered call is also the positive proof that
            # this catch was reached.
            Mock -ModuleName 'Omnicit.EntraRBAC' Remove-OERErrorRecord { }
            $Err = $null
            Add-OERCatalogResource -Catalog 'cat-1' -GroupId 'grp-guid' -Confirm:$false `
                -ErrorAction SilentlyContinue -ErrorVariable Err | Out-Null
            $Published = @($Err) | Where-Object {
                $_.InvocationInfo -and $_.InvocationInfo.MyCommand -and
                $_.InvocationInfo.MyCommand.Name -eq 'Add-OERCatalogResource'
            }
            @($Published).Count | Should -Be 1
            Should -Invoke -ModuleName 'Omnicit.EntraRBAC' Remove-OERErrorRecord -Times 1 -Exactly -ParameterFilter {
                $Record.Exception.Message -eq 'Authorization_RequestDenied: Insufficient privileges to complete the operation.'
            }
        }

        It 'still proceeds to the POST when the idempotency read returns null (the resource is not in the catalog)' {
            Mock -ModuleName 'Omnicit.EntraRBAC' Resolve-OERCatalogResource { $null }
            Mock -ModuleName 'Omnicit.EntraRBAC' Invoke-OERGraphRequest {
                @{ id = 'req-1'; resource = @{ id = 'res-1'; originSystem = 'AadGroup'; originId = 'grp-guid' } }
            } -ParameterFilter { $Method -eq 'POST' }
            $Result = Add-OERCatalogResource -Catalog 'cat-1' -GroupId 'grp-guid' -Confirm:$false
            $Result.Id | Should -Be 'res-1'
            Should -Invoke -ModuleName 'Omnicit.EntraRBAC' Invoke-OERGraphRequest -Times 1 -Exactly -ParameterFilter { $Method -eq 'POST' }
        }
    }

    Context 'the read-back after a POST that returned no inline resource' {
        BeforeEach {
            Mock -ModuleName 'Omnicit.EntraRBAC' Invoke-OERGraphRequest { @{ id = 'req-1' } } -ParameterFilter { $Method -eq 'POST' }
            # First call (the idempotency read): the resource is not in the catalog yet. Second call
            # (the read-back after the POST): a 403.
            Mock -ModuleName 'Omnicit.EntraRBAC' Resolve-OERCatalogResource {
                $script:ReadBackCallCount++
                if ($script:ReadBackCallCount -eq 1) { return $null }
                throw [System.Management.Automation.ErrorRecord]::new(
                    [System.Exception]::new('Authorization_RequestDenied: Insufficient privileges to complete the operation.'),
                    'Authorization_RequestDenied',
                    [System.Management.Automation.ErrorCategory]::PermissionDenied,
                    'cat-1')
            }
        }

        It 'warns once, returns nothing and publishes no error when the read-back fails after a successful POST' {
            $Err = $null
            $Warn = $null
            $Result = Add-OERCatalogResource -Catalog 'cat-1' -GroupId 'grp-guid' -Confirm:$false `
                -ErrorAction SilentlyContinue -ErrorVariable Err -WarningAction SilentlyContinue -WarningVariable Warn

            # The positive half first: the catch WAS reached and said so, exactly once.
            @($Warn).Count | Should -Be 1
            $Warn[0].Message | Should -Match 'was added to catalog'
            $Warn[0].Message | Should -Match 'reading it back failed'
            $Warn[0].Message | Should -Be (
                "Resource 'grp-guid' was added to catalog 'cat-1', but reading it back failed, so it is not returned: " +
                'Authorization_RequestDenied: Insufficient privileges to complete the operation. ' +
                "Read it with Get-OERCatalogResource -Catalog 'cat-1'.")
            $Result | Should -BeNullOrEmpty
            # No record of the cmdlet's own: the resource exists, so the cmdlet did not fail. Narrowed
            # for the same reason as above -- the engine's capture of the inner throw is in $Err.
            @($Err | Where-Object {
                $_.InvocationInfo -and $_.InvocationInfo.MyCommand -and
                $_.InvocationInfo.MyCommand.Name -eq 'Add-OERCatalogResource'
            }).Count | Should -Be 0
            Should -Invoke -ModuleName 'Omnicit.EntraRBAC' Invoke-OERGraphRequest -Times 1 -Exactly -ParameterFilter { $Method -eq 'POST' }
            Should -Invoke -ModuleName 'Omnicit.EntraRBAC' Resolve-OERCatalogResource -Times 2 -Exactly
        }

        It 'scrubs the failed read-back record before warning (bearer hygiene)' {
            # The catch only warns, so $Error does not show whether the scrub ran. Guard the call
            # directly (rationale.md, #bearer-scrub-tests); the filtered call is also the positive proof
            # that this catch was reached, and it must be the only scrub on the path.
            Mock -ModuleName 'Omnicit.EntraRBAC' Remove-OERErrorRecord { }
            $Warn = $null
            Add-OERCatalogResource -Catalog 'cat-1' -GroupId 'grp-guid' -Confirm:$false `
                -ErrorAction SilentlyContinue -WarningAction SilentlyContinue -WarningVariable Warn | Out-Null
            @($Warn).Count | Should -Be 1
            Should -Invoke -ModuleName 'Omnicit.EntraRBAC' Remove-OERErrorRecord -Times 1 -Exactly -ParameterFilter {
                $Record.Exception.Message -eq 'Authorization_RequestDenied: Insufficient privileges to complete the operation.'
            }
        }

        It 'stays silent and returns nothing when the read-back returns null (no warning, as before)' {
            Mock -ModuleName 'Omnicit.EntraRBAC' Resolve-OERCatalogResource { $null }
            $Warn = $null
            $Result = Add-OERCatalogResource -Catalog 'cat-1' -GroupId 'grp-guid' -Confirm:$false `
                -ErrorAction SilentlyContinue -WarningAction SilentlyContinue -WarningVariable Warn
            $Result | Should -BeNullOrEmpty
            @($Warn).Count | Should -Be 0
            Should -Invoke -ModuleName 'Omnicit.EntraRBAC' Invoke-OERGraphRequest -Times 1 -Exactly -ParameterFilter { $Method -eq 'POST' }
            Should -Invoke -ModuleName 'Omnicit.EntraRBAC' Resolve-OERCatalogResource -Times 2 -Exactly
        }
    }
}
