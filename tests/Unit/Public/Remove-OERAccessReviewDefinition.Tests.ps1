BeforeAll {
    Import-Module Omnicit.EntraRBAC -Force
    . "$PSScriptRoot/../TestHelpers/OERConfirmHost.ps1"
}

Describe 'Remove-OERAccessReviewDefinition' {
    BeforeEach {
        InModuleScope Omnicit.EntraRBAC { $script:_OERAuthState = $null }
        Mock -ModuleName Omnicit.EntraRBAC Initialize-OERAuth { }
        Mock -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest { }
    }

    It 'DELETEs by id when confirmed' {
        Remove-OERAccessReviewDefinition -Id 'd1' -Confirm:$false
        Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest -ParameterFilter {
            $Method -eq 'DELETE' -and
            $Uri -eq 'v1.0/identityGovernance/accessReviews/definitions/d1'
        }
    }

    It 'warns before deleting and still issues the DELETE' {
        # CLAUDE.md SECURITY rule #4: audit PR9 Task 7 sweep -- Remove-OERAccessReviewDefinition.ps1:60
        # emits an operator warning before the destructive DELETE, but no It captured it.
        $Warnings = @()
        Remove-OERAccessReviewDefinition -Id 'd1' -Confirm:$false -WarningVariable Warnings -WarningAction SilentlyContinue
        $Warnings.Count | Should -BeGreaterThan 0
        $Warnings -join ' ' | Should -Match 'irreversible'
        Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest -Times 1 -ParameterFilter {
            $Method -eq 'DELETE' -and
            $Uri -eq 'v1.0/identityGovernance/accessReviews/definitions/d1'
        }
    }

    It 'destroys nothing with -WhatIf' {
        # NARROWED DELIBERATELY (live check 14.1.2): this used to assert the cmdlet makes NO Graph call
        # at all under -WhatIf. The diagnostic GET that feeds the scope warning now runs ahead of
        # ShouldProcess, so it happens under -WhatIf too -- on purpose, since the warning is precisely
        # what a -WhatIf run exists to show, and a GET changes nothing in the tenant. What -WhatIf must
        # still guarantee is the absence of the DESTRUCTIVE call, which is what this now pins.
        Remove-OERAccessReviewDefinition -Id 'd1' -WhatIf
        Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest -Times 0 -Exactly -ParameterFilter {
            $Method -eq 'DELETE'
        }
    }

    It 'resolves by display name (ByName) then DELETEs the resolved id' {
        Mock -ModuleName Omnicit.EntraRBAC Resolve-OERAccessReviewDefinitionId { 'resolved-id-1' }
        Remove-OERAccessReviewDefinition -DisplayName 'Q3 AP Review' -Confirm:$false
        Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest -ParameterFilter {
            $Method -eq 'DELETE' -and
            $Uri -eq 'v1.0/identityGovernance/accessReviews/definitions/resolved-id-1'
        }
    }

    It 'writes a non-terminating error (no DELETE) when definition resolution throws (Fix 4 bearer-leak guard path)' {
        Mock -ModuleName Omnicit.EntraRBAC Resolve-OERAccessReviewDefinitionId { throw 'resolution failed' }
        Remove-OERAccessReviewDefinition -DisplayName 'ghost-def' -Confirm:$false -ErrorVariable ErrVar -ErrorAction SilentlyContinue
        # Match the cmdlet-QUALIFIED ErrorId. The mock's own thrown record is auto-recorded into
        # -ErrorVariable at roughly a dozen call boundaries (14 records here; only the last is the
        # cmdlet's own), so 'Should -Not -BeNullOrEmpty' cannot fail. Note the resolver catch at
        # Remove-OERAccessReviewDefinition.ps1:51 swallows to $null -- the record that is actually
        # written comes from the not-found branch at :53, hence AccessReviewDefinitionNotFound.
        @($ErrVar | Where-Object { $_.FullyQualifiedErrorId -eq 'AccessReviewDefinitionNotFound,Remove-OERAccessReviewDefinition' }).Count |
            Should -Be 1
        Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest -Times 0
    }

    It 'surfaces a Graph DELETE failure as a non-terminating error and emits nothing' {
        # Targets the DELETE catch at Remove-OERAccessReviewDefinition.ps1:65 -- distinct from the
        # resolver-throw test above, which never reaches Invoke-OERGraphRequest at all. Guards two
        # things the cmdlet must do on a Graph failure: call Remove-OERErrorRecord (the mandatory
        # bearer-token-hygiene line -- asserted via Should -Invoke, since a deleted line would
        # otherwise pass unnoticed) and write its OWN non-terminating record. Match the
        # cmdlet-QUALIFIED ErrorId: PowerShell auto-records the mock's throw into -ErrorVariable a
        # dozen times before the catch runs, so matching the bare Graph code would pass even with
        # WriteError deleted.
        Mock -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest {
            throw [System.Management.Automation.ErrorRecord]::new(
                [System.Exception]::new('Authorization_RequestDenied: Insufficient privileges.'),
                'Authorization_RequestDenied',
                [System.Management.Automation.ErrorCategory]::PermissionDenied,
                $null)
        }
        Mock -ModuleName Omnicit.EntraRBAC Remove-OERErrorRecord { }
        $Err = $null
        $Result = Remove-OERAccessReviewDefinition -Id 'd1' -Confirm:$false -ErrorAction SilentlyContinue -ErrorVariable Err
        $Result | Should -BeNullOrEmpty
        Should -Invoke -ModuleName Omnicit.EntraRBAC Remove-OERErrorRecord -Times 1
        @($Err | Where-Object { $_.FullyQualifiedErrorId -eq 'Authorization_RequestDenied,Remove-OERAccessReviewDefinition' }).Count |
            Should -Be 1
    }
}

