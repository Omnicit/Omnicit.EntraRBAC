BeforeAll {
    Import-Module Omnicit.EntraRBAC -Force

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
}

Describe 'Get-OERTokenObjectId' {
    It 'reads the oid claim from a delegated-shaped token, lower-cased' {
        $Token = New-TestToken -Claims @{
            oid   = 'AAAAAAAA-0000-0000-0000-000000000001'
            scp   = 'RoleManagement.ReadWrite.Directory'
            upn   = 'person1@example.com'
            idtyp = 'user'
        }
        InModuleScope Omnicit.EntraRBAC -Parameters @{ Token = $Token } {
            param($Token)
            Get-OERTokenObjectId -Token $Token | Should -BeExactly 'aaaaaaaa-0000-0000-0000-000000000001'
        }
    }

    It 'reads the oid claim from an app-only-shaped token (no scp, no upn)' {
        $Token = New-TestToken -Claims @{
            oid   = 'aaaaaaaa-0000-0000-0000-000000000002'
            roles = @('RoleManagement.ReadWrite.Directory')
            idtyp = 'app'
            appid = '11111111-1111-1111-1111-111111111111'
        }
        InModuleScope Omnicit.EntraRBAC -Parameters @{ Token = $Token } {
            param($Token)
            Get-OERTokenObjectId -Token $Token | Should -BeExactly 'aaaaaaaa-0000-0000-0000-000000000002'
        }
    }

    It 'returns $null when the payload has no oid claim' {
        $Token = New-TestToken -Claims @{ scp = 'RoleManagement.ReadWrite.Directory' }
        InModuleScope Omnicit.EntraRBAC -Parameters @{ Token = $Token } {
            param($Token)
            Get-OERTokenObjectId -Token $Token | Should -BeNullOrEmpty
        }
    }

    It 'returns $null when the oid claim is not a GUID' {
        $Token = New-TestToken -Claims @{ oid = 'not-a-guid' }
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

    It 'returns $null for an empty string, without throwing' {
        InModuleScope Omnicit.EntraRBAC {
            { Get-OERTokenObjectId -Token '' } | Should -Not -Throw
            Get-OERTokenObjectId -Token '' | Should -BeNullOrEmpty
        }
    }

    It 'returns $null for a two-segment string, without throwing' {
        InModuleScope Omnicit.EntraRBAC {
            { Get-OERTokenObjectId -Token 'a.b' } | Should -Not -Throw
            Get-OERTokenObjectId -Token 'a.b' | Should -BeNullOrEmpty
        }
    }

    It 'returns $null for a plain non-token string, without throwing' {
        InModuleScope Omnicit.EntraRBAC {
            { Get-OERTokenObjectId -Token 'not-a-token' } | Should -Not -Throw
            Get-OERTokenObjectId -Token 'not-a-token' | Should -BeNullOrEmpty
        }
    }

    It 'returns $null when the payload segment is not valid base64, without throwing' {
        InModuleScope Omnicit.EntraRBAC {
            { Get-OERTokenObjectId -Token 'header.!!!not-base64!!!.NOT-A-REAL-TOKEN' } | Should -Not -Throw
            Get-OERTokenObjectId -Token 'header.!!!not-base64!!!.NOT-A-REAL-TOKEN' | Should -BeNullOrEmpty
        }
    }

    It 'returns $null when the decoded payload is not JSON, without throwing' {
        $NotJson = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes('not-json-at-all')).TrimEnd('=').Replace('+', '-').Replace('/', '_')
        $Token = "header.$NotJson.NOT-A-REAL-TOKEN"
        InModuleScope Omnicit.EntraRBAC -Parameters @{ Token = $Token } {
            param($Token)
            { Get-OERTokenObjectId -Token $Token } | Should -Not -Throw
            Get-OERTokenObjectId -Token $Token | Should -BeNullOrEmpty
        }
    }

    It 'never writes the token text to output or the Verbose stream' {
        $Token = New-TestToken -Claims @{ oid = 'aaaaaaaa-0000-0000-0000-000000000001' }
        $AllOutput = InModuleScope Omnicit.EntraRBAC -Parameters @{ Token = $Token } {
            param($Token)
            Get-OERTokenObjectId -Token $Token -Verbose
        } 4>&1
        ($AllOutput | Out-String) | Should -Not -Match 'NOT-A-REAL-TOKEN'
    }
}
