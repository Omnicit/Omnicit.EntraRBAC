BeforeAll {
    Import-Module Omnicit.EntraRBAC -Force
    . "$PSScriptRoot/../TestHelpers/OERTransportTripwire.ps1"
    Install-OERTransportTripwire

    # A live Approval_EndUser_Assignment rule as Microsoft Graph returns it (hashtables), with the
    # given approvers on its first stage. -Stage2 adds a second stage, which must be ignored.
    function New-TestApprovalRule {
        param([object[]]$Approvers = @(), [object[]]$Stage2 = $null, [switch]$NoStage)
        $Stages = if ($NoStage) { @() } else { @(@{ approvalStageTimeOutInDays = 1; primaryApprovers = @($Approvers) }) }
        if ($null -ne $Stage2) { $Stages = @($Stages) + @(@{ approvalStageTimeOutInDays = 1; primaryApprovers = @($Stage2) }) }
        @{ id = 'Approval_EndUser_Assignment'; setting = @{ isApprovalRequired = $true; approvalStages = $Stages } }
    }
    function New-TestUser ([string]$Id) { @{ '@odata.type' = '#microsoft.graph.singleUser'; userId = $Id; description = 'Person' } }
    function New-TestGroup ([string]$Id) { @{ '@odata.type' = '#microsoft.graph.groupMembers'; groupId = $Id; description = 'Approvers' } }

    # Runs the helper in module scope with the given named parameters.
    function Invoke-ApproverSet ([hashtable]$Splat) {
        InModuleScope Omnicit.EntraRBAC -Parameters @{ Splat = $Splat } {
            param($Splat)
            Resolve-OERGraphApproverSet @Splat
        }
    }
}

AfterAll {
    try { Assert-OERTransportTripwire } finally { Uninstall-OERTransportTripwire }
}

