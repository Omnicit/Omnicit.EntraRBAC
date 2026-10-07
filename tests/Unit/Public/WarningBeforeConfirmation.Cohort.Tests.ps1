# Cross-cmdlet suite, named after no single function. Do NOT delete it as an orphan when auditing the
# one-test-file-per-function invariant.
#
# What it holds (BL-18, rule A4): a public cmdlet's warning about a deletion or about widened access is
# written BEFORE the cmdlet's own $PSCmdlet.ShouldProcess, so -WhatIf shows it and a -Confirm prompt is
# answered with it on screen. Emitted inside the gate, such a warning printed only once the operator had
# already answered, and never under -WhatIf -- a warning seen only after committing is not a guard.
#
#   A. The AST rule over every source/Public/*.ps1 file: no Write-Warning may START after the file's
#      first $PSCmdlet.ShouldProcess call, except a named OUTCOME warning (one that reports what the
#      action did, or depends on what the operator confirmed, and so cannot be known before the
#      prompt), each listed below with its reason. Stricter than "not inside the if body": it also
#      catches $Proceed = $PSCmdlet.ShouldProcess(...) followed by if ($Proceed) { Write-Warning ... }
#      and an early if (-not $PSCmdlet.ShouldProcess(...)) { return }. Known-answer tests run the same
#      checker on fixture text, and an allowlist entry that matches no warning or more than one fails.
#   B. The positive roster: the twenty cmdlets that warn before their gate -- the four that always did
#      and the sixteen moved by BL-18 -- each still have that warning before their first
#      ShouldProcess, pinned by name and count, so a DELETED warning is caught, not only a moved one.
#   C. A runtime proof per moved warning (seventeen), in a second runspace whose host records the order
#      of warnings, 'What if:' lines and prompts (tests/Unit/TestHelpers/OERConfirmHost.ps1): under
#      -WhatIf the warning comes before the 'What if:' line, under -Confirm answered No it comes before
#      the prompt, its text is exact, and no write request is sent in either.
#
# Parts A and B read source files with the AST and import nothing. Unset, OER_COHORT_SOURCE_ROOT leaves
# them on the repository's own source/; a mutation proof sets it to a scratch copy of source/ so they
# read the mutated tree. It is never set in CI. Part C imports the module, so this file installs the
# transport tripwire.

