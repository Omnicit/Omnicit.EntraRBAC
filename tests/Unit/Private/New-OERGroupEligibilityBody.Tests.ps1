BeforeAll {
    $script:moduleName = 'Omnicit.EntraRBAC'
    Get-Module $script:moduleName | Remove-Module -Force -ErrorAction SilentlyContinue
    Import-Module $script:moduleName -Force -ErrorAction Stop
}

Describe 'New-OERGroupEligibilityBody' {
    It 'builds an adminAssign body with afterDuration expiration' {
        InModuleScope $script:moduleName {
            $Body = New-OERGroupEligibilityBody -GroupId 'g1' -PrincipalId 'p1' -Duration 'P1Y'
            $Body.accessId | Should -Be 'member'
            $Body.action | Should -Be 'adminAssign'
            $Body.groupId | Should -Be 'g1'
            $Body.principalId | Should -Be 'p1'
            $Body.scheduleInfo.expiration.type | Should -Be 'afterDuration'
            $Body.scheduleInfo.expiration.duration | Should -Be 'P1Y'
        }
    }

    It 'builds a noExpiration schedule when no duration is supplied' {
        InModuleScope $script:moduleName {
            $Body = New-OERGroupEligibilityBody -GroupId 'g1' -PrincipalId 'p1'
            $Body.scheduleInfo.expiration.type | Should -Be 'noExpiration'
        }
    }

    It 'supports owner access and adminRemove action' {
        InModuleScope $script:moduleName {
            $Body = New-OERGroupEligibilityBody -GroupId 'g1' -PrincipalId 'p1' -AccessType owner -Action adminRemove
            $Body.accessId | Should -Be 'owner'
            $Body.action | Should -Be 'adminRemove'
        }
    }

    It 'accepts an hour-scoped ISO 8601 duration (audit PR6)' {
        InModuleScope $script:moduleName {
            $Body = New-OERGroupEligibilityBody -GroupId 'g1' -PrincipalId 'p1' -Duration 'PT8H'
            $Body.scheduleInfo.expiration.type | Should -Be 'afterDuration'
            $Body.scheduleInfo.expiration.duration | Should -Be 'PT8H'
        }
    }
}
