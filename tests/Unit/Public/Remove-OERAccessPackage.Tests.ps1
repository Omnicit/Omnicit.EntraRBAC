BeforeAll {
    $script:moduleName = 'Omnicit.EntraRBAC'
    Get-Module $script:moduleName | Remove-Module -Force -ErrorAction SilentlyContinue
    Import-Module $script:moduleName -Force -ErrorAction Stop
}

Describe 'Remove-OERAccessPackage' {
    BeforeEach {
        InModuleScope $script:moduleName { $script:_OERAuthState = $null }
        Mock -ModuleName $script:moduleName Initialize-OERAuth {}
        Mock -ModuleName $script:moduleName Resolve-OERAccessPackageId { 'ap-1' }
    }

    It 'deletes the access package when confirmed' {
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {}
        Mock -ModuleName $script:moduleName Write-Warning {}
        Remove-OERAccessPackage -Id 'ap-1' -Confirm:$false
        Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 1 -ParameterFilter {
            $Method -eq 'DELETE' -and $Uri -like '*accessPackages/ap-1'
        }
        Should -Invoke -ModuleName $script:moduleName Write-Warning -Times 1
    }

    It 'does not DELETE under -WhatIf' {
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {}
        Remove-OERAccessPackage -Id 'ap-1' -WhatIf
        Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 0
    }

    It 'warns before deleting and still issues the DELETE' {
        # CLAUDE.md SECURITY rule #4: audit PR9 Task 7 sweep -- the operator warning at
        # Remove-OERAccessPackage.ps1:58 was previously asserted only via a Write-Warning mock
        # count (It 'deletes the access package when confirmed'), which does not catch a warning
        # that loses its meaning. Capture the real warning text via -WarningVariable instead.
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {}
        $Warnings = @()
        Remove-OERAccessPackage -Id 'ap-1' -Confirm:$false -WarningVariable Warnings -WarningAction SilentlyContinue
        $Warnings.Count | Should -BeGreaterThan 0
        $Warnings -join ' ' | Should -Match 'irreversible'
        Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 1 -ParameterFilter {
            $Method -eq 'DELETE' -and $Uri -like '*accessPackages/ap-1'
        }
    }

    It 'writes an AccessPackageNotFound non-terminating error when the package does not exist' {
        Mock -ModuleName $script:moduleName Resolve-OERAccessPackageId { $null }
        Remove-OERAccessPackage -Id 'missing' -Confirm:$false -ErrorVariable err -ErrorAction SilentlyContinue
        $err.FullyQualifiedErrorId | Should -Match 'AccessPackageNotFound'
    }

    It 'resolves by DisplayName when ByName parameter set is used' {
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {}
        Mock -ModuleName $script:moduleName Write-Warning {}
        Remove-OERAccessPackage -DisplayName 'AP-Sales' -Confirm:$false
        Should -Invoke -ModuleName $script:moduleName Resolve-OERAccessPackageId -Times 1 -ParameterFilter {
            $DisplayName -eq 'AP-Sales'
        }
    }

    It 'accepts the id from the pipeline by property name' {
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {}
        Mock -ModuleName $script:moduleName Write-Warning {}
        [pscustomobject]@{ Id = 'ap-1' } | Remove-OERAccessPackage -Confirm:$false
        Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 1 -ParameterFilter {
            $Method -eq 'DELETE' -and $Uri -like '*accessPackages/ap-1'
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
        Mock -ModuleName $script:moduleName Write-Warning {}
        Mock -ModuleName $script:moduleName Remove-OERErrorRecord { }
        $Err = $null
        $Result = Remove-OERAccessPackage -Id 'ap-1' -Confirm:$false -ErrorAction SilentlyContinue -ErrorVariable Err
        $Result | Should -BeNullOrEmpty
        @($Err | Where-Object { $_.FullyQualifiedErrorId -eq 'Authorization_RequestDenied,Remove-OERAccessPackage' }).Count |
            Should -Be 1
        Should -Invoke -ModuleName $script:moduleName Remove-OERErrorRecord -Times 1
    }
}

Describe 'Remove-OERAccessPackage -- a failed resolver read is not a not-found (issue #71, fix round 1)' {
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
        Remove-OERAccessPackage -DisplayName 'AP-Sales' -Confirm:$false -ErrorAction SilentlyContinue -ErrorVariable Err | Out-Null

        # NARROWED ON PURPOSE, and the narrowing is the whole guard. -ErrorVariable also collects
        # the engine's own capture of the INNER throw, whose FullyQualifiedErrorId is the bare
        # 'Authorization_RequestDenied' whether or not this cmdlet re-published it -- measured, not
        # assumed. An unnarrowed $Err[0] or -join match therefore passes with the fix reverted.
        # Only the record this cmdlet published carries its own name in InvocationInfo.
        $Published = @($Err) | Where-Object {
            $_.InvocationInfo -and $_.InvocationInfo.MyCommand -and
            $_.InvocationInfo.MyCommand.Name -eq 'Remove-OERAccessPackage'
        }
        @($Published).Count | Should -Be 1
        $Published[0].FullyQualifiedErrorId | Should -Match '^Authorization_RequestDenied'
        $Published[0].FullyQualifiedErrorId | Should -Not -Match 'AccessPackageNotFound' -Because (
            'a permission failure booked as a missing object is the failed-read-as-an-empty-fact defect of issue #76')
        $Published[0].CategoryInfo.Category | Should -Be 'PermissionDenied'
        Should -Invoke -ModuleName 'Omnicit.EntraRBAC' Invoke-OERGraphRequest -Times 0 -Exactly
    }
}
