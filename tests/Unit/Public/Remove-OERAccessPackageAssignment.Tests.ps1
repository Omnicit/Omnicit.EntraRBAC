BeforeAll {
    $script:moduleName = 'Omnicit.EntraRBAC'
    Get-Module $script:moduleName | Remove-Module -Force -ErrorAction SilentlyContinue
    Import-Module $script:moduleName -Force -ErrorAction Stop
}

Describe 'Remove-OERAccessPackageAssignment' {
    BeforeEach {
        InModuleScope $script:moduleName { $script:_OERAuthState = $null }
        Mock -ModuleName $script:moduleName Initialize-OERAuth {}
    }

    It 'posts an adminRemove assignment request for the assignment id' {
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest { @{ id = 'req-x' } } -ParameterFilter { $Method -eq 'POST' }
        Mock -ModuleName $script:moduleName Write-Warning {}
        Remove-OERAccessPackageAssignment -AssignmentId 'asg-1' -Confirm:$false
        Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 1 -ParameterFilter {
            $Method -eq 'POST' -and $Uri -like '*assignmentRequests' -and
            $Body.requestType -eq 'adminRemove' -and $Body.assignment.id -eq 'asg-1'
        }
        Should -Invoke -ModuleName $script:moduleName Write-Warning -Times 1
    }

    It 'warns before revoking and still issues the adminRemove request' {
        # CLAUDE.md SECURITY rule #4: audit PR9 Task 7 sweep -- the operator warning at
        # Remove-OERAccessPackageAssignment.ps1:46 was previously asserted only via a Write-Warning
        # mock count, which does not catch a warning that loses its meaning. Capture the real
        # warning text via -WarningVariable instead.
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest { @{ id = 'req-x' } } -ParameterFilter { $Method -eq 'POST' }
        $Warnings = @()
        Remove-OERAccessPackageAssignment -AssignmentId 'asg-1' -Confirm:$false -WarningVariable Warnings -WarningAction SilentlyContinue
        $Warnings.Count | Should -BeGreaterThan 0
        $Warnings -join ' ' | Should -Match 'Revoking'
        Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 1 -ParameterFilter {
            $Method -eq 'POST' -and $Body.requestType -eq 'adminRemove' -and $Body.assignment.id -eq 'asg-1'
        }
    }

    It 'does not POST under -WhatIf' {
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {}
        Remove-OERAccessPackageAssignment -AssignmentId 'asg-1' -WhatIf
        Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 0
    }

    It 'accepts the assignment id from the pipeline by the Id property' {
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest { @{ id = 'req-x' } } -ParameterFilter { $Method -eq 'POST' }
        Mock -ModuleName $script:moduleName Write-Warning {}
        [pscustomobject]@{ Id = 'asg-1' } | Remove-OERAccessPackageAssignment -Confirm:$false
        Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 1 -ParameterFilter {
            $Method -eq 'POST' -and $Body.requestType -eq 'adminRemove' -and $Body.assignment.id -eq 'asg-1'
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
        $Result = Remove-OERAccessPackageAssignment -AssignmentId 'asg-1' -Confirm:$false -ErrorAction SilentlyContinue -ErrorVariable Err
        $Result | Should -BeNullOrEmpty
        @($Err | Where-Object { $_.FullyQualifiedErrorId -eq 'Authorization_RequestDenied,Remove-OERAccessPackageAssignment' }).Count |
            Should -Be 1
        Should -Invoke -ModuleName $script:moduleName Remove-OERErrorRecord -Times 1
    }
}
