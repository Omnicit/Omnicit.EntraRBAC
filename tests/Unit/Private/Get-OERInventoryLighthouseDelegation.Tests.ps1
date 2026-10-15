BeforeAll {
    $script:moduleName = 'Omnicit.EntraRBAC'
    Get-Module $script:moduleName | Remove-Module -Force -ErrorAction SilentlyContinue
    Import-Module $script:moduleName -Force -ErrorAction Stop
    . "$PSScriptRoot/../TestHelpers/OERTransportTripwire.ps1"
    Install-OERTransportTripwire

    # Placeholder ids, none of them version 4 shaped. Two subscriptions, one managing tenant, and role
    # definition ids that stand for a contributor-like and an access-administrator-like role.
    $script:SubA = '11111111-1111-1111-1111-111111111111'
    $script:SubB = '22222222-2222-2222-2222-222222222222'
    $script:ManagingTenant = '33333333-3333-3333-3333-333333333333'
    $script:RoleContributor = 'dddddddd-dddd-dddd-dddd-dddddddddddd'
    $script:RoleAccessAdmin = 'eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee'
    $script:RoleOther = 'ffffffff-ffff-ffff-ffff-ffffffffffff'
    # The path pieces the reader sends, written out here rather than imported from it.
    $script:AssignmentQuery = '/providers/Microsoft.ManagedServices/registrationAssignments?$expandRegistrationDefinition=true&api-version=2022-10-01'
    $script:DefinitionQuery = '/providers/Microsoft.ManagedServices/registrationDefinitions?api-version=2022-10-01'

    function New-LhAuthorization {
        param([string]$Principal = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', [string]$Role = 'dddddddd-dddd-dddd-dddd-dddddddddddd', [string]$Name = 'Support User', [string[]]$Delegated)
        $Authorization = [PSCustomObject]@{ principalId = $Principal; principalIdDisplayName = $Name; roleDefinitionId = $Role }
        if ($Delegated) { $Authorization | Add-Member -NotePropertyName delegatedRoleDefinitionIds -NotePropertyValue $Delegated }
        $Authorization
    }

    function New-LhDefinition {
        param(
            [string]$Sub,
            [string]$Guid,
            [string]$Offer = 'Contoso Managed Services',
            [string]$Tenant = '33333333-3333-3333-3333-333333333333',
            [object[]]$Authorizations = @((New-LhAuthorization)),
            [object[]]$Eligible = @()
        )
        [PSCustomObject]@{
            id         = "/subscriptions/$Sub/providers/Microsoft.ManagedServices/registrationDefinitions/$Guid"
            properties = [PSCustomObject]@{
                registrationDefinitionName = $Offer
                managedByTenantId          = $Tenant
                managedByTenantName        = 'Contoso Corp.'
                authorizations             = $Authorizations
                eligibleAuthorizations     = $Eligible
            }
        }
    }

    # An assignment at -At (a subscription or resource group path) that names -Definition; -Expand also
    # carries the definition inside it, as the list with $expandRegistrationDefinition=true does.
    function New-LhAssignment {
        param([string]$At, [string]$Guid, [object]$Definition, [switch]$Expand)
        [PSCustomObject]@{
            id         = "$At/providers/Microsoft.ManagedServices/registrationAssignments/$Guid"
            properties = [PSCustomObject]@{
                registrationDefinitionId = $Definition.id
                registrationDefinition   = $(if ($Expand) { $Definition } else { $null })
            }
        }
    }

    function New-LhList {
        param([object[]]$Value = @())
        [PSCustomObject]@{ value = @($Value) }
    }

    function New-LhArmError {
        param([string]$Code, [string]$Message)
        [System.Management.Automation.ErrorRecord]::new(
            [System.Exception]::new("$Code`: $Message"), $Code, [System.Management.Automation.ErrorCategory]::OperationStopped, $null)
    }
}

AfterAll {
    try { Assert-OERTransportTripwire } finally { Uninstall-OERTransportTripwire }
}

Describe 'Get-OERInventoryLighthouseDelegation' {
    BeforeEach {
        InModuleScope $script:moduleName { $script:_OERAuthState = $null }
        # The one answer table of the mocked ARM transport: a path to a response, or to an error record
        # the mock throws. A path nobody listed is a failed read, so a request the reader should not
        # have made shows as a missing row and not as an empty answer.
        $script:Replies = @{}
        Mock -ModuleName $script:moduleName Initialize-OERAuth {}
        Mock -ModuleName $script:moduleName Invoke-OERArmRequest {
            param($Method, $Path, $Body, [switch]$All)
            if (-not $script:Replies.ContainsKey($Path)) { throw "No mocked answer for '$Path'." }
            $Reply = $script:Replies[$Path]
            if ($Reply -is [System.Management.Automation.ErrorRecord]) { throw $Reply }
            $Reply
        }
    }

    Context 'a delegation at a subscription' {
        It 'returns one row with the role names resolved, one role read per distinct role id, and no resource group listing' {
            $SubPath = "/subscriptions/$($script:SubA)"
            $Definition = New-LhDefinition -Sub $script:SubA -Guid '55555555-5555-5555-5555-555555555555' `
                -Authorizations @(
                    (New-LhAuthorization -Principal 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa' -Role $script:RoleContributor)
                    (New-LhAuthorization -Principal 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb' -Role $script:RoleAccessAdmin -Name 'Access Administrators' -Delegated @($script:RoleContributor, $script:RoleOther))
                ) `
                -Eligible @((New-LhAuthorization -Principal 'cccccccc-cccc-cccc-cccc-cccccccccccc' -Role $script:RoleContributor -Name 'On-call Engineers'))
            $Assignment = New-LhAssignment -At $SubPath -Guid '66666666-6666-6666-6666-666666666666' -Definition $Definition -Expand
            $script:Replies["$SubPath$($script:AssignmentQuery)"] = New-LhList @($Assignment)
            $script:Replies["$SubPath$($script:DefinitionQuery)"] = New-LhList @($Definition)
            $script:Replies["$SubPath/providers/Microsoft.Authorization/roleDefinitions/$($script:RoleContributor)?api-version=2022-04-01"] = [PSCustomObject]@{ properties = [PSCustomObject]@{ roleName = 'Contributor' } }
            $script:Replies["$SubPath/providers/Microsoft.Authorization/roleDefinitions/$($script:RoleAccessAdmin)?api-version=2022-04-01"] = [PSCustomObject]@{ properties = [PSCustomObject]@{ roleName = 'User Access Administrator' } }

            $Result = InModuleScope $script:moduleName -Parameters @{ Sub = $script:SubA } {
                Get-OERInventoryLighthouseDelegation -Scope "/subscriptions/$Sub"
            }

            @($Result.Delegations).Count | Should -Be 1
            $Row = $Result.Delegations[0]
            $Row.scope | Should -BeExactly $SubPath
            $Row.subscriptionId | Should -BeExactly $script:SubA
            $Row.resourceGroup | Should -BeNullOrEmpty
            $Row.managedByTenantId | Should -BeExactly $script:ManagingTenant
            $Row.offerName | Should -BeExactly 'Contoso Managed Services'
            $Row.authorizations[0].roleName | Should -BeExactly 'Contributor'
            $Row.authorizations[1].roleName | Should -BeExactly 'User Access Administrator'
            $Row.authorizations[1].delegatedRoleDefinitionIds | Should -Be @($script:RoleContributor, $script:RoleOther)
            $Row.eligibleAuthorizations[0].roleName | Should -BeExactly 'Contributor'
            @($Result.Unread).Count | Should -Be 0
            @($Result.Causes).Count | Should -Be 0

            # Exactly one read per distinct role id, although Contributor stands in three places.
            Should -Invoke -ModuleName $script:moduleName Invoke-OERArmRequest -Times 1 -Exactly -ParameterFilter { $Path -like '*roleDefinitions/dddddddd-dddd-dddd-dddd-dddddddddddd?*' }
            Should -Invoke -ModuleName $script:moduleName Invoke-OERArmRequest -Times 1 -Exactly -ParameterFilter { $Path -like '*roleDefinitions/eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee?*' }
            # A delegated role is not a role of the row, so it is not looked up.
            Should -Invoke -ModuleName $script:moduleName Invoke-OERArmRequest -Times 0 -ParameterFilter { $Path -like '*roleDefinitions/ffffffff-ffff-ffff-ffff-ffffffffffff?*' }
            Should -Invoke -ModuleName $script:moduleName Invoke-OERArmRequest -Times 0 -ParameterFilter { $Path -like '*/resourcegroups?api-version=2025-04-01' }
            Should -Invoke -ModuleName $script:moduleName Invoke-OERArmRequest -Times 4 -Exactly
        }

        It 'uses the definition an assignment carries expanded when the definition list does not hold it' {
            $SubPath = "/subscriptions/$($script:SubA)"
            $Definition = New-LhDefinition -Sub $script:SubA -Guid '55555555-5555-5555-5555-555555555555' -Offer 'Expanded offer'
            $Assignment = New-LhAssignment -At $SubPath -Guid '66666666-6666-6666-6666-666666666666' -Definition $Definition -Expand
            $script:Replies["$SubPath$($script:AssignmentQuery)"] = New-LhList @($Assignment)
            $script:Replies["$SubPath$($script:DefinitionQuery)"] = New-LhList
            $script:Replies["$SubPath/providers/Microsoft.Authorization/roleDefinitions/$($script:RoleContributor)?api-version=2022-04-01"] = [PSCustomObject]@{ properties = [PSCustomObject]@{ roleName = 'Contributor' } }

            $Result = InModuleScope $script:moduleName -Parameters @{ Sub = $script:SubA } {
                Get-OERInventoryLighthouseDelegation -Scope "/subscriptions/$Sub" -WarningAction SilentlyContinue
            }

            @($Result.Delegations).Count | Should -Be 1
            $Result.Delegations[0].offerName | Should -BeExactly 'Expanded offer'
            @($Result.Unread).Count | Should -Be 0
        }

        It 'reads the assignment list and the definition list with the pinned api-version, paged' {
            $SubPath = "/subscriptions/$($script:SubA)"
            $script:Replies["$SubPath$($script:AssignmentQuery)"] = New-LhList
            $script:Replies["$SubPath$($script:DefinitionQuery)"] = New-LhList
            InModuleScope $script:moduleName -Parameters @{ Sub = $script:SubA } {
                $null = Get-OERInventoryLighthouseDelegation -Scope "/subscriptions/$Sub"
            }
            Should -Invoke -ModuleName $script:moduleName Invoke-OERArmRequest -Times 1 -Exactly -ParameterFilter {
                $Path -eq '/subscriptions/11111111-1111-1111-1111-111111111111/providers/Microsoft.ManagedServices/registrationAssignments?$expandRegistrationDefinition=true&api-version=2022-10-01' -and $All -and -not $Method
            }
            Should -Invoke -ModuleName $script:moduleName Invoke-OERArmRequest -Times 1 -Exactly -ParameterFilter {
                $Path -eq '/subscriptions/11111111-1111-1111-1111-111111111111/providers/Microsoft.ManagedServices/registrationDefinitions?api-version=2022-10-01' -and $All
            }
        }

        It 'finds the definition of an assignment the list did not expand through the definition list, without regard to letter case' {
            $SubPath = "/subscriptions/$($script:SubA)"
            $Definition = New-LhDefinition -Sub $script:SubA -Guid '55555555-5555-5555-5555-555555555555'
            $Assignment = New-LhAssignment -At $SubPath -Guid '66666666-6666-6666-6666-666666666666' -Definition $Definition
            $Assignment.properties.registrationDefinitionId = $Definition.id.ToUpperInvariant()
            $script:Replies["$SubPath$($script:AssignmentQuery)"] = New-LhList @($Assignment)
            $script:Replies["$SubPath$($script:DefinitionQuery)"] = New-LhList @($Definition)
            $script:Replies["$SubPath/providers/Microsoft.Authorization/roleDefinitions/$($script:RoleContributor)?api-version=2022-04-01"] = [PSCustomObject]@{ properties = [PSCustomObject]@{ roleName = 'Contributor' } }

            $Result = InModuleScope $script:moduleName -Parameters @{ Sub = $script:SubA } {
                Get-OERInventoryLighthouseDelegation -Scope "/subscriptions/$Sub"
            }

            @($Result.Delegations).Count | Should -Be 1
            $Result.Delegations[0].offerName | Should -BeExactly 'Contoso Managed Services'
            @($Result.Unread).Count | Should -Be 0
            # The upper-cased reference still counts as naming the definition: no resource group listing.
            Should -Invoke -ModuleName $script:moduleName Invoke-OERArmRequest -Times 0 -ParameterFilter { $Path -like '*/resourcegroups?api-version=2025-04-01' }
        }
    }

    Context 'a delegation at a resource group' {
        It 'finds it through the resource group fallback when the subscription list is empty and a definition is unreferenced' {
            $SubPath = "/subscriptions/$($script:SubA)"
            $Definition = New-LhDefinition -Sub $script:SubA -Guid '55555555-5555-5555-5555-555555555555'
            $GroupOne = "$SubPath/resourceGroups/rg-one"
            $GroupTwo = "$SubPath/resourceGroups/rg-two"
            # Not expanded: the definition has to come from the definition list.
            $Assignment = New-LhAssignment -At $GroupOne -Guid '66666666-6666-6666-6666-666666666666' -Definition $Definition
            $script:Replies["$SubPath$($script:AssignmentQuery)"] = New-LhList
            $script:Replies["$SubPath$($script:DefinitionQuery)"] = New-LhList @($Definition)
            $script:Replies["$SubPath/resourcegroups?api-version=2025-04-01"] = New-LhList @([PSCustomObject]@{ id = $GroupOne; name = 'rg-one' }, [PSCustomObject]@{ id = $GroupTwo; name = 'rg-two' })
            $script:Replies["$GroupOne$($script:AssignmentQuery)"] = New-LhList @($Assignment)
            $script:Replies["$GroupTwo$($script:AssignmentQuery)"] = New-LhList
            $script:Replies["$SubPath/providers/Microsoft.Authorization/roleDefinitions/$($script:RoleContributor)?api-version=2022-04-01"] = [PSCustomObject]@{ properties = [PSCustomObject]@{ roleName = 'Contributor' } }

            $Result = InModuleScope $script:moduleName -Parameters @{ Sub = $script:SubA } {
                Get-OERInventoryLighthouseDelegation -Scope "/subscriptions/$Sub"
            }

            @($Result.Delegations).Count | Should -Be 1
            $Result.Delegations[0].scope | Should -BeExactly $GroupOne
            $Result.Delegations[0].resourceGroup | Should -BeExactly 'rg-one'
            $Result.Delegations[0].authorizations[0].roleName | Should -BeExactly 'Contributor'
            @($Result.Unread).Count | Should -Be 0
            Should -Invoke -ModuleName $script:moduleName Invoke-OERArmRequest -Times 1 -Exactly -ParameterFilter { $Path -like '*/resourcegroups?api-version=2025-04-01' }
            Should -Invoke -ModuleName $script:moduleName Invoke-OERArmRequest -Times 1 -Exactly -ParameterFilter { $Path -like '*resourceGroups/rg-one/providers/*' }
            Should -Invoke -ModuleName $script:moduleName Invoke-OERArmRequest -Times 1 -Exactly -ParameterFilter { $Path -like '*resourceGroups/rg-two/providers/*' }
        }

        It 'does not list resource groups when the subscription list itself returns the resource group delegation' {
            $SubPath = "/subscriptions/$($script:SubA)"
            $GroupOne = "$SubPath/resourceGroups/rg-one"
            $Definition = New-LhDefinition -Sub $script:SubA -Guid '55555555-5555-5555-5555-555555555555'
            $Assignment = New-LhAssignment -At $GroupOne -Guid '66666666-6666-6666-6666-666666666666' -Definition $Definition -Expand
            $script:Replies["$SubPath$($script:AssignmentQuery)"] = New-LhList @($Assignment)
            $script:Replies["$SubPath$($script:DefinitionQuery)"] = New-LhList @($Definition)
            $script:Replies["$SubPath/providers/Microsoft.Authorization/roleDefinitions/$($script:RoleContributor)?api-version=2022-04-01"] = [PSCustomObject]@{ properties = [PSCustomObject]@{ roleName = 'Contributor' } }

            $Result = InModuleScope $script:moduleName -Parameters @{ Sub = $script:SubA } {
                Get-OERInventoryLighthouseDelegation -Scope "/subscriptions/$Sub"
            }

            @($Result.Delegations).Count | Should -Be 1
            $Result.Delegations[0].resourceGroup | Should -BeExactly 'rg-one'
            Should -Invoke -ModuleName $script:moduleName Invoke-OERArmRequest -Times 0 -ParameterFilter { $Path -like '*/resourcegroups?api-version=2025-04-01' }
            Should -Invoke -ModuleName $script:moduleName Invoke-OERArmRequest -Times 0 -ParameterFilter { $Path -like '*resourceGroups/rg-one/providers/Microsoft.ManagedServices*' }
        }

        It 'counts an assignment returned by the subscription list and again by a resource group read once' {
            $SubPath = "/subscriptions/$($script:SubA)"
            $GroupOne = "$SubPath/resourceGroups/rg-one"
            $Referenced = New-LhDefinition -Sub $script:SubA -Guid '55555555-5555-5555-5555-555555555555'
            $Unreferenced = New-LhDefinition -Sub $script:SubA -Guid '77777777-7777-7777-7777-777777777777' -Offer 'Idle offer'
            $Assignment = New-LhAssignment -At $GroupOne -Guid '66666666-6666-6666-6666-666666666666' -Definition $Referenced -Expand
            $script:Replies["$SubPath$($script:AssignmentQuery)"] = New-LhList @($Assignment)
            $script:Replies["$SubPath$($script:DefinitionQuery)"] = New-LhList @($Referenced, $Unreferenced)
            # An unreferenced definition makes the reader list the groups; the group read returns the same assignment again.
            $script:Replies["$SubPath/resourcegroups?api-version=2025-04-01"] = New-LhList @([PSCustomObject]@{ id = $GroupOne; name = 'rg-one' })
            $script:Replies["$GroupOne$($script:AssignmentQuery)"] = New-LhList @($Assignment)
            $script:Replies["$SubPath/providers/Microsoft.Authorization/roleDefinitions/$($script:RoleContributor)?api-version=2022-04-01"] = [PSCustomObject]@{ properties = [PSCustomObject]@{ roleName = 'Contributor' } }

            $Result = InModuleScope $script:moduleName -Parameters @{ Sub = $script:SubA } {
                Get-OERInventoryLighthouseDelegation -Scope "/subscriptions/$Sub"
            }

            @($Result.Delegations).Count | Should -Be 1
            @($Result.Unread).Count | Should -Be 0
            Should -Invoke -ModuleName $script:moduleName Invoke-OERArmRequest -Times 1 -Exactly -ParameterFilter { $Path -like '*/resourcegroups?api-version=2025-04-01' }
            Should -Invoke -ModuleName $script:moduleName Invoke-OERArmRequest -Times 1 -Exactly -ParameterFilter { $Path -like '*resourceGroups/rg-one/providers/*' }
        }

        It 'deduplicates a row with a blank assignment id on its scope and definition id' {
            $SubPath = "/subscriptions/$($script:SubA)"
            $GroupOne = "$SubPath/resourceGroups/rg-one"
            $Referenced = New-LhDefinition -Sub $script:SubA -Guid '55555555-5555-5555-5555-555555555555'
            $Unreferenced = New-LhDefinition -Sub $script:SubA -Guid '77777777-7777-7777-7777-777777777777' -Offer 'Idle offer'
            $Blank = [PSCustomObject]@{ id = ''; properties = [PSCustomObject]@{ registrationDefinitionId = $Referenced.id; registrationDefinition = $Referenced } }
            $script:Replies["$SubPath$($script:AssignmentQuery)"] = New-LhList @($Blank)
            $script:Replies["$SubPath$($script:DefinitionQuery)"] = New-LhList @($Referenced, $Unreferenced)
            $script:Replies["$SubPath/resourcegroups?api-version=2025-04-01"] = New-LhList @([PSCustomObject]@{ id = $GroupOne; name = 'rg-one' })
            $script:Replies["$GroupOne$($script:AssignmentQuery)"] = New-LhList @($Blank)
            $script:Replies["$SubPath/providers/Microsoft.Authorization/roleDefinitions/$($script:RoleContributor)?api-version=2022-04-01"] = [PSCustomObject]@{ properties = [PSCustomObject]@{ roleName = 'Contributor' } }

            # Read at the subscription and again at the group, the blank id falls back to the scope that
            # was read, so the two rows differ in scope and are two rows; the same blank row read twice
            # at one scope is one. The second list below proves the second half.
            $Result = InModuleScope $script:moduleName -Parameters @{ Sub = $script:SubA } {
                Get-OERInventoryLighthouseDelegation -Scope "/subscriptions/$Sub"
            }
            @($Result.Delegations).Count | Should -Be 2
            @($Result.Delegations | ForEach-Object { $_.scope } | Sort-Object) | Should -Be @($SubPath, $GroupOne)

            $script:Replies["$GroupOne$($script:AssignmentQuery)"] = New-LhList @($Blank, $Blank)
            $Result = InModuleScope $script:moduleName -Parameters @{ Sub = $script:SubA } {
                Get-OERInventoryLighthouseDelegation -Scope "/subscriptions/$Sub"
            }
            @($Result.Delegations).Count | Should -Be 2
        }

        It 'treats a resource group listed without an id as an unread subscription' {
            $SubPath = "/subscriptions/$($script:SubA)"
            $Unreferenced = New-LhDefinition -Sub $script:SubA -Guid '77777777-7777-7777-7777-777777777777'
            $script:Replies["$SubPath$($script:AssignmentQuery)"] = New-LhList
            $script:Replies["$SubPath$($script:DefinitionQuery)"] = New-LhList @($Unreferenced)
            $script:Replies["$SubPath/resourcegroups?api-version=2025-04-01"] = New-LhList @([PSCustomObject]@{ id = ''; name = 'rg-one' })

            $Result = InModuleScope $script:moduleName -Parameters @{ Sub = $script:SubA } {
                Get-OERInventoryLighthouseDelegation -Scope "/subscriptions/$Sub" -WarningAction SilentlyContinue
            }

            @($Result.Delegations).Count | Should -Be 0
            @($Result.Unread) | Should -Be @("lighthouseDelegations at $SubPath")
            @($Result.Causes)[0].Cause | Should -BeLike '*was listed without an id*'
        }
    }

    Context 'nothing is delegated' {
        It 'returns no rows and reads nothing more than the two lists' {
            $SubPath = "/subscriptions/$($script:SubA)"
            $script:Replies["$SubPath$($script:AssignmentQuery)"] = New-LhList
            $script:Replies["$SubPath$($script:DefinitionQuery)"] = New-LhList

            $Result = InModuleScope $script:moduleName -Parameters @{ Sub = $script:SubA } {
                Get-OERInventoryLighthouseDelegation -Scope "/subscriptions/$Sub"
            }

            @($Result.Delegations).Count | Should -Be 0
            @($Result.Unread).Count | Should -Be 0
            @($Result.Causes).Count | Should -Be 0
            Should -Invoke -ModuleName $script:moduleName Invoke-OERArmRequest -Times 0 -ParameterFilter { $Path -like '*/resourcegroups?api-version=2025-04-01' }
            Should -Invoke -ModuleName $script:moduleName Invoke-OERArmRequest -Times 0 -ParameterFilter { $Path -like '*roleDefinitions*' }
            Should -Invoke -ModuleName $script:moduleName Invoke-OERArmRequest -Times 2 -Exactly
        }

        It 'returns an empty Delegations array, not null, and is tagged InventoryLighthouseDelegation' {
            $Result = InModuleScope $script:moduleName { Get-OERInventoryLighthouseDelegation -Scope @() }
            ($Result.PSObject.Properties.Name -join ',') | Should -BeExactly 'Delegations,Unread,Causes'
            $Result.PSObject.TypeNames[0] | Should -BeExactly 'Omnicit.EntraRBAC.InventoryLighthouseDelegation'
            ($Result.Delegations -is [System.Array]) | Should -BeTrue
            ($Result.Unread -is [System.Array]) | Should -BeTrue
            ($Result.Causes -is [System.Array]) | Should -BeTrue
            Should -Invoke -ModuleName $script:moduleName Invoke-OERArmRequest -Times 0
        }
    }

    Context 'a failed read' {
        It 'names the subscription unread, adds one cause and one warning, and still reads the other subscription' {
            $PathA = "/subscriptions/$($script:SubA)"
            $PathB = "/subscriptions/$($script:SubB)"
            $DefinitionB = New-LhDefinition -Sub $script:SubB -Guid '55555555-5555-5555-5555-555555555555'
            $AssignmentB = New-LhAssignment -At $PathB -Guid '66666666-6666-6666-6666-666666666666' -Definition $DefinitionB -Expand
            $script:Replies["$PathA$($script:AssignmentQuery)"] = New-LhArmError -Code 'AuthorizationFailed' -Message 'The client does not have authorization to perform action registrationAssignments/read.'
            $script:Replies["$PathB$($script:AssignmentQuery)"] = New-LhList @($AssignmentB)
            $script:Replies["$PathB$($script:DefinitionQuery)"] = New-LhList @($DefinitionB)
            $script:Replies["$PathB/providers/Microsoft.Authorization/roleDefinitions/$($script:RoleContributor)?api-version=2022-04-01"] = [PSCustomObject]@{ properties = [PSCustomObject]@{ roleName = 'Contributor' } }

            $Result = InModuleScope $script:moduleName -Parameters @{ A = $script:SubA; B = $script:SubB } {
                $Out = Get-OERInventoryLighthouseDelegation -Scope "/subscriptions/$A", "/subscriptions/$B" -WarningVariable W -WarningAction SilentlyContinue -ErrorVariable E -ErrorAction SilentlyContinue
                # -ErrorVariable also holds the records of the layers below (the transport's own throw, caught here);
                # the ones this command wrote itself carry its name as the suffix of their FullyQualifiedErrorId.
                [PSCustomObject]@{ Out = $Out; Warnings = @($W); Errors = @(@($E) | Where-Object { $_.FullyQualifiedErrorId -like '*,Get-OERInventoryLighthouseDelegation' }) }
            }

            @($Result.Out.Delegations).Count | Should -Be 1
            $Result.Out.Delegations[0].subscriptionId | Should -BeExactly $script:SubB
            @($Result.Out.Unread) | Should -Be @("lighthouseDelegations at $PathA")
            @($Result.Out.Causes).Count | Should -Be 1
            $Result.Out.Causes[0].Target | Should -BeExactly $PathA
            $Result.Out.Causes[0].Cause | Should -BeLike 'AuthorizationFailed*'
            @($Result.Warnings).Count | Should -Be 1
            "$($Result.Warnings[0])" | Should -BeExactly "Could not read the Azure Lighthouse delegations at scope '$PathA', so lighthouseDelegations.json holds none of them: AuthorizationFailed: The client does not have authorization to perform action registrationAssignments/read."
            @($Result.Errors).Count | Should -Be 0 -Because 'a helper reports through its result and writes no error record'
        }

        It 'names every scope of the subscription unread once and joins them in the warning' {
            $SubPath = "/subscriptions/$($script:SubA)"
            $script:Replies["$SubPath$($script:AssignmentQuery)"] = New-LhArmError -Code 'Forbidden' -Message 'denied'

            # The first scope is named twice, once in another letter case: it is named once.
            $Result = InModuleScope $script:moduleName -Parameters @{ Sub = $script:SubA } {
                $Out = Get-OERInventoryLighthouseDelegation -Scope "/subscriptions/$Sub/resourceGroups/rg-one", "/subscriptions/$Sub/resourceGroups/rg-one/providers/Microsoft.Web/sites/app", "/subscriptions/$Sub/resourceGroups/RG-ONE" -WarningVariable W -WarningAction SilentlyContinue
                [PSCustomObject]@{ Out = $Out; Warnings = @($W) }
            }

            @($Result.Out.Unread) | Should -Be @(
                "lighthouseDelegations at $SubPath/resourceGroups/rg-one"
                "lighthouseDelegations at $SubPath/resourceGroups/rg-one/providers/Microsoft.Web/sites/app"
            )
            @($Result.Out.Causes).Count | Should -Be 1
            @($Result.Warnings).Count | Should -Be 1
            "$($Result.Warnings[0])" | Should -BeExactly "Could not read the Azure Lighthouse delegations at scope '$SubPath/resourceGroups/rg-one, $SubPath/resourceGroups/rg-one/providers/Microsoft.Web/sites/app', so lighthouseDelegations.json holds none of them: Forbidden: denied"
        }

        It 'leaves a subscription with no row at all when only its definition list fails (whole or nothing)' {
            $SubPath = "/subscriptions/$($script:SubA)"
            $Definition = New-LhDefinition -Sub $script:SubA -Guid '55555555-5555-5555-5555-555555555555'
            $Assignment = New-LhAssignment -At $SubPath -Guid '66666666-6666-6666-6666-666666666666' -Definition $Definition -Expand
            $script:Replies["$SubPath$($script:AssignmentQuery)"] = New-LhList @($Assignment)
            $script:Replies["$SubPath$($script:DefinitionQuery)"] = New-LhArmError -Code 'ServiceUnavailable' -Message 'try later'

            $Result = InModuleScope $script:moduleName -Parameters @{ Sub = $script:SubA } {
                Get-OERInventoryLighthouseDelegation -Scope "/subscriptions/$Sub" -WarningAction SilentlyContinue
            }

            @($Result.Delegations).Count | Should -Be 0
            @($Result.Unread) | Should -Be @("lighthouseDelegations at $SubPath")
            Should -Invoke -ModuleName $script:moduleName Invoke-OERArmRequest -Times 0 -ParameterFilter { $Path -like '*roleDefinitions*' }
        }

        It 'leaves a subscription with no row at all when the resource group listing fails' {
            $SubPath = "/subscriptions/$($script:SubA)"
            $Referenced = New-LhDefinition -Sub $script:SubA -Guid '55555555-5555-5555-5555-555555555555'
            $Unreferenced = New-LhDefinition -Sub $script:SubA -Guid '77777777-7777-7777-7777-777777777777'
            $Assignment = New-LhAssignment -At $SubPath -Guid '66666666-6666-6666-6666-666666666666' -Definition $Referenced -Expand
            $script:Replies["$SubPath$($script:AssignmentQuery)"] = New-LhList @($Assignment)
            $script:Replies["$SubPath$($script:DefinitionQuery)"] = New-LhList @($Referenced, $Unreferenced)
            $script:Replies["$SubPath/resourcegroups?api-version=2025-04-01"] = New-LhArmError -Code 'Throttled' -Message 'slow down'

            $Result = InModuleScope $script:moduleName -Parameters @{ Sub = $script:SubA } {
                Get-OERInventoryLighthouseDelegation -Scope "/subscriptions/$Sub" -WarningAction SilentlyContinue
            }

            @($Result.Delegations).Count | Should -Be 0
            @($Result.Unread) | Should -Be @("lighthouseDelegations at $SubPath")
            @($Result.Causes)[0].Cause | Should -BeLike 'Throttled*'
        }

        It 'leaves a subscription with no row at all when a resource group read fails' {
            $SubPath = "/subscriptions/$($script:SubA)"
            $GroupOne = "$SubPath/resourceGroups/rg-one"
            $GroupTwo = "$SubPath/resourceGroups/rg-two"
            $Referenced = New-LhDefinition -Sub $script:SubA -Guid '55555555-5555-5555-5555-555555555555'
            $Unreferenced = New-LhDefinition -Sub $script:SubA -Guid '77777777-7777-7777-7777-777777777777'
            $Assignment = New-LhAssignment -At $GroupOne -Guid '66666666-6666-6666-6666-666666666666' -Definition $Referenced -Expand
            $script:Replies["$SubPath$($script:AssignmentQuery)"] = New-LhList
            $script:Replies["$SubPath$($script:DefinitionQuery)"] = New-LhList @($Referenced, $Unreferenced)
            $script:Replies["$SubPath/resourcegroups?api-version=2025-04-01"] = New-LhList @([PSCustomObject]@{ id = $GroupOne }, [PSCustomObject]@{ id = $GroupTwo })
            $script:Replies["$GroupOne$($script:AssignmentQuery)"] = New-LhList @($Assignment)
            $script:Replies["$GroupTwo$($script:AssignmentQuery)"] = New-LhArmError -Code 'Forbidden' -Message 'denied at rg-two'

            $Result = InModuleScope $script:moduleName -Parameters @{ Sub = $script:SubA } {
                Get-OERInventoryLighthouseDelegation -Scope "/subscriptions/$Sub" -WarningAction SilentlyContinue
            }

            @($Result.Delegations).Count | Should -Be 0 -Because 'rg-one was read, but the subscription is read whole or not at all'
            @($Result.Unread) | Should -Be @("lighthouseDelegations at $SubPath")
            @($Result.Causes)[0].Cause | Should -BeLike 'Forbidden*'
        }

        It 'names the subscription unread when an assignment has a definition that is neither expanded nor listed' {
            $SubPath = "/subscriptions/$($script:SubA)"
            $Missing = New-LhDefinition -Sub $script:SubA -Guid '88888888-8888-8888-8888-888888888888'
            $Assignment = New-LhAssignment -At $SubPath -Guid '66666666-6666-6666-6666-666666666666' -Definition $Missing
            $script:Replies["$SubPath$($script:AssignmentQuery)"] = New-LhList @($Assignment)
            $script:Replies["$SubPath$($script:DefinitionQuery)"] = New-LhList

            $Result = InModuleScope $script:moduleName -Parameters @{ Sub = $script:SubA } {
                Get-OERInventoryLighthouseDelegation -Scope "/subscriptions/$Sub" -WarningAction SilentlyContinue
            }

            @($Result.Delegations).Count | Should -Be 0
            @($Result.Unread) | Should -Be @("lighthouseDelegations at $SubPath")
            $Result.Causes[0].Cause | Should -BeExactly "The registration definition of the registration assignment '$($Assignment.id)' could not be read."
        }

        It 'scrubs the error record before it reads it' {
            $SubPath = "/subscriptions/$($script:SubA)"
            $script:Replies["$SubPath$($script:AssignmentQuery)"] = New-LhArmError -Code 'Forbidden' -Message 'denied'
            Mock -ModuleName $script:moduleName Remove-OERErrorRecord {}

            $null = InModuleScope $script:moduleName -Parameters @{ Sub = $script:SubA } {
                Get-OERInventoryLighthouseDelegation -Scope "/subscriptions/$Sub" -WarningAction SilentlyContinue
            }

            Should -Invoke -ModuleName $script:moduleName Remove-OERErrorRecord -Times 1 -Exactly
        }
    }

    Context 'the role names' {
        BeforeEach {
            $script:SubPath = "/subscriptions/$($script:SubA)"
            $script:Definition = New-LhDefinition -Sub $script:SubA -Guid '55555555-5555-5555-5555-555555555555' -Authorizations @(
                (New-LhAuthorization -Principal 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa' -Role $script:RoleContributor)
                (New-LhAuthorization -Principal 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb' -Role $script:RoleAccessAdmin -Name 'Access Administrators')
            )
            $Assignment = New-LhAssignment -At $script:SubPath -Guid '66666666-6666-6666-6666-666666666666' -Definition $script:Definition -Expand
            $script:Replies["$($script:SubPath)$($script:AssignmentQuery)"] = New-LhList @($Assignment)
            $script:Replies["$($script:SubPath)$($script:DefinitionQuery)"] = New-LhList @($script:Definition)
        }

        It 'leaves roleName null, and the read not unread, for a role that does not exist' {
            $script:Replies["$($script:SubPath)/providers/Microsoft.Authorization/roleDefinitions/$($script:RoleContributor)?api-version=2022-04-01"] = New-LhArmError -Code 'RoleDefinitionDoesNotExist' -Message 'The specified role definition does not exist.'
            $script:Replies["$($script:SubPath)/providers/Microsoft.Authorization/roleDefinitions/$($script:RoleAccessAdmin)?api-version=2022-04-01"] = New-LhArmError -Code 'NotFound' -Message 'gone'

            $Result = InModuleScope $script:moduleName -Parameters @{ Sub = $script:SubA } {
                $Out = Get-OERInventoryLighthouseDelegation -Scope "/subscriptions/$Sub" -WarningVariable W -WarningAction SilentlyContinue
                [PSCustomObject]@{ Out = $Out; Warnings = @($W) }
            }

            $Result.Out.Delegations[0].authorizations[0].roleName | Should -BeNullOrEmpty
            $Result.Out.Delegations[0].authorizations[1].roleName | Should -BeNullOrEmpty
            @($Result.Out.Unread).Count | Should -Be 0
            @($Result.Out.Causes).Count | Should -Be 0
            @($Result.Warnings).Count | Should -Be 0
        }

        It 'leaves roleName null wherever the role appears, names the read unread, adds a cause and one warning for any other failure' {
            $script:Replies["$($script:SubPath)/providers/Microsoft.Authorization/roleDefinitions/$($script:RoleContributor)?api-version=2022-04-01"] = New-LhArmError -Code 'Forbidden' -Message 'denied'
            $script:Replies["$($script:SubPath)/providers/Microsoft.Authorization/roleDefinitions/$($script:RoleAccessAdmin)?api-version=2022-04-01"] = [PSCustomObject]@{ properties = [PSCustomObject]@{ roleName = 'User Access Administrator' } }

            $Result = InModuleScope $script:moduleName -Parameters @{ Sub = $script:SubA } {
                $Out = Get-OERInventoryLighthouseDelegation -Scope "/subscriptions/$Sub" -WarningVariable W -WarningAction SilentlyContinue
                [PSCustomObject]@{ Out = $Out; Warnings = @($W) }
            }

            @($Result.Out.Delegations).Count | Should -Be 1 -Because 'the row stays; only the role name is unknown'
            $Result.Out.Delegations[0].authorizations[0].roleName | Should -BeNullOrEmpty
            $Result.Out.Delegations[0].authorizations[1].roleName | Should -BeExactly 'User Access Administrator'
            @($Result.Out.Unread) | Should -Be @("lighthouseDelegations role $($script:RoleContributor)")
            @($Result.Out.Causes).Count | Should -Be 1
            $Result.Out.Causes[0].Target | Should -BeExactly $script:RoleContributor
            @($Result.Warnings).Count | Should -Be 1
            "$($Result.Warnings[0])" | Should -BeExactly "Could not read the name of the role '$($script:RoleContributor)' for lighthouseDelegations.json, so roleName is null where it appears: Forbidden: denied"
        }

        It 'scrubs the error record of a failed role read before it reads it' {
            $script:Replies["$($script:SubPath)/providers/Microsoft.Authorization/roleDefinitions/$($script:RoleContributor)?api-version=2022-04-01"] = New-LhArmError -Code 'Forbidden' -Message 'denied'
            $script:Replies["$($script:SubPath)/providers/Microsoft.Authorization/roleDefinitions/$($script:RoleAccessAdmin)?api-version=2022-04-01"] = New-LhArmError -Code 'RoleDefinitionDoesNotExist' -Message 'gone'
            Mock -ModuleName $script:moduleName Remove-OERErrorRecord {}

            $null = InModuleScope $script:moduleName -Parameters @{ Sub = $script:SubA } {
                Get-OERInventoryLighthouseDelegation -Scope "/subscriptions/$Sub" -WarningAction SilentlyContinue
            }

            # Both role reads failed (one of them a role that does not exist): each record is scrubbed.
            Should -Invoke -ModuleName $script:moduleName Remove-OERErrorRecord -Times 2 -Exactly
        }

        It 'reads a role named by a full role definition path by its lower-cased guid, and none that is not a guid' {
            $Odd = New-LhDefinition -Sub $script:SubA -Guid '55555555-5555-5555-5555-555555555555' -Authorizations @(
                (New-LhAuthorization -Role "/subscriptions/$($script:SubA)/providers/Microsoft.Authorization/roleDefinitions/$($script:RoleContributor.ToUpperInvariant())")
                (New-LhAuthorization -Principal 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb' -Role 'not-a-guid')
                (New-LhAuthorization -Principal 'cccccccc-cccc-cccc-cccc-cccccccccccc' -Role '')
            )
            $Assignment = New-LhAssignment -At $script:SubPath -Guid '66666666-6666-6666-6666-666666666666' -Definition $Odd -Expand
            $script:Replies["$($script:SubPath)$($script:AssignmentQuery)"] = New-LhList @($Assignment)
            $script:Replies["$($script:SubPath)$($script:DefinitionQuery)"] = New-LhList @($Odd)
            $script:Replies["$($script:SubPath)/providers/Microsoft.Authorization/roleDefinitions/$($script:RoleContributor)?api-version=2022-04-01"] = [PSCustomObject]@{ properties = [PSCustomObject]@{ roleName = 'Contributor' } }

            $Result = InModuleScope $script:moduleName -Parameters @{ Sub = $script:SubA } {
                Get-OERInventoryLighthouseDelegation -Scope "/subscriptions/$Sub" -WarningAction SilentlyContinue
            }

            $Result.Delegations[0].authorizations[0].roleName | Should -BeExactly 'Contributor'
            $Result.Delegations[0].authorizations[1].roleName | Should -BeNullOrEmpty
            $Result.Delegations[0].authorizations[2].roleName | Should -BeNullOrEmpty
            @($Result.Unread).Count | Should -Be 0
            Should -Invoke -ModuleName $script:moduleName Invoke-OERArmRequest -Times 1 -Exactly -ParameterFilter { $Path -like '*roleDefinitions/*' }
        }

        It 'reads a role at the subscription of the first row that carries it' {
            $PathB = "/subscriptions/$($script:SubB)"
            $DefinitionB = New-LhDefinition -Sub $script:SubB -Guid '55555555-5555-5555-5555-555555555555' -Authorizations @(
                (New-LhAuthorization -Role $script:RoleContributor)
                (New-LhAuthorization -Principal 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb' -Role $script:RoleOther)
            )
            $AssignmentB = New-LhAssignment -At $PathB -Guid '66666666-6666-6666-6666-666666666666' -Definition $DefinitionB -Expand
            $script:Replies["$PathB$($script:AssignmentQuery)"] = New-LhList @($AssignmentB)
            $script:Replies["$PathB$($script:DefinitionQuery)"] = New-LhList @($DefinitionB)
            $script:Replies["$($script:SubPath)/providers/Microsoft.Authorization/roleDefinitions/$($script:RoleContributor)?api-version=2022-04-01"] = [PSCustomObject]@{ properties = [PSCustomObject]@{ roleName = 'Contributor' } }
            $script:Replies["$($script:SubPath)/providers/Microsoft.Authorization/roleDefinitions/$($script:RoleAccessAdmin)?api-version=2022-04-01"] = [PSCustomObject]@{ properties = [PSCustomObject]@{ roleName = 'User Access Administrator' } }
            $script:Replies["$PathB/providers/Microsoft.Authorization/roleDefinitions/$($script:RoleOther)?api-version=2022-04-01"] = [PSCustomObject]@{ properties = [PSCustomObject]@{ roleName = 'Reader' } }

            $Result = InModuleScope $script:moduleName -Parameters @{ A = $script:SubA; B = $script:SubB } {
                Get-OERInventoryLighthouseDelegation -Scope "/subscriptions/$A", "/subscriptions/$B" -WarningAction SilentlyContinue
            }

            @($Result.Delegations).Count | Should -Be 2
            @($Result.Unread).Count | Should -Be 0
            # Contributor is first carried by the row at SubA, so it is read there and only there.
            Should -Invoke -ModuleName $script:moduleName Invoke-OERArmRequest -Times 1 -Exactly -ParameterFilter { $Path -like '/subscriptions/11111111-1111-1111-1111-111111111111/providers/Microsoft.Authorization/roleDefinitions/dddddddd-*' }
            Should -Invoke -ModuleName $script:moduleName Invoke-OERArmRequest -Times 0 -ParameterFilter { $Path -like '/subscriptions/22222222-2222-2222-2222-222222222222/providers/Microsoft.Authorization/roleDefinitions/dddddddd-*' }
            Should -Invoke -ModuleName $script:moduleName Invoke-OERArmRequest -Times 1 -Exactly -ParameterFilter { $Path -like '/subscriptions/22222222-2222-2222-2222-222222222222/providers/Microsoft.Authorization/roleDefinitions/ffffffff-*' }
        }

        It 'reads a role at the subscription it was listed from when the row names none' {
            $Definition = New-LhDefinition -Sub $script:SubA -Guid '55555555-5555-5555-5555-555555555555' -Authorizations @((New-LhAuthorization -Role $script:RoleContributor))
            # An assignment id whose scope part is not a subscription path: the row has no subscription id.
            $Odd = [PSCustomObject]@{
                id         = '/odd/providers/Microsoft.ManagedServices/registrationAssignments/66666666-6666-6666-6666-666666666666'
                properties = [PSCustomObject]@{ registrationDefinitionId = $Definition.id; registrationDefinition = $Definition }
            }
            $script:Replies["$($script:SubPath)$($script:AssignmentQuery)"] = New-LhList @($Odd)
            $script:Replies["$($script:SubPath)$($script:DefinitionQuery)"] = New-LhList @($Definition)
            $script:Replies["$($script:SubPath)/providers/Microsoft.Authorization/roleDefinitions/$($script:RoleContributor)?api-version=2022-04-01"] = [PSCustomObject]@{ properties = [PSCustomObject]@{ roleName = 'Contributor' } }

            $Result = InModuleScope $script:moduleName -Parameters @{ Sub = $script:SubA } {
                Get-OERInventoryLighthouseDelegation -Scope "/subscriptions/$Sub" -WarningAction SilentlyContinue
            }

            $Result.Delegations[0].subscriptionId | Should -BeNullOrEmpty
            $Result.Delegations[0].authorizations[0].roleName | Should -BeExactly 'Contributor'
            @($Result.Unread).Count | Should -Be 0
        }
    }

    Context 'which scopes are read' {
        It 'sends no request for a management group scope or the root scope' {
            InModuleScope $script:moduleName {
                $Result = Get-OERInventoryLighthouseDelegation -Scope '/providers/Microsoft.Management/managementGroups/mg-platform', '/'
                @($Result.Delegations).Count | Should -Be 0
                @($Result.Unread).Count | Should -Be 0
            }
            Should -Invoke -ModuleName $script:moduleName Invoke-OERArmRequest -Times 0
        }

        It 'reads the two lists and the named resource group, keeps the rows at the subscription and that group, and drops the rest' {
            $SubPath = "/subscriptions/$($script:SubA)"
            $GroupA = "$SubPath/resourceGroups/rgA"
            $GroupB = "$SubPath/resourceGroups/rgB"
            $DefinitionOne = New-LhDefinition -Sub $script:SubA -Guid '55555555-5555-5555-5555-555555555555'
            # Unreferenced by any assignment: a subscription named whole would list its groups for this one.
            $DefinitionIdle = New-LhDefinition -Sub $script:SubA -Guid '77777777-7777-7777-7777-777777777777' -Offer 'Idle offer'
            $AtSub = New-LhAssignment -At $SubPath -Guid '11111111-0000-0000-0000-000000000001' -Definition $DefinitionOne -Expand
            $AtGroupA = New-LhAssignment -At $GroupA -Guid '11111111-0000-0000-0000-000000000002' -Definition $DefinitionOne -Expand
            $AtGroupB = New-LhAssignment -At $GroupB -Guid '11111111-0000-0000-0000-000000000003' -Definition $DefinitionOne -Expand
            $script:Replies["$SubPath$($script:AssignmentQuery)"] = New-LhList @($AtSub, $AtGroupA, $AtGroupB)
            $script:Replies["$SubPath$($script:DefinitionQuery)"] = New-LhList @($DefinitionOne, $DefinitionIdle)
            $script:Replies["$GroupA$($script:AssignmentQuery)"] = New-LhList @($AtGroupA)
            $script:Replies["$SubPath/providers/Microsoft.Authorization/roleDefinitions/$($script:RoleContributor)?api-version=2022-04-01"] = [PSCustomObject]@{ properties = [PSCustomObject]@{ roleName = 'Contributor' } }

            $Result = InModuleScope $script:moduleName -Parameters @{ Sub = $script:SubA } {
                Get-OERInventoryLighthouseDelegation -Scope "/subscriptions/$Sub/resourceGroups/rgA", "/subscriptions/$Sub/resourceGroups/rgA/providers/Microsoft.Web/sites/app"
            }

            @($Result.Delegations | ForEach-Object { $_.scope }) | Should -Be @($SubPath, $GroupA)
            @($Result.Unread).Count | Should -Be 0
            Should -Invoke -ModuleName $script:moduleName Invoke-OERArmRequest -Times 1 -Exactly -ParameterFilter { $Path -like '/subscriptions/11111111-1111-1111-1111-111111111111/providers/Microsoft.ManagedServices/registrationAssignments?*' }
            Should -Invoke -ModuleName $script:moduleName Invoke-OERArmRequest -Times 1 -Exactly -ParameterFilter { $Path -like '/subscriptions/11111111-1111-1111-1111-111111111111/providers/Microsoft.ManagedServices/registrationDefinitions?*' }
            Should -Invoke -ModuleName $script:moduleName Invoke-OERArmRequest -Times 1 -Exactly -ParameterFilter { $Path -like '*/resourceGroups/rgA/providers/Microsoft.ManagedServices/registrationAssignments?*' }
            Should -Invoke -ModuleName $script:moduleName Invoke-OERArmRequest -Times 0 -ParameterFilter { $Path -like '*/resourcegroups?api-version=2025-04-01' }
            Should -Invoke -ModuleName $script:moduleName Invoke-OERArmRequest -Times 0 -ParameterFilter { $Path -like '*/resourceGroups/rgB/*' }
        }

        It 'keeps only the subscription delegation when a scope below the subscription names no resource group' {
            $SubPath = "/subscriptions/$($script:SubA)"
            $DefinitionOne = New-LhDefinition -Sub $script:SubA -Guid '55555555-5555-5555-5555-555555555555'
            $AtSub = New-LhAssignment -At $SubPath -Guid '11111111-0000-0000-0000-000000000001' -Definition $DefinitionOne -Expand
            $AtGroup = New-LhAssignment -At "$SubPath/resourceGroups/rgC" -Guid '11111111-0000-0000-0000-000000000002' -Definition $DefinitionOne -Expand
            $script:Replies["$SubPath$($script:AssignmentQuery)"] = New-LhList @($AtSub, $AtGroup)
            $script:Replies["$SubPath$($script:DefinitionQuery)"] = New-LhList @($DefinitionOne)
            $script:Replies["$SubPath/providers/Microsoft.Authorization/roleDefinitions/$($script:RoleContributor)?api-version=2022-04-01"] = [PSCustomObject]@{ properties = [PSCustomObject]@{ roleName = 'Contributor' } }

            $Result = InModuleScope $script:moduleName -Parameters @{ Sub = $script:SubA } {
                Get-OERInventoryLighthouseDelegation -Scope "/subscriptions/$Sub/providers/Microsoft.Web/sites/app"
            }

            @($Result.Delegations | ForEach-Object { $_.scope }) | Should -Be @($SubPath)
            Should -Invoke -ModuleName $script:moduleName Invoke-OERArmRequest -Times 0 -ParameterFilter { $Path -like '*/resourcegroups?api-version=2025-04-01' }
        }

        It 'reads a subscription named twice, in any letter case and by several scopes, once' {
            # Letters in the id, so that the letter case of a second spelling is a real difference.
            $SubLetters = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'
            $SubPath = "/subscriptions/$SubLetters"
            $script:Replies["$SubPath$($script:AssignmentQuery)"] = New-LhList
            $script:Replies["$SubPath$($script:DefinitionQuery)"] = New-LhList

            InModuleScope $script:moduleName -Parameters @{ Sub = $SubLetters } {
                $null = Get-OERInventoryLighthouseDelegation -Scope "/subscriptions/$Sub", "/subscriptions/$($Sub.ToUpperInvariant())", "/subscriptions/$Sub/"
            }

            Should -Invoke -ModuleName $script:moduleName Invoke-OERArmRequest -Times 1 -Exactly -ParameterFilter { $Path -like '*registrationAssignments?*' }
            Should -Invoke -ModuleName $script:moduleName Invoke-OERArmRequest -Times 1 -Exactly -ParameterFilter { $Path -like '*registrationDefinitions?*' }
        }

        It 'reads a subscription named whole and through a resource group as whole' {
            $SubPath = "/subscriptions/$($script:SubA)"
            $Referenced = New-LhDefinition -Sub $script:SubA -Guid '55555555-5555-5555-5555-555555555555'
            $Unreferenced = New-LhDefinition -Sub $script:SubA -Guid '77777777-7777-7777-7777-777777777777'
            $AtGroupB = New-LhAssignment -At "$SubPath/resourceGroups/rgB" -Guid '11111111-0000-0000-0000-000000000003' -Definition $Referenced -Expand
            $script:Replies["$SubPath$($script:AssignmentQuery)"] = New-LhList @($AtGroupB)
            $script:Replies["$SubPath$($script:DefinitionQuery)"] = New-LhList @($Referenced, $Unreferenced)
            $script:Replies["$SubPath/resourcegroups?api-version=2025-04-01"] = New-LhList @([PSCustomObject]@{ id = "$SubPath/resourceGroups/rgA" })
            $script:Replies["$SubPath/resourceGroups/rgA$($script:AssignmentQuery)"] = New-LhList
            $script:Replies["$SubPath/providers/Microsoft.Authorization/roleDefinitions/$($script:RoleContributor)?api-version=2022-04-01"] = [PSCustomObject]@{ properties = [PSCustomObject]@{ roleName = 'Contributor' } }

            $Result = InModuleScope $script:moduleName -Parameters @{ Sub = $script:SubA } {
                Get-OERInventoryLighthouseDelegation -Scope "/subscriptions/$Sub/resourceGroups/rgA", "/subscriptions/$Sub"
            }

            # Whole: the row at rgB (not named by any scope) is kept, and the groups are listed.
            @($Result.Delegations | ForEach-Object { $_.resourceGroup }) | Should -Be @('rgB')
            Should -Invoke -ModuleName $script:moduleName Invoke-OERArmRequest -Times 1 -Exactly -ParameterFilter { $Path -like '*/resourcegroups?api-version=2025-04-01' }
        }
    }

    Context 'the order of the rows' {
        It 'sorts by scope, managing tenant, offer and assignment id' {
            $PathA = "/subscriptions/$($script:SubA)"
            $PathB = "/subscriptions/$($script:SubB)"
            $T1 = '33333333-3333-3333-3333-333333333333'
            $T2 = '99999999-9999-9999-9999-999999999999'
            $DefAlphaT1 = New-LhDefinition -Sub $script:SubA -Guid '12121212-0000-0000-0000-00000000000a' -Offer 'Alpha' -Tenant $T1
            $DefZetaT1 = New-LhDefinition -Sub $script:SubA -Guid '12121212-0000-0000-0000-00000000000b' -Offer 'Zeta' -Tenant $T1
            $DefAlphaT2 = New-LhDefinition -Sub $script:SubA -Guid '12121212-0000-0000-0000-00000000000c' -Offer 'Alpha' -Tenant $T2
            $DefBeta = New-LhDefinition -Sub $script:SubB -Guid '12121212-0000-0000-0000-00000000000d' -Offer 'Beta' -Tenant $T1
            $Rows = @(
                # Handed over in an order that is none of the sort orders.
                New-LhAssignment -At $PathA -Guid '12121212-0000-0000-0000-000000000005' -Definition $DefAlphaT2 -Expand
                New-LhAssignment -At "$PathA/resourceGroups/rg1" -Guid '12121212-0000-0000-0000-000000000001' -Definition $DefAlphaT1 -Expand
                New-LhAssignment -At $PathA -Guid '12121212-0000-0000-0000-000000000004' -Definition $DefZetaT1 -Expand
                New-LhAssignment -At $PathA -Guid '12121212-0000-0000-0000-000000000003' -Definition $DefAlphaT1 -Expand
                New-LhAssignment -At $PathA -Guid '12121212-0000-0000-0000-000000000002' -Definition $DefAlphaT1 -Expand
            )
            $script:Replies["$PathA$($script:AssignmentQuery)"] = New-LhList $Rows
            $script:Replies["$PathA$($script:DefinitionQuery)"] = New-LhList @($DefAlphaT1, $DefZetaT1, $DefAlphaT2)
            $script:Replies["$PathB$($script:AssignmentQuery)"] = New-LhList @(New-LhAssignment -At $PathB -Guid '12121212-0000-0000-0000-000000000006' -Definition $DefBeta -Expand)
            $script:Replies["$PathB$($script:DefinitionQuery)"] = New-LhList @($DefBeta)
            # Named in the reverse of the sort order, so the order of the scopes decides nothing. The first
            # row carries the role at SubB, so that is where its name is read.
            $script:Replies["$PathB/providers/Microsoft.Authorization/roleDefinitions/$($script:RoleContributor)?api-version=2022-04-01"] = [PSCustomObject]@{ properties = [PSCustomObject]@{ roleName = 'Contributor' } }

            $Result = InModuleScope $script:moduleName -Parameters @{ A = $script:SubA; B = $script:SubB } {
                Get-OERInventoryLighthouseDelegation -Scope "/subscriptions/$B", "/subscriptions/$A" -WarningAction SilentlyContinue
            }

            @($Result.Unread).Count | Should -Be 0
            $Order = @($Result.Delegations | ForEach-Object {
                    '{0}|{1}|{2}|{3}' -f $_.scope.Replace($script:SubA, 'A').Replace($script:SubB, 'B'), $_.managedByTenantId.Substring(0, 2), $_.offerName, $_.registrationAssignmentId.Substring($_.registrationAssignmentId.Length - 2)
                })
            $Order | Should -Be @(
                '/subscriptions/A|33|Alpha|02'
                '/subscriptions/A|33|Alpha|03'
                '/subscriptions/A|33|Zeta|04'
                '/subscriptions/A|99|Alpha|05'
                '/subscriptions/A/resourceGroups/rg1|33|Alpha|01'
                '/subscriptions/B|33|Beta|06'
            )
        }
    }
}
