BeforeAll {
    $script:moduleName = 'Omnicit.EntraRBAC'
    Get-Module $script:moduleName | Remove-Module -Force -ErrorAction SilentlyContinue
    Import-Module $script:moduleName -Force -ErrorAction Stop
}

Describe 'Add-OERGroupMember' {
    BeforeEach {
        InModuleScope $script:moduleName { $script:_OERAuthState = $null }
        Mock -ModuleName $script:moduleName Initialize-OERAuth {}
        Mock -ModuleName $script:moduleName Resolve-OERGroupId { param($DisplayName) $DisplayName }
    }

    It 'adds a member via the members/$ref endpoint' {
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {}
        Add-OERGroupMember -Group 'gid-1' -PrincipalId '11111111-1111-1111-1111-111111111111'
        Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 1 -ParameterFilter {
            $Method -eq 'POST' -and $Uri -eq 'v1.0/groups/gid-1/members/$ref' -and
            $Body.'@odata.id' -match 'directoryObjects/11111111-1111-1111-1111-111111111111'
        }
    }

    It 'adds an owner when -AccessType owner is used' {
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {}
        Add-OERGroupMember -Group 'gid-1' -PrincipalId '22222222-2222-2222-2222-222222222222' -AccessType owner
        Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 1 -ParameterFilter {
            $Method -eq 'POST' -and $Uri -eq 'v1.0/groups/gid-1/owners/$ref'
        }
    }

    It 'processes multiple principals' {
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {}
        Add-OERGroupMember -Group 'gid-1' -PrincipalId '11111111-1111-1111-1111-111111111111', '22222222-2222-2222-2222-222222222222', '33333333-3333-3333-3333-333333333333'
        Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 3 -ParameterFilter { $Method -eq 'POST' }
    }

    It 'does not POST under -WhatIf' {
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {}
        Add-OERGroupMember -Group 'gid-1' -PrincipalId '11111111-1111-1111-1111-111111111111' -WhatIf
        Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 0 -ParameterFilter { $Method -eq 'POST' }
    }

    It 'keeps POSTing the remaining principals after one principals Graph POST fails' {
        # Add-OERGroupMember.ps1:149-153 is a catch { Remove-OERErrorRecord; WriteError; continue }
        # inside the foreach over principals. The existing partial-failure test only drives the
        # GUID guard at :137-142, so this Graph-side continue has never run under test.
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {} -ParameterFilter {
            $Body['@odata.id'] -notmatch '22222222'
        }
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {
            throw [System.Management.Automation.ErrorRecord]::new(
                [System.Exception]::new('Request_BadRequest: One or more added object references already exist.'),
                'Request_BadRequest',
                [System.Management.Automation.ErrorCategory]::InvalidOperation,
                $null)
        } -ParameterFilter { $Body['@odata.id'] -match '22222222' }
        Mock -ModuleName $script:moduleName Remove-OERErrorRecord { }

        $Err = $null
        Add-OERGroupMember -Group 'gid-1' -PrincipalId `
            '11111111-1111-1111-1111-111111111111', `
            '22222222-2222-2222-2222-222222222222', `
            '33333333-3333-3333-3333-333333333333' `
            -Confirm:$false -ErrorAction SilentlyContinue -ErrorVariable Err

        # Count only the cmdlet's OWN record. -ErrorVariable also collects a dozen
        # PowerShell-auto-recorded pass-throughs of the mock's throw, each carrying the BARE
        # 'Request_BadRequest' id, so neither @($Err).Count nor a bare-code -Match can
        # distinguish "the cmdlet wrote one error" from "the cmdlet swallowed it silently".
        @($Err | Where-Object { $_.FullyQualifiedErrorId -eq 'Request_BadRequest,Add-OERGroupMember' }).Count |
            Should -Be 1
        Should -Invoke -ModuleName $script:moduleName Remove-OERErrorRecord -Times 1
        Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 1 -ParameterFilter {
            $Body['@odata.id'] -match '11111111'
        }
        Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 1 -ParameterFilter {
            $Body['@odata.id'] -match '33333333'
        }
    }

    It 'round-trips a piped GroupMember object: GroupId->-Group, PrincipalId->-PrincipalId and POST targets the group and principal' {
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {}
        $Member = [pscustomobject]@{
            Id          = '44444444-4444-4444-4444-444444444444'
            DisplayName = 'Anna'
            GroupId     = 'GROUP'
            MemberType  = 'Member'
            PrincipalId = '44444444-4444-4444-4444-444444444444'
        }
        $Member | Add-OERGroupMember
        Should -Invoke -ModuleName $script:moduleName Resolve-OERGroupId -Times 1 -ParameterFilter {
            $DisplayName -eq 'GROUP'
        }
        Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 1 -ParameterFilter {
            $Method -eq 'POST' -and $Uri -eq 'v1.0/groups/GROUP/members/$ref' -and
            $Body.'@odata.id' -match 'directoryObjects/44444444-4444-4444-4444-444444444444'
        }
    }

    It 'piped owner object routes to the owners collection via -AccessType binding' {
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {}
        $Owner = [pscustomobject]@{
            Id          = '55555555-5555-5555-5555-555555555555'
            DisplayName = 'Bob'
            GroupId     = 'GROUP'
            MemberType  = 'Owner'
            PrincipalId = '55555555-5555-5555-5555-555555555555'
        }
        $Owner | Add-OERGroupMember
        Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 1 -ParameterFilter {
            $Method -eq 'POST' -and $Uri -eq 'v1.0/groups/GROUP/owners/$ref'
        }
    }

    It 'back-compat: explicit -Id alias still resolves the group' {
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {}
        Add-OERGroupMember -Id 'gid-1' -PrincipalId '11111111-1111-1111-1111-111111111111'
        Should -Invoke -ModuleName $script:moduleName Resolve-OERGroupId -Times 1 -ParameterFilter {
            $DisplayName -eq 'gid-1'
        }
        Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 1 -ParameterFilter {
            $Method -eq 'POST' -and $Uri -like '*gid-1/members/*'
        }
    }

    It 'binds the third positional argument to -AccessType (positional back-compat)' {
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {}
        Add-OERGroupMember 'gggg0000-0000-0000-0000-00000000000a' 'aaaa0000-0000-0000-0000-000000000001' 'owner' -Confirm:$false
        Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 1 -ParameterFilter {
            $Method -eq 'POST' -and $Uri -eq 'v1.0/groups/gggg0000-0000-0000-0000-00000000000a/owners/$ref' -and
            $Body.'@odata.id' -match 'directoryObjects/aaaa0000-0000-0000-0000-000000000001'
        }
    }

    It 'back-compat: explicit -DisplayName alias still resolves the group by name' {
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {}
        Add-OERGroupMember -DisplayName 'role_sec_identity_administrator' -PrincipalId '11111111-1111-1111-1111-111111111111'
        Should -Invoke -ModuleName $script:moduleName Resolve-OERGroupId -Times 1 -ParameterFilter {
            $DisplayName -eq 'role_sec_identity_administrator'
        }
    }

    Context 'friendly principal input' {
        BeforeEach {
            InModuleScope Omnicit.EntraRBAC { $script:_OERAuthState = $null }
            Mock -ModuleName Omnicit.EntraRBAC Initialize-OERAuth { }
            Mock -ModuleName Omnicit.EntraRBAC Resolve-OERGroupId { 'gggg0000-0000-0000-0000-00000000000a' }
            Mock -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest { }
        }

        It 'resolves -User to an object id and posts it to members/$ref' {
            Mock -ModuleName Omnicit.EntraRBAC Resolve-OERPrincipal {
                [PSCustomObject]@{ PrincipalId = 'bbbb0000-0000-0000-0000-000000000002'; PrincipalType = 'User' }
            }
            Add-OERGroupMember -Group 'role_sec_team' -User 'anna.berg@contoso.com' -Confirm:$false
            Should -Invoke Invoke-OERGraphRequest -ModuleName Omnicit.EntraRBAC -Times 1 -ParameterFilter {
                $Method -eq 'POST' -and
                $Uri -eq 'v1.0/groups/gggg0000-0000-0000-0000-00000000000a/members/$ref' -and
                $Body['@odata.id'] -eq 'https://graph.microsoft.com/v1.0/directoryObjects/bbbb0000-0000-0000-0000-000000000002'
            }
        }

        It 'resolves -GroupPrincipal and routes -AccessType owner to owners/$ref' {
            Mock -ModuleName Omnicit.EntraRBAC Resolve-OERPrincipal {
                [PSCustomObject]@{ PrincipalId = 'cccc0000-0000-0000-0000-000000000003'; PrincipalType = 'Group' }
            }
            Add-OERGroupMember -Group 'role_sec_team' -GroupPrincipal 'Sales Team' -AccessType owner -Confirm:$false
            Should -Invoke Invoke-OERGraphRequest -ModuleName Omnicit.EntraRBAC -Times 1 -ParameterFilter {
                $Uri -eq 'v1.0/groups/gggg0000-0000-0000-0000-00000000000a/owners/$ref' -and
                $Body['@odata.id'] -eq 'https://graph.microsoft.com/v1.0/directoryObjects/cccc0000-0000-0000-0000-000000000003'
            }
        }

        It 'resolves -ServicePrincipal to an object id and posts it to members/$ref' {
            Mock -ModuleName Omnicit.EntraRBAC Resolve-OERPrincipal {
                [PSCustomObject]@{ PrincipalId = 'dddd0000-0000-0000-0000-000000000004'; PrincipalType = 'ServicePrincipal' }
            }
            Add-OERGroupMember -Group 'role_sec_team' -ServicePrincipal 'Contoso App' -Confirm:$false
            Should -Invoke Resolve-OERPrincipal -ModuleName Omnicit.EntraRBAC -Times 1 -ParameterFilter {
                $ServicePrincipal -eq 'Contoso App'
            }
            Should -Invoke Invoke-OERGraphRequest -ModuleName Omnicit.EntraRBAC -Times 1 -ParameterFilter {
                $Method -eq 'POST' -and
                $Uri -eq 'v1.0/groups/gggg0000-0000-0000-0000-00000000000a/members/$ref' -and
                $Body['@odata.id'] -eq 'https://graph.microsoft.com/v1.0/directoryObjects/dddd0000-0000-0000-0000-000000000004'
            }
        }

        It 'unions -PrincipalId, -User and -GroupPrincipal into one call per principal, each with its own distinct id' {
            Mock -ModuleName Omnicit.EntraRBAC Resolve-OERPrincipal {
                if ($User) { [PSCustomObject]@{ PrincipalId = 'bbbb0000-0000-0000-0000-000000000002'; PrincipalType = 'User' } }
                else { [PSCustomObject]@{ PrincipalId = 'cccc0000-0000-0000-0000-000000000003'; PrincipalType = 'Group' } }
            }
            Add-OERGroupMember -Group 'role_sec_team' `
                -PrincipalId 'aaaa0000-0000-0000-0000-000000000001' `
                -User 'anna.berg@contoso.com' -GroupPrincipal 'Sales Team' -Confirm:$false
            Should -Invoke Invoke-OERGraphRequest -ModuleName Omnicit.EntraRBAC -Times 3 -ParameterFilter {
                $Method -eq 'POST'
            }
            Should -Invoke Invoke-OERGraphRequest -ModuleName Omnicit.EntraRBAC -Times 1 -ParameterFilter {
                $Body['@odata.id'] -eq 'https://graph.microsoft.com/v1.0/directoryObjects/aaaa0000-0000-0000-0000-000000000001'
            }
            Should -Invoke Invoke-OERGraphRequest -ModuleName Omnicit.EntraRBAC -Times 1 -ParameterFilter {
                $Body['@odata.id'] -eq 'https://graph.microsoft.com/v1.0/directoryObjects/bbbb0000-0000-0000-0000-000000000002'
            }
            Should -Invoke Invoke-OERGraphRequest -ModuleName Omnicit.EntraRBAC -Times 1 -ParameterFilter {
                $Body['@odata.id'] -eq 'https://graph.microsoft.com/v1.0/directoryObjects/cccc0000-0000-0000-0000-000000000003'
            }
        }

        It 'rejects a UPN passed to -PrincipalId with InvalidPrincipalId and does not call Graph' {
            $Err = $null
            Add-OERGroupMember -Group 'role_sec_team' -PrincipalId 'anna.berg@contoso.com' `
                -Confirm:$false -ErrorAction SilentlyContinue -ErrorVariable Err
            $Err[0].FullyQualifiedErrorId | Should -BeLike 'InvalidPrincipalId*'
            $Err[0].Exception.Message | Should -BeLike '*-User*'
            Should -Invoke Invoke-OERGraphRequest -ModuleName Omnicit.EntraRBAC -Times 0 -ParameterFilter {
                $Method -eq 'POST'
            }
        }

        It 'keeps processing the remaining principals after one fails the GUID guard' {
            $Err = $null
            Add-OERGroupMember -Group 'role_sec_team' `
                -PrincipalId 'anna.berg@contoso.com', 'aaaa0000-0000-0000-0000-000000000001' `
                -Confirm:$false -ErrorAction SilentlyContinue -ErrorVariable Err
            $Err.Count | Should -Be 1
            Should -Invoke Invoke-OERGraphRequest -ModuleName Omnicit.EntraRBAC -Times 1 -ParameterFilter {
                $Body['@odata.id'] -eq 'https://graph.microsoft.com/v1.0/directoryObjects/aaaa0000-0000-0000-0000-000000000001'
            }
        }

        It 'reports NoPrincipal when no principal parameter is supplied' {
            $Err = $null
            Add-OERGroupMember -Group 'role_sec_team' -Confirm:$false `
                -ErrorAction SilentlyContinue -ErrorVariable Err
            $Err[0].FullyQualifiedErrorId | Should -BeLike 'NoPrincipal*'
        }

        It 'still round-trips a piped Get-OERGroupMember object' {
            $Member = [PSCustomObject]@{
                GroupId     = 'gggg0000-0000-0000-0000-00000000000a'
                PrincipalId = 'aaaa0000-0000-0000-0000-000000000001'
                MemberType  = 'member'
            }
            $Member | Add-OERGroupMember -Confirm:$false
            Should -Invoke Invoke-OERGraphRequest -ModuleName Omnicit.EntraRBAC -Times 1 -ParameterFilter {
                $Uri -eq 'v1.0/groups/gggg0000-0000-0000-0000-00000000000a/members/$ref'
            }
        }
    }

    Context 'sovereign cloud @odata.id host' {
        BeforeEach {
            InModuleScope $script:moduleName { $script:_OERAuthState = $null }
            Mock -ModuleName $script:moduleName Initialize-OERAuth {}
            Mock -ModuleName $script:moduleName Resolve-OERGroupId { 'gid-1' }
            Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {}
        }
        AfterEach {
            # Never leak a sovereign-cloud session into a later test in this or another file.
            InModuleScope $script:moduleName { $script:_OERAuthState = $null }
        }

        It 'pins today''s exact public-cloud @odata.id literal when there is no session at all' {
            Add-OERGroupMember -Group 'gid-1' -PrincipalId '11111111-1111-1111-1111-111111111111' -Confirm:$false
            Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 1 -Exactly -ParameterFilter {
                $Body.'@odata.id' -ceq 'https://graph.microsoft.com/v1.0/directoryObjects/11111111-1111-1111-1111-111111111111'
            }
        }

        It 'uses the public-cloud root when the cached session state carries no Environment' {
            InModuleScope $script:moduleName {
                $script:_OERAuthState = @{ TenantId = 'contoso.onmicrosoft.com' }
            }
            Add-OERGroupMember -Group 'gid-1' -PrincipalId '22222222-2222-2222-2222-222222222222' -Confirm:$false
            Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 1 -Exactly -ParameterFilter {
                $Body.'@odata.id' -ceq 'https://graph.microsoft.com/v1.0/directoryObjects/22222222-2222-2222-2222-222222222222'
            }
        }

        It 'names the session cloud''s own Graph service root for <_>' -ForEach @('USGov', 'USGovDoD', 'China') {
            $Cloud = $_
            $PrincipalGuid = '33333333-3333-3333-3333-333333333333'
            InModuleScope $script:moduleName -Parameters @{ Cloud = $Cloud } {
                param($Cloud)
                $script:_OERAuthState = @{ TenantId = 'contoso.onmicrosoft.com'; Environment = $Cloud }
            }
            # Driven from the table owner itself, not a second hardcoded expectation.
            $ExpectedRoot = InModuleScope $script:moduleName -Parameters @{ Cloud = $Cloud } {
                param($Cloud)
                (Get-OERCloudEndpoint -Environment $Cloud).GraphServiceRoot
            }
            Add-OERGroupMember -Group 'gid-1' -PrincipalId $PrincipalGuid -Confirm:$false
            Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 1 -Exactly -ParameterFilter {
                $Body.'@odata.id' -ceq "$ExpectedRoot/directoryObjects/$PrincipalGuid"
            }
        }

        It 'never emits a double slash after the host for <_>' -ForEach @('Global', 'USGov', 'USGovDoD', 'China') {
            $Cloud = $_
            $PrincipalGuid = '44444444-4444-4444-4444-444444444444'
            InModuleScope $script:moduleName -Parameters @{ Cloud = $Cloud } {
                param($Cloud)
                $script:_OERAuthState = @{ TenantId = 'contoso.onmicrosoft.com'; Environment = $Cloud }
            }
            $script:CapturedBody = $null
            Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {
                $script:CapturedBody = $Body
            }
            Add-OERGroupMember -Group 'gid-1' -PrincipalId $PrincipalGuid -Confirm:$false
            $script:CapturedBody | Should -Not -BeNullOrEmpty
            ($script:CapturedBody.'@odata.id' -replace '^https://', '') | Should -Not -Match '//'
        }
    }
}

