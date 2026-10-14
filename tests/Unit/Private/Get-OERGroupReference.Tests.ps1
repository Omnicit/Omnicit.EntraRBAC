BeforeAll {
    Import-Module Omnicit.EntraRBAC -Force
    . "$PSScriptRoot/../TestHelpers/OERTransportTripwire.ps1"
    Install-OERTransportTripwire
}

AfterAll {
    try { Assert-OERTransportTripwire } finally { Uninstall-OERTransportTripwire }
}

Describe 'Get-OERGroupReference' {
    # BL-131 (R-2, Task 3c). The single owner of how the export names a group it references as a
    # principal: its display name only when the index of every group in the tenant was read and exactly
    # one group, this one, carries that name; otherwise its object id. Pure: no request, no error
    # record, no throw. No id below is version-4 shaped.
    BeforeAll {
        # An index the way Get-OERGroupNameIndex returns one: lower-cased ids under names compared
        # without regard to letter case.
        $script:NewIndex = {
            param([hashtable]$IdsByName, [bool]$Read = $true)
            $Ids = [System.Collections.Generic.Dictionary[string, System.Collections.Generic.List[string]]]::new([System.StringComparer]::OrdinalIgnoreCase)
            foreach ($Name in $IdsByName.Keys) {
                $Ids[$Name] = [System.Collections.Generic.List[string]]::new()
                foreach ($One in @($IdsByName[$Name])) { $Ids[$Name].Add($One) }
            }
            [PSCustomObject]@{ Read = $Read; IdsByName = $(if ($Read) { $Ids } else { $null }); Message = $(if ($Read) { $null } else { 'Could not list every group to count the names groups share: denied' }) }
        }
        $script:GroupA = 'aaaa3333-0000-0000-0000-00000000000a'
        $script:GroupB = 'aaaa3333-0000-0000-0000-00000000000b'
    }

    It 'returns the name when exactly this group carries it' {
        $Index = & $script:NewIndex @{ 'Admins' = @($script:GroupA); 'Readers' = @($script:GroupB) }
        InModuleScope Omnicit.EntraRBAC -Parameters @{ Index = $Index; Id = $script:GroupA } {
            param($Index, $Id)
            Mock Invoke-OERGraphRequest { throw 'no request is expected' }
            Get-OERGroupReference -Id $Id -Name 'Admins' -Index $Index | Should -BeExactly 'Admins'
            Should -Invoke Invoke-OERGraphRequest -Times 0
        }
    }

    It 'returns the id when another group carries the name too' {
        $Index = & $script:NewIndex @{ 'Admins' = @($script:GroupA, $script:GroupB) }
        InModuleScope Omnicit.EntraRBAC -Parameters @{ Index = $Index; Id = $script:GroupA } {
            param($Index, $Id)
            Get-OERGroupReference -Id $Id -Name 'Admins' -Index $Index | Should -BeExactly $Id
        }
    }

    It 'returns the id when the index was not read, whatever it holds' {
        $Index = & $script:NewIndex @{ 'Admins' = @($script:GroupA) }
        # A failed index that still carries a dictionary is never trusted: Read decides.
        $Index.Read = $false
        InModuleScope Omnicit.EntraRBAC -Parameters @{ Index = $Index; Id = $script:GroupA } {
            param($Index, $Id)
            Get-OERGroupReference -Id $Id -Name 'Admins' -Index $Index | Should -BeExactly $Id
        }
    }

    It 'returns the id when the index is a failed read with no dictionary, or null' {
        $Failed = & $script:NewIndex @{} -Read $false
        InModuleScope Omnicit.EntraRBAC -Parameters @{ Failed = $Failed; Id = $script:GroupA } {
            param($Failed, $Id)
            Get-OERGroupReference -Id $Id -Name 'Admins' -Index $Failed | Should -BeExactly $Id
            Get-OERGroupReference -Id $Id -Name 'Admins' -Index $null | Should -BeExactly $Id
        }
    }

    It 'returns the id, and does not throw, when an index marked read carries no dictionary' {
        $Index = [PSCustomObject]@{ Read = $true; IdsByName = $null; Message = $null }
        InModuleScope Omnicit.EntraRBAC -Parameters @{ Index = $Index; Id = $script:GroupA } {
            param($Index, $Id)
            { Get-OERGroupReference -Id $Id -Name 'Admins' -Index $Index -ErrorAction Stop } | Should -Not -Throw
            Get-OERGroupReference -Id $Id -Name 'Admins' -Index $Index | Should -BeExactly $Id
        }
    }

    It 'returns the id, and does not throw, when the index does not hold the name' {
        $Index = & $script:NewIndex @{ 'Readers' = @($script:GroupB) }
        InModuleScope Omnicit.EntraRBAC -Parameters @{ Index = $Index; Id = $script:GroupA } {
            param($Index, $Id)
            { Get-OERGroupReference -Id $Id -Name 'Admins' -Index $Index -ErrorAction Stop } | Should -Not -Throw
            Get-OERGroupReference -Id $Id -Name 'Admins' -Index $Index | Should -BeExactly $Id
        }
    }

    It 'returns the id when the one group under the name is another group' {
        $Index = & $script:NewIndex @{ 'Admins' = @($script:GroupB) }
        InModuleScope Omnicit.EntraRBAC -Parameters @{ Index = $Index; Id = $script:GroupA } {
            param($Index, $Id)
            Get-OERGroupReference -Id $Id -Name 'Admins' -Index $Index | Should -BeExactly $Id
        }
    }

    It 'finds the name in any letter case and compares the id without regard to letter case, returning the name as given' {
        $Index = & $script:NewIndex @{ 'Admins' = @($script:GroupA) }
        InModuleScope Omnicit.EntraRBAC -Parameters @{ Index = $Index; Id = $script:GroupA.ToUpperInvariant() } {
            param($Index, $Id)
            Get-OERGroupReference -Id $Id -Name 'ADMINS' -Index $Index | Should -BeExactly 'ADMINS'
        }
    }

    It 'returns the id for a blank or null name, even when the index holds one under it' {
        $Index = & $script:NewIndex @{ ' ' = @($script:GroupA) }
        InModuleScope Omnicit.EntraRBAC -Parameters @{ Index = $Index; Id = $script:GroupA } {
            param($Index, $Id)
            Get-OERGroupReference -Id $Id -Name ' ' -Index $Index | Should -BeExactly $Id
            Get-OERGroupReference -Id $Id -Name '' -Index $Index | Should -BeExactly $Id
            Get-OERGroupReference -Id $Id -Name $null -Index $Index | Should -BeExactly $Id
        }
    }

    It 'declares a string output, a mandatory id and a mandatory index that may be null' {
        $Command = InModuleScope Omnicit.EntraRBAC { Get-Command Get-OERGroupReference }
        @($Command.OutputType.Type) | Should -Be @([string])
        $Command.Parameters['Id'].Attributes.Where({ $_ -is [System.Management.Automation.ParameterAttribute] }).Mandatory | Should -BeTrue
        $Command.Parameters['Index'].Attributes.Where({ $_ -is [System.Management.Automation.ParameterAttribute] }).Mandatory | Should -BeTrue
        @($Command.Parameters['Index'].Attributes | Where-Object { $_ -is [System.Management.Automation.AllowNullAttribute] }).Count | Should -Be 1
    }
}
