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
}
