BeforeAll {
    $script:moduleName = 'Omnicit.EntraRBAC'
    Get-Module $script:moduleName | Remove-Module -Force -ErrorAction SilentlyContinue
    Import-Module $script:moduleName -Force -ErrorAction Stop
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
