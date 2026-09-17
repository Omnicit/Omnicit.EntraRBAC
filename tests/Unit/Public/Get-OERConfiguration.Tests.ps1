BeforeAll {
    $script:moduleName = 'Omnicit.EntraRBAC'
    Get-Module $script:moduleName | Remove-Module -Force -ErrorAction SilentlyContinue
    Import-Module $script:moduleName -Force -ErrorAction Stop
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
        # to the operator's home tenant instead of the customer tenant.
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
        Should -Invoke -ModuleName Omnicit.EntraRBAC Remove-OERErrorRecord -Times 1
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
}
