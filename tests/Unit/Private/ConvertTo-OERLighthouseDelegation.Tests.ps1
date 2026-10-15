BeforeAll {
    $script:moduleName = 'Omnicit.EntraRBAC'
    Get-Module $script:moduleName | Remove-Module -Force -ErrorAction SilentlyContinue
    Import-Module $script:moduleName -Force -ErrorAction Stop
    . "$PSScriptRoot/../TestHelpers/OERTransportTripwire.ps1"
    Install-OERTransportTripwire

    # A subscription delegation shaped after Microsoft Learn's Registration Assignments - List example
    # (the definition expanded), with placeholder ids that are not version 4 shaped.
    $script:SubA = '11111111-1111-1111-1111-111111111111'
    $script:DefinitionId = "/subscriptions/$($script:SubA)/providers/Microsoft.ManagedServices/registrationDefinitions/55555555-5555-5555-5555-555555555555"
    $script:AssignmentId = "/subscriptions/$($script:SubA)/providers/Microsoft.ManagedServices/registrationAssignments/66666666-6666-6666-6666-666666666666"
    $script:AssignmentJson = @"
{
  "id": "$($script:AssignmentId)",
  "type": "Microsoft.ManagedServices/registrationAssignments",
  "name": "66666666-6666-6666-6666-666666666666",
  "properties": {
    "registrationDefinitionId": "$($script:DefinitionId)",
    "provisioningState": "Succeeded"
  }
}
"@
    $script:DefinitionJson = @"
{
  "id": "$($script:DefinitionId)",
  "type": "Microsoft.ManagedServices/registrationDefinitions",
  "name": "55555555-5555-5555-5555-555555555555",
  "properties": {
    "description": "Managed services offer",
    "authorizations": [
      {
        "principalId": "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa",
        "principalIdDisplayName": "Support User",
        "roleDefinitionId": "dddddddd-dddd-dddd-dddd-dddddddddddd"
      },
      {
        "principalId": "bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb",
        "principalIdDisplayName": "Access Administrators",
        "roleDefinitionId": "eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee",
        "delegatedRoleDefinitionIds": [ "dddddddd-dddd-dddd-dddd-dddddddddddd", "ffffffff-ffff-ffff-ffff-ffffffffffff" ]
      }
    ],
    "eligibleAuthorizations": [
      {
        "principalId": "cccccccc-cccc-cccc-cccc-cccccccccccc",
        "principalIdDisplayName": "On-call Engineers",
        "roleDefinitionId": "dddddddd-dddd-dddd-dddd-dddddddddddd",
        "justInTimeAccessPolicy": { "multiFactorAuthProvider": "Azure", "maximumActivationDuration": "PT8H" }
      }
    ],
    "registrationDefinitionName": "Contoso Managed Services",
    "provisioningState": "Succeeded",
    "managedByTenantId": "33333333-3333-3333-3333-333333333333",
    "managedByTenantName": "Contoso Corp."
  }
}
"@
}

AfterAll {
    try { Assert-OERTransportTripwire } finally { Uninstall-OERTransportTripwire }
}

