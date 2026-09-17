BeforeAll {
    $script:moduleName = 'Omnicit.EntraRBAC'
    Get-Module $script:moduleName | Remove-Module -Force -ErrorAction SilentlyContinue
    Import-Module $script:moduleName -Force -ErrorAction Stop
}

Describe 'ConvertTo-OERGroupEligibility' {
    It 'maps an eligibilityScheduleInstance into a tagged object' {
        InModuleScope $script:moduleName {
            $Raw = @{ id = 'inst-1'; principalId = 'p1'; accessId = 'member'; memberType = 'direct'; eligibilityScheduleId = 'sched-1'; startDateTime = '2026-01-01T00:00:00Z'; endDateTime = '2027-01-01T00:00:00Z' }
            $Out = ConvertTo-OERGroupEligibility -InputObject $Raw -GroupId 'g1'
            $Out.PSObject.TypeNames[0]  | Should -Be 'Omnicit.EntraRBAC.GroupEligibilitySchedule'
            $Out.GroupId                | Should -Be 'g1'
            $Out.PrincipalId            | Should -Be 'p1'
            $Out.AccessType             | Should -Be 'member'
            $Out.MemberType             | Should -Be 'direct'
            $Out.StartDateTime          | Should -Be '2026-01-01T00:00:00Z'
            $Out.EndDateTime            | Should -Be '2027-01-01T00:00:00Z'
            $Out.ScheduleInstanceId     | Should -Be 'inst-1'
            $Out.EligibilityScheduleId  | Should -Be 'sched-1'
        }
    }

    It 'does not carry Action or Status (those belong to the request output)' {
        InModuleScope $script:moduleName {
            $Out = ConvertTo-OERGroupEligibility -InputObject @{ id = 'i1'; principalId = 'p1'; accessId = 'member'; memberType = 'direct' } -GroupId 'g1'
            $Out.PSObject.Properties.Name | Should -Not -Contain 'Action'
            $Out.PSObject.Properties.Name | Should -Not -Contain 'Status'
        }
    }

    It 'processes multiple instances from the pipeline' {
        InModuleScope $script:moduleName {
            $Raw = @(
                @{ id = 'i1'; principalId = 'p1'; accessId = 'member'; memberType = 'direct' }
                @{ id = 'i2'; principalId = 'p2'; accessId = 'owner'; memberType = 'group' }
            )
            $Out = $Raw | ConvertTo-OERGroupEligibility -GroupId 'g1'
            $Out.Count         | Should -Be 2
            $Out[1].AccessType | Should -Be 'owner'
            $Out[1].MemberType | Should -Be 'group'
        }
    }
}
