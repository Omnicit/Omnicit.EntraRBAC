BeforeAll { Import-Module Omnicit.EntraRBAC -Force }

Describe 'ConvertFrom-OERDuration' {

    It 'parses the canonical day form' {
        InModuleScope Omnicit.EntraRBAC { ConvertFrom-OERDuration -Duration 'P365D' -Unit Days | Should -Be 365 }
    }

    It 'parses the canonical hour form' {
        InModuleScope Omnicit.EntraRBAC { ConvertFrom-OERDuration -Duration 'PT8H' -Unit Hours | Should -Be 8 }
    }

    It 'parses a year form into whole days (XmlConvert treats a year as 365 days)' {
        InModuleScope Omnicit.EntraRBAC { ConvertFrom-OERDuration -Duration 'P1Y' -Unit Days | Should -Be 365 }
    }

    It 'parses a month form into whole days (XmlConvert treats a month as 30 days)' {
        InModuleScope Omnicit.EntraRBAC { ConvertFrom-OERDuration -Duration 'P6M' -Unit Days | Should -Be 180 }
    }

    It 'parses a composite duration into whole hours' {
        InModuleScope Omnicit.EntraRBAC { ConvertFrom-OERDuration -Duration 'P1DT12H' -Unit Hours | Should -Be 36 }
    }

    It 'returns null for a fractional unit rather than truncating it' {
        InModuleScope Omnicit.EntraRBAC { ConvertFrom-OERDuration -Duration 'PT30M' -Unit Hours | Should -Be $null }
    }

    It 'returns null for a fractional composite duration in hours' {
        InModuleScope Omnicit.EntraRBAC { ConvertFrom-OERDuration -Duration 'PT1H30M' -Unit Hours | Should -Be $null }
    }

    It 'returns null for an unparseable string' {
        InModuleScope Omnicit.EntraRBAC { ConvertFrom-OERDuration -Duration 'not-a-duration' -Unit Days | Should -Be $null }
    }

    It 'returns null for an empty or null input' {
        InModuleScope Omnicit.EntraRBAC {
            ConvertFrom-OERDuration -Duration '' -Unit Days | Should -Be $null
            ConvertFrom-OERDuration -Duration $null -Unit Days | Should -Be $null
        }
    }

    It 'returns null for whitespace-only input' {
        InModuleScope Omnicit.EntraRBAC { ConvertFrom-OERDuration -Duration '   ' -Unit Days | Should -Be $null }
    }

    It 'does not remove anything from $Error (pure in-memory parse, not a Graph/ARM call)' {
        InModuleScope Omnicit.EntraRBAC {
            Mock Remove-OERErrorRecord { }
            ConvertFrom-OERDuration -Duration 'garbage' -Unit Days | Out-Null
            Should -Invoke Remove-OERErrorRecord -Times 0
        }
    }

    It 'round-trips every value ConvertTo-OERDuration can emit' {
        InModuleScope Omnicit.EntraRBAC {
            foreach ($D in 1, 30, 90, 180, 365, 3650) {
                ConvertFrom-OERDuration -Duration (ConvertTo-OERDuration -Days $D) -Unit Days | Should -Be $D
            }
            foreach ($H in 1, 8, 24) {
                ConvertFrom-OERDuration -Duration (ConvertTo-OERDuration -Hours $H) -Unit Hours | Should -Be $H
            }
        }
    }
}
