BeforeAll {
    Import-Module Omnicit.EntraRBAC -Force
    . "$PSScriptRoot/../TestHelpers/OERTransportTripwire.ps1"
    Install-OERTransportTripwire
}

AfterAll {
    try { Assert-OERTransportTripwire } finally { Uninstall-OERTransportTripwire }
}
Describe 'Resolve-OERAccessReviewDefinitionId' {
    It 'returns a GUID verbatim with no Graph call' {
        InModuleScope Omnicit.EntraRBAC {
            Mock Invoke-OERGraphRequest { }
            Resolve-OERAccessReviewDefinitionId -DisplayName '55555555-5555-5555-5555-555555555555' | Should -Be '55555555-5555-5555-5555-555555555555'
            Should -Invoke Invoke-OERGraphRequest -Times 0
        }
    }
    It 'returns -Id verbatim with no Graph call' {
        InModuleScope Omnicit.EntraRBAC {
            Mock Invoke-OERGraphRequest { }
            Resolve-OERAccessReviewDefinitionId -Id 'def-123' | Should -Be 'def-123'
            Should -Invoke Invoke-OERGraphRequest -Times 0
        }
    }
    It 'resolves a display name via filtered query' {
        InModuleScope Omnicit.EntraRBAC {
            Mock Invoke-OERGraphRequest { @{ value = @(@{ id = 'def-id'; displayName = 'Q3 Review' }) } }
            Resolve-OERAccessReviewDefinitionId -DisplayName 'Q3 Review' | Should -Be 'def-id'
        }
    }
    It 'returns null when none matches' {
        InModuleScope Omnicit.EntraRBAC {
            Mock Invoke-OERGraphRequest { @{ value = @() } }
            Resolve-OERAccessReviewDefinitionId -DisplayName 'nope' | Should -BeNullOrEmpty
        }
    }
    It 'percent-encodes a display name containing reserved characters so the query survives transport' {
        InModuleScope Omnicit.EntraRBAC {
            Mock Invoke-OERGraphRequest { @{ value = @(@{ id = 'def-2'; displayName = 'R&D + Core' }) } }
            Resolve-OERAccessReviewDefinitionId -DisplayName 'R&D + Core' | Should -Be 'def-2'
            Should -Invoke Invoke-OERGraphRequest -Times 1 -ParameterFilter {
                $Uri -like "*displayName eq 'R%26D%20%2B%20Core'*"
            }
        }
    }

    Context 'a display name that more than one definition carries' {
        # Graph does not enforce unique access review definition display names, and the callers
        # DELETE (Remove-OERAccessReviewDefinition), PUT (Set-OERAccessReviewDefinition) or act on an
        # instance of whatever this returns. Returning the first match acted on an arbitrary one of
        # several same-named definitions, so a name that cannot identify a single definition is refused.
        It 'throws AmbiguousName naming both candidate ids when two definitions share the display name' {
            Mock -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest {
                @{ value = @(
                        @{ id = '11111111-1111-1111-1111-111111111111'; displayName = 'Dup' },
                        @{ id = '22222222-2222-2222-2222-222222222222'; displayName = 'Dup' }) }
            }
            $Caught = InModuleScope Omnicit.EntraRBAC {
                $Result = $null
                try { Resolve-OERAccessReviewDefinitionId -DisplayName 'Dup' } catch { $Result = $PSItem }
                $Result
            }
            $Caught | Should -Not -BeNullOrEmpty
            $Caught.FullyQualifiedErrorId | Should -Be 'AmbiguousName'
            $Caught.CategoryInfo.Category | Should -Be 'InvalidArgument'
            $Caught.TargetObject | Should -Be 'Dup'
            $Caught.Exception.Message | Should -Be (
                "Access review definition display name 'Dup' matches 2 definitions " +
                '(11111111-1111-1111-1111-111111111111, 22222222-2222-2222-2222-222222222222). ' +
                'Access reviews do not enforce unique definition display names, so this name cannot ' +
                'identify a single definition. Re-run with the definition id instead of the display name.')
        }

        It 'counts every candidate when three definitions share the display name' {
            Mock -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest {
                @{ value = @(
                        @{ id = 'aaaaaaaa-1111-1111-1111-111111111111'; displayName = 'Dup' },
                        @{ id = 'bbbbbbbb-2222-2222-2222-222222222222'; displayName = 'Dup' },
                        @{ id = 'cccccccc-3333-3333-3333-333333333333'; displayName = 'Dup' }) }
            }
            $Caught = InModuleScope Omnicit.EntraRBAC {
                $Result = $null
                try { Resolve-OERAccessReviewDefinitionId -DisplayName 'Dup' } catch { $Result = $PSItem }
                $Result
            }
            $Caught.FullyQualifiedErrorId | Should -Be 'AmbiguousName'
            $Caught.Exception.Message | Should -Match "matches 3 definitions \(aaaaaaaa-1111-1111-1111-111111111111, bbbbbbbb-2222-2222-2222-222222222222, cccccccc-3333-3333-3333-333333333333\)\."
        }

        It 'reads every page of the filtered listing, so candidates beyond the first page still make the name ambiguous' {
            # The wrapper returns ONE aggregated @{ value = <all pages> } under -All and only page 1
            # without it. Two same-named definitions split across two pages are therefore visible to
            # the refusal only when the read is made with -All.
            Mock -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest {
                param($Uri, [switch]$All)
                if ($All -and $Uri -like '*accessReviews/definitions*') {
                    @{ value = @(
                            @{ id = '11111111-1111-1111-1111-111111111111'; displayName = 'Dup' },
                            @{ id = '22222222-2222-2222-2222-222222222222'; displayName = 'Dup' }) }
                } else {
                    @{ value = @(@{ id = '11111111-1111-1111-1111-111111111111'; displayName = 'Dup' }) }
                }
            }
            $Caught = InModuleScope Omnicit.EntraRBAC {
                $Result = $null
                try { Resolve-OERAccessReviewDefinitionId -DisplayName 'Dup' } catch { $Result = $PSItem }
                $Result
            }
            # Positive proof first: the filtered read was made, and with -All.
            Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest -Times 1 -Exactly -ParameterFilter {
                $Uri -like '*definitions?$filter=displayName eq*' -and $All
            }
            $Caught | Should -Not -BeNullOrEmpty
            $Caught.FullyQualifiedErrorId | Should -Be 'AmbiguousName'
            $Caught.Exception.Message | Should -Match '22222222-2222-2222-2222-222222222222'
        }

        It 'returns the single match unchanged when exactly one definition has the name' {
            Mock -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest {
                @{ value = @(@{ id = '33333333-3333-3333-3333-333333333333'; displayName = 'Solo' }) }
            }
            InModuleScope Omnicit.EntraRBAC {
                Resolve-OERAccessReviewDefinitionId -DisplayName 'Solo' | Should -Be '33333333-3333-3333-3333-333333333333'
            }
        }

        It 'returns $null, not an empty string, on a genuine no-match' {
            Mock -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest { @{ value = @() } }
            InModuleScope Omnicit.EntraRBAC {
                $Result = Resolve-OERAccessReviewDefinitionId -DisplayName 'No-Such-Name'
                $null -eq $Result | Should -BeTrue
            }
        }

        It 'returns $null when the response carries no value collection at all' {
            Mock -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest { @{ } }
            InModuleScope Omnicit.EntraRBAC {
                $Result = Resolve-OERAccessReviewDefinitionId -DisplayName 'No-Such-Name'
                $null -eq $Result | Should -BeTrue
            }
        }

        It 'ignores a null entry in the value collection when counting candidates' {
            # One real definition beside a null entry is ONE match, not two: the null is dropped before
            # the count, exactly as Resolve-OERCatalogId drops it.
            Mock -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest {
                @{ value = @($null, @{ id = '44444444-4444-4444-4444-444444444444'; displayName = 'Solo' }) }
            }
            InModuleScope Omnicit.EntraRBAC {
                Resolve-OERAccessReviewDefinitionId -DisplayName 'Solo' | Should -Be '44444444-4444-4444-4444-444444444444'
            }
        }

        It 'returns $null when the value collection holds only null entries' {
            Mock -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest { @{ value = @($null, $null) } }
            InModuleScope Omnicit.EntraRBAC {
                $Result = Resolve-OERAccessReviewDefinitionId -DisplayName 'No-Such-Name'
                $null -eq $Result | Should -BeTrue
            }
        }
    }
}
