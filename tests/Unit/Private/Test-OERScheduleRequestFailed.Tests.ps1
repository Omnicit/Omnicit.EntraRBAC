BeforeDiscovery {
    # The cohort is DERIVED from the files (BL-99), never listed by hand: every cmdlet under
    # source/Public whose syntax tree holds a string -- single-quoted, double-quoted or expandable --
    # that matches ScheduleRequests, case-insensitively. That is how each of them names the PIM
    # schedule request resource it sends to, whether the path is written out (Graph v1.0, ARM) or
    # handed to Get-OERPimGroupsGraphPath (Graph beta). Each must ask the owner whether the answer is
    # a failure (BL-33). A new sender is found by this derivation and must call the owner; nothing
    # joins a list by hand. Static only: the files are parsed and nothing in them runs.
    #
    # What the derivation does NOT see: a path assembled at run time from pieces, a path held in a
    # Private helper, and any file outside source/Public. Send-OERNewGroupEligibilityRequest is such
    # a helper; the one wait of Sync-OERStructureGroup that calls it asks the owner itself, and that
    # wait is held by the behaviour tests in Sync-OERStructureGroup.Tests.ps1, not here. The
    # derivation can also be too wide: a cmdlet that only READS a schedule request resource would
    # join the cohort and fail the owner check below. That red is the prompt to narrow the
    # derivation to senders, never to hand-list an exemption.
    $SourceRootAtDiscovery = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '../../../source')).Path
    $script:ScheduleRequestCohort = @(
        foreach ($File in (Get-ChildItem -LiteralPath (Join-Path $SourceRootAtDiscovery 'Public') -Filter '*.ps1' -File | Sort-Object -Property Name)) {
            $Tokens = $null
            $ParseErrors = $null
            $Ast = [System.Management.Automation.Language.Parser]::ParseFile($File.FullName, [ref]$Tokens, [ref]$ParseErrors)
            if (@($ParseErrors).Count -gt 0) {
                throw "Cannot derive the schedule request cohort: $($File.Name) does not parse ($($ParseErrors[0].Message))."
            }
            $PathStrings = @($Ast.FindAll({
                        param($Node)
                        ($Node -is [System.Management.Automation.Language.StringConstantExpressionAst] -or
                        $Node -is [System.Management.Automation.Language.ExpandableStringExpressionAst]) -and
                        $Node.Value -match '(?i)ScheduleRequests'
                    }, $true))
            if ($PathStrings.Count -gt 0) { $File.BaseName }
        }
    )

    # The twelve cmdlets the rule was written for in BL-33, listed by hand ONCE as a CONTROL on the
    # derivation above, not as the cohort: every one of them must be in the derived set, so a
    # derivation that stops matching cannot silently shrink the cohort and leave every check green
    # on the smaller set.
    $script:ScheduleRequestKnownSenders = @(
        'Add-OERGroupEligibility'
        'Remove-OERGroupEligibility'
        'New-OEREligibleDirectoryRoleAssignment'
        'Remove-OEREligibleDirectoryRoleAssignment'
        'New-OEREligibleRoleAssignment'
        'Remove-OEREligibleRoleAssignment'
        'New-OERActiveDirectoryRoleAssignment'
        'Remove-OERActiveDirectoryRoleAssignment'
        'New-OERActiveRoleAssignment'
        'Remove-OERActiveRoleAssignment'
        'Enable-OEREligibleRoleAssignment'
        'Disable-OEREligibleRoleAssignment'
    )
}

BeforeAll {
    Import-Module Omnicit.EntraRBAC -Force
    . "$PSScriptRoot/../TestHelpers/OERTransportTripwire.ps1"
    Install-OERTransportTripwire
}

AfterAll {
    try { Assert-OERTransportTripwire } finally { Uninstall-OERTransportTripwire }
}

Describe 'Test-OERScheduleRequestFailed' {
    # Known answers for the rule of Ruling R1: the Failed family, compared without regard to letter
    # case, is an error, and nothing else is -- Revoked (a removal's success) included.
    It 'answers $true for status <Status>, which is in the Failed family' -ForEach @(
        @{ Status = 'Failed' }
        @{ Status = 'FAILED' }
        @{ Status = 'failed' }
        @{ Status = 'FailedAsResourceIsLocked' }
        @{ Status = 'failedasresourceislocked' }
    ) {
        InModuleScope Omnicit.EntraRBAC -Parameters @{ Status = $Status } {
            param($Status)
            $Answer = Test-OERScheduleRequestFailed -Status $Status
            $Answer | Should -BeOfType ([bool])
            $Answer | Should -BeTrue
        }
    }

    It 'answers $false for status <Label>' -ForEach @(
        @{ Label = 'Revoked'; Status = 'Revoked' }
        @{ Label = 'Provisioned'; Status = 'Provisioned' }
        @{ Label = 'Granted'; Status = 'Granted' }
        @{ Label = 'PendingApproval'; Status = 'PendingApproval' }
        @{ Label = 'PendingProvisioning'; Status = 'PendingProvisioning' }
        @{ Label = 'Canceled'; Status = 'Canceled' }
        @{ Label = 'Denied'; Status = 'Denied' }
        @{ Label = 'AdminDenied'; Status = 'AdminDenied' }
        @{ Label = 'TimedOut'; Status = 'TimedOut' }
        @{ Label = 'Invalid'; Status = 'Invalid' }
        @{ Label = 'ScheduleCreated'; Status = 'ScheduleCreated' }
        @{ Label = 'NotFailed'; Status = 'NotFailed' }
        @{ Label = "' Failed' (a leading space)"; Status = ' Failed' }
        @{ Label = 'an empty string'; Status = '' }
        @{ Label = '$null'; Status = $null }
    ) {
        InModuleScope Omnicit.EntraRBAC -Parameters @{ Status = $Status } {
            param($Status)
            $Answer = Test-OERScheduleRequestFailed -Status $Status
            $Answer | Should -BeOfType ([bool])
            $Answer | Should -BeFalse
        }
    }
}

