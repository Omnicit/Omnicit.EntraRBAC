BeforeAll {
    $script:ProjectPath = (Resolve-Path -Path (Join-Path -Path $PSScriptRoot -ChildPath '..\..')).Path

    # =====================================================================================
    # WHY THIS GATE EXISTS.
    #
    # README.md and the about topic say the same things twice, for two audiences: the README for
    # someone looking at the repository, the about topic for someone at a prompt with the module
    # already installed. Until this gate, NOTHING held them against each other. Each had its own
    # check that it names every exported cmdlet -- tests/QA/module.tests.ps1 for the README,
    # tests/QA/about.tests.ps1 for the topic -- and both of those match anywhere in the FILE, so a
    # cmdlet mentioned once in a Quick Start snippet satisfied them while being absent from the
    # roster a reader actually reads.
    #
    # That is the same defect class as the per-cohort scope lines in PR #38: documented, wrong, and
    # complete-looking. The two documents were hand-synchronised twice on the fix/tenant-switch-warning
    # branch alone, which is the point at which a convention stops being a convention.
    #
    # Two bindings, chosen because they are the two places the drift actually happened:
    #
    #   1. THE ROSTER. Every exported cmdlet is rostered in README's '## Available Cmdlets' AND in
    #      the about topic's 'COMMAND COHORTS' -- in those SECTIONS, not merely somewhere in the
    #      file -- and neither roster carries a name the other does not.
    #
    #   2. THE SIGN-IN TYPE VERDICTS. The tenant-switch table says, per sign-in type, what a later
    #      call naming another tenant actually does. It is the most load-bearing shared claim in
    #      either document and the one a reader acts on. Both copies must say the same thing, word
    #      for word once formatting is normalised away.
    #
    # WHAT THIS GATE DOES NOT DO, stated so it is not mistaken for more than it is: it does not bind
    # the prose around either structure. The SOVEREIGN CLOUDS, TENANT PROFILE and PERMISSIONS
    # sections are deliberately rewritten for their medium and are NOT held equal -- measured, they
    # differ from their README counterparts today on purpose. A claim edited in one of those and not
    # the other still passes here.
    # =====================================================================================

    $script:ReadmePath = Join-Path -Path $script:ProjectPath -ChildPath 'README.md'
    $script:AboutPath = Join-Path -Path $script:ProjectPath -ChildPath 'source' |
        Join-Path -ChildPath 'en-US' |
            Join-Path -ChildPath 'about_Omnicit.EntraRBAC.help.txt'
    $script:ManifestPath = Join-Path -Path $script:ProjectPath -ChildPath 'source' |
        Join-Path -ChildPath 'Omnicit.EntraRBAC.psd1'

    $script:ExportedNames = (Import-PowerShellDataFile -Path $script:ManifestPath).FunctionsToExport
    $script:ReadmeLines = [System.IO.File]::ReadAllLines($script:ReadmePath)
    $script:AboutLines = [System.IO.File]::ReadAllLines($script:AboutPath)

    # The cmdlet-name shape used throughout both documents. Matching bare (the about topic writes no
    # backticks) and then filtering against FunctionsToExport is deliberate: it is how a name that
    # is NOT exported gets noticed rather than silently skipped.
    $script:CmdletNamePattern = [regex]'\b[A-Z][a-z]+-OER[A-Za-z]*\b'

    function Get-DocSyncMarkdownSection {
        <#
            .SYNOPSIS
                Returns the lines of a Markdown section, heading excluded.

            .DESCRIPTION
                Ends at the next heading of the same level or shallower, so a '###' subsection
                inside a '##' section does not terminate it. Returns $null when the heading is
                absent, which every caller asserts on rather than treating as an empty section.
        #>
        [OutputType([string[]])]
        param (
            [Parameter(Mandatory = $true)]
            [AllowEmptyCollection()]
            [AllowEmptyString()]
            [string[]]$Line,

            [Parameter(Mandatory = $true)]
            [string]$Heading
        )

        $Level = ($Heading -split ' ')[0].Length
        $Start = -1

        for ($Index = 0; $Index -lt $Line.Count; $Index++) {
            if ($Line[$Index].Trim() -eq $Heading) {
                $Start = $Index + 1
                break
            }
        }

        if ($Start -lt 0) {
            return $null
        }

        $End = $Line.Count

        for ($Index = $Start; $Index -lt $Line.Count; $Index++) {
            if ($Line[$Index] -match ('^#{1,' + $Level + '} ')) {
                $End = $Index
                break
            }
        }

        if ($End -le $Start) {
            return @()
        }

        return $Line[$Start..($End - 1)]
    }

    function Get-DocSyncAboutSection {
        <#
            .SYNOPSIS
                Returns the lines of an about-topic section, heading excluded.

            .DESCRIPTION
                About topics have no markup: a section heading is an ALL-CAPS line at column zero.
                Returns $null when the heading is absent.
        #>
        [OutputType([string[]])]
        param (
            [Parameter(Mandatory = $true)]
            [AllowEmptyCollection()]
            [AllowEmptyString()]
            [string[]]$Line,

            [Parameter(Mandatory = $true)]
            [string]$Heading
        )

        $Start = -1

        for ($Index = 0; $Index -lt $Line.Count; $Index++) {
            if ($Line[$Index] -eq $Heading) {
                $Start = $Index + 1
                break
            }
        }

        if ($Start -lt 0) {
            return $null
        }

        $End = $Line.Count

        for ($Index = $Start; $Index -lt $Line.Count; $Index++) {
            if ($Line[$Index] -match '^[A-Z][A-Z ]+$') {
                $End = $Index
                break
            }
        }

        if ($End -le $Start) {
            return @()
        }

        return $Line[$Start..($End - 1)]
    }

    function ConvertTo-DocSyncComparableText {
        <#
            .SYNOPSIS
                Strips the formatting that legitimately differs between the two documents.

            .DESCRIPTION
                The README writes a Markdown table with pipes and backticks; the about topic writes
                the same rows as indented plain text wrapped at a different width. Neither
                difference is a claim. What survives normalisation is the wording, which is.
        #>
        [OutputType([string])]
        param (
            [Parameter(Mandatory = $true)]
            [AllowEmptyString()]
            [string]$Text
        )

        $Result = $Text -replace '\|', ' '
        $Result = $Result -replace '`', ''
        $Result = $Result -replace '\*\*', ''
        $Result = $Result -replace '\s+', ' '

        return $Result.Trim()
    }

    function Get-DocSyncKnownLimitation {
        <#
            .SYNOPSIS
                Returns the normalised text of the paragraph that OPENS with 'Known limitation'.

            .DESCRIPTION
                The paragraph runs from that opening line to the next blank line. Returns $null if
                no line OPENS one -- a sentence merely mentioning a known limitation, such as the
                table row's 'see the known limitation below', is a cross-reference and must not be
                mistaken for the limitation itself.
        #>
        [OutputType([string])]
        param (
            [Parameter(Mandatory = $true)]
            [AllowEmptyCollection()]
            [AllowEmptyString()]
            [string[]]$Line
        )

        $Start = -1

        for ($Index = 0; $Index -lt $Line.Count; $Index++) {
            if ((($Line[$Index] -replace '\*\*', '').Trim()) -match '^(?i)known limitation\b') {
                $Start = $Index
                break
            }
        }

        if ($Start -lt 0) {
            return $null
        }

        $End = $Line.Count - 1

        for ($Index = $Start + 1; $Index -lt $Line.Count; $Index++) {
            if ([string]::IsNullOrWhiteSpace($Line[$Index])) {
                $End = $Index - 1
                break
            }
        }

        return ConvertTo-DocSyncComparableText -Text (($Line[$Start..$End]) -join ' ')
    }

    # The five sign-in types the tenant-switch table covers. A closed set on purpose: a sixth
    # sign-in type added to one document and not the other is caught by the 'names every sign-in
    # type' assertion below rather than by silently comparing four rows and passing.
    $script:SignInTypes = @('Client secret', 'Device code', 'Managed identity', 'Interactive', 'Certificate')

    function Get-DocSyncSignInVerdict {
        <#
            .SYNOPSIS
                Returns an ordered map of sign-in type -> normalised verdict text.

            .DESCRIPTION
                A row runs from its type label to the next type label or the next blank line,
                whichever comes first. A type whose row is absent maps to $null, and the caller
                fails on that rather than comparing two absences and calling them equal -- two
                documents that have both lost the same row are not in agreement, they are both
                wrong.
        #>
        [OutputType([System.Collections.Specialized.OrderedDictionary])]
        param (
            [Parameter(Mandatory = $true)]
            [AllowEmptyCollection()]
            [AllowEmptyString()]
            [string[]]$Line
        )

        $Text = $Line -join "`n"
        $Alternation = ($script:SignInTypes | ForEach-Object { [regex]::Escape($_) }) -join '|'
        $Verdict = [ordered]@{}

        foreach ($Type in $script:SignInTypes) {
            $Expression =
            '(?m)^[\s\|]*' + [regex]::Escape($Type) + '\b(?<body>.*?)' +
            '(?=(?:\r?\n[\s\|]*(?:' + $Alternation + ')\b)|(?:\r?\n\s*\r?\n))'

            $Match = [regex]::Match($Text, $Expression, 'Singleline')

            if (-not $Match.Success) {
                $Verdict[$Type] = $null
                continue
            }

            $Verdict[$Type] = ConvertTo-DocSyncComparableText -Text $Match.Groups['body'].Value
        }

        return $Verdict
    }
}

