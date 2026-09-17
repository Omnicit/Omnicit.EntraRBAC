BeforeAll {
    $script:moduleName = 'Omnicit.EntraRBAC'
    Get-Module $script:moduleName | Remove-Module -Force -ErrorAction SilentlyContinue
    Import-Module $script:moduleName -Force -ErrorAction Stop
}

Describe 'Set-OERAccessPackageAssignmentPolicy' {
    BeforeEach {
        InModuleScope $script:moduleName { $script:_OERAuthState = $null }
        Mock -ModuleName $script:moduleName Initialize-OERAuth {}
    }

    It 'PUTs the reassembled body to the policy id' {
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {
            @{ id = 'pol-1'; accessPackage = @{ id = 'ap-1' }; displayName = 'Default' }
        } -ParameterFilter { -not $Method -or $Method -eq 'GET' }
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {
            @{ id = 'pol-1'; displayName = 'Renamed'; allowedTargetScope = 'allMemberUsers'; expiration = @{ type = 'noExpiration' } }
        } -ParameterFilter { $Method -eq 'PUT' }
        $Scope = New-OERAccessPackageRequestorScope -Scope AllMemberUsers
        $R = Set-OERAccessPackageAssignmentPolicy -Id 'pol-1' -DisplayName 'Renamed' -RequestorScope $Scope
        $R.DisplayName | Should -Be 'Renamed'
        Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 1 -ParameterFilter {
            $Method -eq 'PUT' -and $Uri -like '*assignmentPolicies/pol-1' -and $Body.accessPackage.id -eq 'ap-1'
        }
    }

    It 'PUTs a body with no approval stages when -ApprovalStage is bound to an empty array, without dropping the untouched approval booleans' {
        # Issue #56. This is the REAL cmdlet, not the handler's mock of it: it proves the PUT that
        # Sync-OERStructureAccessPackage triggers for a declared "approvalStages": [] actually carries
        # stages = [] on the wire. The GET returns a policy that HAS a stage, so a carried-forward
        # baseline would be visible as a non-empty stages array in the PUT body.
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {
            @{
                id                      = 'pol-1'
                accessPackage           = @{ id = 'ap-1' }
                displayName             = 'Default'
                allowedTargetScope      = 'allMemberUsers'
                expiration              = @{ type = 'noExpiration' }
                requestApprovalSettings = @{
                    isApprovalRequiredForAdd         = $true
                    isApprovalRequiredForUpdate      = $true
                    isRequestorJustificationRequired = $true
                    stages                           = @(@{ durationBeforeAutomaticDenial = 'P3D' })
                }
            }
        } -ParameterFilter { -not $Method -or $Method -eq 'GET' }
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {
            @{ id = 'pol-1'; displayName = 'Default'; allowedTargetScope = 'allMemberUsers'; expiration = @{ type = 'noExpiration' } }
        } -ParameterFilter { $Method -eq 'PUT' }

        Set-OERAccessPackageAssignmentPolicy -Id 'pol-1' -DisplayName 'Default' -ApprovalStage @() | Out-Null

        # @($null).Count is 1, so a missing stages key fails this filter rather than passing it.
        Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 1 -Exactly -ParameterFilter {
            $Method -eq 'PUT' -and @($Body.requestApprovalSettings.stages).Count -eq 0
        }
        # requestApprovalSettings is assembled as ONE unit in ConvertTo-OERPolicyBody, so clearing the
        # stages must not wipe the sibling booleans the caller never mentioned -- the
        # composite-field-wiped-when-sent-empty hazard from audit PR-5 (#29). -eq $false / -eq $true
        # rather than a truthiness check: $null would fail both, which is the point.
        Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 1 -Exactly -ParameterFilter {
            $Method -eq 'PUT' -and
            $Body.requestApprovalSettings.isApprovalRequiredForAdd -eq $false -and
            $Body.requestApprovalSettings.isApprovalRequiredForUpdate -eq $true -and
            $Body.requestApprovalSettings.isRequestorJustificationRequired -eq $true
        }
    }

    It 'does not PUT under -WhatIf' {
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {
            @{ id = 'pol-1'; accessPackage = @{ id = 'ap-1' }; displayName = 'Default' }
        } -ParameterFilter { -not $Method -or $Method -eq 'GET' }
        $Scope = New-OERAccessPackageRequestorScope -Scope AllMemberUsers
        Set-OERAccessPackageAssignmentPolicy -Id 'pol-1' -DisplayName 'x' -RequestorScope $Scope -WhatIf | Out-Null
        Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 0 -ParameterFilter { $Method -eq 'PUT' }
    }

    It 'errors InvalidPolicyInput when both -DurationInDays and -ExpirationDateTime are supplied' {
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {}
        $Scope = New-OERAccessPackageRequestorScope -Scope AllMemberUsers
        Set-OERAccessPackageAssignmentPolicy -Id 'pol-1' -DisplayName 'd' -RequestorScope $Scope `
            -DurationInDays 30 -ExpirationDateTime ([datetime]'2027-01-01') `
            -ErrorVariable Err -ErrorAction SilentlyContinue | Out-Null
        $Err[-1].FullyQualifiedErrorId | Should -Match 'InvalidPolicyInput'
        Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 0 -ParameterFilter { $Method -eq 'PUT' }
    }

    It 'errors InvalidPolicyInput when -RequestorScope is not a builder object' {
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {}
        Set-OERAccessPackageAssignmentPolicy -Id 'pol-1' -DisplayName 'd' `
            -RequestorScope ([pscustomobject]@{ x = 1 }) `
            -ErrorVariable Err -ErrorAction SilentlyContinue | Out-Null
        $Err.FullyQualifiedErrorId | Should -Match 'InvalidPolicyInput'
        Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 0
    }

    It 'GETs the existing policy with $expand=accessPackage to learn the package and includes it in the PUT body' {
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {
            @{ id = 'pol-1'; accessPackage = @{ id = 'ap-99' }; displayName = 'Old' }
        } -ParameterFilter { -not $Method -or $Method -eq 'GET' }
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {
            @{ id = 'pol-1'; displayName = 'New'; allowedTargetScope = 'allMemberUsers'; expiration = @{ type = 'noExpiration' } }
        } -ParameterFilter { $Method -eq 'PUT' }
        $Scope = New-OERAccessPackageRequestorScope -Scope AllMemberUsers
        $R = Set-OERAccessPackageAssignmentPolicy -Id 'pol-1' -DisplayName 'New' -RequestorScope $Scope
        $R.AccessPackageId | Should -Be 'ap-99'
        Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 1 -ParameterFilter {
            (-not $Method -or $Method -eq 'GET') -and $Uri -like '*assignmentPolicies/pol-1?*expand=accessPackage*'
        }
        Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 1 -ParameterFilter {
            $Method -eq 'PUT' -and $Body.accessPackage.id -eq 'ap-99'
        }
    }

    It 'returns a tagged AssignmentPolicy object on success' {
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {
            @{ id = 'pol-1'; accessPackage = @{ id = 'ap-1' }; displayName = 'Default' }
        } -ParameterFilter { -not $Method -or $Method -eq 'GET' }
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {
            @{ id = 'pol-1'; displayName = 'Default'; allowedTargetScope = 'allMemberUsers'; expiration = @{ type = 'noExpiration' } }
        } -ParameterFilter { $Method -eq 'PUT' }
        $Scope = New-OERAccessPackageRequestorScope -Scope AllMemberUsers
        $R = Set-OERAccessPackageAssignmentPolicy -Id 'pol-1' -DisplayName 'Default' -RequestorScope $Scope
        $R.PSObject.TypeNames[0] | Should -Be 'Omnicit.EntraRBAC.AssignmentPolicy'
    }

    It 'binds -DisplayName from the pipeline, so a real ConvertTo-OERAssignmentPolicy object round-trips without -DisplayName' {
        # -Id already binds ValueFromPipelineByPropertyName; -DisplayName is Mandatory and (before this
        # fix) plain -- a missing-mandatory pipeline binding failure skips the WHOLE process block for
        # that item (neither the RMW GET nor the PUT fire), so the -Times 2 -Exactly assertion below is
        # the meaningful red/green proof. A bare -ErrorVariable assertion would be vacuous here: this
        # specific engine-level binding failure never reaches -ErrorVariable at all (verified empirically
        # 2026-08-25), it only shows up in $Global:Error and the default error stream.
        $ExistingRaw = @{
            id                      = 'pol-77'
            displayName             = 'Pipeline Policy'
            accessPackage           = @{ id = 'ap-77' }
            allowedTargetScope      = 'allMemberUsers'
            requestorSettings       = @{ enableTargetsToSelfAddAccess = $true; onBehalfRequestors = @() }
            requestApprovalSettings = @{ isApprovalRequiredForAdd = $false; stages = @() }
            expiration              = @{ type = 'noExpiration' }
        }
        $PipedPolicy = InModuleScope $script:moduleName -Parameters @{ Raw = $ExistingRaw } {
            param($Raw)
            ConvertTo-OERAssignmentPolicy -InputObject $Raw
        }
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest { $ExistingRaw } -ParameterFilter { -not $Method -or $Method -eq 'GET' }
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {
            @{ id = 'pol-77'; displayName = 'Pipeline Policy'; allowedTargetScope = 'allMemberUsers'; expiration = @{ type = 'afterDuration'; duration = 'P60D' } }
        } -ParameterFilter { $Method -eq 'PUT' }

        $PipedPolicy | Set-OERAccessPackageAssignmentPolicy -DurationInDays 60 -Confirm:$false | Out-Null

        Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 2 -Exactly
        Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 1 -Exactly -ParameterFilter {
            $Method -eq 'PUT' -and $Body.displayName -eq 'Pipeline Policy'
        }
    }

    It 'accepts the id from the pipeline by property name' {
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {
            @{ id = 'pol-1'; accessPackage = @{ id = 'ap-1' }; displayName = 'Default' }
        } -ParameterFilter { -not $Method -or $Method -eq 'GET' }
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {
            @{ id = 'pol-1'; displayName = 'Renamed'; allowedTargetScope = 'allMemberUsers'; expiration = @{ type = 'noExpiration' } }
        } -ParameterFilter { $Method -eq 'PUT' }
        $Scope = New-OERAccessPackageRequestorScope -Scope AllMemberUsers
        [pscustomobject]@{ Id = 'pol-1' } | Set-OERAccessPackageAssignmentPolicy -DisplayName 'Renamed' -RequestorScope $Scope | Out-Null
        Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 1 -ParameterFilter {
            $Method -eq 'PUT' -and $Uri -like '*assignmentPolicies/pol-1'
        }
    }

    It 'preserves undeclared settings (requestorSettings/reviewSettings/isApprovalRequiredForUpdate) via read-modify-write' {
        $ExistingPolicy = @{
            id                     = 'pol1'
            accessPackage          = @{ id = 'ap1' }
            requestorSettings      = @{
                allowCustomAssignmentSchedule       = $true
                enableTargetsToSelfAddAccess        = $false
                enableTargetsToSelfUpdateAccess     = $false
                enableTargetsToSelfRemoveAccess     = $false
                enableOnBehalfRequestorsToAddAccess = $false
                onBehalfRequestors                  = @()
            }
            requestApprovalSettings = @{
                isApprovalRequiredForAdd         = $true
                isApprovalRequiredForUpdate      = $true
                isRequestorJustificationRequired = $false
                stages                           = @()
            }
            reviewSettings          = @{ isEnabled = $true }
            expiration              = @{ type = 'noExpiration' }
        }
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest -ParameterFilter { $Method -ne 'PUT' } { $ExistingPolicy }
        $script:SetPut = $null
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest -ParameterFilter { $Method -eq 'PUT' } {
            $script:SetPut = $Body
            $Body
        }
        $Scope = New-OERAccessPackageRequestorScope -Scope AllMemberUsers
        Set-OERAccessPackageAssignmentPolicy -Id 'pol1' -DisplayName 'D' -RequestorScope $Scope -Confirm:$false | Out-Null
        InModuleScope $script:moduleName -Parameters @{ P = $script:SetPut } {
            param($P)
            $P.requestorSettings.allowCustomAssignmentSchedule | Should -BeTrue
            $P.reviewSettings.isEnabled | Should -BeTrue
            $P.requestApprovalSettings.isApprovalRequiredForUpdate | Should -BeTrue
        }
    }

    It 'three-way expiration conflict (DurationInDays+DurationInHours) -> InvalidPolicyInput non-terminating' {
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest { @{ id = 'p' } }
        $Scope = New-OERAccessPackageRequestorScope -Scope AllMemberUsers
        Set-OERAccessPackageAssignmentPolicy -Id 'pol-1' -DisplayName 'D' -RequestorScope $Scope `
            -DurationInDays 1 -DurationInHours 1 -ErrorVariable E -ErrorAction SilentlyContinue | Out-Null
        $E[0].FullyQualifiedErrorId | Should -BeLike 'InvalidPolicyInput*'
        Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 0 -ParameterFilter { $Method -eq 'PUT' }
    }

    It 'three-way expiration conflict (DurationInHours+ExpirationDateTime) -> InvalidPolicyInput non-terminating' {
        Mock -ModuleName $script:moduleName Initialize-OERAuth {}
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest { @{ id = 'p' } }
        $Scope = New-OERAccessPackageRequestorScope -Scope AllMemberUsers
        Set-OERAccessPackageAssignmentPolicy -Id 'pol-1' -DisplayName 'D' -RequestorScope $Scope `
            -DurationInHours 8 -ExpirationDateTime ([datetime]'2027-01-01') `
            -ErrorVariable E -ErrorAction SilentlyContinue | Out-Null
        $E[0].FullyQualifiedErrorId | Should -BeLike 'InvalidPolicyInput*'
        Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 0 -ParameterFilter { $Method -eq 'PUT' }
    }

    It 'rejects a -RequestorSettings of the wrong type on Set' {
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest { @{ id = 'p' } }
        $Scope = New-OERAccessPackageRequestorScope -Scope AllMemberUsers
        Set-OERAccessPackageAssignmentPolicy -Id 'pol-1' -DisplayName 'D' -RequestorScope $Scope `
            -RequestorSettings ([pscustomobject]@{ x = 1 }) -ErrorVariable E -ErrorAction SilentlyContinue | Out-Null
        $E[0].FullyQualifiedErrorId | Should -BeLike 'InvalidPolicyInput*'
        Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 0 -ParameterFilter { $Method -eq 'PUT' }
    }

    Context 'duration vocabulary aliases (audit PR6)' {
        It 'binds -DurationDays to the day-count expiration' {
            Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {
                @{ id = 'pol-1'; accessPackage = @{ id = 'ap-1' }; displayName = 'Default' }
            } -ParameterFilter { -not $Method -or $Method -eq 'GET' }
            Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {
                @{ id = 'pol-1'; displayName = 'Default'; allowedTargetScope = 'allMemberUsers'; expiration = @{ type = 'afterDuration'; duration = 'P30D' } }
            } -ParameterFilter { $Method -eq 'PUT' }
            $Scope = New-OERAccessPackageRequestorScope -Scope AllMemberUsers
            Set-OERAccessPackageAssignmentPolicy -Id 'pol-1' -DisplayName 'Default' -RequestorScope $Scope -DurationDays 30 -Confirm:$false | Out-Null
            Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 1 -ParameterFilter {
                $Method -eq 'PUT' -and $Body.expiration.duration -eq 'P30D'
            }
        }

        It 'binds -DurationHours to the hour-count expiration' {
            Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {
                @{ id = 'pol-1'; accessPackage = @{ id = 'ap-1' }; displayName = 'Default' }
            } -ParameterFilter { -not $Method -or $Method -eq 'GET' }
            Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {
                @{ id = 'pol-1'; displayName = 'Default'; allowedTargetScope = 'allMemberUsers'; expiration = @{ type = 'afterDuration'; duration = 'PT8H' } }
            } -ParameterFilter { $Method -eq 'PUT' }
            $Scope = New-OERAccessPackageRequestorScope -Scope AllMemberUsers
            Set-OERAccessPackageAssignmentPolicy -Id 'pol-1' -DisplayName 'Default' -RequestorScope $Scope -DurationHours 8 -Confirm:$false | Out-Null
            Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 1 -ParameterFilter {
                $Method -eq 'PUT' -and $Body.expiration.duration -eq 'PT8H'
            }
        }
    }

    It 'surfaces a Graph failure as a non-terminating error on the read-modify-write GET and emits nothing' {
        # Guards two things the cmdlet must do on a Graph failure: call Remove-OERErrorRecord (the
        # mandatory bearer-token-hygiene line -- asserted via Should -Invoke, since a deleted line
        # would otherwise pass unnoticed) and write its OWN non-terminating record. Match the
        # cmdlet-QUALIFIED ErrorId: PowerShell auto-records the mock's throw into -ErrorVariable a
        # dozen times before the catch runs, so matching the bare Graph code would pass even with
        # WriteError deleted. No -ParameterFilter is needed: this is the only Graph call the
        # RMW-GET catch site can ever be reached by, since PUT is unreachable once the GET fails.
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {
            throw [System.Management.Automation.ErrorRecord]::new(
                [System.Exception]::new('Authorization_RequestDenied: Insufficient privileges.'),
                'Authorization_RequestDenied',
                [System.Management.Automation.ErrorCategory]::PermissionDenied,
                $null)
        }
        Mock -ModuleName $script:moduleName Remove-OERErrorRecord { }
        $Scope = New-OERAccessPackageRequestorScope -Scope AllMemberUsers
        $Err = $null
        $Result = Set-OERAccessPackageAssignmentPolicy -Id 'pol-1' -DisplayName 'Default' -RequestorScope $Scope `
            -Confirm:$false -ErrorAction SilentlyContinue -ErrorVariable Err
        $Result | Should -BeNullOrEmpty
        @($Err | Where-Object { $_.FullyQualifiedErrorId -eq 'Authorization_RequestDenied,Set-OERAccessPackageAssignmentPolicy' }).Count |
            Should -Be 1
        Should -Invoke -ModuleName $script:moduleName Remove-OERErrorRecord -Times 1
    }

    It 'surfaces a Graph failure as a non-terminating error on the PUT and emits nothing' {
        # Guards the same two obligations as the RMW-GET It above, for the PUT catch block (source
        # :221). Scoped with -ParameterFilter so the RMW GET still succeeds and only the PUT fails,
        # proving this catch is independently exercised from the sibling GET catch above.
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {
            @{ id = 'pol-1'; accessPackage = @{ id = 'ap-1' }; displayName = 'Default' }
        } -ParameterFilter { -not $Method -or $Method -eq 'GET' }
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {
            throw [System.Management.Automation.ErrorRecord]::new(
                [System.Exception]::new('Request_BadRequest: The policy is not valid.'),
                'Request_BadRequest',
                [System.Management.Automation.ErrorCategory]::InvalidOperation,
                $null)
        } -ParameterFilter { $Method -eq 'PUT' }
        Mock -ModuleName $script:moduleName Remove-OERErrorRecord { }
        $Scope = New-OERAccessPackageRequestorScope -Scope AllMemberUsers
        $Err = $null
        $Result = Set-OERAccessPackageAssignmentPolicy -Id 'pol-1' -DisplayName 'Default' -RequestorScope $Scope `
            -Confirm:$false -ErrorAction SilentlyContinue -ErrorVariable Err
        $Result | Should -BeNullOrEmpty
        @($Err | Where-Object { $_.FullyQualifiedErrorId -eq 'Request_BadRequest,Set-OERAccessPackageAssignmentPolicy' }).Count |
            Should -Be 1
        Should -Invoke -ModuleName $script:moduleName Remove-OERErrorRecord -Times 1
    }
}

