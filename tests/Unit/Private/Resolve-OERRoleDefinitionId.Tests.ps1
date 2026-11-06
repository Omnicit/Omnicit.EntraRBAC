BeforeAll {
    Import-Module Omnicit.EntraRBAC -Force
    . "$PSScriptRoot/../TestHelpers/OERTransportTripwire.ps1"
    Install-OERTransportTripwire
}

AfterAll {
    try { Assert-OERTransportTripwire } finally { Uninstall-OERTransportTripwire }
}

Describe 'Resolve-OERRoleDefinitionId' {
    It 'passes a full ARM role definition id through unchanged' {
        InModuleScope Omnicit.EntraRBAC {
            Mock Invoke-OERArmRequest { throw 'should not be called' }
            $Full = '/subscriptions/s1/providers/Microsoft.Authorization/roleDefinitions/acdd72a7-3385-48ef-bd42-f606fba81ae7'
            Resolve-OERRoleDefinitionId -Role $Full -Scope '/subscriptions/s1' | Should -Be $Full
            Should -Invoke Invoke-OERArmRequest -Times 0 -Exactly
        }
    }

    It 'expands a bare GUID to the full id at the target scope without any ARM call' {
        InModuleScope Omnicit.EntraRBAC {
            Mock Invoke-OERArmRequest { throw 'should not be called' }
            Resolve-OERRoleDefinitionId -Role 'acdd72a7-3385-48ef-bd42-f606fba81ae7' -Scope '/subscriptions/s1' |
                Should -Be '/subscriptions/s1/providers/Microsoft.Authorization/roleDefinitions/acdd72a7-3385-48ef-bd42-f606fba81ae7'
        }
    }

    It 'resolves a role display name via the roleName filter with URL encoding' {
        InModuleScope Omnicit.EntraRBAC {
            Mock Invoke-OERArmRequest {
                [PSCustomObject]@{ value = @(
                    [PSCustomObject]@{ id = '/subscriptions/s1/providers/Microsoft.Authorization/roleDefinitions/00000000-0000-0000-0000-000000000056' }
                ) }
            }
            Resolve-OERRoleDefinitionId -Role 'User Access Administrator' -Scope '/subscriptions/s1' |
                Should -Be '/subscriptions/s1/providers/Microsoft.Authorization/roleDefinitions/00000000-0000-0000-0000-000000000056'
            Should -Invoke Invoke-OERArmRequest -Times 1 -Exactly -ParameterFilter {
                $Path -eq "/subscriptions/s1/providers/Microsoft.Authorization/roleDefinitions?api-version=2022-04-01&`$filter=roleName%20eq%20%27User%20Access%20Administrator%27"
            }
        }
    }

    It 'throws when no role matches the name' {
        InModuleScope Omnicit.EntraRBAC {
            Mock Invoke-OERArmRequest { [PSCustomObject]@{ value = @() } }
            { Resolve-OERRoleDefinitionId -Role 'No Such Role' -Scope '/subscriptions/s1' } |
                Should -Throw "*'No Such Role'*"
        }
    }

    It 'throws the no-match case as a plain string without -ThrowUnresolved (Sync-OERStructureRoleAssignment republishes it as is)' {
        InModuleScope Omnicit.EntraRBAC {
            Mock Invoke-OERArmRequest { [PSCustomObject]@{ value = @() } }
            $Caught = $null
            try { Resolve-OERRoleDefinitionId -Role 'No Such Role' -Scope '/subscriptions/s1' } catch { $Caught = $PSItem }
            $Caught.TargetObject | Should -BeOfType ([string])
            # A thrown string's id is its own text, and no internal id appears anywhere in it.
            $Caught.FullyQualifiedErrorId | Should -Be $Caught.Exception.Message
            $Caught.FullyQualifiedErrorId | Should -Not -Match 'RoleDefinitionUnresolved'
            $Caught.CategoryInfo.Category | Should -Be 'OperationStopped'
        }
    }

    It 'with -ThrowUnresolved throws the no-match case as RoleDefinitionUnresolved, ObjectNotFound, same message, target the role' {
        InModuleScope Omnicit.EntraRBAC {
            Mock Invoke-OERArmRequest { [PSCustomObject]@{ value = @() } }
            $Plain = $null
            try { Resolve-OERRoleDefinitionId -Role 'No Such Role' -Scope '/subscriptions/s1' } catch { $Plain = $PSItem }
            $Caught = $null
            try { Resolve-OERRoleDefinitionId -Role 'No Such Role' -Scope '/subscriptions/s1' -ThrowUnresolved } catch { $Caught = $PSItem }
            $Caught.FullyQualifiedErrorId | Should -Be 'RoleDefinitionUnresolved'
            $Caught.CategoryInfo.Category | Should -Be 'ObjectNotFound'
            $Caught.TargetObject | Should -Be 'No Such Role'
            $Caught.Exception.Message | Should -Be $Plain.Exception.Message
            Test-OERRoleLookupUnresolved -Record $Caught | Should -BeTrue
        }
    }

    It 'with -ThrowUnresolved still lets a failed read through as the transport''s own record, never as the no-match record' {
        InModuleScope Omnicit.EntraRBAC {
            Mock Invoke-OERArmRequest {
                throw [System.Management.Automation.ErrorRecord]::new([System.Exception]::new('Authorization failed (403).'),
                    'AuthorizationFailed', [System.Management.Automation.ErrorCategory]::PermissionDenied, 'x')
            }
            $Caught = $null
            try { Resolve-OERRoleDefinitionId -Role 'Reader' -Scope '/subscriptions/s1' -ThrowUnresolved } catch { $Caught = $PSItem }
            $Caught.FullyQualifiedErrorId | Should -Be 'AuthorizationFailed'
            Test-OERRoleLookupUnresolved -Record $Caught | Should -BeFalse
        }
    }

    It 'with -ThrowUnresolved still throws AmbiguousName for a name two definitions share, and returns a match unchanged' {
        InModuleScope Omnicit.EntraRBAC {
            Mock Invoke-OERArmRequest {
                [PSCustomObject]@{ value = @([PSCustomObject]@{ id = '/s/r1' }, [PSCustomObject]@{ id = '/s/r2' }) }
            }
            $Caught = $null
            try { Resolve-OERRoleDefinitionId -Role 'Dup' -Scope '/subscriptions/s1' -ThrowUnresolved } catch { $Caught = $PSItem }
            $Caught.FullyQualifiedErrorId | Should -Be 'AmbiguousName'
            Test-OERRoleLookupUnresolved -Record $Caught | Should -BeFalse
            Mock Invoke-OERArmRequest { [PSCustomObject]@{ value = @([PSCustomObject]@{ id = '/s/r1' }) } }
            Resolve-OERRoleDefinitionId -Role 'One' -Scope '/subscriptions/s1' -ThrowUnresolved | Should -Be '/s/r1'
        }
    }

    It 'names Get-OERRoleDefinition in the not-found message' {
        # A bare "was not found" leaves the operator with no way to discover the right spelling, and
        # all ten -Role consumers pass this message through verbatim, so the hint belongs here.
        InModuleScope Omnicit.EntraRBAC {
            Mock Invoke-OERArmRequest { [PSCustomObject]@{ value = @() } }
            $Caught = $null
            try {
                Resolve-OERRoleDefinitionId -Role 'Reeder' -Scope '/subscriptions/s1'
            } catch {
                $Caught = $PSItem
            }
            $Caught | Should -Not -BeNullOrEmpty
            $Caught.Exception.Message | Should -Match 'Get-OERRoleDefinition'
            $Caught.Exception.Message | Should -Match "-Scope '/subscriptions/s1'"
        }
    }

    It 'throws AmbiguousName when two role definitions share the name at the scope' {
        InModuleScope Omnicit.EntraRBAC {
            Mock Invoke-OERArmRequest {
                [PSCustomObject]@{ value = @(
                        [PSCustomObject]@{ id = '/subscriptions/s1/providers/Microsoft.Authorization/roleDefinitions/r1' }
                        [PSCustomObject]@{ id = '/providers/Microsoft.Management/managementGroups/mg1/providers/Microsoft.Authorization/roleDefinitions/r2' }
                    ) }
            }
            $Caught = $null
            try {
                Resolve-OERRoleDefinitionId -Role 'Custom Operator' -Scope '/subscriptions/s1'
            } catch {
                $Caught = $PSItem
            }
            $Caught | Should -Not -BeNullOrEmpty
            $Caught.FullyQualifiedErrorId | Should -Match '^AmbiguousName'
            $Caught.Exception.Message | Should -Match 'roleDefinitions/r1'
            $Caught.Exception.Message | Should -Match 'roleDefinitions/r2'
        }
    }

    It 'still reports not found when the value array holds only a null' {
        # @($null).Count is 1, so a naive @($Response.value)[0].id would return an empty string here
        # and every caller would then build a role assignment body with no roleDefinitionId.
        InModuleScope Omnicit.EntraRBAC {
            Mock Invoke-OERArmRequest { [PSCustomObject]@{ value = @($null) } }
            $Caught = $null
            try {
                Resolve-OERRoleDefinitionId -Role 'No Such Role' -Scope '/subscriptions/s1'
            } catch {
                $Caught = $PSItem
            }
            $Caught | Should -Not -BeNullOrEmpty
            $Caught.Exception.Message | Should -Match 'was not found at scope'
        }
    }

    It 'returns a single match unchanged and makes no ambiguity claim' {
        InModuleScope Omnicit.EntraRBAC {
            Mock Invoke-OERArmRequest {
                [PSCustomObject]@{ value = @(
                        [PSCustomObject]@{ id = '/subscriptions/s1/providers/Microsoft.Authorization/roleDefinitions/only' }
                    ) }
            }
            Resolve-OERRoleDefinitionId -Role 'Reader' -Scope '/subscriptions/s1' |
                Should -Be '/subscriptions/s1/providers/Microsoft.Authorization/roleDefinitions/only'
        }
    }
}

