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

Describe 'New-OERApproverObject typed error records' {
    It 'throws UnknownApproverSpec as a typed record: New-OERApproverObject -Spec @{ Bogus = 1 }' {
        $Caught = InModuleScope 'Omnicit.EntraRBAC' {
            $Result = $null
            try { New-OERApproverObject -Spec @{ Bogus = 1 } } catch { $Result = $PSItem }
            $Result
        }
        $Caught | Should -BeOfType ([System.Management.Automation.ErrorRecord])
        $Caught.FullyQualifiedErrorId | Should -BeExactly 'UnknownApproverSpec'
        $Caught.CategoryInfo.Category | Should -Be 'InvalidArgument'
        $Caught.TargetObject | Should -BeOfType [hashtable]
        $Caught.TargetObject.ContainsKey('Bogus') | Should -BeTrue
        $Caught.Exception.Message | Should -BeExactly 'Unrecognized approver spec. Use one of: User, Group, Manager, InternalSponsor, ExternalSponsor. Got keys: Bogus.'
    }
}