BeforeDiscovery {
    # Part B roster: one row per warning that must stand before the cmdlet's first ShouldProcess. The
    # fragment is a distinctive piece of the Write-Warning command's SOURCE text (the extent, variables
    # unexpanded). Invoke-OERAccessReviewInstanceDecision carries two (reset and apply), so the twenty
    # cmdlets give twenty-one rows.
    $script:Roster = @(
        # The four that warned before their gate already.
        @{ Cmdlet = 'Remove-OERGroup'; Fragment = "Deleting Entra ID group '`$GroupId'" }
        @{ Cmdlet = 'Remove-OERAdministrativeUnit'; Fragment = "Deleting Entra ID administrative unit '`$AuId'" }
        @{ Cmdlet = 'Remove-OERAccessReviewDefinition'; Fragment = "Deleting access review definition '`$DefinitionId'" }
        @{ Cmdlet = 'Remove-OERAccessPackageAssignmentPolicy'; Fragment = "Deleting assignment policy '`$Id'" }
        # The sixteen moved by BL-18 (seventeen warnings).
        @{ Cmdlet = 'Disable-OEREligibleRoleAssignment'; Fragment = 'Deactivating $Target.' }
        @{ Cmdlet = 'Invoke-OERAccessReviewInstanceDecision'; Fragment = "Resetting decisions on access review instance '`$Instance'" }
        @{ Cmdlet = 'Invoke-OERAccessReviewInstanceDecision'; Fragment = "Applying decisions on access review instance '`$Instance'" }
        @{ Cmdlet = 'Remove-OERAccessPackage'; Fragment = "Deleting access package '`$PackageId'" }
        @{ Cmdlet = 'Remove-OERAccessPackageAssignment'; Fragment = "Revoking access package assignment '`$AssignmentId'" }
        @{ Cmdlet = 'Remove-OERActiveDirectoryRoleAssignment'; Fragment = 'Removing $Target.' }
        @{ Cmdlet = 'Remove-OERActiveRoleAssignment'; Fragment = 'Removing $Target.' }
        @{ Cmdlet = 'Remove-OERAdministrativeUnitScopedRole'; Fragment = "Removing scoped role membership '`$MembershipId'" }
        @{ Cmdlet = 'Remove-OERCatalog'; Fragment = "Deleting catalog '`$CatalogId'" }
        @{ Cmdlet = 'Remove-OEREligibleDirectoryRoleAssignment'; Fragment = 'Removing $Target.' }
        @{ Cmdlet = 'Remove-OEREligibleRoleAssignment'; Fragment = 'Removing $Target.' }
        @{ Cmdlet = 'Remove-OERGroupEligibility'; Fragment = 'Removing PIM $AccessType eligibility' }
        @{ Cmdlet = 'Remove-OERResourceGroup'; Fragment = "Deleting resource group '`$Name'" }
        @{ Cmdlet = 'Remove-OERRoleAssignment'; Fragment = "Deleting Azure role assignment '`$Id'" }
        @{ Cmdlet = 'Set-OERAdministrativeUnit'; Fragment = 'Changing the membership type of administrative unit' }
        @{ Cmdlet = 'Set-OERRoleAssignment'; Fragment = 'Removing the ABAC condition from role assignment' }
        @{ Cmdlet = 'Stop-OERAccessReviewInstance'; Fragment = "Stopping access review instance '`$Instance'" }
    )

    # Part C cases: one per moved warning. Every id is a GUID-shaped fixture that is NOT version-4
    # shaped, so the cmdlet's own resolvers short-circuit and nothing is looked up.
    $Principal = '11111111-1111-1111-1111-111111111111'
    $Object = '22222222-2222-2222-2222-222222222222'
    $Scope = '/subscriptions/33333333-3333-3333-3333-333333333333'
    $RoleAssignmentId = "$Scope/providers/Microsoft.Authorization/roleAssignments/$Object"
    $script:RuntimeCases = @(
        @{
            Cmdlet     = 'Disable-OEREligibleRoleAssignment'
            Invocation = "Disable-OEREligibleRoleAssignment -Role '$Object' -PrincipalId '$Principal' -Scope '$Scope'"
            Warning    = "Deactivating active assignment of role '$Object' for principal '$Principal' at scope '$Scope'."
        }
        @{
            Cmdlet     = 'Invoke-OERAccessReviewInstanceDecision (Reset)'
            Invocation = "Invoke-OERAccessReviewInstanceDecision -Definition '$Object' -Instance 'instance-1' -Reset"
            Warning    = "Resetting decisions on access review instance 'instance-1'. Every recorded reviewer decision is discarded irreversibly and cannot be recovered."
        }
        @{
            Cmdlet     = 'Invoke-OERAccessReviewInstanceDecision (Apply)'
            Invocation = "Invoke-OERAccessReviewInstanceDecision -Definition '$Object' -Instance 'instance-1'"
            Warning    = "Applying decisions on access review instance 'instance-1'. This commits the recorded access revocations."
        }
        @{
            Cmdlet     = 'Remove-OERAccessPackage'
            Invocation = "Remove-OERAccessPackage -Id '$Object'"
            Warning    = "Deleting access package '$Object'. This is irreversible."
        }
        @{
            Cmdlet     = 'Remove-OERAccessPackageAssignment'
            Invocation = "Remove-OERAccessPackageAssignment -AssignmentId '$Object'"
            Warning    = "Revoking access package assignment '$Object'."
        }
        @{
            Cmdlet     = 'Remove-OERActiveDirectoryRoleAssignment'
            Invocation = "Remove-OERActiveDirectoryRoleAssignment -Role '$Object' -PrincipalId '$Principal'"
            Warning    = "Removing active directory role '$Object' for principal '$Principal' at directory scope '/'."
        }
        @{
            Cmdlet     = 'Remove-OERActiveRoleAssignment'
            Invocation = "Remove-OERActiveRoleAssignment -Role '$Object' -PrincipalId '$Principal' -Scope '$Scope'"
            Warning    = "Removing active assignment of role '$Object' for principal '$Principal' at scope '$Scope'."
        }
        @{
            Cmdlet     = 'Remove-OERAdministrativeUnitScopedRole'
            Invocation = "Remove-OERAdministrativeUnitScopedRole -AdministrativeUnit '$Object' -ScopedRoleMembershipId 'membership-1'"
            Warning    = "Removing scoped role membership 'membership-1' from administrative unit '$Object'. This revokes the principal's delegated administrator privilege over that unit."
        }
        @{
            Cmdlet     = 'Remove-OERCatalog'
            Invocation = "Remove-OERCatalog -Id '$Object'"
            Warning    = "Deleting catalog '$Object'. This is irreversible and removes the catalog container."
        }
        @{
            Cmdlet     = 'Remove-OEREligibleDirectoryRoleAssignment'
            Invocation = "Remove-OEREligibleDirectoryRoleAssignment -Role '$Object' -PrincipalId '$Principal'"
            Warning    = "Removing eligible directory role '$Object' for principal '$Principal' at directory scope '/'."
        }
        @{
            Cmdlet     = 'Remove-OEREligibleRoleAssignment'
            Invocation = "Remove-OEREligibleRoleAssignment -Role '$Object' -PrincipalId '$Principal' -Scope '$Scope'"
            Warning    = "Removing eligible role '$Object' for principal '$Principal' at scope '$Scope'."
        }
        @{
            Cmdlet     = 'Remove-OERGroupEligibility'
            Invocation = "Remove-OERGroupEligibility -Group '$Object' -PrincipalId '$Principal'"
            Warning    = "Removing PIM member eligibility for principal '$Principal' from group '$Object'. The principal loses the ability to activate this member access."
        }
        @{
            Cmdlet     = 'Remove-OERResourceGroup'
            Invocation = "Remove-OERResourceGroup -Subscription '33333333-3333-3333-3333-333333333333' -Name 'rg-cohort'"
            Warning    = "Deleting resource group 'rg-cohort' permanently deletes ALL resources it contains."
        }
        @{
            Cmdlet     = 'Remove-OERRoleAssignment'
            Invocation = "Remove-OERRoleAssignment -Id '$RoleAssignmentId'"
            Warning    = "Deleting Azure role assignment '$RoleAssignmentId'. This removes the principal's access at that scope."
        }
        @{
            Cmdlet     = 'Set-OERAdministrativeUnit'
            Invocation = "Set-OERAdministrativeUnit -AdministrativeUnit '$Object' -MembershipType 'Assigned'"
            Warning    = "Changing the membership type of administrative unit '$Object' to 'Assigned'. The unit's existing membership can change as a result; on a Dynamic unit the membership rule owns the membership and members can no longer be added or removed manually."
        }
        @{
            # The live read (a GET, answered by the fake below with a condition) runs before the gate.
            Cmdlet     = 'Set-OERRoleAssignment'
            Invocation = "Set-OERRoleAssignment -Id '$RoleAssignmentId' -Condition ''"
            Warning    = "Removing the ABAC condition from role assignment '$RoleAssignmentId'. This WIDENS the principal's access at that scope."
        }
        @{
            Cmdlet     = 'Stop-OERAccessReviewInstance'
            Invocation = "Stop-OERAccessReviewInstance -Definition '$Object' -Instance 'instance-1'"
            Warning    = "Stopping access review instance 'instance-1'. An instance cannot be restarted once stopped."
        }
    )
}

