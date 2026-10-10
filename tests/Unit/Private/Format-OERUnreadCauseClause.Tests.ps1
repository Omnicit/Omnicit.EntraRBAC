BeforeAll {
    Import-Module Omnicit.EntraRBAC -Force
    . "$PSScriptRoot/../TestHelpers/OERTransportTripwire.ps1"
    Install-OERTransportTripwire
}

AfterAll {
    try { Assert-OERTransportTripwire } finally { Uninstall-OERTransportTripwire }
}

Describe 'Format-OERUnreadCauseClause' {
    Context 'nothing to say' {
        It 'returns an empty string for an empty cause list' {
            InModuleScope Omnicit.EntraRBAC {
                $Clause = Format-OERUnreadCauseClause -Cause @()
                $Clause | Should -BeOfType ([string])
                $Clause | Should -BeExactly ''
            }
        }

        It 'returns an empty string when no cause is given at all' {
            InModuleScope Omnicit.EntraRBAC {
                Format-OERUnreadCauseClause | Should -BeExactly ''
            }
        }

        It 'returns an empty string when every cause is blank or the entry is null' {
            InModuleScope Omnicit.EntraRBAC {
                $Blank = @(
                    [PSCustomObject]@{ Cause = ''; Target = 'g-1' },
                    [PSCustomObject]@{ Cause = '   '; Target = '' },
                    [PSCustomObject]@{ Cause = $null; Target = $null },
                    $null
                )
                Format-OERUnreadCauseClause -Cause $Blank | Should -BeExactly ''
            }
        }
    }

    Context 'the clause' {
        It 'joins the causes in order behind a Causes lead-in and ends with a full stop' {
            InModuleScope Omnicit.EntraRBAC {
                $Cause = @(
                    [PSCustomObject]@{ Cause = 'first failure'; Target = '' },
                    [PSCustomObject]@{ Cause = 'second failure'; Target = '' }
                )
                Format-OERUnreadCauseClause -Cause $Cause | Should -BeExactly ' Causes: first failure; second failure.'
            }
        }

        It 'skips a blank cause and keeps the others' {
            InModuleScope Omnicit.EntraRBAC {
                $Cause = @(
                    [PSCustomObject]@{ Cause = 'first failure'; Target = '' },
                    [PSCustomObject]@{ Cause = ' '; Target = 'g-1' },
                    [PSCustomObject]@{ Cause = 'second failure'; Target = '' }
                )
                Format-OERUnreadCauseClause -Cause $Cause | Should -BeExactly ' Causes: first failure; second failure.'
            }
        }

        It 'changes only the lead-in when a label is given' {
            InModuleScope Omnicit.EntraRBAC {
                $Cause = @(
                    [PSCustomObject]@{ Cause = 'first failure'; Target = '' },
                    [PSCustomObject]@{ Cause = 'second failure'; Target = '' }
                )
                Format-OERUnreadCauseClause -Cause $Cause -Label 'Causes of the unread group reads' |
                    Should -BeExactly ' Causes of the unread group reads: first failure; second failure.'
            }
        }
    }

    Context 'deduplication' {
        It 'shows one cause, the first message, for causes that differ only by their target id' {
            InModuleScope Omnicit.EntraRBAC {
                $Cause = @(
                    [PSCustomObject]@{ Cause = "Could not read members for group 'g-1': Too many requests (429)."; Target = 'g-1' },
                    [PSCustomObject]@{ Cause = "Could not read members for group 'g-2': Too many requests (429)."; Target = 'g-2' },
                    [PSCustomObject]@{ Cause = "Could not read members for group 'g-3': Too many requests (429)."; Target = 'g-3' }
                )
                # The clause adds its own full stop after the message's, as it always has.
                Format-OERUnreadCauseClause -Cause $Cause |
                    Should -BeExactly " Causes: Could not read members for group 'g-1': Too many requests (429).."
            }
        }

        It 'keeps causes that differ by more than their target id' {
            InModuleScope Omnicit.EntraRBAC {
                $Cause = @(
                    [PSCustomObject]@{ Cause = "Could not read members for group 'g-1': Too many requests (429)."; Target = 'g-1' },
                    [PSCustomObject]@{ Cause = "Could not read members for group 'g-2': Insufficient privileges."; Target = 'g-2' }
                )
                Format-OERUnreadCauseClause -Cause $Cause |
                    Should -BeExactly " Causes: Could not read members for group 'g-1': Too many requests (429).; Could not read members for group 'g-2': Insufficient privileges.."
            }
        }

        It 'keys a cause with an empty target on its whole text, so ids in the text still differ' {
            InModuleScope Omnicit.EntraRBAC {
                $Cause = @(
                    [PSCustomObject]@{ Cause = "unit 'u-1' failed"; Target = '' },
                    [PSCustomObject]@{ Cause = "unit 'u-2' failed"; Target = '' },
                    [PSCustomObject]@{ Cause = "unit 'u-1' failed"; Target = $null }
                )
                Format-OERUnreadCauseClause -Cause $Cause | Should -BeExactly " Causes: unit 'u-1' failed; unit 'u-2' failed."
            }
        }

        It 'compares keys without regard to letter case, as the list always did' {
            InModuleScope Omnicit.EntraRBAC {
                $Cause = @(
                    [PSCustomObject]@{ Cause = 'Too Many Requests'; Target = '' },
                    [PSCustomObject]@{ Cause = 'too many requests'; Target = '' }
                )
                Format-OERUnreadCauseClause -Cause $Cause | Should -BeExactly ' Causes: Too Many Requests.'
            }
        }
    }

    Context 'the cap' {
        It 'shows exactly 23 of 25 distinct causes and states that two more were dropped' {
            InModuleScope Omnicit.EntraRBAC {
                $Cause = foreach ($N in 1..25) { [PSCustomObject]@{ Cause = "failure shape $N"; Target = '' } }
                $Clause = Format-OERUnreadCauseClause -Cause $Cause
                $Shown = @(($Clause -replace '^ Causes: ', '' -replace ', plus .*$', '') -split '; ')
                $Shown.Count | Should -Be 23
                $Shown[0] | Should -Be 'failure shape 1'
                $Shown[22] | Should -Be 'failure shape 23'
                $Clause | Should -Not -Match 'failure shape 24'
                $Clause | Should -BeLike '* Causes: *, plus 2 more distinct cause(s) not shown -- rerun with -Verbose for all of them.'
                $Clause.EndsWith(', plus 2 more distinct cause(s) not shown -- rerun with -Verbose for all of them.') | Should -BeTrue
            }
        }

        It 'says nothing about dropped causes when exactly 23 are distinct' {
            InModuleScope Omnicit.EntraRBAC {
                $Cause = foreach ($N in 1..23) { [PSCustomObject]@{ Cause = "failure shape $N"; Target = '' } }
                $Clause = Format-OERUnreadCauseClause -Cause $Cause
                $Clause | Should -Not -Match 'more distinct'
                @(($Clause -replace '^ Causes: ', '' -replace '\.$', '') -split '; ').Count | Should -Be 23
            }
        }

        It 'counts a dropped cause once however many times it repeats, and counts a dropped id-variant by its key' {
            InModuleScope Omnicit.EntraRBAC {
                $Cause = @(foreach ($N in 1..23) { [PSCustomObject]@{ Cause = "failure shape $N"; Target = '' } })
                $Cause += [PSCustomObject]@{ Cause = "dropped shape for 'g-1'"; Target = 'g-1' }
                $Cause += [PSCustomObject]@{ Cause = "dropped shape for 'g-2'"; Target = 'g-2' }
                $Cause += [PSCustomObject]@{ Cause = "dropped shape for 'g-1'"; Target = 'g-1' }
                $Clause = Format-OERUnreadCauseClause -Cause $Cause
                $Clause | Should -BeLike '*, plus 1 more distinct cause(s) not shown -- rerun with -Verbose for all of them.'
                $Clause | Should -Not -Match 'dropped shape'
            }
        }

        It 'deduplicates before it caps, so forty repeats of one cause neither fill the cap nor count as dropped' {
            InModuleScope Omnicit.EntraRBAC {
                $Cause = @(foreach ($N in 1..40) { [PSCustomObject]@{ Cause = "Too many requests for 'g-$N'"; Target = "g-$N" } })
                Format-OERUnreadCauseClause -Cause $Cause | Should -BeExactly " Causes: Too many requests for 'g-1'."
            }
        }
    }
}
