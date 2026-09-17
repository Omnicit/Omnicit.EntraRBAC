BeforeDiscovery {
    $projectPath = "$($PSScriptRoot)\..\.." | Convert-Path

    <#
        If the QA tests are run outside of the build script (e.g with Invoke-Pester)
        the parent scope has not set the variable $ProjectName.
    #>
    if (-not $ProjectName)
    {
        # Assuming project folder name is project name.
        $ProjectName = Get-SamplerProjectName -BuildRoot $projectPath
    }

    $script:moduleName = $ProjectName

    Remove-Module -Name $script:moduleName -Force -ErrorAction SilentlyContinue

    $mut = Get-Module -Name $script:moduleName -ListAvailable |
        Select-Object -First 1 |
            Import-Module -Force -ErrorAction Stop -PassThru
}

BeforeAll {
    # Convert-Path required for PS7 or Join-Path fails
    $projectPath = "$($PSScriptRoot)\..\.." | Convert-Path
    # Get git-related project path. This is relevant for modules that will not be deployed in the root folder of Git.
    $gitTopLevelPath = (&git rev-parse --show-toplevel)
    $gitRelatedModulePath = (($projectPath -replace [regex]::Escape([IO.Path]::DirectorySeparatorChar), '/') -replace $gitTopLevelPath, '')
    if (-not [string]::IsNullOrEmpty($gitRelatedModulePath)) { $gitRelatedModulePath = $gitRelatedModulePath.Trim('/')  + '/' }
    $escapedGitRelatedModulePath = [regex]::Escape($gitRelatedModulePath)

    <#
        If the QA tests are run outside of the build script (e.g with Invoke-Pester)
        the parent scope has not set the variable $ProjectName.
    #>
    if (-not $ProjectName)
    {
        # Assuming project folder name is project name.
        $ProjectName = Get-SamplerProjectName -BuildRoot $projectPath
    }

    $script:moduleName = $ProjectName

    $sourcePath = (
        Get-ChildItem -Path $projectPath\*\*.psd1 |
            Where-Object -FilterScript {
                ($_.Directory.Name -match 'source|src' -or $_.Directory.Name -eq $_.BaseName) `
                    -and $(
                    try
                    {
                        Test-ModuleManifest -Path $_.FullName -ErrorAction Stop
                    }
                    catch
                    {
                        $false
                    }
                )
            }
    ).Directory.FullName

    <#
        The module under test, re-resolved for the RUN phase. The $mut set by the BeforeDiscovery
        at the top of this file lives in Pester's DISCOVERY session state; the two BeforeDiscovery
        blocks below can read it, but an It cannot. The release gates in this file need the built
        artefact at run time, so resolve it again here exactly the way discovery does --
        Get-Module -ListAvailable, first match -- which under ./build.ps1 -Tasks test is the BUILT
        module, i.e. ModuleBase output/module/<name>/<version>/ and Version the computed
        ModuleVersion.
    #>
    $script:moduleUnderTest = Get-Module -Name $script:moduleName -ListAvailable |
        Select-Object -First 1
}

Describe 'Changelog Management' -Tag 'Changelog' {
    It 'Changelog has been updated' -Skip:(
        -not ([bool](Get-Command git -ErrorAction SilentlyContinue) -and
            [bool](&(Get-Process -Id $PID).Path -NoProfile -Command 'git rev-parse --is-inside-work-tree 2>$null'))
    ) {
        <#
            Get the list of changed files compared with branch main to verify
            that required files are changed.
        #>

        $filesChanged = @()
        # Only run if there is a remote called origin
        if (((git remote) -match 'origin'))
        {
            $headCommit = &git rev-parse HEAD
            $defaultBranchCommit = &git rev-parse origin/main
            $filesChanged += (&git @('diff', "$defaultBranchCommit...$headCommit", '--name-only') |
                Where-Object { $_ -match "^$escapedGitRelatedModulePath" }) -replace "^$escapedGitRelatedModulePath", ""
        }

        $filesStagedAndUnstaged = (&git @('diff', 'HEAD', '--name-only') 2>&1 |
            Where-Object { $_ -match "^$escapedGitRelatedModulePath" }) -replace "^$escapedGitRelatedModulePath", ""

        $filesChanged += $filesStagedAndUnstaged

        <#
            Only require a changelog entry when the SHIPPED module changed. The paths above have
            already had the $gitRelatedModulePath prefix stripped and git reports them with forward
            slashes, so a source file is anything matching '^source/'. Per issue #61, and the
            "## CHANGELOG and Version" section of CLAUDE.md: the changelog is a customer-facing
            document, and forcing an entry out of a test-only, QA-only, docs-only or build-only PR
            fills it with noise that no reader of the published release notes can use.
        #>
        $sourceFilesChanged = @($filesChanged | Where-Object { $_ -match '^source/' })

        if ($sourceFilesChanged)
        {
            $filesChanged | Should -Contain 'CHANGELOG.md' -Because (
                'a PR that changes the shipped module documents itself in the CHANGELOG.md ' +
                '[Unreleased] section, while a test-only, QA-only, docs-only or build-only PR does ' +
                "not have to. Changed under source/: $($sourceFilesChanged -join ', ')."
            )
        }
    }

    It 'Changelog format compliant with keepachangelog format' -Skip:(![bool](Get-Command git -EA SilentlyContinue)) {
        { Get-ChangelogData -Path (Join-Path $ProjectPath 'CHANGELOG.md') -ErrorAction Stop } | Should -Not -Throw
    }

    It 'Changelog should have an Unreleased header' {
            (Get-ChangelogData -Path (Join-Path -Path $ProjectPath -ChildPath 'CHANGELOG.md') -ErrorAction Stop).Unreleased | Should -Not -BeNullOrEmpty
    }

    It 'Changelog Unreleased section fits the published ReleaseNotes budget' {
        <#
            The Unreleased section IS the next release's notes: Sampler's
            Create_changelog_release_output task rewrites its heading to '## [<version>] - <date>'
            in output/CHANGELOG.md and copies that section's RawData into the built manifest's
            PrivateData.PSData.ReleaseNotes (release.module.build.ps1:118, 133-140, 182).

            Two-sided on purpose, against opposite failures. The ceiling catches the oversize
            section that issue #39 was about, the one Sampler cuts mid-sentence. The floor catches
            the reverse -- an emptied Unreleased section publishes an empty release note, and a
            bare ceiling check cannot see that, because a short length is less than any ceiling.
            Neither assertion is redundant and neither is inert.
        #>
        $changelogPath = Join-Path -Path $ProjectPath -ChildPath 'CHANGELOG.md'
        $unreleased = (Get-ChangelogData -Path $changelogPath -ErrorAction Stop).Unreleased

        $unreleased.RawData | Should -Not -BeNullOrEmpty -Because 'a null Unreleased section would make the length check below read 0 and pass silently: $null.Length is the integer 0, not $null'

        $unreleasedLength = $unreleased.RawData.Length

        $unreleasedLength | Should -BeGreaterOrEqual 500 -Because (
            'the Unreleased section is published verbatim as the release notes, so it must always ' +
            'carry a usable summary of what this version is. A near-empty section ships a release ' +
            'with no usable notes -- the same outcome as the issue #39 truncation, reached from the ' +
            'opposite direction -- and a ceiling check on its own cannot see it, since a short ' +
            "length satisfies any upper bound. It is currently $unreleasedLength characters."
        )

        $unreleasedLength | Should -BeLessOrEqual 4000 -Because (
            '4,000 characters is the working budget for a release-note summary: enough for what ' +
            'changed and why, short enough that the PowerShell Gallery description stays readable. ' +
            "It is currently $unreleasedLength characters. Sampler's hard truncation at 10,000 " +
            '(release.module.build.ps1:133-140) is the backstop that silently cuts the note ' +
            'mid-sentence, not the budget -- do not treat the gap between the two as headroom. ' +
            'Note the measurement here reads SHORT of the published article: RawData includes the ' +
            "15-character '## [Unreleased]' heading, while the published section carries the " +
            "longer '## [<version>] - <date>' form (29 characters for '## [0.8.0-chore] - " +
            "2026-08-28', so about 14 characters more, and more again for a longer version or " +
            'prerelease label). Per-PR detail does not belong here: close finished work under a ' +
            "dated '## [<version>] - <date>' section, or leave it in the PR body -- see CLAUDE.md " +
            '-- but never convert the Unreleased heading by hand: Sampler does that at build ' +
            'time, and a hand-converted section leaves Unreleased empty.'
        )
    }

    It 'Built manifest ReleaseNotes is populated and not truncated' {
        <#
            Issue #61 AC 4. The two checks above measure the SOURCE side; this one measures what
            actually reached the shipped artefact, which is the only thing a Gallery consumer ever
            sees. It reads the BUILT manifest -- $moduleUnderTest.ModuleBase is
            output/module/<name>/<version>/ -- because that is where Sampler's Update-Manifest
            writes PrivateData.PSData.ReleaseNotes (release.module.build.ps1:182).

            Because it compares the built artefact against the current CHANGELOG.md, a stale
            output/module/ trips it too. That is deliberate: a stale build is exactly the state in
            which the source-side gates above are green while the published note is wrong. Rebuild
            with ./build.ps1 -Tasks build.
        #>
        $script:moduleUnderTest | Should -Not -BeNullOrEmpty -Because (
            "the module '$($script:moduleName)' must resolve from PSModulePath for the release " +
            'gates to have anything to measure; run ./build.ps1 -Tasks build first.'
        )

        $builtManifestPath = Join-Path -Path $script:moduleUnderTest.ModuleBase -ChildPath "$($script:moduleName).psd1"

        Test-Path -Path $builtManifestPath | Should -BeTrue -Because (
            "the manifest '$builtManifestPath' must exist; run ./build.ps1 -Tasks build first."
        )

        $builtManifest = Import-PowerShellDataFile -Path $builtManifestPath
        $psData = $builtManifest.PrivateData.PSData

        $psData | Should -Not -BeNullOrEmpty -Because (
            "'$builtManifestPath' has no PrivateData.PSData block, so it cannot be the built " +
            'manifest; run ./build.ps1 -Tasks build first.'
        )

        $psData.Keys | Should -Contain 'ReleaseNotes' -Because (
            "'$builtManifestPath' carries no PrivateData.PSData.ReleaseNotes key at all, so the " +
            'module under test is not a built module; run ./build.ps1 -Tasks build first.'
        )

        $releaseNotes = $psData.ReleaseNotes

        $releaseNotes | Should -Not -BeNullOrEmpty -Because (
            'an empty PrivateData.PSData.ReleaseNotes means Sampler Create_changelog_release_output ' +
            'found nothing to publish -- a release shipped with no notes at all, the same outcome ' +
            'as the issue #39 truncation reached from the opposite direction. The source manifest ' +
            "ships ReleaseNotes = '' as a placeholder and the build fills it in, so an empty value " +
            'here is a real build failure, never a reason to skip.'
        )

        $releaseNotes.Length | Should -BeGreaterOrEqual 500 -Because (
            'the published release notes must carry a usable summary, matching the floor the ' +
            "Unreleased section is held to above. They are currently $($releaseNotes.Length) " +
            'characters. A stale artefact reaches this assertion too, so if the current ' +
            'CHANGELOG.md Unreleased section is longer than that, run ./build.ps1 -Tasks build ' +
            'first and re-measure.'
        )

        $releaseNotes.Length | Should -BeLessThan 10000 -Because (
            'Sampler truncates with .Substring(0, 10000) (release.module.build.ps1:133-140), so a ' +
            'length of exactly 10,000 is the signature of a note that was cut, not a note that ' +
            "happened to fit. They are currently $($releaseNotes.Length) characters."
        )

        <#
            Length alone cannot see a cut that lands under 10,000 (a shorter cap, a different
            Sampler, a hand-edited manifest), so prove the published note still ENDS where the
            source section ends. Update-Changelog -LinkMode none rewrites only the heading, so
            everything after it is byte-identical: measured on this branch the longest common
            suffix is 1688 characters, which is the whole Unreleased body. 400 is a safe sample --
            the 500-character floor above leaves at least 485 characters of body after the
            15-character '## [Unreleased]' heading -- and the guards below turn a shorter section
            into a readable assertion failure instead of a Substring exception.
        #>
        $sourceUnreleased = (Get-ChangelogData -Path (Join-Path -Path $ProjectPath -ChildPath 'CHANGELOG.md') -ErrorAction Stop).Unreleased.RawData

        $sourceUnreleased | Should -Not -BeNullOrEmpty -Because 'the tail comparison below needs a source section to compare against'

        $publishedTail = $releaseNotes.TrimEnd()
        $sourceTail = $sourceUnreleased.TrimEnd()
        $tailLength = 400

        $publishedTail.Length | Should -BeGreaterOrEqual $tailLength -Because 'the published release notes are too short to sample a tail from; the floor assertion above explains why that is a defect'
        $sourceTail.Length | Should -BeGreaterOrEqual $tailLength -Because 'the source Unreleased section is too short to sample a tail from; the floor assertion above explains why that is a defect'

        $publishedTail.Substring($publishedTail.Length - $tailLength) |
            Should -BeExactly $sourceTail.Substring($sourceTail.Length - $tailLength) -Because (
                'the published release notes must end where the CHANGELOG.md Unreleased section ' +
                'ends. Update-Changelog -LinkMode none changes only the heading, so the last ' +
                "$tailLength characters are identical unless the value was cut short -- which is " +
                'the issue #39 defect. If this fails and the note looks complete, output/module/ ' +
                'is stale: rebuild with ./build.ps1 -Tasks build.'
            )
    }
}

<#
    The 'Changelog' tag is shared with the changelog Describe above ON PURPOSE, not by accident.
    Check 3.3 in docs/live-verification/chore-version-cap-and-changelog-budget-checklist.md
    falsifies the cap with -TagFilter Changelog, which selects both Describes and would miss this
    one entirely if the tag were dropped or renamed here. The same coupling runs the other way: an
    ExcludeTag: Changelog added to build.yaml to quieten the changelog suite would silently take
    the version cap with it, and the gate would go green with nothing holding the cap at all.
#>
Describe 'Release version cap' -Tags 'Changelog' {
    It 'Should build a version in the 1.x line' {
        <#
            Issue #55 AC 3, lifted by issue #62 on 2026-09-13: the first public release is 1.0.0.
            Read from the module under test rather than by re-running GitVersion: what matters is
            the version that was actually stamped into the artefact, whatever produced it.
        #>
        $script:moduleUnderTest | Should -Not -BeNullOrEmpty -Because (
            "the module '$($script:moduleName)' must resolve from PSModulePath for this gate to " +
            'have a version to measure; run ./build.ps1 -Tasks build first.'
        )

        $builtVersion = $script:moduleUnderTest.Version

        <#
            Guard the guard. $null -lt [version]'2.0.0' evaluates to $true in PowerShell, so an
            unresolved version would sail through the upper bound below, and the gate would assert
            only half of what it claims.
        #>
        $builtVersion | Should -Not -BeNullOrEmpty -Because 'a null version would satisfy the -BeLessThan comparison below and make this gate inert'
        $builtVersion | Should -BeOfType [System.Version] -Because 'the comparisons below must be version comparisons, not string ones: as strings "10.0.0" sorts before "2.0.0"'

        $builtVersion | Should -BeGreaterOrEqual ([System.Version]'1.0.0') -Because (
            "the module built $builtVersion. The first public release is 1.0.0 (issue #62), and " +
            "GitVersion.yml's next-version supplies that base. A version below it means the " +
            'version pipeline did not run -- with no ModuleVersion and no GitVersion, Sampler falls ' +
            "back to the source manifest's placeholder 0.0.1 -- or next-version was lowered again. " +
            'Fix the pipeline; do not lower this bound to make a build pass.'
        )

        $builtVersion | Should -BeLessThan ([System.Version]'2.0.0') -Because (
            "the module built $builtVersion. A move to 2.0.0 is a release decision, not something " +
            "a commit message may make on its own: GitVersion.yml's major-version-bump-message is " +
            "live again for '+semver: major', and this bound stops such a commit from shipping " +
            '2.0.0 unnoticed. When 2.0.0 is called, raise it together with next-version -- never ' +
            'the assertion alone, and never merely to make a build pass.'
        )
    }
}

Describe 'General module control' -Tags 'FunctionalQuality' {
    It 'Should import without errors' {
        { Import-Module -Name $script:moduleName -Force -ErrorAction Stop } | Should -Not -Throw

        Get-Module -Name $script:moduleName | Should -Not -BeNullOrEmpty
    }

    It 'Should remove without error' {
        { Remove-Module -Name $script:moduleName -ErrorAction Stop } | Should -Not -Throw

        Get-Module $script:moduleName | Should -BeNullOrEmpty
    }
}

BeforeDiscovery {
    # Must use the imported module to build test cases.
    $allModuleFunctions = & $mut { Get-Command -Module $args[0] -CommandType Function } $script:moduleName

    # Build test cases.
    $testCases = @()

    foreach ($function in $allModuleFunctions)
    {
        $testCases += @{
            Name = $function.Name
        }
    }
}

Describe 'Quality for module' -Tags 'TestQuality' {
    BeforeDiscovery {
        if (Get-Command -Name Invoke-ScriptAnalyzer -ErrorAction SilentlyContinue)
        {
            $scriptAnalyzerRules = Get-ScriptAnalyzerRule
        }
        else
        {
            if ($ErrorActionPreference -ne 'Stop')
            {
                Write-Warning -Message 'ScriptAnalyzer not found!'
            }
            else
            {
                throw 'ScriptAnalyzer not found!'
            }
        }

        <#
            Task 8g's OutputType gate is scoped to EXPORTED functions only, not $testCases (every
            module function, private helpers included -- correct for the two unit-test/analyzer
            checks below, which is why they stay on $testCases unchanged). CLAUDE.md's OutputType
            rule is scoped to "every function that returns type-tagged objects", and the 8g audit
            that computed the eleven-cmdlet gap explicitly counted only source/Public/*.ps1 (89
            files) -- a private helper was never in scope and must not start failing this gate
            retroactively. $testCases is filtered rather than re-derived from Get-Command, so this
            can never drift from the set the two existing Its already validated against.

            The export list itself comes from $mut.ExportedFunctions (the already-imported module
            from the top-level BeforeDiscovery above, not a second manifest read) -- the module
            system's own resolved FunctionsToExport, exactly what the top of this file already
            trusts to build $allModuleFunctions. Fix round 1, M-4: an earlier version of this block
            re-read the manifest via a hardcoded 'source' path, while this same file's BeforeAll
            (below, RUN phase) discovers that folder dynamically by asking Test-ModuleManifest which
            candidate under $projectPath\*\*.psd1 actually validates -- duplicating the "source"
            literal here would drift the moment that folder is ever renamed. $mut.ExportedFunctions
            sidesteps needing either path at all. Verified empirically: 89 keys, contains
            'Connect-OER', does not contain the private 'Export-OERConfiguration'.
        #>
        $exportedFunctionNames = [System.Collections.Generic.HashSet[string]]::new(
            [string[]]$mut.ExportedFunctions.Keys, [System.StringComparer]::OrdinalIgnoreCase)
        $exportedTestCases = @($testCases | Where-Object { $exportedFunctionNames.Contains($_.Name) })
    }

    It 'Should have a unit test for <Name>' -ForEach $testCases {
        Get-ChildItem -Path 'tests\' -Recurse -Include "$Name.Tests.ps1" | Should -Not -BeNullOrEmpty
    }

    It 'Should pass Script Analyzer for <Name>' -ForEach $testCases -Skip:(-not $scriptAnalyzerRules) {
        $functionFile = Get-ChildItem -Path $sourcePath -Recurse -Include "$Name.ps1"

        $pssaResult = (Invoke-ScriptAnalyzer -Path $functionFile.FullName)
        $report = $pssaResult | Format-Table -AutoSize | Out-String -Width 110
        $pssaResult | Should -BeNullOrEmpty -Because `
            "some rule triggered.`r`n`r`n $report"
    }

    It 'Should declare an [OutputType(...)] for <Name>' -ForEach $exportedTestCases {
        <#
            Task 8g: computed over all 89 files in source/Public/, 78 carried [OutputType] (68
            [PSCustomObject], 10 [void]) and 11 carried none -- a de-facto-convention gap, not a
            CLAUDE.md breach (the rule is scoped to functions that return type-tagged objects, and
            none of the 11 do). This gate closes it permanently: every exported function must declare
            [OutputType(...)], either [PSCustomObject] for tagged output or [void] for a cmdlet that
            emits nothing, matching the module's own established convention.

            Attribute detection is AST-based on the PARAM BLOCK's own Attributes collection --
            [CmdletBinding()]/[OutputType()]/[Alias()] preceding param(...) attach there, not to the
            FunctionDefinitionAst -- the same file-per-function lookup the surrounding help tests in
            this Describe already use, so a single parse serves both.
        #>
        $functionFile = Get-ChildItem -Path $sourcePath -Recurse -Include "$Name.ps1"

        $scriptFileRawContent = Get-Content -Raw -Path $functionFile.FullName

        $abstractSyntaxTree = [System.Management.Automation.Language.Parser]::ParseInput($scriptFileRawContent, [ref] $null, [ref] $null)

        $astSearchDelegate = { $args[0] -is [System.Management.Automation.Language.FunctionDefinitionAst] }

        $parsedFunction = $abstractSyntaxTree.FindAll( $astSearchDelegate, $true ) |
            Where-Object -FilterScript {
                $_.Name -eq $Name
            }

        $outputTypeAttribute = @($parsedFunction.Body.ParamBlock.Attributes) |
            Where-Object { $_.TypeName.Name -eq 'OutputType' }

        $outputTypeAttribute | Should -Not -BeNullOrEmpty -Because (
            "$Name must declare [OutputType([PSCustomObject])] or [OutputType([void])] on the line after [CmdletBinding(...)], matching every other exported cmdlet")
    }
}

Describe 'Help for module' -Tags 'helpQuality' {
    It 'Should have .SYNOPSIS for <Name>' -ForEach $testCases {
        $functionFile = Get-ChildItem -Path $sourcePath -Recurse -Include "$Name.ps1"

        $scriptFileRawContent = Get-Content -Raw -Path $functionFile.FullName

        $abstractSyntaxTree = [System.Management.Automation.Language.Parser]::ParseInput($scriptFileRawContent, [ref] $null, [ref] $null)

        $astSearchDelegate = { $args[0] -is [System.Management.Automation.Language.FunctionDefinitionAst] }

        $parsedFunction = $abstractSyntaxTree.FindAll( $astSearchDelegate, $true ) |
            Where-Object -FilterScript {
                $_.Name -eq $Name
            }

        $functionHelp = $parsedFunction.GetHelpContent()

        $functionHelp.Synopsis | Should -Not -BeNullOrEmpty
    }

    It 'Should have a .DESCRIPTION with length greater than 40 characters for <Name>' -ForEach $testCases {
        $functionFile = Get-ChildItem -Path $sourcePath -Recurse -Include "$Name.ps1"

        $scriptFileRawContent = Get-Content -Raw -Path $functionFile.FullName

        $abstractSyntaxTree = [System.Management.Automation.Language.Parser]::ParseInput($scriptFileRawContent, [ref] $null, [ref] $null)

        $astSearchDelegate = { $args[0] -is [System.Management.Automation.Language.FunctionDefinitionAst] }

        $parsedFunction = $abstractSyntaxTree.FindAll($astSearchDelegate, $true) |
            Where-Object -FilterScript {
                $_.Name -eq $Name
            }

        $functionHelp = $parsedFunction.GetHelpContent()

        $functionHelp.Description.Length | Should -BeGreaterThan 40
    }

    It 'Should have at least one (1) example for <Name>' -ForEach $testCases {
        $functionFile = Get-ChildItem -Path $sourcePath -Recurse -Include "$Name.ps1"

        $scriptFileRawContent = Get-Content -Raw -Path $functionFile.FullName

        $abstractSyntaxTree = [System.Management.Automation.Language.Parser]::ParseInput($scriptFileRawContent, [ref] $null, [ref] $null)

        $astSearchDelegate = { $args[0] -is [System.Management.Automation.Language.FunctionDefinitionAst] }

        $parsedFunction = $abstractSyntaxTree.FindAll( $astSearchDelegate, $true ) |
            Where-Object -FilterScript {
                $_.Name -eq $Name
            }

        $functionHelp = $parsedFunction.GetHelpContent()

        $Name | Should -Not -BeNullOrEmpty -Because 'the -ForEach test case must carry the function name; a case-shape refactor that drops it would silently make the two assertions below vacuous'
        $functionHelp.Examples.Count | Should -BeGreaterThan 0
        $functionHelp.Examples[0] | Should -Match ([regex]::Escape($Name))
        $functionHelp.Examples[0].Length | Should -BeGreaterThan ($Name.Length + 10)

    }

    It 'Should have described all parameters for <Name>' -ForEach $testCases {
        $functionFile = Get-ChildItem -Path $sourcePath -Recurse -Include "$Name.ps1"

        $scriptFileRawContent = Get-Content -Raw -Path $functionFile.FullName

        $abstractSyntaxTree = [System.Management.Automation.Language.Parser]::ParseInput($scriptFileRawContent, [ref] $null, [ref] $null)

        $astSearchDelegate = { $args[0] -is [System.Management.Automation.Language.FunctionDefinitionAst] }

        $parsedFunction = $abstractSyntaxTree.FindAll( $astSearchDelegate, $true ) |
            Where-Object -FilterScript {
                $_.Name -eq $Name
            }

        $functionHelp = $parsedFunction.GetHelpContent()

        $parameters = $parsedFunction.Body.ParamBlock.Parameters.Name.VariablePath.ForEach({ $_.ToString() })

        foreach ($parameter in $parameters)
        {
            $functionHelp.Parameters.($parameter.ToUpper()) | Should -Not -BeNullOrEmpty -Because ('the parameter {0} must have a description' -f $parameter)
            $functionHelp.Parameters.($parameter.ToUpper()).Length | Should -BeGreaterThan 25 -Because ('the parameter {0} must have descriptive description' -f $parameter)
        }
    }
}


Describe 'README documentation' -Tags 'helpQuality' {
    BeforeAll {
        $script:readmePath = Join-Path -Path $projectPath -ChildPath 'README.md'
        $script:readmeText = Get-Content -Path $script:readmePath -Raw
        $script:exportedNames = (Import-PowerShellDataFile -Path (
                Join-Path -Path $sourcePath -ChildPath "$($script:moduleName).psd1")).FunctionsToExport

        <#
            README explains the auto-authentication behaviour by naming the private helper
            Initialize-OERAuth, which is the only non-exported function it mentions. Allow exactly
            that one rather than every private function, so README cannot start describing an
            internal helper as though it were a public cmdlet.
        #>
        $script:knownNames = $script:exportedNames + 'Initialize-OERAuth'
    }

    It 'Should exist at the repository root' {
        Test-Path -Path $script:readmePath | Should -BeTrue
    }

    It 'Should document every exported cmdlet' {
        $missing = $script:exportedNames | Where-Object {
            $script:readmeText -notmatch ('(?m)\b{0}\b' -f [regex]::Escape($_))
        }

        $missing | Should -BeNullOrEmpty -Because (
            'README.md must name every cmdlet in FunctionsToExport; missing: {0}' -f ($missing -join ', '))
    }

    It 'Should not name a function that does not exist' {
        $named = [regex]::Matches($script:readmeText, '\b[A-Z][a-z]+-OER[A-Za-z]*\b') |
            ForEach-Object { $_.Value } | Sort-Object -Unique
        $named | Should -Not -BeNullOrEmpty -Because 'README.md must name the module cmdlets'

        $unknown = $named | Where-Object { $_ -notin $script:knownNames }

        $unknown | Should -BeNullOrEmpty -Because (
            'every Verb-OER name in README.md must resolve to a real module function; unknown: {0}' -f ($unknown -join ', '))
    }

    It 'Should not use a hardcoded Windows path separator in a PSModulePath example' {
        <#
            The module is Core-only and CI runs Linux and macOS, where the separator is ':'.
            Matching the bare ';$env:PSModulePath' tail catches the concatenated and the
            double-quoted interpolated forms alike; use [IO.Path]::PathSeparator instead.
        #>
        $script:readmeText | Should -Not -Match ';\s*\$env:PSModulePath'
    }
}
