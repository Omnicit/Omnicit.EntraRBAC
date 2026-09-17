BeforeAll {
    $script:moduleName = 'Omnicit.EntraRBAC'
    Get-Module $script:moduleName | Remove-Module -Force -ErrorAction SilentlyContinue
    Import-Module $script:moduleName -Force -ErrorAction Stop
}

Describe 'New-OERAccessPackageApprovalStage' {
    BeforeEach {
        InModuleScope $script:moduleName { $script:_OERAuthState = $null }
        Mock -ModuleName $script:moduleName Initialize-OERAuth {}
        Mock -ModuleName $script:moduleName Resolve-OERUserId { 'uid-1' }
        Mock -ModuleName $script:moduleName Resolve-OERGroupId { 'gid-1' }
    }

    It 'builds a stage with a manager primary approver and justification, no auth' {
        $Stage = New-OERAccessPackageApprovalStage -DurationDays 7 -Manager -RequireJustification
        $Stage.PSObject.TypeNames[0] | Should -Be 'Omnicit.EntraRBAC.ApprovalStage'
        $Stage.GraphStage.durationBeforeAutomaticDenial | Should -Be 'P7D'
        $Stage.GraphStage.isApproverJustificationRequired | Should -BeTrue
        $Stage.GraphStage.primaryApprovers[0]['@odata.type'] | Should -Be '#microsoft.graph.requestorManager'
        $Stage.GraphStage.primaryApprovers[0].managerLevel | Should -Be 1
        ($Stage.GraphStage.Keys -contains 'fallbackPrimaryApprovers') | Should -BeTrue
        ($Stage.GraphStage.Keys -contains 'fallbackEscalationApprovers') | Should -BeTrue
        @($Stage.GraphStage.fallbackPrimaryApprovers).Count | Should -Be 0
        Should -Invoke -ModuleName $script:moduleName Initialize-OERAuth -Times 0
    }

    It 'honours -ManagerLevel' {
        $Stage = New-OERAccessPackageApprovalStage -DurationDays 7 -Manager -ManagerLevel 2
        $Stage.GraphStage.primaryApprovers[0].managerLevel | Should -Be 2
    }

    It 'resolves a user approver by UPN and authenticates' {
        $Stage = New-OERAccessPackageApprovalStage -DurationDays 7 -User 'anna.berg@contoso.com'
        $Stage.GraphStage.primaryApprovers[0]['@odata.type'] | Should -Be '#microsoft.graph.singleUser'
        $Stage.GraphStage.primaryApprovers[0].userId | Should -Be 'uid-1'
        Should -Invoke -ModuleName $script:moduleName Initialize-OERAuth -Times 1
    }

    It 'builds internal and external sponsor approvers' {
        $Stage = New-OERAccessPackageApprovalStage -DurationDays 7 -InternalSponsor -ExternalSponsor
        $Types = $Stage.GraphStage.primaryApprovers | ForEach-Object { $_['@odata.type'] }
        $Types | Should -Contain '#microsoft.graph.internalSponsors'
        $Types | Should -Contain '#microsoft.graph.externalSponsors'
    }

    It 'adds escalation approvers from -AlternateGroup and enables escalation' {
        $Stage = New-OERAccessPackageApprovalStage -DurationDays 14 -User 'anna.berg@contoso.com' `
            -AlternateGroup 'Escalation Approvers' -EscalationDays 8
        $Stage.GraphStage.isEscalationEnabled | Should -BeTrue
        $Stage.GraphStage.escalationApprovers[0]['@odata.type'] | Should -Be '#microsoft.graph.groupMembers'
        $Stage.GraphStage.durationBeforeEscalation | Should -Be 'P8D'
    }

    It 'sets durationBeforeEscalation to PT0S and isEscalationEnabled false when -EscalationDays is not given' {
        $Stage = New-OERAccessPackageApprovalStage -DurationDays 7 -Manager
        $Stage.GraphStage.durationBeforeEscalation | Should -Be 'PT0S'
        $Stage.GraphStage.isEscalationEnabled | Should -BeFalse
    }

    It 'reports Approvers count and DurationDays' {
        $Stage = New-OERAccessPackageApprovalStage -DurationDays 30 `
            -User '11111111-1111-1111-1111-111111111111','22222222-2222-2222-2222-222222222222'
        $Stage.Approvers | Should -Be 2
        $Stage.DurationDays | Should -Be 30
        Should -Invoke -ModuleName $script:moduleName Initialize-OERAuth -Times 0
    }

    It 'errors NoApprover when no primary approver is supplied' {
        New-OERAccessPackageApprovalStage -DurationDays 7 -ErrorVariable err -ErrorAction SilentlyContinue | Out-Null
        $err.FullyQualifiedErrorId | Should -Match 'NoApprover'
    }

    It 'errors UserNotFound when a primary user cannot be resolved' {
        Mock -ModuleName $script:moduleName Resolve-OERUserId { $null }
        New-OERAccessPackageApprovalStage -DurationDays 7 -User 'nope@contoso.com' `
            -ErrorVariable err -ErrorAction SilentlyContinue | Out-Null
        $err.FullyQualifiedErrorId | Should -Match 'UserNotFound'
    }

    It 'errors GroupNotFound when an alternate group cannot be resolved' {
        Mock -ModuleName $script:moduleName Resolve-OERGroupId { $null }
        New-OERAccessPackageApprovalStage -DurationDays 7 -Manager -AlternateGroup 'nope' `
            -ErrorVariable err -ErrorAction SilentlyContinue | Out-Null
        $err.FullyQualifiedErrorId | Should -Match 'GroupNotFound'
    }

    It 'defaults approverInformationVisibility to default' {
        (New-OERAccessPackageApprovalStage -DurationDays 7 -Manager).GraphStage.approverInformationVisibility | Should -Be 'default'
    }

    It 'maps -ApproverInfoVisibility Visible' {
        (New-OERAccessPackageApprovalStage -DurationDays 7 -Manager -ApproverInfoVisibility Visible).GraphStage.approverInformationVisibility | Should -Be 'visible'
    }

    It 'maps -ApproverInfoVisibility NotVisible' {
        (New-OERAccessPackageApprovalStage -DurationDays 7 -Manager -ApproverInfoVisibility NotVisible).GraphStage.approverInformationVisibility | Should -Be 'notVisible'
    }

    It 'emits fallbackPrimaryApprovers from -FallbackUser and -FallbackGroup' {
        $Stage = New-OERAccessPackageApprovalStage -DurationDays 7 -Manager -FallbackUser 'person25@example.com' -FallbackGroup 'FB Group'
        @($Stage.GraphStage.fallbackPrimaryApprovers).Count | Should -Be 2
        $Types = $Stage.GraphStage.fallbackPrimaryApprovers | ForEach-Object { $_['@odata.type'] }
        $Types | Should -Contain '#microsoft.graph.singleUser'
        $Types | Should -Contain '#microsoft.graph.groupMembers'
        Should -Invoke -ModuleName $script:moduleName Initialize-OERAuth -Times 1
    }

    It 'still emits an empty fallbackPrimaryApprovers when no fallback is supplied (regression guard)' {
        $Stage = New-OERAccessPackageApprovalStage -DurationDays 7 -Manager
        ($Stage.GraphStage.Keys -contains 'fallbackPrimaryApprovers') | Should -BeTrue
        @($Stage.GraphStage.fallbackPrimaryApprovers).Count | Should -Be 0
    }

    It 'still emits an empty fallbackEscalationApprovers -- not authorable through this builder' {
        $Stage = New-OERAccessPackageApprovalStage -DurationDays 7 -Manager -FallbackUser 'person25@example.com'
        ($Stage.GraphStage.Keys -contains 'fallbackEscalationApprovers') | Should -BeTrue
        @($Stage.GraphStage.fallbackEscalationApprovers).Count | Should -Be 0
    }

    It 'errors UserNotFound when a fallback user cannot be resolved' {
        Mock -ModuleName $script:moduleName Resolve-OERUserId { $null }
        New-OERAccessPackageApprovalStage -DurationDays 7 -Manager -FallbackUser 'nope@contoso.com' `
            -ErrorVariable err -ErrorAction SilentlyContinue | Out-Null
        $err.FullyQualifiedErrorId | Should -Match 'UserNotFound'
    }
}

Describe 'New-OERAccessPackageApprovalStage ambiguous approver group' {
    BeforeEach {
        InModuleScope Omnicit.EntraRBAC { $script:_OERAuthState = $null }
        Mock -ModuleName Omnicit.EntraRBAC Initialize-OERAuth { }
        Mock -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest { }
    }

    It 'reports an ambiguous approver group as a NON-terminating error naming the candidate ids' {
        Mock -ModuleName Omnicit.EntraRBAC Resolve-OERGroupId {
            throw [System.Management.Automation.ErrorRecord]::new(
                [System.Exception]::new(
                    "Group display name 'Dup' matches 2 groups (11111111-1111-1111-1111-111111111111, 22222222-2222-2222-2222-222222222222)."),
                'AmbiguousName', [System.Management.Automation.ErrorCategory]::InvalidArgument, 'Dup')
        }
        $Caught = $null; $Err = $null; $Out = $null
        try {
            $Out = New-OERAccessPackageApprovalStage -DurationDays 7 -Group 'Dup' -ErrorAction SilentlyContinue -ErrorVariable Err
        } catch { $Caught = $PSItem }
        # Resolve-OERTargetList must report the ambiguity through its Failed* descriptor, not throw.
        # A throw escaping a public cmdlet terminates the pipeline and defeats -ErrorAction
        # SilentlyContinue for a caller building a list of stages.
        $Caught | Should -Be $null
        @($Err | Where-Object { $_.FullyQualifiedErrorId -eq 'AmbiguousGroupName,New-OERAccessPackageApprovalStage' }).Count | Should -Be 1
        $Reported = @($Err | Where-Object { $_.FullyQualifiedErrorId -eq 'AmbiguousGroupName,New-OERAccessPackageApprovalStage' })[0]
        $Reported.Exception.Message | Should -Match '11111111-1111-1111-1111-111111111111'
        $Reported.Exception.Message | Should -Match '22222222-2222-2222-2222-222222222222'
        # An ambiguity is a bad argument, not a missing object.
        $Reported.CategoryInfo.Category | Should -Be 'InvalidArgument'
        $Out | Should -Be $null
        Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest -Times 0
    }

    It 'still reports the existing GroupNotFound error for a genuine no-match' {
        Mock -ModuleName Omnicit.EntraRBAC Resolve-OERGroupId { $null }
        $Err = $null
        New-OERAccessPackageApprovalStage -DurationDays 7 -Group 'missing' -ErrorAction SilentlyContinue -ErrorVariable Err | Out-Null
        @($Err | Where-Object { $_.FullyQualifiedErrorId -eq 'GroupNotFound,New-OERAccessPackageApprovalStage' }).Count | Should -Be 1
        @($Err | Where-Object { $_.FullyQualifiedErrorId -eq 'AmbiguousGroupName,New-OERAccessPackageApprovalStage' }).Count | Should -Be 0
        # The pre-existing not-found path keeps ObjectNotFound: only the ambiguity branch is new.
        @($Err | Where-Object { $_.FullyQualifiedErrorId -eq 'GroupNotFound,New-OERAccessPackageApprovalStage' })[0].CategoryInfo.Category | Should -Be 'ObjectNotFound'
    }
}
