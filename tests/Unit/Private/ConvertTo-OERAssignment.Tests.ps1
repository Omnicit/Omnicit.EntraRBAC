BeforeAll {
    $script:moduleName = 'Omnicit.EntraRBAC'
    Get-Module $script:moduleName | Remove-Module -Force -ErrorAction SilentlyContinue
    Import-Module $script:moduleName -Force -ErrorAction Stop
}

Describe 'ConvertTo-OERAssignment' {
    It 'maps target, package, state and expiry and tags the type' {
        InModuleScope $script:moduleName {
            $Raw = @{
                id              = '00000000-0000-0000-0000-000000000051'
                state           = 'delivered'
                status          = 'Delivered'
                expiredDateTime = '2026-12-31T23:59:59Z'
                schedule        = @{
                    startDateTime = '2026-08-01T00:00:00Z'
                    expiration    = @{ endDateTime = '2026-12-31T23:59:59Z'; type = 'afterDateTime' }
                }
                target          = @{
                    id          = 'subject-record-id'
                    objectId    = 'aaaaaaaa-0000-0000-0000-000000000001'
                    displayName = 'Ada Lovelace'
                    email       = 'ada@contoso.com'
                }
                accessPackage   = @{ id = 'ap-1'; displayName = 'AP-OER-Demo' }
            }
            $Out = ConvertTo-OERAssignment -InputObject $Raw
            $Out.Id | Should -Be '00000000-0000-0000-0000-000000000051'
            $Out.TargetDisplayName | Should -Be 'Ada Lovelace'
            $Out.AccessPackageId | Should -Be 'ap-1'
            $Out.AccessPackageDisplayName | Should -Be 'AP-OER-Demo'
            $Out.AccessPackageName | Should -Be 'AP-OER-Demo'
            $Out.State | Should -Be 'delivered'
            $Out.PSObject.TypeNames[0] | Should -Be 'Omnicit.EntraRBAC.Assignment'
        }
    }

    It 'reads TargetId from target.objectId, not target.id, when both are present' {
        InModuleScope $script:moduleName {
            $Raw = @{
                id     = 'asg-objectid'
                state  = 'delivered'
                target = @{
                    id       = 'subject-record-id'
                    objectId = 'aaaaaaaa-0000-0000-0000-000000000001'
                }
            }
            $Out = ConvertTo-OERAssignment -InputObject $Raw
            $Out.TargetId | Should -Be 'aaaaaaaa-0000-0000-0000-000000000001'
            $Out.TargetId | Should -Not -Be 'subject-record-id'
        }
    }

    It 'falls back to target.id when target.objectId is absent' {
        InModuleScope $script:moduleName {
            $Raw = @{
                id     = 'asg-fallback'
                state  = 'delivered'
                target = @{ id = 'subject-record-id-only' }
            }
            $Out = ConvertTo-OERAssignment -InputObject $Raw
            $Out.TargetId | Should -Be 'subject-record-id-only'
        }
    }

    It 'falls back to .state when .assignmentState is absent' {
        InModuleScope $script:moduleName {
            $Raw = @{
                id     = 'asg-2'
                state  = 'partiallyDelivered'
                target = @{ objectId = 't-2'; displayName = 'Grace Hopper' }
                accessPackage = @{ id = 'ap-2'; displayName = 'AP-Engineering' }
            }
            $Out = ConvertTo-OERAssignment -InputObject $Raw
            $Out.State | Should -Be 'partiallyDelivered'
        }
    }

    It 'prefers .assignmentState over .state when both are present' {
        InModuleScope $script:moduleName {
            $Raw = @{
                id              = 'asg-both'
                assignmentState = 'Delivered'
                state           = 'delivered'
            }
            $Out = ConvertTo-OERAssignment -InputObject $Raw
            $Out.State | Should -Be 'Delivered'
        }
    }

    It 'reads ExpirationDateTime from the top-level expiredDateTime property' {
        InModuleScope $script:moduleName {
            $Raw = @{
                id              = 'asg-expired'
                expiredDateTime = '2026-12-31T23:59:59Z'
                schedule        = @{ expiration = @{ endDateTime = '2099-01-01T00:00:00Z' } }
            }
            $Out = ConvertTo-OERAssignment -InputObject $Raw
            $Out.ExpirationDateTime | Should -Be '2026-12-31T23:59:59Z'
        }
    }

    It 'falls back to schedule.expiration.endDateTime when expiredDateTime is absent' {
        InModuleScope $script:moduleName {
            $Raw = @{
                id       = 'asg-noexpired'
                schedule = @{
                    startDateTime = '2026-08-01T00:00:00Z'
                    expiration    = @{ endDateTime = '2026-12-31T23:59:59Z'; type = 'afterDateTime' }
                }
            }
            $Out = ConvertTo-OERAssignment -InputObject $Raw
            $Out.ExpirationDateTime | Should -Be '2026-12-31T23:59:59Z'
        }
    }

    It 'falls back to the beta-shaped schedule.stopDateTime as a last resort' {
        InModuleScope $script:moduleName {
            $Raw = @{
                id       = 'asg-beta'
                schedule = @{ stopDateTime = '2028-06-01T00:00:00Z' }
            }
            $Out = ConvertTo-OERAssignment -InputObject $Raw
            $Out.ExpirationDateTime | Should -Be '2028-06-01T00:00:00Z'
        }
    }

    It 'sets ExpirationDateTime to $null when no expiry field is present' {
        InModuleScope $script:moduleName {
            $Raw = @{
                id            = 'asg-3'
                state         = 'delivered'
                target        = @{ objectId = 't-3'; displayName = 'Alan Turing' }
                accessPackage = @{ id = 'ap-3'; displayName = 'AP-Research' }
            }
            $Out = ConvertTo-OERAssignment -InputObject $Raw
            $Out.ExpirationDateTime | Should -BeNullOrEmpty
        }
    }

    It 'accepts pipeline input' {
        InModuleScope $script:moduleName {
            $Raw = @{
                id              = 'asg-4'
                state           = 'delivered'
                target          = @{ objectId = 't-4'; displayName = 'Linus Torvalds' }
                accessPackage   = @{ id = 'ap-4'; displayName = 'AP-Infra' }
                expiredDateTime = '2028-06-01T00:00:00Z'
            }
            $Out = $Raw | ConvertTo-OERAssignment
            $Out.Id | Should -Be 'asg-4'
            $Out.PSObject.TypeNames[0] | Should -Be 'Omnicit.EntraRBAC.Assignment'
        }
    }

    It 'names the access package display name AccessPackageDisplayName' {
        InModuleScope $script:moduleName {
            $Out = ConvertTo-OERAssignment -InputObject @{
                id            = 'a1'
                state         = 'delivered'
                target        = @{ objectId = 't1'; displayName = 'Ada Lovelace' }
                accessPackage = @{ id = 'ap1'; displayName = 'AP-Sales' }
            }
            $Out.AccessPackageDisplayName | Should -Be 'AP-Sales'
            $Out.PSObject.Properties['AccessPackageDisplayName'].MemberType | Should -Be 'NoteProperty'
        }
    }

    It 'keeps AccessPackageName working as an alias' {
        InModuleScope $script:moduleName {
            $Out = ConvertTo-OERAssignment -InputObject @{ id = 'a1'; accessPackage = @{ id = 'ap1'; displayName = 'AP-Sales' } }
            $Out.AccessPackageName | Should -Be 'AP-Sales'
            $Out.PSObject.Properties['AccessPackageName'].MemberType | Should -Be 'AliasProperty'
        }
    }
}
