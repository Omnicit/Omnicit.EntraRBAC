BeforeAll {
    $script:moduleName = 'Omnicit.EntraRBAC'
    Get-Module $script:moduleName | Remove-Module -Force -ErrorAction SilentlyContinue
    Import-Module $script:moduleName -Force -ErrorAction Stop
    . "$PSScriptRoot/../TestHelpers/OERTransportTripwire.ps1"
    Install-OERTransportTripwire
}

AfterAll {
    try { Assert-OERTransportTripwire } finally { Uninstall-OERTransportTripwire }
}

Describe 'Resolve-OERStructureEnumCasing' {
    It 'returns the canonical spelling for a value that already matches' {
        InModuleScope $script:moduleName {
            Resolve-OERStructureEnumCasing -EnumName 'accessType' -Value 'member' | Should -Be 'member'
            Resolve-OERStructureEnumCasing -EnumName 'principalType' -Value 'ServicePrincipal' | Should -Be 'ServicePrincipal'
        }
    }

    It 'maps a differently cased value onto the canonical spelling' {
        InModuleScope $script:moduleName {
            Resolve-OERStructureEnumCasing -EnumName 'accessType' -Value 'Member' | Should -Be 'member'
            Resolve-OERStructureEnumCasing -EnumName 'accessType' -Value 'OWNER' | Should -Be 'owner'
            Resolve-OERStructureEnumCasing -EnumName 'membershipRuleProcessingState' -Value 'on' | Should -Be 'On'
            Resolve-OERStructureEnumCasing -EnumName 'catalogResourceType' -Value 'sharepointsite' | Should -Be 'SharePointSite'
            Resolve-OERStructureEnumCasing -EnumName 'enablement' -Value 'multifactorauthentication' | Should -Be 'MultiFactorAuthentication'
            Resolve-OERStructureEnumCasing -EnumName 'accessReviewRecurrence' -Value 'onetime' | Should -Be 'OneTime'
            Resolve-OERStructureEnumCasing -EnumName 'accessReviewRecurrence' -Value 'semiannually' | Should -BeExactly 'SemiAnnually'
            Resolve-OERStructureEnumCasing -EnumName 'accessReviewRecurrence' -Value 'SEMIANNUALLY' | Should -BeExactly 'SemiAnnually'
            Resolve-OERStructureEnumCasing -EnumName 'accessReviewDefaultDecision' -Value 'recommendation' | Should -Be 'Recommendation'
            Resolve-OERStructureEnumCasing -EnumName 'approverInfoVisibility' -Value 'notvisible' | Should -Be 'NotVisible'
            Resolve-OERStructureEnumCasing -EnumName 'directoryRoleAssignmentType' -Value 'eligible' | Should -BeExactly 'Eligible'
            Resolve-OERStructureEnumCasing -EnumName 'directoryRoleAssignmentType' -Value 'ACTIVE' | Should -BeExactly 'Active'
            Resolve-OERStructureEnumCasing -EnumName 'principalStatus' -Value 'deleted' | Should -BeExactly 'Deleted'
            Resolve-OERStructureEnumCasing -EnumName 'principalStatus' -Value 'UNRESOLVED' | Should -BeExactly 'Unresolved'
            Resolve-OERStructureEnumCasing -EnumName 'principalStatus' -Value 'Unresolved' | Should -BeExactly 'Unresolved'
        }
    }

    It 'returns null for a principalStatus that is not Deleted or Unresolved (A18)' {
        # A principal that is a live object, or any other word, is not a status the export writes.
        InModuleScope $script:moduleName {
            foreach ($Value in 'Gone', 'Active', 'Resolved', 'Delete', 'User') {
                $Result = Resolve-OERStructureEnumCasing -EnumName 'principalStatus' -Value $Value
                $null -eq $Result | Should -Be $true -Because "'$Value' is not a member of principalStatus"
            }
        }
    }

    It 'does not resolve an Activated or Assigned schedule type as a directory role assignment type' {
        # The document names the KIND of assignment (Eligible or Active); the schedule's own
        # Activated/Assigned type is a different vocabulary and must not slip into this enum.
        InModuleScope $script:moduleName {
            $null -eq (Resolve-OERStructureEnumCasing -EnumName 'directoryRoleAssignmentType' -Value 'Activated') | Should -Be $true
            $null -eq (Resolve-OERStructureEnumCasing -EnumName 'directoryRoleAssignmentType' -Value 'Assigned') | Should -Be $true
        }
    }

    It 'returns null for a value that is not a member of the enum' {
        InModuleScope $script:moduleName {
            $Result = Resolve-OERStructureEnumCasing -EnumName 'accessType' -Value 'guest'
            # Not Should -BeNullOrEmpty: an empty string would pass that and must not.
            $null -eq $Result | Should -Be $true
        }
    }

    It 'returns null for an empty or null value rather than throwing' {
        InModuleScope $script:moduleName {
            $null -eq (Resolve-OERStructureEnumCasing -EnumName 'accessType' -Value '') | Should -Be $true
            $null -eq (Resolve-OERStructureEnumCasing -EnumName 'accessType' -Value $null) | Should -Be $true
        }
    }

    It 'lists the canonical set for every enum it owns' {
        InModuleScope $script:moduleName {
            $Expected = @{
                accessType                    = @('member', 'owner')
                enablement                    = @('Justification', 'MultiFactorAuthentication', 'Ticketing')
                membershipRuleProcessingState = @('On', 'Paused')
                catalogResourceType           = @('Group', 'Application', 'SharePointSite')
                approverInfoVisibility        = @('Default', 'Visible', 'NotVisible')
                accessReviewRecurrence        = @('OneTime', 'Weekly', 'Monthly', 'Quarterly', 'SemiAnnually', 'Annually')
                accessReviewDefaultDecision   = @('None', 'Approve', 'Deny', 'Recommendation')
                principalType                 = @('User', 'Group', 'ServicePrincipal')
                directoryRoleAssignmentType   = @('Eligible', 'Active')
                principalStatus               = @('Deleted', 'Unresolved')
            }
            foreach ($Name in $Expected.Keys) {
                $Actual = @(Resolve-OERStructureEnumCasing -EnumName $Name -List)
                # -join makes both order and casing part of the assertion.
                ($Actual -join ',') | Should -BeExactly (($Expected[$Name]) -join ',') -Because "'$Name' is declared in Get-OERStructureSchemaJson in this order"
            }
        }
    }

    It 'rejects an enum name it does not own' {
        InModuleScope $script:moduleName {
            { Resolve-OERStructureEnumCasing -EnumName 'notAnEnum' -Value 'x' } | Should -Throw
        }
    }
}

