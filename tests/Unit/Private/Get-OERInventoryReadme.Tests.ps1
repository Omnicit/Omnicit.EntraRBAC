BeforeAll {
    $script:moduleName = 'Omnicit.EntraRBAC'
    Get-Module $script:moduleName | Remove-Module -Force -ErrorAction SilentlyContinue
    Import-Module $script:moduleName -Force -ErrorAction Stop
    . "$PSScriptRoot/../TestHelpers/OERTransportTripwire.ps1"
    Install-OERTransportTripwire
}

AfterAll {
    try { Assert-OERTransportTripwire } finally { Uninstall-OERTransportTripwire }
}

Describe 'Get-OERInventoryReadme' {
    It 'returns markdown that names every bundle file and the next-step cmdlets' {
        InModuleScope $script:moduleName {
            $Md = Get-OERInventoryReadme -IncompleteReads @() -SkippedScopes @() -SkippedEligibilityScopes @() -PimLeftOut @() -RootScopeAssignments @() -SharedNames @() -UnresolvedPrincipalAssignments @() -UndeclarableScopeAssignments @() -RestrictedUnitPimGroups @() -LighthouseDelegations @() -ForeignSubscriptions @()
            $Md | Should -BeOfType ([string])
            # Every file Export-OERInventory writes, the two directory role area files included.
            foreach ($File in @('inventory.json', 'groups.json', 'administrativeUnits.json',
                    'catalogs.json', 'accessPackages.json', 'accessReviews.json',
                    'directoryRoleManagementPolicies.json', 'directoryRoleAssignments.json',
                    'groupsRoster.json', 'scopeHierarchy.json', 'azurePimEligibility.json',
                    'lighthouseDelegations.json', 'roleAssignments.json', 'roleManagementPolicies.json',
                    'schema.json', 'rbac-architect-prompt.md')) {
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
            $Md = Get-OERInventoryReadme -IncompleteReads @() -SkippedScopes @() -SkippedEligibilityScopes @() -PimLeftOut @() -RootScopeAssignments @() -SharedNames @() -UnresolvedPrincipalAssignments @() -UndeclarableScopeAssignments @() -RestrictedUnitPimGroups @() -LighthouseDelegations @() -ForeignSubscriptions @()
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
            $Md = Get-OERInventoryReadme -IncompleteReads @() -SkippedScopes @() -SkippedEligibilityScopes @() -PimLeftOut @() -RootScopeAssignments @() -SharedNames @() -UnresolvedPrincipalAssignments @() -UndeclarableScopeAssignments @() -RestrictedUnitPimGroups @() -LighthouseDelegations @() -ForeignSubscriptions @()
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
            $Md = Get-OERInventoryReadme -IncompleteReads @() -SkippedScopes @() -SkippedEligibilityScopes @() -PimLeftOut @() -RootScopeAssignments @() -SharedNames @() -UnresolvedPrincipalAssignments @() -UndeclarableScopeAssignments @() -RestrictedUnitPimGroups @() -LighthouseDelegations @() -ForeignSubscriptions @()
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
            $Md = Get-OERInventoryReadme -IncompleteReads @() -SkippedScopes @() -SkippedEligibilityScopes @() -PimLeftOut @() -RootScopeAssignments @() -SharedNames @() -UnresolvedPrincipalAssignments @() -UndeclarableScopeAssignments @() -RestrictedUnitPimGroups @() -LighthouseDelegations @() -ForeignSubscriptions @()
            # Regression guard: a group/application/directory-role review is excluded regardless
            # of stage count -- a different cause from the multi-stage skip above, so it needs its
            # own bullet rather than being folded into that one.
            $Md | Should -Match 'a group, an application or a directory role'
        }
    }

    It 'says in the file roster that groupsRoster.json carries onPremisesSynced among its flags (A15)' {
        InModuleScope $script:moduleName {
            $Md = Get-OERInventoryReadme -IncompleteReads @() -SkippedScopes @() -SkippedEligibilityScopes @() -PimLeftOut @() -RootScopeAssignments @() -SharedNames @() -UnresolvedPrincipalAssignments @() -UndeclarableScopeAssignments @() -RestrictedUnitPimGroups @() -LighthouseDelegations @() -ForeignSubscriptions @()
            $Flat = $Md -replace '\s+', ' '
            $Flat | Should -Match ([regex]::Escape('and flags, including `onPremisesSynced`.'))
        }
    }

    It 'says in the file roster that each groupsRoster.json row carries the group''s id and type (BL-131)' {
        InModuleScope $script:moduleName {
            $Md = Get-OERInventoryReadme -IncompleteReads @() -SkippedScopes @() -SkippedEligibilityScopes @() -PimLeftOut @() -RootScopeAssignments @() -SharedNames @() -UnresolvedPrincipalAssignments @() -UndeclarableScopeAssignments @() -RestrictedUnitPimGroups @() -LighthouseDelegations @() -ForeignSubscriptions @()
            $Bullet = (($Md -split '(?m)^- `groupsRoster\.json` ')[1] -split '(?m)^- ')[0] -replace '\s+', ' '
            $Bullet | Should -Match ([regex]::Escape('-- a lightweight roster of EVERY group in the tenant, of every group type, read unfiltered: one row per group with its `id` and `displayName`, its type (`securityEnabled`, `mailEnabled` and `groupTypes`), `visibility`, `createdDateTime` and flags, including `onPremisesSynced`. The `id` tells apart two groups that share a name.'))
            # The roster used to be described as names and flags alone, which its rows no longer are.
            $Bullet | Should -Not -Match ([regex]::Escape('names + flags'))
        }
    }

    It 'says in the file roster that memberCount is null for a group the export did not read in full, and why (R3)' {
        InModuleScope $script:moduleName {
            $Md = Get-OERInventoryReadme -IncompleteReads @() -SkippedScopes @() -SkippedEligibilityScopes @() -PimLeftOut @() -RootScopeAssignments @() -SharedNames @() -UnresolvedPrincipalAssignments @() -UndeclarableScopeAssignments @() -RestrictedUnitPimGroups @() -LighthouseDelegations @() -ForeignSubscriptions @()
            # The groupsRoster.json bullet alone: from its own marker to the next bullet, whitespace
            # collapsed so the assertion does not depend on where the line wraps.
            $Md | Should -Match '(?m)^- `groupsRoster\.json` '
            $Bullet = (($Md -split '(?m)^- `groupsRoster\.json` ')[1] -split '(?m)^- ')[0] -replace '\s+', ' '
            $Bullet | Should -Match ([regex]::Escape('Its `memberCount` is the group''s member count when the export read the group in full (every security group with `-AllGroupsDetailed`), and `null` otherwise -- not known, which is not zero: a count would cost a request per group.'))
            # A group the export read and then left out for a shared name has no count either.
            $Bullet | Should -Match ([regex]::Escape('A group left out of `inventory.json` and `groups.json` because another group shares its name has a `null` count too.'))
            # The bullet is the roster's, and the sentence about the flags stays in front of it.
            $Bullet | Should -Match ([regex]::Escape('and flags, including `onPremisesSynced`.'))
            $Bullet.IndexOf('including `onPremisesSynced`') | Should -BeLessThan $Bullet.IndexOf('Its `memberCount`')
            # The text is Markdown: no bare angle bracket, which GitHub would render as a tag.
            $Bullet | Should -Not -Match '[<>]'
        }
    }

    It 'explains in "Which groups are covered" that a synchronized group is detailed only on request and is never written by the apply (A15)' {
        InModuleScope $script:moduleName {
            $Md = Get-OERInventoryReadme -IncompleteReads @() -SkippedScopes @() -SkippedEligibilityScopes @() -PimLeftOut @() -RootScopeAssignments @() -SharedNames @() -UnresolvedPrincipalAssignments @() -UndeclarableScopeAssignments @() -RestrictedUnitPimGroups @() -LighthouseDelegations @() -ForeignSubscriptions @()
            $Md | Should -Match '(?m)^## Which groups are covered\r?$'
            $Section = (($Md -split '(?m)^## Which groups are covered\r?$')[1] -split '(?m)^## ')[0] -replace '\s+', ' '
            $Section | Should -Match ([regex]::Escape('A group synchronized from on-premises Active Directory (`onPremisesSynced` true in `groupsRoster.json`) is managed there and read-only in the cloud: it cannot be role-assignable or managed in PIM for Groups, so `inventory.json` details it only when the export ran with `-IncludeSyncedGroups` or `-AllGroupsDetailed`, and there it carries `onPremisesSynced: true`. `Invoke-OERStructure` writes nothing to such a group.'))
            # The paragraph belongs to the section it describes, ahead of the coverage limits.
            $Md.IndexOf('-IncludeSyncedGroups') | Should -BeLessThan $Md.IndexOf('## Coverage limits')
        }
    }

    It 'explains in "Which groups are covered" how the export chose the groups it detailed, and that -GroupFilter only narrows (A13)' {
        InModuleScope $script:moduleName {
            $Md = Get-OERInventoryReadme -IncompleteReads @() -SkippedScopes @() -SkippedEligibilityScopes @() -PimLeftOut @() -RootScopeAssignments @() -SharedNames @() -UnresolvedPrincipalAssignments @() -UndeclarableScopeAssignments @() -RestrictedUnitPimGroups @() -LighthouseDelegations @() -ForeignSubscriptions @()
            $Section = (($Md -split '(?m)^## Which groups are covered\r?$')[1] -split '(?m)^## ')[0] -replace '\s+', ' '
            # Which groups are detailed, and that a group found not relevant was never read in full.
            $Section | Should -Match ([regex]::Escape('Unless the export ran with `-AllGroupsDetailed`, `inventory.json` details only the RBAC-relevant security groups: role-assignable ones, ones with PIM eligibility, ones found to use PIM for Groups (written with a `pimPolicy` block), and synchronized ones when the export ran with `-IncludeSyncedGroups`.'))
            $Section | Should -Match ([regex]::Escape('The export decided that before reading any group in full, so a group it found not relevant had no members, owners or PIM policy read at all, and its absence from `inventory.json` says nothing about them.'))
            # An undecided group is read, and its gaps are listed, never guessed away.
            $Section | Should -Match ([regex]::Escape('A group whose relevance could not be decided was read in full, and what could not be read about it is listed under "What this export could not read".'))
            # The export's -GroupFilter narrows; the widening lever stays Get-OERInventory's.
            $Section | Should -Match ([regex]::Escape('The export''s own `-GroupFilter` only narrows this scope: `inventory.json` then covers only security groups the filter matched, never a group that is not security-enabled, while `groupsRoster.json` still lists every group.'))
            $Section.IndexOf('Unless the export ran with') | Should -BeGreaterThan $Section.IndexOf('Get-OERInventory -GroupFilter')
            # The roster bullet names the filter's null count too.
            $Bullet = (($Md -split '(?m)^- `groupsRoster\.json` ')[1] -split '(?m)^- ')[0] -replace '\s+', ' '
            $Bullet | Should -Match ([regex]::Escape('So has a security group outside the export''s `-GroupFilter`, which was not read.'))
        }
    }

    It 'warns that an unread members, scopedRoles, resources or resourceRoles collection is written as null and must never be changed to []' {
        InModuleScope $script:moduleName {
            $Md = Get-OERInventoryReadme -IncompleteReads @() -SkippedScopes @() -SkippedEligibilityScopes @() -PimLeftOut @() -RootScopeAssignments @() -SharedNames @() -UnresolvedPrincipalAssignments @() -UndeclarableScopeAssignments @() -RestrictedUnitPimGroups @() -LighthouseDelegations @() -ForeignSubscriptions @()
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
            # The partial is promised only for what the export REPORTS as unread, so a flat "every
            # collection it could not read" would be false of the others (an owners or eligibility
            # collection is omitted, and a policy list is []).
            $Section | Should -Match ([regex]::Escape('`InventoryPartial` error naming each collection it reports as unread, these four and any other; the others are left out or written only as far as they were read'))
            $Section | Should -Not -Match ([regex]::Escape('naming every collection it could not read, these four and any other')) -Because 'the others are left out or written only as far as they were read'
            # A section that could not be read at all is ALSO reported now, under its own name, and is
            # still written as an empty array; the group roster is named groupsRoster. The old text said
            # such a section had "no InventoryPartial", which is no longer true of any of them.
            $Section | Should -Match ([regex]::Escape('A section that could not be read at all (the group list, the administrative unit list or the access review list) is reported by a warning and through `InventoryPartial` under the section''s own name (`groups`, `administrativeUnits` or `accessReviews`), and is written as an empty array.'))
            $Section | Should -Match ([regex]::Escape('The group roster that could not be read is named `groupsRoster` in the export''s `IncompleteReads` and written as an empty array in `groupsRoster.json`.'))
            $Section | Should -Not -Match ([regex]::Escape('with no `InventoryPartial`')) -Because 'every unread section is named in the partial now'
            # An entry with no usable name is never written with an empty one.
            $Section | Should -Match ([regex]::Escape('An entry is never written with an empty name.'))
            $Section | Should -Match ([regex]::Escape('A group or application binding whose name cannot be read is written under its object id'))
            $Section | Should -Match ([regex]::Escape('makes its whole collection `null`, named in `InventoryPartial`, exactly like an unread one.'))
            # The reader is told where the list of what was NOT read is, so this section is not the
            # only place it has to look.
            $Section | Should -Match ([regex]::Escape('`Export-OERInventory` lists each such report, and each Azure scope it could not read, under "What this export could not read" above.'))
            # The section sits ahead of the numbered next steps it would otherwise be read after.
            $Md.IndexOf('## Unread collections') | Should -BeLessThan $Md.IndexOf('## Next steps')
        }
    }

    It 'tells the reader in Next steps that a proposal keeping tenantId is applied only in the tenant the export came from' {
        InModuleScope $script:moduleName {
            $Md = Get-OERInventoryReadme -IncompleteReads @() -SkippedScopes @() -SkippedEligibilityScopes @() -PimLeftOut @() -RootScopeAssignments @() -SharedNames @() -UnresolvedPrincipalAssignments @() -UndeclarableScopeAssignments @() -RestrictedUnitPimGroups @() -LighthouseDelegations @() -ForeignSubscriptions @()
            # Whitespace collapsed first, so the assertion does not depend on where the paragraph wraps.
            $Section = ($Md -split '(?m)^## Next steps\r?$')[1] -replace '\s+', ' '
            $Section | Should -Match ([regex]::Escape('A proposal that keeps the `tenantId` of `inventory.json` is applied only in the tenant this export came from: `Invoke-OERStructure` refuses it anywhere else. To apply it in another tenant, change or remove `tenantId` first.'))
            # The sentence follows the apply step it qualifies, inside the Next steps section.
            $Section.IndexOf('`Invoke-OERStructure -Path ./proposal.json`') | Should -BeLessThan $Section.IndexOf('A proposal that keeps the `tenantId`')
        }
    }

    It 'contains only ASCII characters' {
        InModuleScope $script:moduleName {
            $Bytes = [System.Text.Encoding]::UTF8.GetBytes((Get-OERInventoryReadme -IncompleteReads @() -SkippedScopes @() -SkippedEligibilityScopes @() -PimLeftOut @() -RootScopeAssignments @() -SharedNames @() -UnresolvedPrincipalAssignments @() -UndeclarableScopeAssignments @() -RestrictedUnitPimGroups @() -LighthouseDelegations @() -ForeignSubscriptions @()))
            ($Bytes | Where-Object { $_ -gt 127 }).Count | Should -Be 0
        }
    }
}

Describe 'Get-OERInventoryReadme (what this export could not read)' {
    # F2 / A17. IncompleteReads, SkippedScopes and SkippedEligibilityScopes used to exist only on the
    # object Export-OERInventory returns and in its InventoryPartial error, so whoever received the
    # bundle (an LLM, say) saw empty arrays and no list. The README is where the bundle explains
    # itself, so the list goes there -- in both states, since "nothing was left unread" is a claim
    # the reader needs to be able to rely on as much as the list itself.
    BeforeAll {
        # Builds the README through the private function and hands the string back to the test scope.
        function Get-TestReadme {
            param([string[]]$IncompleteReads = @(), [string[]]$SkippedScopes = @(), [string[]]$SkippedEligibilityScopes = @(), [object[]]$PimLeftOut = @())
            InModuleScope $script:moduleName -Parameters @{ A = $IncompleteReads; B = $SkippedScopes; C = $SkippedEligibilityScopes; D = $PimLeftOut } {
                param($A, $B, $C, $D)
                Get-OERInventoryReadme -IncompleteReads $A -SkippedScopes $B -SkippedEligibilityScopes $C -PimLeftOut $D -RootScopeAssignments @() -SharedNames @() -UnresolvedPrincipalAssignments @() -UndeclarableScopeAssignments @() -RestrictedUnitPimGroups @() -LighthouseDelegations @() -ForeignSubscriptions @()
            }
        }
        # The section, heading included, up to the next level 2 heading.
        function Get-TestSection {
            param([string]$Readme)
            $Start = $Readme.IndexOf('## What this export could not read')
            if ($Start -lt 0) { return $null }
            $Next = $Readme.IndexOf("`n## ", $Start)
            if ($Next -lt 0) { return $Readme.Substring($Start) }
            $Readme.Substring($Start, $Next - $Start)
        }
        function Get-TestBullets {
            param([string]$Section)
            @($Section -split '\r?\n' | Where-Object { $_ -like '- *' })
        }
    }

    It 'places the section right after the opening paragraph and ahead of ## Files (<State>)' -ForEach @(
        @{ State = 'partial'; Incomplete = @('groups') }
        @{ State = 'complete'; Incomplete = @() }
    ) {
        $Md = Get-TestReadme -IncompleteReads $Incomplete
        ([regex]::Matches($Md, '(?m)^## What this export could not read\r?$')).Count | Should -Be 1
        $Md | Should -Match '(?s)\A# OER RBAC Inventory Bundle\r?\n\r?\nThis folder was produced by.*?appliable improvement proposals\.\r?\n\r?\n## What this export could not read\r?\n.*?\r?\n\r?\n## Files\r?\n'
    }

    It 'lists every entry of the three lists as a bullet in a code span, in order, and says the bundle is partial' {
        $Md = Get-TestReadme `
            -IncompleteReads @('groups', 'groupsRoster') `
            -SkippedScopes @('<all Azure scopes: scope enumeration failed>', '/subscriptions/aaaaaaaa-0000-0000-0000-000000000001') `
            -SkippedEligibilityScopes @('/subscriptions/aaaaaaaa-0000-0000-0000-000000000002')
        $Section = Get-TestSection -Readme $Md
        $Section | Should -Not -BeNullOrEmpty
        $Expected = @(
            '- Entra ID: `groups`'
            '- Entra ID: `groupsRoster`'
            '- Azure scope, absent from `roleAssignments.json` and `roleManagementPolicies.json`: `<all Azure scopes: scope enumeration failed>`'
            '- Azure scope, absent from `roleAssignments.json` and `roleManagementPolicies.json`: `/subscriptions/aaaaaaaa-0000-0000-0000-000000000001`'
            '- Azure scope, absent from `azurePimEligibility.json`: `/subscriptions/aaaaaaaa-0000-0000-0000-000000000002`'
        )
        # One string, so a failure prints the whole list rather than the first element that differs.
        ((Get-TestBullets -Section $Section) -join "`n") | Should -BeExactly ($Expected -join "`n")
        # Whitespace collapsed first, so the assertions do not depend on where the prose wraps.
        $Collapsed = $Section -replace '\s+', ' '
        $Collapsed | Should -Match ([regex]::Escape('This bundle is PARTIAL: `Export-OERInventory` could not read, or could not write, everything it was asked to, so do not treat it as a full tenant snapshot.'))
        $Collapsed | Should -Match ([regex]::Escape('Apart from the entries labelled "Azure role management policies kept without being judged", "Role assignment principal that could not be read", "Azure Lighthouse read that failed" and "Azure subscription whose tenant could not be read", each entry below names collections or objects that could not be read, could not be written without an empty name, or were left out because two or more live objects share a name; none of them is stated as a fact in this bundle.'))
        # Sprint 11 step 6 (BL-133): a role assignment principal entry names a row that IS written, so the
        # intro says how each kind of it is written instead of counting it among the facts left out.
        $Collapsed | Should -Match ([regex]::Escape('An entry labelled "Role assignment principal that could not be read" names a row of `roleAssignments.json` as `roleAssignments/<role> -> <principal id> @ <scope>`, followed by `/principal` or `/principalStatus`. With `/principal`, the lookup of the principal failed: the row is written by the principal''s object id with no `principalStatus`, so whether the directory holds the principal is not known. With `/principalStatus`, the directory did not return the principal and the read of its deleted items failed: the row is written with `principalStatus` `Unresolved`, and the reason is not known.'))
        # Outside its code spans the intro holds no angle bracket: Markdown would read it as a tag.
        ($Collapsed -replace '`[^`]*`', '') | Should -Not -Match '<'
        # BL-107: the Azure role selection entry is the one kind that names no unread collection, so
        # the intro says what it means instead of counting it among the reads that failed.
        $Collapsed | Should -Match ([regex]::Escape('An entry labelled "Azure role management policies kept without being judged" names an Azure scope where the export could not tell, for at least one policy, whether its role is used there or whether the policy was changed, since a read it needed failed or the policy list gave nothing to judge by. Every policy there that it could not judge was kept, none of them left out -- where a role assignment or eligibility read failed, that is every policy of a role neither used nor changed at the scope -- so `roleManagementPolicies.json` may hold policies of roles that are neither used nor changed there. It does not mean every policy at the scope was kept: when only one policy could not be judged, the other unused, unchanged policies there are still left out.'))
        # A scope is named also when a single row could not be judged, so the intro never claims that
        # nothing at the scope was left out.
        $Collapsed | Should -Not -Match 'nothing is missing for that scope'
        # "Unread collections" covers an unread collection only; an object left out for a shared name
        # is said to be absent here, since that section does not describe it.
        $Collapsed | Should -Match ([regex]::Escape('"Unread collections" below says how an unread collection is written; an object left out for a shared name is absent from `inventory.json` and the per-area files, which does not mean the tenant has none.'))
        $Collapsed | Should -Not -Match ([regex]::Escape('says how each kind is written'))
        # The partial state never carries the complete state's claim.
        $Section | Should -Not -Match 'Nothing\.'
        $Section | Should -Not -Match 'read everything it was asked to read'
    }

    It 'lists a single entry of one list alone (<List>)' -ForEach @(
        @{ List = 'IncompleteReads'; Splat = @{ IncompleteReads = @('groupsRoster') }; Bullet = '- Entra ID: `groupsRoster`' }
        @{ List = 'SkippedScopes'; Splat = @{ SkippedScopes = @('/subscriptions/aaaaaaaa-0000-0000-0000-000000000001') }; Bullet = '- Azure scope, absent from `roleAssignments.json` and `roleManagementPolicies.json`: `/subscriptions/aaaaaaaa-0000-0000-0000-000000000001`' }
        @{ List = 'SkippedEligibilityScopes'; Splat = @{ SkippedEligibilityScopes = @('/subscriptions/aaaaaaaa-0000-0000-0000-000000000002') }; Bullet = '- Azure scope, absent from `azurePimEligibility.json`: `/subscriptions/aaaaaaaa-0000-0000-0000-000000000002`' }
    ) {
        # Each list alone is enough to make the bundle partial, and a list lands under its own label.
        $Section = Get-TestSection -Readme (Get-TestReadme @Splat)
        ((Get-TestBullets -Section $Section) -join "`n") | Should -BeExactly $Bullet
        $Section | Should -Match 'This bundle is PARTIAL'
        $Section | Should -Not -Match 'Nothing\.'
    }

    It 'says that nothing was left unread when every list is empty or holds only blank entries (<Case>)' -ForEach @(
        @{ Case = 'empty'; Incomplete = @(); Skipped = @(); Eligibility = @() }
        @{ Case = 'blank'; Incomplete = @('', '   '); Skipped = @(''); Eligibility = @("`t", '') }
    ) {
        $Section = Get-TestSection -Readme (Get-TestReadme -IncompleteReads $Incomplete -SkippedScopes $Skipped -SkippedEligibilityScopes $Eligibility)
        $Section | Should -Not -BeNullOrEmpty
        $Collapsed = $Section -replace '\s+', ' '
        $Collapsed | Should -Match 'Nothing\.'
        $Collapsed | Should -Match 'read everything it was asked to read'
        $Collapsed | Should -Match ([regex]::Escape('Nothing. `Export-OERInventory` read everything it was asked to read: no collection, section, group roster or Azure scope was reported as unread, and no `InventoryPartial` error was raised. The coverage limits below still apply -- they describe what this bundle never captures, not a read that failed.'))
        @(Get-TestBullets -Section $Section).Count | Should -Be 0
        $Section | Should -Not -MatchExactly 'This bundle is PARTIAL'
    }

    It 'labels an IncompleteReads entry that starts with roleManagementPolicies/ as Azure role management policies kept without being judged, and every other entry Entra ID' {
        # BL-107: the export appends one such entry per Azure scope whose role management policies were
        # kept without being judged, after the Entra ID entries. directoryRoleManagementPolicies/... is
        # an Entra ID entry: it only ends with the same words.
        $Section = Get-TestSection -Readme (Get-TestReadme -IncompleteReads @(
                'groupsRoster'
                'directoryRoleManagementPolicies/role selection'
                'roleManagementPolicies/role selection at /subscriptions/aaaaaaaa-0000-0000-0000-000000000001'
            ) -SkippedScopes @('/subscriptions/aaaaaaaa-0000-0000-0000-000000000002'))
        $Expected = @(
            '- Entra ID: `groupsRoster`'
            '- Entra ID: `directoryRoleManagementPolicies/role selection`'
            '- Azure role management policies kept without being judged: `roleManagementPolicies/role selection at /subscriptions/aaaaaaaa-0000-0000-0000-000000000001`'
            '- Azure scope, absent from `roleAssignments.json` and `roleManagementPolicies.json`: `/subscriptions/aaaaaaaa-0000-0000-0000-000000000002`'
        )
        ((Get-TestBullets -Section $Section) -join "`n") | Should -BeExactly ($Expected -join "`n")
        $Section | Should -Match 'This bundle is PARTIAL'
    }

    It 'labels an IncompleteReads entry that starts with roleAssignments/ as a role assignment principal that could not be read (Sprint 11 step 6, BL-133)' {
        # The export appends one such entry per role assignment principal it could not read, after the
        # Entra ID entries and before the role policy selection entries, and keeps it apart from both.
        $Section = Get-TestSection -Readme (Get-TestReadme -IncompleteReads @(
                'groupsRoster'
                'roleAssignments/Owner -> dddd7777-0000-0000-0000-000000000011 @ /subscriptions/aaaaaaaa-0000-0000-0000-000000000001/principal'
                'roleAssignments/Reader -> dddd7777-0000-0000-0000-000000000012 @ /subscriptions/aaaaaaaa-0000-0000-0000-000000000001/principalStatus'
                'roleManagementPolicies/role selection at /subscriptions/aaaaaaaa-0000-0000-0000-000000000001'
            ))
        $Expected = @(
            '- Entra ID: `groupsRoster`'
            '- Role assignment principal that could not be read: `roleAssignments/Owner -> dddd7777-0000-0000-0000-000000000011 @ /subscriptions/aaaaaaaa-0000-0000-0000-000000000001/principal`'
            '- Role assignment principal that could not be read: `roleAssignments/Reader -> dddd7777-0000-0000-0000-000000000012 @ /subscriptions/aaaaaaaa-0000-0000-0000-000000000001/principalStatus`'
            '- Azure role management policies kept without being judged: `roleManagementPolicies/role selection at /subscriptions/aaaaaaaa-0000-0000-0000-000000000001`'
        )
        ((Get-TestBullets -Section $Section) -join "`n") | Should -BeExactly ($Expected -join "`n")
        $Section | Should -Match 'This bundle is PARTIAL'
    }

    It 'shows an entry that looks like an HTML tag, since every entry is a code span' {
        $Entry = '<all Azure scopes: scope enumeration failed>'
        $Section = Get-TestSection -Readme (Get-TestReadme -SkippedScopes @($Entry) -SkippedEligibilityScopes @($Entry))
        $Bullets = @(Get-TestBullets -Section $Section)
        $Bullets.Count | Should -Be 2
        $Bullets[0] | Should -BeExactly ('- Azure scope, absent from `roleAssignments.json` and `roleManagementPolicies.json`: `' + $Entry + '`')
        $Bullets[1] | Should -BeExactly ('- Azure scope, absent from `azurePimEligibility.json`: `' + $Entry + '`')
        # Outside a code span the section holds no angle bracket at all: Markdown would read the
        # entry as an HTML tag and render nothing, so the reader would see an empty bullet.
        ($Section -replace '`[^`]*`', '') | Should -Not -Match '<'
    }

    It 'wraps an entry that holds a backtick in double backticks, and fences longer for a longer run' {
        $Section = Get-TestSection -Readme (Get-TestReadme -IncompleteReads @(
                'groups/Odd`Name/members'
                'groups/Odder``Name/members'
                '`edge`'
            ))
        $Expected = @(
            '- Entra ID: `` groups/Odd`Name/members ``'
            '- Entra ID: ``` groups/Odder``Name/members ```'
            '- Entra ID: `` `edge` ``'
        )
        ((Get-TestBullets -Section $Section) -join "`n") | Should -BeExactly ($Expected -join "`n")
    }

    It 'keeps an entry that holds a newline on one line' {
        $Entry = "groups/First line`r`nsecond line`nthird line`rfourth"
        $Section = Get-TestSection -Readme (Get-TestReadme -IncompleteReads @($Entry))
        $Bullets = @(Get-TestBullets -Section $Section)
        $Bullets.Count | Should -Be 1
        $Bullets[0] | Should -BeExactly '- Entra ID: `groups/First line second line third line fourth`'
        # No later line of the section carries a piece of the entry.
        @($Section -split '\r?\n' | Where-Object { $_ -match 'second line|third line|fourth' }).Count | Should -Be 1
    }

    It 'skips a blank entry among real ones and keeps the order of the rest' {
        $Section = Get-TestSection -Readme (Get-TestReadme -IncompleteReads @('', 'groups', '   ', 'groupsRoster'))
        $Expected = @('- Entra ID: `groups`', '- Entra ID: `groupsRoster`')
        ((Get-TestBullets -Section $Section) -join "`n") | Should -BeExactly ($Expected -join "`n")
    }

    It 'declares <Name> Mandatory, so a caller cannot forget it and write a README that claims a complete read' -ForEach @(
        @{ Name = 'IncompleteReads' }
        @{ Name = 'SkippedScopes' }
        @{ Name = 'SkippedEligibilityScopes' }
    ) {
        $Parameter = InModuleScope $script:moduleName -Parameters @{ N = $Name } {
            param($N)
            $Meta = (Get-Command Get-OERInventoryReadme).Parameters[$N]
            [PSCustomObject]@{
                Type           = $Meta.ParameterType
                Mandatory      = @($Meta.Attributes | Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] } | Where-Object { $_.Mandatory }).Count
                AllowsEmptyArr = @($Meta.Attributes | Where-Object { $_ -is [System.Management.Automation.AllowEmptyCollectionAttribute] }).Count
            }
        }
        $Parameter.Type | Should -Be ([string[]])
        $Parameter.Mandatory | Should -Be 1
        $Parameter.AllowsEmptyArr | Should -Be 1
    }

    It 'points the unread collections section and the next steps at the new section' {
        $Md = Get-TestReadme
        $Collapsed = $Md -replace '\s+', ' '
        $Collapsed | Should -Match ([regex]::Escape('2. Provide the prompt, this README and the JSON files to any capable LLM.'))
        $Collapsed | Should -Not -Match ([regex]::Escape('2. Provide the prompt and the JSON files to any capable LLM.'))
        # The Files bullet for the prompt says the same as the next steps: the README goes with it,
        # since the prompt's Inputs list opens with this README.
        $Collapsed | Should -Match ([regex]::Escape('then give it to any LLM together with this README and the JSON files above.'))
        $Collapsed | Should -Not -Match ([regex]::Escape('then give it to any LLM together with the JSON files above.'))
        $Collapsed | Should -Match ([regex]::Escape('under "What this export could not read" above'))
    }

    It 'contains only ASCII characters in the partial state too' {
        $Md = Get-TestReadme -IncompleteReads @('groupsRoster') -SkippedScopes @('<all Azure scopes: scope enumeration failed>') -SkippedEligibilityScopes @('/subscriptions/aaaaaaaa-0000-0000-0000-000000000002')
        $Md | Should -Match 'This bundle is PARTIAL'
        $Bytes = [System.Text.Encoding]::UTF8.GetBytes($Md)
        ($Bytes | Where-Object { $_ -gt 127 }).Count | Should -Be 0
    }
}

