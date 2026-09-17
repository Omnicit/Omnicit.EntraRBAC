BeforeAll { Import-Module Omnicit.EntraRBAC -Force }

Describe 'Resolve-OERRoleCompletion' {
    It 'returns one CompletionResult per curated role for an empty word' {
        InModuleScope Omnicit.EntraRBAC {
            $Results = @(Resolve-OERRoleCompletion -WordToComplete '')
            $Results.Count | Should -Be 5
            $Results[0] | Should -BeOfType [System.Management.Automation.CompletionResult]
        }
    }

    It 'filters case-insensitively by prefix' {
        InModuleScope Omnicit.EntraRBAC {
            $Results = @(Resolve-OERRoleCompletion -WordToComplete 'cont')
            $Results.Count | Should -Be 1
            $Results[0].ListItemText | Should -Be 'Contributor'
        }
    }

    It 'returns multiple matches for an ambiguous prefix' {
        InModuleScope Omnicit.EntraRBAC {
            $Texts = @(Resolve-OERRoleCompletion -WordToComplete 'R').ListItemText
            $Texts | Should -Contain 'Reader'
            $Texts | Should -Contain 'Role Based Access Control Administrator'
            $Texts | Should -Not -Contain 'Owner'
        }
    }

    It 'quotes role names that contain spaces in the completion text' {
        InModuleScope Omnicit.EntraRBAC {
            $Result = @(Resolve-OERRoleCompletion -WordToComplete 'User')[0]
            $Result.CompletionText | Should -Be "'User Access Administrator'"
            $Result.ListItemText   | Should -Be 'User Access Administrator'
        }
    }

    It 'does not quote single-token role names' {
        InModuleScope Omnicit.EntraRBAC {
            (@(Resolve-OERRoleCompletion -WordToComplete 'Reader')[0]).CompletionText | Should -Be 'Reader'
        }
    }

    It 'returns the full set when WordToComplete is not supplied' {
        InModuleScope Omnicit.EntraRBAC {
            (@(Resolve-OERRoleCompletion)).Count | Should -Be 5
        }
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
            try { $Results = @(Resolve-OERRoleCompletion -WordToComplete 'Read[') }
            catch { $Threw = $true }
            $Threw | Should -Be $false
            , $Results | Should -BeOfType [array]
            $Results.Count | Should -Be 0
        }
    }

    It 'treats the typed word literally rather than as a wildcard pattern' {
        InModuleScope Omnicit.EntraRBAC {
            @(Resolve-OERRoleCompletion -WordToComplete '*Administrator').Count | Should -Be 0
        }
    }
}

