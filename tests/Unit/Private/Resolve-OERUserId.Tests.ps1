BeforeAll {
    $script:moduleName = 'Omnicit.EntraRBAC'
    Get-Module $script:moduleName | Remove-Module -Force -ErrorAction SilentlyContinue
    Import-Module $script:moduleName -Force -ErrorAction Stop
}

Describe 'Resolve-OERUserId' {
    It 'returns the Id verbatim when -Id is supplied without a Graph call' {
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {}
        InModuleScope $script:moduleName {
            Resolve-OERUserId -Id '11111111-1111-1111-1111-111111111111' |
                Should -Be '11111111-1111-1111-1111-111111111111'
        }
        Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 0
    }

    It 'returns a GUID UserPrincipalName verbatim without a Graph call' {
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {}
        InModuleScope $script:moduleName {
            Resolve-OERUserId -UserPrincipalName '22222222-2222-2222-2222-222222222222' |
                Should -Be '22222222-2222-2222-2222-222222222222'
        }
        Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 0
    }

    It 'resolves a UserPrincipalName to an id via a filtered users query' {
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {
            @{ value = @(@{ id = 'uid-1'; userPrincipalName = 'anna.berg@contoso.com' }) }
        }
        InModuleScope $script:moduleName {
            Resolve-OERUserId -UserPrincipalName 'anna.berg@contoso.com' | Should -Be 'uid-1'
        }
        Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 1 -ParameterFilter {
            # The '@' is percent-encoded (%40) so the value survives transport as a query parameter.
            $Uri -match "userPrincipalName eq 'anna.berg%40contoso.com'"
        }
    }

    It 'percent-encodes the reserved # in a guest (B2B) UserPrincipalName so the filter is not truncated' {
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {
            @{ value = @(@{ id = 'guid-guest'; userPrincipalName = 'person45_example.com#EXT#@contoso.onmicrosoft.com' }) }
        }
        InModuleScope $script:moduleName {
            Resolve-OERUserId -UserPrincipalName 'person45_example.com#EXT#@contoso.onmicrosoft.com' | Should -Be 'guid-guest'
        }
        Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 1 -ParameterFilter {
            # '#' MUST be %23 (it is a URL fragment delimiter); the raw '#' would drop everything after it.
            ($Uri -match 'person45_example\.com%23EXT%23%40contoso\.onmicrosoft\.com') -and ($Uri -notmatch '#')
        }
    }

    It 'returns $null when no user matches the UserPrincipalName' {
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest { @{ value = @() } }
        InModuleScope $script:moduleName {
            Resolve-OERUserId -UserPrincipalName 'nobody@contoso.com' | Should -BeNullOrEmpty
        }
    }

    It 'throws when neither -Id nor -UserPrincipalName is supplied' {
        InModuleScope $script:moduleName {
            { Resolve-OERUserId } | Should -Throw -ExpectedMessage '*-Id or -UserPrincipalName*'
        }
    }

    It 'escapes single quotes in the UserPrincipalName filter' {
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest { @{ value = @() } }
        InModuleScope $script:moduleName { Resolve-OERUserId -UserPrincipalName "o'brien@contoso.com" | Out-Null }
        Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 1 -ParameterFilter {
            # Doubled quote first (''), then percent-encoded ('' -> %27%27, '@' -> %40).
            $Uri -match "o%27%27brien%40contoso.com"
        }
    }
}
