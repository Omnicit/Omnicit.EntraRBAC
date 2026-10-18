BeforeAll {
    $script:moduleName = 'Omnicit.EntraRBAC'
    Get-Module $script:moduleName | Remove-Module -Force -ErrorAction SilentlyContinue
    Import-Module $script:moduleName -Force -ErrorAction Stop
    . "$PSScriptRoot/../TestHelpers/OERTransportTripwire.ps1"
    Install-OERTransportTripwire

    # The four list requests and the three full-read forms the reader sends, written out here rather
    # than imported from it.
    $script:PermissionListUri = 'v1.0/servicePrincipals?$select=id,appId,displayName,appRoles&$expand=appRoleAssignments&$top=999'
    $script:SpOwnerListUri = 'v1.0/servicePrincipals?$select=id,displayName&$expand=owners($select=id,displayName,userPrincipalName)&$top=999'
    $script:AppOwnerListUri = 'v1.0/applications?$select=id,appId,displayName&$expand=owners($select=id,displayName,userPrincipalName)&$top=999'
    $script:GrantListUri = 'v1.0/oauth2PermissionGrants?$top=999'
    function script:Get-PermissionReReadUri { param([string]$Id) "v1.0/servicePrincipals/$Id/appRoleAssignments?`$top=999" }
    function script:Get-SpOwnerReReadUri { param([string]$Id) "v1.0/servicePrincipals/$Id/owners?`$select=id,displayName,userPrincipalName&`$top=999" }
    function script:Get-AppOwnerReReadUri { param([string]$Id) "v1.0/applications/$Id/owners?`$select=id,displayName,userPrincipalName&`$top=999" }

    # Placeholder ids, none of them version 4 shaped.
    $script:ClientId = '11111111-1111-1111-1111-111111111111'
    $script:ResourceId = '22222222-2222-2222-2222-222222222222'
    $script:GoneResourceId = '99999999-9999-9999-9999-999999999999'
    $script:RoleUserRead = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'
    $script:RoleGroupRead = 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb'
    $script:RoleRemoved = 'cccccccc-cccc-cccc-cccc-cccccccccccc'
    $script:DefaultAccessRole = '00000000-0000-0000-0000-000000000000'
    $script:UserOne = '33333333-3333-3333-3333-333333333333'
    $script:UserTwo = '66666666-6666-6666-6666-666666666666'
    $script:UserGone = '88888888-8888-8888-8888-888888888888'
    $script:ClientAppObjectId = '55555555-5555-5555-5555-555555555555'
    $script:ClientAppId = '12121212-1212-1212-1212-121212121212'
    $script:OtherAppObjectId = '77777777-7777-7777-7777-777777777777'
    $script:OtherAppId = '78787878-7878-7878-7878-787878787878'

    function script:New-SpaList { param([object[]]$Value = @()) @{ value = @($Value) } }
    function script:New-SpaGraphError {
        param([string]$Code = 'Authorization_RequestDenied', [string]$Message = 'Insufficient privileges to complete the operation. (403)')
        [System.Management.Automation.ErrorRecord]::new([System.Exception]::new($Message), $Code, [System.Management.Automation.ErrorCategory]::PermissionDenied, $null)
    }
    function script:New-SpaOwner {
        param([string]$Type, [string]$Id, [string]$Name, [string]$Upn)
        $Owner = @{ '@odata.type' = $Type; id = $Id; displayName = $Name }
        if ($Upn) { $Owner.userPrincipalName = $Upn }
        $Owner
    }

    # The answers of the mocked transport for a small tenant: a client service principal holding two
    # app roles of a resource it lists (one the resource declares, one it no longer does) and the
    # default access role of a resource the list does not hold; the resource itself, holding nothing.
    # Every object is a hashtable, as the transport returns it.
    function script:New-SpaReplies {
        $Client = @{
            id = $script:ClientId; appId = $script:ClientAppId; displayName = 'Client App'; appRoles = @()
            appRoleAssignments = @(
                @{ id = 'assign-1'; appRoleId = $script:RoleUserRead; principalId = $script:ClientId; principalType = 'ServicePrincipal'; resourceId = $script:ResourceId; resourceDisplayName = 'Graph Resource (assignment)' }
                @{ id = 'assign-2'; appRoleId = $script:RoleRemoved; principalId = $script:ClientId; principalType = 'ServicePrincipal'; resourceId = $script:ResourceId; resourceDisplayName = 'Graph Resource (assignment)' }
                @{ id = 'assign-3'; appRoleId = $script:DefaultAccessRole; principalId = $script:ClientId; principalType = 'ServicePrincipal'; resourceId = $script:GoneResourceId; resourceDisplayName = 'Gone Resource' }
            )
        }
        $Resource = @{
            id = $script:ResourceId; appId = '23232323-2323-2323-2323-232323232323'; displayName = 'Graph Resource'
            appRoles = @(
                @{ id = $script:RoleUserRead; value = 'User.Read.All'; displayName = 'Read all users' }
                @{ id = $script:RoleGroupRead; value = 'Group.Read.All'; displayName = 'Read all groups' }
            )
            appRoleAssignments = @()
        }
        @{
            $script:PermissionListUri = New-SpaList @($Client, $Resource)
            $script:SpOwnerListUri    = New-SpaList @(
                @{ id = $script:ClientId; displayName = 'Client App'; owners = @(New-SpaOwner -Type '#microsoft.graph.user' -Id $script:UserOne -Name 'Person One' -Upn 'person1@example.com') }
                @{ id = $script:ResourceId; displayName = 'Graph Resource'; owners = @(New-SpaOwner -Type '#microsoft.graph.servicePrincipal' -Id $script:ClientId -Name 'Client App') }
            )
            $script:AppOwnerListUri   = New-SpaList @(
                @{ id = $script:ClientAppObjectId; appId = $script:ClientAppId; displayName = 'Client App'; owners = @(New-SpaOwner -Type '#microsoft.graph.user' -Id $script:UserTwo -Name 'Person Two' -Upn 'person2@example.com') }
                @{ id = $script:OtherAppObjectId; appId = $script:OtherAppId; displayName = 'Other App'; owners = @(New-SpaOwner -Type '#microsoft.graph.servicePrincipal' -Id $script:ClientId -Name 'Client App') }
            )
            $script:GrantListUri      = New-SpaList @(
                @{ id = 'grant-1'; clientId = $script:ClientId; consentType = 'AllPrincipals'; principalId = $null; resourceId = $script:ResourceId; scope = ' User.Read openid ' }
                @{ id = 'grant-2'; clientId = $script:ClientId; consentType = 'Principal'; principalId = $script:UserOne; resourceId = $script:ResourceId; scope = 'Mail.Read' }
                @{ id = 'grant-3'; clientId = $script:ClientId; consentType = 'Principal'; principalId = $script:UserGone; resourceId = $script:ResourceId; scope = 'Files.Read' }
            )
        }
    }

    # N expanded entries, each with an id of its own, none version 4 shaped.
    function script:New-SpaAssignments {
        param([int]$Count, [string]$Client)
        @(for ($Index = 1; $Index -le $Count; $Index++) {
                @{ id = "assign-$Index"; appRoleId = ('{0:d8}-0000-0000-0000-000000000000' -f $Index); principalId = $Client; resourceId = '22222222-2222-2222-2222-222222222222'; resourceDisplayName = 'Graph Resource' }
            })
    }
    function script:New-SpaOwners {
        param([int]$Count)
        @(for ($Index = 1; $Index -le $Count; $Index++) {
                New-SpaOwner -Type '#microsoft.graph.user' -Id ('{0:d8}-3333-3333-3333-333333333333' -f $Index) -Name ('Owner {0:d2}' -f $Index) -Upn ('person{0}@example.com' -f $Index)
            })
    }

    function script:Invoke-Spa {
        InModuleScope $script:moduleName { Get-OERServicePrincipalAccess }
    }
}

