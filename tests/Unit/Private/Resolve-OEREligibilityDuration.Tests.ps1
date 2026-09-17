BeforeAll {
    Import-Module Omnicit.EntraRBAC -Force
}

Describe 'Resolve-OEREligibilityDuration' {
    It 'returns null when endDateTime is null (permanent eligibility)' {
        InModuleScope Omnicit.EntraRBAC {
            Resolve-OEREligibilityDuration -StartDateTime '2026-01-01T00:00:00Z' -EndDateTime $null |
                Should -BeNullOrEmpty
        }
    }

    It 'returns null when endDateTime is an empty string' {
        InModuleScope Omnicit.EntraRBAC {
            Resolve-OEREligibilityDuration -StartDateTime '2026-01-01T00:00:00Z' -EndDateTime '' |
                Should -BeNullOrEmpty
        }
    }

    It 'returns null for the year 9999 permanent sentinel' {
        InModuleScope Omnicit.EntraRBAC {
            Resolve-OEREligibilityDuration -StartDateTime '2026-01-01T00:00:00Z' -EndDateTime '9999-12-31T23:59:59.9999999Z' |
                Should -BeNullOrEmpty
        }
    }

    It 'returns the whole-day window length for a time-bound instance' {
        InModuleScope Omnicit.EntraRBAC {
            Resolve-OEREligibilityDuration -StartDateTime '2026-01-01T09:00:00Z' -EndDateTime '2026-01-31T09:00:00Z' |
                Should -Be 30
        }
    }

    It 'rounds a sub-day skew to the nearest whole day' {
        InModuleScope Omnicit.EntraRBAC {
            Resolve-OEREligibilityDuration -StartDateTime '2026-01-01T09:00:00Z' -EndDateTime '2026-01-31T08:59:41Z' |
                Should -Be 30
        }
    }

    It 'accepts DateTimeOffset input as well as strings' {
        InModuleScope Omnicit.EntraRBAC {
            $Start = [datetimeoffset]::Parse('2026-03-01T00:00:00Z')
            $End   = [datetimeoffset]::Parse('2026-03-08T00:00:00Z')
            Resolve-OEREligibilityDuration -StartDateTime $Start -EndDateTime $End | Should -Be 7
        }
    }

    It 'clamps a sub-day window up to 1 day' {
        InModuleScope Omnicit.EntraRBAC {
            Resolve-OEREligibilityDuration -StartDateTime '2026-01-01T00:00:00Z' -EndDateTime '2026-01-01T04:00:00Z' |
                Should -Be 1
        }
    }

    It 'clamps a window longer than the schema maximum down to 3650 days' {
        InModuleScope Omnicit.EntraRBAC {
            Resolve-OEREligibilityDuration -StartDateTime '2026-01-01T00:00:00Z' -EndDateTime '2050-01-01T00:00:00Z' |
                Should -Be 3650
        }
    }

    It 'falls back to now when startDateTime is missing or unparsable' {
        InModuleScope Omnicit.EntraRBAC {
            $End = [datetimeoffset]::UtcNow.AddDays(10)
            Resolve-OEREligibilityDuration -StartDateTime $null -EndDateTime $End | Should -Be 10
        }
    }

    It 'returns null when endDateTime cannot be parsed at all' {
        InModuleScope Omnicit.EntraRBAC {
            Resolve-OEREligibilityDuration -StartDateTime '2026-01-01T00:00:00Z' -EndDateTime 'not-a-date' |
                Should -BeNullOrEmpty
        }
    }
}