Describe 'Get-OERInventoryReadme (members and owners left out as PIM for Groups access, BL-125)' {
    # BL-125 (A3). A member or owner whose access PIM for Groups holds is left out of inventory.json, so
    # the README says so, per group by name and never by principal, in both states: "none was left
    # out" is a claim the reader needs to rely on as much as the list.
    BeforeAll {
        $script:PimHeading = '## Members and owners left out as PIM for Groups access'
        function Get-PimReadme {
            param([object[]]$PimLeftOut = @(), [string[]]$IncompleteReads = @())
            InModuleScope $script:moduleName -Parameters @{ P = $PimLeftOut; I = $IncompleteReads } {
                param($P, $I)
                Get-OERInventoryReadme -IncompleteReads $I -SkippedScopes @() -SkippedEligibilityScopes @() -PimLeftOut $P -RootScopeAssignments @() -SharedNames @() -UnresolvedPrincipalAssignments @() -UndeclarableScopeAssignments @() -RestrictedUnitPimGroups @() -LighthouseDelegations @() -ForeignSubscriptions @()
            }
        }
        # The section, heading included, up to the next level 2 heading; $null when it is missing.
        function Get-PimSection {
            param([string]$Readme)
            $Start = $Readme.IndexOf($script:PimHeading)
            if ($Start -lt 0) { return $null }
            $Next = $Readme.IndexOf("`n## ", $Start)
            if ($Next -lt 0) { return $Readme.Substring($Start) }
            $Readme.Substring($Start, $Next - $Start)
        }
        function Get-PimBullets {
            param([string]$Section)
            @($Section -split '\r?\n' | Where-Object { $_ -like '- *' })
        }
        function New-LeftOut {
            param([string]$GroupId, [string]$Group, [int]$Members, [int]$Owners, [string]$Basis)
            [PSCustomObject]@{ GroupId = $GroupId; Group = $Group; Members = $Members; Owners = $Owners; Basis = $Basis }
        }
        $script:PimProse = '`inventory.json` and `groups.json` write a group''s standing members and owners only. A member or owner whose access PIM for Groups holds -- an activation, or another active assignment that is not standing, such as a time-bound one -- is left out, since applying it would make access that PIM for Groups grants standing, past PIM''s time limit, approval and multi-factor authentication. Where the PIM for Groups assignments of a group could not be read, every member or owner that is also eligible for the same access was left out, and the group is listed under "What this export could not read"; where its eligibility could not be read either, its members and owners are not written -- `members` as `null`, `owners` left out -- unless they were read empty. A member or owner left out is still a member or owner in the tenant: leaving it out of the export changes nothing there.'
    }

    It 'never claims that a member or owner left out leaves the group' {
        # A standing member that is also eligible is left out on the Eligibility basis and stays a
        # member, so the section must not tie its membership to an activation ending.
        $Section = Get-PimSection -Readme (Get-PimReadme)
        $Collapsed = $Section -replace '\s+', ' '
        $Collapsed | Should -Not -Match 'until its activation'
        $Collapsed | Should -Not -Match 'time-bound assignment, ends'
        $Collapsed | Should -Match ([regex]::Escape('A member or owner left out is still a member or owner in the tenant: leaving it out of the export changes nothing there.'))
    }

    It 'places the section directly after "What this export could not read" and ahead of ## Files (<State>)' -ForEach @(
        @{ State = 'none left out, complete read'; LeftOut = @(); Incomplete = @() }
        @{ State = 'some left out, partial read'; LeftOut = @([PSCustomObject]@{ GroupId = 'g-1'; Group = 'role_sec_pim'; Members = 1; Owners = 0; Basis = 'Assignments' }); Incomplete = @('groups/role_sec_pim/pimAssignments') }
    ) {
        $Md = Get-PimReadme -PimLeftOut $LeftOut -IncompleteReads $Incomplete
        ([regex]::Matches($Md, '(?m)^## Members and owners left out as PIM for Groups access\r?$')).Count | Should -Be 1
        $Headings = @([regex]::Matches($Md, '(?m)^## .*$') | ForEach-Object { $_.Value.TrimEnd("`r") })
        $Index = [array]::IndexOf($Headings, '## What this export could not read')
        $Index | Should -BeGreaterOrEqual 0
        $Headings[$Index + 1] | Should -BeExactly $script:PimHeading
        # BL-126: the root scope section follows this one; BL-131: the shared names section follows
        # that; Sprint 11 step 6 (BL-133): the unresolved principals section follows that; A13, A15: the
        # undeclarable scope section follows that; BL-134: the restricted management unit section follows
        # that; Sprint 11 step 6b (BL-133): the Azure Lighthouse delegations section follows that; BL-150 (A19):
        # the subscriptions delegated from another tenant follow that, and ## Files follows it.
        $Headings[$Index + 2] | Should -BeExactly '## Role assignments at the root scope (elevated access)'
        $Headings[$Index + 3] | Should -BeExactly '## Names two or more objects share'
        $Headings[$Index + 4] | Should -BeExactly '## Role assignments whose principal the directory did not return'
        $Headings[$Index + 5] | Should -BeExactly '## Role assignments at a scope no document can declare'
        $Headings[$Index + 6] | Should -BeExactly '## Groups using PIM for Groups in a restricted management unit'
        $Headings[$Index + 7] | Should -BeExactly '## Azure Lighthouse delegations (access from another tenant)'
        $Headings[$Index + 8] | Should -BeExactly '## Subscriptions delegated from another tenant (not read)'
        $Headings[$Index + 9] | Should -BeExactly '## Files'
    }

    It 'says that none was left out when the list is empty' {
        $Section = Get-PimSection -Readme (Get-PimReadme)
        $Section | Should -Not -BeNullOrEmpty
        $Collapsed = $Section -replace '\s+', ' '
        $Collapsed | Should -Match ([regex]::Escape($script:PimProse))
        $Collapsed | Should -Match ([regex]::Escape('None. This export left no member or owner out as PIM for Groups access.'))
        @(Get-PimBullets -Section $Section).Count | Should -Be 0
    }

    It 'writes one bullet per group, in order, with the basis worded, and no "None"' {
        $Section = Get-PimSection -Readme (Get-PimReadme -PimLeftOut @(
                (New-LeftOut -GroupId 'g-1' -Group 'role_sec_pim' -Members 2 -Owners 1 -Basis 'Assignments')
                (New-LeftOut -GroupId 'g-2' -Group 'role_sec_other' -Members 0 -Owners 3 -Basis 'Eligibility')
            ))
        $Expected = @(
            '- `role_sec_pim`: 2 member(s) and 1 owner(s) left out -- an activation, or another active assignment that is not standing, such as a time-bound one, in PIM for Groups'
            '- `role_sec_other`: 0 member(s) and 3 owner(s) left out -- eligible for the same access; the group''s PIM for Groups assignments could not be read'
        )
        ((Get-PimBullets -Section $Section) -join "`n") | Should -BeExactly ($Expected -join "`n")
        ($Section -replace '\s+', ' ') | Should -Match ([regex]::Escape($script:PimProse))
        $Section | Should -Not -Match 'None\.'
    }

    It 'writes a group name as a code span with the fence rule of the other bullets, on one line' {
        $Section = Get-PimSection -Readme (Get-PimReadme -PimLeftOut @(
                (New-LeftOut -GroupId 'g-1' -Group 'Odd`Name' -Members 1 -Owners 0 -Basis 'Assignments')
                (New-LeftOut -GroupId 'g-2' -Group "<two`nlines>" -Members 1 -Owners 0 -Basis 'Assignments')
            ))
        $Expected = @(
            '- `` Odd`Name ``: 1 member(s) and 0 owner(s) left out -- an activation, or another active assignment that is not standing, such as a time-bound one, in PIM for Groups'
            '- `<two lines>`: 1 member(s) and 0 owner(s) left out -- an activation, or another active assignment that is not standing, such as a time-bound one, in PIM for Groups'
        )
        ((Get-PimBullets -Section $Section) -join "`n") | Should -BeExactly ($Expected -join "`n")
        # Outside its code span the bullet holds no angle bracket: Markdown would read it as a tag.
        ((Get-PimBullets -Section $Section)[1] -replace '`[^`]*`', '') | Should -Not -Match '<'
    }

    It 'names groups only, never a principal and never an id' {
        $Md = Get-PimReadme -PimLeftOut @(
            (New-LeftOut -GroupId '11111111-1111-1111-1111-111111111111' -Group 'role_sec_pim' -Members 1 -Owners 1 -Basis 'Assignments')
        )
        $Section = Get-PimSection -Readme $Md
        $Section | Should -Match ([regex]::Escape('`role_sec_pim`'))
        $Md | Should -Not -Match '11111111-1111-1111-1111-111111111111'
        $Section | Should -Not -Match '@'
    }

    It 'leaves the "What this export could not read" section exactly as it was' {
        $Without = Get-PimReadme -IncompleteReads @('groups/role_sec_pim/pimAssignments')
        $With = Get-PimReadme -IncompleteReads @('groups/role_sec_pim/pimAssignments') -PimLeftOut @(
            (New-LeftOut -GroupId 'g-1' -Group 'role_sec_pim' -Members 1 -Owners 0 -Basis 'Eligibility')
        )
        $Cut = { param($Md) $S = $Md.IndexOf('## What this export could not read'); $Md.Substring($S, $Md.IndexOf("`n## ", $S) - $S) }
        (& $Cut $With) | Should -BeExactly (& $Cut $Without)
        (& $Cut $With) | Should -Match ([regex]::Escape('- Entra ID: `groups/role_sec_pim/pimAssignments`'))
    }

    It 'declares PimLeftOut Mandatory, so a caller cannot forget it and write a README that claims nothing was left out' {
        $Parameter = InModuleScope $script:moduleName {
            $Meta = (Get-Command Get-OERInventoryReadme).Parameters['PimLeftOut']
            [PSCustomObject]@{
                Type           = $Meta.ParameterType
                Mandatory      = @($Meta.Attributes | Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] } | Where-Object { $_.Mandatory }).Count
                AllowsEmptyArr = @($Meta.Attributes | Where-Object { $_ -is [System.Management.Automation.AllowEmptyCollectionAttribute] }).Count
            }
        }
        $Parameter.Type | Should -Be ([object[]])
        $Parameter.Mandatory | Should -Be 1
        $Parameter.AllowsEmptyArr | Should -Be 1
    }

    It 'contains only ASCII characters with entries' {
        $Md = Get-PimReadme -PimLeftOut @(
            (New-LeftOut -GroupId 'g-1' -Group 'role_sec_pim' -Members 1 -Owners 2 -Basis 'Assignments')
            (New-LeftOut -GroupId 'g-2' -Group 'role_sec_other' -Members 1 -Owners 0 -Basis 'Eligibility')
        )
        $Bytes = [System.Text.Encoding]::UTF8.GetBytes($Md)
        ($Bytes | Where-Object { $_ -gt 127 }).Count | Should -Be 0
    }
}

