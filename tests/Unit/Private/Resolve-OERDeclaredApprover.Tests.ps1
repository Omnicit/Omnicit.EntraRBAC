BeforeAll {
    Import-Module Omnicit.EntraRBAC -Force
    . "$PSScriptRoot/../TestHelpers/OERTransportTripwire.ps1"
    Install-OERTransportTripwire
}

AfterAll {
    try { Assert-OERTransportTripwire } finally { Uninstall-OERTransportTripwire }
}

Describe 'Resolve-OERDeclaredApprover' {
    BeforeEach {
        InModuleScope Omnicit.EntraRBAC {
            Mock Resolve-OERPrincipal {
                param($User, $Group)
                $Map = @{
                    'person1@example.com' = '11111111-1111-1111-1111-111111111111'
                    '11111111-1111-1111-1111-111111111111' = '11111111-1111-1111-1111-111111111111'
                    'Approvers' = '22222222-2222-2222-2222-222222222222'
                }
                $Key = if ($User) { $User } else { $Group }
                if (-not $Map.ContainsKey($Key)) {
                    # The record the real Resolve-OERPrincipal throws for a value that matches nothing.
                    $Text = if ($User) { "User '$User' was not found." } else { "Group '$Group' was not found." }
                    throw [System.Management.Automation.ErrorRecord]::new(
                        [System.Exception]::new($Text), 'PrincipalUnresolved',
                        [System.Management.Automation.ErrorCategory]::ObjectNotFound, $Key)
                }
                [PSCustomObject]@{ PrincipalId = $Map[$Key]; PrincipalType = $(if ($User) { 'User' } else { 'Group' }) }
            }
        }
    }

    It 'returns the same object when approvers is not declared at all' {
        InModuleScope Omnicit.EntraRBAC {
            $Declared = [PSCustomObject]@{ scope = '/s'; role = 'Contributor'; requireApproval = $true }
            $Result = Resolve-OERDeclaredApprover -Declared $Declared
            [object]::ReferenceEquals($Result, $Declared) | Should -Be $true
            Should -Invoke Resolve-OERPrincipal -Times 0
        }
    }

    It 'returns the same object when approvers is explicitly null' {
        InModuleScope Omnicit.EntraRBAC {
            $Declared = '{ "scope": "/s", "role": "Contributor", "requireApproval": true, "approvers": null }' | ConvertFrom-Json
            $Result = Resolve-OERDeclaredApprover -Declared $Declared
            [object]::ReferenceEquals($Result, $Declared) | Should -Be $true
            Should -Invoke Resolve-OERPrincipal -Times 0
        }
    }

    It 'does not resolve and does not throw when requireApproval is declared false, even with an unresolvable approver' {
        InModuleScope Omnicit.EntraRBAC {
            $Declared = [PSCustomObject]@{
                scope = '/s'; role = 'Contributor'; requireApproval = $false
                approvers = [PSCustomObject]@{ users = @('nobody@example.com') }
            }
            # Called directly (not wrapped in a { } | Should -Not -Throw script block, which Pester
            # invokes via the call operator and therefore in a CHILD scope -- an assignment made
            # inside it never escapes to this scope). An unhandled exception here still fails the
            # test on its own, so this is an equally valid "does not throw" proof.
            $Result = Resolve-OERDeclaredApprover -Declared $Declared
            [object]::ReferenceEquals($Result, $Declared) | Should -Be $true
            Should -Invoke Resolve-OERPrincipal -Times 0
        }
    }

    It 'resolves users with -User and groups with -Group into object ids' {
        InModuleScope Omnicit.EntraRBAC {
            $Declared = [PSCustomObject]@{
                scope = '/s'; role = 'Contributor'; requireApproval = $true
                approvers = [PSCustomObject]@{ users = @('person1@example.com'); groups = @('Approvers') }
            }
            $Copy = Resolve-OERDeclaredApprover -Declared $Declared
            @($Copy.approvers.users) | Should -Be @('11111111-1111-1111-1111-111111111111')
            @($Copy.approvers.groups) | Should -Be @('22222222-2222-2222-2222-222222222222')
            Should -Invoke Resolve-OERPrincipal -Times 1 -Exactly -ParameterFilter { $User -eq 'person1@example.com' }
            Should -Invoke Resolve-OERPrincipal -Times 1 -Exactly -ParameterFilter { $Group -eq 'Approvers' }
        }
    }

    It 'leaves groups undeclared on the copy when the document declares only users' {
        InModuleScope Omnicit.EntraRBAC {
            $Declared = [PSCustomObject]@{
                scope = '/s'; role = 'Contributor'; requireApproval = $true
                approvers = [PSCustomObject]@{ users = @('person1@example.com') }
            }
            $Copy = Resolve-OERDeclaredApprover -Declared $Declared
            Test-OERDeclaredProperty -Node $Copy.approvers -Name 'users' | Should -Be $true
            Test-OERDeclaredProperty -Node $Copy.approvers -Name 'groups' | Should -Be $false
        }
    }

    It 'de-duplicates resolved ids case-insensitively' {
        InModuleScope Omnicit.EntraRBAC {
            Mock Resolve-OERPrincipal {
                param($User, $Group)
                if ($User -eq 'person2@example.com') {
                    return [PSCustomObject]@{ PrincipalId = 'aaaaaaaa-aaaa-1aaa-aaaa-aaaaaaaaaaaa'; PrincipalType = 'User' }
                }
                [PSCustomObject]@{ PrincipalId = $User; PrincipalType = 'User' }
            }
            $Declared = [PSCustomObject]@{
                scope = '/s'; role = 'Contributor'; requireApproval = $true
                approvers = [PSCustomObject]@{
                    users = @('person2@example.com', 'aaaaaaaa-aaaa-1aaa-aaaa-aaaaaaaaaaaa', 'AAAAAAAA-AAAA-1AAA-AAAA-AAAAAAAAAAAA')
                }
            }
            $Copy = Resolve-OERDeclaredApprover -Declared $Declared
            @($Copy.approvers.users).Count | Should -Be 1
        }
    }

    It 'skips empty and whitespace-only entries' {
        InModuleScope Omnicit.EntraRBAC {
            $Declared = [PSCustomObject]@{
                scope = '/s'; role = 'Contributor'; requireApproval = $true
                approvers = [PSCustomObject]@{ users = @('', '  ', 'person1@example.com') }
            }
            $Copy = Resolve-OERDeclaredApprover -Declared $Declared
            @($Copy.approvers.users).Count | Should -Be 1
            Should -Invoke Resolve-OERPrincipal -Times 1 -Exactly
        }
    }

    It 'does not mutate the input object' {
        InModuleScope Omnicit.EntraRBAC {
            $Declared = [PSCustomObject]@{
                scope = '/s'; role = 'Contributor'; requireApproval = $true
                approvers = [PSCustomObject]@{ users = @('person1@example.com') }
            }
            $null = Resolve-OERDeclaredApprover -Declared $Declared
            @($Declared.approvers.users) | Should -Be @('person1@example.com')
        }
    }

    It 'throws ApproverUnresolved with the resolver''s message and the value as target for an unresolvable user' {
        $Caught = InModuleScope Omnicit.EntraRBAC {
            $Declared = [PSCustomObject]@{
                scope = '/s'; role = 'Contributor'; requireApproval = $true
                approvers = [PSCustomObject]@{ users = @('person1@example.com', 'nobody@example.com') }
            }
            try { Resolve-OERDeclaredApprover -Declared $Declared; $null } catch { $PSItem }
        }
        $Caught.FullyQualifiedErrorId | Should -Be 'ApproverUnresolved'
        $Caught.CategoryInfo.Category | Should -Be 'ObjectNotFound'
        $Caught.TargetObject | Should -Be 'nobody@example.com'
        $Caught.Exception.Message | Should -Be "User 'nobody@example.com' was not found."
    }

    It 'keeps a declared empty users array declared and empty on the copy' {
        InModuleScope Omnicit.EntraRBAC {
            $Declared = [PSCustomObject]@{
                scope = '/s'; role = 'Contributor'; requireApproval = $true
                approvers = [PSCustomObject]@{ users = @() }
            }
            $Copy = Resolve-OERDeclaredApprover -Declared $Declared
            @($Copy.approvers.users).Count | Should -Be 0
            Test-OERDeclaredProperty -Node $Copy.approvers -Name 'users' | Should -Be $true
        }
    }
}

