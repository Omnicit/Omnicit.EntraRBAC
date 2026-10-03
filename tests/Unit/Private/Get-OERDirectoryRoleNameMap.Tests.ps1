BeforeAll {
    $script:moduleName = 'Omnicit.EntraRBAC'
    Get-Module $script:moduleName | Remove-Module -Force -ErrorAction SilentlyContinue
    Import-Module $script:moduleName -Force -ErrorAction Stop
}

Describe 'Get-OERDirectoryRoleNameMap' {
    It 'maps both the role id and the role template id to the display name' {
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {
            @{ value = @(
                @{ id = 'role-1'; roleTemplateId = 'tmpl-1'; displayName = 'User Administrator' }
            ) }
        } -ParameterFilter { $Uri -eq 'v1.0/directoryRoles' }
        InModuleScope $script:moduleName {
            $Map = Get-OERDirectoryRoleNameMap
            $Map['role-1'] | Should -Be 'User Administrator'
            $Map['tmpl-1'] | Should -Be 'User Administrator'
        }
    }

    It 'returns an empty map when the Graph call fails' {
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest { throw 'graph down' }
        InModuleScope $script:moduleName {
            $Map = Get-OERDirectoryRoleNameMap
            $Map       | Should -BeOfType [hashtable]
            $Map.Count | Should -Be 0
        }
    }

    It 'scrubs the failed read exactly once and still returns an empty map when the Graph call fails' {
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest { throw 'graph down (injected default-mode failure)' }
        Mock -ModuleName $script:moduleName Remove-OERErrorRecord { }
        InModuleScope $script:moduleName {
            $Map = Get-OERDirectoryRoleNameMap
            # Positive proof first: the catch was reached and swallowed the failure.
            $Map       | Should -BeOfType [hashtable]
            $Map.Count | Should -Be 0
        }
        Should -Invoke -ModuleName $script:moduleName Remove-OERErrorRecord -Times 1 -Exactly -ParameterFilter {
            $Record.Exception.Message -eq 'graph down (injected default-mode failure)'
        }
    }

    Context '-ThrowOnFailure (the caller that cannot treat an unreadable map as an empty one)' {
        It 'returns the same map as the default when the read succeeds' {
            Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {
                @{ value = @(
                    @{ id = 'role-1'; roleTemplateId = 'tmpl-1'; displayName = 'User Administrator' }
                ) }
            } -ParameterFilter { $Uri -eq 'v1.0/directoryRoles' }
            InModuleScope $script:moduleName {
                $Map = Get-OERDirectoryRoleNameMap -ThrowOnFailure
                $Map           | Should -BeOfType [hashtable]
                $Map.Count     | Should -Be 2
                $Map['role-1'] | Should -Be 'User Administrator'
                $Map['tmpl-1'] | Should -Be 'User Administrator'
            }
        }

        It 'returns an empty map without throwing when the read succeeds and lists no activated role' {
            Mock -ModuleName $script:moduleName Invoke-OERGraphRequest { @{ value = @() } } -ParameterFilter { $Uri -eq 'v1.0/directoryRoles' }
            InModuleScope $script:moduleName {
                $Map = Get-OERDirectoryRoleNameMap -ThrowOnFailure
                $Map       | Should -BeOfType [hashtable]
                $Map.Count | Should -Be 0
            }
        }

        It 'throws instead of returning an empty map when the Graph call fails, naming the read and keeping the cause' {
            Mock -ModuleName $script:moduleName Invoke-OERGraphRequest { throw 'graph down (injected strict failure)' }
            InModuleScope $script:moduleName {
                $Thrown = $null
                $Map = 'sentinel: the call did not return'
                try { $Map = Get-OERDirectoryRoleNameMap -ThrowOnFailure } catch { $Thrown = $PSItem }
                # Positive proof first: the failure surfaced, and no map (empty or otherwise) came back.
                $null -ne $Thrown | Should -BeTrue
                $Map | Should -BeExactly 'sentinel: the call did not return'
                $Thrown.Exception.Message | Should -Match 'v1\.0/directoryRoles'
                $Thrown.Exception.Message | Should -Match 'injected strict failure'
                $Thrown.Exception.InnerException.Message | Should -Be 'graph down (injected strict failure)'
            }
        }

        It 'scrubs the failed read exactly once before it throws' {
            Mock -ModuleName $script:moduleName Invoke-OERGraphRequest { throw 'graph down (injected strict failure)' }
            Mock -ModuleName $script:moduleName Remove-OERErrorRecord { }
            InModuleScope $script:moduleName {
                $Thrown = $null
                try { $null = Get-OERDirectoryRoleNameMap -ThrowOnFailure } catch { $Thrown = $PSItem }
                # The catch was reached and rethrew, so the scrub assertion below is not vacuous.
                $null -ne $Thrown | Should -BeTrue
            }
            Should -Invoke -ModuleName $script:moduleName Remove-OERErrorRecord -Times 1 -Exactly -ParameterFilter {
                $Record.Exception.Message -eq 'graph down (injected strict failure)'
            }
        }
    }

    It 'passes -All to the directoryRoles read (closes rt-graph-list-reads-first-page-only)' {
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {
            @{ value = @(
                @{ id = 'role-1'; roleTemplateId = 'tmpl-1'; displayName = 'User Administrator' }
            ) }
        } -ParameterFilter { $Uri -eq 'v1.0/directoryRoles' }
        InModuleScope $script:moduleName {
            $null = Get-OERDirectoryRoleNameMap
        }
        Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 1 -Exactly -ParameterFilter {
            $Uri -eq 'v1.0/directoryRoles' -and $All
        }
    }
}
