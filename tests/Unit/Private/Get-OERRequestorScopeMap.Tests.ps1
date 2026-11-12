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

Describe 'Get-OERRequestorScopeMap' {
    It 'returns the requestor scope names in the builder order, each with its allowedTargetScope value' {
        InModuleScope $script:moduleName {
            $Map = Get-OERRequestorScopeMap
            @($Map.Keys) | Should -BeExactly @(
                'AllMemberUsers', 'AllDirectoryUsers', 'AllExternalUsers', 'SpecificDirectoryUsers',
                'SpecificConnectedOrganizationUsers', 'AllConfiguredConnectedOrganizationUsers',
                'AllDirectoryServicePrincipals', 'AllDirectoryAgentIdentities',
                'SpecificDirectoryServicePrincipals', 'NoSubjects', 'NotSpecified')
            $Map['AllMemberUsers'] | Should -BeExactly 'allMemberUsers'
            $Map['AllDirectoryUsers'] | Should -BeExactly 'allDirectoryUsers'
            $Map['AllExternalUsers'] | Should -BeExactly 'allExternalUsers'
            $Map['SpecificDirectoryUsers'] | Should -BeExactly 'specificDirectoryUsers'
            $Map['SpecificConnectedOrganizationUsers'] | Should -BeExactly 'specificConnectedOrganizationUsers'
            $Map['AllConfiguredConnectedOrganizationUsers'] | Should -BeExactly 'allConfiguredConnectedOrganizationUsers'
            $Map['AllDirectoryServicePrincipals'] | Should -BeExactly 'allDirectoryServicePrincipals'
            $Map['AllDirectoryAgentIdentities'] | Should -BeExactly 'allDirectoryAgentIdentities'
            $Map['NotSpecified'] | Should -BeExactly 'notSpecified'
        }
    }

    It 'maps NoSubjects to notSpecified and holds $null for SpecificDirectoryServicePrincipals' {
        InModuleScope $script:moduleName {
            $Map = Get-OERRequestorScopeMap
            $Map['NoSubjects'] | Should -BeExactly 'notSpecified'
            $Map.Contains('SpecificDirectoryServicePrincipals') | Should -BeTrue
            $Map['SpecificDirectoryServicePrincipals'] | Should -BeNullOrEmpty
        }
    }

    It 'does not list unknownFutureValue as a scope name' {
        InModuleScope $script:moduleName {
            @((Get-OERRequestorScopeMap).Keys) | Should -Not -Contain 'unknownFutureValue'
        }
    }

    It 'returns a new dictionary on every call, so a change never reaches another caller' {
        InModuleScope $script:moduleName {
            $First = Get-OERRequestorScopeMap
            $First['AllMemberUsers'] = 'changed'
            $First.Remove('NotSpecified')
            $Second = Get-OERRequestorScopeMap
            $Second['AllMemberUsers'] | Should -BeExactly 'allMemberUsers'
            $Second.Contains('NotSpecified') | Should -BeTrue
        }
    }
}
