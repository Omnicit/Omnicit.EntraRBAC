BeforeDiscovery {
    # Cross-cmdlet suite, named after no single function (like GroupAliasOrder.Cohort.Tests.ps1, whose
    # method it follows). The objects that name an access package -- an assignment policy, a resource
    # role, an assignment, an assignment request -- carry BOTH their own Id and an AccessPackageId, and
    # PowerShell resolves ValueFromPipelineByPropertyName by parameter name first, then aliases in
    # DECLARATION ORDER, first match wins. An Id-before-AccessPackageId Alias(...) list on any
    # -AccessPackage parameter therefore binds the piped object's OWN id (a policy id, say) as the access
    # package. Every source/Public/*.ps1 file declaring a -AccessPackage parameter that is bound from the
    # pipeline by property name (ANY [Parameter()] attribute on it, one per parameter set, with
    # ValueFromPipelineByPropertyName not set to $false) and whose Alias list holds Id or DisplayName, or
    # whose Alias list holds AccessPackageId, is read from its own AST (never imported), so a future
    # carrier is covered without editing this file (BL-196: a pipeline parameter with only Alias('Id')
    # was once skipped for lacking AccessPackageId, which hid Get-OERAccessPackageResourceRole's defect).
    # Unset, OER_COHORT_SOURCE_ROOT leaves the scan on the repository's own source/;
    # a mutation proof sets it to a scratch copy of source/ so the scan reads the mutated tree.
    # Do not delete this file as an orphan when auditing the one-test-file-per-function invariant.
    $script:CohortSourceRoot = if ($env:OER_COHORT_SOURCE_ROOT) {
        $env:OER_COHORT_SOURCE_ROOT
    } else {
        Join-Path -Path $PSScriptRoot -ChildPath '../../../source'
    }
    $script:CohortSourceRoot = (Resolve-Path -Path $script:CohortSourceRoot).Path
    if ($env:OER_COHORT_SOURCE_ROOT) {
        Write-Warning "OER_COHORT_SOURCE_ROOT is set: scanning $script:CohortSourceRoot instead of the repository source."
    }

    $script:AccessPackageAliasCarriers = @(
        foreach ($File in (Get-ChildItem -Path (Join-Path -Path $script:CohortSourceRoot -ChildPath 'Public') -Filter '*.ps1' -File)) {
            $FileAst = [System.Management.Automation.Language.Parser]::ParseFile($File.FullName, [ref]$null, [ref]$null)
            $ParamAst = $FileAst.FindAll({
                    param($Node)
                    $Node -is [System.Management.Automation.Language.ParameterAst] -and
                    $Node.Name.VariablePath.UserPath -eq 'AccessPackage'
                }, $true) | Select-Object -First 1
            if (-not $ParamAst) { continue }

            $AliasAttributeAst = $ParamAst.Attributes | Where-Object { $_.TypeName.Name -eq 'Alias' } | Select-Object -First 1
            $AliasValues = if ($AliasAttributeAst) {
                @($AliasAttributeAst.PositionalArguments | ForEach-Object { $_.SafeGetValue() })
            } else {
                @()
            }
            $FromPipeline = $false
            foreach ($Attr in ($ParamAst.Attributes | Where-Object { $_.TypeName.Name -eq 'Parameter' })) {
                foreach ($Named in $Attr.NamedArguments | Where-Object { $_.ArgumentName -eq 'ValueFromPipelineByPropertyName' }) {
                    $Value = if ($Named.ExpressionOmitted) { $true } else { try { $Named.Argument.SafeGetValue() } catch { $true } }
                    if ($Value -ne $false) { $FromPipeline = $true }
                }
            }
            $Selected = ($AliasValues -contains 'AccessPackageId') -or
            ($FromPipeline -and (($AliasValues -contains 'Id') -or ($AliasValues -contains 'DisplayName')))
            if (-not $Selected) { continue }
            @{
                File        = $File.Name
                Cmdlet      = $File.BaseName
                AliasValues = $AliasValues
            }
        }
    )
}

BeforeAll {
    # The selection rule of the scan (written twice: BeforeDiscovery variables are not visible in Run;
    # keep both copies identical). Takes a parameter AST, returns the alias values when selected, else $null.
    $script:SelectAccessPackageParam = {
        param($ParamAst)
        $AliasAttributeAst = $ParamAst.Attributes | Where-Object { $_.TypeName.Name -eq 'Alias' } | Select-Object -First 1
        $AliasValues = if ($AliasAttributeAst) {
            @($AliasAttributeAst.PositionalArguments | ForEach-Object { $_.SafeGetValue() })
        } else {
            @()
        }
        $FromPipeline = $false
        foreach ($Attr in ($ParamAst.Attributes | Where-Object { $_.TypeName.Name -eq 'Parameter' })) {
            foreach ($Named in $Attr.NamedArguments | Where-Object { $_.ArgumentName -eq 'ValueFromPipelineByPropertyName' }) {
                $Value = if ($Named.ExpressionOmitted) { $true } else { try { $Named.Argument.SafeGetValue() } catch { $true } }
                if ($Value -ne $false) { $FromPipeline = $true }
            }
        }
        $Selected = ($AliasValues -contains 'AccessPackageId') -or
        ($FromPipeline -and (($AliasValues -contains 'Id') -or ($AliasValues -contains 'DisplayName')))
        if ($Selected) { , $AliasValues } else { $null }
    }

    # The predicate the scan applies: AccessPackageId precedes Id and DisplayName wherever those are listed.
    $script:AccessPackageIdFirst = {
        param([string[]]$AliasValues)
        $Own = [array]::IndexOf($AliasValues, 'AccessPackageId')
        if ($Own -lt 0) { return $false }
        foreach ($Other in 'Id', 'DisplayName') {
            $At = [array]::IndexOf($AliasValues, $Other)
            if ($At -ge 0 -and $Own -gt $At) { return $false }
        }
        $true
    }
}

