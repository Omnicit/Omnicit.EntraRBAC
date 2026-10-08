BeforeAll {
    $script:moduleName = 'Omnicit.EntraRBAC'
    Get-Module $script:moduleName | Remove-Module -Force -ErrorAction SilentlyContinue
    Import-Module $script:moduleName -Force -ErrorAction Stop
    . "$PSScriptRoot/../TestHelpers/OERTransportTripwire.ps1"
    Install-OERTransportTripwire
    . "$PSScriptRoot/../TestHelpers/OERConfirmHost.ps1"
}

AfterAll {
    try { Assert-OERTransportTripwire } finally { Uninstall-OERTransportTripwire }
}

Describe 'Add-OERGroupEligibility' {
    BeforeEach {
        InModuleScope $script:moduleName { $script:_OERAuthState = $null }
        $script:PrincipalGuid = '11111111-1111-1111-1111-111111111111'
        Mock -ModuleName $script:moduleName Initialize-OERAuth {}
        Mock -ModuleName $script:moduleName Resolve-OERGroupId { 'gid-1' }
        Mock -ModuleName $script:moduleName Resolve-OERPrincipal { [PSCustomObject]@{ PrincipalId = 'resolved-user-id'; PrincipalType = 'User' } }
        Mock -ModuleName $script:moduleName Get-OERGroupPermanentEligibilityState { [PSCustomObject]@{ HasPolicy = $true; PolicyId = 'pol-1'; PermanentAllowed = $true } }
        Mock -ModuleName $script:moduleName Enable-OERGroupPermanentEligibility { $true }
    }

    It 'posts an adminAssign eligibility request, converting -Duration days to an ISO 8601 duration' {
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest { @{ id = 'req-1'; status = 'Provisioned'; action = 'adminAssign' } }
        $Result = Add-OERGroupEligibility -Group 'gid-1' -PrincipalId $script:PrincipalGuid -Duration 365
        $Result.PSObject.TypeNames[0] | Should -Be 'Omnicit.EntraRBAC.GroupEligibility'
        Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 1 -ParameterFilter {
            $Method -eq 'POST' -and
            $Uri -eq 'beta/identityGovernance/privilegedAccess/group/eligibilityScheduleRequests' -and
            $Body.action -eq 'adminAssign' -and $Body.principalId -eq '11111111-1111-1111-1111-111111111111' -and
            $Body.scheduleInfo.expiration.type -eq 'afterDuration' -and
            $Body.scheduleInfo.expiration.duration -eq 'P365D'
        }
    }

    It 'requests permanent (noExpiration) eligibility when -Duration is omitted' {
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest { @{ id = 'req-2'; status = 'Provisioned'; action = 'adminAssign' } }
        Add-OERGroupEligibility -Group 'gid-1' -PrincipalId $script:PrincipalGuid | Out-Null
        Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 1 -ParameterFilter {
            $Method -eq 'POST' -and $Body.scheduleInfo.expiration.type -eq 'noExpiration'
        }
    }

    It 'binds the third positional argument to -User (positional back-compat)' {
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest { @{ id = 'req-pos'; status = 'Provisioned'; action = 'adminAssign' } }
        Add-OERGroupEligibility 'gid-1' '' 'anna.berg@contoso.com' -Duration 365 -Confirm:$false | Out-Null
        Should -Invoke -ModuleName $script:moduleName Resolve-OERPrincipal -Times 1 -ParameterFilter { $User -eq 'anna.berg@contoso.com' }
        Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 1 -ParameterFilter {
            $Method -eq 'POST' -and $Body.principalId -eq 'resolved-user-id'
        }
    }

    It 'does not POST under -WhatIf' {
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {}
        Add-OERGroupEligibility -Group 'gid-1' -PrincipalId $script:PrincipalGuid -WhatIf | Out-Null
        Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 0
    }

    It 'surfaces a Graph POST failure as a non-terminating error and emits no request object' {
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {
            throw [System.Management.Automation.ErrorRecord]::new(
                [System.Exception]::new('Request_BadRequest: The eligibility duration is not permitted by policy.'),
                'Request_BadRequest',
                [System.Management.Automation.ErrorCategory]::InvalidOperation,
                $null)
        }
        Mock -ModuleName $script:moduleName Remove-OERErrorRecord { }
        $Err = $null
        $Result = Add-OERGroupEligibility -Group 'gid-1' -PrincipalId $script:PrincipalGuid `
            -Confirm:$false -ErrorAction SilentlyContinue -ErrorVariable Err
        $Result | Should -BeNullOrEmpty
        Should -Invoke -ModuleName $script:moduleName Remove-OERErrorRecord -Times 1
        @($Err | Where-Object { $_.FullyQualifiedErrorId -eq 'Request_BadRequest,Add-OERGroupEligibility' }).Count |
            Should -Be 1
    }

    Context 'admin action selection' {
        It 'defaults to action adminAssign in the request body when -Action is not supplied' {
            Mock -ModuleName $script:moduleName Invoke-OERGraphRequest { @{ id = 'req-a1'; status = 'Provisioned'; action = 'adminAssign' } }
            $Result = Add-OERGroupEligibility -Group 'gid-1' -PrincipalId $script:PrincipalGuid -Duration 365
            $Result.Action | Should -Be 'adminAssign'
            Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 1 -ParameterFilter {
                $Method -eq 'POST' -and $Body.action -eq 'adminAssign'
            }
        }

        It 'sends action adminUpdate in the request body when -Action adminUpdate is supplied' {
            Mock -ModuleName $script:moduleName Invoke-OERGraphRequest { @{ id = 'req-a2'; status = 'Provisioned'; action = 'adminUpdate' } }
            $Result = Add-OERGroupEligibility -Group 'gid-1' -PrincipalId $script:PrincipalGuid -Duration 365 -Action adminUpdate
            $Result.Action | Should -Be 'adminUpdate'
            Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 1 -ParameterFilter {
                $Method -eq 'POST' -and $Body.action -eq 'adminUpdate'
            }
        }
    }

    Context 'principal resolution' {
        It 'resolves -User via Resolve-OERPrincipal and sends the resolved id' {
            Mock -ModuleName $script:moduleName Invoke-OERGraphRequest { @{ id = 'req-u'; status = 'Provisioned'; action = 'adminAssign' } }
            Add-OERGroupEligibility -Group 'gid-1' -User 'anna.berg@contoso.com' -Duration 365 | Out-Null
            Should -Invoke -ModuleName $script:moduleName Resolve-OERPrincipal -Times 1 -ParameterFilter { $User -eq 'anna.berg@contoso.com' }
            Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 1 -ParameterFilter { $Body.principalId -eq 'resolved-user-id' }
        }
        It 'accepts a GUID for -User (forwarded to Resolve-OERPrincipal)' {
            Mock -ModuleName $script:moduleName Invoke-OERGraphRequest { @{ id = 'req-u2'; status = 'Provisioned'; action = 'adminAssign' } }
            Add-OERGroupEligibility -Group 'gid-1' -User $script:PrincipalGuid -Duration 365 | Out-Null
            Should -Invoke -ModuleName $script:moduleName Resolve-OERPrincipal -Times 1 -ParameterFilter { $User -eq '11111111-1111-1111-1111-111111111111' }
        }
        It 'uses a raw GUID -PrincipalId verbatim without calling Resolve-OERPrincipal' {
            Mock -ModuleName $script:moduleName Invoke-OERGraphRequest { @{ id = 'req-p'; status = 'Provisioned'; action = 'adminAssign' } }
            Add-OERGroupEligibility -Group 'gid-1' -PrincipalId $script:PrincipalGuid -Duration 365 | Out-Null
            Should -Invoke -ModuleName $script:moduleName Resolve-OERPrincipal -Times 0
            Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 1 -ParameterFilter { $Body.principalId -eq '11111111-1111-1111-1111-111111111111' }
        }
        It 'errors InvalidPrincipalId for a non-GUID -PrincipalId and does NOT POST' {
            Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {}
            Add-OERGroupEligibility -Group 'gid-1' -PrincipalId 'anna@contoso.com' -Duration 365 -ErrorVariable e -ErrorAction SilentlyContinue | Out-Null
            $e[0].FullyQualifiedErrorId | Should -Match 'InvalidPrincipalId'
            Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 0
        }
        It 'errors NoPrincipal when neither -User nor -PrincipalId is supplied' {
            Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {}
            Add-OERGroupEligibility -Group 'gid-1' -Duration 365 -ErrorVariable e -ErrorAction SilentlyContinue | Out-Null
            $e[0].FullyQualifiedErrorId | Should -Match 'NoPrincipal'
            Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 0
        }
        It 'uses -PrincipalId and ignores -User when both are supplied (PrincipalId takes precedence per Resolve-OERPrincipalOrId), warning that -User was dropped' {
            Mock -ModuleName $script:moduleName Invoke-OERGraphRequest { @{ id = 'req-amb'; status = 'Provisioned'; action = 'adminAssign' } }
            $Warnings = $null
            Add-OERGroupEligibility -Group 'gid-1' -User 'anna@contoso.com' -PrincipalId $script:PrincipalGuid -Duration 365 -Confirm:$false `
                -WarningVariable Warnings -WarningAction SilentlyContinue | Out-Null
            Should -Invoke -ModuleName $script:moduleName Resolve-OERPrincipal -Times 0
            Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 1 -ParameterFilter { $Body.principalId -eq $script:PrincipalGuid }
            ($Warnings | ForEach-Object { $_.Message }) -join ' ' | Should -BeLike '*-User*'
        }
        It 'errors PrincipalNotFound when Resolve-OERPrincipal throws' {
            Mock -ModuleName $script:moduleName Resolve-OERPrincipal { throw 'User not found' }
            Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {}
            Add-OERGroupEligibility -Group 'gid-1' -User 'ghost@contoso.com' -Duration 365 -ErrorVariable e -ErrorAction SilentlyContinue | Out-Null
            (($e | ForEach-Object { $_.FullyQualifiedErrorId }) -join ' ') | Should -Match 'PrincipalNotFound'
            Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 0
        }
    }

    Context 'group resolution and back-compat' {
        It 'resolves a -Group display name via Resolve-OERGroupId' {
            Mock -ModuleName $script:moduleName Invoke-OERGraphRequest { @{ id = 'req-g'; status = 'Provisioned'; action = 'adminAssign' } }
            Add-OERGroupEligibility -Group 'role_sec_admins' -PrincipalId $script:PrincipalGuid -Duration 365 | Out-Null
            Should -Invoke -ModuleName $script:moduleName Resolve-OERGroupId -Times 1 -ParameterFilter { $DisplayName -eq 'role_sec_admins' }
        }
        It 'still binds the legacy -DisplayName alias' {
            Mock -ModuleName $script:moduleName Invoke-OERGraphRequest { @{ id = 'req-d'; status = 'Provisioned'; action = 'adminAssign' } }
            Add-OERGroupEligibility -DisplayName 'role_sec_admins' -PrincipalId $script:PrincipalGuid -Duration 365 | Out-Null
            Should -Invoke -ModuleName $script:moduleName Resolve-OERGroupId -Times 1 -ParameterFilter { $DisplayName -eq 'role_sec_admins' }
        }
        It 'binds the group id from the pipeline via the Id alias (Get-OERGroup | Add-OERGroupEligibility)' {
            Mock -ModuleName $script:moduleName Invoke-OERGraphRequest { @{ id = 'req-pipe'; status = 'Provisioned'; action = 'adminAssign' } }
            [pscustomobject]@{ Id = 'gid-1' } | Add-OERGroupEligibility -PrincipalId $script:PrincipalGuid -Duration 365 | Out-Null
            Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 1 -ParameterFilter { $Method -eq 'POST' }
        }
        It 'errors GroupNotFound and does NOT POST when the group cannot be resolved' {
            Mock -ModuleName $script:moduleName Resolve-OERGroupId { $null }
            Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {}
            Add-OERGroupEligibility -Group 'nope' -PrincipalId $script:PrincipalGuid -Duration 365 -ErrorVariable e -ErrorAction SilentlyContinue | Out-Null
            $e[0].FullyQualifiedErrorId | Should -Match 'GroupNotFound'
            Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 0
        }

        It 'gives an actionable GroupNotFound message' {
            Mock -ModuleName $script:moduleName Resolve-OERGroupId { $null }
            Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {}
            Add-OERGroupEligibility -Group 'ghost' -PrincipalId $script:PrincipalGuid -Duration 365 `
                -Confirm:$false -ErrorAction SilentlyContinue -ErrorVariable Err
            $Joined = @($Err).FullyQualifiedErrorId -join ';'
            $Joined | Should -Match 'GroupNotFound'
            $Text = @($Err).Exception.Message -join ' '
            $Text | Should -Match 'display name'
            $Text | Should -Match 'object id'
        }

        It 'reports a failed group resolver as itself, exactly once, and never as GroupNotFound' {
            Mock -ModuleName $script:moduleName Initialize-OERAuth { }
            Mock -ModuleName $script:moduleName Resolve-OERGroupId { throw 'transport failure' }
            Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {}
            $Error.Clear()
            Add-OERGroupEligibility -Group 'grp' -PrincipalId $script:PrincipalGuid -Duration 365 -ErrorAction SilentlyContinue | Out-Null
            # Supersedes 'leaves no record in $Error when the group resolver fails', which pinned the old
            # swallow-then-GroupNotFound path. The failure is now reported as itself and once: exactly one
            # record remains, the failure and not a GroupNotFound. This is the CONTRACT, not the scrub
            # proof: the catch re-publishes the caught record, so the same single record is there whether
            # or not Remove-OERErrorRecord ran. The scrub has its own test below.
            @($Error).Count | Should -Be 1
            $Error[0].Exception.Message | Should -Match 'transport failure'
            $Error[0].FullyQualifiedErrorId | Should -Not -Match 'GroupNotFound'
        }

        It 'scrubs the failed group resolver record before re-publishing it (bearer hygiene)' {
            # The catch re-publishes the caught record with $PSCmdlet.WriteError($PSItem), the same shape as a
            # bare re-throw: the same exception instance reaches $Error with or without the scrub, so an
            # $Error-based proof passes with the Remove-OERErrorRecord line deleted. The prescribed proof
            # (rationale.md, #bearer-scrub-tests) guards the call directly: mock it and require exactly
            # one call, filtered to THIS record so no other catch on the path can satisfy it.
            Mock -ModuleName $script:moduleName Initialize-OERAuth { }
            Mock -ModuleName $script:moduleName Resolve-OERGroupId { throw 'transport failure' }
            Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {}
            Mock -ModuleName $script:moduleName Remove-OERErrorRecord { }
            Add-OERGroupEligibility -Group 'grp' -PrincipalId $script:PrincipalGuid -Duration 365 -ErrorAction SilentlyContinue | Out-Null
            Should -Invoke -ModuleName $script:moduleName Remove-OERErrorRecord -Times 1 -Exactly -ParameterFilter {
                $Record.Exception.Message -eq 'transport failure'
            }
        }
    }

    Context 'permanent self-heal' {
        It 'opens the group policy then POSTs when permanent eligibility is forbidden' {
            Mock -ModuleName $script:moduleName Get-OERGroupPermanentEligibilityState { [PSCustomObject]@{ HasPolicy = $true; PolicyId = 'pol-1'; PermanentAllowed = $false } }
            Mock -ModuleName $script:moduleName Enable-OERGroupPermanentEligibility { $true }
            Mock -ModuleName $script:moduleName Invoke-OERGraphRequest { @{ id = 'req-x'; status = 'Provisioned'; action = 'adminAssign' } }
            Add-OERGroupEligibility -Group 'gid-1' -PrincipalId $script:PrincipalGuid -Confirm:$false | Out-Null
            Should -Invoke -ModuleName $script:moduleName Enable-OERGroupPermanentEligibility -Times 1 -ParameterFilter { $PolicyId -eq 'pol-1' }
            Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 1 -ParameterFilter { $Method -eq 'POST' }
        }
        It 'does NOT open when permanent eligibility is already allowed' {
            Mock -ModuleName $script:moduleName Get-OERGroupPermanentEligibilityState { [PSCustomObject]@{ HasPolicy = $true; PolicyId = 'pol-1'; PermanentAllowed = $true } }
            Mock -ModuleName $script:moduleName Enable-OERGroupPermanentEligibility { $true }
            Mock -ModuleName $script:moduleName Invoke-OERGraphRequest { @{ id = 'req-x'; status = 'Provisioned'; action = 'adminAssign' } }
            Add-OERGroupEligibility -Group 'gid-1' -PrincipalId $script:PrincipalGuid -Confirm:$false | Out-Null
            Should -Invoke -ModuleName $script:moduleName Enable-OERGroupPermanentEligibility -Times 0
            Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 1 -ParameterFilter { $Method -eq 'POST' }
        }
        It 'does NOT pre-check for a time-bound grant' {
            Mock -ModuleName $script:moduleName Get-OERGroupPermanentEligibilityState { }
            Mock -ModuleName $script:moduleName Invoke-OERGraphRequest { @{ id = 'req-x'; status = 'Provisioned'; action = 'adminAssign' } }
            Add-OERGroupEligibility -Group 'gid-1' -PrincipalId $script:PrincipalGuid -Duration 365 -Confirm:$false | Out-Null
            Should -Invoke -ModuleName $script:moduleName Get-OERGroupPermanentEligibilityState -Times 0
            Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 1 -ParameterFilter { $Method -eq 'POST' }
        }
        It 'errors GroupNotOnboarded and does NOT POST when the group has no policy' {
            Mock -ModuleName $script:moduleName Get-OERGroupPermanentEligibilityState { [PSCustomObject]@{ HasPolicy = $false; PolicyId = $null; PermanentAllowed = $false } }
            Mock -ModuleName $script:moduleName Invoke-OERGraphRequest { }
            Add-OERGroupEligibility -Group 'gid-1' -PrincipalId $script:PrincipalGuid -Confirm:$false -ErrorVariable e -ErrorAction SilentlyContinue | Out-Null
            $e[0].FullyQualifiedErrorId | Should -Match 'GroupNotOnboarded'
            Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 0
        }
        It 'errors PolicyOpenFailed and does NOT POST when opening fails' {
            Mock -ModuleName $script:moduleName Get-OERGroupPermanentEligibilityState { [PSCustomObject]@{ HasPolicy = $true; PolicyId = 'pol-1'; PermanentAllowed = $false } }
            Mock -ModuleName $script:moduleName Enable-OERGroupPermanentEligibility { throw 'Forbidden' }
            Mock -ModuleName $script:moduleName Invoke-OERGraphRequest { }
            Add-OERGroupEligibility -Group 'gid-1' -PrincipalId $script:PrincipalGuid -Confirm:$false -ErrorVariable e -ErrorAction SilentlyContinue | Out-Null
            (($e | ForEach-Object { $_.FullyQualifiedErrorId }) -join ' ') | Should -Match 'PolicyOpenFailed'
            Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 0
        }
        It 'words PolicyOpenFailed for <AccessType> access with the cause and a command that runs as typed, without -ActivationMaxHours' -ForEach @(
            @{ AccessType = 'member' }
            @{ AccessType = 'owner' }
        ) {
            Mock -ModuleName $script:moduleName Get-OERGroupPermanentEligibilityState { [PSCustomObject]@{ HasPolicy = $true; PolicyId = 'pol-1'; PermanentAllowed = $false } }
            Mock -ModuleName $script:moduleName Enable-OERGroupPermanentEligibility { throw 'Forbidden' }
            Mock -ModuleName $script:moduleName Invoke-OERGraphRequest { }
            $Err = $null
            Add-OERGroupEligibility -Group 'gid-1' -PrincipalId $script:PrincipalGuid -AccessType $AccessType -Confirm:$false -ErrorVariable Err -ErrorAction SilentlyContinue | Out-Null
            # Reached: the open was tried, and failed, before anything was sent.
            Should -Invoke -ModuleName $script:moduleName Enable-OERGroupPermanentEligibility -Times 1 -Exactly -ParameterFilter { $PolicyId -eq 'pol-1' }
            Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 0
            $Own = @($Err | Where-Object { $_ -is [System.Management.Automation.ErrorRecord] -and $_.FullyQualifiedErrorId -eq 'PolicyOpenFailed,Add-OERGroupEligibility' })
            $Own.Count | Should -Be 1
            $Own[0].CategoryInfo.Category | Should -Be ([System.Management.Automation.ErrorCategory]::PermissionDenied)
            $Own[0].TargetObject | Should -BeExactly 'pol-1'
            # The whole message, built from the expected text and not from the helper.
            $Own[0].Exception.Message | Should -BeExactly ('Could not open the PIM-for-groups policy to allow permanent eligibility: Forbidden ' +
                "Run 'Set-OERGroupPimPolicy -Group ''gid-1'' -AccessType $AccessType -AllowPermanentEligibility' " +
                'with sufficient permissions, or grant a time-bound eligibility with -DurationDays.')
            $Own[0].Exception.Message | Should -Not -Match 'ActivationMaxHours'
        }
        It 'degrades and still POSTs when the pre-check read fails' {
            Mock -ModuleName $script:moduleName Get-OERGroupPermanentEligibilityState { throw 'read failed' }
            Mock -ModuleName $script:moduleName Enable-OERGroupPermanentEligibility { $true }
            Mock -ModuleName $script:moduleName Invoke-OERGraphRequest { @{ id = 'req-x'; status = 'Provisioned'; action = 'adminAssign' } }
            Add-OERGroupEligibility -Group 'gid-1' -PrincipalId $script:PrincipalGuid -Confirm:$false | Out-Null
            Should -Invoke -ModuleName $script:moduleName Enable-OERGroupPermanentEligibility -Times 0
            Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 1 -ParameterFilter { $Method -eq 'POST' }
        }
    }

    Context 'permanent self-heal is gated on the grant decision' {
        BeforeEach {
            Mock -ModuleName $script:moduleName Get-OERGroupPermanentEligibilityState {
                [PSCustomObject]@{ HasPolicy = $true; PolicyId = 'pol-1'; PermanentAllowed = $false }
            }
            Mock -ModuleName $script:moduleName Enable-OERGroupPermanentEligibility { $true }
            Mock -ModuleName $script:moduleName Invoke-OERGraphRequest { @{ id = 'req-x'; status = 'Provisioned'; action = 'adminAssign' } }
        }
        BeforeAll {
            # -ErrorVariable also collects records the mock layers raise as the refused POST unwinds;
            # the cmdlet's OWN records are the ones that carry its name, in the order written.
            function Get-TestOwnRecord ($Records) {
                @($Records | Where-Object { [string]$_.FullyQualifiedErrorId -like '*,Add-OERGroupEligibility' })
            }
            # Under -ErrorAction Stop the record that stopped the cmdlet reaches -ErrorVariable only
            # inside the ActionPreferenceStopException (measured), so read each id from a record, or
            # from the record an exception carries.
            function Get-TestRecordId ($Records) {
                foreach ($Record in $Records) {
                    if ($Record -is [System.Management.Automation.ErrorRecord]) { [string]$Record.FullyQualifiedErrorId }
                    elseif ($Record -is [System.Management.Automation.IContainsErrorRecord]) { [string]$Record.ErrorRecord.FullyQualifiedErrorId }
                }
            }
            # The refused grant's message, and the full PolicyOpenedButGrantFailed text: the advice, with
            # that message inside it.
            $script:GrantRefusedMessage = 'Request_BadRequest: Graph rejected the eligibility request.'
            $script:OpenedButFailedText = "The PIM member eligibility grant failed after PIM-for-groups policy 'pol-1' had been opened " +
                'to allow permanent eligibility. The policy is still open; close it with ' +
                "'Set-OERGroupPimPolicy -Group ''gid-1'' -AccessType member -AllowPermanentEligibility:`$false' " +
                'if you do not intend to retry. The request failed with: ' + $script:GrantRefusedMessage
        }

        It 'makes NO policy change when the operator genuinely declines the confirmation prompt' {
            # The decline is the state this guard exists for, and it is the one state an in-process
            # Pester construct cannot produce: -Confirm:$false confirms, and -WhatIf sets
            # $WhatIfPreference. So run the cmdlet twice in an answering runspace (see
            # tests/Unit/TestHelpers/OERConfirmHost.ps1) -- once answering Yes, which proves the
            # harness really reaches the code, and once answering No.
            $Scenario = {
                Import-Module Omnicit.EntraRBAC -Force -ErrorAction Stop
                $Module = Get-Module Omnicit.EntraRBAC
                & $Module {
                    $script:OERTestCalls = [System.Collections.Generic.List[string]]::new()
                    Set-Item -Path function:script:Initialize-OERAuth -Value { }
                    Set-Item -Path function:script:Resolve-OERGroupId -Value { 'gid-1' }
                    Set-Item -Path function:script:Resolve-OERPrincipalOrId -Value { [PSCustomObject]@{ PrincipalId = '11111111-1111-1111-1111-111111111111' } }
                    Set-Item -Path function:script:Get-OERGroupPermanentEligibilityState -Value { [PSCustomObject]@{ HasPolicy = $true; PolicyId = 'pol-1'; PermanentAllowed = $false } }
                    Set-Item -Path function:script:Enable-OERGroupPermanentEligibility -Value { $script:OERTestCalls.Add('open'); $true }
                    Set-Item -Path function:script:Invoke-OERGraphRequest -Value { $script:OERTestCalls.Add('grant') }
                    Set-Item -Path function:script:ConvertTo-OERGroupEligibilityRequest -Value { }
                }
                Add-OERGroupEligibility -Group 'gid-1' -PrincipalId '11111111-1111-1111-1111-111111111111' -Confirm | Out-Null
                & $Module { "CALLS:$($script:OERTestCalls -join ',')" }
            }
            $Accepted = Invoke-OERWithConfirmAnswer -Answer '&Yes' -Script $Scenario
            $Declined = Invoke-OERWithConfirmAnswer -Answer '&No' -Script $Scenario

            $Accepted.Output[-1] | Should -Be 'CALLS:open,grant'
            $Declined.Output[-1] | Should -Be 'CALLS:'
            ($Declined.Warnings -join ' ') | Should -BeLike '*affects ALL member eligibility for this group*'
        }

        It 'reaches no policy write except through the grant decision' {
            # Backstop for the behavioural test above, and the only guard that survives if the
            # answering-runspace harness is ever removed: every call that WRITES the policy must sit
            # under an if whose condition reads $Proceed, and must come after the gate is evaluated.
            $FunctionAst = (Get-Command Add-OERGroupEligibility).ScriptBlock.Ast
            $GateOffset = $FunctionAst.FindAll({
                    param($Node)
                    $Node -is [System.Management.Automation.Language.InvokeMemberExpressionAst] -and $Node.Member.Value -eq 'ShouldProcess'
                }, $true) | ForEach-Object { $_.Extent.StartOffset } | Sort-Object | Select-Object -First 1
            $WriteCalls = @($FunctionAst.FindAll({
                        param($Node)
                        $Node -is [System.Management.Automation.Language.CommandAst] -and
                        $Node.GetCommandName() -eq 'Enable-OERGroupPermanentEligibility'
                    }, $true))

            $GateOffset | Should -Not -BeNullOrEmpty
            $WriteCalls.Count | Should -BeGreaterThan 0
            foreach ($Call in $WriteCalls) {
                $Call.Extent.StartOffset | Should -BeGreaterThan $GateOffset
                $Gated = $false
                $Node = $Call.Parent
                while ($null -ne $Node) {
                    if ($Node -is [System.Management.Automation.Language.IfStatementAst]) {
                        foreach ($Clause in $Node.Clauses) {
                            $Referenced = @($Clause.Item1.FindAll({
                                        param($Inner)
                                        $Inner -is [System.Management.Automation.Language.VariableExpressionAst] -and
                                        $Inner.VariablePath.UserPath -eq 'Proceed'
                                    }, $true))
                            if ($Referenced.Count -gt 0) { $Gated = $true }
                        }
                    }
                    $Node = $Node.Parent
                }
                $Gated | Should -BeTrue -Because 'every policy write must be enclosed by an if whose condition reads the gate decision'
            }
        }

        It 'warns about the blast radius BEFORE the operator is asked, and opens before granting' {
            $Order = [System.Collections.Generic.List[string]]::new()
            Mock -ModuleName $script:moduleName Enable-OERGroupPermanentEligibility { $Order.Add('open'); $true }
            Mock -ModuleName $script:moduleName Invoke-OERGraphRequest { $Order.Add('grant'); @{ id = 'req-x'; status = 'Provisioned'; action = 'adminAssign' } }
            $Warnings = Add-OERGroupEligibility -Group 'gid-1' -PrincipalId $script:PrincipalGuid -Confirm:$false 3>&1 |
                Where-Object { $_ -is [System.Management.Automation.WarningRecord] }
            ($Warnings.Message -join ' ') | Should -BeLike '*affects ALL member eligibility for this group*'
            # The warning precedes the decision, so it must describe what the grant REQUIRES, never
            # claim the policy has already been opened.
            ($Warnings.Message -join ' ') | Should -BeLike '*requires opening the PIM-for-groups policy*'
            $Order -join ',' | Should -Be 'open,grant'
        }

        It 'STILL shows the policy open in the -WhatIf plan (PR #19 behaviour must not regress)' {
            $Warnings = Add-OERGroupEligibility -Group 'gid-1' -PrincipalId $script:PrincipalGuid -WhatIf 3>&1 |
                Where-Object { $_ -is [System.Management.Automation.WarningRecord] }
            Should -Invoke -ModuleName $script:moduleName Enable-OERGroupPermanentEligibility -Times 1
            ($Warnings.Message -join ' ') | Should -BeLike '*affects ALL member eligibility for this group*'
        }

        It 'reports PolicyOpenedButGrantFailed FIRST, naming the policy left open and the cause, then the grant''s own error, when the grant fails (BL-98)' {
            Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {
                throw [System.Management.Automation.ErrorRecord]::new(
                    [System.Exception]::new('Request_BadRequest: Graph rejected the eligibility request.'),
                    'Request_BadRequest',
                    [System.Management.Automation.ErrorCategory]::InvalidOperation,
                    $null)
            }
            $Err = $null
            $Out = @(Add-OERGroupEligibility -Group 'gid-1' -PrincipalId $script:PrincipalGuid -Confirm:$false `
                    -WarningAction SilentlyContinue -ErrorAction SilentlyContinue -ErrorVariable Err)
            $Out.Count | Should -Be 0
            Should -Invoke -ModuleName $script:moduleName Enable-OERGroupPermanentEligibility -Times 1 -Exactly -ParameterFilter { $PolicyId -eq 'pol-1' }
            # The cmdlet's own records, in the order written: PolicyOpenedButGrantFailed first, with the
            # advice and the grant's message inside it, then the grant's own record, re-published unchanged.
            $Own = Get-TestOwnRecord $Err
            $Own.Count | Should -Be 2
            $Own[0].FullyQualifiedErrorId | Should -BeExactly 'PolicyOpenedButGrantFailed,Add-OERGroupEligibility'
            $Own[0].CategoryInfo.Category | Should -Be ([System.Management.Automation.ErrorCategory]::InvalidOperation)
            $Own[0].TargetObject | Should -BeExactly 'pol-1'
            $Own[0].Exception.Message | Should -BeExactly $script:OpenedButFailedText
            $Own[1].FullyQualifiedErrorId | Should -BeExactly 'Request_BadRequest,Add-OERGroupEligibility'
            $Own[1].Exception.Message | Should -BeExactly $script:GrantRefusedMessage
        }

        It 'stops a caller under -ErrorAction Stop with PolicyOpenedButGrantFailed, carrying the advice and the cause, and never writes the grant''s own error (BL-98)' {
            Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {
                throw [System.Management.Automation.ErrorRecord]::new(
                    [System.Exception]::new('Request_BadRequest: Graph rejected the eligibility request.'),
                    'Request_BadRequest',
                    [System.Management.Automation.ErrorCategory]::InvalidOperation,
                    $null)
            }
            $Err = $null
            $Thrown = $null
            try {
                Add-OERGroupEligibility -Group 'gid-1' -PrincipalId $script:PrincipalGuid -Confirm:$false `
                    -WarningAction SilentlyContinue -ErrorAction Stop -ErrorVariable Err | Out-Null
            } catch {
                $Thrown = $PSItem
            }
            Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 1 -Exactly -ParameterFilter { $Method -eq 'POST' }
            $Thrown.FullyQualifiedErrorId | Should -BeExactly 'PolicyOpenedButGrantFailed,Add-OERGroupEligibility'
            $Thrown.Exception.Message | Should -BeExactly $script:OpenedButFailedText
            # The cmdlet's own ids are the advice alone: the grant's own record, which the old order
            # wrote first, is never reached under Stop.
            @(Get-TestRecordId $Err | Where-Object { $_ -like '*,Add-OERGroupEligibility' }) |
                Should -Be @('PolicyOpenedButGrantFailed,Add-OERGroupEligibility')
        }

        It 'scrubs the refused POST record before re-publishing it, on the opened-policy path (bearer hygiene)' {
            # The catch re-publishes the caught record, so the proof is a mocked scrub asked for that
            # very record: an $Error-based proof passes with the Remove-OERErrorRecord line deleted.
            Mock -ModuleName $script:moduleName Remove-OERErrorRecord { }
            Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {
                throw [System.Management.Automation.ErrorRecord]::new(
                    [System.Exception]::new('Request_BadRequest: Graph rejected the eligibility request.'),
                    'Request_BadRequest',
                    [System.Management.Automation.ErrorCategory]::InvalidOperation,
                    $null)
            }
            $Err = $null
            Add-OERGroupEligibility -Group 'gid-1' -PrincipalId $script:PrincipalGuid -Confirm:$false `
                -WarningAction SilentlyContinue -ErrorAction SilentlyContinue -ErrorVariable Err | Out-Null
            # Reached: the policy was opened and the refused POST took the opened-policy path.
            Should -Invoke -ModuleName $script:moduleName Enable-OERGroupPermanentEligibility -Times 1 -Exactly
            @($Err | Where-Object { [string]$_.FullyQualifiedErrorId -eq 'PolicyOpenedButGrantFailed,Add-OERGroupEligibility' }).Count | Should -Be 1
            Should -Invoke -ModuleName $script:moduleName Remove-OERErrorRecord -Times 1 -Exactly -ParameterFilter {
                $Record.Exception.Message -eq 'Request_BadRequest: Graph rejected the eligibility request.'
            }
        }

        It 'does NOT report PolicyOpenedButGrantFailed when the grant fails without an open' {
            Mock -ModuleName $script:moduleName Get-OERGroupPermanentEligibilityState {
                [PSCustomObject]@{ HasPolicy = $true; PolicyId = 'pol-1'; PermanentAllowed = $true }
            }
            Mock -ModuleName $script:moduleName Remove-OERErrorRecord { }
            Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {
                throw [System.Management.Automation.ErrorRecord]::new(
                    [System.Exception]::new('Request_BadRequest: Graph rejected the eligibility request.'),
                    'Request_BadRequest',
                    [System.Management.Automation.ErrorCategory]::InvalidOperation,
                    $null)
            }
            $Err = $null
            Add-OERGroupEligibility -Group 'gid-1' -PrincipalId $script:PrincipalGuid `
                -Confirm:$false -ErrorAction SilentlyContinue -ErrorVariable Err | Out-Null
            Should -Invoke -ModuleName $script:moduleName Enable-OERGroupPermanentEligibility -Times 0
            @($Err | Where-Object { $_.FullyQualifiedErrorId -eq 'PolicyOpenedButGrantFailed,Add-OERGroupEligibility' }).Count |
                Should -Be 0
            # Exactly one record of the cmdlet's own: the grant's, re-published unchanged.
            $Own = Get-TestOwnRecord $Err
            $Own.Count | Should -Be 1
            $Own[0].FullyQualifiedErrorId | Should -BeExactly 'Request_BadRequest,Add-OERGroupEligibility'
            $Own[0].Exception.Message | Should -BeExactly $script:GrantRefusedMessage
        }

        It 'does NOT report PolicyOpenedButGrantFailed when the nested policy open was DECLINED' {
            # Under an explicit -Confirm the propagated $ConfirmPreference makes the self-gating
            # helper prompt on its own, and answering No returns $false having written nothing. A
            # later grant failure must not then name a policy this run never opened.
            Mock -ModuleName $script:moduleName Enable-OERGroupPermanentEligibility { $false }
            Mock -ModuleName $script:moduleName Remove-OERErrorRecord { }
            Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {
                throw [System.Management.Automation.ErrorRecord]::new(
                    [System.Exception]::new('Request_BadRequest: Graph rejected the eligibility request.'),
                    'Request_BadRequest',
                    [System.Management.Automation.ErrorCategory]::InvalidOperation,
                    $null)
            }
            $Err = $null
            Add-OERGroupEligibility -Group 'gid-1' -PrincipalId $script:PrincipalGuid `
                -Confirm:$false -ErrorAction SilentlyContinue -ErrorVariable Err | Out-Null
            Should -Invoke -ModuleName $script:moduleName Enable-OERGroupPermanentEligibility -Times 1 -Exactly
            @($Err | Where-Object { $_.FullyQualifiedErrorId -eq 'PolicyOpenedButGrantFailed,Add-OERGroupEligibility' }).Count |
                Should -Be 0
            # Exactly one record of the cmdlet's own: the grant's, re-published unchanged.
            $Own = Get-TestOwnRecord $Err
            $Own.Count | Should -Be 1
            $Own[0].FullyQualifiedErrorId | Should -BeExactly 'Request_BadRequest,Add-OERGroupEligibility'
            $Own[0].Exception.Message | Should -BeExactly $script:GrantRefusedMessage
        }
    }

    Context 'friendly principal input' {
        BeforeEach {
            InModuleScope Omnicit.EntraRBAC { $script:_OERAuthState = $null }
            Mock -ModuleName Omnicit.EntraRBAC Initialize-OERAuth { }
            Mock -ModuleName Omnicit.EntraRBAC Resolve-OERGroupId { 'gggg0000-0000-0000-0000-00000000000a' }
            Mock -ModuleName Omnicit.EntraRBAC Get-OERGroupPermanentEligibilityState {
                [PSCustomObject]@{ HasPolicy = $true; PermanentAllowed = $true; PolicyId = 'pol1' }
            }
            Mock -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest {
                @{ id = 'req1'; status = 'Provisioned' }
            }
        }

        It 'resolves -GroupPrincipal to an object id and puts it in the request body' {
            Mock -ModuleName Omnicit.EntraRBAC Resolve-OERPrincipal {
                [PSCustomObject]@{ PrincipalId = 'cccc0000-0000-0000-0000-000000000003'; PrincipalType = 'Group' }
            }
            $Result = Add-OERGroupEligibility -Group 'role_sec_team' -GroupPrincipal 'Sales Team' `
                -Duration 365 -Confirm:$false
            $Result.PrincipalId | Should -Be 'cccc0000-0000-0000-0000-000000000003'
            Should -Invoke Resolve-OERPrincipal -ModuleName Omnicit.EntraRBAC -Times 1 -ParameterFilter {
                $Group -eq 'Sales Team'
            }
        }

        It 'resolves -ServicePrincipal to an object id' {
            Mock -ModuleName Omnicit.EntraRBAC Resolve-OERPrincipal {
                [PSCustomObject]@{ PrincipalId = 'dddd0000-0000-0000-0000-000000000004'; PrincipalType = 'ServicePrincipal' }
            }
            $Result = Add-OERGroupEligibility -Group 'role_sec_team' -ServicePrincipal 'Contoso App' `
                -Duration 365 -Confirm:$false
            $Result.PrincipalId | Should -Be 'dddd0000-0000-0000-0000-000000000004'
        }

        It 'still accepts a raw GUID -PrincipalId without any principal lookup' {
            Mock -ModuleName Omnicit.EntraRBAC Resolve-OERPrincipal { throw 'should not be called' }
            $Result = Add-OERGroupEligibility -Group 'role_sec_team' `
                -PrincipalId 'aaaa0000-0000-0000-0000-000000000001' -Duration 365 -Confirm:$false
            $Result.PrincipalId | Should -Be 'aaaa0000-0000-0000-0000-000000000001'
            Should -Invoke Resolve-OERPrincipal -ModuleName Omnicit.EntraRBAC -Times 0
        }

        It 'rejects a UPN passed to -PrincipalId and names the friendly parameters' {
            $Err = $null
            Add-OERGroupEligibility -Group 'role_sec_team' -PrincipalId 'anna@contoso.com' `
                -Duration 365 -Confirm:$false -ErrorAction SilentlyContinue -ErrorVariable Err
            $Err[0].FullyQualifiedErrorId | Should -BeLike 'InvalidPrincipalId*'
            $Err[0].Exception.Message | Should -BeLike '*-GroupPrincipal*'
            Should -Invoke Invoke-OERGraphRequest -ModuleName Omnicit.EntraRBAC -Times 0 -ParameterFilter {
                $Method -eq 'POST'
            }
        }

        It 'reports AmbiguousPrincipal when -User and -GroupPrincipal are both supplied' {
            $Err = $null
            Add-OERGroupEligibility -Group 'role_sec_team' -User 'anna@contoso.com' `
                -GroupPrincipal 'Sales Team' -Duration 365 -Confirm:$false `
                -ErrorAction SilentlyContinue -ErrorVariable Err
            $Err[0].FullyQualifiedErrorId | Should -BeLike 'AmbiguousPrincipal*'
        }
    }

    Context 'duration vocabulary (audit PR6)' {
        It 'still accepts the historical bare day count on -Duration' {
            Mock -ModuleName $script:moduleName Invoke-OERGraphRequest { @{ id = 'req-dv1'; status = 'Provisioned'; action = 'adminAssign' } }
            Add-OERGroupEligibility -Group 'gid-1' -PrincipalId $script:PrincipalGuid -Duration 365 -Confirm:$false | Out-Null
            Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 1 -ParameterFilter {
                $Body.scheduleInfo.expiration.duration -eq 'P365D'
            }
        }

        It 'accepts a raw ISO 8601 duration on -Duration' {
            Mock -ModuleName $script:moduleName Invoke-OERGraphRequest { @{ id = 'req-dv2'; status = 'Provisioned'; action = 'adminAssign' } }
            Add-OERGroupEligibility -Group 'gid-1' -PrincipalId $script:PrincipalGuid -Duration 'PT8H' -Confirm:$false | Out-Null
            Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 1 -ParameterFilter {
                $Body.scheduleInfo.expiration.duration -eq 'PT8H'
            }
        }

        It 'accepts the module-standard -DurationDays' {
            Mock -ModuleName $script:moduleName Invoke-OERGraphRequest { @{ id = 'req-dv3'; status = 'Provisioned'; action = 'adminAssign' } }
            Add-OERGroupEligibility -Group 'gid-1' -PrincipalId $script:PrincipalGuid -DurationDays 90 -Confirm:$false | Out-Null
            Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 1 -ParameterFilter {
                $Body.scheduleInfo.expiration.duration -eq 'P90D'
            }
        }

        It 'does NOT treat -DurationDays as a permanent grant (no policy open)' {
            Mock -ModuleName $script:moduleName Invoke-OERGraphRequest { @{ id = 'req-dv4'; status = 'Provisioned'; action = 'adminAssign' } }
            Add-OERGroupEligibility -Group 'gid-1' -PrincipalId $script:PrincipalGuid -DurationDays 90 -Confirm:$false | Out-Null
            Should -Invoke -ModuleName $script:moduleName Get-OERGroupPermanentEligibilityState -Times 0
            Should -Invoke -ModuleName $script:moduleName Enable-OERGroupPermanentEligibility -Times 0
        }

        It 'still treats no duration at all as a permanent grant' {
            Mock -ModuleName $script:moduleName Invoke-OERGraphRequest { @{ id = 'req-dv5'; status = 'Provisioned'; action = 'adminAssign' } }
            Add-OERGroupEligibility -Group 'gid-1' -PrincipalId $script:PrincipalGuid -Confirm:$false | Out-Null
            Should -Invoke -ModuleName $script:moduleName Get-OERGroupPermanentEligibilityState -Times 1
        }

        It 'rejects -Duration and -DurationDays together with AmbiguousDuration' {
            Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {}
            Add-OERGroupEligibility -Group 'gid-1' -PrincipalId $script:PrincipalGuid -Duration 'P365D' -DurationDays 90 `
                -Confirm:$false -ErrorAction SilentlyContinue -ErrorVariable Err | Out-Null
            $Err | Should -Not -BeNullOrEmpty
            $Err | Where-Object { $_.FullyQualifiedErrorId -like 'AmbiguousDuration*' } | Should -Not -BeNullOrEmpty
            Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 0
        }

        It 'emits InvalidDuration for a value that is neither a count nor ISO' {
            Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {}
            Add-OERGroupEligibility -Group 'gid-1' -PrincipalId $script:PrincipalGuid -Duration 'banana' `
                -Confirm:$false -ErrorAction SilentlyContinue -ErrorVariable Err | Out-Null
            $Err | Should -Not -BeNullOrEmpty
            $Err | Where-Object { $_.FullyQualifiedErrorId -like 'InvalidDuration*' } | Should -Not -BeNullOrEmpty
            Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 0
        }
    }

    Context 'a request Graph accepts but answers status Failed (Sprint 8 step 3, BL-04)' {
        # Microsoft Graph can accept an eligibility schedule request (201) and answer it with status
        # Failed, which grants nothing. The cmdlet still emits the request object, then writes
        # EligibilityRequestFailed, so a caller never takes the Failed request for a grant.
        BeforeAll {
            $script:FailedMessage = "Microsoft Graph accepted the PIM member eligibility request 'req-f1' for principal " +
                "'11111111-1111-1111-1111-111111111111' on group 'gid-1' but answered status Failed, so nothing was granted; " +
                're-running the same request usually succeeds (a group created moments ago can take a while to be known to ' +
                'PIM for Groups).'
        }

        It 'emits the request object AND writes EligibilityRequestFailed when Graph answers status Failed' {
            Mock -ModuleName $script:moduleName Invoke-OERGraphRequest { @{ id = 'req-f1'; status = 'Failed' } }
            $Err = $null
            $Result = @(Add-OERGroupEligibility -Group 'gid-1' -PrincipalId $script:PrincipalGuid -DurationDays 30 `
                    -Confirm:$false -ErrorAction SilentlyContinue -ErrorVariable Err)
            $Result.Count | Should -Be 1
            $Result[0].PSObject.TypeNames[0] | Should -Be 'Omnicit.EntraRBAC.GroupEligibility'
            $Result[0].RequestId | Should -BeExactly 'req-f1'
            $Result[0].Status | Should -BeExactly 'Failed'
            @($Err).Count | Should -Be 1
            $Err[0].FullyQualifiedErrorId | Should -BeExactly 'EligibilityRequestFailed,Add-OERGroupEligibility'
            $Err[0].CategoryInfo.Category | Should -Be ([System.Management.Automation.ErrorCategory]::InvalidResult)
            $Err[0].TargetObject | Should -BeExactly 'gid-1'
            $Err[0].Exception.Message | Should -BeExactly $script:FailedMessage
            Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 1 -Exactly -ParameterFilter { $Method -eq 'POST' }
        }

        It 'reads the status case-insensitively: a lower-case failed is the same error, naming the access type' {
            Mock -ModuleName $script:moduleName Invoke-OERGraphRequest { @{ id = 'req-f2'; status = 'failed' } }
            $Err = $null
            $Result = @(Add-OERGroupEligibility -Group 'gid-1' -PrincipalId $script:PrincipalGuid -AccessType owner -DurationDays 30 `
                    -Confirm:$false -ErrorAction SilentlyContinue -ErrorVariable Err)
            $Result.Count | Should -Be 1
            $Result[0].Status | Should -BeExactly 'failed'
            @($Err).Count | Should -Be 1
            $Err[0].FullyQualifiedErrorId | Should -BeExactly 'EligibilityRequestFailed,Add-OERGroupEligibility'
            $Err[0].Exception.Message | Should -BeLike "Microsoft Graph accepted the PIM owner eligibility request 'req-f2' for principal *"
        }

        It 'asks the owner of the Failed family: <Status> is the same error, and the message shows the status as answered (BL-33)' -ForEach @(
            @{ Status = 'FAILED' }
            @{ Status = 'FailedAsResourceIsLocked' }
        ) {
            $script:AnsweredStatus = $Status
            Mock -ModuleName $script:moduleName Invoke-OERGraphRequest { @{ id = 'req-f3'; status = $script:AnsweredStatus } }
            $Err = $null
            $Result = @(Add-OERGroupEligibility -Group 'gid-1' -PrincipalId $script:PrincipalGuid -DurationDays 30 `
                    -Confirm:$false -ErrorAction SilentlyContinue -ErrorVariable Err)
            $Result.Count | Should -Be 1
            $Result[0].Status | Should -BeExactly $Status
            @($Err).Count | Should -Be 1
            $Err[0].FullyQualifiedErrorId | Should -BeExactly 'EligibilityRequestFailed,Add-OERGroupEligibility'
            $Err[0].Exception.Message | Should -BeExactly ($script:FailedMessage.Replace("'req-f1'", "'req-f3'").Replace('answered status Failed,', "answered status $Status,"))
        }

        It 'writes no error for status <Status>, which is not Failed' -ForEach @(
            @{ Status = 'Provisioned' }
            @{ Status = 'PendingApproval' }
            @{ Status = 'PendingProvisioning' }
        ) {
            $script:AnsweredStatus = $Status
            Mock -ModuleName $script:moduleName Invoke-OERGraphRequest { @{ id = 'req-ok'; status = $script:AnsweredStatus } }
            $Err = $null
            $Result = @(Add-OERGroupEligibility -Group 'gid-1' -PrincipalId $script:PrincipalGuid -DurationDays 30 `
                    -Confirm:$false -ErrorAction SilentlyContinue -ErrorVariable Err)
            # The request was sent and answered with this status, so the absence below is a decision.
            Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 1 -Exactly -ParameterFilter { $Method -eq 'POST' }
            $Result.Count | Should -Be 1
            $Result[0].Status | Should -BeExactly $Status
            @($Err).Count | Should -Be 0
        }

        It 'still hands the object to -OutVariable under -ErrorAction Stop, and the throw carries EligibilityRequestFailed' {
            Mock -ModuleName $script:moduleName Invoke-OERGraphRequest { @{ id = 'req-f1'; status = 'Failed' } }
            $Out = $null
            $Thrown = $null
            try {
                Add-OERGroupEligibility -Group 'gid-1' -PrincipalId $script:PrincipalGuid -DurationDays 30 `
                    -Confirm:$false -ErrorAction Stop -OutVariable Out | Out-Null
            } catch {
                $Thrown = $PSItem
            }
            $Thrown | Should -Not -BeNullOrEmpty
            $Thrown.FullyQualifiedErrorId | Should -BeExactly 'EligibilityRequestFailed,Add-OERGroupEligibility'
            $Thrown.Exception.Message | Should -BeExactly $script:FailedMessage
            @($Out).Count | Should -Be 1
            $Out[0].RequestId | Should -BeExactly 'req-f1'
            $Out[0].Status | Should -BeExactly 'Failed'
        }

        It 'names the policy this invocation opened, and how to close it, when the permanent request is answered Failed' {
            Mock -ModuleName $script:moduleName Get-OERGroupPermanentEligibilityState {
                [PSCustomObject]@{ HasPolicy = $true; PolicyId = 'pol-1'; PermanentAllowed = $false }
            }
            Mock -ModuleName $script:moduleName Enable-OERGroupPermanentEligibility { $true }
            Mock -ModuleName $script:moduleName Invoke-OERGraphRequest { @{ id = 'req-f1'; status = 'Failed' } }
            $Err = $null
            $Result = @(Add-OERGroupEligibility -Group 'gid-1' -PrincipalId $script:PrincipalGuid `
                    -Confirm:$false -ErrorAction SilentlyContinue -ErrorVariable Err -WarningAction SilentlyContinue)
            Should -Invoke -ModuleName $script:moduleName Enable-OERGroupPermanentEligibility -Times 1 -Exactly -ParameterFilter { $PolicyId -eq 'pol-1' }
            $Result.Count | Should -Be 1
            # One record, EligibilityRequestFailed: the request was not refused, so this is not
            # PolicyOpenedButGrantFailed, but it carries the same advice about the open policy.
            @($Err).Count | Should -Be 1
            $Err[0].FullyQualifiedErrorId | Should -BeExactly 'EligibilityRequestFailed,Add-OERGroupEligibility'
            $Err[0].Exception.Message | Should -BeExactly ($script:FailedMessage + " PIM-for-groups policy 'pol-1' had been opened " +
                'to allow permanent eligibility before the request was sent. The policy is still open; close it with ' +
                "'Set-OERGroupPimPolicy -Group ''gid-1'' -AccessType member -AllowPermanentEligibility:`$false' " +
                'if you do not intend to retry.')
        }

        It 'does not name a policy when this invocation did not open one' {
            # PermanentAllowed already (the Describe default), so nothing is opened.
            Mock -ModuleName $script:moduleName Invoke-OERGraphRequest { @{ id = 'req-f1'; status = 'Failed' } }
            $Err = $null
            Add-OERGroupEligibility -Group 'gid-1' -PrincipalId $script:PrincipalGuid `
                -Confirm:$false -ErrorAction SilentlyContinue -ErrorVariable Err | Out-Null
            Should -Invoke -ModuleName $script:moduleName Get-OERGroupPermanentEligibilityState -Times 1 -Exactly
            Should -Invoke -ModuleName $script:moduleName Enable-OERGroupPermanentEligibility -Times 0
            @($Err).Count | Should -Be 1
            $Err[0].Exception.Message | Should -BeExactly $script:FailedMessage
        }

        It 'writes no error while the apply engine owns a Failed status as replication (module-scope flag)' {
            # Sync-OERStructureGroup sets this flag around its call for a group created in the same run
            # only, where a Failed answer is waited on and asked again from the shared budget.
            Mock -ModuleName $script:moduleName Invoke-OERGraphRequest { @{ id = 'req-f1'; status = 'Failed' } }
            $Err = $null
            InModuleScope $script:moduleName { $script:_OERGroupEligibilityFailedIsReplication = $true }
            try {
                $Result = @(Add-OERGroupEligibility -Group 'gid-1' -PrincipalId $script:PrincipalGuid -DurationDays 30 `
                        -Confirm:$false -ErrorAction SilentlyContinue -ErrorVariable Err)
            } finally {
                InModuleScope $script:moduleName { $script:_OERGroupEligibilityFailedIsReplication = $false }
            }
            Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 1 -Exactly -ParameterFilter { $Method -eq 'POST' }
            $Result.Count | Should -Be 1
            $Result[0].Status | Should -BeExactly 'Failed'
            @($Err).Count | Should -Be 0
        }
    }

    It 'still emits the full GroupEligibility request shape after the converter extraction' {
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest { @{ id = 'req-shape'; status = 'Provisioned'; action = 'adminAssign' } }
        $Result = Add-OERGroupEligibility -Group 'gid-1' -PrincipalId $script:PrincipalGuid -Duration 365 -Confirm:$false
        $Result.PSObject.TypeNames[0] | Should -Be 'Omnicit.EntraRBAC.GroupEligibility'
        @($Result.PSObject.Properties.Name) -join ',' |
            Should -Be 'RequestId,GroupId,PrincipalId,AccessType,Action,Status'
    }
}

