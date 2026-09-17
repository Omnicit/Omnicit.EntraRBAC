BeforeAll {
    $script:moduleName = 'Omnicit.EntraRBAC'
    Get-Module $script:moduleName | Remove-Module -Force -ErrorAction SilentlyContinue
    Import-Module $script:moduleName -Force -ErrorAction Stop
}

Describe 'ConvertTo-OERAccessReviewDefinition' {
    It 'tags and maps a raw definition' {
        InModuleScope $script:moduleName {
            $raw = @{
                id                      = 'd1'
                displayName             = 'Q3'
                status                  = 'InProgress'
                descriptionForAdmins    = 'a'
                descriptionForReviewers = 'r'
                createdDateTime         = '2026-07-01T00:00:00Z'
                scope                   = @{ query = '/identityGovernance/entitlementManagement/accessPackageAssignments?...' }
                reviewers               = @(@{ query = '/users/x' })
                settings                = @{ instanceDurationInDays = 14 }
                stageSettings           = @(@{ stageId = '1' }, @{ stageId = '2' })
            }
            $o = ConvertTo-OERAccessReviewDefinition -InputObject $raw
            $o.PSObject.TypeNames[0] | Should -Be 'Omnicit.EntraRBAC.AccessReviewDefinition'
            $o.Id | Should -Be 'd1'
            $o.Status | Should -Be 'InProgress'
            $o.StageCount | Should -Be 2
        }
    }

    It 'exposes AccessReviewDefinitionId equal to Id for pipeline binding' {
        InModuleScope $script:moduleName {
            $raw = @{
                id                      = 'def-pipeline-1'
                displayName             = 'Pipeline'
                status                  = 'NotStarted'
                scope                   = @{ query = '/some/query' }
                settings                = @{ instanceDurationInDays = 7 }
            }
            $o = ConvertTo-OERAccessReviewDefinition -InputObject $raw
            $o.AccessReviewDefinitionId | Should -Be 'def-pipeline-1'
            $o.AccessReviewDefinitionId | Should -Be $o.Id
        }
    }

    It 'stores Id as an AliasProperty of AccessReviewDefinitionId, not a second copy (Task 8a)' {
        InModuleScope $script:moduleName {
            $o = ConvertTo-OERAccessReviewDefinition -InputObject @{ id = 'def-alias-1'; displayName = 'X' }

            # MemberType, not just value: a silently-absent alias (e.g. a swallowed Update-TypeData
            # registration failure) would read $null the same as a present-and-null alias, so pinning
            # the value alone would not catch a dropped registration.
            ($o.PSObject.Properties | Where-Object MemberType -eq 'NoteProperty').Name |
                Should -Not -Contain 'Id' -Because 'Id must be the AliasProperty registered in suffix.ps1, not a second stored copy'
            $o.PSObject.Properties['Id'].MemberType | Should -Be 'AliasProperty'
            $o.PSObject.Properties['Id'].ReferencedMemberName | Should -Be 'AccessReviewDefinitionId'
            $o.Id | Should -Be 'def-alias-1'
        }
    }

    It 'pipes into Remove-OERAccessReviewDefinition -Id, proving the AliasProperty resolves on a real downstream consumer (Task 8a)' {
        <#
            Remove-OERAccessReviewDefinition's -Id parameter's OWN canonical name is 'Id' (its alias
            is the domain-specific AccessReviewDefinitionId, the opposite direction from most other
            consumers in this sweep) -- so ValueFromPipelineByPropertyName resolves it by matching
            'Id' directly against the piped object's property names FIRST, before ever consulting the
            parameter's own alias list. This is the one real downstream site where the AliasProperty
            this test file's converter now emits is the exact thing being bound through, not merely
            preserved alongside an unrelated stored property.
        #>
        Mock -ModuleName Omnicit.EntraRBAC Initialize-OERAuth { }
        Mock -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest { }

        InModuleScope Omnicit.EntraRBAC {
            $Definition = ConvertTo-OERAccessReviewDefinition -InputObject @{ id = 'def-pipe-1'; displayName = 'Piped' }
            $Definition | Remove-OERAccessReviewDefinition -Confirm:$false
        }

        Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest -Exactly -Times 1 -ParameterFilter {
            $Method -eq 'DELETE' -and $Uri -eq 'v1.0/identityGovernance/accessReviews/definitions/def-pipe-1'
        }
    }

    It 'maps Scope from scope.query' {
        InModuleScope $script:moduleName {
            $raw = @{
                id                      = 'd2'
                displayName             = 'Quarterly'
                status                  = 'NotStarted'
                descriptionForAdmins    = ''
                descriptionForReviewers = ''
                createdDateTime         = '2026-07-01T00:00:00Z'
                scope                   = @{ query = '/identityGovernance/entitlementManagement/accessPackageAssignments?$filter=...' }
                reviewers               = @(@{ query = '/users/a' }, @{ query = '/users/b' })
                settings                = @{ instanceDurationInDays = 7 }
                stageSettings           = @()
            }
            $o = ConvertTo-OERAccessReviewDefinition -InputObject $raw
            $o.Scope | Should -Be '/identityGovernance/entitlementManagement/accessPackageAssignments?$filter=...'
            $o.ReviewerCount | Should -Be 2
            $o.StageCount | Should -Be 0
        }
    }

    It 'accepts pipeline input' {
        InModuleScope $script:moduleName {
            $raw = @{
                id                      = 'd3'
                displayName             = 'Annual'
                status                  = 'Completed'
                descriptionForAdmins    = 'admin desc'
                descriptionForReviewers = 'reviewer desc'
                createdDateTime         = '2026-01-01T00:00:00Z'
                scope                   = @{ query = '/some/query' }
                reviewers               = @()
                settings                = @{ instanceDurationInDays = 30 }
                stageSettings           = @(@{ stageId = '1' })
            }
            $o = $raw | ConvertTo-OERAccessReviewDefinition
            $o.PSObject.TypeNames[0] | Should -Be 'Omnicit.EntraRBAC.AccessReviewDefinition'
            $o.DisplayName | Should -Be 'Annual'
            $o.DescriptionForAdmins | Should -Be 'admin desc'
        }
    }

    It 'maps DescriptionForReviewers, CreatedDateTime, and Settings.instanceDurationInDays' {
        InModuleScope $script:moduleName {
            $raw = @{
                id                      = 'd4'
                displayName             = 'Mapping check'
                status                  = 'NotStarted'
                descriptionForAdmins    = 'admin note'
                descriptionForReviewers = 'reviewer note'
                createdDateTime         = '2025-03-15T08:30:00Z'
                scope                   = @{ query = '/some/path' }
                reviewers               = @(@{ query = '/users/z' })
                settings                = @{ instanceDurationInDays = 21 }
                stageSettings           = @()
            }
            $o = ConvertTo-OERAccessReviewDefinition -InputObject $raw
            $o.DescriptionForReviewers | Should -Be 'reviewer note'
            $o.CreatedDateTime | Should -Be '2025-03-15T08:30:00Z'
            $o.Settings.instanceDurationInDays | Should -Be 21
        }
    }

    It 'yields StageCount 0 and ReviewerCount 0 when stageSettings and reviewers are absent' {
        InModuleScope $script:moduleName {
            $raw = @{
                id          = 'd5'
                displayName = 'Minimal'
                status      = 'NotStarted'
                scope       = @{ query = '/some/path' }
                settings    = @{ instanceDurationInDays = 7 }
            }
            $o = ConvertTo-OERAccessReviewDefinition -InputObject $raw
            $o.ReviewerCount | Should -Be 0
            $o.StageCount | Should -Be 0
        }
    }

    Context 'round-trip fields (PR3)' {
        It 'parses accessPackageId and assignmentPolicyId from the v1.0 scope query (relationship filter)' {
            InModuleScope 'Omnicit.EntraRBAC' {
                $def = @{
                    id = 'ar-1'; displayName = 'Quarterly'
                    scope = @{ query = "/identityGovernance/entitlementManagement/assignments?`$filter=accessPackage/id eq 'ap-9' and assignmentPolicy/id eq 'pol-9'" }
                }
                $out = ConvertTo-OERAccessReviewDefinition -InputObject $def
                $out.AccessPackageId | Should -Be 'ap-9'
                $out.AssignmentPolicyId | Should -Be 'pol-9'
            }
        }

        It 'still parses a legacy beta scope query (scalar accessPackageId/assignmentPolicyId)' {
            InModuleScope 'Omnicit.EntraRBAC' {
                $def = @{
                    id = 'ar-1'; displayName = 'Quarterly'
                    scope = @{ query = "/identityGovernance/entitlementManagement/accessPackageAssignments?`$filter=(accessPackageId eq 'ap-9' and assignmentPolicyId eq 'pol-9' and catalogId eq 'cat-9')" }
                }
                $out = ConvertTo-OERAccessReviewDefinition -InputObject $def
                $out.AccessPackageId | Should -Be 'ap-9'
                $out.AssignmentPolicyId | Should -Be 'pol-9'
            }
        }

        It 'surfaces reviewers, recurrence and durationInDays from settings' {
            InModuleScope 'Omnicit.EntraRBAC' {
                $def = @{
                    id = 'ar-1'; displayName = 'Quarterly'
                    scope = @{ query = "accessPackageId eq 'ap-9' and assignmentPolicyId eq 'pol-9'" }
                    reviewers = @(@{ query = './manager'; queryType = 'MicrosoftGraph'; queryRoot = 'decisions' })
                    fallbackReviewers = @(@{ query = '/users/fb-1'; queryType = 'MicrosoftGraph' })
                    settings = @{
                        instanceDurationInDays = 14
                        recurrence = @{ pattern = @{ type = 'absoluteMonthly'; interval = 3 }; range = @{ type = 'noEnd'; startDate = '2026-07-01' } }
                    }
                }
                $out = ConvertTo-OERAccessReviewDefinition -InputObject $def
                @($out.Reviewers).Count | Should -Be 1
                $out.Reviewers[0].query | Should -Be './manager'
                @($out.FallbackReviewers).Count | Should -Be 1
                $out.FallbackReviewers[0].query | Should -Be '/users/fb-1'
                $out.Recurrence.pattern.type | Should -Be 'absoluteMonthly'
                $out.DurationInDays | Should -Be 14
            }
        }

        It 'tolerates a definition with no scope/reviewers/recurrence (one-time, self-review)' {
            InModuleScope 'Omnicit.EntraRBAC' {
                $out = ConvertTo-OERAccessReviewDefinition -InputObject @{ id = 'ar-2'; displayName = 'X' }
                $out.AccessPackageId | Should -BeNullOrEmpty
                @($out.Reviewers).Count | Should -Be 0
                $out.Recurrence | Should -BeNullOrEmpty
            }
        }

        It 'surfaces the settings booleans, defaultDecision and defaultDecisionEnabled as flat members' {
            InModuleScope 'Omnicit.EntraRBAC' {
                $Raw = [PSCustomObject]@{
                    id = 'ar-1'; displayName = 'R'
                    settings = [PSCustomObject]@{
                        mailNotificationsEnabled        = $true
                        reminderNotificationsEnabled    = $false
                        justificationRequiredOnApproval = $true
                        recommendationsEnabled          = $true
                        autoApplyDecisionsEnabled       = $true
                        defaultDecision                 = 'Deny'
                        defaultDecisionEnabled          = $true
                        instanceDurationInDays          = 14
                    }
                }
                $Def = ConvertTo-OERAccessReviewDefinition -InputObject $Raw
                $Def.MailNotificationsEnabled     | Should -Be $true
                $Def.ReminderNotificationsEnabled | Should -Be $false
                $Def.JustificationRequired        | Should -Be $true
                $Def.RecommendationsEnabled       | Should -Be $true
                $Def.AutoApplyDecisionsEnabled    | Should -Be $true
                $Def.DefaultDecision              | Should -BeExactly 'Deny'
                $Def.DefaultDecisionEnabled       | Should -Be $true
                $Def.Settings                     | Should -Not -BeNullOrEmpty
            }
        }

        It 'surfaces settings correctly when the bag arrives as a raw Graph dictionary, not just a PSCustomObject fixture' {
            InModuleScope 'Omnicit.EntraRBAC' {
                # A hashtable, because that is the shape settings actually arrives in from
                # Invoke-MgGraphRequest in production, unlike every other fixture in this file. This does
                # NOT prove Get-SettingValue guards against a lookup regression -- PowerShell's IDictionary
                # member adapter already resolves named-key '.' access correctly on a Hashtable, so a plain
                # $Settings.mailNotificationsEnabled read would pass this exact assertion too. It proves
                # only that the converter's output is correct against the real-world dictionary shape.
                $Raw = [PSCustomObject]@{ id = 'ar-1'; settings = @{ mailNotificationsEnabled = $true; defaultDecision = 'Approve' } }
                $Def = ConvertTo-OERAccessReviewDefinition -InputObject $Raw
                $Def.MailNotificationsEnabled | Should -Be $true
                $Def.DefaultDecision          | Should -BeExactly 'Approve'
            }
        }

        It 'projects stageSettings on the definition' {
            InModuleScope 'Omnicit.EntraRBAC' {
                $Raw = [PSCustomObject]@{
                    id = 'ar-1'
                    stageSettings = @(
                        [PSCustomObject]@{ stageId = '1'; durationInDays = 7; recommendationsEnabled = $true; reviewers = @(); fallbackReviewers = @() }
                        [PSCustomObject]@{ stageId = '2'; dependsOn = @('1'); durationInDays = 3; decisionsThatWillMoveToNextStage = @('Deny') }
                    )
                }
                $Def = ConvertTo-OERAccessReviewDefinition -InputObject $Raw
                $Def.StageCount | Should -Be 2
                @($Def.StageSettings).Count | Should -Be 2
                $Def.StageSettings[0].StageId | Should -BeExactly '1'
                $Def.StageSettings[0].DurationInDays | Should -Be 7
                $Def.StageSettings[0].RecommendationsEnabled | Should -Be $true
                @($Def.StageSettings[0].DependsOn) | Should -BeNullOrEmpty
                $Def.StageSettings[1].StageId | Should -BeExactly '2'
                @($Def.StageSettings[1].DependsOn) | Should -Contain '1'
                @($Def.StageSettings[1].DecisionsThatMoveToNextStage) | Should -Contain 'Deny'
            }
        }

        It 'yields an empty StageSettings and StageCount 0 for a single-stage definition' {
            InModuleScope 'Omnicit.EntraRBAC' {
                # No stageSettings property at all -- exercises the @($NullVar.someProperty) trap: a raw
                # array read of a $null property yields a one-element array containing $null, not an
                # empty array, unless every read is wrapped in Where-Object { $_ }.
                $Raw = [PSCustomObject]@{ id = 'ar-1'; displayName = 'Single' }
                $Def = ConvertTo-OERAccessReviewDefinition -InputObject $Raw
                $Def.StageCount | Should -Be 0
                @($Def.StageSettings) | Should -BeNullOrEmpty
            }
        }
    }
}
