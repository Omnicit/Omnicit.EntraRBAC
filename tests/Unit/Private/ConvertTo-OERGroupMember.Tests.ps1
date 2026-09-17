BeforeAll {
    $script:moduleName = 'Omnicit.EntraRBAC'
    Get-Module $script:moduleName | Remove-Module -Force -ErrorAction SilentlyContinue
    Import-Module $script:moduleName -Force -ErrorAction Stop
}

Describe 'ConvertTo-OERGroupMember' {
    It 'maps a user member into a tagged object with a friendly ObjectType' {
        InModuleScope $script:moduleName {
            $Raw = @{ '@odata.type' = '#microsoft.graph.user'; id = 'u1'; displayName = 'Anna'; userPrincipalName = 'anna@contoso.com' }
            $Out = ConvertTo-OERGroupMember -InputObject $Raw -GroupId 'g1' -MemberType 'Member'
            $Out.PSObject.TypeNames[0] | Should -Be 'Omnicit.EntraRBAC.GroupMember'
            $Out.Id                | Should -Be 'u1'
            $Out.DisplayName       | Should -Be 'Anna'
            $Out.UserPrincipalName | Should -Be 'anna@contoso.com'
            $Out.ObjectType        | Should -Be 'user'
            $Out.MemberType        | Should -Be 'Member'
            $Out.GroupId           | Should -Be 'g1'
            $Out.PrincipalId       | Should -Be 'u1'
        }
    }

    It 'yields a null (not empty-string) ObjectType when @odata.type is absent, matching ConvertTo-OERAdministrativeUnitMember' {
        InModuleScope $script:moduleName {
            $Out = ConvertTo-OERGroupMember -InputObject @{ id = 'g2'; displayName = 'A Group' } -GroupId 'g1' -MemberType 'Member'
            $Out.ObjectType | Should -BeNullOrEmpty
            # BeNullOrEmpty alone passes on '' too, which is exactly the mismatch the two member
            # shapes used to have -- pin the actual runtime value so a regression back to '' is caught.
            ($null -eq $Out.ObjectType) | Should -BeTrue
            $Out.Id         | Should -Be 'g2'
        }
    }

    It 'processes multiple objects from the pipeline' {
        InModuleScope $script:moduleName {
            $Raw = @(
                @{ '@odata.type' = '#microsoft.graph.user'; id = 'u1'; displayName = 'Anna' }
                @{ '@odata.type' = '#microsoft.graph.group'; id = 'g9'; displayName = 'Nested' }
            )
            $Out = $Raw | ConvertTo-OERGroupMember -GroupId 'g1' -MemberType 'Owner'
            $Out.Count          | Should -Be 2
            $Out[1].ObjectType  | Should -Be 'group'
            $Out[1].MemberType  | Should -Be 'Owner'
        }
    }

    It 'stores Id as an AliasProperty of PrincipalId, not a second copy (Task 8a)' {
        InModuleScope $script:moduleName {
            $Out = ConvertTo-OERGroupMember -InputObject @{ id = 'u-alias-1'; displayName = 'Alias' } -GroupId 'g1' -MemberType 'Member'

            ($Out.PSObject.Properties | Where-Object MemberType -eq 'NoteProperty').Name |
                Should -Not -Contain 'Id' -Because 'Id must be the AliasProperty registered in suffix.ps1, not a second stored copy'
            $Out.PSObject.Properties['Id'].MemberType | Should -Be 'AliasProperty'
            $Out.PSObject.Properties['Id'].ReferencedMemberName | Should -Be 'PrincipalId'
            $Out.Id | Should -Be 'u-alias-1'
        }
    }

    It 'pipes into Remove-OERGroupMember and binds -Group via GroupId, NOT the member''s own Id alias (Task 8a)' {
        <#
            Remove-OERGroupMember -Group declares its aliases 'GroupId', 'Id', 'DisplayName' IN THAT
            ORDER (CLAUDE.md ## Code Style, Alias declaration order: "in a parameter's `[Alias()]`
            list, the specific `<Noun>Id` form comes before the generic `Id`"). A GroupMember
            object now carries BOTH a stored GroupId (the group's id) and an Id AliasProperty (the
            MEMBER's own id, via PrincipalId) -- if alias resolution ever preferred the generic Id
            over GroupId, -Group would silently bind to the wrong id (the principal being removed,
            not the group it is being removed from). Piping a full object through the real cmdlet and
            asserting on the DELETE URI proves the declared precedence still wins post-migration.
        #>
        Mock -ModuleName Omnicit.EntraRBAC Initialize-OERAuth { }
        Mock -ModuleName Omnicit.EntraRBAC Resolve-OERGroupId { param($DisplayName) $DisplayName }
        Mock -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest { }

        InModuleScope Omnicit.EntraRBAC {
            $Member = ConvertTo-OERGroupMember -InputObject @{ id = '11111111-1111-1111-1111-111111111111'; displayName = 'Anna' } `
                -GroupId 'gid-pipe-1' -MemberType 'Owner'
            $Member | Remove-OERGroupMember -Confirm:$false
        }

        Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest -Exactly -Times 1 -ParameterFilter {
            $Method -eq 'DELETE' -and $Uri -eq 'v1.0/groups/gid-pipe-1/owners/11111111-1111-1111-1111-111111111111/$ref'
        }
    }
}
