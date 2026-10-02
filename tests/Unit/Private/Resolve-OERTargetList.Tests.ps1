BeforeAll {
    $script:moduleName = 'Omnicit.EntraRBAC'
    Get-Module $script:moduleName | Remove-Module -Force -ErrorAction SilentlyContinue
    Import-Module $script:moduleName -Force -ErrorAction Stop
}

Describe 'Resolve-OERTargetList' {
    BeforeEach {
        InModuleScope $script:moduleName { $script:_OERAuthState = $null }
        Mock -ModuleName $script:moduleName Initialize-OERAuth {}
        Mock -ModuleName $script:moduleName Resolve-OERUserId { 'uid-resolved' }
        Mock -ModuleName $script:moduleName Resolve-OERGroupId { 'gid-resolved' }
    }

    It 'does not authenticate when every value is a GUID' {
        InModuleScope $script:moduleName {
            $R = Resolve-OERTargetList -User '11111111-1111-1111-1111-111111111111' -Group '22222222-2222-2222-2222-222222222222'
            $R.Approvers.Count | Should -Be 2
            $R.FailedValue | Should -BeNullOrEmpty
        }
        Should -Invoke -ModuleName $script:moduleName Initialize-OERAuth -Times 0
    }

    It 'authenticates once when at least one value is a name' {
        InModuleScope $script:moduleName {
            $null = Resolve-OERTargetList -User 'anna.berg@contoso.com'
        }
        Should -Invoke -ModuleName $script:moduleName Initialize-OERAuth -Times 1
    }

    It 'resolves a user name to a singleUser approver object' {
        InModuleScope $script:moduleName {
            $R = Resolve-OERTargetList -User 'anna.berg@contoso.com'
            $R.Approvers[0]['@odata.type'] | Should -Be '#microsoft.graph.singleUser'
            $R.Approvers[0].userId | Should -Be 'uid-resolved'
        }
    }

    It 'resolves a group name to a groupMembers approver object' {
        InModuleScope $script:moduleName {
            $R = Resolve-OERTargetList -Group 'Sales Team'
            $R.Approvers[0]['@odata.type'] | Should -Be '#microsoft.graph.groupMembers'
            $R.Approvers[0].groupId | Should -Be 'gid-resolved'
        }
    }

    It 'reports a failed user when Resolve-OERUserId returns null' {
        Mock -ModuleName $script:moduleName Resolve-OERUserId { $null }
        InModuleScope $script:moduleName {
            $R = Resolve-OERTargetList -User 'nobody@contoso.com'
            $R.FailedKind | Should -Be 'User'
            $R.FailedValue | Should -Be 'nobody@contoso.com'
            @($R.Approvers).Count | Should -Be 0
        }
    }

    It 'reports a failed group when Resolve-OERGroupId returns null' {
        Mock -ModuleName $script:moduleName Resolve-OERGroupId { $null }
        InModuleScope $script:moduleName {
            $R = Resolve-OERTargetList -Group 'no-such-group'
            $R.FailedKind | Should -Be 'Group'
            $R.FailedValue | Should -Be 'no-such-group'
        }
    }

    It 'passes a GUID user value straight through Resolve-OERUserId as the UPN argument' {
        InModuleScope $script:moduleName {
            $null = Resolve-OERTargetList -User '44444444-4444-4444-4444-444444444444'
        }
        Should -Invoke -ModuleName $script:moduleName Resolve-OERUserId -Times 1 -ParameterFilter {
            $UserPrincipalName -eq '44444444-4444-4444-4444-444444444444'
        }
    }

    It 'returns empty Approvers and no failure when called with no arguments and does not authenticate' {
        InModuleScope $script:moduleName {
            $R = Resolve-OERTargetList
            @($R.Approvers).Count | Should -Be 0
            $R.FailedValue | Should -BeNullOrEmpty
        }
        Should -Invoke -ModuleName $script:moduleName Initialize-OERAuth -Times 0
    }
}

