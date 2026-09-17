BeforeDiscovery {
    # Cross-cmdlet suite, named after no single function (like AmbiguousName.Guard.Tests.ps1 and
    # NothingToUpdate.Cohort.Tests.ps1). ConvertTo-OERGroupMember emits both Id (the PRINCIPAL) and
    # GroupId (the group); PowerShell resolves ValueFromPipelineByPropertyName by parameter name
    # first, then aliases in DECLARATION ORDER, first match wins. An Id-before-GroupId Alias(...) list
    # on ANY -Group parameter therefore binds the piped principal instead of the piped group -- and on
    # Remove-OERGroup (ConfirmImpact = 'High') that means `Get-OERGroupMember ... | Remove-OERGroup`
    # deletes the PRINCIPAL's tenant object, not the group. Only the two readers
    # (Get-OERGroupEligibility, Get-OERGroupMember) had regression coverage for this before this file;
    # the other seven reordered sites -- including the destructive one -- had none.
    #
    # Every source/Public/*Group*.ps1 file that declares a -Group parameter is discovered directly
    # from its own AST (not from the built module), so this needs no prior build step and also catches
    # a typo'd alias before the build ever runs. Discovery is automatic: a future -Group carrier is
    # covered here without editing this file, and the exact-count assertion below fails loudly if one
    # is added without the correct alias order (or if one is silently dropped). Do not delete this file
    # as an orphan when auditing the one-test-file-per-function invariant.
    $script:ProjectPath = (Resolve-Path -Path (Join-Path -Path $PSScriptRoot -ChildPath '..\..\..')).Path
    $script:GroupSourcePath = Join-Path -Path $script:ProjectPath -ChildPath 'source\Public'

    $script:GroupAliasCarriers = @(
        foreach ($File in (Get-ChildItem -Path $script:GroupSourcePath -Filter '*Group*.ps1' -File)) {
            $FileAst = [System.Management.Automation.Language.Parser]::ParseFile($File.FullName, [ref]$null, [ref]$null)
            $ParamAst = $FileAst.FindAll({
                    param($Node)
                    $Node -is [System.Management.Automation.Language.ParameterAst] -and
                    $Node.Name.VariablePath.UserPath -eq 'Group'
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

Describe 'Every -Group parameter binds GroupId before Id from the pipeline (fix/groups T1NEW)' {
    It 'discovers exactly the eleven known -Group parameter carriers' {
        # A cohort test that silently discovers zero carriers would pass while proving nothing -- pin
        # both the count and the exact name set so a future rename, removal or addition is caught here
        # rather than silently shrinking coverage.
        #
        # $script:GroupAliasCarriers is set inside BeforeDiscovery, which -- unlike BeforeAll -- runs
        # only during Pester's Discovery pass and is unset again by the time this It body executes in
        # the Run pass (proven: a BeforeDiscovery-set $script: variable reads back $null/empty inside
        # an It -- the same caveat NothingToUpdate.Cohort.Tests.ps1 documents and works around). So the
        # roster is re-derived here directly from the source tree via $PSScriptRoot, which -- unlike a
        # BeforeDiscovery-set variable -- IS available in both passes, instead of trusting the
        # BeforeDiscovery-scoped variable to have survived.
        $LiveSourcePath = Join-Path -Path (Resolve-Path -Path (Join-Path -Path $PSScriptRoot -ChildPath '..\..\..')).Path -ChildPath 'source\Public'
        $LiveCarriers = @(
            Get-ChildItem -Path $LiveSourcePath -Filter '*Group*.ps1' -File | ForEach-Object {
                $FileAst = [System.Management.Automation.Language.Parser]::ParseFile($_.FullName, [ref]$null, [ref]$null)
                $ParamAst = $FileAst.FindAll({
                        param($Node)
                        $Node -is [System.Management.Automation.Language.ParameterAst] -and
                        $Node.Name.VariablePath.UserPath -eq 'Group'
                    }, $true) | Select-Object -First 1
                if ($ParamAst) { $_.BaseName }
            }
        )
        $LiveCarriers.Count | Should -Be 11
        @($LiveCarriers | Sort-Object) | Should -Be @(
            'Add-OERGroupEligibility',
            'Add-OERGroupMember',
            'Get-OERGroup',
            'Get-OERGroupEligibility',
            'Get-OERGroupMember',
            'Get-OERGroupPimPolicy',
            'Remove-OERGroup',
            'Remove-OERGroupEligibility',
            'Remove-OERGroupMember',
            'Set-OERGroup',
            'Set-OERGroupPimPolicy'
        )
    }

    It '<Cmdlet> lists GroupId before Id in the -Group AliasAttribute' -ForEach $script:GroupAliasCarriers {
        $AliasValues | Should -Not -BeNullOrEmpty -Because "$Cmdlet's -Group parameter must carry an Alias attribute"
        $GroupIdIndex = [array]::IndexOf($AliasValues, 'GroupId')
        $IdIndex = [array]::IndexOf($AliasValues, 'Id')
        $GroupIdIndex | Should -BeGreaterOrEqual 0 -Because "$Cmdlet's -Group Alias must include GroupId"
        $IdIndex | Should -BeGreaterOrEqual 0 -Because "$Cmdlet's -Group Alias must include Id"
        $GroupIdIndex | Should -BeLessThan $IdIndex -Because (
            "GroupId must resolve before Id during ValueFromPipelineByPropertyName alias matching, " +
            "or a piped Get-OERGroupMember object binds the principal instead of the group")
    }
}
