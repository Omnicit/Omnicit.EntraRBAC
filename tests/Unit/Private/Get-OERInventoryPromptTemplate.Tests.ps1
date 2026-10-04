BeforeAll {
    $script:moduleName = 'Omnicit.EntraRBAC'
    Get-Module $script:moduleName | Remove-Module -Force -ErrorAction SilentlyContinue
    Import-Module $script:moduleName -Force -ErrorAction Stop
}

Describe 'Get-OERInventoryPromptTemplate' {
    It 'returns a string covering the schema, the three tiers, and the preferences block' {
        InModuleScope $script:moduleName {
            $P = Get-OERInventoryPromptTemplate
            $P | Should -BeOfType ([string])
            $P | Should -Match 'USER PREFERENCES'
            $P | Should -Match 'Foundational'
            $P | Should -Match 'Recommended'
            $P | Should -Match 'Advanced'
            # schema contract markers
            $P | Should -Match 'roleManagementPolicies'
            $P | Should -Match 'activationMaxHours'
            $P | Should -Match 'SharePointSite'
            $P | Should -Match 'Test-OERStructure'
            # references the embedded JSON Schema and the common-value reference
            $P | Should -Match 'schema\.json'
            $P | Should -Match 'User Access Administrator'
        }
    }

    It 'injects a supplied naming convention into the preferences block' {
        InModuleScope $script:moduleName {
            $P = Get-OERInventoryPromptTemplate -NamingConvention 'role_sec_{area}_{tier}'
            $P | Should -Match ([regex]::Escape('role_sec_{area}_{tier}'))
        }
    }

    It 'documents the nested member/owner pimPolicy fields' {
        InModuleScope $script:moduleName {
            $P = Get-OERInventoryPromptTemplate
            $P | Should -Match 'member'
            $P | Should -Match 'owner'
            $P | Should -Match 'activationEnablement'
            $P | Should -Match 'notifications'
        }
    }

    It 'warns that pimPolicy is exported only for groups found to use PIM for Groups and onboards on write' {
        InModuleScope $script:moduleName {
            $T = (Get-OERInventoryPromptTemplate) -replace '\s+', ' '
            $T | Should -Match 'pimPolicy is exported only for a group the inventory found to use PIM for Groups'
            $T | Should -Match ([regex]::Escape('Adding or changing a pimPolicy on a group that does not use PIM for Groups yet ONBOARDS it, which cannot be undone'))
            $T | Should -Match 'propose that only deliberately, and say so in the rationale'
        }
    }

    It 'documents the granular assignment policy fields' {
        InModuleScope $script:moduleName {
            $T = Get-OERInventoryPromptTemplate
            $T | Should -Match 'requestorSettings'
            $T | Should -Match 'requireApproval'
            $T | Should -Match 'approverInfoVisibility'
            $T | Should -Match 'durationInHours'
            $T | Should -Match 'notificationsDisabled'
        }
    }

    It 'tells the model that an omitted requestorScope.scope infers SpecificDirectoryUsers (issue #69)' {
        InModuleScope $script:moduleName {
            $T = Get-OERInventoryPromptTemplate
            $T | Should -Match 'an explicit scope always wins'
            $T | Should -Match 'infers SpecificDirectoryUsers'
        }
    }

    It 'tells the model the role assignment fields are applied in place at the defining scope' {
        InModuleScope $script:moduleName {
            $T = Get-OERInventoryPromptTemplate
            # The engine updates description/condition/conditionVersion in place now; the old wording
            # told the model the engine would only report drift, so it never proposed such a change.
            $T | Should -Not -Match 'reports\s+drift on them instead of updating in place'
            $T | Should -Match 'IN PLACE'
            $T | Should -Match 'DEFINED'
        }
    }

    It 'documents the scope forms, the one-scope rule and the declare-once rule' {
        InModuleScope $script:moduleName {
            # Whitespace collapsed first, so the assertions do not depend on where the lines wrap.
            $Collapsed = (Get-OERInventoryPromptTemplate) -replace '\s+', ' '
            # The short forms the apply engine accepts, next to the ARM strings in both places.
            $Collapsed | Should -Match ([regex]::Escape('sub:<guid or name> (also subscription:<guid or name>) and mg:<name or display name>'))
            $Collapsed | Should -Match ([regex]::Escape('the short forms sub:<guid or name>, subscription:<guid or name> and mg:<name or display name> name the same scopes'))
            # Two spellings of one scope are one scope, compared without regard to case. A trailing or
            # doubled slash is not a spelling: the offline check refuses it (A15).
            $Collapsed | Should -Match ([regex]::Escape('compares scopes without regard to letter case, so two spellings of one scope are ONE scope'))
            $Collapsed | Should -Match ([regex]::Escape('write a scope without a trailing / and without //: the offline check reports either as an Error'))
            $Collapsed | Should -Match ([regex]::Escape('sub:, subscription: or mg:, never with a trailing / or //), and each (scope, role) is declared once'))
            $Collapsed | Should -Not -Match 'ignoring a trailing /'
            # The declare-once rules, for roleAssignments, roleManagementPolicies and the other sections.
            $Collapsed | Should -Match ([regex]::Escape('declare each (scope, role, principal) once'))
            $Collapsed | Should -Match ([regex]::Escape('each (scope, role) is declared once'))
            $Collapsed | Should -Match ([regex]::Escape('and each access package once per catalog'))
            # The role is matched on its GUID, so a GUID matches the live assignment below a subscription.
            $Collapsed | Should -Match ([regex]::Escape('is matched on its GUID, so a role given as a GUID matches the live assignment at a resource group or management group'))
        }
    }

    It 'tells the model to reciprocate a group administrativeUnit in the unit members array (issue #59)' {
        InModuleScope $script:moduleName {
            $T = Get-OERInventoryPromptTemplate
            $T | Should -Match 'administrativeUnit is create-only and never round-trips'
            $T | Should -Match 'MUST also add this group''s displayName to the members\[\] array'
            $T | Should -Match '-Prune removes the membership'
        }
    }

    It 'tells the model that a dynamic administrative unit owns its own membership' {
        InModuleScope $script:moduleName {
            $T = Get-OERInventoryPromptTemplate
            $T | Should -Match 'membershipRule'
            $T | Should -Match 'only reconciled on an ASSIGNED unit'
        }
    }

    It 'tells the model where the apply document stops covering the tenant' {
        InModuleScope $script:moduleName {
            $T = Get-OERInventoryPromptTemplate
            # Without this the LLM assumes the four areas are covered and emits an apply document
            # declaring invented resource-group scopes, PIM eligibility, or a "corrected" review.
            $T | Should -Match 'Coverage limits'
            $T | Should -Match 'Azure resource GROUPS and individual RESOURCES'
            $T | Should -Match 'Azure PIM eligible and active role assignments are NOT appliable'
            $T | Should -Match 'SKIPPED entirely'
            $T | Should -Match 'ACCESS-PACKAGE-SCOPED'
            # each area must point at the cmdlet that does manage it
            $T | Should -Match 'New-OERResourceGroup'
            $T | Should -Match 'Get-OERResource'
            $T | Should -Match 'New-OEREligibleRoleAssignment'
            $T | Should -Match 'New-OERActiveRoleAssignment'
            $T | Should -Match 'New-OERAccessReviewStage'
        }
    }

    It 'points the model at azurePimEligibility.json for the eligible half, but never lets it express eligibility itself' {
        InModuleScope $script:moduleName {
            $T = Get-OERInventoryPromptTemplate
            # Regression guard for a stale claim: eligible Azure PIM assignments used to be entirely
            # uncaptured; Export-OERInventory now writes them into azurePimEligibility.json as
            # read-only context, so the Inputs list and the coverage bullet must both say so -- while
            # still refusing to let the model express an eligibility inside the apply document.
            $T | Should -Match ([regex]::Escape('azurePimEligibility.json'))
            $T | Should -Match 'do not try to express the eligibility itself'
        }
    }

    It 'does not claim a resource-group-scoped role assignment is unappliable' {
        InModuleScope $script:moduleName {
            $T = Get-OERInventoryPromptTemplate
            # The engine's roleAssignments scope pre-pass (Resolve-OERStructureRoleAssignmentScope)
            # parses any '/'-prefixed scope with ConvertTo-OERScopeSplat -- which only trims a
            # trailing '/' -- and hands it to Resolve-OERScope, which handles
            # /subscriptions/{id}/resourceGroups/{rg}. Saying otherwise would contradict the
            # least-privilege principle stated further down the prompt and push the model toward
            # needlessly broad grants.
            $T | Should -Match 'resource-group or resource scope does apply'
            $T | Should -Match 'preserve it verbatim'
            $T | Should -Match 'Least privilege'
            # A resource-group-scoped eligibility can now reach azurePimEligibility.json (see the
            # R4 below-scope coverage), so a verbatim scope already there is a second legitimate
            # source, not just inventory.json. \s+ bridges the prose's own line wrap between the
            # filename and its parenthetical -- the source text wraps at ~100 chars, and a raw
            # multi-line here-string keeps that newline as a literal character -Match sees.
            $T | Should -Match 'azurePimEligibility\.json\s+\(an eligibility there can be scoped below a subscription\)'
        }
    }

    It 'states a multi-stage review is skipped rather than fabricated as a lossy self review' {
        InModuleScope $script:moduleName {
            $T = Get-OERInventoryPromptTemplate
            # Regression guard for a stale claim: Get-OERInventory no longer fabricates a
            # single-stage self review out of a multi-stage one (commit 611f241) -- it skips the
            # review entirely with a warning, so the prompt must not tell the model otherwise.
            $T | Should -Not -Match 'reviewers \["self"\]'
            $T | Should -Not -Match 'captured LOSSILY'
            $T | Should -Match 'fabricated as a single-stage self review'
        }
    }

    It 'names the access-package-scope carve-out as its own coverage limit' {
        InModuleScope $script:moduleName {
            $T = Get-OERInventoryPromptTemplate
            # Regression guard: a group/application/directory-role review is excluded regardless
            # of stage count -- a different cause from the multi-stage skip above, so it needs its
            # own bullet rather than being folded into that one.
            $T | Should -Match 'a group, an application or a directory role'
        }
    }

    It 'contains only ASCII characters' {
        InModuleScope $script:moduleName {
            $Bytes = [System.Text.Encoding]::UTF8.GetBytes((Get-OERInventoryPromptTemplate))
            ($Bytes | Where-Object { $_ -gt 127 }).Count | Should -Be 0
        }
    }

    It 'states the absent / null / empty-array rule' {
        InModuleScope $script:moduleName {
            $Prompt = Get-OERInventoryPromptTemplate
            # 'null' alone pre-dates this branch's own change (it already appeared five times in
            # the prompt, e.g. the roleAssignments/roleManagementPolicies sections) and would
            # match even without the new section this test guards. Anchor on the new section's own
            # header instead.
            $Prompt | Should -Match 'Document semantics -- absent vs null vs empty'
            $Prompt | Should -Match 'empty array'
        }
    }

    It 'states the child-collection absent/null/empty rule differs from the scalar rule' {
        InModuleScope $script:moduleName {
            $Prompt = Get-OERInventoryPromptTemplate
            # The trap this guards: applying the scalar "absent == null" rule to a child
            # collection like members is backwards -- an absent members key still prunes.
            $Prompt | Should -Match 'CHILD COLLECTION'
            $Prompt | Should -Match 'eligibility and owners'
        }
    }

    It 'tells the model that a null in inventory.json means unknown, not empty, and never to turn it into []' {
        InModuleScope $script:moduleName {
            # Whitespace collapsed first, so the assertion does not depend on where the line wraps.
            $Collapsed = (Get-OERInventoryPromptTemplate) -replace '\s+', ' '
            $Collapsed | Should -Match ([regex]::Escape('The inventory writes null for a members, scopedRoles, resources or resourceRoles collection it could not read (the export reports it as partial), so a null in inventory.json means unknown, not empty: keep it null in every proposal, and never turn it into [].'))
            # The claim names the four collections: an unread owners or eligibility collection is
            # omitted, not null, so a flat "a collection it could not read" would be false of it.
            $Collapsed | Should -Not -Match ([regex]::Escape('The inventory writes null for a collection it could not read'))
            # The scalar paragraph used to say the inventory omits keys rather than emit null, flatly.
            # That is no longer true of an unread child collection, so it must not be claimed.
            $Collapsed | Should -Not -Match 'The inventory itself omits most keys rather than emit null'
            $Collapsed | Should -Match ([regex]::Escape('Apart from an unread members, scopedRoles, resources or resourceRoles collection (see below), the inventory omits most keys rather than emit null'))
            $Collapsed | Should -Match 'to assert a list is genuinely empty you must hand-author an explicit \[\]'
        }
    }

    It 'documents pimPolicy approval fields and their precedence' {
        InModuleScope $script:moduleName {
            $T = Get-OERInventoryPromptTemplate
            $T | Should -Match 'requireApproval \(bool\)'
            $T | Should -Match 'approvers \{ users\[\]'
            $T | Should -Match 'requireApproval false wins'
            $T | Should -Match 'names are resolved to object ids before\s+comparison'
            # The true rule for approvers declared without requireApproval: written only when they
            # differ from the live approvers, and writing them turns approval on. The old sentence
            # ("apply only when requireApproval is true") was false for exactly that case.
            $T | Should -Match 'to require approval, declare requireApproval: true'
            $T | Should -Match 'approvers declared without requireApproval\s+are written only when they differ from the live approvers, and writing them turns approval on'
            $T | Should -Not -Match 'approvers apply only when requireApproval is true'
        }
    }

    It 'documents the three keys Tasks 16 and 17 added to the schema' {
        InModuleScope $script:moduleName {
            $Prompt = Get-OERInventoryPromptTemplate
            $Prompt | Should -Match 'owners\[\]'
            # A bare 'membershipRuleProcessingState' match is not discriminating: the key already
            # appeared in the administrativeUnits[] bullet before this branch touched the file.
            # Anchor on the groups[]-specific phrasing this branch actually added.
            $Prompt | Should -Match 'membershipRuleProcessingState \(On\|Paused; dynamic'
            $Prompt | Should -Match 'externallyVisible'
        }
    }
}

