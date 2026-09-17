BeforeAll {
    $script:moduleName = 'Omnicit.EntraRBAC'
    Get-Module $script:moduleName | Remove-Module -Force -ErrorAction SilentlyContinue
    Import-Module $script:moduleName -Force -ErrorAction Stop
}

Describe 'Get-OERAuthenticationContext' {
    BeforeEach {
        InModuleScope $script:moduleName { $script:_OERAuthState = $null }
        Mock -ModuleName $script:moduleName Initialize-OERAuth {}
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {
            @{ value = @(
                    @{ id = 'c1'; displayName = 'Require MFA'; description = 'a'; isAvailable = $true }
                    @{ id = 'c2'; displayName = 'Privileged'; description = 'b'; isAvailable = $false }
                ) }
        }
    }

    It 'reads the v1.0 conditional access endpoint' {
        $null = Get-OERAuthenticationContext
        Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Exactly 1 -ParameterFilter {
            $Uri -like '*identity/conditionalAccess/authenticationContextClassReferences*'
        }
    }

    It 'returns every context tagged' {
        $R = @(Get-OERAuthenticationContext)
        $R.Count | Should -Be 2
        $R[0].PSObject.TypeNames[0] | Should -Be 'Omnicit.EntraRBAC.AuthenticationContext'
    }

    It 'filters to a single id' {
        $R = @(Get-OERAuthenticationContext -Id 'c2')
        $R.Count | Should -Be 1
        $R[0].AuthenticationContextId | Should -Be 'c2'
    }

    It 'filters to published contexts with -Available' {
        $R = @(Get-OERAuthenticationContext -Available)
        $R.Count | Should -Be 1
        $R[0].AuthenticationContextId | Should -Be 'c1'
    }

    It 'returns nothing when the tenant has no contexts' {
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest { @{ value = @() } }
        @(Get-OERAuthenticationContext).Count | Should -Be 0
    }

    It 'writes a non-terminating error when Graph fails' {
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest { throw 'boom' }
        $Err = $null
        Get-OERAuthenticationContext -ErrorVariable Err -ErrorAction SilentlyContinue | Out-Null
        $Err | Should -Not -BeNullOrEmpty
        # PowerShell auto-records the mock's thrown ErrorRecord into -ErrorVariable at roughly a
        # dozen call boundaries before this cmdlet's own catch runs (see
        # docs/development/rationale.md#bearer-scrub-tests). Check the LAST entry -- the cmdlet's
        # own Write-CmdletError call -- not the first, which is always the raw mocked exception.
        $Err[-1].FullyQualifiedErrorId | Should -Match 'AuthenticationContextReadFailed'
    }
}
