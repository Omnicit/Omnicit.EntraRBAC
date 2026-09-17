BeforeAll { Import-Module Omnicit.EntraRBAC -Force }

Describe 'Resolve-OERDirectoryRoleCompletion' {
    It 'returns one CompletionResult per curated directory role for an empty word' {
        InModuleScope Omnicit.EntraRBAC {
            $Results = @(Resolve-OERDirectoryRoleCompletion -WordToComplete '')
            $Results.Count | Should -Be 14
            $Results[0] | Should -BeOfType [System.Management.Automation.CompletionResult]
        }
    }

    It 'filters case-insensitively by prefix' {
        InModuleScope Omnicit.EntraRBAC {
            $Texts = @(Resolve-OERDirectoryRoleCompletion -WordToComplete 'user').ListItemText
            $Texts | Should -Contain 'User Administrator'
            $Texts | Should -Not -Contain 'Groups Administrator'
        }
    }

    It 'returns multiple matches for an ambiguous prefix' {
        InModuleScope Omnicit.EntraRBAC {
            $Texts = @(Resolve-OERDirectoryRoleCompletion -WordToComplete 'Attribute').ListItemText
            $Texts | Should -Contain 'Attribute Assignment Administrator'
            $Texts | Should -Contain 'Attribute Assignment Reader'
        }
    }

    It 'quotes role names that contain spaces in the completion text' {
        InModuleScope Omnicit.EntraRBAC {
            $Result = @(Resolve-OERDirectoryRoleCompletion -WordToComplete 'User Admin')[0]
            $Result.CompletionText | Should -Be "'User Administrator'"
            $Result.ListItemText   | Should -Be 'User Administrator'
        }
    }

    It 'strips surrounding quotes from the word before matching' {
        InModuleScope Omnicit.EntraRBAC {
            $Texts = @(Resolve-OERDirectoryRoleCompletion -WordToComplete "'User").ListItemText
            $Texts | Should -Contain 'User Administrator'
        }
    }

    It 'returns the full set when WordToComplete is not supplied' {
        InModuleScope Omnicit.EntraRBAC {
            (@(Resolve-OERDirectoryRoleCompletion)).Count | Should -Be 14
        }
    }

    It 'makes no Graph call' {
        Mock -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest { throw 'completers must not call Graph' }
        InModuleScope Omnicit.EntraRBAC { $null = Resolve-OERDirectoryRoleCompletion -WordToComplete '' }
        Should -Invoke Invoke-OERGraphRequest -ModuleName Omnicit.EntraRBAC -Times 0
    }

    It 'does not throw on a word containing an unbalanced wildcard bracket' {
        InModuleScope Omnicit.EntraRBAC {
            # A completer must never throw and must return no results instead (CLAUDE.md, Argument
            # Completion, rule 3), so both halves are real contract here. Assign in THIS scope: a
            # { ... } | Should -Not -Throw wrapper runs the scriptblock in a CHILD scope, so the outer
            # $Results would stay $null however many results came back -- and $null.Count is the
            # integer 0, so the count assertion below would then pass unconditionally.
            $Threw = $false
            $Results = $null
            try { $Results = @(Resolve-OERDirectoryRoleCompletion -WordToComplete 'License[') }
            catch { $Threw = $true }
            $Threw | Should -Be $false
            , $Results | Should -BeOfType [array]
            $Results.Count | Should -Be 0
        }
    }

    It 'treats the typed word literally rather than as a wildcard pattern' {
        InModuleScope Omnicit.EntraRBAC {
            @(Resolve-OERDirectoryRoleCompletion -WordToComplete '*Administrator').Count | Should -Be 0
        }
    }
}