AfterAll {
    try { Assert-OERTransportTripwire } finally { Uninstall-OERTransportTripwire }
}

Describe 'Get-OERServicePrincipalAccess' {
    BeforeEach {
        InModuleScope $script:moduleName { $script:_OERAuthState = $null }
        Mock -ModuleName $script:moduleName Initialize-OERAuth {}
        # The one answer table of the mocked transport: a request to its answer, or to an error record
        # the mock throws. A request nobody listed is a failed read, so a request the reader should not
        # have made shows as a missing part and not as an empty answer.
        $script:Replies = New-SpaReplies
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {
            if (-not $script:Replies.ContainsKey($Uri)) { throw "No mocked answer for '$Uri'." }
            $Reply = $script:Replies[$Uri]
            if ($Reply -is [System.Management.Automation.ErrorRecord]) { throw $Reply }
            $Reply
        }
        # The user lookup: an id in this table is answered with its entry; any other id is one the
        # directory did not return. Name follows the helper's own rule (the UPN for a user), so a row that
        # took Name for either of its two names shows.
        $script:Lookup = @{
            $script:UserOne = [PSCustomObject]@{ Id = $script:UserOne; Read = $true; Found = $true; Name = 'person1@example.com'; ObjectType = 'user'; DisplayName = 'Person One'; UserPrincipalName = 'person1@example.com'; Cause = $null }
        }
        Mock -ModuleName $script:moduleName Resolve-OERPrincipalName {
            foreach ($One in @($Id)) {
                if ($script:Lookup.ContainsKey($One)) { $script:Lookup[$One] }
                else { [PSCustomObject]@{ Id = $One; Read = $true; Found = $false; Name = $null; ObjectType = $null; DisplayName = $null; UserPrincipalName = $null; Cause = $null } }
            }
        }
    }

    Context 'every part as read' {
        It 'returns one object tagged Omnicit.EntraRBAC.ServicePrincipalAccess with the six properties in order' {
            $Result = Invoke-Spa
            @($Result).Count | Should -Be 1
            $Result.PSObject.TypeNames[0] | Should -BeExactly 'Omnicit.EntraRBAC.ServicePrincipalAccess'
            ($Result.PSObject.Properties.Name -join ',') | Should -BeExactly 'ApplicationPermissions,DelegatedPermissionGrants,ApplicationOwners,ServicePrincipalOwners,Unread,Causes'
            @($Result.Unread).Count | Should -Be 0
            @($Result.Causes).Count | Should -Be 0
        }

        It 'writes the application permissions from the client side, a declared role mapped to its value and an undeclared one to null' {
            $Rows = @((Invoke-Spa).ApplicationPermissions)
            $Rows.Count | Should -Be 3
            ($Rows[0].PSObject.Properties.Name -join ',') | Should -BeExactly 'servicePrincipalId,servicePrincipalDisplayName,resourceId,resourceDisplayName,appRoleId,appRoleValue'
            # Sorted on the client's name, then the resource's: 'Gone Resource' before 'Graph Resource'.
            $Rows[0].servicePrincipalId | Should -BeExactly $script:ClientId
            $Rows[0].servicePrincipalDisplayName | Should -BeExactly 'Client App'
            $Rows[0].resourceId | Should -BeExactly $script:GoneResourceId
            # The resource is not in the list: its name is the assignment's, and the default access role
            # is declared by no listed resource.
            $Rows[0].resourceDisplayName | Should -BeExactly 'Gone Resource'
            $Rows[0].appRoleId | Should -BeExactly $script:DefaultAccessRole
            $null -eq $Rows[0].appRoleValue | Should -BeTrue
            # The resource is listed: its own name wins over the assignment's.
            $Rows[1].resourceDisplayName | Should -BeExactly 'Graph Resource'
            $Rows[1].appRoleId | Should -BeExactly $script:RoleUserRead
            $Rows[1].appRoleValue | Should -BeExactly 'User.Read.All'
            # A role the resource does not declare (since removed) has no value.
            $Rows[2].appRoleId | Should -BeExactly $script:RoleRemoved
            $null -eq $Rows[2].appRoleValue | Should -BeTrue
        }

        It 'writes the delegated permission grants: AllPrincipals without a principal, a Principal found and one the directory did not return' {
            $Rows = @((Invoke-Spa).DelegatedPermissionGrants)
            $Rows.Count | Should -Be 3
            ($Rows[0].PSObject.Properties.Name -join ',') | Should -BeExactly 'clientId,clientDisplayName,resourceId,resourceDisplayName,consentType,principalId,principalDisplayName,principalUserPrincipalName,scope'
            # Same client and resource names: sorted on the ids, a null principal id first.
            $Rows[0].clientId | Should -BeExactly $script:ClientId
            $Rows[0].clientDisplayName | Should -BeExactly 'Client App'
            $Rows[0].resourceId | Should -BeExactly $script:ResourceId
            $Rows[0].resourceDisplayName | Should -BeExactly 'Graph Resource'
            $Rows[0].consentType | Should -BeExactly 'AllPrincipals'
            $null -eq $Rows[0].principalId | Should -BeTrue
            $null -eq $Rows[0].principalDisplayName | Should -BeTrue
            $null -eq $Rows[0].principalUserPrincipalName | Should -BeTrue
            # The scope string is trimmed, its inner space kept.
            $Rows[0].scope | Should -BeExactly 'User.Read openid'
            $Rows[1].consentType | Should -BeExactly 'Principal'
            $Rows[1].principalId | Should -BeExactly $script:UserOne
            # The user's display name and user principal name, each in its own key (Ruling R-8).
            $Rows[1].principalDisplayName | Should -BeExactly 'Person One'
            $Rows[1].principalUserPrincipalName | Should -BeExactly 'person1@example.com'
            $Rows[1].scope | Should -BeExactly 'Mail.Read'
            $Rows[2].principalId | Should -BeExactly $script:UserGone
            $null -eq $Rows[2].principalDisplayName | Should -BeTrue
            $null -eq $Rows[2].principalUserPrincipalName | Should -BeTrue
            $Rows[2].scope | Should -BeExactly 'Files.Read'
            # ONE lookup, for the two users the Principal grants name, and none for AllPrincipals.
            Should -Invoke -ModuleName $script:moduleName Resolve-OERPrincipalName -Times 1 -Exactly -ParameterFilter {
                $Detailed -and @($Id).Count -eq 2 -and $Id -contains '33333333-3333-3333-3333-333333333333' -and $Id -contains '88888888-8888-8888-8888-888888888888'
            }
        }

        It 'writes each of the two names of a found user on its own, a blank one as null (<Case>)' -ForEach @(
            @{ Case = 'a blank user principal name'; DisplayName = 'Person One'; UserPrincipalName = '  '; ExpectDisplay = 'Person One'; ExpectUpn = $null }
            @{ Case = 'a blank display name'; DisplayName = ''; UserPrincipalName = 'person1@example.com'; ExpectDisplay = $null; ExpectUpn = 'person1@example.com' }
        ) {
            # Name is set to the other value on purpose: the row reads the two names, never Name.
            $script:Lookup[$script:UserOne] = [PSCustomObject]@{ Id = $script:UserOne; Read = $true; Found = $true; Name = 'name-rule-choice'; ObjectType = 'user'; DisplayName = $DisplayName; UserPrincipalName = $UserPrincipalName; Cause = $null }
            $Row = @(@((Invoke-Spa).DelegatedPermissionGrants) | Where-Object { $_.principalId -eq $script:UserOne })[0]
            $Row | Should -Not -BeNullOrEmpty
            if ($null -eq $ExpectDisplay) { $null -eq $Row.principalDisplayName | Should -BeTrue } else { $Row.principalDisplayName | Should -BeExactly $ExpectDisplay }
            if ($null -eq $ExpectUpn) { $null -eq $Row.principalUserPrincipalName | Should -BeTrue } else { $Row.principalUserPrincipalName | Should -BeExactly $ExpectUpn }
        }

        It 'writes the owners of the app registrations and of the service principals, of type user and servicePrincipal' {
            $Result = Invoke-Spa
            $AppOwners = @($Result.ApplicationOwners)
            $AppOwners.Count | Should -Be 2
            ($AppOwners[0].PSObject.Properties.Name -join ',') | Should -BeExactly 'applicationId,appId,applicationDisplayName,ownerId,ownerType,ownerDisplayName,ownerUserPrincipalName'
            $AppOwners[0].applicationId | Should -BeExactly $script:ClientAppObjectId
            $AppOwners[0].appId | Should -BeExactly $script:ClientAppId
            $AppOwners[0].applicationDisplayName | Should -BeExactly 'Client App'
            $AppOwners[0].ownerId | Should -BeExactly $script:UserTwo
            $AppOwners[0].ownerType | Should -BeExactly 'User'
            $AppOwners[0].ownerDisplayName | Should -BeExactly 'Person Two'
            $AppOwners[0].ownerUserPrincipalName | Should -BeExactly 'person2@example.com'
            $AppOwners[1].applicationDisplayName | Should -BeExactly 'Other App'
            $AppOwners[1].ownerType | Should -BeExactly 'ServicePrincipal'
            $AppOwners[1].ownerId | Should -BeExactly $script:ClientId
            $null -eq $AppOwners[1].ownerUserPrincipalName | Should -BeTrue

            $SpOwners = @($Result.ServicePrincipalOwners)
            $SpOwners.Count | Should -Be 2
            ($SpOwners[0].PSObject.Properties.Name -join ',') | Should -BeExactly 'servicePrincipalId,servicePrincipalDisplayName,ownerId,ownerType,ownerDisplayName,ownerUserPrincipalName'
            $SpOwners[0].servicePrincipalId | Should -BeExactly $script:ClientId
            $SpOwners[0].servicePrincipalDisplayName | Should -BeExactly 'Client App'
            $SpOwners[0].ownerType | Should -BeExactly 'User'
            $SpOwners[0].ownerUserPrincipalName | Should -BeExactly 'person1@example.com'
            $SpOwners[1].servicePrincipalDisplayName | Should -BeExactly 'Graph Resource'
            $SpOwners[1].ownerType | Should -BeExactly 'ServicePrincipal'
            $SpOwners[1].ownerDisplayName | Should -BeExactly 'Client App'
            $null -eq $SpOwners[1].ownerUserPrincipalName | Should -BeTrue
        }

        It 'writes an owner type the principal type enum does not hold without its prefix, and none at all as null' {
            $script:Replies[$script:SpOwnerListUri] = New-SpaList @(
                @{ id = $script:ClientId; displayName = 'Client App'; owners = @(
                        (New-SpaOwner -Type '#microsoft.graph.device' -Id '44444444-4444-4444-4444-444444444444' -Name 'A Device')
                        @{ id = '45454545-4545-4545-4545-454545454545'; displayName = 'No Type' }
                    )
                }
            )
            $Rows = @((Invoke-Spa).ServicePrincipalOwners)
            $Rows.Count | Should -Be 2
            $Rows[0].ownerDisplayName | Should -BeExactly 'A Device'
            $Rows[0].ownerType | Should -BeExactly 'device'
            $Rows[1].ownerDisplayName | Should -BeExactly 'No Type'
            $null -eq $Rows[1].ownerType | Should -BeTrue
        }

        It 'writes every blank text as null and every id lower-cased' {
            $script:Replies[$script:AppOwnerListUri] = New-SpaList @(
                @{ id = '5A5A5A5A-5A5A-5A5A-5A5A-5A5A5A5A5A5A'; appId = '   '; displayName = ''; owners = @(
                        @{ '@odata.type' = '#microsoft.graph.user'; id = 'ABABABAB-ABAB-ABAB-ABAB-ABABABABABAB'; displayName = ' '; userPrincipalName = '' }
                    )
                }
            )
            $Row = @((Invoke-Spa).ApplicationOwners)[0]
            $Row.applicationId | Should -BeExactly '5a5a5a5a-5a5a-5a5a-5a5a-5a5a5a5a5a5a'
            $Row.ownerId | Should -BeExactly 'abababab-abab-abab-abab-abababababab'
            $null -eq $Row.appId | Should -BeTrue
            $null -eq $Row.applicationDisplayName | Should -BeTrue
            $null -eq $Row.ownerDisplayName | Should -BeTrue
            $null -eq $Row.ownerUserPrincipalName | Should -BeTrue
        }

        It 'reads objects the transport returns as objects, not hashtables, the same way' {
            $script:Replies[$script:AppOwnerListUri] = [PSCustomObject]@{ value = @(
                    [PSCustomObject]@{ id = $script:ClientAppObjectId; appId = $script:ClientAppId; displayName = 'Client App'; owners = @(
                            [PSCustomObject]@{ '@odata.type' = '#microsoft.graph.user'; id = $script:UserTwo; displayName = 'Person Two'; userPrincipalName = 'person2@example.com' }
                        )
                    }
                )
            }
            $Result = Invoke-Spa
            @($Result.ApplicationOwners).Count | Should -Be 1
            $Result.ApplicationOwners[0].ownerType | Should -BeExactly 'User'
            @($Result.Unread).Count | Should -Be 0
        }

        It 'counts an object listed twice once' {
            $Listed = $script:Replies[$script:AppOwnerListUri].value
            $script:Replies[$script:AppOwnerListUri] = New-SpaList @($Listed[0], $Listed[1], $Listed[0])
            $Listed = $script:Replies[$script:PermissionListUri].value
            $script:Replies[$script:PermissionListUri] = New-SpaList @($Listed[0], $Listed[1], $Listed[0])
            $Listed = $script:Replies[$script:SpOwnerListUri].value
            $script:Replies[$script:SpOwnerListUri] = New-SpaList @($Listed[0], $Listed[1], $Listed[0])
            $Result = Invoke-Spa
            @($Result.ApplicationOwners).Count | Should -Be 2
            @($Result.ApplicationPermissions).Count | Should -Be 3
            @($Result.ServicePrincipalOwners).Count | Should -Be 2
        }

        It 'sorts each part ordinally without regard to letter case: first display name, then the second, then the ids' {
            $script:Replies[$script:AppOwnerListUri] = New-SpaList @(
                @{ id = '0e0e0e0e-0e0e-0e0e-0e0e-0e0e0e0e0e0e'; appId = $null; displayName = 'beta'; owners = @(
                        (New-SpaOwner -Type '#microsoft.graph.user' -Id '0d0d0d0d-0d0d-0d0d-0d0d-0d0d0d0d0d0d' -Name 'zed')
                        (New-SpaOwner -Type '#microsoft.graph.user' -Id '0c0c0c0c-0c0c-0c0c-0c0c-0c0c0c0c0c0c' -Name 'Adam')
                    )
                }
                @{ id = '0b0b0b0b-0b0b-0b0b-0b0b-0b0b0b0b0b0b'; appId = $null; displayName = 'Alpha'; owners = @(
                        (New-SpaOwner -Type '#microsoft.graph.user' -Id '0a0a0a0a-0a0a-0a0a-0a0a-0a0a0a0a0a0a' -Name 'same')
                        (New-SpaOwner -Type '#microsoft.graph.user' -Id '09090909-0909-0909-0909-090909090909' -Name 'SAME')
                    )
                }
                @{ id = '08080808-0808-0808-0808-080808080808'; appId = $null; displayName = $null; owners = @(
                        (New-SpaOwner -Type '#microsoft.graph.user' -Id '07070707-0707-0707-0707-070707070707' -Name 'nameless app owner')
                    )
                }
                @{ id = '06060606-0606-0606-0606-060606060606'; appId = $null; displayName = 'alpha'; owners = @(
                        (New-SpaOwner -Type '#microsoft.graph.user' -Id '05050505-0505-0505-0505-050505050505' -Name 'b')
                    )
                }
            )
            $Rows = @((Invoke-Spa).ApplicationOwners)
            # A null name first; 'Alpha' and 'alpha' are one name to the sort, told apart by the owner's
            # name ('b' before 'same'); two owners named alike in another case are told apart by their ids;
            # 'beta' after them, and its 'Adam' before 'zed' whatever the case.
            ($Rows | ForEach-Object { '{0}/{1}/{2}' -f $_.applicationDisplayName, $_.ownerDisplayName, $_.ownerId }) | Should -Be @(
                '/nameless app owner/07070707-0707-0707-0707-070707070707'
                'alpha/b/05050505-0505-0505-0505-050505050505'
                'Alpha/SAME/09090909-0909-0909-0909-090909090909'
                'Alpha/same/0a0a0a0a-0a0a-0a0a-0a0a-0a0a0a0a0a0a'
                'beta/Adam/0c0c0c0c-0c0c-0c0c-0c0c-0c0c0c0c0c0c'
                'beta/zed/0d0d0d0d-0d0d-0d0d-0d0d-0d0d0d0d0d0d'
            )
        }

        It 'returns four empty parts and nothing unread for an empty tenant' {
            $script:Replies = @{
                $script:PermissionListUri = New-SpaList
                $script:SpOwnerListUri    = New-SpaList
                $script:AppOwnerListUri   = New-SpaList
                $script:GrantListUri      = New-SpaList
            }
            $Result = Invoke-Spa
            foreach ($Part in @('ApplicationPermissions', 'DelegatedPermissionGrants', 'ApplicationOwners', 'ServicePrincipalOwners')) {
                $null -eq $Result.$Part | Should -BeFalse -Because "$Part was read, so it is an empty array and not null"
                , $Result.$Part | Should -BeOfType ([object[]])
                $Result.$Part.Count | Should -Be 0
            }
            @($Result.Unread).Count | Should -Be 0
            @($Result.Causes).Count | Should -Be 0
            # No grant names a user, so nothing is looked up.
            Should -Invoke -ModuleName $script:moduleName Resolve-OERPrincipalName -Times 0
        }

        It 'sends exactly the four list requests and one lookup, and nothing but GET requests' {
            $null = Invoke-Spa
            Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 4 -Exactly
            foreach ($ListUri in @($script:PermissionListUri, $script:SpOwnerListUri, $script:AppOwnerListUri, $script:GrantListUri)) {
                $script:ExpectedUri = $ListUri
                Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 1 -Exactly -ParameterFilter { $Uri -ceq $script:ExpectedUri -and $All }
            }
            Should -Invoke -ModuleName $script:moduleName Resolve-OERPrincipalName -Times 1 -Exactly
            # No POST, PATCH or DELETE from this function: the getByIds POST is Resolve-OERPrincipalName's.
            Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 0 -ParameterFilter { $PesterBoundParameters.ContainsKey('Method') -and $Method -ne 'GET' }
        }

        It 'states in its help the one dependency between the parts and the grant row''s two user names' {
            $Help = InModuleScope $script:moduleName { Get-Help Get-OERServicePrincipalAccess -Full }
            $Description = ((@($Help.Description) | ForEach-Object { $_.Text }) -join ' ') -replace '\s+', ' '
            $Description | Should -Match ([regex]::Escape('One part failing never stops another, except that the grants are not read when read 1 was not;'))
            $Description | Should -Match ([regex]::Escape('principalDisplayName and principalUserPrincipalName (for Principal the user''s displayName and userPrincipalName as the lookup returned them'))
            $Description | Should -Match ([regex]::Escape('without an appRoles collection (the roles it declares are then not known)'))
        }

        It 'never names a -Method on a Graph request in its source, so the requiredscope gate reads every literal as a read' {
            $Function = InModuleScope $script:moduleName { Get-Command Get-OERServicePrincipalAccess -CommandType Function }
            $Calls = @($Function.ScriptBlock.Ast.FindAll({
                        param($Node)
                        $Node -is [System.Management.Automation.Language.CommandAst] -and $Node.GetCommandName() -eq 'Invoke-OERGraphRequest'
                    }, $true))
            $Calls.Count | Should -BeGreaterThan 0 -Because 'the reader sends its reads through the Graph transport'
            foreach ($Call in $Calls) {
                @($Call.CommandElements | Where-Object { $_ -is [System.Management.Automation.Language.CommandParameterAst] -and $_.ParameterName -eq 'Method' }).Count | Should -Be 0
            }
        }
    }

    Context 'an object with 20 or more expanded entries is read in full' {
        It 'reads the app role assignments of a client with 20 expanded ones once more and uses that read' {
            $Client = $script:Replies[$script:PermissionListUri].value[0]
            $Client.appRoleAssignments = New-SpaAssignments -Count 20 -Client $script:ClientId
            # The full read holds 21, so its rows are told from the expanded ones.
            $script:Replies[(Get-PermissionReReadUri -Id $script:ClientId)] = New-SpaList (New-SpaAssignments -Count 21 -Client $script:ClientId)
            $Result = Invoke-Spa
            @($Result.ApplicationPermissions).Count | Should -Be 21
            @($Result.ApplicationPermissions | Where-Object { $_.appRoleId -eq '00000021-0000-0000-0000-000000000000' }).Count | Should -Be 1
            $script:ExpectedUri = Get-PermissionReReadUri -Id $script:ClientId
            Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 1 -Exactly -ParameterFilter { $Uri -ceq $script:ExpectedUri -and $All }
            # The four lists and the one full read.
            Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 5 -Exactly
            @($Result.Unread).Count | Should -Be 0
        }

        It 'does not read a client with 19 expanded app role assignments again' {
            $Client = $script:Replies[$script:PermissionListUri].value[0]
            $Client.appRoleAssignments = New-SpaAssignments -Count 19 -Client $script:ClientId
            $Result = Invoke-Spa
            @($Result.ApplicationPermissions).Count | Should -Be 19
            Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 0 -ParameterFilter { $Uri -like '*/appRoleAssignments?*' }
            Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 4 -Exactly
        }

        It 'reads the owners of a service principal with 20 expanded ones once more and uses that read' {
            $script:Replies[$script:SpOwnerListUri].value[0].owners = New-SpaOwners -Count 20
            $script:Replies[(Get-SpOwnerReReadUri -Id $script:ClientId)] = New-SpaList (New-SpaOwners -Count 22)
            $Result = Invoke-Spa
            @($Result.ServicePrincipalOwners | Where-Object { $_.servicePrincipalId -eq $script:ClientId }).Count | Should -Be 22
            $script:ExpectedUri = Get-SpOwnerReReadUri -Id $script:ClientId
            Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 1 -Exactly -ParameterFilter { $Uri -ceq $script:ExpectedUri -and $All }
            Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 5 -Exactly
        }

        It 'reads the owners of an app registration with 20 expanded ones once more and uses that read' {
            $script:Replies[$script:AppOwnerListUri].value[1].owners = New-SpaOwners -Count 20
            $script:Replies[(Get-AppOwnerReReadUri -Id $script:OtherAppObjectId)] = New-SpaList (New-SpaOwners -Count 23)
            $Result = Invoke-Spa
            @($Result.ApplicationOwners | Where-Object { $_.applicationId -eq $script:OtherAppObjectId }).Count | Should -Be 23
            $script:ExpectedUri = Get-AppOwnerReReadUri -Id $script:OtherAppObjectId
            Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 1 -Exactly -ParameterFilter { $Uri -ceq $script:ExpectedUri -and $All }
            Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 5 -Exactly
        }

        It 'does not read a service principal or an app registration with 19 expanded owners again' {
            $script:Replies[$script:SpOwnerListUri].value[0].owners = New-SpaOwners -Count 19
            $script:Replies[$script:AppOwnerListUri].value[1].owners = New-SpaOwners -Count 19
            $Result = Invoke-Spa
            @($Result.ServicePrincipalOwners | Where-Object { $_.servicePrincipalId -eq $script:ClientId }).Count | Should -Be 19
            @($Result.ApplicationOwners | Where-Object { $_.applicationId -eq $script:OtherAppObjectId }).Count | Should -Be 19
            Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 0 -ParameterFilter { $Uri -like '*/owners?*' }
            Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 4 -Exactly
        }

        # The id in a full read's path is Graph's, so it is URI-escaped as a path segment. A GUID is sent
        # unchanged, which is why the tests above match their unescaped forms; an id holding a space, a '/'
        # and a '#' shows the escape. A path sent unescaped has no mocked answer, so it reads as a failed part.
        It 'escapes the id in the path of a full read (<Name>)' -ForEach @(
            @{ Name = 'the app role assignments of a client'; Part = 'ApplicationPermissions'
                Escaped = 'v1.0/servicePrincipals/odd%20id%2F%231/appRoleAssignments?$top=999' }
            @{ Name = 'the owners of an app registration'; Part = 'ApplicationOwners'
                Escaped = 'v1.0/applications/odd%20id%2F%231/owners?$select=id,displayName,userPrincipalName&$top=999' }
        ) {
            if ($Part -eq 'ApplicationPermissions') {
                $Odd = @{ id = 'Odd Id/#1'; appId = '13131313-1313-1313-1313-131313131313'; displayName = 'Odd Client'; appRoles = @()
                    appRoleAssignments = New-SpaAssignments -Count 20 -Client 'odd id/#1' }
                $script:Replies[$script:PermissionListUri].value += $Odd
                $script:Replies[$Escaped] = New-SpaList (New-SpaAssignments -Count 21 -Client 'odd id/#1')
            } else {
                $Odd = @{ id = 'Odd Id/#1'; appId = '13131313-1313-1313-1313-131313131313'; displayName = 'Odd App'; owners = New-SpaOwners -Count 20 }
                $script:Replies[$script:AppOwnerListUri].value += $Odd
                $script:Replies[$Escaped] = New-SpaList (New-SpaOwners -Count 21)
            }
            $Result = Invoke-Spa
            @($Result.Unread).Count | Should -Be 0
            $script:ExpectedUri = $Escaped
            Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 1 -Exactly -ParameterFilter { $Uri -ceq $script:ExpectedUri -and $All }
            if ($Part -eq 'ApplicationPermissions') {
                @($Result.ApplicationPermissions | Where-Object { $_.servicePrincipalId -ceq 'odd id/#1' }).Count | Should -Be 21
            } else {
                @($Result.ApplicationOwners | Where-Object { $_.applicationId -ceq 'odd id/#1' }).Count | Should -Be 21
            }
        }

        It 'leaves the part unread when the full read of one object fails, naming that object' {
            $script:Replies[$script:SpOwnerListUri].value[0].owners = New-SpaOwners -Count 20
            $script:Replies[(Get-SpOwnerReReadUri -Id $script:ClientId)] = New-SpaGraphError -Message 'Too many requests (429).'
            $Result = Invoke-Spa
            $null -eq $Result.ServicePrincipalOwners | Should -BeTrue
            @($Result.Unread) | Should -Be @('servicePrincipalAccess/servicePrincipalOwners')
            @($Result.Causes).Count | Should -Be 1
            $Result.Causes[0].Cause | Should -BeExactly "Could not read the owners of the service principal '$($script:ClientId)': Too many requests (429)."
            $Result.Causes[0].Target | Should -BeExactly $script:ClientId
            # The other parts are read.
            @($Result.ApplicationPermissions).Count | Should -Be 3
            @($Result.ApplicationOwners).Count | Should -Be 2
            @($Result.DelegatedPermissionGrants).Count | Should -Be 3
        }
    }

    Context 'a read that fails leaves its part unread and no other' {
        It 'leaves the application permissions AND the grants unread when the service principal list fails, and does not read the grants' {
            $script:Replies[$script:PermissionListUri] = New-SpaGraphError
            $Result = Invoke-Spa
            $null -eq $Result.ApplicationPermissions | Should -BeTrue
            $null -eq $Result.DelegatedPermissionGrants | Should -BeTrue
            @($Result.Unread) | Should -Be @('servicePrincipalAccess/applicationPermissions', 'servicePrincipalAccess/delegatedPermissionGrants')
            @($Result.Causes).Count | Should -Be 1
            $Result.Causes[0].Cause | Should -BeExactly 'Could not read the service principal list with its app role assignments: Insufficient privileges to complete the operation. (403)'
            $Result.Causes[0].Target | Should -BeExactly $script:PermissionListUri
            # The grants are named through that list, so they are not read at all, and nobody is looked up.
            $script:ExpectedUri = $script:GrantListUri
            Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 0 -ParameterFilter { $Uri -ceq $script:ExpectedUri }
            Should -Invoke -ModuleName $script:moduleName Resolve-OERPrincipalName -Times 0
            # The two owner parts are read.
            @($Result.ServicePrincipalOwners).Count | Should -Be 2
            @($Result.ApplicationOwners).Count | Should -Be 2
        }

        It 'leaves only the service principal owners unread when their list fails' {
            $script:Replies[$script:SpOwnerListUri] = New-SpaGraphError
            $Result = Invoke-Spa
            $null -eq $Result.ServicePrincipalOwners | Should -BeTrue
            @($Result.Unread) | Should -Be @('servicePrincipalAccess/servicePrincipalOwners')
            $Result.Causes[0].Cause | Should -BeExactly 'Could not read the service principal list with its owners: Insufficient privileges to complete the operation. (403)'
            $Result.Causes[0].Target | Should -BeExactly $script:SpOwnerListUri
            @($Result.ApplicationPermissions).Count | Should -Be 3
            @($Result.DelegatedPermissionGrants).Count | Should -Be 3
            @($Result.ApplicationOwners).Count | Should -Be 2
        }

        It 'leaves only the app registration owners unread when their list fails' {
            $script:Replies[$script:AppOwnerListUri] = New-SpaGraphError
            $Result = Invoke-Spa
            $null -eq $Result.ApplicationOwners | Should -BeTrue
            @($Result.Unread) | Should -Be @('servicePrincipalAccess/applicationOwners')
            $Result.Causes[0].Cause | Should -BeExactly 'Could not read the app registration list with its owners: Insufficient privileges to complete the operation. (403)'
            $Result.Causes[0].Target | Should -BeExactly $script:AppOwnerListUri
            @($Result.ApplicationPermissions).Count | Should -Be 3
            @($Result.DelegatedPermissionGrants).Count | Should -Be 3
            @($Result.ServicePrincipalOwners).Count | Should -Be 2
        }

        It 'leaves only the grants unread when their list fails' {
            $script:Replies[$script:GrantListUri] = New-SpaGraphError
            $Result = Invoke-Spa
            $null -eq $Result.DelegatedPermissionGrants | Should -BeTrue
            @($Result.Unread) | Should -Be @('servicePrincipalAccess/delegatedPermissionGrants')
            $Result.Causes[0].Cause | Should -BeExactly 'Could not read the delegated permission grants: Insufficient privileges to complete the operation. (403)'
            $Result.Causes[0].Target | Should -BeExactly $script:GrantListUri
            @($Result.ApplicationPermissions).Count | Should -Be 3
            @($Result.ApplicationOwners).Count | Should -Be 2
            @($Result.ServicePrincipalOwners).Count | Should -Be 2
        }

        It 'names every part in the part order when every read fails, and the causes in the order found' {
            foreach ($ListUri in @($script:PermissionListUri, $script:SpOwnerListUri, $script:AppOwnerListUri)) { $script:Replies[$ListUri] = New-SpaGraphError }
            $Result = Invoke-Spa
            @($Result.Unread) | Should -Be @(
                'servicePrincipalAccess/applicationPermissions'
                'servicePrincipalAccess/delegatedPermissionGrants'
                'servicePrincipalAccess/applicationOwners'
                'servicePrincipalAccess/servicePrincipalOwners'
            )
            @($Result.Causes | ForEach-Object { $_.Target }) | Should -Be @($script:PermissionListUri, $script:SpOwnerListUri, $script:AppOwnerListUri)
        }

        It 'never throws, writes no error record and no warning, and scrubs the failing record first' {
            Mock -ModuleName $script:moduleName Remove-OERErrorRecord {}
            $script:Replies[$script:AppOwnerListUri] = New-SpaGraphError
            # Under Stop, an error record or a warning of the reader's own would end the call here.
            $Run = InModuleScope $script:moduleName {
                $SpaErr = $null
                $SpaWarn = $null
                $Read = Get-OERServicePrincipalAccess -ErrorAction Stop -WarningAction Stop -ErrorVariable SpaErr -WarningVariable SpaWarn
                [PSCustomObject]@{
                    Result   = $Read
                    Own      = @(@($SpaErr) | Where-Object { [string]$_.FullyQualifiedErrorId -like '*,Get-OERServicePrincipalAccess' }).Count
                    Warnings = @($SpaWarn).Count
                }
            }
            @($Run.Result.Unread) | Should -Be @('servicePrincipalAccess/applicationOwners')
            $Run.Own | Should -Be 0
            $Run.Warnings | Should -Be 0
            Should -Invoke -ModuleName $script:moduleName Remove-OERErrorRecord -Times 1 -Exactly -ParameterFilter {
                $Record.Exception.Message -eq 'Insufficient privileges to complete the operation. (403)'
            }
        }
    }

    Context 'an answer that says nothing is never read as none' {
        It 'leaves <Part> unread when an object carries no <Key> key at all' -ForEach @(
            @{ Part = 'applicationPermissions'; Key = 'appRoleAssignments'; List = 'Permission'; Index = 1; Kind = 'the app role assignments of the service principal'; Id = '22222222-2222-2222-2222-222222222222'; AlsoUnread = @('delegatedPermissionGrants') }
            @{ Part = 'servicePrincipalOwners'; Key = 'owners'; List = 'SpOwner'; Index = 1; Kind = 'the owners of the service principal'; Id = '22222222-2222-2222-2222-222222222222'; AlsoUnread = @() }
            @{ Part = 'applicationOwners'; Key = 'owners'; List = 'AppOwner'; Index = 0; Kind = 'the owners of the app registration'; Id = '55555555-5555-5555-5555-555555555555'; AlsoUnread = @() }
        ) {
            $ListUri = switch ($List) { 'Permission' { $script:PermissionListUri } 'SpOwner' { $script:SpOwnerListUri } default { $script:AppOwnerListUri } }
            # The expansion did not happen for one object: the key is absent, not an empty list.
            $script:Replies[$ListUri].value[$Index].Remove($Key)
            $Result = Invoke-Spa
            $Expected = @(@($Part) + @($AlsoUnread) | ForEach-Object { "servicePrincipalAccess/$_" })
            foreach ($Unread in $Expected) { @($Result.Unread) | Should -Contain $Unread }
            @($Result.Unread).Count | Should -Be $Expected.Count
            $Property = $Part.Substring(0, 1).ToUpperInvariant() + $Part.Substring(1)
            $null -eq $Result.$Property | Should -BeTrue
            $Result.Causes[0].Cause | Should -BeExactly "Could not read $Kind '$Id': Microsoft Graph returned it without its expanded $Key collection, so the expansion did not happen."
            $Result.Causes[0].Target | Should -BeExactly $Id
        }

        It 'leaves the application permissions AND the grants unread when a service principal is listed without its app roles (<Case>)' -ForEach @(
            @{ Case = 'no appRoles key at all'; Mode = 'missing' }
            @{ Case = 'the key with no collection (null)'; Mode = 'null' }
        ) {
            # The resource of the client's roles: without its appRoles the roles it declares are not known,
            # so every appRoleValue on it would be written null as if it declared none. An empty collection
            # (the client's own appRoles = @()) is an answer and is read as declaring none.
            if ($Mode -eq 'missing') { $script:Replies[$script:PermissionListUri].value[1].Remove('appRoles') }
            else { $script:Replies[$script:PermissionListUri].value[1].appRoles = $null }
            $Result = Invoke-Spa
            $null -eq $Result.ApplicationPermissions | Should -BeTrue
            $null -eq $Result.DelegatedPermissionGrants | Should -BeTrue
            @($Result.Unread) | Should -Be @('servicePrincipalAccess/applicationPermissions', 'servicePrincipalAccess/delegatedPermissionGrants')
            @($Result.Causes).Count | Should -Be 1
            $Result.Causes[0].Cause | Should -BeExactly "Could not read the app roles of the service principal '$($script:ResourceId)': Microsoft Graph returned it without its appRoles collection, so the roles it declares are not known."
            $Result.Causes[0].Target | Should -BeExactly $script:ResourceId
            # The grants are named through that list, so they are not read at all, and nobody is looked up.
            $script:ExpectedUri = $script:GrantListUri
            Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 0 -ParameterFilter { $Uri -ceq $script:ExpectedUri }
            Should -Invoke -ModuleName $script:moduleName Resolve-OERPrincipalName -Times 0
            # Reach proof: the list was read, and the two owner parts are read.
            $script:ExpectedUri = $script:PermissionListUri
            Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 1 -Exactly -ParameterFilter { $Uri -ceq $script:ExpectedUri }
            @($Result.ServicePrincipalOwners).Count | Should -Be 2
            @($Result.ApplicationOwners).Count | Should -Be 2
        }

        It 'leaves the application permissions unread the same way when the transport returns an object, not a hashtable, without appRoles' {
            $script:Replies[$script:PermissionListUri] = [PSCustomObject]@{ value = @(
                    [PSCustomObject]@{ id = $script:ClientId; appId = $script:ClientAppId; displayName = 'Client App'; appRoleAssignments = @() }
                )
            }
            $Result = Invoke-Spa
            $null -eq $Result.ApplicationPermissions | Should -BeTrue
            @($Result.Unread) | Should -Be @('servicePrincipalAccess/applicationPermissions', 'servicePrincipalAccess/delegatedPermissionGrants')
            $Result.Causes[0].Target | Should -BeExactly $script:ClientId
        }

        It 'leaves a part unread when an object carries the key with no collection (null)' {
            $script:Replies[$script:AppOwnerListUri].value[0].owners = $null
            $Result = Invoke-Spa
            $null -eq $Result.ApplicationOwners | Should -BeTrue
            @($Result.Unread) | Should -Be @('servicePrincipalAccess/applicationOwners')
        }

        It 'leaves a part unread the same way when the transport returns an object, not a hashtable, without the key' {
            $script:Replies[$script:AppOwnerListUri] = [PSCustomObject]@{ value = @([PSCustomObject]@{ id = $script:ClientAppObjectId; appId = $script:ClientAppId; displayName = 'Client App' }) }
            $Result = Invoke-Spa
            $null -eq $Result.ApplicationOwners | Should -BeTrue
            @($Result.Unread) | Should -Be @('servicePrincipalAccess/applicationOwners')
        }

        It 'leaves a part unread when its list answer carries no value collection (<Name>)' -ForEach @(
            @{ Name = 'no answer'; Reply = 'none' }
            @{ Name = 'an answer without value'; Reply = 'novalue' }
            @{ Name = 'a null value'; Reply = 'nullvalue' }
        ) {
            $script:Replies[$script:SpOwnerListUri] = switch ($Reply) { 'none' { $null } 'novalue' { @{ other = 1 } } default { @{ value = $null } } }
            $Result = Invoke-Spa
            $null -eq $Result.ServicePrincipalOwners | Should -BeTrue
            @($Result.Unread) | Should -Be @('servicePrincipalAccess/servicePrincipalOwners')
            $Result.Causes[0].Cause | Should -BeExactly 'Could not read the service principal list with its owners: Microsoft Graph returned no value collection for the list.'
        }

        It 'leaves a part unread when an object is listed without an id' {
            $script:Replies[$script:PermissionListUri].value[1].Remove('id')
            $Result = Invoke-Spa
            @($Result.Unread) | Should -Be @('servicePrincipalAccess/applicationPermissions', 'servicePrincipalAccess/delegatedPermissionGrants')
            $Result.Causes[0].Cause | Should -BeExactly 'Could not read the service principal list with its app role assignments: Microsoft Graph listed a service principal without an id.'
            $Result.Causes[0].Target | Should -BeExactly $script:PermissionListUri
        }

        It 'leaves the grants unread when the lookup answers Read false for a user, naming each such user' {
            $script:Lookup[$script:UserGone] = [PSCustomObject]@{ Id = $script:UserGone; Read = $false; Found = $false; Name = $null; ObjectType = $null; DisplayName = $null; UserPrincipalName = $null; Cause = 'Too many requests (429).' }
            $Result = Invoke-Spa
            $null -eq $Result.DelegatedPermissionGrants | Should -BeTrue
            @($Result.Unread) | Should -Be @('servicePrincipalAccess/delegatedPermissionGrants')
            @($Result.Causes).Count | Should -Be 1
            $Result.Causes[0].Cause | Should -BeExactly "Could not look up the user '$($script:UserGone)' named in a delegated permission grant: Too many requests (429)."
            $Result.Causes[0].Target | Should -BeExactly $script:UserGone
            # Reach proof: the lookup ran, and the other parts are read.
            Should -Invoke -ModuleName $script:moduleName Resolve-OERPrincipalName -Times 1 -Exactly
            @($Result.ApplicationPermissions).Count | Should -Be 3
        }

        It 'leaves the grants unread when the lookup gives no answer for a user' {
            Mock -ModuleName $script:moduleName Resolve-OERPrincipalName {
                [PSCustomObject]@{ Id = '33333333-3333-3333-3333-333333333333'; Read = $true; Found = $true; Name = 'person1@example.com'; ObjectType = 'user'; DisplayName = 'Person One'; UserPrincipalName = 'person1@example.com'; Cause = $null }
            }
            $Result = Invoke-Spa
            $null -eq $Result.DelegatedPermissionGrants | Should -BeTrue
            @($Result.Unread) | Should -Be @('servicePrincipalAccess/delegatedPermissionGrants')
            $Result.Causes[0].Cause | Should -BeExactly "Could not look up the user '$($script:UserGone)' named in a delegated permission grant: the lookup gave no answer for it"
        }
    }
}
