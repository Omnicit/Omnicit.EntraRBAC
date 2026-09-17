BeforeAll {
    $script:moduleName = 'Omnicit.EntraRBAC'
    Get-Module $script:moduleName | Remove-Module -Force -ErrorAction SilentlyContinue
    Import-Module $script:moduleName -Force -ErrorAction Stop
}

Describe 'Resolve-OERStructureEnumCasing' {
    It 'returns the canonical spelling for a value that already matches' {
        InModuleScope $script:moduleName {
            Resolve-OERStructureEnumCasing -EnumName 'accessType' -Value 'member' | Should -Be 'member'
            Resolve-OERStructureEnumCasing -EnumName 'principalType' -Value 'ServicePrincipal' | Should -Be 'ServicePrincipal'
        }
    }

    It 'maps a differently cased value onto the canonical spelling' {
        InModuleScope $script:moduleName {
            Resolve-OERStructureEnumCasing -EnumName 'accessType' -Value 'Member' | Should -Be 'member'
            Resolve-OERStructureEnumCasing -EnumName 'accessType' -Value 'OWNER' | Should -Be 'owner'
            Resolve-OERStructureEnumCasing -EnumName 'membershipRuleProcessingState' -Value 'on' | Should -Be 'On'
            Resolve-OERStructureEnumCasing -EnumName 'catalogResourceType' -Value 'sharepointsite' | Should -Be 'SharePointSite'
            Resolve-OERStructureEnumCasing -EnumName 'enablement' -Value 'multifactorauthentication' | Should -Be 'MultiFactorAuthentication'
            Resolve-OERStructureEnumCasing -EnumName 'accessReviewRecurrence' -Value 'onetime' | Should -Be 'OneTime'
            Resolve-OERStructureEnumCasing -EnumName 'accessReviewDefaultDecision' -Value 'recommendation' | Should -Be 'Recommendation'
            Resolve-OERStructureEnumCasing -EnumName 'approverInfoVisibility' -Value 'notvisible' | Should -Be 'NotVisible'
        }
    }

    It 'returns null for a value that is not a member of the enum' {
        InModuleScope $script:moduleName {
            $Result = Resolve-OERStructureEnumCasing -EnumName 'accessType' -Value 'guest'
            # Not Should -BeNullOrEmpty: an empty string would pass that and must not.
            $null -eq $Result | Should -Be $true
        }
    }

    It 'returns null for an empty or null value rather than throwing' {
        InModuleScope $script:moduleName {
            $null -eq (Resolve-OERStructureEnumCasing -EnumName 'accessType' -Value '') | Should -Be $true
            $null -eq (Resolve-OERStructureEnumCasing -EnumName 'accessType' -Value $null) | Should -Be $true
        }
    }

    It 'lists the canonical set for every enum it owns' {
        InModuleScope $script:moduleName {
            $Expected = @{
                accessType                    = @('member', 'owner')
                enablement                    = @('Justification', 'MultiFactorAuthentication', 'Ticketing')
                membershipRuleProcessingState = @('On', 'Paused')
                catalogResourceType           = @('Group', 'Application', 'SharePointSite')
                approverInfoVisibility        = @('Default', 'Visible', 'NotVisible')
                accessReviewRecurrence        = @('OneTime', 'Weekly', 'Monthly', 'Quarterly', 'Annually')
                accessReviewDefaultDecision   = @('None', 'Approve', 'Deny', 'Recommendation')
                principalType                 = @('User', 'Group', 'ServicePrincipal')
            }
            foreach ($Name in $Expected.Keys) {
                $Actual = @(Resolve-OERStructureEnumCasing -EnumName $Name -List)
                # -join makes both order and casing part of the assertion.
                ($Actual -join ',') | Should -BeExactly (($Expected[$Name]) -join ',') -Because "'$Name' is declared in Get-OERStructureSchemaJson in this order"
            }
        }
    }

    It 'rejects an enum name it does not own' {
        InModuleScope $script:moduleName {
            { Resolve-OERStructureEnumCasing -EnumName 'notAnEnum' -Value 'x' } | Should -Throw
        }
    }
}
