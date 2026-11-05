BeforeAll {
    Import-Module Omnicit.EntraRBAC -Force
    . "$PSScriptRoot/../TestHelpers/OERTransportTripwire.ps1"
    Install-OERTransportTripwire
}

AfterAll {
    try { Assert-OERTransportTripwire } finally { Uninstall-OERTransportTripwire }
}

Describe 'Get-OERAccessReviewDuration' {
    It 'reads a one-time review length from its range' {
        InModuleScope Omnicit.EntraRBAC {
            $Settings = @{
                recurrence             = @{ pattern = $null; range = @{ type = 'numbered'; startDate = '2026-11-12'; endDate = '2026-11-26' } }
                instanceDurationInDays = 7
            }
            Get-OERAccessReviewDuration -Settings $Settings | Should -Be 14
        }
    }

    It 'reads the older one-time shape Graph stores (noEnd range, duration 0)' {
        InModuleScope Omnicit.EntraRBAC {
            $Settings = @{
                recurrence             = @{ pattern = $null; range = @{ type = 'noEnd'; startDate = '2026-11-05'; endDate = '2026-12-05' } }
                instanceDurationInDays = 0
            }
            Get-OERAccessReviewDuration -Settings $Settings | Should -Be 30
        }
    }

    It 'reads instanceDurationInDays for a repeating review' {
        InModuleScope Omnicit.EntraRBAC {
            $Settings = @{
                recurrence             = @{
                    pattern = @{ type = 'absoluteMonthly'; interval = 1; dayOfMonth = 5 }
                    range   = @{ type = 'noEnd'; startDate = '2026-11-05'; endDate = '9999-12-31' }
                }
                instanceDurationInDays = 14
            }
            Get-OERAccessReviewDuration -Settings $Settings | Should -Be 14
        }
    }

    It 'reads instanceDurationInDays when there is no recurrence at all' {
        InModuleScope Omnicit.EntraRBAC {
            Get-OERAccessReviewDuration -Settings @{ instanceDurationInDays = 21 } | Should -Be 21
        }
    }

    It 'returns null for null settings' {
        InModuleScope Omnicit.EntraRBAC {
            Get-OERAccessReviewDuration -Settings $null | Should -BeNullOrEmpty
        }
    }

    It 'returns null for a one-time review with unparsable dates and no duration' {
        InModuleScope Omnicit.EntraRBAC {
            $Settings = @{ recurrence = @{ pattern = $null; range = @{ type = 'numbered'; startDate = 'soon'; endDate = 'later' } } }
            Get-OERAccessReviewDuration -Settings $Settings | Should -BeNullOrEmpty
        }
    }

    It 'falls back to instanceDurationInDays when a one-time range ends before it starts' {
        InModuleScope Omnicit.EntraRBAC {
            $Settings = @{
                recurrence             = @{ pattern = $null; range = @{ startDate = '2026-11-26'; endDate = '2026-11-12' } }
                instanceDurationInDays = 9
            }
            Get-OERAccessReviewDuration -Settings $Settings | Should -Be 9
        }
    }

    It 'falls back to instanceDurationInDays when a one-time range has no end date' {
        InModuleScope Omnicit.EntraRBAC {
            $Settings = @{
                recurrence             = @{ pattern = $null; range = @{ startDate = '2026-11-12' } }
                instanceDurationInDays = 9
            }
            Get-OERAccessReviewDuration -Settings $Settings | Should -Be 9
        }
    }

    It 'returns null when instanceDurationInDays is not a number' {
        InModuleScope Omnicit.EntraRBAC {
            Get-OERAccessReviewDuration -Settings @{ instanceDurationInDays = 'many' } | Should -BeNullOrEmpty
        }
    }

    It 'reads datetime start and end values' {
        InModuleScope Omnicit.EntraRBAC {
            $Settings = @{
                recurrence = @{ pattern = $null; range = @{ startDate = [datetime]'2026-11-12'; endDate = [datetime]'2026-11-19' } }
            }
            Get-OERAccessReviewDuration -Settings $Settings | Should -Be 7
        }
    }

    It 'reads a Dictionary[string,object] settings bag' {
        InModuleScope Omnicit.EntraRBAC {
            $Range = [System.Collections.Generic.Dictionary[string, object]]::new()
            $Range['startDate'] = '2026-11-12'
            $Range['endDate'] = '2026-11-26'
            $Recurrence = [System.Collections.Generic.Dictionary[string, object]]::new()
            $Recurrence['pattern'] = $null
            $Recurrence['range'] = $Range
            $Settings = [System.Collections.Generic.Dictionary[string, object]]::new()
            $Settings['recurrence'] = $Recurrence
            $Settings['instanceDurationInDays'] = 0
            Get-OERAccessReviewDuration -Settings $Settings | Should -Be 14
        }
    }

    It 'reads an [ordered] settings bag of a one-time review (no ContainsKey on OrderedDictionary)' {
        InModuleScope Omnicit.EntraRBAC {
            $Settings = [ordered]@{
                recurrence             = [ordered]@{ pattern = $null; range = [ordered]@{ startDate = '2026-11-12'; endDate = '2026-11-26' } }
                instanceDurationInDays = 0
            }
            Get-OERAccessReviewDuration -Settings $Settings | Should -Be 14
        }
    }

    It 'reads an [ordered] settings bag of a repeating review' {
        InModuleScope Omnicit.EntraRBAC {
            $Settings = [ordered]@{
                recurrence             = [ordered]@{ pattern = [ordered]@{ type = 'weekly'; interval = 1 }; range = [ordered]@{ type = 'noEnd'; startDate = '2026-11-12' } }
                instanceDurationInDays = 21
            }
            Get-OERAccessReviewDuration -Settings $Settings | Should -Be 21
        }
    }

    It 'reads a PSCustomObject settings fixture' {
        InModuleScope Omnicit.EntraRBAC {
            $Settings = [pscustomobject]@{
                recurrence             = [pscustomobject]@{ pattern = $null; range = [pscustomobject]@{ startDate = '2026-11-12'; endDate = '2026-11-26' } }
                instanceDurationInDays = 0
            }
            Get-OERAccessReviewDuration -Settings $Settings | Should -Be 14
        }
    }
}
