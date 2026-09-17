BeforeAll { Import-Module Omnicit.EntraRBAC -Force }

Describe 'New-OERScheduleInfo' {
    It 'builds an AfterDuration expiration from -Duration' {
        InModuleScope Omnicit.EntraRBAC {
            $R = New-OERScheduleInfo -Duration 'PT8H'
            $R.expiration.type     | Should -Be 'AfterDuration'
            $R.expiration.duration | Should -Be 'PT8H'
            $R.expiration.Keys     | Should -Not -Contain 'endDateTime'
            $R.startDateTime | Should -Match '^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}'
        }
    }
    It 'rejects a degenerate PT duration with no time units' {
        InModuleScope Omnicit.EntraRBAC {
            { New-OERScheduleInfo -Duration 'PT' } | Should -Throw
        }
    }
    It 'builds an AfterDateTime expiration from -EndDateTime' {
        InModuleScope Omnicit.EntraRBAC {
            $End = [datetime]::new(2030, 1, 1, 0, 0, 0, [DateTimeKind]::Utc)
            $R = New-OERScheduleInfo -EndDateTime $End
            $R.expiration.type        | Should -Be 'AfterDateTime'
            $R.expiration.endDateTime | Should -Match '2030-01-01'
        }
    }
    It 'builds a NoExpiration expiration from -Permanent' {
        InModuleScope Omnicit.EntraRBAC {
            $R = New-OERScheduleInfo -Permanent
            $R.expiration.type | Should -Be 'NoExpiration'
            $R.expiration.Keys | Should -HaveCount 1
        }
    }
    It 'defaults to NoExpiration when nothing is supplied' {
        InModuleScope Omnicit.EntraRBAC {
            (New-OERScheduleInfo).expiration.type | Should -Be 'NoExpiration'
        }
    }
    It 'throws when -Duration and -Permanent are both supplied' {
        InModuleScope Omnicit.EntraRBAC {
            { New-OERScheduleInfo -Duration 'PT8H' -Permanent } |
                Should -Throw '*-Duration*-Permanent*'
        }
    }
    It 'throws when -Duration and -EndDateTime are both supplied' {
        InModuleScope Omnicit.EntraRBAC {
            { New-OERScheduleInfo -Duration 'PT8H' -EndDateTime ([datetime]::UtcNow.AddHours(1)) } |
                Should -Throw '*-Duration*-EndDateTime*'
        }
    }
    It 'throws when -EndDateTime and -Permanent are both supplied' {
        InModuleScope Omnicit.EntraRBAC {
            { New-OERScheduleInfo -EndDateTime ([datetime]::UtcNow.AddHours(1)) -Permanent } |
                Should -Throw '*-EndDateTime*-Permanent*'
        }
    }
}
