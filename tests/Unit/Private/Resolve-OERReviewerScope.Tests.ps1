BeforeAll { Import-Module Omnicit.EntraRBAC -Force }

Describe 'Resolve-OERReviewerScope' {
    BeforeEach { InModuleScope Omnicit.EntraRBAC { $script:_OERAuthState = $null } }
    It 'maps a GUID user reviewer without auth or Graph call' {
        InModuleScope Omnicit.EntraRBAC {
            Mock Initialize-OERAuth { }
            Mock Invoke-OERGraphRequest { }
            $r = Resolve-OERReviewerScope -Reviewer '11111111-1111-1111-1111-111111111111'
            $r.Reviewers[0].query     | Should -Be '/users/11111111-1111-1111-1111-111111111111'
            $r.Reviewers[0].queryType | Should -Be 'MicrosoftGraph'
            $r.FailedValue            | Should -BeNullOrEmpty
            Should -Invoke Initialize-OERAuth -Times 0
            Should -Invoke Invoke-OERGraphRequest -Times 0
        }
    }
    It 'maps a group reviewer to transitiveMembers' {
        InModuleScope Omnicit.EntraRBAC {
            Mock Initialize-OERAuth { }
            $r = Resolve-OERReviewerScope -ReviewerGroup '22222222-2222-2222-2222-222222222222'
            $r.Reviewers[0].query | Should -Be '/groups/22222222-2222-2222-2222-222222222222/transitiveMembers'
        }
    }
    It 'maps -Manager with queryRoot decisions' {
        InModuleScope Omnicit.EntraRBAC {
            $r = Resolve-OERReviewerScope -Manager
            $r.Reviewers[0].query     | Should -Be './manager'
            $r.Reviewers[0].queryRoot | Should -Be 'decisions'
        }
    }
    It 'leaves reviewers empty for self-review' {
        InModuleScope Omnicit.EntraRBAC {
            $r = Resolve-OERReviewerScope -SelfReview
            @($r.Reviewers).Count | Should -Be 0
        }
    }
    It 'resolves a name via Graph and authenticates lazily' {
        InModuleScope Omnicit.EntraRBAC {
            Mock Initialize-OERAuth { }
            Mock Resolve-OERUserId { 'resolved-id' }
            $r = Resolve-OERReviewerScope -Reviewer 'anna@contoso.com'
            $r.Reviewers[0].query | Should -Be '/users/resolved-id'
            Should -Invoke Initialize-OERAuth -Times 1
        }
    }
    It 'reports the first unresolved name' {
        InModuleScope Omnicit.EntraRBAC {
            Mock Initialize-OERAuth { }
            Mock Resolve-OERUserId { $null }
            $r = Resolve-OERReviewerScope -Reviewer 'ghost@contoso.com'
            $r.FailedKind  | Should -Be 'User'
            $r.FailedValue | Should -Be 'ghost@contoso.com'
        }
    }
    It 'maps fallback reviewers separately' {
        InModuleScope Omnicit.EntraRBAC {
            $r = Resolve-OERReviewerScope -SelfReview -FallbackReviewer '33333333-3333-3333-3333-333333333333'
            $r.FallbackReviewers[0].query | Should -Be '/users/33333333-3333-3333-3333-333333333333'
        }
    }
}

Describe 'Resolve-OERReviewerScope ambiguity handling' {
    BeforeEach { InModuleScope Omnicit.EntraRBAC { $script:_OERAuthState = $null } }

    It 'reports an ambiguous group display name through FailedErrorId/FailedMessage, never by throwing' {
        # The ambiguity must NOT escape as a throw: no caller wraps this helper, so a throw would
        # terminate the calling public cmdlet and defeat -ErrorAction SilentlyContinue. It travels
        # through the same optional descriptor companions Resolve-OERAccessReviewScopeTarget uses.
        InModuleScope Omnicit.EntraRBAC {
            Mock Initialize-OERAuth { }
            Mock Remove-OERErrorRecord { }
            Mock Resolve-OERGroupId {
                throw [System.Management.Automation.ErrorRecord]::new(
                    [System.Exception]::new("Group display name 'Dup' matches 2 groups (aaa-1, bbb-2)."),
                    'AmbiguousName', [System.Management.Automation.ErrorCategory]::InvalidArgument, 'Dup')
            }
            $Caught = $null
            $R = $null
            try { $R = Resolve-OERReviewerScope -ReviewerGroup 'Dup' } catch { $Caught = $PSItem }
            $Caught        | Should -Be $null
            $R.FailedKind    | Should -Be 'Group'
            $R.FailedValue   | Should -Be 'Dup'
            $R.FailedErrorId | Should -Be 'AmbiguousGroupName'
            $R.FailedMessage | Should -Match 'aaa-1'
            $R.FailedMessage | Should -Match 'bbb-2'
            Should -Invoke Remove-OERErrorRecord -Times 1
        }
    }

    It 'reports an ambiguous FALLBACK reviewer group through the same descriptor' {
        InModuleScope Omnicit.EntraRBAC {
            Mock Initialize-OERAuth { }
            Mock Remove-OERErrorRecord { }
            Mock Resolve-OERGroupId {
                throw [System.Management.Automation.ErrorRecord]::new(
                    [System.Exception]::new("Group display name 'Dup' matches 2 groups (aaa-1, bbb-2)."),
                    'AmbiguousName', [System.Management.Automation.ErrorCategory]::InvalidArgument, 'Dup')
            }
            $R = Resolve-OERReviewerScope -Manager -FallbackReviewerGroup 'Dup'
            $R.FailedErrorId | Should -Be 'AmbiguousGroupName'
            $R.FailedMessage | Should -Match 'aaa-1'
        }
    }

    It 'still reports a genuine no-match through FailedKind/FailedValue with no ErrorId override' {
        InModuleScope Omnicit.EntraRBAC {
            Mock Initialize-OERAuth { }
            Mock Resolve-OERGroupId { $null }
            $R = Resolve-OERReviewerScope -ReviewerGroup 'missing'
            $R.FailedKind    | Should -Be 'Group'
            $R.FailedValue   | Should -Be 'missing'
            $R.FailedErrorId | Should -Be $null
            $R.FailedMessage | Should -Be $null
        }
    }
}
