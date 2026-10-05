BeforeAll { Import-Module Omnicit.EntraRBAC -Force }

Describe 'Resolve-OERApproverInput' {
    BeforeEach {
        # An id resolves to itself (letter case preserved, as the real resolver returns a GUID
        # input untouched); a name resolves through the map; anything else is not found, thrown as
        # the record the real Resolve-OERPrincipal throws for a value that matches nothing.
        Mock -ModuleName Omnicit.EntraRBAC Resolve-OERPrincipal {
            $Map = @{
                'person1@example.com' = 'bbbbbbbb-0000-0000-0000-000000000001'
                'person2@example.com' = 'bbbbbbbb-0000-0000-0000-000000000002'
                'PIM Approvers'       = 'cccccccc-0000-0000-0000-000000000001'
            }
            $Kind = if ($User) { 'User' } else { 'Group' }
            $Name = if ($User) { $User } else { $Group }
            $Id = if ($Name -match '^[0-9a-fA-F]{8}-([0-9a-fA-F]{4}-){3}[0-9a-fA-F]{12}$') { $Name } else { $Map[$Name] }
            if (-not $Id) {
                throw [System.Management.Automation.ErrorRecord]::new(
                    [System.Exception]::new("$Kind '$Name' was not found."), 'PrincipalUnresolved',
                    [System.Management.Automation.ErrorCategory]::ObjectNotFound, $Name)
            }
            [pscustomobject]@{ PrincipalId = $Id; PrincipalType = $Kind }
        }
    }

    It 'resolves users through -User and groups through -Group into two id arrays' {
        $Result = InModuleScope Omnicit.EntraRBAC {
            Resolve-OERApproverInput -User 'person1@example.com' -Group 'PIM Approvers'
        }
        @($Result.User) | Should -Be @('bbbbbbbb-0000-0000-0000-000000000001')
        @($Result.Group) | Should -Be @('cccccccc-0000-0000-0000-000000000001')
        # A single id still comes back as an array, so a caller's .Count is an element count.
        , $Result.User | Should -BeOfType [string[]]
        Should -Invoke -ModuleName Omnicit.EntraRBAC Resolve-OERPrincipal -Times 1 -Exactly -ParameterFilter { $User -eq 'person1@example.com' }
        Should -Invoke -ModuleName Omnicit.EntraRBAC Resolve-OERPrincipal -Times 1 -Exactly -ParameterFilter { $Group -eq 'PIM Approvers' }
    }

    It 'returns empty arrays and resolves nothing when no value is supplied (<Shape>)' -TestCases @(
        @{ Shape = 'null'; Users = $null; Groups = $null }
        @{ Shape = 'empty lists'; Users = @(); Groups = @() }
    ) {
        $Result = InModuleScope Omnicit.EntraRBAC -Parameters @{ Users = $Users; Groups = $Groups } {
            param($Users, $Groups)
            Resolve-OERApproverInput -User $Users -Group $Groups
        }
        @($Result.User).Count | Should -Be 0
        @($Result.Group).Count | Should -Be 0
        Should -Invoke -ModuleName Omnicit.EntraRBAC Resolve-OERPrincipal -Times 0
    }

    It 'skips an empty or whitespace-only value instead of resolving it' {
        $Result = InModuleScope Omnicit.EntraRBAC {
            Resolve-OERApproverInput -User 'person1@example.com', '   ', '' -Group "`t", 'PIM Approvers'
        }
        @($Result.User) | Should -Be @('bbbbbbbb-0000-0000-0000-000000000001')
        @($Result.Group) | Should -Be @('cccccccc-0000-0000-0000-000000000001')
        Should -Invoke -ModuleName Omnicit.EntraRBAC Resolve-OERPrincipal -Times 2 -Exactly
    }

    It 'keeps a principal named twice, by name and by id in another letter case, once and in first-seen order' {
        $Result = InModuleScope Omnicit.EntraRBAC {
            Resolve-OERApproverInput `
                -User 'person2@example.com', 'person1@example.com', 'BBBBBBBB-0000-0000-0000-000000000002' `
                -Group 'PIM Approvers', 'CCCCCCCC-0000-0000-0000-000000000001'
        }
        @($Result.User) | Should -Be @('bbbbbbbb-0000-0000-0000-000000000002', 'bbbbbbbb-0000-0000-0000-000000000001')
        @($Result.Group) | Should -Be @('cccccccc-0000-0000-0000-000000000001')
    }

    It 'de-duplicates each side on its own, so an id named as a user and as a group is kept on both' {
        $Result = InModuleScope Omnicit.EntraRBAC {
            Resolve-OERApproverInput -User 'dddddddd-0000-0000-0000-000000000001' -Group 'dddddddd-0000-0000-0000-000000000001'
        }
        @($Result.User) | Should -Be @('dddddddd-0000-0000-0000-000000000001')
        @($Result.Group) | Should -Be @('dddddddd-0000-0000-0000-000000000001')
    }

    It 'throws at the first value that does not resolve, naming it as the target, and resolves nothing after it' {
        $Caught = InModuleScope Omnicit.EntraRBAC {
            try {
                Resolve-OERApproverInput -User 'person1@example.com', 'nobody@example.com', 'person2@example.com' -Group 'PIM Approvers'
                $null
            } catch { $PSItem }
        }
        $Caught | Should -Not -BeNullOrEmpty
        $Caught.CategoryInfo.Category | Should -Be 'ObjectNotFound'
        $Caught.TargetObject | Should -Be 'nobody@example.com'
        $Caught.Exception.Message | Should -Be "User 'nobody@example.com' was not found."
        $Caught.FullyQualifiedErrorId | Should -BeLike 'ApproverUnresolved*'
        Should -Invoke -ModuleName Omnicit.EntraRBAC Resolve-OERPrincipal -Times 2 -Exactly
        Should -Invoke -ModuleName Omnicit.EntraRBAC Resolve-OERPrincipal -Times 0 -ParameterFilter { $User -eq 'person2@example.com' -or $Group }
    }

    It 'names a group that does not resolve as the target' {
        $Caught = InModuleScope Omnicit.EntraRBAC {
            try { Resolve-OERApproverInput -Group 'no-such-group'; $null } catch { $PSItem }
        }
        $Caught.TargetObject | Should -Be 'no-such-group'
        $Caught.Exception.Message | Should -Be "Group 'no-such-group' was not found."
    }

    It 'never throws an ApproverNotFound id of its own, so a calling cmdlet''s -ErrorVariable holds that id once' {
        # A record thrown inside a nested command is also collected by the calling cmdlet's
        # -ErrorVariable, even when the cmdlet catches it. The callers match their own
        # ApproverNotFound record with a -like 'ApproverNotFound*' filter, so this helper's id must
        # not share that prefix.
        $Caught = InModuleScope Omnicit.EntraRBAC {
            try { Resolve-OERApproverInput -User 'nobody@example.com'; $null } catch { $PSItem }
        }
        $Caught.FullyQualifiedErrorId | Should -Not -BeLike 'ApproverNotFound*'
    }
}

