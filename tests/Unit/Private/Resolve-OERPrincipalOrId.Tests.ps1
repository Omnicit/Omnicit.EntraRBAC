BeforeAll {
    Import-Module Omnicit.EntraRBAC -Force
}

Describe 'Resolve-OERPrincipalOrId' {
    BeforeEach {
        InModuleScope Omnicit.EntraRBAC { $script:_OERAuthState = $null }
    }

    Context 'raw principal id' {
        It 'returns a canonical GUID verbatim without any lookup' {
            Mock -ModuleName Omnicit.EntraRBAC Resolve-OERPrincipal { throw 'should not be called' }
            InModuleScope Omnicit.EntraRBAC {
                $Result = Resolve-OERPrincipalOrId -PrincipalId 'aaaa0000-0000-0000-0000-000000000001'
                $Result.PrincipalId | Should -Be 'aaaa0000-0000-0000-0000-000000000001'
                $Result.ErrorId | Should -BeNullOrEmpty
            }
            Should -Invoke Resolve-OERPrincipal -ModuleName Omnicit.EntraRBAC -Times 0
        }

        It 'returns an InvalidPrincipalId failure for a non-GUID value and names the friendly parameters' {
            InModuleScope Omnicit.EntraRBAC {
                $Result = Resolve-OERPrincipalOrId -PrincipalId 'anna.berg@contoso.com'
                $Result.ErrorId | Should -Be 'InvalidPrincipalId'
                $Result.Category | Should -Be 'InvalidArgument'
                $Result.PrincipalId | Should -BeNullOrEmpty
                $Result.TargetObject | Should -Be 'anna.berg@contoso.com'
                $Result.Message | Should -BeLike "*'-PrincipalId'*"
                $Result.Message | Should -BeLike '*-User, -Group or -ServicePrincipal*'
            }
        }

        It 'uses the configured id parameter name and error id in the failure' {
            InModuleScope Omnicit.EntraRBAC {
                $Result = Resolve-OERPrincipalOrId -PrincipalId 'not-a-guid' `
                    -IdParameterName 'TargetId' -InvalidIdErrorId 'InvalidTargetId' `
                    -FriendlyParameterHint '-User'
                $Result.ErrorId | Should -Be 'InvalidTargetId'
                $Result.Message | Should -BeLike "*'-TargetId'*"
                $Result.Message | Should -BeLike '*-User*'
            }
        }
    }

    Context 'friendly references' {
        It 'resolves -User through Resolve-OERPrincipal' {
            Mock -ModuleName Omnicit.EntraRBAC Resolve-OERPrincipal {
                [PSCustomObject]@{ PrincipalId = 'bbbb0000-0000-0000-0000-000000000002'; PrincipalType = 'User' }
            }
            InModuleScope Omnicit.EntraRBAC {
                $Result = Resolve-OERPrincipalOrId -User 'anna.berg@contoso.com'
                $Result.PrincipalId | Should -Be 'bbbb0000-0000-0000-0000-000000000002'
                $Result.PrincipalType | Should -Be 'User'
                $Result.ErrorId | Should -BeNullOrEmpty
            }
            Should -Invoke Resolve-OERPrincipal -ModuleName Omnicit.EntraRBAC -Times 1 -ParameterFilter {
                $User -eq 'anna.berg@contoso.com'
            }
        }

        It 'resolves -Group through Resolve-OERPrincipal' {
            Mock -ModuleName Omnicit.EntraRBAC Resolve-OERPrincipal {
                [PSCustomObject]@{ PrincipalId = 'cccc0000-0000-0000-0000-000000000003'; PrincipalType = 'Group' }
            }
            InModuleScope Omnicit.EntraRBAC {
                (Resolve-OERPrincipalOrId -Group 'Sales Team').PrincipalId |
                    Should -Be 'cccc0000-0000-0000-0000-000000000003'
            }
            Should -Invoke Resolve-OERPrincipal -ModuleName Omnicit.EntraRBAC -Times 1 -ParameterFilter {
                $Group -eq 'Sales Team'
            }
        }

        It 'resolves -ServicePrincipal through Resolve-OERPrincipal' {
            Mock -ModuleName Omnicit.EntraRBAC Resolve-OERPrincipal {
                [PSCustomObject]@{ PrincipalId = 'dddd0000-0000-0000-0000-000000000004'; PrincipalType = 'ServicePrincipal' }
            }
            InModuleScope Omnicit.EntraRBAC {
                (Resolve-OERPrincipalOrId -ServicePrincipal 'Contoso App').PrincipalType |
                    Should -Be 'ServicePrincipal'
            }
        }

        It 'returns a PrincipalNotFound failure when Resolve-OERPrincipal throws' {
            Mock -ModuleName Omnicit.EntraRBAC Resolve-OERPrincipal { throw "User 'ghost@contoso.com' was not found." }
            InModuleScope Omnicit.EntraRBAC {
                $Result = Resolve-OERPrincipalOrId -User 'ghost@contoso.com'
                $Result.ErrorId | Should -Be 'PrincipalNotFound'
                $Result.Category | Should -Be 'ObjectNotFound'
                $Result.Message | Should -BeLike '*ghost@contoso.com*'
            }
        }
    }

    Context 'argument validation' {
        It 'returns a NoPrincipal failure when nothing is supplied' {
            InModuleScope Omnicit.EntraRBAC {
                $Result = Resolve-OERPrincipalOrId
                $Result.ErrorId | Should -Be 'NoPrincipal'
                $Result.Category | Should -Be 'InvalidArgument'
            }
        }

        It 'appends the NoPrincipalHint parenthetical when supplied' {
            InModuleScope Omnicit.EntraRBAC {
                $Result = Resolve-OERPrincipalOrId -NoPrincipalHint 'or pipe from Get-OEREligibleRoleAssignment'
                $Result.Message | Should -Be 'A principal is required: supply -PrincipalId or one of -User, -Group or -ServicePrincipal (or pipe from Get-OEREligibleRoleAssignment).'
            }
        }

        It 'returns an AmbiguousPrincipal failure when two friendly references are supplied' {
            InModuleScope Omnicit.EntraRBAC {
                $Result = Resolve-OERPrincipalOrId -User 'anna@contoso.com' -Group 'Sales Team'
                $Result.ErrorId | Should -Be 'AmbiguousPrincipal'
                $Result.Category | Should -Be 'InvalidArgument'
            }
        }

        It 'lets -PrincipalId win over a friendly reference without an ambiguity error' {
            Mock -ModuleName Omnicit.EntraRBAC Resolve-OERPrincipal { throw 'should not be called' }
            InModuleScope Omnicit.EntraRBAC {
                $Result = Resolve-OERPrincipalOrId -PrincipalId 'aaaa0000-0000-0000-0000-000000000001' -User 'anna@contoso.com'
                $Result.PrincipalId | Should -Be 'aaaa0000-0000-0000-0000-000000000001'
                $Result.ErrorId | Should -BeNullOrEmpty
            }
        }

        It 'warns that the ignored friendly parameter is dropped when -PrincipalId wins' {
            Mock -ModuleName Omnicit.EntraRBAC Resolve-OERPrincipal { throw 'should not be called' }
            InModuleScope Omnicit.EntraRBAC {
                $Warnings = $null
                $Result = Resolve-OERPrincipalOrId -PrincipalId 'aaaa0000-0000-0000-0000-000000000001' `
                    -User 'anna@contoso.com' -WarningVariable Warnings -WarningAction SilentlyContinue
                $Result.PrincipalId | Should -Be 'aaaa0000-0000-0000-0000-000000000001'
                $Warnings.Count | Should -Be 1
                $Warnings[0].Message | Should -BeLike '*-User*'
                $Warnings[0].Message | Should -BeLike '*-PrincipalId*'
                $Warnings[0].Message | Should -BeLike "*'aaaa0000-0000-0000-0000-000000000001'*"
            }
        }

        It 'names every ignored friendly parameter when more than one is supplied alongside -PrincipalId' {
            Mock -ModuleName Omnicit.EntraRBAC Resolve-OERPrincipal { throw 'should not be called' }
            InModuleScope Omnicit.EntraRBAC {
                $Warnings = $null
                $null = Resolve-OERPrincipalOrId -PrincipalId 'aaaa0000-0000-0000-0000-000000000001' `
                    -User 'anna@contoso.com' -Group 'Sales Team' -ServicePrincipal 'Contoso App' `
                    -WarningVariable Warnings -WarningAction SilentlyContinue
                $Warnings.Count | Should -Be 1
                $Warnings[0].Message | Should -BeLike '*-User*'
                $Warnings[0].Message | Should -BeLike '*-Group*'
                $Warnings[0].Message | Should -BeLike '*-ServicePrincipal*'
            }
        }

        It 'uses the configured -GroupParameterName in the precedence warning' {
            Mock -ModuleName Omnicit.EntraRBAC Resolve-OERPrincipal { throw 'should not be called' }
            InModuleScope Omnicit.EntraRBAC {
                $Warnings = $null
                $null = Resolve-OERPrincipalOrId -PrincipalId 'aaaa0000-0000-0000-0000-000000000001' `
                    -Group 'Sales Team' -GroupParameterName 'GroupPrincipal' `
                    -WarningVariable Warnings -WarningAction SilentlyContinue
                $Warnings[0].Message | Should -BeLike '*-GroupPrincipal*'
                $Warnings[0].Message | Should -Not -BeLike '*-Group value*'
            }
        }

        It 'does not warn when -PrincipalId is supplied alone with no friendly parameter' {
            InModuleScope Omnicit.EntraRBAC {
                $Warnings = $null
                $null = Resolve-OERPrincipalOrId -PrincipalId 'aaaa0000-0000-0000-0000-000000000001' `
                    -WarningVariable Warnings -WarningAction SilentlyContinue
                $Warnings.Count | Should -Be 0
            }
        }

        It 'never throws for any input combination' {
            InModuleScope Omnicit.EntraRBAC {
                { Resolve-OERPrincipalOrId } | Should -Not -Throw
                { Resolve-OERPrincipalOrId -PrincipalId 'x' } | Should -Not -Throw
                { Resolve-OERPrincipalOrId -User 'a' -Group 'b' -ServicePrincipal 'c' } | Should -Not -Throw
            }
        }
    }

    It 'scrubs the bearer-hygiene record when the friendly principal lookup fails' {
        Mock -ModuleName Omnicit.EntraRBAC Resolve-OERPrincipal { throw 'principal not found' }
        Mock -ModuleName Omnicit.EntraRBAC Remove-OERErrorRecord { }
        InModuleScope Omnicit.EntraRBAC {
            $Result = Resolve-OERPrincipalOrId -User 'anna@contoso.com'
            $Result.ErrorId | Should -Be 'PrincipalNotFound'
        }
        Should -Invoke Remove-OERErrorRecord -ModuleName Omnicit.EntraRBAC -Times 1
    }
}
