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
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest { @{ id = 'ap-exists'; displayName = 'AP-Sales'; catalog = @{ id = 'cat-1' } } } -ParameterFilter { $Method -eq 'GET' -or -not $Method }
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

    It 'binds the catalog''s Id from a piped Catalog object that also carries the CatalogId alias member' {
        Mock -ModuleName $script:moduleName Resolve-OERCatalogId { 'CAT-1' }
        Mock -ModuleName $script:moduleName Resolve-OERAccessPackageId { $null }
        $CatalogObj = [pscustomobject]@{ Id = 'aaaa3333-0000-0000-0000-000000000001'; DisplayName = 'CAT Core' }
        $CatalogObj.PSObject.TypeNames.Insert(0, 'Omnicit.EntraRBAC.Catalog')
        $CatalogObj.CatalogId | Should -BeExactly 'aaaa3333-0000-0000-0000-000000000001'
        $CatalogObj | New-OERAccessPackage -DisplayName 'AP' -WhatIf | Out-Null
        Should -Invoke -ModuleName $script:moduleName Resolve-OERCatalogId -Times 1 -Exactly -ParameterFilter { $DisplayName -eq 'aaaa3333-0000-0000-0000-000000000001' }
    }

    It 'binds -Catalog from a piped access package by its CatalogId, never its own Id' {
        Mock -ModuleName $script:moduleName Resolve-OERAccessPackageId { $null }
        $Ap = [pscustomobject]@{ Id = 'aaaa2222-0000-0000-0000-000000000001'; DisplayName = 'AP-Old'; CatalogId = 'aaaa3333-0000-0000-0000-000000000001' }
        $Ap.PSObject.TypeNames.Insert(0, 'Omnicit.EntraRBAC.AccessPackage')
        $Ap | New-OERAccessPackage -DisplayName 'AP-New' -WhatIf | Out-Null
        Should -Invoke -ModuleName $script:moduleName Resolve-OERCatalogId -Times 1 -Exactly -ParameterFilter { $DisplayName -eq 'aaaa3333-0000-0000-0000-000000000001' }
        Should -Invoke -ModuleName $script:moduleName Resolve-OERCatalogId -Times 0 -ParameterFilter { $DisplayName -eq 'aaaa2222-0000-0000-0000-000000000001' }
    }

    It 'declares the -Catalog aliases CatalogId before Id' {
        $Aliases = @((Get-Command New-OERAccessPackage).Parameters['Catalog'].Aliases)
        $Aliases | Should -Be @('CatalogId', 'Id')
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
        Should -Invoke -ModuleName $script:moduleName Remove-OERErrorRecord -Times 1 -Exactly
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
            Should -Invoke -ModuleName $script:moduleName Remove-OERErrorRecord -Times 1 -Exactly
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
            Should -Invoke -ModuleName $script:moduleName Remove-OERErrorRecord -Times 1 -Exactly
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
            Mock -ModuleName $script:moduleName Resolve-OERCatalogId { 'cat-77' }
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
            Should -Invoke -ModuleName $script:moduleName Remove-OERErrorRecord -Times 1 -Exactly
        }
    }

    Context 'a name that exists in another catalog is never returned (BL-148a)' {
        BeforeEach {
            Mock -ModuleName $script:moduleName Invoke-OERGraphRequest { $null }
            Mock -ModuleName $script:moduleName Resolve-OERAccessPackageId { 'ap-other' }
            Mock -ModuleName $script:moduleName Invoke-OERGraphRequest { $null } -ParameterFilter { $Method -eq 'POST' }
        }

        It 'refuses with AccessPackageInAnotherCatalog, returns nothing and creates nothing' {
            Mock -ModuleName $script:moduleName Invoke-OERGraphRequest { $null }
            Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {
                @{ id = 'ap-other'; displayName = 'AP-Sales'; catalog = @{ id = 'cat-B' } }
            } -ParameterFilter { $Method -ne 'POST' }
            $Err = $null
            $R = New-OERAccessPackage -DisplayName 'AP-Sales' -Catalog 'CAT-IT-Core' -Confirm:$false `
                -ErrorAction SilentlyContinue -ErrorVariable Err
            $R | Should -BeNullOrEmpty
            $Mine = @($Err | Where-Object { $_.FullyQualifiedErrorId -eq 'AccessPackageInAnotherCatalog,New-OERAccessPackage' })
            $Mine.Count | Should -Be 1
            $Mine[0].CategoryInfo.Category | Should -Be 'ResourceExists'
            $Mine[0].TargetObject | Should -Be 'AP-Sales'
            $Mine[0].Exception.Message | Should -BeLike "*exists in another catalog (cat-B), not in catalog 'CAT-IT-Core' (cat-1)*nothing was created*"
            Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 0 -ParameterFilter { $Method -eq 'POST' }
        }

        It 'refuses under -WhatIf too' {
            Mock -ModuleName $script:moduleName Invoke-OERGraphRequest { $null }
            Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {
                @{ id = 'ap-other'; displayName = 'AP-Sales'; catalog = @{ id = 'cat-B' } }
            } -ParameterFilter { $Method -ne 'POST' }
            $Err = $null
            $R = New-OERAccessPackage -DisplayName 'AP-Sales' -Catalog 'CAT-IT-Core' -WhatIf `
                -ErrorAction SilentlyContinue -ErrorVariable Err
            $R | Should -BeNullOrEmpty
            @($Err | Where-Object { $_.FullyQualifiedErrorId -eq 'AccessPackageInAnotherCatalog,New-OERAccessPackage' }).Count | Should -Be 1
        }

        It 'returns the package when its catalog id differs only in letter case' {
            Mock -ModuleName $script:moduleName Invoke-OERGraphRequest { $null }
            Mock -ModuleName $script:moduleName Resolve-OERCatalogId { 'CAT-1' }
            Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {
                @{ id = 'ap-other'; displayName = 'AP-Sales'; catalog = @{ id = 'cat-1' } }
            } -ParameterFilter { $Method -ne 'POST' }
            $Err = $null
            $R = New-OERAccessPackage -DisplayName 'AP-Sales' -Catalog 'CAT-IT-Core' -ErrorAction SilentlyContinue -ErrorVariable Err
            $R.Id | Should -BeExactly 'ap-other'
            @($Err).Count | Should -Be 0
            Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 0 -ParameterFilter { $Method -eq 'POST' }
        }

        It 'refuses with the unreadable-catalog message when the read carries no catalog' {
            Mock -ModuleName $script:moduleName Invoke-OERGraphRequest { $null }
            Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {
                @{ id = 'ap-other'; displayName = 'AP-Sales' }
            } -ParameterFilter { $Method -ne 'POST' }
            $Err = $null
            $R = New-OERAccessPackage -DisplayName 'AP-Sales' -Catalog 'CAT-IT-Core' -Confirm:$false `
                -ErrorAction SilentlyContinue -ErrorVariable Err
            $R | Should -BeNullOrEmpty
            $Mine = @($Err | Where-Object { $_.FullyQualifiedErrorId -eq 'AccessPackageInAnotherCatalog,New-OERAccessPackage' })
            $Mine.Count | Should -Be 1
            $Mine[0].Exception.Message | Should -BeLike "*exists (ap-other), but its catalog could not be read*catalog 'CAT-IT-Core' (cat-1)*not returned and nothing was created*"
            Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 0 -ParameterFilter { $Method -eq 'POST' }
        }

        It 'reaches -ErrorVariable and stops under -ErrorAction Stop in a runspace without try' {
            $Lines = @(
                'Import-Module Omnicit.EntraRBAC -Force'
                '& (Get-Module Omnicit.EntraRBAC) {'
                '    Set-Item -Path function:script:Initialize-OERAuth -Value { $null = ''STUB-AUTH'' }'
                '    Set-Item -Path function:script:Resolve-OERCatalogId -Value { ''cat-1'' }'
                '    Set-Item -Path function:script:Resolve-OERAccessPackageId -Value { ''ap-other'' }'
                '    Set-Item -Path function:script:Invoke-OERGraphRequest -Value {'
                '        param($Uri, $Method, $Body)'
                '        if ($Method -eq ''POST'') { $global:OERPosted = $true; return $null }'
                '        @{ id = ''ap-other''; displayName = ''AP-Sales''; catalog = @{ id = ''cat-B'' } }'
                '    }'
                '}'
                '# The stubs must be the ones the module''s own calls resolve to, or the real transport is reachable.'
                '$Resolved = & (Get-Module Omnicit.EntraRBAC) {'
                '    (Get-Command Initialize-OERAuth).ScriptBlock.ToString().Contains(''STUB-AUTH'') -and'
                '    (Get-Command Resolve-OERCatalogId).ScriptBlock.ToString().Contains(''cat-1'') -and'
                '    (Get-Command Resolve-OERAccessPackageId).ScriptBlock.ToString().Contains(''ap-other'') -and'
                '    (Get-Command Invoke-OERGraphRequest).ScriptBlock.ToString().Contains(''OERPosted'')'
                '}'
                'if (-not $Resolved) { throw ''stubs do not resolve in module scope'' }'
                '$global:OERPosted = $false'
                '$null = New-OERAccessPackage -DisplayName ''AP-Sales'' -Catalog ''C'' -ErrorAction SilentlyContinue -ErrorVariable EV'
                '$global:OERVariableIds = @($EV | ForEach-Object { $_.FullyQualifiedErrorId })'
                'New-OERAccessPackage -DisplayName ''AP-Sales'' -Catalog ''C'' -ErrorAction Stop'
                '$global:OERReachedAfterStop = $true'
            )
            $Runspace = [runspacefactory]::CreateRunspace()
            $Runspace.Open()
            $Ps = [powershell]::Create()
            try {
                # First statement inside the try: the transport names throw in this runspace too, and the
                # test fails if anything reached one of them.
                Install-OERTransportTripwireInRunspace -Runspace $Runspace
                $Ps.Runspace = $Runspace
                $null = $Ps.AddScript(($Lines -join "`n"))
                $Thrown = $null
                try { $null = $Ps.Invoke() } catch { $Thrown = $PSItem }
                Test-OERTransportTripwireInRunspace -Runspace $Runspace
                $Ids = @($Runspace.SessionStateProxy.PSVariable.GetValue('OERVariableIds'))
                $After = $Runspace.SessionStateProxy.PSVariable.GetValue('OERReachedAfterStop')
                $Posted = $Runspace.SessionStateProxy.PSVariable.GetValue('OERPosted')
            } finally {
                $Ps.Dispose()
                $Runspace.Dispose()
            }
            $Ids | Should -Contain 'AccessPackageInAnotherCatalog,New-OERAccessPackage'
            $Thrown | Should -Not -BeNullOrEmpty
            $Thrown.ToString() | Should -BeLike '*exists in another catalog*'
            $After | Should -BeNullOrEmpty
            $Posted | Should -BeFalse
        }
    }

    Context 'the existence check is scoped to the catalog' {
        It 'looks the name up with -Catalog set to the resolved catalog id' {
            Mock -ModuleName $script:moduleName Resolve-OERAccessPackageId { $null }
            Mock -ModuleName $script:moduleName Invoke-OERGraphRequest { $null }
            Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {
                @{ id = 'ap-new'; displayName = 'AP-Sales' }
            } -ParameterFilter { $Method -eq 'POST' }
            New-OERAccessPackage -DisplayName 'AP-Sales' -Catalog 'CAT-IT-Core' -Confirm:$false | Out-Null
            Should -Invoke -ModuleName $script:moduleName Resolve-OERAccessPackageId -Times 1 -Exactly -ParameterFilter {
                $DisplayName -eq 'AP-Sales' -and $Catalog -eq 'cat-1'
            }
        }

        It 'creates the package when the name exists only in another catalog (the scoped lookup finds nothing)' {
            # The resolver is catalog-scoped, so a twin in another catalog is never a candidate: it
            # answers $null and the create goes ahead into the named catalog.
            Mock -ModuleName $script:moduleName Resolve-OERAccessPackageId { $null }
            Mock -ModuleName $script:moduleName Invoke-OERGraphRequest { $null }
            Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {
                @{ id = 'ap-new'; displayName = 'AP-Sales' }
            } -ParameterFilter { $Method -eq 'POST' }
            $R = New-OERAccessPackage -DisplayName 'AP-Sales' -Catalog 'CAT-IT-Core' -Confirm:$false
            $R.Id | Should -BeExactly 'ap-new'
            Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 1 -Exactly -ParameterFilter {
                $Method -eq 'POST' -and $Body.displayName -eq 'AP-Sales' -and $Body.catalog.id -eq 'cat-1'
            }
        }

        It 'publishes AccessPackageNotInCatalog as itself for a GUID name of another catalog, creating nothing' {
            Mock -ModuleName $script:moduleName Resolve-OERAccessPackageId {
                throw [System.Management.Automation.ErrorRecord]::new(
                    [System.Exception]::new('Access package is not in catalog.'),
                    'AccessPackageNotInCatalog',
                    [System.Management.Automation.ErrorCategory]::InvalidArgument,
                    '00000000-0000-0000-0000-000000000011')
            }
            Mock -ModuleName $script:moduleName Invoke-OERGraphRequest { $null }
            Mock -ModuleName $script:moduleName Invoke-OERGraphRequest -ParameterFilter { $Method -eq 'POST' } -MockWith { }
            $Err = $null
            $R = New-OERAccessPackage -DisplayName '00000000-0000-0000-0000-000000000011' -Catalog 'CAT-IT-Core' -Confirm:$false `
                -ErrorAction SilentlyContinue -ErrorVariable Err
            $R | Should -BeNullOrEmpty
            $Mine = @($Err | Where-Object { $_.FullyQualifiedErrorId -eq 'AccessPackageNotInCatalog,New-OERAccessPackage' })
            $Mine.Count | Should -Be 1
            $Mine[0].CategoryInfo.Category | Should -Be 'InvalidArgument'
            @($Err | Where-Object { $_.FullyQualifiedErrorId -like 'AccessPackageResolveFailed*' }).Count | Should -Be 0
            Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 0 -Exactly -ParameterFilter { $Method -eq 'POST' }
        }
    }

    Context 'create then call again converges (G8)' {
        AfterEach { Remove-Variable -Name OERT6Created -Scope Global -ErrorAction SilentlyContinue }

        It 'returns the existing package on the second call with exactly one POST over both' {
            # Relies on the file-level Resolve-OERCatalogId mock ('cat-1').
            $global:OERT6Created = $false
            Mock -ModuleName $script:moduleName Resolve-OERAccessPackageId { if ($global:OERT6Created) { 'ap-1' } else { $null } }
            Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {
                @{ id = 'ap-1'; displayName = 'AP-Sales'; catalog = @{ id = 'cat-1' } }
            }
            Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {
                @{ id = 'ap-1'; displayName = 'AP-Sales' }
            } -ParameterFilter { $Method -eq 'POST' }
            $First = New-OERAccessPackage -DisplayName 'AP-Sales' -Catalog 'CAT-IT-Core' -Confirm:$false
            $global:OERT6Created = $true
            $Second = New-OERAccessPackage -DisplayName 'AP-Sales' -Catalog 'CAT-IT-Core' -Confirm:$false
            $First.Id | Should -BeExactly 'ap-1'
            $Second.Id | Should -BeExactly 'ap-1'
            $Second.CatalogId | Should -BeExactly 'cat-1'
            Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 1 -Exactly -ParameterFilter { $Method -eq 'POST' }
        }
    }
}
