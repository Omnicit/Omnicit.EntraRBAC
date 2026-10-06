BeforeDiscovery {
    # Cross-cmdlet suite, named after no single function (like GroupAliasOrder.Cohort.Tests.ps1 and
    # AdministrativeUnitAliasOrder.Cohort.Tests.ps1, whose AST pattern this file follows). Do not delete it
    # as an orphan when auditing the one-test-file-per-function invariant.
    #
    # A12 (BL-94): every public cmdlet read an empty -TenantId as no tenant at all, so a loop such as
    # Invoke-OERStructure -TenantId $Row.TenantId -Path $Row.Path -Prune, over rows with an empty cell,
    # applied that row's document in the tenant of the current session. Every public cmdlet that declares
    # -TenantId therefore carries [ValidateNotNullOrEmpty()] on it: the parameter binding error stops that
    # one command, which then sends nothing. Connect-OER is the one named exception (A12 (a)): it refuses a
    # blank -TenantId itself, with InvalidTenantId, in its process block AFTER it marks the session
    # uncertain, since a binding error never reaches the function and would leave the marker as the previous
    # sign-in left it. So Connect-OER's -TenantId must carry no validation at all.
    #
    # Every source/Public/*.ps1 file is read with the AST, not imported, so the scan needs no build and
    # covers a new -TenantId carrier without editing this file; the exact count below fails loudly when one
    # is added or dropped. Unset, OER_COHORT_SOURCE_ROOT leaves the scan on the repository's own source/;
    # a mutation proof sets it to a scratch copy of source/ so the scan reads the mutated tree.
    $script:CohortSourceRoot = if ($env:OER_COHORT_SOURCE_ROOT) {
        $env:OER_COHORT_SOURCE_ROOT
    } else {
        Join-Path -Path $PSScriptRoot -ChildPath '../../../source'
    }
    $script:TenantIdCarriers = @(
        foreach ($File in (Get-ChildItem -Path (Join-Path -Path $script:CohortSourceRoot -ChildPath 'Public') -Filter '*.ps1' -File)) {
            $FileAst = [System.Management.Automation.Language.Parser]::ParseFile($File.FullName, [ref]$null, [ref]$null)
            $FunctionAst = $FileAst.Find({ param($Node) $Node -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $false)
            $ParamAst = @($FunctionAst.Body.ParamBlock.Parameters | Where-Object { $_.Name.VariablePath.UserPath -eq 'TenantId' })[0]
            if (-not $ParamAst) { continue }
            @{
                Cmdlet     = $File.BaseName
                Attributes = @($ParamAst.Attributes | ForEach-Object { $_.TypeName.Name })
                Mandatory  = [bool](@($ParamAst.Attributes | Where-Object {
                            $_.TypeName.Name -eq 'Parameter' -and
                            @($_.NamedArguments | Where-Object { $_.ArgumentName -eq 'Mandatory' }).Count -gt 0
                        }).Count)
            }
        }
    )
    $script:ValidatedCarriers = @($script:TenantIdCarriers | Where-Object { $_.Cmdlet -ne 'Connect-OER' })
    $script:ConnectCarrier = @($script:TenantIdCarriers | Where-Object { $_.Cmdlet -eq 'Connect-OER' })
}

BeforeAll {
    Import-Module Omnicit.EntraRBAC -Force
    . "$PSScriptRoot/../TestHelpers/OERTransportTripwire.ps1"
    Install-OERTransportTripwire

    if ($env:OER_COHORT_SOURCE_ROOT) {
        Write-Warning "OER_COHORT_SOURCE_ROOT is set: scanning $env:OER_COHORT_SOURCE_ROOT instead of the repository source."
    }
}

AfterAll {
    try { Assert-OERTransportTripwire } finally { Uninstall-OERTransportTripwire }
}

Describe 'Every public -TenantId refuses an empty value at parameter binding, except Connect-OER''s (A12, BL-94)' {
    It 'discovers the 91 public -TenantId carriers, Connect-OER among them' {
        # A cohort scan that silently discovers nothing would pass while proving nothing. A variable set in
        # BeforeDiscovery is gone by the Run pass, so the roster is derived again here.
        $Root = if ($env:OER_COHORT_SOURCE_ROOT) { $env:OER_COHORT_SOURCE_ROOT } else { Join-Path -Path $PSScriptRoot -ChildPath '../../../source' }
        $Live = @(
            Get-ChildItem -Path (Join-Path -Path $Root -ChildPath 'Public') -Filter '*.ps1' -File | ForEach-Object {
                $FileAst = [System.Management.Automation.Language.Parser]::ParseFile($_.FullName, [ref]$null, [ref]$null)
                $FunctionAst = $FileAst.Find({ param($Node) $Node -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $false)
                if (@($FunctionAst.Body.ParamBlock.Parameters | Where-Object { $_.Name.VariablePath.UserPath -eq 'TenantId' }).Count) {
                    $_.BaseName
                }
            }
        )
        $Live.Count | Should -Be 91
        $Live | Should -Contain 'Connect-OER'
        $Live | Should -Contain 'Get-OERGroup'
        $Live | Should -Contain 'Invoke-OERStructure'
    }

    It '<Cmdlet> declares [ValidateNotNullOrEmpty()] on -TenantId' -ForEach $script:ValidatedCarriers {
        $Attributes | Should -Contain 'ValidateNotNullOrEmpty' -Because (
            "an empty -TenantId on $Cmdlet must stop at parameter binding rather than be read as no tenant, " +
            'which would act on the tenant of the current session')
    }

    It 'Connect-OER declares no validation on -TenantId and does not make it mandatory, so a blank value reaches its own refusal' -ForEach $script:ConnectCarrier {
        @($Attributes | Where-Object { $_ -like 'Validate*' -or $_ -like 'Allow*' }) | Should -BeNullOrEmpty -Because (
            'a parameter binding error never reaches the process block, which marks the session uncertain ' +
            'before it refuses a blank -TenantId with InvalidTenantId')
        $Mandatory | Should -BeFalse
    }
}

Describe 'A public cmdlet given an empty -TenantId sends nothing (A12, BL-94)' {
    # The attribute at work, for the cmdlets the live checklist drives and the two that store a tenant:
    # the binding error comes before the command's begin block, so neither a sign-in nor a request is made.
    BeforeAll {
        Mock -ModuleName Omnicit.EntraRBAC Initialize-OERAuth { }
        Mock -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest { }
        Mock -ModuleName Omnicit.EntraRBAC Invoke-OERArmRequest { }
        Mock -ModuleName Omnicit.EntraRBAC Export-OERConfiguration { }
    }

    It '<Name> -TenantId <Label> is refused at parameter binding, before any sign-in' -ForEach @(
        @{ Name = 'Get-OERGroup'; Label = 'empty'; Value = ''; Extra = @{ Filter = "startswith(displayName,'oer-a12-')" } }
        @{ Name = 'Get-OERGroup'; Label = 'null'; Value = $null; Extra = @{ Filter = "startswith(displayName,'oer-a12-')" } }
        @{ Name = 'Invoke-OERStructure'; Label = 'empty'; Value = ''; Extra = @{ Path = 'oer-a12-not-a-file.json'; WhatIf = $true } }
        @{ Name = 'Invoke-OERStructure'; Label = 'null'; Value = $null; Extra = @{ Path = 'oer-a12-not-a-file.json'; WhatIf = $true } }
        @{ Name = 'Get-OERSubscription'; Label = 'empty'; Value = ''; Extra = @{} }
        @{ Name = 'New-OERConfiguration'; Label = 'empty'; Value = ''; Extra = @{ TenantAlias = 'oer-a12'; BasePath = 'TestDrive:\a12' } }
        @{ Name = 'Set-OERConfiguration'; Label = 'empty'; Value = ''; Extra = @{ TenantAlias = 'oer-a12'; BasePath = 'TestDrive:\a12' } }
    ) {
        $Caught = $null
        try {
            & $Name -TenantId $Value @Extra -ErrorAction Stop
        } catch {
            $Caught = $PSItem
        }

        $Caught | Should -Not -BeNullOrEmpty
        # Exactly the attribute's id: a Mandatory [string] refuses '' on its own, as
        # ParameterArgumentValidationErrorEmptyStringNotAllowed, so a wildcard would keep the
        # New-OERConfiguration row green with the attribute removed.
        $Caught.FullyQualifiedErrorId | Should -BeExactly "ParameterArgumentValidationError,$Name"
        $Caught.Exception | Should -BeOfType [System.Management.Automation.ParameterBindingException]
        Should -Invoke -ModuleName Omnicit.EntraRBAC Initialize-OERAuth -Times 0 -Scope It
        Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest -Times 0 -Scope It
        Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-OERArmRequest -Times 0 -Scope It
        Should -Invoke -ModuleName Omnicit.EntraRBAC Export-OERConfiguration -Times 0 -Scope It
    }
}
