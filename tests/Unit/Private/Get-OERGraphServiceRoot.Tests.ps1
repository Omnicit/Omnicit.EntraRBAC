BeforeAll {
    Import-Module Omnicit.EntraRBAC -Force
}

Describe 'Get-OERGraphServiceRoot' {
    AfterEach {
        InModuleScope Omnicit.EntraRBAC { $script:_OERAuthState = $null }
    }

    It 'returns the Global service root when there is no session' {
        InModuleScope Omnicit.EntraRBAC {
            $script:_OERAuthState = $null
            Get-OERGraphServiceRoot | Should -BeExactly 'https://graph.microsoft.com/v1.0'
        }
    }

    It 'returns the Global service root when the cached state carries no Environment' {
        InModuleScope Omnicit.EntraRBAC {
            $script:_OERAuthState = @{ TenantId = 'contoso.onmicrosoft.com' }
            Get-OERGraphServiceRoot | Should -BeExactly 'https://graph.microsoft.com/v1.0'
        }
    }

    It 'returns the session cloud''s service root for <_>' -ForEach @('Global', 'USGov', 'USGovDoD', 'China') {
        $Cloud = $_
        InModuleScope Omnicit.EntraRBAC -Parameters @{ Cloud = $Cloud } {
            param($Cloud)
            $script:_OERAuthState = @{ TenantId = 'contoso.onmicrosoft.com'; Environment = $Cloud }
            $Expected = (Get-OERCloudEndpoint -Environment $Cloud).GraphServiceRoot
            Get-OERGraphServiceRoot | Should -BeExactly $Expected
        }
    }

    It 'makes no Graph or ARM call' {
        InModuleScope Omnicit.EntraRBAC {
            $script:_OERAuthState = @{ TenantId = 'contoso.onmicrosoft.com'; Environment = 'USGov' }
            Mock Invoke-OERGraphRequest { throw 'should not be called' }
            Mock Invoke-OERArmRequest { throw 'should not be called' }
            Mock Get-AzToken { throw 'should not be called' }
            $null = Get-OERGraphServiceRoot
            Should -Invoke Invoke-OERGraphRequest -Times 0 -Exactly
            Should -Invoke Invoke-OERArmRequest -Times 0 -Exactly
            Should -Invoke Get-AzToken -Times 0 -Exactly
        }
    }
}
