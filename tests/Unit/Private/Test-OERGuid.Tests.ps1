BeforeAll {
    Import-Module Omnicit.EntraRBAC -Force
    . "$PSScriptRoot/../TestHelpers/OERTransportTripwire.ps1"
    Install-OERTransportTripwire
}

AfterAll {
    try { Assert-OERTransportTripwire } finally { Uninstall-OERTransportTripwire }
}

Describe 'Test-OERGuid' {
    It 'returns true for a canonical hyphenated GUID' {
        InModuleScope Omnicit.EntraRBAC {
            Test-OERGuid -Value 'aaaa0000-0000-0000-0000-000000000001' | Should -BeTrue
        }
    }
    It 'returns false for a user principal name' {
        InModuleScope Omnicit.EntraRBAC {
            Test-OERGuid -Value 'anna@contoso.com' | Should -BeFalse
        }
    }
    It 'returns false for a display name' {
        InModuleScope Omnicit.EntraRBAC {
            Test-OERGuid -Value 'role_sec_admins' | Should -BeFalse
        }
    }
    It 'returns false for an empty string' {
        InModuleScope Omnicit.EntraRBAC {
            Test-OERGuid -Value '' | Should -BeFalse
        }
    }
    It 'returns false for a braced GUID' {
        InModuleScope Omnicit.EntraRBAC {
            Test-OERGuid -Value '{aaaa0000-0000-0000-0000-000000000001}' | Should -BeFalse
        }
    }
    It 'returns false for a dash-less 32-hex string' {
        InModuleScope Omnicit.EntraRBAC {
            Test-OERGuid -Value ('aaaa0000-0000-0000-0000-000000000001' -replace '-', '') | Should -BeFalse
        }
    }
}

Describe 'Test-OERGuid is the single GUID predicate' {
    It 'leaves no inline GUID regex in the shipped module outside Test-OERGuid itself' {
        # Regression guard for I-guid-regex-duplicated-not-testoerguid: a future helper that
        # re-implements the pattern instead of calling the predicate is caught here.
        # Walk up from tests/Unit/Private until the repo root (the folder holding source/) is
        # found, rather than counting Split-Path levels, so the test survives a move.
        $SourceRoot = $null
        $Probe = $PSScriptRoot
        while ($Probe -and -not $SourceRoot) {
            $Candidate = Join-Path $Probe 'source'
            if (Test-Path -Path $Candidate -PathType Container) { $SourceRoot = $Candidate }
            else { $Probe = Split-Path $Probe -Parent }
        }
        $SourceRoot | Should -Not -BeNullOrEmpty -Because 'the source tree must be locatable from the test file'
        # Matches both the full [0-9a-fA-F]{8}- spelling and a lower-case-only [0-9a-f]{8}- copy
        # (the optional (?:A-F)? group), since either literal class defines the same hex digits and
        # both are inline GUID regex duplication that should route through Test-OERGuid instead.
        #
        # Test-OERGuid.ps1 is exempt as the predicate itself. Get-OERStructureSchemaJson.ps1 is
        # exempt for exactly ONE match: its draft-07 JSON Schema carries the same canonical-GUID
        # pattern on the top-level tenantId property. That is not PowerShell code re-implementing
        # the predicate: it is the declarative twin of Test-OERGuid inside a document an external
        # validator (an LLM's tooling, Test-Json) reads, so it cannot call Test-OERGuid. The offline
        # validator's Rule 1b in Test-OERStructureSchema does call Test-OERGuid. The file is
        # reported when its match count is not exactly 1 -- the single tenantId pattern of the JSON
        # Schema -- so a second copy, or a removed pattern with a stale exemption, fails. The regex
        # is never loosened, and the next It holds the schema's pattern to Test-OERGuid's verdicts.
        # The match is case-insensitive, as the -match this replaced was.
        $GuidClass = '\[0-9a-f(?:A-F)?\]\{8\}-'
        $Offenders = Get-ChildItem -Path $SourceRoot -Recurse -Filter '*.ps1' |
            Where-Object { $_.Name -ne 'Test-OERGuid.ps1' } |
            Where-Object {
                $Count = [regex]::Matches((Get-Content -Raw -Path $_.FullName), $GuidClass, 'IgnoreCase').Count
                if ($_.Name -eq 'Get-OERStructureSchemaJson.ps1') { $Count -ne 1 } else { $Count -gt 0 }
            } |
            ForEach-Object { $_.Name }
        $Offenders -join ', ' | Should -BeNullOrEmpty
    }

    # Parity for the one exemption above. The schema's pattern is read from the schema the module
    # returns and compared with Test-OERGuid's verdict for each value, so a change to either side
    # that the other does not follow turns this red.
    #
    # A trailing line feed is deliberately NOT in the set: Test-OERGuid uses -match with a final
    # dollar anchor, which also accepts a single trailing line feed, while the ECMA-262 dollar of a
    # JSON Schema validator does not. That difference is a recorded finding, out of scope for the
    # branch that added the tenantId property.
    It 'keeps the tenantId schema pattern in step with Test-OERGuid: <Name>' -ForEach @(
        @{ Name = 'canonical lower-case GUID'; Value = 'aaaa0000-0000-0000-0000-000000000001' }
        @{ Name = 'canonical upper-case GUID'; Value = 'AAAA0000-0000-0000-0000-00000000000A' }
        @{ Name = 'braced GUID'; Value = '{aaaa0000-0000-0000-0000-000000000001}' }
        @{ Name = 'dash-less 32-hex string'; Value = 'aaaa0000000000000000000000000001' }
        @{ Name = 'GUID with a trailing space'; Value = 'aaaa0000-0000-0000-0000-000000000001 ' }
        @{ Name = 'empty string'; Value = '' }
        @{ Name = 'tenant domain'; Value = 'contoso.onmicrosoft.com' }
        @{ Name = 'GUID with the last group one character short'; Value = 'aaaa0000-0000-0000-0000-00000000001' }
    ) {
        InModuleScope Omnicit.EntraRBAC -Parameters @{ Name = $Name; Value = $Value } {
            $Pattern = (Get-OERStructureSchemaJson | ConvertFrom-Json).properties.tenantId.pattern
            $Pattern | Should -Not -BeNullOrEmpty -Because 'the schema declares a pattern for tenantId'
            $Expected = Test-OERGuid -Value $Value
            [regex]::IsMatch($Value, $Pattern) | Should -Be $Expected -Because "the schema pattern and Test-OERGuid must agree on the $Name"
        }
    }
}
