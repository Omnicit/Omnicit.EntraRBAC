BeforeAll {
    $script:moduleName = 'Omnicit.EntraRBAC'
    Get-Module $script:moduleName | Remove-Module -Force -ErrorAction SilentlyContinue
    Import-Module $script:moduleName -Force -ErrorAction Stop
}

Describe 'ConvertTo-OERAssignmentPolicy' {
    It 'maps properties and derives DurationInDays from an afterDuration expiration' {
        InModuleScope $script:moduleName {
            $Raw = @{
                id                 = 'pol-1'; displayName = 'Default'; accessPackage = @{ id = 'ap-1' }
                allowedTargetScope = 'allMemberUsers'
                expiration         = @{ type = 'afterDuration'; duration = 'P30D' }
            }
            $Out = ConvertTo-OERAssignmentPolicy -InputObject $Raw
            $Out.Id | Should -Be 'pol-1'
            $Out.AccessPackageId | Should -Be 'ap-1'
            $Out.AllowedTargetScope | Should -Be 'allMemberUsers'
            $Out.DurationInDays | Should -Be 30
            $Out.PSObject.TypeNames[0] | Should -Be 'Omnicit.EntraRBAC.AssignmentPolicy'
        }
    }

    It 'uses the -AccessPackageId override when the input has no expanded accessPackage' {
        InModuleScope $script:moduleName {
            $Out = ConvertTo-OERAssignmentPolicy -InputObject @{ id = 'pol-1'; displayName = 'Default' } -AccessPackageId 'ap-override'
            $Out.AccessPackageId | Should -Be 'ap-override'
        }
    }

    It 'leaves DurationInDays null for noExpiration' {
        InModuleScope $script:moduleName {
            $Out = ConvertTo-OERAssignmentPolicy -InputObject @{
                id          = 'p'
                displayName = 'd'
                expiration  = @{ type = 'noExpiration' }
            }
            $Out.DurationInDays | Should -BeNullOrEmpty
        }
    }

    It 'omits DurationInDays when an afterDuration truncates to a non-positive day count' {
        InModuleScope $script:moduleName {
            $Out = ConvertTo-OERAssignmentPolicy -InputObject @{
                id          = 'p'
                displayName = 'd'
                expiration  = @{ type = 'afterDuration'; duration = 'P0D' }
            }
            $Out.DurationInDays | Should -BeNullOrEmpty
        }
    }

    Context 'requestor scope and approval stages (PR3)' {
        It 'maps allowedTargetScope to a friendly RequestorScope.scope' {
            InModuleScope 'Omnicit.EntraRBAC' {
                $p = @{ id = 'pol-1'; displayName = 'Default'; allowedTargetScope = 'allMemberUsers' }
                (ConvertTo-OERAssignmentPolicy -InputObject $p).RequestorScope.scope | Should -Be 'AllMemberUsers'
            }
        }

        It 'maps notSpecified (None / admin-only) to the friendly NotSpecified so it round-trips' {
            InModuleScope 'Omnicit.EntraRBAC' {
                $p = @{ id = 'pol-1'; displayName = 'AdminOnly'; allowedTargetScope = 'notSpecified' }
                (ConvertTo-OERAssignmentPolicy -InputObject $p).RequestorScope.scope | Should -Be 'NotSpecified'
            }
        }

        It 'maps allConfiguredConnectedOrganizationUsers to its friendly form' {
            InModuleScope 'Omnicit.EntraRBAC' {
                $p = @{ id = 'pol-1'; displayName = 'Conn'; allowedTargetScope = 'allConfiguredConnectedOrganizationUsers' }
                (ConvertTo-OERAssignmentPolicy -InputObject $p).RequestorScope.scope | Should -Be 'AllConfiguredConnectedOrganizationUsers'
            }
        }

        It 'an unknown future allowedTargetScope still passes through unchanged' {
            InModuleScope 'Omnicit.EntraRBAC' {
                $p = @{ id = 'pol-1'; displayName = 'Future'; allowedTargetScope = 'someFutureScope' }
                (ConvertTo-OERAssignmentPolicy -InputObject $p).RequestorScope.scope | Should -Be 'someFutureScope'
            }
        }

        It 'projects approval stages with durationDays and a manager flag' {
            InModuleScope 'Omnicit.EntraRBAC' {
                $p = @{
                    id = 'pol-1'; displayName = 'Default'; allowedTargetScope = 'allMemberUsers'
                    requestApprovalSettings = @{
                        stages = @(@{ durationBeforeAutomaticDenial = 'P7D'; primaryApprovers = @(@{ '@odata.type' = '#microsoft.graph.requestorManager' }) })
                    }
                }
                $stages = @((ConvertTo-OERAssignmentPolicy -InputObject $p).ApprovalStages)
                $stages.Count | Should -Be 1
                $stages[0].durationDays | Should -Be 7
                $stages[0].manager | Should -BeTrue
            }
        }

        It 'projects managerLevel 3 when requestorManager has managerLevel=3' {
            InModuleScope 'Omnicit.EntraRBAC' {
                $p = @{
                    id = 'pol-1'; displayName = 'Default'; allowedTargetScope = 'allMemberUsers'
                    requestApprovalSettings = @{
                        stages = @(@{ durationBeforeAutomaticDenial = 'P7D'; primaryApprovers = @(@{ '@odata.type' = '#microsoft.graph.requestorManager'; managerLevel = 3 }) })
                    }
                }
                $stages = @((ConvertTo-OERAssignmentPolicy -InputObject $p).ApprovalStages)
                $stages[0].manager | Should -BeTrue
                $stages[0].managerLevel | Should -Be 3
            }
        }

        It 'reports manager false for a non-manager approver stage' {
            InModuleScope 'Omnicit.EntraRBAC' {
                $p = @{
                    id = 'pol-1'; displayName = 'Default'; allowedTargetScope = 'allMemberUsers'
                    requestApprovalSettings = @{
                        stages = @(@{ durationBeforeAutomaticDenial = 'P14D'; primaryApprovers = @(@{ '@odata.type' = '#microsoft.graph.singleUser'; userId = 'u-1' }) })
                    }
                }
                $stages = @((ConvertTo-OERAssignmentPolicy -InputObject $p).ApprovalStages)
                $stages[0].manager | Should -BeFalse
                $stages[0].durationDays | Should -Be 14
            }
        }

        It 'returns an empty ApprovalStages array when there are no stages' {
            InModuleScope 'Omnicit.EntraRBAC' {
                $p = @{ id = 'pol-1'; displayName = 'Default'; allowedTargetScope = 'allMemberUsers' }
                @((ConvertTo-OERAssignmentPolicy -InputObject $p).ApprovalStages).Count | Should -Be 0
            }
        }
    }
}

