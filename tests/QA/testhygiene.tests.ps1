BeforeAll {
    $script:ProjectPath = (Resolve-Path -Path (Join-Path -Path $PSScriptRoot -ChildPath '..\..')).Path

    # =====================================================================================
    # THE TRANSPORT TRIPWIRE, HELD BY PRESENCE.
    #
    # tests/Unit/TestHelpers/OERTransportTripwire.ps1 replaces the six commands through which
    # module code reaches a tenant or the network (Get-AzToken, Connect-MgGraph, Disconnect-MgGraph,
    # Invoke-MgGraphRequest, Invoke-WebRequest, Invoke-RestMethod) with global functions that record
    # the call and throw. It only works in a file that installs it: a unit test file that forgets
    # would run with nothing between an unmocked module call and the real transport, and stay
    # green. This gate reads every unit test file statically -- it imports nothing and runs no
    # module code -- and requires, in each, a root BeforeAll that calls Install-OERTransportTripwire
    # AFTER the module import, and a root AfterAll whose try calls Assert-OERTransportTripwire and
    # whose finally calls Uninstall-OERTransportTripwire -- a try with no catch, since a catch would
    # swallow the assert's throw and leave the file green.
    # Why: docs/development/rationale.md#bearer-scrub-tests
    #
    # The QA gate files are outside it on purpose: they call help, the analyzer and pure maps only.
    # =====================================================================================

    # The two AST-only cohort suites parse source files and import nothing, so no module code can
    # run in them. Named here, and the second It below fails if either starts importing, calls a
    # Verb-OER* command or runs Get-Command -Module.
    $script:TripwireExempt = @(
        'tests/Unit/Public/AdministrativeUnitAliasOrder.Cohort.Tests.ps1'
        'tests/Unit/Public/GroupAliasOrder.Cohort.Tests.ps1'
    )

    function Get-TestHygieneRootBlockBody {
        <#
        .SYNOPSIS
        Returns the scriptblock body of every ROOT call of the named Pester block in a parsed file.
        #>
        [OutputType([System.Management.Automation.Language.ScriptBlockAst])]
        param(
            [Parameter(Mandatory)]
            [System.Management.Automation.Language.ScriptBlockAst]$Ast,

            [Parameter(Mandatory)]
            [string]$Name
        )
        if ($null -eq $Ast.EndBlock) { return }
        foreach ($Statement in $Ast.EndBlock.Statements) {
            if ($Statement -isnot [System.Management.Automation.Language.PipelineAst]) { continue }
            $Command = $Statement.PipelineElements[0]
            if ($Command -isnot [System.Management.Automation.Language.CommandAst]) { continue }
            if ($Command.GetCommandName() -ne $Name) { continue }
            $Block = @($Command.CommandElements | Where-Object { $_ -is [System.Management.Automation.Language.ScriptBlockExpressionAst] })[0]
            if ($Block) { $Block.ScriptBlock }
        }
    }

    function Get-TestHygieneDirectCall {
        <#
        .SYNOPSIS
        Returns every statement in a list that is a direct call of the named command.
        #>
        [OutputType([System.Management.Automation.Language.CommandAst])]
        param(
            [AllowNull()]
            [object]$Statements,

            [Parameter(Mandatory)]
            [string]$Name
        )
        foreach ($Statement in @($Statements)) {
            if ($Statement -isnot [System.Management.Automation.Language.PipelineAst]) { continue }
            $Command = $Statement.PipelineElements[0]
            if ($Command -is [System.Management.Automation.Language.CommandAst] -and $Command.GetCommandName() -eq $Name) {
                $Command
            }
        }
    }

    function Get-TestHygieneTripwireFinding {
        <#
        .SYNOPSIS
        Returns one reason per way a unit test file fails to install, check and uninstall the tripwire.
        .DESCRIPTION
        Parses the text and reads only its ROOT BeforeAll and AfterAll (pipelines directly in the
        file's end block). The Install and Assert/Uninstall calls must be direct statements of those
        blocks -- a call buried in a function that nothing invokes would otherwise pass. A root
        BeforeAll "calls Install before Import-Module" when the Install call's StartOffset is not
        greater than the StartOffset of the first Import-Module command in that block, or when the
        block has no Import-Module at all. The try around the Assert call must have no catch clause:
        a catch would swallow the assert's throw. Returns nothing for a file that wires the tripwire.
        #>
        [OutputType([string])]
        param(
            [Parameter(Mandatory)]
            [string]$Text
        )
        $Tokens = $null
        $Errors = $null
        $Ast = [System.Management.Automation.Language.Parser]::ParseInput($Text, [ref]$Tokens, [ref]$Errors)
        if (@($Errors).Count -gt 0) {
            'does not parse'
            return
        }

        $BeforeAll = @(Get-TestHygieneRootBlockBody -Ast $Ast -Name 'BeforeAll')
        if ($BeforeAll.Count -eq 0) {
            'no root BeforeAll'
        } else {
            $Installed = $false
            $InstalledInOrder = $false
            foreach ($Body in $BeforeAll) {
                $Installs = @(Get-TestHygieneDirectCall -Statements $Body.EndBlock.Statements -Name 'Install-OERTransportTripwire')
                if ($Installs.Count -eq 0) { continue }
                $Installed = $true
                $FirstImport = @($Body.FindAll({
                            param($Node)
                            $Node -is [System.Management.Automation.Language.CommandAst] -and $Node.GetCommandName() -eq 'Import-Module'
                        }, $true) | Sort-Object -Property { $_.Extent.StartOffset })[0]
                if ($FirstImport -and $Installs[0].Extent.StartOffset -gt $FirstImport.Extent.StartOffset) {
                    $InstalledInOrder = $true
                }
            }
            if (-not $Installed) {
                'root BeforeAll does not call Install-OERTransportTripwire'
            } elseif (-not $InstalledInOrder) {
                'root BeforeAll calls Install-OERTransportTripwire before Import-Module'
            }
        }

        $AfterAll = @(Get-TestHygieneRootBlockBody -Ast $Ast -Name 'AfterAll')
        if ($AfterAll.Count -eq 0) {
            'no root AfterAll'
        } else {
            $Checked = $false
            foreach ($Body in $AfterAll) {
                foreach ($Statement in @($Body.EndBlock.Statements)) {
                    if ($Statement -isnot [System.Management.Automation.Language.TryStatementAst]) { continue }
                    if ($null -eq $Statement.Finally) { continue }
                    if ($Statement.CatchClauses.Count -gt 0) { continue }
                    $Asserts = @(Get-TestHygieneDirectCall -Statements $Statement.Body.Statements -Name 'Assert-OERTransportTripwire')
                    $Uninstalls = @(Get-TestHygieneDirectCall -Statements $Statement.Finally.Statements -Name 'Uninstall-OERTransportTripwire')
                    if ($Asserts.Count -gt 0 -and $Uninstalls.Count -gt 0) { $Checked = $true }
                }
            }
            if (-not $Checked) {
                'root AfterAll does not call Assert-OERTransportTripwire inside a try with no catch whose finally calls Uninstall-OERTransportTripwire'
            }
        }
    }

    function Get-TestHygieneExemptFinding {
        <#
        .SYNOPSIS
        Returns 'line N: name' for each command in a parsed file that can import or run module code.
        .DESCRIPTION
        An exempt file must import nothing. Refused: Import-Module and InModuleScope; any command
        whose name holds '-OER', since module autoloading imports the module to run a Verb-OER*
        command; and Get-Command with its -Module parameter, under any of its names or a prefix of
        one (-Module, -PSSnapin, -FullyQualifiedModule). Returns nothing for a file that does none
        of these.
        #>
        [OutputType([string])]
        param(
            [Parameter(Mandatory)]
            [System.Management.Automation.Language.Ast]$Ast
        )
        $Commands = $Ast.FindAll({
                param($Node)
                $Node -is [System.Management.Automation.Language.CommandAst]
            }, $true)
        foreach ($Command in $Commands) {
            $Name = $Command.GetCommandName()
            if (-not $Name) { continue }
            $Refused = ($Name -in @('Import-Module', 'InModuleScope')) -or ($Name -match '-OER')
            if (-not $Refused -and $Name -eq 'Get-Command') {
                foreach ($Element in $Command.CommandElements) {
                    if ($Element -isnot [System.Management.Automation.Language.CommandParameterAst]) { continue }
                    foreach ($Full in 'Module', 'PSSnapin', 'FullyQualifiedModule') {
                        if ($Element.ParameterName -and $Full.StartsWith($Element.ParameterName, [System.StringComparison]::OrdinalIgnoreCase)) { $Refused = $true }
                    }
                }
            }
            if ($Refused) {
                'line {0}: {1}' -f $Command.Extent.StartLineNumber, $Name
            }
        }
    }

    # =====================================================================================
    # A DEFAULT MOCK BESIDE EVERY FILTERED MOCK, HELD BY A RATCHET.
    #
    # A call that no -ParameterFilter of a mock matches, with no default mock beside them, calls the
    # original on Pester 5.7.1 (now the tripwire) and throws "No mock for command ... matched the
    # call" on 6.x, inside module code where a catch can swallow it (the happy path silently
    # replaced by the failure path). The remedy is a default mock beside every filtered mock.
    # Why: docs/development/rationale.md#bearer-scrub-tests
    #
    # The rule, read statically from the text of every unit test file (nothing imported, no module
    # code run): a Mock call carrying -ParameterFilter needs, in the SAME script block, a Mock of
    # the same command with the same -ModuleName text (or none on both) and no -ParameterFilter.
    # "Same block" is the innermost script block holding the Mock call: an It, BeforeAll,
    # BeforeEach or AfterEach body, a Context or Describe body, or a nested script block. A default
    # in an enclosing or a nested block does not count -- stricter than Pester's own fallback, on
    # purpose, and the ratchet below absorbs the sites that predate the rule.
    #
    # A Mock whose command is not a literal (a variable, a splat) cannot be matched by name. Such a
    # site is counted as unresolvable and reported, never as a violation.
    #
    # The table is keyed on Mock statements only: a later edit of a Should -Invoke line moves
    # nothing in it.
    # =====================================================================================

    function Get-TestHygieneMockArgument {
        <#
        .SYNOPSIS
        Returns the command name, module name text and filter flag of one parsed Mock call.
        .DESCRIPTION
        Reads the call's elements by Pester's own parameter names (a unique prefix is accepted, as
        PowerShell binds it): -CommandName, -MockWith, -ModuleName and -ParameterFilter take a value,
        -Verifiable, -RemoveParameterType and -RemoveParameterValidation do not take one as a switch
        and so consume nothing; the first positional value is the command name when -CommandName is
        not named. CommandName is $null when it is not a string literal or the call is splatted.
        ModuleName is the literal text, or the argument's source text when it is not a literal, and
        $null when absent.
        #>
        [OutputType([pscustomobject])]
        param(
            [Parameter(Mandatory)]
            [System.Management.Automation.Language.CommandAst]$Command
        )
        $ValueParameters = 'CommandName', 'MockWith', 'ModuleName', 'ParameterFilter', 'RemoveParameterType', 'RemoveParameterValidation'
        $SwitchParameters = 'Verifiable'
        $Named = @{}
        $Positional = [System.Collections.Generic.List[System.Management.Automation.Language.Ast]]::new()
        $Splatted = $false
        $Elements = @($Command.CommandElements | Select-Object -Skip 1)
        for ($Index = 0; $Index -lt $Elements.Count; $Index++) {
            $Element = $Elements[$Index]
            if ($Element -is [System.Management.Automation.Language.CommandParameterAst]) {
                $Candidates = @($ValueParameters + $SwitchParameters | Where-Object { $_.StartsWith($Element.ParameterName, [System.StringComparison]::OrdinalIgnoreCase) })
                $Exact = @($Candidates | Where-Object { $_ -eq $Element.ParameterName })
                if ($Exact.Count -eq 1) { $Candidates = $Exact }
                if ($Candidates.Count -ne 1) { continue }
                $Resolved = $Candidates[0]
                if ($Resolved -in $SwitchParameters) { continue }
                if ($null -ne $Element.Argument) {
                    $Named[$Resolved] = $Element.Argument
                } elseif ($Index + 1 -lt $Elements.Count) {
                    $Named[$Resolved] = $Elements[$Index + 1]
                    $Index++
                }
                continue
            }
            if ($Element -is [System.Management.Automation.Language.VariableExpressionAst] -and $Element.Splatted) {
                $Splatted = $true
                continue
            }
            $Positional.Add($Element)
        }

        $NameAst = $null
        if ($Named.ContainsKey('CommandName')) {
            $NameAst = $Named['CommandName']
        } elseif ($Positional.Count -gt 0) {
            $NameAst = $Positional[0]
        }
        $CommandName = $null
        if (-not $Splatted -and $NameAst -is [System.Management.Automation.Language.StringConstantExpressionAst]) {
            $CommandName = $NameAst.Value
        }
        $ModuleName = $null
        if ($Named.ContainsKey('ModuleName')) {
            $ModuleAst = $Named['ModuleName']
            $ModuleName = if ($ModuleAst -is [System.Management.Automation.Language.StringConstantExpressionAst]) { $ModuleAst.Value } else { $ModuleAst.Extent.Text }
        }
        [pscustomobject]@{
            CommandName = $CommandName
            ModuleName  = $ModuleName
            Filtered    = $Named.ContainsKey('ParameterFilter')
        }
    }

    function Get-TestHygieneMockDefaultFinding {
        <#
        .SYNOPSIS
        Returns one record per Mock call that carries -ParameterFilter, with whether it is a violation.
        .DESCRIPTION
        Parses the text and looks at every command named Mock. For each that carries -ParameterFilter
        the innermost script block holding it is found (the first ScriptBlockAst up its parents); the
        filtered mock is a violation unless that same block also holds a Mock of the same command
        name (ignoring case) and the same -ModuleName text (or none on both) with no
        -ParameterFilter. A Mock inside an if or a loop of the block counts as in the block; one in
        a nested or an enclosing script block does not. A Mock whose command name is not a literal gets Kind 'Unresolvable' and is
        never a violation. Each record has Kind ('Violation', 'Unresolvable', 'Covered' or
        'Unparsable'), Line and Command. Returns the single record 'Unparsable' for text that does
        not parse, which the ratchet counts as a violation. Returns nothing for a file with no
        filtered Mock.
        #>
        [OutputType([pscustomobject])]
        param(
            [Parameter(Mandatory)]
            [string]$Text
        )
        $Tokens = $null
        $Errors = $null
        $Ast = [System.Management.Automation.Language.Parser]::ParseInput($Text, [ref]$Tokens, [ref]$Errors)
        if (@($Errors).Count -gt 0) {
            [pscustomobject]@{ Kind = 'Unparsable'; Line = 0; Command = '' }
            return
        }
        $Mocks = @($Ast.FindAll({
                    param($Node)
                    $Node -is [System.Management.Automation.Language.CommandAst] -and $Node.GetCommandName() -eq 'Mock'
                }, $true))
        $Parsed = foreach ($Mock in $Mocks) {
            $Block = $Mock.Parent
            while ($null -ne $Block -and $Block -isnot [System.Management.Automation.Language.ScriptBlockAst]) { $Block = $Block.Parent }
            $Argument = Get-TestHygieneMockArgument -Command $Mock
            [pscustomobject]@{
                Ast         = $Mock
                Block       = $Block
                CommandName = $Argument.CommandName
                ModuleName  = $Argument.ModuleName
                Filtered    = $Argument.Filtered
            }
        }
        foreach ($Item in @($Parsed | Where-Object { $_.Filtered })) {
            $Line = $Item.Ast.Extent.StartLineNumber
            if ($null -eq $Item.CommandName) {
                [pscustomobject]@{ Kind = 'Unresolvable'; Line = $Line; Command = '' }
                continue
            }
            $Defaults = @($Parsed | Where-Object {
                    -not $_.Filtered -and
                    [object]::ReferenceEquals($_.Block, $Item.Block) -and
                    $null -ne $_.CommandName -and
                    $_.CommandName -eq $Item.CommandName -and
                    (($null -eq $_.ModuleName -and $null -eq $Item.ModuleName) -or ($null -ne $_.ModuleName -and $null -ne $Item.ModuleName -and $_.ModuleName -eq $Item.ModuleName))
                })
            [pscustomobject]@{
                Kind    = if ($Defaults.Count -gt 0) { 'Covered' } else { 'Violation' }
                Line    = $Line
                Command = $Item.CommandName
            }
        }
    }

    # File (relative path) -> count of filtered Mock calls with no default beside them in the same
    # script block, measured on 2026-10-22. A file not listed is held to 0. Lower a number in the
    # same change that adds the default mock; a higher count is a new violation and fails.
    $script:MockDefaultRatchet = [ordered]@{
        'tests/Unit/Private/ConvertTo-OERManagementGroup.Tests.ps1' = 3
        'tests/Unit/Private/Enable-OERGroupPermanentEligibility.Tests.ps1' = 7
        'tests/Unit/Private/Get-OERDirectoryRoleNameMap.Tests.ps1' = 7
        'tests/Unit/Private/Get-OERGroupPimPolicyCloseAdvice.Tests.ps1' = 2
        'tests/Unit/Private/Get-OERGroupPimPolicyOpenAdvice.Tests.ps1' = 2
        'tests/Unit/Private/Get-OERGroupRelation.Tests.ps1' = 22
        'tests/Unit/Private/Get-OERRoleAssignableState.Tests.ps1' = 1
        'tests/Unit/Private/Get-OERSubscriptionHomeTenant.Tests.ps1' = 2
        'tests/Unit/Private/Read-OERGroupCollection.Tests.ps1' = 6
        'tests/Unit/Private/Resolve-OERCatalogResource.Tests.ps1' = 3
        'tests/Unit/Private/Resolve-OERDirectoryRoleId.Tests.ps1' = 13
        'tests/Unit/Private/Resolve-OERInventoryScopeTree.Tests.ps1' = 2
        'tests/Unit/Private/Resolve-OERScope.Tests.ps1' = 33
        'tests/Unit/Private/Resolve-OERStructurePrincipal.Tests.ps1' = 2
        'tests/Unit/Private/Sync-OERStructureAccessPackage.Tests.ps1' = 45
        'tests/Unit/Private/Sync-OERStructureAccessReview.Tests.ps1' = 7
        'tests/Unit/Private/Sync-OERStructureAdministrativeUnit.Tests.ps1' = 34
        'tests/Unit/Private/Sync-OERStructureCatalog.Tests.ps1' = 42
        'tests/Unit/Private/Sync-OERStructureDirectoryRoleAssignment.Tests.ps1' = 5
        'tests/Unit/Private/Sync-OERStructureDirectoryRoleManagementPolicy.Tests.ps1' = 3
        'tests/Unit/Private/Sync-OERStructureGroup.Tests.ps1' = 14
        'tests/Unit/Private/Sync-OERStructureRoleManagementPolicy.Tests.ps1' = 3
        'tests/Unit/Public/Add-OERAccessPackageResourceRole.Tests.ps1' = 16
        'tests/Unit/Public/Add-OERAdministrativeUnitMember.Tests.ps1' = 4
        'tests/Unit/Public/Add-OERAdministrativeUnitScopedRole.Tests.ps1' = 5
        'tests/Unit/Public/Add-OERCatalogResource.Tests.ps1' = 12
        'tests/Unit/Public/Add-OERGroupMember.Tests.ps1' = 2
        'tests/Unit/Public/Enable-OEREligibleRoleAssignment.Tests.ps1' = 13
        'tests/Unit/Public/Export-OERInventory.Tests.ps1' = 20
        'tests/Unit/Public/Get-OERAccessPackage.Tests.ps1' = 6
        'tests/Unit/Public/Get-OERAccessPackageAssignmentPolicy.Tests.ps1' = 3
        'tests/Unit/Public/Get-OERActiveRoleAssignment.Tests.ps1' = 1
        'tests/Unit/Public/Get-OERAdministrativeUnit.Tests.ps1' = 21
        'tests/Unit/Public/Get-OERAdministrativeUnitScopedRole.Tests.ps1' = 6
        'tests/Unit/Public/Get-OERCatalog.Tests.ps1' = 4
        'tests/Unit/Public/Get-OERCatalogResource.Tests.ps1' = 3
        'tests/Unit/Public/Get-OEREligibleRoleAssignment.Tests.ps1' = 1
        'tests/Unit/Public/Get-OERGroup.Tests.ps1' = 64
        'tests/Unit/Public/Get-OERGroupMember.Tests.ps1' = 6
        'tests/Unit/Public/Get-OERGroupPimPolicy.Tests.ps1' = 10
        'tests/Unit/Public/Get-OERInventory.Tests.ps1' = 44
        'tests/Unit/Public/Get-OERManagementGroup.Tests.ps1' = 10
        'tests/Unit/Public/Get-OERRoleAssignment.Tests.ps1' = 12
        'tests/Unit/Public/Get-OERSubscription.Tests.ps1' = 6
        'tests/Unit/Public/Invoke-OERAccessReviewInstanceDecision.Tests.ps1' = 2
        'tests/Unit/Public/Invoke-OERStructure.Tests.ps1' = 6
        'tests/Unit/Public/New-OERAccessPackage.Tests.ps1' = 13
        'tests/Unit/Public/New-OERAccessPackageAssignment.Tests.ps1' = 5
        'tests/Unit/Public/New-OERAccessPackageAssignmentPolicy.Tests.ps1' = 6
        'tests/Unit/Public/New-OERAdministrativeUnit.Tests.ps1' = 6
        'tests/Unit/Public/New-OERCatalog.Tests.ps1' = 7
        'tests/Unit/Public/New-OEREligibleRoleAssignment.Tests.ps1' = 1
        'tests/Unit/Public/New-OERGroup.Tests.ps1' = 16
        'tests/Unit/Public/New-OERRoleAssignment.Tests.ps1' = 2
        'tests/Unit/Public/Remove-OERAccessPackageAssignment.Tests.ps1' = 3
        'tests/Unit/Public/Remove-OERAccessReviewDefinition.Tests.ps1' = 22
        'tests/Unit/Public/Remove-OERActiveDirectoryRoleAssignment.Tests.ps1' = 4
        'tests/Unit/Public/Remove-OERAdministrativeUnit.Tests.ps1' = 1
        'tests/Unit/Public/Remove-OERAdministrativeUnitMember.Tests.ps1' = 2
        'tests/Unit/Public/Remove-OERAdministrativeUnitScopedRole.Tests.ps1' = 25
        'tests/Unit/Public/Remove-OERCatalogResource.Tests.ps1' = 7
        'tests/Unit/Public/Remove-OEREligibleDirectoryRoleAssignment.Tests.ps1' = 4
        'tests/Unit/Public/Remove-OERGroupEligibility.Tests.ps1' = 1
        'tests/Unit/Public/Set-OERAccessPackage.Tests.ps1' = 6
        'tests/Unit/Public/Set-OERAccessPackageAssignmentPolicy.Tests.ps1' = 44
        'tests/Unit/Public/Set-OERAccessReviewDefinition.Tests.ps1' = 2
        'tests/Unit/Public/Set-OERAdministrativeUnit.Tests.ps1' = 10
        'tests/Unit/Public/Set-OERCatalog.Tests.ps1' = 1
        'tests/Unit/Public/Set-OERDirectoryRoleManagementPolicy.Tests.ps1' = 7
        'tests/Unit/Public/Set-OERGroup.Tests.ps1' = 22
        'tests/Unit/Public/Set-OERGroupPimPolicy.Tests.ps1' = 13
        'tests/Unit/Public/Set-OERResourceGroup.Tests.ps1' = 2
        'tests/Unit/Public/Set-OERRoleManagementPolicy.Tests.ps1' = 25
        'tests/Unit/Public/Stop-OERAccessReviewInstance.Tests.ps1' = 1
    }
}

Describe 'Unit test hygiene' -Tags 'TestHygiene' {
    It 'Should install, check and uninstall the transport tripwire in every unit test file that imports the module' {
        $UnitRoot = Join-Path -Path $script:ProjectPath -ChildPath 'tests/Unit'
        $Files = @(Get-ChildItem -Path $UnitRoot -Recurse -Filter '*.Tests.ps1' -File)
        $Files.Count | Should -BeGreaterThan 0 -Because 'the gate must measure at least one unit test file; zero files means the enumeration failed and the check ran on nothing'

        $ExemptPresent = @($script:TripwireExempt | Where-Object { Test-Path -LiteralPath (Join-Path -Path $script:ProjectPath -ChildPath $_) })
        $Hits = [System.Collections.Generic.List[string]]::new()
        $Checked = 0
        foreach ($File in $Files) {
            $Relative = [System.IO.Path]::GetRelativePath($script:ProjectPath, $File.FullName).Replace('\', '/')
            if ($script:TripwireExempt -contains $Relative) { continue }
            $Checked++
            foreach ($Reason in @(Get-TestHygieneTripwireFinding -Text ([System.IO.File]::ReadAllText($File.FullName)))) {
                $Hits.Add(('{0}: {1}' -f $Relative, $Reason))
            }
        }

        $Checked | Should -Be ($Files.Count - $ExemptPresent.Count) -Because 'every unit test file outside the named exemptions must be checked; a different count means a file was skipped without being named'
        @($Hits).Count | Should -Be 0 -Because ('every unit test file that imports the module must dot-source tests/Unit/TestHelpers/OERTransportTripwire.ps1 and call Install-OERTransportTripwire in its root BeforeAll after Import-Module, and end with a root AfterAll {{ try {{ Assert-OERTransportTripwire }} finally {{ Uninstall-OERTransportTripwire }} }}; zero means every file does. Files that do not: {0}' -f ($Hits -join '; '))
    }

    It 'Should exempt only unit test files that import nothing' {
        # Known answer. A check edited into one that never fires leaves every exempt file green, so
        # a fixed sample proves it still refuses each shape: lines 1 to 5 of the second sample are
        # refused, and a Get-Command by name, the last line, is not.
        $Clean = @'
Describe 'x' {
    It 'y' {
        Get-ChildItem -Path $PSScriptRoot | Should -Not -BeNullOrEmpty
        Get-Command -Name Get-ChildItem | Should -Not -BeNullOrEmpty
    }
}
'@
        $Loading = @'
Import-Module Omnicit.EntraRBAC
InModuleScope Omnicit.EntraRBAC { 1 }
Get-OERGroup -Group 'x'
Get-Command -Module Omnicit.EntraRBAC
Get-Command -PSSnapin Omnicit.EntraRBAC
Get-Command -Name Get-ChildItem
'@
        @(Get-TestHygieneExemptFinding -Ast ([System.Management.Automation.Language.Parser]::ParseInput($Clean, [ref]$null, [ref]$null))).Count |
            Should -Be 0 -Because 'a file that imports nothing must produce no finding, or every exemption would fail'
        @(Get-TestHygieneExemptFinding -Ast ([System.Management.Automation.Language.Parser]::ParseInput($Loading, [ref]$null, [ref]$null))) |
            Should -Be @('line 1: Import-Module', 'line 2: InModuleScope', 'line 3: Get-OERGroup', 'line 4: Get-Command', 'line 5: Get-Command') -Because 'each way to import or run module code must be refused, and a Get-Command by name must not be'

        @($script:TripwireExempt).Count | Should -BeGreaterThan 0 -Because 'the exemption list is named on purpose; an empty list means this check measures nothing'
        foreach ($Relative in $script:TripwireExempt) {
            $Path = Join-Path -Path $script:ProjectPath -ChildPath $Relative
            Test-Path -LiteralPath $Path | Should -BeTrue -Because ('an exemption must name a file that exists, or it silently exempts nothing: {0}' -f $Relative)
            $Ast = [System.Management.Automation.Language.Parser]::ParseFile($Path, [ref]$null, [ref]$null)
            $Findings = @(Get-TestHygieneExemptFinding -Ast $Ast)
            $Findings.Count | Should -Be 0 -Because ('an exempt file must import nothing, call no Verb-OER* command and run no Get-Command -Module, so no module code can run in it; one that does must install the tripwire instead: {0}: {1}' -f $Relative, ($Findings -join '; '))
        }
    }

    It 'Should tell a file that wires the tripwire from one that does not (known answer)' {
        $Correct = @'
BeforeAll {
    Import-Module Omnicit.EntraRBAC -Force
    . "$PSScriptRoot/x.ps1"
    Install-OERTransportTripwire
}

AfterAll {
    try { Assert-OERTransportTripwire } finally { Uninstall-OERTransportTripwire }
}

Describe 'x' { It 'y' { 1 | Should -Be 1 } }
'@
        $NoInstall = @'
BeforeAll {
    Import-Module Omnicit.EntraRBAC -Force
    . "$PSScriptRoot/x.ps1"
}

AfterAll {
    try { Assert-OERTransportTripwire } finally { Uninstall-OERTransportTripwire }
}

Describe 'x' { It 'y' { 1 | Should -Be 1 } }
'@
        $InstallFirst = @'
BeforeAll {
    . "$PSScriptRoot/x.ps1"
    Install-OERTransportTripwire
    Import-Module Omnicit.EntraRBAC -Force
}

AfterAll {
    try { Assert-OERTransportTripwire } finally { Uninstall-OERTransportTripwire }
}

Describe 'x' { It 'y' { 1 | Should -Be 1 } }
'@
        $NoAfterAll = @'
BeforeAll {
    Import-Module Omnicit.EntraRBAC -Force
    . "$PSScriptRoot/x.ps1"
    Install-OERTransportTripwire
}

Describe 'x' { It 'y' { 1 | Should -Be 1 } }
'@
        $NoTryFinally = @'
BeforeAll {
    Import-Module Omnicit.EntraRBAC -Force
    . "$PSScriptRoot/x.ps1"
    Install-OERTransportTripwire
}

AfterAll {
    Assert-OERTransportTripwire
    Uninstall-OERTransportTripwire
}

Describe 'x' { It 'y' { 1 | Should -Be 1 } }
'@
        # An empty catch swallows the assert's throw, so the file stays green whatever was reached.
        $CatchSwallows = @'
BeforeAll {
    Import-Module Omnicit.EntraRBAC -Force
    . "$PSScriptRoot/x.ps1"
    Install-OERTransportTripwire
}

AfterAll {
    try { Assert-OERTransportTripwire } catch { } finally { Uninstall-OERTransportTripwire }
}

Describe 'x' { It 'y' { 1 | Should -Be 1 } }
'@
        $AfterAllReason = 'root AfterAll does not call Assert-OERTransportTripwire inside a try with no catch whose finally calls Uninstall-OERTransportTripwire'
        @(Get-TestHygieneTripwireFinding -Text $Correct).Count | Should -Be 0 -Because 'a correctly wired file must produce no finding, or the gate would fail every file'
        @(Get-TestHygieneTripwireFinding -Text $NoInstall) | Should -Be @('root BeforeAll does not call Install-OERTransportTripwire')
        @(Get-TestHygieneTripwireFinding -Text $InstallFirst) | Should -Be @('root BeforeAll calls Install-OERTransportTripwire before Import-Module')
        @(Get-TestHygieneTripwireFinding -Text $NoAfterAll) | Should -Be @('no root AfterAll')
        @(Get-TestHygieneTripwireFinding -Text $NoTryFinally) | Should -Be @($AfterAllReason)
        @(Get-TestHygieneTripwireFinding -Text $CatchSwallows) | Should -Be @($AfterAllReason)
    }

    It 'Should hold a default mock beside every filtered mock, with no new violation (ratchet)' {
        $UnitRoot = Join-Path -Path $script:ProjectPath -ChildPath 'tests/Unit'
        $Files = @(Get-ChildItem -Path $UnitRoot -Recurse -Filter '*.Tests.ps1' -File)
        $Files.Count | Should -BeGreaterThan 0 -Because 'the gate must measure at least one unit test file; zero files means the enumeration failed and the check ran on nothing'

        $Counts = [ordered]@{}
        $Filtered = 0
        $Unresolvable = [System.Collections.Generic.List[string]]::new()
        foreach ($File in $Files) {
            $Relative = [System.IO.Path]::GetRelativePath($script:ProjectPath, $File.FullName).Replace('\', '/')
            $Violations = 0
            $Text = [System.IO.File]::ReadAllText($File.FullName)
            if ($Text -notmatch 'ParameterFilter') { continue }
            foreach ($Finding in @(Get-TestHygieneMockDefaultFinding -Text $Text)) {
                $Filtered++
                if ($Finding.Kind -eq 'Unresolvable') {
                    $Unresolvable.Add(('{0}:{1}' -f $Relative, $Finding.Line))
                } elseif ($Finding.Kind -ne 'Covered') {
                    $Violations++
                }
            }
            if ($Violations -gt 0) { $Counts[$Relative] = $Violations }
        }
        $Filtered | Should -BeGreaterThan 0 -Because 'the unit suite holds filtered mocks; zero means the scan read nothing'

        $Differences = [System.Collections.Generic.List[string]]::new()
        foreach ($Relative in $Counts.Keys) {
            $Allowed = if ($script:MockDefaultRatchet.Contains($Relative)) { [int]$script:MockDefaultRatchet[$Relative] } else { 0 }
            if ($Counts[$Relative] -ne $Allowed) {
                $Differences.Add(('{0}: {1} found, {2} in the table' -f $Relative, $Counts[$Relative], $Allowed))
            }
        }
        foreach ($Relative in $script:MockDefaultRatchet.Keys) {
            if (-not $Counts.Contains($Relative)) {
                $Differences.Add(('{0}: 0 found, {1} in the table' -f $Relative, $script:MockDefaultRatchet[$Relative]))
            }
        }

        $Sum = 0
        foreach ($Value in $Counts.Values) { $Sum += $Value }
        @($Differences).Count | Should -Be 0 -Because ('every Mock that carries -ParameterFilter needs a Mock of the same command and -ModuleName without one in the same script block, so a call the filters stop matching falls back to it; a higher count is a new violation (add the default mock), a lower one a fixed site (lower the number in the table in the same change). Found {0} violations in {1} files of {2} scanned, {3} filtered mocks, {4} with a command that is not a literal and so not checked. Differences: {5}' -f $Sum, $Counts.Count, $Files.Count, $Filtered, $Unresolvable.Count, ($Differences -join '; '))
    }

    It 'Should keep the default-mock ratchet table sorted, with every entry a unit test file and a positive count' {
        $Keys = @($script:MockDefaultRatchet.Keys)
        $Keys.Count | Should -BeGreaterThan 0 -Because 'the table holds the sites that predate the rule; an empty table means it was lost'
        $Sorted = [string[]]$Keys.Clone()
        [System.Array]::Sort($Sorted, [System.StringComparer]::Ordinal)
        ($Keys -join '; ') | Should -Be ($Sorted -join '; ') -Because 'the table is kept sorted by path (ordinal), so a merge conflict or a duplicate is visible'
        foreach ($Relative in $Keys) {
            Test-Path -LiteralPath (Join-Path -Path $script:ProjectPath -ChildPath $Relative) | Should -BeTrue -Because ('a table entry must name a unit test file that exists: {0}' -f $Relative)
            $Relative | Should -Match '^tests/Unit/.+\.Tests\.ps1$'
            $script:MockDefaultRatchet[$Relative] | Should -BeGreaterThan 0 -Because ('a count of zero is not an entry, so delete the line: {0}' -f $Relative)
        }
    }

    It 'Should tell a filtered mock with a default beside it from one without (known answer)' {
        $Violations = {
            param([string]$Text)
            @(Get-TestHygieneMockDefaultFinding -Text $Text | Where-Object { $_.Kind -eq 'Violation' }).Count
        }
        $WithDefault = @'
Describe 'x' {
    It 'y' {
        Mock -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest { 1 } -ParameterFilter { $Uri -eq 'a' }
        Mock -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest { 2 }
    }
}
'@
        $FilteredOnly = @'
Describe 'x' {
    It 'y' {
        Mock -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest { 1 } -ParameterFilter { $Uri -eq 'a' }
    }
}
'@
        $EnclosingOnly = @'
Describe 'x' {
    BeforeAll {
        Mock -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest { 2 }
    }
    It 'y' {
        Mock -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest { 1 } -ParameterFilter { $Uri -eq 'a' }
    }
}
'@
        $NestedOnly = @'
Describe 'x' {
    It 'y' {
        Mock -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest { 1 } -ParameterFilter { $Uri -eq 'a' }
        & {
            Mock -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest { 2 }
        }
    }
}
'@
        $OtherModule = @'
Describe 'x' {
    It 'y' {
        Mock -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest { 1 } -ParameterFilter { $Uri -eq 'a' }
        Mock -ModuleName Other.Module Invoke-OERGraphRequest { 2 }
    }
}
'@
        $NoModuleOnDefault = @'
Describe 'x' {
    It 'y' {
        Mock -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest { 1 } -ParameterFilter { $Uri -eq 'a' }
        Mock Invoke-OERGraphRequest { 2 }
    }
}
'@
        $OtherCommand = @'
Describe 'x' {
    It 'y' {
        Mock Invoke-OERGraphRequest { 1 } -ParameterFilter { $Uri -eq 'a' }
        Mock Invoke-OERArmRequest { 2 }
    }
}
'@
        $Named = @'
Describe 'x' {
    It 'y' {
        Mock -CommandName Invoke-OERGraphRequest -ModuleName Omnicit.EntraRBAC -MockWith { 1 } -ParameterFilter { $Uri -eq 'a' }
        Mock -CommandName 'Invoke-OERGraphRequest' -ModuleName 'Omnicit.EntraRBAC' -MockWith { 2 }
    }
}
'@
        $NamedFilteredOnly = @'
Describe 'x' {
    It 'y' {
        Mock -CommandName Invoke-OERGraphRequest -ModuleName Omnicit.EntraRBAC -MockWith { 1 } -ParameterFilter { $Uri -eq 'a' }
    }
}
'@
        $InsideIf = @'
Describe 'x' {
    It 'y' {
        Mock Invoke-OERGraphRequest { 1 } -ParameterFilter { $Uri -eq 'a' }
        if ($true) { Mock Invoke-OERGraphRequest { 2 } }
    }
}
'@
        $TwoFiltered = @'
Describe 'x' {
    It 'y' {
        Mock Invoke-OERGraphRequest { 1 } -ParameterFilter { $Uri -eq 'a' }
        Mock Invoke-OERGraphRequest { 2 } -ParameterFilter { $Uri -eq 'b' }
    }
}
'@
        $Unfiltered = @'
Describe 'x' {
    It 'y' {
        Mock Invoke-OERGraphRequest { 1 }
        Should -Invoke Invoke-OERGraphRequest -Times 1 -Exactly -ParameterFilter { $Uri -eq 'a' }
    }
}
'@
        $Variable = @'
Describe 'x' {
    It 'y' {
        $Name = 'Invoke-OERGraphRequest'
        Mock $Name { 1 } -ParameterFilter { $Uri -eq 'a' }
    }
}
'@

        & $Violations $WithDefault | Should -Be 0 -Because 'a filtered mock with a default beside it in the same block is covered'
        & $Violations $FilteredOnly | Should -Be 1 -Because 'a filtered mock alone has nothing to fall back to'
        & $Violations $EnclosingOnly | Should -Be 1 -Because 'a default in an enclosing block only does not count: the rule is the same block'
        & $Violations $NestedOnly | Should -Be 1 -Because 'a default in a nested block does not count either'
        & $Violations $OtherModule | Should -Be 1 -Because 'a default for another -ModuleName is another mock'
        & $Violations $NoModuleOnDefault | Should -Be 1 -Because 'a default with no -ModuleName beside a filtered mock with one is another mock'
        & $Violations $OtherCommand | Should -Be 1 -Because 'a default for another command does not cover it'
        & $Violations $Named | Should -Be 0 -Because 'the -CommandName and -MockWith named form is read like the positional one'
        & $Violations $NamedFilteredOnly | Should -Be 1 -Because 'the -CommandName named form is recognised as a filtered mock'
        & $Violations $InsideIf | Should -Be 0 -Because 'a default inside an if of the same block is in the block'
        & $Violations $TwoFiltered | Should -Be 2 -Because 'two filtered mocks and no default are two violations'
        & $Violations $Unfiltered | Should -Be 0 -Because 'a Should -Invoke filter and an unfiltered mock are no filtered Mock'

        # A command that is not a literal cannot be matched by name: reported, never a violation.
        $Found = @(Get-TestHygieneMockDefaultFinding -Text $Variable)
        $Found.Count | Should -Be 1
        $Found[0].Kind | Should -Be 'Unresolvable' -Because 'a Mock of a variable command cannot be matched by name, so it is reported apart and not counted'
        @(Get-TestHygieneMockDefaultFinding -Text 'Describe "x" {').Kind | Should -Be @('Unparsable') -Because 'text that does not parse is reported, which the ratchet counts as a violation'
    }
}
