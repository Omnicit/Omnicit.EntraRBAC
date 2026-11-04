BeforeAll {
    Import-Module Omnicit.EntraRBAC -Force
    . "$PSScriptRoot/../TestHelpers/OERTransportTripwire.ps1"
    Install-OERTransportTripwire
}

AfterAll {
    try { Assert-OERTransportTripwire } finally { Uninstall-OERTransportTripwire }
}

Describe 'Test-OERRoleLookupUnresolved' {
    # Pure: the answer comes from the record's FullyQualifiedErrorId alone. Each record is built with the id
    # as given, so a bare id stands for the record as thrown and an id with ',<command>' for one that has
    # already crossed a WriteError boundary.
    It 'answers <Answer> for <Id>' -ForEach @(
        @{ Id = 'RoleDefinitionUnresolved'; Answer = $true }
        @{ Id = 'RoleDefinitionUnresolved,Get-OERRoleManagementPolicy'; Answer = $true }
        @{ Id = 'RolePolicyUnresolved'; Answer = $true }
        @{ Id = 'RolePolicyUnresolved,Set-OERRoleManagementPolicy'; Answer = $true }
        # A failed read, an ambiguous name and a paging refusal are no evidence that nothing matched.
        @{ Id = 'AuthorizationFailed'; Answer = $false }
        @{ Id = 'AmbiguousName'; Answer = $false }
        @{ Id = 'ArmPagingIncomplete,Invoke-OERArmRequest'; Answer = $false }
        @{ Id = 'GraphPagingIncomplete'; Answer = $false }
        # The published ids are not the internal ones: a record already reported is never re-read as one.
        @{ Id = 'RoleDefinitionNotFound'; Answer = $false }
        @{ Id = 'PolicyNotFound'; Answer = $false }
        # Ordinal and a prefix: another letter case, or the id later in the text, is not the id.
        @{ Id = 'roledefinitionunresolved'; Answer = $false }
        @{ Id = 'ROLEPOLICYUNRESOLVED'; Answer = $false }
        @{ Id = 'XRolePolicyUnresolved'; Answer = $false }
        @{ Id = 'Lookup,RoleDefinitionUnresolved'; Answer = $false }
    ) {
        InModuleScope Omnicit.EntraRBAC -Parameters @{ Id = $Id; Answer = $Answer } {
            param($Id, $Answer)
            $Record = [System.Management.Automation.ErrorRecord]::new(
                [System.Exception]::new('lookup answer'), $Id, [System.Management.Automation.ErrorCategory]::NotSpecified, 'value')
            $Result = Test-OERRoleLookupUnresolved -Record $Record
            $Result | Should -BeOfType ([bool])
            $Result | Should -Be $Answer
        }
    }

    It 'classifies a record caught from a throw the way the two helpers throw it' {
        InModuleScope Omnicit.EntraRBAC {
            $Caught = $null
            try {
                throw [System.Management.Automation.ErrorRecord]::new(
                    [System.Exception]::new('Role definition ''x'' was not found.'), 'RoleDefinitionUnresolved',
                    [System.Management.Automation.ErrorCategory]::ObjectNotFound, 'x')
            } catch {
                $Caught = $PSItem
            }
            Test-OERRoleLookupUnresolved -Record $Caught | Should -BeTrue
        }
    }

    It 'answers false for a plain string throw: its id is its own text, which no helper gives an internal id' {
        InModuleScope Omnicit.EntraRBAC {
            $Caught = $null
            try { throw 'Role definition was not found.' } catch { $Caught = $PSItem }
            Test-OERRoleLookupUnresolved -Record $Caught | Should -BeFalse
        }
    }

    It 'answers false for a null record, and never throws' {
        InModuleScope Omnicit.EntraRBAC {
            { Test-OERRoleLookupUnresolved -Record $null } | Should -Not -Throw
            Test-OERRoleLookupUnresolved -Record $null | Should -BeFalse
            Test-OERRoleLookupUnresolved | Should -BeFalse
        }
    }
}

