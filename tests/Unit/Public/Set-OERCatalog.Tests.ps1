BeforeAll {
    $script:moduleName = 'Omnicit.EntraRBAC'
    Get-Module $script:moduleName | Remove-Module -Force -ErrorAction SilentlyContinue
    Import-Module $script:moduleName -Force -ErrorAction Stop
}

Describe 'Set-OERCatalog' {
    BeforeEach {
        InModuleScope $script:moduleName { $script:_OERAuthState = $null }
        Mock -ModuleName $script:moduleName Initialize-OERAuth {}
        Mock -ModuleName $script:moduleName Resolve-OERCatalogId { 'cat-1' }
    }

    It 'patches the description' {
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest { @{ id = 'cat-1'; displayName = 'd'; description = 'new' } }
        Set-OERCatalog -Id 'cat-1' -Description 'new' | Out-Null
        Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 1 -ParameterFilter {
            $Method -eq 'PATCH' -and $Uri -like '*catalogs/cat-1' -and $Body.description -eq 'new'
        }
    }

    It 'renames the catalog: maps -NewDisplayName to the displayName body field' {
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest { @{ id = 'cat-1'; displayName = 'CAT-IT-Core-EMEA' } }
        Set-OERCatalog -DisplayName 'CAT-IT-Core' -NewDisplayName 'CAT-IT-Core-EMEA' | Out-Null
        Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 1 -ParameterFilter {
            $Method -eq 'PATCH' -and $Uri -like '*catalogs/cat-1' -and $Body.displayName -eq 'CAT-IT-Core-EMEA'
        }
    }

    It 'patches isExternallyVisible from -ExternallyVisible:$false' {
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest { @{ id = 'cat-1'; displayName = 'd' } }
        Set-OERCatalog -Id 'cat-1' -ExternallyVisible:$false | Out-Null
        Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 1 -ParameterFilter {
            $Method -eq 'PATCH' -and $Body.isExternallyVisible -eq $false
        }
    }

    It 'does not PATCH under -WhatIf' {
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {}
        Set-OERCatalog -Id 'cat-1' -Description 'x' -WhatIf | Out-Null
        Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 0
    }

    It 'errors NothingToUpdate when no property is supplied' {
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {}
        Set-OERCatalog -Id 'cat-1' -ErrorVariable err -ErrorAction SilentlyContinue | Out-Null
        $err.FullyQualifiedErrorId | Should -Match 'NothingToUpdate'
        Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 0
    }

    It 'errors CatalogNotFound when the catalog cannot be resolved' {
        Mock -ModuleName $script:moduleName Resolve-OERCatalogId { $null }
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {}
        Set-OERCatalog -DisplayName 'nope' -Description 'x' -ErrorVariable err -ErrorAction SilentlyContinue | Out-Null
        $err.FullyQualifiedErrorId | Should -Match 'CatalogNotFound'
        Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 0
    }

    It 'accepts the id from the pipeline by property name' {
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest { @{ id = 'cat-1'; displayName = 'd'; description = 'new' } }
        [pscustomobject]@{ Id = 'cat-1' } | Set-OERCatalog -Description 'new' | Out-Null
        Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 1 -ParameterFilter {
            $Method -eq 'PATCH' -and $Uri -like '*catalogs/cat-1' -and $Body.description -eq 'new'
        }
    }

    It 'surfaces a Graph failure as a non-terminating error and emits nothing' {
        # Guards two things the cmdlet must do on a Graph failure: call Remove-OERErrorRecord (the
        # mandatory bearer-token-hygiene line -- asserted via Should -Invoke, since a deleted line
        # would otherwise pass unnoticed) and write its OWN non-terminating record. Match the
        # cmdlet-QUALIFIED ErrorId: PowerShell auto-records the mock's throw into -ErrorVariable a
        # dozen times before the catch runs, so matching the bare Graph code would pass even with
        # WriteError deleted.
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {
            throw [System.Management.Automation.ErrorRecord]::new(
                [System.Exception]::new('Authorization_RequestDenied: Insufficient privileges.'),
                'Authorization_RequestDenied',
                [System.Management.Automation.ErrorCategory]::PermissionDenied,
                $null)
        } -ParameterFilter { $Method -eq 'PATCH' }
        Mock -ModuleName $script:moduleName Remove-OERErrorRecord { }
        $Err = $null
        $Result = Set-OERCatalog -Id 'cat-1' -Description 'new' -Confirm:$false -ErrorAction SilentlyContinue -ErrorVariable Err
        $Result | Should -BeNullOrEmpty
        @($Err | Where-Object { $_.FullyQualifiedErrorId -eq 'Authorization_RequestDenied,Set-OERCatalog' }).Count |
            Should -Be 1
        Should -Invoke -ModuleName $script:moduleName Remove-OERErrorRecord -Times 1
    }
}
