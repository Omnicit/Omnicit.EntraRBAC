BeforeAll {
    $script:moduleName = 'Omnicit.EntraRBAC'
    Get-Module $script:moduleName | Remove-Module -Force -ErrorAction SilentlyContinue
    Import-Module $script:moduleName -Force -ErrorAction Stop
}

Describe 'Get-OERInventoryReadme' {
    It 'returns markdown that names every bundle file and the next-step cmdlets' {
        InModuleScope $script:moduleName {
            $Md = Get-OERInventoryReadme
            $Md | Should -BeOfType ([string])
            foreach ($File in @('inventory.json', 'groups.json', 'groupsRoster.json',
                    'scopeHierarchy.json', 'roleAssignments.json', 'roleManagementPolicies.json',
                    'schema.json', 'rbac-architect-prompt.md')) {
                $Md | Should -Match ([regex]::Escape($File))
            }
            $Md | Should -Match 'Test-OERStructure'
            $Md | Should -Match 'Invoke-OERStructure'
        }
    }

    It 'states where the bundle stops covering the tenant' {
        InModuleScope $script:moduleName {
            $Md = Get-OERInventoryReadme
            # An operator must not read the bundle as a complete picture: all four areas below are
            # absent entirely -- none of them is captured lossily (a multi-stage review used to be
            # fabricated as a lossy single-stage self review; it is skipped instead).
            $Md | Should -Match 'Coverage limits'
            $Md | Should -Match 'Azure resource groups and individual Azure resources'
            $Md | Should -Match 'not captured at all'
            $Md | Should -Match 'SKIPPED entirely'
            $Md | Should -Match 'ACCESS-PACKAGE-SCOPED'
            foreach ($Cmdlet in @('New-OERResourceGroup', 'Get-OERResource',
                    'New-OEREligibleRoleAssignment', 'New-OERActiveRoleAssignment',
                    'New-OERAccessReviewStage')) {
                $Md | Should -Match ([regex]::Escape($Cmdlet))
            }
        }
    }

    It 'states a multi-stage review is skipped rather than fabricated as a lossy self review' {
        InModuleScope $script:moduleName {
            $Md = Get-OERInventoryReadme
            # Regression guard for a stale claim: Get-OERInventory no longer fabricates a
            # single-stage self review out of a multi-stage one (commit 611f241) -- it skips the
            # review entirely with a warning, so the README must not claim otherwise.
            $Md | Should -Not -Match ([regex]::Escape('reviewers: ["self"]'))
            $Md | Should -Not -Match 'captured LOSSILY'
            $Md | Should -Match 'fabricated as a single-stage self review'
        }
    }

    It 'names the access-package-scope carve-out as its own coverage limit' {
        InModuleScope $script:moduleName {
            $Md = Get-OERInventoryReadme
            # Regression guard: a group/application/directory-role review is excluded regardless
            # of stage count -- a different cause from the multi-stage skip above, so it needs its
            # own bullet rather than being folded into that one.
            $Md | Should -Match 'a group, an application or a directory role'
        }
    }

    It 'contains only ASCII characters' {
        InModuleScope $script:moduleName {
            $Bytes = [System.Text.Encoding]::UTF8.GetBytes((Get-OERInventoryReadme))
            ($Bytes | Where-Object { $_ -gt 127 }).Count | Should -Be 0
        }
    }
}