Describe 'Resolve-OERGraphApproverSet' {
    It 'replaces the user side with the bound users and carries the live group side' {
        $Rule = New-TestApprovalRule -Approvers @((New-TestUser 'u1'), (New-TestGroup 'g1'))
        $Set = Invoke-ApproverSet @{ LiveApprovalRule = $Rule; UserBound = $true; GroupBound = $false; ResolvedUser = @('u2') }
        @($Set.EffUser) | Should -Be @('u2')
        @($Set.EffGroup) | Should -Be @('g1')
        $Set.EffRequired | Should -BeTrue
        $Set.ApproverCount | Should -Be 2
        $Set.NoApprover | Should -BeFalse
        $Set.NoApproverReason | Should -Be ''
    }

    It 'replaces the group side with the bound groups and carries the live user side' {
        $Rule = New-TestApprovalRule -Approvers @((New-TestUser 'u1'), (New-TestGroup 'g1'))
        $Set = Invoke-ApproverSet @{ LiveApprovalRule = $Rule; UserBound = $false; GroupBound = $true; ResolvedGroup = @('g2', 'g3') }
        @($Set.EffUser) | Should -Be @('u1')
        @($Set.EffGroup) | Should -Be @('g2', 'g3')
        $Set.ApproverCount | Should -Be 3
    }

    It 'clears a side bound to an empty list and keeps the other' {
        $Rule = New-TestApprovalRule -Approvers @((New-TestUser 'u1'), (New-TestGroup 'g1'))
        $Set = Invoke-ApproverSet @{ LiveApprovalRule = $Rule; UserBound = $false; GroupBound = $true; ResolvedGroup = @() }
        @($Set.EffUser) | Should -Be @('u1')
        @($Set.EffGroup).Count | Should -Be 0
        $Set.ApproverCount | Should -Be 1
    }

    It 'carries a live approver of another kind as the very object read, and counts it' {
        $Manager = @{ '@odata.type' = '#microsoft.graph.requestorManager'; managerLevel = 1 }
        $Rule = New-TestApprovalRule -Approvers @($Manager, (New-TestUser 'u1'))
        $Set = Invoke-ApproverSet @{ LiveApprovalRule = $Rule; UserBound = $true; GroupBound = $false; ResolvedUser = @() }
        @($Set.LiveOther).Count | Should -Be 1
        [object]::ReferenceEquals(@($Set.LiveOther)[0], $Manager) | Should -BeTrue
        @($Set.EffUser).Count | Should -Be 0
        # Both user-side approvers cleared, but the manager is still sent, so approval is satisfiable.
        $Set.ApproverCount | Should -Be 1
        $Set.NoApprover | Should -BeFalse
    }

    It 'reads a beta-shaped { id } approver through the Graph approver reader' {
        $Rule = New-TestApprovalRule -Approvers @(
            @{ '@odata.type' = '#microsoft.graph.singleUser'; id = 'user-beta' }
            @{ '@odata.type' = '#microsoft.graph.groupMembers'; id = 'grp-beta' }
        )
        $Set = Invoke-ApproverSet @{ LiveApprovalRule = $Rule; UserBound = $true; GroupBound = $false; ResolvedUser = @('u2') }
        @($Set.EffGroup) | Should -Be @('grp-beta')
        @($Set.LivePrimary.Id) | Should -Be @('user-beta', 'grp-beta')
    }

    It 'reads only the first approval stage' {
        $Rule = New-TestApprovalRule -Approvers @((New-TestUser 'u1')) -Stage2 @((New-TestGroup 'g-second-stage'))
        $Set = Invoke-ApproverSet @{ LiveApprovalRule = $Rule; UserBound = $true; GroupBound = $false; ResolvedUser = @('u2') }
        @($Set.EffGroup).Count | Should -Be 0
        @($Set.LivePrimary).Count | Should -Be 1
    }

    # Flipped on purpose in Sprint 9 step 4 (BL-08): this test pinned that approvers bound beside
    # -RequireApproval $false require approval anyway. Both callers refuse that combination with
    # MutuallyExclusiveParameter before they look anything up, so the helper no longer answers it; it
    # throws, as a backstop that a caller which forgot the refusal cannot get past silently.
    It 'refuses approvers bound beside -RequireApproval $false (<Shape>)' -TestCases @(
        @{ Shape = 'groups'; Splat = @{ UserBound = $false; GroupBound = $true; ResolvedGroup = @('g2') } }
        @{ Shape = 'users'; Splat = @{ UserBound = $true; GroupBound = $false; ResolvedUser = @('u2') } }
        @{ Shape = 'both sides'; Splat = @{ UserBound = $true; GroupBound = $true; ResolvedUser = @('u2'); ResolvedGroup = @('g2') } }
        @{ Shape = 'an empty user list'; Splat = @{ UserBound = $true; GroupBound = $false; ResolvedUser = @() } }
    ) {
        $Caught = $null
        try {
            $Splat.LiveApprovalRule = New-TestApprovalRule -Approvers @()
            $Splat.RequireApprovalBound = $true
            $Splat.RequireApproval = $false
            $null = Invoke-ApproverSet $Splat
        } catch {
            $Caught = $PSItem
        }
        $Caught | Should -Not -BeNullOrEmpty
        $Caught.FullyQualifiedErrorId | Should -Be 'MutuallyExclusiveParameter'
        $Caught.CategoryInfo.Category | Should -Be 'InvalidArgument'
        $Caught.Exception | Should -BeOfType ([System.ArgumentException])
        $Caught.Exception.Message | Should -BeExactly 'Approvers were bound beside -RequireApproval $false; the caller must refuse that combination with MutuallyExclusiveParameter before any lookup.'
    }

    It 'still requires approval when approvers are bound and -RequireApproval is not bound at all' {
        $Rule = New-TestApprovalRule -Approvers @()
        $Set = Invoke-ApproverSet @{
            LiveApprovalRule = $Rule; UserBound = $false; GroupBound = $true; ResolvedGroup = @('g2')
            RequireApprovalBound = $false; RequireApproval = $false
        }
        $Set.EffRequired | Should -BeTrue
    }

    It 'requires approval when approvers are bound beside -RequireApproval $true' {
        $Rule = New-TestApprovalRule -Approvers @()
        $Set = Invoke-ApproverSet @{
            LiveApprovalRule = $Rule; UserBound = $false; GroupBound = $true; ResolvedGroup = @('g2')
            RequireApprovalBound = $true; RequireApproval = $true
        }
        $Set.EffRequired | Should -BeTrue
        @($Set.EffGroup) | Should -Be @('g2')
    }

    It 'counts the live approvers as they are when only -RequireApproval is bound' {
        $Rule = New-TestApprovalRule -Approvers @((New-TestUser 'u1'), (New-TestGroup 'g1'))
        $Set = Invoke-ApproverSet @{ LiveApprovalRule = $Rule; UserBound = $false; GroupBound = $false; RequireApprovalBound = $true; RequireApproval = $true }
        $Set.EffRequired | Should -BeTrue
        $Set.ApproverCount | Should -Be 2
        @($Set.EffUser) | Should -Be @('u1')
        @($Set.EffGroup) | Should -Be @('g1')
        $Set.NoApprover | Should -BeFalse
    }

    It 'reports NoApprover with reason Live when approval is required and the live rule has none (<Shape>)' -TestCases @(
        @{ Shape = 'stage without approvers' }
        @{ Shape = 'no stage' }
        @{ Shape = 'no rule' }
    ) {
        $Rule = switch ($Shape) {
            'stage without approvers' { New-TestApprovalRule -Approvers @() }
            'no stage' { New-TestApprovalRule -NoStage }
            'no rule' { $null }
        }
        $Set = Invoke-ApproverSet @{ LiveApprovalRule = $Rule; UserBound = $false; GroupBound = $false; RequireApprovalBound = $true; RequireApproval = $true }
        $Set.NoApprover | Should -BeTrue
        $Set.NoApproverReason | Should -Be 'Live'
        $Set.ApproverCount | Should -Be 0
    }

    It 'reports NoApprover with reason Bound when the bound approver parameters leave none' {
        $Rule = New-TestApprovalRule -Approvers @((New-TestGroup 'g1'))
        $Set = Invoke-ApproverSet @{ LiveApprovalRule = $Rule; UserBound = $false; GroupBound = $true; ResolvedGroup = @() }
        $Set.NoApprover | Should -BeTrue
        $Set.NoApproverReason | Should -Be 'Bound'
    }

    It 'does not require approval when -RequireApproval $false is bound alone, with no approver anywhere' {
        $Set = Invoke-ApproverSet @{ LiveApprovalRule = (New-TestApprovalRule -NoStage); UserBound = $false; GroupBound = $false; RequireApprovalBound = $true; RequireApproval = $false }
        $Set.EffRequired | Should -BeFalse
        $Set.NoApprover | Should -BeFalse
        $Set.NoApproverReason | Should -Be ''
    }

    It 'requires nothing when neither approvers nor -RequireApproval are bound' {
        $Set = Invoke-ApproverSet @{ LiveApprovalRule = $null; UserBound = $false; GroupBound = $false; RequireApprovalBound = $false; RequireApproval = $true }
        $Set.EffRequired | Should -BeFalse
        $Set.NoApprover | Should -BeFalse
    }

    It 'returns each side as a string array, even with one element' {
        $Rule = New-TestApprovalRule -Approvers @((New-TestGroup 'g1'))
        $Set = Invoke-ApproverSet @{ LiveApprovalRule = $Rule; UserBound = $true; GroupBound = $false; ResolvedUser = @('u2') }
        , $Set.EffUser | Should -BeOfType [string[]]
        , $Set.EffGroup | Should -BeOfType [string[]]
        $Set.EffUser.Count | Should -Be 1
    }
}