Describe 'Get-OERInventoryReadme (role assignments at the root scope, BL-126)' {
    # BL-126 (R4). A role assignment at the Azure root scope '/' is elevated access, left out of
    # inventory.json and roleAssignments.json, so the README names each one -- role, principal and type
    # -- in both states: "none was read" is a claim the reader needs to rely on as much as the list.
    BeforeAll {
        $script:RootHeading = '## Role assignments at the root scope (elevated access)'
        function Get-RootReadme {
            param([object[]]$Rows = @())
            InModuleScope $script:moduleName -Parameters @{ R = $Rows } {
                param($R)
                Get-OERInventoryReadme -IncompleteReads @() -SkippedScopes @() -SkippedEligibilityScopes @() -PimLeftOut @() -RootScopeAssignments $R -SharedNames @() -UnresolvedPrincipalAssignments @() -UndeclarableScopeAssignments @() -RestrictedUnitPimGroups @() -LighthouseDelegations @() -ForeignSubscriptions @()
            }
        }
        # The section, heading included, up to the next level 2 heading; $null when it is missing.
        function Get-RootSection {
            param([string]$Readme)
            $Start = $Readme.IndexOf($script:RootHeading)
            if ($Start -lt 0) { return $null }
            $Next = $Readme.IndexOf("`n## ", $Start)
            if ($Next -lt 0) { return $Readme.Substring($Start) }
            $Readme.Substring($Start, $Next - $Start)
        }
        function Get-RootBullets {
            param([string]$Section)
            @($Section -split '\r?\n' | Where-Object { $_ -like '- *' })
        }
        function New-RootRow {
            param([string]$Role, [string]$Principal, [string]$PrincipalType, [string]$RoleAssignmentId = '')
            [PSCustomObject]@{ RoleAssignmentId = $RoleAssignmentId; Role = $Role; Principal = $Principal; PrincipalType = $PrincipalType }
        }
        $script:RootProse = 'The root scope `/` stands above every management group and subscription in the tenant, so a role assignment there reaches every Azure resource. It is elevated access -- most often User Access Administrator, which the Microsoft Entra setting "Access management for Azure resources" grants a Global Administrator -- and a finding to review, not part of the RBAC model this bundle describes. `inventory.json` and `roleAssignments.json` never carry a role assignment at the root scope, and `Invoke-OERStructure` never creates or removes one, even when a document declares it. Leaving them out of the export changes nothing in the tenant.'
        $script:RootNone = 'None. No role assignment this export read is at the root scope `/`. Role assignments are read only when the export includes `RoleAssignments`.'
    }

    It 'says that none was read when the list is empty' {
        $Section = Get-RootSection -Readme (Get-RootReadme)
        $Section | Should -Not -BeNullOrEmpty
        $Collapsed = $Section -replace '\s+', ' '
        $Collapsed | Should -Match ([regex]::Escape($script:RootProse))
        $Collapsed | Should -Match ([regex]::Escape($script:RootNone))
        @(Get-RootBullets -Section $Section).Count | Should -Be 0
        $Section | Should -Not -MatchExactly 'This export read \d+'
    }

    It 'writes the count line and one bullet per row, in the order given, and no "None"' {
        $Section = Get-RootSection -Readme (Get-RootReadme -Rows @(
                (New-RootRow -Role 'User Access Administrator' -Principal 'person1@example.com' -PrincipalType 'User')
                (New-RootRow -Role 'Owner' -Principal 'Zeta Partners' -PrincipalType '')
            ))
        ($Section -replace '\s+', ' ') | Should -Match ([regex]::Escape($script:RootProse))
        $Section | Should -Match '(?m)^This export read 2 role assignment\(s\) at the root scope:\r?$'
        $Expected = @(
            '- `User Access Administrator` for `person1@example.com` (User)'
            '- `Owner` for `Zeta Partners`'
        )
        ((Get-RootBullets -Section $Section) -join "`n") | Should -BeExactly ($Expected -join "`n")
        # The count line stands between the prose and the bullets.
        $Section.IndexOf('Leaving them') | Should -BeLessThan $Section.IndexOf('This export read 2')
        $Section.IndexOf('This export read 2') | Should -BeLessThan $Section.IndexOf('- `User Access Administrator`')
        $Section | Should -Not -Match 'None\.'
    }

    It 'writes a role or principal that holds a backtick as a code span with the fence rule of the other bullets' {
        $Section = Get-RootSection -Readme (Get-RootReadme -Rows @(
                (New-RootRow -Role 'Owner' -Principal 'Odd`Name' -PrincipalType 'Group')
            ))
        ((Get-RootBullets -Section $Section) -join "`n") | Should -BeExactly '- `Owner` for `` Odd`Name `` (Group)'
        $Section | Should -Match '(?m)^This export read 1 role assignment\(s\) at the root scope:\r?$'
    }

    It 'places the section after "Members and owners left out as PIM for Groups access" and ahead of ## Files (<State>)' -ForEach @(
        @{ State = 'none'; Rows = @() }
        @{ State = 'one row'; Rows = @([PSCustomObject]@{ RoleAssignmentId = ''; Role = 'Owner'; Principal = 'Ops'; PrincipalType = 'Group' }) }
    ) {
        $Md = Get-RootReadme -Rows $Rows
        ([regex]::Matches($Md, '(?m)^## Role assignments at the root scope \(elevated access\)\r?$')).Count | Should -Be 1
        $Headings = @([regex]::Matches($Md, '(?m)^## .*$') | ForEach-Object { $_.Value.TrimEnd("`r") })
        $Index = [array]::IndexOf($Headings, $script:RootHeading)
        $Headings[$Index - 1] | Should -BeExactly '## Members and owners left out as PIM for Groups access'
        # BL-131: the shared names section comes directly after this one; Sprint 11 step 6 (BL-133): the
        # unresolved principals section after that; A13, A15: the undeclarable scope section after that;
        # BL-134: the restricted management unit section after that; Sprint 11 step 6b (BL-133): the Azure
        # Lighthouse delegations section after that; BL-150 (A19): the subscriptions delegated from another
        # tenant after that, ahead of ## Files.
        $Headings[$Index + 1] | Should -BeExactly '## Names two or more objects share'
        $Headings[$Index + 2] | Should -BeExactly '## Role assignments whose principal the directory did not return'
        $Headings[$Index + 3] | Should -BeExactly '## Role assignments at a scope no document can declare'
        $Headings[$Index + 4] | Should -BeExactly '## Groups using PIM for Groups in a restricted management unit'
        $Headings[$Index + 5] | Should -BeExactly '## Azure Lighthouse delegations (access from another tenant)'
        $Headings[$Index + 6] | Should -BeExactly '## Subscriptions delegated from another tenant (not read)'
        $Headings[$Index + 7] | Should -BeExactly '## Files'
    }

    It 'names roles and principals only, never the role assignment id' {
        $Md = Get-RootReadme -Rows @(
            (New-RootRow -Role 'User Access Administrator' -Principal 'person1@example.com' -PrincipalType 'User' `
                    -RoleAssignmentId '/providers/Microsoft.Authorization/roleAssignments/11111111-1111-1111-1111-111111111111')
        )
        $Section = Get-RootSection -Readme $Md
        $Section | Should -Match ([regex]::Escape('`person1@example.com`'))
        $Md | Should -Not -Match '11111111-1111-1111-1111-111111111111'
        $Md | Should -Not -Match 'roleAssignments/'
    }

    It 'declares RootScopeAssignments Mandatory, so a caller cannot forget it and write a README that claims none was read' {
        $Parameter = InModuleScope $script:moduleName {
            $Meta = (Get-Command Get-OERInventoryReadme).Parameters['RootScopeAssignments']
            [PSCustomObject]@{
                Type           = $Meta.ParameterType
                Mandatory      = @($Meta.Attributes | Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] } | Where-Object { $_.Mandatory }).Count
                AllowsEmptyArr = @($Meta.Attributes | Where-Object { $_ -is [System.Management.Automation.AllowEmptyCollectionAttribute] }).Count
            }
        }
        $Parameter.Type | Should -Be ([object[]])
        $Parameter.Mandatory | Should -Be 1
        $Parameter.AllowsEmptyArr | Should -Be 1
    }

    It 'contains only ASCII characters with rows' {
        $Md = Get-RootReadme -Rows @(
            (New-RootRow -Role 'Owner' -Principal 'Ops' -PrincipalType 'Group')
        )
        $Bytes = [System.Text.Encoding]::UTF8.GetBytes($Md)
        ($Bytes | Where-Object { $_ -gt 127 }).Count | Should -Be 0
    }
}

Describe 'Get-OERInventoryReadme (names two or more objects share, BL-131)' {
    # BL-131 (R-3). Every object whose name another object of its kind shares is left out of
    # inventory.json, so the README names each such name with how many objects carry it and its
    # section, in both states: "no two objects share a name" is a claim the reader needs to rely on as
    # much as the list.
    BeforeAll {
        $script:SharedHeading = '## Names two or more objects share'
        function Get-SharedReadme {
            param([object[]]$Names = @())
            InModuleScope $script:moduleName -Parameters @{ S = $Names } {
                param($S)
                Get-OERInventoryReadme -IncompleteReads @() -SkippedScopes @() -SkippedEligibilityScopes @() -PimLeftOut @() -RootScopeAssignments @() -SharedNames $S -UnresolvedPrincipalAssignments @() -UndeclarableScopeAssignments @() -RestrictedUnitPimGroups @() -LighthouseDelegations @() -ForeignSubscriptions @()
            }
        }
        # The section, heading included, up to the next level 2 heading; $null when it is missing.
        function Get-SharedSection {
            param([string]$Readme)
            $Start = $Readme.IndexOf($script:SharedHeading)
            if ($Start -lt 0) { return $null }
            $Next = $Readme.IndexOf("`n## ", $Start)
            if ($Next -lt 0) { return $Readme.Substring($Start) }
            $Readme.Substring($Start, $Next - $Start)
        }
        function Get-SharedBullets {
            param([string]$Section)
            @($Section -split '\r?\n' | Where-Object { $_ -like '- *' })
        }
        function New-SharedName {
            param([string]$Section, [string]$Name, [int]$Count)
            [PSCustomObject]@{ Section = $Section; Name = $Name; Count = $Count }
        }
        $script:SharedProse = 'Microsoft Entra ID does not keep display names unique, and `Invoke-OERStructure` refuses a name that more than one live object answers to. So every object whose name another object of its kind shares, compared without regard to letter case, is left out of `inventory.json` and the per-area files -- all of them -- and is named under "What this export could not read" too. Groups are counted over every group in the tenant, Microsoft 365 groups and distribution groups included, so a security group that shares its name with one of those is left out as well; when the group roster could not be read (`groupsRoster` under "What this export could not read"), groups are counted among the security groups the export read. An access package''s name is counted among the packages of its catalog, and an assignment policy''s among the policies of its own access package only; a policy is listed with section `assignmentPolicies` as `<package>/<policy>`. The name of an administrative unit, a catalog or an access review is counted among the ones this export read, an access review''s among the access-package reviews it captured. A reference to such an object elsewhere in the document is written as the object''s id: the catalog of an access package, the access package and assignment policy of an access review, and a group named as the principal of a role assignment or a directory role assignment, written with `principalType` `Group`. A group named in any other place -- an eligibility principal, a reviewer, a catalog resource, a resource role, a member of a group or an administrative unit -- still carries its name (or its id where the export always writes ids), and an ambiguous name there is refused when applied, with nothing written for it. Leaving them out of the export changes nothing in the tenant.'
        $script:SharedNone = 'None. No two objects this export read share a name.'
    }

    It 'says that no two objects share a name when the list is empty' {
        $Section = Get-SharedSection -Readme (Get-SharedReadme)
        $Section | Should -Not -BeNullOrEmpty
        $Collapsed = $Section -replace '\s+', ' '
        $Collapsed | Should -Match ([regex]::Escape($script:SharedProse))
        $Collapsed | Should -Match ([regex]::Escape($script:SharedNone))
        @(Get-SharedBullets -Section $Section).Count | Should -Be 0
    }

    It 'says where the name of each kind is counted, an assignment policy''s within its own access package, and how a policy is listed (Sprint 11 step 5)' {
        $Collapsed = (Get-SharedSection -Readme (Get-SharedReadme)) -replace '\s+', ' '
        $Collapsed | Should -Match ([regex]::Escape('An access package''s name is counted among the packages of its catalog, and an assignment policy''s among the policies of its own access package only; a policy is listed with section `assignmentPolicies` as `<package>/<policy>`.'))
        # The other kinds are counted among the objects the export read, never over the whole tenant.
        $Collapsed | Should -Match ([regex]::Escape('The name of an administrative unit, a catalog or an access review is counted among the ones this export read, an access review''s among the access-package reviews it captured.'))
        # They follow the sentence on how groups are counted and precede the one on references by id.
        $Collapsed.IndexOf('An access package''s name is counted') | Should -BeGreaterThan $Collapsed.IndexOf('groups are counted among the security groups the export read.')
        $Collapsed.IndexOf('The name of an administrative unit, a catalog or an access review') | Should -BeGreaterThan $Collapsed.IndexOf('An access package''s name is counted')
        $Collapsed.IndexOf('The name of an administrative unit, a catalog or an access review') | Should -BeLessThan $Collapsed.IndexOf('A reference to such an object elsewhere')
        # The group principal written by id is the one of a role assignment or a directory role
        # assignment: a group named elsewhere (an eligibility principal, a reviewer) keeps its name.
        $Collapsed | Should -Not -Match ([regex]::Escape('and a group named as a principal, written'))
        # And that is said, after the references by id and before the closing sentence.
        $Collapsed | Should -Match ([regex]::Escape('A group named in any other place -- an eligibility principal, a reviewer, a catalog resource, a resource role, a member of a group or an administrative unit -- still carries its name (or its id where the export always writes ids), and an ambiguous name there is refused when applied, with nothing written for it.'))
        $Collapsed.IndexOf('A group named in any other place') | Should -BeGreaterThan $Collapsed.IndexOf('A reference to such an object elsewhere')
        $Collapsed.IndexOf('A group named in any other place') | Should -BeLessThan $Collapsed.IndexOf('Leaving them out')
        # Outside its code spans the prose holds no angle bracket: Markdown would read it as a tag.
        ($Collapsed -replace '`[^`]*`', '') | Should -Not -Match '<'
    }

    It 'writes one bullet per name, in the order given, with its count and section, and no "None"' {
        $Section = Get-SharedSection -Readme (Get-SharedReadme -Names @(
                (New-SharedName -Section 'groups' -Name 'Admins' -Count 2)
                (New-SharedName -Section 'administrativeUnits' -Name 'Region North' -Count 3)
                (New-SharedName -Section 'accessPackages' -Name 'Catalog One/Package' -Count 2)
            ))
        $Expected = @(
            '- `Admins` -- 2 objects, section `groups`'
            '- `Region North` -- 3 objects, section `administrativeUnits`'
            '- `Catalog One/Package` -- 2 objects, section `accessPackages`'
        )
        ((Get-SharedBullets -Section $Section) -join "`n") | Should -BeExactly ($Expected -join "`n")
        ($Section -replace '\s+', ' ') | Should -Match ([regex]::Escape($script:SharedProse))
        $Section | Should -Not -Match 'None\.'
        # The bullets stand after the prose.
        $Section.IndexOf('Leaving them out') | Should -BeLessThan $Section.IndexOf('- `Admins`')
    }

    It 'writes a name that holds a backtick or an angle bracket as a code span with the fence rule of the other bullets, on one line' {
        $Section = Get-SharedSection -Readme (Get-SharedReadme -Names @(
                (New-SharedName -Section 'groups' -Name 'Odd`Name' -Count 2)
                (New-SharedName -Section 'groups' -Name "<two`nlines>" -Count 4)
            ))
        $Expected = @(
            '- `` Odd`Name `` -- 2 objects, section `groups`'
            '- `<two lines>` -- 4 objects, section `groups`'
        )
        ((Get-SharedBullets -Section $Section) -join "`n") | Should -BeExactly ($Expected -join "`n")
        # Outside its code span the bullet holds no angle bracket: Markdown would read it as a tag.
        ((Get-SharedBullets -Section $Section)[1] -replace '`[^`]*`', '') | Should -Not -Match '<'
    }

    It 'places the section directly after "Role assignments at the root scope (elevated access)" and ahead of ## Files (<State>)' -ForEach @(
        @{ State = 'none'; Names = @() }
        @{ State = 'one name'; Names = @([PSCustomObject]@{ Section = 'groups'; Name = 'Admins'; Count = 2 }) }
    ) {
        $Md = Get-SharedReadme -Names $Names
        ([regex]::Matches($Md, '(?m)^## Names two or more objects share\r?$')).Count | Should -Be 1
        $Headings = @([regex]::Matches($Md, '(?m)^## .*$') | ForEach-Object { $_.Value.TrimEnd("`r") })
        $Index = [array]::IndexOf($Headings, $script:SharedHeading)
        $Index | Should -BeGreaterThan 0
        $Headings[$Index - 1] | Should -BeExactly '## Role assignments at the root scope (elevated access)'
        # Sprint 11 step 6 (BL-133): the section on role assignment principals that could not be looked
        # up comes directly after this one; A13, A15: the undeclarable scope section after that; BL-134: the
        # restricted management unit section after that; Sprint 11 step 6b (BL-133): the Azure Lighthouse
        # delegations section after that; BL-150 (A19): the subscriptions delegated from another tenant after
        # that, ahead of ## Files.
        $Headings[$Index + 1] | Should -BeExactly '## Role assignments whose principal the directory did not return'
        $Headings[$Index + 2] | Should -BeExactly '## Role assignments at a scope no document can declare'
        $Headings[$Index + 3] | Should -BeExactly '## Groups using PIM for Groups in a restricted management unit'
        $Headings[$Index + 4] | Should -BeExactly '## Azure Lighthouse delegations (access from another tenant)'
        $Headings[$Index + 5] | Should -BeExactly '## Subscriptions delegated from another tenant (not read)'
        $Headings[$Index + 6] | Should -BeExactly '## Files'
    }

    It 'leaves the other sections exactly as they were' {
        $Without = Get-SharedReadme
        $With = Get-SharedReadme -Names @((New-SharedName -Section 'groups' -Name 'Admins' -Count 2))
        $Cut = { param($Md) $S = $Md.IndexOf($script:SharedHeading); $Md.Remove($S, $Md.IndexOf("`n## ", $S) - $S) }
        (& $Cut $With) | Should -BeExactly (& $Cut $Without)
    }

    It 'declares SharedNames Mandatory, so a caller cannot forget it and write a README that claims no name is shared' {
        $Parameter = InModuleScope $script:moduleName {
            $Meta = (Get-Command Get-OERInventoryReadme).Parameters['SharedNames']
            [PSCustomObject]@{
                Type           = $Meta.ParameterType
                Mandatory      = @($Meta.Attributes | Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] } | Where-Object { $_.Mandatory }).Count
                AllowsEmptyArr = @($Meta.Attributes | Where-Object { $_ -is [System.Management.Automation.AllowEmptyCollectionAttribute] }).Count
            }
        }
        $Parameter.Type | Should -Be ([object[]])
        $Parameter.Mandatory | Should -Be 1
        $Parameter.AllowsEmptyArr | Should -Be 1
    }

    It 'contains only ASCII characters with names' {
        $Md = Get-SharedReadme -Names @((New-SharedName -Section 'groups' -Name 'Admins' -Count 2))
        $Bytes = [System.Text.Encoding]::UTF8.GetBytes($Md)
        ($Bytes | Where-Object { $_ -gt 127 }).Count | Should -Be 0
    }
}

