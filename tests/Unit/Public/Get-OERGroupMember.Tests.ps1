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

Describe 'Get-OERGroupMember' {
    BeforeEach {
        InModuleScope $script:moduleName { $script:_OERAuthState = $null }
        Mock -ModuleName $script:moduleName Initialize-OERAuth {}
        Mock -ModuleName $script:moduleName Resolve-OERGroupId { 'g1' }
    }

    It 'lists members via groups/{id}/members' {
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {
            @{ value = @(@{ '@odata.type' = '#microsoft.graph.user'; id = 'u1'; displayName = 'Anna'; userPrincipalName = 'anna@contoso.com' }) }
        }
        $R = Get-OERGroupMember -Group 'role_sec_x'
        $R[0].PSObject.TypeNames[0] | Should -Be 'Omnicit.EntraRBAC.GroupMember'
        $R[0].MemberType | Should -Be 'Member'
        Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 1 -ParameterFilter { $Uri -like '*groups/g1/members*' }
    }

    It 'lists owners via groups/{id}/owners with -Owners' {
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest { @{ value = @(@{ '@odata.type' = '#microsoft.graph.user'; id = 'u2'; displayName = 'Bo' }) } }
        $R = Get-OERGroupMember -Group 'role_sec_x' -Owners
        $R[0].MemberType | Should -Be 'Owner'
        Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 1 -ParameterFilter { $Uri -like '*groups/g1/owners*' }
    }

    It 'errors GroupNotFound when the group cannot be resolved' {
        Mock -ModuleName $script:moduleName Resolve-OERGroupId { $null }
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {}
        Get-OERGroupMember -Group 'nope' -ErrorVariable Err -ErrorAction SilentlyContinue | Out-Null
        $Err[0].FullyQualifiedErrorId | Should -Match 'GroupNotFound'
        Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 0 -Exactly
    }

    It 'gives an actionable GroupNotFound message' {
        Mock -ModuleName $script:moduleName Initialize-OERAuth { }
        Mock -ModuleName $script:moduleName Resolve-OERGroupId { $null }
        Get-OERGroupMember -Group 'ghost' -ErrorAction SilentlyContinue -ErrorVariable Err
        $Joined = @($Err).FullyQualifiedErrorId -join ';'
        $Joined | Should -Match 'GroupNotFound'
        $Text = @($Err).Exception.Message -join ' '
        $Text | Should -Match 'display name'
        $Text | Should -Match 'object id'
    }

    It 'returns nothing when the group has no members' {
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest { @{ value = @() } }
        Get-OERGroupMember -Group 'role_sec_x' | Should -BeNullOrEmpty
    }

    It 'surfaces a non-terminating error when the Graph call fails' {
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest { throw 'graph down' }
        Get-OERGroupMember -Group 'role_sec_x' -ErrorVariable Err -ErrorAction SilentlyContinue | Out-Null
        # Match the cmdlet-QUALIFIED ErrorId. PowerShell re-records the mock's own thrown record
        # into -ErrorVariable at roughly a dozen call boundaries before the cmdlet's catch runs
        # (13 records here; only the last carries ',Get-OERGroupMember'), so a bare count or a
        # bare-code match passes even with the cmdlet's $PSCmdlet.WriteError deleted.
        # The catch at Get-OERGroupMember.ps1:73-77 passes $PSItem through unchanged, so the
        # qualified id is the code the mock threw plus the cmdlet name.
        @($Err | Where-Object { $_.FullyQualifiedErrorId -eq 'graph down,Get-OERGroupMember' }).Count |
            Should -Be 1
    }

    It 'passes -All to the members/owners read (closes rt-graph-list-reads-first-page-only)' {
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {
            @{ value = @(@{ '@odata.type' = '#microsoft.graph.user'; id = 'u1'; displayName = 'Anna' }) }
        }
        Get-OERGroupMember -Group 'role_sec_x' | Out-Null
        Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 1 -Exactly -ParameterFilter {
            $Uri -eq 'v1.0/groups/g1/members' -and $All
        }
    }

    It 'binds the parent GroupId, not the principal Id, from a piped group member' {
        # Get-OERGroupMember also resolves -Group through Resolve-OERGroupId (like
        # Get-OERGroupEligibility) rather than building the URI straight from the raw pipeline
        # value, so the same ParameterFilter-on-Resolve-OERGroupId assertion applies here.
        Mock -ModuleName $script:moduleName Initialize-OERAuth { }
        Mock -ModuleName $script:moduleName Resolve-OERGroupId { 'GROUP-RESOLVED' }
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest { @{ value = @() } }

        $Member = InModuleScope $script:moduleName {
            ConvertTo-OERGroupMember -InputObject @{
                id                = '11111111-1111-1111-1111-111111111111'
                displayName       = 'Anna'
                userPrincipalName = 'anna@contoso.com'
                '@odata.type'     = '#microsoft.graph.user'
            } -GroupId '22222222-2222-2222-2222-222222222222' -MemberType 'Member'
        }

        $Member | Get-OERGroupMember -ErrorAction SilentlyContinue | Out-Null

        Should -Invoke -ModuleName $script:moduleName Resolve-OERGroupId -Times 1 -Exactly `
            -ParameterFilter { $DisplayName -eq '22222222-2222-2222-2222-222222222222' }
        Should -Invoke -ModuleName $script:moduleName Resolve-OERGroupId -Times 0 -Exactly `
            -ParameterFilter { $DisplayName -eq '11111111-1111-1111-1111-111111111111' }
    }

    It 'accepts a group display name from the pipeline via the DisplayName alias' {
        Mock -ModuleName $script:moduleName Initialize-OERAuth { }
        Mock -ModuleName $script:moduleName Resolve-OERGroupId { 'GROUP-RESOLVED' }
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest { @{ value = @() } }

        [pscustomobject]@{ DisplayName = 'role_sec_x' } |
            Get-OERGroupMember -ErrorAction SilentlyContinue | Out-Null

        Should -Invoke -ModuleName $script:moduleName Resolve-OERGroupId -Times 1 -Exactly `
            -ParameterFilter { $DisplayName -eq 'role_sec_x' }
    }

    It 'selects the owners collection when -AccessType owner is supplied' {
        Mock -ModuleName $script:moduleName Initialize-OERAuth { }
        Mock -ModuleName $script:moduleName Resolve-OERGroupId { 'g1' }
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest { @{ value = @() } }

        Get-OERGroupMember -Group 'g1' -AccessType owner | Out-Null

        Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 1 -Exactly `
            -ParameterFilter { $Uri -eq 'v1.0/groups/g1/owners' }
    }

    It 'still binds a positional second argument to -TenantId' {
        Mock -ModuleName $script:moduleName Initialize-OERAuth { }
        Mock -ModuleName $script:moduleName Resolve-OERGroupId { 'g1' }
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest { @{ value = @() } }

        Get-OERGroupMember 'g1' 'contoso.onmicrosoft.com' | Out-Null

        Should -Invoke -ModuleName $script:moduleName Initialize-OERAuth -Times 1 -Exactly `
            -ParameterFilter { $TenantId -eq 'contoso.onmicrosoft.com' }
    }

    It 'errors AmbiguousAccessType when -Owners and -AccessType disagree' {
        Mock -ModuleName $script:moduleName Initialize-OERAuth { }
        Mock -ModuleName $script:moduleName Resolve-OERGroupId { 'g1' }
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest { @{ value = @() } }

        Get-OERGroupMember -Group 'g1' -Owners -AccessType member -ErrorVariable Err -ErrorAction SilentlyContinue |
            Out-Null

        # Cmdlet-qualified id, not a bare-code match: a bare 'AmbiguousAccessType' match would pass
        # even if this cmdlet's own WriteError were deleted and some upstream call happened to record
        # an error carrying that substring.
        $Err[0].FullyQualifiedErrorId | Should -Be 'AmbiguousAccessType,Get-OERGroupMember'
        Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 0 -Exactly
    }

    It 'does not error when -Owners and -AccessType owner agree' {
        Mock -ModuleName $script:moduleName Initialize-OERAuth { }
        Mock -ModuleName $script:moduleName Resolve-OERGroupId { 'g1' }
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest { @{ value = @() } }

        { Get-OERGroupMember -Group 'g1' -Owners -AccessType owner -ErrorAction Stop | Out-Null } |
            Should -Not -Throw

        Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 1 -Exactly `
            -ParameterFilter { $Uri -eq 'v1.0/groups/g1/owners' }
    }

    It 'does not bind -AccessType from the pipeline, even from a piped object carrying MemberType Owner' {
        # This invariant is the entire reason -AccessType deliberately omits
        # [Parameter(ValueFromPipelineByPropertyName)] in source/Public/Get-OERGroupMember.ps1: the
        # real ConvertTo-OERGroupMember output below carries MemberType = 'Owner', which -AccessType
        # also carries as an [Alias('MemberType')]. If -AccessType ever gained pipeline binding "for
        # consistency" with -Group, this piped OWNER record would silently flip
        # `Get-OERGroupMember -Group X -Owners | Get-OERGroupMember` to read the owners collection
        # again instead of re-reading MEMBERS for whatever -Group resolves to. Proven by mutation: see
        # the fix-round section of task-1-report.md for the temporarily-added-attribute failing run.
        Mock -ModuleName $script:moduleName Initialize-OERAuth { }
        Mock -ModuleName $script:moduleName Resolve-OERGroupId { 'g1' }
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest { @{ value = @() } }

        $OwnerMember = InModuleScope $script:moduleName {
            ConvertTo-OERGroupMember -InputObject @{
                id                = '33333333-3333-3333-3333-333333333333'
                displayName       = 'Cara'
                userPrincipalName = 'cara@contoso.com'
                '@odata.type'     = '#microsoft.graph.user'
            } -GroupId 'g1' -MemberType 'Owner'
        }

        $OwnerMember | Get-OERGroupMember -ErrorAction SilentlyContinue | Out-Null

        Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 1 -Exactly `
            -ParameterFilter { $Uri -eq 'v1.0/groups/g1/members' }
    }

    Context 'a service principal only the typed read lists' {
        # Microsoft Graph v1.0 groups/{id}/members and groups/{id}/owners leave service principals
        # out (measured 2026-10-06); the typed .../microsoft.graph.servicePrincipal read lists them,
        # without an @odata.type annotation.
        It 'lists it after the untyped members, with ObjectType servicePrincipal' {
            Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {
                @{ value = @(@{ '@odata.type' = '#microsoft.graph.group'; id = 'g-nested'; displayName = 'nested' }) }
            } -ParameterFilter { $Uri -eq 'v1.0/groups/g1/members' }
            Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {
                @{ value = @(@{ id = 'sp-1'; displayName = 'an app' }) }
            } -ParameterFilter { $Uri -eq 'v1.0/groups/g1/members/microsoft.graph.servicePrincipal' }

            $R = @(Get-OERGroupMember -Group 'role_sec_x' -ErrorAction Stop)
            $R.Count | Should -Be 2
            $R[0].PrincipalId | Should -Be 'g-nested'
            $R[0].ObjectType | Should -Be 'group'
            $R[1].PrincipalId | Should -Be 'sp-1'
            $R[1].ObjectType | Should -Be 'servicePrincipal'
            $R[1].MemberType | Should -Be 'Member'
            $R[1].GroupId | Should -Be 'g1'
            Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 1 -Exactly -ParameterFilter {
                $Uri -eq 'v1.0/groups/g1/members/microsoft.graph.servicePrincipal' -and $All
            }
        }

        It 'lists it as an Owner with -Owners when the untyped owners read is empty' {
            Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {
                @{ value = @() }
            } -ParameterFilter { $Uri -eq 'v1.0/groups/g1/owners' }
            Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {
                @{ value = @(@{ id = 'sp-1'; displayName = 'an app' }) }
            } -ParameterFilter { $Uri -eq 'v1.0/groups/g1/owners/microsoft.graph.servicePrincipal' }

            $R = @(Get-OERGroupMember -Group 'role_sec_x' -Owners -ErrorAction Stop)
            $R.Count | Should -Be 1
            $R[0].PrincipalId | Should -Be 'sp-1'
            $R[0].ObjectType | Should -Be 'servicePrincipal'
            $R[0].MemberType | Should -Be 'Owner'
            Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 1 -Exactly -ParameterFilter {
                $Uri -eq 'v1.0/groups/g1/owners/microsoft.graph.servicePrincipal' -and $All
            }
        }

        It 'lists it as an Owner with -AccessType owner when the untyped owners read is empty' {
            Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {
                @{ value = @() }
            } -ParameterFilter { $Uri -eq 'v1.0/groups/g1/owners' }
            Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {
                @{ value = @(@{ id = 'sp-1'; displayName = 'an app' }) }
            } -ParameterFilter { $Uri -eq 'v1.0/groups/g1/owners/microsoft.graph.servicePrincipal' }

            $R = @(Get-OERGroupMember -Group 'role_sec_x' -AccessType owner -ErrorAction Stop)
            $R.Count | Should -Be 1
            $R[0].PrincipalId | Should -Be 'sp-1'
            $R[0].ObjectType | Should -Be 'servicePrincipal'
            $R[0].MemberType | Should -Be 'Owner'
            Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 1 -Exactly -ParameterFilter {
                $Uri -eq 'v1.0/groups/g1/owners/microsoft.graph.servicePrincipal' -and $All
            }
        }
    }

    Context 'a failed typed read leaves the collection unread' {
        # The typed service principal read fails AFTER the untyped read succeeded and listed a
        # member. A collection is read whole or not at all: nothing is emitted (no partial list a
        # pipeline could act on) and the transport's own record is written as itself.
        BeforeEach {
            Mock -ModuleName $script:moduleName Invoke-OERGraphRequest { throw "unexpected request: $Uri" }
            Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {
                @{ value = @(@{ '@odata.type' = '#microsoft.graph.user'; id = 'u-1'; displayName = 'a user' }) }
            } -ParameterFilter { $Uri -eq 'v1.0/groups/g1/members' }
            Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {
                throw [System.Management.Automation.ErrorRecord]::new([System.Exception]::new('Forbidden: denied'), 'Forbidden', 'PermissionDenied', $null)
            } -ParameterFilter { $Uri -eq 'v1.0/groups/g1/members/microsoft.graph.servicePrincipal' }
            Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {
                @{ value = @(@{ '@odata.type' = '#microsoft.graph.user'; id = 'u-1'; displayName = 'a user' }) }
            } -ParameterFilter { $Uri -eq 'v1.0/groups/g1/owners' }
            Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {
                throw [System.Management.Automation.ErrorRecord]::new([System.Exception]::new('Forbidden: denied'), 'Forbidden', 'PermissionDenied', $null)
            } -ParameterFilter { $Uri -eq 'v1.0/groups/g1/owners/microsoft.graph.servicePrincipal' }
        }

        It 'emits nothing and writes the transport''s own record when the typed members read fails' {
            $Out = @(Get-OERGroupMember -Group 'role_sec_x' -ErrorAction SilentlyContinue -ErrorVariable Err)
            $Out.Count | Should -Be 0
            # The catch was reached, by the typed read: it was sent, and the written record is the
            # transport's own (the cmdlet-qualified id, as in the Graph-call failure test above).
            Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 1 -Exactly -ParameterFilter {
                $Uri -eq 'v1.0/groups/g1/members/microsoft.graph.servicePrincipal' -and $All
            }
            $Written = @($Err | Where-Object { $_.FullyQualifiedErrorId -eq 'Forbidden,Get-OERGroupMember' })
            $Written.Count | Should -Be 1
            $Written[0].Exception.Message | Should -Be 'Forbidden: denied'
        }

        It 'scrubs the typed members read failure before it is reported' {
            Mock -ModuleName $script:moduleName Remove-OERErrorRecord { }
            $Out = @(Get-OERGroupMember -Group 'role_sec_x' -ErrorAction SilentlyContinue -ErrorVariable Err)
            $Out.Count | Should -Be 0
            @($Err | Where-Object { $_.FullyQualifiedErrorId -eq 'Forbidden,Get-OERGroupMember' }).Count | Should -Be 1
            Should -Invoke -ModuleName $script:moduleName Remove-OERErrorRecord -Times 1 -Exactly -ParameterFilter {
                $Record.Exception.Message -like '*Forbidden*'
            }
        }

        It 'emits nothing and writes the transport''s own record when the typed owners read fails, with -Owners' {
            $Out = @(Get-OERGroupMember -Group 'role_sec_x' -Owners -ErrorAction SilentlyContinue -ErrorVariable Err)
            $Out.Count | Should -Be 0
            Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 1 -Exactly -ParameterFilter {
                $Uri -eq 'v1.0/groups/g1/owners/microsoft.graph.servicePrincipal' -and $All
            }
            $Written = @($Err | Where-Object { $_.FullyQualifiedErrorId -eq 'Forbidden,Get-OERGroupMember' })
            $Written.Count | Should -Be 1
            $Written[0].Exception.Message | Should -Be 'Forbidden: denied'
        }

        It 'emits nothing and writes the transport''s own record when the typed owners read fails, with -AccessType owner' {
            $Out = @(Get-OERGroupMember -Group 'role_sec_x' -AccessType owner -ErrorAction SilentlyContinue -ErrorVariable Err)
            $Out.Count | Should -Be 0
            Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 1 -Exactly -ParameterFilter {
                $Uri -eq 'v1.0/groups/g1/owners/microsoft.graph.servicePrincipal' -and $All
            }
            @($Err | Where-Object { $_.FullyQualifiedErrorId -eq 'Forbidden,Get-OERGroupMember' }).Count | Should -Be 1
        }

        It 'scrubs the typed owners read failure before it is reported' {
            Mock -ModuleName $script:moduleName Remove-OERErrorRecord { }
            $Out = @(Get-OERGroupMember -Group 'role_sec_x' -Owners -ErrorAction SilentlyContinue -ErrorVariable Err)
            $Out.Count | Should -Be 0
            @($Err | Where-Object { $_.FullyQualifiedErrorId -eq 'Forbidden,Get-OERGroupMember' }).Count | Should -Be 1
            Should -Invoke -ModuleName $script:moduleName Remove-OERErrorRecord -Times 1 -Exactly -ParameterFilter {
                $Record.Exception.Message -like '*Forbidden*'
            }
        }
    }
}

Describe 'Get-OERGroupMember and Get-OERGroup with a failed typed read, in a script with no try' {
    # Pester's It runs inside a try, and a try hides what a caller does outside one: a caller carries
    # on past a nested advanced function's terminating error, and a plain uncaught throw ends the
    # whole script. So the same two guards run here in a runspace whose script has NO try of its own
    # (Invoke-OERWithConfirmAnswer), with every dependency of the module stubbed in ITS copy of the
    # module scope. The script ends with a sentinel line, so one that died early cannot pass, and its
    # stub of the transport throws a thrown ErrorRecord exactly as the real wrapper does.
    BeforeAll {
        $script:NewNoTryScenario = {
            param([string]$TypedRead)
            [scriptblock]::Create((@'
Import-Module Omnicit.EntraRBAC -Force -ErrorAction Stop
$Module = Get-Module Omnicit.EntraRBAC
& $Module {
    Set-Item -Path function:script:Initialize-OERAuth -Value { }
    Set-Item -Path function:script:Remove-OERErrorRecord -Value { }
    Set-Item -Path function:script:Invoke-OERGraphRequest -Value {
        [CmdletBinding()]
        param([string]$Uri, [switch]$All)
        $GroupUri = 'v1.0/groups/22222222-2222-2222-2222-222222222222'
        if ($Uri -eq $GroupUri) {
            return @{ id = '22222222-2222-2222-2222-222222222222'; displayName = 'role_sec_team'; securityEnabled = $true; isAssignableToRole = $false; groupTypes = @() }
        }
        if ($Uri -eq "$GroupUri/members") {
            return @{ value = @(@{ '@odata.type' = '#microsoft.graph.group'; id = 'g-nested'; displayName = 'nested' }) }
        }
        if ($Uri -eq "$GroupUri/members/microsoft.graph.servicePrincipal") {
            #TYPEDREAD#
        }
        throw "unexpected request: $Uri"
    }
}
$M = @(Get-OERGroupMember -Group '22222222-2222-2222-2222-222222222222')
"MEMBERS:$($M.Count)"
$G = Get-OERGroup -Group '22222222-2222-2222-2222-222222222222' -IncludeMembers
"HASMEMBERS:$($null -ne $G.PSObject.Properties['Members']);ID:$($G.Id)"
& $Module {
    Remove-Item function:Initialize-OERAuth
    Remove-Item function:Remove-OERErrorRecord
    Remove-Item function:Invoke-OERGraphRequest
    "STUBS:$(@('Initialize-OERAuth', 'Remove-OERErrorRecord', 'Invoke-OERGraphRequest' | Where-Object { Get-Command -Name $PSItem -CommandType Function -ErrorAction Ignore }).Count)"
}
'END'
'@).Replace('#TYPEDREAD#', $TypedRead))
        }
        $script:TypedReadFails = "throw [System.Management.Automation.ErrorRecord]::new([System.Exception]::new('Forbidden: denied'), 'Forbidden', 'PermissionDenied', `$null)"
        $script:TypedReadAnswers = "return @{ value = @(@{ id = 'sp-1'; displayName = 'an app' }) }"
    }

    It 'lists nothing and omits Members, with both errors, when the typed members read fails' {
        $Scenario = & $script:NewNoTryScenario -TypedRead $script:TypedReadFails
        $Result = Invoke-OERWithConfirmAnswer -Answer '&Yes' -Script $Scenario
        # One line per statement, in order, ending in the sentinel: a script that died early, or that
        # emitted a partial list into the pipeline, reads differently.
        ($Result.Output -join '|') | Should -Be 'MEMBERS:0|HASMEMBERS:False;ID:22222222-2222-2222-2222-222222222222|STUBS:0|END'
        # Get-OERGroupMember writes the transport's own record; Get-OERGroup writes its own.
        @($Result.Errors | Where-Object { $_ -eq 'Forbidden: denied' }).Count | Should -Be 1
        @($Result.Errors | Where-Object { $_ -like 'Could not read members for group 22222222-2222-2222-2222-222222222222: Forbidden: denied*' }).Count | Should -Be 1
        $Result.Errors.Count | Should -Be 2
    }

    It 'lists the service principal and keeps Members, with no error, when the typed members read succeeds' {
        # The control: the same scenario with the typed read answered. Without it the zero above could
        # come from a stub that never listed anything.
        $Scenario = & $script:NewNoTryScenario -TypedRead $script:TypedReadAnswers
        $Result = Invoke-OERWithConfirmAnswer -Answer '&Yes' -Script $Scenario
        ($Result.Output -join '|') | Should -Be 'MEMBERS:2|HASMEMBERS:True;ID:22222222-2222-2222-2222-222222222222|STUBS:0|END'
        $Result.Errors.Count | Should -Be 0
    }
}
