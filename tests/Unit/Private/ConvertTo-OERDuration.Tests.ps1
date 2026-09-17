BeforeAll {
    $script:moduleName = 'Omnicit.EntraRBAC'
    Get-Module $script:moduleName | Remove-Module -Force -ErrorAction SilentlyContinue
    Import-Module $script:moduleName -Force -ErrorAction Stop
}

Describe 'ConvertTo-OERDuration' {
    It 'converts a day count to an ISO 8601 day duration' {
        InModuleScope $script:moduleName {
            ConvertTo-OERDuration -Days 365 | Should -Be 'P365D'
            ConvertTo-OERDuration -Days 180 | Should -Be 'P180D'
            ConvertTo-OERDuration -Days 1   | Should -Be 'P1D'
        }
    }

    It 'rejects a non-positive day count' {
        InModuleScope $script:moduleName {
            { ConvertTo-OERDuration -Days 0 } | Should -Throw
        }
    }

    It 'converts an hour count to an ISO 8601 hour duration' {
        InModuleScope $script:moduleName {
            ConvertTo-OERDuration -Hours 8 | Should -Be 'PT8H'
            ConvertTo-OERDuration -Hours 1 | Should -Be 'PT1H'
        }
    }

    It 'rejects a non-positive hour count' {
        InModuleScope $script:moduleName {
            { ConvertTo-OERDuration -Hours 0 } | Should -Throw
        }
    }
}
