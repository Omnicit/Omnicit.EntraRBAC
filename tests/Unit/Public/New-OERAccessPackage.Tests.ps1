BeforeAll {
    $script:moduleName = 'Omnicit.EntraRBAC'
    Get-Module $script:moduleName | Remove-Module -Force -ErrorAction SilentlyContinue
    Import-Module $script:moduleName -Force -ErrorAction Stop
}

Describe 'New-OERAccessPackage' {
    BeforeEach {
        InModuleScope $script:moduleName { $script:_OERAuthState = $null }
        Mock -ModuleName $script:moduleName Initialize-OERAuth {}
        Mock -ModuleName $script:moduleName Resolve-OERCatalogId { 'cat-1' }
        # Default catch-all so no call can ever reach the REAL Invoke-OERGraphRequest. Several tests
        # below mock only the POST; the create path also issues a confirmation GET, and an unmatched
        # filtered mock falls through to the real command. Returning $null makes that read a no-op,
        # which drives the documented fall-back-to-the-create-response branch.
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest { $null }
    }

    It 'creates an access package in a catalog' {
        Mock -ModuleName $script:moduleName Resolve-OERAccessPackageId { $null }
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest { @{ id = 'ap-1'; displayName = 'AP-Sales'; catalogId = 'cat-1' } } -ParameterFilter { $Method -eq 'POST' }
        $R = New-OERAccessPackage -DisplayName 'AP-Sales' -Catalog 'CAT-IT-Core'
        $R.Id | Should -Be 'ap-1'
        $R.PSObject.TypeNames[0] | Should -Be 'Omnicit.EntraRBAC.AccessPackage'
        Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 1 -ParameterFilter {
            $Method -eq 'POST' -and $Uri -like '*accessPackages' -and $Body.displayName -eq 'AP-Sales' -and $Body.catalog.id -eq 'cat-1'
        }
    }

    It 'is idempotent: returns the existing package without a POST' {
        Mock -ModuleName $script:moduleName Resolve-OERAccessPackageId { 'ap-exists' }
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest { @{ id = 'ap-exists'; displayName = 'AP-Sales' } } -ParameterFilter { $Method -eq 'GET' -or -not $Method }
        $R = New-OERAccessPackage -DisplayName 'AP-Sales' -Catalog 'CAT-IT-Core'
        $R.Id | Should -Be 'ap-exists'
        $R.PSObject.TypeNames[0] | Should -Be 'Omnicit.EntraRBAC.AccessPackage'
        Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 0 -ParameterFilter { $Method -eq 'POST' }
    }

    It 'errors when the catalog cannot be resolved' {
        Mock -ModuleName $script:moduleName Resolve-OERCatalogId { $null }
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {}
        New-OERAccessPackage -DisplayName 'AP-Sales' -Catalog 'nope' -ErrorVariable err -ErrorAction SilentlyContinue | Out-Null
        $err.FullyQualifiedErrorId | Should -Match 'CatalogNotFound'
    }

    It 'creates an access package from -Name via the default template' {
        Mock -ModuleName $script:moduleName Resolve-OERCatalogId { 'cat-1' }
        Mock -ModuleName $script:moduleName Resolve-OERAccessPackageId { $null }
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest { @{ id = 'ap-2'; displayName = 'Sales'; catalogId = 'cat-1' } } -ParameterFilter { $Method -eq 'POST' }
        New-OERAccessPackage -Name 'Sales' -Catalog 'CAT-IT-Core' | Out-Null
        Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 1 -ParameterFilter {
            $Method -eq 'POST' -and $Body.displayName -eq 'Sales'
        }
    }

    It 'errors NameResolutionFailed when a template token cannot be resolved' {
        Mock -ModuleName $script:moduleName Resolve-OERCatalogId { 'cat-1' }
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {}
        New-OERAccessPackage -Name 'Sales' -Template '{name}_{missingtoken}' -Catalog 'CAT-IT-Core' -ErrorVariable err -ErrorAction SilentlyContinue | Out-Null
        $err[-1].FullyQualifiedErrorId | Should -Match 'NameResolutionFailed'
        Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 0 -ParameterFilter { $Method -eq 'POST' }
    }

    It 'binds -Catalog from a piped Catalog object via the Id alias' {
        Mock -ModuleName $script:moduleName Resolve-OERCatalogId { 'CAT-1' }
        Mock -ModuleName $script:moduleName Resolve-OERAccessPackageId { $null }
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {
            @{ id = 'ap-pipe'; displayName = 'AP'; catalogId = 'CAT-1' }
        } -ParameterFilter { $Method -eq 'POST' }
        $CatalogObj = [pscustomobject]@{ Id = 'CAT-1'; DisplayName = 'CAT Core' }
        $CatalogObj.PSObject.TypeNames.Insert(0, 'Omnicit.EntraRBAC.Catalog')
        $R = $CatalogObj | New-OERAccessPackage -DisplayName 'AP'
        $R.Id | Should -Be 'ap-pipe'
        Should -Invoke -ModuleName $script:moduleName Resolve-OERCatalogId -Times 1 -ParameterFilter { $DisplayName -eq 'CAT-1' }
    }

    It 'surfaces a Graph POST failure as a non-terminating error and emits nothing' {
        # Guards two things the cmdlet must do on a Graph failure: call Remove-OERErrorRecord (the
        # mandatory bearer-token-hygiene line -- asserted via Should -Invoke, since a deleted line
        # would otherwise pass unnoticed) and write its OWN non-terminating record. Match the
        # cmdlet-QUALIFIED ErrorId: PowerShell auto-records the mock's throw into -ErrorVariable a
        # dozen times before the catch runs, so matching the bare Graph code would pass even with
        # WriteError deleted.
        Mock -ModuleName $script:moduleName Resolve-OERAccessPackageId { $null }
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {
            throw [System.Management.Automation.ErrorRecord]::new(
                [System.Exception]::new('Request_BadRequest: The access package is not valid.'),
                'Request_BadRequest',
                [System.Management.Automation.ErrorCategory]::InvalidOperation,
                $null)
        } -ParameterFilter { $Method -eq 'POST' }
        Mock -ModuleName $script:moduleName Remove-OERErrorRecord { }
        $Err = $null
        $Result = New-OERAccessPackage -DisplayName 'AP-Sales' -Catalog 'CAT-IT-Core' `
            -Confirm:$false -ErrorAction SilentlyContinue -ErrorVariable Err
        $Result | Should -BeNullOrEmpty
        @($Err | Where-Object { $_.FullyQualifiedErrorId -eq 'Request_BadRequest,New-OERAccessPackage' }).Count |
            Should -Be 1
        Should -Invoke -ModuleName $script:moduleName Remove-OERErrorRecord -Times 1
    }

    Context 'pre-check failure must not create a duplicate' {
        It 'errors with AccessPackageResolveFailed and does NOT create when the pre-check throws' {
            Mock -ModuleName $script:moduleName Resolve-OERAccessPackageId { throw 'Graph returned 429 TooManyRequests' }
            Mock -ModuleName $script:moduleName Invoke-OERGraphRequest -ParameterFilter { $Method -eq 'POST' } -MockWith { }
            New-OERAccessPackage -DisplayName 'AP-Sales' -Catalog 'CAT-IT-Core' -Confirm:$false `
                -ErrorAction SilentlyContinue -ErrorVariable Err
            Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -ParameterFilter { $Method -eq 'POST' } -Times 0
            @($Err | Where-Object { $_.FullyQualifiedErrorId -eq 'AccessPackageResolveFailed,New-OERAccessPackage' }).Count | Should -Be 1
        }

        It 'scrubs the bearer-carrying record before reporting the pre-check failure' {
            Mock -ModuleName $script:moduleName Resolve-OERAccessPackageId { throw 'Graph returned 429 TooManyRequests' }
            Mock -ModuleName $script:moduleName Remove-OERErrorRecord { }
            New-OERAccessPackage -DisplayName 'AP-Sales' -Catalog 'CAT-IT-Core' -Confirm:$false -ErrorAction SilentlyContinue
            Should -Invoke -ModuleName $script:moduleName Remove-OERErrorRecord -Times 1
        }

        It 'still creates when the pre-check genuinely finds nothing' {
            Mock -ModuleName $script:moduleName Resolve-OERAccessPackageId { $null }
            Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {
                @{ id = 'ap-new'; displayName = 'AP-Sales'; catalogId = 'cat-1' }
            } -ParameterFilter { $Method -eq 'POST' }
            New-OERAccessPackage -DisplayName 'AP-Sales' -Catalog 'CAT-IT-Core' -Confirm:$false | Out-Null
            Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -ParameterFilter { $Method -eq 'POST' } -Times 1
        }
    }

    Context 'catalog lookup failure must not create a duplicate' {
        It 'errors with CatalogResolveFailed and does NOT create when the catalog lookup throws' {
            Mock -ModuleName $script:moduleName Resolve-OERCatalogId { throw 'Graph returned 429 TooManyRequests' }
            Mock -ModuleName $script:moduleName Invoke-OERGraphRequest -ParameterFilter { $Method -eq 'POST' } -MockWith { }
            New-OERAccessPackage -DisplayName 'AP-Sales' -Catalog 'CAT-IT-Core' -Confirm:$false `
                -ErrorAction SilentlyContinue -ErrorVariable Err
            Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -ParameterFilter { $Method -eq 'POST' } -Times 0
            @($Err | Where-Object { $_.FullyQualifiedErrorId -eq 'CatalogResolveFailed,New-OERAccessPackage' }).Count | Should -Be 1
        }

        It 'scrubs the bearer-carrying record before reporting the catalog lookup failure' {
            Mock -ModuleName $script:moduleName Resolve-OERCatalogId { throw 'Graph returned 429 TooManyRequests' }
            Mock -ModuleName $script:moduleName Remove-OERErrorRecord { }
            New-OERAccessPackage -DisplayName 'AP-Sales' -Catalog 'CAT-IT-Core' -Confirm:$false -ErrorAction SilentlyContinue
            Should -Invoke -ModuleName $script:moduleName Remove-OERErrorRecord -Times 1
        }

        It 'still reports CatalogNotFound when the catalog lookup genuinely finds nothing' {
            Mock -ModuleName $script:moduleName Resolve-OERCatalogId { $null }
            Mock -ModuleName $script:moduleName Invoke-OERGraphRequest -ParameterFilter { $Method -eq 'POST' } -MockWith { }
            New-OERAccessPackage -DisplayName 'AP-Sales' -Catalog 'nope' -Confirm:$false `
                -ErrorAction SilentlyContinue -ErrorVariable Err
            @($Err | Where-Object { $_.FullyQualifiedErrorId -eq 'CatalogNotFound,New-OERAccessPackage' }).Count | Should -Be 1
        }
    }

    Context 'CatalogId is populated on both output paths' {
        # The v1.0 accessPackage entity has no catalogId property and Graph does not echo the catalog
        # navigation property on a POST, so neither the create response nor a bare GET can carry it.
        # The idempotent read uses $expand=catalog and the create path follows its POST with one
        # confirmation read of the same shape, so create output and read output agree.

        It 'reads the existing package with $expand=catalog on the idempotent path' {
            Mock -ModuleName $script:moduleName Resolve-OERAccessPackageId { 'ap-exists' }
            Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {
                @{ id = 'ap-exists'; displayName = 'AP-Sales'; catalog = @{ id = 'cat-77' } }
            }
            $R = New-OERAccessPackage -DisplayName 'AP-Sales' -Catalog 'CAT-IT-Core'
            $R | Should -Not -BeNullOrEmpty
            $R.Id | Should -BeExactly 'ap-exists'
            $R.CatalogId | Should -BeExactly 'cat-77'
            Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 1 -ParameterFilter {
                $Uri -like '*accessPackages/ap-exists*' -and $Uri -match '\$expand=[^&]*\bcatalog\b'
            }
        }

        It 'follows the create POST with a confirmation read that populates CatalogId' {
            Mock -ModuleName $script:moduleName Resolve-OERAccessPackageId { $null }
            Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {
                @{ id = 'ap-1'; displayName = 'AP-Sales' }
            } -ParameterFilter { $Method -eq 'POST' }
            Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {
                @{ id = 'ap-1'; displayName = 'AP-Sales'; catalog = @{ id = 'cat-77' } }
            } -ParameterFilter { $Uri -like '*accessPackages/ap-1?*' }
            $R = New-OERAccessPackage -DisplayName 'AP-Sales' -Catalog 'CAT-IT-Core' -Confirm:$false
            # Prove the object is real before measuring it: $null.CatalogId is also $null.
            $R | Should -Not -BeNullOrEmpty
            $R.Id | Should -BeExactly 'ap-1'
            $R.CatalogId | Should -BeExactly 'cat-77'
            Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 1 -Exactly -ParameterFilter {
                $Method -ne 'POST' -and $Uri -like '*accessPackages/ap-1*' -and $Uri -match '\$expand=[^&]*\bcatalog\b'
            }
        }

        It 'falls back to the create response and still emits when the confirmation read fails' {
            # The package WAS created. A failed confirmation read must never be reported as a failed
            # creation, and must not write an error record either.
            Mock -ModuleName $script:moduleName Resolve-OERAccessPackageId { $null }
            Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {
                @{ id = 'ap-1'; displayName = 'AP-Sales' }
            } -ParameterFilter { $Method -eq 'POST' }
            Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {
                throw [System.Management.Automation.ErrorRecord]::new(
                    [System.Exception]::new('TooManyRequests: throttled.'),
                    'TooManyRequests',
                    [System.Management.Automation.ErrorCategory]::LimitsExceeded,
                    $null)
            } -ParameterFilter { $Uri -like '*accessPackages/ap-1?*' }
            Mock -ModuleName $script:moduleName Remove-OERErrorRecord { }
            $Err = $null
            $R = New-OERAccessPackage -DisplayName 'AP-Sales' -Catalog 'CAT-IT-Core' `
                -Confirm:$false -ErrorAction SilentlyContinue -ErrorVariable Err
            $R | Should -Not -BeNullOrEmpty
            $R.Id | Should -BeExactly 'ap-1'
            $R.CatalogId | Should -BeNullOrEmpty
            @($Err | Where-Object { $_.FullyQualifiedErrorId -like '*,New-OERAccessPackage' }).Count | Should -Be 0
            # The failed confirmation read carried the bearer header too.
            Should -Invoke -ModuleName $script:moduleName Remove-OERErrorRecord -Times 1
        }
    }
}