Describe 'Every -AccessPackage parameter binds AccessPackageId before Id and DisplayName from the pipeline (BL-192, BL-196)' {
    It 'finds at least the seven cmdlets that bind -AccessPackage from the pipeline today, so the scan is never vacuous' {
        # BeforeDiscovery variables are not visible in the Run pass, so the roster is derived again here.
        $Root = if ($env:OER_COHORT_SOURCE_ROOT) { $env:OER_COHORT_SOURCE_ROOT } else { Join-Path -Path $PSScriptRoot -ChildPath '../../../source' }
        $Found = @()
        $Missing = @()
        foreach ($File in (Get-ChildItem -Path (Join-Path -Path $Root -ChildPath 'Public') -Filter '*.ps1' -File)) {
            $FileAst = [System.Management.Automation.Language.Parser]::ParseFile($File.FullName, [ref]$null, [ref]$null)
            $ParamAst = $FileAst.FindAll({
                    param($Node)
                    $Node -is [System.Management.Automation.Language.ParameterAst] -and
                    $Node.Name.VariablePath.UserPath -eq 'AccessPackage'
                }, $true) | Select-Object -First 1
            if (-not $ParamAst) { continue }
            $Values = & $script:SelectAccessPackageParam $ParamAst
            if ($null -eq $Values) { continue }
            $Found += $File.BaseName
            if ($Values -notcontains 'AccessPackageId') { $Missing += $File.BaseName }
        }
        foreach ($Name in 'Add-OERAccessPackageResourceRole', 'Get-OERAccessPackageAssignment', 'Get-OERAccessPackageAssignmentPolicy',
            'Get-OERAccessPackageResourceRole', 'New-OERAccessPackageAssignment', 'New-OERAccessPackageAssignmentPolicy',
            'Remove-OERAccessPackageResourceRole') {
            $Found | Should -Contain $Name
        }
        $Found.Count | Should -BeGreaterOrEqual 7
        $Missing | Should -BeNullOrEmpty -Because "a pipeline-bound -AccessPackage with Id or DisplayName must carry AccessPackageId (missing: $($Missing -join ', '))"
    }

    It '<Cmdlet> lists AccessPackageId before Id and DisplayName in the -AccessPackage AliasAttribute' -ForEach $script:AccessPackageAliasCarriers {
        $AliasValues | Should -Contain 'AccessPackageId'
        $AccessPackageIdIndex = [array]::IndexOf($AliasValues, 'AccessPackageId')
        foreach ($Other in 'Id', 'DisplayName') {
            $OtherIndex = [array]::IndexOf($AliasValues, $Other)
            if ($OtherIndex -ge 0) {
                $AccessPackageIdIndex | Should -BeLessThan $OtherIndex -Because (
                    "AccessPackageId must resolve before $Other during ValueFromPipelineByPropertyName alias matching, " +
                    'or a piped policy or resource role binds its own id as the access package')
            }
        }
    }

    It 'the predicate flags a declaration that lists Id before AccessPackageId or omits it (known answer on a parsed miniature)' {
        $Source = @'
function Good { param([Parameter(ValueFromPipelineByPropertyName)][Alias('AccessPackageId', 'Id', 'DisplayName')][string]$AccessPackage) }
function Bad  { param([Parameter(ValueFromPipelineByPropertyName)][Alias('Id', 'AccessPackageId')][string]$AccessPackage) }
function BadDisplayName { param([Parameter(ValueFromPipelineByPropertyName)][Alias('DisplayName', 'AccessPackageId')][string]$AccessPackage) }
function OnlyId { param([Parameter(ValueFromPipelineByPropertyName)][Alias('Id')][string]$AccessPackage) }
function TwoSets { param([Parameter(ParameterSetName = 'A', Mandatory)][Parameter(ParameterSetName = 'B', ValueFromPipelineByPropertyName = $true)][Alias('Id')][string]$AccessPackage) }
function NotPiped { param([Parameter(Mandatory)][Alias('Id')][string]$AccessPackage) }
function PipeOff { param([Parameter(ValueFromPipelineByPropertyName = $false)][Alias('Id')][string]$AccessPackage) }
'@
        $Ast = [System.Management.Automation.Language.Parser]::ParseInput($Source, [ref]$null, [ref]$null)
        $Verdict = @{}
        $Selected = @{}
        foreach ($Function in $Ast.FindAll({ param($Node) $Node -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true)) {
            $ParamAst = $Function.FindAll({
                    param($Node)
                    $Node -is [System.Management.Automation.Language.ParameterAst] -and $Node.Name.VariablePath.UserPath -eq 'AccessPackage'
                }, $true) | Select-Object -First 1
            $Values = & $script:SelectAccessPackageParam $ParamAst
            $Selected[$Function.Name] = $null -ne $Values
            if ($null -ne $Values) { $Verdict[$Function.Name] = & $script:AccessPackageIdFirst $Values }
        }
        $Verdict['Good'] | Should -BeTrue
        $Verdict['Bad'] | Should -BeFalse
        $Verdict['BadDisplayName'] | Should -BeFalse
        # A pipeline declaration with Alias('Id') alone is selected and flagged, also over two parameter sets.
        $Selected['OnlyId'] | Should -BeTrue
        $Verdict['OnlyId'] | Should -BeFalse
        $Selected['TwoSets'] | Should -BeTrue
        $Verdict['TwoSets'] | Should -BeFalse
        # A declaration not bound from the pipeline by property name is not selected.
        $Selected['NotPiped'] | Should -BeFalse
        $Selected['PipeOff'] | Should -BeFalse
    }
}
