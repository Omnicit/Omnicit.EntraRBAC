BeforeAll {
    $script:moduleName = 'Omnicit.EntraRBAC'
    Get-Module $script:moduleName | Remove-Module -Force -ErrorAction SilentlyContinue
    Import-Module $script:moduleName -Force -ErrorAction Stop
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
}
