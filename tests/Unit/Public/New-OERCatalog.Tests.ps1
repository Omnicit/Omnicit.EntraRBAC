BeforeAll {
    $script:moduleName = 'Omnicit.EntraRBAC'
    Get-Module $script:moduleName | Remove-Module -Force -ErrorAction SilentlyContinue
    Import-Module $script:moduleName -Force -ErrorAction Stop
}

Describe 'New-OERCatalog' {
    BeforeEach {
        InModuleScope $script:moduleName { $script:_OERAuthState = $null }
        Mock -ModuleName $script:moduleName Initialize-OERAuth {}
    }

    It 'creates a catalog with a display name' {
        Mock -ModuleName $script:moduleName Resolve-OERCatalogId { $null }
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {
            @{ id = 'cat-1'; displayName = 'CAT-IT-Core' }
        } -ParameterFilter { $Method -eq 'POST' }
        $Result = New-OERCatalog -DisplayName 'CAT-IT-Core'
        $Result.Id | Should -Be 'cat-1'
        $Result.PSObject.TypeNames[0] | Should -Be 'Omnicit.EntraRBAC.Catalog'
        Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 1 -ParameterFilter {
            $Method -eq 'POST' -and
            $Uri -eq 'v1.0/identityGovernance/entitlementManagement/catalogs' -and
            $Body.displayName -eq 'CAT-IT-Core' -and $Body.catalogType -eq 'userManaged'
        }
        Should -Invoke -ModuleName $script:moduleName Initialize-OERAuth -Times 1
    }

    It 'sets isExternallyVisible for -ExternallyVisible' {
        Mock -ModuleName $script:moduleName Resolve-OERCatalogId { $null }
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest { @{ id = 'c'; displayName = 'd' } } -ParameterFilter { $Method -eq 'POST' }
        New-OERCatalog -DisplayName 'd' -ExternallyVisible | Out-Null
        Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 1 -ParameterFilter {
            $Method -eq 'POST' -and $Body.isExternallyVisible -eq $true
        }
    }

    It 'is idempotent: returns the existing catalog without a POST' {
        Mock -ModuleName $script:moduleName Resolve-OERCatalogId { 'cat-exists' }
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {
            @{ id = 'cat-exists'; displayName = 'CAT-IT-Core' }
        } -ParameterFilter { $Method -eq 'GET' -or -not $Method }
        $Result = New-OERCatalog -DisplayName 'CAT-IT-Core'
        $Result.Id | Should -Be 'cat-exists'
        Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 0 -ParameterFilter { $Method -eq 'POST' }
    }

    It 'does not POST under -WhatIf' {
        Mock -ModuleName $script:moduleName Resolve-OERCatalogId { $null }
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {}
        New-OERCatalog -DisplayName 'wi' -WhatIf | Out-Null
        Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 0 -ParameterFilter { $Method -eq 'POST' }
    }

    It 'resolves the name from -Org/-Scope via the default template' {
        Mock -ModuleName $script:moduleName Resolve-OERCatalogId { $null }
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest { @{ id = 't'; displayName = 'CAT-IT-Core' } } -ParameterFilter { $Method -eq 'POST' }
        New-OERCatalog -Org 'IT' -Scope 'Core' | Out-Null
        Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 1 -ParameterFilter {
            $Method -eq 'POST' -and $Body.displayName -eq 'CAT-IT-Core'
        }
    }

    It 'surfaces a Graph failure as a non-terminating error on the existing-catalog GET and emits nothing' {
        # Guards two things the cmdlet must do on a Graph failure: call Remove-OERErrorRecord (the
        # mandatory bearer-token-hygiene line -- asserted via Should -Invoke, since a deleted line
        # would otherwise pass unnoticed) and write its OWN non-terminating record. Match the
        # cmdlet-QUALIFIED ErrorId: PowerShell auto-records the mock's throw into -ErrorVariable a
        # dozen times before the catch runs, so matching the bare Graph code would pass even with
        # WriteError deleted.
        Mock -ModuleName $script:moduleName Resolve-OERCatalogId { 'cat-exists' }
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {
            throw [System.Management.Automation.ErrorRecord]::new(
                [System.Exception]::new('Authorization_RequestDenied: Insufficient privileges.'),
                'Authorization_RequestDenied',
                [System.Management.Automation.ErrorCategory]::PermissionDenied,
                $null)
        }
        Mock -ModuleName $script:moduleName Remove-OERErrorRecord { }
        $Err = $null
        $Result = New-OERCatalog -DisplayName 'CAT-IT-Core' -Confirm:$false -ErrorAction SilentlyContinue -ErrorVariable Err
        $Result | Should -BeNullOrEmpty
        @($Err | Where-Object { $_.FullyQualifiedErrorId -eq 'Authorization_RequestDenied,New-OERCatalog' }).Count |
            Should -Be 1
        Should -Invoke -ModuleName $script:moduleName Remove-OERErrorRecord -Times 1
    }

    It 'surfaces a Graph failure as a non-terminating error on the create POST and emits nothing' {
        Mock -ModuleName $script:moduleName Resolve-OERCatalogId { $null }
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {
            throw [System.Management.Automation.ErrorRecord]::new(
                [System.Exception]::new('TooManyRequests: throttled.'),
                'TooManyRequests',
                [System.Management.Automation.ErrorCategory]::LimitsExceeded,
                $null)
        } -ParameterFilter { $Method -eq 'POST' }
        Mock -ModuleName $script:moduleName Remove-OERErrorRecord { }
        $Err = $null
        $Result = New-OERCatalog -DisplayName 'CAT-IT-Core' -Confirm:$false -ErrorAction SilentlyContinue -ErrorVariable Err
        $Result | Should -BeNullOrEmpty
        @($Err | Where-Object { $_.FullyQualifiedErrorId -eq 'TooManyRequests,New-OERCatalog' }).Count |
            Should -Be 1
        Should -Invoke -ModuleName $script:moduleName Remove-OERErrorRecord -Times 1
    }

    Context 'pre-check failure must not create a duplicate' {
        It 'errors with CatalogResolveFailed and does NOT create when the pre-check throws' {
            Mock -ModuleName $script:moduleName Resolve-OERCatalogId { throw 'Graph returned 429 TooManyRequests' }
            Mock -ModuleName $script:moduleName Invoke-OERGraphRequest -ParameterFilter { $Method -eq 'POST' } -MockWith { }
            New-OERCatalog -DisplayName 'CAT-IT-Core' -Confirm:$false -ErrorAction SilentlyContinue -ErrorVariable Err
            Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -ParameterFilter { $Method -eq 'POST' } -Times 0
            @($Err | Where-Object { $_.FullyQualifiedErrorId -eq 'CatalogResolveFailed,New-OERCatalog' }).Count | Should -Be 1
        }

        It 'scrubs the bearer-carrying record before reporting the pre-check failure' {
            Mock -ModuleName $script:moduleName Resolve-OERCatalogId { throw 'Graph returned 429 TooManyRequests' }
            Mock -ModuleName $script:moduleName Remove-OERErrorRecord { }
            New-OERCatalog -DisplayName 'CAT-IT-Core' -Confirm:$false -ErrorAction SilentlyContinue
            Should -Invoke -ModuleName $script:moduleName Remove-OERErrorRecord -Times 1
        }

        It 'still creates when the pre-check genuinely finds nothing' {
            Mock -ModuleName $script:moduleName Resolve-OERCatalogId { $null }
            Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {
                @{ id = 'cat-new'; displayName = 'CAT-IT-Core' }
            } -ParameterFilter { $Method -eq 'POST' }
            New-OERCatalog -DisplayName 'CAT-IT-Core' -Confirm:$false | Out-Null
            Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -ParameterFilter { $Method -eq 'POST' } -Times 1
        }
    }
}