Describe 'Get-OERInventoryReadme (role assignments whose principal the directory did not return, Sprint 11 step 6, BL-133)' {
    # BL-133 (A18). A role assignment whose principal the directory does not return stays in the
    # document, written by its object id with principalStatus, so the README names each one -- role,
    # scope, principal, type and the reason -- in both states: "none" is a claim the reader needs to rely
    # on as much as the list. No id below is version-4 shaped.
    BeforeAll {
        $script:UpHeading = '## Role assignments whose principal the directory did not return'
        function Get-UpReadme {
            param([object[]]$Rows = @())
            InModuleScope $script:moduleName -Parameters @{ U = $Rows } {
                param($U)
                Get-OERInventoryReadme -IncompleteReads @() -SkippedScopes @() -SkippedEligibilityScopes @() -PimLeftOut @() -RootScopeAssignments @() -SharedNames @() -UnresolvedPrincipalAssignments $U -UndeclarableScopeAssignments @() -RestrictedUnitPimGroups @() -LighthouseDelegations @() -ForeignSubscriptions @()
            }
        }
        # The section, heading included, up to the next level 2 heading; $null when it is missing.
        function Get-UpSection {
            param([string]$Readme)
            $Start = $Readme.IndexOf($script:UpHeading)
            if ($Start -lt 0) { return $null }
            $Next = $Readme.IndexOf("`n## ", $Start)
            if ($Next -lt 0) { return $Readme.Substring($Start) }
            $Readme.Substring($Start, $Next - $Start)
        }
        function Get-UpBullets {
            param([string]$Section)
            @($Section -split '\r?\n' | Where-Object { $_ -like '- *' })
        }
        # The row shape of the Omnicit.EntraRBAC.UnresolvedPrincipal notice; StatusRead says whether the
        # deleted items read behind PrincipalStatus succeeded.
        function New-UpRow {
            param([string]$Scope, [string]$Role, [string]$Principal, [string]$PrincipalType, [string]$PrincipalStatus, [bool]$StatusRead = $true, [string]$RoleAssignmentId = '')
            [PSCustomObject]@{
                RoleAssignmentId = $RoleAssignmentId; Scope = $Scope; Role = $Role; Principal = $Principal
                PrincipalType = $PrincipalType; PrincipalStatus = $PrincipalStatus; StatusRead = $StatusRead
            }
        }
        $script:UpProse = 'A role assignment can name a principal that Microsoft Entra ID does not return: one that was deleted, or one this directory cannot read. Such an assignment stays in `inventory.json` and `roleAssignments.json`, with its principal written as the object id and `principalStatus` saying why: `Deleted` or `Unresolved`. Where this section lists an assignment, its entry says what its status means. `Invoke-OERStructure` never creates such an assignment, and removing its entry from the document lets `-Prune` remove it, like any undeclared assignment, at a scope the document still declares. A principal whose lookup failed is not listed here: it is written by its object id without `principalStatus` and named under "What this export could not read". Where the read of its deleted items failed, the principal is listed here as `Unresolved` with the reason not known, and that read is named there too.'
        $script:UpNone = 'None. No role assignment this export read names a principal that the directory did not return, apart from any whose lookup failed, which are named under "What this export could not read". Role assignments are read only when the export includes `RoleAssignments`.'
        $script:UpDeletedReason = 'found among the directory''s deleted items'
        $script:UpUnresolvedReason = 'found neither in the directory nor among its deleted items (deleted beyond the retention period, a principal of another tenant, for example through Azure Lighthouse, or not readable)'
        $script:UpUnknownReason = 'not returned by the directory, and the read of its deleted items failed, so the reason is not known; that read is named under "What this export could not read"'
    }

    It 'gives an Unresolved row whose deleted items read failed no reason as a fact, and says why' {
        $Section = Get-UpSection -Readme (Get-UpReadme -Rows @(
                (New-UpRow -Scope '/subscriptions/aaaa1111-0000-0000-0000-000000000001' -Role 'Reader' -Principal 'dddd7777-0000-0000-0000-000000000021' -PrincipalType 'User' -PrincipalStatus 'Unresolved' -StatusRead $false)
                (New-UpRow -Scope '/subscriptions/aaaa1111-0000-0000-0000-000000000001' -Role 'Owner' -Principal 'dddd7777-0000-0000-0000-000000000022' -PrincipalType 'User' -PrincipalStatus 'Unresolved' -StatusRead $true)
            ))
        $Expected = @(
            "- ``Reader`` at ``/subscriptions/aaaa1111-0000-0000-0000-000000000001`` for ``dddd7777-0000-0000-0000-000000000021`` (User): ``Unresolved``, $($script:UpUnknownReason)"
            "- ``Owner`` at ``/subscriptions/aaaa1111-0000-0000-0000-000000000001`` for ``dddd7777-0000-0000-0000-000000000022`` (User): ``Unresolved``, $($script:UpUnresolvedReason)"
        )
        ((Get-UpBullets -Section $Section) -join "`n") | Should -BeExactly ($Expected -join "`n")
    }

    It 'reads a row with no StatusRead as a status whose read is not known to have succeeded' {
        # A row without the member says nothing about the read, so its reason is not stated as a fact.
        $Row = [PSCustomObject]@{ RoleAssignmentId = ''; Scope = '/subscriptions/x'; Role = 'Reader'; Principal = 'dddd7777-0000-0000-0000-000000000023'; PrincipalType = ''; PrincipalStatus = 'Unresolved' }
        $Bullets = @(Get-UpBullets -Section (Get-UpSection -Readme (Get-UpReadme -Rows @($Row))))
        $Bullets | Should -Be @("- ``Reader`` at ``/subscriptions/x`` for ``dddd7777-0000-0000-0000-000000000023``: ``Unresolved``, $($script:UpUnknownReason)")
    }

    It 'says that none was found when the list is empty' {
        $Section = Get-UpSection -Readme (Get-UpReadme)
        $Section | Should -Not -BeNullOrEmpty
        $Collapsed = $Section -replace '\s+', ' '
        $Collapsed | Should -Match ([regex]::Escape($script:UpProse))
        $Collapsed | Should -Match ([regex]::Escape($script:UpNone))
        @(Get-UpBullets -Section $Section).Count | Should -Be 0
        $Section | Should -Not -Match 'This export read \d+'
    }

    It 'writes the count line and one bullet per row, in the order given, with the reason in words, and no "None"' {
        $Section = Get-UpSection -Readme (Get-UpReadme -Rows @(
                (New-UpRow -Scope '/subscriptions/aaaa1111-0000-0000-0000-000000000001' -Role 'Reader' -Principal 'dddd7777-0000-0000-0000-000000000001' -PrincipalType 'User' -PrincipalStatus 'Deleted')
                (New-UpRow -Scope '/providers/Microsoft.Management/managementGroups/plat' -Role 'Owner' -Principal 'dddd7777-0000-0000-0000-000000000002' -PrincipalType '' -PrincipalStatus 'Unresolved')
            ))
        ($Section -replace '\s+', ' ') | Should -Match ([regex]::Escape($script:UpProse))
        $Section | Should -Match '(?m)^This export read 2 such role assignment\(s\):\r?$'
        $Expected = @(
            "- ``Reader`` at ``/subscriptions/aaaa1111-0000-0000-0000-000000000001`` for ``dddd7777-0000-0000-0000-000000000001`` (User): ``Deleted``, $($script:UpDeletedReason)"
            "- ``Owner`` at ``/providers/Microsoft.Management/managementGroups/plat`` for ``dddd7777-0000-0000-0000-000000000002``: ``Unresolved``, $($script:UpUnresolvedReason)"
        )
        ((Get-UpBullets -Section $Section) -join "`n") | Should -BeExactly ($Expected -join "`n")
        # The count line stands between the prose and the bullets (read on the collapsed text, so a line
        # break inside the prose cannot hide either index).
        $Collapsed = $Section -replace '\s+', ' '
        $Collapsed.IndexOf('and that read is named there too.') | Should -BeGreaterThan 0
        $Collapsed.IndexOf('and that read is named there too.') | Should -BeLessThan $Collapsed.IndexOf('This export read 2')
        $Collapsed.IndexOf('This export read 2') | Should -BeLessThan $Collapsed.IndexOf('- `Reader`')
        $Section | Should -Not -Match 'None\.'
    }

    It 'writes a value that holds a backtick or an angle bracket as a code span with the fence rule of the other bullets, on one line' {
        $Section = Get-UpSection -Readme (Get-UpReadme -Rows @(
                (New-UpRow -Scope "/subscriptions/x/resourceGroups/<rg`nnew>" -Role 'Odd`Role' -Principal 'dddd7777-0000-0000-0000-000000000003' -PrincipalType 'Group' -PrincipalStatus 'Deleted')
            ))
        # The role holds a backtick, so its fence is two; the scope holds an angle bracket and a line
        # break, so it stays inside its code span, on one line.
        ((Get-UpBullets -Section $Section) -join "`n") | Should -BeExactly "- ```` Odd``Role ```` at ``/subscriptions/x/resourceGroups/<rg new>`` for ``dddd7777-0000-0000-0000-000000000003`` (Group): ``Deleted``, $($script:UpDeletedReason)"
    }

    It 'places the section directly after "Names two or more objects share" and ahead of "Role assignments at a scope no document can declare" (<State>)' -ForEach @(
        @{ State = 'none'; Rows = @() }
        @{ State = 'one row'; Rows = @([PSCustomObject]@{ RoleAssignmentId = ''; Scope = '/subscriptions/x'; Role = 'Owner'; Principal = 'dddd7777-0000-0000-0000-000000000004'; PrincipalType = 'Group'; PrincipalStatus = 'Unresolved' }) }
    ) {
        $Md = Get-UpReadme -Rows $Rows
        ([regex]::Matches($Md, '(?m)^## Role assignments whose principal the directory did not return\r?$')).Count | Should -Be 1
        $Headings = @([regex]::Matches($Md, '(?m)^## .*$') | ForEach-Object { $_.Value.TrimEnd("`r") })
        $Index = [array]::IndexOf($Headings, $script:UpHeading)
        $Index | Should -BeGreaterThan 0
        $Headings[$Index - 1] | Should -BeExactly '## Names two or more objects share'
        $Headings[$Index + 1] | Should -BeExactly '## Role assignments at a scope no document can declare'
    }

    It 'names role, scope, principal, type and status only, never the role assignment id' {
        $Md = Get-UpReadme -Rows @(
            (New-UpRow -Scope '/subscriptions/x' -Role 'Reader' -Principal 'dddd7777-0000-0000-0000-000000000005' -PrincipalType 'User' -PrincipalStatus 'Deleted' `
                    -RoleAssignmentId '/subscriptions/x/providers/Microsoft.Authorization/roleAssignments/cccc7777-0000-0000-0000-000000000001')
        )
        (Get-UpSection -Readme $Md) | Should -Match ([regex]::Escape('`dddd7777-0000-0000-0000-000000000005`'))
        $Md | Should -Not -Match 'cccc7777-0000-0000-0000-000000000001'
    }

    It 'leaves the other sections exactly as they were' {
        $Without = Get-UpReadme
        $With = Get-UpReadme -Rows @((New-UpRow -Scope '/subscriptions/x' -Role 'Reader' -Principal 'dddd7777-0000-0000-0000-000000000006' -PrincipalType 'User' -PrincipalStatus 'Unresolved'))
        $Cut = { param($Md) $S = $Md.IndexOf($script:UpHeading); $Md.Remove($S, $Md.IndexOf("`n## ", $S) - $S) }
        (& $Cut $With) | Should -BeExactly (& $Cut $Without)
    }

    It 'declares UnresolvedPrincipalAssignments Mandatory, so a caller cannot forget it and write a README that claims none was found' {
        $Parameter = InModuleScope $script:moduleName {
            $Meta = (Get-Command Get-OERInventoryReadme).Parameters['UnresolvedPrincipalAssignments']
            [PSCustomObject]@{
                Type           = $Meta.ParameterType
                Mandatory      = @($Meta.Attributes | Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] } | Where-Object { $_.Mandatory }).Count
                AllowsEmptyArr = @($Meta.Attributes | Where-Object { $_ -is [System.Management.Automation.AllowEmptyCollectionAttribute] }).Count
            }
        }
        $Parameter.Type | Should -Be ([object[]])
        $Parameter.Mandatory | Should -Be 1
        $Parameter.AllowsEmptyArr | Should -Be 1
    }

    It 'contains only ASCII characters with rows' {
        $Md = Get-UpReadme -Rows @((New-UpRow -Scope '/subscriptions/x' -Role 'Reader' -Principal 'dddd7777-0000-0000-0000-000000000007' -PrincipalType 'User' -PrincipalStatus 'Deleted'))
        $Bytes = [System.Text.Encoding]::UTF8.GetBytes($Md)
        ($Bytes | Where-Object { $_ -gt 127 }).Count | Should -Be 0
    }
}