BeforeAll {
    Import-Module Omnicit.EntraRBAC -Force
    . "$PSScriptRoot/../TestHelpers/OERTransportTripwire.ps1"
    Install-OERTransportTripwire
    . "$PSScriptRoot/../TestHelpers/OERConfirmHost.ps1"

    $script:CohortSourceRoot = if ($env:OER_COHORT_SOURCE_ROOT) {
        $env:OER_COHORT_SOURCE_ROOT
    } else {
        Join-Path -Path $PSScriptRoot -ChildPath '../../../source'
    }
    if ($env:OER_COHORT_SOURCE_ROOT) {
        Write-Host "OER_COHORT_SOURCE_ROOT is set: parts A and B scan $env:OER_COHORT_SOURCE_ROOT instead of the repository source."
    }

    # Part A allowlist: the OUTCOME warnings that may stand after a cmdlet's first ShouldProcess. Each
    # entry names its file, a distinctive fragment of the Write-Warning command's source text, and why
    # it cannot be written before the prompt. An entry must match exactly one such warning.
    $script:OutcomeAllowlist = @(
        @{
            File     = 'Add-OERCatalogResource.ps1'
            Fragment = 'but reading it back failed'
            Reason   = 'Reports that the read-back after the onboarding failed; it exists only once the add has run.'
        }
        @{
            File     = 'Export-OERInventory.ps1'
            Fragment = 'did not pass apply-schema validation'
            Reason   = 'The apply-schema self-check of the bundle just written; it exists only once the write has run.'
        }
        @{
            File     = 'Export-OERInventory.ps1'
            Fragment = 'Could not run the apply-schema self-check'
            Reason   = 'The self-check of the bundle just written could not run; it exists only once the write has run.'
        }
        @{
            File     = 'Remove-OERActiveDirectoryRoleAssignment.ps1'
            Fragment = 'but the principal still holds the role'
            Reason   = 'Reports the outcome of the removal: done, but the principal still holds the role another way.'
        }
        @{
            File     = 'Remove-OEREligibleDirectoryRoleAssignment.ps1'
            Fragment = 'but the principal still holds the role'
            Reason   = 'Reports the outcome of the removal: done, but the principal is still eligible another way.'
        }
        @{
            File     = 'Set-OERDirectoryRoleManagementPolicy.ps1'
            Fragment = 'Write-Warning $Message'
            Reason   = 'The send messages Send-OERPimRulePatch returns, written after the last request so a -WarningAction Stop caller is never stopped half-way.'
        }
        @{
            File     = 'Set-OERGroupPimPolicy.ps1'
            Fragment = 'Could not read the live rule'
            Reason   = 'Depends on which rules the operator confirmed: the live partner rule is read only for a pair that will be sent.'
        }
        @{
            File     = 'Set-OERGroupPimPolicy.ps1'
            Fragment = 'Write-Warning $Message'
            Reason   = 'The send messages Send-OERPimRulePatch returns, written after the last request so a -WarningAction Stop caller is never stopped half-way.'
        }
        @{
            File     = 'Set-OERGroupPimPolicy.ps1'
            Fragment = 'was declined while'
            Reason   = 'Reports a partner rule the operator declined at the prompt while the other rule was applied.'
        }
    )

    function Get-WarningGateScan {
        <#
        .SYNOPSIS
        Reads one script's text with the AST and reports its Write-Warning commands against its first
        $PSCmdlet.ShouldProcess call.
        .DESCRIPTION
        Finds the first InvokeMemberExpressionAst on the variable PSCmdlet with member ShouldProcess (by
        start offset). Every Write-Warning command is Before when its extent starts before that call's
        start and After otherwise; with no such call, every warning is Before. An After warning is a
        Violation unless its source text contains the Fragment of an allowlist entry for this File. An
        allowlist entry for this File that is contained in no After warning, or in more than one, is an
        AllowlistProblem (stale or ambiguous).
        #>
        param(
            [Parameter(Mandatory)]
            [string]$Text,

            [Parameter(Mandatory)]
            [string]$File,

            [object[]]$Allowlist = @()
        )
        $Tokens = $null
        $Errors = $null
        $Ast = [System.Management.Automation.Language.Parser]::ParseInput($Text, [ref]$Tokens, [ref]$Errors)
        $Gate = @($Ast.FindAll({
                    param($Node)
                    $Node -is [System.Management.Automation.Language.InvokeMemberExpressionAst] -and
                    $Node.Expression -is [System.Management.Automation.Language.VariableExpressionAst] -and
                    $Node.Expression.VariablePath.UserPath -eq 'PSCmdlet' -and
                    $Node.Member -is [System.Management.Automation.Language.StringConstantExpressionAst] -and
                    $Node.Member.Value -eq 'ShouldProcess'
                }, $true) | Sort-Object -Property { $_.Extent.StartOffset })[0]
        $Warnings = @($Ast.FindAll({
                    param($Node)
                    $Node -is [System.Management.Automation.Language.CommandAst] -and
                    ($Node.GetCommandName() -eq 'Write-Warning' -or $Node.GetCommandName() -like '*\Write-Warning')
                }, $true) | Sort-Object -Property { $_.Extent.StartOffset })
        $Before = [System.Collections.Generic.List[object]]::new()
        $After = [System.Collections.Generic.List[object]]::new()
        foreach ($Warning in $Warnings) {
            $Row = [PSCustomObject]@{ Line = $Warning.Extent.StartLineNumber; Text = $Warning.Extent.Text }
            if ($Gate -and $Warning.Extent.StartOffset -gt $Gate.Extent.StartOffset) { $After.Add($Row) } else { $Before.Add($Row) }
        }
        $Entries = @($Allowlist | Where-Object { $_.File -eq $File })
        $Violations = [System.Collections.Generic.List[string]]::new()
        foreach ($Row in $After) {
            $Allowed = @($Entries | Where-Object { $Row.Text.Contains([string]$_.Fragment) }).Count -gt 0
            if (-not $Allowed) { $Violations.Add(('{0}:{1}: {2}' -f $File, $Row.Line, $Row.Text)) }
        }
        $Problems = [System.Collections.Generic.List[string]]::new()
        foreach ($Entry in $Entries) {
            $Hits = @($After | Where-Object { $_.Text.Contains([string]$Entry.Fragment) }).Count
            if ($Hits -eq 0) { $Problems.Add(("{0}: allowlist fragment '{1}' matches no warning after the first ShouldProcess (stale)" -f $File, $Entry.Fragment)) }
            if ($Hits -gt 1) { $Problems.Add(("{0}: allowlist fragment '{1}' matches {2} warnings after the first ShouldProcess (ambiguous)" -f $File, $Entry.Fragment, $Hits)) }
        }
        [PSCustomObject]@{
            File              = $File
            GateLine          = if ($Gate) { $Gate.Extent.StartLineNumber } else { $null }
            Before            = @($Before)
            After             = @($After)
            Violations        = @($Violations)
            AllowlistProblems = @($Problems)
        }
    }

    function Get-PublicSourceFile {
        Get-ChildItem -Path (Join-Path -Path $script:CohortSourceRoot -ChildPath 'Public') -Filter '*.ps1' -File | Sort-Object -Property Name
    }

    # Part C scenario: the module is imported in the answering runspace, Initialize-OERAuth and both
    # transports are replaced in THAT runspace's copy of the module (Pester mocks do not cross a
    # runspace), and every transport call is recorded. The ARM fake answers a GET with a role
    # assignment that carries a condition, for Set-OERRoleAssignment's live read. The invocation runs
    # once with -WhatIf and once with -Confirm (answered No by the host); a host line between the two
    # splits the ordered events by phase.
    function New-WarningGateScenario {
        param([Parameter(Mandatory)][string]$Invocation)
        $Text = @'
Import-Module Omnicit.EntraRBAC -Force -ErrorAction Stop
$Module = Get-Module Omnicit.EntraRBAC
& $Module {
    $script:CohortCalls = [System.Collections.Generic.List[string]]::new()
    Set-Item -Path function:script:Initialize-OERAuth -Value { }
    Set-Item -Path function:script:Invoke-OERGraphRequest -Value {
        param([string]$Method = 'GET', [string]$Uri, $Body)
        $script:CohortCalls.Add("GRAPH $Method $Uri")
    }
    Set-Item -Path function:script:Invoke-OERArmRequest -Value {
        param([string]$Method = 'GET', [string]$Path, $Body)
        $script:CohortCalls.Add("ARM $Method $Path")
        if ($Method -eq 'GET') {
            [pscustomobject]@{
                id         = '/subscriptions/33333333-3333-3333-3333-333333333333/providers/Microsoft.Authorization/roleAssignments/22222222-2222-2222-2222-222222222222'
                properties = [pscustomobject]@{
                    roleDefinitionId = '/subscriptions/33333333-3333-3333-3333-333333333333/providers/Microsoft.Authorization/roleDefinitions/22222222-2222-2222-2222-222222222222'
                    principalId      = '11111111-1111-1111-1111-111111111111'
                    principalType    = 'User'
                    condition        = "@Resource[Microsoft.Storage/storageAccounts/blobServices/containers:name] StringEquals 'cohort'"
                    conditionVersion = '2.0'
                }
            }
        }
    }
}
$Host.UI.WriteLine('PHASE: WhatIf')
#INVOCATION# -WhatIf
"WHATIF-CALLS:$(& $Module { @($script:CohortCalls) -join ';' })"
& $Module { $script:CohortCalls.Clear() }
$Host.UI.WriteLine('PHASE: Confirm')
#INVOCATION# -Confirm
"CONFIRM-CALLS:$(& $Module { @($script:CohortCalls) -join ';' })"
'END'
'@
        [scriptblock]::Create($Text.Replace('#INVOCATION#', $Invocation))
    }

    # The events of one phase: from that phase's marker line to the next marker (or the end).
    function Get-PhaseEvent {
        param([string[]]$Events, [Parameter(Mandatory)][string]$Phase)
        $Start = [array]::IndexOf($Events, "Line: PHASE: $Phase")
        if ($Start -lt 0) { return }
        for ($Index = $Start + 1; $Index -lt $Events.Count; $Index++) {
            if ($Events[$Index] -like 'Line: PHASE: *') { break }
            $Events[$Index]
        }
    }
}

