BeforeAll {
    $script:moduleName = 'Omnicit.EntraRBAC'
    Get-Module $script:moduleName | Remove-Module -Force -ErrorAction SilentlyContinue
    Import-Module $script:moduleName -Force -ErrorAction Stop
}

Describe 'Get-OERAccessPackageAssignmentPolicy' {
    BeforeEach {
        InModuleScope $script:moduleName { $script:_OERAuthState = $null }
        Mock -ModuleName $script:moduleName Initialize-OERAuth {}
        Mock -ModuleName $script:moduleName Resolve-OERAccessPackageId { 'ap-1' }
    }

    It 'gets a policy by id with $expand=accessPackage and surfaces the package id' {
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest { @{ id = 'pol-1'; displayName = 'Default'; accessPackage = @{ id = 'ap-1' } } } -ParameterFilter { $Uri -like '*assignmentPolicies/pol-1*' }
        $R = Get-OERAccessPackageAssignmentPolicy -Id 'pol-1'
        $R.PSObject.TypeNames[0] | Should -Be 'Omnicit.EntraRBAC.AssignmentPolicy'
        $R.AccessPackageId | Should -Be 'ap-1'
        Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 1 -ParameterFilter { $Uri -like '*assignmentPolicies/pol-1?*expand=accessPackage*' }
    }

    It 'lists policies for an access package with the filter and $expand=accessPackage' {
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest { @{ value = @(@{ id = 'pol-1'; displayName = 'A'; accessPackage = @{ id = 'ap-1' } }) } }
        $R = Get-OERAccessPackageAssignmentPolicy -AccessPackage 'AP-Sales'
        $R.AccessPackageId | Should -Be 'ap-1'
        Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 1 -ParameterFilter { $Uri -like "*accessPackage/id eq 'ap-1'*" -and $Uri -like '*expand=accessPackage*' }
    }

    It 'accepts an AccessPackage object piped in, resolves its DisplayName, and selects the ByPackage set' {
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest { @{ value = @(@{ id = 'pol-pipe'; displayName = 'B'; accessPackage = @{ id = 'ap-1' } }) } }
        $ApObj = [pscustomobject]@{ Id = 'AP-1'; DisplayName = 'AP Sales' }
        $ApObj.PSObject.TypeNames.Insert(0, 'Omnicit.EntraRBAC.AccessPackage')
        $R = $ApObj | Get-OERAccessPackageAssignmentPolicy
        $R | Should -Not -BeNullOrEmpty
        Should -Invoke -ModuleName $script:moduleName Resolve-OERAccessPackageId -Times 1 -ParameterFilter {
            $DisplayName -eq 'AP Sales'
        }
        Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 1 -ParameterFilter {
            $Uri -like "*accessPackage/id eq 'ap-1'*"
        }
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
        } -ParameterFilter { $Uri -like '*assignmentPolicies/pol-1*' }
        Mock -ModuleName $script:moduleName Remove-OERErrorRecord { }
        $Err = $null
        $Result = Get-OERAccessPackageAssignmentPolicy -Id 'pol-1' -ErrorAction SilentlyContinue -ErrorVariable Err
        $Result | Should -BeNullOrEmpty
        @($Err | Where-Object { $_.FullyQualifiedErrorId -eq 'Authorization_RequestDenied,Get-OERAccessPackageAssignmentPolicy' }).Count |
            Should -Be 1
        Should -Invoke -ModuleName $script:moduleName Remove-OERErrorRecord -Times 1
    }

    It 'surfaces a Graph failure as a non-terminating error for -AccessPackage and emits nothing' {
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {
            throw [System.Management.Automation.ErrorRecord]::new(
                [System.Exception]::new('TooManyRequests: throttled.'),
                'TooManyRequests',
                [System.Management.Automation.ErrorCategory]::LimitsExceeded,
                $null)
        }
        Mock -ModuleName $script:moduleName Remove-OERErrorRecord { }
        $Err = $null
        $Result = Get-OERAccessPackageAssignmentPolicy -AccessPackage 'AP-Sales' -ErrorAction SilentlyContinue -ErrorVariable Err
        $Result | Should -BeNullOrEmpty
        @($Err | Where-Object { $_.FullyQualifiedErrorId -eq 'TooManyRequests,Get-OERAccessPackageAssignmentPolicy' }).Count |
            Should -Be 1
        Should -Invoke -ModuleName $script:moduleName Remove-OERErrorRecord -Times 1
    }

    It 'passes -All to the list read (closes rt-graph-list-reads-first-page-only)' {
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest { @{ value = @(@{ id = 'pol-1'; displayName = 'A'; accessPackage = @{ id = 'ap-1' } }) } }
        Get-OERAccessPackageAssignmentPolicy -AccessPackage 'AP-Sales' | Out-Null
        Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 1 -Exactly -ParameterFilter { $All }
    }

    It 'does NOT pass -All to the single-entity -Id read' {
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest { @{ id = 'pol-1'; displayName = 'Default'; accessPackage = @{ id = 'ap-1' } } } -ParameterFilter { $Uri -like '*assignmentPolicies/pol-1*' }
        Get-OERAccessPackageAssignmentPolicy -Id 'pol-1' | Out-Null
        Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 1 -Exactly -ParameterFilter { -not $All }
    }
}

Describe 'Get-OERAccessPackageAssignmentPolicy -- a failed resolver read is not a not-found (issue #71, fix round 1)' {
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
        Get-OERAccessPackageAssignmentPolicy -AccessPackage 'AP-Sales' -ErrorAction SilentlyContinue -ErrorVariable Err | Out-Null

        # NARROWED ON PURPOSE, and the narrowing is the whole guard. -ErrorVariable also collects
        # the engine's own capture of the INNER throw, whose FullyQualifiedErrorId is the bare
        # 'Authorization_RequestDenied' whether or not this cmdlet re-published it -- measured, not
        # assumed. An unnarrowed $Err[0] or -join match therefore passes with the fix reverted.
        # Only the record this cmdlet published carries its own name in InvocationInfo.
        $Published = @($Err) | Where-Object {
            $_.InvocationInfo -and $_.InvocationInfo.MyCommand -and
            $_.InvocationInfo.MyCommand.Name -eq 'Get-OERAccessPackageAssignmentPolicy'
        }
        @($Published).Count | Should -Be 1
        $Published[0].FullyQualifiedErrorId | Should -Match '^Authorization_RequestDenied'
        $Published[0].FullyQualifiedErrorId | Should -Not -Match 'AccessPackageNotFound' -Because (
            'a permission failure booked as a missing object is the failed-read-as-an-empty-fact defect of issue #76')
        $Published[0].CategoryInfo.Category | Should -Be 'PermissionDenied'
        Should -Invoke -ModuleName 'Omnicit.EntraRBAC' Invoke-OERGraphRequest -Times 0 -Exactly
    }
}
