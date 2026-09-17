BeforeAll {
    $script:moduleName = 'Omnicit.EntraRBAC'
    Get-Module $script:moduleName | Remove-Module -Force -ErrorAction SilentlyContinue
    Import-Module $script:moduleName -Force -ErrorAction Stop
}

Describe 'Get-OERCatalog' {
    BeforeEach {
        InModuleScope $script:moduleName { $script:_OERAuthState = $null }
        Mock -ModuleName $script:moduleName Initialize-OERAuth {}
    }

    It 'gets a catalog by id' {
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {
            @{ id = 'cat-1'; displayName = 'CAT-IT-Core' }
        } -ParameterFilter { $Uri -like '*catalogs/cat-1*' }
        $Result = Get-OERCatalog -Id 'cat-1'
        $Result.Id | Should -Be 'cat-1'
        $Result.PSObject.TypeNames[0] | Should -Be 'Omnicit.EntraRBAC.Catalog'
    }

    It 'lists all catalogs when no filter is given' {
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {
            @{ value = @(@{ id = 'a'; displayName = 'A' }, @{ id = 'b'; displayName = 'B' }) }
        }
        $Result = Get-OERCatalog
        $Result.Count | Should -Be 2
        $Result[0].PSObject.TypeNames[0] | Should -Be 'Omnicit.EntraRBAC.Catalog'
    }

    It 'filters by display name' {
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {
            @{ value = @(@{ id = 'cat-9'; displayName = 'CAT-IT-Core' }) }
        }
        Get-OERCatalog -DisplayName 'CAT-IT-Core' | Out-Null
        Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 1 -ParameterFilter {
            $Uri -like "*displayName eq 'CAT-IT-Core'*"
        }
    }

    It 'percent-encodes a display name containing reserved characters so the query survives transport' {
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {
            @{ value = @(@{ id = 'cat-9'; displayName = 'R&D + Core' }) }
        }
        $Result = Get-OERCatalog -DisplayName 'R&D + Core'
        $Result.Id | Should -Be 'cat-9'
        Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 1 -ParameterFilter {
            $Uri -like "*displayName eq 'R%26D%20%2B%20Core'*"
        }
    }

    It 'percent-encodes a -Filter value containing reserved characters' {
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {
            @{ value = @() }
        }
        Get-OERCatalog -Filter "startswith(displayName,'R&D')" | Out-Null
        Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 1 -ParameterFilter {
            $Uri -notmatch '&D' -and $Uri -match '%26D'
        }
    }

    It 'has a registered format view for the Catalog type' {
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest { @{ id = 'cat-1'; displayName = 'CAT-IT-Core' } } -ParameterFilter { $Uri -like '*catalogs/cat-1*' }
        $Formatted = Get-OERCatalog -Id 'cat-1' | Format-Table | Out-String
        $Formatted | Should -Match 'DisplayName'
    }

    It 'surfaces a Graph failure as a non-terminating error for -Id and emits nothing' {
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
        } -ParameterFilter { $Uri -like '*catalogs/cat-1*' }
        Mock -ModuleName $script:moduleName Remove-OERErrorRecord { }
        $Err = $null
        $Result = Get-OERCatalog -Id 'cat-1' -ErrorAction SilentlyContinue -ErrorVariable Err
        $Result | Should -BeNullOrEmpty
        @($Err | Where-Object { $_.FullyQualifiedErrorId -eq 'Authorization_RequestDenied,Get-OERCatalog' }).Count |
            Should -Be 1
        Should -Invoke -ModuleName $script:moduleName Remove-OERErrorRecord -Times 1
    }

    It 'surfaces a Graph failure as a non-terminating error for the list path and emits nothing' {
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {
            throw [System.Management.Automation.ErrorRecord]::new(
                [System.Exception]::new('TooManyRequests: throttled.'),
                'TooManyRequests',
                [System.Management.Automation.ErrorCategory]::LimitsExceeded,
                $null)
        }
        Mock -ModuleName $script:moduleName Remove-OERErrorRecord { }
        $Err = $null
        $Result = Get-OERCatalog -ErrorAction SilentlyContinue -ErrorVariable Err
        $Result | Should -BeNullOrEmpty
        @($Err | Where-Object { $_.FullyQualifiedErrorId -eq 'TooManyRequests,Get-OERCatalog' }).Count |
            Should -Be 1
        Should -Invoke -ModuleName $script:moduleName Remove-OERErrorRecord -Times 1
    }

    It 'passes -All to the list read (closes rt-graph-list-reads-first-page-only)' {
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {
            @{ value = @(@{ id = 'a'; displayName = 'A' }, @{ id = 'b'; displayName = 'B' }) }
        }
        Get-OERCatalog | Out-Null
        Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 1 -Exactly -ParameterFilter { $All }
    }

    It 'does NOT pass -All to the single-entity -Id read' {
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {
            @{ id = 'cat-1'; displayName = 'CAT-IT-Core' }
        } -ParameterFilter { $Uri -like '*catalogs/cat-1*' }
        Get-OERCatalog -Id 'cat-1' | Out-Null
        Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 1 -Exactly -ParameterFilter { -not $All }
    }
}
