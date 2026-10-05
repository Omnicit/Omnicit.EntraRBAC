BeforeAll {
    Import-Module Omnicit.EntraRBAC -Force
    . "$PSScriptRoot/../TestHelpers/OERTransportTripwire.ps1"
    Install-OERTransportTripwire
}

AfterAll {
    try { Assert-OERTransportTripwire } finally { Uninstall-OERTransportTripwire }
}

Describe 'Resolve-OERBuiltInDirectoryRoleCompletion' {
    It 'returns one CompletionResult per built-in directory role for an empty word' {
        InModuleScope Omnicit.EntraRBAC {
            $Results = @(Resolve-OERBuiltInDirectoryRoleCompletion -WordToComplete '')
            $Results.Count | Should -Be 136
            $Results[0] | Should -BeOfType [System.Management.Automation.CompletionResult]
        }
    }

    It 'filters case-insensitively by prefix' {
        InModuleScope Omnicit.EntraRBAC {
            $Texts = @(Resolve-OERBuiltInDirectoryRoleCompletion -WordToComplete 'rep').ListItemText
            $Texts | Should -Contain 'Reports Reader'
            $Texts | Should -Not -Contain 'Global Administrator'
        }
    }

    It 'quotes role names that contain spaces in the completion text' {
        InModuleScope Omnicit.EntraRBAC {
            $Result = @(Resolve-OERBuiltInDirectoryRoleCompletion -WordToComplete 'Rep')[0]
            $Result.CompletionText | Should -Be "'Reports Reader'"
            $Result.ListItemText   | Should -Be 'Reports Reader'
        }
    }

    It 'strips surrounding quotes from the word before matching' {
        InModuleScope Omnicit.EntraRBAC {
            $Texts = @(Resolve-OERBuiltInDirectoryRoleCompletion -WordToComplete "'Mess").ListItemText
            $Texts | Should -Contain 'Message Center Privacy Reader'
            $Texts | Should -Contain 'Message Center Reader'
        }
    }

    It 'returns the full set when WordToComplete is not supplied' {
        InModuleScope Omnicit.EntraRBAC {
            (@(Resolve-OERBuiltInDirectoryRoleCompletion)).Count | Should -Be 136
        }
    }

    It 'makes no Graph call' {
        Mock -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest { throw 'completers must not call Graph' }
        InModuleScope Omnicit.EntraRBAC { $null = Resolve-OERBuiltInDirectoryRoleCompletion -WordToComplete '' }
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
            try { $Results = @(Resolve-OERBuiltInDirectoryRoleCompletion -WordToComplete 'License[') }
            catch { $Threw = $true }
            $Threw | Should -Be $false
            , $Results | Should -BeOfType [array]
            $Results.Count | Should -Be 0
        }
    }

    It 'treats the typed word literally rather than as a wildcard pattern' {
        InModuleScope Omnicit.EntraRBAC {
            @(Resolve-OERBuiltInDirectoryRoleCompletion -WordToComplete '*Administrator').Count | Should -Be 0
        }
    }
}

Describe 'Built-in directory role argument completer registration' {
    It 'completes -Role on Get-OERDirectoryRoleManagementPolicy with a prefix match' {
        # 'Reports Reader' contains whitespace, so the emitted CompletionText is single-quoted (the
        # same quoting rule Resolve-OERBuiltInDirectoryRoleCompletion applies to every spaced name).
        $Line = 'Get-OERDirectoryRoleManagementPolicy -Role Reports'
        $Completion = TabExpansion2 -inputScript $Line -cursorColumn $Line.Length
        $Completion.CompletionMatches.CompletionText | Should -Contain "'Reports Reader'"
    }

    It 'completes -Role on Set-OERDirectoryRoleManagementPolicy with a prefix match' {
        $Line = 'Set-OERDirectoryRoleManagementPolicy -Role Reports'
        $Completion = TabExpansion2 -inputScript $Line -cursorColumn $Line.Length
        $Completion.CompletionMatches.CompletionText | Should -Contain "'Reports Reader'"
    }

    It 'completes -Role on <Cmdlet> with a prefix match' -ForEach @(
        @{ Cmdlet = 'New-OEREligibleDirectoryRoleAssignment' }
        @{ Cmdlet = 'Get-OEREligibleDirectoryRoleAssignment' }
        @{ Cmdlet = 'Remove-OEREligibleDirectoryRoleAssignment' }
        @{ Cmdlet = 'New-OERActiveDirectoryRoleAssignment' }
        @{ Cmdlet = 'Get-OERActiveDirectoryRoleAssignment' }
        @{ Cmdlet = 'Remove-OERActiveDirectoryRoleAssignment' }
    ) {
        $Line = "$Cmdlet -Role Reports"
        $Completion = TabExpansion2 -inputScript $Line -cursorColumn $Line.Length
        $Completion.CompletionMatches.CompletionText | Should -Contain "'Reports Reader'"
        ($Completion.CompletionMatches | Where-Object CompletionText -EQ "'Reports Reader'")[0].ListItemText |
            Should -Be 'Reports Reader'
    }

    It 'still accepts a free-text role name that is not in the curated set (no ValidateSet) on <Cmdlet>' -ForEach @(
        @{ Cmdlet = 'Get-OERDirectoryRoleManagementPolicy' }
        @{ Cmdlet = 'Set-OERDirectoryRoleManagementPolicy' }
        @{ Cmdlet = 'New-OEREligibleDirectoryRoleAssignment' }
        @{ Cmdlet = 'Get-OEREligibleDirectoryRoleAssignment' }
        @{ Cmdlet = 'Remove-OEREligibleDirectoryRoleAssignment' }
        @{ Cmdlet = 'New-OERActiveDirectoryRoleAssignment' }
        @{ Cmdlet = 'Get-OERActiveDirectoryRoleAssignment' }
        @{ Cmdlet = 'Remove-OERActiveDirectoryRoleAssignment' }
    ) {
        (Get-Command $Cmdlet).Parameters['Role'].Attributes |
            Where-Object { $_ -is [System.Management.Automation.ValidateSetAttribute] } |
            Should -BeNullOrEmpty
    }
}
