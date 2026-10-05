BeforeAll {
    Import-Module Omnicit.EntraRBAC -Force
    . "$PSScriptRoot/../TestHelpers/OERTransportTripwire.ps1"
    Install-OERTransportTripwire
}

AfterAll {
    try { Assert-OERTransportTripwire } finally { Uninstall-OERTransportTripwire }
}

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

Describe 'Resolve-OERReviewerScope -- a failed lookup is not a not-found' {
    BeforeEach { InModuleScope Omnicit.EntraRBAC { $script:_OERAuthState = $null } }

    # A 403, an exhausted 429 or a 5xx out of a user or group lookup says nothing about whether the
    # object exists. The descriptor carries the caught record in FailedRecord, so the calling cmdlet can
    # re-publish it as itself; FailedErrorId stays $null on that path, since a caller reads the mere
    # PRESENCE of FailedErrorId as "bad argument" and would label a refused read InvalidArgument.

    It 'carries a 403 out of Resolve-OERUserId in FailedRecord and leaves the not-found companions null' {
        InModuleScope Omnicit.EntraRBAC {
            Mock Initialize-OERAuth { }
            Mock Remove-OERErrorRecord { }
            Mock Resolve-OERUserId {
                throw [System.Management.Automation.ErrorRecord]::new(
                    [System.Exception]::new('Authorization_RequestDenied: Insufficient privileges to complete the operation.'),
                    'Authorization_RequestDenied', [System.Management.Automation.ErrorCategory]::PermissionDenied, 'denied@contoso.com')
            }
            $R = Resolve-OERReviewerScope -Reviewer 'denied@contoso.com'
            $R.FailedRecord                       | Should -Not -BeNullOrEmpty
            $R.FailedRecord.FullyQualifiedErrorId | Should -Match '^Authorization_RequestDenied'
            $R.FailedRecord.CategoryInfo.Category | Should -Be 'PermissionDenied'
            $R.FailedKind                         | Should -Be 'User'
            $R.FailedValue                        | Should -Be 'denied@contoso.com'
            $R.FailedErrorId                      | Should -BeNullOrEmpty
            $R.FailedMessage                      | Should -BeNullOrEmpty
            @($R.Reviewers).Count                 | Should -Be 0
        }
    }

    It 'carries a 403 out of Resolve-OERUserId for a FALLBACK reviewer the same way' {
        InModuleScope Omnicit.EntraRBAC {
            Mock Initialize-OERAuth { }
            Mock Remove-OERErrorRecord { }
            Mock Resolve-OERUserId {
                throw [System.Management.Automation.ErrorRecord]::new(
                    [System.Exception]::new('Authorization_RequestDenied: Insufficient privileges to complete the operation.'),
                    'Authorization_RequestDenied', [System.Management.Automation.ErrorCategory]::PermissionDenied, 'denied@contoso.com')
            }
            $R = Resolve-OERReviewerScope -SelfReview -FallbackReviewer 'denied@contoso.com'
            $R.FailedRecord.FullyQualifiedErrorId | Should -Match '^Authorization_RequestDenied'
            $R.FailedKind                         | Should -Be 'User'
            $R.FailedValue                        | Should -Be 'denied@contoso.com'
        }
    }

    It 'carries a 403 out of Resolve-OERGroupId in FailedRecord and leaves the ambiguity companions null' {
        InModuleScope Omnicit.EntraRBAC {
            Mock Initialize-OERAuth { }
            Mock Remove-OERErrorRecord { }
            Mock Resolve-OERGroupId {
                throw [System.Management.Automation.ErrorRecord]::new(
                    [System.Exception]::new('Authorization_RequestDenied: Insufficient privileges to complete the operation.'),
                    'Authorization_RequestDenied', [System.Management.Automation.ErrorCategory]::PermissionDenied, 'Denied Group')
            }
            $R = Resolve-OERReviewerScope -ReviewerGroup 'Denied Group'
            $R.FailedRecord                       | Should -Not -BeNullOrEmpty
            $R.FailedRecord.FullyQualifiedErrorId | Should -Match '^Authorization_RequestDenied'
            $R.FailedKind                         | Should -Be 'Group'
            $R.FailedValue                        | Should -Be 'Denied Group'
            $R.FailedErrorId                      | Should -BeNullOrEmpty
            $R.FailedMessage                      | Should -BeNullOrEmpty
            @($R.Reviewers).Count                 | Should -Be 0
        }
    }

    It 'carries a 403 out of Resolve-OERGroupId for a FALLBACK reviewer group the same way' {
        InModuleScope Omnicit.EntraRBAC {
            Mock Initialize-OERAuth { }
            Mock Remove-OERErrorRecord { }
            Mock Resolve-OERGroupId {
                throw [System.Management.Automation.ErrorRecord]::new(
                    [System.Exception]::new('Authorization_RequestDenied: Insufficient privileges to complete the operation.'),
                    'Authorization_RequestDenied', [System.Management.Automation.ErrorCategory]::PermissionDenied, 'Denied Group')
            }
            $R = Resolve-OERReviewerScope -Manager -FallbackReviewerGroup 'Denied Group'
            $R.FailedRecord.FullyQualifiedErrorId | Should -Match '^Authorization_RequestDenied'
            $R.FailedKind                         | Should -Be 'Group'
        }
    }

    It 'leaves FailedRecord null for a $null user lookup, and the not-found shape is unchanged' {
        InModuleScope Omnicit.EntraRBAC {
            Mock Initialize-OERAuth { }
            Mock Resolve-OERUserId { $null }
            $R = Resolve-OERReviewerScope -Reviewer 'ghost@contoso.com'
            $R.FailedKind    | Should -Be 'User'
            $R.FailedValue   | Should -Be 'ghost@contoso.com'
            $R.FailedErrorId | Should -BeNullOrEmpty
            $R.FailedRecord  | Should -BeNullOrEmpty
            $R.ContainsKey('FailedRecord') | Should -BeTrue
        }
    }

    It 'leaves FailedRecord null for a $null group lookup and for an ambiguous group name' {
        InModuleScope Omnicit.EntraRBAC {
            Mock Initialize-OERAuth { }
            Mock Remove-OERErrorRecord { }
            Mock Resolve-OERGroupId { $null }
            $R = Resolve-OERReviewerScope -ReviewerGroup 'missing'
            $R.FailedKind   | Should -Be 'Group'
            $R.FailedRecord | Should -BeNullOrEmpty
            Mock Resolve-OERGroupId {
                throw [System.Management.Automation.ErrorRecord]::new(
                    [System.Exception]::new("Group display name 'Dup' matches 2 groups (aaa-1, bbb-2)."),
                    'AmbiguousName', [System.Management.Automation.ErrorCategory]::InvalidArgument, 'Dup')
            }
            $R = Resolve-OERReviewerScope -ReviewerGroup 'Dup'
            $R.FailedErrorId | Should -Be 'AmbiguousGroupName'
            $R.FailedRecord  | Should -BeNullOrEmpty
        }
    }

    It 'carries a FailedRecord key, null, on a successful descriptor' {
        InModuleScope Omnicit.EntraRBAC {
            $R = Resolve-OERReviewerScope -SelfReview
            $R.ContainsKey('FailedRecord') | Should -BeTrue
            $R.FailedRecord                | Should -BeNullOrEmpty
            $R.FailedValue                 | Should -BeNullOrEmpty
        }
    }

    It 'scrubs the failed Resolve-OERUserId record before carrying it out (bearer hygiene)' {
        # The catch hands the record on instead of discarding it, so an $Error-count proof stays green with
        # the scrub deleted. Guard the call itself (rationale.md, #bearer-scrub-tests); the FailedRecord
        # assertion beside it is the positive proof that this catch was reached.
        InModuleScope Omnicit.EntraRBAC {
            Mock Initialize-OERAuth { }
            Mock Remove-OERErrorRecord { }
            Mock Resolve-OERUserId {
                throw [System.Management.Automation.ErrorRecord]::new(
                    [System.Exception]::new('Authorization_RequestDenied: user lookup scrub marker.'),
                    'Authorization_RequestDenied', [System.Management.Automation.ErrorCategory]::PermissionDenied, 'denied@contoso.com')
            }
            $R = Resolve-OERReviewerScope -Reviewer 'denied@contoso.com'
            $R.FailedRecord.Exception.Message | Should -Be 'Authorization_RequestDenied: user lookup scrub marker.'
            Should -Invoke Remove-OERErrorRecord -Times 1 -Exactly -ParameterFilter {
                $Record.Exception.Message -eq 'Authorization_RequestDenied: user lookup scrub marker.'
            }
        }
    }

    It 'scrubs the failed Resolve-OERGroupId record before carrying it out (bearer hygiene)' {
        InModuleScope Omnicit.EntraRBAC {
            Mock Initialize-OERAuth { }
            Mock Remove-OERErrorRecord { }
            Mock Resolve-OERGroupId {
                throw [System.Management.Automation.ErrorRecord]::new(
                    [System.Exception]::new('Authorization_RequestDenied: group lookup scrub marker.'),
                    'Authorization_RequestDenied', [System.Management.Automation.ErrorCategory]::PermissionDenied, 'Denied Group')
            }
            $R = Resolve-OERReviewerScope -ReviewerGroup 'Denied Group'
            $R.FailedRecord.Exception.Message | Should -Be 'Authorization_RequestDenied: group lookup scrub marker.'
            Should -Invoke Remove-OERErrorRecord -Times 1 -Exactly -ParameterFilter {
                $Record.Exception.Message -eq 'Authorization_RequestDenied: group lookup scrub marker.'
            }
        }
    }
}
