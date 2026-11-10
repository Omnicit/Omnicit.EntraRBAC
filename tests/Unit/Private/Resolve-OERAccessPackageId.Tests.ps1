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

Describe 'Resolve-OERAccessPackageId' {
    It 'returns the Id verbatim without a Graph call' {
        InModuleScope $script:moduleName {
            Mock Invoke-OERGraphRequest {}
            Resolve-OERAccessPackageId -Id 'ap-1' | Should -Be 'ap-1'
            # -Exactly is redundant at -Times 0 -- Pester implies it at zero (verified against
            # 5.7.1 and 6.2.0) -- and is kept only for explicitness. The at-least trap is real,
            # but only for -Times N where N >= 1.
            Should -Invoke Invoke-OERGraphRequest -Times 0 -Exactly
        }
    }

    It 'resolves a display name to an id via a filtered query' {
        InModuleScope $script:moduleName {
            Mock Invoke-OERGraphRequest { @{ value = @(@{ id = 'ap-9'; displayName = 'AP-Sales' }) } }
            Resolve-OERAccessPackageId -DisplayName 'AP-Sales' | Should -Be 'ap-9'
            Should -Invoke Invoke-OERGraphRequest -Times 1 -ParameterFilter {
                $Uri -like "*accessPackages?*displayName eq 'AP-Sales'*"
            }
        }
    }

    It 'returns $null when no access package matches' {
        InModuleScope $script:moduleName {
            Mock Invoke-OERGraphRequest { @{ value = @() } }
            Resolve-OERAccessPackageId -DisplayName 'nope' | Should -Be $null
        }
    }

    It 'throws when neither -Id nor -DisplayName is supplied' {
        InModuleScope $script:moduleName {
            { Resolve-OERAccessPackageId } | Should -Throw
        }
    }

    It 'escapes single quotes in the display name' {
        InModuleScope $script:moduleName {
            Mock Invoke-OERGraphRequest { @{ value = @() } }
            Resolve-OERAccessPackageId -DisplayName "O'Brien" | Out-Null
            # Doubled quote first (''), then percent-encoded ('' -> %27%27).
            Should -Invoke Invoke-OERGraphRequest -Times 1 -ParameterFilter { $Uri -like "*O%27%27Brien*" }
        }
    }

    It 'percent-encodes a display name containing reserved characters so the query survives transport' {
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {
            @{ value = @(@{ id = 'ap-7'; displayName = 'R&D + Core' }) }
        }
        InModuleScope $script:moduleName {
            Resolve-OERAccessPackageId -DisplayName 'R&D + Core' | Should -Be 'ap-7'
        }
        Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 1 -ParameterFilter {
            $Uri -like "*displayName eq 'R%26D%20%2B%20Core'*"
        }
    }

    Context 'a GUID display name is confirmed to exist before it is handed back (issue #71)' {
        # The Omnicit.EntraRBAC.GraphExpectedError marker is what Invoke-OERGraphRequest returns
        # INSTEAD of raising, when the caller declared the answering code with -ExpectedErrorCode.
        # It is built inline in each mock below by type name rather than by calling into the
        # wrapper, so these tests measure the resolver's reaction to the marker and nothing else.

        It '4a: returns the GUID verbatim after exactly one existence read, and writes no error' {
            Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {
                @{ id = '22222222-2222-2222-2222-222222222222' }
            }
            $Resolved = InModuleScope $script:moduleName {
                Resolve-OERAccessPackageId -DisplayName '22222222-2222-2222-2222-222222222222' -ErrorVariable ResolveErr
                $ResolveErr | Should -BeNullOrEmpty
            }
            $Resolved | Should -Be '22222222-2222-2222-2222-222222222222'
            Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 1 -Exactly -ParameterFilter {
                $Uri -like '*accessPackages/22222222-2222-2222-2222-222222222222?*' -and
                $Uri -like '*select=id*'
            }
        }

        It '4a: declares the measured not-found code set to the transport so no other failure is softened' {
            # The set was narrowed on 2026-09-11 from a four-code guessed superset to the two codes
            # that were actually measured: AccessPackageNotFound (what entitlement management
            # answers for this GET) and NotFound (Convert-GraphHttpException's status-derived label
            # for a 404 with no parseable body code). The three removed codes are asserted absent,
            # not merely unmentioned -- a test that only checked the two present codes would stay
            # green if the old superset were restored beside them.
            Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {
                @{ id = '22222222-2222-2222-2222-222222222222' }
            }
            InModuleScope $script:moduleName {
                Resolve-OERAccessPackageId -DisplayName '22222222-2222-2222-2222-222222222222' | Out-Null
            }
            Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 1 -Exactly -ParameterFilter {
                @($ExpectedErrorCode) -contains 'AccessPackageNotFound' -and
                @($ExpectedErrorCode) -contains 'NotFound' -and
                @($ExpectedErrorCode).Count -eq 2 -and
                @($ExpectedErrorCode) -notcontains 'ResourceNotFound' -and
                @($ExpectedErrorCode) -notcontains 'ObjectNotFound' -and
                @($ExpectedErrorCode) -notcontains 'Request_ResourceNotFound'
            }
        }

        It '4b: throws AccessPackageNotFound naming the id when the probe answers AccessPackageNotFound' {
            # AccessPackageNotFound is the code MEASURED live on 2026-09-11 for a GET of a
            # non-existent access package id. It was outside the resolver's declared set until that
            # measurement, so the marker was never produced and this tailored ErrorRecord never
            # fired -- the caller saw Graph's own terse text with Category OperationStopped instead.
            # The mock reproduces the wrapper's real contract rather than handing back a marker
            # unconditionally: the service answers AccessPackageNotFound, and the marker is returned
            # ONLY when the caller declared that code. Drop AccessPackageNotFound from the
            # resolver's -ExpectedErrorCode list and this test goes red on the Graph error, which is
            # exactly what the live run saw.
            $Caught = InModuleScope $script:moduleName {
                Mock Invoke-OERGraphRequest {
                    if (@($ExpectedErrorCode) -notcontains 'AccessPackageNotFound') {
                        throw [System.Management.Automation.ErrorRecord]::new(
                            [System.Exception]::new('AccessPackageNotFound: The access package was not found.'),
                            'AccessPackageNotFound',
                            [System.Management.Automation.ErrorCategory]::OperationStopped,
                            $null)
                    }
                    $Marker = [PSCustomObject]@{
                        ExpectedErrorCode = 'AccessPackageNotFound'
                        StatusCode        = 404
                        Message           = 'AccessPackageNotFound: The access package was not found.'
                        Uri               = 'x'
                    }
                    $Marker.PSObject.TypeNames.Insert(0, 'Omnicit.EntraRBAC.GraphExpectedError')
                    $Marker
                }
                $Result = $null
                try { Resolve-OERAccessPackageId -DisplayName '77777777-7777-7777-7777-777777777777' } catch { $Result = $PSItem }
                $Result
            }
            $Caught | Should -Not -BeNullOrEmpty -Because 'the measured code must produce the resolver''s own ErrorRecord, not Graph''s terse one'
            $Caught.FullyQualifiedErrorId | Should -Match '^AccessPackageNotFound'
            $Caught.CategoryInfo.Category | Should -Be 'ObjectNotFound'
            $Caught.TargetObject | Should -Be '77777777-7777-7777-7777-777777777777'
            $Caught.Exception.Message | Should -BeLike "The access package id '77777777-7777-7777-7777-777777777777' does not resolve to an access package in this tenant.*"
        }

        It '4b: throws AccessPackageNotFound naming the id when the existence read answers not-found' {
            $Caught = InModuleScope $script:moduleName {
                Mock Invoke-OERGraphRequest {
                    $Marker = [PSCustomObject]@{
                        ExpectedErrorCode = 'NotFound'
                        StatusCode        = 404
                        Message           = 'NotFound: not found'
                        Uri               = 'x'
                    }
                    $Marker.PSObject.TypeNames.Insert(0, 'Omnicit.EntraRBAC.GraphExpectedError')
                    $Marker
                }
                $Result = $null
                try { Resolve-OERAccessPackageId -DisplayName '33333333-3333-3333-3333-333333333333' } catch { $Result = $PSItem }
                $Result
            }
            $Caught | Should -Not -BeNullOrEmpty
            $Caught.FullyQualifiedErrorId | Should -Match '^AccessPackageNotFound'
            $Caught.CategoryInfo.Category | Should -Be 'ObjectNotFound'
            $Caught.TargetObject | Should -Be '33333333-3333-3333-3333-333333333333'
            $Caught.Exception.Message | Should -Match '33333333-3333-3333-3333-333333333333'
        }

        It '4b: never answers a stale GUID with $null, which would read as "this name is free"' {
            $Outcome = InModuleScope $script:moduleName {
                Mock Invoke-OERGraphRequest {
                    $Marker = [PSCustomObject]@{ ExpectedErrorCode = 'AccessPackageNotFound'; StatusCode = 404; Message = 'x'; Uri = 'y' }
                    $Marker.PSObject.TypeNames.Insert(0, 'Omnicit.EntraRBAC.GraphExpectedError')
                    $Marker
                }
                $Returned = 'sentinel'
                $Threw = $false
                try { $Returned = Resolve-OERAccessPackageId -DisplayName '33333333-3333-3333-3333-333333333333' } catch { $Threw = $true }
                [PSCustomObject]@{ Returned = $Returned; Threw = $Threw }
            }
            $Outcome.Threw | Should -BeTrue -Because 'a $null return is what New-OERAccessPackage and the apply engine read as "create it"'
            $Outcome.Returned | Should -Be 'sentinel'
        }

        It '4c: a 403 on the existence read propagates as itself and is NOT reported as not-found' {
            $Caught = InModuleScope $script:moduleName {
                Mock Invoke-OERGraphRequest {
                    throw [System.Management.Automation.ErrorRecord]::new(
                        [System.Exception]::new('Authorization_RequestDenied: Insufficient privileges to complete the operation.'),
                        'Authorization_RequestDenied',
                        [System.Management.Automation.ErrorCategory]::PermissionDenied,
                        $null)
                }
                $Result = $null
                try { Resolve-OERAccessPackageId -DisplayName '44444444-4444-4444-4444-444444444444' } catch { $Result = $PSItem }
                $Result
            }
            $Caught | Should -Not -BeNullOrEmpty
            $Caught.FullyQualifiedErrorId | Should -Match '^Authorization_RequestDenied'
            $Caught.FullyQualifiedErrorId | Should -Not -Match 'AccessPackageNotFound' -Because (
                'a failed read booked as an empty fact is the defect class issue #76 closed; a permission failure ' +
                'must never be softened into "this access package does not exist"')
        }

        It '4c: a 429 on the existence read propagates as itself and is NOT reported as not-found' {
            $Caught = InModuleScope $script:moduleName {
                Mock Invoke-OERGraphRequest {
                    throw [System.Management.Automation.ErrorRecord]::new(
                        [System.Exception]::new('TooManyRequests: throttled'),
                        'TooManyRequests',
                        [System.Management.Automation.ErrorCategory]::LimitsExceeded,
                        $null)
                }
                $Result = $null
                try { Resolve-OERAccessPackageId -DisplayName '55555555-5555-5555-5555-555555555555' } catch { $Result = $PSItem }
                $Result
            }
            $Caught | Should -Not -BeNullOrEmpty
            $Caught.FullyQualifiedErrorId | Should -Match '^TooManyRequests'
            $Caught.FullyQualifiedErrorId | Should -Not -Match 'AccessPackageNotFound'
        }

        It '4f: -Id still short-circuits with no Graph call at all' {
            InModuleScope $script:moduleName {
                Mock Invoke-OERGraphRequest {}
                Resolve-OERAccessPackageId -Id '66666666-6666-6666-6666-666666666666' |
                    Should -Be '66666666-6666-6666-6666-666666666666'
                Should -Invoke Invoke-OERGraphRequest -Times 0 -Exactly
            }
        }
    }

    It 'throws AmbiguousName listing the candidates when two access packages share the display name' {
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {
            @{ value = @(
                    @{ id = 'dddddddd-1111-1111-1111-111111111111'; displayName = 'Dup-Name' },
                    @{ id = 'eeeeeeee-2222-2222-2222-222222222222'; displayName = 'Dup-Name' }) }
        }
        $Caught = InModuleScope $script:moduleName {
            $Result = $null
            try { Resolve-OERAccessPackageId -DisplayName 'Dup-Name' } catch { $Result = $PSItem }
            $Result
        }
        $Caught | Should -Not -BeNullOrEmpty
        $Caught.FullyQualifiedErrorId | Should -Match '^AmbiguousName'
        $Caught.Exception.Message | Should -Match 'dddddddd-1111-1111-1111-111111111111'
        $Caught.Exception.Message | Should -Match 'eeeeeeee-2222-2222-2222-222222222222'
    }

    It 'still returns the single match unchanged when exactly one access package has the name' {
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {
            @{ value = @(@{ id = 'ffffffff-3333-3333-3333-333333333333'; displayName = 'Solo-Name' }) }
        }
        InModuleScope $script:moduleName {
            Resolve-OERAccessPackageId -DisplayName 'Solo-Name' | Should -Be 'ffffffff-3333-3333-3333-333333333333'
        }
    }

    It 'still returns $null on a genuine no-match with an empty value collection' {
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest { @{ value = @() } }
        InModuleScope $script:moduleName {
            Resolve-OERAccessPackageId -DisplayName 'No-Such-Name' | Should -Be $null
        }
    }

    It 'still returns $null when the response carries no value collection at all' {
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest { @{ } }
        InModuleScope $script:moduleName {
            Resolve-OERAccessPackageId -DisplayName 'No-Such-Name' | Should -Be $null
        }
    }
}