Describe 'Resolve-OERRoleDefinitionId: the example in the not-found message (BL-113)' {
    It 'shows the Get-OERRoleDefinition example so it parses and gives the scope back for a scope holding <Label>' -ForEach @(
        @{ Label = 'a straight apostrophe (U+0027)'; Scope = "/subscriptions/s1/resourceGroups/rg's"; Escaped = "/subscriptions/s1/resourceGroups/rg''s" }
        @{ Label = 'a right single quotation mark (U+2019)'; Scope = ('/subscriptions/s1/resourceGroups/rg' + [char]0x2019 + 's'); Escaped = ('/subscriptions/s1/resourceGroups/rg' + [char]0x2019 + [char]0x2019 + 's') }
    ) {
        InModuleScope Omnicit.EntraRBAC -Parameters @{ Scope = $Scope; Escaped = $Escaped } {
            Mock Invoke-OERArmRequest { [PSCustomObject]@{ value = @() } }
            $Caught = $null
            try {
                Resolve-OERRoleDefinitionId -Role 'Reeder' -Scope $Scope
            } catch {
                $Caught = $PSItem
            }
            $Caught | Should -Not -BeNullOrEmpty
            $Message = $Caught.Exception.Message
            $Start = $Message.IndexOf('. Run ', [System.StringComparison]::Ordinal)
            $End = $Message.IndexOf(' without -Role', [System.StringComparison]::Ordinal)
            $Start | Should -BeGreaterOrEqual 0
            $End | Should -BeGreaterThan $Start
            $Example = $Message.Substring($Start + 6, $End - $Start - 6)
            $Example | Should -BeExactly "Get-OERRoleDefinition -Scope '$Escaped'"
            $ParseErrors = $null
            $Ast = [System.Management.Automation.Language.Parser]::ParseInput($Example, [ref]$null, [ref]$ParseErrors)
            @($ParseErrors).Count | Should -Be 0
            $Command = $Ast.Find({ param($Node) $Node -is [System.Management.Automation.Language.CommandAst] }, $true)
            $Command.GetCommandName() | Should -BeExactly 'Get-OERRoleDefinition'
            $Argument = @($Command.CommandElements)[2]
            $Argument | Should -BeOfType ([System.Management.Automation.Language.StringConstantExpressionAst])
            $Argument.Value | Should -BeExactly $Scope
        }
    }
}