Describe 'Role argument completer registration' {
    It 'completes -Role on Get-OERRoleManagementPolicy with the curated set (quoting spaced names)' {
        $Line = 'Get-OERRoleManagementPolicy -Role '
        $Completion = TabExpansion2 -inputScript $Line -cursorColumn $Line.Length
        $Texts = $Completion.CompletionMatches.CompletionText
        $Texts | Should -Contain 'Reader'
        $Texts | Should -Contain 'Contributor'
        $Texts | Should -Contain 'Owner'
        $Texts | Should -Contain "'User Access Administrator'"
        $Texts | Should -Contain "'Role Based Access Control Administrator'"
    }

    It 'completes and filters -Role on Get-OERRoleDefinition' {
        $Line = 'Get-OERRoleDefinition -Role Cont'
        $Completion = TabExpansion2 -inputScript $Line -cursorColumn $Line.Length
        $Completion.CompletionMatches.CompletionText | Should -Contain 'Contributor'
        $Completion.CompletionMatches.CompletionText | Should -Not -Contain 'Reader'
    }

    It 'completes -Role on the state-changing cmdlet <Cmdlet>' -ForEach @(
        @{ Cmdlet = 'New-OERRoleAssignment' }
        @{ Cmdlet = 'New-OEREligibleRoleAssignment' }
        @{ Cmdlet = 'Remove-OEREligibleRoleAssignment' }
        @{ Cmdlet = 'New-OERActiveRoleAssignment' }
        @{ Cmdlet = 'Remove-OERActiveRoleAssignment' }
        @{ Cmdlet = 'Enable-OEREligibleRoleAssignment' }
        @{ Cmdlet = 'Disable-OEREligibleRoleAssignment' }
        @{ Cmdlet = 'Set-OERRoleManagementPolicy' }
    ) {
        $Line = "$Cmdlet -Role "
        $Completion = TabExpansion2 -inputScript $Line -cursorColumn $Line.Length
        $Texts = $Completion.CompletionMatches.CompletionText
        $Texts | Should -Contain 'Reader'
        $Texts | Should -Contain 'Contributor'
        $Texts | Should -Contain 'Owner'
        $Texts | Should -Contain "'User Access Administrator'"
        $Texts | Should -Contain "'Role Based Access Control Administrator'"
    }

    It 'completes and filters -Role on the state-changing cmdlet <Cmdlet>' -ForEach @(
        @{ Cmdlet = 'New-OERRoleAssignment' }
        @{ Cmdlet = 'New-OEREligibleRoleAssignment' }
        @{ Cmdlet = 'Set-OERRoleManagementPolicy' }
    ) {
        $Line = "$Cmdlet -Role Own"
        $Completion = TabExpansion2 -inputScript $Line -cursorColumn $Line.Length
        $Completion.CompletionMatches.CompletionText | Should -Contain 'Owner'
        $Completion.CompletionMatches.CompletionText | Should -Not -Contain 'Reader'
    }

    It 'completes -Role on Get-OERInventory' {
        $Line = 'Get-OERInventory -Role '
        $Completion = TabExpansion2 -inputScript $Line -cursorColumn $Line.Length
        $Completion.CompletionMatches.CompletionText | Should -Contain 'Reader'
    }

    It 'does not complete Azure role names on the entitlement-management -Role parameter' {
        # Add-OERAccessPackageResourceRole -Role names a resource role (for example Member/Owner on a
        # catalog group), not an Azure RBAC role. Offering 'Contributor' there would be wrong.
        $Line = 'Add-OERAccessPackageResourceRole -Role '
        $Completion = TabExpansion2 -inputScript $Line -cursorColumn $Line.Length
        $Completion.CompletionMatches.CompletionText | Should -Not -Contain 'Contributor'
    }

    It 'still accepts a free-text role name that is not in the curated set (no ValidateSet)' {
        # The completer must remain purely additive: binding a non-curated name must not fail.
        (Get-Command New-OERRoleAssignment).Parameters['Role'].Attributes |
            Where-Object { $_ -is [System.Management.Automation.ValidateSetAttribute] } |
            Should -BeNullOrEmpty
    }
}

Describe 'Role parameter help documents the completion list is a hint (E-common-role-set-only-five)' {
    # Get-OERCommonRoleName is deliberately capped at five entries -- it is also read by the
    # -CommonRoles switch on Get-OERRoleManagementPolicy/Get-OERInventory, so growing it would
    # silently widen what -CommonRoles reads. The open half of the finding is documentation: every
    # cmdlet whose -Role is backed by this completer (the exact -CommandName list registered in
    # suffix.ps1) must say the completion list is a hint, not the full set. Driven through Get-Help
    # (the shipped help text), not source grep, so a help edit that does not survive into
    # comment-based help still fails this.
    It 'documents the tab-completion hint on -Role for <Cmdlet>' -ForEach @(
        @{ Cmdlet = 'Get-OERRoleDefinition' }
        @{ Cmdlet = 'Get-OERRoleManagementPolicy' }
        @{ Cmdlet = 'Set-OERRoleManagementPolicy' }
        @{ Cmdlet = 'Get-OERInventory' }
        @{ Cmdlet = 'New-OERRoleAssignment' }
        @{ Cmdlet = 'New-OEREligibleRoleAssignment' }
        @{ Cmdlet = 'Remove-OEREligibleRoleAssignment' }
        @{ Cmdlet = 'Enable-OEREligibleRoleAssignment' }
        @{ Cmdlet = 'Disable-OEREligibleRoleAssignment' }
        @{ Cmdlet = 'New-OERActiveRoleAssignment' }
        @{ Cmdlet = 'Remove-OERActiveRoleAssignment' }
    ) {
        # Get-Help word-wraps .description.Text to console width and embeds real newlines at the
        # wrap points, so the sentence boundary can land mid-phrase; collapse all whitespace runs to
        # a single space before matching rather than joining array elements (there is only one).
        $Description = ((Get-Help -Name $Cmdlet -Parameter Role).description.Text -join ' ') -replace '\s+', ' '
        $Description | Should -Match 'five curated common Azure RBAC roles'
        $Description | Should -Match 'any other built-in or custom role name is still accepted'
    }
}
