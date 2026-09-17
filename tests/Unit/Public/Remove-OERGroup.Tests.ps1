BeforeAll {
    $script:moduleName = 'Omnicit.EntraRBAC'
    Get-Module $script:moduleName | Remove-Module -Force -ErrorAction SilentlyContinue
    Import-Module $script:moduleName -Force -ErrorAction Stop
}

Describe 'Remove-OERGroup' {
    BeforeEach {
        InModuleScope $script:moduleName { $script:_OERAuthState = $null }
        Mock -ModuleName $script:moduleName Initialize-OERAuth {}
    }

    It 'deletes a group by id (Confirm suppressed)' {
        Mock -ModuleName $script:moduleName Resolve-OERGroupId { 'gid-1' }
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {}
        Remove-OERGroup -Id 'gid-1' -Confirm:$false
        Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 1 -ParameterFilter {
            $Method -eq 'DELETE' -and $Uri -eq 'v1.0/groups/gid-1'
        }
    }

    It 'errors when the group is not found' {
        Mock -ModuleName $script:moduleName Resolve-OERGroupId { $null }
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {}
        Remove-OERGroup -DisplayName 'missing' -Confirm:$false -ErrorVariable err -ErrorAction SilentlyContinue
        $err.FullyQualifiedErrorId | Should -Match 'GroupNotFound'
        Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 0 -ParameterFilter { $Method -eq 'DELETE' }
    }

    It 'does not delete under -WhatIf' {
        Mock -ModuleName $script:moduleName Resolve-OERGroupId { 'gid-1' }
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {}
        Remove-OERGroup -Id 'gid-1' -WhatIf
        Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 0 -ParameterFilter { $Method -eq 'DELETE' }
    }

    It 'accepts -DisplayName from the pipeline by property name (name-only object | Remove-OERGroup)' {
        Mock -ModuleName $script:moduleName Resolve-OERGroupId { 'gid-3' }
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {}
        [pscustomobject]@{ DisplayName = 'role_sec_x' } | Remove-OERGroup -Confirm:$false
        Should -Invoke -ModuleName $script:moduleName Resolve-OERGroupId -Times 1 -ParameterFilter {
            $DisplayName -eq 'role_sec_x'
        }
        Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 1 -ParameterFilter {
            $Method -eq 'DELETE'
        }
    }

    It 'warns before deleting and still issues the DELETE' {
        # CLAUDE.md SECURITY rule #4: an explicit operator warning must precede the destructive
        # call. The Write-Warning is lexically unconditional immediately before the ShouldProcess
        # gate, so asserting both the warning and the DELETE proves warn-before-destroy.
        Mock -ModuleName $script:moduleName Resolve-OERGroupId { 'gid-1' }
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {}
        $Warnings = @()
        Remove-OERGroup -Id 'gid-1' -Confirm:$false -WarningVariable Warnings -WarningAction SilentlyContinue
        $Warnings.Count | Should -BeGreaterThan 0
        $Warnings -join ' ' | Should -Match 'high-impact'
        Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 1 -ParameterFilter {
            $Method -eq 'DELETE' -and $Uri -eq 'v1.0/groups/gid-1'
        }
    }

    It 'DOES warn under -WhatIf, and still destroys nothing' {
        # DELIBERATE REVERSAL of the It that stood here ('does not warn under -WhatIf, since nothing
        # is destroyed').
        #
        # LIVE-MEASURED (check 13.1): with the Write-Warning sitting behind ShouldProcess, the
        # high-impact warning printed only AFTER the operator had already answered the ConfirmImpact
        # High prompt, and under -WhatIf it never printed at all. So the one run whose entire purpose
        # is to show what a delete would do showed the least, and the prompt was answered before the
        # warning was readable. The warning now precedes the gate; nothing is destroyed either way,
        # which the DELETE assertion below still pins.
        Mock -ModuleName $script:moduleName Resolve-OERGroupId { 'gid-1' }
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {}
        $Warnings = @()
        Remove-OERGroup -Id 'gid-1' -WhatIf -WarningVariable Warnings -WarningAction SilentlyContinue
        ($Warnings | ForEach-Object { [string]$_ }) -join ' ' | Should -Match 'high-impact' -Because 'a -WhatIf run is exactly when an operator is deciding, so it is the run that most needs the warning'
        Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 0 -Exactly
    }

    It 'surfaces a Graph DELETE failure as a non-terminating error and scrubs the bearer record' {
        # Match the cmdlet-QUALIFIED ErrorId, never the bare Graph code. PowerShell re-records the
        # mock's thrown ErrorRecord into -ErrorVariable at every call boundary it crosses before the
        # catch runs, so a bare-code match passes even with WriteError deleted. Only the cmdlet's own
        # record carries the ',<CmdletName>' suffix. Should -Invoke on the scrub helper is what
        # actually guards the mandatory bearer-hygiene line.
        Mock -ModuleName $script:moduleName Resolve-OERGroupId { 'gid-1' }
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {
            throw [System.Management.Automation.ErrorRecord]::new(
                [System.Exception]::new('Authorization_RequestDenied: Insufficient privileges.'),
                'Authorization_RequestDenied',
                [System.Management.Automation.ErrorCategory]::PermissionDenied,
                $null)
        }
        Mock -ModuleName $script:moduleName Remove-OERErrorRecord { }
        $Err = $null
        Remove-OERGroup -Id 'gid-1' -Confirm:$false -WarningAction SilentlyContinue `
            -ErrorAction SilentlyContinue -ErrorVariable Err
        Should -Invoke -ModuleName $script:moduleName Remove-OERErrorRecord -Times 1
        @($Err | Where-Object { $_.FullyQualifiedErrorId -eq 'Authorization_RequestDenied,Remove-OERGroup' }).Count |
            Should -Be 1
    }

    It 'refuses to delete when the display name is ambiguous' {
        # MEM-resolve-groupid-first-match-no-uniqueness: two groups can legally share a display name,
        # and this cmdlet is the worst place to pick an arbitrary one. Mocking Remove-OERErrorRecord
        # is what actually guards the mandatory bearer-hygiene line inside the resolver catch -- a
        # $global:Error reference-identity proof cannot see it, because the guard swallows the record.
        Mock -ModuleName $script:moduleName Resolve-OERGroupId {
            throw [System.Management.Automation.ErrorRecord]::new(
                [System.Exception]::new(
                    "Group display name 'Dup' matches 2 groups (11111111-1111-1111-1111-111111111111, 22222222-2222-2222-2222-222222222222)."),
                'AmbiguousName', [System.Management.Automation.ErrorCategory]::InvalidArgument, 'Dup')
        }
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {}
        Mock -ModuleName $script:moduleName Remove-OERErrorRecord { }
        $Err = $null
        Remove-OERGroup -Group 'Dup' -Confirm:$false -WarningAction SilentlyContinue `
            -ErrorAction SilentlyContinue -ErrorVariable Err
        Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 0 -ParameterFilter { $Method -eq 'DELETE' }
        Should -Invoke -ModuleName $script:moduleName Remove-OERErrorRecord -Times 1
        @($Err | Where-Object { $_.FullyQualifiedErrorId -eq 'AmbiguousGroupName,Remove-OERGroup' }).Count | Should -Be 1
        # The guard must RETURN, not fall through: without the return the cmdlet would also emit the
        # misleading GroupNotFound. The -Times 0 DELETE assertion above cannot see that, because the
        # fall-through lands in the GroupNotFound branch which also returns before the DELETE.
        @($Err | Where-Object { $_.FullyQualifiedErrorId -eq 'GroupNotFound,Remove-OERGroup' }).Count | Should -Be 0
        $Reported = @($Err | Where-Object { $_.FullyQualifiedErrorId -eq 'AmbiguousGroupName,Remove-OERGroup' })[0]
        $Reported.Exception.Message | Should -Match '11111111-1111-1111-1111-111111111111'
        $Reported.Exception.Message | Should -Match '22222222-2222-2222-2222-222222222222'
    }

    It 'still reports GroupNotFound when the resolver returns null rather than throwing' {
        # Property 2 of the ambiguity change at a representative call site: a genuine no-match must
        # keep taking the existing GroupNotFound path, not the new ambiguity path.
        Mock -ModuleName $script:moduleName Resolve-OERGroupId { $null }
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {}
        $Err = $null
        Remove-OERGroup -Group 'missing' -Confirm:$false -ErrorAction SilentlyContinue -ErrorVariable Err
        Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 0 -ParameterFilter { $Method -eq 'DELETE' }
        @($Err | Where-Object { $_.FullyQualifiedErrorId -eq 'GroupNotFound,Remove-OERGroup' }).Count | Should -Be 1
        @($Err | Where-Object { $_.FullyQualifiedErrorId -eq 'AmbiguousGroupName,Remove-OERGroup' }).Count | Should -Be 0
    }

    It 'still reports GroupNotFound when the resolver throws something other than an ambiguity' {
        # The guard must NOT broaden D-au-resolve-catch-null-masks-failures: a transport failure keeps
        # today's fall-through to GroupNotFound, which is deliberately out of scope for this change.
        Mock -ModuleName $script:moduleName Resolve-OERGroupId {
            throw [System.Management.Automation.ErrorRecord]::new(
                [System.Exception]::new('Request throttled.'), 'TooManyRequests',
                [System.Management.Automation.ErrorCategory]::LimitsExceeded, 'Dup')
        }
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {}
        $Err = $null
        Remove-OERGroup -Group 'Dup' -Confirm:$false -ErrorAction SilentlyContinue -ErrorVariable Err
        @($Err | Where-Object { $_.FullyQualifiedErrorId -eq 'GroupNotFound,Remove-OERGroup' }).Count | Should -Be 1
        @($Err | Where-Object { $_.FullyQualifiedErrorId -eq 'AmbiguousGroupName,Remove-OERGroup' }).Count | Should -Be 0
    }

    Context 'unified -Group target (audit PR6)' {
        It 'deletes a group addressed by -Group display name' {
            Mock -ModuleName $script:moduleName Resolve-OERGroupId { 'gid-1' }
            Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {}
            Remove-OERGroup -Group 'role_sec_obsolete' -Confirm:$false
            Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 1 -ParameterFilter {
                $Method -eq 'DELETE' -and $Uri -eq 'v1.0/groups/gid-1'
            }
        }
        It 'still binds the historical -Id parameter name' {
            Mock -ModuleName $script:moduleName Resolve-OERGroupId { '11111111-1111-1111-1111-111111111111' }
            Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {}
            Remove-OERGroup -Id '11111111-1111-1111-1111-111111111111' -Confirm:$false
            Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 1 -ParameterFilter {
                $Method -eq 'DELETE' -and $Uri -eq 'v1.0/groups/11111111-1111-1111-1111-111111111111'
            }
        }
        It 'still binds the historical -DisplayName parameter name' {
            Mock -ModuleName $script:moduleName Resolve-OERGroupId { 'gid-2' }
            Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {}
            Remove-OERGroup -DisplayName 'role_sec_obsolete' -Confirm:$false
            Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 1 -ParameterFilter {
                $Method -eq 'DELETE' -and $Uri -eq 'v1.0/groups/gid-2'
            }
        }
        It 'binds a piped group object' {
            Mock -ModuleName $script:moduleName Resolve-OERGroupId { 'gid-3' }
            Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {}
            [PSCustomObject]@{ Id = 'gid-3' } | Remove-OERGroup -Confirm:$false
            Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 1 -ParameterFilter {
                $Method -eq 'DELETE' -and $Uri -eq 'v1.0/groups/gid-3'
            }
        }
    }
}