Describe 'Resolve-OERRoleDefinitionId asks the transport for a list (BL-167a)' {
    BeforeEach { InModuleScope Omnicit.EntraRBAC { $script:_OERAuthState = $null } }

    It 'passes -RequireValue on the name lookup, and not on the GUID or full id forms (no request there)' {
        InModuleScope Omnicit.EntraRBAC {
            Mock Invoke-OERArmRequest { [PSCustomObject]@{ value = @([PSCustomObject]@{ id = '/s/r1' }) } }
            Resolve-OERRoleDefinitionId -Role 'Reader' -Scope '/subscriptions/s1' | Should -Be '/s/r1'
            Should -Invoke Invoke-OERArmRequest -Times 1 -Exactly -ParameterFilter { $RequireValue }
        }
    }

    Context 'through the real transport' {
        BeforeEach {
            InModuleScope Omnicit.EntraRBAC {
                $script:_OERAuthState = @{
                    AuthMethod     = 'Interactive'
                    TenantId       = 'organizations'
                    ArmToken       = (ConvertTo-SecureString 'fake-arm-token' -AsPlainText -Force)
                    ArmResourceUrl = 'https://management.azure.com/'
                }
            }
        }

        It 'treats <Name> as an unread lookup (ArmPagingIncomplete), with and without -ThrowUnresolved, never as no match' -ForEach @(
            @{ Name = 'an empty 200 body'; Body = '' }
            @{ Name = 'a JSON null body'; Body = 'null' }
            @{ Name = 'a body with no value member'; Body = '{"other":1}' }
        ) {
            InModuleScope Omnicit.EntraRBAC -Parameters @{ Body = $Body } {
                $script:RvBody = $Body
                Mock Invoke-WebRequest { [PSCustomObject]@{ StatusCode = 200; Content = $script:RvBody } }
                foreach ($Switch in @($false, $true)) {
                    $Caught = $null
                    try {
                        if ($Switch) { $null = Resolve-OERRoleDefinitionId -Role 'Reader' -Scope '/subscriptions/s1' -ThrowUnresolved -ErrorAction Stop }
                        else { $null = Resolve-OERRoleDefinitionId -Role 'Reader' -Scope '/subscriptions/s1' -ErrorAction Stop }
                    } catch { $Caught = $PSItem }
                    $Caught | Should -Not -BeNullOrEmpty
                    $Caught.FullyQualifiedErrorId | Should -Be 'ArmPagingIncomplete'
                    Test-OERRoleLookupUnresolved -Record $Caught | Should -BeFalse
                }
            }
        }

        It 'still reads an empty value list as no match (RoleDefinitionUnresolved with -ThrowUnresolved)' {
            InModuleScope Omnicit.EntraRBAC {
                Mock Invoke-WebRequest { [PSCustomObject]@{ StatusCode = 200; Content = '{"value":[]}' } }
                $Caught = $null
                try { $null = Resolve-OERRoleDefinitionId -Role 'Reader' -Scope '/subscriptions/s1' -ThrowUnresolved -ErrorAction Stop } catch { $Caught = $PSItem }
                $Caught.FullyQualifiedErrorId | Should -Be 'RoleDefinitionUnresolved'
                Test-OERRoleLookupUnresolved -Record $Caught | Should -BeTrue
            }
        }
    }
}