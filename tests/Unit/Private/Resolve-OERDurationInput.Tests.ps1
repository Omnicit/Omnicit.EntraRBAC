BeforeAll {
    Import-Module Omnicit.EntraRBAC -Force
    . "$PSScriptRoot/../TestHelpers/OERTransportTripwire.ps1"
    Install-OERTransportTripwire
}

AfterAll {
    try { Assert-OERTransportTripwire } finally { Uninstall-OERTransportTripwire }
}

Describe 'Resolve-OERDurationInput' {
    Context 'whole-unit input (back-compat form)' {
        It 'converts a bare day count to an ISO day duration' {
            InModuleScope Omnicit.EntraRBAC { Resolve-OERDurationInput -Value '365' } | Should -Be 'P365D'
        }
        It 'converts an integer argument (coerced to string) to an ISO day duration' {
            InModuleScope Omnicit.EntraRBAC { Resolve-OERDurationInput -Value 30 } | Should -Be 'P30D'
        }
        It 'converts a bare hour count to an ISO hour duration when -Unit Hours' {
            InModuleScope Omnicit.EntraRBAC { Resolve-OERDurationInput -Value '8' -Unit Hours } | Should -Be 'PT8H'
        }
    }

    Context 'ISO 8601 input' {
        It 'passes a day duration through unchanged' {
            InModuleScope Omnicit.EntraRBAC { Resolve-OERDurationInput -Value 'P365D' } | Should -Be 'P365D'
        }
        It 'passes an hour duration through unchanged even when the unit is Days' {
            InModuleScope Omnicit.EntraRBAC { Resolve-OERDurationInput -Value 'PT8H' } | Should -Be 'PT8H'
        }
        It 'passes a lowercase ISO duration through as upper case' {
            InModuleScope Omnicit.EntraRBAC { Resolve-OERDurationInput -Value 'p365d' } | Should -Be 'P365D'
        }
        It 'does not range-check an ISO duration against -Maximum' {
            InModuleScope Omnicit.EntraRBAC { Resolve-OERDurationInput -Value 'P4000D' -Maximum 3650 } | Should -Be 'P4000D'
        }
    }

    Context 'invalid input' {
        It 'throws on a non-numeric, non-ISO value' {
            { InModuleScope Omnicit.EntraRBAC { Resolve-OERDurationInput -Value 'banana' } } |
                Should -Throw -ExpectedMessage "*is not a valid duration*"
        }
        It 'throws on zero' {
            { InModuleScope Omnicit.EntraRBAC { Resolve-OERDurationInput -Value '0' } } |
                Should -Throw -ExpectedMessage "*between 1 and 3650*"
        }
        It 'throws when the whole-unit count exceeds -Maximum' {
            { InModuleScope Omnicit.EntraRBAC { Resolve-OERDurationInput -Value '4000' -Maximum 3650 } } |
                Should -Throw -ExpectedMessage "*between 1 and 3650*"
        }
        It 'throws on an empty value' {
            { InModuleScope Omnicit.EntraRBAC { Resolve-OERDurationInput -Value '' } } |
                Should -Throw -ExpectedMessage "*duration value is required*"
        }
        It 'throws on a bare P with no components' {
            { InModuleScope Omnicit.EntraRBAC { Resolve-OERDurationInput -Value 'P' } } |
                Should -Throw -ExpectedMessage "*is not a valid duration*"
        }
    }
}

Describe 'Resolve-OERDurationInput typed error records' {
    It 'throws DurationInputInvalid as a typed record: Resolve-OERDurationInput -Value    ' {
        $Caught = InModuleScope 'Omnicit.EntraRBAC' {
            $Result = $null
            try { Resolve-OERDurationInput -Value '   ' } catch { $Result = $PSItem }
            $Result
        }
        $Caught | Should -BeOfType ([System.Management.Automation.ErrorRecord])
        $Caught.FullyQualifiedErrorId | Should -BeExactly 'DurationInputInvalid'
        $Caught.CategoryInfo.Category | Should -Be 'InvalidArgument'
        $Caught.TargetObject | Should -BeExactly '   '
        $Caught.Exception.Message | Should -BeExactly 'A duration value is required. Supply a whole number of days (e.g. 365) or an ISO 8601 duration (e.g. ''P365D'').'
    }

    It 'throws DurationInputInvalid as a typed record: Resolve-OERDurationInput -Value 5000' {
        $Caught = InModuleScope 'Omnicit.EntraRBAC' {
            $Result = $null
            try { Resolve-OERDurationInput -Value '5000' } catch { $Result = $PSItem }
            $Result
        }
        $Caught | Should -BeOfType ([System.Management.Automation.ErrorRecord])
        $Caught.FullyQualifiedErrorId | Should -BeExactly 'DurationInputInvalid'
        $Caught.CategoryInfo.Category | Should -Be 'InvalidArgument'
        $Caught.TargetObject | Should -BeExactly '5000'
        $Caught.Exception.Message | Should -BeExactly 'Duration ''5000'' is out of range: a whole number of days must be between 1 and 3650.'
    }

    It 'throws DurationInputInvalid as a typed record: Resolve-OERDurationInput -Value bogus' {
        $Caught = InModuleScope 'Omnicit.EntraRBAC' {
            $Result = $null
            try { Resolve-OERDurationInput -Value 'bogus' } catch { $Result = $PSItem }
            $Result
        }
        $Caught | Should -BeOfType ([System.Management.Automation.ErrorRecord])
        $Caught.FullyQualifiedErrorId | Should -BeExactly 'DurationInputInvalid'
        $Caught.CategoryInfo.Category | Should -Be 'InvalidArgument'
        $Caught.TargetObject | Should -BeExactly 'bogus'
        $Caught.Exception.Message | Should -BeExactly 'Duration ''bogus'' is not a valid duration. Supply a whole number of days (e.g. 365) or an ISO 8601 duration (e.g. ''P365D'' or ''PT8H'').'
    }
}