AfterAll {
    try { Assert-OERTransportTripwire } finally { Uninstall-OERTransportTripwire }
}

Describe 'Warnings before the confirmation gate: the checker (known answers)' {
    It 'flags a warning inside the ShouldProcess if body' {
        $Text = @'
function Remove-Fixture {
    [CmdletBinding(SupportsShouldProcess)]
    param()
    if ($PSCmdlet.ShouldProcess('target', 'action')) {
        Write-Warning 'Deleting the fixture.'
    }
}
'@
        $Scan = Get-WarningGateScan -Text $Text -File 'Fixture.ps1'
        $Scan.GateLine | Should -Be 4
        @($Scan.Violations).Count | Should -Be 1
        $Scan.Violations[0] | Should -BeExactly "Fixture.ps1:5: Write-Warning 'Deleting the fixture.'"
    }

    It 'flags the $Proceed form: the gate assigned to a variable, the warning under if ($Proceed)' {
        $Text = @'
function Remove-Fixture {
    [CmdletBinding(SupportsShouldProcess)]
    param()
    $Proceed = $PSCmdlet.ShouldProcess('target', 'action')
    if ($Proceed) { Write-Warning 'Deleting the fixture.' }
}
'@
        $Scan = Get-WarningGateScan -Text $Text -File 'Fixture.ps1'
        $Scan.GateLine | Should -Be 4
        @($Scan.Violations).Count | Should -Be 1
    }

    It 'flags a warning after an early negated-gate return' {
        $Text = @'
function Remove-Fixture {
    [CmdletBinding(SupportsShouldProcess)]
    param()
    if (-not $PSCmdlet.ShouldProcess('target', 'action')) { return }
    Write-Warning 'Deleting the fixture.'
}
'@
        $Scan = Get-WarningGateScan -Text $Text -File 'Fixture.ps1'
        @($Scan.Violations).Count | Should -Be 1
        $Scan.Violations[0] | Should -BeLike 'Fixture.ps1:5: *'
    }

    It 'passes a warning written before the gate, and counts it as Before' {
        $Text = @'
function Remove-Fixture {
    [CmdletBinding(SupportsShouldProcess)]
    param()
    Write-Warning 'Deleting the fixture.'
    if ($PSCmdlet.ShouldProcess('target', 'action')) { 'deleted' }
}
'@
        $Scan = Get-WarningGateScan -Text $Text -File 'Fixture.ps1'
        @($Scan.Violations).Count | Should -Be 0
        @($Scan.Before).Count | Should -Be 1
        @($Scan.After).Count | Should -Be 0
    }

    It 'passes a file with no ShouldProcess at all, every warning counted as Before' {
        $Text = @'
function Get-Fixture {
    [CmdletBinding()]
    param()
    Write-Warning 'Could not read the fixture.'
}
'@
        $Scan = Get-WarningGateScan -Text $Text -File 'Fixture.ps1'
        $Scan.GateLine | Should -BeNullOrEmpty
        @($Scan.Violations).Count | Should -Be 0
        @($Scan.Before).Count | Should -Be 1
    }

    It 'passes an allowlisted outcome warning after the gate, and reports no allowlist problem' {
        $Text = @'
function Remove-Fixture {
    [CmdletBinding(SupportsShouldProcess)]
    param()
    if ($PSCmdlet.ShouldProcess('target', 'action')) {
        Write-Warning 'Removed the fixture, but an outcome remains.'
    }
}
'@
        $Allow = @(@{ File = 'Fixture.ps1'; Fragment = 'but an outcome remains'; Reason = 'known answer' })
        $Scan = Get-WarningGateScan -Text $Text -File 'Fixture.ps1' -Allowlist $Allow
        @($Scan.After).Count | Should -Be 1
        @($Scan.Violations).Count | Should -Be 0
        @($Scan.AllowlistProblems).Count | Should -Be 0
    }

    It 'reports an allowlist entry that matches no warning after the gate as stale' {
        $Text = @'
function Remove-Fixture {
    [CmdletBinding(SupportsShouldProcess)]
    param()
    Write-Warning 'Removed the fixture, but an outcome remains.'
    if ($PSCmdlet.ShouldProcess('target', 'action')) { 'removed' }
}
'@
        $Allow = @(@{ File = 'Fixture.ps1'; Fragment = 'but an outcome remains'; Reason = 'known answer' })
        $Scan = Get-WarningGateScan -Text $Text -File 'Fixture.ps1' -Allowlist $Allow
        @($Scan.AllowlistProblems).Count | Should -Be 1
        $Scan.AllowlistProblems[0] | Should -BeLike '*(stale)'
    }

    It 'reports an allowlist entry that matches two warnings after the gate as ambiguous' {
        $Text = @'
function Remove-Fixture {
    [CmdletBinding(SupportsShouldProcess)]
    param()
    if ($PSCmdlet.ShouldProcess('target', 'action')) {
        Write-Warning 'First, but an outcome remains.'
        Write-Warning 'Second, but an outcome remains.'
    }
}
'@
        $Allow = @(@{ File = 'Fixture.ps1'; Fragment = 'but an outcome remains'; Reason = 'known answer' })
        $Scan = Get-WarningGateScan -Text $Text -File 'Fixture.ps1' -Allowlist $Allow
        @($Scan.AllowlistProblems).Count | Should -Be 1
        $Scan.AllowlistProblems[0] | Should -BeLike '*matches 2 warnings*(ambiguous)'
    }
}

