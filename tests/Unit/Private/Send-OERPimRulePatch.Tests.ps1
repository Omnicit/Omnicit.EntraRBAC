BeforeAll {
    Import-Module Omnicit.EntraRBAC -Force
    . "$PSScriptRoot/../TestHelpers/OERTransportTripwire.ps1"
    Install-OERTransportTripwire

    $script:RulesPath = 'beta/policies/roleManagementPolicies/p1/rules'
    $script:Label = "PIM policy 'p1'"

    # Runs the private helper inside the module and hands its one result object back to the test.
    # -Mode selects how a caller would try to stop it on a warning: not at all, -WarningAction Stop on
    # the call, or $WarningPreference = 'Stop' in the calling scope.
    function Invoke-TestSend {
        param([hashtable]$Splat, [string]$Mode = 'Plain')
        InModuleScope Omnicit.EntraRBAC -Parameters @{ Splat = $Splat; Mode = $Mode } {
            param($Splat, $Mode)
            if ($Mode -eq 'WarningAction') { return Send-OERPimRulePatch @Splat -WarningAction Stop }
            if ($Mode -eq 'WarningPreference') {
                $WarningPreference = 'Stop'
                return Send-OERPimRulePatch @Splat
            }
            Send-OERPimRulePatch @Splat
        }
    }

    # A rule as JSON with its keys sorted at every level, so a PATCH body can be compared with the
    # rule it must equal whatever order either dictionary enumerates its keys in.
    function ConvertTo-CanonicalJson ($Value) {
        function ConvertTo-SortedNode ($Node) {
            if ($Node -is [System.Collections.IDictionary]) {
                $Sorted = [ordered]@{}
                foreach ($Key in @($Node.Keys | Sort-Object)) { $Sorted[[string]$Key] = ConvertTo-SortedNode $Node[$Key] }
                return $Sorted
            }
            if ($Node -is [System.Collections.IEnumerable] -and $Node -isnot [string]) {
                return , @(foreach ($Item in $Node) { ConvertTo-SortedNode $Item })
            }
            $Node
        }
        ConvertTo-SortedNode $Value | ConvertTo-Json -Depth 20 -Compress
    }

    # The two rules of the MFA / authentication-context pair as Microsoft Graph returns them on a
    # single-rule read (a hashtable carrying '@odata.context'), and the same rule as it must be sent
    # back: identical, without that one key.
    function New-TestLiveRule ([string]$Id) {
        if ($Id -eq 'AuthenticationContext_EndUser_Assignment') {
            return @{
                '@odata.context' = 'https://graph.microsoft.com/beta/$metadata#policies/roleManagementPolicies/p1/rules/$entity'
                '@odata.type'    = '#microsoft.graph.unifiedRoleManagementPolicyAuthenticationContextRule'
                id               = $Id
                isEnabled        = $true
                claimValue       = 'c1'
                target           = @{ caller = 'EndUser'; operations = @('All'); level = 'Assignment' }
            }
        }
        @{
            '@odata.context' = 'https://graph.microsoft.com/beta/$metadata#policies/roleManagementPolicies/p1/rules/$entity'
            '@odata.type'    = '#microsoft.graph.unifiedRoleManagementPolicyEnablementRule'
            id               = $Id
            enabledRules     = @('MultiFactorAuthentication', 'Justification')
            target           = @{ caller = 'EndUser'; operations = @('All'); level = 'Assignment' }
        }
    }
    function New-TestExpectedPutBack ([string]$Id) {
        $Expected = New-TestLiveRule -Id $Id
        $Expected.Remove('@odata.context')
        $Expected
    }
    function New-TestChangedRule ([string]$Id) {
        if ($Id -eq 'AuthenticationContext_EndUser_Assignment') {
            return @{ '@odata.type' = '#microsoft.graph.unifiedRoleManagementPolicyAuthenticationContextRule'; id = $Id; isEnabled = $false; claimValue = '' }
        }
        if ($Id -eq 'Enablement_EndUser_Assignment') {
            return @{ '@odata.type' = '#microsoft.graph.unifiedRoleManagementPolicyEnablementRule'; id = $Id; enabledRules = @('Justification') }
        }
        @{ id = $Id; isExpirationRequired = $true; maximumDuration = 'PT4H' }
    }
}

