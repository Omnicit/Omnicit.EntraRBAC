BeforeAll {
    Import-Module Omnicit.EntraRBAC -Force
}

Describe 'Set-OERResourceGroup' {
    BeforeEach {
        InModuleScope Omnicit.EntraRBAC { $script:_OERAuthState = $null }
        Mock -ModuleName Omnicit.EntraRBAC Initialize-OERAuth { }
        Mock -ModuleName Omnicit.EntraRBAC Resolve-OERScope { '/subscriptions/sub-guid/resourceGroups/rg-net' }
    }

    It 'GETs then PUTs preserving location and replacing tags' {
        Mock -ModuleName Omnicit.EntraRBAC Invoke-OERArmRequest -ParameterFilter { $Method -eq 'GET' -or -not $Method } {
            [PSCustomObject]@{ id = '/subscriptions/sub-guid/resourceGroups/rg-net'; name = 'rg-net'; location = 'westeurope'; tags = [PSCustomObject]@{ old = 'x' }; properties = [PSCustomObject]@{ provisioningState = 'Succeeded' } }
        }
        Mock -ModuleName Omnicit.EntraRBAC Invoke-OERArmRequest -ParameterFilter { $Method -eq 'PUT' } {
            [PSCustomObject]@{ id = '/subscriptions/sub-guid/resourceGroups/rg-net'; name = 'rg-net'; location = 'westeurope'; tags = [PSCustomObject]@{ env = 'prod' }; properties = [PSCustomObject]@{ provisioningState = 'Succeeded' } }
        }
        $Result = Set-OERResourceGroup -Subscription 'Prod' -Name 'rg-net' -Tag @{ env = 'prod' }
        $Result.PSObject.TypeNames[0] | Should -Be 'Omnicit.EntraRBAC.ResourceGroup'
        Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-OERArmRequest -Times 1 -ParameterFilter {
            $Method -eq 'PUT' -and $Body.location -eq 'westeurope' -and $Body.tags.env -eq 'prod'
        }
    }

    It 'errors ResourceGroupNotFound when the GET 404s' {
        Mock -ModuleName Omnicit.EntraRBAC Invoke-OERArmRequest {
            $Rec = [System.Management.Automation.ErrorRecord]::new(
                [System.Exception]::new('not found'), 'ResourceGroupNotFound',
                [System.Management.Automation.ErrorCategory]::ObjectNotFound, $null)
            throw $Rec
        }
        # This is the only test that enters the GET catch at Set-OERResourceGroup.ps1:78-86, so it
        # is the only possible cover for that catch's mandatory Remove-OERErrorRecord line.
        Mock -ModuleName Omnicit.EntraRBAC Remove-OERErrorRecord { }
        $null = Set-OERResourceGroup -Subscription 'Prod' -Name 'missing' -Tag @{ a = 'b' } -ErrorAction SilentlyContinue -ErrorVariable Err
        Should -Invoke -ModuleName Omnicit.EntraRBAC Remove-OERErrorRecord -Times 1
        # $Err[0] is the MOCK's record, not the cmdlet's: PowerShell auto-records the thrown record
        # at roughly a dozen call boundaries before the catch runs (13 records here; the mock throws
        # the bare code 'ResourceGroupNotFound' itself, so a -BeLike on index 0 passed even with the
        # cmdlet's Write-CmdletError deleted). Match the cmdlet-QUALIFIED id instead.
        @($Err | Where-Object { $_.FullyQualifiedErrorId -eq 'ResourceGroupNotFound,Set-OERResourceGroup' }).Count |
            Should -Be 1
    }

    It 'does not PUT under -WhatIf' {
        Mock -ModuleName Omnicit.EntraRBAC Invoke-OERArmRequest {
            [PSCustomObject]@{ id = '/subscriptions/sub-guid/resourceGroups/rg-net'; name = 'rg-net'; location = 'westeurope'; properties = [PSCustomObject]@{ provisioningState = 'Succeeded' } }
        }
        Set-OERResourceGroup -Subscription 'Prod' -Name 'rg-net' -Tag @{ env = 'prod' } -WhatIf
        # T4: the read (GET/no-Method) must happen; the write (PUT) must not
        Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-OERArmRequest -Times 1 -ParameterFilter { $Method -eq 'GET' -or -not $Method }
        Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-OERArmRequest -Times 0 -ParameterFilter { $Method -eq 'PUT' }
    }

    It 'declares ConfirmImpact Medium for parity with the ARM create/update cohort' {
        $Attr = (Get-Command Set-OERResourceGroup).ScriptBlock.Attributes |
            Where-Object { $_ -is [System.Management.Automation.CmdletBindingAttribute] }
        $Attr.ConfirmImpact | Should -Be ([System.Management.Automation.ConfirmImpact]::Medium)
    }
}
