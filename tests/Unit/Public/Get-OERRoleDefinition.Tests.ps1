BeforeAll {
    Import-Module Omnicit.EntraRBAC -Force
    . "$PSScriptRoot/../TestHelpers/OERTransportTripwire.ps1"
    Install-OERTransportTripwire
}

AfterAll {
    try { Assert-OERTransportTripwire } finally { Uninstall-OERTransportTripwire }
}

Describe 'Get-OERRoleDefinition' {
    BeforeEach {
        InModuleScope Omnicit.EntraRBAC { $script:_OERAuthState = $null }
        Mock -ModuleName Omnicit.EntraRBAC Initialize-OERAuth { }
    }

    It 'lists all role definitions tenant-wide when no scope or filter is given' {
        Mock -ModuleName Omnicit.EntraRBAC Invoke-OERArmRequest { [PSCustomObject]@{ value = @() } }
        $null = Get-OERRoleDefinition
        Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-OERArmRequest -Times 1 -Exactly -ParameterFilter {
            $Path -eq '/providers/Microsoft.Authorization/roleDefinitions?api-version=2022-04-01' -and $All
        }
    }

    It 'scopes the list to a subscription GUID' {
        Mock -ModuleName Omnicit.EntraRBAC Invoke-OERArmRequest { [PSCustomObject]@{ value = @() } }
        $null = Get-OERRoleDefinition -Subscription 'aaaa1111-0000-0000-0000-000000000000'
        Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-OERArmRequest -Times 1 -Exactly -ParameterFilter {
            $Path -eq '/subscriptions/aaaa1111-0000-0000-0000-000000000000/providers/Microsoft.Authorization/roleDefinitions?api-version=2022-04-01' -and $All
        }
    }

    It 'resolves a role by display name via the roleName filter' {
        Mock -ModuleName Omnicit.EntraRBAC Invoke-OERArmRequest {
            [PSCustomObject]@{ value = @(
                [PSCustomObject]@{ id = '/providers/Microsoft.Authorization/roleDefinitions/acdd72a7-3385-48ef-bd42-f606fba81ae7'; name = 'acdd72a7-3385-48ef-bd42-f606fba81ae7'; properties = [PSCustomObject]@{ roleName = 'Reader'; type = 'BuiltInRole' } }
            ) }
        }
        $Result = Get-OERRoleDefinition -Role 'Reader'
        $Result.RoleName | Should -Be 'Reader'
        $Result.PSObject.TypeNames[0] | Should -Be 'Omnicit.EntraRBAC.RoleDefinition'
        Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-OERArmRequest -Times 1 -Exactly -ParameterFilter {
            $Path -like "/providers/Microsoft.Authorization/roleDefinitions?api-version=2022-04-01&`$filter=*"
        }
    }

    It 'errors RoleDefinitionNotFound when a name matches nothing' {
        Mock -ModuleName Omnicit.EntraRBAC Invoke-OERArmRequest { [PSCustomObject]@{ value = @() } }
        { Get-OERRoleDefinition -Role 'No Such Role' -ErrorAction Stop } |
            Should -Throw -ErrorId 'RoleDefinitionNotFound,Get-OERRoleDefinition'
    }

    It 'tells the operator how to list the available roles when a name matches nothing' {
        Mock -ModuleName Omnicit.EntraRBAC Invoke-OERArmRequest { [PSCustomObject]@{ value = @() } }
        $Err = $null
        Get-OERRoleDefinition -Role 'Reeder' -ErrorAction SilentlyContinue -ErrorVariable Err
        $Record = @($Err | Where-Object { $_.FullyQualifiedErrorId -eq 'RoleDefinitionNotFound,Get-OERRoleDefinition' })
        $Record.Count | Should -Be 1
        $Record[0].Exception.Message | Should -Match 'without -Role to list the roles available'
    }

    It 'keeps the scope clause conditional in the not-found hint' {
        # The message builds its scope clause with an inline if, so the hint must stay conditional
        # too: a tenant-wide lookup has no scope to name and must not print an empty -Scope ''.
        Mock -ModuleName Omnicit.EntraRBAC Invoke-OERArmRequest { [PSCustomObject]@{ value = @() } }
        Mock -ModuleName Omnicit.EntraRBAC Resolve-OERScope { '/subscriptions/aaaa1111-0000-0000-0000-000000000000' }

        $TenantWide = $null
        Get-OERRoleDefinition -Role 'Reeder' -ErrorAction SilentlyContinue -ErrorVariable TenantWide
        $TenantRecord = @($TenantWide | Where-Object { $_.FullyQualifiedErrorId -eq 'RoleDefinitionNotFound,Get-OERRoleDefinition' })
        $TenantRecord.Count | Should -Be 1
        $TenantRecord[0].Exception.Message | Should -Not -Match '-Scope'
        $TenantRecord[0].Exception.Message | Should -Not -Match 'at scope'

        $Scoped = $null
        Get-OERRoleDefinition -Role 'Reeder' -Subscription 'aaaa1111-0000-0000-0000-000000000000' `
            -ErrorAction SilentlyContinue -ErrorVariable Scoped
        $ScopedRecord = @($Scoped | Where-Object { $_.FullyQualifiedErrorId -eq 'RoleDefinitionNotFound,Get-OERRoleDefinition' })
        $ScopedRecord.Count | Should -Be 1
        $ScopedRecord[0].Exception.Message | Should -Match "at scope '/subscriptions/aaaa1111-0000-0000-0000-000000000000'"
        $ScopedRecord[0].Exception.Message | Should -Match "-Scope '/subscriptions/aaaa1111-0000-0000-0000-000000000000'"
    }

    It 'gets a role definition directly by GUID' {
        Mock -ModuleName Omnicit.EntraRBAC Invoke-OERArmRequest {
            [PSCustomObject]@{ id = '/providers/Microsoft.Authorization/roleDefinitions/acdd72a7-3385-48ef-bd42-f606fba81ae7'; name = 'acdd72a7-3385-48ef-bd42-f606fba81ae7'; properties = [PSCustomObject]@{ roleName = 'Reader'; type = 'BuiltInRole' } }
        }
        $null = Get-OERRoleDefinition -Role 'acdd72a7-3385-48ef-bd42-f606fba81ae7'
        Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-OERArmRequest -Times 1 -Exactly -ParameterFilter {
            $Path -eq '/providers/Microsoft.Authorization/roleDefinitions/acdd72a7-3385-48ef-bd42-f606fba81ae7?api-version=2022-04-01'
        }
    }

    It 'lists only custom roles with -Custom and rejects -Custom with -Role' {
        Mock -ModuleName Omnicit.EntraRBAC Invoke-OERArmRequest { [PSCustomObject]@{ value = @() } }
        $null = Get-OERRoleDefinition -Custom
        Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-OERArmRequest -Times 1 -Exactly -ParameterFilter {
            $Path -like "/providers/Microsoft.Authorization/roleDefinitions?api-version=2022-04-01&`$filter=*CustomRole*" -and $All
        }
        { Get-OERRoleDefinition -Custom -Role 'Reader' -ErrorAction Stop } |
            Should -Throw -ErrorId 'AmbiguousFilter,Get-OERRoleDefinition'
    }

    It 'binds -ResourceGroup from the pipeline by property name' {
        $RgParam = (Get-Command Get-OERRoleDefinition).Parameters['ResourceGroup']
        $Attr = $RgParam.Attributes | Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] }
        @($Attr.ValueFromPipelineByPropertyName) | Should -Contain $true
    }

    It 'binds a piped resource-group-shaped object end to end (not just by attribute metadata)' {
        # An attribute-presence test passes even when an alias collision silently mis-binds at
        # runtime -- which is exactly what B-subscription-mg-id-collides was. Pipe a real object
        # and assert the resolver received the bound values.
        Mock -ModuleName Omnicit.EntraRBAC Resolve-OERScope { '/subscriptions/sub-guid/resourceGroups/rg-net' }
        Mock -ModuleName Omnicit.EntraRBAC Invoke-OERArmRequest { [PSCustomObject]@{ value = @() } }

        $Rg = [PSCustomObject]@{ SubscriptionId = 'sub-guid'; ResourceGroup = 'rg-net' }
        $null = $Rg | Get-OERRoleDefinition
        Should -Invoke -ModuleName Omnicit.EntraRBAC Resolve-OERScope -Times 1 -ParameterFilter {
            $Subscription -eq 'sub-guid' -and $ResourceGroup -eq 'rg-net'
        }
    }

    It 'scrubs the bearer-hygiene record when the ARM transport fails' {
        # CLAUDE.md SECURITY rule 6: the failed Invoke-WebRequest inside Invoke-OERArmRequest carries
        # Authorization: Bearer <token> on the request object recorded in $Error, so the catch must
        # call Remove-OERErrorRecord. Mock + Should -Invoke is the proof that holds for every rethrow
        # shape; a $global:Error + ReferenceEquals check is inert against a bare throw. This drives
        # the roleDefinitions LIST catch -- with no scope parameter Resolve-OERScope is never called.
        Mock -ModuleName Omnicit.EntraRBAC Invoke-OERArmRequest { throw 'transport failure' }
        Mock -ModuleName Omnicit.EntraRBAC Remove-OERErrorRecord { }
        $null = Get-OERRoleDefinition -ErrorAction SilentlyContinue
        Should -Invoke -ModuleName Omnicit.EntraRBAC Remove-OERErrorRecord -Times 1
    }
}