Describe 'Get-OERInventoryReadme (role assignments at a scope no document can declare, A13, A15)' {
    # A role assignment whose scope breaks a scope spelling rule the validator applies is left out of
    # inventory.json and roleAssignments.json, so the README names each one -- role, scope, principal,
    # type and the rules the scope breaks -- in both states: "none" is a claim the reader needs to rely on
    # as much as the list. Scopes holding '#' or '%' are fixtures only. No id below is version-4 shaped.
    BeforeAll {
        $script:UdHeading = '## Role assignments at a scope no document can declare'
        function Get-UdReadme {
            param([object[]]$Rows = @())
            InModuleScope $script:moduleName -Parameters @{ D = $Rows } {
                param($D)
                Get-OERInventoryReadme -IncompleteReads @() -SkippedScopes @() -SkippedEligibilityScopes @() -PimLeftOut @() -RootScopeAssignments @() -SharedNames @() -UnresolvedPrincipalAssignments @() -UndeclarableScopeAssignments $D -RestrictedUnitPimGroups @() -LighthouseDelegations @() -ForeignSubscriptions @()
            }
        }
        # The section, heading included, up to the next level 2 heading; $null when it is missing.
        function Get-UdSection {
            param([string]$Readme)
            $Start = $Readme.IndexOf($script:UdHeading)
            if ($Start -lt 0) { return $null }
            $Next = $Readme.IndexOf("`n## ", $Start)
            if ($Next -lt 0) { return $Readme.Substring($Start) }
            $Readme.Substring($Start, $Next - $Start)
        }
        function Get-UdBullets {
            param([string]$Section)
            @($Section -split '\r?\n' | Where-Object { $_ -like '- *' })
        }
        # The row shape of the Omnicit.EntraRBAC.UndeclarableScope notice.
        function New-UdRow {
            param([string]$Scope, [string]$Role, [string]$Principal, [string]$PrincipalType, [string]$Reason, [string]$RoleAssignmentId = '')
            [PSCustomObject]@{
                RoleAssignmentId = $RoleAssignmentId; Scope = $Scope; Role = $Role; Principal = $Principal
                PrincipalType = $PrincipalType; Reason = $Reason
            }
        }
        # Sprint 11 step 6: the prose gives an example and leaves the rules to the owner
        # (Get-OERScopeSpellingProblem) and to each row's reason, so a new rule cannot leave it incomplete.
        $script:UdProse = 'Azure Resource Manager can return a role assignment at a scope whose spelling the validator (`Test-OERStructure`, which `Invoke-OERStructure` runs first) refuses, for example the scope of a resource whose name holds a `#` or a `%`. Where this section lists an assignment, its entry names the rules its scope breaks. No document can declare such a scope, and a document that carried one would be refused as a whole, so `inventory.json` and `roleAssignments.json` leave the assignment out. `Invoke-OERStructure` never creates a role assignment at such a scope, and never removes one, since it prunes only at a scope a document declares. A role assignment at the root scope is listed under "Role assignments at the root scope (elevated access)" only. Leaving them out of the export changes nothing in the tenant.'
        $script:UdNone = 'None. No role assignment this export read is at a scope a document cannot declare. Role assignments are read only when the export includes `RoleAssignments`.'
        $script:UdSub = '/subscriptions/aaaa1111-0000-0000-0000-000000000001'
    }

    It 'says that none was read when the list is empty' {
        $Section = Get-UdSection -Readme (Get-UdReadme)
        $Section | Should -Not -BeNullOrEmpty
        $Collapsed = $Section -replace '\s+', ' '
        $Collapsed | Should -Match ([regex]::Escape($script:UdProse))
        $Collapsed | Should -Match ([regex]::Escape($script:UdNone))
        @(Get-UdBullets -Section $Section).Count | Should -Be 0
        $Section | Should -Not -Match 'This export read \d+'
    }

    It 'writes the count line and one bullet per row, in the order given, with the reason in words, and no "None"' {
        $Section = Get-UdSection -Readme (Get-UdReadme -Rows @(
                (New-UdRow -Scope "$($script:UdSub)/resourceGroups/rg-one/providers/Microsoft.Sql/servers/srv1/databases/db#1" -Role 'Reader' -Principal 'person1@example.com' -PrincipalType 'User' -Reason 'the scope holds a question mark or a number sign')
                (New-UdRow -Scope "$($script:UdSub)/resourceGroups/rg%2Fone" -Role 'Owner' -Principal 'dddd6666-0000-0000-0000-000000000002' -PrincipalType '' -Reason 'the scope holds a percent sign')
            ))
        ($Section -replace '\s+', ' ') | Should -Match ([regex]::Escape($script:UdProse))
        $Section | Should -Match '(?m)^This export read 2 such role assignment\(s\):\r?$'
        $Expected = @(
            "- ``Reader`` at ``$($script:UdSub)/resourceGroups/rg-one/providers/Microsoft.Sql/servers/srv1/databases/db#1`` for ``person1@example.com`` (User): the scope holds a question mark or a number sign"
            "- ``Owner`` at ``$($script:UdSub)/resourceGroups/rg%2Fone`` for ``dddd6666-0000-0000-0000-000000000002``: the scope holds a percent sign"
        )
        ((Get-UdBullets -Section $Section) -join "`n") | Should -BeExactly ($Expected -join "`n")
        # The count line stands between the prose and the bullets (read on the collapsed text, so a line
        # break inside the prose cannot hide either index).
        $Collapsed = $Section -replace '\s+', ' '
        $Collapsed.IndexOf('changes nothing in the tenant.') | Should -BeGreaterThan 0
        $Collapsed.IndexOf('changes nothing in the tenant.') | Should -BeLessThan $Collapsed.IndexOf('This export read 2')
        $Collapsed.IndexOf('This export read 2') | Should -BeLessThan $Collapsed.IndexOf('- `Reader`')
        $Section | Should -Not -Match 'None\.'
    }

    It 'writes a value that holds a backtick, a backslash or an angle bracket as a code span with the fence rule of the other bullets, on one line' {
        $Section = Get-UdSection -Readme (Get-UdReadme -Rows @(
                (New-UdRow -Scope "$($script:UdSub)/resourceGroups\<rg`nnew>" -Role 'Odd`Role' -Principal 'dddd6666-0000-0000-0000-000000000003' -PrincipalType 'Group' -Reason "the scope holds a backslash;`nand more")
            ))
        # The role holds a backtick, so its fence is two; the scope holds a backslash, an angle bracket and a
        # line break, so it stays inside its code span, on one line; a line break in the reason becomes a space.
        ((Get-UdBullets -Section $Section) -join "`n") | Should -BeExactly "- ```` Odd``Role ```` at ``$($script:UdSub)/resourceGroups\<rg new>`` for ``dddd6666-0000-0000-0000-000000000003`` (Group): the scope holds a backslash; and more"
    }

    It 'writes no reason, and no colon, for a row that gives none' {
        $Bullets = @(Get-UdBullets -Section (Get-UdSection -Readme (Get-UdReadme -Rows @(
                        (New-UdRow -Scope '/subscriptions/x/rg#1' -Role 'Reader' -Principal 'dddd6666-0000-0000-0000-000000000008' -PrincipalType 'User' -Reason '')
                    ))))
        $Bullets | Should -Be @('- `Reader` at `/subscriptions/x/rg#1` for `dddd6666-0000-0000-0000-000000000008` (User)')
    }

    It 'places the section directly after "Role assignments whose principal the directory did not return" and ahead of "Groups using PIM for Groups in a restricted management unit" (<State>)' -ForEach @(
        @{ State = 'none'; Rows = @() }
        @{ State = 'one row'; Rows = @([PSCustomObject]@{ RoleAssignmentId = ''; Scope = '/subscriptions/x/rg#1'; Role = 'Owner'; Principal = 'dddd6666-0000-0000-0000-000000000004'; PrincipalType = 'Group'; Reason = 'the scope holds a question mark or a number sign' }) }
    ) {
        $Md = Get-UdReadme -Rows $Rows
        ([regex]::Matches($Md, '(?m)^## Role assignments at a scope no document can declare\r?$')).Count | Should -Be 1
        $Headings = @([regex]::Matches($Md, '(?m)^## .*$') | ForEach-Object { $_.Value.TrimEnd("`r") })
        $Index = [array]::IndexOf($Headings, $script:UdHeading)
        $Index | Should -BeGreaterThan 0
        $Headings[$Index - 1] | Should -BeExactly '## Role assignments whose principal the directory did not return'
        $Headings[$Index + 1] | Should -BeExactly '## Groups using PIM for Groups in a restricted management unit'
    }

    It 'names role, scope, principal, type and reason only, never the role assignment id' {
        $Md = Get-UdReadme -Rows @(
            (New-UdRow -Scope '/subscriptions/x/rg#1' -Role 'Reader' -Principal 'dddd6666-0000-0000-0000-000000000005' -PrincipalType 'User' -Reason 'the scope holds a question mark or a number sign' `
                    -RoleAssignmentId '/subscriptions/x/providers/Microsoft.Authorization/roleAssignments/cccc6666-0000-0000-0000-000000000001')
        )
        (Get-UdSection -Readme $Md) | Should -Match ([regex]::Escape('`dddd6666-0000-0000-0000-000000000005`'))
        $Md | Should -Not -Match 'cccc6666-0000-0000-0000-000000000001'
    }

    It 'leaves the other sections exactly as they were' {
        $Without = Get-UdReadme
        $With = Get-UdReadme -Rows @((New-UdRow -Scope '/subscriptions/x/rg%1' -Role 'Reader' -Principal 'dddd6666-0000-0000-0000-000000000006' -PrincipalType 'User' -Reason 'the scope holds a percent sign'))
        $Cut = { param($Md) $S = $Md.IndexOf($script:UdHeading); $Md.Remove($S, $Md.IndexOf("`n## ", $S) - $S) }
        (& $Cut $With) | Should -BeExactly (& $Cut $Without)
    }

    It 'declares UndeclarableScopeAssignments Mandatory, so a caller cannot forget it and write a README that claims none was read' {
        $Parameter = InModuleScope $script:moduleName {
            $Meta = (Get-Command Get-OERInventoryReadme).Parameters['UndeclarableScopeAssignments']
            [PSCustomObject]@{
                Type           = $Meta.ParameterType
                Mandatory      = @($Meta.Attributes | Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] } | Where-Object { $_.Mandatory }).Count
                AllowsEmptyArr = @($Meta.Attributes | Where-Object { $_ -is [System.Management.Automation.AllowEmptyCollectionAttribute] }).Count
            }
        }
        $Parameter.Type | Should -Be ([object[]])
        $Parameter.Mandatory | Should -Be 1
        $Parameter.AllowsEmptyArr | Should -Be 1
    }

    It 'contains only ASCII characters with rows' {
        $Md = Get-UdReadme -Rows @((New-UdRow -Scope '/subscriptions/x/rg#1' -Role 'Reader' -Principal 'dddd6666-0000-0000-0000-000000000007' -PrincipalType 'User' -Reason 'the scope holds a question mark or a number sign'))
        $Bytes = [System.Text.Encoding]::UTF8.GetBytes($Md)
        ($Bytes | Where-Object { $_ -gt 127 }).Count | Should -Be 0
    }
}