Describe 'Test-OERRoleLookupUnresolved cohort: the single owner of the role and policy lookup classification (Sprint 12 step 3)' {
    # Static: the source files are parsed, nothing in them runs. A "test" of an internal id is a string
    # constant that names it standing as an operand of a comparison operator (-eq, -ne, -like, -notlike,
    # -match, -notmatch, -contains, -notcontains, -in, -notin, each in every letter-case form), as an argument
    # of a string comparison method (StartsWith, EndsWith, Contains, Equals, Compare, CompareOrdinal,
    # IndexOf), or as a switch clause. The two producers construct the ids and are allowed. Not seen: an id
    # held in a variable first, or built at run time; an id given to a COMMAND as a parameter value rather
    # than to an operator; and a method outside the list above, such as [regex]::IsMatch. Those are kept out
    # by review. The ids are also kept out of every other construction: no file but the owner and the two
    # producers names either id at all.
    BeforeAll {
        $script:SourceRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '../../../source')).Path
        $script:OwnerFile = 'Private/Test-OERRoleLookupUnresolved.ps1'
        $script:Allowed = @(
            $script:OwnerFile
            'Private/Resolve-OERRoleDefinitionId.ps1'
            'Private/Get-OERRoleManagementPolicyId.ps1'
        )
        $script:TwoSites = @(
            'Public/Get-OERRoleManagementPolicy.ps1'
            'Public/Set-OERRoleManagementPolicy.ps1'
        )

        function script:Get-RoleIdTest {
            param([System.Management.Automation.Language.Ast]$Ast)
            $Comparison = @(
                'Ieq', 'Ceq', 'Ine', 'Cne', 'Ilike', 'Clike', 'Inotlike', 'Cnotlike', 'Imatch', 'Cmatch', 'Inotmatch', 'Cnotmatch',
                'Icontains', 'Ccontains', 'Inotcontains', 'Cnotcontains', 'Iin', 'Cin', 'Inotin', 'Cnotin'
            )
            $Methods = @('StartsWith', 'EndsWith', 'Contains', 'Equals', 'Compare', 'CompareOrdinal', 'IndexOf')
            $NamesId = {
                param($Node)
                ($Node -is [System.Management.Automation.Language.StringConstantExpressionAst] -or
                    $Node -is [System.Management.Automation.Language.ExpandableStringExpressionAst]) -and
                [string]$Node.Value -match 'RoleDefinitionUnresolved|RolePolicyUnresolved'
            }
            $HoldsId = {
                param($Node)
                $null -ne $Node -and @($Node.FindAll($NamesId, $true)).Count -gt 0
            }
            $Hits = $Ast.FindAll({
                    param($Node)
                    if ($Node -is [System.Management.Automation.Language.BinaryExpressionAst]) {
                        return ([string]$Node.Operator -in $Comparison) -and ((& $HoldsId $Node.Left) -or (& $HoldsId $Node.Right))
                    }
                    if ($Node -is [System.Management.Automation.Language.InvokeMemberExpressionAst]) {
                        $Member = $Node.Member
                        if ($Member -isnot [System.Management.Automation.Language.StringConstantExpressionAst]) { return $false }
                        if ([string]$Member.Value -notin $Methods) { return $false }
                        foreach ($Argument in @($Node.Arguments)) { if (& $HoldsId $Argument) { return $true } }
                        return $false
                    }
                    if ($Node -is [System.Management.Automation.Language.SwitchStatementAst]) {
                        foreach ($Clause in @($Node.Clauses)) { if (& $HoldsId $Clause.Item1) { return $true } }
                        return $false
                    }
                    $false
                }, $true)
            foreach ($Hit in $Hits) { 'line {0}: {1}' -f $Hit.Extent.StartLineNumber, ($Hit.Extent.Text -split "`n")[0].Trim() }
        }
        function script:Get-RoleIdTestInText ([string]$Text) {
            $Tokens = $null
            $ParseErrors = $null
            Get-RoleIdTest -Ast ([System.Management.Automation.Language.Parser]::ParseInput($Text, [ref]$Tokens, [ref]$ParseErrors))
        }
        function script:Get-RoleIdTestInFile ([string]$Path) {
            $Tokens = $null
            $ParseErrors = $null
            $Ast = [System.Management.Automation.Language.Parser]::ParseFile($Path, [ref]$Tokens, [ref]$ParseErrors)
            @($ParseErrors).Count | Should -Be 0 -Because "the file '$Path' must parse"
            Get-RoleIdTest -Ast $Ast
        }
    }

    It 'the scan is not inert: it finds the owner''s own two tests and every inline shape, and no construction' {
        @(Get-RoleIdTestInFile -Path (Join-Path $script:SourceRoot $script:OwnerFile)).Count | Should -Be 2
        foreach ($Shape in @(
                "if (([string]`$PSItem.FullyQualifiedErrorId).StartsWith('RoleDefinitionUnresolved', [System.StringComparison]::Ordinal)) { }"
                "if ([string]`$E.FullyQualifiedErrorId -like 'RolePolicyUnresolved*') { }"
                "if (`$E.FullyQualifiedErrorId -match '^RoleDefinitionUnresolved') { }"
                "if (`$Id -eq 'RolePolicyUnresolved') { }"
                "if ('RoleDefinitionUnresolved' -ceq `$Id) { }"
                "if (`$Id -notlike 'RolePolicyUnresolved*') { }"
                "if (`$Id -in @('RoleDefinitionUnresolved', 'RolePolicyUnresolved')) { }"
                "if ([string]::Equals(`$Id, 'RolePolicyUnresolved', [System.StringComparison]::Ordinal)) { }"
                "switch -Wildcard (`$Id) { 'RoleDefinitionUnresolved*' { } }"
            )) {
            @(Get-RoleIdTestInText -Text $Shape).Count | Should -Be 1 -Because "the shape must be found: $Shape"
        }
        # A producer constructs the id: that is not a test, and an id named in a message is not one either.
        @(Get-RoleIdTestInText -Text "throw [System.Management.Automation.ErrorRecord]::new(`$Ex, 'RolePolicyUnresolved', [System.Management.Automation.ErrorCategory]::ObjectNotFound, `$Value)").Count | Should -Be 0
        @(Get-RoleIdTestInText -Text "Write-Verbose 'RoleDefinitionUnresolved is internal'").Count | Should -Be 0
    }

    It 'no file under source/ other than the owner and the two producers tests RoleDefinitionUnresolved or RolePolicyUnresolved' {
        $Files = @(Get-ChildItem -LiteralPath $script:SourceRoot -Recurse -File -Filter '*.ps1')
        # The scan reaches the tree: the two cmdlets are among the files read.
        $Files.Count | Should -BeGreaterThan 100
        foreach ($Site in $script:TwoSites) {
            @($Files | Where-Object { $_.FullName -eq (Get-Item -LiteralPath (Join-Path $script:SourceRoot $Site)).FullName }).Count | Should -Be 1
        }
        $Found = @(foreach ($File in $Files) {
                $Relative = $File.FullName.Substring($script:SourceRoot.Length + 1).Replace('\', '/')
                if ($Relative -in $script:Allowed) { continue }
                foreach ($Hit in (Get-RoleIdTestInFile -Path $File.FullName)) { '{0}: {1}' -f $Relative, $Hit }
            })
        $Found | Should -BeNullOrEmpty -Because 'Test-OERRoleLookupUnresolved is the single owner of the classification; ask it instead'
    }

    It 'no file under source/ other than the owner and the two producers names an internal id at all (never published)' {
        $Files = @(Get-ChildItem -LiteralPath $script:SourceRoot -Recurse -File -Filter '*.ps1')
        $Named = @(foreach ($File in $Files) {
                $Relative = $File.FullName.Substring($script:SourceRoot.Length + 1).Replace('\', '/')
                if ($Relative -in $script:Allowed) { continue }
                # The two public cmdlets and the inventory may talk ABOUT the ids in comments only; code naming
                # one is a test the scan above cannot see (a variable, a parameter value).
                $Tokens = $null
                $ParseErrors = $null
                $null = [System.Management.Automation.Language.Parser]::ParseFile($File.FullName, [ref]$Tokens, [ref]$ParseErrors)
                foreach ($Token in $Tokens) {
                    if ($Token.Kind -eq [System.Management.Automation.Language.TokenKind]::Comment) { continue }
                    if ($Token.Text -match 'RoleDefinitionUnresolved|RolePolicyUnresolved') { '{0}: line {1}' -f $Relative, $Token.Extent.StartLineNumber }
                }
            })
        $Named | Should -BeNullOrEmpty
    }

    It '<_> asks Test-OERRoleLookupUnresolved' -ForEach @(
        'Public/Get-OERRoleManagementPolicy.ps1'
        'Public/Set-OERRoleManagementPolicy.ps1'
    ) {
        $File = Join-Path $script:SourceRoot $_
        $Tokens = $null
        $ParseErrors = $null
        $Ast = [System.Management.Automation.Language.Parser]::ParseFile($File, [ref]$Tokens, [ref]$ParseErrors)
        @($ParseErrors).Count | Should -Be 0
        $Calls = @($Ast.FindAll({
                    param($Node)
                    $Node -is [System.Management.Automation.Language.CommandAst] -and
                    $Node.GetCommandName() -eq 'Test-OERRoleLookupUnresolved'
                }, $true))
        # ByRole asks twice (definition, policy); Get-OERRoleManagementPolicy asks a third time in -CommonRoles.
        $Calls.Count | Should -BeGreaterThan 1
    }
}
