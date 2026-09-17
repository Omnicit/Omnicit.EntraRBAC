BeforeAll {
    $script:moduleName = 'Omnicit.EntraRBAC'
    Get-Module $script:moduleName | Remove-Module -Force -ErrorAction SilentlyContinue
    Import-Module $script:moduleName -Force -ErrorAction Stop
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
            $Uri -like '*groups/g1/members*' -and $All
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
            -ParameterFilter { $Uri -like '*groups/g1/owners*' }
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
            -ParameterFilter { $Uri -like '*groups/g1/owners*' }
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
            -ParameterFilter { $Uri -like '*/members*' }
    }
}