Describe 'Get-OERInventoryPromptTemplate apply-document section list' {
    # The coverage paragraph counts and lists the apply-document sections. Tie both to the sections
    # schema.json declares, so a section added to the schema cannot leave the prompt claiming fewer.
    It 'counts and names every section schema.json declares, and names both directory role sections as captured' {
        InModuleScope $script:moduleName {
            $T = Get-OERInventoryPromptTemplate
            $Sections = @((Get-OERStructureSchemaJson | ConvertFrom-Json).properties.PSObject.Properties.Name |
                    Where-Object { $_ -notin @('version', 'tenantAlias') })
            $Word = @{ 7 = 'seven'; 8 = 'eight'; 9 = 'nine'; 10 = 'ten' }[$Sections.Count]
            $T | Should -Match "The apply document has exactly $Word sections"
            foreach ($Section in $Sections) {
                $T | Should -Match "\b$Section\b"
            }
            # Whitespace collapsed first, so the assertion does not depend on where the paragraph wraps.
            $Collapsed = $T -replace '\s+', ' '
            $Collapsed | Should -Not -Match 'apply-only for now'
            $Collapsed | Should -Not -Match 'does not read them'
            $Collapsed | Should -Match ([regex]::Escape('directoryRoleManagementPolicies (the PIM settings of Microsoft Entra directory roles) and directoryRoleAssignments (eligible and active assignments of Microsoft Entra directory roles) are both captured in inventory.json (policies for roles with at least one eligible or active assignment unless the export used -AllDirectoryRolePolicies; assignments that are direct and at tenant scope -- activations and assignments inherited through a group are not listed), and may be proposed.'))
        }
    }

    It 'documents the directoryRoleManagementPolicies[] and directoryRoleAssignments[] output-schema fields' {
        InModuleScope $script:moduleName {
            $T = (Get-OERInventoryPromptTemplate) -replace '\s+', ' '
            $T | Should -Match ([regex]::Escape('directoryRoleManagementPolicies[]: { role (required -- a Microsoft Entra directory role display name or role definition id), and the same fields as roleManagementPolicies without scope }'))
            $T | Should -Match 'approvers replace only the declared side \(users or groups\); an empty array clears that side'
            $T | Should -Match 'the policy always exists and is never removed'
            $T | Should -Match 'it is applied before directoryRoleAssignments'
            $T | Should -Match ([regex]::Escape('directoryRoleAssignments[]: { role (required), principal (required -- UPN, group display name, or service principal OBJECT ID), principalType (User | Group | ServicePrincipal), assignmentType (required -- Eligible | Active), durationDays (1-3650; omit for a permanent assignment), permanent (bool), justification }'))
            $T | Should -Match 'matched on role, principal and assignmentType'
            $T | Should -Match ([regex]::Escape('a permanent assignment needs a policy that allows it (declare it in directoryRoleManagementPolicies)'))
            $T | Should -Match 'only role-assignable groups can hold a directory role'
            $T | Should -Match ([regex]::Escape('under -Prune only the (role, assignmentType) pairs the document declares are reconciled'))
            $T | Should -Match "the signed-in identity's own assignments are never removed"
            $T | Should -Match 'prefer Eligible over Active for privileged roles'
        }
    }

    It 'extends the Entra directory roles common-values line with the two new role fields' {
        InModuleScope $script:moduleName {
            $T = (Get-OERInventoryPromptTemplate) -replace '\s+', ' '
            $T | Should -Match ([regex]::Escape('Entra directory roles (directoryRoleManagementPolicies[].role, directoryRoleAssignments[].role, administrativeUnits[].scopedRoles[].role):'))
        }
    }
}

