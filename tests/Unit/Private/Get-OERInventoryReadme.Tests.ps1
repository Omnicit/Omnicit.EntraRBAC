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
            # Every file Export-OERInventory writes, the two directory role area files included.
            foreach ($File in @('inventory.json', 'groups.json', 'administrativeUnits.json',
                    'catalogs.json', 'accessPackages.json', 'accessReviews.json',
                    'directoryRoleManagementPolicies.json', 'directoryRoleAssignments.json',
                    'groupsRoster.json', 'scopeHierarchy.json', 'azurePimEligibility.json',
                    'roleAssignments.json', 'roleManagementPolicies.json', 'schema.json',
                    'rbac-architect-prompt.md')) {
                $Md | Should -Match ([regex]::Escape($File))
            }
            # No cross-reference to a heading the README does not have.
            ($Md -replace '\s+', ' ') | Should -Not -Match ([regex]::Escape('"Azure PIM eligibility" under Coverage limits'))
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
            $Md | Should -Match 'not captured anywhere in this bundle'
            $Md | Should -Match 'SKIPPED entirely'
            $Md | Should -Match 'ACCESS-PACKAGE-SCOPED'
            foreach ($Cmdlet in @('New-OERResourceGroup', 'Get-OERResource',
                    'New-OEREligibleRoleAssignment', 'Remove-OEREligibleRoleAssignment',
                    'New-OERActiveRoleAssignment', 'New-OERAccessReviewStage')) {
                $Md | Should -Match ([regex]::Escape($Cmdlet))
            }
        }
    }

    It 'states eligible Azure PIM assignments are read-only context in azurePimEligibility.json' {
        InModuleScope $script:moduleName {
            $Md = Get-OERInventoryReadme
            # Regression guard for a stale claim: eligible Azure PIM assignments used to be entirely
            # uncaptured; Export-OERInventory now writes them into azurePimEligibility.json as
            # read-only context, so the README must say so rather than repeat the old blanket claim.
            $Md | Should -Match ([regex]::Escape('azurePimEligibility.json'))
            $Md | Should -Match 'read-only context'
            $Md | Should -Match 'not an apply section'
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

    It 'warns that an unread members, scopedRoles, resources or resourceRoles collection is written as null and must never be changed to []' {
        InModuleScope $script:moduleName {
            $Md = Get-OERInventoryReadme
            $Md | Should -Match '(?m)^## Unread collections\r?$'
            # Whitespace collapsed first, so the assertion does not depend on where the paragraph wraps.
            $Section = (($Md -split '(?m)^## Unread collections\r?$')[1] -split '(?m)^## ')[0] -replace '\s+', ' '
            $Section | Should -Match ([regex]::Escape('`null`'))
            foreach ($Key in @('members', 'scopedRoles', 'resources', 'resourceRoles')) {
                $Section | Should -Match ([regex]::Escape('`' + $Key + '`')) -Because "the section must name $Key"
            }
            # The claim is about these four collections only: an unread owners or eligibility
            # collection is omitted and an unread policy list is [], so a flat "the collection is
            # never written as empty" would be false of them.
            $Section | Should -Match ([regex]::Escape('When a read of a `members`, `scopedRoles`, `resources` or `resourceRoles` collection fails'))
            $Section | Should -Match ([regex]::Escape('the export never writes that collection as empty'))
            $Section | Should -Not -Match ([regex]::Escape('the export never writes the collection as empty'))
            $Section | Should -Match ([regex]::Escape('The key is written as `null`, which `Invoke-OERStructure` reads as "leave untouched".'))
            $Section | Should -Match ([regex]::Escape('Do not change such a `null` to `[]`: under `-Prune` an empty collection removes every live entry.'))
            $Section | Should -Match ([regex]::Escape('`InventoryPartial` error naming every collection it could not read, these four and any other; the others are left out or written only as far as they were read'))
            # The section sits ahead of the numbered next steps it would otherwise be read after.
            $Md.IndexOf('## Unread collections') | Should -BeLessThan $Md.IndexOf('## Next steps')
        }
    }

    It 'contains only ASCII characters' {
        InModuleScope $script:moduleName {
            $Bytes = [System.Text.Encoding]::UTF8.GetBytes((Get-OERInventoryReadme))
            ($Bytes | Where-Object { $_ -gt 127 }).Count | Should -Be 0
        }
    }
}

Describe 'Get-OERInventoryReadme apply-document section list' {
    # The coverage paragraph counts and lists the apply-document sections. Tie both to the sections
    # schema.json declares, so a section added to the schema cannot leave the README claiming fewer.
    It 'counts and names every section schema.json declares, and names both directory role sections as captured' {
        InModuleScope $script:moduleName {
            $Md = Get-OERInventoryReadme
            $Sections = @((Get-OERStructureSchemaJson | ConvertFrom-Json).properties.PSObject.Properties.Name |
                    Where-Object { $_ -notin @('version', 'tenantAlias') })
            $Word = @{ 7 = 'seven'; 8 = 'eight'; 9 = 'nine'; 10 = 'ten' }[$Sections.Count]
            $Md | Should -Match "The apply document has $Word sections only"
            foreach ($Section in $Sections) {
                $Md | Should -Match "\b$Section\b"
            }
            # Whitespace collapsed first, so the assertion does not depend on where the paragraph wraps.
            $Collapsed = $Md -replace '\s+', ' '
            $Collapsed | Should -Not -Match 'apply-only for now'
            $Collapsed | Should -Not -Match 'does not read them'
            $Collapsed | Should -Match ([regex]::Escape('`directoryRoleManagementPolicies` (the PIM settings of Microsoft Entra directory roles) and `directoryRoleAssignments` (eligible and active assignments of Microsoft Entra directory roles) are both captured in `inventory.json` (policies for roles with at least one eligible or active assignment unless the export used `-AllDirectoryRolePolicies`; assignments that are direct and at tenant scope -- activations and assignments inherited through a group are not listed), and may be proposed.'))
        }
    }
}