Describe 'Add-OERGroupEligibility verbose output' {
    BeforeEach {
        InModuleScope $script:moduleName { $script:_OERAuthState = $null }
        Mock -ModuleName $script:moduleName Initialize-OERAuth {}
        Mock -ModuleName $script:moduleName Resolve-OERGroupId { 'gid-1' }
        Mock -ModuleName $script:moduleName Resolve-OERPrincipal { [PSCustomObject]@{ PrincipalId = 'resolved-user-id'; PrincipalType = 'User' } }
        Mock -ModuleName $script:moduleName Get-OERGroupPermanentEligibilityState { [PSCustomObject]@{ HasPolicy = $true; PolicyId = 'pol-1'; PermanentAllowed = $true } }
        Mock -ModuleName $script:moduleName Enable-OERGroupPermanentEligibility { $true }
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest { @{ id = 'req-1'; status = 'Provisioned'; action = 'adminAssign' } }
    }

    It 'reports the resolved group and principal under -Verbose' {
        $Verbose = Add-OERGroupEligibility -Group 'gid-1' -PrincipalId '11111111-1111-1111-1111-111111111111' `
            -Duration 365 -Confirm:$false -Verbose 4>&1 |
            Where-Object { $_ -is [System.Management.Automation.VerboseRecord] }
        $Text = $Verbose.Message -join "`n"
        $Text | Should -Match "\[Add-OERGroupEligibility\] Resolved group to 'gid-1'."
        $Text | Should -Match "\[Add-OERGroupEligibility\] Resolved principal to '11111111-1111-1111-1111-111111111111'."
    }

    It 'emits no verbose output without -Verbose' {
        $Verbose = Add-OERGroupEligibility -Group 'gid-1' -PrincipalId '11111111-1111-1111-1111-111111111111' `
            -Duration 365 -Confirm:$false 4>&1 | Where-Object { $_ -is [System.Management.Automation.VerboseRecord] }
        $Verbose | Should -BeNullOrEmpty
    }

    It 'reports the resolved PIM policy id under -Verbose when the permanent auto-open branch runs' {
        Mock -ModuleName $script:moduleName Get-OERGroupPermanentEligibilityState { [PSCustomObject]@{ HasPolicy = $true; PolicyId = 'pol-1'; PermanentAllowed = $false } }
        $Verbose = Add-OERGroupEligibility -Group 'gid-1' -PrincipalId '11111111-1111-1111-1111-111111111111' `
            -Confirm:$false -Verbose 4>&1 |
            Where-Object { $_ -is [System.Management.Automation.VerboseRecord] }
        $Text = $Verbose.Message -join "`n"
        $Text | Should -Match "\[Add-OERGroupEligibility\] Resolved PIM policy id: 'pol-1'."
        Should -Invoke -ModuleName $script:moduleName Enable-OERGroupPermanentEligibility -Times 1 -ParameterFilter { $PolicyId -eq 'pol-1' }
    }
}

