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

Describe 'Resolve-OERStructureDefault' {
    It 'returns the Defaults value for a known key (hashtable Defaults)' {
        InModuleScope $script:moduleName {
            Mock Get-OERConfiguration { [PSCustomObject]@{ Defaults = @{ ActivationMaxHours = 8; Catalog = 'CAT-IT' } } }
            Resolve-OERStructureDefault -TenantAlias 'omnicit' -Name 'ActivationMaxHours' | Should -Be 8
            Resolve-OERStructureDefault -TenantAlias 'omnicit' -Name 'Catalog' | Should -Be 'CAT-IT'
        }
    }
    It 'returns an array default intact (PrimaryApprovers)' {
        InModuleScope $script:moduleName {
            Mock Get-OERConfiguration { [PSCustomObject]@{ Defaults = @{ PrimaryApprovers = @('a', 'b') } } }
            @(Resolve-OERStructureDefault -TenantAlias 'omnicit' -Name 'PrimaryApprovers').Count | Should -Be 2
        }
    }
    It 'returns null for an unknown key' {
        InModuleScope $script:moduleName {
            Mock Get-OERConfiguration { [PSCustomObject]@{ Defaults = @{ ActivationMaxHours = 8 } } }
            Resolve-OERStructureDefault -TenantAlias 'omnicit' -Name 'AuthenticationContextId' | Should -BeNullOrEmpty
        }
    }
    It 'returns null when no alias is given' {
        InModuleScope $script:moduleName {
            Resolve-OERStructureDefault -Name 'ActivationMaxHours' | Should -BeNullOrEmpty
        }
    }
    It 'returns null when Defaults section is absent' {
        InModuleScope $script:moduleName {
            Mock Get-OERConfiguration { [PSCustomObject]@{ TenantId = 'x' } }
            Resolve-OERStructureDefault -TenantAlias 'omnicit' -Name 'Catalog' | Should -BeNullOrEmpty
        }
    }
    It 'returns null for a profile that does not exist (Get-OERConfiguration writes no error for it)' {
        InModuleScope $script:moduleName {
            Mock Get-OERConfiguration { }
            Resolve-OERStructureDefault -TenantAlias 'absent' -Name 'Catalog' | Should -BeNullOrEmpty
            # The positive half: the profile was looked up, and found nothing -- which is "no default",
            # and the only thing that is.
            Should -Invoke Get-OERConfiguration -Times 1 -Exactly -ParameterFilter { $TenantAlias -eq 'absent' }
        }
    }

    Context 'a failed profile read is not "no default"' {
        # INVERTED. These two Its pinned a throw from the profile read -- which is exactly what a
        # profile that cannot be parsed, or declares no TenantId, or names an unsupported Environment
        # produces -- as $null, i.e. "no default". The apply engine then reported an approval stage as
        # having "no Tenant Profile PrimaryApprovers default", sending the operator to add a default
        # to a profile that already holds one but cannot be read. A MISSING profile still returns
        # $null (the It above): Get-OERConfiguration writes no error for it.
        #
        # The failure mock is a CMDLET failure, never Write-Error: this helper calls
        # Get-OERConfiguration with -ErrorAction Stop, and only a mock that goes through the cmdlet's
        # own WriteError is promoted to a terminating error by it (a Write-Error mock is not; measured).
        BeforeAll {
            $script:MalformedProfileRead = {
                [CmdletBinding()] param([string]$TenantAlias, [string]$BasePath)
                $PSCmdlet.WriteError([System.Management.Automation.ErrorRecord]::new(
                        [System.Exception]::new("Tenant Profile 'broken' at 'profile-path' could not be parsed and was skipped: profile read scrub marker."),
                        'TenantProfileMalformed', [System.Management.Automation.ErrorCategory]::InvalidData, 'profile-path'))
            }
        }

        It 'rethrows the failed profile read as itself instead of returning null' {
            InModuleScope $script:moduleName -Parameters @{ FailRead = $script:MalformedProfileRead } {
                Mock Get-OERConfiguration $FailRead
                $Caught = $null
                $Result = 'not-assigned'
                try {
                    $Result = Resolve-OERStructureDefault -TenantAlias 'broken' -Name 'PrimaryApprovers'
                } catch {
                    $Caught = $PSItem
                }
                # The positive half: the profile read was reached, once, for this alias.
                Should -Invoke Get-OERConfiguration -Times 1 -Exactly -ParameterFilter { $TenantAlias -eq 'broken' }
                $Caught | Should -Not -BeNullOrEmpty
                $Caught.FullyQualifiedErrorId | Should -Match '^TenantProfileMalformed'
                $Caught.CategoryInfo.Category | Should -Be 'InvalidData'
                $Caught.Exception.Message | Should -Match 'profile read scrub marker'
                # No fact was returned: not $null, and not any default.
                $Result | Should -Be 'not-assigned'
            }
        }

        It 'scrubs the failed profile read record before rethrowing it (bearer hygiene)' {
            InModuleScope $script:moduleName -Parameters @{ FailRead = $script:MalformedProfileRead } {
                Mock Get-OERConfiguration $FailRead
                Mock Remove-OERErrorRecord { }
                $Caught = $null
                try {
                    Resolve-OERStructureDefault -TenantAlias 'broken' -Name 'Catalog'
                } catch {
                    $Caught = $PSItem
                }
                # The catch rethrows the SAME record, which PowerShell re-appends to $global:Error at
                # the next call boundary whether or not the scrub ran, so only the mocked call detects
                # a deleted scrub line -- beside a positive assertion that the catch was reached.
                $Caught | Should -Not -BeNullOrEmpty
                $Caught.Exception.Message | Should -Match 'profile read scrub marker'
                Should -Invoke Remove-OERErrorRecord -Times 1 -Exactly -ParameterFilter {
                    $Record.Exception.Message -match 'profile read scrub marker'
                }
            }
        }
    }
}
