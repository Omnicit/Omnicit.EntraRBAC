BeforeAll {
    $script:moduleName = 'Omnicit.EntraRBAC'
    Get-Module $script:moduleName | Remove-Module -Force -ErrorAction SilentlyContinue
    Import-Module $script:moduleName -Force -ErrorAction Stop
}

Describe 'New-OERApproverObject' {
    It 'builds a singleUser approver from @{ User = guid }' {
        InModuleScope $script:moduleName {
            $O = New-OERApproverObject -Spec @{ User = 'u-1' }
            $O['@odata.type'] | Should -Be '#microsoft.graph.singleUser'
            $O.userId | Should -Be 'u-1'
        }
    }
    It 'builds a groupMembers approver from @{ Group = guid }' {
        InModuleScope $script:moduleName {
            $O = New-OERApproverObject -Spec @{ Group = 'g-1' }
            $O['@odata.type'] | Should -Be '#microsoft.graph.groupMembers'
            $O.groupId | Should -Be 'g-1'
        }
    }
    It 'builds a requestorManager approver with manager level' {
        InModuleScope $script:moduleName {
            $O = New-OERApproverObject -Spec @{ Manager = $true; ManagerLevel = 2 }
            $O['@odata.type'] | Should -Be '#microsoft.graph.requestorManager'
            $O.managerLevel | Should -Be 2
        }
    }
    It 'builds internal and external sponsor approvers' {
        InModuleScope $script:moduleName {
            (New-OERApproverObject -Spec @{ InternalSponsor = $true })['@odata.type'] | Should -Be '#microsoft.graph.internalSponsors'
            (New-OERApproverObject -Spec @{ ExternalSponsor = $true })['@odata.type'] | Should -Be '#microsoft.graph.externalSponsors'
        }
    }
    It 'throws on an unrecognized spec' {
        InModuleScope $script:moduleName { { New-OERApproverObject -Spec @{ Nope = 'x' } } | Should -Throw }
    }
    It 'defaults managerLevel to 1 when ManagerLevel is not specified' {
        InModuleScope $script:moduleName {
            $O = New-OERApproverObject -Spec @{ Manager = $true }
            $O['@odata.type'] | Should -Be '#microsoft.graph.requestorManager'
            $O.managerLevel | Should -Be 1
        }
    }
}
