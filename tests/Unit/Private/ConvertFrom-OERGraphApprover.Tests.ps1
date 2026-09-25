BeforeAll {
    Import-Module Omnicit.EntraRBAC -Force
}

Describe 'ConvertFrom-OERGraphApprover' {
    It 'reads a v1.0 / PATCH-shaped user approver from userId' {
        InModuleScope Omnicit.EntraRBAC {
            $R = ConvertFrom-OERGraphApprover -Approver @{ '@odata.type' = '#microsoft.graph.singleUser'; userId = 'user-1' }
            $R.Id | Should -Be 'user-1'
            $R.UserType | Should -Be 'User'
        }
    }
    It 'reads a v1.0 / PATCH-shaped group approver from groupId' {
        InModuleScope Omnicit.EntraRBAC {
            $R = ConvertFrom-OERGraphApprover -Approver ([PSCustomObject]@{ '@odata.type' = '#microsoft.graph.groupMembers'; groupId = 'grp-1' })
            $R.Id | Should -Be 'grp-1'
            $R.UserType | Should -Be 'Group'
        }
    }
    It 'reads a beta-shaped group approver, which carries the id as id and no groupId' {
        InModuleScope Omnicit.EntraRBAC {
            $Beta = [PSCustomObject]@{ '@odata.type' = '#microsoft.graph.groupMembers'; id = 'grp-1'; description = 'Approvers'; isBackup = $false }
            $R = ConvertFrom-OERGraphApprover -Approver $Beta
            $R.Id | Should -Be 'grp-1'
            $R.UserType | Should -Be 'Group'
            $R.DisplayName | Should -Be 'Approvers'
        }
    }
    It 'reads a beta-shaped user approver from id' {
        InModuleScope Omnicit.EntraRBAC {
            $R = ConvertFrom-OERGraphApprover -Approver ([PSCustomObject]@{ '@odata.type' = '#microsoft.graph.singleUser'; id = 'user-1'; description = 'Person One' })
            $R.Id | Should -Be 'user-1'
            $R.UserType | Should -Be 'User'
        }
    }
    It 'prefers groupId over id when both are present' {
        InModuleScope Omnicit.EntraRBAC {
            (ConvertFrom-OERGraphApprover -Approver @{ '@odata.type' = '#microsoft.graph.groupMembers'; groupId = 'grp-1'; id = 'other' }).Id | Should -Be 'grp-1'
        }
    }
    It 'infers the kind from the id field when @odata.type is missing' {
        InModuleScope Omnicit.EntraRBAC {
            (ConvertFrom-OERGraphApprover -Approver @{ groupId = 'grp-1' }).UserType | Should -Be 'Group'
            (ConvertFrom-OERGraphApprover -Approver @{ userId = 'user-1' }).UserType | Should -Be 'User'
        }
    }
    It 'returns an empty UserType for an approver kind that is neither a user nor a group' {
        InModuleScope Omnicit.EntraRBAC {
            $R = ConvertFrom-OERGraphApprover -Approver @{ '@odata.type' = '#microsoft.graph.requestorManager'; managerLevel = 1 }
            $R.UserType | Should -Be ''
            $R.Id | Should -Be ''
        }
    }
    It 'reads what New-OERApproverObject builds, so a PATCH body round-trips' {
        InModuleScope Omnicit.EntraRBAC {
            (ConvertFrom-OERGraphApprover -Approver (New-OERApproverObject -Spec @{ Group = 'grp-1' })).Id | Should -Be 'grp-1'
            (ConvertFrom-OERGraphApprover -Approver (New-OERApproverObject -Spec @{ User = 'user-1' })).Id | Should -Be 'user-1'
        }
    }
    It 'emits nothing for a null approver' {
        InModuleScope Omnicit.EntraRBAC {
            @(ConvertFrom-OERGraphApprover -Approver $null).Count | Should -Be 0
        }
    }
}
