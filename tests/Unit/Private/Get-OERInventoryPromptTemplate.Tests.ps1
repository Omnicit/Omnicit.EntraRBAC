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
            $T | Should -Match 'Azure PIM eligible and active role assignments are NOT captured'
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

    It 'does not claim a resource-group-scoped role assignment is unappliable' {
        InModuleScope $script:moduleName {
            $T = Get-OERInventoryPromptTemplate
            # Sync-OERStructureRoleAssignment passes any '/'-prefixed scope straight to
            # Resolve-OERScope, which handles /subscriptions/{id}/resourceGroups/{rg}. Saying
            # otherwise would contradict the least-privilege principle stated further down the
            # prompt and push the model toward needlessly broad grants.
            $T | Should -Match 'resource-group or resource scope does apply'
            $T | Should -Match 'preserve it verbatim'
            $T | Should -Match 'Least privilege'
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