Describe 'Resolve-OERApproverInput: only a principal that matches nothing is ApproverUnresolved (Sprint 8 step 3, BL-14)' {
    # The real Resolve-OERPrincipal runs here; only the lookups under it answer. An ambiguous name
    # and a failed lookup are not a missing approver, so they leave this helper exactly as they were
    # thrown, and the caller reports each as what it is.
    It 'wraps the real resolver''s PrincipalUnresolved as ApproverUnresolved, keeping its message, the value as target and the cause' {
        $Caught = InModuleScope Omnicit.EntraRBAC {
            Mock Resolve-OERGroupId { $null }
            try { Resolve-OERApproverInput -Group 'missing-approvers'; $null } catch { $PSItem }
        }
        $Caught.FullyQualifiedErrorId | Should -Be 'ApproverUnresolved'
        $Caught.CategoryInfo.Category | Should -Be 'ObjectNotFound'
        $Caught.TargetObject | Should -Be 'missing-approvers'
        $Caught.Exception.Message | Should -Be "Group 'missing-approvers' was not found."
        $Caught.Exception.InnerException.Message | Should -Be "Group 'missing-approvers' was not found."
    }

    It 'lets <Shape> through as it was thrown, never as ApproverUnresolved, and resolves nothing after it' -ForEach @(
        @{ Shape = 'an ambiguous group name'; Id = 'AmbiguousName'; Category = 'InvalidArgument'; Text = "Group display name 'dup-approvers' matches 2 groups (11111111-1111-1111-1111-111111111111, 22222222-2222-2222-2222-222222222222)." }
        @{ Shape = 'a refused (403) lookup'; Id = 'Authorization_RequestDenied'; Category = 'PermissionDenied'; Text = 'Authorization_RequestDenied: Insufficient privileges to complete the operation.' }
    ) {
        $Result = InModuleScope Omnicit.EntraRBAC -Parameters @{ Id = $Id; Category = $Category; Text = $Text } {
            param($Id, $Category, $Text)
            $script:BL14Thrown = [System.Exception]::new($Text)
            $script:BL14Id = $Id
            $script:BL14Category = $Category
            Mock Resolve-OERGroupId -ParameterFilter { $DisplayName -eq 'dup-approvers' } {
                throw [System.Management.Automation.ErrorRecord]::new(
                    $script:BL14Thrown, $script:BL14Id, [System.Management.Automation.ErrorCategory]$script:BL14Category, 'dup-approvers')
            }
            Mock Resolve-OERGroupId { 'cccccccc-0000-0000-0000-000000000009' }
            $Caught = try { Resolve-OERApproverInput -Group 'dup-approvers', 'later-approvers'; $null } catch { $PSItem }
            [PSCustomObject]@{ Caught = $Caught; SameException = [object]::ReferenceEquals($Caught.Exception, $script:BL14Thrown) }
        }
        $Result.Caught.FullyQualifiedErrorId | Should -Be $Id
        $Result.Caught.CategoryInfo.Category | Should -Be $Category
        $Result.Caught.TargetObject | Should -Be 'dup-approvers'
        $Result.SameException | Should -BeTrue
        Should -Invoke -ModuleName Omnicit.EntraRBAC Resolve-OERGroupId -Times 0 -ParameterFilter { $DisplayName -eq 'later-approvers' }
    }

    It 'scrubs a failed lookup before it lets it through' {
        $Result = InModuleScope Omnicit.EntraRBAC {
            $script:BL14Thrown = [System.Exception]::new('Authorization_RequestDenied: Insufficient privileges to complete the operation.')
            Mock Resolve-OERPrincipal {
                throw [System.Management.Automation.ErrorRecord]::new(
                    $script:BL14Thrown, 'Authorization_RequestDenied', [System.Management.Automation.ErrorCategory]::PermissionDenied, 'person9@example.com')
            }
            Mock Remove-OERErrorRecord { }
            $Caught = try { Resolve-OERApproverInput -User 'person9@example.com'; $null } catch { $PSItem }
            [PSCustomObject]@{ Id = [string]$Caught.FullyQualifiedErrorId }
        }
        # Reached: the record left the helper as itself.
        $Result.Id | Should -Be 'Authorization_RequestDenied'
        Should -Invoke -ModuleName Omnicit.EntraRBAC Remove-OERErrorRecord -Times 1 -Exactly -ParameterFilter {
            $Record -and [string]$Record.FullyQualifiedErrorId -eq 'Authorization_RequestDenied' -and
            $Record.Exception.Message -like '*Insufficient privileges*'
        }
    }
}
