# Known-answer suite for the transport tripwire (tests/Unit/TestHelpers/OERTransportTripwire.ps1).
#
# Rule for every test below: a transport name is NEVER called by name. It is resolved first, what it
# resolved to is asserted, and only the resolved command object is invoked -- so a broken
# installation fails an assertion and can never reach a real cmdlet.
#
# The suite holds its OWN expected list, never Get-OERTransportTripwireName, so deleting a name from
# the helper turns it red.

BeforeDiscovery {
    $script:Expected = @(
        @{ Name = 'Get-AzToken'; Arguments = @{} }
        @{ Name = 'Connect-MgGraph'; Arguments = @{} }
        @{ Name = 'Disconnect-MgGraph'; Arguments = @{} }
        @{ Name = 'Invoke-MgGraphRequest'; Arguments = @{ Method = 'GET'; Uri = 'v1.0/oer-tripwire-known-answer' } }
        @{ Name = 'Invoke-WebRequest'; Arguments = @{ Uri = 'https://oer-tripwire.invalid/known-answer' } }
        @{ Name = 'Invoke-RestMethod'; Arguments = @{ Uri = 'https://oer-tripwire.invalid/known-answer' } }
    )
}

BeforeAll {
    Import-Module Omnicit.EntraRBAC -Force
    . "$PSScriptRoot/OERTransportTripwire.ps1"
    . "$PSScriptRoot/OERConfirmHost.ps1"
    Install-OERTransportTripwire
    Mock -ModuleName Omnicit.EntraRBAC Initialize-OERAuth { }

    # Resolves a name from the module's scope, where module code resolves it. -CommandType narrows
    # the lookup; without it, the result is what an unqualified call in module code would run.
    function Resolve-TripwireKnownAnswerCommand {
        param(
            [Parameter(Mandatory)]
            [string]$Name,

            [string]$CommandType
        )
        $Module = Get-Module -Name Omnicit.EntraRBAC | Select-Object -First 1
        if ($CommandType) {
            & $Module { param($N, $T) Get-Command -Name $N -CommandType $T -ErrorAction Ignore } $Name $CommandType
        } else {
            & $Module { param($N) Get-Command -Name $N -ErrorAction Ignore } $Name
        }
    }

    # Invokes a RESOLVED command object from the module's scope, never a name.
    function Invoke-TripwireKnownAnswerCommand {
        param(
            [Parameter(Mandatory)]
            [System.Management.Automation.CommandInfo]$Command,

            [hashtable]$Arguments = @{}
        )
        $Module = Get-Module -Name Omnicit.EntraRBAC | Select-Object -First 1
        & $Module { param($C, $A) & $C @A } $Command $Arguments
    }
}

AfterAll {
    try { Assert-OERTransportTripwire } finally { Uninstall-OERTransportTripwire }
}