Describe 'Resolve-OERTargetList ambiguity handling' {
    BeforeEach {
        InModuleScope $script:moduleName { $script:_OERAuthState = $null }
        Mock -ModuleName $script:moduleName Initialize-OERAuth {}
        Mock -ModuleName $script:moduleName Remove-OERErrorRecord {}
    }

    It 'reports an ambiguous group display name through FailedErrorId/FailedMessage, never by throwing' {
        # The ambiguity must NOT escape as a throw: no caller wraps this helper, so a throw would
        # terminate the calling public cmdlet and defeat -ErrorAction SilentlyContinue. It travels
        # through the same optional descriptor companions Resolve-OERAccessReviewScopeTarget uses.
        Mock -ModuleName $script:moduleName Resolve-OERGroupId {
            throw [System.Management.Automation.ErrorRecord]::new(
                [System.Exception]::new("Group display name 'Dup' matches 2 groups (aaa-1, bbb-2)."),
                'AmbiguousName', [System.Management.Automation.ErrorCategory]::InvalidArgument, 'Dup')
        }
        $Result = InModuleScope $script:moduleName {
            $Caught = $null
            $R = $null
            try { $R = Resolve-OERTargetList -Group 'Dup' } catch { $Caught = $PSItem }
            @{ Caught = $Caught; Descriptor = $R }
        }
        $Result.Caught                   | Should -Be $null
        $Result.Descriptor.FailedKind    | Should -Be 'Group'
        $Result.Descriptor.FailedValue   | Should -Be 'Dup'
        $Result.Descriptor.FailedErrorId | Should -Be 'AmbiguousGroupName'
        $Result.Descriptor.FailedMessage | Should -Match 'aaa-1'
        $Result.Descriptor.FailedMessage | Should -Match 'bbb-2'
        Should -Invoke -ModuleName $script:moduleName Remove-OERErrorRecord -Times 1
    }

    It 'still reports a genuine no-match through FailedKind/FailedValue with no ErrorId override' {
        Mock -ModuleName $script:moduleName Resolve-OERGroupId { $null }
        InModuleScope $script:moduleName {
            $R = Resolve-OERTargetList -Group 'missing'
            $R.FailedKind    | Should -Be 'Group'
            $R.FailedValue   | Should -Be 'missing'
            $R.FailedErrorId | Should -Be $null
            $R.FailedMessage | Should -Be $null
        }
    }
}