Describe 'Get-OERRoleDefinition: the example in the RoleDefinitionNotFound message (BL-113)' {
    BeforeAll {
        # BL-113: a command shown in a message must parse as typed and give the value back. Zero parse
        # errors is not enough on its own -- an unbalanced string can parse into the wrong tokens -- so
        # the argument must also come back, as a string constant, exactly as the value was typed.
        function Get-BL113Segment ([string]$Message, [string]$After, [string]$Before) {
            $Start = $Message.IndexOf($After, [System.StringComparison]::Ordinal)
            $Start | Should -BeGreaterOrEqual 0 -Because "the message holds '$After'"
            $Start += $After.Length
            $End = $Message.IndexOf($Before, $Start, [System.StringComparison]::Ordinal)
            $End | Should -BeGreaterThan $Start -Because "the message holds '$Before' after '$After'"
            $Message.Substring($Start, $End - $Start)
        }
        function Read-BL113Argument ([string]$Text, [string]$Command, [string]$Parameter) {
            $ParseErrors = $null
            $Ast = [System.Management.Automation.Language.Parser]::ParseInput($Text, [ref]$null, [ref]$ParseErrors)
            $Found = $Ast.Find({
                    param($Node)
                    $Node -is [System.Management.Automation.Language.CommandAst] -and $Node.GetCommandName() -eq $Command
                }, $true)
            $IsConstant = $false
            $Value = $null
            if ($Found) {
                $Elements = @($Found.CommandElements)
                for ($I = 0; $I -lt $Elements.Count - 1; $I++) {
                    if ($Elements[$I] -is [System.Management.Automation.Language.CommandParameterAst] -and $Elements[$I].ParameterName -eq $Parameter) {
                        $IsConstant = $Elements[$I + 1] -is [System.Management.Automation.Language.StringConstantExpressionAst]
                        if ($IsConstant) { $Value = $Elements[$I + 1].Value }
                    }
                }
            }
            [PSCustomObject]@{ ParseErrorCount = @($ParseErrors).Count; Found = [bool]$Found; IsConstant = $IsConstant; Value = $Value }
        }
        # The nested form: the command sits inside ONE single-quoted literal of the message. Read that
        # literal first (one literal and the end of the input), then the command it holds, up to $CutAt.
        function Read-BL113NestedArgument ([string]$Literal, [string]$CutAt, [string]$Command, [string]$Parameter) {
            $Tokens = $null
            $ParseErrors = $null
            $null = [System.Management.Automation.Language.Parser]::ParseInput($Literal, [ref]$Tokens, [ref]$ParseErrors)
            @($ParseErrors).Count | Should -Be 0 -Because "the literal in the message ($Literal) parses"
            @($Tokens).Count | Should -Be 2 -Because "the text in the message ($Literal) is one string literal"
            $Tokens[0].Kind | Should -Be ([System.Management.Automation.Language.TokenKind]::StringLiteral)
            $Inner = [string]$Tokens[0].Value
            if ($CutAt -and $Inner.Contains($CutAt)) { $Inner = $Inner.Substring(0, $Inner.IndexOf($CutAt, [System.StringComparison]::Ordinal)) }
            Read-BL113Argument -Text $Inner -Command $Command -Parameter $Parameter
        }
    }

    BeforeEach {
        InModuleScope Omnicit.EntraRBAC { $script:_OERAuthState = $null }
        Mock -ModuleName Omnicit.EntraRBAC Initialize-OERAuth { }
        Mock -ModuleName Omnicit.EntraRBAC Invoke-OERArmRequest { [PSCustomObject]@{ value = @() } }
        Mock -ModuleName Omnicit.EntraRBAC Resolve-OERScope { $script:BL113Scope }
    }

    It 'shows the Get-OERRoleDefinition example in RoleDefinitionNotFound so it parses and gives the scope back for a scope holding <Label>' -ForEach @(
        @{ Label = 'a straight apostrophe (U+0027)'; Scope = "/subscriptions/s1/resourceGroups/rg's"; Escaped = "/subscriptions/s1/resourceGroups/rg''s" }
        @{ Label = 'a right single quotation mark (U+2019)'; Scope = ('/subscriptions/s1/resourceGroups/rg' + [char]0x2019 + 's'); Escaped = ('/subscriptions/s1/resourceGroups/rg' + [char]0x2019 + [char]0x2019 + 's') }
    ) {
        $script:BL113Scope = $Scope
        $Err = $null
        $null = Get-OERRoleDefinition -Role 'Reeder' -Subscription 'aaaa1111-0000-0000-0000-000000000000' `
            -ErrorAction SilentlyContinue -ErrorVariable Err
        $Own = @($Err | Where-Object { [string]$_.FullyQualifiedErrorId -ceq 'RoleDefinitionNotFound,Get-OERRoleDefinition' })
        $Own.Count | Should -Be 1
        $Example = Get-BL113Segment -Message $Own[0].Exception.Message -After '. Run ' -Before ' without -Role'
        $Example | Should -BeExactly "Get-OERRoleDefinition -Scope '$Escaped'"
        $Read = Read-BL113Argument -Text $Example -Command 'Get-OERRoleDefinition' -Parameter 'Scope'
        $Read.ParseErrorCount | Should -Be 0
        $Read.IsConstant | Should -BeTrue
        $Read.Value | Should -BeExactly $Scope
    }
}
