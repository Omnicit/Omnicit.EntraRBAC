BeforeAll {
    Import-Module Omnicit.EntraRBAC -Force
}

Describe 'Get-OERRequiredScope' {
    Context 'Whole table' {
        It 'Returns every entry when no filter is supplied' {
            $All = @(Get-OERRequiredScope)
            $Expected = InModuleScope Omnicit.EntraRBAC { @(Get-OERRequiredScopeMap).Count }

            $All.Count | Should -Be $Expected
        }

        It 'Tags every entry with the RequiredScope type name' {
            $All = @(Get-OERRequiredScope)

            $All | Should -Not -BeNullOrEmpty
            foreach ($Entry in $All) {
                $Entry.PSObject.TypeNames[0] | Should -Be 'Omnicit.EntraRBAC.RequiredScope'
            }
        }

        It 'Returns entries in a stable alphabetical order' {
            $Names = @(Get-OERRequiredScope).Cmdlet

            ($Names -join '|') | Should -Be (($Names | Sort-Object) -join '|')
        }
    }

    Context 'Ordering of a filtered result' {
        It 'Follows the order the names were asked for, not the table order' {
            <#
                Pinned deliberately. The unfiltered table is alphabetical because that is how the
                map stores it, but an explicit request is answered in the order it was made -- and
                without this case the alphabetical assertion above would let either behaviour pass.
            #>
            $Forward = @(Get-OERRequiredScope -Cmdlet 'New-OERGroup', 'Add-OERGroupMember').Cmdlet
            $Reverse = @(Get-OERRequiredScope -Cmdlet 'Add-OERGroupMember', 'New-OERGroup').Cmdlet

            ($Forward -join '|') | Should -Be 'New-OERGroup|Add-OERGroupMember'
            ($Reverse -join '|') | Should -Be 'Add-OERGroupMember|New-OERGroup'
        }

        It 'Sorts the -Unique permission arrays regardless of the order asked for' {
            $Forward = Get-OERRequiredScope -Cmdlet 'New-OERGroup', 'Add-OERGroupMember' -Unique
            $Reverse = Get-OERRequiredScope -Cmdlet 'Add-OERGroupMember', 'New-OERGroup' -Unique

            ($Forward.GraphScope -join '|') | Should -Be ($Reverse.GraphScope -join '|') -Because (
                'a consent list must be diffable between runs')
            ($Forward.GraphScope -join '|') | Should -Be (($Forward.GraphScope | Sort-Object) -join '|')
        }
    }

    Context 'Filtering' {
        It 'Returns only the named cmdlet' {
            $Result = @(Get-OERRequiredScope -Cmdlet 'New-OERGroup')

            $Result.Count | Should -Be 1
            $Result[0].Cmdlet | Should -Be 'New-OERGroup'
        }

        It 'Returns one entry per name when several are named' {
            $Result = @(Get-OERRequiredScope -Cmdlet 'New-OERGroup', 'Add-OERAdministrativeUnitScopedRole')

            $Result.Count | Should -Be 2
            $Result.Cmdlet | Should -Contain 'New-OERGroup'
            $Result.Cmdlet | Should -Contain 'Add-OERAdministrativeUnitScopedRole'
        }

        It 'Expands a wildcard' {
            $Result = @(Get-OERRequiredScope -Cmdlet 'Get-OERGroup*')

            $Result.Count | Should -BeGreaterThan 1
            foreach ($Entry in $Result) {
                $Entry.Cmdlet | Should -BeLike 'Get-OERGroup*'
            }
        }

        It 'Matches a name case-insensitively' {
            $Result = @(Get-OERRequiredScope -Cmdlet 'new-oergroup')

            $Result.Count | Should -Be 1
            $Result[0].Cmdlet | Should -Be 'New-OERGroup'
        }

        It 'Returns an overlapping name only once' {
            $Result = @(Get-OERRequiredScope -Cmdlet 'New-OERGroup', 'New-OERGroup*')

            @($Result | Where-Object Cmdlet -EQ 'New-OERGroup').Count | Should -Be 1
        }

        It 'Accepts a name over the pipeline by value' {
            $Result = @('New-OERGroup' | Get-OERRequiredScope)

            $Result.Count | Should -Be 1
            $Result[0].Cmdlet | Should -Be 'New-OERGroup'
        }

        It 'Accepts a Name property over the pipeline, so Get-Command output binds' {
            $Result = @([PSCustomObject]@{ Name = 'New-OERGroup' } | Get-OERRequiredScope)

            $Result.Count | Should -Be 1
            $Result[0].Cmdlet | Should -Be 'New-OERGroup'
        }

        It 'Returns nothing for an empty pipeline rather than falling back to the whole table' {
            $Result = @(@() | Get-OERRequiredScope)

            $Result.Count | Should -Be 0
        }
    }

    Context 'Unknown names' {
        It 'Writes a non-terminating error for a name that matches nothing' {
            $Result = @(Get-OERRequiredScope -Cmdlet 'Get-OERNotAThing' -ErrorAction SilentlyContinue -ErrorVariable Err)

            $Result.Count | Should -Be 0
            $Err.Count | Should -Be 1
            $Err[0].FullyQualifiedErrorId | Should -Match 'CmdletNotFound,Get-OERRequiredScope'
        }

        It 'Still returns the valid names alongside the error' {
            $Result = @(Get-OERRequiredScope -Cmdlet 'Get-OERNotAThing', 'New-OERGroup' -ErrorAction SilentlyContinue)

            $Result.Count | Should -Be 1
            $Result[0].Cmdlet | Should -Be 'New-OERGroup'
        }

        It 'Writes an error for a wildcard that matches nothing' {
            $null = Get-OERRequiredScope -Cmdlet 'Set-OERNothing*' -ErrorAction SilentlyContinue -ErrorVariable Err

            $Err.Count | Should -Be 1
            $Err[0].FullyQualifiedErrorId | Should -Match 'CmdletNotFound,Get-OERRequiredScope'
        }

        It 'Writes an error for an empty name' {
            $null = Get-OERRequiredScope -Cmdlet '' -ErrorAction SilentlyContinue -ErrorVariable Err

            $Err.Count | Should -Be 1
            $Err[0].FullyQualifiedErrorId | Should -Match 'CmdletNotFound,Get-OERRequiredScope'
        }
    }

    Context 'Unique' {
        It 'Returns a single summary object' {
            $Result = @(Get-OERRequiredScope -Cmdlet 'Get-OER*' -Unique)

            $Result.Count | Should -Be 1
            $Result[0].PSObject.TypeNames[0] | Should -Be 'Omnicit.EntraRBAC.RequiredScopeSummary'
        }

        It 'Unions and deduplicates the permissions across the matched cmdlets' {
            $Summary = Get-OERRequiredScope -Cmdlet 'Get-OERGroup', 'New-OERGroup' -Unique
            $Group = Get-OERRequiredScope -Cmdlet 'Get-OERGroup'
            $New = Get-OERRequiredScope -Cmdlet 'New-OERGroup'

            $Expected = @(@($Group.GraphScope) + @($New.GraphScope) | Sort-Object -Unique)

            ($Summary.GraphScope -join '|') | Should -Be ($Expected -join '|')
            $Summary.CmdletCount | Should -Be 2
        }

        It 'Lists the cmdlets the union was taken over' {
            $Summary = Get-OERRequiredScope -Cmdlet 'Get-OERGroup', 'New-OERGroup' -Unique

            $Summary.Cmdlet | Should -Contain 'Get-OERGroup'
            $Summary.Cmdlet | Should -Contain 'New-OERGroup'
        }

        It 'Unions the Azure roles for an ARM workflow' {
            $Summary = Get-OERRequiredScope -Cmdlet 'New-OERRoleAssignment', 'Get-OERSubscription' -Unique

            $Summary.AzureRole | Should -Contain 'User Access Administrator'
            $Summary.AzureRole | Should -Contain 'Reader'
            $Summary.GraphScope | Should -Not -BeNullOrEmpty
        }

        It 'Returns empty collections rather than a null element for an offline selection' {
            $Summary = Get-OERRequiredScope -Cmdlet 'Test-OERStructure' -Unique

            @($Summary.GraphScope).Count | Should -Be 0
            @($Summary.AzureRole).Count | Should -Be 0
            $Summary.CmdletCount | Should -Be 1
        }
    }

    Context 'Known answers' {
        It 'Gives the scoped-role cmdlets a role-management write permission, not only an AU one' {
            <#
                This is the defect the per-cohort scope line shipped with: the three *ScopedRole
                cmdlets write scopedRoleMembers, which is directory role membership.
            #>
            foreach ($Name in 'Add-OERAdministrativeUnitScopedRole', 'Remove-OERAdministrativeUnitScopedRole') {
                (Get-OERRequiredScope -Cmdlet $Name).GraphScope |
                    Should -Contain 'RoleManagement.ReadWrite.Directory' -Because $Name
            }
        }

        It 'Gives the PIM policy cmdlets the policy permission rather than the eligibility one' {
            (Get-OERRequiredScope -Cmdlet 'Set-OERGroupPimPolicy').GraphScope |
                Should -Contain 'RoleManagementPolicy.ReadWrite.AzureADGroup'
            (Get-OERRequiredScope -Cmdlet 'Get-OERGroupPimPolicy').GraphScope |
                Should -Contain 'RoleManagementPolicy.Read.AzureADGroup'
        }

        It 'Distinguishes a read cmdlet from its write sibling' {
            (Get-OERRequiredScope -Cmdlet 'Get-OERCatalog').GraphScope |
                Should -Contain 'EntitlementManagement.Read.All'
            (Get-OERRequiredScope -Cmdlet 'New-OERCatalog').GraphScope |
                Should -Contain 'EntitlementManagement.ReadWrite.All'
        }

        It 'Reports a cmdlet that reaches Graph only through a private helper' {
            <#
                Get-OERGroupEligibility contains no Invoke-OERGraphRequest call of its own; it
                reaches Graph through Get-OERGroup and Resolve-OERGroupId.
            #>
            $Entry = Get-OERRequiredScope -Cmdlet 'Get-OERGroupEligibility'

            $Entry.Transport | Should -Be 'Graph'
            $Entry.GraphScope | Should -Not -BeNullOrEmpty
        }

        It 'Reports the offline cmdlets as needing nothing' {
            foreach ($Name in 'Test-OERStructure', 'New-OERConfiguration', 'Get-OERRequiredScope') {
                $Entry = Get-OERRequiredScope -Cmdlet $Name
                $Entry.Transport | Should -Be 'None' -Because $Name
                @($Entry.GraphScope).Count | Should -Be 0 -Because $Name
                @($Entry.AzureRole).Count | Should -Be 0 -Because $Name
            }
        }

        It 'Reports the ARM-only cmdlets with an Azure role and no Graph permission' {
            $Entry = Get-OERRequiredScope -Cmdlet 'Get-OERSubscription'

            $Entry.Transport | Should -Be 'Arm'
            @($Entry.GraphScope).Count | Should -Be 0
            $Entry.AzureRole | Should -Contain 'Reader'
        }
    }

    Context 'Purity' {
        It 'Never authenticates and never calls a tenant' {
            Mock -ModuleName Omnicit.EntraRBAC Initialize-OERAuth { throw 'must not authenticate' }
            Mock -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest { throw 'must not call Graph' }
            Mock -ModuleName Omnicit.EntraRBAC Invoke-OERArmRequest { throw 'must not call ARM' }

            { Get-OERRequiredScope } | Should -Not -Throw
            { Get-OERRequiredScope -Cmdlet 'Get-OER*' -Unique } | Should -Not -Throw

            Should -Invoke -ModuleName Omnicit.EntraRBAC Initialize-OERAuth -Times 0
            Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest -Times 0
            Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-OERArmRequest -Times 0
        }
    }
}
