BeforeAll {
    $script:ProjectPath = (Resolve-Path -Path (Join-Path -Path $PSScriptRoot -ChildPath '..\..')).Path

    # =====================================================================================
    # SCOPE: every TRACKED file under docs/, specs/, source/ or tests/, whatever its extension.
    #
    # docs/live-verification/ is where live tenant console output is pasted in on purpose, and it
    # was this gate's first scope. Issue #62 widened it to all of docs/ and specs/ once the planning
    # material that would have failed a wider gate on day one had been redacted and untracked. What
    # is tracked beyond the checklists is docs/development/ and docs/examples/example-structure.json,
    # the worked apply-document example and the file most likely to receive a pasted real principal.
    # The internal planning and design material under docs/superpowers/ was left out of the public
    # repository entirely when it was seeded, so no rule here needs to reach it.
    #
    # source/ and tests/ joined that scope when the repository was about to be published. Until
    # then the argument for leaving them out was that the repository was private; publication
    # removes it. source/ ships inside the built module to every installed copy, and tests/ lands in
    # the public repository's first commit. Both are as unredactable after the fact as a checklist.
    #
    # Every extension is scanned, not just .md: the example document is .json. A binary file would
    # be scanned as text too, which for a leak gate errs toward RED -- the right direction. A
    # top-level specs/ does not exist today; it is in scope so that one created later is covered
    # from its first commit instead of silently skipped.
    #
    # KNOWN FALSE POSITIVE, deliberately not exempted: a Graph annotation such as the
    # 'members' odata.bind form matches the address pattern below. No tracked file in scope carries
    # one -- this comment deliberately names it WITHOUT its '@' for that reason, which is also the
    # fix if one is ever added. Do not add an exemption, and never widen the domain allowlist to
    # make this gate green.
    # =====================================================================================
    $script:DocHygieneScopePattern = '^(docs|specs|source|tests)/'

    # =====================================================================================
    # MARKDOWN SCOPE: every tracked .md under docs/ or specs/, plus README.md and CHANGELOG.md.
    #
    # GitHub reads a '<word>' written outside code as an HTML tag and renders nothing in its
    # place, so a redacted stand-in such as '<id>' silently vanishes from the page that is the
    # record, and the sentence around it stops making sense. The check that keeps those out reads
    # Markdown only, and it reaches two files at the root that no other check here does:
    # README.md, the repository's front page, and CHANGELOG.md, whose [Unreleased] section is
    # published as the release notes: the PowerShell Gallery shows them as plain text, and the
    # GitHub release body built from the same notes renders them as Markdown, where a tag
    # vanishes. Adding the root files to the scope above instead would also put them under the
    # object-id, address and credential rules, which is a separate decision this check does not
    # take.
    # =====================================================================================
    $script:DocHygieneMarkdownScopePattern = '^((docs|specs)/.+\.md|README\.md|CHANGELOG\.md)$'

    # =====================================================================================
    # PROSE SCOPE vs CODE SCOPE -- why the object-id rule is not the same in both.
    #
    # Under docs/ and specs/ every GUID is PROSE. It got there by being pasted out of a console, so
    # the rule is absolute: it must be a 00000000-0000-0000-0000-0000000000NN placeholder.
    #
    # Under source/ and tests/ a GUID is a FIXTURE, typed on purpose. Roughly seventy distinct ones
    # exist -- 11111111-..., aaaaaaaa-...-0001 and so on -- and they are readable precisely because
    # they are not interchangeable: a test tells a principal from a group from an administrative
    # unit at a glance. Forcing them all to the placeholder shape would rewrite about thirteen
    # hundred sites and destroy that, while buying nothing: none of them could ever have come from a
    # tenant.
    #
    # So the code-scope rule keys on the one structural property that separates a real identifier
    # from an invented one: a TENANT-GENERATED Entra ID object id, and an ARM subscription or
    # resource id, is a version-4 (random) UUID, and no hand-written fixture in this repository
    # needs to be. A v4-shaped GUID in source/ or tests/ is therefore either a real identifier that
    # must not ship, or a fixture typed to look like one, which is indistinguishable from the first
    # by inspection and just as bad. The placeholder range is not v4, so placeholders pass here too.
    #
    # WHAT THIS RULE DOES NOT CATCH, stated rather than left to be discovered. Some well-known
    # Microsoft identifiers are deliberately NOT v4 -- the Microsoft Graph service principal's own
    # application id is a hand-assigned value in the all-zeros style -- and this check lets them
    # through. That is the correct direction: a non-random id is a published constant that is the
    # same in every tenant, not somebody's directory object. The residual gap is the mirror image:
    # a tenant identifier that somehow is not v4 would be missed here. Nothing generates such an id
    # today, and the rule is a shape heuristic rather than a proof -- redacting as you write, and
    # the register in docs/live-verification/README.md, remain the primary control.
    #
    # This is a rule about SHAPE, not a list of blessed values, and that is the point: it cannot be
    # satisfied by adding an entry to something. The three exceptions below are the whole of the
    # list, they are pinned, and each one is a published Microsoft constant or the module's own
    # identity -- never a tenant object.
    # =====================================================================================
    $script:DocHygieneCodeScopePattern = '^(source|tests)/'

    # =====================================================================================
    # THE PUBLIC-CONSTANT REGISTER -- three entries, and it does not grow.
    #
    # Each of these is v4-shaped and cannot be replaced with a placeholder, for a reason that is
    # different in kind for each one. None of them can ever be a tenant identifier: the first IS
    # this module, and the other two are published by Microsoft and identical in every tenant on
    # earth.
    #
    # A fourth entry is not the way to make this gate green. If a new v4 GUID appears in source/ or
    # tests/, the fix is a placeholder -- see docs/live-verification/README.md for the allocation.
    # The It named 'Should hold no stale entry in the public-constant register' below makes the
    # register rot loudly rather than quietly: an entry whose value has left the tree fails, so the
    # register shrinks when a constant goes away instead of accumulating dead permissions.
    # =====================================================================================
    $script:DocHygienePublicConstant = @(
        @{
            # The module's own GUID in source/Omnicit.EntraRBAC.psd1. It is the module's identity to
            # PowerShellGet and to every installed copy; changing it publishes a DIFFERENT module
            # that no longer updates the one already installed. It names no tenant object at all.
            Value  = '7b9e4a1c-2d6f-4f3a-9c8b-1e5d0a7c3f42'
            Reason = "the module's own GUID in the manifest -- its identity on the PowerShell Gallery"
        }
        @{
            # Microsoft Graph Command Line Tools, the first-party application the Microsoft Graph
            # PowerShell SDK signs in as. Documented by Microsoft, the same value in every tenant,
            # and FUNCTIONAL here: source/Private/Initialize-OERAuth.ps1 sends it as the default
            # client id, so a placeholder would break authentication rather than redact anything.
            Value  = '14d82eec-204b-4c2f-b7e8-296a70dab67e'
            Reason = 'the Microsoft Graph Command Line Tools first-party application id'
        }
        @{
            # The Azure built-in role definition id for Reader, published at
            # learn.microsoft.com/azure/role-based-access-control/built-in-roles/general and
            # identical in every tenant. It appears in a help example and in the role-definition
            # tests, where using the real id is what makes the example correct.
            Value  = 'acdd72a7-3385-48ef-bd42-f606fba81ae7'
            Reason = 'the Azure built-in role definition id for Reader'
        }
    )

    # =====================================================================================
    # TENANT DOMAINS -- four labels are allowed, and the list does not grow to make this gate green.
    #
    # Every tenant has an initial domain: a LABEL in front of .onmicrosoft.com, .onmicrosoft.us in
    # the US Government clouds, or .onmschina.cn under 21Vianet. The label names exactly one
    # tenant, so it identifies a customer as surely as the tenant id does, and it arrives in exactly
    # the places this gate watches: sign-in output, user principal names, Graph request paths. None
    # of the other rules here reads it. It is no GUID, and the email rule sees it only behind a
    # literal '@' -- not as a bare domain, not URL-encoded in a request path, not escaped in a
    # regular expression.
    #
    # So every line is NORMALIZED before it is matched: '%40' becomes '@' (a user principal name
    # in a URL-encoded path) and '\.' becomes '.' (a domain written as a regular expression in a
    # test). Those are the two forms the tests in this repository actually use, and without the
    # normalization both would slip through. A bare mention of the suffix, with no label in front
    # of it, names no tenant and never matches.
    #
    # Every entry below is a fictional or deliberately non-existent tenant. A real label is never
    # added here to make this gate green: the fix is to replace it with one of these. The It named
    # 'Should hold no stale entry in the tenant-domain allowlist' fails on an entry that has left
    # the tree, the same way the public-constant register does, so the list shrinks when a use
    # goes away instead of keeping a permission nobody reads.
    # =====================================================================================
    $script:DocHygieneTenantLabelAllowlist = @(
        'contoso'                            # the documentation tenant, everywhere
        'fabrikam'                           # the second documentation tenant, a switching example and a guest UPN fixture
        'other'                              # a deliberately different tenant name in an auth test
        'oer-sovereign-verify-doesnotexist'  # a deliberately non-existent tenant in a sovereign-cloud checklist
    )

    # =====================================================================================
    # THE PLACEHOLDER REGISTER IS READ, NOT JUST CITED.
    #
    # docs/live-verification/README.md allocates every placeholder used outside the checklists --
    # the all-zeros object ids and the personN addresses -- one row per slot, and names the next
    # free one in a sentence. Until this gate read it, nothing checked the register against itself
    # or against the tree, and it drifted: the sentence named a slot the table had already given
    # away. The register's whole purpose is to stop two objects sharing one placeholder, so a
    # register that disagrees with itself is the defect it exists to prevent, waiting to happen.
    #
    # The gate now reads it (Get-DocHygienePlaceholderRegister), fails on a register that
    # contradicts itself (Get-DocHygieneRegisterFinding), and fails on a placeholder used in
    # source/, tests/, docs/examples/ or docs/development/ that the register does not show as
    # taken. What it still cannot check is whether a slot's description means what the last
    # person thought it meant; the unique description per row is that human check.
    #
    # The sample below mirrors the real register's shapes and is the reader's known answer. A row
    # after the section's end is there on purpose: the reader must stop at the next heading. Ids
    # are read as HEX, which is how '...0aa' and '...abc' take their place among the others.
    # =====================================================================================
    $script:DocHygieneSampleRegister = @'
Text before the register is not part of it.

## The placeholder register

Prose before the tables is read too, and holds nothing the reader takes.

| Placeholder | Slot (generic) | Status |
|---|---|---|
| `...000` - `...045` | the per-file numbering and the any-id stand-in | taken, under the per-file rule |
| `...046` | a subscription id in the worked example | taken |
| `...047` | a principal id in the worked example | taken |
| `...066` and up | -- | **FREE. Allocate from here.** |
| `...099` | a deliberately non-existent object id | taken |
| `...0aa` | an assignment target principal id | taken |
| `...abc` | an administrative unit id | taken |

Addresses follow the same global rule:

| Placeholder | Slot (generic) | Status |
|---|---|---|
| `person1` - `person13`, `person15` - `person45` | reviewers, requestors and members | taken |
| `person14` | -- | allocated and never used; left reserved, do not reuse |
| `person46` and up | -- | **FREE. Allocate from here.** |

`...0aa`, `...abc` and `...099` sit outside the counting sequence for historical reasons and are
listed so they are not handed out twice. Allocate new object ids from `...066` and new addresses
from `person46`, and add a row here in the same commit that uses them.

## The next section

| `...070` | a row after the register, which the reader must not take | taken |
'@

    # =====================================================================================
    # ENUMERATE TRACKED FILES WITH `git ls-files`, NOT THE FILESYSTEM.
    #
    # Raw console output and unredacted working copies live beside the checklists as UNTRACKED
    # files -- docs/live-verification/raw/ and docs/live-verification/*.log are git-ignored for
    # exactly that purpose. A gate that scanned the disk would therefore be RED on the maintainer's
    # machine and GREEN in CI, and a gate that is red only locally gets switched off rather than
    # fixed. What matters for a leak is what is committed, and that is what `git ls-files` reports.
    #
    # CONTENT, however, is read from the WORKING TREE, never from the index. Reading index blobs
    # (`git show :path`) would measure STAGED content, so an unredacted edit sitting unstaged in the
    # working tree would sail straight through green -- a guard that looks like a guard and enforces
    # nothing. `git ls-files` decides WHICH files are in scope; the disk decides WHAT they say.
    #
    # Both rules survived every widening unchanged, and the first one matters more after each one:
    # the planning material that was never tracked sits unredacted on the maintainer's disk, which
    # is exactly the local-red, CI-green split it prevents.
    # =====================================================================================
    $script:DocHygieneSkipReason = $null
    $script:DocHygieneFiles = @()
    $script:DocHygieneMarkdownFiles = @()

    if (-not (Get-Command -Name 'git' -CommandType Application -ErrorAction SilentlyContinue)) {
        $script:DocHygieneSkipReason =
        'git was not found on PATH, and this gate enumerates TRACKED files with git ls-files. It measured nothing -- install git, or run it inside a clone, then re-run.'
    }
    else {
        # README.md and CHANGELOG.md are listed for the Markdown scope only; the scope pattern
        # keeps them out of $script:DocHygieneFiles and so out of every other check here.
        $TrackedPaths = @(& git -C $script:ProjectPath -c core.quotePath=false ls-files -- 'docs' 'specs' 'source' 'tests' 'README.md' 'CHANGELOG.md' 2>$null)

        if (0 -ne $LASTEXITCODE) {
            $script:DocHygieneSkipReason =
            ('git ls-files exited {0} here, so the tracked-file enumeration failed -- this is not a clone, or the working tree is unreadable. It measured nothing.' -f $LASTEXITCODE)
        }
        else {
            $script:DocHygieneFiles = @(
                foreach ($RelativePath in ($TrackedPaths | Where-Object { $_ -match $script:DocHygieneScopePattern })) {
                    $FullPath = Join-Path -Path $script:ProjectPath -ChildPath $RelativePath

                    # A tracked path whose working-tree copy is gone (a staged deletion) holds no
                    # text to leak. Skip it rather than throwing; the emptiness guard in each It
                    # still catches the case where that leaves nothing at all to measure.
                    if (-not (Test-Path -LiteralPath $FullPath -PathType Leaf)) {
                        continue
                    }

                    [PSCustomObject]@{
                        RelativePath = $RelativePath
                        IsCode       = $RelativePath -match $script:DocHygieneCodeScopePattern
                        Lines        = [System.IO.File]::ReadAllLines($FullPath)
                    }
                }
            )

            $script:DocHygieneMarkdownFiles = @(
                foreach ($RelativePath in ($TrackedPaths | Where-Object { $_ -match $script:DocHygieneMarkdownScopePattern })) {
                    $FullPath = Join-Path -Path $script:ProjectPath -ChildPath $RelativePath

                    if (-not (Test-Path -LiteralPath $FullPath -PathType Leaf)) {
                        continue
                    }

                    [PSCustomObject]@{
                        RelativePath = $RelativePath
                        Lines        = [System.IO.File]::ReadAllLines($FullPath)
                    }
                }
            )
        }
    }

    function Get-DocHygieneMatchLocation {
        <#
            .SYNOPSIS
                Returns 'path:line' for every match of Pattern that IsAllowed rejects.

            .DESCRIPTION
                The matched VALUE is never returned and never rendered. This gate exists to keep
                tenant identifiers out of logs, and a failure message that quoted its own hit would
                copy that identifier into every CI run that went red -- turning the guard into the
                leak it was added to close.

                IsAllowed is called with the matched value AND the file entry it came from, so a
                check can apply one rule to prose under docs/ and another to code under source/.

                AcrossLineBreak adds a second pass for a value that console output WRAPPED: a
                formatted table breaks a long cell at the column edge and indents the rest, so one
                identifier lands on two lines and neither line alone matches. That pass reads the
                file as one string with every line break, and the whitespace on both sides of it,
                removed. It reports only a match that crosses a line boundary, at the line the match
                starts on; a match inside one line is the first pass's to report, so no location
                is counted twice.
        #>
        [OutputType([string])]
        param (
            [Parameter(Mandatory = $true)]
            [AllowEmptyCollection()]
            [object[]]$File,

            [Parameter(Mandatory = $true)]
            [regex]$Pattern,

            [Parameter(Mandatory = $true)]
            [scriptblock]$IsAllowed,

            [Parameter()]
            [switch]$AcrossLineBreak
        )

        $Locations = [System.Collections.Generic.List[string]]::new()

        foreach ($Entry in $File) {
            for ($Index = 0; $Index -lt $Entry.Lines.Count; $Index++) {
                foreach ($Match in $Pattern.Matches($Entry.Lines[$Index])) {
                    if (& $IsAllowed $Match.Value $Entry) {
                        continue
                    }

                    $Locations.Add(('{0}:{1}' -f $Entry.RelativePath, ($Index + 1)))
                }
            }

            if (-not $AcrossLineBreak -or $Entry.Lines.Count -lt 2) {
                continue
            }

            # One string, and the offset at which each line starts in it. An empty line starts
            # where the next one does, so the lookup below takes the LAST line starting at or
            # before an offset: that is the line the character at the offset belongs to.
            $Joined = [System.Text.StringBuilder]::new()
            $LineStart = [int[]]::new($Entry.Lines.Count)

            for ($Index = 0; $Index -lt $Entry.Lines.Count; $Index++) {
                $LineStart[$Index] = $Joined.Length
                $null = $Joined.Append($Entry.Lines[$Index].Trim(" `t".ToCharArray()))
            }

            $GetLine = {
                param ($Offset)

                $Line = [System.Array]::BinarySearch($LineStart, [int]$Offset)

                if ($Line -lt 0) {
                    # Not an exact line start: the complement is the first line starting AFTER the
                    # offset, so the one before it holds the character.
                    return ((-bnot $Line) - 1)
                }

                while ($Line + 1 -lt $LineStart.Count -and $LineStart[$Line + 1] -eq $LineStart[$Line]) {
                    $Line++
                }

                return $Line
            }

            foreach ($Match in $Pattern.Matches($Joined.ToString())) {
                $FirstLine = & $GetLine $Match.Index
                $LastLine = & $GetLine ($Match.Index + $Match.Length - 1)

                if ($FirstLine -eq $LastLine) {
                    continue
                }

                if (& $IsAllowed $Match.Value $Entry) {
                    continue
                }

                $Locations.Add(('{0}:{1}' -f $Entry.RelativePath, ($FirstLine + 1)))
            }
        }

        return $Locations
    }

    function Test-DocHygieneVersion4Guid {
        <#
            .SYNOPSIS
                True when Value has RFC 4122 version-4 shape.

            .DESCRIPTION
                Version nibble 4 and variant nibble 8, 9, a or b. Every Entra ID object id and every
                ARM resource id has this shape; the invented fixtures in this repository do not, and
                neither does the 00000000-0000-0000-0000-0000000000NN placeholder range.
        #>
        [OutputType([bool])]
        param (
            [Parameter(Mandatory = $true)]
            [string]$Value
        )

        $Bare = $Value -replace '-', ''

        return ($Bare[12] -eq '4' -and $Bare[16] -match '[89abAB]')
    }

    function ConvertTo-DocHygieneMarkdownProse {
        <#
            .SYNOPSIS
                Returns a Markdown file's lines with fenced blocks and code spans blanked out.

            .DESCRIPTION
                The algorithm is exactly the one in Test-MdAngleBrackets.py, the maintainer's
                checker for the live-verification notes kept outside this repository, and the two
                must agree hit for hit on the same tree. It is close to CommonMark but not the same,
                and where they differ the script is what this follows:

                - A line that opens with optional whitespace and then three or more backticks or
                  tildes opens a fenced block. The block runs to the next such line of the same
                  character whose run is at least as long, or to the end of the file. The whole
                  block is skipped, both fence lines included.
                - The remaining lines are grouped into paragraphs at blank lines and at fences.
                - Within a paragraph, a run of N backticks opens a code span that the next run of
                  exactly N closes, across a line break too. A candidate closer FOLLOWED by another
                  backtick is skipped; only the character after it is checked. A run with no
                  closer is literal text.
                - A code span is replaced by spaces with its line breaks kept, so every character
                  left keeps its line and column.

                KNOWN FALSE NEGATIVE, deliberately not handled, shared with Test-MdAngleBrackets.py:
                CommonMark lets an open tag's attributes cross one line break, so a long stand-in
                broken by the 100-column wrap -- '<management groups: the' ending one line and
                'listing failed>' starting the next -- is hidden by GitHub but matched by neither
                scanner, since the tag pattern stops at a line break. Zero such cases are in scope
                today. Keep a redacted stand-in on one line; do not change the pattern to reach
                across a break.

                Lines holds the masked text, one entry per input line, with skipped lines empty.
                CodeSpanCount is the number of code spans removed outside fenced blocks; the check
                uses it to prove that it reached any prose at all.
        #>
        [OutputType([PSCustomObject])]
        param (
            [Parameter(Mandatory = $true)]
            [AllowEmptyCollection()]
            [AllowEmptyString()]
            [string[]]$Line
        )

        $FencePattern = [regex]'^\s*(`{3,}|~{3,})'
        $Tick = [char]'`'

        # Pass 1: which lines are prose, grouped into paragraphs of line indexes.
        $Paragraphs = [System.Collections.Generic.List[int[]]]::new()
        $Current = [System.Collections.Generic.List[int]]::new()
        $Fence = $null

        for ($Index = 0; $Index -lt $Line.Count; $Index++) {
            $FenceMatch = $FencePattern.Match($Line[$Index])

            if ($Fence) {
                if ($FenceMatch.Success -and $FenceMatch.Groups[1].Value[0] -eq $Fence[0] -and $FenceMatch.Groups[1].Value.Length -ge $Fence.Length) {
                    $Fence = $null
                }

                continue
            }

            if ($FenceMatch.Success -or [string]::IsNullOrWhiteSpace($Line[$Index])) {
                if ($Current.Count -gt 0) {
                    $Paragraphs.Add($Current.ToArray())
                    $Current.Clear()
                }

                if ($FenceMatch.Success) {
                    $Fence = $FenceMatch.Groups[1].Value
                }

                continue
            }

            $Current.Add($Index)
        }

        if ($Current.Count -gt 0) {
            $Paragraphs.Add($Current.ToArray())
        }

        # Pass 2: blank every code span in each paragraph, keeping its line breaks.
        [string[]]$Masked = @('') * $Line.Count
        $CodeSpanCount = 0

        foreach ($Indices in $Paragraphs) {
            $Text = [string]::Join("`n", [string[]]@(foreach ($Member in $Indices) { $Line[$Member] }))
            $Builder = [System.Text.StringBuilder]::new($Text.Length)
            $Position = 0

            while ($Position -lt $Text.Length) {
                $RunStart = $Text.IndexOf($Tick, $Position)

                if ($RunStart -lt 0) {
                    $null = $Builder.Append($Text, $Position, $Text.Length - $Position)
                    break
                }

                $null = $Builder.Append($Text, $Position, $RunStart - $Position)

                $RunEnd = $RunStart
                while ($RunEnd -lt $Text.Length -and $Text[$RunEnd] -eq $Tick) {
                    $RunEnd++
                }

                $Run = $Text.Substring($RunStart, $RunEnd - $RunStart)
                $Close = $Text.IndexOf($Run, $RunEnd, [System.StringComparison]::Ordinal)

                while ($Close -ge 0 -and ($Close + $Run.Length) -lt $Text.Length -and $Text[$Close + $Run.Length] -eq $Tick) {
                    $Close = $Text.IndexOf($Run, $Close + $Run.Length + 1, [System.StringComparison]::Ordinal)
                }

                if ($Close -ge 0) {
                    $SpanEnd = $Close + $Run.Length
                    $null = $Builder.Append(($Text.Substring($RunStart, $SpanEnd - $RunStart) -replace '[^\n]', ' '))
                    $CodeSpanCount++
                    $Position = $SpanEnd
                    continue
                }

                $null = $Builder.Append($Run)
                $Position = $RunEnd
            }

            $MaskedParagraph = $Builder.ToString().Split("`n")

            for ($Offset = 0; $Offset -lt $Indices.Count; $Offset++) {
                $Masked[$Indices[$Offset]] = $MaskedParagraph[$Offset]
            }
        }

        [PSCustomObject]@{
            Lines         = $Masked
            CodeSpanCount = $CodeSpanCount
        }
    }

    function Get-DocHygieneTenantDomainLabel {
        <#
            .SYNOPSIS
                Returns the label of every tenant domain in Line, after normalization.

            .DESCRIPTION
                Before matching, '%40' is read as '@' and a backslash-escaped dot as a dot, so a
                user principal name in a URL-encoded path and a domain written as a regular
                expression are read the way a tenant would read them. The label is the run of
                letters, digits and hyphens in front of one of the three suffixes, the commercial
                and US Government onmicrosoft ones and the 21Vianet onmschina one. A bare suffix
                with no label in front of it names no tenant and yields nothing.

                The pattern cannot match across a line break, so Line may also be a whole file
                joined with line feeds: a joined text with no label has none in any of its lines.
        #>
        [OutputType([string])]
        param (
            [Parameter(Mandatory = $true)]
            [AllowEmptyString()]
            [string]$Line
        )

        $Pattern = [regex]'(?i)(?<![A-Za-z0-9-])([A-Za-z0-9-]+)\.(?:onmicrosoft\.(?:com|us)|onmschina\.cn)(?![A-Za-z0-9-])'
        $Normalized = $Line.Replace('%40', '@').Replace('\.', '.')

        foreach ($Match in $Pattern.Matches($Normalized)) {
            $Match.Groups[1].Value
        }
    }

    function Get-DocHygieneTenantDomainUse {
        <#
            .SYNOPSIS
                Returns a Location ('path:line') and a Label for every tenant domain in File.

            .DESCRIPTION
                Each file is first read as ONE string, and only a file holding at least one tenant
                domain is read again line by line. That first pass is exact, not a heuristic -- see
                Get-DocHygieneTenantDomainLabel -- and it spares a per-line call on the many
                thousands of lines in scope that carry no domain at all.

                The Label is returned so a caller can test it against the allowlist. A caller that
                reports a hit renders the Location only, never the Label: the label IS the
                tenant's name.
        #>
        [OutputType([PSCustomObject])]
        param (
            [Parameter(Mandatory = $true)]
            [AllowEmptyCollection()]
            [object[]]$File
        )

        foreach ($Entry in $File) {
            if (-not @(Get-DocHygieneTenantDomainLabel -Line ([string]::Join("`n", [string[]]$Entry.Lines))).Count) {
                continue
            }

            for ($Index = 0; $Index -lt $Entry.Lines.Count; $Index++) {
                foreach ($Label in @(Get-DocHygieneTenantDomainLabel -Line $Entry.Lines[$Index])) {
                    [PSCustomObject]@{
                        Location = '{0}:{1}' -f $Entry.RelativePath, ($Index + 1)
                        Label    = $Label
                    }
                }
            }
        }
    }

    function Test-DocHygieneTenantLabelAllowed {
        <#
            .SYNOPSIS
                True when Label is one of the fictional tenants on the allowlist, ignoring case.
        #>
        [OutputType([bool])]
        param (
            [Parameter(Mandatory = $true)]
            [string]$Label
        )

        foreach ($Allowed in $script:DocHygieneTenantLabelAllowlist) {
            if ([string]::Equals($Label, $Allowed, [System.StringComparison]::OrdinalIgnoreCase)) {
                return $true
            }
        }

        return $false
    }

    function Get-DocHygienePlaceholderRegister {
        <#
            .SYNOPSIS
                Reads the placeholder register out of the lines of docs/live-verification/README.md.

            .DESCRIPTION
                The register runs from the line '## The placeholder register' to the next line
                that starts with '## '. Nothing outside it is read.

                Every table row whose first cell holds a backticked id token (three dots and three
                hex characters) or address token ('person' and a number) becomes one Row:

                - Table: Id or Address, from the kind of the first token in the cell.
                - Intervals: one [Start, End] pair per comma-separated part of the first cell -- a
                  single token, an 'A - B' range, or 'A and up', whose End is [int]::MaxValue. An
                  id is its three characters read as HEX; an address is its number.
                - Unreadable: true when any part of the first cell is none of those three shapes,
                  when the cell mixes ids and addresses, when a range ends before it starts, or when
                  the row has fewer than three cells. Such a row is REPORTED, never skipped: a
                  reader that dropped a row it could not parse would quietly stop checking it.
                - Slot: the second cell, trimmed.
                - Status: Free when the third cell says FREE, Taken when it starts with 'taken',
                  otherwise Reserved.
                - Line: the 1-based line number in Line.

                The prose is read a paragraph at a time, with each paragraph's lines joined, so a
                sentence that wraps is still one sentence. AllocateId and AllocateAddress come from
                the first sentence of the form 'Allocate new object ids from (id) and new addresses
                from (address)', and AllocateLine is the line it starts on; all three are $null when
                no such sentence exists. Outliers are the ids named in the sentence that says they
                sit 'outside the counting sequence', and HeadingLine is the line of the heading
                itself, or $null when the section is missing.
        #>
        [OutputType([PSCustomObject])]
        param (
            [Parameter(Mandatory = $true)]
            [AllowEmptyCollection()]
            [AllowEmptyString()]
            [string[]]$Line
        )

        $Token = '`(?:\.\.\.[0-9A-Fa-f]{3}|person\d{1,9})`'
        $PartPattern = [regex]('^\s*(' + $Token + ')(?:\s*-\s*(' + $Token + ')|\s+(and up))?\s*$')
        $AllocatePattern = [regex]'(?i)Allocate\s+new\s+object\s+ids\s+from\s+`\.\.\.([0-9A-Fa-f]{3})`\s+and\s+new\s+addresses\s+from\s+`person(\d{1,9})`'
        $OutlierPattern = [regex]'(?i)outside\s+the\s+counting\s+sequence'
        $IdTokenPattern = [regex]'`\.\.\.([0-9A-Fa-f]{3})`'

        $ReadToken = {
            param ($Text)

            $Bare = $Text.Trim('`')

            if ($Bare.StartsWith('...')) {
                return [PSCustomObject]@{ Kind = 'Id'; Value = [Convert]::ToInt32($Bare.Substring(3), 16) }
            }

            return [PSCustomObject]@{ Kind = 'Address'; Value = [int]$Bare.Substring(6) }
        }

        $HeadingIndex = -1
        for ($Index = 0; $Index -lt $Line.Count; $Index++) {
            if ($Line[$Index].TrimEnd() -eq '## The placeholder register') {
                $HeadingIndex = $Index
                break
            }
        }

        $Rows = [System.Collections.Generic.List[object]]::new()
        $Paragraphs = [System.Collections.Generic.List[int[]]]::new()

        if ($HeadingIndex -ge 0) {
            $Current = [System.Collections.Generic.List[int]]::new()

            for ($Index = $HeadingIndex + 1; $Index -lt $Line.Count; $Index++) {
                $Text = $Line[$Index]

                if ($Text.StartsWith('## ')) {
                    break
                }

                if ($Text -match '^\s*\|' -or [string]::IsNullOrWhiteSpace($Text)) {
                    if ($Current.Count -gt 0) {
                        $Paragraphs.Add($Current.ToArray())
                        $Current.Clear()
                    }
                }
                else {
                    $Current.Add($Index)
                    continue
                }

                if ($Text -notmatch '^\s*\|') {
                    continue
                }

                $Cells = $Text.Trim().Trim('|').Split('|')

                # A header row or the separator row holds no token and is not a register row.
                $FirstToken = [regex]::Match($Cells[0], $Token)
                if (-not $FirstToken.Success) {
                    continue
                }

                $Kinds = [System.Collections.Generic.HashSet[string]]::new()
                $Intervals = [System.Collections.Generic.List[int[]]]::new()
                $Unreadable = $Cells.Count -lt 3

                foreach ($Part in $Cells[0].Split(',')) {
                    $PartMatch = $PartPattern.Match($Part)

                    if (-not $PartMatch.Success) {
                        $Unreadable = $true
                        continue
                    }

                    $From = & $ReadToken $PartMatch.Groups[1].Value
                    $null = $Kinds.Add($From.Kind)
                    $To = $From.Value

                    if ($PartMatch.Groups[2].Success) {
                        $Last = & $ReadToken $PartMatch.Groups[2].Value
                        $null = $Kinds.Add($Last.Kind)
                        $To = $Last.Value
                    }
                    elseif ($PartMatch.Groups[3].Success) {
                        $To = [int]::MaxValue
                    }

                    if ($To -lt $From.Value) {
                        $Unreadable = $true
                    }

                    $Intervals.Add([int[]]@($From.Value, $To))
                }

                if ($Kinds.Count -gt 1) {
                    $Unreadable = $true
                }

                $Status = 'Reserved'
                if ($Cells.Count -ge 3) {
                    if ($Cells[2] -match '\bFREE\b') {
                        $Status = 'Free'
                    }
                    elseif ($Cells[2].Trim() -match '^taken\b') {
                        $Status = 'Taken'
                    }
                }

                $Rows.Add([PSCustomObject]@{
                        Table      = (& $ReadToken $FirstToken.Value).Kind
                        Intervals  = $Intervals.ToArray()
                        Slot       = $(if ($Cells.Count -ge 2) { $Cells[1].Trim() } else { '' })
                        Status     = $Status
                        Unreadable = $Unreadable
                        Line       = $Index + 1
                    })
            }

            if ($Current.Count -gt 0) {
                $Paragraphs.Add($Current.ToArray())
            }
        }

        $AllocateId = $null
        $AllocateAddress = $null
        $AllocateLine = $null
        $Outliers = [System.Collections.Generic.List[int]]::new()
        $OutliersRead = $false

        foreach ($Indices in $Paragraphs) {
            # One string per paragraph, each line trimmed and joined with one space, and the
            # offset at which each line starts in it.
            $Builder = [System.Text.StringBuilder]::new()
            $Offsets = [int[]]::new($Indices.Count)

            for ($Member = 0; $Member -lt $Indices.Count; $Member++) {
                $Offsets[$Member] = $Builder.Length
                $null = $Builder.Append($Line[$Indices[$Member]].Trim()).Append(' ')
            }

            $Joined = $Builder.ToString()

            if ($null -eq $AllocateId) {
                $AllocateMatch = $AllocatePattern.Match($Joined)

                if ($AllocateMatch.Success) {
                    $AllocateId = [Convert]::ToInt32($AllocateMatch.Groups[1].Value, 16)
                    $AllocateAddress = [int]$AllocateMatch.Groups[2].Value

                    $Member = $Indices.Count - 1
                    while ($Offsets[$Member] -gt $AllocateMatch.Index) {
                        $Member--
                    }

                    $AllocateLine = $Indices[$Member] + 1
                }
            }

            $OutlierMatch = $OutlierPattern.Match($Joined)

            if (-not $OutliersRead -and $OutlierMatch.Success) {
                $OutliersRead = $true

                # The sentence around the phrase. A sentence ends at '.', '!' or '?' followed by
                # whitespace; the dots inside a token are followed by another dot or a hex digit,
                # never by whitespace, so they do not end one.
                $SentenceStart = 0
                foreach ($Stop in [regex]::Matches($Joined.Substring(0, $OutlierMatch.Index), '[.!?]\s')) {
                    $SentenceStart = $Stop.Index + $Stop.Length
                }

                $SentenceEnd = $Joined.Length
                $EndMatch = [regex]::new('[.!?](?:\s|$)').Match($Joined, $OutlierMatch.Index + $OutlierMatch.Length)
                if ($EndMatch.Success) {
                    $SentenceEnd = $EndMatch.Index + 1
                }

                foreach ($IdMatch in $IdTokenPattern.Matches($Joined.Substring($SentenceStart, $SentenceEnd - $SentenceStart))) {
                    $Outliers.Add([Convert]::ToInt32($IdMatch.Groups[1].Value, 16))
                }
            }
        }

        [PSCustomObject]@{
            HeadingLine     = $(if ($HeadingIndex -ge 0) { $HeadingIndex + 1 } else { $null })
            Rows            = $Rows.ToArray()
            AllocateId      = $AllocateId
            AllocateAddress = $AllocateAddress
            AllocateLine    = $AllocateLine
            Outliers        = $Outliers.ToArray()
        }
    }

    function Get-DocHygieneRegisterFinding {
        <#
            .SYNOPSIS
                Returns one 'line: what' string per defect in a register read by
                Get-DocHygienePlaceholderRegister.

            .DESCRIPTION
                A register is defective when:

                - a row's placeholder cell cannot be read (such a row takes part in no other check);
                - two taken or reserved intervals of the same table overlap;
                - two rows that are not FREE share a slot description, compared trimmed and
                  ignoring case, where '--' is no description and is never compared;
                - a table has not exactly one FREE row;
                - the Allocate sentence names an id or an address other than the start of its
                  table's FREE row, or is missing;
                - a taken or reserved id at or above the Id table's FREE start is not one of the
                  outliers, or a taken or reserved address is at or above the Address table's.

                The last two need exactly one FREE row to compare against; a table without one is
                reported by the check before them instead. A finding names placeholder tokens
                such as '...066' and 'person46', which identify a slot in this register and nothing
                in any tenant, and never quotes a slot description.
        #>
        [OutputType([string])]
        param (
            [Parameter(Mandatory = $true)]
            [object]$Register
        )

        $Findings = [System.Collections.Generic.List[string]]::new()
        $Anchor = $(if ($Register.HeadingLine) { $Register.HeadingLine } else { 0 })

        $FormatToken = {
            param ($Table, $Value)

            if ($Table -eq 'Id') {
                return ('...{0:x3}' -f $Value)
            }

            return ('person{0}' -f $Value)
        }

        $FormatInterval = {
            param ($Table, $Interval)

            if ($Interval[0] -eq $Interval[1]) {
                return (& $FormatToken $Table $Interval[0])
            }

            if ($Interval[1] -eq [int]::MaxValue) {
                return ('{0} and up' -f (& $FormatToken $Table $Interval[0]))
            }

            return ('{0} - {1}' -f (& $FormatToken $Table $Interval[0]), (& $FormatToken $Table $Interval[1]))
        }

        foreach ($Row in @($Register.Rows | Where-Object { $_.Unreadable })) {
            $Findings.Add(("{0}: the placeholder cell cannot be read as tokens, ranges and 'and up' of one kind" -f $Row.Line))
        }

        $Readable = @($Register.Rows | Where-Object { -not $_.Unreadable })
        $Held = @($Readable | Where-Object { $_.Status -ne 'Free' })

        # Repeated slot descriptions, across both tables.
        $SlotLine = @{}
        foreach ($Row in $Held) {
            $Slot = $Row.Slot.Trim().ToLowerInvariant()

            if ($Slot -eq '--' -or $Slot -eq '') {
                continue
            }

            if ($SlotLine.ContainsKey($Slot)) {
                $Findings.Add(('{0}: the slot description repeats the one on line {1}' -f $Row.Line, $SlotLine[$Slot]))
                continue
            }

            $SlotLine[$Slot] = $Row.Line
        }

        foreach ($Table in 'Id', 'Address') {
            $TableRows = @($Readable | Where-Object { $_.Table -eq $Table })
            $TableHeld = @($Held | Where-Object { $_.Table -eq $Table })
            $Free = @($TableRows | Where-Object { $_.Status -eq 'Free' })

            # Overlapping intervals, every pair once, a row's own intervals included.
            $Flat = @(
                foreach ($Row in $TableHeld) {
                    foreach ($Interval in $Row.Intervals) {
                        [PSCustomObject]@{ Interval = $Interval; Line = $Row.Line }
                    }
                }
            )

            for ($First = 0; $First -lt $Flat.Count; $First++) {
                for ($Second = $First + 1; $Second -lt $Flat.Count; $Second++) {
                    $A = $Flat[$First].Interval
                    $B = $Flat[$Second].Interval

                    if ($A[0] -le $B[1] -and $B[0] -le $A[1]) {
                        $Findings.Add(('{0}: the {1} interval {2} overlaps {3} on line {4}' -f $Flat[$Second].Line, $Table, (& $FormatInterval $Table $B), (& $FormatInterval $Table $A), $Flat[$First].Line))
                    }
                }
            }

            if ($Free.Count -ne 1) {
                $Line = $(if ($TableRows.Count -gt 0) { $TableRows[0].Line } else { $Anchor })
                $Findings.Add(('{0}: the {1} table has {2} FREE rows, not exactly one' -f $Line, $Table, $Free.Count))
                continue
            }

            $FreeStart = [int]::MaxValue
            foreach ($Interval in $Free[0].Intervals) {
                if ($Interval[0] -lt $FreeStart) {
                    $FreeStart = $Interval[0]
                }
            }

            $Allocate = $(if ($Table -eq 'Id') { $Register.AllocateId } else { $Register.AllocateAddress })

            if ($null -eq $Allocate -or $Allocate -ne $FreeStart) {
                $Named = $(if ($null -eq $Allocate) { 'nothing' } else { & $FormatToken $Table $Allocate })
                $Line = $(if ($Register.AllocateLine) { $Register.AllocateLine } else { $Anchor })
                $Findings.Add(('{0}: the Allocate sentence names {1} for the {2} table, whose FREE row starts at {3}' -f $Line, $Named, $Table, (& $FormatToken $Table $FreeStart)))
            }

            foreach ($Row in $TableHeld) {
                foreach ($Interval in $Row.Intervals) {
                    if ($Interval[1] -lt $FreeStart) {
                        continue
                    }

                    if ($Table -eq 'Address') {
                        $Findings.Add(('{0}: the Address slot {1} is held at or above the FREE start {2}' -f $Row.Line, (& $FormatInterval $Table $Interval), (& $FormatToken $Table $FreeStart)))
                        continue
                    }

                    if ($Interval[0] -eq $Interval[1] -and @($Register.Outliers) -contains $Interval[0]) {
                        continue
                    }

                    $Findings.Add(('{0}: the Id slot {1} is held at or above the FREE start {2} and is not a named outlier' -f $Row.Line, (& $FormatInterval $Table $Interval), (& $FormatToken $Table $FreeStart)))
                }
            }
        }

        return $Findings
    }

    function Get-DocHygieneUnregisteredPlaceholderLocation {
        <#
            .SYNOPSIS
                Returns 'path:line' for every placeholder in File that Register does not show as taken.

            .DESCRIPTION
                An all-zeros object id is a register placeholder when the last twelve hex digits
                start with nine zeros; its slot is the last three, read as hex, and it must fall in
                a TAKEN interval of the Id table. Any other tail is reported too: it has the
                placeholder's shape without being one the register can hand out. A
                personN@example.com address must fall in a TAKEN interval of the Address table.

                Reserved and FREE are both reported. A reserved slot was set aside so that it is
                never used, and a FREE one used without a row is exactly the state the next person
                allocates over. Unreadable rows grant nothing.

                The matched value is never returned, only its location.
        #>
        [OutputType([string])]
        param (
            [Parameter(Mandatory = $true)]
            [AllowEmptyCollection()]
            [object[]]$File,

            [Parameter(Mandatory = $true)]
            [object]$Register
        )

        $GuidPattern = [regex]'(?i)00000000-0000-0000-0000-([0-9a-f]{12})'
        $AddressPattern = [regex]'(?i)(?<![A-Za-z0-9._%+-])person(\d+)@example\.com'

        $Taken = @($Register.Rows | Where-Object { $_.Status -eq 'Taken' -and -not $_.Unreadable })
        $TakenId = @(foreach ($Row in @($Taken | Where-Object { $_.Table -eq 'Id' })) { $Row.Intervals })
        $TakenAddress = @(foreach ($Row in @($Taken | Where-Object { $_.Table -eq 'Address' })) { $Row.Intervals })

        $IsInside = {
            param ($Value, $Intervals)

            foreach ($Interval in $Intervals) {
                if ($Value -ge $Interval[0] -and $Value -le $Interval[1]) {
                    return $true
                }
            }

            return $false
        }

        $Locations = [System.Collections.Generic.List[string]]::new()

        foreach ($Entry in $File) {
            for ($Index = 0; $Index -lt $Entry.Lines.Count; $Index++) {
                $Text = $Entry.Lines[$Index]

                foreach ($Match in $GuidPattern.Matches($Text)) {
                    $Tail = $Match.Groups[1].Value

                    if ($Tail.StartsWith('000000000') -and (& $IsInside ([Convert]::ToInt32($Tail.Substring(9), 16)) $TakenId)) {
                        continue
                    }

                    $Locations.Add(('{0}:{1}' -f $Entry.RelativePath, ($Index + 1)))
                }

                foreach ($Match in $AddressPattern.Matches($Text)) {
                    $Number = 0L

                    if ([long]::TryParse($Match.Groups[1].Value, [ref]$Number) -and (& $IsInside $Number $TakenAddress)) {
                        continue
                    }

                    $Locations.Add(('{0}:{1}' -f $Entry.RelativePath, ($Index + 1)))
                }
            }
        }

        return $Locations
    }
}

