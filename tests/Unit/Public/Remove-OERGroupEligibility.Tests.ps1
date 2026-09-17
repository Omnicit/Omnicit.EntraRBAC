BeforeAll {
    $script:moduleName = 'Omnicit.EntraRBAC'
    Get-Module $script:moduleName | Remove-Module -Force -ErrorAction SilentlyContinue
    Import-Module $script:moduleName -Force -ErrorAction Stop
}

Describe 'Remove-OERGroupEligibility' {
    BeforeEach {
        InModuleScope $script:moduleName { $script:_OERAuthState = $null }
        $script:PrincipalGuid = '11111111-1111-1111-1111-111111111111'
        Mock -ModuleName $script:moduleName Initialize-OERAuth {}
        Mock -ModuleName $script:moduleName Resolve-OERGroupId { 'gid-1' }
        Mock -ModuleName $script:moduleName Resolve-OERPrincipal { [PSCustomObject]@{ PrincipalId = 'resolved-user-id'; PrincipalType = 'User' } }
    }

    It 'posts an adminRemove eligibility request' {
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest { @{ id = 'req-2'; status = 'Revoked'; action = 'adminRemove' } }
        Remove-OERGroupEligibility -Group 'gid-1' -PrincipalId $script:PrincipalGuid -Confirm:$false | Out-Null
        Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 1 -ParameterFilter {
            $Method -eq 'POST' -and $Body.action -eq 'adminRemove' -and $Body.principalId -eq '11111111-1111-1111-1111-111111111111'
        }
    }

    It 'binds GroupId, PrincipalId, and AccessType from a piped Get-OERGroupEligibility object (revoke round-trip)' {
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest { @{ id = 'req-rt'; status = 'Revoked'; action = 'adminRemove' } }
        [pscustomobject]@{
            GroupId     = 'gid-1'
            PrincipalId = $script:PrincipalGuid
            AccessType  = 'owner'
        } | Remove-OERGroupEligibility -Confirm:$false | Out-Null
        Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 1 -ParameterFilter {
            $Method -eq 'POST' -and $Body.action -eq 'adminRemove' -and
            $Body.principalId -eq '11111111-1111-1111-1111-111111111111' -and $Body.accessId -eq 'owner'
        }
    }

    It 'does not POST under -WhatIf' {
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {}
        Remove-OERGroupEligibility -Group 'gid-1' -PrincipalId $script:PrincipalGuid -WhatIf | Out-Null
        Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 0
    }

    It 'resolves -User via Resolve-OERPrincipal and sends the resolved id' {
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest { @{ id = 'req-u'; status = 'Revoked'; action = 'adminRemove' } }
        Remove-OERGroupEligibility -Group 'gid-1' -User 'anna.berg@contoso.com' -Confirm:$false | Out-Null
        Should -Invoke -ModuleName $script:moduleName Resolve-OERPrincipal -Times 1 -ParameterFilter { $User -eq 'anna.berg@contoso.com' }
        Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 1 -ParameterFilter { $Body.principalId -eq 'resolved-user-id' }
    }

    It 'errors InvalidPrincipalId for a non-GUID -PrincipalId and does NOT POST' {
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {}
        Remove-OERGroupEligibility -Group 'gid-1' -PrincipalId 'anna@contoso.com' -Confirm:$false -ErrorVariable e -ErrorAction SilentlyContinue | Out-Null
        $e[0].FullyQualifiedErrorId | Should -Match 'InvalidPrincipalId'
        Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 0
    }

    It 'errors NoPrincipal when neither -User nor -PrincipalId is supplied' {
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {}
        Remove-OERGroupEligibility -Group 'gid-1' -Confirm:$false -ErrorVariable e -ErrorAction SilentlyContinue | Out-Null
        $e[0].FullyQualifiedErrorId | Should -Match 'NoPrincipal'
        Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 0
    }

    It 'uses -PrincipalId and ignores -User when both are supplied (PrincipalId takes precedence per Resolve-OERPrincipalOrId), warning that -User was dropped' {
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest { @{ id = 'req-amb'; status = 'Revoked'; action = 'adminRemove' } }
        $Warnings = $null
        Remove-OERGroupEligibility -Group 'gid-1' -User 'anna@contoso.com' -PrincipalId $script:PrincipalGuid -Confirm:$false `
            -WarningVariable Warnings -WarningAction SilentlyContinue | Out-Null
        Should -Invoke -ModuleName $script:moduleName Resolve-OERPrincipal -Times 0
        Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 1 -ParameterFilter { $Body.principalId -eq $script:PrincipalGuid }
        ($Warnings | ForEach-Object { $_.Message }) -join ' ' | Should -BeLike '*-User*'
    }

    It 'still binds the legacy -Id alias and the pipeline Id property' {
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest { @{ id = 'req-d'; status = 'Revoked'; action = 'adminRemove' } }
        [pscustomobject]@{ Id = 'gid-1' } | Remove-OERGroupEligibility -PrincipalId $script:PrincipalGuid -Confirm:$false | Out-Null
        Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 1 -ParameterFilter { $Method -eq 'POST' }
    }

    It 'errors GroupNotFound and does NOT POST when the group cannot be resolved' {
        Mock -ModuleName $script:moduleName Resolve-OERGroupId { $null }
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {}
        Remove-OERGroupEligibility -Group 'nope' -PrincipalId $script:PrincipalGuid -Confirm:$false -ErrorVariable e -ErrorAction SilentlyContinue | Out-Null
        $e[0].FullyQualifiedErrorId | Should -Match 'GroupNotFound'
        Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 0
    }

    It 'gives an actionable GroupNotFound message' {
        Mock -ModuleName $script:moduleName Resolve-OERGroupId { $null }
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {}
        Remove-OERGroupEligibility -Group 'ghost' -PrincipalId $script:PrincipalGuid -Confirm:$false `
            -ErrorAction SilentlyContinue -ErrorVariable Err
        $Joined = @($Err).FullyQualifiedErrorId -join ';'
        $Joined | Should -Match 'GroupNotFound'
        $Text = @($Err).Exception.Message -join ' '
        $Text | Should -Match 'display name'
        $Text | Should -Match 'object id'
    }

    It 'errors PrincipalNotFound when Resolve-OERPrincipal throws' {
        Mock -ModuleName $script:moduleName Resolve-OERPrincipal { throw 'User not found' }
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {}
        Remove-OERGroupEligibility -Group 'gid-1' -User 'ghost@contoso.com' -Confirm:$false -ErrorVariable e -ErrorAction SilentlyContinue | Out-Null
        (($e | ForEach-Object { $_.FullyQualifiedErrorId }) -join ' ') | Should -Match 'PrincipalNotFound'
        Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 0
    }

    It 'scrubs the bearer-hygiene record when the eligibility request fails' {
        # Drives the POST catch in source/Public/Remove-OERGroupEligibility.ps1 (the
        # eligibilityScheduleRequests try inside ShouldProcess). Resolve-OERGroupId and
        # Resolve-OERPrincipal are mocked to SUCCEED by the Describe BeforeEach, so the mocked
        # transport failure is what reaches the catch. CLAUDE.md SECURITY rule 6 makes
        # Remove-OERErrorRecord -Record $PSItem its mandatory first statement.
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest { throw 'transport failure' }
        Mock -ModuleName $script:moduleName Remove-OERErrorRecord { }
        Remove-OERGroupEligibility -Group 'gid-1' -PrincipalId $script:PrincipalGuid -Confirm:$false `
            -WarningAction SilentlyContinue -ErrorAction SilentlyContinue | Out-Null
        Should -Invoke -ModuleName $script:moduleName Remove-OERErrorRecord -Times 1
    }

    Context 'friendly principal input' {
        BeforeEach {
            InModuleScope Omnicit.EntraRBAC { $script:_OERAuthState = $null }
            Mock -ModuleName Omnicit.EntraRBAC Initialize-OERAuth { }
            Mock -ModuleName Omnicit.EntraRBAC Resolve-OERGroupId { 'gggg0000-0000-0000-0000-00000000000a' }
            Mock -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest {
                @{ id = 'req1'; status = 'Provisioned' }
            }
        }

        It 'resolves -GroupPrincipal to an object id and puts it in the request body' {
            Mock -ModuleName Omnicit.EntraRBAC Resolve-OERPrincipal {
                [PSCustomObject]@{ PrincipalId = 'cccc0000-0000-0000-0000-000000000003'; PrincipalType = 'Group' }
            }
            $Result = Remove-OERGroupEligibility -Group 'role_sec_team' -GroupPrincipal 'Sales Team' -Confirm:$false
            $Result.PrincipalId | Should -Be 'cccc0000-0000-0000-0000-000000000003'
            Should -Invoke Resolve-OERPrincipal -ModuleName Omnicit.EntraRBAC -Times 1 -ParameterFilter {
                $Group -eq 'Sales Team'
            }
        }

        It 'resolves -ServicePrincipal to an object id' {
            Mock -ModuleName Omnicit.EntraRBAC Resolve-OERPrincipal {
                [PSCustomObject]@{ PrincipalId = 'dddd0000-0000-0000-0000-000000000004'; PrincipalType = 'ServicePrincipal' }
            }
            $Result = Remove-OERGroupEligibility -Group 'role_sec_team' -ServicePrincipal 'Contoso App' -Confirm:$false
            $Result.PrincipalId | Should -Be 'dddd0000-0000-0000-0000-000000000004'
        }

        It 'still accepts a raw GUID -PrincipalId without any principal lookup' {
            Mock -ModuleName Omnicit.EntraRBAC Resolve-OERPrincipal { throw 'should not be called' }
            $Result = Remove-OERGroupEligibility -Group 'role_sec_team' `
                -PrincipalId 'aaaa0000-0000-0000-0000-000000000001' -Confirm:$false
            $Result.PrincipalId | Should -Be 'aaaa0000-0000-0000-0000-000000000001'
            Should -Invoke Resolve-OERPrincipal -ModuleName Omnicit.EntraRBAC -Times 0
        }

        It 'rejects a UPN passed to -PrincipalId and names the friendly parameters' {
            $Err = $null
            Remove-OERGroupEligibility -Group 'role_sec_team' -PrincipalId 'anna@contoso.com' `
                -Confirm:$false -ErrorAction SilentlyContinue -ErrorVariable Err
            $Err[0].FullyQualifiedErrorId | Should -BeLike 'InvalidPrincipalId*'
            $Err[0].Exception.Message | Should -BeLike '*-GroupPrincipal*'
            Should -Invoke Invoke-OERGraphRequest -ModuleName Omnicit.EntraRBAC -Times 0 -ParameterFilter {
                $Method -eq 'POST'
            }
        }

        It 'reports AmbiguousPrincipal when -User and -GroupPrincipal are both supplied' {
            $Err = $null
            Remove-OERGroupEligibility -Group 'role_sec_team' -User 'anna@contoso.com' `
                -GroupPrincipal 'Sales Team' -Confirm:$false `
                -ErrorAction SilentlyContinue -ErrorVariable Err
            $Err[0].FullyQualifiedErrorId | Should -BeLike 'AmbiguousPrincipal*'
        }
    }

    Context 'piped ambiguity guard' {
        BeforeEach {
            InModuleScope Omnicit.EntraRBAC { $script:_OERAuthState = $null }
            Mock -ModuleName Omnicit.EntraRBAC Initialize-OERAuth { }
            Mock -ModuleName Omnicit.EntraRBAC Resolve-OERGroupId { 'gggg0000-0000-0000-0000-00000000000a' }
        }

        It 'errors AmbiguousPrincipal and makes no Graph call when -User is supplied alongside piped input' {
            Mock -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest { }
            $Err = $null
            [pscustomobject]@{
                GroupId     = 'gggg0000-0000-0000-0000-00000000000a'
                PrincipalId = '11111111-1111-1111-1111-111111111111'
            } | Remove-OERGroupEligibility -User 'anna@contoso.com' -Confirm:$false `
                -ErrorAction SilentlyContinue -ErrorVariable Err
            $Err[0].FullyQualifiedErrorId | Should -BeLike 'AmbiguousPrincipal*'
            Should -Invoke Invoke-OERGraphRequest -ModuleName Omnicit.EntraRBAC -Times 0
        }

        It 'does not fire the piped-ambiguity guard for a normal round-trip with no friendly parameter' {
            Mock -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest { @{ id = 'req'; status = 'Revoked' } }
            [pscustomobject]@{
                GroupId     = 'gggg0000-0000-0000-0000-00000000000a'
                PrincipalId = '11111111-1111-1111-1111-111111111111'
            } | Remove-OERGroupEligibility -Confirm:$false | Out-Null
            Should -Invoke Invoke-OERGraphRequest -ModuleName Omnicit.EntraRBAC -Times 1 -ParameterFilter {
                $Method -eq 'POST'
            }
        }
    }

    Context 'destructive guard' {
        It 'warns BEFORE the POST fires' {
            # The warning AND the mutation record into the SAME list. A list that only ever records
            # the POST would stay green with the Write-Warning moved below it, which is exactly the
            # defect this guard exists to catch.
            $Order = [System.Collections.Generic.List[string]]::new()
            Mock -ModuleName $script:moduleName Write-Warning -ParameterFilter { $Message -match 'loses the ability to activate' } -MockWith { $Order.Add('warn') }
            Mock -ModuleName $script:moduleName Invoke-OERGraphRequest -MockWith {
                $Order.Add('post')
                @{ id = 'req-guard'; status = 'Revoked'; action = 'adminRemove' }
            }
            Remove-OERGroupEligibility -Group 'gid-1' -PrincipalId $script:PrincipalGuid -Confirm:$false `
                -WarningAction SilentlyContinue | Out-Null
            $Order -join ',' | Should -Be 'warn,post'
            Should -Invoke -ModuleName $script:moduleName Write-Warning -Times 1 -ParameterFilter { $Message -match 'loses the ability to activate' }
        }

        It 'does not POST under -WhatIf (destructive guard)' {
            Mock -ModuleName $script:moduleName Invoke-OERGraphRequest { }
            Remove-OERGroupEligibility -Group 'gid-1' -PrincipalId $script:PrincipalGuid -WhatIf | Out-Null
            Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 0
        }

        It 'does not warn under -WhatIf (the warning belongs inside the ShouldProcess block)' {
            Mock -ModuleName $script:moduleName Invoke-OERGraphRequest { }
            Remove-OERGroupEligibility -Group 'gid-1' -PrincipalId $script:PrincipalGuid -WhatIf `
                -WarningVariable Warn -WarningAction SilentlyContinue | Out-Null
            @($Warn | Where-Object { $_.Message -match 'eligibility' }).Count | Should -Be 0
        }
    }

    It 'still emits the full GroupEligibility request shape after the converter extraction' {
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest { @{ id = 'req-shape'; status = 'Revoked'; action = 'adminRemove' } }
        $Result = Remove-OERGroupEligibility -Group 'gid-1' -PrincipalId $script:PrincipalGuid -Confirm:$false
        $Result.PSObject.TypeNames[0] | Should -Be 'Omnicit.EntraRBAC.GroupEligibility'
        @($Result.PSObject.Properties.Name) -join ',' |
            Should -Be 'RequestId,GroupId,PrincipalId,AccessType,Action,Status'
    }
}