Describe 'ConvertTo-OERAssignmentPolicy (full normalizer)' {
    It 'projects all granular fields' {
        InModuleScope Omnicit.EntraRBAC {
            $raw = @{
                id = 'p'; displayName = 'D'; description = 'desc'; allowedTargetScope = 'specificDirectoryUsers'
                specificAllowedTargets = @(
                    @{ '@odata.type' = '#microsoft.graph.singleUser'; userId = 'AAA11111-1111-1111-1111-111111111111' }
                    @{ '@odata.type' = '#microsoft.graph.groupMembers'; groupId = 'BBB22222-2222-2222-2222-222222222222' })
                requestorSettings = @{ enableTargetsToSelfAddAccess = $true; enableOnBehalfRequestorsToAddAccess = $true; onBehalfRequestors = @(@{ '@odata.type' = '#microsoft.graph.requestorManager'; managerLevel = 2 }); allowCustomAssignmentSchedule = $true; enableTargetsToSelfUpdateAccess = $true; enableTargetsToSelfRemoveAccess = $true; enableOnBehalfRequestorsToUpdateAccess = $true; enableOnBehalfRequestorsToRemoveAccess = $true }
                requestApprovalSettings = @{ isApprovalRequiredForAdd = $true; isApprovalRequiredForUpdate = $true; isRequestorJustificationRequired = $true; stages = @(
                        @{ durationBeforeAutomaticDenial = 'P7D'; isApproverJustificationRequired = $true; approverInformationVisibility = 'visible'; isEscalationEnabled = $true; durationBeforeEscalation = 'P3D'; primaryApprovers = @(@{ '@odata.type' = '#microsoft.graph.requestorManager'; managerLevel = 1 }, @{ '@odata.type' = '#microsoft.graph.singleUser'; userId = 'CCC33333-3333-3333-3333-333333333333' }); escalationApprovers = @(@{ '@odata.type' = '#microsoft.graph.groupMembers'; groupId = 'DDD44444-4444-4444-4444-444444444444' }); fallbackPrimaryApprovers = @(@{ '@odata.type' = '#microsoft.graph.singleUser'; userId = 'EEE55555-5555-5555-5555-555555555555' }, @{ '@odata.type' = '#microsoft.graph.groupMembers'; groupId = 'FFF66666-6666-6666-6666-666666666666' }) }) }
                expiration = @{ type = 'afterDuration'; duration = 'PT8H' }
                notificationSettings = @{ isAssignmentNotificationDisabled = $true }
            }
            $p = ConvertTo-OERAssignmentPolicy -InputObject $raw -AccessPackageId 'ap'
            $p.Description | Should -Be 'desc'
            $p.RequestorScope.users | Should -Contain 'aaa11111-1111-1111-1111-111111111111'
            $p.RequestorScope.groups | Should -Contain 'bbb22222-2222-2222-2222-222222222222'
            $p.RequestorSettings.allowSelfRequest | Should -BeTrue
            $p.RequestorSettings.allowManagerRequest | Should -BeTrue
            $p.RequestorSettings.managerLevel | Should -Be 2
            $p.RequestorSettings.allowCustomSchedule | Should -BeTrue
            $p.RequestorSettings.allowSelfExtend | Should -BeTrue
            $p.RequestorSettings.allowSelfRemove | Should -BeTrue
            $p.RequestorSettings.allowOnBehalfUpdate | Should -BeTrue
            $p.RequestorSettings.allowOnBehalfRemove | Should -BeTrue
            $p.RequireApproval | Should -BeTrue
            $p.RequireApprovalForUpdate | Should -BeTrue
            $p.RequireRequestorJustification | Should -BeTrue
            $s = @($p.ApprovalStages)[0]
            $s.manager | Should -BeTrue
            $s.managerLevel | Should -Be 1
            $s.users | Should -Contain 'ccc33333-3333-3333-3333-333333333333'
            $s.alternateGroups | Should -Contain 'ddd44444-4444-4444-4444-444444444444'
            $s.fallbackUsers | Should -Contain 'eee55555-5555-5555-5555-555555555555'
            $s.fallbackGroups | Should -Contain 'fff66666-6666-6666-6666-666666666666'
            $s.escalationDays | Should -Be 3
            $s.approverInfoVisibility | Should -Be 'Visible'
            $s.requireApproverJustification | Should -BeTrue
            $p.DurationInHours | Should -Be 8
            $p.DurationInDays | Should -BeNullOrEmpty
            $p.NotificationsDisabled | Should -BeTrue
        }
    }
    It 'noExpiration projects all expiration fields null' {
        InModuleScope Omnicit.EntraRBAC {
            $p = ConvertTo-OERAssignmentPolicy -InputObject @{ id = 'p'; expiration = @{ type = 'noExpiration' } } -AccessPackageId 'ap'
            $p.DurationInDays | Should -BeNullOrEmpty
            $p.DurationInHours | Should -BeNullOrEmpty
            $p.ExpirationDateTime | Should -BeNullOrEmpty
        }
    }
    It 'absent approverInformationVisibility -> Default; back-compat scope+stage' {
        InModuleScope Omnicit.EntraRBAC {
            $p = ConvertTo-OERAssignmentPolicy -InputObject @{ id = 'p'; allowedTargetScope = 'allMemberUsers'; requestApprovalSettings = @{ stages = @(@{ durationBeforeAutomaticDenial = 'P5D'; primaryApprovers = @(@{ '@odata.type' = '#microsoft.graph.requestorManager'; managerLevel = 1 }) }) } } -AccessPackageId 'ap'
            $p.RequestorScope.scope | Should -Be 'AllMemberUsers'
            $s = @($p.ApprovalStages)[0]
            $s.durationDays | Should -Be 5
            $s.manager | Should -BeTrue
            $s.approverInfoVisibility | Should -Be 'Default'
        }
    }
    It 'afterDateTime projects ExpirationDateTime' {
        InModuleScope Omnicit.EntraRBAC {
            $p = ConvertTo-OERAssignmentPolicy -InputObject @{ id = 'p'; expiration = @{ type = 'afterDateTime'; endDateTime = '2027-01-01T00:00:00Z' } } -AccessPackageId 'ap'
            $p.ExpirationDateTime | Should -Be '2027-01-01T00:00:00Z'
        }
    }
    It 'sorts and lowercases requestor scope and stage GUID lists' {
        InModuleScope Omnicit.EntraRBAC {
            $raw = @{
                id = 'p'; allowedTargetScope = 'specificDirectoryUsers'
                specificAllowedTargets = @(
                    @{ '@odata.type' = '#microsoft.graph.singleUser'; userId = 'FFF11111-1111-1111-1111-111111111111' }
                    @{ '@odata.type' = '#microsoft.graph.singleUser'; userId = 'AAA11111-1111-1111-1111-111111111111' })
                requestApprovalSettings = @{ stages = @(@{ durationBeforeAutomaticDenial = 'P1D'; primaryApprovers = @(
                                @{ '@odata.type' = '#microsoft.graph.internalSponsors' }
                                @{ '@odata.type' = '#microsoft.graph.externalSponsors' }) }) }
            }
            $p = ConvertTo-OERAssignmentPolicy -InputObject $raw -AccessPackageId 'ap'
            @($p.RequestorScope.users)[0] | Should -Be 'aaa11111-1111-1111-1111-111111111111'
            @($p.RequestorScope.users)[1] | Should -Be 'fff11111-1111-1111-1111-111111111111'
            $s = @($p.ApprovalStages)[0]
            $s.internalSponsor | Should -BeTrue
            $s.externalSponsor | Should -BeTrue
        }
    }
    It 'projects empty RequestorScope users/groups arrays when no specific targets' {
        InModuleScope Omnicit.EntraRBAC {
            $p = ConvertTo-OERAssignmentPolicy -InputObject @{ id = 'p'; allowedTargetScope = 'allMemberUsers' } -AccessPackageId 'ap'
            @($p.RequestorScope.users).Count | Should -Be 0
            @($p.RequestorScope.groups).Count | Should -Be 0
        }
    }
    It 'defaults RequestorSettings to all-false managerLevel 1 when absent' {
        InModuleScope Omnicit.EntraRBAC {
            $p = ConvertTo-OERAssignmentPolicy -InputObject @{ id = 'p'; allowedTargetScope = 'allMemberUsers' } -AccessPackageId 'ap'
            $p.RequestorSettings.allowSelfRequest | Should -BeFalse
            $p.RequestorSettings.allowManagerRequest | Should -BeFalse
            $p.RequestorSettings.managerLevel | Should -Be 1
            $p.RequestorSettings.allowCustomSchedule | Should -BeFalse
            $p.RequestorSettings.allowSelfExtend | Should -BeFalse
            $p.RequestorSettings.allowSelfRemove | Should -BeFalse
            $p.RequestorSettings.allowOnBehalfUpdate | Should -BeFalse
            $p.RequestorSettings.allowOnBehalfRemove | Should -BeFalse
        }
    }

    It 'projects allowSelfRemove, allowOnBehalfUpdate and allowOnBehalfRemove from the matching Graph keys' {
        InModuleScope Omnicit.EntraRBAC {
            $raw = @{
                id = 'p'; allowedTargetScope = 'allMemberUsers'
                requestorSettings = @{
                    enableTargetsToSelfRemoveAccess        = $true
                    enableOnBehalfRequestorsToUpdateAccess = $true
                    enableOnBehalfRequestorsToRemoveAccess = $true
                }
            }
            $p = ConvertTo-OERAssignmentPolicy -InputObject $raw -AccessPackageId 'ap'
            $p.RequestorSettings.allowSelfRemove | Should -BeTrue
            $p.RequestorSettings.allowOnBehalfUpdate | Should -BeTrue
            $p.RequestorSettings.allowOnBehalfRemove | Should -BeTrue
        }
    }

    It 'projects fallbackUsers and fallbackGroups from a stage''s fallbackPrimaryApprovers' {
        InModuleScope Omnicit.EntraRBAC {
            $raw = @{
                id = 'p'; allowedTargetScope = 'allMemberUsers'
                requestApprovalSettings = @{ stages = @(
                        @{
                            durationBeforeAutomaticDenial = 'P7D'
                            primaryApprovers               = @(@{ '@odata.type' = '#microsoft.graph.requestorManager'; managerLevel = 1 })
                            fallbackPrimaryApprovers        = @(
                                @{ '@odata.type' = '#microsoft.graph.singleUser'; userId = 'AAA11111-1111-1111-1111-111111111111' }
                                @{ '@odata.type' = '#microsoft.graph.groupMembers'; groupId = 'BBB22222-2222-2222-2222-222222222222' }
                            )
                        }
                    )
                }
            }
            $p = ConvertTo-OERAssignmentPolicy -InputObject $raw -AccessPackageId 'ap'
            $s = @($p.ApprovalStages)[0]
            $s.fallbackUsers | Should -Contain 'aaa11111-1111-1111-1111-111111111111'
            $s.fallbackGroups | Should -Contain 'bbb22222-2222-2222-2222-222222222222'
        }
    }

    It 'projects empty fallbackUsers/fallbackGroups when the stage has no fallbackPrimaryApprovers' {
        InModuleScope Omnicit.EntraRBAC {
            $raw = @{
                id = 'p'; allowedTargetScope = 'allMemberUsers'
                requestApprovalSettings = @{ stages = @(
                        @{ durationBeforeAutomaticDenial = 'P7D'; primaryApprovers = @(@{ '@odata.type' = '#microsoft.graph.requestorManager'; managerLevel = 1 }) }
                    )
                }
            }
            $p = ConvertTo-OERAssignmentPolicy -InputObject $raw -AccessPackageId 'ap'
            $s = @($p.ApprovalStages)[0]
            @($s.fallbackUsers).Count | Should -Be 0
            @($s.fallbackGroups).Count | Should -Be 0
        }
    }
    It 'projects whole-day afterDuration as DurationInDays and leaves DurationInHours null' {
        InModuleScope Omnicit.EntraRBAC {
            $p = ConvertTo-OERAssignmentPolicy -InputObject @{ id = 'p'; expiration = @{ type = 'afterDuration'; duration = 'P30D' } } -AccessPackageId 'ap'
            $p.DurationInDays | Should -Be 30
            $p.DurationInHours | Should -BeNullOrEmpty
        }
    }
    It 'projects escalationDays null when escalation is disabled' {
        InModuleScope Omnicit.EntraRBAC {
            $raw = @{ id = 'p'; requestApprovalSettings = @{ stages = @(@{ durationBeforeAutomaticDenial = 'P7D'; isEscalationEnabled = $false; durationBeforeEscalation = 'P3D'; primaryApprovers = @(@{ '@odata.type' = '#microsoft.graph.singleUser'; userId = 'AAA11111-1111-1111-1111-111111111111' }) }) } }
            $p = ConvertTo-OERAssignmentPolicy -InputObject $raw -AccessPackageId 'ap'
            @($p.ApprovalStages)[0].escalationDays | Should -BeNullOrEmpty
        }
    }

    It 'scrubs the bearer-hygiene record when the expiration duration is unparseable' {
        InModuleScope Omnicit.EntraRBAC {
            Mock Remove-OERErrorRecord { }
            $Out = ConvertTo-OERAssignmentPolicy -InputObject @{
                id         = 'p'
                expiration = @{ type = 'afterDuration'; duration = 'not-a-duration' }
            } -AccessPackageId 'ap'
            $Out.DurationInDays | Should -BeNullOrEmpty
            Should -Invoke Remove-OERErrorRecord -Times 1
        }
    }
}
