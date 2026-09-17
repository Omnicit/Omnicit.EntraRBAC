BeforeAll {
    Import-Module Omnicit.EntraRBAC -Force
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