Describe 'Test-OERScheduleRequestFailed cohort: the single owner of the Failed-status rule (BL-33)' -ForEach @(
    @{ Cohort = $script:ScheduleRequestCohort; KnownSenders = $script:ScheduleRequestKnownSenders }
) {
    # Static: the source files are read and parsed, nothing in them runs. The derived cohort and the
    # known-senders control come in as this block's data, so the run phase sees the same sets that
    # discovery expanded.
    BeforeAll {
        $script:SourceRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '../../../source')).Path
        $script:OwnerFile = Join-Path $script:SourceRoot 'Private/Test-OERScheduleRequestFailed.ps1'
        # A status-named operand compared with a 'Failed...' literal, in either order. The forward
        # form is the shape of the three comparisons the owner replaced; the reversed form catches the
        # same comparison written the other way round.
        $script:FailedComparisonPatterns = @(
            '(?i)status\W*\s*-(c|i)?(eq|ne|like|notlike|match|notmatch)\s+[''"]Failed'
            '(?i)[''"]Failed\w*\*?[''"]\s*-(c|i)?(eq|ne|like|notlike|match|notmatch)\s+\S*status'
        )
        # Each hit as 'line N: text', so a failure names the place to change.
        function Get-TestFailedComparison ([string]$Text) {
            foreach ($Pattern in $script:FailedComparisonPatterns) {
                foreach ($Match in [regex]::Matches($Text, $Pattern)) {
                    'line {0}: {1}' -f @($Text.Substring(0, $Match.Index) -split "`n").Count, $Match.Value
                }
            }
        }
    }

    It 'derives at least the twelve senders known when the rule was written, all of them' {
        # The control for the derivation in BeforeDiscovery: a pattern that stopped matching, or a
        # path moved into a helper, would shrink the cohort, and every check below would stay green
        # on the smaller set. A thirteenth sender raises the count and fails nothing here.
        $Missing = @($KnownSenders | Where-Object { $_ -notin @($Cohort) })
        $Missing | Should -BeNullOrEmpty -Because 'every cmdlet the rule was written for must still be found by the derivation'
        @($Cohort).Count | Should -BeGreaterOrEqual 12
    }

    It '<_> asks Test-OERScheduleRequestFailed whether the answer is a failure' -ForEach $Cohort {
        $File = Join-Path $script:SourceRoot "Public/$_.ps1"
        Test-Path -LiteralPath $File | Should -BeTrue
        $Tokens = $null
        $ParseErrors = $null
        $Ast = [System.Management.Automation.Language.Parser]::ParseFile($File, [ref]$Tokens, [ref]$ParseErrors)
        @($ParseErrors).Count | Should -Be 0
        $Calls = @($Ast.FindAll({
                    param($Node)
                    $Node -is [System.Management.Automation.Language.CommandAst] -and
                    $Node.GetCommandName() -eq 'Test-OERScheduleRequestFailed'
                }, $true))
        $Calls.Count | Should -BeGreaterThan 0
    }

    It 'the patterns are not inert: they find the owner''s own comparison' {
        # The positive reach proof for the negative assertion below: the very patterns that must find
        # nothing elsewhere do find the one comparison the owner is allowed to hold.
        @(Get-TestFailedComparison -Text (Get-Content -LiteralPath $script:OwnerFile -Raw)).Count | Should -BeGreaterThan 0
        @(Get-TestFailedComparison -Text "if ([string]`$_.Status -eq 'Failed') { }").Count | Should -Be 1
        @(Get-TestFailedComparison -Text "if ('Failed' -eq `$Request.Status) { }").Count | Should -Be 1
    }

    It 'no file under source/ other than the owner compares a status with a Failed literal' {
        $Files = @(Get-ChildItem -LiteralPath $script:SourceRoot -Recurse -File |
                Where-Object { $_.FullName -ne (Get-Item -LiteralPath $script:OwnerFile).FullName })
        # The scan reaches the tree: every cohort file is among the files read.
        $Files.Count | Should -BeGreaterThan 100
        foreach ($Name in $Cohort) {
            @($Files | Where-Object { $_.Name -eq "$Name.ps1" }).Count | Should -Be 1
        }
        $Found = @(foreach ($File in $Files) {
                foreach ($Hit in (Get-TestFailedComparison -Text (Get-Content -LiteralPath $File.FullName -Raw))) {
                    '{0}: {1}' -f $File.FullName.Substring($script:SourceRoot.Length + 1), $Hit
                }
            })
        $Found | Should -BeNullOrEmpty -Because 'Test-OERScheduleRequestFailed is the single owner of the rule; ask it instead'
    }
}
