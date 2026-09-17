BeforeAll {
    $script:moduleName = 'Omnicit.EntraRBAC'
    Get-Module $script:moduleName | Remove-Module -Force -ErrorAction SilentlyContinue
    Import-Module $script:moduleName -Force -ErrorAction Stop
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
                SpecificDirectoryUsers                  = 'specificDirectoryUsers'
                SpecificConnectedOrganizationUsers      = 'specificConnectedOrganizationUsers'
                AllConfiguredConnectedOrganizationUsers = 'allConfiguredConnectedOrganizationUsers'
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