Describe 'Get-OERInventoryReadme (groups using PIM for Groups in a restricted management unit, Sprint 11 step 6, BL-134)' {
    # Microsoft Learn states that Privileged Identity Management does not support a group in a restricted
    # management administrative unit. inventory.json keeps such a group; the README names each one and its
    # units, in both states: "none" is a claim the reader needs to rely on as much as the list, so it also
    # says which units were not checked. Names only, never an id. No id below is version-4 shaped.
    BeforeAll {
        $script:RuHeading = '## Groups using PIM for Groups in a restricted management unit'
        function Get-RuReadme {
            param([object[]]$Rows = @())
            InModuleScope $script:moduleName -Parameters @{ R = $Rows } {
                param($R)
                Get-OERInventoryReadme -IncompleteReads @() -SkippedScopes @() -SkippedEligibilityScopes @() -PimLeftOut @() -RootScopeAssignments @() -SharedNames @() -UnresolvedPrincipalAssignments @() -UndeclarableScopeAssignments @() -RestrictedUnitPimGroups $R -LighthouseDelegations @() -ForeignSubscriptions @()
            }
        }
        # The section, heading included, up to the next level 2 heading; $null when it is missing.
        function Get-RuSection {
            param([string]$Readme)
            $Start = $Readme.IndexOf($script:RuHeading)
            if ($Start -lt 0) { return $null }
            $Next = $Readme.IndexOf("`n## ", $Start)
            if ($Next -lt 0) { return $Readme.Substring($Start) }
            $Readme.Substring($Start, $Next - $Start)
        }
        function Get-RuBullets {
            param([string]$Section)
            @($Section -split '\r?\n' | Where-Object { $_ -like '- *' })
        }
        # The row shape Export-OERInventory hands over: the group's display name and the display names of
        # the restricted units it is a member of.
        function New-RuRow {
            param([string]$Group, [string[]]$Units)
            [PSCustomObject]@{ Group = $Group; Units = $Units }
        }
        $script:RuProse = 'A group that uses PIM for Groups -- one with PIM eligibility or a `pimPolicy` block -- and is a member of a restricted management administrative unit is a case Microsoft documents as unsupported: Microsoft Learn states that Privileged Identity Management does not support a group in a restricted management administrative unit. `inventory.json` keeps such a group, and `Invoke-OERStructure` still sends the PIM settings and eligibility a document declares for it; what Microsoft Graph answers to those writes has not been measured. Review each group below as a finding before applying a document that declares it. Only a group `inventory.json` writes is listed, against a restricted unit whose members this export read and which it kept in the document: a unit left out of the document because another unit shares its name is not checked here, and is named under "Names two or more objects share" and "What this export could not read". Listing a group changes nothing in the tenant and leaves nothing out of the export.'
        $script:RuNone = 'None. No group that `inventory.json` writes with PIM eligibility or a `pimPolicy` block is a member of a restricted management unit this export checked. The check needs both `Groups` and `AdministrativeUnits` in the export; a unit whose members could not be read, and a unit left out of the document because another unit shares its name, were not checked, and each is named under "What this export could not read".'
    }

    It 'says that none was found when the list is empty' {
        $Section = Get-RuSection -Readme (Get-RuReadme)
        $Section | Should -Not -BeNullOrEmpty
        $Collapsed = $Section -replace '\s+', ' '
        $Collapsed | Should -Match ([regex]::Escape($script:RuProse))
        $Collapsed | Should -Match ([regex]::Escape($script:RuNone))
        @(Get-RuBullets -Section $Section).Count | Should -Be 0
        $Section | Should -Not -Match 'This export found \d+'
    }

    It 'writes the count line and one bullet per group, in the order given, with its units, and no "None"' {
        $Section = Get-RuSection -Readme (Get-RuReadme -Rows @(
                (New-RuRow -Group 'role_sec_admin' -Units @('Restricted AU'))
                (New-RuRow -Group 'role_sec_pim' -Units @('Restricted AU', 'Second AU'))
            ))
        ($Section -replace '\s+', ' ') | Should -Match ([regex]::Escape($script:RuProse))
        $Section | Should -Match '(?m)^This export found 2 such group\(s\):\r?$'
        $Expected = @(
            '- `role_sec_admin` -- member of the restricted management unit(s) `Restricted AU`'
            '- `role_sec_pim` -- member of the restricted management unit(s) `Restricted AU`, `Second AU`'
        )
        ((Get-RuBullets -Section $Section) -join "`n") | Should -BeExactly ($Expected -join "`n")
        # The count line stands between the prose and the bullets (read on the collapsed text, so a line
        # break inside the prose cannot hide either index).
        $Collapsed = $Section -replace '\s+', ' '
        $Collapsed.IndexOf('leaves nothing out of the export.') | Should -BeGreaterThan 0
        $Collapsed.IndexOf('leaves nothing out of the export.') | Should -BeLessThan $Collapsed.IndexOf('This export found 2')
        $Collapsed.IndexOf('This export found 2') | Should -BeLessThan $Collapsed.IndexOf('- `role_sec_admin`')
        $Section | Should -Not -Match 'None\.'
    }

    It 'writes a name that holds a backtick or an angle bracket as a code span with the fence rule of the other bullets, on one line' {
        $Section = Get-RuSection -Readme (Get-RuReadme -Rows @(
                (New-RuRow -Group 'Odd`Group' -Units @("<unit`nnew>", 'Plain AU'))
            ))
        # The group holds a backtick, so its fence is two; the first unit holds an angle bracket and a line
        # break, so it stays inside its code span, on one line.
        ((Get-RuBullets -Section $Section) -join "`n") | Should -BeExactly '- `` Odd`Group `` -- member of the restricted management unit(s) `<unit new>`, `Plain AU`'
        # Outside its code spans the bullet holds no angle bracket: Markdown would read it as a tag.
        ((Get-RuBullets -Section $Section)[0] -replace '`[^`]*`', '') | Should -Not -Match '<'
    }

    It 'places the section directly after "Role assignments at a scope no document can declare" and ahead of the Azure Lighthouse delegations section and ## Files (<State>)' -ForEach @(
        @{ State = 'none'; Rows = @() }
        @{ State = 'one row'; Rows = @([PSCustomObject]@{ Group = 'role_sec_pim'; Units = @('Restricted AU') }) }
    ) {
        $Md = Get-RuReadme -Rows $Rows
        ([regex]::Matches($Md, '(?m)^## Groups using PIM for Groups in a restricted management unit\r?$')).Count | Should -Be 1
        $Headings = @([regex]::Matches($Md, '(?m)^## .*$') | ForEach-Object { $_.Value.TrimEnd("`r") })
        $Index = [array]::IndexOf($Headings, $script:RuHeading)
        $Index | Should -BeGreaterThan 0
        $Headings[$Index - 1] | Should -BeExactly '## Role assignments at a scope no document can declare'
        # Sprint 11 step 6b (BL-133): the Azure Lighthouse delegations section follows this one; BL-150 (A19):
        # the subscriptions delegated from another tenant follow that.
        $Headings[$Index + 1] | Should -BeExactly '## Azure Lighthouse delegations (access from another tenant)'
        $Headings[$Index + 2] | Should -BeExactly '## Subscriptions delegated from another tenant (not read)'
        $Headings[$Index + 3] | Should -BeExactly '## Files'
    }

    It 'names groups and units only, never an id or any other property of a row' {
        $Row = [PSCustomObject]@{ Group = 'role_sec_pim'; Units = @('Restricted AU'); GroupId = 'eeee5555-0000-0000-0000-000000000001'; UnitIds = @('eeee5555-0000-0000-0000-000000000002') }
        $Md = Get-RuReadme -Rows @($Row)
        (Get-RuSection -Readme $Md) | Should -Match ([regex]::Escape('`role_sec_pim`'))
        $Md | Should -Not -Match 'eeee5555-0000-0000-0000-000000000001'
        $Md | Should -Not -Match 'eeee5555-0000-0000-0000-000000000002'
    }

    It 'leaves the other sections exactly as they were' {
        $Without = Get-RuReadme
        $With = Get-RuReadme -Rows @((New-RuRow -Group 'role_sec_pim' -Units @('Restricted AU')))
        $Cut = { param($Md) $S = $Md.IndexOf($script:RuHeading); $Md.Remove($S, $Md.IndexOf("`n## ", $S) - $S) }
        (& $Cut $With) | Should -BeExactly (& $Cut $Without)
    }

    It 'declares RestrictedUnitPimGroups Mandatory, so a caller cannot forget it and write a README that claims none was found' {
        $Parameter = InModuleScope $script:moduleName {
            $Meta = (Get-Command Get-OERInventoryReadme).Parameters['RestrictedUnitPimGroups']
            [PSCustomObject]@{
                Type           = $Meta.ParameterType
                Mandatory      = @($Meta.Attributes | Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] } | Where-Object { $_.Mandatory }).Count
                AllowsEmptyArr = @($Meta.Attributes | Where-Object { $_ -is [System.Management.Automation.AllowEmptyCollectionAttribute] }).Count
            }
        }
        $Parameter.Type | Should -Be ([object[]])
        $Parameter.Mandatory | Should -Be 1
        $Parameter.AllowsEmptyArr | Should -Be 1
    }

    It 'contains only ASCII characters with rows' {
        $Md = Get-RuReadme -Rows @((New-RuRow -Group 'role_sec_pim' -Units @('Restricted AU')))
        $Bytes = [System.Text.Encoding]::UTF8.GetBytes($Md)
        ($Bytes | Where-Object { $_ -gt 127 }).Count | Should -Be 0
    }
}

