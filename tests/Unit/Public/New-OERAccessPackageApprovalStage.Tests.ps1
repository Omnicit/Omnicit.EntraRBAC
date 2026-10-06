BeforeAll {
    $script:moduleName = 'Omnicit.EntraRBAC'
    Get-Module $script:moduleName | Remove-Module -Force -ErrorAction SilentlyContinue
    Import-Module $script:moduleName -Force -ErrorAction Stop
    . "$PSScriptRoot/../TestHelpers/OERTransportTripwire.ps1"
    Install-OERTransportTripwire
}

AfterAll {
    try { Assert-OERTransportTripwire } finally { Uninstall-OERTransportTripwire }
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

Describe 'New-OERAccessPackageApprovalStage -- a failed approver lookup is not a not-found' {
    BeforeEach {
        InModuleScope Omnicit.EntraRBAC { $script:_OERAuthState = $null }
        Mock -ModuleName Omnicit.EntraRBAC Initialize-OERAuth { }
        Mock -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest { }
        # Only the named value is refused; every other lookup succeeds, so each case reaches exactly the
        # approver slot (primary, alternate or fallback) it is about.
        Mock -ModuleName Omnicit.EntraRBAC Resolve-OERUserId {
            param([string]$Id, [string]$UserPrincipalName)
            if ($UserPrincipalName -eq 'denied@contoso.com') {
                throw [System.Management.Automation.ErrorRecord]::new(
                    [System.Exception]::new('Authorization_RequestDenied: Insufficient privileges to complete the operation.'),
                    'Authorization_RequestDenied', [System.Management.Automation.ErrorCategory]::PermissionDenied, $UserPrincipalName)
            }
            'uid-ok'
        }
        Mock -ModuleName Omnicit.EntraRBAC Resolve-OERGroupId {
            param([string]$DisplayName)
            if ($DisplayName -eq 'Denied Group') {
                throw [System.Management.Automation.ErrorRecord]::new(
                    [System.Exception]::new('Authorization_RequestDenied: Insufficient privileges to complete the operation.'),
                    'Authorization_RequestDenied', [System.Management.Automation.ErrorCategory]::PermissionDenied, $DisplayName)
            }
            'gid-ok'
        }
    }

    It 'publishes a 403 on the <Slot> as itself, never as a not-found, and builds no stage' -ForEach @(
        @{
            Slot = 'primary approver user'; Resolver = 'Resolve-OERUserId'
            Params = @{ DurationDays = 7; User = 'denied@contoso.com' }
        }
        @{
            Slot = 'primary approver group'; Resolver = 'Resolve-OERGroupId'
            Params = @{ DurationDays = 7; Group = 'Denied Group' }
        }
        @{
            Slot = 'escalation (alternate) approver user'; Resolver = 'Resolve-OERUserId'
            Params = @{ DurationDays = 7; Manager = $true; AlternateUser = 'denied@contoso.com' }
        }
        @{
            Slot = 'fallback approver user'; Resolver = 'Resolve-OERUserId'
            Params = @{ DurationDays = 7; Manager = $true; FallbackUser = 'denied@contoso.com' }
        }
        @{
            Slot = 'fallback approver group'; Resolver = 'Resolve-OERGroupId'
            Params = @{ DurationDays = 7; Manager = $true; FallbackGroup = 'Denied Group' }
        }
    ) {
        $Err = $null
        $Out = New-OERAccessPackageApprovalStage @Params -ErrorAction SilentlyContinue -ErrorVariable Err
        # NARROWED ON PURPOSE: -ErrorVariable also holds the engine's own capture of the INNER throw,
        # whose id is the bare 'Authorization_RequestDenied' whether or not this cmdlet re-published it,
        # so an unnarrowed match passes with the fix reverted (measured; see the issue #71 Describe in
        # Add-OERAccessPackageResourceRole.Tests.ps1).
        $Published = @(@($Err) | Where-Object {
                $_.InvocationInfo -and $_.InvocationInfo.MyCommand -and
                $_.InvocationInfo.MyCommand.Name -eq 'New-OERAccessPackageApprovalStage'
            })
        # The positive half: the lookup was attempted and refused, so the zeros below are not a cmdlet
        # that never got that far.
        Should -Invoke -ModuleName Omnicit.EntraRBAC -CommandName $Resolver -Times 1 -Exactly
        @($Published).Count | Should -Be 1
        $Published[0].FullyQualifiedErrorId | Should -Match '^Authorization_RequestDenied'
        $Published[0].FullyQualifiedErrorId | Should -Not -Match 'NotFound'
        $Published[0].CategoryInfo.Category | Should -Be 'PermissionDenied'
        $Out | Should -BeNullOrEmpty
        Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest -Times 0 -Exactly
    }
}

Describe 'New-OERAccessPackageApprovalStage looks a name up only under the session it began with (BL-81)' {
    # The builder signs in only in its process block, through its name lookup (Resolve-OERTargetList).
    # Every begin block of a pipeline runs before any process block, so a DOWNSTREAM command's begin
    # block -- here a ForEach-Object -Begin, the shape of Connect-OER or any cmdlet naming another
    # tenant -- switches the module's sign-in identity after the builder's begin block and before its
    # process block. Without -TenantId the stage must then be refused with SignInSuperseded, before
    # anything is looked up. The resolver is mocked at the module boundary; the switch is a direct
    # write of the module state.
    BeforeAll {
        function script:Set-ProbeState {
            param([string]$TenantId, [string]$AuthMethod = 'ClientCertificate', [string]$ClientId = '33333333-3333-3333-3333-333333333333')
            InModuleScope Omnicit.EntraRBAC -Parameters @{ T = $TenantId; M = $AuthMethod; C = $ClientId } {
                param($T, $M, $C)
                $script:_OERAuthState = if ($T) { @{ TenantId = $T; AuthMethod = $M; ClientId = $C; Environment = 'Global' } } else { $null }
            }
        }
    }
    BeforeEach {
        Set-ProbeState -TenantId '44444444-4444-4444-4444-444444444444'
        Mock -ModuleName Omnicit.EntraRBAC Initialize-OERAuth { }
        Mock -ModuleName Omnicit.EntraRBAC Resolve-OERTargetList {
            @{
                Approvers     = @(@{ '@odata.type' = '#microsoft.graph.singleUser'; userId = 'uid-1' })
                FailedKind    = $null
                FailedValue   = $null
                FailedErrorId = $null
                FailedMessage = $null
                FailedRecord  = $null
            }
        }
    }
    AfterAll { Set-ProbeState -TenantId $null }

    It 'refuses the stage with SignInSuperseded, before any lookup, when a later pipeline command switched the tenant' {
        $Errs = $null
        $Out = @(New-OERAccessPackageApprovalStage -DurationDays 7 -User 'person1@example.com' -ErrorAction SilentlyContinue -ErrorVariable Errs |
                ForEach-Object -Begin { Set-ProbeState -TenantId '77777777-7777-7777-7777-777777777777' } -Process { $_ })
        # Nothing was looked up -- the lookup is where the builder signs in; the record below proves the
        # check was reached.
        Should -Invoke -ModuleName Omnicit.EntraRBAC Resolve-OERTargetList -Times 0
        @($Errs | Where-Object { $_.FullyQualifiedErrorId -eq 'SignInSuperseded,New-OERAccessPackageApprovalStage' }).Count | Should -Be 1
        @($Errs | Where-Object { $_.FullyQualifiedErrorId -eq 'SignInSuperseded,New-OERAccessPackageApprovalStage' })[0].TargetObject |
            Should -BeExactly 'New-OERAccessPackageApprovalStage'
        @($Errs).Count | Should -Be 1
        $Out | Should -BeNullOrEmpty
    }

    It 'refuses a stage that names no approver by name too, under a changed session (fail-safe)' {
        # The check stands before the first lookup step, whatever the arguments: a stage of switches
        # alone, which would look nothing up, is refused as well.
        $Errs = $null
        $Out = @(New-OERAccessPackageApprovalStage -DurationDays 7 -Manager -ErrorAction SilentlyContinue -ErrorVariable Errs |
                ForEach-Object -Begin { Set-ProbeState -TenantId '77777777-7777-7777-7777-777777777777' } -Process { $_ })
        Should -Invoke -ModuleName Omnicit.EntraRBAC Resolve-OERTargetList -Times 0
        @($Errs | Where-Object { $_.FullyQualifiedErrorId -eq 'SignInSuperseded,New-OERAccessPackageApprovalStage' }).Count | Should -Be 1
        @($Errs).Count | Should -Be 1
        $Out | Should -BeNullOrEmpty
    }

    It 'reports a stage with no approver as NoApprover, not SignInSuperseded, under a changed session' {
        # The check stands after the cmdlet's own argument check, so a stage that is invalid anyway
        # reports its own error.
        $Errs = $null
        $Out = @(New-OERAccessPackageApprovalStage -DurationDays 7 -ErrorAction SilentlyContinue -ErrorVariable Errs |
                ForEach-Object -Begin { Set-ProbeState -TenantId '77777777-7777-7777-7777-777777777777' } -Process { $_ })
        $Out | Should -BeNullOrEmpty
        @($Errs | Where-Object { $_.FullyQualifiedErrorId -eq 'NoApprover,New-OERAccessPackageApprovalStage' }).Count | Should -Be 1
        @($Errs | Where-Object { $_.FullyQualifiedErrorId -like 'SignInSuperseded*' }).Count | Should -Be 0
        @($Errs).Count | Should -Be 1
        Should -Invoke -ModuleName Omnicit.EntraRBAC Resolve-OERTargetList -Times 0
    }

    It 'looks the names up and builds the stage when the later pipeline command signs in again as the same identity' {
        $Errs = $null
        $Out = @(New-OERAccessPackageApprovalStage -DurationDays 7 -User 'person1@example.com' -ErrorAction SilentlyContinue -ErrorVariable Errs |
                ForEach-Object -Begin { Set-ProbeState -TenantId '44444444-4444-4444-4444-444444444444' } -Process { $_ })
        $Out.Count | Should -Be 1
        $Out[0].PSObject.TypeNames[0] | Should -Be 'Omnicit.EntraRBAC.ApprovalStage'
        $Out[0].Approvers | Should -Be 1
        @($Errs).Count | Should -Be 0
        # Primary, escalation and fallback: the builder resolves all three lists.
        Should -Invoke -ModuleName Omnicit.EntraRBAC Resolve-OERTargetList -Times 3 -Exactly
    }

    It 'behaves as today with -TenantId: no check, the names are looked up in the tenant it names' {
        # The same downstream switch as the first test. With -TenantId the lookup's sign-in names its
        # tenant, so the builder does not compare.
        $Errs = $null
        $Out = @(New-OERAccessPackageApprovalStage -DurationDays 7 -User 'person1@example.com' -TenantId '44444444-4444-4444-4444-444444444444' -ErrorAction SilentlyContinue -ErrorVariable Errs |
                ForEach-Object -Begin { Set-ProbeState -TenantId '77777777-7777-7777-7777-777777777777' } -Process { $_ })
        $Out.Count | Should -Be 1
        $Out[0].PSObject.TypeNames[0] | Should -Be 'Omnicit.EntraRBAC.ApprovalStage'
        @($Errs | Where-Object { $_.FullyQualifiedErrorId -like 'SignInSuperseded*' }).Count | Should -Be 0
        @($Errs).Count | Should -Be 0
        Should -Invoke -ModuleName Omnicit.EntraRBAC Resolve-OERTargetList -Times 3 -Exactly -ParameterFilter { $TenantId -eq '44444444-4444-4444-4444-444444444444' }
        Should -Invoke -ModuleName Omnicit.EntraRBAC Resolve-OERTargetList -Times 3 -Exactly
        # Not vacuous: the downstream switch really happened before the builder looked anything up.
        InModuleScope Omnicit.EntraRBAC { $script:_OERAuthState.TenantId } | Should -Be '77777777-7777-7777-7777-777777777777'
    }

    It 'is not refused when called inside another command''s process block, the shape Sync-OERStructureAccessPackage uses' {
        # Review Focus 4: a nested builder runs its begin and process blocks back to back, so its
        # snapshot is taken after everything the outer pipeline did -- here a downstream switch that
        # happened before the outer command's process block called the builder.
        function Invoke-BL81NestedProbe {
            [CmdletBinding()]
            param()
            process { New-OERAccessPackageApprovalStage -DurationDays 7 -User 'person1@example.com' }
        }
        $Errs = $null
        $Out = @(Invoke-BL81NestedProbe -ErrorAction SilentlyContinue -ErrorVariable Errs |
                ForEach-Object -Begin { Set-ProbeState -TenantId '77777777-7777-7777-7777-777777777777' } -Process { $_ })
        $Out.Count | Should -Be 1
        $Out[0].PSObject.TypeNames[0] | Should -Be 'Omnicit.EntraRBAC.ApprovalStage'
        @($Errs).Count | Should -Be 0
        Should -Invoke -ModuleName Omnicit.EntraRBAC Resolve-OERTargetList -Times 3 -Exactly
        # Not vacuous: the state the nested builder began and ran under is the switched one.
        InModuleScope Omnicit.EntraRBAC { $script:_OERAuthState.TenantId } | Should -Be '77777777-7777-7777-7777-777777777777'
    }
}
