function Read-OERStructureDocument {
    <#
    .SYNOPSIS
    Parses an orchestration document from a file path or a JSON string into a normalized object.

    .DESCRIPTION
    Reads the Phase 5 orchestration JSON either from -Path (a file), -Json (a literal string), or
    -InputObject and converts it to a [PSCustomObject] with ConvertFrom-Json. -InputObject accepts
    three shapes: a document object (a PSCustomObject, such as the output of Get-OERInventory or an
    already-parsed document), which is serialized and re-parsed; a file path string; or a
    System.IO.FileInfo (for example piped from Get-ChildItem or Get-Item) -- the latter two are read
    from disk exactly like -Path. A System.IO.DirectoryInfo piped to -InputObject is an error, since
    there is no single document to read from a directory. Malformed JSON, a missing file, an empty
    document, and a document whose root is not a single JSON object all throw, so the public callers
    (Test-OERStructure and Invoke-OERStructure) can catch and surface a clean error before any
    validation or write. Exactly one of -Path, -Json, or -InputObject must be supplied.

    Before returning, every recognized enum value in the document is rewritten to the canonical
    spelling Get-OERStructureSchemaJson declares (as resolved by Resolve-OERStructureEnumCasing), so a
    hand-authored or LLM-authored casing variant never reaches an apply handler's Graph or ARM request
    body. A value that is not a member of its enum is left untouched so the validator can still report
    it.

    Pass -SkipEnumNormalization to skip that rewrite step entirely and return the document exactly as
    written. Test-OERStructure passes this switch so the offline validator sees the document's real
    casing and can warn that a non-canonical value will be rejected by a draft-07 validator outside the
    module, while Invoke-OERStructure never passes it, because the apply path always normalizes so the
    value that reaches a Graph or ARM request body is the canonical one.

    .PARAMETER Path
    The path to a JSON file to read.

    .PARAMETER Json
    A literal JSON string to parse.

    .PARAMETER InputObject
    A document object (a PSCustomObject, such as the output of Get-OERInventory) to serialize and
    parse, OR a file to read -- either a path string or a System.IO.FileInfo (for example piped from
    Get-ChildItem or Get-Item), read from disk exactly like -Path. A System.IO.DirectoryInfo is an
    error.

    .PARAMETER SkipEnumNormalization
    When set, skips the enum casing normalization step entirely and returns the parsed document
    exactly as written, without rewriting any enum value to its canonical spelling. Test-OERStructure
    passes this switch so it validates the document as the operator or LLM actually wrote it, including
    any non-canonical casing that Test-OERStructureSchema then reports as a Warning; Invoke-OERStructure
    never passes it, because the apply path always normalizes so the value that reaches a Graph or ARM
    request body is the canonical one.

    .EXAMPLE
    Read-OERStructureDocument -Path ./example-structure.json
    Returns the parsed document object.

    .EXAMPLE
    Read-OERStructureDocument -Json '{ "version": "1.0" }'
    Parses the inline JSON string into an object.

    .EXAMPLE
    Read-OERStructureDocument -InputObject (Get-OERInventory)
    Parses an inventory object into a normalized document.

    .EXAMPLE
    Read-OERStructureDocument -Path ./proposal.json -SkipEnumNormalization
    Parses the document without rewriting any enum value, preserving its casing exactly as written.
    #>
    [OutputType([PSCustomObject])]
    [CmdletBinding(DefaultParameterSetName = 'Path')]
    param(
        [Parameter(ParameterSetName = 'Path', Mandatory)][string]$Path,
        [Parameter(ParameterSetName = 'Json', Mandatory)][string]$Json,
        [Parameter(ParameterSetName = 'InputObject', Mandatory)][object]$InputObject,
        [Parameter()][switch]$SkipEnumNormalization
    )
    # -InputObject redirect: a caller can pipe a file path or a Get-ChildItem/Get-Item result into
    # -InputObject too (it is the only ValueFromPipeline candidate on Test-OERStructure and
    # Invoke-OERStructure, and [object] accepts anything by value), so a FileInfo or a path-like
    # string must reach the SAME file-reading code the Path parameter set uses, not be serialized
    # with ConvertTo-Json as if it were document data. This check runs BEFORE the Json/Path branch
    # selection below so both callers get identical treatment regardless of -SkipEnumNormalization.
    # A genuine PSCustomObject (e.g. Get-OERInventory output) is untouched: it falls through to the
    # existing serialize-then-parse path exactly as before.
    $EffectiveParameterSetName = $PSCmdlet.ParameterSetName
    $EffectivePath = $Path
    if ($PSCmdlet.ParameterSetName -eq 'InputObject') {
        if ($InputObject -is [System.IO.DirectoryInfo]) {
            throw "A directory ('$($InputObject.FullName)') was piped to Read-OERStructureDocument. Pipe a file (or its path) instead, or use -Path directly."
        }
        elseif ($InputObject -is [System.IO.FileInfo]) {
            $EffectiveParameterSetName = 'Path'
            $EffectivePath = $InputObject.FullName
        }
        elseif ($InputObject -is [string]) {
            $Trimmed = $InputObject.Trim()
            if ($Trimmed.Length -gt 0) {
                $LooksLikeJson = $Trimmed.StartsWith('{') -or $Trimmed.StartsWith('[')
                if (-not $LooksLikeJson) {
                    # Not JSON-shaped text: treat as a path unconditionally. If it does not exist, the
                    # Path branch below throws the clear "not found at path" error instead of the
                    # confusing "root must be a single JSON object" a serialized string would have hit.
                    # Use $Trimmed, not $InputObject: a leading/trailing-whitespace path (e.g. copy-pasted
                    # from a terminal) was classified as path-like above via $Trimmed, so it must be
                    # resolved via $Trimmed too, or it fails "not found" against the untrimmed string.
                    $EffectiveParameterSetName = 'Path'
                    $EffectivePath = $Trimmed
                }
                elseif (Test-Path -LiteralPath $InputObject -ErrorAction SilentlyContinue) {
                    # Rare: a JSON-shaped string that also happens to be an existing file path. The
                    # file on disk wins, matching how -Path itself behaves. Test-Path is checked against
                    # the untrimmed $InputObject (whitespace around JSON text is not path whitespace),
                    # but the resolved path itself still goes through $Trimmed for the same reason as above.
                    $EffectiveParameterSetName = 'Path'
                    $EffectivePath = $Trimmed
                }
            }
        }
    }
    if ($EffectiveParameterSetName -eq 'InputObject') {
        $Json = $InputObject | ConvertTo-Json -Depth 32
    }
    if ($EffectiveParameterSetName -eq 'Path') {
        if (-not (Test-Path -LiteralPath $EffectivePath -PathType Leaf)) {
            throw "Structure document not found at path '$EffectivePath'."
        }
        $Json = Get-Content -LiteralPath $EffectivePath -Raw
    }
    if ([string]::IsNullOrWhiteSpace($Json)) {
        throw 'The structure document is empty.'
    }
    try {
        $Doc = $Json | ConvertFrom-Json -Depth 32 -ErrorAction Stop
    } catch {
        Remove-OERErrorRecord -Record $PSItem
        throw "The structure document is not valid JSON: $($PSItem.Exception.Message)"
    }
    if ($Doc -is [System.Array] -or $null -eq $Doc -or $Doc -is [string] -or $Doc -is [ValueType]) {
        throw 'The structure document root must be a single JSON object.'
    }
    # --- Enum casing normalization -----------------------------------------------------------
    # Resolve-OERStructureEnumCasing owns the canonical spelling. Test-OERStructureSchema accepts any
    # casing (with a Warning), but everything downstream must carry the spelling schema.json declares:
    # the raw value survives into the Graph body the apply handlers build -- Sync-OERStructureGroup ->
    # Resolve-OERGroupEligibilityChange -> New-OERGroupEligibilityBody sends 'accessId = <as written>'.
    # Every parameter set above produced a freshly parsed object, so this never mutates a caller's
    # -InputObject, and property assignment is case-insensitive, so it cannot add a duplicate key.
    # -SkipEnumNormalization (Test-OERStructure's request) bypasses this whole block so the validator
    # sees the document exactly as written instead of the already-canonicalized result.
    if (-not $SkipEnumNormalization) {
        function Write-OEREnumValue {
            param([object]$Node, [string]$Key, [string]$EnumName)
            # Test-OERDeclaredProperty, never an inline PSObject.Properties.Name chain: $Node is an
            # apply-document node, so the declared-value rule governs it (CLAUDE.md ## Code Style;
            # docs/development/rationale.md#declared-property). The predicate folds all three of the
            # guards this line used to carry -- null node, absent key, explicit null value -- into
            # one call with identical behaviour: it is false for every one of them, and there is
            # nothing to canonicalize in any of the three cases.
            if (-not (Test-OERDeclaredProperty -Node $Node -Name $Key)) { return }
            $Current = $Node.$Key
            if ($Current -is [string]) {
                $Canonical = Resolve-OERStructureEnumCasing -EnumName $EnumName -Value $Current
                if ($null -ne $Canonical) { $Node.$Key = $Canonical }
                return
            }
            if ($Current -is [System.Collections.IEnumerable]) {
                $Node.$Key = @(foreach ($Entry in @($Current)) {
                        $Canonical = Resolve-OERStructureEnumCasing -EnumName $EnumName -Value ([string]$Entry)
                        if ($null -ne $Canonical) { $Canonical } else { $Entry }
                    })
            }
        }

        foreach ($Group in @($Doc.groups)) {
            if ($null -eq $Group) { continue }
            foreach ($Eligibility in @($Group.eligibility)) {
                Write-OEREnumValue -Node $Eligibility -Key 'accessType' -EnumName 'accessType'
            }
            # The pimPolicy block has a flat (member-only) back-compat form and a nested member/owner form.
            foreach ($Block in @($Group.pimPolicy, $Group.pimPolicy.member, $Group.pimPolicy.owner)) {
                Write-OEREnumValue -Node $Block -Key 'activationEnablement' -EnumName 'enablement'
                Write-OEREnumValue -Node $Block -Key 'activeEnablement' -EnumName 'enablement'
            }
        }
        foreach ($Unit in @($Doc.administrativeUnits)) {
            Write-OEREnumValue -Node $Unit -Key 'membershipRuleProcessingState' -EnumName 'membershipRuleProcessingState'
        }
        foreach ($Catalog in @($Doc.catalogs)) {
            if ($null -eq $Catalog) { continue }
            foreach ($Resource in @($Catalog.resources)) {
                Write-OEREnumValue -Node $Resource -Key 'type' -EnumName 'catalogResourceType'
            }
        }
        foreach ($Package in @($Doc.accessPackages)) {
            if ($null -eq $Package) { continue }
            foreach ($Policy in @($Package.assignmentPolicies)) {
                if ($null -eq $Policy) { continue }
                foreach ($Stage in @($Policy.approvalStages)) {
                    Write-OEREnumValue -Node $Stage -Key 'approverInfoVisibility' -EnumName 'approverInfoVisibility'
                }
            }
        }
        foreach ($Review in @($Doc.accessReviews)) {
            Write-OEREnumValue -Node $Review -Key 'recurrence' -EnumName 'accessReviewRecurrence'
            Write-OEREnumValue -Node $Review -Key 'defaultDecision' -EnumName 'accessReviewDefaultDecision'
        }
        foreach ($Assignment in @($Doc.roleAssignments)) {
            Write-OEREnumValue -Node $Assignment -Key 'principalType' -EnumName 'principalType'
        }
    }

    $Doc
}