Describe 'Warnings before the confirmation gate: every public cmdlet (A, BL-18)' {
    It 'discovers the 59 public cmdlets that call $PSCmdlet.ShouldProcess' {
        # A scan that silently finds no gate would pass while proving nothing; the exact count fails
        # loudly when a gated cmdlet is added or dropped.
        $Gated = @(Get-PublicSourceFile | Where-Object {
                $null -ne (Get-WarningGateScan -Text (Get-Content -Raw -LiteralPath $_.FullName) -File $_.Name).GateLine
            })
        $Gated.Count | Should -Be 59
    }

    It 'no public cmdlet writes a Write-Warning after its first $PSCmdlet.ShouldProcess, except the named outcome warnings' {
        $Violations = @(Get-PublicSourceFile | ForEach-Object {
                (Get-WarningGateScan -Text (Get-Content -Raw -LiteralPath $_.FullName) -File $_.Name -Allowlist $script:OutcomeAllowlist).Violations
            })
        ($Violations -join [Environment]::NewLine) | Should -BeExactly '' -Because (
            'a warning written inside or after the gate never shows under -WhatIf and shows under -Confirm only after the ' +
            'answer; move it ahead of the gate, or name it in the outcome allowlist with a reason')
    }

    It 'every outcome allowlist entry matches exactly one warning after its file''s first ShouldProcess' {
        $Problems = @(foreach ($FileName in @($script:OutcomeAllowlist | ForEach-Object { $_.File } | Sort-Object -Unique)) {
                $Path = Join-Path -Path (Join-Path -Path $script:CohortSourceRoot -ChildPath 'Public') -ChildPath $FileName
                if (-not (Test-Path -LiteralPath $Path)) { "${FileName}: no such public file"; continue }
                (Get-WarningGateScan -Text (Get-Content -Raw -LiteralPath $Path) -File $FileName -Allowlist $script:OutcomeAllowlist).AllowlistProblems
            })
        ($Problems -join [Environment]::NewLine) | Should -BeExactly ''
        @($script:OutcomeAllowlist).Count | Should -Be 9
    }
}

