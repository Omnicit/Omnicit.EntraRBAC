BeforeDiscovery {
    # The twelve cmdlets that send a PIM schedule request and emit its answer (BL-33). Each must ask
    # the owner whether the answer is a failure; a thirteenth joins this list.
    $script:ScheduleRequestCohort = @(
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
    @{ Cohort = $script:ScheduleRequestCohort }
) {
    # Static: the source files are read and parsed, nothing in them runs. The cohort list comes in as
    # this block's data, so the run phase sees the same list that discovery expanded.
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

    It 'lists the twelve cmdlets of the cohort' {
        @($Cohort).Count | Should -Be 12
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