Describe 'Add-OERGroupMember verbose output' {
    BeforeEach {
        InModuleScope $script:moduleName { $script:_OERAuthState = $null }
        Mock -ModuleName $script:moduleName Initialize-OERAuth {}
        Mock -ModuleName $script:moduleName Resolve-OERGroupId { 'gid-1' }
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {}
    }

    It 'reports the resolved group and one line per resolved principal under -Verbose' {
        $Verbose = Add-OERGroupMember -Group 'gid-1' -PrincipalId @(
            '11111111-1111-1111-1111-111111111111',
            '22222222-2222-2222-2222-222222222222'
        ) -Confirm:$false -Verbose 4>&1 |
            Where-Object { $_ -is [System.Management.Automation.VerboseRecord] }

        $Text = $Verbose.Message -join "`n"
        $Text | Should -Match "\[Add-OERGroupMember\] Resolved group to 'gid-1'."
        @($Verbose | Where-Object { $_.Message -match 'Resolved principal to ' }).Count | Should -Be 2
    }

    It 'emits no verbose output without -Verbose' {
        $Verbose = Add-OERGroupMember -Group 'gid-1' -PrincipalId '11111111-1111-1111-1111-111111111111' `
            -Confirm:$false 4>&1 | Where-Object { $_ -is [System.Management.Automation.VerboseRecord] }
        $Verbose | Should -BeNullOrEmpty
    }
}
