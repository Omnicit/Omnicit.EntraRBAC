BeforeAll {
    Import-Module Omnicit.EntraRBAC -Force
}

Describe 'New-OERResourceGroup' {
    BeforeEach {
        InModuleScope Omnicit.EntraRBAC { $script:_OERAuthState = $null }
        Mock -ModuleName Omnicit.EntraRBAC Initialize-OERAuth { }
        Mock -ModuleName Omnicit.EntraRBAC Resolve-OERScope { '/subscriptions/sub-guid/resourceGroups/rg-net' }
        Mock -ModuleName Omnicit.EntraRBAC Invoke-OERArmRequest {
            [PSCustomObject]@{
                id         = '/subscriptions/sub-guid/resourceGroups/rg-net'
                name       = 'rg-net'
                location   = 'westeurope'
                properties = [PSCustomObject]@{ provisioningState = 'Succeeded' }
                tags       = [PSCustomObject]@{ env = 'prod' }
            }
        }
    }

    It 'PUTs the resource group with location and tags and tags the output' {
        $Result = New-OERResourceGroup -Subscription 'Prod' -Name 'rg-net' -Location 'westeurope' -Tag @{ env = 'prod' }
        $Result.PSObject.TypeNames[0] | Should -Be 'Omnicit.EntraRBAC.ResourceGroup'
        Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-OERArmRequest -Times 1 -ParameterFilter {
            $Method -eq 'PUT' -and
            $Path -eq '/subscriptions/sub-guid/resourceGroups/rg-net?api-version=2025-04-01' -and
            $Body.location -eq 'westeurope' -and
            $Body.tags.env -eq 'prod'
        }
    }

    It 'rejects an invalid resource group name without calling ARM' {
        $Result = New-OERResourceGroup -Subscription 'Prod' -Name 'bad/name' -Location 'westeurope' -ErrorAction SilentlyContinue -ErrorVariable Err
        $Err[0].FullyQualifiedErrorId | Should -BeLike 'InvalidResourceGroupName*'
        Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-OERArmRequest -Times 0
        # T2: name validation fires before scope resolution -- Resolve-OERScope must not be called
        Should -Invoke -ModuleName Omnicit.EntraRBAC Resolve-OERScope -Times 0
    }

    It 'does not call ARM under -WhatIf' {
        New-OERResourceGroup -Subscription 'Prod' -Name 'rg-net' -Location 'westeurope' -WhatIf
        Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-OERArmRequest -Times 0
    }

    It 'declares ConfirmImpact Medium for parity with the ARM create/update cohort' {
        $Attr = (Get-Command New-OERResourceGroup).ScriptBlock.Attributes |
            Where-Object { $_ -is [System.Management.Automation.CmdletBindingAttribute] }
        $Attr.ConfirmImpact | Should -Be ([System.Management.Automation.ConfirmImpact]::Medium)
    }

    It 'scrubs the bearer-hygiene record when the ARM PUT fails' {
        # CLAUDE.md SECURITY rule 6. Drives the transport catch at
        # source/Public/New-OERResourceGroup.ps1:82. Resolve-OERScope is already mocked by the
        # Describe-level BeforeEach, so the only catch reachable here is the PUT one.
        Mock -ModuleName Omnicit.EntraRBAC Invoke-OERArmRequest { throw 'transport failure' }
        Mock -ModuleName Omnicit.EntraRBAC Remove-OERErrorRecord { }
        $null = New-OERResourceGroup -Subscription 'Prod' -Name 'rg-net' -Location 'westeurope' -Confirm:$false -ErrorAction SilentlyContinue
        Should -Invoke -ModuleName Omnicit.EntraRBAC Resolve-OERScope -Times 1
        Should -Invoke -ModuleName Omnicit.EntraRBAC Remove-OERErrorRecord -Times 1
    }
}
