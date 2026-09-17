BeforeAll {
    $script:moduleName = 'Omnicit.EntraRBAC'
    Get-Module $script:moduleName | Remove-Module -Force -ErrorAction SilentlyContinue
    Import-Module $script:moduleName -Force -ErrorAction Stop
}

Describe 'ConvertTo-OERAccessReviewStage' {
    It 'tags the output and maps Id and Status' {
        InModuleScope $script:moduleName {
            $raw = @{
                id            = 'stage-1'
                status        = 'InProgress'
                startDateTime = '2026-07-01T00:00:00Z'
                endDateTime   = '2026-07-08T00:00:00Z'
            }
            $o = ConvertTo-OERAccessReviewStage -InputObject $raw
            $o.PSObject.TypeNames[0] | Should -Be 'Omnicit.EntraRBAC.AccessReviewStage'
            $o.Id | Should -Be 'stage-1'
            $o.Status | Should -Be 'InProgress'
        }
    }

    It 'maps StartDateTime and EndDateTime' {
        InModuleScope $script:moduleName {
            $raw = @{
                id            = 'stage-2'
                status        = 'Completed'
                startDateTime = '2026-08-01T00:00:00Z'
                endDateTime   = '2026-08-08T00:00:00Z'
            }
            $o = ConvertTo-OERAccessReviewStage -InputObject $raw
            $o.StartDateTime | Should -Be '2026-08-01T00:00:00Z'
            $o.EndDateTime | Should -Be '2026-08-08T00:00:00Z'
        }
    }

    It 'accepts pipeline input' {
        InModuleScope $script:moduleName {
            $raw = @{
                id            = 'stage-3'
                status        = 'NotStarted'
                startDateTime = '2026-09-01T00:00:00Z'
                endDateTime   = '2026-09-08T00:00:00Z'
            }
            $o = $raw | ConvertTo-OERAccessReviewStage
            $o.PSObject.TypeNames[0] | Should -Be 'Omnicit.EntraRBAC.AccessReviewStage'
            $o.Id | Should -Be 'stage-3'
        }
    }

    It 'surfaces the stage reviewers and fallback reviewers the Graph resource returns' {
        InModuleScope $script:moduleName {
            $Stage = ConvertTo-OERAccessReviewStage -InputObject ([PSCustomObject]@{
                    id = 's-1'; status = 'InProgress'; startDateTime = '2026-01-01'; endDateTime = '2026-01-08'
                    reviewers = @([PSCustomObject]@{ query = '/users/u-1' })
                    fallbackReviewers = @([PSCustomObject]@{ query = '/users/u-2' })
                })
            $Stage.Id | Should -BeExactly 's-1'
            @($Stage.Reviewers).Count | Should -Be 1
            $Stage.Reviewers[0].query | Should -Be '/users/u-1'
            @($Stage.FallbackReviewers).Count | Should -Be 1
            $Stage.FallbackReviewers[0].query | Should -Be '/users/u-2'
        }
    }

    It 'tags the object and tolerates a stage with no reviewers' {
        InModuleScope $script:moduleName {
            # No reviewers/fallbackReviewers property at all -- exercises the @($NullVar.someProperty)
            # trap: a raw array read of a $null property yields a one-element array containing $null,
            # not an empty array, unless wrapped in Where-Object { $_ }.
            $Stage = ConvertTo-OERAccessReviewStage -InputObject ([PSCustomObject]@{
                    id = 's-2'; status = 'NotStarted'; startDateTime = '2026-02-01'; endDateTime = '2026-02-08'
                })
            $Stage.PSObject.TypeNames[0] | Should -Be 'Omnicit.EntraRBAC.AccessReviewStage'
            @($Stage.Reviewers) | Should -BeNullOrEmpty
            @($Stage.FallbackReviewers) | Should -BeNullOrEmpty
        }
    }

    It '-InstanceId and -DefinitionId are optional -- InputObject alone still succeeds (Task 4a)' {
        InModuleScope $script:moduleName {
            $Stage = ConvertTo-OERAccessReviewStage -InputObject @{
                id = 's-4'; status = 'NotStarted'; startDateTime = '2026-03-01'; endDateTime = '2026-03-08'
            }
            $Stage.AccessReviewStageId | Should -Be 's-4'
            $Stage.AccessReviewInstanceId | Should -BeNullOrEmpty
            $Stage.AccessReviewDefinitionId | Should -BeNullOrEmpty
        }
    }

    It 'stamps AccessReviewStageId, AccessReviewInstanceId and AccessReviewDefinitionId for pipeline binding (Task 4a)' {
        InModuleScope $script:moduleName {
            $Stage = ConvertTo-OERAccessReviewStage -InputObject @{
                id = 's-5'; status = 'InProgress'; startDateTime = '2026-04-01'; endDateTime = '2026-04-08'
            } -InstanceId 'i-9' -DefinitionId 'd-9'
            $Stage.AccessReviewStageId | Should -Be 's-5'
            $Stage.AccessReviewStageId | Should -Be $Stage.Id
            $Stage.AccessReviewInstanceId | Should -Be 'i-9'
            $Stage.AccessReviewDefinitionId | Should -Be 'd-9'
        }
    }

    It 'stores Id as an AliasProperty of AccessReviewStageId, not a second copy (Task 8a addendum 3)' {
        <#
            The real downstream consumer of this shape, Get-OERAccessReviewInstanceDecision -Stage,
            is owned by another concurrently-running task on this branch (agent-rules.md forbids
            touching its file), so this test deliberately stops at the same boundary
            ConvertTo-OERRoleDefinition.Tests.ps1 does for its ResourceId row: pin the AliasProperty
            registration here, and rely on static inspection for the consumer side. -Stage's own
            declared aliases are 'AccessReviewStageId', 'StageId' -- both point at the STORED name on
            this shape, unaffected by this migration -- so no downstream bind depends on the NEW Id
            alias specifically.
        #>
        InModuleScope $script:moduleName {
            $o = ConvertTo-OERAccessReviewStage -InputObject @{ id = 'stage-alias-1'; status = 'InProgress' }

            ($o.PSObject.Properties | Where-Object MemberType -eq 'NoteProperty').Name |
                Should -Not -Contain 'Id' -Because 'Id must be the AliasProperty registered in suffix.ps1, not a second stored copy'
            $o.PSObject.Properties['Id'].MemberType | Should -Be 'AliasProperty'
            $o.PSObject.Properties['Id'].ReferencedMemberName | Should -Be 'AccessReviewStageId'
            $o.Id | Should -Be 'stage-alias-1'
        }
    }
}
