BeforeAll { Import-Module Omnicit.EntraRBAC -Force }

Describe 'Get-OEREligibleRoleAssignment' {
    BeforeEach { InModuleScope Omnicit.EntraRBAC { $script:_OERAuthState = $null } }
    BeforeAll {
        Mock -ModuleName Omnicit.EntraRBAC Initialize-OERAuth { }
        Mock -ModuleName Omnicit.EntraRBAC Resolve-OERScope { '/subscriptions/s1' }
        Mock -ModuleName Omnicit.EntraRBAC Resolve-OERPrincipal { [PSCustomObject]@{ PrincipalId = 'p1'; PrincipalType = 'User' } }
        Mock -ModuleName Omnicit.EntraRBAC Invoke-OERArmRequest {
            [PSCustomObject]@{ value = @([PSCustomObject]@{ id='/subscriptions/s1/providers/Microsoft.Authorization/RoleEligibilitySchedules/sch1'; name='sch1'
                properties=[PSCustomObject]@{ scope='/subscriptions/s1'; roleDefinitionId='rd1'; principalId='p1'; principalType='User'; status='Provisioned'; memberType='Direct'
                    startDateTime='t'; endDateTime='t2'; createdOn='t'; updatedOn='t'; roleEligibilityScheduleRequestId='req1'
                    expandedProperties=[PSCustomObject]@{ principal=[PSCustomObject]@{displayName='Anna'}; roleDefinition=[PSCustomObject]@{displayName='Reader'}; scope=[PSCustomObject]@{displayName='Prod'} } } }) }
        }
    }
    It 'GETs roleEligibilitySchedules with -All and no filter by default' {
        Get-OEREligibleRoleAssignment -Subscription 'Prod'
        Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-OERArmRequest -Times 1 -ParameterFilter {
            $Path -eq '/subscriptions/s1/providers/Microsoft.Authorization/roleEligibilitySchedules?api-version=2020-10-01' -and $All
        }
    }
    It 'applies assignedTo() filter embedding the resolved principal id (transitive, includes group-inherited)' {
        Mock -ModuleName Omnicit.EntraRBAC Resolve-OERScope { '/subscriptions/s1' }
        Mock -ModuleName Omnicit.EntraRBAC Resolve-OERPrincipal { [PSCustomObject]@{ PrincipalId = 'pid-1' } }
        Mock -ModuleName Omnicit.EntraRBAC Invoke-OERArmRequest { @{ value = @() } }
        Get-OEREligibleRoleAssignment -Subscription 'Prod' -User 'anna@contoso.com' | Out-Null
        Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-OERArmRequest -Times 1 -ParameterFilter {
            $Path -like "*assignedTo*pid-1*" -and $Path -notlike '*principalId*'
        }
    }
    It 'applies atScope() for -AtScope' {
        Get-OEREligibleRoleAssignment -Subscription 'Prod' -AtScope
        Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-OERArmRequest -Times 1 -ParameterFilter { $Path -like '*&$filter=atScope()' }
    }
    It 'applies asTarget() for -AsTarget' {
        Get-OEREligibleRoleAssignment -Subscription 'Prod' -AsTarget
        Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-OERArmRequest -Times 1 -ParameterFilter { $Path -like '*&$filter=asTarget()' }
    }
    It 'errors when a principal filter is combined with -AtScope' {
        Get-OEREligibleRoleAssignment -Subscription 'Prod' -User 'a' -AtScope -ErrorVariable e -ErrorAction SilentlyContinue
        $e[0].FullyQualifiedErrorId | Should -Match 'AmbiguousFilter'
    }
    It 'errors when a principal filter is combined with -AsTarget' {
        Get-OEREligibleRoleAssignment -Subscription 'Prod' -User 'a' -AsTarget -ErrorVariable e -ErrorAction SilentlyContinue
        $e[0].FullyQualifiedErrorId | Should -Match 'AmbiguousFilter'
    }
    It 'errors when -AtScope and -AsTarget are combined' {
        Get-OEREligibleRoleAssignment -Subscription 'Prod' -AtScope -AsTarget -ErrorVariable e -ErrorAction SilentlyContinue
        $e[0].FullyQualifiedErrorId | Should -Match 'AmbiguousFilter'
    }
    It 'returns tagged EligibleRoleAssignment objects' {
        (Get-OEREligibleRoleAssignment -Subscription 'Prod')[0].PSObject.TypeNames[0] | Should -Be 'Omnicit.EntraRBAC.EligibleRoleAssignment'
    }

    It 'binds -ResourceGroup from the pipeline by property name' {
        $RgParam = (Get-Command Get-OEREligibleRoleAssignment).Parameters['ResourceGroup']
        $Attr = $RgParam.Attributes | Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] }
        @($Attr.ValueFromPipelineByPropertyName) | Should -Contain $true
    }
    It 'binds -ResourceName and -ResourceType from the pipeline by property name' {
        foreach ($ParamName in 'ResourceName', 'ResourceType') {
            $Param = (Get-Command Get-OEREligibleRoleAssignment).Parameters[$ParamName]
            $Attr = $Param.Attributes | Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] }
            @($Attr.ValueFromPipelineByPropertyName) | Should -Contain $true
        }
    }
    It 'forwards -ResourceType/-ResourceName to Resolve-OERScope' {
        Get-OEREligibleRoleAssignment -Subscription 'Prod' -ResourceGroup 'rg1' -ResourceType 'Microsoft.Storage/storageAccounts' -ResourceName 'stg1'
        Should -Invoke -ModuleName Omnicit.EntraRBAC Resolve-OERScope -Times 1 -ParameterFilter {
            $ResourceType -eq 'Microsoft.Storage/storageAccounts' -and $ResourceName -eq 'stg1'
        }
    }

    It 'binds a piped resource-group-shaped object end to end (not just by attribute metadata)' {
        # An attribute-presence test passes even when an alias collision silently mis-binds at
        # runtime -- which is exactly what B-subscription-mg-id-collides was. Pipe a real object
        # and assert the resolver received the bound values.
        Mock -ModuleName Omnicit.EntraRBAC Resolve-OERScope { '/subscriptions/sub-guid/resourceGroups/rg-net' }
        Mock -ModuleName Omnicit.EntraRBAC Invoke-OERArmRequest { [PSCustomObject]@{ value = @() } }

        $Rg = [PSCustomObject]@{ SubscriptionId = 'sub-guid'; ResourceGroup = 'rg-net' }
        $Rg | Get-OEREligibleRoleAssignment
        Should -Invoke -ModuleName Omnicit.EntraRBAC Resolve-OERScope -Times 1 -ParameterFilter {
            $Subscription -eq 'sub-guid' -and $ResourceGroup -eq 'rg-net'
        }
    }

    It 'binds a piped resource-shaped object end to end, including -ResourceName and -ResourceType' {
        # Companion to the resource-group pipe test above: a real Omnicit.EntraRBAC.Resource object
        # (ConvertTo-OERResource.ps1) also carries ResourceName and ResourceType, and until now
        # nothing piped that shape -- only the ValueFromPipelineByPropertyName attribute was checked
        # by reflection, and the "forwards -ResourceType/-ResourceName" It above passes them as
        # explicit parameters, which never exercises pipeline binding either.
        Mock -ModuleName Omnicit.EntraRBAC Resolve-OERScope { '/subscriptions/sub-guid/resourceGroups/rg-net/providers/Microsoft.Storage/storageAccounts/stg1' }
        Mock -ModuleName Omnicit.EntraRBAC Invoke-OERArmRequest { [PSCustomObject]@{ value = @() } }

        $Resource = [PSCustomObject]@{
            SubscriptionId = 'sub-guid'
            ResourceGroup  = 'rg-net'
            ResourceName   = 'stg1'
            ResourceType   = 'Microsoft.Storage/storageAccounts'
        }
        $Resource | Get-OEREligibleRoleAssignment
        Should -Invoke -ModuleName Omnicit.EntraRBAC Resolve-OERScope -Times 1 -ParameterFilter {
            $Subscription -eq 'sub-guid' -and $ResourceGroup -eq 'rg-net' -and $ResourceName -eq 'stg1' -and $ResourceType -eq 'Microsoft.Storage/storageAccounts'
        }
    }

    It 'scrubs the bearer-hygiene record when the ARM transport fails' {
        # CLAUDE.md SECURITY rule 6: the failed Invoke-WebRequest inside Invoke-OERArmRequest carries
        # Authorization: Bearer <token> on the request object recorded in $Error, so the catch must
        # call Remove-OERErrorRecord. Mock + Should -Invoke is the proof that holds for every rethrow
        # shape; a $global:Error + ReferenceEquals check is inert against a bare throw. This drives
        # the roleEligibilitySchedules list catch.
        Mock -ModuleName Omnicit.EntraRBAC Resolve-OERScope { '/subscriptions/s1' }
        Mock -ModuleName Omnicit.EntraRBAC Invoke-OERArmRequest { throw 'transport failure' }
        Mock -ModuleName Omnicit.EntraRBAC Remove-OERErrorRecord { }
        $null = Get-OEREligibleRoleAssignment -Subscription 'Prod' -ErrorAction SilentlyContinue
        Should -Invoke -ModuleName Omnicit.EntraRBAC Remove-OERErrorRecord -Times 1
    }
}

