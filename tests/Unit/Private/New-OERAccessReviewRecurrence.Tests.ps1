BeforeAll { Import-Module Omnicit.EntraRBAC -Force }

Describe 'New-OERAccessReviewRecurrence' {
    It 'returns null for OneTime' {
        InModuleScope Omnicit.EntraRBAC {
            New-OERAccessReviewRecurrence -Recurrence OneTime -StartDate ([datetime]'2026-07-01') | Should -BeNullOrEmpty
        }
    }
    It 'builds a weekly noEnd recurrence' {
        InModuleScope Omnicit.EntraRBAC {
            $r = New-OERAccessReviewRecurrence -Recurrence Weekly -StartDate ([datetime]'2026-07-01')
            $r.pattern.type     | Should -Be 'weekly'
            $r.pattern.interval | Should -Be 1
            $r.pattern.Keys     | Should -Not -Contain 'dayOfMonth'
            $r.range.type       | Should -Be 'noEnd'
            $r.range.startDate  | Should -Be '2026-07-01'
        }
    }
    It 'builds a quarterly recurrence with dayOfMonth from the start date' {
        InModuleScope Omnicit.EntraRBAC {
            $r = New-OERAccessReviewRecurrence -Recurrence Quarterly -StartDate ([datetime]'2026-07-05')
            $r.pattern.type       | Should -Be 'absoluteMonthly'
            $r.pattern.interval   | Should -Be 3
            $r.pattern.dayOfMonth | Should -Be 5
        }
    }
    It 'builds an endDate range' {
        InModuleScope Omnicit.EntraRBAC {
            $r = New-OERAccessReviewRecurrence -Recurrence Monthly -StartDate ([datetime]'2026-07-01') -EndDate ([datetime]'2027-07-01')
            $r.range.type    | Should -Be 'endDate'
            $r.range.endDate | Should -Be '2027-07-01'
        }
    }
    It 'builds a numbered range' {
        InModuleScope Omnicit.EntraRBAC {
            $r = New-OERAccessReviewRecurrence -Recurrence Annually -StartDate ([datetime]'2026-07-01') -Occurrences 3
            $r.range.type                | Should -Be 'numbered'
            $r.range.numberOfOccurrences | Should -Be 3
            $r.pattern.interval          | Should -Be 12
        }
    }
    It 'builds a Monthly absoluteMonthly pattern with interval 1 and dayOfMonth from the start date' {
        InModuleScope Omnicit.EntraRBAC {
            $r = New-OERAccessReviewRecurrence -Recurrence Monthly -StartDate ([datetime]'2026-07-15')
            $r.pattern.type       | Should -Be 'absoluteMonthly'
            $r.pattern.interval   | Should -Be 1
            $r.pattern.dayOfMonth | Should -Be 15
        }
    }
    It 'throws when both -EndDate and -Occurrences are supplied' {
        InModuleScope Omnicit.EntraRBAC {
            { New-OERAccessReviewRecurrence -Recurrence Monthly -StartDate ([datetime]'2026-07-01') -EndDate ([datetime]'2027-07-01') -Occurrences 3 } |
                Should -Throw '*mutually exclusive*'
        }
    }
}
