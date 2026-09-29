BeforeAll {
    Import-Module Omnicit.EntraRBAC -Force

    # Builds a JWT-shaped string at run time only -- never a literal starting 'eyJ' in this tracked
    # file. The signature segment is deliberately not a real signature; nothing here checks one.
    function New-TestToken {
        param([hashtable]$Claims)
        $Encode = {
            param([string]$Json)
            [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($Json)).TrimEnd('=').Replace('+', '-').Replace('/', '_')
        }
        $Header = & $Encode (@{ alg = 'none'; typ = 'JWT' } | ConvertTo-Json -Compress)
        $Payload = & $Encode ($Claims | ConvertTo-Json -Compress)
        "$Header.$Payload.NOT-A-REAL-TOKEN"
    }

    # The helper takes the token as a SecureString (Initialize-OERAuth passes the one it hands to
    # Connect-MgGraph), so every case converts its runtime-built text here.
    function ConvertTo-TestSecureToken {
        param([string]$TokenText)
        ConvertTo-SecureString -String $TokenText -AsPlainText -Force
    }
}

Describe 'Get-OERTokenObjectId' {
    It 'declares -Token as a SecureString, so module logging records no plaintext token' {
        # PowerShell module logging (Event 4103) records every bound parameter value. A [string]
        # -Token would log the live Graph token on every sign-in; a SecureString logs its type name.
        InModuleScope Omnicit.EntraRBAC {
            (Get-Command Get-OERTokenObjectId).Parameters['Token'].ParameterType |
                Should -Be ([securestring])
        }
    }

    It 'refuses a plain string for -Token instead of binding it' {
        $TokenText = New-TestToken -Claims @{ oid = 'aaaaaaaa-0000-0000-0000-000000000001' }
        InModuleScope Omnicit.EntraRBAC -Parameters @{ TokenText = $TokenText } {
            param($TokenText)
            { Get-OERTokenObjectId -Token $TokenText } | Should -Throw -ErrorId 'ParameterArgumentTransformationError,Get-OERTokenObjectId'
        }
    }

    It 'reads the oid claim from a delegated-shaped token, lower-cased' {
        $Token = ConvertTo-TestSecureToken (New-TestToken -Claims @{
                oid   = 'AAAAAAAA-0000-0000-0000-000000000001'
                scp   = 'RoleManagement.ReadWrite.Directory'
                upn   = 'person1@example.com'
                idtyp = 'user'
            })
        InModuleScope Omnicit.EntraRBAC -Parameters @{ Token = $Token } {
            param($Token)
            Get-OERTokenObjectId -Token $Token | Should -BeExactly 'aaaaaaaa-0000-0000-0000-000000000001'
        }
    }

    It 'reads the oid claim from an app-only-shaped token (no scp, no upn)' {
        $Token = ConvertTo-TestSecureToken (New-TestToken -Claims @{
                oid   = 'aaaaaaaa-0000-0000-0000-000000000002'
                roles = @('RoleManagement.ReadWrite.Directory')
                idtyp = 'app'
                appid = '11111111-1111-1111-1111-111111111111'
            })
        InModuleScope Omnicit.EntraRBAC -Parameters @{ Token = $Token } {
            param($Token)
            Get-OERTokenObjectId -Token $Token | Should -BeExactly 'aaaaaaaa-0000-0000-0000-000000000002'
        }
    }

    It 'leaves the caller''s SecureString usable (it is not disposed or emptied)' {
        $Token = ConvertTo-TestSecureToken (New-TestToken -Claims @{ oid = 'aaaaaaaa-0000-0000-0000-000000000001' })
        $LengthBefore = $Token.Length
        InModuleScope Omnicit.EntraRBAC -Parameters @{ Token = $Token } {
            param($Token)
            Get-OERTokenObjectId -Token $Token | Out-Null
        }
        $Token.Length | Should -Be $LengthBefore
    }

    It 'returns $null when the payload has no oid claim' {
        $Token = ConvertTo-TestSecureToken (New-TestToken -Claims @{ scp = 'RoleManagement.ReadWrite.Directory' })
        InModuleScope Omnicit.EntraRBAC -Parameters @{ Token = $Token } {
            param($Token)
            Get-OERTokenObjectId -Token $Token | Should -BeNullOrEmpty
        }
    }

    It 'returns $null when the oid claim is not a GUID' {
        $Token = ConvertTo-TestSecureToken (New-TestToken -Claims @{ oid = 'not-a-guid' })
        InModuleScope Omnicit.EntraRBAC -Parameters @{ Token = $Token } {
            param($Token)
            Get-OERTokenObjectId -Token $Token | Should -BeNullOrEmpty
        }
    }

    It 'returns $null for $null, without throwing' {
        InModuleScope Omnicit.EntraRBAC {
            { Get-OERTokenObjectId -Token $null } | Should -Not -Throw
            Get-OERTokenObjectId -Token $null | Should -BeNullOrEmpty
        }
    }

    It 'returns $null for an empty SecureString, without throwing' {
        InModuleScope Omnicit.EntraRBAC {
            $Empty = [securestring]::new()
            { Get-OERTokenObjectId -Token $Empty } | Should -Not -Throw
            Get-OERTokenObjectId -Token $Empty | Should -BeNullOrEmpty
        }
    }

    It 'returns $null for a disposed SecureString, without throwing' {
        $Token = ConvertTo-TestSecureToken (New-TestToken -Claims @{ oid = 'aaaaaaaa-0000-0000-0000-000000000001' })
        $Token.Dispose()
        InModuleScope Omnicit.EntraRBAC -Parameters @{ Token = $Token } {
            param($Token)
            { Get-OERTokenObjectId -Token $Token } | Should -Not -Throw
            Get-OERTokenObjectId -Token $Token | Should -BeNullOrEmpty
        }
    }

    It 'returns $null for a two-segment value, without throwing' {
        $Token = ConvertTo-TestSecureToken 'a.b'
        InModuleScope Omnicit.EntraRBAC -Parameters @{ Token = $Token } {
            param($Token)
            { Get-OERTokenObjectId -Token $Token } | Should -Not -Throw
            Get-OERTokenObjectId -Token $Token | Should -BeNullOrEmpty
        }
    }

    It 'returns $null for a plain non-token value, without throwing' {
        $Token = ConvertTo-TestSecureToken 'not-a-token'
        InModuleScope Omnicit.EntraRBAC -Parameters @{ Token = $Token } {
            param($Token)
            { Get-OERTokenObjectId -Token $Token } | Should -Not -Throw
            Get-OERTokenObjectId -Token $Token | Should -BeNullOrEmpty
        }
    }

    It 'returns $null when the payload segment is not valid base64, without throwing' {
        $Token = ConvertTo-TestSecureToken 'header.!!!not-base64!!!.NOT-A-REAL-TOKEN'
        InModuleScope Omnicit.EntraRBAC -Parameters @{ Token = $Token } {
            param($Token)
            { Get-OERTokenObjectId -Token $Token } | Should -Not -Throw
            Get-OERTokenObjectId -Token $Token | Should -BeNullOrEmpty
        }
    }

    It 'returns $null when the decoded payload is not JSON, without throwing' {
        $NotJson = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes('not-json-at-all')).TrimEnd('=').Replace('+', '-').Replace('/', '_')
        $Token = ConvertTo-TestSecureToken "header.$NotJson.NOT-A-REAL-TOKEN"
        InModuleScope Omnicit.EntraRBAC -Parameters @{ Token = $Token } {
            param($Token)
            { Get-OERTokenObjectId -Token $Token } | Should -Not -Throw
            Get-OERTokenObjectId -Token $Token | Should -BeNullOrEmpty
        }
    }

    It 'never writes the token text to output or the Verbose stream' {
        $Token = ConvertTo-TestSecureToken (New-TestToken -Claims @{ oid = 'aaaaaaaa-0000-0000-0000-000000000001' })
        $AllOutput = InModuleScope Omnicit.EntraRBAC -Parameters @{ Token = $Token } {
            param($Token)
            Get-OERTokenObjectId -Token $Token -Verbose
        } 4>&1
        ($AllOutput | Out-String) | Should -Not -Match 'NOT-A-REAL-TOKEN'
    }
}
