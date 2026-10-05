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
        # CLAUDE.md SECURITY rule #4: audit PR9 Task 7 sweep -- Remove-OERAccessReviewDefinition
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

    It 'publishes a failed definition lookup (a 403) as itself, never as AccessReviewDefinitionNotFound, and deletes nothing' {
        # INVERTED. This It used to pin the OLD behaviour: a resolver that THROWS was folded into
        # AccessReviewDefinitionNotFound, which told the operator the definition did not exist when the
        # lookup had merely been refused (a 403, an exhausted 429, a 5xx). Only a $null answer from the
        # lookup is "not found" (the It below); a throw is published as the record it is, and nothing
        # after it runs -- no scope read, no warning, no DELETE.
        Mock -ModuleName Omnicit.EntraRBAC Resolve-OERAccessReviewDefinitionId {
            throw [System.Management.Automation.ErrorRecord]::new(
                [System.Exception]::new('Authorization_RequestDenied: Insufficient privileges to complete the operation.'),
                'Authorization_RequestDenied', [System.Management.Automation.ErrorCategory]::PermissionDenied, 'denied-def')
        }
        $Err = $null
        $Out = Remove-OERAccessReviewDefinition -DisplayName 'denied-def' -Confirm:$false `
            -ErrorAction SilentlyContinue -ErrorVariable Err
        # NARROWED ON PURPOSE: -ErrorVariable also holds the engine's own capture of the INNER throw,
        # whose id is the bare 'Authorization_RequestDenied' whether or not this cmdlet re-published it,
        # so an unnarrowed match passes with the fix reverted (measured; see the issue #71 Describe in
        # Add-OERAccessPackageResourceRole.Tests.ps1).
        $Published = @(@($Err) | Where-Object {
                $_.InvocationInfo -and $_.InvocationInfo.MyCommand -and
                $_.InvocationInfo.MyCommand.Name -eq 'Remove-OERAccessReviewDefinition'
            })
        # The positive half: the lookup was reached, once, so the no-DELETE assertion below is not a
        # cmdlet that never got that far.
        Should -Invoke -ModuleName Omnicit.EntraRBAC Resolve-OERAccessReviewDefinitionId -Times 1 -Exactly
        $Published.Count | Should -Be 1
        $Published[0].FullyQualifiedErrorId | Should -Match '^Authorization_RequestDenied'
        $Published[0].FullyQualifiedErrorId | Should -Not -Match 'NotFound'
        $Published[0].CategoryInfo.Category | Should -Be 'PermissionDenied'
        $Out | Should -BeNullOrEmpty
        Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest -Times 0 -Exactly
    }

    It 'still reports AccessReviewDefinitionNotFound, once, when the display name matches nothing' {
        # The counterpart of the It above: a $null from the lookup IS "not found", and nothing about
        # the throw path may change its id, its category or its message.
        Mock -ModuleName Omnicit.EntraRBAC Resolve-OERAccessReviewDefinitionId { $null }
        $Err = $null
        $Out = Remove-OERAccessReviewDefinition -DisplayName 'ghost-def' -Confirm:$false `
            -ErrorAction SilentlyContinue -ErrorVariable Err
        $Published = @(@($Err) | Where-Object {
                $_.InvocationInfo -and $_.InvocationInfo.MyCommand -and
                $_.InvocationInfo.MyCommand.Name -eq 'Remove-OERAccessReviewDefinition'
            })
        Should -Invoke -ModuleName Omnicit.EntraRBAC Resolve-OERAccessReviewDefinitionId -Times 1 -Exactly
        $Published.Count | Should -Be 1
        $Published[0].FullyQualifiedErrorId | Should -Be 'AccessReviewDefinitionNotFound,Remove-OERAccessReviewDefinition'
        $Published[0].CategoryInfo.Category | Should -Be 'ObjectNotFound'
        $Published[0].Exception.Message | Should -Be 'Access review definition not found.'
        $Out | Should -BeNullOrEmpty
        Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest -Times 0 -Exactly
    }

    It 'scrubs the failed definition lookup record before publishing it (bearer hygiene)' {
        # The catch hands the record on with WriteError, so an $Error-count proof would stay green with
        # the Remove-OERErrorRecord call deleted. The proof is the mocked call: exactly one, for THIS
        # record, beside a positive assertion that the catch was reached and the record published.
        Mock -ModuleName Omnicit.EntraRBAC Resolve-OERAccessReviewDefinitionId {
            throw [System.Management.Automation.ErrorRecord]::new(
                [System.Exception]::new('Authorization_RequestDenied: definition lookup scrub marker.'),
                'Authorization_RequestDenied', [System.Management.Automation.ErrorCategory]::PermissionDenied, 'denied-def')
        }
        Mock -ModuleName Omnicit.EntraRBAC Remove-OERErrorRecord { }
        $Err = $null
        Remove-OERAccessReviewDefinition -DisplayName 'denied-def' -Confirm:$false `
            -ErrorAction SilentlyContinue -ErrorVariable Err
        $Published = @(@($Err) | Where-Object {
                $_.InvocationInfo -and $_.InvocationInfo.MyCommand -and
                $_.InvocationInfo.MyCommand.Name -eq 'Remove-OERAccessReviewDefinition'
            })
        $Published.Count | Should -Be 1
        $Published[0].Exception.Message | Should -Be 'Authorization_RequestDenied: definition lookup scrub marker.'
        Should -Invoke -ModuleName Omnicit.EntraRBAC Remove-OERErrorRecord -Times 1 -Exactly -ParameterFilter {
            $Record.Exception.Message -eq 'Authorization_RequestDenied: definition lookup scrub marker.'
        }
    }

    It 'surfaces a Graph DELETE failure as a non-terminating error and emits nothing' {
        # Targets the catch around the Graph DELETE call -- distinct from the resolver-throw tests
        # above, which never reach Invoke-OERGraphRequest at all. Guards two
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

    It 'warns that the Lifecycle check could not be made, naming the cause, when the pre-delete read fails, and still DELETEs' {
        # INVERTED (decision A6). This It used to pin SILENCE for a failed pre-delete read, which let an
        # operator read "no Lifecycle warning" as "no Lifecycle risk" when the check was never made. The
        # read failure is now a Warning that names the cause and says the check could not be made. It
        # invents no scope fact, writes no error, and blocks nothing.
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
        # The positive half: the read was reached, once, and failed, so the assertions below are about
        # THAT failure and not about a cmdlet that never read anything.
        Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest -Times 1 -Exactly -ParameterFilter {
            ($Uri -eq 'v1.0/identityGovernance/accessReviews/definitions/d1') -and (-not $Method -or $Method -eq 'GET')
        }
        $Texts = @($Warnings | ForEach-Object { [string]$_ })
        $Texts.Count | Should -Be 2 -Because 'the irreversibility warning and the could-not-check warning, and nothing else'
        $Texts[0] | Should -Match 'irreversible' -Because 'the pre-existing irreversibility warning is untouched by a failed diagnostic read and still comes first'
        $Texts[1] | Should -Match "Could not read access review definition 'd1'"
        $Texts[1] | Should -Match 'Forbidden: read denied\.' -Because 'the warning names the cause, the read error''s own message'
        $Texts[1] | Should -Match "the check for an assignment policy's Lifecycle access review could not be made" -Because 'the live checklist matches this exact phrase'
        # No scope fact is invented from a read that returned nothing.
        ($Texts -join ' ') | Should -Not -Match 'indistinguishable by scope alone'
        ($Texts -join ' ') | Should -Not -Match "targets an access package's assignments"
        # The read failure is a Warning, never this cmdlet's own error...
        @($Err | Where-Object { $_.FullyQualifiedErrorId -like '*,Remove-OERAccessReviewDefinition' }).Count | Should -Be 0
        # ...and the delete still happens.
        Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest -Times 1 -Exactly -ParameterFilter {
            $Method -eq 'DELETE'
        }
    }

    It 'still DELETEs, with no error and no throw, when the pre-delete read fails under -ErrorAction Stop' {
        # The case decision A6 protects. Under a global Stop a WriteError from the failed-read catch
        # would terminate the cmdlet BEFORE ShouldProcess, so the delete the operator asked for would
        # silently not happen. A Warning has no such effect. Nothing may throw, and the DELETE must go
        # out exactly once.
        Mock -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest {
            throw [System.Management.Automation.ErrorRecord]::new(
                [System.Exception]::new('Forbidden: read denied.'), 'Forbidden',
                [System.Management.Automation.ErrorCategory]::PermissionDenied, $null)
        } -ParameterFilter { -not $Method -or $Method -eq 'GET' }
        Mock -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest { } -ParameterFilter { $Method -eq 'DELETE' }

        $Warnings = @()
        $Thrown = $null
        try {
            Remove-OERAccessReviewDefinition -Id 'd1' -Confirm:$false -ErrorAction Stop `
                -WarningVariable Warnings -WarningAction SilentlyContinue
        }
        catch { $Thrown = $PSItem }

        $Thrown | Should -BeNullOrEmpty -Because 'a failed diagnostic read must not stop the delete under a global Stop'
        # The positive half: the warning proves the failed-read catch was reached.
        @($Warnings | Where-Object { ([string]$_) -match "the check for an assignment policy's Lifecycle access review could not be made" }).Count |
            Should -Be 1
        Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest -Times 1 -Exactly -ParameterFilter {
            $Method -eq 'DELETE' -and $Uri -eq 'v1.0/identityGovernance/accessReviews/definitions/d1'
        }
    }

    It 'emits the could-not-check warning under -WhatIf as well, and DELETEs nothing' {
        # The warning sits AHEAD of ShouldProcess like the other two (see the live measurement in the
        # cmdlet), so the operator planning a delete with -WhatIf learns the check was not made.
        Mock -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest {
            throw [System.Management.Automation.ErrorRecord]::new(
                [System.Exception]::new('Forbidden: read denied.'), 'Forbidden',
                [System.Management.Automation.ErrorCategory]::PermissionDenied, $null)
        } -ParameterFilter { -not $Method -or $Method -eq 'GET' }
        Mock -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest { } -ParameterFilter { $Method -eq 'DELETE' }

        $Warnings = @()
        Remove-OERAccessReviewDefinition -Id 'd1' -WhatIf -WarningVariable Warnings -WarningAction SilentlyContinue
        Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest -Times 1 -Exactly -ParameterFilter {
            -not $Method -or $Method -eq 'GET'
        }
        @($Warnings | Where-Object { ([string]$_) -match "the check for an assignment policy's Lifecycle access review could not be made" }).Count |
            Should -Be 1
        Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest -Times 0 -Exactly -ParameterFilter {
            $Method -eq 'DELETE'
        }
    }

    It 'does not warn that a check could not be made when the pre-delete read succeeds' {
        # The counterpart that stops the new warning being unconditional: a read that returned is a
        # check that WAS made, whatever scope it found.
        Mock -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest {
            @{ id = 'd1'; scope = @{ query = '/groups/g-1/transitiveMembers' } }
        } -ParameterFilter { -not $Method -or $Method -eq 'GET' }
        Mock -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest { } -ParameterFilter { $Method -eq 'DELETE' }

        $Warnings = @()
        Remove-OERAccessReviewDefinition -Id 'd1' -Confirm:$false -WarningVariable Warnings -WarningAction SilentlyContinue
        Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest -Times 1 -Exactly -ParameterFilter {
            -not $Method -or $Method -eq 'GET'
        }
        $Texts = @($Warnings | ForEach-Object { [string]$_ })
        $Texts.Count | Should -Be 1
        $Texts[0] | Should -Match 'irreversible'
        ($Texts -join ' ') | Should -Not -Match 'could not be made'
    }

    It 'scrubs the failed pre-delete definition read record before warning (bearer hygiene)' {
        # The catch no longer swallows to $null: it keeps the message and warns, so an $Error-count proof
        # would stay green with the scrub deleted. The proof is the mocked call -- exactly one, for THIS
        # record -- beside a positive assertion that the catch was reached (the warning carries the
        # marker).
        Mock -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest {
            throw [System.Management.Automation.ErrorRecord]::new(
                [System.Exception]::new('Forbidden: pre-delete read scrub marker.'), 'Forbidden',
                [System.Management.Automation.ErrorCategory]::PermissionDenied, $null)
        } -ParameterFilter { -not $Method -or $Method -eq 'GET' }
        Mock -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest { } -ParameterFilter { $Method -eq 'DELETE' }
        Mock -ModuleName Omnicit.EntraRBAC Remove-OERErrorRecord { }

        $Warnings = @()
        Remove-OERAccessReviewDefinition -Id 'd1' -Confirm:$false -WarningVariable Warnings -WarningAction SilentlyContinue
        @($Warnings | Where-Object { ([string]$_) -match 'Forbidden: pre-delete read scrub marker\.' }).Count | Should -Be 1
        Should -Invoke -ModuleName Omnicit.EntraRBAC Remove-OERErrorRecord -Times 1 -Exactly -ParameterFilter {
            $Record.Exception.Message -eq 'Forbidden: pre-delete read scrub marker.'
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

Describe 'Remove-OERAccessReviewDefinition refuses an ambiguous display name' {
    # Graph does not enforce unique access review definition display names, so -DisplayName used to
    # DELETE whichever of several same-named definitions the lookup listed first. These Its leave the
    # resolver REAL and mock only the Graph boundary, so they prove the refusal end to end: the lookup
    # finds two definitions, the resolver refuses the name, and nothing is deleted. A mocked resolver
    # could not show that -- it would stay green with the resolver's count check deleted.
    BeforeEach {
        InModuleScope Omnicit.EntraRBAC { $script:_OERAuthState = $null }
        Mock -ModuleName Omnicit.EntraRBAC Initialize-OERAuth { }
    }

    It 'publishes AmbiguousName with both candidate ids and issues no DELETE when two definitions share the display name' {
        Mock -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest {
            if ($Method -eq 'DELETE') { return $null }
            if ($Uri -like '*accessReviews/definitions?*displayName eq*') {
                return @{ value = @(
                        @{ id = '11111111-1111-1111-1111-111111111111'; displayName = 'Dup' },
                        @{ id = '22222222-2222-2222-2222-222222222222'; displayName = 'Dup' }) }
            }
            return @{ id = '11111111-1111-1111-1111-111111111111'; scope = @{ query = '/groups/g-1/transitiveMembers' } }
        }
        $Err = $null
        $Out = Remove-OERAccessReviewDefinition -DisplayName 'Dup' -Confirm:$false -WarningAction SilentlyContinue `
            -ErrorAction SilentlyContinue -ErrorVariable Err
        # NARROWED ON PURPOSE: -ErrorVariable also holds the engine's own capture of the INNER throw,
        # whose id is the bare 'AmbiguousName' whether or not this cmdlet re-published it, so an
        # unnarrowed match passes with the fix reverted (measured; see the issue #71 Describe in
        # Add-OERAccessPackageResourceRole.Tests.ps1).
        $Published = @(@($Err) | Where-Object {
                $_.InvocationInfo -and $_.InvocationInfo.MyCommand -and
                $_.InvocationInfo.MyCommand.Name -eq 'Remove-OERAccessReviewDefinition'
            })
        # The positive half: the real resolver ran its lookup, once, so the zero-DELETE assertion
        # below is not a cmdlet that never got that far.
        Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest -Times 1 -Exactly -ParameterFilter {
            $Uri -like "*accessReviews/definitions?*displayName eq 'Dup'*"
        }
        # The point of the refusal, asserted FIRST so that a resolver which picks a definition anyway
        # fails on the DELETE it then issues: not one of the two same-named definitions is deleted...
        Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest -Times 0 -Exactly -ParameterFilter {
            $Method -eq 'DELETE'
        }
        # ...and the lookup is the ONLY Graph call -- not even the pre-delete scope read happened.
        Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest -Times 1 -Exactly
        $Published.Count | Should -Be 1
        $Published[0].FullyQualifiedErrorId | Should -Be 'AmbiguousName,Remove-OERAccessReviewDefinition'
        $Published[0].CategoryInfo.Category | Should -Be 'InvalidArgument'
        $Published[0].Exception.Message | Should -Match '11111111-1111-1111-1111-111111111111'
        $Published[0].Exception.Message | Should -Match '22222222-2222-2222-2222-222222222222'
        $Published[0].Exception.Message | Should -Match 'Re-run with the definition id instead of the display name'
        $Out | Should -BeNullOrEmpty
    }

    It 'still DELETEs the one definition a display name matches (the real resolver, one match)' {
        # The positive counterpart of the It above: the refusal is for AMBIGUITY, not for names. One
        # match is resolved and deleted as before, so the zero-DELETE proof above cannot be a cmdlet
        # that refuses every display name.
        Mock -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest {
            if ($Method -eq 'DELETE') { return $null }
            if ($Uri -like '*accessReviews/definitions?*displayName eq*') {
                return @{ value = @(@{ id = '33333333-3333-3333-3333-333333333333'; displayName = 'Solo' }) }
            }
            return @{ id = '33333333-3333-3333-3333-333333333333'; scope = @{ query = '/groups/g-1/transitiveMembers' } }
        }
        $Err = $null
        Remove-OERAccessReviewDefinition -DisplayName 'Solo' -Confirm:$false -WarningAction SilentlyContinue `
            -ErrorAction SilentlyContinue -ErrorVariable Err
        @($Err).Count | Should -Be 0
        Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest -Times 1 -Exactly -ParameterFilter {
            $Method -eq 'DELETE' -and
            $Uri -eq 'v1.0/identityGovernance/accessReviews/definitions/33333333-3333-3333-3333-333333333333'
        }
    }
}
