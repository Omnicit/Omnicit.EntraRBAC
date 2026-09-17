BeforeAll { Import-Module Omnicit.EntraRBAC -Force }

Describe 'Resolve-OERAssignmentPolicyChange' {
    BeforeEach {
        $script:base = [PSCustomObject]@{
            Description       = 'D'
            RequestorScope    = [PSCustomObject]@{ scope = 'AllMemberUsers'; users = @(); groups = @() }
            RequestorSettings = [PSCustomObject]@{ allowSelfRequest = $true; allowManagerRequest = $false; managerLevel = 1; allowCustomSchedule = $false; allowSelfExtend = $false; allowSelfRemove = $false; allowOnBehalfUpdate = $false; allowOnBehalfRemove = $false }
            RequireApproval   = $true; RequireRequestorJustification = $false; RequireApprovalForUpdate = $false
            ApprovalStages    = @([PSCustomObject]@{ durationDays = 7; manager = $true; managerLevel = 1; users = @(); groups = @(); internalSponsor = $false; externalSponsor = $false; alternateUsers = @(); alternateGroups = @(); fallbackUsers = @(); fallbackGroups = @(); escalationDays = $null; requireApproverJustification = $false; approverInfoVisibility = 'Default' })
            DurationInDays    = 30; DurationInHours = $null; ExpirationDateTime = $null; NotificationsDisabled = $false
        }
        # Declared in BeforeEach (not the Describe body) so it survives the Pester v5 discovery/run
        # phase boundary -- a bare Describe-scope variable is $null inside the It at run time.
        $script:allFields = @('description', 'requestorScope', 'requestorSettings', 'requireApproval', 'requireRequestorJustification', 'requireApprovalForUpdate', 'approvalStages', 'expiration', 'notificationsDisabled')
    }

    It 'identical projections, all declared -> no diff' {
        InModuleScope Omnicit.EntraRBAC -Parameters @{ b = $script:base; f = $script:allFields } { param($b, $f)
            (Resolve-OERAssignmentPolicyChange -Desired $b -Current $b -DeclaredFields $f).Differs | Should -BeFalse }
    }

    It 'undeclared changed field is ignored' {
        InModuleScope Omnicit.EntraRBAC -Parameters @{ b = $script:base } { param($b)
            $cur = $b.PSObject.Copy(); $cur.NotificationsDisabled = $true
            (Resolve-OERAssignmentPolicyChange -Desired $b -Current $cur -DeclaredFields @('description')).Differs | Should -BeFalse }
    }

    It 'declared changed scalar -> diff + ChangedFields' {
        InModuleScope Omnicit.EntraRBAC -Parameters @{ b = $script:base } { param($b)
            $cur = $b.PSObject.Copy(); $cur.NotificationsDisabled = $true
            $r = Resolve-OERAssignmentPolicyChange -Desired $b -Current $cur -DeclaredFields @('notificationsDisabled')
            $r.Differs | Should -BeTrue; $r.ChangedFields | Should -Contain 'notificationsDisabled' }
    }

    It 'requestorScope user set is order/case-insensitive' {
        InModuleScope Omnicit.EntraRBAC -Parameters @{ b = $script:base } { param($b)
            $d = $b.PSObject.Copy(); $d.RequestorScope = [PSCustomObject]@{ scope = 'SpecificDirectoryUsers'; users = @('AAA', 'bbb'); groups = @() }
            $c = $b.PSObject.Copy(); $c.RequestorScope = [PSCustomObject]@{ scope = 'SpecificDirectoryUsers'; users = @('bbb', 'aaa'); groups = @() }
            (Resolve-OERAssignmentPolicyChange -Desired $d -Current $c -DeclaredFields @('requestorScope')).Differs | Should -BeFalse }
    }

    It 'expiration compared as a unit (days vs hours differ)' {
        InModuleScope Omnicit.EntraRBAC -Parameters @{ b = $script:base } { param($b)
            $c = $b.PSObject.Copy(); $c.DurationInDays = $null; $c.DurationInHours = 8
            (Resolve-OERAssignmentPolicyChange -Desired $b -Current $c -DeclaredFields @('expiration')).Differs | Should -BeTrue }
    }

    It 'stage count difference -> diff' {
        InModuleScope Omnicit.EntraRBAC -Parameters @{ b = $script:base } { param($b)
            $c = $b.PSObject.Copy(); $c.ApprovalStages = @()
            (Resolve-OERAssignmentPolicyChange -Desired $b -Current $c -DeclaredFields @('approvalStages')).Differs | Should -BeTrue }
    }

    It 'per-stage approver set difference -> diff' {
        InModuleScope Omnicit.EntraRBAC -Parameters @{ b = $script:base } { param($b)
            $c = $b.PSObject.Copy()
            $c.ApprovalStages = @([PSCustomObject]@{ durationDays = 7; manager = $true; managerLevel = 1; users = @('zzz'); groups = @(); internalSponsor = $false; externalSponsor = $false; alternateUsers = @(); alternateGroups = @(); escalationDays = $null; requireApproverJustification = $false; approverInfoVisibility = 'Default' })
            (Resolve-OERAssignmentPolicyChange -Desired $b -Current $c -DeclaredFields @('approvalStages')).Differs | Should -BeTrue }
    }

    # -- Additional behavior coverage (beyond the brief's minimum set) --------------------

    It 'description change is detected when declared' {
        InModuleScope Omnicit.EntraRBAC -Parameters @{ b = $script:base } { param($b)
            $c = $b.PSObject.Copy(); $c.Description = 'Different'
            $r = Resolve-OERAssignmentPolicyChange -Desired $b -Current $c -DeclaredFields @('description')
            $r.Differs | Should -BeTrue; $r.ChangedFields | Should -Contain 'description' }
    }

    It 'requestorScope scope string difference is case-insensitive' {
        InModuleScope Omnicit.EntraRBAC -Parameters @{ b = $script:base } { param($b)
            $d = $b.PSObject.Copy(); $d.RequestorScope = [PSCustomObject]@{ scope = 'allmemberusers'; users = @(); groups = @() }
            (Resolve-OERAssignmentPolicyChange -Desired $d -Current $b -DeclaredFields @('requestorScope')).Differs | Should -BeFalse }
    }

    It 'requestorScope scope string difference is detected' {
        InModuleScope Omnicit.EntraRBAC -Parameters @{ b = $script:base } { param($b)
            $d = $b.PSObject.Copy(); $d.RequestorScope = [PSCustomObject]@{ scope = 'AllDirectoryUsers'; users = @(); groups = @() }
            (Resolve-OERAssignmentPolicyChange -Desired $d -Current $b -DeclaredFields @('requestorScope')).Differs | Should -BeTrue }
    }

    It 'requestorScope group set difference is detected' {
        InModuleScope Omnicit.EntraRBAC -Parameters @{ b = $script:base } { param($b)
            $d = $b.PSObject.Copy(); $d.RequestorScope = [PSCustomObject]@{ scope = 'SpecificDirectoryUsers'; users = @(); groups = @('g1') }
            $c = $b.PSObject.Copy(); $c.RequestorScope = [PSCustomObject]@{ scope = 'SpecificDirectoryUsers'; users = @(); groups = @('g2') }
            (Resolve-OERAssignmentPolicyChange -Desired $d -Current $c -DeclaredFields @('requestorScope')).Differs | Should -BeTrue }
    }

    It 'null RequestorScope on both sides is treated as no diff' {
        InModuleScope Omnicit.EntraRBAC -Parameters @{ b = $script:base } { param($b)
            $d = $b.PSObject.Copy(); $d.RequestorScope = $null
            $c = $b.PSObject.Copy(); $c.RequestorScope = $null
            (Resolve-OERAssignmentPolicyChange -Desired $d -Current $c -DeclaredFields @('requestorScope')).Differs | Should -BeFalse }
    }

    It 'null vs present RequestorScope is a diff' {
        InModuleScope Omnicit.EntraRBAC -Parameters @{ b = $script:base } { param($b)
            $d = $b.PSObject.Copy(); $d.RequestorScope = $null
            (Resolve-OERAssignmentPolicyChange -Desired $d -Current $b -DeclaredFields @('requestorScope')).Differs | Should -BeTrue }
    }

    It 'requestorSettings bool difference is detected' {
        InModuleScope Omnicit.EntraRBAC -Parameters @{ b = $script:base } { param($b)
            $c = $b.PSObject.Copy(); $c.RequestorSettings = [PSCustomObject]@{ allowSelfRequest = $false; allowManagerRequest = $false; managerLevel = 1; allowCustomSchedule = $false; allowSelfExtend = $false }
            (Resolve-OERAssignmentPolicyChange -Desired $b -Current $c -DeclaredFields @('requestorSettings')).Differs | Should -BeTrue }
    }

    It 'requestorSettings managerLevel int difference is detected' {
        InModuleScope Omnicit.EntraRBAC -Parameters @{ b = $script:base } { param($b)
            $c = $b.PSObject.Copy(); $c.RequestorSettings = [PSCustomObject]@{ allowSelfRequest = $true; allowManagerRequest = $false; managerLevel = 2; allowCustomSchedule = $false; allowSelfExtend = $false }
            (Resolve-OERAssignmentPolicyChange -Desired $b -Current $c -DeclaredFields @('requestorSettings')).Differs | Should -BeTrue }
    }

    It 'requestorSettings identical -> no diff' {
        InModuleScope Omnicit.EntraRBAC -Parameters @{ b = $script:base } { param($b)
            $c = $b.PSObject.Copy()
            (Resolve-OERAssignmentPolicyChange -Desired $b -Current $c -DeclaredFields @('requestorSettings')).Differs | Should -BeFalse }
    }

    It 'requestorSettings allowSelfRemove difference is detected' {
        InModuleScope Omnicit.EntraRBAC -Parameters @{ b = $script:base } { param($b)
            $c = $b.PSObject.Copy(); $c.RequestorSettings = [PSCustomObject]@{ allowSelfRequest = $true; allowManagerRequest = $false; managerLevel = 1; allowCustomSchedule = $false; allowSelfExtend = $false; allowSelfRemove = $true; allowOnBehalfUpdate = $false; allowOnBehalfRemove = $false }
            (Resolve-OERAssignmentPolicyChange -Desired $b -Current $c -DeclaredFields @('requestorSettings')).Differs | Should -BeTrue }
    }

    It 'requestorSettings allowOnBehalfUpdate difference is detected' {
        InModuleScope Omnicit.EntraRBAC -Parameters @{ b = $script:base } { param($b)
            $c = $b.PSObject.Copy(); $c.RequestorSettings = [PSCustomObject]@{ allowSelfRequest = $true; allowManagerRequest = $false; managerLevel = 1; allowCustomSchedule = $false; allowSelfExtend = $false; allowSelfRemove = $false; allowOnBehalfUpdate = $true; allowOnBehalfRemove = $false }
            (Resolve-OERAssignmentPolicyChange -Desired $b -Current $c -DeclaredFields @('requestorSettings')).Differs | Should -BeTrue }
    }

    It 'requestorSettings allowOnBehalfRemove difference is detected' {
        InModuleScope Omnicit.EntraRBAC -Parameters @{ b = $script:base } { param($b)
            $c = $b.PSObject.Copy(); $c.RequestorSettings = [PSCustomObject]@{ allowSelfRequest = $true; allowManagerRequest = $false; managerLevel = 1; allowCustomSchedule = $false; allowSelfExtend = $false; allowSelfRemove = $false; allowOnBehalfUpdate = $false; allowOnBehalfRemove = $true }
            (Resolve-OERAssignmentPolicyChange -Desired $b -Current $c -DeclaredFields @('requestorSettings')).Differs | Should -BeTrue }
    }

    It 'requireApproval bool difference is detected' {
        InModuleScope Omnicit.EntraRBAC -Parameters @{ b = $script:base } { param($b)
            $c = $b.PSObject.Copy(); $c.RequireApproval = $false
            $r = Resolve-OERAssignmentPolicyChange -Desired $b -Current $c -DeclaredFields @('requireApproval')
            $r.Differs | Should -BeTrue; $r.ChangedFields | Should -Contain 'requireApproval' }
    }

    It 'expiration date-time difference is detected' {
        InModuleScope Omnicit.EntraRBAC -Parameters @{ b = $script:base } { param($b)
            $d = $b.PSObject.Copy(); $d.DurationInDays = $null; $d.ExpirationDateTime = '2026-01-01T00:00:00Z'
            $c = $b.PSObject.Copy(); $c.DurationInDays = $null; $c.ExpirationDateTime = '2027-01-01T00:00:00Z'
            (Resolve-OERAssignmentPolicyChange -Desired $d -Current $c -DeclaredFields @('expiration')).Differs | Should -BeTrue }
    }

    It 'expiration same instant different serializations -> no diff' {
        InModuleScope Omnicit.EntraRBAC -Parameters @{ b = $script:base } { param($b)
            $d = $b.PSObject.Copy(); $d.DurationInDays = $null; $d.ExpirationDateTime = '2026-12-31T00:00:00Z'
            $c = $b.PSObject.Copy(); $c.DurationInDays = $null; $c.ExpirationDateTime = '2026-12-31T00:00:00.0000000+00:00'
            (Resolve-OERAssignmentPolicyChange -Desired $d -Current $c -DeclaredFields @('expiration')).Differs | Should -BeFalse }
    }

    It 'expiration genuinely different dates -> diff' {
        InModuleScope Omnicit.EntraRBAC -Parameters @{ b = $script:base } { param($b)
            $d = $b.PSObject.Copy(); $d.DurationInDays = $null; $d.ExpirationDateTime = '2026-12-31T00:00:00Z'
            $c = $b.PSObject.Copy(); $c.DurationInDays = $null; $c.ExpirationDateTime = '2027-12-31T00:00:00.0000000+00:00'
            (Resolve-OERAssignmentPolicyChange -Desired $d -Current $c -DeclaredFields @('expiration')).Differs | Should -BeTrue }
    }

    It 'expiration none vs days is a diff' {
        InModuleScope Omnicit.EntraRBAC -Parameters @{ b = $script:base } { param($b)
            $c = $b.PSObject.Copy(); $c.DurationInDays = $null
            (Resolve-OERAssignmentPolicyChange -Desired $b -Current $c -DeclaredFields @('expiration')).Differs | Should -BeTrue }
    }

    It 'expiration identical days -> no diff' {
        InModuleScope Omnicit.EntraRBAC -Parameters @{ b = $script:base } { param($b)
            $c = $b.PSObject.Copy()
            (Resolve-OERAssignmentPolicyChange -Desired $b -Current $c -DeclaredFields @('expiration')).Differs | Should -BeFalse }
    }

    It 'per-stage scalar difference is detected' {
        InModuleScope Omnicit.EntraRBAC -Parameters @{ b = $script:base } { param($b)
            $c = $b.PSObject.Copy()
            $c.ApprovalStages = @([PSCustomObject]@{ durationDays = 14; manager = $true; managerLevel = 1; users = @(); groups = @(); internalSponsor = $false; externalSponsor = $false; alternateUsers = @(); alternateGroups = @(); escalationDays = $null; requireApproverJustification = $false; approverInfoVisibility = 'Default' })
            (Resolve-OERAssignmentPolicyChange -Desired $b -Current $c -DeclaredFields @('approvalStages')).Differs | Should -BeTrue }
    }

    It 'per-stage alternate (escalation) set difference is detected' {
        InModuleScope Omnicit.EntraRBAC -Parameters @{ b = $script:base } { param($b)
            $c = $b.PSObject.Copy()
            $c.ApprovalStages = @([PSCustomObject]@{ durationDays = 7; manager = $true; managerLevel = 1; users = @(); groups = @(); internalSponsor = $false; externalSponsor = $false; alternateUsers = @('alt1'); alternateGroups = @(); fallbackUsers = @(); fallbackGroups = @(); escalationDays = $null; requireApproverJustification = $false; approverInfoVisibility = 'Default' })
            (Resolve-OERAssignmentPolicyChange -Desired $b -Current $c -DeclaredFields @('approvalStages')).Differs | Should -BeTrue }
    }

    It 'per-stage fallback set difference is detected -- fallbackUsers only' {
        InModuleScope Omnicit.EntraRBAC -Parameters @{ b = $script:base } { param($b)
            $c = $b.PSObject.Copy()
            $c.ApprovalStages = @([PSCustomObject]@{ durationDays = 7; manager = $true; managerLevel = 1; users = @(); groups = @(); internalSponsor = $false; externalSponsor = $false; alternateUsers = @(); alternateGroups = @(); fallbackUsers = @('fb1'); fallbackGroups = @(); escalationDays = $null; requireApproverJustification = $false; approverInfoVisibility = 'Default' })
            (Resolve-OERAssignmentPolicyChange -Desired $b -Current $c -DeclaredFields @('approvalStages')).Differs | Should -BeTrue }
    }

    It 'per-stage fallback set difference is detected -- fallbackGroups only' {
        InModuleScope Omnicit.EntraRBAC -Parameters @{ b = $script:base } { param($b)
            $c = $b.PSObject.Copy()
            $c.ApprovalStages = @([PSCustomObject]@{ durationDays = 7; manager = $true; managerLevel = 1; users = @(); groups = @(); internalSponsor = $false; externalSponsor = $false; alternateUsers = @(); alternateGroups = @(); fallbackUsers = @(); fallbackGroups = @('fbg1'); escalationDays = $null; requireApproverJustification = $false; approverInfoVisibility = 'Default' })
            (Resolve-OERAssignmentPolicyChange -Desired $b -Current $c -DeclaredFields @('approvalStages')).Differs | Should -BeTrue }
    }

    It 'a policy whose only difference is its stage fallbacks reports Differs -- not Unchanged' {
        InModuleScope Omnicit.EntraRBAC -Parameters @{ b = $script:base } { param($b)
            $Desired = $b.PSObject.Copy()
            $Current = $b.PSObject.Copy()
            $Current.ApprovalStages = @([PSCustomObject]@{ durationDays = 7; manager = $true; managerLevel = 1; users = @(); groups = @(); internalSponsor = $false; externalSponsor = $false; alternateUsers = @(); alternateGroups = @(); fallbackUsers = @('fb-live'); fallbackGroups = @(); escalationDays = $null; requireApproverJustification = $false; approverInfoVisibility = 'Default' })
            $Result = Resolve-OERAssignmentPolicyChange -Desired $Desired -Current $Current -DeclaredFields @('approvalStages')
            $Result.Differs | Should -BeTrue
            $Result.ChangedFields | Should -Contain 'approvalStages'
        }
    }

    It 'per-stage identical -> no diff' {
        InModuleScope Omnicit.EntraRBAC -Parameters @{ b = $script:base } { param($b)
            $c = $b.PSObject.Copy()
            (Resolve-OERAssignmentPolicyChange -Desired $b -Current $c -DeclaredFields @('approvalStages')).Differs | Should -BeFalse }
    }

    It 'multiple declared fields all changed are all reported' {
        InModuleScope Omnicit.EntraRBAC -Parameters @{ b = $script:base } { param($b)
            $c = $b.PSObject.Copy(); $c.Description = 'X'; $c.NotificationsDisabled = $true
            $r = Resolve-OERAssignmentPolicyChange -Desired $b -Current $c -DeclaredFields @('description', 'notificationsDisabled', 'requireApproval')
            $r.Differs | Should -BeTrue
            $r.ChangedFields | Should -Contain 'description'
            $r.ChangedFields | Should -Contain 'notificationsDisabled'
            $r.ChangedFields | Should -Not -Contain 'requireApproval' }
    }

    It 'empty DeclaredFields -> no diff even when everything differs' {
        InModuleScope Omnicit.EntraRBAC -Parameters @{ b = $script:base } { param($b)
            $c = $b.PSObject.Copy(); $c.Description = 'X'; $c.NotificationsDisabled = $true; $c.RequireApproval = $false
            $r = Resolve-OERAssignmentPolicyChange -Desired $b -Current $c -DeclaredFields @()
            $r.Differs | Should -Be $false; @($r.ChangedFields).Count | Should -Be 0 }
    }

    It 'ChangedFields is always an array' {
        InModuleScope Omnicit.EntraRBAC -Parameters @{ b = $script:base } { param($b)
            $r = Resolve-OERAssignmentPolicyChange -Desired $b -Current $b -DeclaredFields @('description')
            , $r.ChangedFields | Should -BeOfType [System.Array] }
    }
}
