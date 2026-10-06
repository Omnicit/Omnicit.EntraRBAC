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
}