AfterAll {
    try { Assert-OERTransportTripwire } finally { Uninstall-OERTransportTripwire }
}

Describe 'Send-OERPimRulePatch' {
    BeforeEach {
        InModuleScope Omnicit.EntraRBAC { $script:_OERAuthState = $null }
        $script:Calls = [System.Collections.Generic.List[object]]::new()
        $script:RejectRuleId = @()
        # A rule id here is accepted on its first PATCH and rejected on every later one, which is how
        # a put-back that fails is staged.
        $script:RejectRepeatRuleId = @()
        Mock -ModuleName Omnicit.EntraRBAC Initialize-OERAuth { }
        Mock -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest {
            param([string]$Method = 'GET', [string]$Uri, $Body)
            $RuleId = ($Uri -split '/')[-1]
            $script:Calls.Add([pscustomobject]@{ Method = $Method; Uri = $Uri; RuleId = $RuleId; Body = $Body })
            if ($script:RejectRuleId -contains $RuleId) { throw "Graph rejected rule '$RuleId'." }
            if ($script:RejectRepeatRuleId -contains $RuleId -and @($script:Calls | Where-Object { $_.RuleId -eq $RuleId }).Count -gt 1) {
                throw "Graph rejected the repeated PATCH of rule '$RuleId'."
            }
            @{}
        }
    }

    It 'sends every rule once, in the given order, as PATCH to its rule path; a dictionary as itself and any other rule as a hashtable' {
        $Dictionary = @{ id = 'Expiration_EndUser_Assignment'; isExpirationRequired = $true; maximumDuration = 'PT4H' }
        $Object = [pscustomobject]@{
            '@odata.type' = '#microsoft.graph.unifiedRoleManagementPolicyEnablementRule'
            id            = 'Enablement_Admin_Assignment'
            enabledRules  = @('Justification', 'MultiFactorAuthentication')
            target        = [pscustomobject]@{ caller = 'Admin'; operations = @('All'); level = 'Assignment' }
        }
        $Last = @{ id = 'Notification_Admin_Admin_Eligibility'; notificationRecipients = @('person18@example.com') }

        $Result = @(Invoke-TestSend -Splat @{ Rule = @($Dictionary, $Object, $Last); RulesPath = $script:RulesPath; PolicyLabel = $script:Label })

        $Result.Count | Should -Be 1
        @($script:Calls.RuleId) | Should -Be @('Expiration_EndUser_Assignment', 'Enablement_Admin_Assignment', 'Notification_Admin_Admin_Eligibility')
        @($script:Calls | Where-Object { $_.Method -ne 'PATCH' }).Count | Should -Be 0
        $script:Calls[0].Uri | Should -Be "$($script:RulesPath)/Expiration_EndUser_Assignment"
        $script:Calls[1].Uri | Should -Be "$($script:RulesPath)/Enablement_Admin_Assignment"
        $script:Calls[2].Uri | Should -Be "$($script:RulesPath)/Notification_Admin_Admin_Eligibility"
        # A dictionary is sent as that very object.
        [object]::ReferenceEquals($script:Calls[0].Body, $Dictionary) | Should -BeTrue
        [object]::ReferenceEquals($script:Calls[2].Body, $Last) | Should -BeTrue
        # A PSCustomObject is sent as a hashtable made by the JSON round trip, nested levels included.
        $script:Calls[1].Body | Should -BeOfType [hashtable]
        $script:Calls[1].Body.target | Should -BeOfType [hashtable]
        (ConvertTo-CanonicalJson $script:Calls[1].Body) | Should -Be (ConvertTo-CanonicalJson ($Object | ConvertTo-Json -Depth 100 | ConvertFrom-Json -AsHashtable))
        @($Result[0].Accepted) | Should -Be @('Expiration_EndUser_Assignment', 'Enablement_Admin_Assignment', 'Notification_Admin_Admin_Eligibility')
        @($Result[0].Failed).Count | Should -Be 0
        @($Result[0].Warning).Count | Should -Be 0
        $Result[0].Restored | Should -BeNullOrEmpty
        $Result[0].RestoreError | Should -BeNullOrEmpty
        $Result[0].PairFirst | Should -BeNullOrEmpty
        $Result[0].PairSecond | Should -BeNullOrEmpty
        @($Result[0].PSObject.Properties.Name) | Should -Be @('Accepted', 'Failed', 'Restored', 'RestoreError', 'PairFirst', 'PairSecond', 'Warning')
    }

    It 'sends nothing and returns an empty result for an empty rule list' {
        $Result = @(Invoke-TestSend -Splat @{ Rule = @(); RulesPath = $script:RulesPath; PolicyLabel = $script:Label })
        $Result.Count | Should -Be 1
        $script:Calls.Count | Should -Be 0
        @($Result[0].Accepted).Count | Should -Be 0
        @($Result[0].Failed).Count | Should -Be 0
        @($Result[0].Warning).Count | Should -Be 0
    }

    It 'carries on past a rejected rule, lists it as failed, returns its message and scrubs each rejection' {
        Mock -ModuleName Omnicit.EntraRBAC Remove-OERErrorRecord { }
        $script:RejectRuleId = @('Expiration_EndUser_Assignment', 'Notification_Admin_Admin_Eligibility')
        $Rules = @(
            New-TestChangedRule -Id 'Expiration_EndUser_Assignment'
            New-TestChangedRule -Id 'Enablement_Admin_Assignment'
            New-TestChangedRule -Id 'Notification_Admin_Admin_Eligibility'
            New-TestChangedRule -Id 'Expiration_Admin_Assignment'
        )
        $Result = Invoke-TestSend -Splat @{ Rule = $Rules; RulesPath = $script:RulesPath; PolicyLabel = $script:Label }

        @($script:Calls.RuleId) | Should -Be @('Expiration_EndUser_Assignment', 'Enablement_Admin_Assignment', 'Notification_Admin_Admin_Eligibility', 'Expiration_Admin_Assignment')
        @($Result.Failed) | Should -Be @('Expiration_EndUser_Assignment', 'Notification_Admin_Admin_Eligibility')
        @($Result.Accepted) | Should -Be @('Enablement_Admin_Assignment', 'Expiration_Admin_Assignment')
        @($Result.Warning) | Should -Be @(
            "Rule 'Expiration_EndUser_Assignment' of PIM policy 'p1' was not applied: Graph rejected rule 'Expiration_EndUser_Assignment'."
            "Rule 'Notification_Admin_Admin_Eligibility' of PIM policy 'p1' was not applied: Graph rejected rule 'Notification_Admin_Admin_Eligibility'."
        )
        Should -Invoke -ModuleName Omnicit.EntraRBAC Remove-OERErrorRecord -Times 2 -Exactly
        Should -Invoke -ModuleName Omnicit.EntraRBAC Remove-OERErrorRecord -Times 1 -Exactly -ParameterFilter {
            $Record.Exception.Message -eq "Graph rejected rule 'Expiration_EndUser_Assignment'."
        }
    }

    Context 'the MFA and authentication context pair' {
        It '<Direction>: puts the accepted <First> back to its live value, directly after <Second> is rejected' -TestCases @(
            @{ Direction = 'context disabled first'; First = 'AuthenticationContext_EndUser_Assignment'; Second = 'Enablement_EndUser_Assignment' }
            @{ Direction = 'enablement first'; First = 'Enablement_EndUser_Assignment'; Second = 'AuthenticationContext_EndUser_Assignment' }
        ) {
            $script:RejectRuleId = @($Second)
            $LiveFirst = New-TestLiveRule -Id $First
            $Rules = @(
                New-TestChangedRule -Id 'Expiration_EndUser_Assignment'
                New-TestChangedRule -Id $First
                New-TestChangedRule -Id $Second
                New-TestChangedRule -Id 'Notification_Admin_Admin_Eligibility'
            )
            # The live rules as a caller holds them: the second half and an unrelated rule beside the first.
            $Live = @((New-TestLiveRule -Id $Second), @{ id = 'Expiration_EndUser_Assignment'; maximumDuration = 'PT8H' }, $LiveFirst)
            $Result = Invoke-TestSend -Splat @{ Rule = $Rules; RulesPath = $script:RulesPath; LiveRule = $Live; PolicyLabel = $script:Label }

            # Exactly one extra PATCH, of the first rule, straight after the rejected second one.
            @($script:Calls.RuleId) | Should -Be @('Expiration_EndUser_Assignment', $First, $Second, $First, 'Notification_Admin_Admin_Eligibility')
            $PutBack = $script:Calls[3]
            $PutBack.Method | Should -Be 'PATCH'
            $PutBack.Uri | Should -Be "$($script:RulesPath)/$First"
            (ConvertTo-CanonicalJson $PutBack.Body) | Should -Be (ConvertTo-CanonicalJson (New-TestExpectedPutBack -Id $First)) -Because 'the put-back sends the rule exactly as it was read, less the read-only context key'
            $PutBack.Body.ContainsKey('@odata.context') | Should -BeFalse
            # A new hashtable: the live rule the caller holds is left as it was read.
            [object]::ReferenceEquals($PutBack.Body, $LiveFirst) | Should -BeFalse
            $LiveFirst.ContainsKey('@odata.context') | Should -BeTrue

            @($Result.Accepted) | Should -Be @('Expiration_EndUser_Assignment', 'Notification_Admin_Admin_Eligibility')
            @($Result.Failed) | Should -Be @($Second)
            $Result.Restored | Should -Be $First
            $Result.RestoreError | Should -BeNullOrEmpty
            $Result.PairFirst | Should -Be $First
            $Result.PairSecond | Should -Be $Second
            @($Result.Warning) | Should -Be @("Rule '$Second' of PIM policy 'p1' was not applied: Graph rejected rule '$Second'.")
        }

        It '<Direction>: keeps <First> accepted and returns why when the put-back is rejected too' -TestCases @(
            @{ Direction = 'context disabled first'; First = 'AuthenticationContext_EndUser_Assignment'; Second = 'Enablement_EndUser_Assignment' }
            @{ Direction = 'enablement first'; First = 'Enablement_EndUser_Assignment'; Second = 'AuthenticationContext_EndUser_Assignment' }
        ) {
            Mock -ModuleName Omnicit.EntraRBAC Remove-OERErrorRecord { }
            $script:RejectRuleId = @($Second)
            $script:RejectRepeatRuleId = @($First)
            $Rules = @((New-TestChangedRule -Id $First), (New-TestChangedRule -Id $Second))
            $Result = Invoke-TestSend -Splat @{ Rule = $Rules; RulesPath = $script:RulesPath; LiveRule = @(New-TestLiveRule -Id $First); PolicyLabel = $script:Label }

            @($script:Calls.RuleId) | Should -Be @($First, $Second, $First)
            $Result.RestoreError | Should -Be "Graph rejected the repeated PATCH of rule '$First'."
            @($Result.Accepted) | Should -Be @($First)
            @($Result.Failed) | Should -Be @($Second)
            $Result.Restored | Should -BeNullOrEmpty
            @($Result.Warning).Count | Should -Be 2
            @($Result.Warning)[-1] | Should -Be "Rule '$First' of PIM policy 'p1' could not be put back to its value before this call: Graph rejected the repeated PATCH of rule '$First'."
            # The failed put-back is scrubbed in its own catch.
            Should -Invoke -ModuleName Omnicit.EntraRBAC Remove-OERErrorRecord -Times 1 -Exactly -ParameterFilter {
                $Record.Exception.Message -like '*repeated PATCH*'
            }
        }

        It 'sends no put-back and names the unread value when the first rule was not supplied live (<Shape>)' -TestCases @(
            @{ Shape = 'no -LiveRule'; LiveShape = 'None' }
            @{ Shape = '-LiveRule $null'; LiveShape = 'Null' }
            @{ Shape = 'only the second rule live'; LiveShape = 'SecondOnly' }
        ) {
            $script:RejectRuleId = @('AuthenticationContext_EndUser_Assignment')
            $Splat = @{
                Rule        = @((New-TestChangedRule -Id 'Enablement_EndUser_Assignment'), (New-TestChangedRule -Id 'AuthenticationContext_EndUser_Assignment'))
                RulesPath   = $script:RulesPath
                PolicyLabel = $script:Label
            }
            if ($LiveShape -eq 'Null') { $Splat.LiveRule = $null }
            if ($LiveShape -eq 'SecondOnly') { $Splat.LiveRule = @(New-TestLiveRule -Id 'AuthenticationContext_EndUser_Assignment') }
            $Result = Invoke-TestSend -Splat $Splat

            @($script:Calls.RuleId) | Should -Be @('Enablement_EndUser_Assignment', 'AuthenticationContext_EndUser_Assignment')
            $Result.RestoreError | Should -Be 'its value before this call was not read'
            $Result.Restored | Should -BeNullOrEmpty
            @($Result.Accepted) | Should -Be @('Enablement_EndUser_Assignment')
            @($Result.Warning)[-1] | Should -Be "Rule 'Enablement_EndUser_Assignment' of PIM policy 'p1' could not be put back to its value before this call: its value before this call was not read"
        }

        It 'sends no put-back when the FIRST rule is rejected (<Shape>)' -TestCases @(
            @{ Shape = 'the second accepted'; Reject = @('AuthenticationContext_EndUser_Assignment') }
            @{ Shape = 'the second rejected too'; Reject = @('AuthenticationContext_EndUser_Assignment', 'Enablement_EndUser_Assignment') }
        ) {
            $script:RejectRuleId = $Reject
            $Rules = @((New-TestChangedRule -Id 'AuthenticationContext_EndUser_Assignment'), (New-TestChangedRule -Id 'Enablement_EndUser_Assignment'))
            $Live = @((New-TestLiveRule -Id 'AuthenticationContext_EndUser_Assignment'), (New-TestLiveRule -Id 'Enablement_EndUser_Assignment'))
            $Result = Invoke-TestSend -Splat @{ Rule = $Rules; RulesPath = $script:RulesPath; LiveRule = $Live; PolicyLabel = $script:Label }

            @($script:Calls.RuleId) | Should -Be @('AuthenticationContext_EndUser_Assignment', 'Enablement_EndUser_Assignment')
            @($Result.Failed) | Should -Be $Reject
            $Result.Restored | Should -BeNullOrEmpty
            $Result.RestoreError | Should -BeNullOrEmpty
            $Result.PairFirst | Should -Be 'AuthenticationContext_EndUser_Assignment'
            $Result.PairSecond | Should -Be 'Enablement_EndUser_Assignment'
            (@($Result.Warning) -join ' ') | Should -Not -BeLike '*put back*'
        }

        It 'runs no pair logic when only <Present> of the pair is sent, even when it is rejected' -TestCases @(
            @{ Present = 'Enablement_EndUser_Assignment' }
            @{ Present = 'AuthenticationContext_EndUser_Assignment' }
        ) {
            $script:RejectRuleId = @($Present)
            $Rules = @((New-TestChangedRule -Id 'Expiration_EndUser_Assignment'), (New-TestChangedRule -Id $Present))
            $Live = @(@{ id = 'Expiration_EndUser_Assignment'; maximumDuration = 'PT8H' }, (New-TestLiveRule -Id $Present))
            $Result = Invoke-TestSend -Splat @{ Rule = $Rules; RulesPath = $script:RulesPath; LiveRule = $Live; PolicyLabel = $script:Label }

            @($script:Calls.RuleId) | Should -Be @('Expiration_EndUser_Assignment', $Present)
            @($Result.Failed) | Should -Be @($Present)
            @($Result.Accepted) | Should -Be @('Expiration_EndUser_Assignment')
            $Result.PairFirst | Should -BeNullOrEmpty
            $Result.PairSecond | Should -BeNullOrEmpty
            $Result.Restored | Should -BeNullOrEmpty
            $Result.RestoreError | Should -BeNullOrEmpty
        }

        It 'runs no pair logic when one pair rule is sent twice and the other not at all' {
            # Two ids from the pair, but the same one: the pair is not complete.
            $script:RejectRepeatRuleId = @('Enablement_EndUser_Assignment')
            $Rules = @((New-TestChangedRule -Id 'Enablement_EndUser_Assignment'), (New-TestChangedRule -Id 'Enablement_EndUser_Assignment'))
            $Result = Invoke-TestSend -Splat @{ Rule = $Rules; RulesPath = $script:RulesPath; LiveRule = @(New-TestLiveRule -Id 'Enablement_EndUser_Assignment'); PolicyLabel = $script:Label }

            @($script:Calls.RuleId) | Should -Be @('Enablement_EndUser_Assignment', 'Enablement_EndUser_Assignment')
            @($Result.Failed) | Should -Be @('Enablement_EndUser_Assignment')
            $Result.PairFirst | Should -BeNullOrEmpty
            $Result.PairSecond | Should -BeNullOrEmpty
            $Result.Restored | Should -BeNullOrEmpty
            $Result.RestoreError | Should -BeNullOrEmpty
        }
    }

    Context 'it writes no warning of its own' {
        It 'neither stops nor loses a message under <Mode> Stop: every PATCH and the put-back are sent' -TestCases @(
            @{ Mode = 'WarningAction' }
            @{ Mode = 'WarningPreference' }
        ) {
            # A rejected rule, a rejected second half and a failed put-back: every message the helper
            # can produce, in one call.
            $script:RejectRuleId = @('Expiration_EndUser_Assignment', 'Enablement_EndUser_Assignment')
            $script:RejectRepeatRuleId = @('AuthenticationContext_EndUser_Assignment')
            $Rules = @(
                New-TestChangedRule -Id 'Expiration_EndUser_Assignment'
                New-TestChangedRule -Id 'AuthenticationContext_EndUser_Assignment'
                New-TestChangedRule -Id 'Enablement_EndUser_Assignment'
                New-TestChangedRule -Id 'Notification_Admin_Admin_Eligibility'
            )
            $Splat = @{ Rule = $Rules; RulesPath = $script:RulesPath; LiveRule = @(New-TestLiveRule -Id 'AuthenticationContext_EndUser_Assignment'); PolicyLabel = $script:Label }
            $script:Out = $null
            { $script:Out = Invoke-TestSend -Splat $Splat -Mode $Mode } | Should -Not -Throw

            @($script:Calls.RuleId) | Should -Be @(
                'Expiration_EndUser_Assignment'
                'AuthenticationContext_EndUser_Assignment'
                'Enablement_EndUser_Assignment'
                'AuthenticationContext_EndUser_Assignment'
                'Notification_Admin_Admin_Eligibility'
            )
            @($script:Out.Warning) | Should -Be @(
                "Rule 'Expiration_EndUser_Assignment' of PIM policy 'p1' was not applied: Graph rejected rule 'Expiration_EndUser_Assignment'."
                "Rule 'Enablement_EndUser_Assignment' of PIM policy 'p1' was not applied: Graph rejected rule 'Enablement_EndUser_Assignment'."
                "Rule 'AuthenticationContext_EndUser_Assignment' of PIM policy 'p1' could not be put back to its value before this call: Graph rejected the repeated PATCH of rule 'AuthenticationContext_EndUser_Assignment'."
            )
        }
    }

    Context 'single ownership of the per-rule PATCH, read from the source (AST)' {
        BeforeAll {
            # tests/Unit/Private -> tests/Unit -> tests -> repo root.
            $script:SourceRoot = Join-Path $PSScriptRoot '../../../source'
            function Get-TestCommand ([string]$RelativePath) {
                $Path = Convert-Path -LiteralPath (Join-Path $script:SourceRoot $RelativePath) -ErrorAction Stop
                $Ast = [System.Management.Automation.Language.Parser]::ParseFile($Path, [ref]$null, [ref]$null)
                , @($Ast.FindAll({ param($Node) $Node -is [System.Management.Automation.Language.CommandAst] }, $true))
            }
            function Get-TestMemberCall ([string]$RelativePath) {
                $Path = Convert-Path -LiteralPath (Join-Path $script:SourceRoot $RelativePath) -ErrorAction Stop
                $Ast = [System.Management.Automation.Language.Parser]::ParseFile($Path, [ref]$null, [ref]$null)
                , @($Ast.FindAll({ param($Node) $Node -is [System.Management.Automation.Language.InvokeMemberExpressionAst] }, $true))
            }
            # An Invoke-OERGraphRequest call that may write: a -Method that is PATCH or not a
            # constant at all, or a splatted call whose method the source does not show.
            function Test-TestPossiblePatch ($Command) {
                $Elements = $Command.CommandElements
                for ($Index = 1; $Index -lt $Elements.Count; $Index++) {
                    $Element = $Elements[$Index]
                    if ($Element -is [System.Management.Automation.Language.VariableExpressionAst] -and $Element.Splatted) { return $true }
                    if ($Element -is [System.Management.Automation.Language.CommandParameterAst] -and $Element.ParameterName -eq 'Method') {
                        $Value = $Element.Argument
                        if ($null -eq $Value -and ($Index + 1) -lt $Elements.Count) { $Value = $Elements[$Index + 1] }
                        if ($Value -isnot [System.Management.Automation.Language.StringConstantExpressionAst]) { return $true }
                        if ([string]$Value.Value -eq 'PATCH') { return $true }
                    }
                }
                $false
            }
        }

        It 'reads the three files it guards, and its PATCH detector finds the two in the helper' {
            # The positive control: without it a detector that never matches would pass the cohort below.
            $Commands = Get-TestCommand -RelativePath 'Private/Send-OERPimRulePatch.ps1'
            $Patches = @($Commands | Where-Object { $_.GetCommandName() -eq 'Invoke-OERGraphRequest' -and (Test-TestPossiblePatch -Command $_) })
            $Patches.Count | Should -Be 2
            foreach ($File in 'Public/Set-OERGroupPimPolicy.ps1', 'Public/Set-OERDirectoryRoleManagementPolicy.ps1') {
                Test-Path -LiteralPath (Join-Path $script:SourceRoot $File) | Should -BeTrue
            }
        }

        It '<File> sends no PATCH of its own and calls Send-OERPimRulePatch exactly once' -TestCases @(
            @{ File = 'Public/Set-OERGroupPimPolicy.ps1' }
            @{ File = 'Public/Set-OERDirectoryRoleManagementPolicy.ps1' }
        ) {
            $Commands = Get-TestCommand -RelativePath $File
            $Commands.Count | Should -BeGreaterThan 0
            $Patches = @($Commands | Where-Object { $_.GetCommandName() -eq 'Invoke-OERGraphRequest' -and (Test-TestPossiblePatch -Command $_) })
            $Patches.Count | Should -Be 0 -Because ('{0} must send its rules through Send-OERPimRulePatch, the single owner of the per-rule PATCH and the pair put-back; found at line(s) {1}' -f
                $File, (($Patches | ForEach-Object { $_.Extent.StartLineNumber }) -join ', '))
            @($Commands | Where-Object { $_.GetCommandName() -eq 'Send-OERPimRulePatch' }).Count | Should -Be 1
        }

        It 'Send-OERPimRulePatch writes no warning, error, information or host output' {
            $Commands = Get-TestCommand -RelativePath 'Private/Send-OERPimRulePatch.ps1'
            # Reached: the file was read and holds its sends.
            @($Commands | Where-Object { $_.GetCommandName() -eq 'Invoke-OERGraphRequest' }).Count | Should -BeGreaterThan 0
            $Writers = @($Commands | Where-Object { $_.GetCommandName() -in 'Write-Warning', 'Write-Host', 'Write-Information', 'Write-Error' })
            $Writers.Count | Should -Be 0
            $Members = Get-TestMemberCall -RelativePath 'Private/Send-OERPimRulePatch.ps1'
            @($Members | Where-Object { [string]$_.Member.Value -in 'WriteWarning', 'WriteError', 'WriteInformation', 'WriteHost' }).Count | Should -Be 0
        }
    }
}
