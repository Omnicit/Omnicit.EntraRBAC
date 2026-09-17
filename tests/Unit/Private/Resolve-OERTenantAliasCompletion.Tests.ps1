BeforeAll { Import-Module Omnicit.EntraRBAC -Force }

Describe 'Resolve-OERTenantAliasCompletion' {
    BeforeAll {
        $script:AliasDir = Join-Path $TestDrive 'Profiles'
        New-Item -ItemType Directory -Path $script:AliasDir -Force | Out-Null
        Set-Content -Path (Join-Path $script:AliasDir 'contoso.psd1')      -Value "@{ TenantId = '1' }"
        Set-Content -Path (Join-Path $script:AliasDir 'contoso-test.psd1') -Value "@{ TenantId = '2' }"
        Set-Content -Path (Join-Path $script:AliasDir 'fabrikam.psd1')     -Value "@{ TenantId = '3' }"
        Set-Content -Path (Join-Path $script:AliasDir 'north wind.psd1')   -Value "@{ TenantId = '4' }"
        # A non-profile file that must never be offered as an alias.
        Set-Content -Path (Join-Path $script:AliasDir 'readme.txt')        -Value 'not a profile'
    }

    It 'returns one CompletionResult per profile file for an empty word' {
        $Dir = $script:AliasDir
        InModuleScope Omnicit.EntraRBAC -Parameters @{ Dir = $Dir } {
            param($Dir)
            $Results = @(Resolve-OERTenantAliasCompletion -WordToComplete '' -BasePath $Dir)
            $Results.Count | Should -Be 4
            $Results[0] | Should -BeOfType [System.Management.Automation.CompletionResult]
        }
    }

    It 'ignores files that are not .psd1 profiles' {
        $Dir = $script:AliasDir
        InModuleScope Omnicit.EntraRBAC -Parameters @{ Dir = $Dir } {
            param($Dir)
            $Texts = @(Resolve-OERTenantAliasCompletion -WordToComplete '' -BasePath $Dir).ListItemText
            $Texts | Should -Not -Contain 'readme'
            $Texts | Should -Not -Contain 'readme.txt'
        }
    }

    It 'filters case-insensitively by prefix' {
        $Dir = $script:AliasDir
        InModuleScope Omnicit.EntraRBAC -Parameters @{ Dir = $Dir } {
            param($Dir)
            $Texts = @(Resolve-OERTenantAliasCompletion -WordToComplete 'CONT' -BasePath $Dir).ListItemText
            $Texts | Should -Contain 'contoso'
            $Texts | Should -Contain 'contoso-test'
            $Texts | Should -Not -Contain 'fabrikam'
        }
    }

    It 'quotes aliases that contain whitespace but keeps the raw name as the list item' {
        $Dir = $script:AliasDir
        InModuleScope Omnicit.EntraRBAC -Parameters @{ Dir = $Dir } {
            param($Dir)
            $Result = @(Resolve-OERTenantAliasCompletion -WordToComplete 'north' -BasePath $Dir)[0]
            $Result.CompletionText | Should -Be "'north wind'"
            $Result.ListItemText   | Should -Be 'north wind'
        }
    }

    It 'does not quote single-token aliases' {
        $Dir = $script:AliasDir
        InModuleScope Omnicit.EntraRBAC -Parameters @{ Dir = $Dir } {
            param($Dir)
            (@(Resolve-OERTenantAliasCompletion -WordToComplete 'fabrikam' -BasePath $Dir)[0]).CompletionText |
                Should -Be 'fabrikam'
        }
    }

    It 'strips surrounding quotes from the word before matching' {
        $Dir = $script:AliasDir
        InModuleScope Omnicit.EntraRBAC -Parameters @{ Dir = $Dir } {
            param($Dir)
            $Texts = @(Resolve-OERTenantAliasCompletion -WordToComplete "'north" -BasePath $Dir).ListItemText
            $Texts | Should -Contain 'north wind'
        }
    }

    It 'returns nothing and does not throw when the base path does not exist' {
        $Missing = Join-Path $TestDrive 'no-such-directory'
        InModuleScope Omnicit.EntraRBAC -Parameters @{ Missing = $Missing } {
            param($Missing)
            # A completer must never throw and must return no results instead (CLAUDE.md, Argument
            # Completion, rule 3), so both halves are real contract here. Assign in THIS scope: a
            # { ... } | Should -Not -Throw wrapper runs the scriptblock in a CHILD scope, so the outer
            # $Results would stay $null however many results came back -- and $null.Count is the
            # integer 0, so the count assertion below would then pass unconditionally.
            $Threw = $false
            $Results = $null
            try { $Results = @(Resolve-OERTenantAliasCompletion -WordToComplete '' -BasePath $Missing) }
            catch { $Threw = $true }
            $Threw | Should -Be $false
            , $Results | Should -BeOfType [array]
            $Results.Count | Should -Be 0
        }
    }

    It 'does not write to the error stream when the base path does not exist' {
        $Missing = Join-Path $TestDrive 'no-such-directory'
        InModuleScope Omnicit.EntraRBAC -Parameters @{ Missing = $Missing } {
            param($Missing)
            $Errors = @()
            $null = Resolve-OERTenantAliasCompletion -WordToComplete '' -BasePath $Missing -ErrorVariable Errors 2>&1
            $Errors.Count | Should -Be 0
        }
    }

    It 'does not throw on a word containing an unbalanced wildcard bracket' {
        $Dir = $script:AliasDir
        InModuleScope Omnicit.EntraRBAC -Parameters @{ Dir = $Dir } {
            param($Dir)
            # See the USERPROFILE test at the bottom of this Describe for why the assignment must not
            # sit inside a { ... } | Should -Not -Throw scriptblock: that is a CHILD scope, so $Results
            # would stay $null here no matter what came back, and $null.Count is the integer 0.
            $Threw = $false
            $Results = $null
            try { $Results = @(Resolve-OERTenantAliasCompletion -WordToComplete 'cont[' -BasePath $Dir) }
            catch { $Threw = $true }
            $Threw | Should -Be $false
            , $Results | Should -BeOfType [array]
            $Results.Count | Should -Be 0
        }
    }

    It 'treats the typed word literally rather than as a wildcard pattern' {
        $Dir = $script:AliasDir
        InModuleScope Omnicit.EntraRBAC -Parameters @{ Dir = $Dir } {
            param($Dir)
            @(Resolve-OERTenantAliasCompletion -WordToComplete '*oso' -BasePath $Dir).Count | Should -Be 0
        }
    }

    It 'does not throw or write error records when USERPROFILE is unset and -BasePath is omitted' {
        # Every other test in this Describe passes -BasePath explicitly, so the -BasePath default is
        # never evaluated -- which is exactly why the old Join-Path $env:USERPROFILE default (a
        # Windows-only variable, while this module declares CompatiblePSEditions Core) shipped without
        # a regression test. A completer must never throw and never emit an error record (CLAUDE.md,
        # Argument Completion, rule 3); it must return no results instead. The default base path is
        # the developer's REAL home directory (GetFolderPath ignores USERPROFILE on Windows), so the
        # completer's first file-system call is intercepted: the default is still bound and shown to
        # reach the body, and the real profile directory is never enumerated
        # (docs/development/rationale.md#bearer-scrub-tests).
        InModuleScope Omnicit.EntraRBAC {
            Mock Test-Path { $false }
            $Saved = $env:USERPROFILE
            try {
                Remove-Item Env:\USERPROFILE -ErrorAction SilentlyContinue
                # -ErrorVariable binds in the scope where the call is made. Wrapping the call in a
                # { ... } | Should -Not -Throw scriptblock runs it in a child scope, so the outer
                # $Errors would stay empty no matter what the completer wrote -- a vacuous assertion.
                # Call directly and capture the throw outcome with try/catch instead.
                $Errors = @()
                $Threw = $false
                try {
                    $null = Resolve-OERTenantAliasCompletion -WordToComplete '' -ErrorVariable Errors 2>&1
                } catch {
                    $Threw = $true
                }
                $Threw | Should -Be $false
                $Errors.Count | Should -Be 0
            } finally {
                if ($null -ne $Saved) { $env:USERPROFILE = $Saved }
            }
            Should -Invoke Test-Path -Exactly -Times 1 -ParameterFilter {
                $LiteralPath -like '*Omnicit.EntraRBAC*Profiles'
            }
        }
    }
}

