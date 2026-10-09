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
    # compared with the canonical list, order included.
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

        # The strings of the [ValidateSet()] on one parameter, in declaration order. Throws, rather than
        # returning an empty list that a caller might compare to nothing, when anything is missing.
        function Get-CohortValidateSet {
            param([string]$RelativePath, [string]$ParameterName)
            $Ast = Read-CohortAst -RelativePath $RelativePath
            $ParamAst = $Ast.FindAll({
                    param($Node)
                    $Node -is [System.Management.Automation.Language.ParameterAst] -and
                    $Node.Name.VariablePath.UserPath -eq $ParameterName
                }, $true) | Select-Object -First 1
            if (-not $ParamAst) { throw "no -$ParameterName parameter in '$RelativePath'" }
            $SetAst = $ParamAst.Attributes | Where-Object {
                $_ -is [System.Management.Automation.Language.AttributeAst] -and $_.TypeName.Name -eq 'ValidateSet'
            } | Select-Object -First 1
            if (-not $SetAst) { throw "-$ParameterName in '$RelativePath' carries no [ValidateSet()]" }
            $Values = @($SetAst.PositionalArguments | ForEach-Object { $_.SafeGetValue() })
            if ($Values.Count -eq 0) { throw "the [ValidateSet()] of -$ParameterName in '$RelativePath' is empty" }
            $Values
        }

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

    It '<Site> lists the canonical recurrence set, in order' -ForEach @(
        @{ Site = 'the ValidateSet of New-OERAccessReviewRecurrence -Recurrence'; Kind = 'ValidateSet'; File = 'Private/New-OERAccessReviewRecurrence.ps1' }
        @{ Site = 'the ValidateSet of New-OERAccessReviewDefinition -Recurrence'; Kind = 'ValidateSet'; File = 'Public/New-OERAccessReviewDefinition.ps1' }
        @{ Site = 'the ValidateSet of Set-OERAccessReviewDefinition -Recurrence'; Kind = 'ValidateSet'; File = 'Public/Set-OERAccessReviewDefinition.ps1' }
        @{ Site = 'ValidRecurrenceValues in Sync-OERStructureAccessReview'; Kind = 'Array'; File = 'Private/Sync-OERStructureAccessReview.ps1' }
        @{ Site = 'the accessReviews recurrence list in the exported prompt'; Kind = 'Prompt'; File = '' }
        @{ Site = 'the accessReviews recurrence enum in the schema'; Kind = 'Schema'; File = '' }
    ) {
        $Canonical = @(InModuleScope $script:moduleName { Resolve-OERStructureEnumCasing -EnumName 'accessReviewRecurrence' -List })
        $Actual = @(switch ($Kind) {
                'ValidateSet' { Get-CohortValidateSet -RelativePath $File -ParameterName 'Recurrence' }
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
        { Get-CohortValidateSet -RelativePath 'Private/NoSuchFile.ps1' -ParameterName 'Recurrence' } | Should -Throw '*does not exist*'
        { Get-CohortValidateSet -RelativePath 'Private/New-OERAccessReviewRecurrence.ps1' -ParameterName 'NoSuchParameter' } | Should -Throw '*no -NoSuchParameter parameter*'
        { Get-CohortValidateSet -RelativePath 'Private/New-OERAccessReviewRecurrence.ps1' -ParameterName 'StartDate' } | Should -Throw '*carries no*ValidateSet*'
        { Get-CohortArrayLiteral -RelativePath 'Private/Sync-OERStructureAccessReview.ps1' -VariableName 'NoSuchVariable' } | Should -Throw '*no assignment*'
        { Get-CohortArrayLiteral -RelativePath 'Private/NoSuchFile.ps1' -VariableName 'ValidRecurrenceValues' } | Should -Throw '*does not exist*'
    }
}