Describe 'Warnings before the confirmation gate: the roster of warning cmdlets (B, BL-18)' {
    It 'pins the roster at twenty cmdlets and twenty-one warnings, by name' -TestCases @(@{ Roster = $script:Roster }) {
        @($Roster).Count | Should -Be 21
        $Names = @($Roster | ForEach-Object { $_.Cmdlet } | Sort-Object -Unique)
        $Names.Count | Should -Be 20
        ($Names -join ',') | Should -BeExactly (@(
                'Disable-OEREligibleRoleAssignment'
                'Invoke-OERAccessReviewInstanceDecision'
                'Remove-OERAccessPackage'
                'Remove-OERAccessPackageAssignment'
                'Remove-OERAccessPackageAssignmentPolicy'
                'Remove-OERAccessReviewDefinition'
                'Remove-OERActiveDirectoryRoleAssignment'
                'Remove-OERActiveRoleAssignment'
                'Remove-OERAdministrativeUnit'
                'Remove-OERAdministrativeUnitScopedRole'
                'Remove-OERCatalog'
                'Remove-OEREligibleDirectoryRoleAssignment'
                'Remove-OEREligibleRoleAssignment'
                'Remove-OERGroup'
                'Remove-OERGroupEligibility'
                'Remove-OERResourceGroup'
                'Remove-OERRoleAssignment'
                'Set-OERAdministrativeUnit'
                'Set-OERRoleAssignment'
                'Stop-OERAccessReviewInstance'
            ) -join ',')
    }

    It '<Cmdlet> writes its "<Fragment>" warning before its first ShouldProcess' -ForEach $script:Roster {
        $Path = Join-Path -Path (Join-Path -Path $script:CohortSourceRoot -ChildPath 'Public') -ChildPath "$Cmdlet.ps1"
        $Scan = Get-WarningGateScan -Text (Get-Content -Raw -LiteralPath $Path) -File "$Cmdlet.ps1"
        $Scan.GateLine | Should -Not -BeNullOrEmpty
        @($Scan.Before | Where-Object { $_.Text.Contains($Fragment) }).Count | Should -Be 1 -Because (
            "the $Cmdlet warning must stand before its first ShouldProcess, so -WhatIf and the -Confirm prompt show it")
    }
}

