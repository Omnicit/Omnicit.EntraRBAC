BeforeAll { Import-Module Omnicit.EntraRBAC -Force }

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
        $Offenders = Get-ChildItem -Path $SourceRoot -Recurse -Filter '*.ps1' |
            Where-Object { $_.Name -ne 'Test-OERGuid.ps1' } |
            Where-Object { (Get-Content -Raw -Path $_.FullName) -match '\[0-9a-f(?:A-F)?\]\{8\}-' } |
            ForEach-Object { $_.Name }
        $Offenders -join ', ' | Should -BeNullOrEmpty
    }
}