Describe 'README and about topic stay in step' -Tags 'helpQuality' {

    BeforeAll {
        $script:ReadmeRoster = Get-DocSyncMarkdownSection -Line $script:ReadmeLines -Heading '## Available Cmdlets'
        $script:AboutRoster = Get-DocSyncAboutSection -Line $script:AboutLines -Heading 'COMMAND COHORTS'
    }

    It 'Should find the roster section in both documents' {
        # Every assertion below reads one of these two sections. A renamed heading would otherwise
        # hand them an empty collection, and a set comparison between two empty sets passes.
        $script:ReadmeRoster | Should -Not -BeNullOrEmpty -Because 'README.md must carry an "## Available Cmdlets" section; if it was renamed, every roster check below silently measures nothing'

        $script:AboutRoster | Should -Not -BeNullOrEmpty -Because 'the about topic must carry a "COMMAND COHORTS" section; if it was renamed, every roster check below silently measures nothing'

        $script:ExportedNames.Count |
            Should -BeGreaterThan 0 -Because 'FunctionsToExport must be readable; zero exported names would make every comparison below vacuous'
    }

    It 'Should roster every exported cmdlet in README''s Available Cmdlets section' {
        # module.tests.ps1 already checks that README.md NAMES every exported cmdlet, but it matches
        # the whole file. A cmdlet mentioned only in a Quick Start snippet passes there and is
        # missing from the list a reader scrolls to. This check is scoped to the section.
        $Rostered = @(
            $script:CmdletNamePattern.Matches(($script:ReadmeRoster -join "`n")) |
                ForEach-Object { $_.Value } |
                Sort-Object -Unique
        )

        $Rostered.Count | Should -BeGreaterThan 0 -Because 'the section must name cmdlets; zero means the section was found but parsed as empty'

        $Missing = @($script:ExportedNames | Where-Object { $_ -notin $Rostered })

        $Missing | Should -BeNullOrEmpty -Because (
            'every exported cmdlet must appear in README.md ## Available Cmdlets, not merely somewhere in the file; missing: {0}' -f ($Missing -join ', '))

        $Unknown = @($Rostered | Where-Object { $_ -notin $script:ExportedNames })

        $Unknown | Should -BeNullOrEmpty -Because (
            'the README roster must name only exported cmdlets; unknown: {0}' -f ($Unknown -join ', '))
    }

    It 'Should roster every exported cmdlet in the about topic''s COMMAND COHORTS section' {
        $Rostered = @(
            $script:CmdletNamePattern.Matches(($script:AboutRoster -join "`n")) |
                ForEach-Object { $_.Value } |
                Sort-Object -Unique
        )

        $Rostered.Count | Should -BeGreaterThan 0 -Because 'the section must name cmdlets; zero means the section was found but parsed as empty'

        $Missing = @($script:ExportedNames | Where-Object { $_ -notin $Rostered })

        $Missing | Should -BeNullOrEmpty -Because (
            'every exported cmdlet must appear in the about topic COMMAND COHORTS section, not merely somewhere in the file; missing: {0}' -f ($Missing -join ', '))

        $Unknown = @($Rostered | Where-Object { $_ -notin $script:ExportedNames })

        $Unknown | Should -BeNullOrEmpty -Because (
            'the about topic roster must name only exported cmdlets; unknown: {0}' -f ($Unknown -join ', '))
    }

    It 'Should roster the same cmdlets in both documents' {
        # The binding itself. The two checks above each compare a roster against
        # FunctionsToExport, so this one can only fail if a roster drifted in a way that also broke
        # one of them -- which is the point: it names the disagreement directly, so a reader sees
        # "these two documents differ" rather than two separate "missing from X" failures.
        $ReadmeSet = @(
            $script:CmdletNamePattern.Matches(($script:ReadmeRoster -join "`n")) |
                ForEach-Object { $_.Value } |
                Where-Object { $_ -in $script:ExportedNames } |
                Sort-Object -Unique
        )

        $AboutSet = @(
            $script:CmdletNamePattern.Matches(($script:AboutRoster -join "`n")) |
                ForEach-Object { $_.Value } |
                Where-Object { $_ -in $script:ExportedNames } |
                Sort-Object -Unique
        )

        $ReadmeSet.Count | Should -BeGreaterThan 0 -Because 'a comparison between two empty sets passes; the README roster must be non-empty for this check to mean anything'
        $AboutSet.Count | Should -BeGreaterThan 0 -Because 'a comparison between two empty sets passes; the about roster must be non-empty for this check to mean anything'

        $OnlyInReadme = @($ReadmeSet | Where-Object { $_ -notin $AboutSet })
        $OnlyInAbout = @($AboutSet | Where-Object { $_ -notin $ReadmeSet })

        ($OnlyInReadme + $OnlyInAbout) | Should -BeNullOrEmpty -Because (
            'README.md ## Available Cmdlets and the about topic COMMAND COHORTS must roster the same cmdlets. Only in README: {0}. Only in the about topic: {1}' -f
                $(if ($OnlyInReadme.Count) { $OnlyInReadme -join ', ' } else { '(none)' }),
            $(if ($OnlyInAbout.Count) { $OnlyInAbout -join ', ' } else { '(none)' }))
    }

    It 'Should declare a cohort size in README that matches the cohort''s contents' {
        <#
            Each '### Cohort (N)' in README carries a count, and nothing checked it. A cmdlet's
            HOME cohort is the first one that names it in document order; a later mention is a
            cross-reference, not a second listing. That rule is what makes the counts checkable:
            'New-OERGroup' appears under Administrative Units to say it takes -AdministrativeUnit,
            and 'Connect-OER' under Azure inventory to say an ARM token is needed, and neither is a
            roster entry. Measured: the rule reproduces all thirteen declared counts exactly and
            sums to FunctionsToExport.
        #>
        $Text = $script:ReadmeRoster
        $Current = $null
        $Declared = [ordered]@{}
        $CohortMember = [ordered]@{}
        $Seen = @{}

        foreach ($Line in $Text) {
            if ($Line -match '^### (?<name>.+?)\s*\((?<count>\d+)\)\s*$') {
                $Current = $Matches['name']
                $Declared[$Current] = [int]$Matches['count']
                $CohortMember[$Current] = [System.Collections.Generic.List[string]]::new()
                continue
            }

            if ($null -eq $Current) {
                continue
            }

            foreach ($Match in ([regex]'`(?<name>[A-Z][a-z]+-OER[A-Za-z]*)`').Matches($Line)) {
                $Name = $Match.Groups['name'].Value

                if ($Seen.ContainsKey($Name) -or $Name -notin $script:ExportedNames) {
                    continue
                }

                $Seen[$Name] = $Current
                $CohortMember[$Current].Add($Name)
            }
        }

        $Declared.Count | Should -BeGreaterThan 0 -Because 'README ## Available Cmdlets must carry "### Cohort (N)" subsections; zero means the heading shape changed and this check measured nothing'

        $Wrong = @(
            foreach ($Cohort in $Declared.Keys) {
                if ($CohortMember[$Cohort].Count -ne $Declared[$Cohort]) {
                    '{0} says ({1}) but rosters {2}' -f $Cohort, $Declared[$Cohort], $CohortMember[$Cohort].Count
                }
            }
        )

        $Wrong | Should -BeNullOrEmpty -Because (
            'every "### Cohort (N)" count in README.md must equal the number of cmdlets that cohort is the FIRST to name; {0}' -f ($Wrong -join '; '))

        $Unhomed = @($script:ExportedNames | Where-Object { -not $Seen.ContainsKey($_) })

        $Unhomed | Should -BeNullOrEmpty -Because (
            'every exported cmdlet must be listed in backticks under exactly one "### Cohort (N)" subsection; without a home it is in no cohort''s count: {0}' -f ($Unhomed -join ', '))

        $Total = ($Declared.Values | Measure-Object -Sum).Sum

        $Total | Should -Be $script:ExportedNames.Count -Because (
            'the cohort counts partition the exported set, so they must sum to FunctionsToExport ({0}); they sum to {1}' -f $script:ExportedNames.Count, $Total)
    }

    It 'Should give the same tenant-switch verdict for every sign-in type in both documents' {
        <#
            The claim a reader acts on: what a later Connect-OER naming another tenant actually
            does, per sign-in type. Three of the five verdicts were rewritten after PR #90 measured
            them, in both documents by hand. This holds the two copies together word for word once
            table pipes, backticks and line wrapping are normalised away.
        #>
        $ReadmeSection = Get-DocSyncMarkdownSection -Line $script:ReadmeLines -Heading '### Switching tenants'
        $AboutSection = Get-DocSyncAboutSection -Line $script:AboutLines -Heading 'SWITCHING TENANTS'

        $ReadmeSection | Should -Not -BeNullOrEmpty -Because 'README.md must carry a "### Switching tenants" section; if it was renamed this check measures nothing'
        $AboutSection | Should -Not -BeNullOrEmpty -Because 'the about topic must carry a "SWITCHING TENANTS" section; if it was renamed this check measures nothing'

        $ReadmeVerdict = Get-DocSyncSignInVerdict -Line $ReadmeSection
        $AboutVerdict = Get-DocSyncSignInVerdict -Line $AboutSection

        # A missing row is a failure in its own right. Comparing $null to $null would otherwise
        # report two documents that have both lost the row as being in agreement.
        $AbsentInReadme = @($script:SignInTypes | Where-Object { [string]::IsNullOrWhiteSpace($ReadmeVerdict[$_]) })
        $AbsentInAbout = @($script:SignInTypes | Where-Object { [string]::IsNullOrWhiteSpace($AboutVerdict[$_]) })

        $AbsentInReadme | Should -BeNullOrEmpty -Because (
            'README.md ### Switching tenants must state a verdict for every sign-in type; absent: {0}' -f ($AbsentInReadme -join ', '))

        $AbsentInAbout | Should -BeNullOrEmpty -Because (
            'the about topic SWITCHING TENANTS must state a verdict for every sign-in type; absent: {0}' -f ($AbsentInAbout -join ', '))

        # ORDINAL on purpose. PowerShell's -eq and -ne on strings are CASE-INSENSITIVE by default,
        # and relying on that default is how a first measurement of these two documents reported
        # them identical when they were not. Measured: the five verdict rows match case-sensitively
        # today, so the strict comparison costs nothing and says what it means. (The known-limitation
        # check below deliberately does the opposite, and says why.)
        $Disagreement = @(
            foreach ($Type in $script:SignInTypes) {
                if (-not [string]::Equals($ReadmeVerdict[$Type], $AboutVerdict[$Type], [System.StringComparison]::Ordinal)) {
                    $Type
                }
            }
        )

        $Disagreement | Should -BeNullOrEmpty -Because (
            'README.md and the about topic must give the same tenant-switch verdict for each sign-in type; they differ for: {0}. Edit both, or neither -- these two rows are the claim a reader acts on' -f ($Disagreement -join ', '))
    }

    It 'Should state the device-code known limitation identically in both documents' {
        <#
            The one named known issue shipped in 1.0.0. It lives in four places (CHANGELOG, README,
            the about topic and the -DeviceCode/-Force help); these are the two this gate can bind.
            A limitation removed from one document and not the other is the worst direction of
            drift: the reader of the surviving copy is warned, the other is not.

            This compares the PARAGRAPH, not the presence of the words. A presence check was
            written first and was inert: deleting the limitation from README still left the phrase
            'see the known limitation below' in the Device code table row, so the check passed over
            a document that no longer carried the limitation at all. Measured with the mutation
            harness before this note was written.
        #>
        $ReadmeSection = Get-DocSyncMarkdownSection -Line $script:ReadmeLines -Heading '### Switching tenants'
        $AboutSection = Get-DocSyncAboutSection -Line $script:AboutLines -Heading 'SWITCHING TENANTS'

        $ReadmeSection | Should -Not -BeNullOrEmpty -Because 'README.md must carry a "### Switching tenants" section; if it was renamed this check measures nothing'
        $AboutSection | Should -Not -BeNullOrEmpty -Because 'the about topic must carry a "SWITCHING TENANTS" section; if it was renamed this check measures nothing'

        $ReadmeLimitation = Get-DocSyncKnownLimitation -Line $ReadmeSection
        $AboutLimitation = Get-DocSyncKnownLimitation -Line $AboutSection

        $ReadmeLimitation | Should -Not -BeNullOrEmpty -Because 'README.md ### Switching tenants must open a paragraph with "Known limitation"; a cross-reference to one elsewhere in the section is not the limitation'

        $AboutLimitation | Should -Not -BeNullOrEmpty -Because 'the about topic SWITCHING TENANTS must open a paragraph with "KNOWN LIMITATION"; a cross-reference to one elsewhere in the section is not the limitation'

        # CASE-INSENSITIVE on purpose, and this is the one place in this file where that is right.
        # An about topic has no bold, so it emphasises by capitalising: README writes
        # 'Known limitation', the topic writes 'KNOWN LIMITATION'. That is the medium's formatting,
        # exactly like the table pipes and backticks normalised away above -- not a difference in
        # what the two documents claim. The comparison is spelled out rather than left to
        # PowerShell's case-insensitive -eq default, so the next reader can see it was a decision.
        [string]::Equals($ReadmeLimitation, $AboutLimitation, [System.StringComparison]::OrdinalIgnoreCase) |
            Should -BeTrue -Because (
                'the device-code known limitation must read the same in README.md and the about topic once formatting is normalised away; edit both, or neither. README: "{0}..." about: "{1}..."' -f
                    $ReadmeLimitation.Substring(0, [Math]::Min(110, $ReadmeLimitation.Length)),
                $AboutLimitation.Substring(0, [Math]::Min(110, $AboutLimitation.Length)))
    }
}
