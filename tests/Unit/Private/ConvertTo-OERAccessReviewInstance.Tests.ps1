BeforeAll {
    $script:moduleName = 'Omnicit.EntraRBAC'
    Get-Module $script:moduleName | Remove-Module -Force -ErrorAction SilentlyContinue
    Import-Module $script:moduleName -Force -ErrorAction Stop
}

Describe 'ConvertTo-OERAccessReviewInstance' {
    It 'tags the output and maps Id and Status' {
        InModuleScope $script:moduleName {
            $raw = @{
                id            = 'inst-1'
                status        = 'InProgress'
                startDateTime = '2026-07-01T00:00:00Z'
                endDateTime   = '2026-07-15T00:00:00Z'
                scope         = @{ query = '/identityGovernance/entitlementManagement/accessPackageAssignments?...' }
            }
            $o = ConvertTo-OERAccessReviewInstance -InputObject $raw
            $o.PSObject.TypeNames[0] | Should -Be 'Omnicit.EntraRBAC.AccessReviewInstance'
            $o.Id | Should -Be 'inst-1'
            $o.Status | Should -Be 'InProgress'
        }
    }

    It 'populates DefinitionId from the -DefinitionId parameter' {
        InModuleScope $script:moduleName {
            $raw = @{
                id            = 'inst-2'
                status        = 'NotStarted'
                startDateTime = '2026-08-01T00:00:00Z'
                endDateTime   = '2026-08-14T00:00:00Z'
                scope         = @{ query = '/some/query' }
            }
            $o = ConvertTo-OERAccessReviewInstance -InputObject $raw -DefinitionId 'def-99'
            $o.DefinitionId | Should -Be 'def-99'
        }
    }

    It 'exposes AccessReviewInstanceId equal to Id for pipeline binding' {
        InModuleScope $script:moduleName {
            $raw = @{
                id            = 'inst-pipe-1'
                status        = 'InProgress'
                startDateTime = '2026-07-01T00:00:00Z'
                endDateTime   = '2026-07-15T00:00:00Z'
                scope         = @{ query = '/some/query' }
            }
            $o = ConvertTo-OERAccessReviewInstance -InputObject $raw -DefinitionId 'def-42'
            $o.AccessReviewInstanceId | Should -Be 'inst-pipe-1'
            $o.AccessReviewInstanceId | Should -Be $o.Id
        }
    }

    It 'exposes AccessReviewDefinitionId equal to DefinitionId for pipeline binding' {
        InModuleScope $script:moduleName {
            $raw = @{
                id            = 'inst-pipe-2'
                status        = 'NotStarted'
                startDateTime = '2026-07-01T00:00:00Z'
                endDateTime   = '2026-07-15T00:00:00Z'
                scope         = @{ query = '/some/query' }
            }
            $o = ConvertTo-OERAccessReviewInstance -InputObject $raw -DefinitionId 'def-77'
            $o.AccessReviewDefinitionId | Should -Be 'def-77'
            $o.AccessReviewDefinitionId | Should -Be $o.DefinitionId
        }
    }

    It 'maps StartDateTime, EndDateTime and Scope from nested properties' {
        InModuleScope $script:moduleName {
            $raw = @{
                id            = 'inst-3'
                status        = 'Completed'
                startDateTime = '2026-09-01T00:00:00Z'
                endDateTime   = '2026-09-15T00:00:00Z'
                scope         = @{ query = '/identityGovernance/entitlementManagement/accessPackageAssignments?$filter=...' }
            }
            $o = ConvertTo-OERAccessReviewInstance -InputObject $raw -DefinitionId 'def-1'
            $o.StartDateTime | Should -Be '2026-09-01T00:00:00Z'
            $o.EndDateTime | Should -Be '2026-09-15T00:00:00Z'
            $o.Scope | Should -Be '/identityGovernance/entitlementManagement/accessPackageAssignments?$filter=...'
        }
    }

    It 'accepts pipeline input' {
        InModuleScope $script:moduleName {
            $raw = @{
                id            = 'inst-4'
                status        = 'Applied'
                startDateTime = '2026-10-01T00:00:00Z'
                endDateTime   = '2026-10-15T00:00:00Z'
                scope         = @{ query = '/some/other/query' }
            }
            $o = $raw | ConvertTo-OERAccessReviewInstance -DefinitionId 'def-2'
            $o.PSObject.TypeNames[0] | Should -Be 'Omnicit.EntraRBAC.AccessReviewInstance'
            $o.Id | Should -Be 'inst-4'
        }
    }

    It 'stores Id and DefinitionId as AliasProperty of AccessReviewInstanceId/AccessReviewDefinitionId, not second copies (Task 8a)' {
        InModuleScope $script:moduleName {
            $o = ConvertTo-OERAccessReviewInstance -InputObject @{ id = 'inst-alias-1'; status = 'InProgress' } -DefinitionId 'def-alias-1'

            $NoteProperties = ($o.PSObject.Properties | Where-Object MemberType -eq 'NoteProperty').Name
            $NoteProperties | Should -Not -Contain 'Id' -Because 'Id must be the AliasProperty registered in suffix.ps1, not a second stored copy'
            $NoteProperties | Should -Not -Contain 'DefinitionId' -Because 'DefinitionId must be the AliasProperty registered in suffix.ps1, not a second stored copy'

            $o.PSObject.Properties['Id'].MemberType | Should -Be 'AliasProperty'
            $o.PSObject.Properties['Id'].ReferencedMemberName | Should -Be 'AccessReviewInstanceId'
            $o.Id | Should -Be 'inst-alias-1'

            $o.PSObject.Properties['DefinitionId'].MemberType | Should -Be 'AliasProperty'
            $o.PSObject.Properties['DefinitionId'].ReferencedMemberName | Should -Be 'AccessReviewDefinitionId'
            $o.DefinitionId | Should -Be 'def-alias-1'
        }
    }

    It 'pipes into Stop-OERAccessReviewInstance -Definition/-Instance, proving the migrated shape still round-trips (Task 8a)' {
        # Stop-OERAccessReviewInstance's -Definition/-Instance parameters bind via their own
        # AccessReviewDefinitionId/AccessReviewInstanceId aliases -- the STORED names on this shape,
        # unaffected by the migration -- so this is a regression check that removing the duplicate
        # Id/DefinitionId NoteProperty copies (and the resulting change in note-property order) did
        # not disturb a real downstream pipeline bind. Resolve-OERAccessReviewDefinitionId is mocked
        # too, matching Stop-OERAccessReviewInstance.Tests.ps1's own established pattern: -Definition
        # is not a GUID here, so the unmocked helper would issue its own (unrelated) Graph lookup
        # first and return $null against an empty mock response, short-circuiting before the POST.
        Mock -ModuleName Omnicit.EntraRBAC Initialize-OERAuth { }
        Mock -ModuleName Omnicit.EntraRBAC Resolve-OERAccessReviewDefinitionId { 'def-pipe-1' }
        Mock -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest { }

        InModuleScope Omnicit.EntraRBAC {
            $Instance = ConvertTo-OERAccessReviewInstance -InputObject @{ id = 'inst-pipe-1'; status = 'InProgress' } -DefinitionId 'def-pipe-1'
            $Instance | Stop-OERAccessReviewInstance -Confirm:$false
        }

        Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest -Exactly -Times 1 -ParameterFilter {
            $Method -eq 'POST' -and $Uri -eq 'v1.0/identityGovernance/accessReviews/definitions/def-pipe-1/instances/inst-pipe-1/stop'
        }
    }
}
