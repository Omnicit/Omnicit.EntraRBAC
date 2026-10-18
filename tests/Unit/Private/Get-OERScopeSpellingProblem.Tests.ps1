BeforeAll {
    $script:moduleName = 'Omnicit.EntraRBAC'
    Get-Module $script:moduleName | Remove-Module -Force -ErrorAction SilentlyContinue
    Import-Module $script:moduleName -Force -ErrorAction Stop
    . "$PSScriptRoot/../TestHelpers/OERTransportTripwire.ps1"
    Install-OERTransportTripwire

    # The owner's answer for one scope, read through the module scope.
    function script:Get-Problem {
        param([AllowNull()][AllowEmptyString()][string]$Scope, [string]$Path = 'roleAssignments[0]')
        InModuleScope $script:moduleName -Parameters @{ Scope = $Scope; Path = $Path } {
            param($Scope, $Path)
            @(Get-OERScopeSpellingProblem -Scope $Scope -Path $Path)
        }
    }
    # The validator's exact messages, written out in full here rather than built the way the source
    # builds them, so a message the owner rewords is caught even where the validator follows it.
    function script:Get-SlashText {
        param([string]$Path, [string]$Scope)
        "'scope' at $Path must be written without a trailing or doubled '/'. Got: '$Scope'."
    }
    function script:Get-DotText {
        param([string]$Path, [string]$Scope)
        "'scope' at $Path must be written without a '.' or '..' segment: the request would name another scope than the one written. Got: '$Scope'."
    }
    function script:Get-PercentText {
        param([string]$Path, [string]$Scope)
        "'scope' at $Path must be written without a '%': an escape can let two spellings reach one resource, and the " +
        "names of most Azure resource types hold no '%'. Got: '$Scope'. A resource whose name holds one cannot be declared in " +
        'a document; remove the entry.'
    }
    function script:Get-BackslashText {
        param([string]$Path, [string]$Scope)
        "'scope' at $Path must be written without a '\': the request reads it as '/', so the scope would be a second " +
        "spelling of the one written with '/'. Got: '$Scope'. A resource whose name holds one cannot be declared in a " +
        'document; remove the entry.'
    }
    function script:Get-PathEndText {
        param([string]$Path, [string]$Scope)
        "'scope' at $Path must be written without a '?' or '#': either ends the path of the request, which would then " +
        "name another scope than the one written. Got: '$Scope'. A resource whose name holds one cannot be declared in a " +
        'document; remove the entry.'
    }
    function script:Get-WhiteSpaceText {
        param([string]$Path, [string]$Scope, [string]$Named)
        "'scope' at $Path must be written without white space at the start or end of the scope or of a segment, white " +
        "space other than a space (U+0020) or a control character; a space between other characters of a segment is " +
        "accepted. Got: '$Scope'.$Named A resource whose name holds one of these cannot be declared in a document; remove " +
        'the entry.'
    }
    $script:SpSub = '/subscriptions/11111111-1111-1111-1111-111111111111'
}

AfterAll {
    try { Assert-OERTransportTripwire } finally { Uninstall-OERTransportTripwire }
}