Describe 'Resolve-OERTargetList -- a failed lookup is not a not-found' {
    BeforeEach {
        InModuleScope $script:moduleName { $script:_OERAuthState = $null }
        Mock -ModuleName $script:moduleName Initialize-OERAuth {}
        Mock -ModuleName $script:moduleName Remove-OERErrorRecord {}
    }

    # A 403, an exhausted 429 or a 5xx out of a user or group lookup says nothing about whether the
    # object exists. The descriptor carries the caught record in FailedRecord, so the calling cmdlet can
    # re-publish it as itself; FailedErrorId stays $null on that path, since a caller reads the mere
    # PRESENCE of FailedErrorId as "bad argument" and would label a refused read InvalidArgument.

    It 'carries a 403 out of Resolve-OERUserId in FailedRecord and leaves the not-found companions null' {
        Mock -ModuleName $script:moduleName Resolve-OERUserId {
            throw [System.Management.Automation.ErrorRecord]::new(
                [System.Exception]::new('Authorization_RequestDenied: Insufficient privileges to complete the operation.'),
                'Authorization_RequestDenied', [System.Management.Automation.ErrorCategory]::PermissionDenied, 'denied@contoso.com')
        }
        InModuleScope $script:moduleName {
            $R = Resolve-OERTargetList -User 'denied@contoso.com'
            $R.FailedRecord                       | Should -Not -BeNullOrEmpty
            $R.FailedRecord.FullyQualifiedErrorId | Should -Match '^Authorization_RequestDenied'
            $R.FailedRecord.CategoryInfo.Category | Should -Be 'PermissionDenied'
            $R.FailedKind                         | Should -Be 'User'
            $R.FailedValue                        | Should -Be 'denied@contoso.com'
            $R.FailedErrorId                      | Should -BeNullOrEmpty
            $R.FailedMessage                      | Should -BeNullOrEmpty
            @($R.Approvers).Count                 | Should -Be 0
        }
    }

    It 'carries a 403 out of Resolve-OERGroupId in FailedRecord and leaves the ambiguity companions null' {
        Mock -ModuleName $script:moduleName Resolve-OERGroupId {
            throw [System.Management.Automation.ErrorRecord]::new(
                [System.Exception]::new('Authorization_RequestDenied: Insufficient privileges to complete the operation.'),
                'Authorization_RequestDenied', [System.Management.Automation.ErrorCategory]::PermissionDenied, 'Denied Group')
        }
        InModuleScope $script:moduleName {
            $R = Resolve-OERTargetList -Group 'Denied Group'
            $R.FailedRecord                       | Should -Not -BeNullOrEmpty
            $R.FailedRecord.FullyQualifiedErrorId | Should -Match '^Authorization_RequestDenied'
            $R.FailedKind                         | Should -Be 'Group'
            $R.FailedValue                        | Should -Be 'Denied Group'
            $R.FailedErrorId                      | Should -BeNullOrEmpty
            $R.FailedMessage                      | Should -BeNullOrEmpty
            @($R.Approvers).Count                 | Should -Be 0
        }
    }

    It 'leaves FailedRecord null for a $null user or group lookup, and the not-found shape is unchanged' {
        Mock -ModuleName $script:moduleName Resolve-OERUserId { $null }
        Mock -ModuleName $script:moduleName Resolve-OERGroupId { $null }
        InModuleScope $script:moduleName {
            $U = Resolve-OERTargetList -User 'nobody@contoso.com'
            $U.FailedKind    | Should -Be 'User'
            $U.FailedValue   | Should -Be 'nobody@contoso.com'
            $U.FailedErrorId | Should -BeNullOrEmpty
            $U.FailedRecord  | Should -BeNullOrEmpty
            $U.ContainsKey('FailedRecord') | Should -BeTrue
            $G = Resolve-OERTargetList -Group 'no-such-group'
            $G.FailedKind    | Should -Be 'Group'
            $G.FailedValue   | Should -Be 'no-such-group'
            $G.FailedErrorId | Should -BeNullOrEmpty
            $G.FailedRecord  | Should -BeNullOrEmpty
            $G.ContainsKey('FailedRecord') | Should -BeTrue
        }
    }

    It 'leaves FailedRecord null for an ambiguous group name' {
        Mock -ModuleName $script:moduleName Resolve-OERGroupId {
            throw [System.Management.Automation.ErrorRecord]::new(
                [System.Exception]::new("Group display name 'Dup' matches 2 groups (aaa-1, bbb-2)."),
                'AmbiguousName', [System.Management.Automation.ErrorCategory]::InvalidArgument, 'Dup')
        }
        InModuleScope $script:moduleName {
            $R = Resolve-OERTargetList -Group 'Dup'
            $R.FailedErrorId | Should -Be 'AmbiguousGroupName'
            $R.FailedRecord  | Should -BeNullOrEmpty
        }
    }

    It 'carries a FailedRecord key, null, on a successful descriptor' {
        InModuleScope $script:moduleName {
            $R = Resolve-OERTargetList
            $R.ContainsKey('FailedRecord') | Should -BeTrue
            $R.FailedRecord                | Should -BeNullOrEmpty
            $R.FailedValue                 | Should -BeNullOrEmpty
        }
    }

    It 'scrubs the failed Resolve-OERUserId record before carrying it out (bearer hygiene)' {
        # The catch hands the record on instead of discarding it, so an $Error-count proof stays green with
        # the scrub deleted. Guard the call itself (rationale.md, #bearer-scrub-tests); the FailedRecord
        # assertion beside it is the positive proof that this catch was reached.
        Mock -ModuleName $script:moduleName Resolve-OERUserId {
            throw [System.Management.Automation.ErrorRecord]::new(
                [System.Exception]::new('Authorization_RequestDenied: user lookup scrub marker.'),
                'Authorization_RequestDenied', [System.Management.Automation.ErrorCategory]::PermissionDenied, 'denied@contoso.com')
        }
        InModuleScope $script:moduleName {
            $R = Resolve-OERTargetList -User 'denied@contoso.com'
            $R.FailedRecord.Exception.Message | Should -Be 'Authorization_RequestDenied: user lookup scrub marker.'
        }
        Should -Invoke -ModuleName $script:moduleName Remove-OERErrorRecord -Times 1 -Exactly -ParameterFilter {
            $Record.Exception.Message -eq 'Authorization_RequestDenied: user lookup scrub marker.'
        }
    }

    It 'scrubs the failed Resolve-OERGroupId record before carrying it out (bearer hygiene)' {
        Mock -ModuleName $script:moduleName Resolve-OERGroupId {
            throw [System.Management.Automation.ErrorRecord]::new(
                [System.Exception]::new('Authorization_RequestDenied: group lookup scrub marker.'),
                'Authorization_RequestDenied', [System.Management.Automation.ErrorCategory]::PermissionDenied, 'Denied Group')
        }
        InModuleScope $script:moduleName {
            $R = Resolve-OERTargetList -Group 'Denied Group'
            $R.FailedRecord.Exception.Message | Should -Be 'Authorization_RequestDenied: group lookup scrub marker.'
        }
        Should -Invoke -ModuleName $script:moduleName Remove-OERErrorRecord -Times 1 -Exactly -ParameterFilter {
            $Record.Exception.Message -eq 'Authorization_RequestDenied: group lookup scrub marker.'
        }
    }
}
