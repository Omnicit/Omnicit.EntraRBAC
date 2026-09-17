BeforeAll {
    $script:moduleName = 'Omnicit.EntraRBAC'
    Get-Module $script:moduleName | Remove-Module -Force -ErrorAction SilentlyContinue
    Import-Module $script:moduleName -Force -ErrorAction Stop
}

Describe 'Resolve-OERProfilePath' {
    It 'builds an alias-based psd1 path under the base path' {
        InModuleScope $script:moduleName {
            # A rooted base path that is never created. A literal 'C:\cfg' on every platform made
            # Join-Path resolve drive C: and throw DriveNotFoundException on Linux and macOS.
            $Base = if ($IsWindows) { 'C:\cfg' } else { '/cfg' }
            $Result = Resolve-OERProfilePath -TenantAlias 'contoso' -BasePath $Base
            $Result | Should -Be (Join-Path $Base 'contoso.psd1')
        }
    }

    It 'throws InvalidTenantAlias for a traversal alias' {
        InModuleScope $script:moduleName {
            $Base = Join-Path $TestDrive 'Profiles'
            { Resolve-OERProfilePath -TenantAlias '../../../evil' -BasePath $Base } |
                Should -Throw -ErrorId 'InvalidTenantAlias'
        }
    }

    It 'does not return a path outside the base directory for a traversal alias' {
        InModuleScope $script:moduleName {
            $Base = Join-Path $TestDrive 'Profiles'
            $Result = try { Resolve-OERProfilePath -TenantAlias '..\..\evil' -BasePath $Base } catch { $null }
            $Result | Should -BeNullOrEmpty
        }
    }

    It 'still resolves a normal alias under the base path' {
        InModuleScope $script:moduleName {
            $Base = Join-Path $TestDrive 'Profiles'
            $Path = Resolve-OERProfilePath -TenantAlias 'contoso' -BasePath $Base
            $Path | Should -Be (Join-Path $Base 'contoso.psd1')
        }
    }

    It 'throws ProfilePathEscapesBase when a bypassed alias still resolves outside the base directory' {
        # Test-OERTenantAlias already forbids every separator and any '..' substring, so no alias
        # that reaches Test-OERTenantAlias can trip the containment check below it. Mock the
        # predicate to force a bypass so the containment guard itself -- the defence-in-depth
        # backstop -- is exercised directly.
        InModuleScope $script:moduleName {
            Mock Test-OERTenantAlias { $true }
            $Base = Join-Path $TestDrive 'Profiles'
            { Resolve-OERProfilePath -TenantAlias '..\..\evil' -BasePath $Base } |
                Should -Throw -ErrorId 'ProfilePathEscapesBase'
        }
    }

    It 'resolves a default base path when USERPROFILE is unset' {
        # USERPROFILE is a Windows-only variable and the module declares CompatiblePSEditions Core,
        # so on Linux and macOS the -BasePath default failed to bind before the function even ran.
        InModuleScope $script:moduleName {
            $Saved = $env:USERPROFILE
            try {
                Remove-Item Env:\USERPROFILE -ErrorAction SilentlyContinue
                $Path = Resolve-OERProfilePath -TenantAlias 'contoso'
                $Path | Should -Not -BeNullOrEmpty
                $Path | Should -Match 'contoso\.psd1$'
                $Path | Should -Match 'Omnicit\.EntraRBAC'
            } finally {
                if ($null -ne $Saved) { $env:USERPROFILE = $Saved }
            }
        }
    }

    It 'resolves the same Windows path it did before' -Skip:(-not $IsWindows) {
        InModuleScope $script:moduleName {
            Resolve-OERProfilePath -TenantAlias 'contoso' |
                Should -Be (Join-Path (Join-Path $env:USERPROFILE '.config/Omnicit.EntraRBAC/Profiles') 'contoso.psd1')
        }
    }
}