Describe 'Remove-OERGroupEligibility verbose output' {
    BeforeEach {
        InModuleScope $script:moduleName { $script:_OERAuthState = $null }
        Mock -ModuleName $script:moduleName Initialize-OERAuth {}
        Mock -ModuleName $script:moduleName Resolve-OERGroupId { 'gid-1' }
        Mock -ModuleName $script:moduleName Resolve-OERPrincipal { [PSCustomObject]@{ PrincipalId = 'resolved-user-id'; PrincipalType = 'User' } }
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest { @{ id = 'req-2'; status = 'Revoked'; action = 'adminRemove' } }
    }

    It 'reports the resolved group and principal under -Verbose' {
        $Verbose = Remove-OERGroupEligibility -Group 'gid-1' -PrincipalId '11111111-1111-1111-1111-111111111111' `
            -Confirm:$false -Verbose 4>&1 |
            Where-Object { $_ -is [System.Management.Automation.VerboseRecord] }
        $Text = $Verbose.Message -join "`n"
        $Text | Should -Match "\[Remove-OERGroupEligibility\] Resolved group to 'gid-1'."
        $Text | Should -Match "\[Remove-OERGroupEligibility\] Resolved principal to '11111111-1111-1111-1111-111111111111'."
    }

    It 'emits no verbose output without -Verbose' {
        $Verbose = Remove-OERGroupEligibility -Group 'gid-1' -PrincipalId '11111111-1111-1111-1111-111111111111' `
            -Confirm:$false 4>&1 | Where-Object { $_ -is [System.Management.Automation.VerboseRecord] }
        $Verbose | Should -BeNullOrEmpty
    }
}
