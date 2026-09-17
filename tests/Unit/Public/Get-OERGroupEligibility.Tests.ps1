BeforeAll {
    $script:moduleName = 'Omnicit.EntraRBAC'
    Get-Module $script:moduleName | Remove-Module -Force -ErrorAction SilentlyContinue
    Import-Module $script:moduleName -Force -ErrorAction Stop
}

Describe 'Get-OERGroupEligibility' {
    BeforeEach {
        InModuleScope $script:moduleName { $script:_OERAuthState = $null }
        Mock -ModuleName $script:moduleName Initialize-OERAuth {}
        Mock -ModuleName $script:moduleName Resolve-OERGroupId { 'g1' }
    }

    It 'reads eligibility via Get-OERGroup -IncludePimEligibility and tags output' {
        Mock -ModuleName $script:moduleName Get-OERGroup {
            [PSCustomObject]@{ Id = 'g1'; PimEligibility = @(@{ id = 'inst-1'; principalId = 'p1'; accessId = 'member'; status = 'Provisioned' }) }
        }
        $R = Get-OERGroupEligibility -Group 'role_sec_x'
        $R[0].PSObject.TypeNames[0] | Should -Be 'Omnicit.EntraRBAC.GroupEligibilitySchedule'
        $R[0].PrincipalId | Should -Be 'p1'
        Should -Invoke -ModuleName $script:moduleName Get-OERGroup -Times 1 -ParameterFilter { $IncludePimEligibility }
    }

    It 'returns nothing for a group with no eligibility (not onboarded to PIM)' {
        Mock -ModuleName $script:moduleName Get-OERGroup { [PSCustomObject]@{ Id = 'g1'; PimEligibility = @() } }
        Get-OERGroupEligibility -Group 'role_sec_x' | Should -BeNullOrEmpty
    }

    It 'errors GroupNotFound when the group cannot be resolved' {
        Mock -ModuleName $script:moduleName Resolve-OERGroupId { $null }
        Mock -ModuleName $script:moduleName Get-OERGroup {}
        Get-OERGroupEligibility -Group 'nope' -ErrorVariable Err -ErrorAction SilentlyContinue | Out-Null
        $Err[0].FullyQualifiedErrorId | Should -Match 'GroupNotFound'
        Should -Invoke -ModuleName $script:moduleName Get-OERGroup -Times 0 -Exactly
    }

    It 'gives an actionable GroupNotFound message' {
        Mock -ModuleName $script:moduleName Initialize-OERAuth { }
        Mock -ModuleName $script:moduleName Resolve-OERGroupId { $null }
        Mock -ModuleName $script:moduleName Get-OERGroup {}
        Get-OERGroupEligibility -Group 'ghost' -ErrorAction SilentlyContinue -ErrorVariable Err
        $Joined = @($Err).FullyQualifiedErrorId -join ';'
        $Joined | Should -Match 'GroupNotFound'
        $Text = @($Err).Exception.Message -join ' '
        $Text | Should -Match 'display name'
        $Text | Should -Match 'object id'
    }

    It 'surfaces a terminating Get-OERGroup failure as its own error and scrubs the bearer record' {
        # The mock must THROW. The catch at Get-OERGroupEligibility.ps1:69-73 fires only on a
        # terminating error; a Write-Error there is non-terminating and simply flows through to the
        # caller (correct wrapper behaviour, but it enters none of the code this It names).
        Mock -ModuleName $script:moduleName Get-OERGroup { throw 'graph down' }
        # This It is the only coverage of that catch's mandatory Remove-OERErrorRecord line, so
        # guard the call directly -- a $global:Error reference-identity proof cannot see it.
        Mock -ModuleName $script:moduleName Remove-OERErrorRecord { }
        Get-OERGroupEligibility -Group 'role_sec_x' -ErrorVariable Err -ErrorAction SilentlyContinue | Out-Null
        Should -Invoke -ModuleName $script:moduleName Remove-OERErrorRecord -Times 1
        # Match the cmdlet-QUALIFIED ErrorId: the mock's own record is auto-recorded into
        # -ErrorVariable roughly a dozen times before the catch runs, so a bare count or a
        # bare-code match passes even with the cmdlet's $PSCmdlet.WriteError deleted.
        @($Err | Where-Object { $_.FullyQualifiedErrorId -eq 'graph down,Get-OERGroupEligibility' }).Count |
            Should -Be 1
    }

    It 'accepts pipeline input by property name (Id alias)' {
        Mock -ModuleName $script:moduleName Get-OERGroup {
            [PSCustomObject]@{ Id = 'g1'; PimEligibility = @(@{ id = 'inst-1'; principalId = 'p1'; accessId = 'member'; status = 'Provisioned' }) }
        }
        $R = [PSCustomObject]@{ Id = 'g1' } | Get-OERGroupEligibility
        $R[0].PrincipalId | Should -Be 'p1'
        Should -Invoke -ModuleName $script:moduleName Get-OERGroup -Times 1
    }

    It 'binds the parent GroupId, not the principal Id, from a piped group member' {
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

        $Member | Get-OERGroupEligibility -ErrorAction SilentlyContinue | Out-Null

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
            Get-OERGroupEligibility -ErrorAction SilentlyContinue | Out-Null

        Should -Invoke -ModuleName $script:moduleName Resolve-OERGroupId -Times 1 -Exactly `
            -ParameterFilter { $DisplayName -eq 'role_sec_x' }
    }
}
