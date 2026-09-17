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

    if (-not (Get-Command -Name 'git' -CommandType Application -ErrorAction SilentlyContinue)) {
        $script:DocHygieneSkipReason =
        'git was not found on PATH, and this gate enumerates TRACKED files with git ls-files. It measured nothing -- install git, or run it inside a clone, then re-run.'
    }
    else {
        $TrackedPaths = @(& git -C $script:ProjectPath -c core.quotePath=false ls-files -- 'docs' 'specs' 'source' 'tests' 2>$null)

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
        #>
        [OutputType([string])]
        param (
            [Parameter(Mandatory = $true)]
            [AllowEmptyCollection()]
            [object[]]$File,

            [Parameter(Mandatory = $true)]
            [regex]$Pattern,

            [Parameter(Mandatory = $true)]
            [scriptblock]$IsAllowed
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

        $Hits = @(Get-DocHygieneMatchLocation -File $Prose -Pattern $GuidPattern -IsAllowed $IsPlaceholder)

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

        $Hits = @(Get-DocHygieneMatchLocation -File $Code -Pattern $GuidPattern -IsAllowed $IsNotIdentifierShaped)

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
}