Describe 'Resolve-OERAccessPackageId typed error records' {
    It 'throws ResolverInputMissing as a typed record: Resolve-OERAccessPackageId' {
        $Caught = InModuleScope 'Omnicit.EntraRBAC' {
            $Result = $null
            try { Resolve-OERAccessPackageId } catch { $Result = $PSItem }
            $Result
        }
        $Caught | Should -BeOfType ([System.Management.Automation.ErrorRecord])
        $Caught.FullyQualifiedErrorId | Should -BeExactly 'ResolverInputMissing'
        $Caught.CategoryInfo.Category | Should -Be 'InvalidArgument'
        $Caught.TargetObject | Should -BeNullOrEmpty
        $Caught.Exception.Message | Should -BeExactly 'Resolve-OERAccessPackageId requires either -Id or -DisplayName.'
    }
}

Describe 'Resolve-OERAccessPackageId -Catalog' {
    BeforeAll {
        $script:ApGuid = '00000000-0000-0000-0000-000000000067'
        $script:CatGuid = '00000000-0000-0000-0000-000000000068'
        $script:OtherCatGuid = '00000000-0000-0000-0000-000000000069'
    }

    It 'looks a name up within the catalog: one catalog lookup, one package request with both filter terms' {
        InModuleScope $script:moduleName {
            Mock Resolve-OERCatalogId { 'cat-1' }
            Mock Invoke-OERGraphRequest { @{ value = @(@{ id = 'ap-9'; displayName = 'AP-Sales' }) } }
            Resolve-OERAccessPackageId -DisplayName 'AP-Sales' -Catalog 'CAT-One' | Should -Be 'ap-9'
            Should -Invoke Resolve-OERCatalogId -Times 1 -Exactly -ParameterFilter { $DisplayName -ceq 'CAT-One' }
            Should -Invoke Invoke-OERGraphRequest -Times 1 -Exactly
            Should -Invoke Invoke-OERGraphRequest -Times 1 -Exactly -ParameterFilter {
                $Uri -ceq "v1.0/identityGovernance/entitlementManagement/accessPackages?`$filter=displayName eq 'AP-Sales' and catalog/id eq 'cat-1'&`$select=id,displayName"
            }
        }
    }

    It 'escapes a quote in both the package name and the catalog id' {
        InModuleScope $script:moduleName {
            Mock Resolve-OERCatalogId { "c'1" }
            Mock Invoke-OERGraphRequest { @{ value = @() } }
            Resolve-OERAccessPackageId -DisplayName "O'Brien" -Catalog 'CAT-One' | Out-Null
            Should -Invoke Invoke-OERGraphRequest -Times 1 -Exactly -ParameterFilter {
                $Uri -like "*displayName eq 'O%27%27Brien' and catalog/id eq 'c%27%271'*"
            }
        }
    }

    It 'throws AmbiguousName naming both ids and the catalog when two packages in the catalog share the name' {
        $Caught = InModuleScope $script:moduleName {
            Mock Resolve-OERCatalogId { 'cat-1' }
            Mock Invoke-OERGraphRequest {
                @{ value = @(@{ id = 'ap-a'; displayName = 'Dup' }, @{ id = 'ap-b'; displayName = 'Dup' }) }
            }
            $Result = $null
            try { Resolve-OERAccessPackageId -DisplayName 'Dup' -Catalog 'CAT-One' } catch { $Result = $PSItem }
            $Result
        }
        $Caught.FullyQualifiedErrorId | Should -BeExactly 'AmbiguousName'
        $Caught.CategoryInfo.Category | Should -Be 'InvalidArgument'
        $Caught.TargetObject | Should -Be 'Dup'
        $Caught.Exception.Message | Should -BeExactly "Access package display name 'Dup' matches 2 access packages in catalog 'CAT-One' (ap-a, ap-b). Entitlement management should keep access package display names unique within a catalog, so this name cannot identify a single access package. Re-run with the access package id instead of the display name."
    }

    It 'returns $null when the catalog holds no package of that name' {
        InModuleScope $script:moduleName {
            Mock Resolve-OERCatalogId { 'cat-1' }
            Mock Invoke-OERGraphRequest { @{ value = @() } }
            Resolve-OERAccessPackageId -DisplayName 'nope' -Catalog 'CAT-One' | Should -Be $null
        }
    }

    It 'returns the GUID when the package is in the catalog (case differs)' {
        $Resolved = InModuleScope $script:moduleName -Parameters @{ Ap = $script:ApGuid } {
            param($Ap)
            Mock Resolve-OERCatalogId { 'CAT-Id-One' }
            Mock Invoke-OERGraphRequest { @{ id = $Ap; catalog = @{ id = 'cat-id-one' } } }
            Resolve-OERAccessPackageId -DisplayName $Ap -Catalog 'CAT-One'
        }
        $Resolved | Should -Be $script:ApGuid
    }

    It 'sends the expand-catalog probe URI with the same expected codes' {
        InModuleScope $script:moduleName -Parameters @{ Ap = $script:ApGuid; Cat = $script:CatGuid } {
            param($Ap, $Cat)
            Mock Resolve-OERCatalogId { $Cat }
            Mock Invoke-OERGraphRequest { @{ id = $Ap; catalog = @{ id = $Cat } } }
            Resolve-OERAccessPackageId -DisplayName $Ap -Catalog $Cat | Out-Null
            Should -Invoke Invoke-OERGraphRequest -Times 1 -Exactly -ParameterFilter {
                $Uri -ceq "v1.0/identityGovernance/entitlementManagement/accessPackages/00000000-0000-0000-0000-000000000067?`$expand=catalog" -and
                @($ExpectedErrorCode).Count -eq 2 -and
                @($ExpectedErrorCode) -contains 'AccessPackageNotFound' -and
                @($ExpectedErrorCode) -contains 'NotFound'
            }
        }
    }

    It 'refuses a package id that is in another catalog with AccessPackageNotInCatalog and sends no second request' {
        $Caught = InModuleScope $script:moduleName -Parameters @{ Ap = $script:ApGuid; Cat = $script:CatGuid; Other = $script:OtherCatGuid } {
            param($Ap, $Cat, $Other)
            Mock Resolve-OERCatalogId { $Cat }
            Mock Invoke-OERGraphRequest { @{ id = $Ap; catalog = @{ id = $Other } } }
            $Result = $null
            try { Resolve-OERAccessPackageId -DisplayName $Ap -Catalog 'CAT-One' } catch { $Result = $PSItem }
            Should -Invoke Invoke-OERGraphRequest -Times 1 -Exactly
            $Result
        }
        $Caught.FullyQualifiedErrorId | Should -BeExactly 'AccessPackageNotInCatalog'
        $Caught.CategoryInfo.Category | Should -Be 'InvalidArgument'
        $Caught.TargetObject | Should -Be $script:ApGuid
        $Caught.Exception.Message | Should -BeExactly "Access package '$($script:ApGuid)' is not in catalog 'CAT-One' ($($script:CatGuid)): it belongs to catalog $($script:OtherCatGuid). Nothing was written to it. Name the access package's own catalog, or omit -Catalog."
    }

    It 'refuses an answer that carries no catalog with AccessPackageNotInCatalog' {
        $Caught = InModuleScope $script:moduleName -Parameters @{ Ap = $script:ApGuid; Cat = $script:CatGuid } {
            param($Ap, $Cat)
            Mock Resolve-OERCatalogId { $Cat }
            Mock Invoke-OERGraphRequest { @{ id = $Ap } }
            $Result = $null
            try { Resolve-OERAccessPackageId -DisplayName $Ap -Catalog 'CAT-One' } catch { $Result = $PSItem }
            $Result
        }
        $Caught.FullyQualifiedErrorId | Should -BeExactly 'AccessPackageNotInCatalog'
        $Caught.CategoryInfo.Category | Should -Be 'InvalidArgument'
        $Caught.Exception.Message | Should -BeLike '*the read did not show its catalog*'
    }

    It 'publishes AccessPackageNotFound as today for a GUID that does not exist, with a catalog' {
        $Caught = InModuleScope $script:moduleName -Parameters @{ Ap = $script:ApGuid; Cat = $script:CatGuid } {
            param($Ap, $Cat)
            Mock Resolve-OERCatalogId { $Cat }
            Mock Invoke-OERGraphRequest {
                $Marker = [PSCustomObject]@{ ExpectedErrorCode = 'AccessPackageNotFound'; StatusCode = 404; Message = 'x'; Uri = 'y' }
                $Marker.PSObject.TypeNames.Insert(0, 'Omnicit.EntraRBAC.GraphExpectedError')
                $Marker
            }
            $Result = $null
            try { Resolve-OERAccessPackageId -DisplayName $Ap -Catalog 'CAT-One' } catch { $Result = $PSItem }
            $Result
        }
        $Caught.FullyQualifiedErrorId | Should -BeExactly 'AccessPackageNotFound'
        $Caught.CategoryInfo.Category | Should -Be 'ObjectNotFound'
        $Caught.Exception.Message | Should -BeLike "The access package id '$($script:ApGuid)' does not resolve to an access package in this tenant.*"
    }

    It 're-throws an ambiguous catalog name as AmbiguousCatalogName and sends no package request' {
        $Caught = InModuleScope $script:moduleName {
            Mock Resolve-OERCatalogId {
                throw [System.Management.Automation.ErrorRecord]::new(
                    [System.Exception]::new("Catalog display name 'CAT-Dup' matches 2 catalogs (c-1, c-2)."),
                    'AmbiguousName',
                    [System.Management.Automation.ErrorCategory]::InvalidArgument,
                    'CAT-Dup')
            }
            Mock Invoke-OERGraphRequest {}
            $Result = $null
            try { Resolve-OERAccessPackageId -DisplayName 'AP-Sales' -Catalog 'CAT-Dup' } catch { $Result = $PSItem }
            Should -Invoke Invoke-OERGraphRequest -Times 0 -Exactly
            $Result
        }
        $Caught.FullyQualifiedErrorId | Should -BeExactly 'AmbiguousCatalogName'
        $Caught.CategoryInfo.Category | Should -Be 'InvalidArgument'
        $Caught.TargetObject | Should -Be 'CAT-Dup'
        $Caught.Exception.Message | Should -Be "Catalog display name 'CAT-Dup' matches 2 catalogs (c-1, c-2)."
    }

    It 'refuses a catalog that matches nothing with CatalogNotFound and sends no package request' {
        $Caught = InModuleScope $script:moduleName {
            Mock Resolve-OERCatalogId { $null }
            Mock Invoke-OERGraphRequest {}
            $Result = $null
            try { Resolve-OERAccessPackageId -DisplayName 'AP-Sales' -Catalog 'CAT-Gone' } catch { $Result = $PSItem }
            Should -Invoke Invoke-OERGraphRequest -Times 0 -Exactly
            $Result
        }
        $Caught.FullyQualifiedErrorId | Should -BeExactly 'CatalogNotFound'
        $Caught.CategoryInfo.Category | Should -Be 'ObjectNotFound'
        $Caught.TargetObject | Should -Be 'CAT-Gone'
        $Caught.Exception.Message | Should -BeExactly "Catalog 'CAT-Gone' not found."
    }

    It 'publishes a failed catalog lookup as itself and sends no package request' {
        $Caught = InModuleScope $script:moduleName {
            Mock Resolve-OERCatalogId {
                throw [System.Management.Automation.ErrorRecord]::new(
                    [System.Exception]::new('Authorization_RequestDenied: Insufficient privileges.'),
                    'Authorization_RequestDenied',
                    [System.Management.Automation.ErrorCategory]::PermissionDenied,
                    $null)
            }
            Mock Invoke-OERGraphRequest {}
            $Result = $null
            try { Resolve-OERAccessPackageId -DisplayName 'AP-Sales' -Catalog 'CAT-One' } catch { $Result = $PSItem }
            Should -Invoke Invoke-OERGraphRequest -Times 0 -Exactly
            $Result
        }
        $Caught.FullyQualifiedErrorId | Should -Match '^Authorization_RequestDenied'
        $Caught.FullyQualifiedErrorId | Should -Not -Match 'CatalogNotFound|AmbiguousCatalogName'
    }

    It 'without -Catalog never resolves a catalog and sends the byte-identical name and GUID requests' {
        InModuleScope $script:moduleName -Parameters @{ Ap = $script:ApGuid } {
            param($Ap)
            Mock Resolve-OERCatalogId { 'cat-x' }
            Mock Invoke-OERGraphRequest { @{ value = @(); id = $Ap } }
            Resolve-OERAccessPackageId -DisplayName 'AP-Sales' | Out-Null
            Resolve-OERAccessPackageId -DisplayName $Ap | Out-Null
            Should -Invoke Resolve-OERCatalogId -Times 0 -Exactly
            Should -Invoke Invoke-OERGraphRequest -Times 1 -Exactly -ParameterFilter {
                $Uri -ceq "v1.0/identityGovernance/entitlementManagement/accessPackages?`$filter=displayName eq 'AP-Sales'&`$select=id,displayName"
            }
            Should -Invoke Invoke-OERGraphRequest -Times 1 -Exactly -ParameterFilter {
                $Uri -ceq "v1.0/identityGovernance/entitlementManagement/accessPackages/00000000-0000-0000-0000-000000000067?`$select=id"
            }
        }
    }

    It 'returns -Id verbatim with no request whatever -Catalog holds' {
        InModuleScope $script:moduleName {
            Mock Resolve-OERCatalogId { 'cat-1' }
            Mock Invoke-OERGraphRequest {}
            Resolve-OERAccessPackageId -Id 'ap-1' -Catalog 'CAT-One' | Should -Be 'ap-1'
            Should -Invoke Invoke-OERGraphRequest -Times 0 -Exactly
            Should -Invoke Resolve-OERCatalogId -Times 0 -Exactly
        }
    }
}
