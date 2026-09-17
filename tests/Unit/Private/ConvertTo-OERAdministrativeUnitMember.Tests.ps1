BeforeAll {
    $script:moduleName = 'Omnicit.EntraRBAC'
    Get-Module $script:moduleName | Remove-Module -Force -ErrorAction SilentlyContinue
    Import-Module $script:moduleName -Force -ErrorAction Stop
}

Describe 'ConvertTo-OERAdministrativeUnitMember' {
    It 'tags the output and derives Type from @odata.type' {
        InModuleScope $script:moduleName {
            $Out = ConvertTo-OERAdministrativeUnitMember -InputObject @{ id = 'u-1'; displayName = 'Jane'; userPrincipalName = 'jane@contoso.com'; '@odata.type' = '#microsoft.graph.user' }
            $Out.PSObject.TypeNames[0] | Should -Be 'Omnicit.EntraRBAC.AdministrativeUnitMember'
            $Out.Id | Should -Be 'u-1'
            $Out.DisplayName | Should -Be 'Jane'
            $Out.UserPrincipalName | Should -Be 'jane@contoso.com'
            $Out.Type | Should -Be 'user'
        }
    }

    It 'yields null Type when @odata.type is absent' {
        InModuleScope $script:moduleName {
            $Out = ConvertTo-OERAdministrativeUnitMember -InputObject @{ id = 'g-1'; displayName = 'Group A' }
            $Out.Type | Should -BeNullOrEmpty
            # A null Type and an ABSENT Type alias (e.g. a swallowed Update-TypeData registration
            # failure) are indistinguishable by value alone -- both read as $null. Asserting the
            # member actually exists as an AliasProperty is what proves the alias is really there.
            $Out.PSObject.Properties['Type'].MemberType | Should -Be 'AliasProperty'
        }
    }

    It 'processes multiple members from the pipeline' {
        InModuleScope $script:moduleName {
            $Out = @(
                @{ id = 'u-1'; displayName = 'Jane'; '@odata.type' = '#microsoft.graph.user' }
                @{ id = 'd-1'; displayName = 'Device1'; '@odata.type' = '#microsoft.graph.device' }
            ) | ConvertTo-OERAdministrativeUnitMember
            $Out.Count | Should -Be 2
            $Out[1].Type | Should -Be 'device'
        }
    }

    It 'names the directory object kind ObjectType, matching ConvertTo-OERGroupMember' {
        InModuleScope Omnicit.EntraRBAC {
            $Out = ConvertTo-OERAdministrativeUnitMember -InputObject @{
                '@odata.type' = '#microsoft.graph.user'; id = 'u1'; displayName = 'Ada'; userPrincipalName = 'ada@contoso.com'
            }
            $Out.ObjectType | Should -Be 'user'
            $Out.PSObject.Properties['ObjectType'].MemberType | Should -Be 'NoteProperty'
        }
    }

    It 'keeps the historical Type property working as an alias of ObjectType' {
        InModuleScope Omnicit.EntraRBAC {
            $Out = ConvertTo-OERAdministrativeUnitMember -InputObject @{ '@odata.type' = '#microsoft.graph.group'; id = 'g1' }
            $Out.Type | Should -Be 'group'
            $Out.PSObject.Properties['Type'].MemberType | Should -Be 'AliasProperty'
        }
    }

    It 'still reports a null object kind when Graph omitted the odata annotation' {
        InModuleScope Omnicit.EntraRBAC {
            $Out = ConvertTo-OERAdministrativeUnitMember -InputObject @{ id = 'x1'; displayName = 'No type' }
            $Out.ObjectType | Should -BeNullOrEmpty
            $Out.Type | Should -BeNullOrEmpty
            # See the note above: without this, a silently-absent Type alias would pass the same as a
            # present alias resolving to null.
            $Out.PSObject.Properties['Type'].MemberType | Should -Be 'AliasProperty'
        }
    }

    It 'emits PrincipalId equal to Id, mirroring ConvertTo-OERGroupMember, so Add-/Remove-OERAdministrativeUnitMember round-trip' {
        InModuleScope $script:moduleName {
            $Out = ConvertTo-OERAdministrativeUnitMember -InputObject @{ id = 'u-1'; displayName = 'Jane' }
            $Out.PrincipalId | Should -Be 'u-1'
        }
    }

    It 'stores Id as an AliasProperty of PrincipalId, not a second copy (Task 8a addendum 2)' {
        # The migration this file's own M3-ruling comment (now removed) deferred: Id/PrincipalId was
        # two independent NoteProperty copies; PrincipalId is now the only stored value and Id is
        # registered as its AliasProperty in suffix.ps1, mirroring ConvertTo-OERGroupMember.
        InModuleScope $script:moduleName {
            $Out = ConvertTo-OERAdministrativeUnitMember -InputObject @{ id = 'u-alias-1'; displayName = 'Alias' }

            ($Out.PSObject.Properties | Where-Object MemberType -eq 'NoteProperty').Name |
                Should -Not -Contain 'Id' -Because 'Id must be the AliasProperty registered in suffix.ps1, not a second stored copy'
            $Out.PSObject.Properties['Id'].MemberType | Should -Be 'AliasProperty'
            $Out.PSObject.Properties['Id'].ReferencedMemberName | Should -Be 'PrincipalId'
            $Out.Id | Should -Be 'u-alias-1'
        }
    }

    It 'pipes into Add-OERAdministrativeUnitMember and binds -AdministrativeUnit via AdministrativeUnitId, NOT the member''s own Id alias (Task 8a)' {
        <#
            Add-OERAdministrativeUnitMember's -AdministrativeUnit parameter declares its aliases
            'AdministrativeUnitId', 'Id', 'DisplayName' IN THAT ORDER, with a comment on the parameter
            itself explaining why: "AdministrativeUnitId precedes Id/DisplayName so a piped
            AdministrativeUnitMember object binds the parent unit's id, not the member's own
            Id/DisplayName". This shape now carries an Id AliasProperty for the FIRST time (it used to
            be a second stored copy) -- proving the declared precedence still wins post-migration is
            exactly the hazard that ordering comment exists to prevent.
        #>
        Mock -ModuleName Omnicit.EntraRBAC Initialize-OERAuth { }
        Mock -ModuleName Omnicit.EntraRBAC Resolve-OERAdministrativeUnitId { 'au-pipe-1' }
        Mock -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest { }

        InModuleScope Omnicit.EntraRBAC {
            $Member = ConvertTo-OERAdministrativeUnitMember -InputObject @{ id = '11111111-1111-1111-1111-111111111111'; displayName = 'Jane' } `
                -AdministrativeUnitId 'au-pipe-1'
            $Member | Add-OERAdministrativeUnitMember -Confirm:$false
        }

        Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest -Exactly -Times 1 -ParameterFilter {
            $Method -eq 'POST' -and
            $Uri -eq 'v1.0/directory/administrativeUnits/au-pipe-1/members/$ref' -and
            $Body.'@odata.id' -match 'directoryObjects/11111111-1111-1111-1111-111111111111'
        }
    }

    It 'stamps the supplied -AdministrativeUnitId onto the output' {
        InModuleScope $script:moduleName {
            $Out = ConvertTo-OERAdministrativeUnitMember -InputObject @{ id = 'u-1' } -AdministrativeUnitId 'au-1'
            $Out.AdministrativeUnitId | Should -Be 'au-1'
        }
    }

    It 'leaves AdministrativeUnitId null when the caller does not supply it' {
        InModuleScope $script:moduleName {
            $Out = ConvertTo-OERAdministrativeUnitMember -InputObject @{ id = 'u-1' }
            # Should -BeNullOrEmpty alone would also pass if the property were absent entirely (e.g.
            # the whole $AdministrativeUnitId parameter reverted) -- assert the property genuinely
            # EXISTS (and is merely null-valued) so a revert of the change is actually caught.
            $Out.PSObject.Properties.Name | Should -Contain 'AdministrativeUnitId'
            $Out.AdministrativeUnitId | Should -BeNullOrEmpty
        }
    }
}