Describe 'Set-OERAccessPackageAssignmentPolicy deleted Lifecycle access review translation' {
    # LIVE-MEASURED: an access package's own Lifecycle access review was deleted by accident, and every
    # later update of the owning policy then failed with a 404 whose whole text was
    # "BusinessFlow not found for id <guid>" -- naming neither the policy, nor reviewSettings (which
    # this cmdlet carries forward on every PUT), nor any remedy.
    BeforeAll {
        Import-Module $script:moduleName -Force
    }
    BeforeEach {
        InModuleScope $script:moduleName { $script:_OERAuthState = $null }
        Mock -ModuleName $script:moduleName Initialize-OERAuth {}
    }

    It 'translates the BusinessFlow 404 into AccessPackageLifecycleReviewMissing naming the missing definition id' {
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {
            @{ id = 'pol-1'; accessPackage = @{ id = 'ap-1' }; displayName = 'Default'; expiration = @{ type = 'noExpiration' } }
        } -ParameterFilter { -not $Method -or $Method -eq 'GET' }
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {
            # Exactly the record Convert-GraphHttpException builds for this response: the body's
            # error.code is EMPTY, so the id falls back to the status-derived 'NotFound'.
            $Detail = 'NotFound: BusinessFlow not found for id 00000000-0000-0000-0000-000000000055'
            $Record = [System.Management.Automation.ErrorRecord]::new(
                [System.Exception]::new($Detail), 'NotFound',
                [System.Management.Automation.ErrorCategory]::OperationStopped, $null)
            $Record.ErrorDetails = [System.Management.Automation.ErrorDetails]::new($Detail)
            throw $Record
        } -ParameterFilter { $Method -eq 'PUT' }

        $Err = $null
        $R = Set-OERAccessPackageAssignmentPolicy -Id 'pol-1' -DisplayName 'Default' -DurationInDays 30 `
            -Confirm:$false -ErrorAction SilentlyContinue -ErrorVariable Err
        $R | Should -BeNullOrEmpty
        # Match the cmdlet-QUALIFIED id: PowerShell auto-records the mock's own throw into
        # -ErrorVariable at a dozen call boundaries, so a bare-id match would pass with the
        # translation deleted.
        $Own = @($Err | Where-Object {
                $_.FullyQualifiedErrorId -eq 'AccessPackageLifecycleReviewMissing,Set-OERAccessPackageAssignmentPolicy'
            })
        $Own.Count | Should -Be 1
        $Own[0].Exception.Message | Should -Match '00000000-0000-0000-0000-000000000055'
        $Own[0].Exception.Message | Should -Match 'reviewSettings'
        $Own[0].Exception.Message | Should -Match 'Lifecycle access review'
        $Own[0].CategoryInfo.Category | Should -Be 'ObjectNotFound'
        # The original failure is preserved, not swallowed.
        $Own[0].Exception.InnerException | Should -Not -BeNullOrEmpty
        $Own[0].Exception.InnerException.Message | Should -Match 'BusinessFlow not found'
    }

    It 'leaves every other Graph PUT failure on the generic path, unchanged' {
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {
            @{ id = 'pol-1'; accessPackage = @{ id = 'ap-1' }; displayName = 'Default'; expiration = @{ type = 'noExpiration' } }
        } -ParameterFilter { -not $Method -or $Method -eq 'GET' }
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {
            throw [System.Management.Automation.ErrorRecord]::new(
                [System.Exception]::new('Authorization_RequestDenied: Insufficient privileges.'),
                'Authorization_RequestDenied',
                [System.Management.Automation.ErrorCategory]::PermissionDenied, $null)
        } -ParameterFilter { $Method -eq 'PUT' }

        $Err = $null
        Set-OERAccessPackageAssignmentPolicy -Id 'pol-1' -DisplayName 'Default' -DurationInDays 30 `
            -Confirm:$false -ErrorAction SilentlyContinue -ErrorVariable Err | Out-Null
        @($Err | Where-Object {
                $_.FullyQualifiedErrorId -eq 'Authorization_RequestDenied,Set-OERAccessPackageAssignmentPolicy'
            }).Count | Should -Be 1
        @($Err | Where-Object { $_.FullyQualifiedErrorId -like 'AccessPackageLifecycleReviewMissing*' }).Count | Should -Be 0
    }

    It 'does not translate a BusinessFlow message whose id is not a GUID' {
        # The id is extracted with a loose token pattern and validated by Test-OERGuid, the module's
        # single GUID predicate, rather than by an inline GUID regex. A message that matches the prose
        # but names something that is not a definition id must stay on the generic path.
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {
            @{ id = 'pol-1'; accessPackage = @{ id = 'ap-1' }; displayName = 'Default'; expiration = @{ type = 'noExpiration' } }
        } -ParameterFilter { -not $Method -or $Method -eq 'GET' }
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {
            $Detail = 'NotFound: BusinessFlow not found for id not-a-guid'
            $Record = [System.Management.Automation.ErrorRecord]::new(
                [System.Exception]::new($Detail), 'NotFound',
                [System.Management.Automation.ErrorCategory]::OperationStopped, $null)
            $Record.ErrorDetails = [System.Management.Automation.ErrorDetails]::new($Detail)
            throw $Record
        } -ParameterFilter { $Method -eq 'PUT' }

        $Err = $null
        Set-OERAccessPackageAssignmentPolicy -Id 'pol-1' -DisplayName 'Default' -DurationInDays 30 `
            -Confirm:$false -ErrorAction SilentlyContinue -ErrorVariable Err | Out-Null
        @($Err | Where-Object { $_.FullyQualifiedErrorId -like 'AccessPackageLifecycleReviewMissing*' }).Count | Should -Be 0
        @($Err | Where-Object {
                $_.FullyQualifiedErrorId -eq 'NotFound,Set-OERAccessPackageAssignmentPolicy'
            }).Count | Should -Be 1
    }

    It 'does not translate a NotFound whose message is not the BusinessFlow shape' {
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {
            @{ id = 'pol-1'; accessPackage = @{ id = 'ap-1' }; displayName = 'Default'; expiration = @{ type = 'noExpiration' } }
        } -ParameterFilter { -not $Method -or $Method -eq 'GET' }
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {
            $Detail = 'NotFound: Resource not found for the segment ''assignmentPolicies''.'
            $Record = [System.Management.Automation.ErrorRecord]::new(
                [System.Exception]::new($Detail), 'NotFound',
                [System.Management.Automation.ErrorCategory]::OperationStopped, $null)
            $Record.ErrorDetails = [System.Management.Automation.ErrorDetails]::new($Detail)
            throw $Record
        } -ParameterFilter { $Method -eq 'PUT' }

        $Err = $null
        Set-OERAccessPackageAssignmentPolicy -Id 'pol-1' -DisplayName 'Default' -DurationInDays 30 `
            -Confirm:$false -ErrorAction SilentlyContinue -ErrorVariable Err | Out-Null
        @($Err | Where-Object { $_.FullyQualifiedErrorId -like 'AccessPackageLifecycleReviewMissing*' }).Count | Should -Be 0
        @($Err | Where-Object {
                $_.FullyQualifiedErrorId -eq 'NotFound,Set-OERAccessPackageAssignmentPolicy'
            }).Count | Should -Be 1
    }
}

