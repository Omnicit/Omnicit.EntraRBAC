BeforeAll {
    $script:moduleName = 'Omnicit.EntraRBAC'
    Get-Module $script:moduleName | Remove-Module -Force -ErrorAction SilentlyContinue
    Import-Module $script:moduleName -Force -ErrorAction Stop
}

Describe 'Remove-OERAccessPackageAssignmentPolicy' {
    BeforeEach {
        InModuleScope $script:moduleName { $script:_OERAuthState = $null }
        Mock -ModuleName $script:moduleName Initialize-OERAuth {}
    }

    It 'deletes the policy when confirmed' {
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {}
        Mock -ModuleName $script:moduleName Write-Warning {}
        Remove-OERAccessPackageAssignmentPolicy -Id 'pol-1' -Confirm:$false
        Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 1 -ParameterFilter {
            $Method -eq 'DELETE' -and $Uri -like '*assignmentPolicies/pol-1'
        }
        Should -Invoke -ModuleName $script:moduleName Write-Warning -Times 1
    }

    It 'warns before deleting and still issues the DELETE' {
        # CLAUDE.md SECURITY rule #4: audit PR9 Task 7 sweep -- the operator warning was previously
        # asserted only via a Write-Warning mock count, which does not catch a warning that loses its
        # meaning. Capture the real warning text via -WarningVariable instead. The Write-Warning is
        # lexically unconditional immediately before the ShouldProcess gate.
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {}
        $Warnings = @()
        Remove-OERAccessPackageAssignmentPolicy -Id 'pol-1' -Confirm:$false -WarningVariable Warnings -WarningAction SilentlyContinue
        $Warnings.Count | Should -BeGreaterThan 0
        $Warnings -join ' ' | Should -Match 'irreversible'
        Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 1 -ParameterFilter {
            $Method -eq 'DELETE' -and $Uri -like '*assignmentPolicies/pol-1'
        }
    }

    It 'does not DELETE under -WhatIf' {
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {}
        Remove-OERAccessPackageAssignmentPolicy -Id 'pol-1' -WhatIf
        Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 0
    }

    It 'DOES warn under -WhatIf, and still destroys nothing' {
        # Same ordering defect the live run measured on the other ConfirmImpact High deletes (checks
        # 13.1 and 13.7): behind ShouldProcess, the warning printed only AFTER the operator had
        # answered the prompt, and never under -WhatIf. Deleting a policy that governs live
        # assignments is exactly the case a -WhatIf run is meant to surface, so the warning now
        # precedes the gate. The DELETE assertion pins that -WhatIf still destroys nothing.
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {}
        $Warnings = @()
        Remove-OERAccessPackageAssignmentPolicy -Id 'pol-1' -WhatIf -WarningVariable Warnings -WarningAction SilentlyContinue
        ($Warnings | ForEach-Object { [string]$_ }) -join ' ' | Should -Match 'irreversible' -Because 'a -WhatIf run is exactly when an operator is deciding, so it is the run that most needs the warning'
        Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 0 -Exactly
    }

    It 'accepts the id from the pipeline by property name' {
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {}
        Mock -ModuleName $script:moduleName Write-Warning {}
        [pscustomobject]@{ Id = 'pol-1' } | Remove-OERAccessPackageAssignmentPolicy -Confirm:$false
        Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 1 -ParameterFilter {
            $Method -eq 'DELETE' -and $Uri -like '*assignmentPolicies/pol-1'
        }
    }

    It 'processes multiple piped policies (bulk delete)' {
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {}
        Mock -ModuleName $script:moduleName Write-Warning {}
        @([pscustomobject]@{ Id = 'pol-1' }, [pscustomobject]@{ Id = 'pol-2' }) | Remove-OERAccessPackageAssignmentPolicy -Confirm:$false
        Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 2 -ParameterFilter { $Method -eq 'DELETE' }
        Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 1 -ParameterFilter { $Uri -like '*assignmentPolicies/pol-1' }
        Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 1 -ParameterFilter { $Uri -like '*assignmentPolicies/pol-2' }
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
        $Result = Remove-OERAccessPackageAssignmentPolicy -Id 'pol-1' -Confirm:$false -ErrorAction SilentlyContinue -ErrorVariable Err
        $Result | Should -BeNullOrEmpty
        @($Err | Where-Object { $_.FullyQualifiedErrorId -eq 'Authorization_RequestDenied,Remove-OERAccessPackageAssignmentPolicy' }).Count |
            Should -Be 1
        Should -Invoke -ModuleName $script:moduleName Remove-OERErrorRecord -Times 1
    }
}