Describe 'Resolve-OERDeclaredApprover: only a principal that matches nothing is ApproverUnresolved (Sprint 8 step 3, BL-14)' {
    # The real Resolve-OERPrincipal runs here; only the lookups under it answer. The three apply
    # handlers report ApproverUnresolved as ApproverNotFound, an ambiguous name as
    # AmbiguousApproverName and anything else as itself, so this helper must hand them the three
    # shapes unmixed.
    It 'wraps the real resolver''s PrincipalUnresolved as ApproverUnresolved, keeping its message, the value as target and the cause' {
        $Caught = InModuleScope Omnicit.EntraRBAC {
            Mock Resolve-OERGroupId { $null }
            $Declared = '{ "role": "Reports Reader", "requireApproval": true, "approvers": { "groups": [ "missing-approvers" ] } }' | ConvertFrom-Json
            try { Resolve-OERDeclaredApprover -Declared $Declared; $null } catch { $PSItem }
        }
        $Caught.FullyQualifiedErrorId | Should -Be 'ApproverUnresolved'
        $Caught.CategoryInfo.Category | Should -Be 'ObjectNotFound'
        $Caught.TargetObject | Should -Be 'missing-approvers'
        $Caught.Exception.Message | Should -Be "Group 'missing-approvers' was not found."
        $Caught.Exception.InnerException.Message | Should -Be "Group 'missing-approvers' was not found."
    }

    It 'lets <Shape> through as it was thrown, never as ApproverUnresolved' -ForEach @(
        @{ Shape = 'an ambiguous group name'; Id = 'AmbiguousName'; Category = 'InvalidArgument'; Text = "Group display name 'dup-approvers' matches 2 groups (11111111-1111-1111-1111-111111111111, 22222222-2222-2222-2222-222222222222)." }
        @{ Shape = 'a refused (403) lookup'; Id = 'Authorization_RequestDenied'; Category = 'PermissionDenied'; Text = 'Authorization_RequestDenied: Insufficient privileges to complete the operation.' }
    ) {
        $Result = InModuleScope Omnicit.EntraRBAC -Parameters @{ Id = $Id; Category = $Category; Text = $Text } {
            param($Id, $Category, $Text)
            $script:BL14Thrown = [System.Exception]::new($Text)
            $script:BL14Id = $Id
            $script:BL14Category = $Category
            Mock Resolve-OERGroupId {
                throw [System.Management.Automation.ErrorRecord]::new(
                    $script:BL14Thrown, $script:BL14Id, [System.Management.Automation.ErrorCategory]$script:BL14Category, 'dup-approvers')
            }
            $Declared = '{ "role": "Reports Reader", "requireApproval": true, "approvers": { "groups": [ "dup-approvers" ] } }' | ConvertFrom-Json
            $Caught = try { Resolve-OERDeclaredApprover -Declared $Declared; $null } catch { $PSItem }
            [PSCustomObject]@{ Caught = $Caught; SameException = [object]::ReferenceEquals($Caught.Exception, $script:BL14Thrown) }
        }
        $Result.Caught.FullyQualifiedErrorId | Should -Be $Id
        $Result.Caught.CategoryInfo.Category | Should -Be $Category
        $Result.Caught.TargetObject | Should -Be 'dup-approvers'
        $Result.SameException | Should -BeTrue
    }

    It 'scrubs a failed lookup before it lets it through' {
        $Result = InModuleScope Omnicit.EntraRBAC {
            $script:BL14Thrown = [System.Exception]::new('Authorization_RequestDenied: Insufficient privileges to complete the operation.')
            Mock Resolve-OERPrincipal {
                throw [System.Management.Automation.ErrorRecord]::new(
                    $script:BL14Thrown, 'Authorization_RequestDenied', [System.Management.Automation.ErrorCategory]::PermissionDenied, 'person9@example.com')
            }
            Mock Remove-OERErrorRecord { }
            $Declared = '{ "role": "Reports Reader", "requireApproval": true, "approvers": { "users": [ "person9@example.com" ] } }' | ConvertFrom-Json
            $Caught = try { Resolve-OERDeclaredApprover -Declared $Declared; $null } catch { $PSItem }
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
