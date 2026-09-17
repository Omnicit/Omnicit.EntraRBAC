BeforeDiscovery {
    # Cross-cmdlet suite, named after no single function (like AmbiguousName.Guard.Tests.ps1,
    # NothingToUpdate.Cohort.Tests.ps1, and GroupAliasOrder.Cohort.Tests.ps1, which this file mirrors).
    # ConvertTo-OERAdministrativeUnitMember emits Id and DisplayName (the MEMBER's own, scoped to
    # whatever principal it represents) alongside AdministrativeUnitId (the PARENT unit). PowerShell
    # resolves ValueFromPipelineByPropertyName by parameter name first, then aliases in DECLARATION
    # ORDER, first match wins. An Id-or-DisplayName-before-AdministrativeUnitId Alias(...) list on ANY
    # -AdministrativeUnit parameter therefore binds the piped member's own id (or display name) instead
    # of the piped parent unit -- and on Remove-OERAdministrativeUnit (ConfirmImpact = 'High') that
    # means `$Au.Members | Remove-OERAdministrativeUnit` would try to delete the PRINCIPAL's tenant
    # object's "administrative unit" (a resolve failure at best, given Id and DisplayName both still
    # coexist correctly ordered against each other) rather than leaving the member alone. The task-5
    # report's own converter help now advertises this pipe as supported for every -AdministrativeUnit
    # carrier, not just Add-/Remove-OERAdministrativeUnitMember (which already had targeted coverage) --
    # this file is what actually pins the order for the other six.
    #
    # Every source/Public/*AdministrativeUnit*.ps1 file that declares a -AdministrativeUnit parameter
    # is discovered directly from its own AST (not from the built module), so this needs no prior build
    # step and also catches a typo'd alias before the build ever runs. Discovery is automatic: a future
    # -AdministrativeUnit carrier is covered here without editing this file, and the exact-count
    # assertion below fails loudly if one is added without the correct alias order (or if one is
    # silently dropped). Do not delete this file as an orphan when auditing the one-test-file-per-
    # function invariant.
    $script:ProjectPath = (Resolve-Path -Path (Join-Path -Path $PSScriptRoot -ChildPath '..\..\..')).Path
    $script:AuSourcePath = Join-Path -Path $script:ProjectPath -ChildPath 'source\Public'

    $script:AuAliasCarriers = @(
        foreach ($File in (Get-ChildItem -Path $script:AuSourcePath -Filter '*AdministrativeUnit*.ps1' -File)) {
            $FileAst = [System.Management.Automation.Language.Parser]::ParseFile($File.FullName, [ref]$null, [ref]$null)
            $ParamAst = $FileAst.FindAll({
                    param($Node)
                    $Node -is [System.Management.Automation.Language.ParameterAst] -and
                    $Node.Name.VariablePath.UserPath -eq 'AdministrativeUnit'
                }, $true) | Select-Object -First 1
            if (-not $ParamAst) { continue }

            $AliasAttributeAst = $ParamAst.Attributes | Where-Object { $_.TypeName.Name -eq 'Alias' } | Select-Object -First 1
            $AliasValues = if ($AliasAttributeAst) {
                @($AliasAttributeAst.PositionalArguments | ForEach-Object { $_.SafeGetValue() })
            } else {
                @()
            }
            @{
                File        = $File.Name
                Cmdlet      = $File.BaseName
                AliasValues = $AliasValues
            }
        }
    )
}

Describe 'Every -AdministrativeUnit parameter binds AdministrativeUnitId before Id before DisplayName from the pipeline (task 5)' {
    It 'discovers exactly the eight known -AdministrativeUnit parameter carriers' {
        # A cohort test that silently discovers zero carriers would pass while proving nothing -- pin
        # both the count and the exact name set so a future rename, removal or addition is caught here
        # rather than silently shrinking coverage.
        #
        # $script:AuAliasCarriers is set inside BeforeDiscovery, which -- unlike BeforeAll -- runs only
        # during Pester's Discovery pass and is unset again by the time this It body executes in the
        # Run pass (the same caveat NothingToUpdate.Cohort.Tests.ps1 and GroupAliasOrder.Cohort.Tests.ps1
        # document and work around). So the roster is re-derived here directly from the source tree via
        # $PSScriptRoot, which -- unlike a BeforeDiscovery-set variable -- IS available in both passes,
        # instead of trusting the BeforeDiscovery-scoped variable to have survived.
        $LiveSourcePath = Join-Path -Path (Resolve-Path -Path (Join-Path -Path $PSScriptRoot -ChildPath '..\..\..')).Path -ChildPath 'source\Public'
        $LiveCarriers = @(
            Get-ChildItem -Path $LiveSourcePath -Filter '*AdministrativeUnit*.ps1' -File | ForEach-Object {
                $FileAst = [System.Management.Automation.Language.Parser]::ParseFile($_.FullName, [ref]$null, [ref]$null)
                $ParamAst = $FileAst.FindAll({
                        param($Node)
                        $Node -is [System.Management.Automation.Language.ParameterAst] -and
                        $Node.Name.VariablePath.UserPath -eq 'AdministrativeUnit'
                    }, $true) | Select-Object -First 1
                if ($ParamAst) { $_.BaseName }
            }
        )
        $LiveCarriers.Count | Should -Be 8
        @($LiveCarriers | Sort-Object) | Should -Be @(
            'Add-OERAdministrativeUnitMember',
            'Add-OERAdministrativeUnitScopedRole',
            'Get-OERAdministrativeUnit',
            'Get-OERAdministrativeUnitScopedRole',
            'Remove-OERAdministrativeUnit',
            'Remove-OERAdministrativeUnitMember',
            'Remove-OERAdministrativeUnitScopedRole',
            'Set-OERAdministrativeUnit'
        )
    }

    It '<Cmdlet> lists AdministrativeUnitId before Id before DisplayName in the -AdministrativeUnit AliasAttribute' -ForEach $script:AuAliasCarriers {
        $AliasValues | Should -Not -BeNullOrEmpty -Because "$Cmdlet's -AdministrativeUnit parameter must carry an Alias attribute"
        $AuIdIndex = [array]::IndexOf($AliasValues, 'AdministrativeUnitId')
        $IdIndex = [array]::IndexOf($AliasValues, 'Id')
        $DisplayNameIndex = [array]::IndexOf($AliasValues, 'DisplayName')
        $AuIdIndex | Should -BeGreaterOrEqual 0 -Because "$Cmdlet's -AdministrativeUnit Alias must include AdministrativeUnitId"
        $IdIndex | Should -BeGreaterOrEqual 0 -Because "$Cmdlet's -AdministrativeUnit Alias must include Id"
        $DisplayNameIndex | Should -BeGreaterOrEqual 0 -Because "$Cmdlet's -AdministrativeUnit Alias must include DisplayName"
        $AuIdIndex | Should -BeLessThan $IdIndex -Because (
            "AdministrativeUnitId must resolve before Id during ValueFromPipelineByPropertyName alias matching, " +
            "or a piped AdministrativeUnitMember object binds the member's own id instead of its parent unit")
        $IdIndex | Should -BeLessThan $DisplayNameIndex -Because (
            "Id must resolve before DisplayName during ValueFromPipelineByPropertyName alias matching, " +
            "matching the historical -Id-wins-over-name resolution order")
    }
}
