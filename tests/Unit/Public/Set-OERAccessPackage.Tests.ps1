BeforeAll {
    $script:moduleName = 'Omnicit.EntraRBAC'
    Get-Module $script:moduleName | Remove-Module -Force -ErrorAction SilentlyContinue
    Import-Module $script:moduleName -Force -ErrorAction Stop
}

Describe 'Set-OERAccessPackage' {
    BeforeEach {
        InModuleScope $script:moduleName { $script:_OERAuthState = $null }
        Mock -ModuleName $script:moduleName Initialize-OERAuth {}
        Mock -ModuleName $script:moduleName Resolve-OERAccessPackageId { 'ap-1' }
    }

    It 'patches the description' {
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest { @{ id = 'ap-1'; displayName = 'd'; description = 'new' } }
        Set-OERAccessPackage -Id 'ap-1' -Description 'new' | Out-Null
        Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 1 -ParameterFilter {
            $Method -eq 'PATCH' -and $Uri -like '*accessPackages/ap-1' -and $Body.description -eq 'new'
        }
    }

    It 'renames the access package: maps -NewDisplayName to the displayName body field' {
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest { @{ id = 'ap-1'; displayName = 'AP-Sales-EMEA' } }
        Set-OERAccessPackage -DisplayName 'AP-Sales' -NewDisplayName 'AP-Sales-EMEA' | Out-Null
        Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 1 -ParameterFilter {
            $Method -eq 'PATCH' -and $Uri -like '*accessPackages/ap-1' -and $Body.displayName -eq 'AP-Sales-EMEA'
        }
    }

    It 'patches isHidden from -Hidden' {
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest { @{ id = 'ap-1'; displayName = 'd'; isHidden = $true } }
        Set-OERAccessPackage -Id 'ap-1' -Hidden | Out-Null
        Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 1 -ParameterFilter {
            $Method -eq 'PATCH' -and $Body.isHidden -eq $true
        }
    }

    It 'does not PATCH under -WhatIf' {
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {}
        Set-OERAccessPackage -Id 'ap-1' -Description 'x' -WhatIf | Out-Null
        Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 0
    }

    It 'errors NothingToUpdate when no property is supplied' {
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {}
        Set-OERAccessPackage -Id 'ap-1' -ErrorVariable err -ErrorAction SilentlyContinue | Out-Null
        $err.FullyQualifiedErrorId | Should -Match 'NothingToUpdate'
        Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 0
    }

    It 'errors AccessPackageNotFound when the access package cannot be resolved' {
        Mock -ModuleName $script:moduleName Resolve-OERAccessPackageId { $null }
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {}
        Set-OERAccessPackage -DisplayName 'nope' -Description 'x' -ErrorVariable err -ErrorAction SilentlyContinue | Out-Null
        $err.FullyQualifiedErrorId | Should -Match 'AccessPackageNotFound'
        Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 0
    }

    It 'accepts the id from the pipeline by property name' {
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest { @{ id = 'ap-1'; displayName = 'd'; description = 'new' } }
        [pscustomobject]@{ Id = 'ap-1' } | Set-OERAccessPackage -Description 'new' | Out-Null
        Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 1 -ParameterFilter {
            $Method -eq 'PATCH' -and $Uri -like '*accessPackages/ap-1' -and $Body.description -eq 'new'
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
        }
        Mock -ModuleName $script:moduleName Remove-OERErrorRecord { }
        $Err = $null
        $Result = Set-OERAccessPackage -Id 'ap-1' -Description 'new' -Confirm:$false -ErrorAction SilentlyContinue -ErrorVariable Err
        $Result | Should -BeNullOrEmpty
        @($Err | Where-Object { $_.FullyQualifiedErrorId -eq 'Authorization_RequestDenied,Set-OERAccessPackage' }).Count |
            Should -Be 1
        Should -Invoke -ModuleName $script:moduleName Remove-OERErrorRecord -Times 1
    }

    Context 'CatalogId is populated on the emitted object' {
        # The v1.0 accessPackage entity has no catalogId property and Graph does not echo the catalog
        # navigation property on a PATCH, so the update response alone cannot carry it. A PATCH that
        # returned a body is followed by one confirmation read using the read path's $expand=catalog
        # shape. The 204 No Content contract is preserved exactly.

        It 'follows a body-returning PATCH with a confirmation read that populates CatalogId' {
            Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {
                @{ id = 'ap-1'; displayName = 'd'; description = 'new' }
            } -ParameterFilter { $Method -eq 'PATCH' }
            Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {
                @{ id = 'ap-1'; displayName = 'd'; description = 'new'; catalog = @{ id = 'cat-77' } }
            } -ParameterFilter { $Method -ne 'PATCH' }
            $R = Set-OERAccessPackage -Id 'ap-1' -Description 'new' -Confirm:$false
            # Prove the object is real before measuring it: $null.CatalogId is also $null.
            $R | Should -Not -BeNullOrEmpty
            $R.Id | Should -BeExactly 'ap-1'
            $R.CatalogId | Should -BeExactly 'cat-77'
            Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 1 -Exactly -ParameterFilter {
                $Method -ne 'PATCH' -and $Uri -like '*accessPackages/ap-1*' -and $Uri -match '\$expand=[^&]*\bcatalog\b'
            }
        }

        It 'emits nothing and performs no confirmation read when the PATCH returns 204 No Content' {
            # Documented contract: no body means no output. The confirmation read only enriches an
            # object that was going to be emitted anyway; it must never turn a silent update into an
            # emitting one.
            Mock -ModuleName $script:moduleName Invoke-OERGraphRequest { $null } -ParameterFilter { $Method -eq 'PATCH' }
            Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {
                @{ id = 'ap-1'; displayName = 'd'; catalog = @{ id = 'cat-77' } }
            } -ParameterFilter { $Method -ne 'PATCH' }
            $R = Set-OERAccessPackage -Id 'ap-1' -Description 'new' -Confirm:$false
            $R | Should -BeNullOrEmpty
            Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 0 -Exactly -ParameterFilter {
                $Method -ne 'PATCH'
            }
        }

        It 'falls back to the PATCH response and still emits when the confirmation read fails' {
            # The package WAS updated. A failed confirmation read must never be reported as a failed
            # update, and must not write an error record either.
            Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {
                @{ id = 'ap-1'; displayName = 'd'; description = 'new' }
            } -ParameterFilter { $Method -eq 'PATCH' }
            Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {
                throw [System.Management.Automation.ErrorRecord]::new(
                    [System.Exception]::new('TooManyRequests: throttled.'),
                    'TooManyRequests',
                    [System.Management.Automation.ErrorCategory]::LimitsExceeded,
                    $null)
            } -ParameterFilter { $Method -ne 'PATCH' }
            Mock -ModuleName $script:moduleName Remove-OERErrorRecord { }
            $Err = $null
            $R = Set-OERAccessPackage -Id 'ap-1' -Description 'new' -Confirm:$false `
                -ErrorAction SilentlyContinue -ErrorVariable Err
            $R | Should -Not -BeNullOrEmpty
            $R.Id | Should -BeExactly 'ap-1'
            $R.CatalogId | Should -BeNullOrEmpty
            @($Err | Where-Object { $_.FullyQualifiedErrorId -like '*,Set-OERAccessPackage' }).Count | Should -Be 0
            # The failed confirmation read carried the bearer header too.
            Should -Invoke -ModuleName $script:moduleName Remove-OERErrorRecord -Times 1
        }
    }
}

Describe 'Set-OERAccessPackage -- a failed resolver read is not a not-found (issue #71, fix round 1)' {
    BeforeEach {
        InModuleScope 'Omnicit.EntraRBAC' { $script:_OERAuthState = $null }
        Mock -ModuleName 'Omnicit.EntraRBAC' Initialize-OERAuth {}
        Mock -ModuleName 'Omnicit.EntraRBAC' Invoke-OERGraphRequest {}
    }

    It 'surfaces a 403 out of Resolve-OERAccessPackageId as itself, never as AccessPackageNotFound' {
        Mock -ModuleName 'Omnicit.EntraRBAC' Resolve-OERAccessPackageId {
            throw [System.Management.Automation.ErrorRecord]::new(
                [System.Exception]::new('Authorization_RequestDenied: Insufficient privileges to complete the operation.'),
                'Authorization_RequestDenied',
                [System.Management.Automation.ErrorCategory]::PermissionDenied,
                'ap-target')
        }
        $Err = $null
        Set-OERAccessPackage -DisplayName 'AP-Sales' -NewDisplayName 'Renamed' -Confirm:$false `
            -ErrorAction SilentlyContinue -ErrorVariable Err | Out-Null

        # NARROWED ON PURPOSE, and the narrowing is the whole guard. -ErrorVariable also collects
        # the engine's own capture of the INNER throw, whose FullyQualifiedErrorId is the bare
        # 'Authorization_RequestDenied' whether or not this cmdlet re-published it -- measured, not
        # assumed. An unnarrowed $Err[0] or -join match therefore passes with the fix reverted.
        # Only the record this cmdlet published carries its own name in InvocationInfo.
        $Published = @($Err) | Where-Object {
            $_.InvocationInfo -and $_.InvocationInfo.MyCommand -and
            $_.InvocationInfo.MyCommand.Name -eq 'Set-OERAccessPackage'
        }
        @($Published).Count | Should -Be 1
        $Published[0].FullyQualifiedErrorId | Should -Match '^Authorization_RequestDenied'
        $Published[0].FullyQualifiedErrorId | Should -Not -Match 'AccessPackageNotFound' -Because (
            'a permission failure booked as a missing object is the failed-read-as-an-empty-fact defect of issue #76')
        $Published[0].CategoryInfo.Category | Should -Be 'PermissionDenied'
        Should -Invoke -ModuleName 'Omnicit.EntraRBAC' Invoke-OERGraphRequest -Times 0 -Exactly
    }
}
