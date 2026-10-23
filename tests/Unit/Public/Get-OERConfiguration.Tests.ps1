BeforeAll {
    $script:moduleName = 'Omnicit.EntraRBAC'
    Get-Module $script:moduleName | Remove-Module -Force -ErrorAction SilentlyContinue
    Import-Module $script:moduleName -Force -ErrorAction Stop
    . "$PSScriptRoot/../TestHelpers/OERTransportTripwire.ps1"
    Install-OERTransportTripwire
}

AfterAll {
    try { Assert-OERTransportTripwire } finally { Uninstall-OERTransportTripwire }
}

Describe 'Get-OERConfiguration' {
    It 'returns nothing when no profiles exist' {
        $Base = Join-Path $TestDrive 'EmptyProfiles'
        (Get-OERConfiguration -BasePath $Base) | Should -BeNullOrEmpty
    }

    It 'returns all profiles when no alias is given' {
        $Base = Join-Path $TestDrive 'AllProfiles'
        New-OERConfiguration -TenantAlias a -TenantId '1' -BasePath $Base | Out-Null
        New-OERConfiguration -TenantAlias b -TenantId '2' -BasePath $Base | Out-Null
        (Get-OERConfiguration -BasePath $Base) | Should -HaveCount 2
    }

    It 'skips a malformed profile with a non-terminating error and still returns the good ones (audit PR7 M6)' {
        $Base = Join-Path $TestDrive 'MixedProfiles'
        New-OERConfiguration -TenantAlias good -TenantId '1' -BasePath $Base | Out-Null
        # Naming is a hand-edited array instead of a hashtable, which fails
        # ConvertTo-OERTenantConfiguration's [hashtable]$Naming parameter binding.
        @"
@{
    TenantId = '2'
    Naming   = @('not', 'a', 'hashtable')
}
"@ | Set-Content -Path (Join-Path $Base 'bad.psd1') -Encoding utf8

        $Results = Get-OERConfiguration -BasePath $Base -ErrorVariable Err -ErrorAction SilentlyContinue
        @($Results).Count | Should -Be 1
        $Results.TenantAlias | Should -Be 'good'

        # -ErrorVariable puts the raw (untagged) record before any WriteError-tagged one, so filter
        # rather than index into $Err[0].
        $TaggedErrors = $Err | Where-Object { $_.FullyQualifiedErrorId -match 'TenantProfileMalformed' }
        @($TaggedErrors).Count | Should -Be 1
        $TaggedErrors[0].TargetObject | Should -Match 'bad\.psd1'
    }

    It 'rejects a traversal alias and returns nothing' {
        $Base = Join-Path $TestDrive 'Profiles'
        $Results = Get-OERConfiguration -TenantAlias '../../../evil' -BasePath $Base `
            -ErrorAction SilentlyContinue -ErrorVariable Err
        $Results | Should -BeNullOrEmpty
        # -ErrorVariable collects the raw record first; find the tagged one by ErrorId.
        @($Err).FullyQualifiedErrorId -join ';' | Should -Match 'InvalidTenantAlias'
    }

    It 'warns about, but still returns, a pre-existing profile whose basename is not a valid alias' {
        $Base = Join-Path $TestDrive 'LegacyProfiles'
        New-Item -ItemType Directory -Path $Base -Force | Out-Null
        # A profile written before Test-OERTenantAlias existed can have a basename outside the
        # letters/digits/dot/underscore/hyphen set (here, a space) -- simulate that directly on disk,
        # since New-OERConfiguration itself would now reject such an alias.
        @"
@{
    TenantId = '3'
}
"@ | Set-Content -Path (Join-Path $Base 'legacy alias.psd1') -Encoding utf8

        $Results = Get-OERConfiguration -BasePath $Base -WarningVariable Warn -WarningAction SilentlyContinue
        $Results.TenantAlias | Should -Be 'legacy alias'
        @($Warn | Where-Object { $_ -match 'legacy alias\.psd1' }) | Should -Not -BeNullOrEmpty
    }

    It 'does not warn when every profile basename is a valid alias' {
        $Base = Join-Path $TestDrive 'ValidProfiles'
        New-OERConfiguration -TenantAlias good -TenantId '1' -BasePath $Base | Out-Null
        $Results = Get-OERConfiguration -BasePath $Base -WarningVariable Warn -WarningAction SilentlyContinue
        $Results.TenantAlias | Should -Be 'good'
        @($Warn) | Should -BeNullOrEmpty
    }

    It 'converts a ProfilePathEscapesBase failure from Resolve-OERProfilePath into a non-terminating error' {
        # Test-OERTenantAlias already forbids every alias this cmdlet's own check would let through, so
        # a real caller can never reach the containment guard inside Resolve-OERProfilePath. Bypass the
        # alias check the same way Resolve-OERProfilePath.Tests.ps1 does, to prove the public cmdlet
        # wraps that guard's throw instead of letting it terminate the pipeline.
        Mock -ModuleName Omnicit.EntraRBAC Test-OERTenantAlias { $true }
        $Base = Join-Path $TestDrive 'ProfilesEscape'
        New-Item -ItemType Directory -Path $Base -Force | Out-Null
        # A try/catch (unlike a scriptblock piped into Should -Not -Throw) does not introduce a new
        # variable scope, so -ErrorVariable Err stays visible below for the FullyQualifiedErrorId check.
        $Threw = $false
        try {
            Get-OERConfiguration -TenantAlias '..\..\evil' -BasePath $Base `
                -ErrorAction SilentlyContinue -ErrorVariable Err | Out-Null
        } catch {
            $Threw = $true
        }
        $Threw | Should -BeFalse
        @($Err).FullyQualifiedErrorId -join ';' | Should -Match 'ProfilePathEscapesBase'
    }

    It 'reports TenantProfileMalformed for an unparsable profile instead of an empty TenantId object' {
        # Import-PowerShellDataFile fails NON-terminatingly on an unparsable file and returns $null.
        # Outside a guard that produced a normal-looking TenantConfiguration with an EMPTY TenantId,
        # which Connect-OER treats as a successful alias lookup -- so the sign-in silently fell back
        # to the operator's home tenant instead of the profile's tenant.
        $Base = Join-Path $TestDrive 'UnparsableProfiles'
        New-Item -ItemType Directory -Path $Base -Force | Out-Null
        Set-Content -Path (Join-Path $Base 'broken.psd1') -Value "@{ Tenant Id = 'x' }" -Encoding utf8

        $Result = Get-OERConfiguration -BasePath $Base -ErrorAction SilentlyContinue -ErrorVariable Err
        # The message half matters: it pins the PARSE guard specifically. The separate
        # no-TenantId guard below would otherwise also catch a null $Data and report a different
        # cause, so a bare ErrorId assertion here would survive removing the try/catch.
        @($Err | Where-Object {
                $_.FullyQualifiedErrorId -eq 'TenantProfileMalformed,Get-OERConfiguration' -and
                $_.Exception.Message -match 'could not be parsed'
            }).Count | Should -Be 1
        # No assertion on the raw Import-PowerShellDataFile record: PowerShell records a thrown
        # ErrorRecord into -ErrorVariable at every call boundary it crosses, so it is present with
        # -ErrorAction Stop too and proves nothing either way.
        @($Result | Where-Object { -not $_.TenantId }).Count | Should -Be 0
    }

    It 'scrubs the error record when the profile read fails' {
        # NOT a bearer path. Every *-OERConfiguration catch guards local file IO
        # (Resolve-OERProfilePath / Import-PowerShellDataFile), so no HttpRequestMessage and no
        # Authorization: Bearer header can ever reach it. The Remove-OERErrorRecord call is still
        # required by CLAUDE.md SECURITY rule 6 (it is unconditional across the module), and this It
        # exists for rule conformance and regression cover, not as a security fix.
        # This drives the Import-PowerShellDataFile catch -- the same one the malformed-profile Its
        # above cover -- by putting an unparsable PSD1 under a temp -BasePath rather than by
        # mocking any transport.
        Mock -ModuleName Omnicit.EntraRBAC Remove-OERErrorRecord { }
        $Base = Join-Path $TestDrive 'ScrubUnparsable'
        New-Item -ItemType Directory -Path $Base -Force | Out-Null
        Set-Content -Path (Join-Path $Base 'broken.psd1') -Value "@{ Tenant Id = 'x' }" -Encoding utf8

        $null = Get-OERConfiguration -BasePath $Base -ErrorAction SilentlyContinue
        Should -Invoke -ModuleName Omnicit.EntraRBAC Remove-OERErrorRecord -Times 1 -Exactly
    }

    It 'continues enumerating after one unparsable profile' {
        $Base = Join-Path $TestDrive 'UnparsableMixed'
        New-Item -ItemType Directory -Path $Base -Force | Out-Null
        # 'a-broken' sorts before 'z-good' so the good profile is only reached if the loop continues.
        Set-Content -Path (Join-Path $Base 'a-broken.psd1') -Value "@{ Tenant Id = 'x' }" -Encoding utf8
        New-OERConfiguration -TenantAlias 'z-good' -TenantId '7' -BasePath $Base | Out-Null

        $Result = @(Get-OERConfiguration -BasePath $Base -ErrorAction SilentlyContinue -ErrorVariable Err)
        $Result.Count | Should -Be 1
        $Result[0].TenantAlias | Should -Be 'z-good'
        $Result[0].TenantId | Should -Be '7'
        @($Err | Where-Object { $_.FullyQualifiedErrorId -eq 'TenantProfileMalformed,Get-OERConfiguration' }).Count |
            Should -Be 1
    }

    It 'reports TenantProfileMalformed for a profile that parses but carries no TenantId' {
        # This file parses cleanly, so the try/catch above never sees it -- only the emptiness guard
        # does. TenantId is the one required key in the profile schema, and an object emitted without
        # it is the exact shape Connect-OER turns into a home-tenant sign-in.
        $Base = Join-Path $TestDrive 'NoTenantIdProfile'
        New-Item -ItemType Directory -Path $Base -Force | Out-Null
        Set-Content -Path (Join-Path $Base 'blank.psd1') -Value "@{ Naming = @{ Group = 'x' } }" -Encoding utf8

        $Result = Get-OERConfiguration -BasePath $Base -ErrorAction SilentlyContinue -ErrorVariable Err
        @($Err | Where-Object { $_.FullyQualifiedErrorId -eq 'TenantProfileMalformed,Get-OERConfiguration' }).Count |
            Should -Be 1
        @($Result).Count | Should -Be 0
    }

    It 'still reads and emits a profile whose stored TenantId is white space only, as it did before BL-96' {
        # Sprint 10 step 3 (BL-96): New-/Set-OERConfiguration refuse a white-space -TenantId at parameter
        # binding, but a profile already on disk with one is read exactly as before -- the refusal is on
        # the write path, and this read path is deliberately unchanged. The file is seeded directly, since
        # the write cmdlets can no longer produce it.
        $Base = Join-Path $TestDrive 'BlankTenantIdProfiles'
        New-Item -ItemType Directory -Path $Base -Force | Out-Null
        Set-Content -Path (Join-Path $Base 'blank-tenant.psd1') -Value "@{ TenantId = '   ' }" -Encoding utf8

        $Single = @(Get-OERConfiguration -TenantAlias 'blank-tenant' -BasePath $Base -ErrorAction SilentlyContinue -ErrorVariable Err)
        @($Err).Count | Should -Be 0
        $Single.Count | Should -Be 1
        $Single[0].TenantAlias | Should -BeExactly 'blank-tenant'
        $Single[0].TenantId | Should -BeExactly '   '

        $All = @(Get-OERConfiguration -BasePath $Base -ErrorAction SilentlyContinue -ErrorVariable ErrAll)
        @($ErrAll).Count | Should -Be 0
        $All.Count | Should -Be 1
        $All[0].TenantId | Should -BeExactly '   '
    }

    # -------------------------------------------------------------------------------------------
    # Sovereign clouds (Sprint 1.5, issue #81, Task 5): the Environment key on a Tenant Profile.
    # -------------------------------------------------------------------------------------------
    Context 'Environment' {
        It 'surfaces a valid stored Environment value' {
            $Base = Join-Path $TestDrive 'EnvGood'
            New-OERConfiguration -TenantAlias usgov -TenantId 'tid-usgov' -Environment USGov -BasePath $Base | Out-Null
            (Get-OERConfiguration -TenantAlias usgov -BasePath $Base).Environment | Should -Be 'USGov'
        }

        It 'returns Environment absent (null), not Global, for a profile that never declared one' {
            # The absence itself is information: only Connect-OER turns an absent Environment into
            # 'Global'. A silent 'Global' emitted here would make every reader of this object unable
            # to tell "no cloud was ever chosen" apart from "Global was chosen".
            $Base = Join-Path $TestDrive 'EnvAbsent'
            New-OERConfiguration -TenantAlias contoso -TenantId 'tid-contoso' -BasePath $Base | Out-Null
            $Cfg = Get-OERConfiguration -TenantAlias contoso -BasePath $Base
            $Cfg.Environment | Should -BeNullOrEmpty
            $Cfg.Environment | Should -Not -Be 'Global'
        }

        It 'reports TenantProfileMalformed and skips a profile whose stored Environment is not one of the four supported clouds' {
            # A hand-edited-file case, not a caller mistake: New-/Set-OERConfiguration can never write
            # 'Mars' since their own -Environment carries the same ValidateSet.
            $Base = Join-Path $TestDrive 'EnvInvalid'
            New-Item -ItemType Directory -Path $Base -Force | Out-Null
            Set-Content -Path (Join-Path $Base 'bad-cloud.psd1') -Value "@{ TenantId = 'x'; Environment = 'Mars' }" -Encoding utf8

            $Result = Get-OERConfiguration -BasePath $Base -ErrorAction SilentlyContinue -ErrorVariable Err
            @($Result).Count | Should -Be 0
            @($Err | Where-Object {
                    $_.FullyQualifiedErrorId -eq 'TenantProfileMalformed,Get-OERConfiguration' -and
                    $_.Exception.Message -match 'unsupported Environment'
                }).Count | Should -Be 1
        }

        It 'never returns an invalid stored Environment as Global -- the file is skipped, not silently downgraded' {
            $Base = Join-Path $TestDrive 'EnvInvalidNoFallback'
            New-Item -ItemType Directory -Path $Base -Force | Out-Null
            Set-Content -Path (Join-Path $Base 'bad-cloud.psd1') -Value "@{ TenantId = 'x'; Environment = 'Mars' }" -Encoding utf8

            $Result = @(Get-OERConfiguration -BasePath $Base -ErrorAction SilentlyContinue)
            @($Result | Where-Object { $_.Environment -eq 'Global' }).Count | Should -Be 0
            $Result | Should -BeNullOrEmpty
        }

        It 'continues enumerating after a profile with an invalid Environment' {
            # 'a-bad-cloud' sorts before 'z-good' so the good profile is only reached if the loop
            # continues, matching the existing unparsable-profile continuation test above.
            $Base = Join-Path $TestDrive 'EnvInvalidMixed'
            New-Item -ItemType Directory -Path $Base -Force | Out-Null
            Set-Content -Path (Join-Path $Base 'a-bad-cloud.psd1') -Value "@{ TenantId = 'x'; Environment = 'Mars' }" -Encoding utf8
            New-OERConfiguration -TenantAlias 'z-good' -TenantId '7' -BasePath $Base | Out-Null

            $Result = @(Get-OERConfiguration -BasePath $Base -ErrorAction SilentlyContinue)
            $Result.Count | Should -Be 1
            $Result[0].TenantAlias | Should -Be 'z-good'
        }
    }

    It 'resolves its default base path when USERPROFILE is unset' {
        # USERPROFILE is a Windows-only variable; the module declares CompatiblePSEditions Core and
        # CI tests Linux and macOS, where binding the -BasePath default threw before it ran.
        # That default is the REAL profile directory (GetFolderPath ignores USERPROFILE on Windows),
        # so the body's first file-system call is intercepted: the default is still bound and shown
        # to reach the body, and no real directory is read
        # (docs/development/rationale.md#bearer-scrub-tests).
        Mock -ModuleName $script:moduleName Test-Path { $false }
        $Saved = $env:USERPROFILE
        try {
            Remove-Item Env:\USERPROFILE -ErrorAction SilentlyContinue
            { Get-OERConfiguration -TenantAlias 'no-such-alias' -ErrorAction Stop } | Should -Not -Throw
        } finally {
            if ($null -ne $Saved) { $env:USERPROFILE = $Saved }
        }
        Should -Invoke -ModuleName $script:moduleName Test-Path -Exactly -Times 1 -ParameterFilter {
            $Path -like '*Omnicit.EntraRBAC*Profiles'
        }
    }

    It 'reads back a profile written with <Label> in every position and lists it without an Environment (BL-113)' -ForEach @(
        @{ Label = 'U+0027'; Code = 0x27 }
        @{ Label = 'U+2018'; Code = 0x2018 }
        @{ Label = 'U+2019'; Code = 0x2019 }
        @{ Label = 'U+201A'; Code = 0x201A }
        @{ Label = 'U+201B'; Code = 0x201B }
    ) {
        # The file is written by the module's own writer into $TestDrive (never the real profile folder);
        # the characters are built from code points so this test file stays ASCII.
        $Q = [string][char]$Code
        $Inject = "x${Q}; Environment = ${Q}China"
        $Base = Join-Path $TestDrive "QuoteGet$Code"
        $Path = Join-Path $Base 'q.psd1'
        InModuleScope $script:moduleName -Parameters @{ Path = $Path; Inject = $Inject; Q = $Q } {
            param($Path, $Inject, $Q)
            Export-OERConfiguration -Path $Path -Configuration @{
                TenantId = $Inject
                Naming   = @{ "Key${Q}One" = $Inject }
                Defaults = @{ Scalar = $Inject; Items = @("a${Q}b", $Inject) }
            }
        }
        $All = @(Get-OERConfiguration -BasePath $Base -ErrorAction Stop)
        $All | Should -HaveCount 1
        $All[0].Environment | Should -BeNullOrEmpty
        $All[0].TenantId -ceq $Inject | Should -BeTrue
        $All[0].Naming["Key${Q}One"] -ceq $Inject | Should -BeTrue
        $All[0].Defaults.Scalar -ceq $Inject | Should -BeTrue
        @($All[0].Defaults.Items)[0] -ceq "a${Q}b" | Should -BeTrue
        @($All[0].Defaults.Items)[1] -ceq $Inject | Should -BeTrue
    }
}