Describe 'Get-OERScopeSpellingProblem' {
    # The single owner of the two scope spelling rules the validator applies to roleAssignments and
    # roleManagementPolicies (A15: a trailing or doubled '/'; A13: a '.' or '..' segment, a '%', a '\', a
    # '?' or '#', and misplaced white space or a control character, with the mg:, sub: and subscription:
    # forms exempt as ConvertTo-OERScopeSplat reads them). One Rule and the validator's exact message per
    # broken rule, in the order the validator reports them. No id below is version-4 shaped.

    It 'returns one <Rule> problem with the validator''s exact message for <Case>' -ForEach @(
        @{ Case = 'a trailing slash'; Rule = 'Slash'; Scope = '/subscriptions/11111111-1111-1111-1111-111111111111/resourceGroups/rg1/'; Text = 'Slash' }
        @{ Case = 'a doubled slash'; Rule = 'Slash'; Scope = '/subscriptions/11111111-1111-1111-1111-111111111111//resourceGroups/rg1'; Text = 'Slash' }
        @{ Case = 'a run of slashes alone'; Rule = 'Slash'; Scope = '//'; Text = 'Slash' }
        @{ Case = 'a parent segment'; Rule = 'DotSegment'; Scope = '/subscriptions/11111111-1111-1111-1111-111111111111/resourceGroups/rg/../other'; Text = 'Dot' }
        @{ Case = 'a dot segment'; Rule = 'DotSegment'; Scope = '/subscriptions/11111111-1111-1111-1111-111111111111/./resourceGroups/rg'; Text = 'Dot' }
        @{ Case = 'an escape'; Rule = 'Escape'; Scope = '/subscriptions/11111111-1111-1111-1111-111111111111/resourceGroups/rg%2Fx'; Text = 'Percent' }
        @{ Case = 'a percent sign alone'; Rule = 'Escape'; Scope = '/subscriptions/11111111-1111-1111-1111-111111111111/resourceGroups/rg%'; Text = 'Percent' }
        @{ Case = 'a backslash'; Rule = 'Backslash'; Scope = '/subscriptions/11111111-1111-1111-1111-111111111111\resourceGroups\rg'; Text = 'Backslash' }
        @{ Case = 'a number sign'; Rule = 'QueryOrFragment'; Scope = '/subscriptions/11111111-1111-1111-1111-111111111111/resourceGroups/rg/providers/Microsoft.Sql/servers/srv1/databases/db#1'; Text = 'PathEnd' }
        @{ Case = 'a question mark'; Rule = 'QueryOrFragment'; Scope = '/subscriptions/11111111-1111-1111-1111-111111111111/resourceGroups/rg?x'; Text = 'PathEnd' }
        @{ Case = 'both a question mark and a number sign, one problem'; Rule = 'QueryOrFragment'; Scope = '/subscriptions/11111111-1111-1111-1111-111111111111/resourceGroups/rg?a#b'; Text = 'PathEnd' }
        @{ Case = 'a space at the start of a segment'; Rule = 'WhiteSpace'; Scope = '/subscriptions/11111111-1111-1111-1111-111111111111/resourceGroups/ rg'; Text = 'WhiteSpace'; Named = '' }
        @{ Case = 'a leading space'; Rule = 'WhiteSpace'; Scope = ' /subscriptions/11111111-1111-1111-1111-111111111111'; Text = 'WhiteSpace'; Named = '' }
        @{ Case = 'a tab inside a segment'; Rule = 'WhiteSpace'; Scope = "/subscriptions/11111111-1111-1111-1111-111111111111/resourceGroups/my$([char]9)rg"; Text = 'WhiteSpace'; Named = ' It contains U+0009.' }
        @{ Case = 'a tab and a no-break space, named in order'; Rule = 'WhiteSpace'; Scope = "/subscriptions/11111111-1111-1111-1111-111111111111/resourceGroups/a$([char]9)b/c$([char]0x00A0)d"; Text = 'WhiteSpace'; Named = ' It contains U+0009, U+00A0.' }
        @{ Case = 'a control character that is not white space'; Rule = 'WhiteSpace'; Scope = "/subscriptions/11111111-1111-1111-1111-111111111111/resourceGroups/my$([char]7)rg"; Text = 'WhiteSpace'; Named = ' It contains U+0007.' }
    ) {
        $Path = 'roleManagementPolicies[4]'
        $Problems = Get-Problem -Scope $Scope -Path $Path
        $Problems.Count | Should -Be 1
        @($Problems[0].PSObject.Properties.Name) | Should -Be @('Rule', 'Message')
        $Problems[0].Rule | Should -BeExactly $Rule
        $Expected = switch ($Text) {
            'Slash' { Get-SlashText -Path $Path -Scope $Scope }
            'Dot' { Get-DotText -Path $Path -Scope $Scope }
            'Percent' { Get-PercentText -Path $Path -Scope $Scope }
            'Backslash' { Get-BackslashText -Path $Path -Scope $Scope }
            'PathEnd' { Get-PathEndText -Path $Path -Scope $Scope }
            'WhiteSpace' { Get-WhiteSpaceText -Path $Path -Scope $Scope -Named $Named }
        }
        $Problems[0].Message | Should -BeExactly $Expected
    }

    It 'returns every rule one scope breaks, in the order the validator reports them' {
        $Scope = "$($script:SpSub)/ rg/..\%2e?#/"
        $Problems = Get-Problem -Scope $Scope -Path 'roleAssignments[2]'
        @($Problems | ForEach-Object { $_.Rule }) | Should -Be @('Slash', 'DotSegment', 'Escape', 'Backslash', 'QueryOrFragment', 'WhiteSpace')
        @($Problems | ForEach-Object { $_.Message }) | Should -Be @(
            (Get-SlashText -Path 'roleAssignments[2]' -Scope $Scope)
            (Get-DotText -Path 'roleAssignments[2]' -Scope $Scope)
            (Get-PercentText -Path 'roleAssignments[2]' -Scope $Scope)
            (Get-BackslashText -Path 'roleAssignments[2]' -Scope $Scope)
            (Get-PathEndText -Path 'roleAssignments[2]' -Scope $Scope)
            (Get-WhiteSpaceText -Path 'roleAssignments[2]' -Scope $Scope -Named '')
        )
    }

    It 'returns nothing for <Case>' -ForEach @(
        @{ Case = 'the root scope'; Scope = '/' }
        @{ Case = 'a subscription'; Scope = '/subscriptions/11111111-1111-1111-1111-111111111111' }
        @{ Case = 'a management group'; Scope = '/providers/Microsoft.Management/managementGroups/plat' }
        @{ Case = 'dots inside a segment'; Scope = '/subscriptions/11111111-1111-1111-1111-111111111111/resourceGroups/rg/providers/Microsoft.Web/sites/a..b' }
        @{ Case = 'one space between other characters of a segment'; Scope = '/subscriptions/11111111-1111-1111-1111-111111111111/resourceGroups/rg/providers/Microsoft.Sql/servers/srv1/databases/sales data' }
        @{ Case = 'two spaces between other characters of a segment'; Scope = '/subscriptions/11111111-1111-1111-1111-111111111111/resourceGroups/rg/providers/Microsoft.Insights/components/web  app 1' }
        @{ Case = 'an empty string'; Scope = '' }
        @{ Case = 'null'; Scope = $null }
    ) {
        (Get-Problem -Scope $Scope).Count | Should -Be 0
    }

    It 'exempts the friendly form <Scope> from the segment rules, as ConvertTo-OERScopeSplat reads it' -ForEach @(
        @{ Scope = 'mg:Contoso Root' }
        @{ Scope = 'Mg:Contoso Root' }
        @{ Scope = 'sub:Visual Studio Enterprise' }
        @{ Scope = 'SUBSCRIPTION:My Sub' }
        @{ Scope = 'mg:a%20b' }
        @{ Scope = 'sub:/../x' }
        @{ Scope = 'mg:a\b' }
        @{ Scope = 'sub:x?y#z' }
        @{ Scope = 'mg: Contoso Root ' }
        @{ Scope = "subscription:My$([char]9)Sub" }
    ) {
        (Get-Problem -Scope $Scope).Count | Should -Be 0
    }

    It 'still applies the slash rule to a friendly form (<Scope>)' -ForEach @(
        @{ Scope = 'mg:plat/' }
        @{ Scope = 'sub:Prod//Dev' }
    ) {
        $Problems = Get-Problem -Scope $Scope -Path 'roleAssignments[1]'
        @($Problems | ForEach-Object { $_.Rule }) | Should -Be @('Slash')
        $Problems[0].Message | Should -BeExactly (Get-SlashText -Path 'roleAssignments[1]' -Scope $Scope)
    }

    It 'exempts no text that merely starts with the prefix: ''mg:'' and a line feed is sent as written' {
        $Scope = "mg:$([char]10)/../x"
        $Problems = Get-Problem -Scope $Scope -Path 'roleManagementPolicies[0]'
        @($Problems | ForEach-Object { $_.Rule }) | Should -Be @('DotSegment', 'WhiteSpace')
        $Problems[1].Message | Should -BeExactly (Get-WhiteSpaceText -Path 'roleManagementPolicies[0]' -Scope $Scope -Named ' It contains U+000A.')
    }
}

