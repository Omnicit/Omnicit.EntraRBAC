BeforeAll {
    $script:moduleName = 'Omnicit.EntraRBAC'
    Get-Module $script:moduleName | Remove-Module -Force -ErrorAction SilentlyContinue
    Import-Module $script:moduleName -Force -ErrorAction Stop
}

Describe 'Get-OERRoleAssignableState' {
    It 'reports IsGroup and IsAssignableToRole true for a role-assignable group, filtering the request correctly' {
        InModuleScope $script:moduleName {
            Mock Invoke-OERGraphRequest {
                [PSCustomObject]@{ id = 'aaaaaaaa-0000-0000-0000-000000000001'; isAssignableToRole = $true }
            } -ParameterFilter { $Uri -eq "v1.0/groups/aaaaaaaa-0000-0000-0000-000000000001`?`$select=id,isAssignableToRole" }

            $Result = Get-OERRoleAssignableState -PrincipalId 'aaaaaaaa-0000-0000-0000-000000000001'

            $Result.IsGroup | Should -BeTrue
            $Result.IsAssignableToRole | Should -BeTrue
            Should -Invoke Invoke-OERGraphRequest -Times 1 -Exactly -ParameterFilter {
                $Uri -eq "v1.0/groups/aaaaaaaa-0000-0000-0000-000000000001`?`$select=id,isAssignableToRole" -and
                (@($ExpectedErrorCode) -contains 'Request_ResourceNotFound')
            }
        }
    }

    It 'reports IsAssignableToRole false for a group that is not role-assignable' {
        InModuleScope $script:moduleName {
            Mock Invoke-OERGraphRequest {
                [PSCustomObject]@{ id = 'aaaaaaaa-0000-0000-0000-000000000001'; isAssignableToRole = $false }
            }
            $Result = Get-OERRoleAssignableState -PrincipalId 'aaaaaaaa-0000-0000-0000-000000000001'
            $Result.IsGroup | Should -BeTrue
            $Result.IsAssignableToRole | Should -BeFalse
        }
    }

    It 'reports IsGroup false when Microsoft Graph answers 404 (expected-error marker)' {
        InModuleScope $script:moduleName {
            Mock Invoke-OERGraphRequest {
                $Marker = [PSCustomObject]@{ ExpectedErrorCode = 'Request_ResourceNotFound'; StatusCode = 404; Message = 'not found'; Uri = 'v1.0/groups/x' }
                $Marker.PSObject.TypeNames.Insert(0, 'Omnicit.EntraRBAC.GraphExpectedError')
                $Marker
            }
            $Result = Get-OERRoleAssignableState -PrincipalId 'aaaaaaaa-0000-0000-0000-000000000001'
            $Result.IsGroup | Should -BeFalse
            $Result.IsAssignableToRole | Should -BeFalse
        }
    }

    It 'throws before any request when -PrincipalId is not a GUID' {
        InModuleScope $script:moduleName {
            Mock Invoke-OERGraphRequest { }
            { Get-OERRoleAssignableState -PrincipalId 'not-a-guid' } | Should -Throw
            Should -Invoke Invoke-OERGraphRequest -Times 0
        }
    }

    It 'propagates a transport failure' {
        InModuleScope $script:moduleName {
            Mock Invoke-OERGraphRequest { throw 'transport failure' }
            { Get-OERRoleAssignableState -PrincipalId 'aaaaaaaa-0000-0000-0000-000000000001' } | Should -Throw 'transport failure'
        }
    }
}
