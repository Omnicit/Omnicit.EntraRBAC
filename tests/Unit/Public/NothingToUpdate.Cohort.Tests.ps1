BeforeDiscovery {
    # Cross-cmdlet suite, named after no single function (like AccessReview.Pipeline.Tests.ps1 and
    # AmbiguousName.Guard.Tests.ps1): the identical "no updatable property was supplied" guard used to
    # speak three dialects -- NoUpdateSpecified, NoChange and NothingToUpdate -- so a caller writing
    # catch { if ($_.FullyQualifiedErrorId -match 'NothingToUpdate') { ... } } silently missed three of
    # the six cmdlets that carried the guard at the time. Issue #47 closed the coverage gap: the guard
    # now reaches ALL ELEVEN exported Set-OER* cmdlets, and this cohort is COMPLETE -- any future
    # Set-OER* cmdlet is expected to join $script:NothingToUpdateCases below, not to be a documented
    # exception. Every one of them is asserted here in one place, so a fourth spelling cannot creep back
    # in unnoticed. Do not delete this file as an orphan when auditing the one-test-file-per-function
    # invariant.
    #
    # Set-OERRoleManagementPolicy is a deliberate DIFFERENT case, not a gap: when a setting IS supplied
    # but matches the live policy, it reports the separate NoChange id ("a setting was supplied, no rule
    # differs"), asserted by the second It block below. NoChange and NothingToUpdate must stay distinct
    # -- collapsing them would make "you passed nothing" and "you passed something that already matches"
    # indistinguishable to a caller.
    #
    # Two members of the cohort carry predicates that are narrower than "any parameter", both by
    # design (issue #47, Philip's call):
    #   - Set-OERAccessPackageAssignmentPolicy's -DisplayName is Mandatory and is re-sent on every call,
    #     so it cannot itself signal an update. The predicate is "no property beyond -DisplayName", so a
    #     rename-only call (-Id and -DisplayName alone) is refused BY DESIGN. Do not read that as a bug
    #     to "fix" in a later audit.
    #   - Set-OERAccessReviewDefinition deliberately excludes -EndDate and -Occurrences from its
    #     updatable set: neither changes anything unless -Recurrence and -StartDate are also supplied,
    #     so a call carrying only one of them would still be a no-op.
    #
    # Two members also place the guard somewhere other than the first statement of process, again by
    # design, so a more specific pre-existing error keeps priority: Set-OERConfiguration guards AFTER
    # its InvalidTenantAlias check (a path-traversal guard on a mandatory parameter), and
    # Set-OERAccessReviewDefinition guards AFTER its MutuallyExclusiveParameter check (-EndDate with
    # -Occurrences).
    $script:NothingToUpdateCases = @(
        @{
            Cmdlet = 'Set-OERAdministrativeUnit'
            Invoke = {
                Set-OERAdministrativeUnit -Id 'a1111111-0000-0000-0000-000000000001' `
                    -Confirm:$false -ErrorAction SilentlyContinue -ErrorVariable Err | Out-Null
                $Err
            }
        }
        @{
            Cmdlet = 'Set-OERGroup'
            Invoke = {
                Set-OERGroup -Group 'a2222222-0000-0000-0000-000000000002' `
                    -Confirm:$false -ErrorAction SilentlyContinue -ErrorVariable Err | Out-Null
                $Err
            }
        }
        @{
            Cmdlet = 'Set-OERAccessPackage'
            Invoke = {
                Set-OERAccessPackage -Id 'a3333333-0000-0000-0000-000000000003' `
                    -Confirm:$false -ErrorAction SilentlyContinue -ErrorVariable Err | Out-Null
                $Err
            }
        }
        @{
            Cmdlet = 'Set-OERCatalog'
            Invoke = {
                Set-OERCatalog -Id 'a4444444-0000-0000-0000-000000000004' `
                    -Confirm:$false -ErrorAction SilentlyContinue -ErrorVariable Err | Out-Null
                $Err
            }
        }
        @{
            Cmdlet = 'Set-OERRoleAssignment'
            Invoke = {
                Set-OERRoleAssignment -Id '/subscriptions/s/providers/Microsoft.Authorization/roleAssignments/00000000-0000-0000-0000-000000000059' `
                    -Confirm:$false -ErrorAction SilentlyContinue -ErrorVariable Err | Out-Null
                $Err
            }
        }
        @{
            Cmdlet = 'Set-OERRoleManagementPolicy'
            Invoke = {
                Set-OERRoleManagementPolicy -PolicyId '/s/providers/Microsoft.Authorization/roleManagementPolicies/pol1' `
                    -Confirm:$false -ErrorAction SilentlyContinue -ErrorVariable Err | Out-Null
                $Err
            }
        }
        @{
            Cmdlet = 'Set-OERResourceGroup'
            Invoke = {
                Set-OERResourceGroup -Subscription 'a5555555-0000-0000-0000-000000000005' -Name 'rg-guard' `
                    -Confirm:$false -ErrorAction SilentlyContinue -ErrorVariable Err | Out-Null
                $Err
            }
        }
        @{
            Cmdlet = 'Set-OERGroupPimPolicy'
            Invoke = {
                Set-OERGroupPimPolicy -Group 'a6666666-0000-0000-0000-000000000006' `
                    -Confirm:$false -ErrorAction SilentlyContinue -ErrorVariable Err | Out-Null
                $Err
            }
        }
        @{
            Cmdlet = 'Set-OERAccessReviewDefinition'
            Invoke = {
                Set-OERAccessReviewDefinition -Id 'a7777777-0000-0000-0000-000000000007' `
                    -Confirm:$false -ErrorAction SilentlyContinue -ErrorVariable Err | Out-Null
                $Err
            }
        }
        @{
            # -DisplayName is Mandatory on this cmdlet, so it must be supplied even though the guard's
            # predicate deliberately excludes it -- see the BeforeDiscovery header comment above.
            Cmdlet = 'Set-OERAccessPackageAssignmentPolicy'
            Invoke = {
                Set-OERAccessPackageAssignmentPolicy -Id 'a8888888-0000-0000-0000-000000000008' -DisplayName 'Policy' `
                    -Confirm:$false -ErrorAction SilentlyContinue -ErrorVariable Err | Out-Null
                $Err
            }
        }
        @{
            # -BasePath MUST stay under $TestDrive: if this guard were ever deleted, the call must not
            # reach the operator's real Tenant Profile directory under the user's home folder.
            Cmdlet = 'Set-OERConfiguration'
            Invoke = {
                Set-OERConfiguration -TenantAlias 'guardalias' -BasePath (Join-Path $TestDrive 'CohortGuard') `
                    -Confirm:$false -ErrorAction SilentlyContinue -ErrorVariable Err | Out-Null
                $Err
            }
        }
    )
}

BeforeAll {
    $script:moduleName = 'Omnicit.EntraRBAC'
    Get-Module $script:moduleName | Remove-Module -Force -ErrorAction SilentlyContinue
    Import-Module $script:moduleName -Force -ErrorAction Stop
}

Describe 'The no-updatable-property guard reports one id across the whole Set-* cohort' {
    BeforeEach {
        InModuleScope $script:moduleName { $script:_OERAuthState = $null }
    }

    It 'covers every exported Set-OER* cmdlet, matching the header''s completeness claim' {
        # The BeforeDiscovery header above claims the cohort is COMPLETE: all eleven exported Set-OER*
        # cmdlets carry the guard, and any future one is expected to join $script:NothingToUpdateCases.
        # Nothing enforced that claim -- the case list is a hand-written literal, so a twelfth Set-OER*
        # cmdlet added tomorrow would fail nothing here. Derive the live roster from the module itself,
        # the same approach the -BasePath carrier roster guard uses in
        # tests/Unit/Private/BasePathDefault.Cohort.Tests.ps1, and diff it against the case list on both
        # the exact sorted name set and the exact count, so a NEW unguarded cmdlet and a SILENTLY DROPPED
        # case both break the build. Otherwise the header's completeness claim is just an unbacked doc
        # comment -- the exact class of problem PR #49 added AST-driven guards for in this repo.
        #
        # $script:NothingToUpdateCases itself is set inside BeforeDiscovery, which -- unlike BeforeAll --
        # runs only during Pester's Discovery pass and is unset again by the time this It body executes
        # in the Run pass (proven: a BeforeDiscovery-set $script: variable reads back $null/empty inside
        # an It). So the case roster is read back from this file's own AST instead of the variable, which
        # works in both passes and needs no separate hand-maintained copy of the Cmdlet list to drift.
        $LiveRoster = @(Get-Command -Module $script:moduleName -Name 'Set-OER*' |
                Select-Object -ExpandProperty Name | Sort-Object)

        $FileAst = [System.Management.Automation.Language.Parser]::ParseFile($PSCommandPath, [ref]$null, [ref]$null)
        $CaseRoster = @(
            $FileAst.FindAll({
                    param($Node)
                    $Node -is [System.Management.Automation.Language.HashtableAst]
                }, $true) | ForEach-Object {
                $CmdletPair = $_.KeyValuePairs | Where-Object { $_.Item1.Extent.Text -eq 'Cmdlet' }
                if ($CmdletPair) { $CmdletPair.Item2.SafeGetValue() }
            } | Sort-Object
        )

        $LiveRoster | Should -Be $CaseRoster
        $LiveRoster.Count | Should -Be 11
        $CaseRoster.Count | Should -Be 11
    }

    It '<Cmdlet> reports NothingToUpdate and issues no request when no updatable property is supplied' -ForEach $script:NothingToUpdateCases {
        Mock -ModuleName $script:moduleName Initialize-OERAuth {}
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {}
        Mock -ModuleName $script:moduleName Invoke-OERArmRequest {}

        $Err = & $Invoke

        # Cmdlet-qualified id: a bare-code match would pass even with the WriteError deleted, because
        # PowerShell re-records a thrown record into -ErrorVariable at every call boundary it crosses.
        @($Err | Where-Object { $_.FullyQualifiedErrorId -eq "NothingToUpdate,$Cmdlet" }).Count | Should -Be 1
        # The retired spellings must not come back on any member of the cohort.
        @($Err | Where-Object { $_.FullyQualifiedErrorId -in @("NoUpdateSpecified,$Cmdlet", "NoChange,$Cmdlet") }).Count | Should -Be 0
        # The guard refuses the call outright: nothing reached Graph or ARM.
        Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 0 -Exactly
        Should -Invoke -ModuleName $script:moduleName Invoke-OERArmRequest -Times 0 -Exactly
    }

    It 'keeps NoChange distinct on Set-OERRoleManagementPolicy: settings were supplied, no rule differs' {
        # This is a DIFFERENT condition from the cohort guard above -- the caller did supply a setting,
        # it simply matches the live policy -- so it deliberately keeps its own id. Renaming it to
        # NothingToUpdate would make the two indistinguishable to a caller.
        Mock -ModuleName $script:moduleName Initialize-OERAuth {}
        Mock -ModuleName $script:moduleName Invoke-OERArmRequest {
            [PSCustomObject]@{ properties = [PSCustomObject]@{ rules = @(); scope = '/s' } }
        }
        Mock -ModuleName $script:moduleName Resolve-OERPolicyRulePatch {
            [PSCustomObject]@{ ChangedRuleId = @(); Rules = @() }
        }

        Set-OERRoleManagementPolicy -PolicyId '/s/providers/Microsoft.Authorization/roleManagementPolicies/pol1' `
            -ActivationMaxHours 8 -Confirm:$false -ErrorAction SilentlyContinue -ErrorVariable Err | Out-Null

        @($Err | Where-Object { $_.FullyQualifiedErrorId -eq 'NoChange,Set-OERRoleManagementPolicy' }).Count | Should -Be 1
        @($Err | Where-Object { $_.FullyQualifiedErrorId -eq 'NothingToUpdate,Set-OERRoleManagementPolicy' }).Count | Should -Be 0
        # No PATCH was attempted: the only ARM call is the policy read.
        Should -Invoke -ModuleName $script:moduleName Invoke-OERArmRequest -Times 0 -Exactly -ParameterFilter { $Method -eq 'PATCH' }
    }
}