Describe 'TenantAlias argument completer registration' {
    BeforeAll {
        $script:AliasDir = Join-Path $TestDrive 'RegProfiles'
        New-Item -ItemType Directory -Path $script:AliasDir -Force | Out-Null
        Set-Content -Path (Join-Path $script:AliasDir 'contoso.psd1')  -Value "@{ TenantId = '1' }"
        Set-Content -Path (Join-Path $script:AliasDir 'fabrikam.psd1') -Value "@{ TenantId = '2' }"
    }

    It 'completes -TenantAlias on <Cmdlet> using the -BasePath already typed' -ForEach @(
        @{ Cmdlet = 'Get-OERConfiguration' }
        @{ Cmdlet = 'Set-OERConfiguration' }
        @{ Cmdlet = 'Remove-OERConfiguration' }
    ) {
        $Line = "$Cmdlet -BasePath '$($script:AliasDir)' -TenantAlias "
        $Completion = TabExpansion2 -inputScript $Line -cursorColumn $Line.Length
        $Completion.CompletionMatches.CompletionText | Should -Contain 'contoso'
        $Completion.CompletionMatches.CompletionText | Should -Contain 'fabrikam'
    }

    It 'completes and filters -TenantAlias on Get-OERConfiguration' {
        $Line = "Get-OERConfiguration -BasePath '$($script:AliasDir)' -TenantAlias cont"
        $Completion = TabExpansion2 -inputScript $Line -cursorColumn $Line.Length
        $Completion.CompletionMatches.CompletionText | Should -Contain 'contoso'
        $Completion.CompletionMatches.CompletionText | Should -Not -Contain 'fabrikam'
    }

    It 'completes -TenantAlias on Connect-OER using the -ProfileBasePath already typed' {
        $Line = "Connect-OER -ProfileBasePath '$($script:AliasDir)' -TenantAlias "
        $Completion = TabExpansion2 -inputScript $Line -cursorColumn $Line.Length
        $Completion.CompletionMatches.CompletionText | Should -Contain 'contoso'
        $Completion.CompletionMatches.CompletionText | Should -Contain 'fabrikam'
    }

    It 'does not complete -TenantAlias on New-OERConfiguration (the alias must not exist yet)' {
        $Line = "New-OERConfiguration -BasePath '$($script:AliasDir)' -TenantAlias "
        $Completion = TabExpansion2 -inputScript $Line -cursorColumn $Line.Length
        $Completion.CompletionMatches.CompletionText | Should -Not -Contain 'contoso'
    }
}
