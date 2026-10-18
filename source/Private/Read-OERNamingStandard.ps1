function Read-OERNamingStandard {
    <#
    .SYNOPSIS
    Reads a naming standard file and returns it as a normalized, validated object.

    .DESCRIPTION
    Reads the JSON file Test-OERStructure -NamingStandard names, checks it against every rule of the
    schema Get-OERNamingStandardSchemaJson returns, and converts it to the object
    Test-OERNamingStandardName and Test-OERStructureSchema consume. The file is read with
    Get-Content -Raw, so a UTF-8 byte order mark is dropped like it is for a structure document.

    The returned object carries exactly these properties: Separator [string]; MaxLength [int], or
    $null when the file sets none; Sections [string[]]; IncludeSyncedGroups [bool] (false when the file
    omits it); Segments [object[]], one object per segment with Position [int] (1-based), Name,
    Values [string[]] or $null, Pattern [string] or $null, Regex [regex] or $null (the pattern compiled
    as \A(?:pattern)\z with RegexOptions.CultureInvariant, so it must match the whole text), Case
    [string] or $null and Optional [bool] (false when the file omits it); Exceptions [object[]], one
    object per entry with Pattern [string] and Regex [regex] (compiled the same way). A segment key
    the file omits is $null on the object (Values, Pattern, Regex, Case) or its default (Optional is false).

    Anything wrong with the file THROWS one exception; nothing is written to the error stream, a file
    that cannot be opened included: Get-Content runs with -ErrorAction Stop, so the non-terminating
    read error it would write is caught here instead. A path that is not a file throws "The naming
    standard was not found at path '<path>'.", a file that exists but cannot be read (locked, or no
    read permission) "The naming standard at '<path>' could not be read: <reason>", an empty or blank
    file "The naming standard at '<path>' is empty.", malformed JSON "The naming standard at '<path>' is
    not valid JSON: <parser message>", and a root that is not one JSON object "The naming standard at
    '<path>' must be a single JSON object.". A file that parses but breaks the standard throws "The
    naming standard at '<path>' is not valid: <problem> [<problem> ...]": every problem is collected
    first, so one throw names them all, each as one sentence that starts with its JSON path (an index
    counts from 0: segments[1].case, sections[2], exceptions[0]; an unknown key is its own path, such as
    seperator or segments[0].allowed) and says what was expected and what was found.

    The schema holds every rule but two, which draft-07 cannot express and this reader enforces:
    every segment pattern and every exceptions entry must compile as a .NET regular expression, and no
    values entry may contain the separator (it could never match a segment, since a name is split at the
    separator first). An integer is a JSON number with a zero fractional part, so maxLength 64.0 is
    read as 64 and 12.5 is refused. Key names and enum values are matched case-sensitively, as draft-07
    does. This function is pure apart from reading the file: no Graph or ARM request, no sign-in.

    .PARAMETER Path
    The path to the naming standard JSON file.

    .EXAMPLE
    Read-OERNamingStandard -Path ./naming-standard.json
    Returns the validated naming standard, or throws one message naming everything that is wrong.
    #>
    [OutputType([PSCustomObject])]
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Path
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "The naming standard was not found at path '$Path'."
    }
    try {
        # -ErrorAction Stop: for a file it cannot open (a lock, no read permission) Get-Content writes a
        # NON-terminating GetContentReaderIOError and returns nothing, which would reach the operator as a
        # second error and then read as an empty file.
        $Json = Get-Content -LiteralPath $Path -Raw -ErrorAction Stop
    } catch {
        Remove-OERErrorRecord -Record $PSItem
        throw "The naming standard at '$Path' could not be read: $($PSItem.Exception.Message)"
    }
    if ([string]::IsNullOrWhiteSpace($Json)) {
        throw "The naming standard at '$Path' is empty."
    }
    try {
        # -NoEnumerate keeps a root array one value, so '[ { } ]' is refused below instead of being
        # unwrapped to its only element and read as the standard.
        $Doc = $Json | ConvertFrom-Json -Depth 32 -NoEnumerate -ErrorAction Stop
    } catch {
        Remove-OERErrorRecord -Record $PSItem
        throw "The naming standard at '$Path' is not valid JSON: $($PSItem.Exception.Message)"
    }
    # [PSCustomObject] is the PSObject accelerator in a type test, which every value satisfies: the real
    # class is what tells a parsed JSON object from a string, a number or an array.
    if ($Doc -isnot [System.Management.Automation.PSCustomObject]) {
        throw "The naming standard at '$Path' must be a single JSON object."
    }

    $Problems = [System.Collections.Generic.List[string]]::new()
    $SectionNames = @('groups', 'administrativeUnits', 'catalogs', 'accessPackages', 'assignmentPolicies', 'accessReviews')
    $CaseNames = @('PascalCase', 'camelCase', 'UPPERCASE', 'lowercase')
    $RootKeys = @('$schema', 'version', 'description', 'separator', 'maxLength', 'sections', 'includeSyncedGroups', 'segments', 'exceptions')
    $SegmentKeys = @('name', 'description', 'values', 'pattern', 'case', 'optional')
    $RegexOptions = [System.Text.RegularExpressions.RegexOptions]::CultureInvariant

    # How a found value reads in a problem: strings quoted and cut at 40 characters, numbers and booleans
    # as JSON writes them, null, and a count-less 'an array' or 'an object'.
    function Format-Found {
        param([object]$Value)
        if ($null -eq $Value) { return 'null' }
        if ($Value -is [string]) {
            if ($Value.Length -gt 40) { return "'" + $Value.Substring(0, 40) + "...'" }
            return "'$Value'"
        }
        if ($Value -is [bool]) { if ($Value) { return 'true' } else { return 'false' } }
        if ($Value -is [ValueType]) { return ([System.IFormattable]$Value).ToString($null, [System.Globalization.CultureInfo]::InvariantCulture) }
        if ($Value -is [System.Array]) { return 'an array' }
        'an object'
    }

    # Exact text comparison. PowerShell's -ceq and -ccontains compare with the invariant culture, which
    # ignores some characters (a soft hyphen, a zero-width space), so a key or an enum value that carries
    # one would pass as the plain spelling; the schema (draft-07) compares exactly, and so does this.
    function Test-OrdinalMember {
        param([string[]]$List, [string]$Value)
        [System.Array]::IndexOf($List, $Value) -ge 0
    }

    function Add-Problem {
        param([string]$Text)
        $Problems.Add($Text)
    }

    # The keys of a JSON object by their exact (case-sensitive) names, in file order.
    function Get-KeyMap {
        param([PSCustomObject]$Node)
        $Map = [System.Collections.Generic.Dictionary[string, object]]::new([System.StringComparer]::Ordinal)
        foreach ($Property in $Node.PSObject.Properties) { $Map[$Property.Name] = $Property.Value }
        , $Map
    }

    function Add-UnknownKeyProblem {
        param([System.Collections.Generic.Dictionary[string, object]]$Map, [string[]]$Known, [string]$Prefix)
        foreach ($Key in $Map.Keys) {
            if (-not (Test-OrdinalMember -List $Known -Value $Key)) {
                Add-Problem "$Prefix$Key is not a known key; expected one of $($Known -join ', ')."
            }
        }
    }

    # A regular expression: it must compile on its own (an unbalanced pattern is reported as written,
    # never wrapped into something that happens to balance), then inside the whole-text anchors.
    function ConvertTo-AnchoredRegex {
        param([string]$Pattern, [string]$At)
        try {
            $null = [regex]::new($Pattern, $RegexOptions)
            return [regex]::new('\A(?:' + $Pattern + ')\z', $RegexOptions)
        } catch {
            # [regex]::new wraps the parser's ArgumentException; its own message names the offset.
            $Reason = if ($PSItem.Exception.InnerException) { $PSItem.Exception.InnerException.Message } else { $PSItem.Exception.Message }
            Add-Problem "$At must be a valid .NET regular expression; found $(Format-Found $Pattern), which does not compile: $Reason"
            return $null
        }
    }

    $Root = Get-KeyMap -Node $Doc
    Add-UnknownKeyProblem -Map $Root -Known $RootKeys -Prefix ''

    foreach ($Key in '$schema', 'description') {
        if ($Root.ContainsKey($Key) -and $Root[$Key] -isnot [string]) {
            Add-Problem "$Key must be a string; found $(Format-Found $Root[$Key])."
        }
    }

    # version
    if (-not $Root.ContainsKey('version')) {
        Add-Problem 'version is required but missing.'
    } elseif ($Root['version'] -isnot [string] -or -not [string]::Equals($Root['version'], '1.0', [System.StringComparison]::Ordinal)) {
        Add-Problem "version must be the string '1.0'; found $(Format-Found $Root['version'])."
    }

    # separator
    $Separator = $null
    if (-not $Root.ContainsKey('separator')) {
        Add-Problem 'separator is required but missing.'
    } elseif ($Root['separator'] -isnot [string] -or $Root['separator'].Length -eq 0) {
        Add-Problem "separator must be a non-empty string; found $(Format-Found $Root['separator'])."
    } else {
        $Separator = $Root['separator']
    }

    # maxLength: a JSON number with a zero fractional part from 1 to 256
    $MaxLength = $null
    if ($Root.ContainsKey('maxLength')) {
        $Raw = $Root['maxLength']
        $IsNumber = ($Raw -is [int]) -or ($Raw -is [long]) -or ($Raw -is [double]) -or ($Raw -is [decimal])
        $Number = if ($IsNumber) { [double]$Raw } else { [double]::NaN }
        if ($IsNumber -and $Number -eq [math]::Floor($Number) -and $Number -ge 1 -and $Number -le 256) {
            $MaxLength = [int]$Number
        } else {
            Add-Problem "maxLength must be an integer from 1 to 256; found $(Format-Found $Raw)."
        }
    }

    # sections
    $Sections = [System.Collections.Generic.List[string]]::new()
    if (-not $Root.ContainsKey('sections')) {
        Add-Problem 'sections is required but missing.'
    } elseif ($Root['sections'] -isnot [System.Array]) {
        Add-Problem "sections must be an array of section names; found $(Format-Found $Root['sections'])."
    } elseif ($Root['sections'].Count -eq 0) {
        Add-Problem 'sections must list at least one section; found an empty array.'
    } else {
        $SeenSection = [System.Collections.Generic.Dictionary[string, int]]::new([System.StringComparer]::Ordinal)
        for ($I = 0; $I -lt $Root['sections'].Count; $I++) {
            $Section = $Root['sections'][$I]
            if ($Section -isnot [string] -or -not (Test-OrdinalMember -List $SectionNames -Value $Section)) {
                Add-Problem "sections[$I] must be one of $($SectionNames -join ', '); found $(Format-Found $Section)."
            } elseif ($SeenSection.ContainsKey($Section)) {
                Add-Problem "sections[$I] repeats '$Section', which sections[$($SeenSection[$Section])] already lists; list each section once."
            } else {
                $SeenSection[$Section] = $I
                $Sections.Add($Section)
            }
        }
    }

    # includeSyncedGroups
    $IncludeSyncedGroups = $false
    if ($Root.ContainsKey('includeSyncedGroups')) {
        if ($Root['includeSyncedGroups'] -is [bool]) {
            $IncludeSyncedGroups = $Root['includeSyncedGroups']
        } else {
            Add-Problem "includeSyncedGroups must be true or false; found $(Format-Found $Root['includeSyncedGroups'])."
        }
    }

    # segments
    $Segments = [System.Collections.Generic.List[object]]::new()
    if (-not $Root.ContainsKey('segments')) {
        Add-Problem 'segments is required but missing.'
    } elseif ($Root['segments'] -isnot [System.Array]) {
        Add-Problem "segments must be an array of segment objects; found $(Format-Found $Root['segments'])."
    } elseif ($Root['segments'].Count -eq 0) {
        Add-Problem 'segments must list at least one segment; found an empty array.'
    } else {
        for ($I = 0; $I -lt $Root['segments'].Count; $I++) {
            $At = "segments[$I]"
            $Node = $Root['segments'][$I]
            if ($Node -isnot [System.Management.Automation.PSCustomObject]) {
                Add-Problem "$At must be an object; found $(Format-Found $Node)."
                continue
            }
            $Map = Get-KeyMap -Node $Node
            Add-UnknownKeyProblem -Map $Map -Known $SegmentKeys -Prefix "$At."

            $Name = $null
            if (-not $Map.ContainsKey('name')) {
                Add-Problem "$At.name is required but missing."
            } elseif ($Map['name'] -isnot [string] -or $Map['name'].Length -eq 0) {
                Add-Problem "$At.name must be a non-empty string; found $(Format-Found $Map['name'])."
            } else {
                $Name = $Map['name']
            }
            if ($Map.ContainsKey('description') -and $Map['description'] -isnot [string]) {
                Add-Problem "$At.description must be a string; found $(Format-Found $Map['description'])."
            }
            if ($Map.ContainsKey('values') -and $Map.ContainsKey('pattern')) {
                Add-Problem "$At must not declare both values and pattern; use one of them."
            }

            $Values = $null
            if ($Map.ContainsKey('values')) {
                if ($Map['values'] -isnot [System.Array]) {
                    Add-Problem "$At.values must be an array of strings; found $(Format-Found $Map['values'])."
                } elseif ($Map['values'].Count -eq 0) {
                    Add-Problem "$At.values must list at least one value; found an empty array."
                } else {
                    $SeenValue = [System.Collections.Generic.Dictionary[string, int]]::new([System.StringComparer]::Ordinal)
                    $ValueList = [System.Collections.Generic.List[string]]::new()
                    for ($J = 0; $J -lt $Map['values'].Count; $J++) {
                        $Value = $Map['values'][$J]
                        if ($Value -isnot [string] -or $Value.Length -eq 0) {
                            Add-Problem "$At.values[$J] must be a non-empty string; found $(Format-Found $Value)."
                        } elseif ($SeenValue.ContainsKey($Value)) {
                            Add-Problem "$At.values[$J] repeats '$Value', which $At.values[$($SeenValue[$Value])] already lists; list each value once."
                        } elseif ($null -ne $Separator -and $Value.Contains($Separator)) {
                            Add-Problem "$At.values[$J] is '$Value', which contains the separator '$Separator' and could never match a segment; remove the separator from it."
                        } else {
                            $SeenValue[$Value] = $J
                            $ValueList.Add($Value)
                        }
                    }
                    $Values = [string[]]$ValueList.ToArray()
                }
            }

            $Pattern = $null
            $Regex = $null
            if ($Map.ContainsKey('pattern')) {
                if ($Map['pattern'] -isnot [string] -or $Map['pattern'].Length -eq 0) {
                    Add-Problem "$At.pattern must be a non-empty string; found $(Format-Found $Map['pattern'])."
                } else {
                    $Pattern = $Map['pattern']
                    $Regex = ConvertTo-AnchoredRegex -Pattern $Pattern -At "$At.pattern"
                }
            }

            $Case = $null
            if ($Map.ContainsKey('case')) {
                if ($Map['case'] -isnot [string] -or -not (Test-OrdinalMember -List $CaseNames -Value $Map['case'])) {
                    Add-Problem "$At.case must be one of $($CaseNames -join ', '); found $(Format-Found $Map['case'])."
                } else {
                    $Case = $Map['case']
                }
            }

            $Optional = $false
            if ($Map.ContainsKey('optional')) {
                if ($Map['optional'] -is [bool]) {
                    $Optional = $Map['optional']
                } else {
                    Add-Problem "$At.optional must be true or false; found $(Format-Found $Map['optional'])."
                }
            }

            $Segments.Add([PSCustomObject]@{
                    Position = $I + 1
                    Name     = $Name
                    Values   = $Values
                    Pattern  = $Pattern
                    Regex    = $Regex
                    Case     = $Case
                    Optional = $Optional
                })
        }
    }

    # exceptions
    $Exceptions = [System.Collections.Generic.List[object]]::new()
    if ($Root.ContainsKey('exceptions')) {
        if ($Root['exceptions'] -isnot [System.Array]) {
            Add-Problem "exceptions must be an array of regular expressions; found $(Format-Found $Root['exceptions'])."
        } else {
            for ($I = 0; $I -lt $Root['exceptions'].Count; $I++) {
                $Entry = $Root['exceptions'][$I]
                if ($Entry -isnot [string] -or $Entry.Length -eq 0) {
                    Add-Problem "exceptions[$I] must be a non-empty string; found $(Format-Found $Entry)."
                    continue
                }
                $Exceptions.Add([PSCustomObject]@{
                        Pattern = $Entry
                        Regex   = ConvertTo-AnchoredRegex -Pattern $Entry -At "exceptions[$I]"
                    })
            }
        }
    }

    if ($Problems.Count -gt 0) {
        throw "The naming standard at '$Path' is not valid: $($Problems -join ' ')"
    }

    [PSCustomObject]@{
        Separator           = $Separator
        MaxLength           = $MaxLength
        Sections            = [string[]]$Sections.ToArray()
        IncludeSyncedGroups = $IncludeSyncedGroups
        Segments            = [object[]]$Segments.ToArray()
        Exceptions          = [object[]]$Exceptions.ToArray()
    }
}
