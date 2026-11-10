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

Describe 'Remove-OERAccessPackageResourceRole' {
    BeforeEach {
        InModuleScope $script:moduleName { $script:_OERAuthState = $null }
        Mock -ModuleName $script:moduleName Initialize-OERAuth {}
        Mock -ModuleName $script:moduleName Resolve-OERAccessPackageId { 'ap-1' }
    }

    It 'deletes the resource role scope by id' {
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {}
        Remove-OERAccessPackageResourceRole -AccessPackage 'AP-Sales' -ResourceRoleScopeId 'scope-1' -Confirm:$false
        Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 1 -ParameterFilter {
            $Method -eq 'DELETE' -and $Uri -like '*accessPackages/ap-1/resourceRoleScopes/scope-1'
        }
    }

    It 'does not DELETE under -WhatIf' {
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {}
        Remove-OERAccessPackageResourceRole -AccessPackage 'AP-Sales' -ResourceRoleScopeId 'scope-1' -WhatIf
        Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 0
    }

    It 'binds ResourceRoleScopeId and AccessPackageId from pipeline (B-em-resourcerole-remove-not-pipeable)' {
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {}
        Mock -ModuleName $script:moduleName Resolve-OERAccessPackageId { $DisplayName }
        $RrsObj = [pscustomobject]@{ ResourceRoleScopeId = 'RRS'; AccessPackageId = 'AP'; RoleName = 'Member' }
        $RrsObj | Remove-OERAccessPackageResourceRole -Confirm:$false
        Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 1 -ParameterFilter {
            $Method -eq 'DELETE' -and $Uri -like '*accessPackages/AP/resourceRoleScopes/RRS'
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
        $Result = Remove-OERAccessPackageResourceRole -AccessPackage 'AP-Sales' -ResourceRoleScopeId 'scope-1' `
            -Confirm:$false -ErrorAction SilentlyContinue -ErrorVariable Err
        $Result | Should -BeNullOrEmpty
        @($Err | Where-Object { $_.FullyQualifiedErrorId -eq 'Authorization_RequestDenied,Remove-OERAccessPackageResourceRole' }).Count |
            Should -Be 1
        Should -Invoke -ModuleName $script:moduleName Remove-OERErrorRecord -Times 1 -Exactly
    }

    Context '-Catalog (BL-184)' {
        BeforeEach {
            Mock -ModuleName $script:moduleName Invoke-OERGraphRequest { @{ value = @() } }

        }

        It 'passes the bound -Catalog and the package name to the resolver' {
            Remove-OERAccessPackageResourceRole -AccessPackage 'AP-Sales' -ResourceRoleScopeId 'scope-1' -Catalog 'CAT-IT-Core' -WhatIf -ErrorAction SilentlyContinue | Out-Null
            Should -Invoke -ModuleName $script:moduleName Resolve-OERAccessPackageId -Times 1 -Exactly -ParameterFilter {
                $PesterBoundParameters.ContainsKey('Catalog') -and $Catalog -eq 'CAT-IT-Core' -and $DisplayName -eq 'AP-Sales'
            }
        }

        It 'calls the resolver without a Catalog key when -Catalog is not bound' {
            Remove-OERAccessPackageResourceRole -AccessPackage 'AP-Sales' -ResourceRoleScopeId 'scope-1' -WhatIf -ErrorAction SilentlyContinue | Out-Null
            Should -Invoke -ModuleName $script:moduleName Resolve-OERAccessPackageId -Times 1 -Exactly -ParameterFilter {
                -not $PesterBoundParameters.ContainsKey('Catalog') -and $DisplayName -eq 'AP-Sales'
            }
            Should -Invoke -ModuleName $script:moduleName Resolve-OERAccessPackageId -Times 0 -ParameterFilter {
                $PesterBoundParameters.ContainsKey('Catalog')
            }
        }

        It 'names the catalog in the not-found text with -Catalog and keeps the old text without it' {
            Mock -ModuleName $script:moduleName Resolve-OERAccessPackageId { $null }
            $Err = $null
            Remove-OERAccessPackageResourceRole -AccessPackage 'AP-Sales' -ResourceRoleScopeId 'scope-1' -Catalog 'CAT-IT-Core' -Confirm:$false -ErrorAction SilentlyContinue -ErrorVariable Err | Out-Null
            $Own = @($Err | Where-Object { $_.FullyQualifiedErrorId -eq 'AccessPackageNotFound,Remove-OERAccessPackageResourceRole' })
            $Own.Count | Should -Be 1
            $Own[0].Exception.Message | Should -BeExactly "Access package 'AP-Sales' not found in catalog 'CAT-IT-Core'."
            $Err = $null
            Remove-OERAccessPackageResourceRole -AccessPackage 'AP-Sales' -ResourceRoleScopeId 'scope-1' -Confirm:$false -ErrorAction SilentlyContinue -ErrorVariable Err | Out-Null
            $Own = @($Err | Where-Object { $_.FullyQualifiedErrorId -eq 'AccessPackageNotFound,Remove-OERAccessPackageResourceRole' })
            $Own.Count | Should -Be 1
            $Own[0].Exception.Message | Should -BeExactly "Access package 'AP-Sales' not found."
        }

        It 'publishes an AccessPackageNotInCatalog refusal as itself, with no write request' {
            Mock -ModuleName $script:moduleName Resolve-OERAccessPackageId {
                throw [System.Management.Automation.ErrorRecord]::new(
                    [System.Exception]::new('refused'),
                    'AccessPackageNotInCatalog',
                    [System.Management.Automation.ErrorCategory]::InvalidArgument,
                    'x')
            }
            $Err = $null
            Remove-OERAccessPackageResourceRole -AccessPackage 'AP-Sales' -ResourceRoleScopeId 'scope-1' -Catalog 'CAT-IT-Core' -Confirm:$false -ErrorAction SilentlyContinue -ErrorVariable Err | Out-Null
            $Own = @($Err | Where-Object { $_.FullyQualifiedErrorId -match '^AccessPackageNotInCatalog,Remove-OERAccessPackageResourceRole$' })
            $Own.Count | Should -Be 1
            $Own[0].InvocationInfo.MyCommand.Name | Should -BeExactly 'Remove-OERAccessPackageResourceRole'
            @($Err | Where-Object { $_.FullyQualifiedErrorId -match '^AmbiguousAccessPackageName' }).Count | Should -Be 0
            Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 0
        }
        It 'publishes an AmbiguousCatalogName refusal as itself, with no write request' {
            Mock -ModuleName $script:moduleName Resolve-OERAccessPackageId {
                throw [System.Management.Automation.ErrorRecord]::new(
                    [System.Exception]::new('refused'),
                    'AmbiguousCatalogName',
                    [System.Management.Automation.ErrorCategory]::InvalidArgument,
                    'x')
            }
            $Err = $null
            Remove-OERAccessPackageResourceRole -AccessPackage 'AP-Sales' -ResourceRoleScopeId 'scope-1' -Catalog 'CAT-IT-Core' -Confirm:$false -ErrorAction SilentlyContinue -ErrorVariable Err | Out-Null
            $Own = @($Err | Where-Object { $_.FullyQualifiedErrorId -match '^AmbiguousCatalogName,Remove-OERAccessPackageResourceRole$' })
            $Own.Count | Should -Be 1
            $Own[0].InvocationInfo.MyCommand.Name | Should -BeExactly 'Remove-OERAccessPackageResourceRole'
            @($Err | Where-Object { $_.FullyQualifiedErrorId -match '^AmbiguousAccessPackageName' }).Count | Should -Be 0
            Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 0
        }
        It 'publishes a CatalogNotFound refusal as itself, with no write request' {
            Mock -ModuleName $script:moduleName Resolve-OERAccessPackageId {
                throw [System.Management.Automation.ErrorRecord]::new(
                    [System.Exception]::new('refused'),
                    'CatalogNotFound',
                    [System.Management.Automation.ErrorCategory]::InvalidArgument,
                    'x')
            }
            $Err = $null
            Remove-OERAccessPackageResourceRole -AccessPackage 'AP-Sales' -ResourceRoleScopeId 'scope-1' -Catalog 'CAT-IT-Core' -Confirm:$false -ErrorAction SilentlyContinue -ErrorVariable Err | Out-Null
            $Own = @($Err | Where-Object { $_.FullyQualifiedErrorId -match '^CatalogNotFound,Remove-OERAccessPackageResourceRole$' })
            $Own.Count | Should -Be 1
            $Own[0].InvocationInfo.MyCommand.Name | Should -BeExactly 'Remove-OERAccessPackageResourceRole'
            @($Err | Where-Object { $_.FullyQualifiedErrorId -match '^AmbiguousAccessPackageName' }).Count | Should -Be 0
            Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 0
        }

        It 'declares -Catalog last, validated, aliasless and not bound from the pipeline' {
            $Cmd = Get-Command Remove-OERAccessPackageResourceRole
            $P = $Cmd.Parameters['Catalog']
            $P | Should -Not -BeNullOrEmpty
            @($P.Attributes | Where-Object { $_ -is [System.Management.Automation.ValidateNotNullOrEmptyAttribute] }).Count | Should -Be 1
            $P.Aliases.Count | Should -Be 0
            @($P.Attributes | Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] -and $_.ValueFromPipelineByPropertyName }).Count | Should -Be 0
            @($P.Attributes | Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] -and $_.ValueFromPipeline }).Count | Should -Be 0
            $Last = $Cmd.ScriptBlock.Ast.Body.ParamBlock.Parameters[-1].Name.VariablePath.UserPath
            $Last | Should -BeExactly 'Catalog'

        }
    }
}

Describe 'Remove-OERAccessPackageResourceRole -- a failed resolver read is not a not-found (issue #71, fix round 1)' {
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
        Remove-OERAccessPackageResourceRole -AccessPackage 'AP-Sales' -ResourceRoleScopeId 'scope-1' `
            -Confirm:$false -ErrorAction SilentlyContinue -ErrorVariable Err | Out-Null

        # NARROWED ON PURPOSE, and the narrowing is the whole guard. -ErrorVariable also collects
        # the engine's own capture of the INNER throw, whose FullyQualifiedErrorId is the bare
        # 'Authorization_RequestDenied' whether or not this cmdlet re-published it -- measured, not
        # assumed. An unnarrowed $Err[0] or -join match therefore passes with the fix reverted.
        # Only the record this cmdlet published carries its own name in InvocationInfo.
        $Published = @($Err) | Where-Object {
            $_.InvocationInfo -and $_.InvocationInfo.MyCommand -and
            $_.InvocationInfo.MyCommand.Name -eq 'Remove-OERAccessPackageResourceRole'
        }
        @($Published).Count | Should -Be 1
        $Published[0].FullyQualifiedErrorId | Should -Match '^Authorization_RequestDenied'
        $Published[0].FullyQualifiedErrorId | Should -Not -Match 'AccessPackageNotFound' -Because (
            'a permission failure booked as a missing object is the failed-read-as-an-empty-fact defect of issue #76')
        $Published[0].CategoryInfo.Category | Should -Be 'PermissionDenied'
        Should -Invoke -ModuleName 'Omnicit.EntraRBAC' Invoke-OERGraphRequest -Times 0 -Exactly
    }
}
