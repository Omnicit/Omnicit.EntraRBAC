BeforeAll {
    Import-Module Omnicit.EntraRBAC -Force
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
                if (-not $Map.ContainsKey($Key)) { if ($User) { throw "User '$User' was not found." } else { throw "Group '$Group' was not found." } }
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

    It 'throws a message containing was not found for an unresolvable user' {
        InModuleScope Omnicit.EntraRBAC {
            $Declared = [PSCustomObject]@{
                scope = '/s'; role = 'Contributor'; requireApproval = $true
                approvers = [PSCustomObject]@{ users = @('nobody@example.com') }
            }
            { Resolve-OERDeclaredApprover -Declared $Declared } | Should -Throw '*was not found*'
        }
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
