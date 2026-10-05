BeforeAll {
    Import-Module Omnicit.EntraRBAC -Force
    . "$PSScriptRoot/../TestHelpers/OERTransportTripwire.ps1"
    Install-OERTransportTripwire
}

AfterAll {
    try { Assert-OERTransportTripwire } finally { Uninstall-OERTransportTripwire }
}

Describe 'Resolve-OERPrincipal' {
    It 'resolves a user UPN through Resolve-OERUserId and tags PrincipalType User' {
        InModuleScope Omnicit.EntraRBAC {
            Mock Resolve-OERUserId { 'aaaa0000-0000-0000-0000-000000000001' }
            $Out = Resolve-OERPrincipal -User 'anna@contoso.com'
            $Out.PrincipalId | Should -Be 'aaaa0000-0000-0000-0000-000000000001'
            $Out.PrincipalType | Should -Be 'User'
        }
    }

    It 'resolves a group display name through Resolve-OERGroupId and tags PrincipalType Group' {
        InModuleScope Omnicit.EntraRBAC {
            Mock Resolve-OERGroupId { 'bbbb0000-0000-0000-0000-000000000002' }
            $Out = Resolve-OERPrincipal -Group 'role_sec_admins'
            $Out.PrincipalId | Should -Be 'bbbb0000-0000-0000-0000-000000000002'
            $Out.PrincipalType | Should -Be 'Group'
        }
    }

    It 'treats a service principal GUID as the object id without a Graph call' {
        InModuleScope Omnicit.EntraRBAC {
            Mock Resolve-OERApplicationId { throw 'should not be called' }
            $Out = Resolve-OERPrincipal -ServicePrincipal 'cccc0000-0000-0000-0000-000000000003'
            $Out.PrincipalId | Should -Be 'cccc0000-0000-0000-0000-000000000003'
            $Out.PrincipalType | Should -Be 'ServicePrincipal'
            Should -Invoke Resolve-OERApplicationId -Times 0 -Exactly
        }
    }

    It 'resolves a service principal display name through Resolve-OERApplicationId' {
        InModuleScope Omnicit.EntraRBAC {
            Mock Resolve-OERApplicationId { 'dddd0000-0000-0000-0000-000000000004' }
            $Out = Resolve-OERPrincipal -ServicePrincipal 'Contoso Automation'
            $Out.PrincipalId | Should -Be 'dddd0000-0000-0000-0000-000000000004'
            $Out.PrincipalType | Should -Be 'ServicePrincipal'
        }
    }

    It 'throws on not-found and on ambiguous/missing input' {
        InModuleScope Omnicit.EntraRBAC {
            Mock Resolve-OERUserId { $null }
            { Resolve-OERPrincipal -User 'ghost@contoso.com' } | Should -Throw "*'ghost@contoso.com'*"
            { Resolve-OERPrincipal } | Should -Throw '*requires one of*'
            { Resolve-OERPrincipal -User 'a' -Group 'b' } | Should -Throw '*only one of*'
        }
    }

    Context 'a principal that matches nothing is a typed record, a failed lookup is not (Sprint 8 step 3, BL-14)' {
        # The approver resolvers tell "matches nothing" apart from a lookup that failed by this record's
        # id; every other caller reads only its message, which is why that text must not change.
        It 'throws PrincipalUnresolved (ObjectNotFound, the value as target, the message it always had) when a <Kind> matches nothing' -ForEach @(
            @{ Kind = 'User'; Resolver = 'Resolve-OERUserId'; Value = 'ghost@example.com'; Message = "User 'ghost@example.com' was not found." }
            @{ Kind = 'Group'; Resolver = 'Resolve-OERGroupId'; Value = 'No Such Group'; Message = "Group 'No Such Group' was not found." }
            @{ Kind = 'ServicePrincipal'; Resolver = 'Resolve-OERApplicationId'; Value = 'No Such App'; Message = "Service principal 'No Such App' was not found." }
        ) {
            $Caught = InModuleScope Omnicit.EntraRBAC -Parameters @{ Kind = $Kind; Resolver = $Resolver; Value = $Value } {
                param($Kind, $Resolver, $Value)
                Mock -CommandName $Resolver -MockWith { $null }
                $Splat = @{ $Kind = $Value }
                try { Resolve-OERPrincipal @Splat; $null } catch { $PSItem }
            }
            $Caught | Should -Not -BeNullOrEmpty
            $Caught.FullyQualifiedErrorId | Should -Be 'PrincipalUnresolved'
            $Caught.CategoryInfo.Category | Should -Be 'ObjectNotFound'
            $Caught.TargetObject | Should -Be $Value
            $Caught.Exception.Message | Should -Be $Message
        }

        It 'lets an ambiguous <Kind> display name through as the resolver threw it, never as PrincipalUnresolved' -ForEach @(
            @{ Kind = 'Group'; Resolver = 'Resolve-OERGroupId' }
            @{ Kind = 'ServicePrincipal'; Resolver = 'Resolve-OERApplicationId' }
        ) {
            $Result = InModuleScope Omnicit.EntraRBAC -Parameters @{ Kind = $Kind; Resolver = $Resolver } {
                param($Kind, $Resolver)
                $script:BL14Thrown = [System.Exception]::new(
                    "Display name 'Dup' matches 2 objects (11111111-1111-1111-1111-111111111111, 22222222-2222-2222-2222-222222222222).")
                Mock -CommandName $Resolver -MockWith {
                    throw [System.Management.Automation.ErrorRecord]::new(
                        $script:BL14Thrown, 'AmbiguousName', [System.Management.Automation.ErrorCategory]::InvalidArgument, 'Dup')
                }
                $Splat = @{ $Kind = 'Dup' }
                $Caught = try { Resolve-OERPrincipal @Splat; $null } catch { $PSItem }
                [PSCustomObject]@{ Caught = $Caught; SameException = [object]::ReferenceEquals($Caught.Exception, $script:BL14Thrown) }
            }
            $Result.Caught.FullyQualifiedErrorId | Should -Be 'AmbiguousName'
            $Result.Caught.TargetObject | Should -Be 'Dup'
            $Result.SameException | Should -BeTrue
        }

        It 'lets a failed lookup through as the resolver threw it: a 403 is never PrincipalUnresolved' {
            $Result = InModuleScope Omnicit.EntraRBAC {
                $script:BL14Thrown = [System.Exception]::new('Authorization_RequestDenied: Insufficient privileges to complete the operation.')
                Mock Resolve-OERUserId {
                    throw [System.Management.Automation.ErrorRecord]::new(
                        $script:BL14Thrown, 'Authorization_RequestDenied', [System.Management.Automation.ErrorCategory]::PermissionDenied, 'person9@example.com')
                }
                $Caught = try { Resolve-OERPrincipal -User 'person9@example.com'; $null } catch { $PSItem }
                [PSCustomObject]@{ Caught = $Caught; SameException = [object]::ReferenceEquals($Caught.Exception, $script:BL14Thrown) }
            }
            $Result.Caught.FullyQualifiedErrorId | Should -Be 'Authorization_RequestDenied'
            $Result.Caught.CategoryInfo.Category | Should -Be 'PermissionDenied'
            $Result.SameException | Should -BeTrue
        }

        It 'keeps the two caller-error throws as plain messages, never PrincipalUnresolved' {
            $Ids = InModuleScope Omnicit.EntraRBAC {
                foreach ($Splat in @(@{}, @{ User = 'a'; Group = 'b' })) {
                    try { Resolve-OERPrincipal @Splat } catch { [string]$PSItem.FullyQualifiedErrorId }
                }
            }
            @($Ids).Count | Should -Be 2
            @($Ids | Where-Object { $_ -like 'PrincipalUnresolved*' }).Count | Should -Be 0
        }
    }
}