Describe 'ConvertTo-OERLighthouseDelegation' {
    It 'gives every field of a subscription delegation, in the documented property order' {
        $Row = InModuleScope $script:moduleName -Parameters @{ A = $script:AssignmentJson; D = $script:DefinitionJson; Sub = $script:SubA } {
            ConvertTo-OERLighthouseDelegation -Assignment ($A | ConvertFrom-Json) -Definition ($D | ConvertFrom-Json) -ReadAt "/subscriptions/$Sub"
        }
        ($Row.PSObject.Properties.Name -join ',') | Should -BeExactly 'scope,subscriptionId,resourceGroup,managedByTenantId,managedByTenantName,offerName,registrationAssignmentId,registrationDefinitionId,authorizations,eligibleAuthorizations'
        $Row.scope | Should -BeExactly "/subscriptions/$($script:SubA)"
        $Row.subscriptionId | Should -BeExactly $script:SubA
        $Row.resourceGroup | Should -BeNullOrEmpty
        $Row.managedByTenantId | Should -BeExactly '33333333-3333-3333-3333-333333333333'
        $Row.managedByTenantName | Should -BeExactly 'Contoso Corp.'
        $Row.offerName | Should -BeExactly 'Contoso Managed Services'
        $Row.registrationAssignmentId | Should -BeExactly $script:AssignmentId
        $Row.registrationDefinitionId | Should -BeExactly $script:DefinitionId

        @($Row.authorizations).Count | Should -Be 2
        ($Row.authorizations[0].PSObject.Properties.Name -join ',') | Should -BeExactly 'principalId,principalDisplayName,roleDefinitionId,roleName,delegatedRoleDefinitionIds'
        $Row.authorizations[0].principalId | Should -BeExactly 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'
        $Row.authorizations[0].principalDisplayName | Should -BeExactly 'Support User'
        $Row.authorizations[0].roleDefinitionId | Should -BeExactly 'dddddddd-dddd-dddd-dddd-dddddddddddd'
        $Row.authorizations[0].roleName | Should -BeNullOrEmpty
        @($Row.authorizations[0].delegatedRoleDefinitionIds).Count | Should -Be 0
        $Row.authorizations[1].principalDisplayName | Should -BeExactly 'Access Administrators'
        $Row.authorizations[1].delegatedRoleDefinitionIds | Should -Be @('dddddddd-dddd-dddd-dddd-dddddddddddd', 'ffffffff-ffff-ffff-ffff-ffffffffffff')

        @($Row.eligibleAuthorizations).Count | Should -Be 1
        ($Row.eligibleAuthorizations[0].PSObject.Properties.Name -join ',') | Should -BeExactly 'principalId,principalDisplayName,roleDefinitionId,roleName'
        $Row.eligibleAuthorizations[0].principalId | Should -BeExactly 'cccccccc-cccc-cccc-cccc-cccccccccccc'
        $Row.eligibleAuthorizations[0].principalDisplayName | Should -BeExactly 'On-call Engineers'
        $Row.eligibleAuthorizations[0].roleDefinitionId | Should -BeExactly 'dddddddd-dddd-dddd-dddd-dddddddddddd'
        $Row.eligibleAuthorizations[0].roleName | Should -BeNullOrEmpty
    }

    It 'gives the resource group and the resource group scope for an assignment id at a resource group' {
        $Row = InModuleScope $script:moduleName -Parameters @{ D = $script:DefinitionJson; Sub = $script:SubA } {
            $Assignment = [PSCustomObject]@{
                id         = "/subscriptions/$Sub/resourceGroups/rg-app/providers/Microsoft.ManagedServices/registrationAssignments/77777777-7777-7777-7777-777777777777"
                properties = [PSCustomObject]@{ registrationDefinitionId = '' }
            }
            ConvertTo-OERLighthouseDelegation -Assignment $Assignment -Definition ($D | ConvertFrom-Json) -ReadAt "/subscriptions/$Sub/resourceGroups/rg-app"
        }
        $Row.scope | Should -BeExactly "/subscriptions/$($script:SubA)/resourceGroups/rg-app"
        $Row.subscriptionId | Should -BeExactly $script:SubA
        $Row.resourceGroup | Should -BeExactly 'rg-app'
    }

    It 'reads a resource group written in lower case (resourcegroups) the same way' {
        $Row = InModuleScope $script:moduleName -Parameters @{ D = $script:DefinitionJson; Sub = $script:SubA } {
            $Assignment = [PSCustomObject]@{
                id         = "/subscriptions/$Sub/resourcegroups/rg-app/providers/microsoft.managedservices/registrationassignments/77777777-7777-7777-7777-777777777777"
                properties = [PSCustomObject]@{ registrationDefinitionId = '' }
            }
            ConvertTo-OERLighthouseDelegation -Assignment $Assignment -Definition ($D | ConvertFrom-Json) -ReadAt "/subscriptions/$Sub"
        }
        $Row.scope | Should -BeExactly "/subscriptions/$($script:SubA)/resourcegroups/rg-app"
        $Row.subscriptionId | Should -BeExactly $script:SubA
        $Row.resourceGroup | Should -BeExactly 'rg-app'
    }

    It 'falls back to the scope that was read when the assignment id does not name the marker' {
        $Row = InModuleScope $script:moduleName -Parameters @{ D = $script:DefinitionJson; Sub = $script:SubA } {
            $Assignment = [PSCustomObject]@{ id = 'odd-id'; properties = [PSCustomObject]@{ registrationDefinitionId = '' } }
            ConvertTo-OERLighthouseDelegation -Assignment $Assignment -Definition ($D | ConvertFrom-Json) -ReadAt "/subscriptions/$Sub/resourceGroups/rg-read/"
        }
        $Row.scope | Should -BeExactly "/subscriptions/$($script:SubA)/resourceGroups/rg-read"
        $Row.subscriptionId | Should -BeExactly $script:SubA
        $Row.resourceGroup | Should -BeExactly 'rg-read'
        $Row.registrationAssignmentId | Should -BeExactly 'odd-id'
    }

    It 'writes a blank name as null for every scalar field' {
        $Row = InModuleScope $script:moduleName -Parameters @{ Sub = $script:SubA } {
            $Assignment = [PSCustomObject]@{
                id         = "/subscriptions/$Sub/providers/Microsoft.ManagedServices/registrationAssignments/66666666-6666-6666-6666-666666666666"
                properties = [PSCustomObject]@{ registrationDefinitionId = '/subscriptions/x/providers/Microsoft.ManagedServices/registrationDefinitions/y' }
            }
            $Definition = [PSCustomObject]@{
                id         = '/ignored'
                properties = [PSCustomObject]@{
                    registrationDefinitionName = '  '
                    managedByTenantId          = ''
                    managedByTenantName        = $null
                    authorizations             = @([PSCustomObject]@{ principalId = ''; principalIdDisplayName = ' '; roleDefinitionId = '' })
                    eligibleAuthorizations     = @([PSCustomObject]@{ principalId = 'cccccccc-cccc-cccc-cccc-cccccccccccc'; principalIdDisplayName = ''; roleDefinitionId = 'dddddddd-dddd-dddd-dddd-dddddddddddd' })
                }
            }
            ConvertTo-OERLighthouseDelegation -Assignment $Assignment -Definition $Definition -ReadAt "/subscriptions/$Sub"
        }
        $Row.offerName | Should -BeNullOrEmpty
        $Row.managedByTenantId | Should -BeNullOrEmpty
        $Row.managedByTenantName | Should -BeNullOrEmpty
        # The three offer fields are null, not empty strings: ConvertTo-Json shows null for each.
        $Json = ConvertTo-Json -InputObject $Row -Depth 5 -Compress
        $Json | Should -Match '"managedByTenantId":null,"managedByTenantName":null,"offerName":null,'
        $Row.authorizations[0].principalDisplayName | Should -BeNullOrEmpty
        $Json | Should -Match '"principalDisplayName":null,"roleDefinitionId":null,"roleName":null,"delegatedRoleDefinitionIds":\[\]'
        $Row.eligibleAuthorizations[0].principalDisplayName | Should -BeNullOrEmpty
    }

    It 'gives empty arrays, not null, for a delegation with no authorization, and writes [] in JSON' {
        $Json = InModuleScope $script:moduleName -Parameters @{ A = $script:AssignmentJson; Sub = $script:SubA } {
            $Definition = [PSCustomObject]@{
                id         = '/subscriptions/x/providers/Microsoft.ManagedServices/registrationDefinitions/y'
                properties = [PSCustomObject]@{ registrationDefinitionName = 'Offer'; managedByTenantId = '33333333-3333-3333-3333-333333333333'; managedByTenantName = 'Contoso Corp.' }
            }
            $Row = ConvertTo-OERLighthouseDelegation -Assignment ($A | ConvertFrom-Json) -Definition $Definition -ReadAt "/subscriptions/$Sub"
            @{
                Authorizations         = ($Row.authorizations -is [System.Array])
                EligibleAuthorizations = ($Row.eligibleAuthorizations -is [System.Array])
                Json                   = (ConvertTo-Json -InputObject $Row -Depth 5 -Compress)
            }
        }
        $Json.Authorizations | Should -BeTrue
        $Json.EligibleAuthorizations | Should -BeTrue
        $Json.Json | Should -Match '"authorizations":\[\],"eligibleAuthorizations":\[\]\}$'
    }

    It 'keeps a one-element authorization list, and a one-element delegated role list, an array in JSON' {
        $Json = InModuleScope $script:moduleName -Parameters @{ A = $script:AssignmentJson; Sub = $script:SubA } {
            $Definition = [PSCustomObject]@{
                id         = '/subscriptions/x/providers/Microsoft.ManagedServices/registrationDefinitions/y'
                properties = [PSCustomObject]@{
                    authorizations         = @([PSCustomObject]@{
                            principalId                = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'
                            roleDefinitionId           = 'eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee'
                            delegatedRoleDefinitionIds = @('dddddddd-dddd-dddd-dddd-dddddddddddd', '', $null)
                        })
                    eligibleAuthorizations = @([PSCustomObject]@{ principalId = 'cccccccc-cccc-cccc-cccc-cccccccccccc'; roleDefinitionId = 'dddddddd-dddd-dddd-dddd-dddddddddddd' })
                }
            }
            ConvertTo-Json -InputObject (ConvertTo-OERLighthouseDelegation -Assignment ($A | ConvertFrom-Json) -Definition $Definition -ReadAt "/subscriptions/$Sub") -Depth 5 -Compress
        }
        $Json | Should -Match '"authorizations":\[\{"principalId":"aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa",'
        $Json | Should -Match '"delegatedRoleDefinitionIds":\["dddddddd-dddd-dddd-dddd-dddddddddddd"\]\}\],"eligibleAuthorizations":\[\{'
        $Json | Should -Match '"roleName":null\}\]\}$'
    }

    It 'skips a null authorization entry' {
        $Row = InModuleScope $script:moduleName -Parameters @{ A = $script:AssignmentJson; Sub = $script:SubA } {
            $Definition = [PSCustomObject]@{
                id         = '/subscriptions/x/providers/Microsoft.ManagedServices/registrationDefinitions/y'
                properties = [PSCustomObject]@{
                    authorizations         = @($null, [PSCustomObject]@{ principalId = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'; roleDefinitionId = 'dddddddd-dddd-dddd-dddd-dddddddddddd' })
                    eligibleAuthorizations = @($null)
                }
            }
            ConvertTo-OERLighthouseDelegation -Assignment ($A | ConvertFrom-Json) -Definition $Definition -ReadAt "/subscriptions/$Sub"
        }
        @($Row.authorizations).Count | Should -Be 1
        @($Row.eligibleAuthorizations).Count | Should -Be 0
    }

    It 'falls back to the definition id when the assignment names no definition' {
        $Row = InModuleScope $script:moduleName -Parameters @{ D = $script:DefinitionJson; Sub = $script:SubA } {
            $Assignment = [PSCustomObject]@{
                id         = "/subscriptions/$Sub/providers/Microsoft.ManagedServices/registrationAssignments/66666666-6666-6666-6666-666666666666"
                properties = [PSCustomObject]@{ registrationDefinitionId = ' ' }
            }
            ConvertTo-OERLighthouseDelegation -Assignment $Assignment -Definition ($D | ConvertFrom-Json) -ReadAt "/subscriptions/$Sub"
        }
        $Row.registrationDefinitionId | Should -BeExactly $script:DefinitionId
    }

    It 'is a pure converter: it sends no request and writes no error record' {
        Mock -ModuleName $script:moduleName Invoke-OERArmRequest { }
        $Errors = InModuleScope $script:moduleName -Parameters @{ A = $script:AssignmentJson; D = $script:DefinitionJson; Sub = $script:SubA } {
            $null = ConvertTo-OERLighthouseDelegation -Assignment ($A | ConvertFrom-Json) -Definition ($D | ConvertFrom-Json) -ReadAt "/subscriptions/$Sub" -ErrorVariable ConvertErrors -ErrorAction SilentlyContinue
            @($ConvertErrors).Count
        }
        $Errors | Should -Be 0
        Should -Invoke -ModuleName $script:moduleName Invoke-OERArmRequest -Times 0
    }
}
