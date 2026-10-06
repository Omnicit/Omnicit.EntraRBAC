BeforeAll {
    Import-Module Omnicit.EntraRBAC -Force
    . "$PSScriptRoot/../TestHelpers/OERTransportTripwire.ps1"
    Install-OERTransportTripwire
}

AfterAll {
    try { Assert-OERTransportTripwire } finally { Uninstall-OERTransportTripwire }
}

Describe 'Get-OERGroupRelation' {
    BeforeEach {
        Mock -ModuleName Omnicit.EntraRBAC Initialize-OERAuth { }
    }

    It 'adds the service principal only the typed members read lists, once, with ObjectType servicePrincipal' {
        InModuleScope Omnicit.EntraRBAC {
            Mock Invoke-OERGraphRequest { @{ value = @(@{ '@odata.type' = '#microsoft.graph.group'; id = 'g-nested'; displayName = 'nested' }) } } -ParameterFilter { $Uri -eq 'v1.0/groups/22222222-2222-2222-2222-222222222222/members' }
            Mock Invoke-OERGraphRequest { @{ value = @(@{ id = 'sp-1'; displayName = 'an app' }) } } -ParameterFilter { $Uri -eq 'v1.0/groups/22222222-2222-2222-2222-222222222222/members/microsoft.graph.servicePrincipal' }
            $R = @(Get-OERGroupRelation -GroupId '22222222-2222-2222-2222-222222222222' -Relation members)
            $R.Count | Should -Be 2
            $R[0].PrincipalId | Should -Be 'g-nested'
            $R[0].ObjectType | Should -Be 'group'
            $R[1].PrincipalId | Should -Be 'sp-1'
            $R[1].ObjectType | Should -Be 'servicePrincipal'
            $R[1].MemberType | Should -Be 'Member'
            $R[1].GroupId | Should -Be '22222222-2222-2222-2222-222222222222'
            $R[1].PSObject.TypeNames[0] | Should -Be 'Omnicit.EntraRBAC.GroupMember'
        }
    }

    It 'adds the service principal only the typed owners read lists, as an Owner with ObjectType servicePrincipal' {
        InModuleScope Omnicit.EntraRBAC {
            Mock Invoke-OERGraphRequest { @{ value = @() } } -ParameterFilter { $Uri -eq 'v1.0/groups/22222222-2222-2222-2222-222222222222/owners' }
            Mock Invoke-OERGraphRequest { @{ value = @(@{ id = 'sp-1'; displayName = 'an app' }) } } -ParameterFilter { $Uri -eq 'v1.0/groups/22222222-2222-2222-2222-222222222222/owners/microsoft.graph.servicePrincipal' }
            $R = @(Get-OERGroupRelation -GroupId '22222222-2222-2222-2222-222222222222' -Relation owners)
            $R.Count | Should -Be 1
            $R[0].PrincipalId | Should -Be 'sp-1'
            $R[0].ObjectType | Should -Be 'servicePrincipal'
            $R[0].MemberType | Should -Be 'Owner'
            $R[0].GroupId | Should -Be '22222222-2222-2222-2222-222222222222'
            $R[0].PSObject.TypeNames[0] | Should -Be 'Omnicit.EntraRBAC.GroupMember'
        }
    }

    It 'lists a service principal both reads list exactly once, at the untyped position, even when the ids differ in case' {
        InModuleScope Omnicit.EntraRBAC {
            Mock Invoke-OERGraphRequest {
                @{ value = @(
                        @{ '@odata.type' = '#microsoft.graph.servicePrincipal'; id = 'SP-1'; displayName = 'an app' }
                        @{ '@odata.type' = '#microsoft.graph.group'; id = 'g-nested'; displayName = 'nested' }
                    ) }
            } -ParameterFilter { $Uri -eq 'v1.0/groups/22222222-2222-2222-2222-222222222222/members' }
            Mock Invoke-OERGraphRequest { @{ value = @(@{ id = 'sp-1'; displayName = 'an app' }) } } -ParameterFilter { $Uri -eq 'v1.0/groups/22222222-2222-2222-2222-222222222222/members/microsoft.graph.servicePrincipal' }
            $R = @(Get-OERGroupRelation -GroupId '22222222-2222-2222-2222-222222222222' -Relation members)
            $R.Count | Should -Be 2
            # The untyped read's own object, in its own position: the typed copy is the duplicate.
            $R[0].PrincipalId | Should -BeExactly 'SP-1'
            $R[0].ObjectType | Should -Be 'servicePrincipal'
            $R[1].PrincipalId | Should -Be 'g-nested'
            @($R | Where-Object { $_.PrincipalId -eq 'sp-1' }).Count | Should -Be 1
        }
    }

    It 'gives an untyped object with no @odata.type the type the typed read proves, and leaves any other one without' {
        InModuleScope Omnicit.EntraRBAC {
            Mock Invoke-OERGraphRequest {
                @{ value = @(
                        @{ id = 'sp-1'; displayName = 'an app' }
                        @{ id = 'x-1'; displayName = 'unannotated' }
                    ) }
            } -ParameterFilter { $Uri -eq 'v1.0/groups/22222222-2222-2222-2222-222222222222/members' }
            Mock Invoke-OERGraphRequest { @{ value = @(@{ id = 'SP-1'; displayName = 'an app' }) } } -ParameterFilter { $Uri -eq 'v1.0/groups/22222222-2222-2222-2222-222222222222/members/microsoft.graph.servicePrincipal' }
            $R = @(Get-OERGroupRelation -GroupId '22222222-2222-2222-2222-222222222222' -Relation members)
            $R.Count | Should -Be 2
            $R[0].PrincipalId | Should -Be 'sp-1'
            $R[0].ObjectType | Should -Be 'servicePrincipal'
            $R[1].PrincipalId | Should -Be 'x-1'
            ($null -eq $R[1].ObjectType) | Should -BeTrue -Because 'only an id the typed read lists carries a type the read proves'
        }
    }

    It 'sends both the untyped and the typed request with -All, for members and for owners' {
        InModuleScope Omnicit.EntraRBAC {
            Mock Invoke-OERGraphRequest { @{ value = @() } }
            $null = @(Get-OERGroupRelation -GroupId '22222222-2222-2222-2222-222222222222' -Relation members)
            $null = @(Get-OERGroupRelation -GroupId '22222222-2222-2222-2222-222222222222' -Relation owners)
            Should -Invoke Invoke-OERGraphRequest -Times 1 -Exactly -ParameterFilter { $Uri -eq 'v1.0/groups/22222222-2222-2222-2222-222222222222/members' -and $All }
            Should -Invoke Invoke-OERGraphRequest -Times 1 -Exactly -ParameterFilter { $Uri -eq 'v1.0/groups/22222222-2222-2222-2222-222222222222/members/microsoft.graph.servicePrincipal' -and $All }
            Should -Invoke Invoke-OERGraphRequest -Times 1 -Exactly -ParameterFilter { $Uri -eq 'v1.0/groups/22222222-2222-2222-2222-222222222222/owners' -and $All }
            Should -Invoke Invoke-OERGraphRequest -Times 1 -Exactly -ParameterFilter { $Uri -eq 'v1.0/groups/22222222-2222-2222-2222-222222222222/owners/microsoft.graph.servicePrincipal' -and $All }
            Should -Invoke Invoke-OERGraphRequest -Times 4 -Exactly
        }
    }

    It 'emits nothing, and writes no error, when both reads are empty' {
        InModuleScope Omnicit.EntraRBAC {
            Mock Invoke-OERGraphRequest { @{ value = @() } } -ParameterFilter { $Uri -eq 'v1.0/groups/22222222-2222-2222-2222-222222222222/members' }
            Mock Invoke-OERGraphRequest { @{ value = @() } } -ParameterFilter { $Uri -eq 'v1.0/groups/22222222-2222-2222-2222-222222222222/members/microsoft.graph.servicePrincipal' }
            $Err = $null
            $R = @(Get-OERGroupRelation -GroupId '22222222-2222-2222-2222-222222222222' -Relation members -ErrorAction Stop -ErrorVariable Err)
            $R.Count | Should -Be 0
            @($Err).Count | Should -Be 0
            Should -Invoke Invoke-OERGraphRequest -Times 2 -Exactly
        }
    }
}
