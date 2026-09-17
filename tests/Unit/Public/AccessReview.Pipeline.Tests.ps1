BeforeAll { Import-Module Omnicit.EntraRBAC -Force }

Describe 'Access Review Pipeline Binding' {
    BeforeEach {
        InModuleScope Omnicit.EntraRBAC { $script:_OERAuthState = $null }
        Mock -ModuleName Omnicit.EntraRBAC Initialize-OERAuth { }
        Mock -ModuleName Omnicit.EntraRBAC Resolve-OERAccessReviewDefinitionId {
            param($DisplayName, $Id)
            if ($Id) { return $Id }
            return $DisplayName
        }
        Mock -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest {
            param($Uri, $Method, $Body)
            if ($Uri -like '*/definitions/d1' -and -not ($Uri -like '*/instances*')) {
                return @{ id = 'd1'; displayName = 'Q3'; status = 'NotStarted'; scope = @{ query = 'x' } }
            }
            if ($Uri -like '*/definitions/d1/instances*' -and -not ($Uri -like '*/instances/*')) {
                return @{ value = @(@{ id = 'i1'; status = 'InProgress'; scope = @{ query = 'x' } }) }
            }
            if ($Uri -eq 'v1.0/identityGovernance/accessReviews/definitions/d1/instances/i1/stages/s1/decisions') {
                return @{ value = @(@{ id = 'dec1'; decision = 'Approve'; principal = @{ displayName = 'User A' } }) }
            }
            # Round-1 review finding I-1: without this branch, the -IncludeStages request below falls
            # through to the generic @{ value = @() } catch-all -- the test would see zero stages and
            # every downstream assertion would pass VACUOUSLY (empty collections, empty pipe). This
            # branch must exist BEFORE the "true end-to-end" test is written.
            if ($Uri -eq 'v1.0/identityGovernance/accessReviews/definitions/d1/instances/i1/stages') {
                return @{ value = @(@{ id = 's1'; status = 'InProgress' }) }
            }
            if ($Uri -like '*/instances/i1/decisions') {
                return @{ value = @(@{ id = 'dec1'; decision = 'Approve'; principal = @{ displayName = 'User A' } }) }
            }
            if ($Uri -like '*/instances/i1/stop') {
                return $null
            }
            return @{ value = @() }
        }
    }

    It 'Get-OERAccessReviewDefinition | Get-OERAccessReviewInstance reaches the correct instances URI (Fix 1)' {
        $Def = InModuleScope Omnicit.EntraRBAC {
            ConvertTo-OERAccessReviewDefinition -InputObject @{
                id          = 'd1'
                displayName = 'Q3'
                status      = 'NotStarted'
                scope       = @{ query = 'x' }
                settings    = @{ instanceDurationInDays = 14 }
            }
        }
        $Def | Get-OERAccessReviewInstance
        Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest -ParameterFilter {
            $Uri -eq 'v1.0/identityGovernance/accessReviews/definitions/d1/instances?$select=id,status,startDateTime,endDateTime,scope'
        }
    }

    It 'piped definition Id does NOT bind instance -Id (Guard against id hijack -- Fix 1)' {
        $Def = InModuleScope Omnicit.EntraRBAC {
            ConvertTo-OERAccessReviewDefinition -InputObject @{
                id          = 'd1'
                displayName = 'Q3'
                status      = 'NotStarted'
                scope       = @{ query = 'x' }
                settings    = @{ instanceDurationInDays = 14 }
            }
        }
        $Instances = $Def | Get-OERAccessReviewInstance
        $Instances | Should -Not -BeNullOrEmpty
        $Instances[0].Id | Should -Be 'i1'
    }

    It 'Get-OERAccessReviewInstance | Get-OERAccessReviewInstanceDecision reaches decisions URI (Fix 1)' {
        $Inst = InModuleScope Omnicit.EntraRBAC {
            ConvertTo-OERAccessReviewInstance -InputObject @{
                id     = 'i1'
                status = 'InProgress'
                scope  = @{ query = 'x' }
            } -DefinitionId 'd1'
        }
        $Inst | Get-OERAccessReviewInstanceDecision
        Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest -ParameterFilter {
            $Uri -eq 'v1.0/identityGovernance/accessReviews/definitions/d1/instances/i1/decisions'
        }
    }

    It 'Get-OERAccessReviewInstance | Stop-OERAccessReviewInstance POSTs to stop URI (Fix 1)' {
        $Inst = InModuleScope Omnicit.EntraRBAC {
            ConvertTo-OERAccessReviewInstance -InputObject @{
                id     = 'i1'
                status = 'InProgress'
                scope  = @{ query = 'x' }
            } -DefinitionId 'd1'
        }
        $Inst | Stop-OERAccessReviewInstance -Confirm:$false
        Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest -ParameterFilter {
            $Method -eq 'POST' -and
            $Uri -like '*/instances/i1/stop'
        }
    }

    It 'a piped stage carries its parent InstanceId/DefinitionId into Get-OERAccessReviewInstanceDecision (Task 4a)' {
        # The stage converter must stamp AccessReviewInstanceId/AccessReviewDefinitionId onto every
        # stage it emits so a piped stage satisfies the two MANDATORY VFPBPN parameters on
        # Get-OERAccessReviewInstanceDecision (-Definition and -Instance) without a double prompt.
        $Stage = InModuleScope Omnicit.EntraRBAC {
            ConvertTo-OERAccessReviewStage -InputObject @{
                id            = 's1'
                status        = 'InProgress'
                startDateTime = '2026-01-01T00:00:00Z'
                endDateTime   = '2026-01-08T00:00:00Z'
            } -InstanceId 'i1' -DefinitionId 'd1'
        }
        $Stage | Get-OERAccessReviewInstanceDecision
        # A '*stages*' -like filter would pass even if -Stage bound to the wrong value (e.g. the
        # instance id instead of the stage id), so the full literal URI is asserted instead.
        Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest -Times 1 -Exactly -ParameterFilter {
            $Uri -eq 'v1.0/identityGovernance/accessReviews/definitions/d1/instances/i1/stages/s1/decisions'
        }
    }

    It 'Get-OERAccessReviewInstance -IncludeStages | Get-OERAccessReviewInstanceDecision reaches the stage decisions URI (Task 4a end-to-end, round-1 finding I-1)' {
        # The test above ("a piped stage carries...") builds its stage by calling
        # ConvertTo-OERAccessReviewStage DIRECTLY with explicit -InstanceId/-DefinitionId, so it never
        # exercises the cmdlet responsible for SUPPLYING those ids
        # (Get-OERAccessReviewInstance.ps1:165). This test drives the real cmdlet end to end: reverting
        # that call site back to a bare `-InputObject $_` (dropping -InstanceId/-DefinitionId) leaves
        # this test, and only this test plus the two new assertions in
        # Get-OERAccessReviewInstance.Tests.ps1, red.
        $Inst = Get-OERAccessReviewInstance -Definition 'd1' -IncludeStages
        $Inst.Stages | Should -Not -BeNullOrEmpty
        $Inst.Stages[0].AccessReviewInstanceId | Should -Be 'i1'
        $Inst.Stages[0].AccessReviewDefinitionId | Should -Be 'd1'

        $Inst.Stages[0] | Get-OERAccessReviewInstanceDecision
        Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest -Times 1 -Exactly -ParameterFilter {
            $Uri -eq 'v1.0/identityGovernance/accessReviews/definitions/d1/instances/i1/stages/s1/decisions'
        }
    }
}
