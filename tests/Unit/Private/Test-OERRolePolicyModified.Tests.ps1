BeforeDiscovery {
    # One case per metadata shape, each run as a hashtable and as a PSCustomObject: ARM answers are
    # read as PSCustomObjects, and the predicate is the single owner of the rule, so it must read both
    # the same way. The untouched shape is the one measured live (2026-10-10) on 965 of 967 rows: the
    # policy carries an id and an EMPTY lastModifiedBy object, and no lastModifiedDateTime key at all.
    $Shapes = @(
        @{ Case = 'a date only'; Expected = $true
            Metadata = @{ id = 'policy-1'; lastModifiedDateTime = '2026-06-01T10:00:00Z' } }
        @{ Case = 'a date read as a DateTime'; Expected = $true
            Metadata = @{ id = 'policy-1'; lastModifiedDateTime = [datetime]'2026-08-01T10:00:00Z'; lastModifiedBy = @{} } }
        @{ Case = 'lastModifiedBy.id only'; Expected = $true
            Metadata = @{ id = 'policy-1'; lastModifiedBy = @{ id = '11111111-1111-1111-1111-111111111111' } } }
        @{ Case = 'lastModifiedBy.displayName only'; Expected = $true
            Metadata = @{ id = 'policy-1'; lastModifiedBy = @{ displayName = 'Person One' } } }
        @{ Case = 'the measured changed shape (a date and a display name)'; Expected = $true
            Metadata = @{ id = 'policy-1'; lastModifiedDateTime = '2026-08-01T10:00:00Z'; lastModifiedBy = @{ displayName = 'Person One' } } }
        @{ Case = 'the measured untouched shape (an empty lastModifiedBy, no date key)'; Expected = $false
            Metadata = @{ id = 'policy-1'; lastModifiedBy = @{} } }
        @{ Case = 'white space values'; Expected = $false
            Metadata = @{ id = 'policy-1'; lastModifiedDateTime = '   '; lastModifiedBy = @{ id = ' '; displayName = "`t" } } }
        @{ Case = 'null values'; Expected = $false
            Metadata = @{ id = 'policy-1'; lastModifiedDateTime = $null; lastModifiedBy = @{ id = $null; displayName = $null; type = 'User' } } }
        @{ Case = 'no lastModifiedBy key and no date'; Expected = $false
            Metadata = @{ id = 'policy-1' } }
        @{ Case = 'an empty policy object'; Expected = $false
            Metadata = @{} }
    )
    $script:Cases = foreach ($Shape in $Shapes) {
        foreach ($Form in @('Hashtable', 'PSCustomObject')) {
            @{ Case = $Shape.Case; Expected = $Shape.Expected; Metadata = $Shape.Metadata; Form = $Form }
        }
    }
}

BeforeAll {
    Import-Module Omnicit.EntraRBAC -Force
    . "$PSScriptRoot/../TestHelpers/OERTransportTripwire.ps1"
    Install-OERTransportTripwire

    # A hashtable, recursively as PSCustomObjects; anything else as it is.
    function ConvertTo-TestObject {
        param($Value)
        if ($Value -is [hashtable]) {
            $Ordered = [ordered]@{}
            foreach ($Key in $Value.Keys) { $Ordered[$Key] = ConvertTo-TestObject -Value $Value[$Key] }
            return [PSCustomObject]$Ordered
        }
        $Value
    }
}

AfterAll {
    try { Assert-OERTransportTripwire } finally { Uninstall-OERTransportTripwire }
}

Describe 'Test-OERRolePolicyModified' {
    It 'returns $null when there is no metadata to judge' {
        # Counted on the call itself, inside the module scope, so the count does not rest on how a
        # variable holds an empty result: 1 for a returned $null, 0 for a bare return (measured with
        # that mutant).
        $Answers = InModuleScope Omnicit.EntraRBAC { @(Test-OERRolePolicyModified -Metadata $null).Count }
        $Answers | Should -Be 1 -Because 'the predicate answers once, with a null, and never with nothing'
        $Result = InModuleScope Omnicit.EntraRBAC { Test-OERRolePolicyModified -Metadata $null }
        $null -eq $Result | Should -BeTrue
    }

    It 'returns <Expected> for <Case> (<Form>)' -ForEach $script:Cases {
        $Value = if ($Form -eq 'Hashtable') { $Metadata } else { ConvertTo-TestObject -Value $Metadata }
        $Result = InModuleScope Omnicit.EntraRBAC -Parameters @{ M = $Value } {
            param($M)
            Test-OERRolePolicyModified -Metadata $M
        }
        @($Result).Count | Should -Be 1
        $Result | Should -BeOfType [bool]
        $Result | Should -Be $Expected
    }

    It 'declares [OutputType([bool])]' {
        $Command = InModuleScope Omnicit.EntraRBAC { Get-Command Test-OERRolePolicyModified }
        @($Command.OutputType.Type) | Should -Contain ([bool])
    }
}