Describe 'Add-OERGroupEligibility -- a failed policy-id read is not GroupNotOnboarded' {
    # The REAL Get-OERGroupPermanentEligibilityState runs here (the Describes above mock it whole), so
    # this is the end-to-end proof of the pair: a refused policy-id read used to come back from that
    # helper as HasPolicy = $false, which this cmdlet reported as GroupNotOnboarded ("Graph does not
    # list a policy for this group yet, re-run after a short while") -- a replication-delay diagnosis
    # for a group that was merely unreadable. The helper now rethrows, and this cmdlet's existing
    # pre-check catch ("Proceeding; Microsoft Graph will enforce the policy") handles it.
    BeforeEach {
        InModuleScope $script:moduleName { $script:_OERAuthState = $null }
        Mock -ModuleName $script:moduleName Initialize-OERAuth {}
        Mock -ModuleName $script:moduleName Resolve-OERGroupId { 'gid-1' }
        Mock -ModuleName $script:moduleName Get-OERPimGroupPolicyId {
            throw [System.Management.Automation.ErrorRecord]::new(
                [System.Exception]::new('Authorization_RequestDenied: Insufficient privileges to complete the operation.'),
                'Authorization_RequestDenied',
                [System.Management.Automation.ErrorCategory]::PermissionDenied,
                'gid-1')
        }
        Mock -ModuleName $script:moduleName Enable-OERGroupPermanentEligibility { $true }
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest { @{ id = 'req-x'; status = 'Provisioned'; action = 'adminAssign' } }
    }

    It 'does not report GroupNotOnboarded for a 403 on the policy-id read, and leaves the decision to Graph' {
        $Err = $null
        $Out = Add-OERGroupEligibility -Group 'gid-1' -PrincipalId '11111111-1111-1111-1111-111111111111' `
            -Confirm:$false -ErrorAction SilentlyContinue -ErrorVariable Err -Verbose 4>&1
        $Verbose = @($Out | Where-Object { $_ -is [System.Management.Automation.VerboseRecord] })
        $Result = @($Out | Where-Object { $_ -isnot [System.Management.Automation.VerboseRecord] })
        # The positive half: the pre-check ran the real helper, which reached the refused read, and the
        # cmdlet's catch took it -- named in its verbose line with the real error text -- so the
        # negative assertion below is not a pre-check that never ran.
        Should -Invoke -ModuleName $script:moduleName Get-OERPimGroupPolicyId -Times 1 -Exactly -ParameterFilter {
            $GroupId -eq 'gid-1' -and $AccessType -eq 'member'
        }
        ($Verbose.Message -join "`n") | Should -Match 'Could not pre-check the PIM-for-groups policy: Authorization_RequestDenied: Insufficient privileges'
        # No GroupNotOnboarded, and no error of the cmdlet's own at all.
        @($Err | Where-Object { $_.FullyQualifiedErrorId -like '*GroupNotOnboarded*' }).Count | Should -Be 0
        @($Err | Where-Object {
                $_.InvocationInfo -and $_.InvocationInfo.MyCommand -and
                $_.InvocationInfo.MyCommand.Name -eq 'Add-OERGroupEligibility'
            }).Count | Should -Be 0
        # The documented degrade: nothing was learned about the policy, so Graph enforces it on the POST.
        Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 1 -Exactly -ParameterFilter { $Method -eq 'POST' }
        Should -Invoke -ModuleName $script:moduleName Enable-OERGroupPermanentEligibility -Times 0 -Exactly
        $Result.Count | Should -Be 1
    }
}