Describe 'Get-OERScopeSpellingProblem is the one rule the validator and the export both apply' {
    # The single-owner rule, held by behaviour: for every scope below, the validator reports an Error at
    # the entry's scope path exactly when the owner returns a problem -- with the owner's messages, in its
    # order -- and Get-OERInventory leaves a role assignment out of the document exactly when the owner
    # returns a problem for its scope. The set covers every Rule, the friendly-form exemption, clean scopes
    # and spaces between other characters of a segment. No scope here is the root scope (the root split
    # comes first; Get-OERInventory.Tests.ps1 holds that). No id below is version-4 shaped.
    BeforeAll {
        $Sub = '/subscriptions/11111111-1111-1111-1111-111111111111'
        $script:AgreeScopes = @(
            $Sub
            "$Sub/resourceGroups/rg1/"
            "$Sub//resourceGroups/rg1"
            "$Sub/resourceGroups/rg/../other"
            "$Sub/resourceGroups/rg%2Fx"
            "$Sub/resourceGroups\rg"
            "$Sub/resourceGroups/rg/providers/Microsoft.Sql/servers/srv1/databases/db#1"
            "$Sub/resourceGroups/rg?x"
            "$Sub/resourceGroups/ rg"
            "$Sub/resourceGroups/my$([char]9)rg"
            "$Sub/resourceGroups/rg/providers/Microsoft.Sql/servers/srv1/databases/sales data"
            "$Sub/resourceGroups/rg/providers/Microsoft.Insights/components/web  app 1"
            "$Sub/ rg/..\%2e?#"
            'mg:Contoso Root'
            'mg:plat/'
            'sub:x?y#z'
            "mg:$([char]10)/../x"
        )
    }

    It 'has the validator report an Error at the scope path exactly when the owner returns a problem, with its messages, in <Section>' -ForEach @(
        @{ Section = 'roleAssignments' }
        @{ Section = 'roleManagementPolicies' }
    ) {
        $Compared = 0
        $Refused = 0
        foreach ($Scope in $script:AgreeScopes) {
            $Entry = if ($Section -eq 'roleAssignments') {
                [pscustomobject]@{ scope = $Scope; role = 'Reader'; principal = 'person1@example.com' }
            } else {
                [pscustomobject]@{ scope = $Scope; role = 'Reader' }
            }
            $Doc = [pscustomobject]@{ version = '1.0'; $Section = @($Entry) }
            $Answer = InModuleScope $script:moduleName -Parameters @{ Doc = $Doc; Scope = $Scope; Path = "$Section[0]" } {
                param($Doc, $Scope, $Path)
                [PSCustomObject]@{
                    Owner     = @(Get-OERScopeSpellingProblem -Scope $Scope -Path $Path | ForEach-Object { $_.Message })
                    Validator = @((Test-OERStructureSchema -Document $Doc).Errors |
                            Where-Object { $_.Severity -eq 'Error' -and $_.Path -eq "$Path.scope" } | ForEach-Object { $_.Message })
                }
            }
            @($Answer.Validator) | Should -Be @($Answer.Owner) -Because "the validator and the owner must agree on '$Scope' in $Section"
            $Compared++
            if (@($Answer.Owner).Count -gt 0) { $Refused++ }
        }
        # Reach proof: every scope was compared, and both answers occur.
        $Compared | Should -Be $script:AgreeScopes.Count
        $Refused | Should -Be 12
    }

    It 'has Get-OERInventory leave a role assignment out exactly when the owner returns a problem for its scope' {
        Mock -ModuleName $script:moduleName Initialize-OERAuth {}
        # A20 (BL-152): the section reads -Subscription only in the session tenant's own subscription, which
        # this one is; the decision is Get-OERSubscriptionHomeTenant's, tested in its own suite.
        Mock -ModuleName $script:moduleName Get-OERSubscriptionHomeTenant {
            [PSCustomObject]@{ Scope = $Scope; SubscriptionId = $null; DisplayName = $null; Verdict = 'Home'; HomeTenantId = $null; SessionTenantId = $null; Reason = $null; ErrorRecord = $null }
        }
        Mock -ModuleName $script:moduleName Get-OERGroupNameIndex {
            $Index = [PSCustomObject]@{
                Read      = $true
                IdsByName = [System.Collections.Generic.Dictionary[string, System.Collections.Generic.List[string]]]::new([System.StringComparer]::OrdinalIgnoreCase)
                Message   = $null
            }
            $Index.PSObject.TypeNames.Insert(0, 'Omnicit.EntraRBAC.GroupNameIndex')
            $Index
        }
        Mock -ModuleName $script:moduleName Get-OERDeletedPrincipalStatus { throw "unexpected deleted items read: $Id" }
        # One row per scope, each with a principal of its own that the directory returns, so no row
        # collides with another and every name is read.
        $script:AgreeRows = @(for ($I = 0; $I -lt $script:AgreeScopes.Count; $I++) {
                $PrincipalId = 'dddd5555-0000-0000-0000-{0:D12}' -f ($I + 1)
                [PSCustomObject]@{
                    Scope = $script:AgreeScopes[$I]; RoleName = 'Reader'
                    RoleDefinitionId = '/providers/Microsoft.Authorization/roleDefinitions/rd-reader'
                    PrincipalId = $PrincipalId; PrincipalType = 'User'; PrincipalDisplayName = "User $I"
                    RoleAssignmentId = "/providers/Microsoft.Authorization/roleAssignments/cccc5555-0000-0000-0000-{0:D12}" -f ($I + 1)
                }
            })
        Mock -ModuleName $script:moduleName Get-OERRoleAssignment { $script:AgreeRows }
        Mock -ModuleName $script:moduleName Resolve-OERPrincipalName {
            param([string[]]$Id, [switch]$PreferDisplayName, [switch]$Detailed)
            foreach ($One in @($Id)) {
                [PSCustomObject]@{ Id = $One; Read = $true; Found = $true; Name = "$One@example.com"; ObjectType = 'user'; Cause = $null }
            }
        }
        $Info = $null
        $Inv = Get-OERInventory -Include RoleAssignments -Subscription '11111111-1111-1111-1111-111111111111' -IncludeARM `
            -WarningAction SilentlyContinue -InformationVariable Info
        $Kept = @($Inv.roleAssignments | ForEach-Object { [string]$_.scope })
        $LeftOut = @(@($Info | Where-Object { $_.Tags -contains 'Omnicit.EntraRBAC.UndeclarableScope' }) |
                ForEach-Object { @($_.MessageData.Assignments) } | ForEach-Object { [string]$_.Scope })
        $Expected = InModuleScope $script:moduleName -Parameters @{ Scopes = $script:AgreeScopes } {
            param($Scopes)
            foreach ($Scope in $Scopes) {
                [PSCustomObject]@{ Scope = $Scope; Refused = (@(Get-OERScopeSpellingProblem -Scope $Scope -Path 'roleAssignments').Count -gt 0) }
            }
        }
        $Kept | Should -Be @($Expected | Where-Object { -not $_.Refused } | ForEach-Object { $_.Scope })
        $LeftOut | Should -Be @($Expected | Where-Object { $_.Refused } | ForEach-Object { $_.Scope })
        # Reach proof: both answers occur, and every row is in exactly one of the two lists.
        $LeftOut.Count | Should -Be 12
        ($Kept.Count + $LeftOut.Count) | Should -Be $script:AgreeScopes.Count
    }
}
