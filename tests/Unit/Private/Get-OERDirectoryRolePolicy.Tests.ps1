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

Describe 'Get-OERDirectoryRolePolicy' {
    It 'reads the policy by id with $expand=rules' {
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {
            @{ id = 'DirectoryRole_pol1'; scopeId = '/'; scopeType = 'DirectoryRole'; rules = @(@{ id = 'Expiration_EndUser_Assignment'; maximumDuration = 'PT8H' }) }
        }
        $Result = InModuleScope $script:moduleName { Get-OERDirectoryRolePolicy -PolicyId 'DirectoryRole_pol1' }
        $Result.rules.Count | Should -Be 1
        Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Exactly 1 -ParameterFilter {
            $Uri -eq "v1.0/policies/roleManagementPolicies/DirectoryRole_pol1`?`$expand=rules"
        }
    }

    It 'propagates a transport failure instead of swallowing it' {
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest { throw 'Forbidden: insufficient privileges' }
        InModuleScope $script:moduleName {
            { Get-OERDirectoryRolePolicy -PolicyId 'DirectoryRole_pol1' } | Should -Throw -ExpectedMessage '*Forbidden*'
        }
    }

    It 'rejects an empty string for -PolicyId at parameter binding' {
        InModuleScope $script:moduleName {
            { Get-OERDirectoryRolePolicy -PolicyId '' } | Should -Throw -ExpectedMessage '*empty string*'
        }
    }

    Context 'scope validation: refuses a policy that is not a directory-role policy' {
        It 'throws NotDirectoryRolePolicy for a PIM for Groups policy (scopeType Group)' {
            Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {
                @{ id = 'Group_11111111-1111-1111-1111-111111111111_22222222-2222-2222-2222-222222222222'; scopeId = '33333333-3333-3333-3333-333333333333'; scopeType = 'Group'; rules = @() }
            }
            $Caught = InModuleScope $script:moduleName {
                $Result = $null
                try { Get-OERDirectoryRolePolicy -PolicyId 'Group_11111111-1111-1111-1111-111111111111_22222222-2222-2222-2222-222222222222' } catch { $Result = $PSItem }
                $Result
            }
            $Caught | Should -Not -BeNullOrEmpty
            $Caught.FullyQualifiedErrorId | Should -Match '^NotDirectoryRolePolicy'
            $Caught.Exception.Message | Should -Match 'Get-OERGroupPimPolicy'
            $Caught.Exception.Message | Should -Match 'Set-OERGroupPimPolicy'
        }

        It 'accepts scopeType Directory (the tenant-wide default policy shape)' {
            Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {
                @{ id = 'DirectoryRole_pol1'; scopeId = '/'; scopeType = 'Directory'; rules = @() }
            }
            InModuleScope $script:moduleName {
                { Get-OERDirectoryRolePolicy -PolicyId 'DirectoryRole_pol1' } | Should -Not -Throw
            }
        }

        It 'accepts scopeType DirectoryRole' {
            Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {
                @{ id = 'DirectoryRole_pol1'; scopeId = '/'; scopeType = 'DirectoryRole'; rules = @() }
            }
            InModuleScope $script:moduleName {
                { Get-OERDirectoryRolePolicy -PolicyId 'DirectoryRole_pol1' } | Should -Not -Throw
            }
        }

        It 'accepts scopeType case-insensitively (directoryrole)' {
            Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {
                @{ id = 'DirectoryRole_pol1'; scopeId = '/'; scopeType = 'directoryrole'; rules = @() }
            }
            InModuleScope $script:moduleName {
                { Get-OERDirectoryRolePolicy -PolicyId 'DirectoryRole_pol1' } | Should -Not -Throw
            }
        }

        It 'throws NotDirectoryRolePolicy when scopeType is missing from the response' {
            Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {
                @{ id = 'DirectoryRole_pol1'; scopeId = '/'; rules = @() }
            }
            InModuleScope $script:moduleName {
                { Get-OERDirectoryRolePolicy -PolicyId 'DirectoryRole_pol1' } | Should -Throw -ErrorId 'NotDirectoryRolePolicy'
            }
        }

        It 'throws NotDirectoryRolePolicy when scopeId is not the tenant root' {
            Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {
                @{ id = 'DirectoryRole_pol1'; scopeId = '33333333-3333-3333-3333-333333333333'; scopeType = 'DirectoryRole'; rules = @() }
            }
            InModuleScope $script:moduleName {
                { Get-OERDirectoryRolePolicy -PolicyId 'DirectoryRole_pol1' } | Should -Throw -ErrorId 'NotDirectoryRolePolicy'
            }
        }
    }
}