Describe 'Remove-OERAccessReviewDefinition access package assignments scope warning' {
    # LIVE-MEASURED: deleting an access package's OWN Lifecycle access review left the owning
    # assignment policy un-updatable -- Set-OERAccessPackageAssignmentPolicy carries reviewSettings
    # forward on every PUT and Graph then refuses with "BusinessFlow not found for id <guid>". This is
    # a diagnostic Warning only: the delete must still go through in every case below.
    #
    # ALSO LIVE-MEASURED: the scope query does NOT identify a Lifecycle review. Five ORDINARY ad-hoc
    # reviews created over an access package during the live run read back with the same
    # entitlementManagement/assignments shape, so the detection is a SUPERSET and the warning must stay
    # CONDITIONAL. The wording test below is what stops it drifting back to an unconditional claim.
    BeforeEach {
        InModuleScope Omnicit.EntraRBAC { $script:_OERAuthState = $null }
        Mock -ModuleName Omnicit.EntraRBAC Initialize-OERAuth { }
    }

    It 'warns, and still DELETEs, when the definition scope targets entitlementManagement/assignments' {
        Mock -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest {
            @{
                id    = 'd1'
                scope = @{ query = "/identityGovernance/entitlementManagement/assignments?`$filter=accessPackage/id eq 'ap-1'" }
            }
        } -ParameterFilter { -not $Method -or $Method -eq 'GET' }
        Mock -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest { } -ParameterFilter { $Method -eq 'DELETE' }

        $Warnings = @()
        Remove-OERAccessReviewDefinition -Id 'd1' -Confirm:$false -WarningVariable Warnings -WarningAction SilentlyContinue
        $Joined = ($Warnings | ForEach-Object { [string]$_ }) -join ' '
        $Joined | Should -Match "targets an access package's assignments"
        $Joined | Should -Match 'Lifecycle access review'
        $Joined | Should -Match 'un-updatable'
        $Joined | Should -Match 'reviewSettings'
        # Diagnostics only: the delete is never blocked.
        Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest -Times 1 -Exactly -ParameterFilter {
            $Method -eq 'DELETE' -and $Uri -eq 'v1.0/identityGovernance/accessReviews/definitions/d1'
        }
    }

    It 'warns in the same terms for the LIVE-measured ad-hoc review scope over an access package' {
        # The exact shape five ORDINARY reviews read back with during the live run. It is the same shape
        # a Lifecycle review carries, which is the whole reason the wording has to stay conditional.
        Mock -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest {
            @{
                id    = 'd1'
                scope = @{ query = "/v1.0/identityGovernance/entitlementManagement/assignments?`$filter=(accessPackage/id eq 'ap-1' and assignmentPolicy/id eq 'pol-1')" }
            }
        } -ParameterFilter { -not $Method -or $Method -eq 'GET' }
        Mock -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest { } -ParameterFilter { $Method -eq 'DELETE' }

        $Warnings = @()
        Remove-OERAccessReviewDefinition -Id 'd1' -Confirm:$false -WarningVariable Warnings -WarningAction SilentlyContinue
        $Joined = ($Warnings | ForEach-Object { [string]$_ }) -join ' '
        $Joined | Should -Match 'indistinguishable by scope alone' -Because 'an ad-hoc review over an access package reads back with the SAME scope as a Lifecycle review, so the warning must own that ambiguity'
        Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest -Times 1 -Exactly -ParameterFilter {
            $Method -eq 'DELETE'
        }
    }

    It 'states the Lifecycle consequence CONDITIONALLY, never as a fact about this definition' {
        # The guard that keeps the claim honest. Commit 93246be asserted outright that any
        # entitlementManagement/assignments-scoped definition IS a Lifecycle access review; the live run
        # then produced five ordinary reviews with that exact scope, making the claim false for all of
        # them on a destructive path. A future edit that re-strengthens the wording reddens here.
        Mock -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest {
            @{
                id    = 'd1'
                scope = @{ query = "/identityGovernance/entitlementManagement/assignments?`$filter=accessPackage/id eq 'ap-1'" }
            }
        } -ParameterFilter { -not $Method -or $Method -eq 'GET' }
        Mock -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest { } -ParameterFilter { $Method -eq 'DELETE' }

        $Warnings = @()
        Remove-OERAccessReviewDefinition -Id 'd1' -Confirm:$false -WarningVariable Warnings -WarningAction SilentlyContinue
        $Joined = ($Warnings | ForEach-Object { [string]$_ }) -join ' '

        # 1. What was actually detected -- the scope, not an identity.
        $Joined | Should -Match "targets an access package's assignments"
        $Joined | Should -Match 'indistinguishable by scope alone'
        # 2. The consequence is hypothetical, and names where the Lifecycle review is configured.
        $Joined | Should -Match 'If it is the Lifecycle access review'
        $Joined | Should -Match 'Lifecycle > Require access reviews'
        # 3. How the operator tells the two apart.
        $Joined | Should -Match 'To tell the two apart'
        $Joined | Should -Match 'ad-hoc review created by hand'
        # 4. The remedy survives.
        $Joined | Should -Match 're-create it on that policy'
        $Joined | Should -Match "turn off 'Require access reviews'"
        # 5. And the unconditional assertion is gone -- the exact wording of 93246be and the obvious
        #    re-strengthenings of it.
        $Joined | Should -Not -Match 'is (an|the) access package[^.]{0,60}Lifecycle access review' -Because 'the scope match detects a SUPERSET, so naming this definition a Lifecycle review outright is false for an ordinary review over the same package'
        $Joined | Should -Not -Match 'Deleting it leaves the owning' -Because 'the un-updatable policy follows only IF this is the policy Lifecycle review, so the consequence may not be stated flatly'
    }

    It 'does NOT warn for a group-scoped access review, and still DELETEs' {
        Mock -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest {
            @{ id = 'd1'; displayName = 'Lifecycle review of everything'; scope = @{ query = '/groups/g-1/transitiveMembers' } }
        } -ParameterFilter { -not $Method -or $Method -eq 'GET' }
        Mock -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest { } -ParameterFilter { $Method -eq 'DELETE' }

        $Warnings = @()
        Remove-OERAccessReviewDefinition -Id 'd1' -Confirm:$false -WarningVariable Warnings -WarningAction SilentlyContinue
        $Joined = ($Warnings | ForEach-Object { [string]$_ }) -join ' '
        # The display name deliberately reads like a lifecycle review: a display name is operator text,
        # not a contract, so it must not drive this determination.
        $Joined | Should -Not -Match 'Lifecycle access review'
        $Joined | Should -Not -Match "targets an access package's assignments"
        $Joined | Should -Match 'irreversible'
        Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest -Times 1 -Exactly -ParameterFilter {
            $Method -eq 'DELETE'
        }
    }

    It 'does NOT warn for a directory-role-scoped access review, and still DELETEs' {
        Mock -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest {
            @{
                id    = 'd1'
                scope = @{ query = "/roleManagement/directory/roleAssignmentScheduleInstances?`$filter=(roleDefinitionId eq 'r-1')" }
            }
        } -ParameterFilter { -not $Method -or $Method -eq 'GET' }
        Mock -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest { } -ParameterFilter { $Method -eq 'DELETE' }

        $Warnings = @()
        Remove-OERAccessReviewDefinition -Id 'd1' -Confirm:$false -WarningVariable Warnings -WarningAction SilentlyContinue
        $Joined = ($Warnings | ForEach-Object { [string]$_ }) -join ' '
        $Joined | Should -Not -Match 'Lifecycle access review'
        $Joined | Should -Not -Match "targets an access package's assignments"
        $Joined | Should -Match 'irreversible'
        Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest -Times 1 -Exactly -ParameterFilter {
            $Method -eq 'DELETE'
        }
    }

    It 'invents no warning and blocks nothing when the pre-delete read fails' {
        Mock -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest {
            throw [System.Management.Automation.ErrorRecord]::new(
                [System.Exception]::new('Forbidden: read denied.'), 'Forbidden',
                [System.Management.Automation.ErrorCategory]::PermissionDenied, $null)
        } -ParameterFilter { -not $Method -or $Method -eq 'GET' }
        Mock -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest { } -ParameterFilter { $Method -eq 'DELETE' }

        $Warnings = @()
        $Err = $null
        Remove-OERAccessReviewDefinition -Id 'd1' -Confirm:$false -WarningVariable Warnings `
            -WarningAction SilentlyContinue -ErrorAction SilentlyContinue -ErrorVariable Err
        $Joined = ($Warnings | ForEach-Object { [string]$_ }) -join ' '
        $Joined | Should -Not -Match 'Lifecycle access review'
        $Joined | Should -Not -Match 'indistinguishable by scope alone'
        $Joined | Should -Match 'irreversible' -Because 'the pre-existing irreversibility warning is untouched by a failed diagnostic read'
        # The read failure is swallowed, not surfaced as this cmdlet's own error...
        @($Err | Where-Object { $_.FullyQualifiedErrorId -like '*,Remove-OERAccessReviewDefinition' }).Count | Should -Be 0
        # ...and the delete still happens.
        Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest -Times 1 -Exactly -ParameterFilter {
            $Method -eq 'DELETE'
        }
    }

    It 'emits BOTH warnings under -WhatIf, reading to produce the second, and DELETEs nothing' {
        # DELIBERATE REVERSAL of the It that stood here ('reads nothing at all under -WhatIf').
        #
        # LIVE-MEASURED (check 14.1.2): with the read and both warnings sitting behind ShouldProcess, a
        # -WhatIf run printed the 'What if:' line and NOTHING else. The scope warning -- the one
        # sentence that would have stopped the live run from destroying an access package's own
        # Lifecycle access review -- was unreachable from the exact command an operator runs to find
        # out what a delete would do. A guard that cannot be seen before the act is not a guard, so the
        # read moved ahead of ShouldProcess and the old assertion became wrong on purpose.
        #
        # The read is a GET: -WhatIf still changes nothing in the tenant, which the DELETE assertion at
        # the bottom is what actually pins.
        Mock -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest {
            @{
                id    = 'd1'
                scope = @{ query = "/identityGovernance/entitlementManagement/assignments?`$filter=accessPackage/id eq 'ap-1'" }
            }
        } -ParameterFilter { -not $Method -or $Method -eq 'GET' }
        Mock -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest { } -ParameterFilter { $Method -eq 'DELETE' }

        $Warnings = @()
        Remove-OERAccessReviewDefinition -Id 'd1' -WhatIf -WarningVariable Warnings -WarningAction SilentlyContinue
        $Joined = ($Warnings | ForEach-Object { [string]$_ }) -join ' '
        $Joined | Should -Match 'irreversible' -Because 'the operator planning a delete must be told it cannot be undone BEFORE running it, not after confirming'
        $Joined | Should -Match "targets an access package's assignments" -Because 'the scope warning is the whole reason the diagnostic read was moved ahead of ShouldProcess'
        $Joined | Should -Match 'indistinguishable by scope alone' -Because 'the conditional wording must survive the move, since an ad-hoc review reads back with the same scope'
        Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest -Times 1 -Exactly -ParameterFilter {
            -not $Method -or $Method -eq 'GET'
        }
        Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest -Times 0 -Exactly -ParameterFilter {
            $Method -eq 'DELETE'
        }
    }

    It 'folds the scope fact into the ShouldProcess action text the Confirm prompt renders' {
        # The Warning carries the detail; the prompt line carries the headline, and the prompt is the
        # one line an operator cannot skip past. ShouldProcess text goes straight to the host, so no
        # stream redirection reaches it -- the answering runspace in
        # tests/Unit/TestHelpers/OERConfirmHost.ps1 is the only way to read it. Pester mocks do not
        # cross a runspace boundary, so each scenario installs its own fakes into that runspace's
        # private copy of the module.
        #
        # Both scenarios answer '&No', so neither deletes anything. The group-scoped scenario is the
        # CONTROL: it proves the prompt really was rendered and captured, so the negative assertion
        # under it is not vacuous.
        $ApScopedScenario = {
            Import-Module Omnicit.EntraRBAC -Force -ErrorAction Stop
            $Module = Get-Module Omnicit.EntraRBAC
            & $Module {
                Set-Item -Path function:script:Initialize-OERAuth -Value { }
                Set-Item -Path function:script:Invoke-OERGraphRequest -Value {
                    param($Method, $Uri)
                    if ($Method -eq 'DELETE') { return }
                    @{ id = 'd1'; scope = @{ query = '/identityGovernance/entitlementManagement/assignments?$filter=accessPackage/id eq ''ap-1''' } }
                }
            }
            Remove-OERAccessReviewDefinition -Id 'd1' -Confirm -WarningAction SilentlyContinue | Out-Null
        }
        $GroupScopedScenario = {
            Import-Module Omnicit.EntraRBAC -Force -ErrorAction Stop
            $Module = Get-Module Omnicit.EntraRBAC
            & $Module {
                Set-Item -Path function:script:Initialize-OERAuth -Value { }
                Set-Item -Path function:script:Invoke-OERGraphRequest -Value {
                    param($Method, $Uri)
                    if ($Method -eq 'DELETE') { return }
                    @{ id = 'd1'; scope = @{ query = '/groups/g-1/transitiveMembers' } }
                }
            }
            Remove-OERAccessReviewDefinition -Id 'd1' -Confirm -WarningAction SilentlyContinue | Out-Null
        }

        $ApScoped = Invoke-OERWithConfirmAnswer -Answer '&No' -Script $ApScopedScenario
        $GroupScoped = Invoke-OERWithConfirmAnswer -Answer '&No' -Script $GroupScopedScenario

        ($GroupScoped.Prompts -join ' ') | Should -Match 'Delete access review definition' -Because 'the control has to prove the prompt was rendered and captured, or the negative below proves nothing'
        ($ApScoped.Prompts -join ' ') | Should -Match "targets an access package's assignments" -Because 'the prompt is the one line an operator cannot skip, so the scope fact belongs in the action text and not only in a Warning'
        ($GroupScoped.Prompts -join ' ') | Should -Not -Match "targets an access package's assignments" -Because 'a group-scoped review carries no access package risk, so its prompt must stay the plain action text'
    }
}