Describe 'Set-OERAccessPackageAssignmentPolicy requestor scope preservation' {
    BeforeAll {
        Import-Module $script:moduleName -Force
    }
    BeforeEach {
        Mock -ModuleName $script:moduleName Initialize-OERAuth { }
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {
            if ($Method -eq 'PUT') { return @{ id = 'pol-1'; displayName = 'p' } }
            @{
                id                     = 'pol-1'
                displayName            = 'p'
                description            = 'live description'
                accessPackage          = @{ id = 'ap-1' }
                allowedTargetScope     = 'specificDirectoryUsers'
                specificAllowedTargets = @(@{ '@odata.type' = '#microsoft.graph.singleUser'; userId = 'u-1' })
                expiration             = @{ type = 'noExpiration' }
            }
        }
    }

    It 'binds without -RequestorScope' {
        { Set-OERAccessPackageAssignmentPolicy -Id 'pol-1' -DisplayName 'p' -DurationInDays 30 -Confirm:$false } |
            Should -Not -Throw
    }

    It 'preserves the live specificDirectoryUsers scope when -RequestorScope is omitted' {
        Set-OERAccessPackageAssignmentPolicy -Id 'pol-1' -DisplayName 'p' -DurationInDays 30 -Confirm:$false | Out-Null
        Should -Invoke Invoke-OERGraphRequest -ModuleName $script:moduleName -Times 1 -Exactly -ParameterFilter {
            $Method -eq 'PUT' -and
            $Body.allowedTargetScope -eq 'specificDirectoryUsers' -and
            @($Body.specificAllowedTargets).Count -eq 1
        }
    }
}
