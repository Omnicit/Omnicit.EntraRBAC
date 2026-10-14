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
            $Md = Get-OERInventoryReadme -IncompleteReads @() -SkippedScopes @() -SkippedEligibilityScopes @() -PimLeftOut @() -RootScopeAssignments @() -SharedNames @()
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
            $Md = Get-OERInventoryReadme -IncompleteReads @() -SkippedScopes @() -SkippedEligibilityScopes @() -PimLeftOut @() -RootScopeAssignments @() -SharedNames @()
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
            $Md = Get-OERInventoryReadme -IncompleteReads @() -SkippedScopes @() -SkippedEligibilityScopes @() -PimLeftOut @() -RootScopeAssignments @() -SharedNames @()
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
            $Md = Get-OERInventoryReadme -IncompleteReads @() -SkippedScopes @() -SkippedEligibilityScopes @() -PimLeftOut @() -RootScopeAssignments @() -SharedNames @()
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
            $Md = Get-OERInventoryReadme -IncompleteReads @() -SkippedScopes @() -SkippedEligibilityScopes @() -PimLeftOut @() -RootScopeAssignments @() -SharedNames @()
            # Regression guard: a group/application/directory-role review is excluded regardless
            # of stage count -- a different cause from the multi-stage skip above, so it needs its
            # own bullet rather than being folded into that one.
            $Md | Should -Match 'a group, an application or a directory role'
        }
    }

    It 'says in the file roster that groupsRoster.json carries onPremisesSynced among its flags (A15)' {
        InModuleScope $script:moduleName {
            $Md = Get-OERInventoryReadme -IncompleteReads @() -SkippedScopes @() -SkippedEligibilityScopes @() -PimLeftOut @() -RootScopeAssignments @() -SharedNames @()
            $Flat = $Md -replace '\s+', ' '
            $Flat | Should -Match ([regex]::Escape('and flags, including `onPremisesSynced`.'))
        }
    }

    It 'says in the file roster that each groupsRoster.json row carries the group''s id and type (BL-131)' {
        InModuleScope $script:moduleName {
            $Md = Get-OERInventoryReadme -IncompleteReads @() -SkippedScopes @() -SkippedEligibilityScopes @() -PimLeftOut @() -RootScopeAssignments @() -SharedNames @()
            $Bullet = (($Md -split '(?m)^- `groupsRoster\.json` ')[1] -split '(?m)^- ')[0] -replace '\s+', ' '
            $Bullet | Should -Match ([regex]::Escape('-- a lightweight roster of EVERY group in the tenant, of every group type, read unfiltered: one row per group with its `id` and `displayName`, its type (`securityEnabled`, `mailEnabled` and `groupTypes`), `visibility`, `createdDateTime` and flags, including `onPremisesSynced`. The `id` tells apart two groups that share a name.'))
            # The roster used to be described as names and flags alone, which its rows no longer are.
            $Bullet | Should -Not -Match ([regex]::Escape('names + flags'))
        }
    }

    It 'says in the file roster that memberCount is null for a group the export did not read in full, and why (R3)' {
        InModuleScope $script:moduleName {
            $Md = Get-OERInventoryReadme -IncompleteReads @() -SkippedScopes @() -SkippedEligibilityScopes @() -PimLeftOut @() -RootScopeAssignments @() -SharedNames @()
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
            $Md = Get-OERInventoryReadme -IncompleteReads @() -SkippedScopes @() -SkippedEligibilityScopes @() -PimLeftOut @() -RootScopeAssignments @() -SharedNames @()
            $Md | Should -Match '(?m)^## Which groups are covered\r?$'
            $Section = (($Md -split '(?m)^## Which groups are covered\r?$')[1] -split '(?m)^## ')[0] -replace '\s+', ' '
            $Section | Should -Match ([regex]::Escape('A group synchronized from on-premises Active Directory (`onPremisesSynced` true in `groupsRoster.json`) is managed there and read-only in the cloud: it cannot be role-assignable or managed in PIM for Groups, so `inventory.json` details it only when the export ran with `-IncludeSyncedGroups` or `-AllGroupsDetailed`, and there it carries `onPremisesSynced: true`. `Invoke-OERStructure` writes nothing to such a group.'))
            # The paragraph belongs to the section it describes, ahead of the coverage limits.
            $Md.IndexOf('-IncludeSyncedGroups') | Should -BeLessThan $Md.IndexOf('## Coverage limits')
        }
    }

    It 'explains in "Which groups are covered" how the export chose the groups it detailed, and that -GroupFilter only narrows (A13)' {
        InModuleScope $script:moduleName {
            $Md = Get-OERInventoryReadme -IncompleteReads @() -SkippedScopes @() -SkippedEligibilityScopes @() -PimLeftOut @() -RootScopeAssignments @() -SharedNames @()
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
            $Md = Get-OERInventoryReadme -IncompleteReads @() -SkippedScopes @() -SkippedEligibilityScopes @() -PimLeftOut @() -RootScopeAssignments @() -SharedNames @()
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
            $Md = Get-OERInventoryReadme -IncompleteReads @() -SkippedScopes @() -SkippedEligibilityScopes @() -PimLeftOut @() -RootScopeAssignments @() -SharedNames @()
            # Whitespace collapsed first, so the assertion does not depend on where the paragraph wraps.
            $Section = ($Md -split '(?m)^## Next steps\r?$')[1] -replace '\s+', ' '
            $Section | Should -Match ([regex]::Escape('A proposal that keeps the `tenantId` of `inventory.json` is applied only in the tenant this export came from: `Invoke-OERStructure` refuses it anywhere else. To apply it in another tenant, change or remove `tenantId` first.'))
            # The sentence follows the apply step it qualifies, inside the Next steps section.
            $Section.IndexOf('`Invoke-OERStructure -Path ./proposal.json`') | Should -BeLessThan $Section.IndexOf('A proposal that keeps the `tenantId`')
        }
    }

    It 'contains only ASCII characters' {
        InModuleScope $script:moduleName {
            $Bytes = [System.Text.Encoding]::UTF8.GetBytes((Get-OERInventoryReadme -IncompleteReads @() -SkippedScopes @() -SkippedEligibilityScopes @() -PimLeftOut @() -RootScopeAssignments @() -SharedNames @()))
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
                Get-OERInventoryReadme -IncompleteReads $A -SkippedScopes $B -SkippedEligibilityScopes $C -PimLeftOut $D -RootScopeAssignments @() -SharedNames @()
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
        $Collapsed | Should -Match ([regex]::Escape('Apart from the entries labelled "Azure role management policies kept without being judged", each entry below names collections or objects that could not be read, could not be written without an empty name, or were left out because two or more live objects share a name; none of them is stated as a fact in this bundle.'))
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
                Get-OERInventoryReadme -IncompleteReads $I -SkippedScopes @() -SkippedEligibilityScopes @() -PimLeftOut $P -RootScopeAssignments @() -SharedNames @()
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
        # that, and ## Files follows it.
        $Headings[$Index + 2] | Should -BeExactly '## Role assignments at the root scope (elevated access)'
        $Headings[$Index + 3] | Should -BeExactly '## Names two or more objects share'
        $Headings[$Index + 4] | Should -BeExactly '## Files'
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
                Get-OERInventoryReadme -IncompleteReads @() -SkippedScopes @() -SkippedEligibilityScopes @() -PimLeftOut @() -RootScopeAssignments $R -SharedNames @()
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
        # BL-131: the shared names section comes directly after this one, ahead of ## Files.
        $Headings[$Index + 1] | Should -BeExactly '## Names two or more objects share'
        $Headings[$Index + 2] | Should -BeExactly '## Files'
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
                Get-OERInventoryReadme -IncompleteReads @() -SkippedScopes @() -SkippedEligibilityScopes @() -PimLeftOut @() -RootScopeAssignments @() -SharedNames $S
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
        $script:SharedProse = 'Microsoft Entra ID does not keep display names unique, and `Invoke-OERStructure` refuses a name that more than one live object answers to. So every object whose name another object of its kind shares, compared without regard to letter case, is left out of `inventory.json` and the per-area files -- all of them -- and is named under "What this export could not read" too. Groups are counted over every group in the tenant, Microsoft 365 groups and distribution groups included, so a security group that shares its name with one of those is left out as well; when the group roster could not be read (`groupsRoster` under "What this export could not read"), groups are counted among the security groups the export read. An assignment policy''s name is counted among the policies of its own access package only, and is listed with section `assignmentPolicies` as `<package>/<policy>`. A reference to such an object elsewhere in the document is written as the object''s id: the catalog of an access package, the access package and assignment policy of an access review, and a group named as the principal of a role assignment or a directory role assignment, written with `principalType` `Group`. Leaving them out of the export changes nothing in the tenant.'
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

    It 'says that an assignment policy''s name is counted within its own access package, and how it is listed (Sprint 11 step 5)' {
        $Collapsed = (Get-SharedSection -Readme (Get-SharedReadme)) -replace '\s+', ' '
        $Collapsed | Should -Match ([regex]::Escape('An assignment policy''s name is counted among the policies of its own access package only, and is listed with section `assignmentPolicies` as `<package>/<policy>`.'))
        # It follows the sentence on how groups are counted and precedes the one on references by id.
        $Collapsed.IndexOf('An assignment policy''s name is counted') | Should -BeGreaterThan $Collapsed.IndexOf('groups are counted among the security groups the export read.')
        $Collapsed.IndexOf('An assignment policy''s name is counted') | Should -BeLessThan $Collapsed.IndexOf('A reference to such an object elsewhere')
        # The group principal written by id is the one of a role assignment or a directory role
        # assignment: a group named elsewhere (an eligibility principal, a reviewer) keeps its name.
        $Collapsed | Should -Not -Match ([regex]::Escape('and a group named as a principal, written'))
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
        $Headings[$Index + 1] | Should -BeExactly '## Files'
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

Describe 'Get-OERInventoryReadme apply-document section list' {
    # The coverage paragraph counts and lists the apply-document sections. Tie both to the sections
    # schema.json declares, so a section added to the schema cannot leave the README claiming fewer.
    It 'counts and names every section schema.json declares, and names both directory role sections as captured' {
        InModuleScope $script:moduleName {
            $Md = Get-OERInventoryReadme -IncompleteReads @() -SkippedScopes @() -SkippedEligibilityScopes @() -PimLeftOut @() -RootScopeAssignments @() -SharedNames @()
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
