BeforeAll {
    Import-Module Omnicit.EntraRBAC -Force
}

Describe 'Get-OERPimGroupsGraphPath' {
    It 'prefixes the pinned API version' {
        InModuleScope Omnicit.EntraRBAC {
            Get-OERPimGroupsGraphPath -Path 'policies/roleManagementPolicies' |
                Should -Be 'beta/policies/roleManagementPolicies'
        }
    }

    It 'tolerates a leading slash' {
        InModuleScope Omnicit.EntraRBAC {
            Get-OERPimGroupsGraphPath -Path '/policies/roleManagementPolicies' |
                Should -Be 'beta/policies/roleManagementPolicies'
        }
    }

    It 'passes a query string through untouched so the caller keeps owning its OData escaping' {
        InModuleScope Omnicit.EntraRBAC {
            Get-OERPimGroupsGraphPath -Path "policies/roleManagementPolicyAssignments?`$filter=scopeId eq 'g''1' and scopeType eq 'Group'" |
                Should -Be "beta/policies/roleManagementPolicyAssignments?`$filter=scopeId eq 'g''1' and scopeType eq 'Group'"
        }
    }

    It 'makes no Graph call' {
        InModuleScope Omnicit.EntraRBAC {
            Mock Invoke-OERGraphRequest { throw 'should not be called' }
            $null = Get-OERPimGroupsGraphPath -Path 'identityGovernance/privilegedAccess/group/eligibilityScheduleRequests'
            Should -Invoke Invoke-OERGraphRequest -Times 0 -Exactly
        }
    }

    Context 'single ownership of the pin' {
        BeforeAll {
            # tests/Unit/Private -> tests/Unit -> tests -> repo root.
            $script:SourceRoot = Join-Path $PSScriptRoot '../../../source'
            $script:PinnedFiles = @(
                'Public/Add-OERGroupEligibility.ps1'
                'Public/Remove-OERGroupEligibility.ps1'
                'Public/Set-OERGroupPimPolicy.ps1'
                'Public/Get-OERGroup.ps1'
                'Public/Get-OERGroupPimPolicy.ps1'
                'Private/Enable-OERGroupPermanentEligibility.ps1'
                'Private/Get-OERGroupPermanentEligibilityState.ps1'
                'Private/Get-OERPimGroupPolicyId.ps1'
            ) | ForEach-Object { Join-Path $script:SourceRoot $_ }
        }

        It 'resolves every file it claims to guard' {
            # Without this the sweep below would pass vacuously if the relative path ever broke,
            # which is the failure mode that makes a drift guard worse than no guard at all.
            $script:PinnedFiles.Count | Should -Be 8
            $Missing = @($script:PinnedFiles | Where-Object { -not (Test-Path -LiteralPath $_) })
            $Missing | Should -BeNullOrEmpty -Because 'the drift guard below only means something if it reads real files'
        }

        It 'is the single owner of the pin -- no call site hardcodes beta' {
            $Offenders = [System.Collections.Generic.List[string]]::new()
            foreach ($File in $script:PinnedFiles) {
                $Hits = @(Select-String -LiteralPath $File -Pattern "'beta/|`"beta/")
                foreach ($Hit in $Hits) {
                    $Offenders.Add(('{0}:{1}' -f (Split-Path -Leaf $File), $Hit.LineNumber))
                }
            }
            $Offenders | Should -BeNullOrEmpty -Because (
                'the PIM-for-Groups API version must live only in Get-OERPimGroupsGraphPath; hardcoded at: {0}' -f
                ($Offenders -join ', '))
        }

        It 'routes every guarded file through the helper' {
            # The negative sweep alone would also pass on a file that had stopped calling Graph
            # entirely. Pair it with the positive: each guarded file must reference the owner.
            $Silent = @($script:PinnedFiles | Where-Object {
                    -not @(Select-String -LiteralPath $_ -Pattern 'Get-OERPimGroupsGraphPath').Count
                } | ForEach-Object { Split-Path -Leaf $_ })
            $Silent | Should -BeNullOrEmpty -Because 'a guarded file that names neither beta nor the helper has silently lost its PIM call'
        }
    }
}