Describe 'access review recurrence vocabulary cohort' {
    # Resolve-OERStructureEnumCasing owns the canonical recurrence set, but the same vocabulary is
    # spelled out by hand at five more sites that nothing else ties to it: the -Recurrence ValidateSet
    # of the private builder and of the two public definition cmdlets, the apply handler's
    # $ValidRecurrenceValues, and the cadence list the exported LLM prompt shows. The schema enum is
    # held beside them. A cadence added to one and not the others is accepted by validation and then
    # refused (or silently dropped) at write time, so each site is read straight out of the source
    # tree (the AST for the four code sites, the rendered text for the prompt and the schema) and
    # compared with the canonical list, order included. The [ValidateSet()] sites are DERIVED from
    # every .ps1 under source/ (BL-117), with the three named ones kept as a floor; the array literal,
    # the prompt and the schema are still read from their one known place.
    BeforeAll {
        # Three hops from tests/Unit/Private to the repository root. Forward slashes resolve on every OS.
        $script:cohortRepoRoot = (Resolve-Path -Path (Join-Path -Path $PSScriptRoot -ChildPath '../../..')).Path
        $script:cohortSourceRoot = Join-Path -Path $script:cohortRepoRoot -ChildPath 'source'

        function Read-CohortAst {
            param([string]$RelativePath)
            $Path = Join-Path -Path $script:cohortSourceRoot -ChildPath $RelativePath
            if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
                throw "cohort site '$RelativePath' does not exist under $script:cohortSourceRoot"
            }
            $Errors = $null
            $Ast = [System.Management.Automation.Language.Parser]::ParseFile($Path, [ref]$null, [ref]$Errors)
            if ($Errors -and $Errors.Count -gt 0) {
                throw "cohort site '$RelativePath' does not parse: $($Errors[0].Message)"
            }
            $Ast
        }

        # Every recurrence parameter under one source root, derived rather than listed by hand
        # (BL-117): each ParameterAst, in EVERY .ps1 file, that is named Recurrence OR carries a
        # [ValidateSet()] containing OneTime. All of them per file -- a file that declares two (a
        # second function or a nested scriptblock) is two sites, never "the first one". A site is
        # { File (relative, forward slashes); Parameter; Sets }, Sets holding one entry per
        # [ValidateSet()] attribute on it, each the comma-joined strings in declaration order.
        # A file that does not parse throws: a cohort that skips what it cannot read proves nothing.
        function Get-CohortRecurrenceSite {
            param([string]$SourceRoot)
            if (-not (Test-Path -LiteralPath $SourceRoot -PathType Container)) {
                throw "cohort source root '$SourceRoot' does not exist"
            }
            $Root = (Resolve-Path -LiteralPath $SourceRoot).Path
            foreach ($File in (Get-ChildItem -LiteralPath $Root -Filter '*.ps1' -Recurse -File | Sort-Object -Property FullName)) {
                # Cheap pre-filter: a file naming neither word cannot hold a site, and parsing every file
                # of the tree would cost seconds. The ParameterAst walk below is the decision.
                if ([System.IO.File]::ReadAllText($File.FullName) -notmatch 'Recurrence|OneTime') { continue }
                $Errors = $null
                $Ast = [System.Management.Automation.Language.Parser]::ParseFile($File.FullName, [ref]$null, [ref]$Errors)
                if ($Errors -and $Errors.Count -gt 0) {
                    throw "cohort file '$($File.FullName)' does not parse: $($Errors[0].Message)"
                }
                $Relative = [System.IO.Path]::GetRelativePath($Root, $File.FullName) -replace '\\', '/'
                $ParameterAsts = $Ast.FindAll({
                        param($Node)
                        $Node -is [System.Management.Automation.Language.ParameterAst]
                    }, $true)
                foreach ($ParameterAst in $ParameterAsts) {
                    $Sets = [System.Collections.Generic.List[string[]]]::new()
                    foreach ($Attribute in $ParameterAst.Attributes) {
                        if ($Attribute -isnot [System.Management.Automation.Language.AttributeAst] -or $Attribute.TypeName.Name -ne 'ValidateSet') { continue }
                        $Sets.Add([string[]]@($Attribute.PositionalArguments | ForEach-Object { [string]$_.SafeGetValue() }))
                    }
                    $Name = $ParameterAst.Name.VariablePath.UserPath
                    $HoldsOneTime = $false
                    foreach ($Set in $Sets) { if ($Set -ccontains 'OneTime') { $HoldsOneTime = $true } }
                    if ($Name -eq 'Recurrence' -or $HoldsOneTime) {
                        [PSCustomObject]@{ File = $Relative; Parameter = $Name; Sets = $Sets }
                    }
                }
            }
        }

        # The findings of the derived cohort, as text: a site without a [ValidateSet()], a set that is
        # not the canonical list in order, and a floor site (one of the three named ValidateSet sites)
        # the derivation did not find. An empty result with an empty derivation cannot happen: the floor
        # fails then. $Floor is a list of 'relative/path.ps1' entries naming a -Recurrence parameter.
        function Test-CohortRecurrenceSite {
            param([string]$SourceRoot, [string[]]$Canonical, [string[]]$Floor)
            $Sites = @(Get-CohortRecurrenceSite -SourceRoot $SourceRoot)
            $Problems = [System.Collections.Generic.List[string]]::new()
            foreach ($FloorFile in $Floor) {
                if (-not @($Sites | Where-Object { $_.File -ceq $FloorFile -and $_.Parameter -eq 'Recurrence' }).Count) {
                    $Problems.Add("floor site not found by the derivation: -Recurrence in '$FloorFile'")
                }
            }
            foreach ($Site in $Sites) {
                if ($Site.Sets.Count -eq 0) {
                    $Problems.Add("-$($Site.Parameter) in '$($Site.File)' carries no [ValidateSet()]")
                    continue
                }
                foreach ($Set in $Site.Sets) {
                    if (-not [string]::Equals(($Set -join ','), ($Canonical -join ','), [System.StringComparison]::Ordinal)) {
                        $Problems.Add("-$($Site.Parameter) in '$($Site.File)' lists '$($Set -join ',')' instead of '$($Canonical -join ',')'")
                    }
                }
            }
            # Elements, not a wrapped array: every caller wraps the call in @().
            $Problems.ToArray()
        }

        $script:cohortFloor = @(
            'Private/New-OERAccessReviewRecurrence.ps1'
            'Public/New-OERAccessReviewDefinition.ps1'
            'Public/Set-OERAccessReviewDefinition.ps1'
        )

        # The string elements of the array literal assigned to one variable, in order.
        function Get-CohortArrayLiteral {
            param([string]$RelativePath, [string]$VariableName)
            $Ast = Read-CohortAst -RelativePath $RelativePath
            $AssignAst = $Ast.FindAll({
                    param($Node)
                    $Node -is [System.Management.Automation.Language.AssignmentStatementAst] -and
                    $Node.Left -is [System.Management.Automation.Language.VariableExpressionAst] -and
                    $Node.Left.VariablePath.UserPath -eq $VariableName
                }, $true) | Select-Object -First 1
            if (-not $AssignAst) { throw "no assignment to `$$VariableName in '$RelativePath'" }
            $Values = @($AssignAst.Right.FindAll({
                        param($Node)
                        $Node -is [System.Management.Automation.Language.StringConstantExpressionAst]
                    }, $true) | ForEach-Object { $_.Value })
            if ($Values.Count -eq 0) { throw "`$$VariableName in '$RelativePath' holds no string literal" }
            $Values
        }

        # The cadence list the exported prompt shows after "recurrence (". Exactly one parenthesised
        # list may start with OneTime, so a second copy of the vocabulary cannot hide behind the first.
        function Get-CohortPromptList {
            $Text = InModuleScope $script:moduleName { Get-OERInventoryPromptTemplate }
            $Lists = @([regex]::Matches([string]$Text, 'recurrence\s*\(([^)]*)\)') | ForEach-Object {
                    , @($_.Groups[1].Value -split '\|' | ForEach-Object { $_.Trim() })
                } | Where-Object { $_ -contains 'OneTime' })
            if ($Lists.Count -ne 1) { throw "expected exactly one recurrence list in the prompt, found $($Lists.Count)" }
            $Lists[0]
        }

        function Get-CohortSchemaEnum {
            $Schema = InModuleScope $script:moduleName { Get-OERStructureSchemaJson } | ConvertFrom-Json
            @($Schema.properties.accessReviews.items.properties.recurrence.enum | Where-Object { $null -ne $_ })
        }
    }

    It 'reads the canonical set from the owner and finds SemiAnnually in it' {
        $Canonical = @(InModuleScope $script:moduleName { Resolve-OERStructureEnumCasing -EnumName 'accessReviewRecurrence' -List })
        $Canonical.Count | Should -Be 6
        $Canonical | Should -Contain 'SemiAnnually'
    }

    It 'every recurrence parameter found in source lists the canonical set, in order (derived, not listed)' {
        # BL-117: the ValidateSet sites are DERIVED from the whole source tree -- every parameter named
        # Recurrence or carrying a [ValidateSet()] with OneTime, every one per file -- so a fourth
        # cmdlet, or a second -Recurrence in a file that already has one, cannot go unchecked. The
        # three named ValidateSet sites are the floor: a derivation that found nothing fails on them.
        $Canonical = @(InModuleScope $script:moduleName { Resolve-OERStructureEnumCasing -EnumName 'accessReviewRecurrence' -List })
        $Problems = @(Test-CohortRecurrenceSite -SourceRoot $script:cohortSourceRoot -Canonical $Canonical -Floor $script:cohortFloor)
        $Problems.Count | Should -Be 0 -Because ('every recurrence parameter must list the canonical set in order: {0}' -f ($Problems -join '; '))
        @(Get-CohortRecurrenceSite -SourceRoot $script:cohortSourceRoot).Count | Should -BeGreaterOrEqual $script:cohortFloor.Count -Because 'the derivation must find at least the three named sites'
    }

    It 'names each problem of a derived site, and fails on an empty derivation (known-answer trees)' {
        $Canonical = @('OneTime', 'Weekly', 'Monthly', 'Quarterly', 'SemiAnnually', 'Annually')
        $Good = "[ValidateSet('OneTime','Weekly','Monthly','Quarterly','SemiAnnually','Annually')]"
        $Short = "[ValidateSet('OneTime','Weekly','Monthly')]"
        $Tree = Join-Path -Path $TestDrive -ChildPath 'cohort-tree'
        $Write = {
            param($Name, $Text)
            $Path = Join-Path -Path $Tree -ChildPath $Name
            New-Item -ItemType Directory -Force -Path (Split-Path -Parent $Path) | Out-Null
            Set-Content -LiteralPath $Path -Value $Text -Encoding ascii
        }

        # A tree holding nothing: the derivation is empty, so the floor reports all three sites.
        New-Item -ItemType Directory -Force -Path $Tree | Out-Null
        $Empty = Test-CohortRecurrenceSite -SourceRoot $Tree -Canonical $Canonical -Floor $script:cohortFloor
        @($Empty).Count | Should -Be 3
        @($Empty)[0] | Should -BeLike 'floor site not found by the derivation*'

        # All three floor files correct: clean.
        foreach ($File in $script:cohortFloor) {
            & $Write $File "function F { param($Good [string]`$Recurrence) }"
        }
        @(Test-CohortRecurrenceSite -SourceRoot $Tree -Canonical $Canonical -Floor $script:cohortFloor).Count | Should -Be 0

        # A SECOND -Recurrence in a file that already has a good one: only the first-in-file reading
        # would miss it.
        & $Write 'Public/Set-OERAccessReviewDefinition.ps1' "function F { param($Good [string]`$Recurrence) }`nfunction G { param($Short [string]`$Recurrence) }"
        $Second = @(Test-CohortRecurrenceSite -SourceRoot $Tree -Canonical $Canonical -Floor $script:cohortFloor)
        $Second.Count | Should -Be 1
        $Second[0] | Should -BeLike "-Recurrence in 'Public/Set-OERAccessReviewDefinition.ps1' lists 'OneTime,Weekly,Monthly'*"
        & $Write 'Public/Set-OERAccessReviewDefinition.ps1' "function F { param($Good [string]`$Recurrence) }"

        # A NEW file with a ValidateSet containing OneTime but missing SemiAnnually, under a name that
        # is not Recurrence.
        & $Write 'Private/Some-NewCadenceCmdlet.ps1' "function H { param($("[ValidateSet('OneTime','Weekly','Monthly','Quarterly','Annually')]") [string]`$Cadence) }"
        $New = @(Test-CohortRecurrenceSite -SourceRoot $Tree -Canonical $Canonical -Floor $script:cohortFloor)
        $New.Count | Should -Be 1
        $New[0] | Should -BeLike "-Cadence in 'Private/Some-NewCadenceCmdlet.ps1' lists*"
        Remove-Item -LiteralPath (Join-Path $Tree 'Private/Some-NewCadenceCmdlet.ps1')

        # A -Recurrence with no ValidateSet at all is a finding.
        & $Write 'Private/Plain.ps1' 'function P { param([string]$Recurrence) }'
        $Plain = @(Test-CohortRecurrenceSite -SourceRoot $Tree -Canonical $Canonical -Floor $script:cohortFloor)
        $Plain.Count | Should -Be 1
        $Plain[0] | Should -BeExactly "-Recurrence in 'Private/Plain.ps1' carries no [ValidateSet()]"
    }

    It '<Site> lists the canonical recurrence set, in order' -ForEach @(
        @{ Site = 'ValidRecurrenceValues in Sync-OERStructureAccessReview'; Kind = 'Array'; File = 'Private/Sync-OERStructureAccessReview.ps1' }
        @{ Site = 'the accessReviews recurrence list in the exported prompt'; Kind = 'Prompt'; File = '' }
        @{ Site = 'the accessReviews recurrence enum in the schema'; Kind = 'Schema'; File = '' }
    ) {
        $Canonical = @(InModuleScope $script:moduleName { Resolve-OERStructureEnumCasing -EnumName 'accessReviewRecurrence' -List })
        $Actual = @(switch ($Kind) {
                'Array' { Get-CohortArrayLiteral -RelativePath $File -VariableName 'ValidRecurrenceValues' }
                'Prompt' { Get-CohortPromptList }
                'Schema' { Get-CohortSchemaEnum }
                default { throw "unknown cohort site kind '$Kind'" }
            })
        $Actual.Count | Should -BeGreaterThan 0 -Because 'a site that yields no list proves nothing'
        # -join makes order and casing part of the assertion.
        ($Actual -join ',') | Should -BeExactly ($Canonical -join ',')
    }

    It 'fails, rather than passing vacuously, when a site cannot be read' {
        { Get-CohortRecurrenceSite -SourceRoot (Join-Path -Path $TestDrive -ChildPath 'NoSuchRoot') | Out-Null } | Should -Throw '*does not exist*'
        { Get-CohortArrayLiteral -RelativePath 'Private/Sync-OERStructureAccessReview.ps1' -VariableName 'NoSuchVariable' } | Should -Throw '*no assignment*'
        { Get-CohortArrayLiteral -RelativePath 'Private/NoSuchFile.ps1' -VariableName 'ValidRecurrenceValues' } | Should -Throw '*does not exist*'
    }
}