Describe 'Documentation hygiene' -Tags 'DocHygiene' {

    It 'Should scope the scan to every tracked file under docs/, specs/, source/ and tests/' {
        if ($script:DocHygieneSkipReason) {
            Set-ItResult -Skipped -Because $script:DocHygieneSkipReason
            return
        }

        # The emptiness guard in the checks below cannot see a scope that silently NARROWS: a
        # pattern reverted to docs/live-verification/ still enumerates files, and every check still
        # passes on them. The assertions here fail on exactly that.
        # docs/examples/example-structure.json is named on purpose: .gitignore allowlists it, so it
        # is the one file outside the checklists that must always be tracked, and its absence from
        # the scope can only mean the scope stopped reaching it. The remaining assertions catch the
        # opposite narrowing -- a pattern such as '^docs/examples/' keeps the example and drops the
        # checklists or the two code trees added when the repository was published.
        $InScope = @($script:DocHygieneFiles | ForEach-Object { $_.RelativePath })

        $InScope | Should -Contain 'docs/examples/example-structure.json' -Because 'the scan must reach the tracked apply-document example; if it does not, it quietly stopped covering all of docs/'

        @($InScope | Where-Object { $_ -notlike 'docs/live-verification/*' }).Count |
            Should -BeGreaterThan 0 -Because 'at least one tracked file outside docs/live-verification/ must be in scope; zero means the scan narrowed back to the checklists'

        @($InScope | Where-Object { $_ -like 'docs/live-verification/*' }).Count |
            Should -BeGreaterThan 0 -Because 'the live-verification checklists must stay in scope; zero means the scan narrowed away from the folder where tenant output is pasted on purpose'

        # The two code trees. source/ ships inside the built module and tests/ lands in the public
        # repository, so a scope that stops reaching either one is the widening silently undone.
        $InScope | Should -Contain 'source/Omnicit.EntraRBAC.psd1' -Because 'the manifest must be in scope; if it is not, the scan stopped covering source/'

        @($InScope | Where-Object { $_ -like 'source/Public/*' }).Count |
            Should -BeGreaterThan 0 -Because 'the exported cmdlets must stay in scope; zero means the scan narrowed away from the payload that ships to every installed copy'

        @($InScope | Where-Object { $_ -like 'tests/Unit/*' }).Count |
            Should -BeGreaterThan 0 -Because 'the unit tests must stay in scope; zero means the scan narrowed away from the tree that carries the fixtures'

        # The code-scope classification is what decides which object-id rule each file gets. A
        # classifier that marked everything prose would leave the v4 rule enforcing nothing while
        # every check still passed.
        @($script:DocHygieneFiles | Where-Object { $_.IsCode }).Count |
            Should -BeGreaterThan 0 -Because 'at least one in-scope file must be classified as CODE; zero means the code-scope pattern stopped matching and the version-4 rule is inert'

        @($script:DocHygieneFiles | Where-Object { -not $_.IsCode }).Count |
            Should -BeGreaterThan 0 -Because 'at least one in-scope file must be classified as PROSE; zero means the placeholder rule is inert'
    }

    It 'Should hold no stale entry in the public-constant register' {
        if ($script:DocHygieneSkipReason) {
            Set-ItResult -Skipped -Because $script:DocHygieneSkipReason
            return
        }

        $script:DocHygieneFiles.Count |
            Should -BeGreaterThan 0 -Because 'this gate must measure at least one tracked file; zero files means the enumeration failed and the check ran on nothing'

        # A register entry is a standing permission for one exact value. An entry whose value has
        # left the tree is a permission nobody is watching any more, and the next value that needs
        # one gets written next to it rather than questioned. So an unused entry is a FAILURE, not
        # a tidy-up: the register shrinks by being enforced.
        #
        # THIS FILE IS EXCLUDED FROM THE SEARCH, and the exclusion is the whole check. The register
        # is declared here, inside a file that is itself in scope, so every entry trivially "still
        # appears in the tree" -- in its own declaration. Measured: without this exclusion a
        # deliberately stale entry planted by the mutation harness passed. A declaration cannot be
        # its own evidence.
        $SelfPath = 'tests/QA/dochygiene.tests.ps1'

        @($script:DocHygieneFiles | Where-Object { $_.RelativePath -eq $SelfPath }).Count |
            Should -Be 1 -Because 'the exclusion below names this gate file by path; if the name stops matching, the exclusion silently does nothing and every register entry vouches for itself again'

        $Evidence = @($script:DocHygieneFiles | Where-Object { $_.RelativePath -ne $SelfPath })

        $Unused = @(
            foreach ($Constant in $script:DocHygienePublicConstant) {
                $Seen = $false

                foreach ($Entry in $Evidence) {
                    if ($Entry.Lines -match [regex]::Escape($Constant.Value)) {
                        $Seen = $true
                        break
                    }
                }

                if (-not $Seen) {
                    $Constant.Reason
                }
            }
        )

        $Unused | Should -BeNullOrEmpty -Because (
            'every entry in the public-constant register must still be present in the tree; remove the entry rather than leaving a standing permission nobody reads. Unused: {0}' -f ($Unused -join '; '))

        # An entry that is not v4-shaped would already pass the code-scope rule on its own, so it is
        # a permission that grants nothing and only makes the register look longer than it is.
        $Unnecessary = @(
            $script:DocHygienePublicConstant |
                Where-Object { -not (Test-DocHygieneVersion4Guid -Value $_.Value) } |
                ForEach-Object { $_.Reason }
        )

        $Unnecessary | Should -BeNullOrEmpty -Because (
            'the register exists only to permit version-4 GUIDs; a non-v4 entry already passes and must be deleted. Unnecessary: {0}' -f ($Unnecessary -join '; '))
    }

    It 'Should carry no object id outside the placeholder range in any tracked file under docs/ or specs/' {
        if ($script:DocHygieneSkipReason) {
            Set-ItResult -Skipped -Because $script:DocHygieneSkipReason
            return
        }

        # Emptiness guard. Zero in-scope files means the enumeration broke, not that the tree is
        # clean, and a check that passes on nothing at all is worse than no check at all. It counts
        # PROSE files specifically: the widening to source/ and tests/ means a total count above
        # zero no longer proves this check measured anything it applies to.
        $Prose = @($script:DocHygieneFiles | Where-Object { -not $_.IsCode })

        $Prose.Count |
            Should -BeGreaterThan 0 -Because 'this check must measure at least one tracked PROSE file under docs/ or specs/; zero files means the enumeration failed and the check ran on nothing'

        # Deliberately unanchored: a GUID embedded in a longer token still matches, so the scan errs
        # towards RED. A placeholder is any id whose first THREE groups are all zeros -- no real
        # Entra object id has that shape.
        $GuidPattern = [regex]'[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}'
        $IsPlaceholder = {
            param ($Value, $Entry)

            $Value.StartsWith('00000000-0000-0000-', [System.StringComparison]::OrdinalIgnoreCase)
        }

        # AcrossLineBreak: a table cell pasted from a console wraps at the column edge, and a real
        # id split over two lines, the second one indented, matched neither line on its own and
        # stayed in a checklist on main. The second pass reads the file with the breaks removed.
        $Hits = @(Get-DocHygieneMatchLocation -File $Prose -Pattern $GuidPattern -IsAllowed $IsPlaceholder -AcrossLineBreak)

        # Double-wrapped on purpose. '$null.Count' is 0 and would pass vacuously; '@($null).Count'
        # is 1 and fails red. Both are recorded traps in this repository.
        @($Hits).Count |
            Should -Be 0 -Because ('every tenant object id in a tracked file under docs/ or specs/ must be a 00000000-0000-0000-0000-0000000000NN placeholder (see docs/live-verification/README.md). Redact these locations, values deliberately not shown: {0}' -f ($Hits -join ', '))
    }

    It 'Should carry no version-4 object id in any tracked file under source/ or tests/' {
        if ($script:DocHygieneSkipReason) {
            Set-ItResult -Skipped -Because $script:DocHygieneSkipReason
            return
        }

        $Code = @($script:DocHygieneFiles | Where-Object { $_.IsCode })

        $Code.Count |
            Should -BeGreaterThan 0 -Because 'this check must measure at least one tracked CODE file under source/ or tests/; zero files means the enumeration failed and the check ran on nothing'

        # See the PROSE SCOPE vs CODE SCOPE block above for why the rule is version-4 shape here and
        # the placeholder range under docs/. In short: every real Entra and ARM id is v4, no
        # invented fixture in this repository is, and the roughly seventy existing fixtures are
        # readable precisely because they are not all the same shape.
        $GuidPattern = [regex]'[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}'
        $RegisteredValue = @($script:DocHygienePublicConstant | ForEach-Object { $_.Value })

        $IsNotIdentifierShaped = {
            param ($Value, $Entry)

            if (-not (Test-DocHygieneVersion4Guid -Value $Value)) {
                return $true
            }

            foreach ($Registered in $RegisteredValue) {
                if ($Value -eq $Registered) {
                    return $true
                }
            }

            return $false
        }

        # The same wrapped-value pass as the prose check: an id split over two lines in a comment
        # or a here-string is as much a leak as one written on a single line.
        $Hits = @(Get-DocHygieneMatchLocation -File $Code -Pattern $GuidPattern -IsAllowed $IsNotIdentifierShaped -AcrossLineBreak)

        @($Hits).Count |
            Should -Be 0 -Because ('no tracked file under source/ or tests/ may carry a version-4 GUID: every Entra ID and ARM object id is v4, so one here is either a real identifier or a fixture typed to look like one. Replace it with a 00000000-0000-0000-0000-0000000000NN placeholder and record it in docs/live-verification/README.md -- do NOT add it to the public-constant register. Locations, values deliberately not shown: {0}' -f ($Hits -join ', '))
    }

    It 'Should carry no email address outside example.com and contoso.com in any tracked file in scope' {
        if ($script:DocHygieneSkipReason) {
            Set-ItResult -Skipped -Because $script:DocHygieneSkipReason
            return
        }

        $script:DocHygieneFiles.Count |
            Should -BeGreaterThan 0 -Because 'this gate must measure at least one tracked file; zero files means the enumeration failed and the check ran on nothing'

        # Unlike the object-id rule, this one does NOT split by scope. A user principal name is a
        # real person either way, and nothing in source/ or tests/ needs one: the fixtures already
        # use personN@example.com.
        @($script:DocHygieneFiles | Where-Object { $_.IsCode }).Count |
            Should -BeGreaterThan 0 -Because 'the code trees must be measured by this check too; zero means the scope stopped reaching source/ and tests/'

        $EmailPattern = [regex]'[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}'
        $IsAllowedDomain = {
            param ($Value, $Entry)

            $Domain = $Value.Substring($Value.LastIndexOf('@') + 1)

            foreach ($Allowed in @('example.com', 'contoso.com')) {
                # The reserved documentation domains, and their subdomains. No real address lives
                # under either, so allowing a subdomain costs nothing.
                if ($Domain -eq $Allowed -or $Domain.EndsWith(('.' + $Allowed), [System.StringComparison]::OrdinalIgnoreCase)) {
                    return $true
                }
            }

            return $false
        }

        $Hits = @(Get-DocHygieneMatchLocation -File $script:DocHygieneFiles -Pattern $EmailPattern -IsAllowed $IsAllowedDomain)

        @($Hits).Count |
            Should -Be 0 -Because ('every email address in a tracked file under docs/, specs/, source/ or tests/ must be personN@example.com, or an address on contoso.com (see docs/live-verification/README.md). Redact these locations, values deliberately not shown: {0}' -f ($Hits -join ', '))
    }

    It 'Should carry no tenant domain outside the fixed allowlist in any tracked file in scope' {
        if ($script:DocHygieneSkipReason) {
            Set-ItResult -Skipped -Because $script:DocHygieneSkipReason
            return
        }

        $script:DocHygieneFiles.Count |
            Should -BeGreaterThan 0 -Because 'this gate must measure at least one tracked file; zero files means the enumeration failed and the check ran on nothing'

        # Like the email rule, this one does not split by scope: a tenant's initial domain names the
        # same customer in a checklist, in help text and in a test fixture.
        @($script:DocHygieneFiles | Where-Object { $_.IsCode }).Count |
            Should -BeGreaterThan 0 -Because 'the code trees must be measured by this check too; zero means the scope stopped reaching source/ and tests/'

        # Known answer. A pattern edited into one that never matches, a normalization step dropped,
        # or an allowlist test that lets everything through all leave this check green on every
        # file, so a fixed sample proves it still finds what it is for. Lines 3, 4, 5 and 7 are the
        # hits: a plain address, a URL-encoded one, the regular-expression form and the 21Vianet
        # suffix. Line 2 is allowed only once its '%40' is read as '@', and line 6 is the bare
        # suffix with no label in front of it.
        #
        # Every sample is built by CONCATENATION. This file is in scope too, and a sample written
        # out whole would put a tenant domain on one of its own lines.
        $Suffix = '.onmicrosoft' + '.com'
        $Sample = @(
            ('user@contoso' + $Suffix)
            ('person1_example.com%23EXT%23%40fabrikam' + $Suffix)
            ('admin@leak' + $Suffix)
            ('x%40leak' + $Suffix)
            ('leak' + '\.onmicrosoft' + '\.com')
            ('its ' + 'onmicrosoft' + '.com name')
            ('tenant.' + 'onmschina' + '.cn')
            ('contoso.onmicrosoft' + '.us')
        )

        $SampleHits = @(
            Get-DocHygieneTenantDomainUse -File @([PSCustomObject]@{ RelativePath = 'sample'; Lines = $Sample }) |
                Where-Object { -not (Test-DocHygieneTenantLabelAllowed -Label $_.Label) } |
                ForEach-Object { $_.Location }
        )

        ($SampleHits -join ', ') |
            Should -Be 'sample:3, sample:4, sample:5, sample:7' -Because 'the known-answer sample must yield exactly its four tenant domains outside the allowlist; anything else means the scan stopped finding a form, stopped normalizing one, or stopped consulting the allowlist'

        $Hits = @(
            Get-DocHygieneTenantDomainUse -File $script:DocHygieneFiles |
                Where-Object { -not (Test-DocHygieneTenantLabelAllowed -Label $_.Label) } |
                ForEach-Object { $_.Location }
        )

        # Locations only, like every other rule here: the label IS the tenant's name.
        @($Hits).Count |
            Should -Be 0 -Because ('no tracked file under docs/, specs/, source/ or tests/ may carry a tenant domain (.onmicrosoft.com, .onmicrosoft.us or .onmschina.cn) whose label is outside the fixed allowlist of fictional tenants. Replace the label with contoso; do not add it to the allowlist. Locations, values deliberately not shown: {0}' -f ($Hits -join ', '))
    }

    It 'Should hold no stale entry in the tenant-domain allowlist' {
        if ($script:DocHygieneSkipReason) {
            Set-ItResult -Skipped -Because $script:DocHygieneSkipReason
            return
        }

        $script:DocHygieneFiles.Count |
            Should -BeGreaterThan 0 -Because 'this gate must measure at least one tracked file; zero files means the enumeration failed and the check ran on nothing'

        # The same reasoning as the public-constant register: an allowlisted label that no file uses
        # any more is a standing permission nobody reads, and the next label that wants one gets
        # written next to it rather than questioned. An unused entry is a FAILURE.
        #
        # THIS FILE IS EXCLUDED FROM THE EVIDENCE for the same reason too. The allowlist is
        # declared here, and a comment or a sample written out whole in this file would make an
        # entry vouch for itself. Only a use somewhere else in the tree keeps an entry alive.
        $SelfPath = 'tests/QA/dochygiene.tests.ps1'

        @($script:DocHygieneFiles | Where-Object { $_.RelativePath -eq $SelfPath }).Count |
            Should -Be 1 -Because 'the exclusion below names this gate file by path; if the name stops matching, the exclusion silently does nothing and an allowlist entry could vouch for itself'

        $Evidence = @($script:DocHygieneFiles | Where-Object { $_.RelativePath -ne $SelfPath })
        $Seen = @(Get-DocHygieneTenantDomainUse -File $Evidence | ForEach-Object { $_.Label })

        # -notcontains compares without regard to case, as the allowlist test itself does.
        $Unused = @($script:DocHygieneTenantLabelAllowlist | Where-Object { $Seen -notcontains $_ })

        # Naming an unused entry is safe here: it is one of the fictional labels this file already
        # declares, not a value found in the tree.
        $Unused | Should -BeNullOrEmpty -Because (
            'every label on the tenant-domain allowlist must still be used by a tracked file in scope other than this one; remove the entry rather than leaving a standing permission nobody reads. Unused: {0}' -f ($Unused -join '; '))
    }

    It 'Should read the placeholder register and find each kind of defect (known answer)' {
        # No skip guard: this It reads no tracked file, only the sample declared in BeforeAll, so it
        # measures the same thing with or without git.
        $Correct = @($script:DocHygieneSampleRegister -split '\r?\n')
        $Register = Get-DocHygienePlaceholderRegister -Line $Correct

        # The reader, field by field. Ids are HEX: '...045' is 69, '...0aa' 170 and '...abc' 2748.
        # 'up' is an 'and up' row's open end. The row after the section's end (line 31) must not
        # be here, and neither must the two header rows of each table.
        $RowText = @(
            foreach ($Row in $Register.Rows) {
                $Intervals = @(
                    foreach ($Interval in $Row.Intervals) {
                        '{0}-{1}' -f $Interval[0], $(if ($Interval[1] -eq [int]::MaxValue) { 'up' } else { $Interval[1] })
                    }
                )

                '{0}:{1}:{2}:{3}' -f $Row.Line, $Row.Table, $Row.Status, ($Intervals -join ',')
            }
        )

        ($RowText -join '; ') |
            Should -Be '9:Id:Taken:0-69; 10:Id:Taken:70-70; 11:Id:Taken:71-71; 12:Id:Free:102-up; 13:Id:Taken:153-153; 14:Id:Taken:170-170; 15:Id:Taken:2748-2748; 21:Address:Taken:1-13,15-45; 22:Address:Reserved:14-14; 23:Address:Free:46-up' -Because 'the reader must return every register row with its table, status and intervals, ids read as hex, and stop at the next heading'

        @($Register.Rows | Where-Object { $_.Unreadable }).Count |
            Should -Be 0 -Because 'every placeholder cell in the correct sample is well formed'

        $Register.Rows[0].Slot |
            Should -Be 'the per-file numbering and the any-id stand-in' -Because 'the slot is the second cell, trimmed'

        $Register.AllocateId | Should -Be 102 -Because 'the Allocate sentence names ...066 for object ids, read as hex, across a line break'
        $Register.AllocateAddress | Should -Be 46 -Because 'the Allocate sentence names person46 for addresses, on the line after the one it starts on'
        $Register.AllocateLine | Should -Be 26 -Because 'the Allocate sentence starts on line 26'

        ((@($Register.Outliers) | Sort-Object) -join ',') |
            Should -Be '153,170,2748' -Because 'the outliers are the three ids named in the sentence about the counting sequence, which wraps over two lines'

        $CorrectFindings = @(Get-DocHygieneRegisterFinding -Register $Register)

        @($CorrectFindings).Count |
            Should -Be 0 -Because ('the correct sample register has no defect, so any finding is a false positive: {0}' -f ($CorrectFindings -join '; '))

        # One of each kind of defect, each made by one edit to the correct copy, so the sample shows
        # exactly what changed. A typo in an edit leaves its defect out and turns this RED, which
        # is the right direction.
        $Defective = $script:DocHygieneSampleRegister
        foreach ($Edit in @(
                # Line 10: 'to' is not a range, so the cell cannot be read.
                , @('| `...046` |', '| `...046` to `...048` |')
                # Line 11: ...040 sits inside ...000 - ...045 on line 9.
                , @('| `...047` |', '| `...040` |')
                # Line 13: ...099 is no longer named an outlier, and is above the FREE start.
                , @('`...0aa`, `...abc` and `...099` sit outside', '`...0aa` and `...abc` sit outside')
                # Line 15: the description of line 14, in another case and with other spacing.
                , @('| an administrative unit id |', '|  An Assignment Target Principal ID  |')
                # Line 21: person14 marked FREE too, so the Address table has two FREE rows.
                , @('| allocated and never used; left reserved, do not reuse |', '| **FREE.** |')
                # Line 26: the Allocate sentence disagrees with the Id table's FREE row.
                , @('object ids from `...066`', 'object ids from `...067`')
            )) {
            $Defective = $Defective.Replace($Edit[0], $Edit[1])
        }

        $Expected = @(
            "10: the placeholder cell cannot be read as tokens, ranges and 'and up' of one kind"
            '11: the Id interval ...040 overlaps ...000 - ...045 on line 9'
            '13: the Id slot ...099 is held at or above the FREE start ...066 and is not a named outlier'
            '15: the slot description repeats the one on line 14'
            '21: the Address table has 2 FREE rows, not exactly one'
            '26: the Allocate sentence names ...067 for the Id table, whose FREE row starts at ...066'
        )

        $Findings = @(Get-DocHygieneRegisterFinding -Register (Get-DocHygienePlaceholderRegister -Line @($Defective -split '\r?\n')))

        ((@($Findings) | Sort-Object) -join ' | ') |
            Should -Be ((@($Expected) | Sort-Object) -join ' | ') -Because 'the defective sample must yield exactly one finding per kind of defect; a missing one means that check stopped looking, an extra one that a check fires on what it should not'

        # The two kinds with an Id half and an Address half: the sample above exercises the Id
        # halves, and its Address table has two FREE rows, which leaves nothing to compare the
        # Address halves against. This sample keeps the Id table correct and breaks only those.
        $AddressDefective = $script:DocHygieneSampleRegister
        foreach ($Edit in @(
                # Line 22: a reserved address at or above the FREE start person46.
                , @('| `person14` |', '| `person50` |')
                # Line 26 (the sentence's first line): the address it names is not the FREE start.
                , @('from `person46`, and add', 'from `person47`, and add')
            )) {
            $AddressDefective = $AddressDefective.Replace($Edit[0], $Edit[1])
        }

        $AddressExpected = @(
            '22: the Address slot person50 is held at or above the FREE start person46'
            '26: the Allocate sentence names person47 for the Address table, whose FREE row starts at person46'
        )

        $AddressFindings = @(Get-DocHygieneRegisterFinding -Register (Get-DocHygienePlaceholderRegister -Line @($AddressDefective -split '\r?\n')))

        ((@($AddressFindings) | Sort-Object) -join ' | ') |
            Should -Be ((@($AddressExpected) | Sort-Object) -join ' | ') -Because 'the address sample must yield exactly the Address halves of the Allocate and FREE-start checks'
    }

    It 'Should keep the placeholder register in docs/live-verification/README.md consistent' {
        if ($script:DocHygieneSkipReason) {
            Set-ItResult -Skipped -Because $script:DocHygieneSkipReason
            return
        }

        # The register is read from the tracked copy in scope, like every other file here. A
        # register that is not found means the path moved or the scope narrowed, and a check that
        # reads nothing finds nothing wrong.
        $RegisterPath = 'docs/live-verification/README.md'
        $RegisterFile = @($script:DocHygieneFiles | Where-Object { $_.RelativePath -eq $RegisterPath })

        $RegisterFile.Count |
            Should -Be 1 -Because ('the placeholder register lives in {0}, a tracked file in scope; without it this check reads nothing' -f $RegisterPath)

        $Register = Get-DocHygienePlaceholderRegister -Line $RegisterFile[0].Lines

        # Emptiness guards, one per table. A heading renamed, or a table reshaped past what the
        # reader recognizes, leaves no rows -- and a register with no rows has no defect to find.
        @($Register.Rows | Where-Object { $_.Table -eq 'Id' }).Count |
            Should -BeGreaterThan 0 -Because 'the register must yield at least one object-id row; zero means the section heading or the table moved and the check ran on nothing'

        @($Register.Rows | Where-Object { $_.Table -eq 'Address' }).Count |
            Should -BeGreaterThan 0 -Because 'the register must yield at least one address row; zero means the address table moved and the check ran on nothing'

        $Findings = @(Get-DocHygieneRegisterFinding -Register $Register | ForEach-Object { '{0}:{1}' -f $RegisterPath, $_ })

        @($Findings).Count |
            Should -Be 0 -Because ('the placeholder register must agree with itself: no overlapping rows, no repeated slot description, exactly one FREE row per table, an Allocate sentence that names those FREE starts, and nothing taken at or above a FREE start except the named outliers. Fix the register: {0}' -f ($Findings -join '; '))
    }

    It 'Should register every placeholder used in source/, tests/, docs/examples/ and docs/development/' {
        if ($script:DocHygieneSkipReason) {
            Set-ItResult -Skipped -Because $script:DocHygieneSkipReason
            return
        }

        # The register's GLOBAL rule covers exactly these four trees. A live-verification checklist
        # numbers its placeholders per file, from 01, so the same placeholder there means a
        # different object in each checklist and is not the register's to allocate.
        $UsageScopePattern = '^(source|tests|docs/examples|docs/development)/'
        $Used = @($script:DocHygieneFiles | Where-Object { $_.RelativePath -match $UsageScopePattern })

        # Emptiness and narrowing guards: every one of the four trees must still be read.
        foreach ($Tree in 'source/', 'tests/', 'docs/examples/', 'docs/development/') {
            @($Used | Where-Object { $_.RelativePath.StartsWith($Tree) }).Count |
                Should -BeGreaterThan 0 -Because ('this check must read at least one tracked file under {0}; zero means its scope narrowed and that tree went unchecked' -f $Tree)
        }

        $RegisterPath = 'docs/live-verification/README.md'
        $RegisterFile = @($script:DocHygieneFiles | Where-Object { $_.RelativePath -eq $RegisterPath })

        $RegisterFile.Count |
            Should -Be 1 -Because ('the placeholder register lives in {0}, a tracked file in scope; without it every placeholder would read as unregistered' -f $RegisterPath)

        $Register = Get-DocHygienePlaceholderRegister -Line $RegisterFile[0].Lines

        @($Register.Rows | Where-Object { $_.Table -eq 'Id' -and $_.Status -eq 'Taken' }).Count |
            Should -BeGreaterThan 0 -Because 'the register must yield at least one taken object-id row; zero means the reader found no table to check against'

        @($Register.Rows | Where-Object { $_.Table -eq 'Address' -and $_.Status -eq 'Taken' }).Count |
            Should -BeGreaterThan 0 -Because 'the register must yield at least one taken address row; zero means the reader found no table to check against'

        # Known answer, against the SAMPLE register in BeforeAll rather than the real one, so that
        # allocating the next slot never turns it red. Lines 2, 4 and 6 are the hits: a FREE id
        # slot, a tail that is not a register placeholder at all, and a RESERVED address. Lines 1,
        # 3 and 5 are taken slots -- 5 one of the hex outliers -- and pass.
        #
        # Every sample is built by CONCATENATION. This file is in scope too, and a placeholder
        # written out whole would be a use of it on one of its own lines.
        $Prefix = '00000000-0000-0000-0000-'
        $Sample = @(
            ('id ' + $Prefix + '000000000' + '046')
            ($Prefix + '000000000' + '077')
            ('person' + '1' + '@example.com')
            ($Prefix + '100000000' + '046')
            ($Prefix + '000000000' + 'abc')
            ('person' + '14' + '@example.com')
        )

        $SampleRegister = Get-DocHygienePlaceholderRegister -Line @($script:DocHygieneSampleRegister -split '\r?\n')
        $SampleHits = @(Get-DocHygieneUnregisteredPlaceholderLocation -File @([PSCustomObject]@{ RelativePath = 'sample'; Lines = $Sample }) -Register $SampleRegister)

        ($SampleHits -join ', ') |
            Should -Be 'sample:2, sample:4, sample:6' -Because 'the known-answer sample must yield exactly its FREE id slot, its non-register tail and its reserved address; anything else means the scan stopped reading the register, or stopped finding a placeholder'

        $Hits = @(Get-DocHygieneUnregisteredPlaceholderLocation -File $Used -Register $Register)

        @($Hits).Count |
            Should -Be 0 -Because ('every placeholder used in source/, tests/, docs/examples/ or docs/development/ must be registered as taken in {0}, in the same commit that uses it: allocate from the FREE row, add a row with a unique slot description, and move the Allocate sentence on. Locations, values deliberately not shown: {1}' -f $RegisterPath, ($Hits -join ', '))
    }

    It 'Should carry no credential in any tracked file in scope' {
        if ($script:DocHygieneSkipReason) {
            Set-ItResult -Skipped -Because $script:DocHygieneSkipReason
            return
        }

        $script:DocHygieneFiles.Count |
            Should -BeGreaterThan 0 -Because 'this gate must measure at least one tracked file; zero files means the enumeration failed and the check ran on nothing'

        @($script:DocHygieneFiles | Where-Object { $_.IsCode }).Count |
            Should -BeGreaterThan 0 -Because 'the code trees must be measured by this check too; zero means the scope stopped reaching source/ and tests/'

        # =================================================================================
        # WHY THIS EXISTS SEPARATELY FROM THE TWO CHECKS ABOVE.
        #
        # An object id is a NAME. A credential is ACCESS. Redacting an id after the fact closes the
        # leak; redacting a credential after the fact does not -- the value was already committed,
        # already pushed, and already in every clone and every CI cache that fetched the branch.
        # A credential that reaches a tracked file is ROTATED, never merely redacted, and the
        # README says so. This gate exists to catch the paste before it becomes a rotation.
        #
        # Live console output is exactly where credentials arrive by accident: an app registration's
        # client secret pasted into a setup section so the run can be repeated, and -- the case that
        # motivated this check -- an ErrorRecord whose TargetObject is the raw HttpRequestMessage,
        # which renders 'Authorization: Bearer <jwt>' in full when a failed Graph read is
        # transcribed. Neither of the two checks above would see either one: a JWT holds no GUID in
        # the shape they match, and no email address.
        #
        # UNDER tests/ THE SAME SHAPE IS REQUIRED, not accidental. The bearer-scrub regression tests
        # have to hand the module something token-shaped in order to prove the scrub removes it, so
        # a rule of 'no token shape here' would delete the module's most important security tests.
        # The rule instead is that a credential-shaped literal must SAY IT IS NOT ONE, in the value
        # itself -- see the marker below. A real token pasted while debugging cannot satisfy that by
        # accident, and a fixture satisfies it by being written down honestly.
        # =================================================================================
        # Every pattern here matches a credential VALUE, never the mere mention of one. A checklist
        # has to be able to say the words 'Authorization: Bearer' in prose, and to quote a captured
        # record with the value replaced by a '<...>' stand-in -- that SHAPE is often the finding
        # being written up. What none of them may carry is a run of credential characters.
        $CredentialPatterns = @(
            # A JWT: 'eyJ' (the base64url of '{"') followed by more base64url, the '.' that
            # separates header from payload, and the payload itself. Every bearer token this module
            # handles has this shape, and the prefix is specific enough that prose never trips it.
            # The match deliberately SPANS the payload rather than stopping at the dot, so that the
            # marker below -- which a fixture carries in its payload, the only place it can go
            # without breaking the header -- is inside the matched value.
            [regex]'eyJ[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{0,512}'

            # An Authorization header followed by an actual value: an optional scheme, then a long
            # unbroken run of token characters. '<token>', '<...-REDACTED>' and a backtick-quoted
            # mention all stop at the first character outside the class, so they do not match, while
            # a real header pasted out of an ErrorRecord does.
            [regex]'(?i)Authorization:\s*(?:Bearer|Basic|Negotiate)?\s*[A-Za-z0-9+/=_.~-]{16,}'

            # The same value without the header name -- a bearer token quoted on its own.
            [regex]'(?i)Bearer\s+[A-Za-z0-9+/=_.~-]{16,}'

            # An Entra client secret as the portal renders it: a short prefix, a '~', then a long
            # run of base64url-ish characters. The '~' at that position is the distinctive part --
            # no object id, URL or PowerShell fragment in these files has one.
            [regex]'[A-Za-z0-9._-]{2,6}~[A-Za-z0-9._~-]{25,}'
        )

        # A value that declares itself is not a credential. REDACTED is the documented way to keep a
        # captured record's shape without its value; NOT-A-REAL-TOKEN is the same declaration made
        # by a test fixture that has to be token-shaped to do its job. Both are matched inside the
        # VALUE, not on the surrounding line, so the declaration belongs to that literal and cannot
        # be borrowed by a real token that happens to sit next to one.
        $IsDeclaredNotACredential = {
            param ($Value, $Entry)

            return ($Value -match '(?i)REDACTED|NOT-A-REAL-TOKEN')
        }

        $Hits = @(
            foreach ($Pattern in $CredentialPatterns) {
                Get-DocHygieneMatchLocation -File $script:DocHygieneFiles -Pattern $Pattern -IsAllowed $IsDeclaredNotACredential
            }
        )

        # Locations only. Rendering the matched value here would print the credential into every CI
        # log of every red run -- the same trap the two checks above avoid, and a worse one, since
        # this value grants access rather than merely naming an object.
        @($Hits).Count |
            Should -Be 0 -Because ('no tracked file under docs/, specs/, source/ or tests/ may contain a credential -- a JWT, an Authorization header with a value, or a client secret (see docs/live-verification/README.md). A credential that reached a tracked file is ROTATED, not just redacted. A test fixture that must be token-shaped says so in the value, with NOT-A-REAL-TOKEN. Locations, values deliberately not shown: {0}' -f (@($Hits | Sort-Object -Unique) -join ', '))
    }

    It 'Should carry no angle bracket that renders as an HTML tag outside code in any tracked Markdown file in scope' {
        if ($script:DocHygieneSkipReason) {
            Set-ItResult -Skipped -Because $script:DocHygieneSkipReason
            return
        }

        # GitHub reads '<word>', '</word>', '<!...>' and '<?...>' outside code as markup and renders
        # nothing in its place. In a checklist that is a redacted stand-in vanishing from the
        # record; a word missing from CHANGELOG.md on GitHub and from the GitHub release body built
        # from it. Fenced blocks and code spans are skipped by ConvertTo-DocHygieneMarkdownProse, a
        # backslash before the bracket escapes it, and what is left must hold no tag.
        $Prose = @(
            foreach ($Entry in $script:DocHygieneMarkdownFiles) {
                $Converted = ConvertTo-DocHygieneMarkdownProse -Line $Entry.Lines

                [PSCustomObject]@{
                    RelativePath  = $Entry.RelativePath
                    Lines         = $Converted.Lines
                    CodeSpanCount = $Converted.CodeSpanCount
                }
            }
        )

        $TagPattern = [regex]'(?<!\\)<(?=[A-Za-z/!?])[^<>\n]*>'
        $IsNeverAllowed = {
            param ($Value, $Entry)

            $false
        }

        # Emptiness guard. Zero files means the enumeration broke, not that the prose is clean.
        $Prose.Count |
            Should -BeGreaterThan 0 -Because 'this check must read at least one tracked Markdown file; zero files means the enumeration failed and the check ran on nothing'

        # Narrowing guards. A scope pattern that loses the root files, or the checklists this check
        # was written for, still enumerates files and still passes on them.
        $InScope = @($Prose | ForEach-Object { $_.RelativePath })

        $InScope | Should -Contain 'README.md' -Because 'README.md must be in scope; if it is not, the check stopped reaching the root files'

        $InScope | Should -Contain 'CHANGELOG.md' -Because 'CHANGELOG.md must be in scope; its [Unreleased] section also becomes the GitHub release body, which GitHub renders the same way'

        @($InScope | Where-Object { $_ -like 'docs/live-verification/*' }).Count |
            Should -BeGreaterThan 0 -Because 'the live-verification checklists must stay in this scope; zero means the scan narrowed away from the folder the check was written for'

        # Reach guard. The files in scope hold thousands of code spans between them, so a scan that
        # removed none reached no prose at all -- every line taken for a fenced block, or the
        # code-span pass never run -- and a check that sees no prose passes on nothing.
        $CodeSpanTotal = 0
        foreach ($Entry in $Prose) {
            $CodeSpanTotal += $Entry.CodeSpanCount
        }

        $CodeSpanTotal |
            Should -BeGreaterThan 0 -Because 'the scan must have removed at least one code span; zero means it reached no prose at all and the check ran on nothing'

        # Known answer. A tag pattern edited into one that never matches leaves every guard above
        # green and this check green on every file, so a fixed sample proves the scan still finds
        # what it is for: the bare tag on line 1 is the ONE hit, while the code span, the escaped
        # form and the fenced block are all skipped.
        $Sample = ConvertTo-DocHygieneMarkdownProse -Line @(
            'A bare <hidden> tag, a `<coded>` one and an escaped \<shown> one.'
            ''
            '```text'
            'A <fenced> one.'
            '```'
        )
        $SampleHits = @(Get-DocHygieneMatchLocation -File @([PSCustomObject]@{ RelativePath = 'sample'; Lines = $Sample.Lines }) -Pattern $TagPattern -IsAllowed $IsNeverAllowed)

        ($SampleHits -join ', ') |
            Should -Be 'sample:1' -Because 'the known-answer sample must yield exactly its one bare tag; anything else means the scan stopped finding tags, or stopped skipping code'

        $Hits = @(Get-DocHygieneMatchLocation -File $Prose -Pattern $TagPattern -IsAllowed $IsNeverAllowed)

        @($Hits).Count |
            Should -Be 0 -Because ('no tracked .md under docs/ or specs/, and neither README.md nor CHANGELOG.md, may hold an angle bracket outside code that GitHub would render as an HTML tag: it is shown as nothing, so a redacted stand-in vanishes from the record. Put the token inside backticks, or write it with a backslash before the bracket where a backtick would close a code span the line already has (see docs/live-verification/README.md). In CHANGELOG.md use backticks only -- the Gallery shows its notes as plain text, where a backslash would show instead of escaping anything. An autolink or deliberate HTML is refused the same way: write a bare URL, or put the markup in backticks. Locations, values deliberately not shown: {0}' -f ($Hits -join ', '))
    }
}
