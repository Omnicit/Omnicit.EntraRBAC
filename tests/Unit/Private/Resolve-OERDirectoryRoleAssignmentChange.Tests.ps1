BeforeAll {
    Import-Module Omnicit.EntraRBAC -Force
    . "$PSScriptRoot/../TestHelpers/OERTransportTripwire.ps1"
    Install-OERTransportTripwire
}

AfterAll {
    try { Assert-OERTransportTripwire } finally { Uninstall-OERTransportTripwire }
}

Describe 'Resolve-OERDirectoryRoleAssignmentChange' {
    It 'reports Absent with a time-bound Detail when there is no current assignment and durationDays is declared' {
        InModuleScope Omnicit.EntraRBAC {
            $Declared = '{ "durationDays": 30 }' | ConvertFrom-Json
            $Change = Resolve-OERDirectoryRoleAssignmentChange -Declared $Declared -Current $null
            $Change.Changed | Should -BeTrue
            $Change.Reason | Should -Be 'Absent'
            $Change.DurationDays | Should -Be 30
            $Change.Permanent | Should -BeFalse
            $Change.Detail | Should -Match '30 days'
        }
    }

    It 'reports Absent as permanent when the declared entry names no window key at all' {
        InModuleScope Omnicit.EntraRBAC {
            $Declared = '{ }' | ConvertFrom-Json
            $Change = Resolve-OERDirectoryRoleAssignmentChange -Declared $Declared -Current $null
            $Change.Changed | Should -BeTrue
            $Change.Reason | Should -Be 'Absent'
            $Change.Permanent | Should -BeTrue
            $Change.DurationDays | Should -BeNullOrEmpty
            $Change.Detail | Should -Match 'permanent'
        }
    }

    It 'reports Absent as permanent for a declared permanent entry that carries no durationDays' {
        InModuleScope Omnicit.EntraRBAC {
            $Declared = '{ "permanent": true }' | ConvertFrom-Json
            $Change = Resolve-OERDirectoryRoleAssignmentChange -Declared $Declared -Current $null
            $Change.Permanent | Should -BeTrue
            $Change.DurationDays | Should -BeNullOrEmpty
        }
    }

    It 'reports no change when the declared duration matches the live 30-day window' {
        InModuleScope Omnicit.EntraRBAC {
            $Declared = '{ "durationDays": 30 }' | ConvertFrom-Json
            $Current = [PSCustomObject]@{ StartDateTime = '2026-09-01T00:00:00Z'; EndDateTime = '2026-10-01T00:00:00Z' }
            $Change = Resolve-OERDirectoryRoleAssignmentChange -Declared $Declared -Current $Current
            $Change.Changed | Should -BeFalse
            $Change.Reason | Should -Be 'None'
            $Change.Detail | Should -Be 'assignment matches'
        }
    }

    It 'reports DurationChanged when the declared duration differs from the live window' {
        InModuleScope Omnicit.EntraRBAC {
            $Declared = '{ "durationDays": 60 }' | ConvertFrom-Json
            $Current = [PSCustomObject]@{ StartDateTime = '2026-09-01T00:00:00Z'; EndDateTime = '2026-10-01T00:00:00Z' }
            $Change = Resolve-OERDirectoryRoleAssignmentChange -Declared $Declared -Current $Current
            $Change.Changed | Should -BeTrue
            $Change.Reason | Should -Be 'DurationChanged'
            $Change.Detail | Should -BeLike '*30*60*'
        }
    }

    It 'reports PermanenceChanged when a permanent entry meets a time-bound assignment' {
        InModuleScope Omnicit.EntraRBAC {
            $Declared = '{ }' | ConvertFrom-Json
            $Current = [PSCustomObject]@{ StartDateTime = '2026-09-01T00:00:00Z'; EndDateTime = '2026-10-01T00:00:00Z' }
            $Change = Resolve-OERDirectoryRoleAssignmentChange -Declared $Declared -Current $Current
            $Change.Changed | Should -BeTrue
            $Change.Reason | Should -Be 'PermanenceChanged'
        }
    }

    It 'reports PermanenceChanged when a time-bound entry meets a permanent assignment' {
        InModuleScope Omnicit.EntraRBAC {
            $Declared = '{ "durationDays": 30 }' | ConvertFrom-Json
            $Current = [PSCustomObject]@{ StartDateTime = '2026-09-01T00:00:00Z'; EndDateTime = $null }
            $Change = Resolve-OERDirectoryRoleAssignmentChange -Declared $Declared -Current $Current
            $Change.Changed | Should -BeTrue
            $Change.Reason | Should -Be 'PermanenceChanged'
        }
    }

    It 'reports no change when both declared and current are permanent' {
        InModuleScope Omnicit.EntraRBAC {
            $Declared = '{ }' | ConvertFrom-Json
            $Current = [PSCustomObject]@{ StartDateTime = '2026-09-01T00:00:00Z'; EndDateTime = $null }
            (Resolve-OERDirectoryRoleAssignmentChange -Declared $Declared -Current $Current).Changed | Should -BeFalse
        }
    }

    It 'tags the output object' {
        InModuleScope Omnicit.EntraRBAC {
            $Declared = '{ }' | ConvertFrom-Json
            (Resolve-OERDirectoryRoleAssignmentChange -Declared $Declared).PSObject.TypeNames |
                Should -Contain 'Omnicit.EntraRBAC.DirectoryRoleAssignmentChange'
        }
    }

    Context 'durationDays read through Test-OERDeclaredProperty (declared-value rule)' {
        <#
            An explicit JSON null for durationDays must mean exactly what an omitted key means: the
            entry is permanent. A bare "PSObject.Properties.Name -icontains 'durationDays'" chain would
            instead see the key as present and coerce [int]$null to 0, reporting a bogus zero-day
            time-bound entry -- the exact defect class Test-OERDeclaredProperty exists to close
            (CLAUDE.md ## Code Style; docs/development/rationale.md#declared-property).
        #>
        It 'treats a null durationDays as permanent rather than a zero-day window' {
            InModuleScope Omnicit.EntraRBAC {
                $Declared = '{ "durationDays": null }' | ConvertFrom-Json
                $Change = Resolve-OERDirectoryRoleAssignmentChange -Declared $Declared -Current $null
                $Change.Permanent | Should -BeTrue
                $Change.DurationDays | Should -BeNullOrEmpty
                $Change.Detail | Should -Match 'permanent'
                $Change.Detail | Should -Not -Match '0 days'
            }
        }

        It 'falls back to permanent when durationDays is omitted, the same outcome as an explicit null' {
            InModuleScope Omnicit.EntraRBAC {
                $Declared = '{ }' | ConvertFrom-Json
                $NullDeclared = '{ "durationDays": null }' | ConvertFrom-Json
                $ChangeOmitted = Resolve-OERDirectoryRoleAssignmentChange -Declared $Declared -Current $null
                $ChangeNull = Resolve-OERDirectoryRoleAssignmentChange -Declared $NullDeclared -Current $null
                $ChangeOmitted.Permanent | Should -Be $ChangeNull.Permanent
                $ChangeOmitted.DurationDays | Should -Be $ChangeNull.DurationDays
            }
        }
    }

    It 'accepts a null -Declared node and reads every property as undeclared' {
        InModuleScope Omnicit.EntraRBAC {
            $Change = Resolve-OERDirectoryRoleAssignmentChange -Declared $null -Current $null
            $Change.Permanent | Should -BeTrue
            $Change.DurationDays | Should -BeNullOrEmpty
            $Change.Detail | Should -Match 'permanent'
        }
    }
}
