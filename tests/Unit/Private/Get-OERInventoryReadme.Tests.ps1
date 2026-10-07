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
            $Md = Get-OERInventoryReadme -IncompleteReads @() -SkippedScopes @() -SkippedEligibilityScopes @()
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
            $Md = Get-OERInventoryReadme -IncompleteReads @() -SkippedScopes @() -SkippedEligibilityScopes @()
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
            $Md = Get-OERInventoryReadme -IncompleteReads @() -SkippedScopes @() -SkippedEligibilityScopes @()
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
            $Md = Get-OERInventoryReadme -IncompleteReads @() -SkippedScopes @() -SkippedEligibilityScopes @()
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
            $Md = Get-OERInventoryReadme -IncompleteReads @() -SkippedScopes @() -SkippedEligibilityScopes @()
            # Regression guard: a group/application/directory-role review is excluded regardless
            # of stage count -- a different cause from the multi-stage skip above, so it needs its
            # own bullet rather than being folded into that one.
            $Md | Should -Match 'a group, an application or a directory role'
        }
    }

    It 'warns that an unread members, scopedRoles, resources or resourceRoles collection is written as null and must never be changed to []' {
        InModuleScope $script:moduleName {
            $Md = Get-OERInventoryReadme -IncompleteReads @() -SkippedScopes @() -SkippedEligibilityScopes @()
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

    It 'contains only ASCII characters' {
        InModuleScope $script:moduleName {
            $Bytes = [System.Text.Encoding]::UTF8.GetBytes((Get-OERInventoryReadme -IncompleteReads @() -SkippedScopes @() -SkippedEligibilityScopes @()))
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
            param([string[]]$IncompleteReads = @(), [string[]]$SkippedScopes = @(), [string[]]$SkippedEligibilityScopes = @())
            InModuleScope $script:moduleName -Parameters @{ A = $IncompleteReads; B = $SkippedScopes; C = $SkippedEligibilityScopes } {
                param($A, $B, $C)
                Get-OERInventoryReadme -IncompleteReads $A -SkippedScopes $B -SkippedEligibilityScopes $C
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
        $Collapsed | Should -Match ([regex]::Escape('Each entry below names collections or objects that could not be read, could not be written without an empty name, or were left out because two or more live objects share a name; none of them is stated as a fact in this bundle.'))
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

Describe 'Get-OERInventoryReadme apply-document section list' {
    # The coverage paragraph counts and lists the apply-document sections. Tie both to the sections
    # schema.json declares, so a section added to the schema cannot leave the README claiming fewer.
    It 'counts and names every section schema.json declares, and names both directory role sections as captured' {
        InModuleScope $script:moduleName {
            $Md = Get-OERInventoryReadme -IncompleteReads @() -SkippedScopes @() -SkippedEligibilityScopes @()
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
        }
    }
}
