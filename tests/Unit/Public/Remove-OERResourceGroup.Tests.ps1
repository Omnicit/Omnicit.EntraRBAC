BeforeAll {
    Import-Module Omnicit.EntraRBAC -Force
    . "$PSScriptRoot/../TestHelpers/OERTransportTripwire.ps1"
    Install-OERTransportTripwire
}

AfterAll {
    try { Assert-OERTransportTripwire } finally { Uninstall-OERTransportTripwire }
}

Describe 'Remove-OERResourceGroup' {
    BeforeEach {
        InModuleScope Omnicit.EntraRBAC { $script:_OERAuthState = $null }
        Mock -ModuleName Omnicit.EntraRBAC Initialize-OERAuth { }
        Mock -ModuleName Omnicit.EntraRBAC Resolve-OERScope { '/subscriptions/sub-guid/resourceGroups/rg-net' }
        Mock -ModuleName Omnicit.EntraRBAC Invoke-OERArmRequest { $null }
    }

    It 'DELETEs the resource group when confirmed' {
        Remove-OERResourceGroup -Subscription 'Prod' -Name 'rg-net' -Confirm:$false
        Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-OERArmRequest -Times 1 -ParameterFilter {
            $Method -eq 'DELETE' -and
            $Path -eq '/subscriptions/sub-guid/resourceGroups/rg-net?api-version=2025-04-01'
        }
    }

    It 'has ConfirmImpact High' {
        $Meta = [System.Management.Automation.CommandMetadata](Get-Command Remove-OERResourceGroup)
        $Meta.ConfirmImpact | Should -Be 'High'
    }

    It 'does not DELETE under -WhatIf' {
        Remove-OERResourceGroup -Subscription 'Prod' -Name 'rg-net' -WhatIf
        Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-OERArmRequest -Times 0
    }

    It 'warns that ALL contained resources are destroyed, then DELETEs' {
        $Warnings = @()
        Remove-OERResourceGroup -Subscription 'Prod' -Name 'rg-net' -Confirm:$false `
            -WarningVariable Warnings -WarningAction SilentlyContinue
        $Warnings.Count | Should -BeGreaterThan 0
        $Warnings -join ' ' | Should -Match 'ALL resources'
        Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-OERArmRequest -Times 1 -ParameterFilter {
            $Method -eq 'DELETE'
        }
    }

    It 'does not warn under -WhatIf, because nothing is destroyed' {
        $Warnings = @()
        Remove-OERResourceGroup -Subscription 'Prod' -Name 'rg-net' -WhatIf `
            -WarningVariable Warnings -WarningAction SilentlyContinue
        $Warnings.Count | Should -Be 0
        Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-OERArmRequest -Times 0
    }

    It 'surfaces an ARM DELETE failure as a non-terminating error and scrubs the bearer record' {
        # Same rule as the Graph path: match the cmdlet-QUALIFIED ErrorId (the bare code appears on
        # a dozen auto-recorded pass-throughs and would pass with WriteError deleted), and assert the
        # scrub helper ran, which is the only thing that guards the mandatory bearer-hygiene line.
        Mock -ModuleName Omnicit.EntraRBAC Invoke-OERArmRequest {
            throw [System.Management.Automation.ErrorRecord]::new(
                [System.Exception]::new('AuthorizationFailed: The client does not have authorization.'),
                'AuthorizationFailed',
                [System.Management.Automation.ErrorCategory]::PermissionDenied,
                $null)
        }
        Mock -ModuleName Omnicit.EntraRBAC Remove-OERErrorRecord { }
        $Err = $null
        Remove-OERResourceGroup -Subscription 'Prod' -Name 'rg-net' -Confirm:$false `
            -WarningAction SilentlyContinue -ErrorAction SilentlyContinue -ErrorVariable Err
        Should -Invoke -ModuleName Omnicit.EntraRBAC Remove-OERErrorRecord -Times 1
        @($Err | Where-Object { $_.FullyQualifiedErrorId -eq 'AuthorizationFailed,Remove-OERResourceGroup' }).Count |
            Should -Be 1
    }
}

Describe 'Remove-OERResourceGroup with an ambiguous subscription display name' {
    # Resolve-OERScope runs for REAL here: only the ARM transport is mocked, and its subscription
    # list answers with two subscriptions that share the display name 'Dup Sub'. A resource group
    # delete removes everything in it, so an arbitrary one of the two subscriptions must never be
    # picked. No id below is version-4 shaped.
    BeforeEach {
        InModuleScope Omnicit.EntraRBAC { $script:_OERAuthState = $null }
        Mock -ModuleName Omnicit.EntraRBAC Initialize-OERAuth { }
        Mock -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest { throw 'unexpected Graph request' }
        Mock -ModuleName Omnicit.EntraRBAC Invoke-OERArmRequest {
            [PSCustomObject]@{ value = @(
                [PSCustomObject]@{ subscriptionId = 'aaaa1111-0000-0000-0000-000000000001'; displayName = 'Dup Sub' }
                [PSCustomObject]@{ subscriptionId = 'aaaa1111-0000-0000-0000-000000000002'; displayName = 'Dup Sub' }
            ) }
        } -ParameterFilter { $Path -eq '/subscriptions?api-version=2022-12-01' -and $All }
        Mock -ModuleName Omnicit.EntraRBAC Invoke-OERArmRequest { throw "unexpected ARM call: $Method $Path" }
    }

    It 'reports InvalidScope carrying both candidate ids, and sends no DELETE' {
        $Err = $null
        Remove-OERResourceGroup -Subscription 'Dup Sub' -Name 'rg-net' -Confirm:$false `
            -WarningAction SilentlyContinue -ErrorAction SilentlyContinue -ErrorVariable Err

        # Positive proof first: the subscription list was read, exactly once. Then the write: no DELETE
        # went to any subscription. Only then is the call count held to that single read.
        Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-OERArmRequest -Times 1 -Exactly -ParameterFilter {
            $Path -eq '/subscriptions?api-version=2022-12-01' -and $All
        }
        Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-OERArmRequest -Times 0 -ParameterFilter { $Method -eq 'DELETE' }
        Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-OERArmRequest -Times 1 -Exactly

        $Mine = @($Err | Where-Object { $_.FullyQualifiedErrorId -eq 'InvalidScope,Remove-OERResourceGroup' })
        $Mine.Count | Should -Be 1
        $Mine[0].Exception.Message | Should -BeLike "Subscription display name 'Dup Sub' matches 2 subscriptions (aaaa1111-0000-0000-0000-000000000001, aaaa1111-0000-0000-0000-000000000002). *Re-run with the subscription id."
    }
}
