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
            # -ErrorAction Stop: an error record written by the call would throw here and fail the
            # test, so reaching the next line is the proof that none was written. (An unfiltered
            # -ErrorVariable count is not: newer Pester lets its own bookkeeping leak into it.)
            $R = @(Get-OERGroupRelation -GroupId '22222222-2222-2222-2222-222222222222' -Relation members -ErrorAction Stop)
            $R.Count | Should -Be 0
            Should -Invoke Invoke-OERGraphRequest -Times 2 -Exactly
        }
    }

    Context 'a failed read leaves the collection unread' {
        # A collection is read whole or not at all (A5): a failure of either read propagates to the
        # caller, and nothing was emitted before it. The failure is a thrown ErrorRecord, exactly how
        # Invoke-OERGraphRequest raises.
        It 'throws, and the collection never completes, when the typed members read fails after the untyped read succeeded' {
            InModuleScope Omnicit.EntraRBAC {
                Mock Invoke-OERGraphRequest { @{ value = @(@{ '@odata.type' = '#microsoft.graph.group'; id = 'g-nested'; displayName = 'nested' }) } } -ParameterFilter { $Uri -eq 'v1.0/groups/22222222-2222-2222-2222-222222222222/members' }
                Mock Invoke-OERGraphRequest {
                    throw [System.Management.Automation.ErrorRecord]::new([System.Exception]::new('Forbidden: denied'), 'Forbidden', 'PermissionDenied', $null)
                } -ParameterFilter { $Uri -eq 'v1.0/groups/22222222-2222-2222-2222-222222222222/members/microsoft.graph.servicePrincipal' }
                $Collected = 'unset'
                $Caught = $null
                try {
                    $Collected = @(Get-OERGroupRelation -GroupId '22222222-2222-2222-2222-222222222222' -Relation members)
                } catch {
                    $Caught = $PSItem
                }
                # The catch was reached, by the typed read's own record.
                $null -ne $Caught | Should -BeTrue
                $Caught.Exception.Message | Should -Be 'Forbidden: denied'
                $Caught.FullyQualifiedErrorId | Should -BeLike 'Forbidden*'
                # The assignment never completed: the untyped member was not handed out on its own.
                $Collected | Should -Be 'unset'
                Should -Invoke Invoke-OERGraphRequest -Times 1 -Exactly -ParameterFilter { $Uri -eq 'v1.0/groups/22222222-2222-2222-2222-222222222222/members/microsoft.graph.servicePrincipal' }
                Should -Invoke Invoke-OERGraphRequest -Times 2 -Exactly
            }
        }

        It 'throws, and the collection never completes, when the typed owners read fails after the untyped read succeeded' {
            InModuleScope Omnicit.EntraRBAC {
                Mock Invoke-OERGraphRequest { @{ value = @(@{ '@odata.type' = '#microsoft.graph.user'; id = 'u-1'; displayName = 'a user' }) } } -ParameterFilter { $Uri -eq 'v1.0/groups/22222222-2222-2222-2222-222222222222/owners' }
                Mock Invoke-OERGraphRequest {
                    throw [System.Management.Automation.ErrorRecord]::new([System.Exception]::new('Forbidden: denied'), 'Forbidden', 'PermissionDenied', $null)
                } -ParameterFilter { $Uri -eq 'v1.0/groups/22222222-2222-2222-2222-222222222222/owners/microsoft.graph.servicePrincipal' }
                $Collected = 'unset'
                $Caught = $null
                try {
                    $Collected = @(Get-OERGroupRelation -GroupId '22222222-2222-2222-2222-222222222222' -Relation owners)
                } catch {
                    $Caught = $PSItem
                }
                $null -ne $Caught | Should -BeTrue
                $Caught.Exception.Message | Should -Be 'Forbidden: denied'
                $Caught.FullyQualifiedErrorId | Should -BeLike 'Forbidden*'
                $Collected | Should -Be 'unset'
                Should -Invoke Invoke-OERGraphRequest -Times 1 -Exactly -ParameterFilter { $Uri -eq 'v1.0/groups/22222222-2222-2222-2222-222222222222/owners/microsoft.graph.servicePrincipal' }
                Should -Invoke Invoke-OERGraphRequest -Times 2 -Exactly
            }
        }

        # The two tests above collect the call with @(...), which discards whatever a helper emitted
        # before it threw. These two STREAM the call into a list instead, so a helper that handed the
        # untyped objects to the pipeline before the typed read had succeeded is caught here: the
        # caller of a pipeline sees each object the moment it is emitted.
        It 'streams nothing to the pipeline before it throws when the typed members read fails' {
            InModuleScope Omnicit.EntraRBAC {
                Mock Invoke-OERGraphRequest { @{ value = @(@{ '@odata.type' = '#microsoft.graph.group'; id = 'g-nested'; displayName = 'nested' }) } } -ParameterFilter { $Uri -eq 'v1.0/groups/22222222-2222-2222-2222-222222222222/members' }
                Mock Invoke-OERGraphRequest {
                    throw [System.Management.Automation.ErrorRecord]::new([System.Exception]::new('Forbidden: denied'), 'Forbidden', 'PermissionDenied', $null)
                } -ParameterFilter { $Uri -eq 'v1.0/groups/22222222-2222-2222-2222-222222222222/members/microsoft.graph.servicePrincipal' }
                $Streamed = [System.Collections.Generic.List[object]]::new()
                $Caught = $null
                try {
                    Get-OERGroupRelation -GroupId '22222222-2222-2222-2222-222222222222' -Relation members | ForEach-Object { $Streamed.Add($_) }
                } catch {
                    $Caught = $PSItem
                }
                # The catch was reached, by the typed read's own record, with the untyped read already done.
                $null -ne $Caught | Should -BeTrue
                $Caught.Exception.Message | Should -Be 'Forbidden: denied'
                Should -Invoke Invoke-OERGraphRequest -Times 1 -Exactly -ParameterFilter { $Uri -eq 'v1.0/groups/22222222-2222-2222-2222-222222222222/members' }
                Should -Invoke Invoke-OERGraphRequest -Times 1 -Exactly -ParameterFilter { $Uri -eq 'v1.0/groups/22222222-2222-2222-2222-222222222222/members/microsoft.graph.servicePrincipal' }
                $Streamed.Count | Should -Be 0
            }
        }

        It 'streams nothing to the pipeline before it throws when the typed owners read fails' {
            InModuleScope Omnicit.EntraRBAC {
                Mock Invoke-OERGraphRequest { @{ value = @(@{ '@odata.type' = '#microsoft.graph.user'; id = 'u-1'; displayName = 'a user' }) } } -ParameterFilter { $Uri -eq 'v1.0/groups/22222222-2222-2222-2222-222222222222/owners' }
                Mock Invoke-OERGraphRequest {
                    throw [System.Management.Automation.ErrorRecord]::new([System.Exception]::new('Forbidden: denied'), 'Forbidden', 'PermissionDenied', $null)
                } -ParameterFilter { $Uri -eq 'v1.0/groups/22222222-2222-2222-2222-222222222222/owners/microsoft.graph.servicePrincipal' }
                $Streamed = [System.Collections.Generic.List[object]]::new()
                $Caught = $null
                try {
                    Get-OERGroupRelation -GroupId '22222222-2222-2222-2222-222222222222' -Relation owners | ForEach-Object { $Streamed.Add($_) }
                } catch {
                    $Caught = $PSItem
                }
                $null -ne $Caught | Should -BeTrue
                $Caught.Exception.Message | Should -Be 'Forbidden: denied'
                Should -Invoke Invoke-OERGraphRequest -Times 1 -Exactly -ParameterFilter { $Uri -eq 'v1.0/groups/22222222-2222-2222-2222-222222222222/owners' }
                Should -Invoke Invoke-OERGraphRequest -Times 1 -Exactly -ParameterFilter { $Uri -eq 'v1.0/groups/22222222-2222-2222-2222-222222222222/owners/microsoft.graph.servicePrincipal' }
                $Streamed.Count | Should -Be 0
            }
        }

        It 'throws, and never sends the typed members read, when the untyped members read fails' {
            InModuleScope Omnicit.EntraRBAC {
                Mock Invoke-OERGraphRequest {
                    throw [System.Management.Automation.ErrorRecord]::new([System.Exception]::new('Forbidden: denied'), 'Forbidden', 'PermissionDenied', $null)
                } -ParameterFilter { $Uri -eq 'v1.0/groups/22222222-2222-2222-2222-222222222222/members' }
                # Answered, so that a typed read that IS sent shows up as the -Times 0 failure below
                # and not as a "no mock matched" error the catch would also swallow.
                Mock Invoke-OERGraphRequest { @{ value = @() } } -ParameterFilter { $Uri -eq 'v1.0/groups/22222222-2222-2222-2222-222222222222/members/microsoft.graph.servicePrincipal' }
                $Collected = 'unset'
                $Caught = $null
                try {
                    $Collected = @(Get-OERGroupRelation -GroupId '22222222-2222-2222-2222-222222222222' -Relation members)
                } catch {
                    $Caught = $PSItem
                }
                $null -ne $Caught | Should -BeTrue
                $Caught.Exception.Message | Should -Be 'Forbidden: denied'
                $Collected | Should -Be 'unset'
                Should -Invoke Invoke-OERGraphRequest -Times 1 -Exactly -ParameterFilter { $Uri -eq 'v1.0/groups/22222222-2222-2222-2222-222222222222/members' }
                Should -Invoke Invoke-OERGraphRequest -Times 0 -ParameterFilter { $Uri -eq 'v1.0/groups/22222222-2222-2222-2222-222222222222/members/microsoft.graph.servicePrincipal' }
            }
        }

        It 'throws, and never sends the typed owners read, when the untyped owners read fails' {
            InModuleScope Omnicit.EntraRBAC {
                Mock Invoke-OERGraphRequest {
                    throw [System.Management.Automation.ErrorRecord]::new([System.Exception]::new('Forbidden: denied'), 'Forbidden', 'PermissionDenied', $null)
                } -ParameterFilter { $Uri -eq 'v1.0/groups/22222222-2222-2222-2222-222222222222/owners' }
                Mock Invoke-OERGraphRequest { @{ value = @() } } -ParameterFilter { $Uri -eq 'v1.0/groups/22222222-2222-2222-2222-222222222222/owners/microsoft.graph.servicePrincipal' }
                $Collected = 'unset'
                $Caught = $null
                try {
                    $Collected = @(Get-OERGroupRelation -GroupId '22222222-2222-2222-2222-222222222222' -Relation owners)
                } catch {
                    $Caught = $PSItem
                }
                $null -ne $Caught | Should -BeTrue
                $Caught.Exception.Message | Should -Be 'Forbidden: denied'
                $Collected | Should -Be 'unset'
                Should -Invoke Invoke-OERGraphRequest -Times 1 -Exactly -ParameterFilter { $Uri -eq 'v1.0/groups/22222222-2222-2222-2222-222222222222/owners' }
                Should -Invoke Invoke-OERGraphRequest -Times 0 -ParameterFilter { $Uri -eq 'v1.0/groups/22222222-2222-2222-2222-222222222222/owners/microsoft.graph.servicePrincipal' }
            }
        }
    }
}
