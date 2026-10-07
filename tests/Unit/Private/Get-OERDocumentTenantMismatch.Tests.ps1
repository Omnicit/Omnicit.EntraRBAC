BeforeAll {
    Import-Module Omnicit.EntraRBAC -Force
    . "$PSScriptRoot/../TestHelpers/OERTransportTripwire.ps1"
    Install-OERTransportTripwire
}

AfterAll {
    try { Assert-OERTransportTripwire } finally { Uninstall-OERTransportTripwire }
}

Describe 'Get-OERDocumentTenantMismatch (BL-88, A14)' {
    # The tenants are invented: A is 4444..., B is 7777..., and cccc... is a tenant ID with letters, so
    # a comparison that is not case-insensitive shows. Every case runs in the module scope, where the
    # helper reads $script:_OERAuthState; nothing here signs in or sends.
    BeforeAll {
        $script:DocA = '{ "version": "1.0", "tenantId": "44444444-4444-4444-4444-444444444444", "groups": [] }' | ConvertFrom-Json
        $script:DocLower = '{ "version": "1.0", "tenantId": "cccccccc-cccc-cccc-cccc-cccccccccccc", "groups": [] }' | ConvertFrom-Json
        $script:DocNone = '{ "version": "1.0", "groups": [] }' | ConvertFrom-Json
    }
    BeforeEach {
        InModuleScope Omnicit.EntraRBAC { $script:_OERAuthState = $null }
    }
    AfterAll {
        InModuleScope Omnicit.EntraRBAC { $script:_OERAuthState = $null }
    }

    Context 'a document without tenantId' {
        It 'returns nothing before the sign-in, whatever -TenantId names' {
            InModuleScope Omnicit.EntraRBAC -Parameters @{ Doc = $script:DocNone } {
                param($Doc)
                @(Get-OERDocumentTenantMismatch -Document $Doc -Target 'doc.json' -RequestedTenantId '77777777-7777-7777-7777-777777777777').Count | Should -Be 0
            }
        }

        It 'returns nothing after the sign-in, even when the session holds no state' {
            InModuleScope Omnicit.EntraRBAC -Parameters @{ Doc = $script:DocNone } {
                param($Doc)
                $script:_OERAuthState = $null
                @(Get-OERDocumentTenantMismatch -Document $Doc -Target 'doc.json').Count | Should -Be 0
                @(Get-OERDocumentTenantMismatch -Document $Doc -Target 'doc.json' -IncludeARM).Count | Should -Be 0
            }
        }

        It 'returns nothing after the sign-in when the session is another tenant' {
            InModuleScope Omnicit.EntraRBAC -Parameters @{ Doc = $script:DocNone } {
                param($Doc)
                $script:_OERAuthState = @{ TenantId = '77777777-7777-7777-7777-777777777777'; TokenTenantId = '77777777-7777-7777-7777-777777777777'; ArmTokenTenantId = '77777777-7777-7777-7777-777777777777' }
                @(Get-OERDocumentTenantMismatch -Document $Doc -Target 'doc.json' -IncludeARM).Count | Should -Be 0
            }
        }
    }

    Context 'before the sign-in (-RequestedTenantId)' {
        It 'returns nothing when -TenantId names the document''s tenant in another letter case' {
            InModuleScope Omnicit.EntraRBAC -Parameters @{ Doc = $script:DocLower } {
                param($Doc)
                @(Get-OERDocumentTenantMismatch -Document $Doc -Target 'doc.json' -RequestedTenantId 'CCCCCCCC-CCCC-CCCC-CCCC-CCCCCCCCCCCC').Count | Should -Be 0
            }
        }

        It 'returns one DocumentTenantMismatch record when -TenantId names another tenant ID' {
            InModuleScope Omnicit.EntraRBAC -Parameters @{ Doc = $script:DocA } {
                param($Doc)
                $Records = @(Get-OERDocumentTenantMismatch -Document $Doc -Target 'C:\docs\a.json' -RequestedTenantId '77777777-7777-7777-7777-777777777777')
                $Records.Count | Should -Be 1
                $Records[0] | Should -BeOfType [System.Management.Automation.ErrorRecord]
                $Records[0].FullyQualifiedErrorId | Should -BeExactly 'DocumentTenantMismatch'
                $Records[0].CategoryInfo.Category | Should -Be ([System.Management.Automation.ErrorCategory]::InvalidOperation)
                $Records[0].TargetObject | Should -BeExactly 'C:\docs\a.json'
                $Message = $Records[0].Exception.Message
                $Message | Should -BeLike "*names tenant '44444444-4444-4444-4444-444444444444', but -TenantId names tenant '77777777-7777-7777-7777-777777777777'.*"
                $Message | Should -BeLike '*nothing was signed in to, read or written for this document*'
                $Message | Should -Not -Match 'eyJ'
            }
        }

        It 'returns nothing when -TenantId is a domain, organizations or a braced tenant ID: those are compared after the sign-in' {
            InModuleScope Omnicit.EntraRBAC -Parameters @{ Doc = $script:DocA } {
                param($Doc)
                foreach ($Requested in @('contoso.onmicrosoft.com', 'organizations', '{77777777-7777-7777-7777-777777777777}')) {
                    @(Get-OERDocumentTenantMismatch -Document $Doc -Target 'doc.json' -RequestedTenantId $Requested).Count |
                        Should -Be 0 -Because "'$Requested' is not a tenant ID, so it is compared through its token"
                }
            }
        }

        It 'never reads the session state before the sign-in' {
            InModuleScope Omnicit.EntraRBAC -Parameters @{ Doc = $script:DocA } {
                param($Doc)
                # A session of another tenant: the comparison before the sign-in is with -TenantId only.
                $script:_OERAuthState = @{ TenantId = '77777777-7777-7777-7777-777777777777'; TokenTenantId = '77777777-7777-7777-7777-777777777777' }
                @(Get-OERDocumentTenantMismatch -Document $Doc -Target 'doc.json' -RequestedTenantId '44444444-4444-4444-4444-444444444444').Count | Should -Be 0
            }
        }
    }

    Context 'after the sign-in (the session)' {
        It 'refuses when the session holds no state' {
            InModuleScope Omnicit.EntraRBAC -Parameters @{ Doc = $script:DocA } {
                param($Doc)
                $script:_OERAuthState = $null
                $Records = @(Get-OERDocumentTenantMismatch -Document $Doc -Target 'doc.json')
                $Records.Count | Should -Be 1
                $Records[0].FullyQualifiedErrorId | Should -BeExactly 'DocumentTenantMismatch'
                $Records[0].CategoryInfo.Category | Should -Be ([System.Management.Automation.ErrorCategory]::InvalidOperation)
                $Records[0].TargetObject | Should -BeExactly 'doc.json'
                $Records[0].Exception.Message | Should -BeLike "*names tenant '44444444-4444-4444-4444-444444444444', but the session holds no Microsoft Graph token whose tenant can be compared with it.*"
                $Records[0].Exception.Message | Should -BeLike '*nothing was read or written for this document*'
                $Records[0].Exception.Message | Should -Not -BeLike '*signed in to*'
            }
        }

        It 'refuses when the Graph token''s tenant is <Case>' -ForEach @(
            @{ Case = 'absent'; Granted = $null }
            @{ Case = 'not a tenant ID'; Granted = 'not-a-guid' }
        ) {
            InModuleScope Omnicit.EntraRBAC -Parameters @{ Doc = $script:DocA; Granted = $Granted } {
                param($Doc, $Granted)
                $script:_OERAuthState = @{ TenantId = '44444444-4444-4444-4444-444444444444'; TokenTenantId = $Granted }
                $Records = @(Get-OERDocumentTenantMismatch -Document $Doc -Target 'doc.json')
                $Records.Count | Should -Be 1
                $Records[0].FullyQualifiedErrorId | Should -BeExactly 'DocumentTenantMismatch'
                $Records[0].Exception.Message | Should -BeLike '*the session holds no Microsoft Graph token whose tenant can be compared with it*'
            }
        }

        It 'refuses, naming both tenants, when the Graph token was issued for another tenant' {
            InModuleScope Omnicit.EntraRBAC -Parameters @{ Doc = $script:DocA } {
                param($Doc)
                $script:_OERAuthState = @{ TenantId = '77777777-7777-7777-7777-777777777777'; TokenTenantId = '77777777-7777-7777-7777-777777777777' }
                $Records = @(Get-OERDocumentTenantMismatch -Document $Doc -Target 'doc.json')
                $Records.Count | Should -Be 1
                $Message = $Records[0].Exception.Message
                $Message | Should -BeLike "The structure document names tenant '44444444-4444-4444-4444-444444444444', but the session's Microsoft Graph token was issued for tenant '77777777-7777-7777-7777-777777777777'. *"
                $Message | Should -BeLike '*Name that tenant with -TenantId, or, to use the document as a template for another tenant, change or remove its tenantId.'
                $Message | Should -Not -Match 'eyJ'
            }
        }

        It 'returns nothing when the Graph token was issued for the document''s tenant in another letter case' {
            InModuleScope Omnicit.EntraRBAC -Parameters @{ Doc = $script:DocLower } {
                param($Doc)
                $script:_OERAuthState = @{ TenantId = 'contoso.onmicrosoft.com'; TokenTenantId = 'CCCCCCCC-CCCC-CCCC-CCCC-CCCCCCCCCCCC' }
                @(Get-OERDocumentTenantMismatch -Document $Doc -Target 'doc.json').Count | Should -Be 0
            }
        }

        It 'compares the GRANTED tenant, never the tenant as named: a named tenant equal to the document''s does not pass when the token differs' {
            InModuleScope Omnicit.EntraRBAC -Parameters @{ Doc = $script:DocA } {
                param($Doc)
                $script:_OERAuthState = @{ TenantId = '44444444-4444-4444-4444-444444444444'; TokenTenantId = '77777777-7777-7777-7777-777777777777' }
                $Records = @(Get-OERDocumentTenantMismatch -Document $Doc -Target 'doc.json')
                $Records.Count | Should -Be 1
                $Records[0].Exception.Message | Should -BeLike "*the session's Microsoft Graph token was issued for tenant '77777777-7777-7777-7777-777777777777'*"
            }
        }

        It 'returns nothing with -IncludeARM when both tokens were issued for the document''s tenant' {
            InModuleScope Omnicit.EntraRBAC -Parameters @{ Doc = $script:DocA } {
                param($Doc)
                $script:_OERAuthState = @{ TokenTenantId = '44444444-4444-4444-4444-444444444444'; ArmTokenTenantId = '44444444-4444-4444-4444-444444444444' }
                @(Get-OERDocumentTenantMismatch -Document $Doc -Target 'doc.json' -IncludeARM).Count | Should -Be 0
            }
        }

        It 'refuses with -IncludeARM, naming the ARM tenant, when the Azure Resource Manager token was issued for another tenant' {
            InModuleScope Omnicit.EntraRBAC -Parameters @{ Doc = $script:DocA } {
                param($Doc)
                $script:_OERAuthState = @{ TokenTenantId = '44444444-4444-4444-4444-444444444444'; ArmTokenTenantId = '77777777-7777-7777-7777-777777777777' }
                $Records = @(Get-OERDocumentTenantMismatch -Document $Doc -Target 'doc.json' -IncludeARM)
                $Records.Count | Should -Be 1
                $Records[0].FullyQualifiedErrorId | Should -BeExactly 'DocumentTenantMismatch'
                $Records[0].Exception.Message | Should -BeLike "*names tenant '44444444-4444-4444-4444-444444444444', but the session's Azure Resource Manager token was issued for tenant '77777777-7777-7777-7777-777777777777'.*"
                $Records[0].Exception.Message | Should -Not -Match 'eyJ'
            }
        }

        It 'refuses with -IncludeARM when the session holds no ARM token tenant' {
            InModuleScope Omnicit.EntraRBAC -Parameters @{ Doc = $script:DocA } {
                param($Doc)
                $script:_OERAuthState = @{ TokenTenantId = '44444444-4444-4444-4444-444444444444'; ArmTokenTenantId = $null }
                $Records = @(Get-OERDocumentTenantMismatch -Document $Doc -Target 'doc.json' -IncludeARM)
                $Records.Count | Should -Be 1
                $Records[0].Exception.Message | Should -BeLike '*the session holds no Azure Resource Manager token whose tenant can be compared with it*'
            }
        }

        It 'does not compare the ARM token without -IncludeARM' {
            InModuleScope Omnicit.EntraRBAC -Parameters @{ Doc = $script:DocA } {
                param($Doc)
                $script:_OERAuthState = @{ TokenTenantId = '44444444-4444-4444-4444-444444444444'; ArmTokenTenantId = '77777777-7777-7777-7777-777777777777' }
                @(Get-OERDocumentTenantMismatch -Document $Doc -Target 'doc.json').Count | Should -Be 0
            }
        }

        It 'never puts a token in the message, whatever the state carries' {
            InModuleScope Omnicit.EntraRBAC -Parameters @{ Doc = $script:DocA } {
                param($Doc)
                $script:_OERAuthState = @{
                    TokenTenantId = '77777777-7777-7777-7777-777777777777'; ArmTokenTenantId = '77777777-7777-7777-7777-777777777777'
                    GraphToken = 'eyJ0eXAiOiJKV1QiNOT-A-REAL-TOKEN'; ArmToken = 'eyJ0eXAiOiJKV1QiNOT-A-REAL-TOKEN'
                }
                $Records = @(Get-OERDocumentTenantMismatch -Document $Doc -Target 'doc.json' -IncludeARM)
                $Records.Count | Should -Be 1
                $Records[0].Exception.Message | Should -Not -Match 'eyJ'
                $Records[0].Exception.Message | Should -Not -Match 'NOT-A-REAL-TOKEN'
            }
        }
    }
}
