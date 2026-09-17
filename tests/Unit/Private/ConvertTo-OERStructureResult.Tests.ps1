BeforeAll {
    $script:moduleName = 'Omnicit.EntraRBAC'
    Get-Module $script:moduleName | Remove-Module -Force -ErrorAction SilentlyContinue
    Import-Module $script:moduleName -Force -ErrorAction Stop
}

Describe 'ConvertTo-OERStructureResult' {
    It 'tags the object Omnicit.EntraRBAC.StructureResult' {
        InModuleScope $script:moduleName {
            $r = ConvertTo-OERStructureResult -Section 'groups' -Item 'g1' -Action 'Created' -Detail 'made it'
            $r.PSObject.TypeNames[0] | Should -Be 'Omnicit.EntraRBAC.StructureResult'
        }
    }
    It 'carries Section/Item/Action/Detail/Error' {
        InModuleScope $script:moduleName {
            $r = ConvertTo-OERStructureResult -Section 'groups' -Item 'g1' -Action 'Created' -Detail 'd'
            $r.Section | Should -Be 'groups'; $r.Item | Should -Be 'g1'
            $r.Action  | Should -Be 'Created'; $r.Detail | Should -Be 'd'
            $r.Error   | Should -BeNullOrEmpty
        }
    }
    It 'defaults Detail to empty and Error to null' {
        InModuleScope $script:moduleName {
            $r = ConvertTo-OERStructureResult -Section 'groups' -Item 'g1' -Action 'Unchanged'
            $r.Detail | Should -Be ''; $r.Error | Should -BeNullOrEmpty
        }
    }
    It 'records an ErrorRecord on Failed' {
        InModuleScope $script:moduleName {
            $er = [System.Management.Automation.ErrorRecord]::new([System.Exception]::new('boom'),'X',[System.Management.Automation.ErrorCategory]::NotSpecified,$null)
            $r = ConvertTo-OERStructureResult -Section 'groups' -Item 'g1' -Action 'Failed' -ErrorRecord $er
            $r.Action | Should -Be 'Failed'; $r.Error.Exception.Message | Should -Be 'boom'
        }
    }
    It 'has a registered format view that groups by Section' {
        $f = (InModuleScope $script:moduleName { ConvertTo-OERStructureResult -Section 'groups' -Item 'g1' -Action 'Created' -Detail 'd' }) | Format-Table | Out-String
        $f | Should -Match 'Action'
        # The registered view groups by Section, producing a 'Section: groups' header that the
        # default list/table rendering (no view) does not emit -- proves the view actually fired.
        $f | Should -Match 'Section: groups'
    }
}
