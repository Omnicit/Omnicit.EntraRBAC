BeforeAll {
    $script:moduleName = 'Omnicit.EntraRBAC'
    Get-Module $script:moduleName | Remove-Module -Force -ErrorAction SilentlyContinue
    Import-Module $script:moduleName -Force -ErrorAction Stop
    . "$PSScriptRoot/../TestHelpers/OERTransportTripwire.ps1"
    Install-OERTransportTripwire
}

AfterAll {
    try { Assert-OERTransportTripwire } finally { Uninstall-OERTransportTripwire }
}

Describe 'ConvertTo-OERPruneWithheldResult' {
    It 'returns nothing when no declared entry is unresolved' {
        InModuleScope $script:moduleName {
            $Empty = [System.Collections.Generic.List[string]]::new()
            $r = @(ConvertTo-OERPruneWithheldResult -Section 'groups' -Item 'g1' -Unresolved $Empty -Candidate "undeclared member 'u-1'")
            $r.Count | Should -Be 0
        }
    }

    It 'returns nothing for an empty array as well as an empty list' {
        InModuleScope $script:moduleName {
            $r = @(ConvertTo-OERPruneWithheldResult -Section 'groups' -Item 'g1' -Unresolved @() -Candidate "undeclared member 'u-1'")
            $r.Count | Should -Be 0
        }
    }

    It 'returns one Skipped StructureResult carrying Section and Item for a single unresolved entry' {
        InModuleScope $script:moduleName {
            $One = [System.Collections.Generic.List[string]]::new()
            $One.Add('x')
            $r = @(ConvertTo-OERPruneWithheldResult -Section 'administrativeUnits' -Item 'AU-IT' -Unresolved $One -Candidate "undeclared member 'u-1'")
            $r.Count | Should -Be 1
            $r[0].PSObject.TypeNames[0] | Should -Be 'Omnicit.EntraRBAC.StructureResult'
            $r[0].Section | Should -Be 'administrativeUnits'
            $r[0].Item    | Should -Be 'AU-IT'
            $r[0].Action  | Should -Be 'Skipped'
            $r[0].Error   | Should -BeNullOrEmpty
        }
    }

    It 'starts the single-entry Detail with the exact withheld phrase and names the candidate' {
        InModuleScope $script:moduleName {
            $r = ConvertTo-OERPruneWithheldResult -Section 'groups' -Item 'g1' -Unresolved @('x') -Candidate "undeclared member 'u-1'"
            $r.Detail.StartsWith("prune withheld: declared entry 'x' could not be resolved") | Should -BeTrue
            $r.Detail | Should -BeExactly "prune withheld: declared entry 'x' could not be resolved, so undeclared member 'u-1' may be its live counterpart and is left in place (our own guard, not a Graph rejection). Fix or remove the unresolved entry to reconcile this collection."
        }
    }

    It 'still returns the Skipped record when an unresolved entry label is an empty string' {
        InModuleScope $script:moduleName {
            $WithEmpty = [System.Collections.Generic.List[string]]::new()
            $WithEmpty.Add('')
            $r = @(ConvertTo-OERPruneWithheldResult -Section 'groups' -Item 'g1' -Unresolved $WithEmpty -Candidate "undeclared member 'u-1'")
            $r.Count | Should -Be 1
            $r[0].Action | Should -Be 'Skipped'
            $r[0].Detail | Should -Match '^prune withheld: declared entry '''' could not be resolved'
        }
    }

    It 'uses the plural form and names every unresolved entry in the given order' {
        InModuleScope $script:moduleName {
            $Two = [System.Collections.Generic.List[string]]::new()
            $Two.Add('b-second-in-alphabet')
            $Two.Add('a-first-in-alphabet')
            $r = @(ConvertTo-OERPruneWithheldResult -Section 'groups' -Item 'g1' -Unresolved $Two -Candidate "undeclared owner 'o-9'")
            $r.Count | Should -Be 1
            $r[0].Action | Should -Be 'Skipped'
            $r[0].Detail | Should -BeExactly "prune withheld: declared entries 'b-second-in-alphabet', 'a-first-in-alphabet' could not be resolved, so undeclared owner 'o-9' may be the live counterpart of one of them and is left in place (our own guard, not a Graph rejection). Fix or remove the unresolved entries to reconcile this collection."
        }
    }

    # A declared entry whose SCOPE could not be resolved (roleAssignments) is a different kind of
    # unresolved: the entry carries no scope, so it may be another spelling of ANY scope in the
    # section, and every candidate in the section is withheld, not only those of one collection.
    Context 'with an unresolved scope (-UnresolvedScope)' {
        It 'returns one Skipped StructureResult carrying Section and Item when only a scope is unresolved' {
            InModuleScope $script:moduleName {
                $r = @(ConvertTo-OERPruneWithheldResult -Section 'roleAssignments' -Item 'rd-reader -> p-1 @ /subscriptions/s-1' -Unresolved @() -UnresolvedScope @('Reader -> x @ sub:Gone') -Candidate "undeclared assignment 'a-1'")
                $r.Count | Should -Be 1
                $r[0].PSObject.TypeNames[0] | Should -Be 'Omnicit.EntraRBAC.StructureResult'
                $r[0].Section | Should -Be 'roleAssignments'
                $r[0].Item    | Should -Be 'rd-reader -> p-1 @ /subscriptions/s-1'
                $r[0].Action  | Should -Be 'Skipped'
                $r[0].Error   | Should -BeNullOrEmpty
            }
        }

        It 'words a single unresolved scope as a section-wide withhold and names the candidate' {
            InModuleScope $script:moduleName {
                $r = ConvertTo-OERPruneWithheldResult -Section 'roleAssignments' -Item 'i' -Unresolved @() -UnresolvedScope @('Reader -> x @ sub:Gone') -Candidate "undeclared assignment 'a-1'"
                $r.Detail.StartsWith("prune withheld: the scope of declared entry 'Reader -> x @ sub:Gone'") | Should -BeTrue
                $r.Detail | Should -BeExactly "prune withheld: the scope of declared entry 'Reader -> x @ sub:Gone' could not be resolved, so it may name this scope, and undeclared assignment 'a-1' may be the live counterpart of that entry; it is left in place (our own guard, not a Graph rejection). Fix or remove the unresolved entry to reconcile this section."
            }
        }

        It 'uses the plural form and names every unresolved scope in the given order' {
            InModuleScope $script:moduleName {
                $r = ConvertTo-OERPruneWithheldResult -Section 'roleAssignments' -Item 'i' -Unresolved @() -UnresolvedScope @('Reader -> b @ sub:Two', 'Reader -> a @ sub:One') -Candidate "undeclared assignment 'a-1'"
                $r.Detail | Should -BeExactly "prune withheld: the scopes of declared entries 'Reader -> b @ sub:Two', 'Reader -> a @ sub:One' could not be resolved, so any of them may name this scope, and undeclared assignment 'a-1' may be the live counterpart of one of them; it is left in place (our own guard, not a Graph rejection). Fix or remove the unresolved entries to reconcile this section."
            }
        }

        It 'puts the entry sentence first and the scope sentence after it when both are unresolved' {
            InModuleScope $script:moduleName {
                $r = ConvertTo-OERPruneWithheldResult -Section 'roleAssignments' -Item 'i' -Unresolved @('Reader -> p @ sub:Prod') -UnresolvedScope @('Reader -> x @ sub:Gone') -Candidate "undeclared assignment 'a-1'"
                $r.Detail | Should -BeExactly "prune withheld: declared entry 'Reader -> p @ sub:Prod' could not be resolved, so undeclared assignment 'a-1' may be its live counterpart and is left in place (our own guard, not a Graph rejection). Fix or remove the unresolved entry to reconcile this collection. The scope of declared entry 'Reader -> x @ sub:Gone' could not be resolved either."
            }
        }

        It 'uses the plural scope sentence after several unresolved entries and several unresolved scopes' {
            InModuleScope $script:moduleName {
                $r = ConvertTo-OERPruneWithheldResult -Section 'roleAssignments' -Item 'i' -Unresolved @('e-1', 'e-2') -UnresolvedScope @('s-1', 's-2') -Candidate "undeclared assignment 'a-1'"
                $r.Detail | Should -BeExactly "prune withheld: declared entries 'e-1', 'e-2' could not be resolved, so undeclared assignment 'a-1' may be the live counterpart of one of them and is left in place (our own guard, not a Graph rejection). Fix or remove the unresolved entries to reconcile this collection. The scopes of declared entries 's-1', 's-2' could not be resolved either."
            }
        }

        It 'keeps the entry-only text byte for byte when -UnresolvedScope is given but empty' {
            InModuleScope $script:moduleName {
                $Without = ConvertTo-OERPruneWithheldResult -Section 'groups' -Item 'g1' -Unresolved @('x') -Candidate "undeclared member 'u-1'"
                $With    = ConvertTo-OERPruneWithheldResult -Section 'groups' -Item 'g1' -Unresolved @('x') -UnresolvedScope @() -Candidate "undeclared member 'u-1'"
                $With.Detail | Should -BeExactly $Without.Detail
                $With.Detail | Should -Not -Match 'scope'
            }
        }

        It 'returns nothing when both lists are empty' {
            InModuleScope $script:moduleName {
                $r = @(ConvertTo-OERPruneWithheldResult -Section 'roleAssignments' -Item 'i' -Unresolved @() -UnresolvedScope @() -Candidate "undeclared assignment 'a-1'")
                $r.Count | Should -Be 0
            }
        }
    }

    # A third kind of entry: a live administrative unit scoped role whose NAME the directory role list
    # did not give (role id known, name blank), held by a principal for whom the document declares a role
    # by name that no live role matches. Unlike the two kinds above this one is not collection-wide and is
    # not a lookup failure: the helper always returns the record, and the record names the role ids.
    Context 'with an unnamed live scoped role (-Declared / -UnnamedRoleId)' {
        It 'names one unnamed live role by its id and says neither side is touched' {
            InModuleScope $script:moduleName {
                $R = ConvertTo-OERPruneWithheldResult -Section 'administrativeUnits' -Item 'AU-IT' `
                    -Declared "scopedRole 'User Administrator' for 'person1@example.com'" -UnnamedRoleId @('dirrole-1')
                @($R).Count | Should -Be 1
                $R.PSObject.TypeNames[0] | Should -BeExactly 'Omnicit.EntraRBAC.StructureResult'
                $R.Action | Should -BeExactly 'Skipped'
                $R.Section | Should -BeExactly 'administrativeUnits'
                $R.Item | Should -BeExactly 'AU-IT'
                $R.Error | Should -BeNullOrEmpty
                $R.Detail | Should -BeExactly ("prune withheld: scopedRole 'User Administrator' for 'person1@example.com' matches no live scoped role by name, " +
                    "and the principal holds a live scoped role on this unit whose name could not be read (role id 'dirrole-1'), which may be that role; " +
                    'it is neither added nor removed (our own guard, not a Graph rejection). Declare the role by the directory role id its live scoped role carries (RoleId in Get-OERAdministrativeUnit -IncludeScopedRoles) to reconcile it.')
            }
        }

        It 'names several unnamed live roles by their ids' {
            InModuleScope $script:moduleName {
                $R = ConvertTo-OERPruneWithheldResult -Section 'administrativeUnits' -Item 'AU-IT' `
                    -Declared "scopedRole 'User Administrator' for 'p'" -UnnamedRoleId @('dirrole-1', 'dirrole-2')
                @($R).Count | Should -Be 1
                $R.Action | Should -BeExactly 'Skipped'
                $R.Detail | Should -BeExactly ("prune withheld: scopedRole 'User Administrator' for 'p' matches no live scoped role by name, " +
                    "and the principal holds 2 live scoped roles on this unit whose names could not be read (role ids 'dirrole-1', 'dirrole-2'), any of which may be that role; " +
                    'none of them is added or removed (our own guard, not a Graph rejection). Declare the role by the directory role id its live scoped role carries (RoleId in Get-OERAdministrativeUnit -IncludeScopedRoles) to reconcile it.')
            }
        }

        It 'keeps the default parameter set, so a call naming -Unresolved and -Candidate still binds as before' {
            InModuleScope $script:moduleName {
                $R = ConvertTo-OERPruneWithheldResult -Section 'groups' -Item 'g1' -Unresolved @('x') -Candidate "undeclared member 'u-1'"
                @($R).Count | Should -Be 1
                $R.Detail | Should -Not -Match 'could not be read'
                $R.Detail | Should -Match '^prune withheld: declared entry ''x'' could not be resolved'
                (Get-Command ConvertTo-OERPruneWithheldResult).DefaultParameterSet | Should -BeExactly 'Unresolved'
            }
        }

        It 'refuses a call that mixes the two parameter sets' {
            InModuleScope $script:moduleName {
                { ConvertTo-OERPruneWithheldResult -Section 'administrativeUnits' -Item 'i' -Unresolved @('x') -Candidate 'c' `
                        -Declared 'd' -UnnamedRoleId @('r') -ErrorAction Stop } | Should -Throw -ErrorId 'AmbiguousParameterSet*'
            }
        }
    }

    # A fourth kind (A9, Sprint 9 step 1 round 1): a LIVE group member or owner that is a service
    # principal. No version before the typed read saw one, so no earlier document lists one, and the
    # group prune never removes one. The helper owns that rule (which object type is withheld) and
    # both of its texts: under -Prune the Skipped record, without it the Extra record, whose hint
    # must not tell the reader that -Prune removes it. It returns nothing for any other type, so the
    # caller carries on exactly as before.
    Context 'with the live object type of a group member or owner (-ObjectType)' {
        It 'returns one Skipped StructureResult for a service principal under -Prune, with the exact reason' {
            InModuleScope $script:moduleName {
                $R = @(ConvertTo-OERPruneWithheldResult -Section 'groups' -Item 'role_sec_x' -ObjectType 'servicePrincipal' -Candidate "undeclared member 'sp-1'" -Prune)
                $R.Count | Should -Be 1
                $R[0].PSObject.TypeNames[0] | Should -BeExactly 'Omnicit.EntraRBAC.StructureResult'
                $R[0].Section | Should -BeExactly 'groups'
                $R[0].Item | Should -BeExactly 'role_sec_x'
                $R[0].Action | Should -BeExactly 'Skipped'
                $R[0].Error | Should -BeNullOrEmpty
                $R[0].Detail | Should -BeExactly ("prune withheld: undeclared member 'sp-1' is a service principal, and -Prune never removes a service principal from a group; " +
                    'it is left in place (our own guard, not a Graph rejection). Remove it with Remove-OERGroupMember (-AccessType owner for an owner) if it is meant to go.')
            }
        }

        It 'returns one Extra StructureResult for a service principal without -Prune, whose hint says -Prune leaves it' {
            InModuleScope $script:moduleName {
                $R = @(ConvertTo-OERPruneWithheldResult -Section 'groups' -Item 'role_sec_x' -ObjectType 'servicePrincipal' -Candidate "undeclared member 'sp-1'")
                $R.Count | Should -Be 1
                $R[0].PSObject.TypeNames[0] | Should -BeExactly 'Omnicit.EntraRBAC.StructureResult'
                $R[0].Section | Should -BeExactly 'groups'
                $R[0].Item | Should -BeExactly 'role_sec_x'
                $R[0].Action | Should -BeExactly 'Extra'
                $R[0].Error | Should -BeNullOrEmpty
                $R[0].Detail | Should -BeExactly "undeclared member 'sp-1' (a service principal, which -Prune leaves in place)"
            }
        }

        It 'names an owner candidate the same way, with and without -Prune' {
            InModuleScope $script:moduleName {
                $R = ConvertTo-OERPruneWithheldResult -Section 'groups' -Item 'g1' -ObjectType 'servicePrincipal' -Candidate "undeclared owner 'sp-9'" -Prune
                $R.Detail | Should -BeLike "prune withheld: undeclared owner 'sp-9' is a service principal, and -Prune never removes a service principal from a group; *"
                $R = ConvertTo-OERPruneWithheldResult -Section 'groups' -Item 'g1' -ObjectType 'servicePrincipal' -Candidate "undeclared owner 'sp-9'"
                $R.Detail | Should -BeExactly "undeclared owner 'sp-9' (a service principal, which -Prune leaves in place)"
            }
        }

        It 'matches the type the way the handler compares strings, ignoring case' {
            InModuleScope $script:moduleName {
                @(ConvertTo-OERPruneWithheldResult -Section 'groups' -Item 'g1' -ObjectType 'ServicePrincipal' -Candidate "undeclared member 'sp-1'" -Prune).Count | Should -Be 1
            }
        }

        It 'returns nothing for a <Label>, with or without -Prune, so the caller reports or prunes it as before' -ForEach @(
            @{ Label = 'user'; Type = 'user' }
            @{ Label = 'group'; Type = 'group' }
            @{ Label = 'device'; Type = 'device' }
            @{ Label = 'type that only starts like one'; Type = 'servicePrincipalX' }
            @{ Label = 'blank type'; Type = '' }
            @{ Label = 'missing type'; Type = $null }
        ) {
            InModuleScope $script:moduleName -Parameters @{ Type = $Type } {
                param($Type)
                @(ConvertTo-OERPruneWithheldResult -Section 'groups' -Item 'g1' -ObjectType $Type -Candidate "undeclared member 'u-1'" -Prune).Count | Should -Be 0
                @(ConvertTo-OERPruneWithheldResult -Section 'groups' -Item 'g1' -ObjectType $Type -Candidate "undeclared member 'u-1'").Count | Should -Be 0
            }
        }

        It 'refuses a call that mixes -ObjectType with -Unresolved' {
            InModuleScope $script:moduleName {
                { ConvertTo-OERPruneWithheldResult -Section 'groups' -Item 'g1' -Unresolved @('x') -ObjectType 'servicePrincipal' `
                        -Candidate 'c' -ErrorAction Stop } | Should -Throw -ErrorId 'AmbiguousParameterSet*'
            }
        }
    }

    # A fifth kind (BL-07, Sprint 9 step 6): a LIVE administrative unit member that is a group the
    # groups section created INTO this unit in the same run (New-OERGroup -AdministrativeUnit).
    # administrativeUnit never round-trips, so the unit's own entry need not list the group, and the
    # run that created the membership must not remove it. The caller decides that the candidate is
    # such a group; the helper owns the text: under -Prune one Skipped record, without -Prune nothing,
    # so the pass reports Extra exactly as before.
    Context 'with a group created into the unit in this run (-CreatedGroup)' {
        It 'returns one Skipped StructureResult under -Prune, with the exact reason' {
            InModuleScope $script:moduleName {
                $R = @(ConvertTo-OERPruneWithheldResult -Section 'administrativeUnits' -Item 'AU-IT' `
                        -Candidate "undeclared member '88888888-8888-8888-8888-888888888888'" -CreatedGroup 'grp-new' -Prune)
                $R.Count | Should -Be 1
                $R[0].PSObject.TypeNames[0] | Should -BeExactly 'Omnicit.EntraRBAC.StructureResult'
                $R[0].Section | Should -BeExactly 'administrativeUnits'
                $R[0].Item | Should -BeExactly 'AU-IT'
                $R[0].Action | Should -BeExactly 'Skipped'
                $R[0].Error | Should -BeNullOrEmpty
                # One text, true for a group the run created into the unit AND for one New-OERGroup
                # found already existing (the handler cannot tell the two apart; BL-100, ruling R2).
                $R[0].Detail | Should -BeExactly ("prune withheld: undeclared member '88888888-8888-8888-8888-888888888888' is group 'grp-new', " +
                    'which the groups section of this run either created into this unit or, when the group already existed, found in place of creating it; ' +
                    'this run does not remove that membership (our own guard, not a Graph rejection). ' +
                    "The next apply with -Prune removes it unless the unit's members name the group.")
                # The earlier text claimed a create in both cases; the assertion above is the proof the
                # path was reached, this one that the false claim is gone.
                $R[0].Detail | Should -Not -BeLike '*which this run created into this unit*'
            }
        }

        It 'returns nothing without -Prune, so the pass reports the candidate Extra as before' {
            InModuleScope $script:moduleName {
                @(ConvertTo-OERPruneWithheldResult -Section 'administrativeUnits' -Item 'AU-IT' `
                        -Candidate "undeclared member '88888888-8888-8888-8888-888888888888'" -CreatedGroup 'grp-new').Count | Should -Be 0
                @(ConvertTo-OERPruneWithheldResult -Section 'administrativeUnits' -Item 'AU-IT' `
                        -Candidate "undeclared member '88888888-8888-8888-8888-888888888888'" -CreatedGroup 'grp-new' -Prune:$false).Count | Should -Be 0
            }
        }

        It 'refuses a call that mixes -CreatedGroup with -ObjectType' {
            InModuleScope $script:moduleName {
                { ConvertTo-OERPruneWithheldResult -Section 'administrativeUnits' -Item 'AU-IT' -Candidate 'c' -CreatedGroup 'grp-new' `
                        -ObjectType 'servicePrincipal' -Prune -ErrorAction Stop } | Should -Throw -ErrorId 'AmbiguousParameterSet*'
            }
        }
    }
}