Describe 'Get-OERConfiguration: the repair examples in TenantProfileMalformed messages (BL-113)' {
    BeforeAll {
        # BL-113: a command shown in a message must parse as typed and give the value back. Zero parse
        # errors is not enough on its own -- an unbalanced string can parse into the wrong tokens -- so
        # the argument must also come back, as a string constant, exactly as the value was typed.
        function Get-BL113Segment ([string]$Message, [string]$After, [string]$Before) {
            $Start = $Message.IndexOf($After, [System.StringComparison]::Ordinal)
            $Start | Should -BeGreaterOrEqual 0 -Because "the message holds '$After'"
            $Start += $After.Length
            $End = $Message.IndexOf($Before, $Start, [System.StringComparison]::Ordinal)
            $End | Should -BeGreaterThan $Start -Because "the message holds '$Before' after '$After'"
            $Message.Substring($Start, $End - $Start)
        }
        function Read-BL113Argument ([string]$Text, [string]$Command, [string]$Parameter) {
            $ParseErrors = $null
            $Ast = [System.Management.Automation.Language.Parser]::ParseInput($Text, [ref]$null, [ref]$ParseErrors)
            $Found = $Ast.Find({
                    param($Node)
                    $Node -is [System.Management.Automation.Language.CommandAst] -and $Node.GetCommandName() -eq $Command
                }, $true)
            $IsConstant = $false
            $Value = $null
            if ($Found) {
                $Elements = @($Found.CommandElements)
                for ($I = 0; $I -lt $Elements.Count - 1; $I++) {
                    if ($Elements[$I] -is [System.Management.Automation.Language.CommandParameterAst] -and $Elements[$I].ParameterName -eq $Parameter) {
                        $IsConstant = $Elements[$I + 1] -is [System.Management.Automation.Language.StringConstantExpressionAst]
                        if ($IsConstant) { $Value = $Elements[$I + 1].Value }
                    }
                }
            }
            [PSCustomObject]@{ ParseErrorCount = @($ParseErrors).Count; Found = [bool]$Found; IsConstant = $IsConstant; Value = $Value }
        }
        # The nested form: the command sits inside ONE single-quoted literal of the message. Read that
        # literal first (one literal and the end of the input), then the command it holds, up to $CutAt.
        function Read-BL113NestedArgument ([string]$Literal, [string]$CutAt, [string]$Command, [string]$Parameter) {
            $Tokens = $null
            $ParseErrors = $null
            $null = [System.Management.Automation.Language.Parser]::ParseInput($Literal, [ref]$Tokens, [ref]$ParseErrors)
            @($ParseErrors).Count | Should -Be 0 -Because "the literal in the message ($Literal) parses"
            @($Tokens).Count | Should -Be 2 -Because "the text in the message ($Literal) is one string literal"
            $Tokens[0].Kind | Should -Be ([System.Management.Automation.Language.TokenKind]::StringLiteral)
            $Inner = [string]$Tokens[0].Value
            if ($CutAt -and $Inner.Contains($CutAt)) { $Inner = $Inner.Substring(0, $Inner.IndexOf($CutAt, [System.StringComparison]::Ordinal)) }
            Read-BL113Argument -Text $Inner -Command $Command -Parameter $Parameter
        }
    }

    It 'shows the <Case> repair example so it parses and gives the alias back for a profile named with <Label>' -ForEach @(
        @{ Case = 'TenantId'; Content = '@{ Naming = @{} }'; Cut = ' -TenantId <id>'; Label = 'a straight apostrophe (U+0027)'; Alias = "o'brien"; Escaped = "o''brien" }
        @{ Case = 'TenantId'; Content = '@{ Naming = @{} }'; Cut = ' -TenantId <id>'; Label = 'a right single quotation mark (U+2019)'; Alias = ('o' + [char]0x2019 + 'brien'); Escaped = ('o' + [char]0x2019 + [char]0x2019 + 'brien') }
        @{ Case = 'Environment'; Content = "@{ TenantId = 'x'; Environment = 'Mars' }"; Cut = ' -Environment <value>'; Label = 'a straight apostrophe (U+0027)'; Alias = "o'brien"; Escaped = "o''brien" }
        @{ Case = 'Environment'; Content = "@{ TenantId = 'x'; Environment = 'Mars' }"; Cut = ' -Environment <value>'; Label = 'a right single quotation mark (U+2019)'; Alias = ('o' + [char]0x2019 + 'brien'); Escaped = ('o' + [char]0x2019 + [char]0x2019 + 'brien') }
    ) {
        # A profile written before Test-OERTenantAlias existed can carry such a basename; it is read
        # with a warning, and the repair command in the TenantProfileMalformed message names it.
        $Base = Join-Path $TestDrive "BL113-$Case-$([guid]::NewGuid().ToString('N'))"
        New-Item -ItemType Directory -Path $Base -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $Base "$Alias.psd1") -Value $Content -Encoding utf8

        $Err = $null
        $Result = Get-OERConfiguration -BasePath $Base -ErrorAction SilentlyContinue -ErrorVariable Err -WarningAction SilentlyContinue
        @($Result).Count | Should -Be 0
        $Own = @($Err | Where-Object { [string]$_.FullyQualifiedErrorId -ceq 'TenantProfileMalformed,Get-OERConfiguration' })
        $Own.Count | Should -Be 1
        $Example = Get-BL113Segment -Message $Own[0].Exception.Message -After 'Repair it with ' -Before $Cut
        $Example | Should -BeExactly "Set-OERConfiguration -TenantAlias '$Escaped'"
        $Read = Read-BL113Argument -Text $Example -Command 'Set-OERConfiguration' -Parameter 'TenantAlias'
        $Read.ParseErrorCount | Should -Be 0
        $Read.IsConstant | Should -BeTrue
        $Read.Value | Should -BeExactly $Alias
    }
}
