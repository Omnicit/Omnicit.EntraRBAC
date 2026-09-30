BeforeAll { Import-Module Omnicit.EntraRBAC -Force }

Describe 'Get-OERMemberGroupId' {
    # One POST v1.0/directoryObjects/{id}/getMemberGroups through the Graph wrapper: transitive, for a
    # user and a service principal alike, never /me. No id below is version-4 shaped.
    BeforeEach {
        InModuleScope Omnicit.EntraRBAC {
            Mock Initialize-OERAuth {}
        }
    }

    It 'posts exactly one getMemberGroups request for the object, with securityEnabledOnly false and nothing else in the body' {
        InModuleScope Omnicit.EntraRBAC {
            Mock Invoke-OERGraphRequest { @{ value = @('cccccccc-0000-0000-0000-000000000001') } }
            $null = Get-OERMemberGroupId -ObjectId 'aaaaaaaa-0000-0000-0000-0000000000ff'
            Should -Invoke Invoke-OERGraphRequest -Times 1 -Exactly
            Should -Invoke Invoke-OERGraphRequest -Times 1 -Exactly -ParameterFilter {
                $Method -eq 'POST' -and
                $Uri -ceq 'v1.0/directoryObjects/aaaaaaaa-0000-0000-0000-0000000000ff/getMemberGroups' -and
                $Body -is [hashtable] -and $Body.Count -eq 1 -and $Body.ContainsKey('securityEnabledOnly') -and
                $Body['securityEnabledOnly'] -is [bool] -and $Body['securityEnabledOnly'] -eq $false
            }
            # An app-only sign-in has no /me, so the object is always named by its id.
            Should -Invoke Invoke-OERGraphRequest -Times 0 -ParameterFilter { $Uri -match '(^|/)me(/|$)' }
        }
    }

    It 'emits each id lower-cased as its own pipeline object, skipping null and blank entries' {
        InModuleScope Omnicit.EntraRBAC {
            Mock Invoke-OERGraphRequest {
                @{ value = @('CCCCCCCC-0000-0000-0000-000000000001', $null, '', '   ', 'dddddddd-0000-0000-0000-000000000002') }
            }
            # Two ids are two pipeline objects: the caller collects them with @(), which would wrap an
            # array emitted as ONE object as a single element instead.
            (Get-OERMemberGroupId -ObjectId 'aaaaaaaa-0000-0000-0000-0000000000ff' | Measure-Object).Count | Should -Be 2
            $Result = @(Get-OERMemberGroupId -ObjectId 'aaaaaaaa-0000-0000-0000-0000000000ff')
            $Result.Count | Should -Be 2
            foreach ($Id in $Result) { $Id -is [string] | Should -BeTrue }
            $Result[0] | Should -BeExactly 'cccccccc-0000-0000-0000-000000000001'
            $Result[1] | Should -BeExactly 'dddddddd-0000-0000-0000-000000000002'
        }
    }

    It 'emits nothing when the object is a member of no group (<Case>)' -TestCases @(
        @{ Case = 'an empty value collection'; Answer = @{ value = @() } }
        @{ Case = 'no value collection at all'; Answer = @{} }
        @{ Case = 'only null and blank entries'; Answer = @{ value = @($null, '') } }
    ) {
        InModuleScope Omnicit.EntraRBAC -Parameters @{ Answer = $Answer } {
            param($Answer)
            $script:MemberGroupAnswer = $Answer
            Mock Invoke-OERGraphRequest { $script:MemberGroupAnswer }
            @(Get-OERMemberGroupId -ObjectId 'aaaaaaaa-0000-0000-0000-0000000000ff').Count | Should -Be 0
        }
    }

    It 'catches nothing: a failed request propagates to the caller' {
        InModuleScope Omnicit.EntraRBAC {
            Mock Invoke-OERGraphRequest { throw 'Graph 403 Authorization_RequestDenied' }
            Mock Remove-OERErrorRecord {}
            { Get-OERMemberGroupId -ObjectId 'aaaaaaaa-0000-0000-0000-0000000000ff' } | Should -Throw '*Authorization_RequestDenied*'
            Should -Invoke Invoke-OERGraphRequest -Times 1 -Exactly
            Should -Invoke Remove-OERErrorRecord -Times 0
        }
    }
}