Describe 'Warnings before the confirmation gate: -WhatIf and -Confirm show each moved warning first (C, BL-18)' {
    Context '<Cmdlet>' -ForEach $script:RuntimeCases {
        BeforeAll {
            $script:Run = Invoke-OERWithConfirmAnswer -Answer '&No' -Script (New-WarningGateScenario -Invocation $Invocation)
            $script:Expected = "Warning: $Warning"
        }

        It 'reaches the end of the scenario with no error' {
            @($script:Run.Output) | Should -Contain 'END'
            @($script:Run.Errors) | Should -BeNullOrEmpty
        }

        It 'under -WhatIf writes the warning before the What if: line, and sends no write request' {
            $Events = @(Get-PhaseEvent -Events $script:Run.Events -Phase 'WhatIf')
            $WhatIf = [array]::FindIndex([string[]]$Events, [Predicate[string]] { param($E) $E -like 'Line: What if: *' })
            $WhatIf | Should -BeGreaterOrEqual 0 -Because 'the cmdlet must reach its gate, so the missing warning below is not a cmdlet that stopped early'
            @($Events | Where-Object { $_ -ceq $script:Expected }).Count | Should -Be 1
            [array]::IndexOf([string[]]$Events, $script:Expected) | Should -BeLessThan $WhatIf
            $Calls = @(@($script:Run.Output | Where-Object { $_ -like 'WHATIF-CALLS:*' })[0].Substring(13) -split ';' | Where-Object { $_ })
            @($Calls | Where-Object { $_ -notmatch '^(GRAPH|ARM) GET ' }) | Should -BeNullOrEmpty
        }

        It 'under -Confirm answered No writes the warning before the prompt, and sends no write request' {
            $Events = @(Get-PhaseEvent -Events $script:Run.Events -Phase 'Confirm')
            $Prompt = [array]::FindIndex([string[]]$Events, [Predicate[string]] { param($E) $E -like 'Prompt: *' })
            $Prompt | Should -BeGreaterOrEqual 0 -Because 'the cmdlet must reach its prompt, so the missing warning below is not a cmdlet that stopped early'
            @($Events | Where-Object { $_ -ceq $script:Expected }).Count | Should -Be 1
            [array]::IndexOf([string[]]$Events, $script:Expected) | Should -BeLessThan $Prompt
            $Calls = @(@($script:Run.Output | Where-Object { $_ -like 'CONFIRM-CALLS:*' })[0].Substring(14) -split ';' | Where-Object { $_ })
            @($Calls | Where-Object { $_ -notmatch '^(GRAPH|ARM) GET ' }) | Should -BeNullOrEmpty
        }
    }
}
