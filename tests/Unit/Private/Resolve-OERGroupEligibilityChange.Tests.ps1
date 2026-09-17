BeforeAll {
    Import-Module Omnicit.EntraRBAC -Force
}

Describe 'Resolve-OERGroupEligibilityChange' {
    It 'reports Absent when there is no current instance' {
        InModuleScope Omnicit.EntraRBAC {
            $D = [PSCustomObject]@{ principal = 'person17@example.com'; durationDays = 30 }
            $C = Resolve-OERGroupEligibilityChange -Declared $D
            $C.Changed | Should -BeTrue
            $C.Reason  | Should -Be 'Absent'
            $C.AccessType | Should -Be 'member'
            $C.DurationDays | Should -Be 30
        }
    }

    It 'defaults AccessType to member when the entry omits it' {
        InModuleScope Omnicit.EntraRBAC {
            $D = [PSCustomObject]@{ principal = 'person17@example.com' }
            (Resolve-OERGroupEligibilityChange -Declared $D).AccessType | Should -Be 'member'
        }
    }

    It 'carries a declared owner AccessType through' {
        InModuleScope Omnicit.EntraRBAC {
            $D = [PSCustomObject]@{ principal = 'person17@example.com'; accessType = 'owner' }
            (Resolve-OERGroupEligibilityChange -Declared $D).AccessType | Should -Be 'owner'
        }
    }

    It 'reports no change when the declared duration matches the live window' {
        InModuleScope Omnicit.EntraRBAC {
            $D = [PSCustomObject]@{ principal = 'person17@example.com'; durationDays = 30 }
            $Cur = @{ startDateTime = '2026-01-01T09:00:00Z'; endDateTime = '2026-01-31T09:00:00Z'; accessId = 'member' }
            $C = Resolve-OERGroupEligibilityChange -Declared $D -Current $Cur
            $C.Changed | Should -BeFalse
            $C.Reason  | Should -Be 'None'
        }
    }

    It 'reports DurationChanged when the declared duration differs from the live window' {
        InModuleScope Omnicit.EntraRBAC {
            $D = [PSCustomObject]@{ principal = 'person17@example.com'; durationDays = 90 }
            $Cur = @{ startDateTime = '2026-01-01T09:00:00Z'; endDateTime = '2026-01-31T09:00:00Z'; accessId = 'member' }
            $C = Resolve-OERGroupEligibilityChange -Declared $D -Current $Cur
            $C.Changed | Should -BeTrue
            $C.Reason  | Should -Be 'DurationChanged'
            $C.Detail  | Should -BeLike '*30*90*'
        }
    }

    It 'reports PermanenceChanged when a permanent entry meets a time-bound instance' {
        InModuleScope Omnicit.EntraRBAC {
            $D = [PSCustomObject]@{ principal = 'person17@example.com' }
            $Cur = @{ startDateTime = '2026-01-01T09:00:00Z'; endDateTime = '2026-01-31T09:00:00Z'; accessId = 'member' }
            $C = Resolve-OERGroupEligibilityChange -Declared $D -Current $Cur
            $C.Changed | Should -BeTrue
            $C.Reason  | Should -Be 'PermanenceChanged'
        }
    }

    It 'reports PermanenceChanged when a time-bound entry meets a permanent instance' {
        InModuleScope Omnicit.EntraRBAC {
            $D = [PSCustomObject]@{ principal = 'person17@example.com'; durationDays = 30 }
            $Cur = @{ startDateTime = '2026-01-01T09:00:00Z'; endDateTime = $null; accessId = 'member' }
            $C = Resolve-OERGroupEligibilityChange -Declared $D -Current $Cur
            $C.Changed | Should -BeTrue
            $C.Reason  | Should -Be 'PermanenceChanged'
        }
    }

    It 'reports no change when both declared and current are permanent' {
        InModuleScope Omnicit.EntraRBAC {
            $D = [PSCustomObject]@{ principal = 'person17@example.com' }
            $Cur = @{ startDateTime = '2026-01-01T09:00:00Z'; endDateTime = $null; accessId = 'member' }
            (Resolve-OERGroupEligibilityChange -Declared $D -Current $Cur).Changed | Should -BeFalse
        }
    }

    It 'tags the output object' {
        InModuleScope Omnicit.EntraRBAC {
            $D = [PSCustomObject]@{ principal = 'person17@example.com' }
            (Resolve-OERGroupEligibilityChange -Declared $D).PSObject.TypeNames |
                Should -Contain 'Omnicit.EntraRBAC.GroupEligibilityChange'
        }
    }

    It 'treats a null durationDays as permanent rather than a zero-day window' {
        InModuleScope 'Omnicit.EntraRBAC' {
            $Declared = '{ "principal": "person17@example.com", "durationDays": null }' | ConvertFrom-Json
            $Change = Resolve-OERGroupEligibilityChange -Declared $Declared -Current $null
            $Change.Detail | Should -Match 'permanent'
            $Change.Detail | Should -Not -Match '0 days'
        }
    }

    Context 'accessType read through Test-OERDeclaredProperty (declared-value migration)' {
        <#
            This site was migrated from an inline "$Declared.PSObject.Properties.Name -icontains
            'accessType'" chain to Test-OERDeclaredProperty, so the sweep that CLAUDE.md ## Code Style
            declares complete really is complete and the QA gate can now see the file. The migration
            had to be behaviour-PRESERVING, not behaviour-changing: the three cases below pin that,
            and the null and omitted cases must land on the SAME outcome, since a declared null means
            exactly what an omitted key means.

            The truthiness clause after the predicate is load-bearing and was deliberately kept: an
            empty accessType is declared as far as the predicate is concerned ('' is the documented
            clear-a-description value), yet it is not a usable access type, so it must still fall back
            to member. That case is pinned too.
        #>
        It 'reads a declared accessType value' {
            InModuleScope Omnicit.EntraRBAC {
                $Declared = '{ "principal": "person17@example.com", "accessType": "owner" }' | ConvertFrom-Json
                (Resolve-OERGroupEligibilityChange -Declared $Declared).AccessType |
                    Should -BeExactly 'owner' -Because 'a declared accessType is what the document asked for'
            }
        }

        It 'falls back to member when accessType is declared as an explicit null' {
            InModuleScope Omnicit.EntraRBAC {
                $Declared = '{ "principal": "person17@example.com", "accessType": null }' | ConvertFrom-Json
                (Resolve-OERGroupEligibilityChange -Declared $Declared).AccessType |
                    Should -BeExactly 'member' -Because 'an explicit null means the key was not declared, so the member default applies'
            }
        }

        It 'falls back to member when accessType is omitted, the same outcome as an explicit null' {
            InModuleScope Omnicit.EntraRBAC {
                $Declared = '{ "principal": "person17@example.com" }' | ConvertFrom-Json
                (Resolve-OERGroupEligibilityChange -Declared $Declared).AccessType |
                    Should -BeExactly 'member' -Because 'an omitted key and an explicit null must resolve identically'
            }
        }

        It 'falls back to member when accessType is declared but empty' {
            InModuleScope Omnicit.EntraRBAC {
                $Declared = '{ "principal": "person17@example.com", "accessType": "" }' | ConvertFrom-Json
                (Resolve-OERGroupEligibilityChange -Declared $Declared).AccessType |
                    Should -BeExactly 'member' -Because 'the truthiness clause kept alongside the predicate is what stops an empty string reaching the Graph body as an accessId'
            }
        }
    }

    It 'accepts a null -Declared node and reads every property as undeclared' {
        <#
            [AllowNull()] on -Declared (deferred minor from the declared-value sweep). Binding $null
            to a Mandatory [PSCustomObject] without it is a terminating binding error; with it the
            call succeeds and every read goes through Test-OERDeclaredProperty, whose own help states
            a null node is never declared. No existing caller passes null -- Sync-OERStructureGroup
            only reaches this helper for an entry it already resolved a principal from -- so this
            changes no existing behaviour, it only stops the helper being the one member of its cohort
            that crashes rather than degrades.
        #>
        InModuleScope Omnicit.EntraRBAC {
            $Change = Resolve-OERGroupEligibilityChange -Declared $null -Current $null
            $Change.AccessType | Should -BeExactly 'member'
            $Change.DurationDays | Should -BeNullOrEmpty
            $Change.Detail | Should -Match 'permanent'
        }
    }
}