Describe 'Get-OEREligibleRoleAssignment with an ambiguous service principal display name' {
    # End to end through Resolve-OERPrincipal -> Resolve-OERApplicationId: only the Graph and ARM
    # transports are mocked, so the real resolvers decide. A raw -Scope resolves without an ARM call,
    # so any ARM request at all would be the assignment read the refusal must prevent. No id below is
    # version-4 shaped.
    BeforeEach {
        InModuleScope Omnicit.EntraRBAC { $script:_OERAuthState = $null }
        Mock -ModuleName Omnicit.EntraRBAC Initialize-OERAuth { }
        Mock -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest -ParameterFilter { $Uri -like 'v1.0/servicePrincipals?*' } -MockWith {
            @{ value = @(
                    @{ id = '11111111-1111-1111-1111-111111111111'; displayName = 'Dup App' },
                    @{ id = '22222222-2222-2222-2222-222222222222'; displayName = 'Dup App' }) }
        }
        Mock -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest -MockWith { throw 'unexpected Graph request' }
        Mock -ModuleName Omnicit.EntraRBAC Invoke-OERArmRequest { [PSCustomObject]@{ value = @() } }
    }

    It 'reports exactly one AmbiguousPrincipalName record naming both candidates, and makes no ARM request' {
        $Err = $null
        $null = Get-OEREligibleRoleAssignment -Scope '/subscriptions/aaaa1111-0000-0000-0000-000000000000' -ServicePrincipal 'Dup App' `
            -ErrorAction SilentlyContinue -ErrorVariable Err
        $Reported = @($Err | Where-Object { $_.FullyQualifiedErrorId -eq 'AmbiguousPrincipalName,Get-OEREligibleRoleAssignment' })
        $Reported.Count | Should -Be 1
        # No fall-through: the cmdlet writes no other record of its own (PrincipalNotFound included).
        @($Err | Where-Object { $_.FullyQualifiedErrorId -like '*,Get-OEREligibleRoleAssignment' }).Count | Should -Be 1
        $Reported[0].CategoryInfo.Category | Should -Be 'InvalidArgument'
        $Reported[0].TargetObject | Should -Be 'Dup App'
        $Reported[0].Exception.Message | Should -Match '11111111-1111-1111-1111-111111111111'
        $Reported[0].Exception.Message | Should -Match '22222222-2222-2222-2222-222222222222'
        Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest -Times 1 -Exactly -ParameterFilter { $Uri -like 'v1.0/servicePrincipals?*' }
        Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-OERArmRequest -Times 0
    }

    It 'still reports PrincipalNotFound when no service principal carries the display name' {
        Mock -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest -ParameterFilter { $Uri -like 'v1.0/servicePrincipals?*' } -MockWith { @{ value = @() } }
        $Err = $null
        $null = Get-OEREligibleRoleAssignment -Scope '/subscriptions/aaaa1111-0000-0000-0000-000000000000' -ServicePrincipal 'Nobody App' `
            -ErrorAction SilentlyContinue -ErrorVariable Err
        @($Err | Where-Object { $_.FullyQualifiedErrorId -eq 'PrincipalNotFound,Get-OEREligibleRoleAssignment' }).Count | Should -Be 1
        @($Err | Where-Object { $_.FullyQualifiedErrorId -like '*,Get-OEREligibleRoleAssignment' }).Count | Should -Be 1
        Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest -Times 1 -Exactly -ParameterFilter { $Uri -like 'v1.0/servicePrincipals?*' }
        Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-OERArmRequest -Times 0
    }
}