Describe 'Get-OERInventoryReadme (Azure Lighthouse delegations, Sprint 11 step 6b, BL-133)' {
    # Azure Lighthouse gives principals of a managing tenant Azure roles over a delegated scope, which no
    # role assignment there shows. lighthouseDelegations.json holds them; the README names each delegation,
    # in both states: "none" is a claim the reader needs to rely on as much as the list. Never a principal.
    # BL-150 (A19): the walk reads only this tenant's own subscriptions, and Azure Lighthouse refuses a
    # delegation whose managing tenant is the subscription's own tenant, so no bullet is ever marked as
    # access this tenant holds over another (the Ruling R-12 mark is gone). No id below is version-4 shaped.
    BeforeAll {
        $script:LhHeading = '## Azure Lighthouse delegations (access from another tenant)'
        function Get-LhReadme {
            param([object[]]$Rows = @(), [string[]]$Incomplete = @())
            InModuleScope $script:moduleName -Parameters @{ R = $Rows; I = $Incomplete } {
                param($R, $I)
                Get-OERInventoryReadme -IncompleteReads $I -SkippedScopes @() -SkippedEligibilityScopes @() -PimLeftOut @() -RootScopeAssignments @() -SharedNames @() -UnresolvedPrincipalAssignments @() -UndeclarableScopeAssignments @() -RestrictedUnitPimGroups @() -LighthouseDelegations $R -ForeignSubscriptions @()
            }
        }
        # The "What this export could not read" section, heading included, up to the next level 2 heading.
        function Get-LhCouldNotRead {
            param([string]$Readme)
            $Start = $Readme.IndexOf('## What this export could not read')
            if ($Start -lt 0) { return $null }
            $Next = $Readme.IndexOf("`n## ", $Start)
            if ($Next -lt 0) { return $Readme.Substring($Start) }
            $Readme.Substring($Start, $Next - $Start)
        }
        # The section, heading included, up to the next level 2 heading; $null when it is missing.
        function Get-LhSection {
            param([string]$Readme)
            $Start = $Readme.IndexOf($script:LhHeading)
            if ($Start -lt 0) { return $null }
            $Next = $Readme.IndexOf("`n## ", $Start)
            if ($Next -lt 0) { return $Readme.Substring($Start) }
            $Readme.Substring($Start, $Next - $Start)
        }
        function Get-LhBullets {
            param([string]$Section)
            @($Section -split '\r?\n' | Where-Object { $_ -like '- *' })
        }
        # The row shape Export-OERInventory writes to lighthouseDelegations.json (what the README reads of it).
        function New-LhRow {
            param(
                [string]$Scope = '/subscriptions/11111111-1111-1111-1111-111111111111',
                [string]$TenantName = 'Contoso Corp.',
                [string]$TenantId = '33333333-3333-3333-3333-333333333333',
                [string]$Offer = 'Managed Services',
                [object[]]$Authorizations = @(),
                [object[]]$Eligible = @()
            )
            [PSCustomObject]@{
                scope                    = $Scope
                managedByTenantId        = $TenantId
                managedByTenantName      = $TenantName
                offerName                = $Offer
                registrationAssignmentId = 'assignment-id-must-not-be-written'
                authorizations           = $Authorizations
                eligibleAuthorizations   = $Eligible
            }
        }
        function New-LhAuth {
            param([string]$RoleName, [string]$RoleId = 'dddddddd-dddd-dddd-dddd-dddddddddddd')
            [PSCustomObject]@{
                principalId          = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'
                principalDisplayName = 'Support User'
                roleDefinitionId     = $RoleId
                roleName             = $RoleName
            }
        }
        $script:LhProse = 'Azure Lighthouse lets another tenant -- a service provider, for example -- manage subscriptions or resource groups of this tenant: a delegation gives principals of that managing tenant Azure built-in roles over the delegated scope. That access is not listed as a role assignment of this tenant, so `roleAssignments.json` and `inventory.json` never show it, and `Invoke-OERStructure` never creates or removes it. `lighthouseDelegations.json` holds every delegation this export read, as read-only context: the delegated scope, the managing tenant, the offer and each authorization, with the eligible (just-in-time) ones apart. Review each delegation below as a finding. A scope whose delegations could not be read is named under "What this export could not read", and its delegations are absent from the file, which does not mean it has none. Listing a delegation changes nothing in the tenant.'
        $script:LhNone = 'None. This export read no Azure Lighthouse delegation. Delegations are read only when the export includes `RoleAssignments` or `RoleManagementPolicies`, at the subscriptions its Azure walk visits; a `-Scope` at a management group or the root scope visits no subscription, so it reads no delegation. A scope whose delegations could not be read is named under "What this export could not read".'
        # BL-150 (A19): the second paragraph says why every delegation is access another tenant holds here.
        $script:LhDirection = 'The Azure walk reads only this tenant''s own subscriptions (see "Subscriptions delegated from another tenant (not read)" below), and Azure Lighthouse refuses a delegation whose managing tenant is the subscription''s own tenant, so every delegation below is access another tenant holds over a subscription or resource group of this tenant.'
    }

    It 'says that none was read when the list is empty' {
        $Section = Get-LhSection -Readme (Get-LhReadme)
        $Section | Should -Not -BeNullOrEmpty
        $Collapsed = $Section -replace '\s+', ' '
        $Collapsed | Should -Match ([regex]::Escape($script:LhProse))
        $Collapsed | Should -Match ([regex]::Escape($script:LhNone))
        @(Get-LhBullets -Section $Section).Count | Should -Be 0
        $Section | Should -Not -Match 'This export read \d+'
    }

    It 'says, between the prose and the list, that every delegation is access another tenant holds over this tenant, exactly (<State>)' -ForEach @(
        @{ State = 'none'; WithRow = $false; Next = 'None. This export read no Azure Lighthouse delegation.' }
        @{ State = 'one row'; WithRow = $true; Next = 'This export read 1 delegation(s):' }
    ) {
        $Rows = @(if ($WithRow) { New-LhRow -Authorizations @((New-LhAuth -RoleName 'Contributor')) })
        $Section = Get-LhSection -Readme (Get-LhReadme -Rows $Rows)
        # The paragraph exactly, its own line breaks included.
        $Section | Should -Match ([regex]::Escape("The Azure walk reads only this tenant's own subscriptions (see `"Subscriptions delegated from`nanother tenant (not read)`" below), and Azure Lighthouse refuses a delegation whose managing tenant`nis the subscription's own tenant, so every delegation below is access another tenant holds over a`nsubscription or resource group of this tenant.").Replace('\n', '\r?\n'))
        $Collapsed = $Section -replace '\s+', ' '
        $Collapsed | Should -Match ([regex]::Escape($script:LhDirection))
        $Collapsed.IndexOf('changes nothing in the tenant.') | Should -BeLessThan $Collapsed.IndexOf($script:LhDirection)
        $Collapsed.IndexOf($script:LhDirection) | Should -BeLessThan $Collapsed.IndexOf($Next)
        # The Ruling R-12 paragraph is gone.
        $Collapsed | Should -Not -Match 'When this tenant is itself a managing tenant'
    }

    It 'writes the count line and one bullet per delegation, in the order given, with the roles of both lists' {
        $First = New-LhRow -Authorizations @((New-LhAuth -RoleName 'Contributor'), (New-LhAuth -RoleName 'User Access Administrator' -RoleId 'eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee')) `
            -Eligible @((New-LhAuth -RoleName 'Contributor'))
        $Second = New-LhRow -Scope '/subscriptions/22222222-2222-2222-2222-222222222222/resourceGroups/rg-app' -TenantName 'Fabrikam Services' -TenantId '99999999-9999-9999-9999-999999999999' -Offer 'Operations' `
            -Authorizations @((New-LhAuth -RoleName 'Reader' -RoleId 'ffffffff-ffff-ffff-ffff-ffffffffffff'))
        $Section = Get-LhSection -Readme (Get-LhReadme -Rows @($First, $Second))
        ($Section -replace '\s+', ' ') | Should -Match ([regex]::Escape($script:LhProse))
        $Section | Should -Match '(?m)^This export read 2 delegation\(s\):\r?$'
        $Expected = @(
            '- `/subscriptions/11111111-1111-1111-1111-111111111111` -- managing tenant `Contoso Corp.` (`33333333-3333-3333-3333-333333333333`), offer `Managed Services`: 2 authorization(s) and 1 eligible authorization(s), roles `Contributor`, `User Access Administrator`'
            '- `/subscriptions/22222222-2222-2222-2222-222222222222/resourceGroups/rg-app` -- managing tenant `Fabrikam Services` (`99999999-9999-9999-9999-999999999999`), offer `Operations`: 1 authorization(s) and 0 eligible authorization(s), roles `Reader`'
        )
        ((Get-LhBullets -Section $Section) -join "`n") | Should -BeExactly ($Expected -join "`n")
        # The count line stands between the prose and the bullets.
        $Collapsed = $Section -replace '\s+', ' '
        $Collapsed.IndexOf('changes nothing in the tenant.') | Should -BeGreaterThan 0
        $Collapsed.IndexOf('changes nothing in the tenant.') | Should -BeLessThan $Collapsed.IndexOf('This export read 2')
        $Collapsed.IndexOf('This export read 2') | Should -BeLessThan $Collapsed.IndexOf('- `/subscriptions/1111')
        $Section | Should -Not -Match '(?m)^None\.'
    }

    It 'names the role definition id for a role whose name is not known, once, and says "roles none" without any' {
        $WithIds = New-LhRow -Authorizations @((New-LhAuth -RoleName $null), (New-LhAuth -RoleName '')) -Eligible @((New-LhAuth -RoleName $null -RoleId 'ffffffff-ffff-ffff-ffff-ffffffffffff'))
        $Without = New-LhRow -Scope '/subscriptions/22222222-2222-2222-2222-222222222222'
        $Bullets = @(Get-LhBullets -Section (Get-LhSection -Readme (Get-LhReadme -Rows @($WithIds, $Without))))
        $Bullets[0] | Should -BeExactly '- `/subscriptions/11111111-1111-1111-1111-111111111111` -- managing tenant `Contoso Corp.` (`33333333-3333-3333-3333-333333333333`), offer `Managed Services`: 2 authorization(s) and 1 eligible authorization(s), roles `dddddddd-dddd-dddd-dddd-dddddddddddd`, `ffffffff-ffff-ffff-ffff-ffffffffffff`'
        $Bullets[1] | Should -BeExactly '- `/subscriptions/22222222-2222-2222-2222-222222222222` -- managing tenant `Contoso Corp.` (`33333333-3333-3333-3333-333333333333`), offer `Managed Services`: 0 authorization(s) and 0 eligible authorization(s), roles none'
    }

    It 'counts only the authorizations a row holds: a null entry in a list, or a list the row does not carry, is none' {
        $Row = [PSCustomObject]@{
            scope                    = '/subscriptions/11111111-1111-1111-1111-111111111111'
            managedByTenantId        = '33333333-3333-3333-3333-333333333333'
            managedByTenantName      = 'Contoso Corp.'
            offerName                = 'Managed Services'
            authorizations           = @($null, (New-LhAuth -RoleName 'Contributor'))
        }
        $Bullet = @(Get-LhBullets -Section (Get-LhSection -Readme (Get-LhReadme -Rows @($Row))))[0]
        $Bullet | Should -BeExactly '- `/subscriptions/11111111-1111-1111-1111-111111111111` -- managing tenant `Contoso Corp.` (`33333333-3333-3333-3333-333333333333`), offer `Managed Services`: 1 authorization(s) and 0 eligible authorization(s), roles `Contributor`'
    }

    It 'writes no empty code span for an authorization whose role has neither a name nor a definition id' {
        $Row = New-LhRow -Authorizations @((New-LhAuth -RoleName '' -RoleId ''), (New-LhAuth -RoleName 'Contributor')) -Eligible @((New-LhAuth -RoleName $null -RoleId ' '))
        $Bullet = @(Get-LhBullets -Section (Get-LhSection -Readme (Get-LhReadme -Rows @($Row))))[0]
        $Bullet | Should -BeExactly '- `/subscriptions/11111111-1111-1111-1111-111111111111` -- managing tenant `Contoso Corp.` (`33333333-3333-3333-3333-333333333333`), offer `Managed Services`: 2 authorization(s) and 1 eligible authorization(s), roles `Contributor`'
    }
    It 'writes "not given" for a managing tenant name, a tenant id and an offer the row does not carry, and once for a tenant with neither (<Name>)' -ForEach @(
        @{ Name = 'no tenant name'; TenantName = $null; TenantId = '33333333-3333-3333-3333-333333333333'; Tenant = 'not given (`33333333-3333-3333-3333-333333333333`)' }
        @{ Name = 'no tenant id'; TenantName = 'Contoso Corp.'; TenantId = ''; Tenant = '`Contoso Corp.` (not given)' }
        @{ Name = 'neither, empty'; TenantName = ''; TenantId = ''; Tenant = 'not given' }
        @{ Name = 'neither, white space'; TenantName = '  '; TenantId = ' '; Tenant = 'not given' }
    ) {
        $Row = New-LhRow -TenantName $TenantName -TenantId $TenantId -Offer ' ' -Authorizations @((New-LhAuth -RoleName 'Contributor'))
        $Bullets = Get-LhBullets -Section (Get-LhSection -Readme (Get-LhReadme -Rows @($Row)))
        $Bullets | Should -BeExactly ('- `/subscriptions/11111111-1111-1111-1111-111111111111` -- managing tenant ' + $Tenant + ', offer not given: 1 authorization(s) and 0 eligible authorization(s), roles `Contributor`')
    }

    It 'never marks a delegation, whatever its managing tenant, and never says "this tenant is the managing tenant" (<Name>)' -ForEach @(
        @{ Name = 'a tenant id'; RowTenant = 'cccccccc-cccc-cccc-cccc-cccccccccccc'; Tenant = '`Contoso Corp.` (`cccccccc-cccc-cccc-cccc-cccccccccccc`)' }
        @{ Name = 'a tenant id in upper case'; RowTenant = 'CCCCCCCC-CCCC-CCCC-CCCC-CCCCCCCCCCCC'; Tenant = '`Contoso Corp.` (`CCCCCCCC-CCCC-CCCC-CCCC-CCCCCCCCCCCC`)' }
        @{ Name = 'an empty tenant id'; RowTenant = ''; Tenant = '`Contoso Corp.` (not given)' }
        @{ Name = 'a null tenant id'; RowTenant = $null; Tenant = '`Contoso Corp.` (not given)' }
    ) {
        $First = New-LhRow -Authorizations @((New-LhAuth -RoleName 'Contributor'))
        $First.managedByTenantId = $RowTenant
        $Other = New-LhRow -Scope '/subscriptions/22222222-2222-2222-2222-222222222222' -TenantName 'Fabrikam Services' -TenantId '99999999-9999-9999-9999-999999999999' -Authorizations @((New-LhAuth -RoleName 'Reader'))
        $Md = Get-LhReadme -Rows @($First, $Other)
        $Bullets = @(Get-LhBullets -Section (Get-LhSection -Readme $Md))
        $Expected = @(
            ('- `/subscriptions/11111111-1111-1111-1111-111111111111` -- managing tenant ' + $Tenant + ', offer `Managed Services`: 1 authorization(s) and 0 eligible authorization(s), roles `Contributor`')
            '- `/subscriptions/22222222-2222-2222-2222-222222222222` -- managing tenant `Fabrikam Services` (`99999999-9999-9999-9999-999999999999`), offer `Managed Services`: 1 authorization(s) and 0 eligible authorization(s), roles `Reader`'
        )
        ($Bullets -join "`n") | Should -BeExactly ($Expected -join "`n")
        $Md | Should -Not -Match 'this tenant is the managing tenant'
        $Md | Should -Not -Match 'marked below'
    }

    It 'takes no -TenantId: the tenant the export read decides nothing in the README' {
        $Has = InModuleScope $script:moduleName { (Get-Command Get-OERInventoryReadme).Parameters.ContainsKey('TenantId') }
        $Has | Should -BeFalse
    }

    It 'writes a name that holds a backtick or an angle bracket as a code span with the fence rule of the other bullets, on one line' {
        $Row = New-LhRow -TenantName 'Odd`Tenant' -Offer "<offer`nnew>" -Authorizations @((New-LhAuth -RoleName 'Contributor'))
        $Bullet = @(Get-LhBullets -Section (Get-LhSection -Readme (Get-LhReadme -Rows @($Row))))[0]
        $Bullet | Should -BeExactly '- `/subscriptions/11111111-1111-1111-1111-111111111111` -- managing tenant `` Odd`Tenant `` (`33333333-3333-3333-3333-333333333333`), offer `<offer new>`: 1 authorization(s) and 0 eligible authorization(s), roles `Contributor`'
        # Outside its code spans the bullet holds no angle bracket: Markdown would read it as a tag.
        ($Bullet -replace '(`+).+?\1', '') | Should -Not -Match '<'
    }

    It 'places the section directly after the restricted management unit section and ahead of the subscriptions delegated from another tenant and ## Files (<State>)' -ForEach @(
        @{ State = 'none'; Rows = @() }
        @{ State = 'one row'; Rows = @([PSCustomObject]@{ scope = '/subscriptions/11111111-1111-1111-1111-111111111111'; managedByTenantId = '33333333-3333-3333-3333-333333333333'; managedByTenantName = 'Contoso Corp.'; offerName = 'Managed Services'; authorizations = @(); eligibleAuthorizations = @() }) }
    ) {
        $Md = Get-LhReadme -Rows $Rows
        ([regex]::Matches($Md, '(?m)^## Azure Lighthouse delegations \(access from another tenant\)\r?$')).Count | Should -Be 1
        $Headings = @([regex]::Matches($Md, '(?m)^## .*$') | ForEach-Object { $_.Value.TrimEnd("`r") })
        $Index = [array]::IndexOf($Headings, $script:LhHeading)
        $Index | Should -BeGreaterThan 0
        $Headings[$Index - 1] | Should -BeExactly '## Groups using PIM for Groups in a restricted management unit'
        $Headings[$Index + 1] | Should -BeExactly '## Subscriptions delegated from another tenant (not read)'
        $Headings[$Index + 2] | Should -BeExactly '## Files'
    }

    It 'lists lighthouseDelegations.json in the Files section, directly after azurePimEligibility.json' {
        $Collapsed = (Get-LhReadme) -replace '\s+', ' '
        $Collapsed | Should -Match ([regex]::Escape('- `lighthouseDelegations.json` -- the Azure Lighthouse delegations at the subscriptions the Azure walk visits, written only when an Azure section is included: access that principals of a managing tenant hold over a delegated subscription or resource group, which is not listed as a role assignment there. Read-only context, not an apply document -- see "Azure Lighthouse delegations (access from another tenant)" above. - `schema.json`'))
        $Collapsed.IndexOf('- `azurePimEligibility.json`') | Should -BeGreaterThan 0
        $Collapsed.IndexOf('- `azurePimEligibility.json`') | Should -BeLessThan $Collapsed.IndexOf('- `lighthouseDelegations.json`')
    }

    It 'names scopes, tenants, offers and roles only, never a principal or an id of the assignment' {
        $Row = New-LhRow -Authorizations @((New-LhAuth -RoleName 'Contributor')) -Eligible @((New-LhAuth -RoleName 'Contributor'))
        $Md = Get-LhReadme -Rows @($Row)
        (Get-LhSection -Readme $Md) | Should -Match ([regex]::Escape('`Contributor`'))
        $Md | Should -Not -Match 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'
        $Md | Should -Not -Match 'Support User'
        $Md | Should -Not -Match 'assignment-id-must-not-be-written'
    }

    It 'leaves the other sections exactly as they were' {
        $Without = Get-LhReadme
        $With = Get-LhReadme -Rows @((New-LhRow -Authorizations @((New-LhAuth -RoleName 'Contributor'))))
        $Cut = { param($Md) $S = $Md.IndexOf($script:LhHeading); $Md.Remove($S, $Md.IndexOf("`n## ", $S) - $S) }
        (& $Cut $With) | Should -BeExactly (& $Cut $Without)
    }

    It 'lists an IncompleteReads entry that starts with lighthouseDelegations under the label Azure Lighthouse read that failed, in the order given, last among the entries' {
        # The export appends the failed Lighthouse reads after every other IncompleteReads entry and keeps them
        # apart from the Entra ID entries, the principal entries and the role selection entries.
        $Section = Get-LhCouldNotRead -Readme (Get-LhReadme -Incomplete @(
                'groupsRoster'
                'roleAssignments/Owner -> bbbbbbbb-2222-2222-2222-222222222222 @ /subscriptions/11111111-1111-1111-1111-111111111111/principal'
                'roleManagementPolicies/role selection at /subscriptions/11111111-1111-1111-1111-111111111111'
                'lighthouseDelegations at /subscriptions/11111111-1111-1111-1111-111111111111'
                'lighthouseDelegations role dddddddd-dddd-dddd-dddd-dddddddddddd'
                'lighthouseDelegations at <all Azure scopes: scope enumeration failed>'
                'lighthouseDelegations at <subscriptions: the listing failed>'
            ))
        $Expected = @(
            '- Entra ID: `groupsRoster`'
            '- Role assignment principal that could not be read: `roleAssignments/Owner -> bbbbbbbb-2222-2222-2222-222222222222 @ /subscriptions/11111111-1111-1111-1111-111111111111/principal`'
            '- Azure role management policies kept without being judged: `roleManagementPolicies/role selection at /subscriptions/11111111-1111-1111-1111-111111111111`'
            '- Azure Lighthouse read that failed: `lighthouseDelegations at /subscriptions/11111111-1111-1111-1111-111111111111`'
            '- Azure Lighthouse read that failed: `lighthouseDelegations role dddddddd-dddd-dddd-dddd-dddddddddddd`'
            '- Azure Lighthouse read that failed: `lighthouseDelegations at <all Azure scopes: scope enumeration failed>`'
            '- Azure Lighthouse read that failed: `lighthouseDelegations at <subscriptions: the listing failed>`'
        )
        # One string, so a failure prints the whole list rather than the first element that differs.
        (@($Section -split '\r?\n' | Where-Object { $_ -like '- *' }) -join "`n") | Should -BeExactly ($Expected -join "`n")
        $Section | Should -Match 'This bundle is PARTIAL'
        $Section | Should -Not -Match 'Nothing\.'
    }

    It 'keeps an entry that only resembles a Lighthouse entry under Entra ID: it must start with lighthouseDelegations and a space, in that letter case (<Name>)' -ForEach @(
        @{ Name = 'no space'; Entry = 'lighthouseDelegations' }
        @{ Name = 'a longer word'; Entry = 'lighthouseDelegationsX at /subscriptions/11111111-1111-1111-1111-111111111111' }
        @{ Name = 'another letter case'; Entry = 'LighthouseDelegations at /subscriptions/11111111-1111-1111-1111-111111111111' }
        @{ Name = 'not at the start'; Entry = 'groups/lighthouseDelegations at /subscriptions/11111111-1111-1111-1111-111111111111' }
    ) {
        $Section = Get-LhCouldNotRead -Readme (Get-LhReadme -Incomplete @($Entry))
        (@($Section -split '\r?\n' | Where-Object { $_ -like '- *' }) -join "`n") | Should -BeExactly ('- Entra ID: `' + $Entry + '`')
    }

    It 'says in the partial prose what a Lighthouse entry names and how the scope and the role are written, with every angle bracket inside a code span' {
        $Section = Get-LhCouldNotRead -Readme (Get-LhReadme -Incomplete @('lighthouseDelegations at /subscriptions/11111111-1111-1111-1111-111111111111'))
        $Collapsed = $Section -replace '\s+', ' '
        $Collapsed | Should -Match ([regex]::Escape('An entry labelled "Azure Lighthouse read that failed" names either a scope, as `lighthouseDelegations at <scope>`, whose Azure Lighthouse delegations could not be read, so they are absent from `lighthouseDelegations.json`, which does not mean the scope has none, or a role, as `lighthouseDelegations role <id>`, whose name could not be read, so its `roleName` is written `null` there.'))
        # The two entries the export adds for a walk that could not start and a subscription listing that
        # failed name no single scope, and the prose says so.
        $Collapsed | Should -Match ([regex]::Escape('Two such entries name no single scope: `lighthouseDelegations at <all Azure scopes: scope enumeration failed>` names a walk that could not start, and `lighthouseDelegations at <subscriptions: the listing failed>` a subscription listing that failed, so the delegations of no subscription were read.'))
        # Outside its code spans the section holds no angle bracket: Markdown would read it as a tag.
        ($Collapsed -replace '`[^`]*`', '') | Should -Not -Match '<'
    }

    It 'writes nothing about a failed Lighthouse read when none failed' {
        $Section = Get-LhCouldNotRead -Readme (Get-LhReadme -Rows @((New-LhRow -Authorizations @((New-LhAuth -RoleName 'Contributor')))))
        $Section | Should -Match 'Nothing\.'
        $Section | Should -Not -Match 'Azure Lighthouse read that failed'
        $Section | Should -Not -Match 'lighthouseDelegations at'
    }

    It 'declares LighthouseDelegations Mandatory, so a caller cannot forget it and write a README that claims none was read' {
        $Parameter = InModuleScope $script:moduleName {
            $Meta = (Get-Command Get-OERInventoryReadme).Parameters['LighthouseDelegations']
            [PSCustomObject]@{
                Type           = $Meta.ParameterType
                Mandatory      = @($Meta.Attributes | Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] } | Where-Object { $_.Mandatory }).Count
                AllowsEmptyArr = @($Meta.Attributes | Where-Object { $_ -is [System.Management.Automation.AllowEmptyCollectionAttribute] }).Count
            }
        }
        $Parameter.Type | Should -Be ([object[]])
        $Parameter.Mandatory | Should -Be 1
        $Parameter.AllowsEmptyArr | Should -Be 1
    }

    It 'contains only ASCII characters with rows' {
        $Md = Get-LhReadme -Rows @((New-LhRow -Authorizations @((New-LhAuth -RoleName 'Contributor'))))
        $Bytes = [System.Text.Encoding]::UTF8.GetBytes($Md)
        ($Bytes | Where-Object { $_ -gt 127 }).Count | Should -Be 0
    }
}
Describe 'Get-OERInventoryReadme (subscriptions delegated from another tenant, BL-150, A19)' {
    # The export's Azure walk reads only the subscriptions whose home tenant is the tenant the session's
    # Microsoft Graph token was issued for. A subscription of another tenant that is listed for the session
    # is not read, and the README names it -- in both states: "none" is a claim the reader needs to rely on
    # as much as the list. A subscription whose home tenant could not be read is named under "What this
    # export could not read" with a label of its own. No id below is version-4 shaped.
    BeforeAll {
        $script:FsHeading = '## Subscriptions delegated from another tenant (not read)'
        function Get-FsReadme {
            param([object[]]$Rows = @(), [string[]]$Incomplete = @())
            InModuleScope $script:moduleName -Parameters @{ R = $Rows; I = $Incomplete } {
                param($R, $I)
                Get-OERInventoryReadme -IncompleteReads $I -SkippedScopes @() -SkippedEligibilityScopes @() -PimLeftOut @() -RootScopeAssignments @() -SharedNames @() -UnresolvedPrincipalAssignments @() -UndeclarableScopeAssignments @() -RestrictedUnitPimGroups @() -LighthouseDelegations @() -ForeignSubscriptions $R
            }
        }
        # A level 2 section, heading included, up to the next level 2 heading; $null when it is missing.
        function Get-FsSection {
            param([string]$Readme, [string]$Heading = $script:FsHeading)
            $Start = $Readme.IndexOf($Heading)
            if ($Start -lt 0) { return $null }
            $Next = $Readme.IndexOf("`n## ", $Start)
            if ($Next -lt 0) { return $Readme.Substring($Start) }
            $Readme.Substring($Start, $Next - $Start)
        }
        function Get-FsBullets {
            param([string]$Section)
            @($Section -split '\r?\n' | Where-Object { $_ -like '- *' })
        }
        # The row shape Resolve-OERInventoryScopeTree names in ForeignSubscriptions.
        function New-FsRow {
            param([string]$Scope = '/subscriptions/aaaa1111-0000-0000-0000-000000000002', [string]$SubscriptionId = 'aaaa1111-0000-0000-0000-000000000002', $DisplayName = 'Customer Prod', $HomeTenantId = 'eeee0000-0000-0000-0000-000000000002')
            [PSCustomObject]@{ SubscriptionId = $SubscriptionId; DisplayName = $DisplayName; HomeTenantId = $HomeTenantId; Scope = $Scope }
        }
        # The intro exactly, with its own line breaks.
        $script:FsIntro = @(
            '## Subscriptions delegated from another tenant (not read)'
            ''
            'The Azure walk reads only the subscriptions whose home tenant is this tenant: the tenant the'
            'session''s Microsoft Graph token was issued for, which `inventory.json` names as its `tenantId`. A'
            'subscription whose home tenant is another tenant can still be listed for this session -- a customer'
            'subscription that tenant delegated to this one through Azure Lighthouse, for example. The export did'
            'not read it: no role assignment, role management policy, PIM eligibility or Azure Lighthouse'
            'delegation of it is in this bundle, and `scopeHierarchy.json` does not list it. That is a'
            'deliberate selection, not a read that failed. `Invoke-OERStructure` refuses a role assignment or a'
            'role management policy at a scope in such a subscription (`SubscriptionTenantMismatch`); manage it'
            'from its home tenant. A subscription whose home tenant could not be read is named under "What this'
            'export could not read" instead.'
        ) -join "`n"
        $script:FsNone = "None. The Azure walk found no subscription whose home tenant is another tenant. Subscriptions are listed only`nwhen the export includes ``RoleAssignments`` or ``RoleManagementPolicies``, and a ``-Scope`` at a management group or the root scope`nlies in no subscription."
    }

    It 'says that none was found when the list is empty, after the intro exactly' {
        $Section = Get-FsSection -Readme (Get-FsReadme)
        $Section | Should -Not -BeNullOrEmpty
        ($Section -replace '\r\n', "`n").TrimEnd() | Should -BeExactly ($script:FsIntro + "`n`n" + $script:FsNone)
        @(Get-FsBullets -Section $Section).Count | Should -Be 0
    }

    It 'writes the count line and one bullet per subscription, in the order given, with "not given" for a name or a tenant it lacks' {
        $Rows = @(
            (New-FsRow)
            (New-FsRow -Scope '/subscriptions/aaaa1111-0000-0000-0000-000000000003/resourceGroups/rg1' -SubscriptionId 'aaaa1111-0000-0000-0000-000000000003' -DisplayName $null -HomeTenantId '')
            (New-FsRow -Scope '/subscriptions/aaaa1111-0000-0000-0000-000000000004' -SubscriptionId 'aaaa1111-0000-0000-0000-000000000004' -DisplayName '  ' -HomeTenantId $null)
        )
        $Section = Get-FsSection -Readme (Get-FsReadme -Rows $Rows)
        ($Section -replace '\r\n', "`n").StartsWith($script:FsIntro + "`n`n" + "This export did not read 3 such subscription(s):`n`n") | Should -BeTrue
        $Expected = @(
            '- `/subscriptions/aaaa1111-0000-0000-0000-000000000002` -- display name `Customer Prod`, home tenant `eeee0000-0000-0000-0000-000000000002`'
            '- `/subscriptions/aaaa1111-0000-0000-0000-000000000003/resourceGroups/rg1` -- display name not given, home tenant not given'
            '- `/subscriptions/aaaa1111-0000-0000-0000-000000000004` -- display name not given, home tenant not given'
        )
        ((Get-FsBullets -Section $Section) -join "`n") | Should -BeExactly ($Expected -join "`n")
        $Section | Should -Not -Match '(?m)^None\.'
    }

    It 'writes a value that holds a backtick or an angle bracket as a code span with the fence rule of the other bullets, on one line' {
        $Row = New-FsRow -DisplayName ('Odd`Name <x>' + "`n" + 'next')
        $Bullet = @(Get-FsBullets -Section (Get-FsSection -Readme (Get-FsReadme -Rows @($Row))))[0]
        $Bullet | Should -BeExactly '- `/subscriptions/aaaa1111-0000-0000-0000-000000000002` -- display name `` Odd`Name <x> next ``, home tenant `eeee0000-0000-0000-0000-000000000002`'
        ($Bullet -replace '(`+).+?\1', '') | Should -Not -Match '<'
    }

    It 'places the section directly after the Azure Lighthouse delegations section and ahead of ## Files (<State>)' -ForEach @(
        @{ State = 'none'; Rows = @() }
        @{ State = 'one row'; Rows = @([PSCustomObject]@{ SubscriptionId = 'aaaa1111-0000-0000-0000-000000000002'; DisplayName = 'Customer Prod'; HomeTenantId = 'eeee0000-0000-0000-0000-000000000002'; Scope = '/subscriptions/aaaa1111-0000-0000-0000-000000000002' }) }
    ) {
        $Md = Get-FsReadme -Rows $Rows
        ([regex]::Matches($Md, '(?m)^## Subscriptions delegated from another tenant \(not read\)\r?$')).Count | Should -Be 1
        $Headings = @([regex]::Matches($Md, '(?m)^## .*$') | ForEach-Object { $_.Value.TrimEnd("`r") })
        $Index = [array]::IndexOf($Headings, $script:FsHeading)
        $Index | Should -BeGreaterThan 0
        $Headings[$Index - 1] | Should -BeExactly '## Azure Lighthouse delegations (access from another tenant)'
        $Headings[$Index + 1] | Should -BeExactly '## Files'
    }

    It 'leaves the other sections exactly as they were' {
        $Without = Get-FsReadme
        $With = Get-FsReadme -Rows @((New-FsRow))
        $Cut = { param($Md) $S = $Md.IndexOf($script:FsHeading); $Md.Remove($S, $Md.IndexOf("`n## ", $S) - $S) }
        (& $Cut $With) | Should -BeExactly (& $Cut $Without)
    }

    It 'names in the Files section that scopeHierarchy.json lists no subscription of another tenant' {
        $Collapsed = (Get-FsReadme) -replace '\s+', ' '
        $Collapsed | Should -Match ([regex]::Escape('- `scopeHierarchy.json` -- the management group / subscription tree of this tenant; a subscription of another tenant is not listed (see "Subscriptions delegated from another tenant (not read)"). Read-only context, not an apply document. - `azurePimEligibility.json`'))
    }

    It 'lists an IncompleteReads entry that starts with subscriptionHomeTenant and a space under the label Azure subscription whose tenant could not be read, after the role selection entries and before the Lighthouse ones' {
        $Section = Get-FsSection -Heading '## What this export could not read' -Readme (Get-FsReadme -Incomplete @(
                'groupsRoster'
                'roleManagementPolicies/role selection at /subscriptions/aaaa1111-0000-0000-0000-000000000001'
                'subscriptionHomeTenant at /subscriptions/aaaa1111-0000-0000-0000-000000000003'
                'subscriptionHomeTenant at /subscriptions/aaaa1111-0000-0000-0000-000000000004/resourceGroups/rg1'
                'lighthouseDelegations at /subscriptions/aaaa1111-0000-0000-0000-000000000001'
            ))
        $Expected = @(
            '- Entra ID: `groupsRoster`'
            '- Azure role management policies kept without being judged: `roleManagementPolicies/role selection at /subscriptions/aaaa1111-0000-0000-0000-000000000001`'
            '- Azure subscription whose tenant could not be read: `subscriptionHomeTenant at /subscriptions/aaaa1111-0000-0000-0000-000000000003`'
            '- Azure subscription whose tenant could not be read: `subscriptionHomeTenant at /subscriptions/aaaa1111-0000-0000-0000-000000000004/resourceGroups/rg1`'
            '- Azure Lighthouse read that failed: `lighthouseDelegations at /subscriptions/aaaa1111-0000-0000-0000-000000000001`'
        )
        ((Get-FsBullets -Section $Section) -join "`n") | Should -BeExactly ($Expected -join "`n")
        $Section | Should -Match 'This bundle is PARTIAL'
    }

    It 'keeps an entry that only resembles a home tenant entry under Entra ID: it must start with subscriptionHomeTenant and a space, in that letter case (<Name>)' -ForEach @(
        @{ Name = 'no space'; Entry = 'subscriptionHomeTenant' }
        @{ Name = 'a longer word'; Entry = 'subscriptionHomeTenantX at /subscriptions/aaaa1111-0000-0000-0000-000000000003' }
        @{ Name = 'another letter case'; Entry = 'SubscriptionHomeTenant at /subscriptions/aaaa1111-0000-0000-0000-000000000003' }
        @{ Name = 'not at the start'; Entry = 'groups/subscriptionHomeTenant at /subscriptions/aaaa1111-0000-0000-0000-000000000003' }
    ) {
        $Section = Get-FsSection -Heading '## What this export could not read' -Readme (Get-FsReadme -Incomplete @($Entry))
        ((Get-FsBullets -Section $Section) -join "`n") | Should -BeExactly ('- Entra ID: `' + $Entry + '`')
    }

    It 'says in the partial prose what a home tenant entry names, with every angle bracket inside a code span' {
        $Section = Get-FsSection -Heading '## What this export could not read' -Readme (Get-FsReadme -Incomplete @('subscriptionHomeTenant at /subscriptions/aaaa1111-0000-0000-0000-000000000003'))
        $Collapsed = $Section -replace '\s+', ' '
        $Collapsed | Should -Match ([regex]::Escape('An entry labelled "Azure subscription whose tenant could not be read" names a subscription, as `subscriptionHomeTenant at <scope>`, that the Azure walk did not enter since whether it belongs to this tenant could not be read: none of its role assignments, role management policies, PIM eligibilities or Azure Lighthouse delegations is in this bundle, which does not mean it has none.'))
        # It follows the Lighthouse sentences.
        $Collapsed.IndexOf('so the delegations of no subscription were read.') | Should -BeGreaterThan 0
        $Collapsed.IndexOf('so the delegations of no subscription were read.') | Should -BeLessThan $Collapsed.IndexOf('An entry labelled "Azure subscription whose tenant could not be read"')
        ($Collapsed -replace '`[^`]*`', '') | Should -Not -Match '<'
    }

    It 'declares ForeignSubscriptions Mandatory, so a caller cannot forget it and write a README that claims none was found' {
        $Parameter = InModuleScope $script:moduleName {
            $Meta = (Get-Command Get-OERInventoryReadme).Parameters['ForeignSubscriptions']
            [PSCustomObject]@{
                Type           = $Meta.ParameterType
                Mandatory      = @($Meta.Attributes | Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] } | Where-Object { $_.Mandatory }).Count
                AllowsEmptyArr = @($Meta.Attributes | Where-Object { $_ -is [System.Management.Automation.AllowEmptyCollectionAttribute] }).Count
            }
        }
        $Parameter.Type | Should -Be ([object[]])
        $Parameter.Mandatory | Should -Be 1
        $Parameter.AllowsEmptyArr | Should -Be 1
    }

    It 'contains only ASCII characters with rows' {
        $Md = Get-FsReadme -Rows @((New-FsRow)) -Incomplete @('subscriptionHomeTenant at /subscriptions/aaaa1111-0000-0000-0000-000000000003')
        $Bytes = [System.Text.Encoding]::UTF8.GetBytes($Md)
        ($Bytes | Where-Object { $_ -gt 127 }).Count | Should -Be 0
    }
}
Describe 'Get-OERInventoryReadme apply-document section list' {
    # The coverage paragraph counts and lists the apply-document sections. Tie both to the sections
    # schema.json declares, so a section added to the schema cannot leave the README claiming fewer.
    It 'counts and names every section schema.json declares, and names both directory role sections as captured' {
        InModuleScope $script:moduleName {
            $Md = Get-OERInventoryReadme -IncompleteReads @() -SkippedScopes @() -SkippedEligibilityScopes @() -PimLeftOut @() -RootScopeAssignments @() -SharedNames @() -UnresolvedPrincipalAssignments @() -UndeclarableScopeAssignments @() -RestrictedUnitPimGroups @() -LighthouseDelegations @() -ForeignSubscriptions @()
            $Sections = @((Get-OERStructureSchemaJson | ConvertFrom-Json).properties.PSObject.Properties.Name |
                    Where-Object { $_ -notin @('version', 'tenantId', 'tenantAlias') })
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
            # BL-107: which Azure role management policies the file holds, and that an absent one was
            # left out by the export rather than missing from the tenant.
            $Collapsed | Should -Match ([regex]::Escape('`roleManagementPolicies` (the PIM settings of Azure roles) holds, unless the export used `-AllRolePolicies`, only the policy of a role with an active role assignment or a PIM eligibility exactly at the policy''s scope, or whose policy has been changed, and every policy the export could not judge, at a scope listed under "What this export could not read" as kept without being judged. A policy absent from it was left out by the export, not missing from the tenant, and applying a document that does not declare it leaves it untouched.'))
        }
    }
}