Describe 'OERTransportTripwire' {
    # Per test, not only in the root BeforeAll: the re-import test below replaces the module
    # instance, and the root BeforeAll's mock stays on the old one, so every test after it would
    # otherwise run against a module whose Initialize-OERAuth is not mocked.
    BeforeEach {
        Mock -ModuleName Omnicit.EntraRBAC Initialize-OERAuth { }
    }

    It 'the helper names exactly the expected six commands' -ForEach @(@{ ExpectedNames = @($script:Expected | ForEach-Object { $_.Name }) }) {
        @($ExpectedNames).Count | Should -Be 6 -Because 'the known-answer list itself must not be empty or short, or the comparison below proves nothing'
        (@(Get-OERTransportTripwireName) | Sort-Object) -join ',' | Should -Be ((@($ExpectedNames) | Sort-Object) -join ',')
    }

    It '<Name> resolves from the module scope to the tripwire' -ForEach $script:Expected {
        $Resolved = Resolve-TripwireKnownAnswerCommand -Name $Name
        $Resolved | Should -BeOfType ([System.Management.Automation.FunctionInfo])
        Test-OERTransportTripwireFunction -Command $Resolved | Should -BeTrue
    }

    It "<Name>'s replacement has exactly the cmdlet's parameters and no dynamicparam" -ForEach $script:Expected {
        $Function = Resolve-TripwireKnownAnswerCommand -Name $Name -CommandType Function
        Test-OERTransportTripwireFunction -Command $Function | Should -BeTrue
        $Cmdlet = Get-Command -Name $Name -CommandType Cmdlet
        $Cmdlet | Should -BeOfType ([System.Management.Automation.CmdletInfo])

        (@($Function.Parameters.Keys) | Sort-Object) -join ',' | Should -Be ((@($Cmdlet.Parameters.Keys) | Sort-Object) -join ',')
        $Function.ParameterSets.Count | Should -Be $Cmdlet.ParameterSets.Count

        # A function made from scriptblock text carries a ScriptBlockAst, not a FunctionDefinitionAst,
        # so its dynamicparam block is read from the Ast itself (an .Ast.Body read is always null
        # here and would prove nothing). The param and end blocks are asserted first so the null
        # below is not vacuous.
        $Ast = $Function.ScriptBlock.Ast
        if ($Ast -is [System.Management.Automation.Language.FunctionDefinitionAst]) { $Ast = $Ast.Body }
        $Ast | Should -BeOfType ([System.Management.Automation.Language.ScriptBlockAst])
        $Ast.ParamBlock | Should -Not -BeNullOrEmpty
        $Ast.EndBlock | Should -Not -BeNullOrEmpty
        $Ast.DynamicParamBlock | Should -BeNullOrEmpty
    }

    It 'a Mock -ModuleName on <Name> still wins and records no hit' -ForEach $script:Expected {
        Mock -ModuleName Omnicit.EntraRBAC -CommandName $Name -MockWith { 'mocked' }
        $Before = $global:OERTransportTripwireHits.Count

        $Resolved = Resolve-TripwireKnownAnswerCommand -Name $Name
        $Resolved.CommandType | Should -Be 'Alias'
        $Module = Get-Module -Name Omnicit.EntraRBAC | Select-Object -First 1
        $Target = & $Module { param($A) $A.ResolvedCommand } $Resolved
        $Target | Should -BeOfType ([System.Management.Automation.FunctionInfo])
        Test-OERTransportTripwireFunction -Command $Target | Should -BeFalse

        Invoke-TripwireKnownAnswerCommand -Command $Resolved -Arguments $Arguments | Should -Be 'mocked'
        $global:OERTransportTripwireHits.Count | Should -Be $Before
        Should -Invoke -ModuleName Omnicit.EntraRBAC -CommandName $Name -Times 1 -Exactly
    }

    It 'an unmocked call to <Name> is recorded and refused' -ForEach $script:Expected {
        $Resolved = Resolve-TripwireKnownAnswerCommand -Name $Name -CommandType Function
        Test-OERTransportTripwireFunction -Command $Resolved | Should -BeTrue
        $Before = $global:OERTransportTripwireHits.Count

        $Message = try {
            Invoke-TripwireKnownAnswerCommand -Command $Resolved -Arguments $Arguments
            'RETURNED'
        } catch {
            $_.Exception.Message
        }

        $Message | Should -BeLike '*OER transport tripwire*'
        $global:OERTransportTripwireHits.Count | Should -Be ($Before + 1)
        $global:OERTransportTripwireHits[$global:OERTransportTripwireHits.Count - 1].Command | Should -Be $Name
        $global:OERTransportTripwireHits.RemoveAt($global:OERTransportTripwireHits.Count - 1)
    }

    It 'a hit records parameter names, never values' {
        $Resolved = Resolve-TripwireKnownAnswerCommand -Name 'Invoke-WebRequest' -CommandType Function
        Test-OERTransportTripwireFunction -Command $Resolved | Should -BeTrue
        $Before = $global:OERTransportTripwireHits.Count

        try {
            Invoke-TripwireKnownAnswerCommand -Command $Resolved -Arguments @{ Uri = 'https://oer-tripwire.invalid/NOT-A-REAL-TOKEN-sentinel-value' }
        } catch {
            $null = $_
        }

        $global:OERTransportTripwireHits.Count | Should -Be ($Before + 1)
        $Record = $global:OERTransportTripwireHits[$global:OERTransportTripwireHits.Count - 1]
        try {
            $Record.Parameters | Should -Be 'Uri'
            ($Record | Out-String) | Should -Not -BeLike '*sentinel*'
        } finally {
            $global:OERTransportTripwireHits.RemoveAt($global:OERTransportTripwireHits.Count - 1)
        }
    }

    It 'resolution survives a re-import of the module' -ForEach @(@{ ExpectedNames = @($script:Expected | ForEach-Object { $_.Name }) }) {
        $Old = Get-Module -Name Omnicit.EntraRBAC | Select-Object -First 1
        Import-Module Omnicit.EntraRBAC -Force
        $New = Get-Module -Name Omnicit.EntraRBAC | Select-Object -First 1
        [object]::ReferenceEquals($Old, $New) | Should -BeFalse -Because 'the check below has to run against a NEW module instance'
        Mock -ModuleName Omnicit.EntraRBAC Initialize-OERAuth { }

        @($ExpectedNames).Count | Should -Be 6
        foreach ($Name in $ExpectedNames) {
            $Resolved = Resolve-TripwireKnownAnswerCommand -Name $Name
            $Resolved | Should -BeOfType ([System.Management.Automation.FunctionInfo])
            Test-OERTransportTripwireFunction -Command $Resolved | Should -BeTrue
        }
    }

    It 'Assert-OERTransportTripwire fails on a recorded hit' {
        $global:OERTransportTripwireHits.Add([pscustomobject]@{ Command = 'Invoke-WebRequest'; Caller = 'known-answer'; Parameters = 'Uri' })
        try {
            { Assert-OERTransportTripwire } | Should -Throw -ExpectedMessage '*reached Invoke-WebRequest from known-answer*'
        } finally {
            $global:OERTransportTripwireHits.RemoveAt($global:OERTransportTripwireHits.Count - 1)
        }
    }

    It 'Assert-OERTransportTripwire fails when a name no longer resolves' {
        # Install-OERTransportTripwire starts a new empty list, so any hit already recorded in this
        # file is carried over and stays visible to the root AfterAll.
        $Carried = @($global:OERTransportTripwireHits)
        try {
            # Unqualified on purpose: Remove-Item honours no scope qualifier on the function: drive,
            # so 'function:global:...' would remove nothing (measured). From here the nearest
            # definition is the global replacement, which is exactly what the precondition proves.
            Remove-Item -Path function:Disconnect-MgGraph
            Test-OERTransportTripwireFunction -Command (Resolve-TripwireKnownAnswerCommand -Name 'Disconnect-MgGraph' -CommandType Function) | Should -BeFalse -Because 'the replacement has to be gone, or the assertion below proves nothing'
            { Assert-OERTransportTripwire } | Should -Throw -ExpectedMessage '*Disconnect-MgGraph no longer resolves*'
        } finally {
            Install-OERTransportTripwire
            foreach ($Hit in $Carried) { $global:OERTransportTripwireHits.Add($Hit) }
        }
    }

    It 'the answering runspace refuses to run without the tripwire' {
        $Saved = $global:OERTransportTripwireDefinitions
        try {
            $global:OERTransportTripwireDefinitions = $null
            { Invoke-OERWithConfirmAnswer -Script { 'x' } } | Should -Throw -ExpectedMessage '*refusing to run module code in a second runspace*'
        } finally {
            $global:OERTransportTripwireDefinitions = $Saved
        }
    }

    It 'the answering runspace installs the tripwire and shares the hit list' {
        $Before = $global:OERTransportTripwireHits.Count
        $Result = Invoke-OERWithConfirmAnswer -Answer '&Yes' -Script {
            Import-Module Omnicit.EntraRBAC -Force -ErrorAction Stop
            $M = Get-Module Omnicit.EntraRBAC
            $R = & $M { Get-Command -Name Invoke-MgGraphRequest -CommandType Function }
            if (-not ($R -is [System.Management.Automation.FunctionInfo] -and $R.ScriptBlock.ToString().Contains('OER-TRANSPORT-TRIPWIRE'))) {
                'NOT-TRIPWIRE'
            } else {
                try {
                    & $M { param($C) & $C -Method GET -Uri 'v1.0/oer-tripwire-answering' } $R
                    'RETURNED'
                } catch {
                    'REFUSED'
                }
            }
        }

        $Added = $global:OERTransportTripwireHits.Count - $Before
        try {
            @($Result.Output)[-1] | Should -Be 'REFUSED'
            $Added | Should -Be 1
            $global:OERTransportTripwireHits[$global:OERTransportTripwireHits.Count - 1].Command | Should -Be 'Invoke-MgGraphRequest'
        } finally {
            for ($Index = 0; $Index -lt $Added; $Index++) {
                $global:OERTransportTripwireHits.RemoveAt($global:OERTransportTripwireHits.Count - 1)
            }
        }
    }

    # A check that fails with an error in the answering runspace must fail the run. Measured without
    # that rule: with the hit list gone there, a removed replacement raised "You cannot call a method
    # on a null-valued expression" inside the check, nothing was recorded, and the run reported
    # success; with the definitions gone, the check raised a parameter validation error instead.
    It 'the check after the scenario fails when <Case>' -ForEach @(
        @{
            Case     = 'the answering runspace lost its definitions'
            Scenario = { $global:OERTransportTripwireDefinitions = $null }
        }
        @{
            Case     = 'the answering runspace lost its hit list and a replacement'
            Scenario = {
                $global:OERTransportTripwireHits = $null
                Remove-Item -Path function:Invoke-WebRequest
            }
        }
    ) {
        $Before = $global:OERTransportTripwireHits.Count
        try {
            { Invoke-OERWithConfirmAnswer -Script $Scenario } | Should -Throw -ExpectedMessage '*the check in the second runspace failed*'
        } finally {
            # The lost-definitions case leaves a nameless record before the check fails; it is no
            # transport hit, and it must not fail this file's root AfterAll.
            for ($Index = $global:OERTransportTripwireHits.Count; $Index -gt $Before; $Index--) {
                $global:OERTransportTripwireHits.RemoveAt($global:OERTransportTripwireHits.Count - 1)
            }
        }
    }

    # LAST in the file: it uninstalls, and puts the tripwire back in a finally.
    It 'uninstall restores the cmdlets, and install puts the tripwire back' -ForEach @(@{ ExpectedNames = @($script:Expected | ForEach-Object { $_.Name }) }) {
        @($ExpectedNames).Count | Should -Be 6
        $Carried = @($global:OERTransportTripwireHits)
        try {
            Uninstall-OERTransportTripwire
            foreach ($Name in $ExpectedNames) {
                # Resolved only, never invoked: with the tripwire gone this is the real cmdlet.
                $Resolved = Resolve-TripwireKnownAnswerCommand -Name $Name
                $Resolved | Should -BeOfType ([System.Management.Automation.CmdletInfo])
            }
        } finally {
            Install-OERTransportTripwire
            foreach ($Hit in $Carried) { $global:OERTransportTripwireHits.Add($Hit) }
        }
        foreach ($Name in $ExpectedNames) {
            $Resolved = Resolve-TripwireKnownAnswerCommand -Name $Name
            $Resolved | Should -BeOfType ([System.Management.Automation.FunctionInfo])
            Test-OERTransportTripwireFunction -Command $Resolved | Should -BeTrue
        }
    }
}
