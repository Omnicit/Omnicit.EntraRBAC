BeforeAll {
    $script:moduleName = 'Omnicit.EntraRBAC'
    Get-Module $script:moduleName | Remove-Module -Force -ErrorAction SilentlyContinue
    Import-Module $script:moduleName -Force -ErrorAction Stop
}

Describe 'New-OERDirectoryRoleScheduleRequestBody' {
    It 'builds an adminAssign body with an afterDuration expiration' {
        InModuleScope $script:moduleName {
            $Body = New-OERDirectoryRoleScheduleRequestBody -Action adminAssign -PrincipalId 'p1' `
                -RoleDefinitionId 'r1' -Duration 'P30D' -Justification 'Test justification'
            $Body.action | Should -Be 'adminAssign'
            $Body.principalId | Should -Be 'p1'
            $Body.roleDefinitionId | Should -Be 'r1'
            $Body.directoryScopeId | Should -Be '/'
            $Body.justification | Should -Be 'Test justification'
            $Body.scheduleInfo.expiration.type | Should -Be 'afterDuration'
            $Body.scheduleInfo.expiration.duration | Should -Be 'P30D'
            [datetime]$Body.scheduleInfo.startDateTime | Should -Not -BeNullOrEmpty
            $Body.ContainsKey('ticketInfo') | Should -BeFalse
        }
    }

    It 'builds a noExpiration schedule when neither -Duration nor -EndDateTime is supplied' {
        InModuleScope $script:moduleName {
            $Body = New-OERDirectoryRoleScheduleRequestBody -Action adminAssign -PrincipalId 'p1' `
                -RoleDefinitionId 'r1' -Justification 'Test justification'
            $Body.scheduleInfo.expiration.type | Should -Be 'noExpiration'
        }
    }

    It 'builds an afterDateTime expiration in ISO 8601 UTC when -EndDateTime is supplied' {
        InModuleScope $script:moduleName {
            $End = (Get-Date).ToUniversalTime().AddDays(30)
            $Body = New-OERDirectoryRoleScheduleRequestBody -Action adminAssign -PrincipalId 'p1' `
                -RoleDefinitionId 'r1' -EndDateTime $End -Justification 'Test justification'
            $Body.scheduleInfo.expiration.type | Should -Be 'afterDateTime'
            [datetimeoffset]::Parse($Body.scheduleInfo.expiration.endDateTime).UtcDateTime |
                Should -Be ([datetime]::SpecifyKind($End, [DateTimeKind]::Utc))
        }
    }

    It 'omits scheduleInfo entirely for adminRemove' {
        InModuleScope $script:moduleName {
            $Body = New-OERDirectoryRoleScheduleRequestBody -Action adminRemove -PrincipalId 'p1' `
                -RoleDefinitionId 'r1' -Justification 'Removal'
            $Body.ContainsKey('scheduleInfo') | Should -BeFalse
        }
    }

    It 'carries ticketInfo when a ticket number or system is supplied' {
        InModuleScope $script:moduleName {
            $Body = New-OERDirectoryRoleScheduleRequestBody -Action adminAssign -PrincipalId 'p1' `
                -RoleDefinitionId 'r1' -Justification 'Test justification' -TicketNumber 'INC123' -TicketSystem 'ServiceNow'
            $Body.ticketInfo.ticketNumber | Should -Be 'INC123'
            $Body.ticketInfo.ticketSystem | Should -Be 'ServiceNow'
        }
    }

    It 'throws when both -Duration and -EndDateTime are supplied' {
        InModuleScope $script:moduleName {
            {
                New-OERDirectoryRoleScheduleRequestBody -Action adminAssign -PrincipalId 'p1' -RoleDefinitionId 'r1' `
                    -Duration 'P30D' -EndDateTime (Get-Date).AddDays(30) -Justification 'Test justification'
            } | Should -Throw
        }
    }
}