Describe 'Get-OERInventoryPromptTemplate group rename through previousDisplayName' {
    # The groups bullet used to tell the model a rename was impossible. previousDisplayName now
    # renames a group in place, so the prompt must teach the rule -- while the units, catalogs and
    # access packages, which still cannot be renamed, keep their sentences.
    It 'teaches the rename rule and lists previousDisplayName among the group fields' {
        InModuleScope $script:moduleName {
            # Whitespace collapsed first, so the assertions do not depend on where the prose wraps.
            $T = (Get-OERInventoryPromptTemplate) -replace '\s+', ' '
            $T | Should -Match ([regex]::Escape('displayName is the match key: an existing group is matched and updated by it. To rename a group, declare its new name as displayName and its current name as previousDisplayName: the group found under previousDisplayName alone is renamed in place. When both names match different groups the entry fails and nothing is changed (two groups are never merged), and when neither matches the entry fails and nothing is created: a rename names an existing group. A NEW group is declared without previousDisplayName.'))
            $T | Should -Match ([regex]::Escape('{ displayName (or template + tokens object), previousDisplayName (rename only'))
            $T | Should -Match ([regex]::Escape("previousDisplayName (rename only -- the group's current display name or object id when displayName declares a new one"))
            $T | Should -Not -Match 'changing displayName creates a new group'
            # A rename must carry every other reference to the group with it, directory role
            # assignments included, and the model must be told the name lookup can lag the rename.
            $T | Should -Match ([regex]::Escape('When a proposal renames a group, every other reference to it in the same document uses the NEW name: administrativeUnits members, catalog resources[] and access package resourceRoles[], eligibility, owner, member and approver entries, and roleAssignments and directoryRoleAssignments principals.'))
            # Measured live 2026-09-30: a catalog keeps the name it recorded for a resource after the
            # group's rename, so a Group or Application resource is matched by object id, and the model
            # is told the inventory writes the CURRENT name -- no "keep the old name" exception.
            $T | Should -Match ([regex]::Escape('A Group or Application catalog resource (and a resourceRole on one) is identified by the object id its name resolves to, never by the name the catalog recorded when the resource was added'))
            $T | Should -Not -Match 'EXCEPTION -- they are matched by the display name the catalog recorded'
            $T | Should -Match ([regex]::Escape("Microsoft Graph's name lookup can follow a rename with a delay."))
            $T | Should -Match ([regex]::Escape('a re-run while neither name resolves yet fails the entry and creates nothing. Keep previousDisplayName in the proposal'))
            # The three sections that still cannot be renamed keep saying so.
            $T | Should -Match 'changing displayName creates a new unit'
            $T | Should -Match 'changing displayName creates a new catalog'
            $T | Should -Match 'changing displayName creates a new package'
        }
    }
}