Describe 'Add-OERGroupEligibility: the advice for an opened policy in a script with no try (BL-98)' {
    # Where no try stands anywhere up the call stack, as at a prompt, a grant refused after this
    # invocation opened the group's policy must still say that the policy is open and how to close it.
    # Under -ErrorAction Stop the first error written ends the whole script, so that first error is
    # PolicyOpenedButGrantFailed, carrying the advice and the grant's own message. The script runs in a
    # runspace through Invoke-OERWithConfirmAnswer, so it is transported as text and installs its own
    # fakes in ITS copy of the module scope; they append the policy open and the POST to a log file
    # whose path is substituted into the text, since a stopped script prints nothing. The control runs
    # the same script without Stop. The log is written with AppendAllText, never Add-Content, which
    # could prompt on its own under a propagated $ConfirmPreference.
    BeforeAll {
        $script:NoTryScenario = {
            param([string]$Log, [string]$Stop)
            [scriptblock]::Create((@'
Import-Module Omnicit.EntraRBAC -Force -ErrorAction Stop
$Module = Get-Module Omnicit.EntraRBAC
& $Module {
    Set-Item -Path function:script:Initialize-OERAuth -Value { }
    Set-Item -Path function:script:Resolve-OERGroupId -Value { 'gid-1' }
    Set-Item -Path function:script:Resolve-OERPrincipalOrId -Value { [pscustomobject]@{ PrincipalId = '11111111-1111-1111-1111-111111111111' } }
    Set-Item -Path function:script:Get-OERGroupPermanentEligibilityState -Value {
        [pscustomobject]@{ HasPolicy = $true; PolicyId = 'pol-1'; PermanentAllowed = $false }
    }
    Set-Item -Path function:script:Enable-OERGroupPermanentEligibility -Value {
        [System.IO.File]::AppendAllText('#LOG#', "open`n")
        $true
    }
    Set-Item -Path function:script:Invoke-OERGraphRequest -Value {
        param([string]$Method = 'GET', [string]$Uri, $Body)
        [System.IO.File]::AppendAllText('#LOG#', "grant $Method`n")
        throw 'Graph rejected the request'
    }
}
$Result = Add-OERGroupEligibility -Group 'gid-1' -PrincipalId '11111111-1111-1111-1111-111111111111' -Confirm:$false -WarningAction SilentlyContinue #STOP#
"REACHED:$(@($Result).Count)"
'END'
'@).Replace('#LOG#', $Log.Replace("'", "''")).Replace('#STOP#', $Stop))
        }
        $script:NoTryAdviceText = "The PIM member eligibility grant failed after PIM-for-groups policy 'pol-1' had been opened " +
            'to allow permanent eligibility. The policy is still open; close it with ' +
            "'Set-OERGroupPimPolicy -Group ''gid-1'' -AccessType member -AllowPermanentEligibility:`$false' " +
            'if you do not intend to retry. The request failed with: Graph rejected the request'
        function Get-TestLoggedLine ([string]$Log) {
            if (Test-Path -LiteralPath $Log) { @(Get-Content -LiteralPath $Log) } else { @() }
        }
    }

    It 'a refused grant after an open, under -ErrorAction Stop, ends the script with PolicyOpenedButGrantFailed, carrying the advice and the cause' {
        $Log = Join-Path $TestDrive ('{0}.log' -f [guid]::NewGuid())
        $Scenario = & $script:NoTryScenario -Log $Log -Stop '-ErrorAction Stop'
        # Measured: a stop outside any try ends the whole script, so the runner throws to its caller.
        $Thrown = { Invoke-OERWithConfirmAnswer -Answer '&Yes' -Script $Scenario } | Should -Throw -PassThru
        $Thrown.Exception.InnerException | Should -BeOfType ([System.Management.Automation.ActionPreferenceStopException])
        $Thrown.Exception.InnerException.ErrorRecord.FullyQualifiedErrorId | Should -BeExactly 'PolicyOpenedButGrantFailed,Add-OERGroupEligibility'
        $Thrown.Exception.InnerException.ErrorRecord.Exception.Message | Should -BeExactly $script:NoTryAdviceText
        # The policy was opened and the POST sent before that error stopped the script.
        @(Get-TestLoggedLine -Log $Log) | Should -Be @('open', 'grant POST')
    }

    It 'the control: without Stop the same script reaches the end, PolicyOpenedButGrantFailed written before the grant''s own error' {
        $Log = Join-Path $TestDrive ('{0}.log' -f [guid]::NewGuid())
        $Scenario = & $script:NoTryScenario -Log $Log -Stop ''
        $Run = Invoke-OERWithConfirmAnswer -Answer '&Yes' -Script $Scenario
        ($Run.Output -join '|') | Should -Be 'REACHED:0|END'
        @(Get-TestLoggedLine -Log $Log) | Should -Be @('open', 'grant POST')
        @($Run.Errors) | Should -Be @($script:NoTryAdviceText, 'Graph rejected the request')
    }
}
