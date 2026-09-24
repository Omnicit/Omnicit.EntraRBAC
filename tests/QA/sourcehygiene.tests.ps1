BeforeAll {
    $script:projectPath = (Resolve-Path -Path (Join-Path -Path $PSScriptRoot -ChildPath '..\..')).Path
    $script:hygieneRoots = @(
        (Join-Path -Path $script:projectPath -ChildPath 'source')
        (Join-Path -Path $script:projectPath -ChildPath 'tests')
    )

    # '*.txt' is deliberately NOT in the include list. The only authored .txt under either root is
    # source/en-US/about_Omnicit.EntraRBAC.help.txt, and tests/QA/about.tests.ps1 already gates it on
    # its raw bytes -- 'Should be UTF-8 without a BOM' and 'Should contain only ASCII characters'.
    # Adding it here would duplicate a gate that exists rather than close a hole, and CLAUDE.md's
    # ASCII rule names .ps1 files specifically. If that about-topic coverage is ever removed, add
    # '*.txt' here instead of leaving the file ungated.
    #
    # Single pass over the authored tree. The Bearer-token hygiene Describe reuses this collection --
    # do not enumerate twice. tests/QA/module.tests.ps1 re-parses per function 816 times; that
    # pattern is deliberately not copied here.
    $script:hygieneFiles = @(
        Get-ChildItem -Path $script:hygieneRoots -Recurse -File -Include '*.ps1', '*.psd1', '*.psm1', '*.ps1xml' |
            ForEach-Object {
                $Bytes = [System.IO.File]::ReadAllBytes($_.FullName)
                [PSCustomObject]@{
                    Path         = $_.FullName
                    Extension    = $_.Extension
                    RelativePath = $_.FullName.Substring($script:projectPath.Length).TrimStart([char]'\', [char]'/')
                    Bytes        = $Bytes
                    Text         = [System.Text.Encoding]::UTF8.GetString($Bytes)
                }
            }
    )

    # Named positive controls are looked up here. A threshold erodes as a tree grows; a named file
    # does not.
    $script:hygieneFilePaths = [System.Collections.Generic.HashSet[string]]::new(
        [string[]]@($script:hygieneFiles | ForEach-Object { $_.RelativePath -replace '/', '\' }),
        [System.StringComparer]::OrdinalIgnoreCase)

    # =====================================================================================
    # Bearer-scrub gate: one AST pass over source/, reusing the files already read above.
    #
    # 'Transport' is anything that can put a credential on the wire, because that is what decides
    # whether an ErrorRecord reaching a catch can carry bearer material. The three
    # credential-acquisition commands are in the set for exactly that reason: a failed Get-AzToken,
    # Connect-MgGraph or Connect-AzAccount record is as sensitive as a failed Graph call, and
    # source/Private/Initialize-OERAuth.ps1 -- the module's token-handling file -- reaches nothing
    # else.
    # =====================================================================================
    $script:transportCommands = @(
        'Invoke-OERGraphRequest', 'Invoke-OERArmRequest', 'Invoke-MgGraphRequest', 'Invoke-WebRequest',
        'Get-AzToken', 'Connect-MgGraph', 'Connect-AzAccount'
    )

    # Catch clauses that legitimately do NOT scrub. Keyed by file, but a file entry alone is NOT
    # enough to exempt: the catch's own try body must ALSO satisfy Test-OERResolveNameOnlyTry below,
    # and that structural shape IS the written justification. Keying on the file alone would silently
    # unguard every OTHER catch in these four files -- 15 of them, several wrapping a direct
    # Invoke-OERGraphRequest call -- which is exactly the structurally-inert-guard failure this file
    # exists to prevent. Line numbers are deliberately not used as the anchor: they drift on every
    # unrelated edit.
    $script:scrubExemptions = @{
        'source\Public\New-OERGroup.ps1'              = 'try body is a single Resolve-OERName call -- a pure local string-template helper that issues no HTTP request, so no bearer-carrying record can reach the catch'
        'source\Public\New-OERCatalog.ps1'            = 'try body is a single Resolve-OERName call -- a pure local string-template helper that issues no HTTP request, so no bearer-carrying record can reach the catch'
        'source\Public\New-OERAccessPackage.ps1'      = 'try body is a single Resolve-OERName call -- a pure local string-template helper that issues no HTTP request, so no bearer-carrying record can reach the catch'
        'source\Public\New-OERAdministrativeUnit.ps1' = 'try body is a single Resolve-OERName call -- a pure local string-template helper that issues no HTTP request, so no bearer-carrying record can reach the catch'
    }

    <#
        The exemption predicate, expressed against the AST rather than against the extent TEXT of the
        first statement. Two failure modes a text match has, both verified:

        1. TOO NARROW. The natural refactor `$Name = Resolve-OERName -Template $T -Tokens $K` does not
           match a '^Resolve-OERName\b' pattern, so the gate would go red on correct code -- and the
           obvious "fix" would be to broaden the pattern, which undoes the exemption's whole point.
           Backtick line-continuation breaks a text match the same way.

        2. TOO LOOSE. Testing only the FIRST statement exempts a try that opens with Resolve-OERName
           and calls Invoke-OERGraphRequest on the next line. The single-statement check below is what
           makes the code enforce what the comment claims.
    #>
    function Test-OERResolveNameOnlyTry {
        param($Catch)

        # CatchClauseAst.Parent is the TryStatementAst, so .Parent.Body is the try block.
        $TryStatements = @($Catch.Parent.Body.Statements)
        if ($TryStatements.Count -ne 1) { return $false }

        $Statement = $TryStatements[0]
        if ($Statement -is [System.Management.Automation.Language.AssignmentStatementAst]) {
            $Statement = $Statement.Right
        }
        if ($Statement -isnot [System.Management.Automation.Language.PipelineAst]) { return $false }

        $Element = @($Statement.PipelineElements)[0]
        if ($Element -isnot [System.Management.Automation.Language.CommandAst]) { return $false }

        return ($Element.GetCommandName() -eq 'Resolve-OERName')
    }

    # --- Pass 1: parse every PowerShell-syntax source file exactly once. ---
    #
    # .ps1xml is excluded because it is XML: Parser::ParseInput reports 10 errors on
    # source/Formats/Omnicit.EntraRBAC.Format.ps1xml, which would make the parse gate below red
    # against a perfectly valid format file. .psd1 parses cleanly as a hashtable literal.
    $script:sourceUnits = [System.Collections.Generic.List[object]]::new()
    $script:parseFailures = @()

    <#
        Duration-encoder-ownership gate (Task 8d). ConvertTo-OERDuration is the sole int-to-ISO
        encoder (CLAUDE.md), so no OTHER file may build an ISO 8601 duration string by hand via the
        -f format operator (the exact shape New-OERPimRuleSet.ps1 used to carry:
        ("PT{0}H" -f $ActivationMaxHours)). Detected on the SAME AST walk as Pass 1 below --
        BinaryExpressionAst is added to that walk's FindAll predicate rather than re-parsing the tree
        a second time, matching this file's own stated "parse exactly once" design.

        The literal test is deliberately narrow: the LEFT operand of a -f (TokenKind.Format) binary
        expression must be a string constant that is ALL uppercase ISO-duration vocabulary (P, T, and
        the Y/M/W/D/H/S designators) plus at least one {n} placeholder -- e.g. 'PT{0}H' or 'P{0}D'.
        A case-sensitive match (-cmatch) avoids false positives from the many lowercase URL-template
        -f calls in this tree (e.g. "policies/roleManagementPolicies/{0}/rules"). (Fix round 1, M-3:
        an earlier version of this comment claimed NO OTHER -f call in the tree starts with an
        uppercase letter at all -- false. Get-OERRequiredScope.ps1 has one:
        "No exported Omnicit.EntraRBAC cmdlet matches '{0}'." -f $Pattern. The CONCLUSION still
        holds because the anchor is 'P' specifically, not "any uppercase letter" -- that string
        starts with 'N' and cannot match ^P... regardless -- but the premise as stated was wrong.)

        SCOPE, stated honestly rather than implied: this only inspects a -f operator whose LEFT
        operand is a string constant. "PT$($Hours)H" (interpolation, no -f at all), string
        concatenation ('PT' + $Hours + 'H'), and [string]::Format(...) would all bypass it entirely
        -- verified today that none of those three shapes exists anywhere in the tree, but that is a
        property of the current source, not a guarantee this gate enforces.

        $IsDurationEncoder (the per-file exemption for ConvertTo-OERDuration.ps1 itself, so the
        encoder's own body is never flagged against its own pattern) is currently INERT: that file
        contains zero -f calls of any kind -- it builds its output entirely through
        [System.Xml.XmlConvert]::ToString(...) -- so the exemption never actually has anything to
        skip. Left in place because it is the correct exemption IF that ever changes, not because it
        currently does anything.
    #>
    $script:durationFormatEncoderPath = 'source\Private\ConvertTo-OERDuration.ps1'
    $script:durationFormatOperatorCount = 0
    $script:durationFormatViolations = @()

    foreach ($File in $script:hygieneFiles) {
        if ($File.RelativePath -notmatch '^source[\\/]') { continue }
        if ($File.Extension -notin '.ps1', '.psm1', '.psd1') { continue }

        $Tokens = $null
        $Errors = $null
        $FileAst = [System.Management.Automation.Language.Parser]::ParseInput(
            $File.Text, $File.Path, [ref]$Tokens, [ref]$Errors)

        <#
            $Errors was previously captured and thrown away. A file that fails to parse yields ZERO
            CommandAst and ZERO CatchClauseAst, so it drops silently out of BOTH counters -- prefixing
            any file with an unterminated here-string removes it from this gate without failing
            anything. Record the failure instead of continuing over a file the parser never read.
        #>
        if ($Errors.Count -gt 0) {
            $script:parseFailures += '{0} -- {1} parse error(s), first: {2}' -f
                $File.RelativePath, $Errors.Count, $Errors[0].Message
            continue
        }

        <#
            Transport is detected via CommandAst.GetCommandName(), never a text grep:
            source/Private/Remove-OERErrorRecord.ps1 carries the literal 'Invoke-MgGraphRequest
            @InvokeParams' inside its .EXAMPLE help block, so a grep scores it as a transport file and
            then reports its non-scrubbing catch as a violation. The AST never sees comment tokens.

            ONE FindAll walk collects all five node kinds into four buckets, filled with a plain
            foreach. Three separate walks cost 2.2s across source/ against 1.0s merged, and a
            `| ForEach-Object | Where-Object` over the ~40k nodes they return costs more again -- the
            predicate scriptblock is invoked once per node either way, so the walk count is what
            matters. Measured in a fresh pwsh: both Describes together run in ~3.8s with this shape
            and ~9s with three separate walks and pipeline bucketing.

            BinaryExpressionAst was added (Task 8d) to feed the duration-format-encoder gate below
            without a second full-tree parse -- see the comment on $script:durationFormatViolations
            above Pass 1 for what it looks for.
        #>
        $Nodes = $FileAst.FindAll({
                $args[0] -is [System.Management.Automation.Language.CommandAst] -or
                $args[0] -is [System.Management.Automation.Language.CatchClauseAst] -or
                $args[0] -is [System.Management.Automation.Language.StringConstantExpressionAst] -or
                $args[0] -is [System.Management.Automation.Language.ExpandableStringExpressionAst] -or
                $args[0] -is [System.Management.Automation.Language.BinaryExpressionAst]
            }, $true)

        $CommandNames = [System.Collections.Generic.List[string]]::new()
        $StringValues = [System.Collections.Generic.List[string]]::new()
        $Catches = [System.Collections.Generic.List[object]]::new()
        $CallsTransport = $false
        $IsDurationEncoder = (($File.RelativePath -replace '/', '\') -eq $script:durationFormatEncoderPath)

        foreach ($Node in $Nodes) {
            if ($Node -is [System.Management.Automation.Language.CommandAst]) {
                $CommandName = $Node.GetCommandName()
                if ($CommandName) {
                    $CommandNames.Add($CommandName)
                    if (-not $CallsTransport -and $script:transportCommands -contains $CommandName) {
                        $CallsTransport = $true
                    }
                }
            }
            elseif ($Node -is [System.Management.Automation.Language.CatchClauseAst]) {
                $Catches.Add($Node)
            }
            elseif ($Node -is [System.Management.Automation.Language.BinaryExpressionAst]) {
                if ($Node.Operator -ne [System.Management.Automation.Language.TokenKind]::Format) { continue }
                $script:durationFormatOperatorCount++

                $Left = $Node.Left
                $LeftValue = if ($Left -is [System.Management.Automation.Language.StringConstantExpressionAst] -or
                    $Left -is [System.Management.Automation.Language.ExpandableStringExpressionAst]) { $Left.Value } else { $null }

                if ($IsDurationEncoder) { continue }
                if ($null -eq $LeftValue) { continue }
                if ($LeftValue -cmatch '^P[A-Z0-9{}]*\{[0-9]+\}[A-Z0-9{}]*$') {
                    $script:durationFormatViolations += '{0}:{1} -- builds an ISO-8601-shaped duration via the -f format operator instead of ConvertTo-OERDuration: {2}' -f
                        ($File.RelativePath -replace '/', '\'), $Node.Extent.StartLineNumber, $Node.Extent.Text.Trim()
                }
            }
            else {
                $StringValues.Add($Node.Value)
            }
        }

        # Top-level definition only: a nested helper is part of its parent's body, not its own node.
        # Searching top-level children ($false) is cheap enough to stay its own call.
        $Definition = $FileAst.FindAll({
                $args[0] -is [System.Management.Automation.Language.FunctionDefinitionAst]
            }, $false) | Select-Object -First 1

        $script:sourceUnits.Add([PSCustomObject]@{
                RelativePath   = ($File.RelativePath -replace '/', '\')
                FunctionName   = if ($Definition) { $Definition.Name } else { $null }
                IsPrivate      = [bool]($File.RelativePath -match '^source[\\/]Private[\\/]')
                CommandNames   = $CommandNames
                StringValues   = $StringValues
                Catches        = $Catches
                CallsTransport = $CallsTransport
                Edges          = $null
            })
    }

    <#
        =====================================================================================
        Pass 2: whole-module call-edge closure, so a file counts as transport-reaching when it calls
        a transport command DIRECTLY or calls (transitively) any module function that does.

        A direct-only net is blind by construction. Verified census before this closure existed: of
        338 catch clauses in source/, 80 sat in 26 files with no literal transport CommandAst of
        their own -- and 77 of those 80 already scrubbed correctly, so deleting any one of those 77
        scrub lines was a silent regression across 23% of the tree. The worst case was
        source/Private/Initialize-OERAuth.ps1, whose three catches all scrub and none of which were
        guarded, in the module's token-handling file.

        The approach and its two traps are lifted from tests/QA/requiredscope.tests.ps1, which builds
        the same closure for the permission table:

        1. TRANSITIVE. Add-OERAdministrativeUnitScopedRole reaches Graph only through
           Resolve-OERDirectoryRoleId. A per-file scan of source/Public finds 51 Graph cmdlets; the
           correct answer is 70.

        2. INDIRECT DISPATCH. Invoke-OERStructure calls its handlers as `& $Section.Handler`, where
           Handler is a STRING. A CommandAst-only walk reports it offline. String constants naming a
           module function therefore count as call edges -- but only PRIVATE ones, because
           Get-OERRequiredScopeMap is a data table that NAMES all 89 public cmdlets and must not be
           read as calling them. Nothing in this module dispatches indirectly to a public cmdlet.
           Comment-based help is a COMMENT token and never an AST expression, so a name that appears
           only in a help block correctly creates no edge.
        =====================================================================================
    #>
    # OrdinalIgnoreCase: PowerShell resolves command names case-insensitively, so a call written
    # `resolve-oergroupid` is a real edge that an ordinal HashSet would drop.
    $script:allFunctions = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    $script:privateFunctions = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)

    foreach ($Unit in $script:sourceUnits) {
        if (-not $Unit.FunctionName) { continue }
        $null = $script:allFunctions.Add($Unit.FunctionName)
        if ($Unit.IsPrivate) { $null = $script:privateFunctions.Add($Unit.FunctionName) }
    }

    $script:callEdges = @{}
    foreach ($Unit in $script:sourceUnits) {
        $Edges = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
        foreach ($CommandName in $Unit.CommandNames) {
            if ($script:allFunctions.Contains($CommandName)) { $null = $Edges.Add($CommandName) }
        }
        foreach ($Value in $Unit.StringValues) {
            if ($script:privateFunctions.Contains($Value)) { $null = $Edges.Add($Value) }
        }

        $Unit.Edges = $Edges
        if ($Unit.FunctionName) { $script:callEdges[$Unit.FunctionName] = $Edges }
    }

    <#
        Reachability is computed by FIXED-POINT ITERATION over a boolean, not by a memoized
        depth-first closure. The DFS this replaced (still present in tests/QA/requiredscope.tests.ps1,
        which builds the same graph for the permission table) cached results that its own re-entry
        guard had TRUNCATED, and pass 3 shares one cache across fresh $Visiting sets, so a single
        poisoned entry persisted for the whole run.

        Demonstrated on a four-node fixture -- D -> A -> B -> C -> A, where only C calls a transport
        command and D holds a non-scrubbing catch. Computing A while B was still in flight hits the
        guard and returns EMPTY, so the DFS stored cache[A] = {B} when the true closure is {A,B,C}.
        D then read that cached {B}, saw nothing calling transport, and dropped out of the scan
        entirely: 0 violations reported where there was 1. Silent under-reach in a bearer-token gate
        is the exact failure this file exists to prevent.

        The module has no call cycles TODAY, so that was latent -- but a cycle is cheap to introduce,
        because the string-literal edge rule above turns a private function's name appearing in a
        sibling's error message into a real edge.

        A boolean fixed point has no truncation state to get wrong. Seed each function with its own
        direct CallsTransport, then propagate along edges until a full pass changes nothing. The
        lattice is monotone (false -> true only) and bounded by the function count, so it always
        terminates, and it reaches the same answer regardless of visit order -- which is what makes a
        cycle a non-event rather than a special case.

        It is also not a cost. Over source/ it settles in 3 passes (two productive, one confirming no
        change), and alternating cold runs put it within noise of the DFS it replaced -- both around
        4s for the whole BeforeAll, which the single AST walk in pass 1 dominates. Census is
        identical either way: 117 transport-reaching files, 318 of the 338 catches in source/.
    #>
    $script:transportReach = @{}
    foreach ($Unit in $script:sourceUnits) {
        if ($Unit.FunctionName) { $script:transportReach[$Unit.FunctionName] = $Unit.CallsTransport }
    }

    $Changed = $true
    while ($Changed) {
        $Changed = $false
        foreach ($Unit in $script:sourceUnits) {
            if (-not $Unit.FunctionName) { continue }
            if ($script:transportReach[$Unit.FunctionName]) { continue }
            foreach ($Edge in $Unit.Edges) {
                # A miss returns $null, which is falsy -- an edge to a name with no unit of its own
                # (nothing in the module today) correctly contributes no reachability.
                if ($script:transportReach[$Edge]) {
                    $script:transportReach[$Unit.FunctionName] = $true
                    $Changed = $true
                    break
                }
            }
        }
    }

    # --- Pass 3: the scrub scan itself, over every transport-reaching file. ---
    $script:scrubViolations = @()
    $script:scrubCatchCount = 0
    $script:scrubTransportFileCount = 0
    $script:scrubCatchByFile = @{}

    foreach ($Unit in $script:sourceUnits) {
        # Edges are consulted even for a unit with no function of its own (the psd1 and the psm1
        # loader), which is why this is not just a $script:transportReach lookup by name.
        $ReachesTransport = $Unit.CallsTransport
        if (-not $ReachesTransport) {
            foreach ($Edge in $Unit.Edges) {
                if ($script:transportReach[$Edge]) { $ReachesTransport = $true; break }
            }
        }
        if (-not $ReachesTransport) { continue }

        $script:scrubTransportFileCount++
        $script:scrubCatchByFile[$Unit.RelativePath] = $Unit.Catches.Count

        $IsExemptFile = $script:scrubExemptions.ContainsKey($Unit.RelativePath)

        foreach ($Catch in $Unit.Catches) {
            $script:scrubCatchCount++

            # The @() wrap is load-bearing: an empty catch body returns $null here instead of
            # throwing on an empty ReadOnlyCollection.
            $FirstStatement = @($Catch.Body.Statements)[0]
            $FirstText = if ($FirstStatement) { $FirstStatement.Extent.Text.Trim() } else { '' }
            if ($FirstText -match '^Remove-OERErrorRecord\s+-Record\s+\$PSItem\b') { continue }

            if ($IsExemptFile -and (Test-OERResolveNameOnlyTry -Catch $Catch)) { continue }

            $Diagnostic = if ($FirstText) { ($FirstText -split "`n")[0] } else { '<empty catch body>' }
            $script:scrubViolations += '{0}:{1} -- first statement is: {2}' -f
                $Unit.RelativePath, $Catch.Extent.StartLineNumber, $Diagnostic
        }
    }

    <#
        =====================================================================================
        Pass 4: cmdlet-reference hygiene. Every Verb-OER... token appearing ANYWHERE in a
        source/**/*.ps1 file's raw TEXT -- comment-based help included, not just live code -- must
        resolve to a real Public or Private function basename. This is deliberately a TEXT scan, not
        an AST CommandAst walk like the bearer-scrub gate above: a stale reference sits in PROSE (a
        .DESCRIPTION naming a cmdlet that was renamed or deleted), which is a comment token the parser
        never turns into a CommandAst at all, so an AST-only pass would be structurally blind to the
        one violation this gate was written to catch
        (ConvertTo-OERAccessReviewDecision.ps1 naming the never-existent Get-OERAccessReviewDecision).

        The noun class ([A-Za-z0-9]+) is deliberately narrow: this is a targeted sweep for OER-prefixed
        cmdlet names, not a general "does this identifier exist" checker. Digits are included because
        at least one real, referenced nested helper carries one (ConvertTo-OERPsd1Fragment).
        =====================================================================================
    #>

    <#
        The valid-target set: every Public/Private TOP-LEVEL function basename (filename equals
        function name module-wide -- CLAUDE.md's one-function-per-file rule) PLUS every NESTED helper
        function defined anywhere in source/**/*.ps1 (e.g. Export-OERConfiguration.ps1's own
        ConvertTo-OERPsd1Fragment, Export-OERInventory.ps1's Write-OERBundleJson,
        Read-OERStructureDocument.ps1's Write-OEREnumValue). Widening the verb set in I-3 below
        surfaced these for the first time -- they were invisible to the original 14-verb list because
        none of Convert/ConvertTo/Write were in it -- and a nested helper is a REAL, callable function
        (Pass 1's own comment above notes it is simply "part of its parent's body, not its own node"
        for the UNRELATED call-graph purpose that section serves); it is not a stale reference just
        because it lacks its own file.
    #>
    $script:sourceFunctionBasenames = [System.Collections.Generic.HashSet[string]]::new(
        [System.StringComparer]::OrdinalIgnoreCase)
    foreach ($File in $script:hygieneFiles) {
        if ($File.RelativePath -match '^source[\\/](Public|Private)[\\/][^\\/]+\.ps1$') {
            $null = $script:sourceFunctionBasenames.Add(
                [System.IO.Path]::GetFileNameWithoutExtension($File.RelativePath))
        }
    }
    foreach ($File in $script:hygieneFiles) {
        if ($File.RelativePath -notmatch '^source[\\/]' -or $File.Extension -ne '.ps1') { continue }
        foreach ($DefMatch in [System.Text.RegularExpressions.Regex]::Matches(
                $File.Text, 'function\s+([A-Za-z]+-OER[A-Za-z0-9]+)')) {
            $null = $script:sourceFunctionBasenames.Add($DefMatch.Groups[1].Value)
        }
    }

    <#
        Round-1 review finding I-3: the verb alternation is DERIVED from the tree, not hardcoded.
        A hand-maintained 14-verb list silently missed Convert, ConvertFrom, ConvertTo, Initialize,
        Read, Resolve, Sync and Write -- 84 of 204 basenames (41% of the module) -- which are exactly
        the private-helper families CLAUDE.md pins by name (Resolve-OERReviewerScopeQuery,
        ConvertTo-OERODataFilterValue, Sync-OERStructure*, Test-OERDeclaredProperty), so a stale
        reference to one of THOSE was at least as likely as the case this gate was written for. Every
        basename module-wide is Verb-OERNoun (CLAUDE.md's naming convention), so splitting each
        collected basename on its first '-' and de-duplicating is a self-maintaining verb set: it can
        never miss a verb the module actually uses, and it grows automatically when a new verb is
        introduced.
    #>
    $script:cmdletRefVerbs = @(
        $script:sourceFunctionBasenames | ForEach-Object { ($_ -split '-', 2)[0] } | Sort-Object -Unique
    )
    $script:cmdletRefPattern = '\b(' + ($script:cmdletRefVerbs -join '|') + ')-OER[A-Za-z0-9]+'

    $script:cmdletRefFiles = @($script:hygieneFiles | Where-Object {
            $_.RelativePath -match '^source[\\/]' -and $_.Extension -eq '.ps1'
        })
    $script:cmdletRefTokenCount = 0
    $script:cmdletRefViolations = @()
    foreach ($File in $script:cmdletRefFiles) {
        <#
            Round-1 review finding M-4: the gate was unsound in the OTHER direction too. A cmdlet name
            hyphen-wrapped across a line break in prose -- e.g. "Get-OERGroup-\n# Member" -- previously
            fed the scanner "Get-OERGroup", which RESOLVES (it is a real basename), so a genuinely
            broken wrap passed silently whenever its prefix happened to be a real cmdlet name. Fixed by
            NORMALIZING the wrap out of the text before scanning, not by loosening the match pattern
            (a looser pattern would just as easily paper over an actual stale reference).

            The normalizer strips a trailing hyphen, the line break, and an optional per-line '#'
            comment-continuation marker, splicing the wrapped word back into one token: "Get-OERGroup-"
            + newline + "# Member" -> "Get-OERGroupMember". Verified empirically against three real
            wraps in this tree (two of them the exact line M-4 was filed against, already independently
            reflowed by the au-task's own round-1 fix; the third is this file's own comment two lines
            above referencing Resolve-\nOERDirectoryRoleId elsewhere in the module). The '#' group is
            ordered AFTER \r?\n, not before -- a hyphen followed by a bare newline never carries a '#'
            on the SAME line in this codebase's line-comment style; the marker belongs to the
            CONTINUATION line.
        #>
        $NormalizedText = $File.Text -replace '-\s*\r?\n\s*(?:#\s*)?', ''
        $TokenMatches = [System.Text.RegularExpressions.Regex]::Matches($NormalizedText, $script:cmdletRefPattern)
        foreach ($TokenMatch in $TokenMatches) {
            <#
                Widening the verb set in I-3 also surfaced a THIRD pre-existing, deliberate prose
                idiom: "Sync-OERStructure*" and "the uniform Sync-OERStructure* handler signature",
                referring to the whole handler FAMILY, not one literal cmdlet -- CLAUDE.md itself uses
                this exact "Verb-OERNoun*" wildcard shorthand. A token immediately followed by '*' is
                therefore skipped entirely (not counted toward the token total, not checked against the
                basename set) rather than matched-and-then-failed.
            #>
            $NextIndex = $TokenMatch.Index + $TokenMatch.Length
            if ($NextIndex -lt $NormalizedText.Length -and $NormalizedText[$NextIndex] -eq '*') { continue }

            $script:cmdletRefTokenCount++
            $Token = $TokenMatch.Value
            if (-not $script:sourceFunctionBasenames.Contains($Token)) {
                $script:cmdletRefViolations += '{0} -- references {1}, which does not exist under source/Public or source/Private' -f
                    $File.RelativePath, $Token
            }
        }
    }

    <#
        =====================================================================================
        Pass 5: ARM api-version documentation hygiene (Task 8f). docs/development/rationale.md's
        ## arm-transport section is the single documented list of pinned ARM api-versions
        (CLAUDE.md ## ARM Requests delegates there rather than carrying its own copy). A prose-only
        fix re-rots the next time an endpoint is added or bumped, so this asserts every DISTINCT
        api-version literal actually reachable in source/ appears verbatim somewhere in that section.

        Reuses the already-read $script:hygieneFiles text (a TEXT scan, like Pass 4 above, not an AST
        walk -- an ARM path is routinely built as "$Scope?api-version=..." with the version the only
        literal fragment, so a comment-based-help example carries the same literal shape a live call
        site does, and rationale.md's own count of 43 hits -- "40 real request-path sites... plus 3
        more that appear only inside Invoke-OERArmRequest's own comment-based help" -- already prices
        that in).
        =====================================================================================
    #>
    $script:armApiVersionPattern = 'api-version=(\d{4}-\d{2}-\d{2})'
    $script:armApiVersionSiteCount = 0
    $script:armApiVersionDistinct = [System.Collections.Generic.SortedSet[string]]::new([System.StringComparer]::Ordinal)

    foreach ($File in $script:hygieneFiles) {
        if ($File.RelativePath -notmatch '^source[\\/]' -or $File.Extension -ne '.ps1') { continue }
        foreach ($VersionMatch in [System.Text.RegularExpressions.Regex]::Matches($File.Text, $script:armApiVersionPattern)) {
            $script:armApiVersionSiteCount++
            $null = $script:armApiVersionDistinct.Add($VersionMatch.Groups[1].Value)
        }
    }

    # The rationale doc lives outside both scanned roots (docs/, not source/ or tests/), so it is
    # read once here rather than added to $script:hygieneRoots -- that collection also feeds the
    # ASCII/BOM gate above, and widening it would pull the whole docs/ tree into a gate that was
    # never scoped to documentation prose.
    $script:rationalePath = Join-Path -Path $script:projectPath -ChildPath 'docs\development\rationale.md'
    $script:rationaleText = [System.IO.File]::ReadAllText($script:rationalePath)

    # Section = from the '## arm-transport' heading to the next top-level '## ' heading, or EOF.
    # Singleline (.NET 's') lets '.' cross line boundaries inside that span; Multiline ('m') is what
    # anchors '^' to a line start rather than only the string start, which is what lets the lookahead
    # find the NEXT heading instead of matching to the end of the file.
    $script:armTransportSection = if ($script:rationaleText -match '(?sm)^## arm-transport\r?\n(.*?)(?=^## |\z)') {
        $Matches[1]
    } else {
        ''
    }

    $script:armApiVersionUndocumented = @(
        $script:armApiVersionDistinct | Where-Object { $script:armTransportSection -notmatch [regex]::Escape($_) }
    )

    <#
        =====================================================================================
        Pass 6: sovereign-cloud endpoint hygiene (Task 6, issue #81). Get-OERCloudEndpoint.ps1 is the
        single owner of the cloud-to-endpoint table (CLAUDE.md ## Code Style); every other
        source/**/*.ps1 file must read a Graph/ARM/authority host from it instead of hardcoding a
        second copy of one of the hostnames the table resolves -- ten of them today, DERIVED from the
        table rather than retyped (see the derivation block below). Two independent checks, both
        scoped to source/**/*.ps1 the same way Pass 4 and Pass 5 above are (tests/ carries no
        transport of its own and is out of scope, matching every source-hygiene gate in this file).

        1. HARDCODED HOST LITERAL. Every StringConstantExpressionAst / ExpandableStringExpressionAst
           node's VALUE is checked against those hostnames. This is deliberately NOT the
           regex-plus-tokenizer-comment-strip approach
           tests/Unit/Private/Get-OERCloudEndpoint.Tests.ps1's Remove-OERCommentRegion uses: a
           comment is a TOKEN, never an AST node -- the parser has already discarded every comment
           before this walk ever sees the tree. Verified empirically before writing this gate: a
           fixture naming a cloud host inside both a block comment and a line comment produced ZERO
           StringConstantExpressionAst/ExpandableStringExpressionAst matches -- only the same
           fixture's one live-code literal did. An AST value scan is therefore comment-immune by
           construction, with no separate stripping step needed -- a deliberately narrower substitute
           for that helper, chosen because an AST node value can never carry comment text in the
           first place, not a third copy of the same technique.

        2. -TokenCache NEVER REACHES Get-AzToken. Spike condition 6
           (docs/development/rationale.md ## sovereign-clouds): AzAuth.Core contains exactly one
           hardcoded authority, reached only when -TokenCache is passed to Get-AzToken. Detected via
           CommandAst.GetCommandName() -eq 'Get-AzToken' plus a CommandParameterAst named
           'TokenCache' among that call's CommandElements -- never a text grep, the same reason the
           bearer-scrub gate above gives for the same technique: a text match would false-positive on
           a mention inside comment-based help. SCOPE, stated honestly: this finds a literal
           '-TokenCache' argument at the call site; it would not see one added to a hashtable later
           splatted into Get-AzToken (the shape Initialize-OERAuth actually uses for every real
           argument it passes) -- verified today that neither splat this module builds sets that key,
           which is a property of the current source, not a guarantee this gate enforces.

        This is its own parse pass rather than folded into Pass 1's shared walk above, so a mistake
        here cannot perturb the six existing gates' proven reachability closure or catch-clause scan
        -- the cost is one extra parse of ~205 files, not the ~40k-node cost the walk-count comment on
        Pass 1 was written against.
        =====================================================================================
    #>
    <#
        The host list this gate scans for is DERIVED FROM THE TABLE ITSELF, not retyped here. Final
        whole-branch review, Finding 4: a hardcoded copy was a third partial copy of the table
        (source, README/about topic, gate) with nothing asserting the three agree, so a FIFTH cloud
        added to Get-OERCloudEndpoint.ps1 would have fallen silently outside the very gate that
        exists to stop that drift -- the new cloud's hosts would be free to be hardcoded anywhere in
        source/ with no violation reported.

        Derivation is by AST, from the file already read into $script:hygieneFiles, so this gate
        keeps taking its input from disk exactly as the other six do -- it never imports the module
        and never dot-sources anything. Restricted to StringConstantExpressionAst: every URL in the
        table is a single-quoted literal, an expandable string would mean the table had started
        computing a host, and a comment is a TOKEN rather than an AST node, so the .DESCRIPTION
        block's illustrative 'https://graph.microsoft.com//v1.0/...' can never leak in here.

        $script:cloudHostDocumented is kept as a written control, NOT as the working list, and the
        Describe below asserts the derived set and the documented set are identical. That is what
        makes a new cloud a LOUD, deliberate edit: the scan below covers it automatically the moment
        the table names it, and the assertion still fails until a human updates this list, the README
        table and the about topic to match. Proven by mutation, not by inspection: a fifth row with a
        novel hostname added to the table reddens that assertion.
    #>
    $script:cloudEndpointRelativePath = 'source\Private\Get-OERCloudEndpoint.ps1'
    $script:cloudHostDerivationFailure = ''
    $script:cloudHostDerived = @()

    $CloudEndpointFile = @($script:hygieneFiles | Where-Object {
            ($_.RelativePath -replace '/', '\') -eq $script:cloudEndpointRelativePath
        })[0]

    if (-not $CloudEndpointFile) {
        $script:cloudHostDerivationFailure =
        "the cloud-endpoint table owner '$script:cloudEndpointRelativePath' was not found among the scanned files, so no host could be derived from it"
    } else {
        $EndpointTokens = $null
        $EndpointErrors = $null
        $EndpointAst = [System.Management.Automation.Language.Parser]::ParseInput(
            $CloudEndpointFile.Text, $CloudEndpointFile.Path, [ref]$EndpointTokens, [ref]$EndpointErrors)

        if ($EndpointErrors.Count -gt 0) {
            $script:cloudHostDerivationFailure =
            "'$script:cloudEndpointRelativePath' does not parse ($($EndpointErrors.Count) error(s)), so no host could be derived from it"
        } else {
            $DerivedHosts = [System.Collections.Generic.List[string]]::new()
            foreach ($Node in $EndpointAst.FindAll({
                        $args[0] -is [System.Management.Automation.Language.StringConstantExpressionAst]
                    }, $true)) {
                if ($Node.Value -notmatch '^https://') { continue }
                # [uri] rather than a regex: it is the same parser the transport will use, so a
                # malformed entry in the table surfaces here instead of being silently half-matched.
                $DerivedHostName = ([uri]$Node.Value).Host
                if ($DerivedHostName -and -not $DerivedHosts.Contains($DerivedHostName)) {
                    $null = $DerivedHosts.Add($DerivedHostName)
                }
            }
            $script:cloudHostDerived = @($DerivedHosts | Sort-Object)
        }
    }

    $script:cloudHostDocumented = @(
        'graph.microsoft.com', 'management.azure.com', 'graph.microsoft.us', 'dod-graph.microsoft.us',
        'microsoftgraph.chinacloudapi.cn', 'management.usgovcloudapi.net', 'management.chinacloudapi.cn',
        'login.microsoftonline.com', 'login.microsoftonline.us', 'login.chinacloudapi.cn'
    )

    # Falls back to the documented control ONLY when derivation produced nothing at all, so a broken
    # derivation cannot silently turn the literal scan below into a no-op (an empty pattern matches
    # every string, which would make every literal a violation) nor into an everything-passes scan.
    # The fallback keeps the scan meaningful while the derivation assertion reports the real cause.
    $script:cloudHostNames = if ($script:cloudHostDerived.Count -gt 0) {
        $script:cloudHostDerived
    } else {
        $script:cloudHostDocumented
    }
    $script:cloudHostPattern = ($script:cloudHostNames | ForEach-Object { [regex]::Escape($_) }) -join '|'

    <#
        Keyed on the file AND carrying a written reason, matching every other exemption list in this
        file ($script:scrubExemptions above is the model). The two entries are NOT the same shape of
        exemption, and round-2 review proved why that distinction matters:

        - Get-OERCloudEndpoint.ps1 is exempted WHOLE-FILE ($script:cloudHostWholeFileExemptions
          below). It legitimately IS the table, so every literal in it is correct by construction --
          reviewer ruling, Task 6 round 2.
        - Invoke-OERArmRequest.ps1 is exempted ONLY for the exact AST shape
          Test-OERArmBaseUrlElseLiteral verifies below, never for the whole file. A file-level key
          alone silently unguards every OTHER literal that file might ever carry -- round-2 review
          proved it live: adding a second, unrelated
          $MutationProbeOnly = 'https://management.chinacloudapi.cn' anywhere else in that file
          passed the original file-only exemption silently. This is the same "keyed on the file AND
          verified structurally" requirement the bearer-scrub gate's Test-OERResolveNameOnlyTry
          enforces for its own four exemptions -- gate 7 had the key but not yet the structural
          verification.
    #>
    $script:cloudHostExemptions = @{
        'source\Private\Get-OERCloudEndpoint.ps1' = 'the single owner of the cloud-to-endpoint table (CLAUDE.md ## Code Style); every literal in this file IS the table, not a copy of it -- exempted whole-file, no further narrowing needed'
        'source\Private\Invoke-OERArmRequest.ps1' = 'controller ruling, Task 6: keeps ONE documented public-cloud ARM fallback (https://management.azure.com), the ElseClause literal of the $ArmBaseUrl assignment, for the case where there is no auth state yet -- see docs/development/rationale.md#arm-transport. Narrowed to that exact AST shape by Test-OERArmBaseUrlElseLiteral below, NOT exempted whole-file: a second, unrelated literal anywhere else in this file must still trip this gate. Do not delete the fallback itself.'
    }
    $script:cloudHostWholeFileExemptions = [System.Collections.Generic.HashSet[string]]::new(
        [string[]]@('source\Private\Get-OERCloudEndpoint.ps1'), [System.StringComparer]::OrdinalIgnoreCase)

    <#
        The Invoke-OERArmRequest.ps1 exemption predicate, expressed against the AST rather than
        against the file as a whole -- the file-level key above only says the file is ELIGIBLE for
        an exemption, this decides whether a SPECIFIC literal in it qualifies. Matches the literal by
        its position: it must be the sole statement of an IfStatementAst's ElseClause (not an
        if/elseif body), and that IfStatementAst must itself be the right-hand side of an assignment
        to $ArmBaseUrl -- the exact shape of

            $ArmBaseUrl = if (...) { ... } else { 'https://management.azure.com' }

        Verified against the real file before being wired in here: returns $true for the one
        legitimate literal at its current location, and $false for the reviewer's own probe (a
        second, unrelated $MutationProbeOnly = 'https://management.chinacloudapi.cn' literal placed
        elsewhere in the same file) -- see the mutation-proof writeup in task-6-report.md.
        [System.Object]::ReferenceEquals, not -eq: AST nodes are reference types with no equality
        override, and the two StatementBlockAst instances being compared here (the ElseClause found
        by walking the parent chain up from the literal, and the same object read off
        IfStatementAst.ElseClause) must be the SAME object, not merely two objects that render the
        same extent text -- a coincidentally identical else-block elsewhere would otherwise pass.
    #>
    function Test-OERArmBaseUrlElseLiteral {
        param($StringNode)

        $CommandExpr = $StringNode.Parent
        if ($CommandExpr -isnot [System.Management.Automation.Language.CommandExpressionAst]) { return $false }
        $Pipeline = $CommandExpr.Parent
        if ($Pipeline -isnot [System.Management.Automation.Language.PipelineAst]) { return $false }
        $Block = $Pipeline.Parent
        if ($Block -isnot [System.Management.Automation.Language.StatementBlockAst]) { return $false }
        $IfStatement = $Block.Parent
        if ($IfStatement -isnot [System.Management.Automation.Language.IfStatementAst]) { return $false }
        if (-not [System.Object]::ReferenceEquals($IfStatement.ElseClause, $Block)) { return $false }

        $Assignment = $IfStatement.Parent
        if ($Assignment -isnot [System.Management.Automation.Language.AssignmentStatementAst]) { return $false }
        $Left = $Assignment.Left
        if ($Left -isnot [System.Management.Automation.Language.VariableExpressionAst]) { return $false }

        return ($Left.VariablePath.UserPath -eq 'ArmBaseUrl')
    }

    $script:cloudHostSiteCount = 0
    $script:cloudHostViolations = @()
    $script:getAzTokenCallCount = 0
    $script:tokenCacheViolations = @()
    $script:sovereignParseFailures = @()

    foreach ($File in $script:cmdletRefFiles) {
        $RelativePath = ($File.RelativePath -replace '/', '\')

        $FileTokens = $null
        $FileErrors = $null
        $FileAst = [System.Management.Automation.Language.Parser]::ParseInput(
            $File.Text, $File.Path, [ref]$FileTokens, [ref]$FileErrors)

        if ($FileErrors.Count -gt 0) {
            # Already reported by Pass 1's own "parses every scanned source file" assertion; recorded
            # here too so THIS gate's non-vacuity counts are never silently thinned by a file that
            # dropped out for the same reason.
            $script:sovereignParseFailures += $RelativePath
            continue
        }

        $StringNodes = $FileAst.FindAll({
                $args[0] -is [System.Management.Automation.Language.StringConstantExpressionAst] -or
                $args[0] -is [System.Management.Automation.Language.ExpandableStringExpressionAst]
            }, $true)

        foreach ($StringNode in $StringNodes) {
            if ($StringNode.Value -notmatch $script:cloudHostPattern) { continue }
            $script:cloudHostSiteCount++

            if ($script:cloudHostWholeFileExemptions.Contains($RelativePath)) { continue }
            if ($RelativePath -eq 'source\Private\Invoke-OERArmRequest.ps1' -and
                (Test-OERArmBaseUrlElseLiteral -StringNode $StringNode)) { continue }

            $script:cloudHostViolations += '{0}:{1} -- hardcoded cloud endpoint literal outside Get-OERCloudEndpoint.ps1: {2}' -f
                $RelativePath, $StringNode.Extent.StartLineNumber, $StringNode.Extent.Text.Trim()
        }

        $GetAzTokenCalls = $FileAst.FindAll({
                $args[0] -is [System.Management.Automation.Language.CommandAst] -and
                $args[0].GetCommandName() -eq 'Get-AzToken'
            }, $true)

        foreach ($Call in $GetAzTokenCalls) {
            $script:getAzTokenCallCount++
            $TokenCacheParam = $Call.CommandElements | Where-Object {
                $_ -is [System.Management.Automation.Language.CommandParameterAst] -and $_.ParameterName -eq 'TokenCache'
            }
            if ($TokenCacheParam) {
                $script:tokenCacheViolations += '{0}:{1} -- Get-AzToken called with -TokenCache, reaching the one hardcoded public-cloud authority inside AzAuth.Core (spike condition 6): {2}' -f
                    $RelativePath, $Call.Extent.StartLineNumber, $Call.Extent.Text.Trim()
            }
        }
    }

    <#
        =====================================================================================
        Pass 7: apply-document declared-value hygiene (Task 8, issue #70). Test-OERDeclaredProperty
        and Test-OERDeclaredNull are the single owners of the apply engine's "declared" predicate
        (CLAUDE.md ## Code Style; docs/development/rationale.md#declared-property): a property on an
        apply-document node is declared only when it is present AND not null, so a handler that
        instead re-implements ".PSObject.Properties.Name -contains ..." plus a separate null check
        treats an explicit JSON null the same as a declared value -- coerced downstream ([string]$null
        is '', [bool]$null is $false, [int]$null is 0) into silently overwriting live tenant state on
        every apply run. Issue #56 found this shape three times over in the Sync-OERStructure*
        handlers; #67, #68, #69 and #70 each found it rebuilt in a new handler after the previous fix
        landed. This gate is what stops a sixth occurrence from shipping unnoticed.

        Detected via the AST, not a text grep, for the same reason the bearer-scrub gate above gives:
        Test-OERDeclaredProperty.ps1 and Test-OERDeclaredNull.ps1 both write the literal phrase
        "PSObject.Properties.Name" inside their own comment-based help (the .DESCRIPTION explains what
        the predicate replaces), and a grep over that text would flag the predicate's own
        documentation as a violation of the rule it defines. A comment is a TOKEN the parser discards
        before this walk ever sees the tree, so an AST scan is immune to it by construction.

        SCOPE is the FOURTEEN files listed below by name -- not a claim about the whole tree, and not
        derived from one glob. They are the seven source/Private/Sync-OERStructure*.ps1 handlers plus
        the seven private helpers that are handed an apply-document node and walk it:

          - source/Private/Read-OERStructureDocument.ps1 -- its nested Write-OEREnumValue helper walks
            the freshly parsed apply document to canonicalize enum casing, so it asks the same
            present-and-not-null question about the same kind of node.
          - the four Resolve-OER*Change helpers whose -Declared parameter IS a document node, each
            handed one straight from the handler that owns that section:
              Resolve-OERGroupEligibilityChange.ps1     <- Sync-OERStructureGroup.ps1 (eligibility[])
              Resolve-OERGroupPimPolicyChange.ps1       <- Sync-OERStructureGroup.ps1 (pimPolicy block)
              Resolve-OERAccessReviewChange.ps1         <- Sync-OERStructureAccessReview.ps1
              Resolve-OERRoleManagementPolicyChange.ps1 <- Sync-OERStructureRoleManagementPolicy.ps1
          - source/Private/Get-OEROmittedPruneCollection.ps1 -- handed the whole parsed apply document
            (-Document) by Invoke-OERStructure and by Test-OERStructureSchema, it walks every groups,
            administrativeUnits, catalogs and accessPackages item and asks whether a collection key is
            declared, explicitly null or omitted -- the declared-value question itself, and the
            answer that decides whether -Prune's warning lists the key. Its parameter is -Document,
            not -Declared, so the tell named under SCOPE MAINTENANCE below would not have found it.
          - source/Private/Resolve-OERDeclaredApprover.ps1 -- handed one roleManagementPolicies[]
            entry (-Declared) by Sync-OERStructureRoleManagementPolicy.ps1 BEFORE the diff, it walks
            the approvers.users/approvers.groups sub-block and requireApproval to decide what needs
            resolving to an object id, so it asks the same present-and-not-null question about the
            same kind of node that Resolve-OERRoleManagementPolicyChange.ps1 asks of it afterward.
            Its name does not end in *Change (it resolves names, it does not diff), which is exactly
            why it is named individually here rather than folded into the Resolve-OER*Change bullet
            above.

        Resolve-OERAssignmentPolicyChange.ps1 is the ONE Resolve-OER*Change helper deliberately left
        out, and the reason is structural rather than a judgement call: it takes -Desired (a BUILT
        projection, already through Build-OERPolicyParts) and -DeclaredFields (a [string[]] the
        caller already computed), never a raw document node, so the declared-value rule has nothing
        to govern there. Checking a parameter named -Declared holding a [PSCustomObject] is the
        distinguishing test, not the file's name.

        THIS SCOPE PARAGRAPH HAS BEEN WRONG TWICE, and both times the wrongness was a UNIVERSAL
        claim about the tree that a narrower list could not support. Recorded rather than quietly
        corrected, since a scope justification that is false is worse than none:
          1. The first version claimed "only the Sync-OERStructure* handlers walk apply-document
             nodes at all" and enumerated out-of-scope sites without naming
             Resolve-OERGroupEligibilityChange.ps1 or Read-OERStructureDocument.ps1. The
             whole-branch review of this sprint caught it.
          2. The second version opened "SCOPE is every file that walks an APPLY-DOCUMENT node" while
             covering only two of the five such helpers -- and its own next sentence named two of the
             three it had left out. The scoped re-review caught it, and mutation-proved the hole:
             three bare chains planted in Resolve-OERAccessReviewChange.ps1 left this gate at
             25 passed / 0 failed.
        Hence the present wording. This paragraph now states what the LIST is; it makes no claim
        about files not on it.

        The remaining PSObject.Properties.Name call sites module-wide -- schema validation in
        Test-OERStructureSchema.ps1, the inventory projection in Get-OERInventory.ps1 and
        Export-OERInventory.ps1, Invoke-OERStructure.ps1's own document-shape checks, and the two
        predicate helpers' own bodies -- inspect a document being READ from Graph or validated
        OFFLINE, neither of which is the "declared vs. explicit null" apply-time question this rule
        governs, so they are correctly out of scope rather than exempted one by one. Measured before
        each widening (Constraint: measure, do not reason). Round 2: the chain predicate found
        exactly two sites across the two files added then, both un-migrated declared-value reads,
        neither a legitimate non-declared-rule use. Round 3: it found ZERO across the three
        Resolve-OER*Change files added then -- the only textual "PSObject.Properties" in any of them
        is a COMMENT in Resolve-OERAccessReviewChange.ps1 saying the live settings are a raw Graph
        dictionary with no PSObject.Properties to enumerate, and a comment is a token the parser
        discards before this walk sees the tree. So neither widening needed an allowlist entry.

        SCOPE MAINTENANCE. A new private helper handed an apply-document node -- a -Declared or
        -Document [PSCustomObject] parameter is the tell -- belongs in
        $script:declaredValueDocumentConsumerNames below AND in the named-file control's $Expected
        list. Both are named-FILE lists, not counts, so a file that disappears from the scan is named
        in the failure rather than merely changing a number. What neither can see is a file that
        should be on the list and never was: that is the hole both earlier versions of this paragraph
        fell into, and the only guard against it is reading this note before adding a helper.

        DETECTION SHAPE (fix round 1, finding S1). The first version of this gate keyed detection on
        the -contains-family OPERATOR: it walked BinaryExpressionAst nodes and checked whether the
        LEFT operand was the chain. That missed the intermediate-variable form entirely --

            $Props = $Item.PSObject.Properties.Name
            ...
            if ($Props -contains 'foo') { ... }

        -- because the chain there feeds an AssignmentStatementAst, never a -contains
        BinaryExpressionAst, so the old walk never visited it. Verified live: injecting that exact
        shape left the gate green. Fixed by flagging the CHAIN ITSELF, independent of what consumes
        it: every MemberExpressionAst in a handler file that Get-OERPropertiesNameChainRoot resolves
        is a candidate violation, whether its parent is a comparison, an assignment, a pipeline
        element, or anything else. Test-OERDeclaredProperty's own help states the rule is about
        READING a node's property names for the declared/absent/null question, not about the
        specific operator later applied to what was read -- so the read itself is what this gate now
        flags. Measured before adopting the broad form (Constraint: measure before committing to it,
        do not adopt by reasoning): the SAME chain predicate already used for the module-wide count
        below, restricted to just the seven handler files, finds exactly the one known site --
        Sync-OERStructureGroup.ps1's $PimResult check -- and nothing else. No legitimate handler use
        of the chain for a different purpose (e.g. enumerating property VALUES rather than testing
        for a NAME) exists in the tree today, so broadening introduces no new legitimate site that
        would need its own allowlist entry.

        ALLOWLIST KEY (fix round 1, finding S2). The first version keyed the allowlist
        '<FileName>:<VariableOrContext>' only. That swallows a FUTURE second, unrelated violation
        that happens to reuse the same variable name in the same file for a genuine apply-document
        read -- e.g. a later '$PimResult.PSObject.Properties.Name -contains ''SomeOtherProperty''' on
        a $PimResult that, in a different code path, legitimately holds a document node. Confirmed
        live. Fixed by keying '<FileName>:<VariableOrContext>:<PropertyLiteral>' instead, where
        PropertyLiteral is extracted structurally (see Get-OERContainsLiteral below) only when the
        chain is the immediate LEFT operand of a -contains-family comparison against a literal
        string on the right -- exactly the shape of the one real exemption. A chain used any other
        way (assigned to a variable, compared to a non-literal, etc.) yields no literal, so it can
        NEVER match an allowlist entry and is always reported -- this is deliberately conservative:
        the intermediate-variable shape that triggered S1 is caught by BOTH fixes at once, since it
        is flagged by the broadened detection and is structurally ineligible for exemption by the
        narrowed key.

        KNOWN RESIDUAL LIMITS, stated honestly rather than left implicit:
        1. INDEX / COMPUTED MEMBER SYNTAX. The chain predicate only recognises literal dotted member
           access ('.PSObject.Properties.Name'). A rewrite as '.PSObject.Properties[''Name'']' (index
           syntax) or through a computed member name builds a different AST node shape entirely and
           evades this gate exactly as it did before this fix round. Verified today that no such
           shape exists anywhere in source/ -- a property of the current source, not a guarantee this
           gate enforces going forward.
        2. NO DATA-FLOW TRACING. The gate flags the CHAIN's own read site (an assignment target, a
           comparison, whatever), but does not trace an intermediate variable forward to find out
           what it is later compared against. A violation naming an assignment therefore shows only
           the read itself, not the downstream test -- which is enough to require a human look (that
           read has no allowlist entry and cannot get one without being rewritten into the direct
           comparison shape), but means the ONE real exemption site would stop matching the allowlist
           and start failing this gate if it were ever refactored to introduce a variable in between,
           even though the check itself would still be legitimate. That failure is the safe direction
           (loud, not silent) and the fix is to keep -- or restore -- the direct chain-into-comparison
           shape at that one site, not to weaken this gate.
        3. THREE FURTHER SPELLINGS OF THE SAME QUESTION (added fix round 2, from the whole-branch
           review's independent probe of this gate's own predicates). The chain predicate keys on the
           exact 'PSObject' -> 'Properties' -> 'Name' member sequence, so these idiomatic PowerShell
           equivalents are NOT detected:
             a. $Item.PSObject.Members.Name -contains 'foo'      (Members, not Properties)
             b. $Item | Get-Member -Name 'foo'                   (a command, not a member chain)
             c. $Item.PSObject.Properties | Where-Object Name -eq 'foo'   (chain stops at Properties)
           Verified during that probe that none exists in source/ today: the only
           PSObject.Properties-without-.Name use in a scanned file enumerates property VALUES
           (Sync-OERStructureGroup.ps1's naming-token walk), and no scanned file calls Get-Member at
           all. Documented rather than closed -- a deliberate call, on the same reasoning as limit 1:
           this block's value is that it stays honest about what the gate does not see, and chasing
           every spelling would trade that honesty for a predicate no one can audit. Anyone adding
           one of these shapes to an apply-document walker is bypassing a rule they had to read this
           comment to bypass.

        CURRENT MEASUREMENTS, re-taken with this gate's own counter on every round rather than
        carried forward (fix round 3 found the previous figure had gone stale in this very block --
        the one that says "measure, do not reason"). Sprint 6 step 2 added
        Resolve-OERDeclaredApprover.ps1 to the scanned set (a seventh document consumer), moving the
        scanned-file count from 13 to 14; it introduces no PSObject.Properties.Name chain of its own
        (it calls Test-OERDeclaredProperty throughout), so the chain-predicate figures below are
        unchanged by its addition:
          - scanned files: 14 (the 7 Sync-OERStructure* handlers + the 7 named document consumers).
          - source/**/*.ps1: 214 files.
          - chain predicate, module-wide: 25.
          - of those, in-scope: exactly ONE -- the $PimResult check in Sync-OERStructureGroup.ps1
            that $script:declaredValueAllowlist documents below, keyed with its literal ('Applied').

        HOW THE MODULE-WIDE NUMBER MOVED, since a bare figure invites the next reader to trust it:
        it was 27 before fix round 2, and 25 after -- NOT because the scan changed (the module-wide
        count walks every MemberExpressionAst in source/ regardless of consumer and regardless of
        scope, so neither broadening the DETECTION shape nor widening the SCOPE moves it), but
        because round 2 MIGRATED two chains out of existence in Resolve-OERGroupEligibilityChange.ps1
        and Read-OERStructureDocument.ps1. Round 3 widened the scope by three more files and moved it
        by zero, exactly as the invariant above predicts: those three carry no chain at all. In-scope
        counts along the way: 3 before round 2's migration (the $PimResult check plus the two sites
        the widened scope exposed), 1 after; round 3 left it at 1.

        WHY THE FLOOR BELOW IS "> 20" AND NOT "> 24". Before the Tasks 2/3/5/6 migration the
        handler-scoped count was 26; the migration is what makes any handler-scoped number unusable
        as this gate's non-vacuity floor -- a threshold checked against the post-migration in-scope
        "1" cannot tell a working scan from a predicate that stopped firing, since both numbers are
        small. The module-wide count is the usable one, and the floor is deliberately kept loose so
        an unrelated refactor does not redden a gate that is working. The margin is now 5 (25 against
        a floor of 20) and SHRINKS with every future migration, which is the intended direction:
        when it does redden, that is the loud, safe failure -- re-measure with this gate's own
        counter, update the four figures above, and re-place the floor deliberately. Do not lower
        the floor to make a red build pass without doing that.

        This is its own parse pass rather than folded into Pass 1's shared walk, matching Pass 6's own
        stated reason above: a mistake here cannot perturb the six existing gates' proven reachability
        closure or catch-clause scan.
        =====================================================================================
    #>
    <#
        The seven apply-document consumers outside the Sync-OERStructure* glob (see SCOPE above).
        Named one by one on purpose: a second glob -- 'Resolve-OER*Change.ps1', say -- would be
        another implicit claim about which files walk document nodes, and it would be wrong, since
        Resolve-OERAssignmentPolicyChange.ps1 matches that shape and takes no document node at all.
        It was exactly such an implicit claim that let these files go unscanned through two rounds.
        Sprint 6 step 2 added Resolve-OERDeclaredApprover.ps1, which reads a declared approvers block
        before the approval diffs.
    #>
    $script:declaredValueDocumentConsumerNames = @(
        'Get-OEROmittedPruneCollection.ps1'
        'Read-OERStructureDocument.ps1'
        'Resolve-OERAccessReviewChange.ps1'
        'Resolve-OERDeclaredApprover.ps1'
        'Resolve-OERGroupEligibilityChange.ps1'
        'Resolve-OERGroupPimPolicyChange.ps1'
        'Resolve-OERRoleManagementPolicyChange.ps1'
    )
    $script:declaredValueHandlerFiles = @($script:cmdletRefFiles | Where-Object {
            ($_.RelativePath -match '^source[\\/]Private[\\/]Sync-OERStructure[^\\/]*\.ps1$') -or
            (($_.RelativePath -match '^source[\\/]Private[\\/]') -and
                ($script:declaredValueDocumentConsumerNames -contains [System.IO.Path]::GetFileName($_.RelativePath)))
        })
    $script:declaredValueHandlerPaths = [System.Collections.Generic.HashSet[string]]::new(
        [string[]]@($script:declaredValueHandlerFiles | ForEach-Object { $_.RelativePath -replace '/', '\' }),
        [System.StringComparer]::OrdinalIgnoreCase)

    <#
        The chain predicate, expressed against the AST rather than a text pattern. Matches
        "<expr>.PSObject.Properties.Name" -- three MemberExpressionAst links, each a NON-STATIC member
        access (Static is $false; a static member access such as [Foo]::Bar builds the same node type
        with Static set, and PSObject/Properties/Name is never one) whose Member is a plain string
        literal 'PSObject', 'Properties' and 'Name' in that order, inside out. Returns the ROOT
        expression (the AST node for <expr>) rather than a bare boolean, so a caller can render it as
        the allowlist anchor text -- e.g. the VariableExpressionAst for $PimResult -- instead of losing
        that context.
    #>
    function Test-OERPropertiesNameMember {
        param($Member, [string]$Expected)
        return ($Member -is [System.Management.Automation.Language.StringConstantExpressionAst]) -and
            ($Member.Value -eq $Expected)
    }

    function Get-OERPropertiesNameChainRoot {
        param($MemberExpr)

        if ($MemberExpr -isnot [System.Management.Automation.Language.MemberExpressionAst]) { return $null }
        if ($MemberExpr.Static) { return $null }
        if (-not (Test-OERPropertiesNameMember -Member $MemberExpr.Member -Expected 'Name')) { return $null }

        $Mid = $MemberExpr.Expression
        if ($Mid -isnot [System.Management.Automation.Language.MemberExpressionAst]) { return $null }
        if ($Mid.Static) { return $null }
        if (-not (Test-OERPropertiesNameMember -Member $Mid.Member -Expected 'Properties')) { return $null }

        $Inner = $Mid.Expression
        if ($Inner -isnot [System.Management.Automation.Language.MemberExpressionAst]) { return $null }
        if ($Inner.Static) { return $null }
        if (-not (Test-OERPropertiesNameMember -Member $Inner.Member -Expected 'PSObject')) { return $null }

        return $Inner.Expression
    }

    <#
        Fix round 1, finding S2. Extracts the property-name literal a chain node is tested against,
        so the allowlist key can name it specifically instead of exempting every use of the same
        variable. Returns $null (no literal, hence no possible allowlist match -- see the DETECTION
        SHAPE note above) unless the chain node is the exact, immediate LEFT operand of a
        -contains-family comparison whose RIGHT operand is a literal string. Reference equality
        (not -eq) on Parent.Left: two structurally-identical-looking chains are still different AST
        node instances, and only the SAME instance FindAll already visited should ever match here.
    #>
    function Get-OERContainsLiteral {
        param($ChainNode)

        $Parent = $ChainNode.Parent
        if ($Parent -isnot [System.Management.Automation.Language.BinaryExpressionAst]) { return $null }
        if (-not [System.Object]::ReferenceEquals($Parent.Left, $ChainNode)) { return $null }
        if ($Parent.Operator -notin @(
                [System.Management.Automation.Language.TokenKind]::Icontains,
                [System.Management.Automation.Language.TokenKind]::Inotcontains,
                [System.Management.Automation.Language.TokenKind]::Ccontains,
                [System.Management.Automation.Language.TokenKind]::Cnotcontains)) { return $null }

        $Right = $Parent.Right
        if ($Right -is [System.Management.Automation.Language.StringConstantExpressionAst] -or
            $Right -is [System.Management.Automation.Language.ExpandableStringExpressionAst]) {
            return $Right.Value
        }
        return $null
    }

    <#
        The allowlist. Keyed '<FileName>:<VariableOrContext>:<PropertyLiteral>' (fix round 1, finding
        S2 -- the property literal joined the key so a future site cannot hide behind a reused
        variable name), never a bare line number -- line numbers rot on the next unrelated edit to
        the same file, the same reasoning $script:scrubExemptions and $script:cloudHostExemptions
        above are keyed against. Every entry must carry a written reason (spec pre-decision for issue
        #70: a blanket exemption is not acceptable). Proven load-bearing rather than decorative by
        mutation -- see task-8-report.md: removing this single entry reddens the assertion below on
        exactly the site it names, and a second, differently-keyed $PimResult site reddens too rather
        than being silently covered by this one.
    #>
    $script:declaredValueAllowlist = @{
        'Sync-OERStructureGroup.ps1:$PimResult:Applied' = 'reads the RESULT object returned by Set-OERGroupPimPolicy (a transport response), not an apply-document node -- Test-OERDeclaredProperty''s own help states the predicate is for apply-document nodes, so the declared-value rule does not govern this check'
    }

    $script:declaredValuePropsNameChainCount = 0
    $script:declaredValueViolations = @()
    $script:declaredValueParseFailures = @()

    foreach ($File in $script:cmdletRefFiles) {
        $RelativePath = ($File.RelativePath -replace '/', '\')

        $FileTokens = $null
        $FileErrors = $null
        $FileAst = [System.Management.Automation.Language.Parser]::ParseInput(
            $File.Text, $File.Path, [ref]$FileTokens, [ref]$FileErrors)

        if ($FileErrors.Count -gt 0) {
            # Already reported by Pass 1's own "parses every scanned source file" assertion; recorded
            # here too so THIS gate's non-vacuity counts are never silently thinned by a file that
            # dropped out for the same reason -- matches the Sovereign cloud endpoint hygiene
            # Describe's own $script:sovereignParseFailures pattern above.
            $script:declaredValueParseFailures += $RelativePath
            continue
        }

        $IsHandlerFile = $script:declaredValueHandlerPaths.Contains($RelativePath)
        # From the NATIVE RelativePath, not the '\'-normalized $RelativePath: '\' is not a directory
        # separator on Linux or macOS, where GetFileName of the normalized string is the whole path.
        $FileBaseName = [System.IO.Path]::GetFileName($File.RelativePath)

        $MemberNodes = $FileAst.FindAll({
                $args[0] -is [System.Management.Automation.Language.MemberExpressionAst]
            }, $true)
        foreach ($MemberNode in $MemberNodes) {
            $ChainRoot = Get-OERPropertiesNameChainRoot -MemberExpr $MemberNode
            if ($null -eq $ChainRoot) { continue }

            $script:declaredValuePropsNameChainCount++
            if (-not $IsHandlerFile) { continue }

            <#
                Fix round 1: no operator filter here at all -- every resolved chain in a handler file
                is a candidate violation regardless of what consumes it (see DETECTION SHAPE above).
                A literal is looked up ONLY to check the allowlist; its absence does not exempt
                anything, it just means no allowlist entry can possibly match.
            #>
            $PropertyLiteral = Get-OERContainsLiteral -ChainNode $MemberNode
            $IsAllowlisted = $false
            if ($null -ne $PropertyLiteral) {
                $AllowlistKey = '{0}:{1}:{2}' -f $FileBaseName, $ChainRoot.Extent.Text.Trim(), $PropertyLiteral
                $IsAllowlisted = $script:declaredValueAllowlist.ContainsKey($AllowlistKey)
            }
            if ($IsAllowlisted) { continue }

            $script:declaredValueViolations += '{0}:{1} -- {2}' -f
                $RelativePath, $MemberNode.Extent.StartLineNumber, $MemberNode.Parent.Extent.Text.Trim()
        }
    }

    <#
        =====================================================================================
        Pass 8: Az-context hygiene. The module acquires an ARM bearer token through AzAuth and
        sends it itself (Invoke-OERArmRequest); it deliberately never calls Connect-AzAccount or
        Set-AzContext, so it never establishes an Az PowerShell context. That property is the
        premise Az.Resources was removed from the manifest on (PR #2, 2026-09-21), and it is what
        source/Public/Connect-OER.ps1's help now promises a caller.

        Until now the property was proven only by MOCK-BASED tests -- the
        'Should -Invoke ... Connect-AzAccount -Times 0' assertion in
        tests/Unit/Private/Initialize-OERAuth.Tests.ps1. Those assertions are sound, but they are
        load-bearing on something they do not control: Pester's Mock resolves the command it is
        given and throws when it cannot, so they only run while Az.Accounts is resolved into
        output/RequiredModules. A session that removed Az.Accounts and then deleted the failing
        Mock and its -Times 0 assertion to get back to green would delete the proof, and nothing
        would say so. That gap was flagged on PR #2 and this pass closes it.

        This gate proves the PROPERTY directly and is independent of what is installed: it reads
        the source text and asks the PowerShell parser what is CALLED there. No Az module needs to
        be present for it to run, and no mock can weaken it.

        DETECTION SHAPE. One AST pass over every source/**/*.ps1, collecting every CommandAst and
        rejecting any whose command name matches '-Az' unless it is explicitly allowed. The AST is
        used rather than a text scan for the reason the bearer-scrub gate gives: a parser does not
        see comments or comment-based help, and source/ is full of prose that names
        Connect-AzAccount and Invoke-AzRestMethod precisely to say the module does NOT call them.
        A grep would drown in those; the parser never offers them.

        KNOWN LIMIT, stated rather than papered over. A command name built at run time is invisible
        here: GetCommandName() returns $null for '& $Variable', so a call assembled into a variable
        would not be detected. Measured on this tree, 26 CommandAst nodes have no static name --
        25 whose first element is a VariableExpressionAst ('& $Fail', '& $CollectIds', '& $Describe',
        '& $ValidatePimBlock') and one MemberExpressionAst ('& $Section.Handler' in
        Invoke-OERStructure.ps1). PR #2 verified by hand that every one of them invokes a LOCAL
        SCRIPTBLOCK, never a command name, and that the module contains no Invoke-Expression, no
        [scriptblock]::Create and no string-built command name. If a dynamic dispatch on a real
        command name is ever introduced, this gate cannot see it and the review must.
    #>
    $script:azContextAllowedCommands = [System.Collections.Generic.HashSet[string]]::new(
        [string[]]@(
            # AzAuth's own token surface. Acquiring a token is the whole design; it establishes no
            # context. Get-AzTokenCache and Clear-AzTokenCache are named here for completeness --
            # measured on this tree they appear only in comments, never as a call.
            'Get-AzToken'
            'Get-AzTokenCache'
            'Clear-AzTokenCache'
            # The module's OWN internal helper, defined inside Initialize-OERAuth.ps1. It wraps
            # Get-AzToken; the name merely matches the pattern.
            'Invoke-AzTokenCall'
        ),
        [System.StringComparer]::OrdinalIgnoreCase)

    <#
        NO EXEMPTIONS. There was one, briefly, and its removal is worth recording.

        source/Public/Disconnect-OER.ps1 used to call Disconnect-AzAccount behind a Get-Command
        guard, so this gate was first written with that one call exempted, pinned to the file, plus
        an assertion that the exemption still matched exactly one live site. That assertion is what
        made the exemption self-retiring, and it did its job: when the call was removed (Philip's
        decision, 2026-09-21 -- the module never establishes an Az context, so the call could only
        ever reach the operator's OWN Az session and on-disk token cache) the gate went red asking
        for the exemption to be retired rather than silently leaving that file exempt. It was
        retired in the same pull request, so the exemption never reached main.

        The allowlist below is therefore the whole of it. Do not reintroduce a per-file exemption:
        the module now calls no Az cmdlet at all outside AzAuth's token surface.
    #>

    $script:azContextParsedFileCount = 0
    $script:azContextCommandAstCount = 0
    $script:azContextAzCallCount     = 0
    $script:azContextParseFailures   = @()
    $script:azContextViolations      = @()

    foreach ($File in $script:cmdletRefFiles) {
        $RelativePath = ($File.RelativePath -replace '/', '\')

        $FileTokens = $null
        $FileErrors = $null
        $FileAst = [System.Management.Automation.Language.Parser]::ParseInput(
            $File.Text, $File.Path, [ref]$FileTokens, [ref]$FileErrors)

        if ($FileErrors.Count -gt 0) {
            # Recorded, not skipped silently: a file that stopped parsing would otherwise thin this
            # gate's non-vacuity counts without anything noticing.
            $script:azContextParseFailures += $RelativePath
            continue
        }
        $script:azContextParsedFileCount++

        $CommandNodes = @($FileAst.FindAll({
                    $args[0] -is [System.Management.Automation.Language.CommandAst]
                }, $true))
        $script:azContextCommandAstCount += $CommandNodes.Count

        foreach ($CommandNode in $CommandNodes) {
            $CommandName = $CommandNode.GetCommandName()

            # $null for a dynamically dispatched call -- see KNOWN LIMIT above.
            if ([string]::IsNullOrEmpty($CommandName)) { continue }
            if ($CommandName -notmatch '-Az') { continue }

            $script:azContextAzCallCount++

            if ($script:azContextAllowedCommands.Contains($CommandName)) { continue }

            $script:azContextViolations += '{0}:{1} -- calls {2}: {3}' -f
                $RelativePath, $CommandNode.Extent.StartLineNumber, $CommandName,
                (($CommandNode.Extent.Text -split "`n")[0].Trim())
        }
    }
}

Describe 'Source encoding' -Tags 'SourceHygiene' {

    It 'finds authored files in every scanned root' {
        <#
            Guards the whole Describe: an empty collection would make every other It vacuously pass,
            because a foreach over nothing asserts nothing.

            Asserted PER ROOT, not as one total. A single total of 100 tolerated losing 76% of the
            tree, and losing the ENTIRE source/ root (208 files) or the entire tests/ root (214)
            still cleared it.

            Each floor sits just under its own root's real count, not at a shared round number. A
            floor of 190 against tests/ 214 left 24 files of slack -- enough for a small directory
            such as tests/Unit/Formats to vanish without tripping anything. This is defence in depth
            rather than the primary guard: the named-control assertion below is what actually catches
            an enumeration that breaks, and per-file QA gates catch a single deleted test. What a
            floor adds is a signal when a whole directory silently stops being scanned, and it only
            adds it while the slack stays small. Raise each number when the tree genuinely grows.
        #>
        $SourceCount = @($script:hygieneFiles | Where-Object { $_.RelativePath -match '^source[\\/]' }).Count
        $TestCount = @($script:hygieneFiles | Where-Object { $_.RelativePath -match '^tests[\\/]' }).Count

        $SourceCount | Should -BeGreaterThan 190 -Because (
            'source/ held 208 authored files at the time this gate was written; a scan that drops below 190 has lost a directory, not shrunk')
        $TestCount | Should -BeGreaterThan 205 -Because (
            'tests/ held 214 authored files at the time this gate was written; a scan that drops below 205 has lost a directory, not shrunk')
    }

    It 'scans the named control files' {
        # A named control cannot erode the way a threshold can. These two files are the ones whose
        # disappearance a count would hide: one per scanned root.
        $script:hygieneFilePaths.Contains('source\Private\Invoke-OERGraphRequest.ps1') |
            Should -BeTrue -Because 'the Graph wrapper must be in the encoding scan; if it is not, the source/ enumeration is broken'
        $script:hygieneFilePaths.Contains('tests\QA\sourcehygiene.tests.ps1') |
            Should -BeTrue -Because 'this gate scans itself; if it is not in its own collection, the tests/ enumeration is broken'
    }

    It 'contains no byte above 0x7F in any authored file' {
        $Offenders = foreach ($File in $script:hygieneFiles) {
            <#
                Fast path on the DECODED text. A single regex over one string costs ~0.08s across the
                whole tree; the per-byte foreach below costs ~3.5s, and CI is always cold, so that
                loop dominated tests/QA/ runtime for no benefit. Safe because invalid UTF-8 decodes
                to U+FFFD, which is itself above 0x7F, so a file that is not valid UTF-8 still trips
                the match -- as does a UTF-8 BOM, which decodes to U+FEFF.

                The byte-level count and offset are kept for the diagnostic and run only for a file
                already known to be dirty, so their per-byte work never touches the clean path.
            #>
            if ($File.Text -notmatch '[^\x00-\x7F]') { continue }

            $Count = 0
            foreach ($Byte in $File.Bytes) {
                if ($Byte -gt 0x7F) { $Count++ }
            }
            $FirstOffset = [Array]::FindIndex($File.Bytes, [Predicate[byte]] { param($B) $B -gt 0x7F })
            '{0} ({1} non-ASCII bytes, first at offset {2})' -f $File.RelativePath, $Count, $FirstOffset
        }
        $Offenders -join "`n" | Should -BeNullOrEmpty -Because @'
CLAUDE.md requires authored .ps1/.psd1/.psm1/.ps1xml files to be ASCII-only. Use -- instead of an
em-dash, straight quotes instead of smart quotes, and ASCII hyphens instead of box-drawing runs.
PSScriptAnalyzer's PSUseBOMForUnicodeEncodedFile does NOT cover this: it inverts to a pass the moment
the file gains a BOM, and it never sees anything under tests/ at all.
'@
    }

    It 'carries no UTF-8 BOM in any authored file' {
        $Offenders = foreach ($File in $script:hygieneFiles) {
            if ($File.Bytes.Length -ge 3 -and
                $File.Bytes[0] -eq 0xEF -and $File.Bytes[1] -eq 0xBB -and $File.Bytes[2] -eq 0xBF) {
                $File.RelativePath
            }
        }
        $Offenders -join "`n" | Should -BeNullOrEmpty -Because @'
CLAUDE.md requires authored files to be UTF-8 WITHOUT a BOM. A BOM also silently disables
PSScriptAnalyzer's PSUseBOMForUnicodeEncodedFile rule, so a BOM-carrying file can hide non-ASCII
content from the analyzer entirely. There is deliberately NO allow-list here: source/Private/Write-CmdletError.ps1
was the one historical exception (a verbatim copy from Omnicit.PIM) and commit b482b8c forked it, so
the exception no longer applies.
'@
    }
}

Describe 'Bearer-token hygiene' -Tags 'SourceHygiene' {

    It 'parses every scanned source file' {
        $script:parseFailures -join "`n" | Should -BeNullOrEmpty -Because @'
A source file that fails to parse produces no CommandAst and no CatchClauseAst, so it silently drops
out of BOTH the transport-file counter and the catch counter below -- an unterminated here-string at
the top of a file removes it from this gate without failing anything. Fix the syntax error; do not
exclude the file.
'@
    }

    It 'scans a meaningful number of catch clauses' {
        <#
            Without this, a detection bug that matched no files would make the gate below pass
            vacuously -- prove a guard can FAIL, not just that it can pass.

            The previous thresholds (50 files, 200 catches) tolerated losing 46% and 22% of the scan
            respectively. These sit just under the measured values after the call-closure widening:
            117 transport-reaching files, 318 catches of the 338 in source/.
        #>
        $script:scrubTransportFileCount | Should -BeGreaterThan 110
        $script:scrubCatchCount | Should -BeGreaterThan 310
    }

    It 'counts every catch of the named control file' {
        <#
            The named positive control. source/Private/Invoke-OERGraphRequest.ps1 is the module's
            Graph transport wrapper and the one file that can never legitimately leave this scan.
            The exact count is asserted rather than a floor so that a catch which stops being seen --
            because a parse broke, or the enumeration changed -- fails HERE with a clear cause instead
            of quietly shrinking a total. If a catch is genuinely added to or removed from that file,
            update this number deliberately.
        #>
        $ControlPath = 'source\Private\Invoke-OERGraphRequest.ps1'

        $script:scrubCatchByFile.ContainsKey($ControlPath) |
            Should -BeTrue -Because 'the Graph wrapper must be detected as a transport file; if it is not, transport detection is broken'
        # 11 -> 12 when the Retry-After header read was made shape-tolerant: the single
        # .Response.Headers.GetValues catch was replaced by two (one guarding the .Response.Headers
        # property read, one inside the Get-RetryAfterHeaderValue reader itself).
        # 12 -> 13 with -ExpectedErrorCode: ConvertTo-SoftFailureRecord guards the response rebuild, since
        # an exception escaping there would replace the Graph error the caller needs to see.
        # 13 -> 14 with issue #73 (a failure on page N no longer discards what was already read): the
        # -All paging loop wraps its Invoke-GraphSingle call in its OWN try/catch so it can attach
        # PartialValue/NextLink/PageNumber to the failing Exception before re-throwing -- a second,
        # separate catch clause from the ones already inside Invoke-GraphSingle, so it needs its own
        # scrub-first statement even though the inner function already scrubbed on its own paths. The
        # comment-based help's final .EXAMPLE also shows a try/catch, but that text lives inside the
        # <# ... #> block comment and produces no CatchClauseAst, so it is not part of this count.
        $script:scrubCatchByFile[$ControlPath] | Should -Be 14 -Because (
            'source/Private/Invoke-OERGraphRequest.ps1 holds 14 catch clauses and every one of them scrubs first')
    }

    It 'calls Remove-OERErrorRecord as the first statement of every Graph/ARM catch' {
        $script:scrubViolations -join "`n" | Should -BeNullOrEmpty -Because @'
CLAUDE.md SECURITY rule 6: the raw HttpRequestMessage stored in $Error carries Authorization: Bearer
<token> in plain text, so Remove-OERErrorRecord -Record $PSItem must be the FIRST statement of every
catch in a file that reaches Graph, ARM or a token acquisition -- directly or through any module
function it calls. The older $Error.Remove($PSItem) idiom never worked -- a module has its own
private $Error list, and the ErrorRecord bound to $PSItem is a different instance than the one
PowerShell appended to the caller's $global:Error, so reference-equality removal no-ops.
If a catch is genuinely exempt (no HTTP record can reach it), add it to $script:scrubExemptions with
a written reason rather than deleting this assertion.
'@
    }
}

Describe 'Duration encoder hygiene' -Tags 'SourceHygiene' {

    It 'scans a meaningful number of -f format-operator expressions' {
        # Without this, a predicate typo (e.g. the wrong TokenKind, or a BinaryExpressionAst that
        # never reaches this branch) would make the assertion below pass VACUOUSLY -- prove the AST
        # walk still finds -f operators before trusting that none of them build a duration.
        $script:durationFormatOperatorCount | Should -BeGreaterThan 20 -Because (
            'source/ carries well over 20 -f format-operator expressions (Graph/ARM URI templates
in particular); a count that drops near zero means the BinaryExpressionAst branch stopped firing,
not that the tree stopped using -f')
    }

    It 'builds no ISO 8601 duration by hand outside ConvertTo-OERDuration' {
        $script:durationFormatViolations -join "`n" | Should -BeNullOrEmpty -Because @'
CLAUDE.md: ConvertTo-OERDuration is the sole int-to-ISO encoder. A file that instead formats a
'PT{0}H'/'P{0}D'-shaped literal with the -f operator (New-OERPimRuleSet.ps1 used to carry
maximumDuration = ("PT{0}H" -f $ActivationMaxHours)) bypasses that owner and can drift from it --
XmlConvert::ToString(([timespan]::FromHours($n))) and a hand-rolled "PT{0}H" -f $n happen to agree
for the values in range today, but nothing enforces that agreement going forward. Route the value
through ConvertTo-OERDuration instead of formatting the literal in place.
'@
    }
}

Describe 'Cmdlet reference hygiene' -Tags 'SourceHygiene' {

    It 'scans a meaningful number of source files and cmdlet-name tokens' {
        <#
            Without this, a detection bug that matched no files (a broken regex, an empty file list)
            would make the assertion below pass VACUOUSLY -- prove the scan can find something before
            trusting that it found nothing wrong. Thresholds sit just under the measured values,
            RE-MEASURED after round-1 finding I-3 widened the verb set from a hardcoded 14 to all 23
            verbs actually used in the tree (205 source/**/*.ps1 files, 3291 Verb-OER... tokens --
            up from 2040 because Convert/ConvertTo/Write/Sync/Resolve and others are now in scope).
        #>
        $script:cmdletRefFiles.Count | Should -BeGreaterThan 195 -Because (
            'source/ held 205 .ps1 files at the time this gate was written; a scan that drops below 195 has lost a directory, not shrunk')
        $script:cmdletRefTokenCount | Should -BeGreaterThan 3100 -Because (
            'source/**/*.ps1 carried 3291 Verb-OER... tokens after the I-3 verb-set widening; a scan that drops below 3100 has broken detection (e.g. a shrunk verb set), not found fewer references')
    }

    It 'every Verb-OER... token in source/**/*.ps1 resolves to a real Public or Private function' {
        $script:cmdletRefViolations -join "`n" | Should -BeNullOrEmpty -Because @'
A comment-based help block naming a cmdlet that does not exist under source/Public or source/Private
is stale documentation pointing a reader at a command that will fail if they run it -- for example
ConvertTo-OERAccessReviewDecision.ps1 once described itself as "used by Get-OERAccessReviewDecision",
a cmdlet this module has never exported (the real callers are Get-OERAccessReviewInstanceDecision and
Get-OERAccessReviewInstance -IncludeDecisions). This is a TEXT scan over the whole file, not an AST
walk, specifically because a stale reference lives in PROSE -- a comment token the parser never turns
into a CommandAst -- so an AST-only pass would never see it. Fix the reference; do not exempt a file
from this scan.
'@
    }
}

Describe 'ARM api-version documentation hygiene' -Tags 'SourceHygiene' {

    It 'finds the rationale doc and its ## arm-transport section' {
        # Guards the two assertions below: an unreadable file or a renamed/removed heading would
        # leave $script:armTransportSection empty, which would make the per-version check below
        # pass VACUOUSLY (every -notmatch against an empty haystack is true, so every version would
        # be reported "undocumented" -- loud, not vacuous, but still the wrong failure to debug).
        # This isolates "the section could not be found" from "a version is missing from it".
        (Test-Path -LiteralPath $script:rationalePath) | Should -BeTrue -Because (
            'docs/development/rationale.md must exist for this gate to read anything')
        $script:armTransportSection | Should -Not -BeNullOrEmpty -Because (
            'the ## arm-transport heading must be present with a non-empty body, or every version below reports as undocumented for the wrong reason')
    }

    It 'scans a meaningful number of ARM api-version literals' {
        # Same non-vacuous-scan proof as the other Describes in this file. rationale.md itself
        # records 43 as the measured total (grep -rno 'api-version=[0-9-]*' source/) -- 40 real
        # request-path sites plus 3 inside Invoke-OERArmRequest's own comment-based help.
        $script:armApiVersionSiteCount | Should -BeGreaterThan 35 -Because (
            'source/**/*.ps1 carried 43 api-version=... literals when this gate was written; a scan that drops below 35 has broken detection, not found fewer pinned versions')
    }

    It 'every distinct ARM api-version literal in source/ is documented in rationale.md ## arm-transport' {
        $script:armApiVersionUndocumented -join ', ' | Should -BeNullOrEmpty -Because @'
docs/development/rationale.md ## arm-transport is the single documented list of pinned ARM
api-versions (CLAUDE.md ## ARM Requests deliberately delegates there instead of carrying its own
copy, per the 2026-08-25 trim). A version pinned in source/ but missing from that section is
un-reviewable: nothing forces a reader auditing the ARM surface to notice a new or bumped
api-version exists. Add it to the "Pinned api-versions" bullet (and the regeneration note's grep
count) in the same edit that introduces or changes the literal in source/.
'@
    }
}

Describe 'Sovereign cloud endpoint hygiene' -Tags 'SourceHygiene' {

    It 'parses every file this gate scans' {
        $script:sovereignParseFailures -join "`n" | Should -BeNullOrEmpty -Because (
            'a source file that fails to parse drops out of both scans below with no violation reported, the same silent-loss failure mode Pass 1 above documents; Pass 1 already asserts the whole tree parses, so this failing points at a file that parses for that gate and not for this one')
    }

    It 'derives its host list from the cloud-endpoint table and finds the documented set' {
        <#
            Final whole-branch review, Finding 4. The scanned host list used to be a THIRD partial
            copy of the table -- retyped here, with nothing asserting it still covered the table's
            rows. A fifth cloud added to Get-OERCloudEndpoint.ps1 would then have fallen outside the
            very gate that exists to stop that drift.

            The list is now derived from the table's own AST (see the derivation block in BeforeAll),
            so the literal scan below covers a new cloud's hosts the moment the table names them. The
            comparison against $script:cloudHostDocumented is what still makes adding a cloud a
            DELIBERATE edit rather than a silent one: it reddens until a human updates that list, the
            README endpoint table and the about topic together.

            The comparison is asserted BEFORE the exact count deliberately, and the order was
            settled by running the mutation rather than by reasoning: with a fifth 'Germany' row
            added to the table, a count-first order reported only "Expected 10 ... but got 13",
            which says a cloud was added but not which files have to change with it. The
            comparison's own message names all three. The count stays afterwards as the backstop the
            comparison cannot be -- Compare-Object over two EMPTY collections returns nothing and
            would pass vacuously if the derivation ever produced nothing AND the documented control
            were emptied in the same edit.
        #>
        $script:cloudHostDerivationFailure | Should -BeNullOrEmpty -Because (
            'the whole list this gate scans for is read out of the cloud-endpoint table; if that read failed, everything below it is measuring the fallback control instead of the real table')

        $Difference = @(Compare-Object -ReferenceObject @($script:cloudHostDocumented | Sort-Object) `
                -DifferenceObject @($script:cloudHostDerived) |
                ForEach-Object { '{0} {1}' -f $_.SideIndicator, $_.InputObject })
        $Difference -join "`n" | Should -BeNullOrEmpty -Because @'
The hosts derived from source/Private/Get-OERCloudEndpoint.ps1 no longer match the documented list in
this gate ($script:cloudHostDocumented). A '=>' line is a host the table resolves and this gate does
not name -- most likely a cloud was added to the table. Adding a cloud is a deliberate, multi-file
edit: update $script:cloudHostDocumented here, the endpoint table in README.md's Sovereign Clouds
section, and the same table in source/en-US/about_Omnicit.EntraRBAC.help.txt, in the same change that
adds the row. A '<=' line is the reverse -- a host this gate names that the table no longer resolves.
Do not delete this assertion to get past it.
'@

        $script:cloudHostDerived.Count | Should -Be 10 -Because (
            'the four rows of the table resolve ten distinct hosts (USGovDoD shares its ARM and authority hosts with USGov); a count of zero means the AST derivation stopped firing, and any other count means the table gained or lost a cloud')
    }

    It 'scans a meaningful number of source files and finds a meaningful number of cloud-host literals' {
        <#
            Without this, a predicate typo -- the wrong AST node type, a pattern that never matches --
            would make the violation assertion below pass VACUOUSLY. Thresholds sit just under the
            measured values: 205 source/**/*.ps1 files (the same count Cmdlet reference hygiene above
            measures), and 21 quoted https:// literals naming one of the ten cloud hosts -- 20 inside
            Get-OERCloudEndpoint.ps1's own table plus the one documented fallback in
            Invoke-OERArmRequest.ps1. A count that drops near zero means the AST walk stopped firing,
            not that the tree stopped naming cloud hosts.
        #>
        $script:cmdletRefFiles.Count | Should -BeGreaterThan 195 -Because (
            'source/ held 205 .ps1 files at the time this gate was written; a scan that drops below 195 has lost a directory, not shrunk')
        $script:cloudHostSiteCount | Should -BeGreaterThan 15 -Because (
            'source/**/*.ps1 carried 21 quoted cloud-host literals (all inside the table owner and the documented ARM fallback) when this gate was written; a scan that drops below 15 has broken detection, not found fewer literals')
    }

    It 'hardcodes no cloud-host literal outside Get-OERCloudEndpoint.ps1 and its documented exemptions' {
        $script:cloudHostViolations -join "`n" | Should -BeNullOrEmpty -Because @'
Get-OERCloudEndpoint.ps1 is the single owner of the Graph/ARM/authority host table for every
sovereign cloud this module supports (CLAUDE.md ## Code Style). A second file hardcoding one of the
hostnames that table resolves -- the set is derived from the table itself and listed by the
derivation assertion above, and each violation line below names the offending literal -- is a second
copy that can silently drift from the table, and on a sovereign tenant sends a request or a
credential to the wrong cloud boundary. Read the host from
Get-OERCloudEndpoint instead. If a NEW file genuinely needs its own copy for a reason as strong as
Invoke-OERArmRequest.ps1's documented public-cloud fallback, add it to $script:cloudHostExemptions
with a written reason rather than deleting this assertion.
'@
    }

    It 'counts Get-AzToken call sites and never passes -TokenCache to one' {
        <#
            Non-vacuity first, same shape as the Bearer-token hygiene Describe's named-control catch
            count above: source/Private/Initialize-OERAuth.ps1 is the module's only Get-AzToken
            caller today and calls it exactly twice (the Graph token, then the optional ARM token),
            both by splat. An EXACT count, not a floor -- if a call site is genuinely added or
            removed, update this number deliberately rather than widen it into a range.
        #>
        $script:getAzTokenCallCount | Should -Be 2 -Because (
            'source/Private/Initialize-OERAuth.ps1 calls Get-AzToken exactly twice today; a count that drops to zero means the CommandAst walk stopped firing, and a count that changes for another reason should update this assertion deliberately')

        $script:tokenCacheViolations -join "`n" | Should -BeNullOrEmpty -Because @'
Spike condition 6 (docs/development/rationale.md ## sovereign-clouds): AzAuth.Core contains exactly
one hardcoded authority, reached only when -TokenCache is passed to Get-AzToken
(CacheManager.InitializeCacheManagerAsync hardcodes AzureCloudInstance.AzurePublic). Passing
-TokenCache anywhere in this module would silently defeat the AZURE_AUTHORITY_HOST override every
sovereign-cloud sign-in depends on. Detected via CommandAst.GetCommandName() and a
CommandParameterAst named TokenCache, never a text grep, for the same reason the bearer-scrub gate
above gives: a grep would false-positive on a mention inside comment-based help.
'@
    }
}

Describe 'suffix.ps1 / psm1 mirror sync' -Tags 'SourceHygiene' {

    It 'keeps the whole mirrored region byte-identical between suffix.ps1 and the dev-mode psm1' {
        <#
            CLAUDE.md:59-60 describes suffix.ps1 as "Update-TypeData -Force blocks +
            Register-ArgumentCompleter calls, each mirrored verbatim in the dev-mode psm1", and
            CLAUDE.md ## Argument Completion rule 4 repeats the requirement for the completers
            specifically ("Register in suffix.ps1 AND mirror it in the dev-mode psm1. Drift means
            completion works from the built module but not from source, or vice versa.") -- this gate
            is what keeps both true. (Fix round 1, M-2: the previous version of this comment put a
            PARAPHRASE in quote marks as though it were verbatim CLAUDE.md text; this repo cites
            CLAUDE.md by name deliberately, so a misquote is a maintenance hazard -- corrected to the
            real line. Fix round 2, M-7: the region used to stop at the first completer, so it
            covered only the Update-TypeData half of the rule it cites. The Register-ArgumentCompleter
            half was UNCOVERED -- the two files happened to be identical there, so the hole was
            dormant, not benign.) Task 8a re-verified (md5 523aaaf9...) that the two regions were
            byte-identical before its own edit and required the same check afterward.

            The region is located by CONTENT anchors, not line numbers (line numbers drift on every
            unrelated edit, per agent-rules.md section 5): it starts at the first Update-TypeData
            occurrence in each file and now runs to END OF FILE, so one comparison covers the type
            data AND every completer registration. Anchoring the end at EOF rather than at a marker
            comment is deliberate: any future block appended to suffix.ps1 is inside the compared
            region automatically, with no gate edit and no second silent hole.

            One difference between the files is legitimate and is normalised away first. The
            dev-mode loader carries a comment-only paragraph ("Formats are loaded natively...")
            between the type data and the completers that suffix.ps1 does not have -- ModuleBuilder
            appends suffix.ps1 verbatim AFTER the built loader's own boilerplate, so that paragraph
            only ever existed in the dev-mode copy. The strip is applied to BOTH strings rather than
            just the psm1: it is a no-op on suffix.ps1 today, and writing it symmetrically means the
            gate cannot start passing for the wrong reason if that paragraph is ever moved or
            duplicated.
        #>
        $SuffixPath = Join-Path -Path $script:projectPath -ChildPath 'source\suffix.ps1'
        $Psm1Path = Join-Path -Path $script:projectPath -ChildPath 'source\Omnicit.EntraRBAC.psm1'
        $SuffixText = [System.IO.File]::ReadAllText($SuffixPath)
        $Psm1Text = [System.IO.File]::ReadAllText($Psm1Path)

        # The dev-mode-only paragraph: the marker line, its continuation lines, and the blank line
        # that closes the paragraph. '.' does not match a newline here (no (?s)), so '.*\r?\n'
        # consumes exactly one line per repetition and the lazy quantifier stops at the first blank
        # line after the marker.
        $DevModeOnlyParagraph = '(?m)^# Formats are loaded natively(?:.*\r?\n)*?\r?\n'

        $SuffixStart = $SuffixText.IndexOf('Update-TypeData')
        $Psm1Start = $Psm1Text.IndexOf('Update-TypeData')
        $SuffixRegion = if ($SuffixStart -ge 0) { ($SuffixText.Substring($SuffixStart) -replace $DevModeOnlyParagraph, '') } else { $null }
        $Psm1Region = if ($Psm1Start -ge 0) { ($Psm1Text.Substring($Psm1Start) -replace $DevModeOnlyParagraph, '') } else { $null }

        # Isolates "the start anchor did not find anything" from "the regions differ" below -- a
        # $null vs $null pair would otherwise pass the equality check vacuously.
        $SuffixRegion | Should -Not -BeNullOrEmpty -Because (
            'the mirrored region must be found in suffix.ps1 via its start anchor, or this gate is comparing nothing')
        $Psm1Region | Should -Not -BeNullOrEmpty -Because (
            'the mirrored region must be found in the psm1 mirror via its start anchor, or this gate is comparing nothing')

        # Proves the widened region actually reaches the completer half. Without this, an end anchor
        # that silently truncated back to the type data would leave the completers uncovered again
        # and the equality check would still pass -- the exact dormant hole M-7 closed.
        $SuffixRegion | Should -Match 'Register-ArgumentCompleter' -Because (
            'the compared region must include the Register-ArgumentCompleter calls, or CLAUDE.md ## Argument Completion rule 4 is unenforced again')
        $Psm1Region | Should -Match 'Register-ArgumentCompleter' -Because (
            'the compared region must include the Register-ArgumentCompleter calls, or CLAUDE.md ## Argument Completion rule 4 is unenforced again')

        $Psm1Region | Should -BeExactly $SuffixRegion -Because (
            'suffix.ps1 is appended verbatim to the built module, so every Update-TypeData call AND every Register-ArgumentCompleter call registered there must be mirrored byte-for-byte in the dev-mode psm1 loader -- otherwise a from-source import (Import-Module ./source/Omnicit.EntraRBAC.psd1) and the built module register different type data, or offer different tab-completion, for the same session')
    }
}

Describe 'Apply-document declared-value hygiene' -Tags 'SourceHygiene' {

    It 'parses every file this gate scans' {
        $script:declaredValueParseFailures -join "`n" | Should -BeNullOrEmpty -Because (
            'a source file that fails to parse drops out of both scans below with no violation reported, the same silent-loss failure mode Pass 1 above documents; Pass 1 already asserts the whole tree parses, so this failing points at a file that parses for that gate and not for this one')
    }

    It 'scans exactly the expected fourteen apply-document-walking files, by name' {
        <#
            Named-FILE control, not a bare count (fix round 2). CLAUDE.md ## Module Layout and
            ## declared-property in docs/development/rationale.md both treat the Sync-OERStructure*
            family as a fixed cohort of seven: AccessPackage, AccessReview, AdministrativeUnit,
            Catalog, Group, RoleAssignment and RoleManagementPolicy. Fix round 2 added two non-Sync
            document consumers; fix round 3 added the remaining three Resolve-OER*Change helpers that
            take a -Declared document node, which round 2 had left out while claiming to cover every
            such file; sprint 6 added Get-OEROmittedPruneCollection.ps1, which walks the whole document
            for Invoke-OERStructure's -Prune warning. Sprint 6 step 2 added
            Resolve-OERDeclaredApprover.ps1, which reads a declared approvers block before the
            approval diffs. Asserting the NAMES rather than the count says
            which file left the scan when one does -- a plain count told you only that "7" became "6", which is precisely the kind
            of silent narrowing this gate exists to stop. A file that appears means a new handler or
            document consumer was added and needs a deliberate look at whether it reads
            PSObject.Properties.Name directly, not a pass-through.
        #>
        $Expected = @(
            'Get-OEROmittedPruneCollection.ps1'
            'Read-OERStructureDocument.ps1'
            'Resolve-OERAccessReviewChange.ps1'
            'Resolve-OERDeclaredApprover.ps1'
            'Resolve-OERGroupEligibilityChange.ps1'
            'Resolve-OERGroupPimPolicyChange.ps1'
            'Resolve-OERRoleManagementPolicyChange.ps1'
            'Sync-OERStructureAccessPackage.ps1'
            'Sync-OERStructureAccessReview.ps1'
            'Sync-OERStructureAdministrativeUnit.ps1'
            'Sync-OERStructureCatalog.ps1'
            'Sync-OERStructureGroup.ps1'
            'Sync-OERStructureRoleAssignment.ps1'
            'Sync-OERStructureRoleManagementPolicy.ps1'
        )
        # The NATIVE RelativePath, never a '\'-normalized copy: '\' is not a directory separator on
        # Linux or macOS, where GetFileName of a normalized path returns the whole path.
        $Actual = @($script:declaredValueHandlerFiles |
                ForEach-Object { [System.IO.Path]::GetFileName($_.RelativePath) } |
                Sort-Object)

        ($Actual -join ', ') | Should -BeExactly ($Expected -join ', ') -Because (
            'this gate scans exactly these fourteen files: the seven source/Private/Sync-OERStructure*.ps1 handlers plus the seven document consumers named in the SCOPE note (Read-OERStructureDocument.ps1, Get-OEROmittedPruneCollection.ps1, Resolve-OERDeclaredApprover.ps1 and the four Resolve-OER*Change helpers that take a -Declared document node); a name missing here means the selection stopped matching that file and silently narrowed the gate, and a name added means a new apply-document walker needs a deliberate look')
    }

    It 'scans a meaningful number of PSObject.Properties.Name member-access chains module-wide' {
        <#
            Without this, a predicate typo in Get-OERPropertiesNameChainRoot -- the wrong AST node
            type in the FindAll predicate, or a member name that never matches -- would make the
            violation assertion below pass VACUOUSLY. The handler-scoped count alone cannot serve as
            that proof: after Tasks 2/3/5/6 it is exactly 1, and a broken scan reporting 0 looks almost
            identical. This instead asserts the SAME chain predicate still finds a substantial number
            of matches across the whole tree, where the true count (25, re-measured on fix round 3
            with this gate's own counter -- it was 27 until round 2 migrated two chains away) is
            large enough that "the predicate stopped matching anything" and "the tree only ever had a
            handful" cannot be confused with each other. Keep this figure in step with the CURRENT
            MEASUREMENTS block above; nothing reddens when it goes stale, which is how it last did.
        #>
        $script:declaredValuePropsNameChainCount | Should -BeGreaterThan 20 -Because (
            'source/**/*.ps1 carried 25 PSObject.Properties.Name member-access chains (AST-derived, not a text count) when this figure was last re-measured; a count that drops near zero means the chain-matching predicate stopped firing, not that the tree stopped reading PSObject.Properties.Name')
    }

    It 'calls Test-OERDeclaredProperty or Test-OERDeclaredNull instead of reading PSObject.Properties.Name directly in an apply-document-walking file' {
        $script:declaredValueViolations -join "`n" | Should -BeNullOrEmpty -Because @'
CLAUDE.md ## Code Style: Test-OERDeclaredProperty and Test-OERDeclaredNull are the single owners of
the apply engine's declared-value rule (docs/development/rationale.md#declared-property). A property
on an apply-document node is declared only when it is present AND not null; one of the fourteen scanned
apply-document walkers (the seven Sync-OERStructure* handlers and the seven document consumers named in
the SCOPE note) that instead reads a node's ".PSObject.Properties.Name" directly
-- whether compared inline with -contains, assigned to a variable for a later comparison, or consumed
any other way -- and pairs
that with a separate null check treats an explicit JSON null the same as a declared value -- coerced
downstream ([string]$null is '', [bool]$null is $false, [int]$null is 0) into silently overwriting
live tenant state on every apply run. Issue #56 found this shape three times over; #67, #68, #69 and
#70 each found it rebuilt in a new handler after the previous fix landed, and an intermediate
variable was enough to hide the first version of this very gate. Migrate the site to
Test-OERDeclaredProperty (or Test-OERDeclaredNull for the explicit-null-only case), or -- if the read
genuinely inspects something other than an apply-document node -- add it to
$script:declaredValueAllowlist with a written reason. Do not delete this assertion to get past it.
'@
    }
}

Describe 'Az context hygiene' -Tags 'SourceHygiene' {

    It 'parses a meaningful number of source files and command nodes' {
        <#
            Non-vacuity guard, the same shape dochygiene.tests.ps1 and the Cmdlet reference gate
            above use. A scan that parsed nothing, or that walked no command nodes, would report no
            violations and pass -- green while proving nothing at all. These thresholds sit just
            under the values measured on 2026-09-21 (210 files parsed, 2,919 CommandAst nodes).
        #>
        $script:azContextParseFailures | Should -BeNullOrEmpty -Because (
            'a source file that no longer parses silently drops out of this scan; fix the file rather than letting the gate measure less than the tree')
        $script:azContextParsedFileCount | Should -BeGreaterThan 195 -Because (
            'source/ held 210 parseable .ps1 files when this gate was written; below 195 the scan has lost a directory, not shrunk')
        $script:azContextCommandAstCount | Should -BeGreaterThan 2700 -Because (
            'source/**/*.ps1 carried 2919 CommandAst nodes when this gate was written; below 2700 the AST walk has broken, not found less code')
    }

    It 'still recognises the Az command shape it is written to detect' {
        <#
            The sharper half of the non-vacuity guard, and the one specific to THIS gate. The two
            assertions above prove files were parsed and commands were walked; neither would notice
            if the '-Az' matcher itself stopped matching. A broken matcher yields zero violations
            AND zero recognised Az calls, which is indistinguishable from a clean tree unless the
            positive count is asserted too. Measured on 2026-09-21 after Disconnect-OER stopped
            calling Disconnect-AzAccount: 4 calls -- Get-AzToken twice and the module's own
            internal Invoke-AzTokenCall twice, all four in Initialize-OERAuth.ps1.
        #>
        $script:azContextAzCallCount | Should -BeGreaterThan 0 -Because (
            'the scan must be able to SEE an Az-shaped command name at all; zero recognised calls means the matcher is broken, not that the module stopped calling AzAuth')
    }

    It 'never calls an Az cmdlet that could establish an Az context' {
        $script:azContextViolations -join "`n" | Should -BeNullOrEmpty -Because @'
Omnicit.EntraRBAC acquires an ARM bearer token through AzAuth and sends it itself from
Invoke-OERArmRequest. It must never call Connect-AzAccount, Set-AzContext or any other Az cmdlet
that establishes or mutates an Az PowerShell context: Az.Accounts cannot reliably reuse an
externally acquired token (docs/development/rationale.md#arm-transport), the module is not
listed as depending on any Az module, and Connect-OER's help promises a caller that -IncludeARM
creates no Az context. That promise, and the removal of Az.Resources from the manifest, both rest
on this property.

This is the direct proof of it. Do NOT satisfy this gate by adding the offending command to
$script:azContextAllowedCommands, and do not reintroduce a per-file exemption -- the allowlist
covers AzAuth's token surface and the module's own internal helper, and nothing else in this
module calls an Az cmdlet at all. A new Az call is a design change that needs a decision recorded
in docs/development/rationale.md, a manifest dependency, and new help text, not an entry here.
'@
    }
}
