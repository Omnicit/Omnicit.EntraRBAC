BeforeAll {
    $script:moduleName = 'Omnicit.EntraRBAC'
    Get-Module $script:moduleName | Remove-Module -Force -ErrorAction SilentlyContinue
    Import-Module $script:moduleName -Force -ErrorAction Stop
    . "$PSScriptRoot/../TestHelpers/OERTransportTripwire.ps1"
    Install-OERTransportTripwire
}

AfterAll {
    try { Assert-OERTransportTripwire } finally { Uninstall-OERTransportTripwire }
}

Describe 'Send-OERNewGroupEligibilityRequest' {
    BeforeEach {
        Mock -ModuleName $script:moduleName Initialize-OERAuth { }
    }

    It 'POSTs the shared eligibility body to the PIM-for-Groups path and declares ResourceNotFound' {
        InModuleScope $script:moduleName {
            Mock Invoke-OERGraphRequest {
                param([string]$Method, [string]$Uri, [hashtable]$Body, [string[]]$ExpectedErrorCode)
                @{ id = 'req-1'; status = 'Provisioned' }
            }
            $r = Send-OERNewGroupEligibilityRequest -GroupId 'g-1' -PrincipalId 'p-1' -DurationDays 5 -AccessType owner
            $r.id | Should -Be 'req-1'
            Should -Invoke Invoke-OERGraphRequest -Times 1 -Exactly -ParameterFilter {
                $Method -eq 'POST' -and
                $Uri -eq (Get-OERPimGroupsGraphPath -Path 'identityGovernance/privilegedAccess/group/eligibilityScheduleRequests') -and
                @($ExpectedErrorCode) -contains 'ResourceNotFound' -and
                $Body.groupId -eq 'g-1' -and $Body.principalId -eq 'p-1' -and $Body.accessId -eq 'owner' -and
                $Body.action -eq 'adminAssign' -and
                $Body.scheduleInfo.expiration.type -eq 'afterDuration' -and $Body.scheduleInfo.expiration.duration -eq 'P5D'
            }
        }
    }

    It 'carries -Action adminUpdate through to the request body' {
        InModuleScope $script:moduleName {
            Mock Invoke-OERGraphRequest {
                param([string]$Method, [string]$Uri, [hashtable]$Body, [string[]]$ExpectedErrorCode)
                @{ id = 'req-1' }
            }
            $null = Send-OERNewGroupEligibilityRequest -GroupId 'g-1' -PrincipalId 'p-1' -DurationDays 5 -Action adminUpdate
            Should -Invoke Invoke-OERGraphRequest -Times 1 -Exactly -ParameterFilter {
                $Body.action -eq 'adminUpdate' -and $Body.accessId -eq 'member'
            }
        }
    }

    It 'returns $null for a 404 ResourceNotFound answer' {
        InModuleScope $script:moduleName {
            Mock Invoke-OERGraphRequest {
                $Marker = [PSCustomObject]@{ ExpectedErrorCode = 'ResourceNotFound'; StatusCode = 404; Message = 'ResourceNotFound: not found'; Uri = 'x' }
                $Marker.PSObject.TypeNames.Insert(0, 'Omnicit.EntraRBAC.GraphExpectedError')
                $Marker
            }
            Send-OERNewGroupEligibilityRequest -GroupId 'g-1' -PrincipalId 'p-1' -DurationDays 5 | Should -BeNullOrEmpty
        }
    }

    It 'throws ResourceNotFound when the code arrives with a status other than 404' {
        InModuleScope $script:moduleName {
            Mock Invoke-OERGraphRequest {
                $Marker = [PSCustomObject]@{ ExpectedErrorCode = 'ResourceNotFound'; StatusCode = 400; Message = 'ResourceNotFound: odd'; Uri = 'x' }
                $Marker.PSObject.TypeNames.Insert(0, 'Omnicit.EntraRBAC.GraphExpectedError')
                $Marker
            }
            { Send-OERNewGroupEligibilityRequest -GroupId 'g-1' -PrincipalId 'p-1' -DurationDays 5 } | Should -Throw -ErrorId 'ResourceNotFound'
        }
    }

    It 'lets any other failure propagate as the transport raised it' {
        InModuleScope $script:moduleName {
            Mock Invoke-OERGraphRequest {
                throw [System.Management.Automation.ErrorRecord]::new(
                    [System.Exception]::new('Authorization_RequestDenied: Insufficient privileges.'),
                    'Authorization_RequestDenied', [System.Management.Automation.ErrorCategory]::PermissionDenied, $null)
            }
            { Send-OERNewGroupEligibilityRequest -GroupId 'g-1' -PrincipalId 'p-1' -DurationDays 5 } | Should -Throw -ErrorId 'Authorization_RequestDenied'
        }
    }
}
