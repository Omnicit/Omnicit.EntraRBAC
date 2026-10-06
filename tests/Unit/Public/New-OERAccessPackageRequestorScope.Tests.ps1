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

Describe 'New-OERAccessPackageRequestorScope' {
    BeforeEach {
        InModuleScope $script:moduleName { $script:_OERAuthState = $null }
        Mock -ModuleName $script:moduleName Initialize-OERAuth {}
        Mock -ModuleName $script:moduleName Resolve-OERUserId { 'uid-1' }
        Mock -ModuleName $script:moduleName Resolve-OERGroupId { 'gid-1' }
    }

    It 'builds an AllMemberUsers scope with no targets and no auth' {
        $S = New-OERAccessPackageRequestorScope -Scope AllMemberUsers
        $S.PSObject.TypeNames[0] | Should -Be 'Omnicit.EntraRBAC.RequestorScope'
        $S.AllowedTargetScope | Should -Be 'allMemberUsers'
        @($S.SpecificAllowedTargets).Count | Should -Be 0
        Should -Invoke -ModuleName $script:moduleName Initialize-OERAuth -Times 0
    }

    It 'builds an admin-assignment-only scope' {
        $S = New-OERAccessPackageRequestorScope -AdminAssignmentOnly
        $S.AllowedTargetScope | Should -Be 'notSpecified'
        $S.PSObject.TypeNames[0] | Should -Be 'Omnicit.EntraRBAC.RequestorScope'
    }

    It 'maps each scope value to its Graph token' {
        (New-OERAccessPackageRequestorScope -Scope AllDirectoryUsers).AllowedTargetScope | Should -Be 'allDirectoryUsers'
        (New-OERAccessPackageRequestorScope -Scope SpecificConnectedOrganizationUsers).AllowedTargetScope | Should -Be 'specificConnectedOrganizationUsers'
        (New-OERAccessPackageRequestorScope -Scope AllExternalUsers).AllowedTargetScope | Should -BeExactly 'allExternalUsers'
        (New-OERAccessPackageRequestorScope -Scope AllDirectoryServicePrincipals).AllowedTargetScope | Should -BeExactly 'allDirectoryServicePrincipals'
        (New-OERAccessPackageRequestorScope -Scope AllDirectoryAgentIdentities).AllowedTargetScope | Should -BeExactly 'allDirectoryAgentIdentities'
    }

    Context '-Scope NoSubjects is mapped to notSpecified with a warning (issue #86, 2026-09-11 live finding)' {
        # noSubjects is the legacy beta requestorSettings.scopeType spelling and is not a member of
        # the v1.0 allowedTargetScope enum, so emitting it made entitlement management reject the
        # whole policy with "InvalidModel: The model is invalid." Its v1.0 equivalent is
        # notSpecified -- administrator direct assignment only, the same state.
        It 'emits notSpecified, never the out-of-enum noSubjects token' {
            $S = New-OERAccessPackageRequestorScope -Scope NoSubjects -WarningAction SilentlyContinue
            $S.AllowedTargetScope | Should -Be 'notSpecified'
            $S.AllowedTargetScope | Should -Not -Be 'noSubjects' -Because (
                'the v1.0 allowedTargetScope enum has no noSubjects member, so sending it is rejected as InvalidModel')
        }

        It 'warns exactly once, naming the legacy origin, the substitution and how to silence it' {
            $Warn = $null
            New-OERAccessPackageRequestorScope -Scope NoSubjects -WarningVariable Warn -WarningAction SilentlyContinue | Out-Null
            @($Warn).Count | Should -Be 1
            [string]$Warn[0] | Should -Match 'legacy beta'
            [string]$Warn[0] | Should -Match 'notSpecified'
            [string]$Warn[0] | Should -Match 'AdminAssignmentOnly'
        }

        It 'leaves every other ValidateSet member mapping to its own documented value, unwarned' {
            $Expected = @{
                AllMemberUsers                          = 'allMemberUsers'
                AllDirectoryUsers                       = 'allDirectoryUsers'
                AllExternalUsers                        = 'allExternalUsers'
                SpecificDirectoryUsers                  = 'specificDirectoryUsers'
                SpecificConnectedOrganizationUsers      = 'specificConnectedOrganizationUsers'
                AllConfiguredConnectedOrganizationUsers = 'allConfiguredConnectedOrganizationUsers'
                AllDirectoryServicePrincipals           = 'allDirectoryServicePrincipals'
                AllDirectoryAgentIdentities             = 'allDirectoryAgentIdentities'
                NotSpecified                            = 'notSpecified'
            }
            foreach ($Name in $Expected.Keys) {
                $Warn = $null
                $Built = New-OERAccessPackageRequestorScope -Scope $Name -WarningVariable Warn -WarningAction SilentlyContinue
                $Built.AllowedTargetScope | Should -Be $Expected[$Name] -Because "-Scope $Name must keep emitting its own documented v1.0 value"
                @($Warn).Count | Should -Be 0 -Because "only NoSubjects is substituted, so -Scope $Name must stay silent"
            }
        }
    }

    It 'accepts -Scope NotSpecified (the None / admin-only scope) for round-trip' {
        # A policy whose "Who can get access" is None reads back as allowedTargetScope 'notSpecified';
        # the inventory emits scope NotSpecified, so the builder must accept it (it previously failed
        # ValidateSet, breaking Invoke-OERStructure).
        (New-OERAccessPackageRequestorScope -Scope NotSpecified).AllowedTargetScope | Should -Be 'notSpecified'
    }

    It 'accepts the lowercase Graph token notSpecified (case-insensitive ValidateSet)' {
        (New-OERAccessPackageRequestorScope -Scope 'notSpecified').AllowedTargetScope | Should -Be 'notSpecified'
    }

    It 'accepts -Scope AllConfiguredConnectedOrganizationUsers' {
        (New-OERAccessPackageRequestorScope -Scope AllConfiguredConnectedOrganizationUsers).AllowedTargetScope | Should -Be 'allConfiguredConnectedOrganizationUsers'
    }

    It 'accepts -Scope <Scope> and builds <Graph> with no targets and no auth' -ForEach @(
        @{ Scope = 'AllExternalUsers'; Graph = 'allExternalUsers' }
        @{ Scope = 'AllDirectoryServicePrincipals'; Graph = 'allDirectoryServicePrincipals' }
        @{ Scope = 'AllDirectoryAgentIdentities'; Graph = 'allDirectoryAgentIdentities' }
    ) {
        $S = New-OERAccessPackageRequestorScope -Scope $Scope -ErrorAction Stop
        $S.PSObject.TypeNames[0] | Should -Be 'Omnicit.EntraRBAC.RequestorScope'
        $S.AllowedTargetScope | Should -BeExactly $Graph
        @($S.SpecificAllowedTargets).Count | Should -Be 0
        Should -Invoke -ModuleName $script:moduleName Initialize-OERAuth -Times 0
    }

    It 'binds every Microsoft Graph v1.0 allowedTargetScope value except unknownFutureValue' {
        # Learn, accessPackageAssignmentPolicy v1.0: allowedTargetScope. unknownFutureValue is the
        # evolvable-enum sentinel, never a scope an author can choose, so it is the one value left out.
        $V1Values = @(
            'notSpecified', 'specificDirectoryUsers', 'specificConnectedOrganizationUsers',
            'specificDirectoryServicePrincipals', 'allMemberUsers', 'allDirectoryUsers',
            'allDirectoryServicePrincipals', 'allConfiguredConnectedOrganizationUsers', 'allExternalUsers',
            'allDirectoryAgentIdentities'
        )
        $ValidSet = @((Get-Command New-OERAccessPackageRequestorScope).Parameters['Scope'].Attributes |
                Where-Object { $_ -is [System.Management.Automation.ValidateSetAttribute] } |
                ForEach-Object { $_.ValidValues })
        foreach ($Value in $V1Values) {
            @($ValidSet | Where-Object { $_ -ieq $Value }).Count | Should -Be 1 -Because "-Scope must bind the v1.0 value '$Value'"
        }
        @($ValidSet | Where-Object { $_ -ieq 'unknownFutureValue' }).Count | Should -Be 0
    }

    Context '-Scope SpecificDirectoryServicePrincipals binds but is refused' {
        # The scope is only meaningful with specificAllowedTargets naming service principals, which the
        # module does not model, so building it would send the scope with no targets at all.
        It 'writes one non-terminating InvalidPolicyInput error naming the scope, and emits no object' {
            $Err = $null
            $Caught = $null
            $Out = $null
            try {
                $Out = New-OERAccessPackageRequestorScope -Scope SpecificDirectoryServicePrincipals -ErrorAction SilentlyContinue -ErrorVariable Err
            } catch { $Caught = $PSItem }
            $Caught | Should -BeNullOrEmpty
            $Out | Should -BeNullOrEmpty
            @($Err).Count | Should -Be 1
            $Err[0].FullyQualifiedErrorId | Should -BeExactly 'InvalidPolicyInput,New-OERAccessPackageRequestorScope'
            $Err[0].CategoryInfo.Category | Should -Be 'InvalidArgument'
            $Err[0].TargetObject | Should -BeExactly 'SpecificDirectoryServicePrincipals'
            $Err[0].Exception.Message | Should -BeExactly ("Requestor scope 'SpecificDirectoryServicePrincipals' needs specificAllowedTargets " +
                'naming service principals, which this module does not model, so the scope cannot be built and nothing was sent.')
        }

        It 'refuses before resolving any -User or -Group, so no lookup and no authentication run' {
            $Err = $null
            $Out = New-OERAccessPackageRequestorScope -Scope SpecificDirectoryServicePrincipals -User 'person1@example.com' -Group 'Sales Team' `
                -ErrorAction SilentlyContinue -ErrorVariable Err -WarningAction SilentlyContinue
            $Out | Should -BeNullOrEmpty
            @($Err | Where-Object { $_.FullyQualifiedErrorId -eq 'InvalidPolicyInput,New-OERAccessPackageRequestorScope' }).Count | Should -Be 1
            Should -Invoke -ModuleName $script:moduleName Resolve-OERUserId -Times 0
            Should -Invoke -ModuleName $script:moduleName Resolve-OERGroupId -Times 0
            Should -Invoke -ModuleName $script:moduleName Initialize-OERAuth -Times 0
        }

        It 'binds the lowercase Graph token too, and refuses it the same way' {
            $Err = $null
            $Out = New-OERAccessPackageRequestorScope -Scope 'specificDirectoryServicePrincipals' -ErrorAction SilentlyContinue -ErrorVariable Err
            $Out | Should -BeNullOrEmpty
            @($Err | Where-Object { $_.FullyQualifiedErrorId -eq 'InvalidPolicyInput,New-OERAccessPackageRequestorScope' }).Count | Should -Be 1
        }
    }

    It 'resolves a group name target for SpecificDirectoryUsers' {
        $S = New-OERAccessPackageRequestorScope -Scope SpecificDirectoryUsers -Group 'Sales Team'
        $S.AllowedTargetScope | Should -Be 'specificDirectoryUsers'
        $S.SpecificAllowedTargets[0]['@odata.type'] | Should -Be '#microsoft.graph.groupMembers'
        $S.SpecificAllowedTargets[0].groupId | Should -Be 'gid-1'
        Should -Invoke -ModuleName $script:moduleName Initialize-OERAuth -Times 1
    }

    It 'resolves a user UPN target for SpecificDirectoryUsers' {
        $S = New-OERAccessPackageRequestorScope -Scope SpecificDirectoryUsers -User 'anna.berg@contoso.com'
        $S.SpecificAllowedTargets[0]['@odata.type'] | Should -Be '#microsoft.graph.singleUser'
        $S.SpecificAllowedTargets[0].userId | Should -Be 'uid-1'
        Should -Invoke -ModuleName $script:moduleName Initialize-OERAuth -Times 1
    }

    It 'accepts mixed -User and -Group arrays' {
        $S = New-OERAccessPackageRequestorScope -Scope SpecificDirectoryUsers `
            -User 'anna.berg@contoso.com' -Group 'Sales Team','Marketing'
        $S.SpecificAllowedTargets.Count | Should -Be 3
    }

    It 'does not authenticate when targets are all GUIDs' {
        $S = New-OERAccessPackageRequestorScope -Scope SpecificDirectoryUsers `
            -User '11111111-1111-1111-1111-111111111111'
        $S.SpecificAllowedTargets.Count | Should -Be 1
        Should -Invoke -ModuleName $script:moduleName Initialize-OERAuth -Times 0
    }

    It 'warns and ignores -User/-Group for a non-Specific scope' {
        $S = New-OERAccessPackageRequestorScope -Scope AllMemberUsers -Group 'Sales Team' -WarningVariable warn -WarningAction SilentlyContinue
        @($S.SpecificAllowedTargets).Count | Should -Be 0
        $warn | Should -Not -BeNullOrEmpty
    }

    It 'errors GroupNotFound when a group name cannot be resolved' {
        Mock -ModuleName $script:moduleName Resolve-OERGroupId { $null }
        New-OERAccessPackageRequestorScope -Scope SpecificDirectoryUsers -Group 'nope' `
            -ErrorVariable err -ErrorAction SilentlyContinue | Out-Null
        $err.FullyQualifiedErrorId | Should -Match 'GroupNotFound'
    }

    It 'errors UserNotFound when a user UPN cannot be resolved' {
        Mock -ModuleName $script:moduleName Resolve-OERUserId { $null }
        New-OERAccessPackageRequestorScope -Scope SpecificDirectoryUsers -User 'nope@contoso.com' `
            -ErrorVariable err -ErrorAction SilentlyContinue | Out-Null
        $err.FullyQualifiedErrorId | Should -Match 'UserNotFound'
    }
}

Describe 'New-OERAccessPackageRequestorScope ambiguous requestor group' {
    BeforeEach {
        InModuleScope Omnicit.EntraRBAC { $script:_OERAuthState = $null }
        Mock -ModuleName Omnicit.EntraRBAC Initialize-OERAuth { }
        Mock -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest { }
    }

    It 'reports an ambiguous requestor group as a NON-terminating error naming the candidate ids' {
        Mock -ModuleName Omnicit.EntraRBAC Resolve-OERGroupId {
            throw [System.Management.Automation.ErrorRecord]::new(
                [System.Exception]::new(
                    "Group display name 'Dup' matches 2 groups (11111111-1111-1111-1111-111111111111, 22222222-2222-2222-2222-222222222222)."),
                'AmbiguousName', [System.Management.Automation.ErrorCategory]::InvalidArgument, 'Dup')
        }
        $Caught = $null; $Err = $null; $Out = $null
        try {
            $Out = New-OERAccessPackageRequestorScope -Scope SpecificDirectoryUsers -Group 'Dup' -ErrorAction SilentlyContinue -ErrorVariable Err
        } catch { $Caught = $PSItem }
        # A throw escaping the helper would terminate this builder; it must be a WriteError instead.
        $Caught | Should -Be $null
        @($Err | Where-Object { $_.FullyQualifiedErrorId -eq 'AmbiguousGroupName,New-OERAccessPackageRequestorScope' }).Count | Should -Be 1
        $Reported = @($Err | Where-Object { $_.FullyQualifiedErrorId -eq 'AmbiguousGroupName,New-OERAccessPackageRequestorScope' })[0]
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
        New-OERAccessPackageRequestorScope -Scope SpecificDirectoryUsers -Group 'missing' -ErrorAction SilentlyContinue -ErrorVariable Err | Out-Null
        @($Err | Where-Object { $_.FullyQualifiedErrorId -eq 'GroupNotFound,New-OERAccessPackageRequestorScope' }).Count | Should -Be 1
        @($Err | Where-Object { $_.FullyQualifiedErrorId -eq 'AmbiguousGroupName,New-OERAccessPackageRequestorScope' }).Count | Should -Be 0
        # The pre-existing not-found path keeps ObjectNotFound: only the ambiguity branch is new.
        @($Err | Where-Object { $_.FullyQualifiedErrorId -eq 'GroupNotFound,New-OERAccessPackageRequestorScope' })[0].CategoryInfo.Category | Should -Be 'ObjectNotFound'
    }
}

Describe 'New-OERAccessPackageRequestorScope -- a failed requestor lookup is not a not-found' {
    BeforeEach {
        InModuleScope Omnicit.EntraRBAC { $script:_OERAuthState = $null }
        Mock -ModuleName Omnicit.EntraRBAC Initialize-OERAuth { }
        Mock -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest { }
        Mock -ModuleName Omnicit.EntraRBAC Resolve-OERUserId {
            throw [System.Management.Automation.ErrorRecord]::new(
                [System.Exception]::new('Authorization_RequestDenied: Insufficient privileges to complete the operation.'),
                'Authorization_RequestDenied', [System.Management.Automation.ErrorCategory]::PermissionDenied, 'denied@contoso.com')
        }
        Mock -ModuleName Omnicit.EntraRBAC Resolve-OERGroupId {
            throw [System.Management.Automation.ErrorRecord]::new(
                [System.Exception]::new('Authorization_RequestDenied: Insufficient privileges to complete the operation.'),
                'Authorization_RequestDenied', [System.Management.Automation.ErrorCategory]::PermissionDenied, 'Denied Group')
        }
    }

    It 'publishes a 403 on a requestor <Slot> as itself, never as a not-found, and builds no scope' -ForEach @(
        @{ Slot = 'user'; Resolver = 'Resolve-OERUserId'; Params = @{ Scope = 'SpecificDirectoryUsers'; User = 'denied@contoso.com' } }
        @{ Slot = 'group'; Resolver = 'Resolve-OERGroupId'; Params = @{ Scope = 'SpecificDirectoryUsers'; Group = 'Denied Group' } }
    ) {
        $Err = $null
        $Out = New-OERAccessPackageRequestorScope @Params -ErrorAction SilentlyContinue -ErrorVariable Err
        # NARROWED ON PURPOSE: -ErrorVariable also holds the engine's own capture of the INNER throw,
        # whose id is the bare 'Authorization_RequestDenied' whether or not this cmdlet re-published it,
        # so an unnarrowed match passes with the fix reverted (measured; see the issue #71 Describe in
        # Add-OERAccessPackageResourceRole.Tests.ps1).
        $Published = @(@($Err) | Where-Object {
                $_.InvocationInfo -and $_.InvocationInfo.MyCommand -and
                $_.InvocationInfo.MyCommand.Name -eq 'New-OERAccessPackageRequestorScope'
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

Describe 'New-OERAccessPackageRequestorScope looks a target up only under the session it began with (BL-81)' {
    # The builder signs in only in its process block, through its target lookup
    # (Resolve-OERTargetList). Every begin block of a pipeline runs before any process block, so a
    # DOWNSTREAM command's begin block -- here a ForEach-Object -Begin, the shape of Connect-OER or any
    # cmdlet naming another tenant -- switches the module's sign-in identity after the builder's begin
    # block and before its process block. Without -TenantId a scope with -User or -Group must then be
    # refused with SignInSuperseded, before anything is looked up; a scope with no targets looks
    # nothing up and is never refused. The resolver is mocked at the module boundary; the switch is a
    # direct write of the module state.
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

    It 'refuses the scope with SignInSuperseded, before any lookup, when a later pipeline command switched the tenant' {
        $Errs = $null
        $Out = @(New-OERAccessPackageRequestorScope -Scope SpecificDirectoryUsers -User 'person1@example.com' -ErrorAction SilentlyContinue -ErrorVariable Errs |
                ForEach-Object -Begin { Set-ProbeState -TenantId '77777777-7777-7777-7777-777777777777' } -Process { $_ })
        # Nothing was looked up or signed in to; the record below proves the check was reached.
        Should -Invoke -ModuleName Omnicit.EntraRBAC Resolve-OERTargetList -Times 0
        Should -Invoke -ModuleName Omnicit.EntraRBAC Initialize-OERAuth -Times 0
        @($Errs | Where-Object { $_.FullyQualifiedErrorId -eq 'SignInSuperseded,New-OERAccessPackageRequestorScope' }).Count | Should -Be 1
        @($Errs | Where-Object { $_.FullyQualifiedErrorId -eq 'SignInSuperseded,New-OERAccessPackageRequestorScope' })[0].TargetObject |
            Should -BeExactly 'New-OERAccessPackageRequestorScope'
        @($Errs).Count | Should -Be 1
        $Out | Should -BeNullOrEmpty
    }

    It 'refuses a scope whose targets are all object ids too, under a changed session (fail-safe)' {
        # The check stands before the lookup step, whatever the targets: object ids, which would look
        # nothing up, are refused as well.
        $Errs = $null
        $Out = @(New-OERAccessPackageRequestorScope -Scope SpecificDirectoryUsers -User '11111111-1111-1111-1111-111111111111' -ErrorAction SilentlyContinue -ErrorVariable Errs |
                ForEach-Object -Begin { Set-ProbeState -TenantId '77777777-7777-7777-7777-777777777777' } -Process { $_ })
        Should -Invoke -ModuleName Omnicit.EntraRBAC Resolve-OERTargetList -Times 0
        @($Errs | Where-Object { $_.FullyQualifiedErrorId -eq 'SignInSuperseded,New-OERAccessPackageRequestorScope' }).Count | Should -Be 1
        @($Errs).Count | Should -Be 1
        $Out | Should -BeNullOrEmpty
    }

    It 'builds a scope with no targets under a changed session: it looks nothing up and is not refused' {
        $Errs = $null
        $Out = @(New-OERAccessPackageRequestorScope -Scope AllMemberUsers -ErrorAction SilentlyContinue -ErrorVariable Errs |
                ForEach-Object -Begin { Set-ProbeState -TenantId '77777777-7777-7777-7777-777777777777' } -Process { $_ })
        $Out.Count | Should -Be 1
        $Out[0].PSObject.TypeNames[0] | Should -Be 'Omnicit.EntraRBAC.RequestorScope'
        $Out[0].AllowedTargetScope | Should -BeExactly 'allMemberUsers'
        @($Errs).Count | Should -Be 0
        Should -Invoke -ModuleName Omnicit.EntraRBAC Resolve-OERTargetList -Times 0
        # Not vacuous: the downstream switch really happened before the scope was built.
        InModuleScope Omnicit.EntraRBAC { $script:_OERAuthState.TenantId } | Should -Be '77777777-7777-7777-7777-777777777777'
    }

    It 'looks the targets up and builds the scope when the later pipeline command signs in again as the same identity' {
        $Errs = $null
        $Out = @(New-OERAccessPackageRequestorScope -Scope SpecificDirectoryUsers -User 'person1@example.com' -ErrorAction SilentlyContinue -ErrorVariable Errs |
                ForEach-Object -Begin { Set-ProbeState -TenantId '44444444-4444-4444-4444-444444444444' } -Process { $_ })
        $Out.Count | Should -Be 1
        $Out[0].PSObject.TypeNames[0] | Should -Be 'Omnicit.EntraRBAC.RequestorScope'
        @($Out[0].SpecificAllowedTargets).Count | Should -Be 1
        @($Errs).Count | Should -Be 0
        Should -Invoke -ModuleName Omnicit.EntraRBAC Resolve-OERTargetList -Times 1 -Exactly
    }

    It 'behaves as today with -TenantId: no check, the targets are looked up in the tenant it names' {
        # The same downstream switch as the first test. With -TenantId the lookup's sign-in names its
        # tenant, so the builder does not compare.
        $Errs = $null
        $Out = @(New-OERAccessPackageRequestorScope -Scope SpecificDirectoryUsers -User 'person1@example.com' -TenantId '44444444-4444-4444-4444-444444444444' -ErrorAction SilentlyContinue -ErrorVariable Errs |
                ForEach-Object -Begin { Set-ProbeState -TenantId '77777777-7777-7777-7777-777777777777' } -Process { $_ })
        $Out.Count | Should -Be 1
        $Out[0].PSObject.TypeNames[0] | Should -Be 'Omnicit.EntraRBAC.RequestorScope'
        @($Errs | Where-Object { $_.FullyQualifiedErrorId -like 'SignInSuperseded*' }).Count | Should -Be 0
        @($Errs).Count | Should -Be 0
        Should -Invoke -ModuleName Omnicit.EntraRBAC Resolve-OERTargetList -Times 1 -Exactly -ParameterFilter { $TenantId -eq '44444444-4444-4444-4444-444444444444' }
        Should -Invoke -ModuleName Omnicit.EntraRBAC Resolve-OERTargetList -Times 1 -Exactly
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
            process { New-OERAccessPackageRequestorScope -Scope SpecificDirectoryUsers -User 'person1@example.com' }
        }
        $Errs = $null
        $Out = @(Invoke-BL81NestedProbe -ErrorAction SilentlyContinue -ErrorVariable Errs |
                ForEach-Object -Begin { Set-ProbeState -TenantId '77777777-7777-7777-7777-777777777777' } -Process { $_ })
        $Out.Count | Should -Be 1
        $Out[0].PSObject.TypeNames[0] | Should -Be 'Omnicit.EntraRBAC.RequestorScope'
        @($Errs).Count | Should -Be 0
        Should -Invoke -ModuleName Omnicit.EntraRBAC Resolve-OERTargetList -Times 1 -Exactly
        # Not vacuous: the state the nested builder began and ran under is the switched one.
        InModuleScope Omnicit.EntraRBAC { $script:_OERAuthState.TenantId } | Should -Be '77777777-7777-7777-7777-777777777777'
    }
}
