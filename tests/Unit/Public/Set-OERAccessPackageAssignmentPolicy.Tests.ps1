BeforeAll {
    $script:moduleName = 'Omnicit.EntraRBAC'
    Get-Module $script:moduleName | Remove-Module -Force -ErrorAction SilentlyContinue
    Import-Module $script:moduleName -Force -ErrorAction Stop
    . "$PSScriptRoot/../TestHelpers/OERTransportTripwire.ps1"
    Install-OERTransportTripwire
    . "$PSScriptRoot/../TestHelpers/OERConfirmHost.ps1"
}

AfterAll {
    try { Assert-OERTransportTripwire } finally { Uninstall-OERTransportTripwire }
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

    It 'GETs the existing policy once, expanding the access package and each stage''s custom extension, to learn the package and includes it in the PUT body' {
        # The exact URI: $expand=accessPackage alone returns a stage as { id, stage } WITHOUT the custom
        # extension's own id (measured 2026-10-13, Sprint 11 step 3), so the stages could not be carried.
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {
            @{ id = 'pol-1'; accessPackage = @{ id = 'ap-99' }; displayName = 'Old' }
        } -ParameterFilter { -not $Method -or $Method -eq 'GET' }
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {
            @{ id = 'pol-1'; displayName = 'New'; allowedTargetScope = 'allMemberUsers'; expiration = @{ type = 'noExpiration' } }
        } -ParameterFilter { $Method -eq 'PUT' }
        $Scope = New-OERAccessPackageRequestorScope -Scope AllMemberUsers
        $R = Set-OERAccessPackageAssignmentPolicy -Id 'pol-1' -DisplayName 'New' -RequestorScope $Scope
        $R.AccessPackageId | Should -Be 'ap-99'
        Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 1 -Exactly -ParameterFilter {
            (-not $Method -or $Method -eq 'GET') -and
            $Uri -ceq 'v1.0/identityGovernance/entitlementManagement/assignmentPolicies/pol-1?$expand=accessPackage,customExtensionStageSettings($expand=customExtension)'
        }
        Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 1 -Exactly -ParameterFilter {
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

Describe 'Set-OERAccessPackageAssignmentPolicy refuses a connected-organization scope that names no target (Sprint 9 step 5, BL-50)' {
    # New-OERAccessPackageRequestorScope builds SpecificConnectedOrganizationUsers with no
    # specificAllowedTargets (the module does not model connected organization targets), and a full
    # update PUTs a declared scope whole, so the live connected organizations would be replaced with
    # an empty list. The refusal sits after the read of the live policy and its AccessPackageNotFound
    # check, and before ConvertTo-OERPolicyBody and ShouldProcess, so it reads the same under -WhatIf.
    BeforeAll {
        $script:Bl50Id = '11111111-1111-1111-1111-111111111111'
        $script:Bl50Message = "-RequestorScope names allowedTargetScope SpecificConnectedOrganizationUsers but no connected organization -- New-OERAccessPackageRequestorScope cannot name one -- so the full update of assignment policy '$($script:Bl50Id)' would replace every connected organization the live policy names with an empty list. Nothing was sent. Omit -RequestorScope to keep the live scope and its connected organizations."

        # A hand-built tagged scope, the shape the builder returns, so a target can be named.
        function New-Bl50Scope {
            param([string]$AllowedTargetScope, $SpecificAllowedTargets, [switch]$OmitTargets)
            $Members = [ordered]@{ AllowedTargetScope = $AllowedTargetScope }
            if (-not $OmitTargets) { $Members.SpecificAllowedTargets = $SpecificAllowedTargets }
            $Out = [PSCustomObject]$Members
            $Out.PSObject.TypeNames.Insert(0, 'Omnicit.EntraRBAC.RequestorScope')
            $Out
        }

        function New-Bl50ConnectedOrgTarget {
            @{
                '@odata.type'           = '#microsoft.graph.connectedOrganizationMembers'
                connectedOrganizationId = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'
                description             = 'Partner organization'
            }
        }

        function Invoke-Bl50Set {
            param($Scope, [bool]$UseWhatIf = $false)
            $Err = $null
            $Result = Set-OERAccessPackageAssignmentPolicy -Id $script:Bl50Id -DisplayName 'Partners' `
                -Description 'new description' -RequestorScope $Scope -WhatIf:$UseWhatIf -Confirm:$false `
                -ErrorAction SilentlyContinue -ErrorVariable Err
            [PSCustomObject]@{ Result = $Result; Errors = @($Err) }
        }
    }

    BeforeEach {
        InModuleScope $script:moduleName { $script:_OERAuthState = $null }
        Mock -ModuleName $script:moduleName Initialize-OERAuth { }
        # The live policy names a connected organization; the read-modify-write GET returns it.
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {
            @{
                id                     = '11111111-1111-1111-1111-111111111111'
                displayName            = 'Partners'
                description            = 'live description'
                accessPackage          = @{ id = 'ap-1' }
                allowedTargetScope     = 'specificConnectedOrganizationUsers'
                specificAllowedTargets = @(@{
                        '@odata.type'           = '#microsoft.graph.connectedOrganizationMembers'
                        connectedOrganizationId = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'
                        description             = 'Partner organization'
                    })
                expiration             = @{ type = 'noExpiration' }
            }
        } -ParameterFilter { -not $Method -or $Method -eq 'GET' }
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {
            @{
                id                 = '11111111-1111-1111-1111-111111111111'
                displayName        = 'Partners'
                allowedTargetScope = $Body.allowedTargetScope
                expiration         = @{ type = 'noExpiration' }
            }
        } -ParameterFilter { $Method -eq 'PUT' }
    }

    Context 'the refusal' {
        It 'refuses the scope New-OERAccessPackageRequestorScope builds, once, after reading the policy once, and sends nothing (WhatIf: <UseWhatIf>)' -ForEach @(
            @{ UseWhatIf = $false }
            @{ UseWhatIf = $true }
        ) {
            $Scope = New-OERAccessPackageRequestorScope -Scope SpecificConnectedOrganizationUsers -ErrorAction Stop

            $Run = Invoke-Bl50Set -Scope $Scope -UseWhatIf $UseWhatIf

            $Run.Result | Should -BeNullOrEmpty
            # The only record this call writes is its own: exactly one, cmdlet-qualified.
            $Run.Errors.Count | Should -Be 1
            $Run.Errors[0].FullyQualifiedErrorId | Should -Be 'InvalidPolicyInput,Set-OERAccessPackageAssignmentPolicy'
            $Run.Errors[0].CategoryInfo.Category | Should -Be 'InvalidArgument'
            $Run.Errors[0].TargetObject | Should -Be $script:Bl50Id
            $Run.Errors[0].Exception.Message | Should -BeExactly $script:Bl50Message
            # Positive proof that the guard was reached: the live policy was read, once, and that was
            # the only request made.
            Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 1 -Exactly -ParameterFilter {
                (-not $Method -or $Method -eq 'GET') -and
                $Uri -ceq 'v1.0/identityGovernance/entitlementManagement/assignmentPolicies/11111111-1111-1111-1111-111111111111?$expand=accessPackage,customExtensionStageSettings($expand=customExtension)'
            }
            Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 1 -Exactly
            Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 0 -ParameterFilter { $Method -eq 'PUT' }
        }

        It 'refuses a scope that names the connected-organization scope and no target (<Name>)' -ForEach @(
            @{ Name = 'the Pascal-case spelling, an empty list'; Scope = 'SpecificConnectedOrganizationUsers'; Targets = @(); Omit = $false }
            @{ Name = 'mixed casing, an empty list'; Scope = 'SPECIFICconnectedOrganizationUsers'; Targets = @(); Omit = $false }
            @{ Name = 'a null target list'; Scope = 'specificConnectedOrganizationUsers'; Targets = $null; Omit = $false }
            @{ Name = 'a list of only null entries'; Scope = 'specificConnectedOrganizationUsers'; Targets = @($null, $null); Omit = $false }
            @{ Name = 'no target member at all'; Scope = 'specificConnectedOrganizationUsers'; Targets = $null; Omit = $true }
        ) {
            $Scope = if ($Omit) {
                New-Bl50Scope -AllowedTargetScope $Scope -OmitTargets
            } else {
                New-Bl50Scope -AllowedTargetScope $Scope -SpecificAllowedTargets $Targets
            }

            $Run = Invoke-Bl50Set -Scope $Scope

            $Run.Result | Should -BeNullOrEmpty
            $Run.Errors.Count | Should -Be 1
            $Run.Errors[0].FullyQualifiedErrorId | Should -Be 'InvalidPolicyInput,Set-OERAccessPackageAssignmentPolicy'
            $Run.Errors[0].Exception.Message | Should -BeExactly $script:Bl50Message
            Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 1 -Exactly -ParameterFilter {
                -not $Method -or $Method -eq 'GET'
            }
            Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 0 -ParameterFilter { $Method -eq 'PUT' }
        }

        It 'reports the missing access package first: the refusal comes after the AccessPackageNotFound check' {
            Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {
                @{ id = '11111111-1111-1111-1111-111111111111'; displayName = 'Partners' }
            } -ParameterFilter { -not $Method -or $Method -eq 'GET' }
            $Scope = New-OERAccessPackageRequestorScope -Scope SpecificConnectedOrganizationUsers -ErrorAction Stop

            $Run = Invoke-Bl50Set -Scope $Scope

            $Run.Errors.Count | Should -Be 1
            $Run.Errors[0].FullyQualifiedErrorId | Should -Be 'AccessPackageNotFound,Set-OERAccessPackageAssignmentPolicy'
            Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 1 -Exactly
            Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 0 -ParameterFilter { $Method -eq 'PUT' }
        }
    }

    Context 'what the refusal leaves alone' {
        It 'sends the update when the connected-organization scope carries a target (<Scope>)' -ForEach @(
            @{ Scope = 'specificConnectedOrganizationUsers' }
            @{ Scope = 'SPECIFICconnectedOrganizationUsers' }
        ) {
            $Scope = New-Bl50Scope -AllowedTargetScope $Scope -SpecificAllowedTargets @(New-Bl50ConnectedOrgTarget)

            $Run = Invoke-Bl50Set -Scope $Scope

            $Run.Errors.Count | Should -Be 0
            $Run.Result.PSObject.TypeNames[0] | Should -Be 'Omnicit.EntraRBAC.AssignmentPolicy'
            Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 1 -Exactly -ParameterFilter { -not $Method -or $Method -eq 'GET' }
            Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 1 -Exactly -ParameterFilter {
                $Method -eq 'PUT' -and
                $Uri -like '*assignmentPolicies/11111111-1111-1111-1111-111111111111' -and
                @($Body.specificAllowedTargets).Count -eq 1 -and
                $Body.specificAllowedTargets[0].connectedOrganizationId -eq 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'
            }
        }

        It 'sends the update for every other scope (<Name>)' -ForEach @(
            @{ Name = 'AllMemberUsers'; Kind = 'Builder'; Expected = 'allMemberUsers' }
            @{ Name = 'AllConfiguredConnectedOrganizationUsers'; Kind = 'Builder'; Expected = 'allConfiguredConnectedOrganizationUsers' }
            @{ Name = 'SpecificDirectoryUsers'; Kind = 'BuilderWithUser'; Expected = 'specificDirectoryUsers' }
            @{ Name = 'SpecificDirectoryUsers hand-built with no target'; Kind = 'HandBuilt'; Expected = 'specificDirectoryUsers' }
        ) {
            $Scope = switch ($Kind) {
                'Builder' { New-OERAccessPackageRequestorScope -Scope $Expected -ErrorAction Stop }
                'BuilderWithUser' { New-OERAccessPackageRequestorScope -Scope SpecificDirectoryUsers -User '22222222-2222-2222-2222-222222222222' -ErrorAction Stop }
                'HandBuilt' { New-Bl50Scope -AllowedTargetScope 'specificDirectoryUsers' -SpecificAllowedTargets @() }
            }
            $script:Bl50ExpectedScope = $Expected

            $Run = Invoke-Bl50Set -Scope $Scope

            $Run.Errors.Count | Should -Be 0
            Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 1 -Exactly -ParameterFilter {
                $Method -eq 'PUT' -and $Body.allowedTargetScope -ceq $script:Bl50ExpectedScope
            }
        }

        It 'keeps the live connected organization when -RequestorScope is omitted' {
            $Err = $null
            Set-OERAccessPackageAssignmentPolicy -Id $script:Bl50Id -DisplayName 'Partners' -Description 'new description' `
                -Confirm:$false -ErrorAction SilentlyContinue -ErrorVariable Err | Out-Null

            @($Err).Count | Should -Be 0
            Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 1 -Exactly -ParameterFilter {
                $Method -eq 'PUT' -and
                $Body.allowedTargetScope -ceq 'specificConnectedOrganizationUsers' -and
                @($Body.specificAllowedTargets).Count -eq 1 -and
                $Body.specificAllowedTargets[0].connectedOrganizationId -eq 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'
            }
        }
    }
}

Describe 'Set-OERAccessPackageAssignmentPolicy: the connected-organization refusal in a script with no try (Sprint 9 step 5, BL-50)' {
    # A refused call writes a NON-terminating error and the script goes on, so what it must not do is
    # send the PUT on the way. The script stands in no try, prints a sentinel at its end, and the
    # stubbed transport appends every request to a log file whose path is substituted into the text.
    # The control runs the allowed form in the same script with the same stub, so a refused run with
    # no PUT in the log cannot be an artefact of a stub that never logs one. The stub writes its log
    # with -WhatIf:$false: a -WhatIf call passes its preference down to Add-Content, which would
    # otherwise skip the write and make a -WhatIf request invisible in the log.
    BeforeAll {
        $script:Bl50Message = "-RequestorScope names allowedTargetScope SpecificConnectedOrganizationUsers but no connected organization -- New-OERAccessPackageRequestorScope cannot name one -- so the full update of assignment policy '11111111-1111-1111-1111-111111111111' would replace every connected organization the live policy names with an empty list. Nothing was sent. Omit -RequestorScope to keep the live scope and its connected organizations."

        $script:NewBl50NoTryScenario = {
            param([string]$Log, [string]$Calls)
            [scriptblock]::Create((@'
Import-Module Omnicit.EntraRBAC -Force -ErrorAction Stop
$Module = Get-Module Omnicit.EntraRBAC
& $Module {
    Set-Item -Path function:script:Initialize-OERAuth -Value { }
    Set-Item -Path function:script:Remove-OERErrorRecord -Value { }
    Set-Item -Path function:script:Invoke-OERGraphRequest -Value {
        param([string]$Method = 'GET', [string]$Uri, $Body)
        if ($Method -eq 'PUT') {
            Add-Content -LiteralPath '#LOG#' -WhatIf:$false -Value "Invoke-OERGraphRequest PUT targets=$(@($Body.specificAllowedTargets).Count)"
            return @{ id = '11111111-1111-1111-1111-111111111111'; displayName = 'Partners'; allowedTargetScope = $Body.allowedTargetScope; expiration = @{ type = 'noExpiration' } }
        }
        Add-Content -LiteralPath '#LOG#' -WhatIf:$false -Value "Invoke-OERGraphRequest $Method"
        @{
            id                     = '11111111-1111-1111-1111-111111111111'
            displayName            = 'Partners'
            accessPackage          = @{ id = 'ap-1' }
            allowedTargetScope     = 'specificConnectedOrganizationUsers'
            specificAllowedTargets = @(@{ '@odata.type' = '#microsoft.graph.connectedOrganizationMembers'; connectedOrganizationId = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa' })
            expiration             = @{ type = 'noExpiration' }
        }
    }
}
$Refused = New-OERAccessPackageRequestorScope -Scope SpecificConnectedOrganizationUsers
$Named = [pscustomobject]@{
    AllowedTargetScope     = 'specificConnectedOrganizationUsers'
    SpecificAllowedTargets = @(@{ '@odata.type' = '#microsoft.graph.connectedOrganizationMembers'; connectedOrganizationId = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa' })
}
$Named.PSObject.TypeNames.Insert(0, 'Omnicit.EntraRBAC.RequestorScope')
#CALLS#
'END'
'@).Replace('#LOG#', $Log.Replace("'", "''")).Replace('#CALLS#', $Calls))
        }

        $script:Bl50RefusedCalls = @'
$Results = @(
    Set-OERAccessPackageAssignmentPolicy -Id '11111111-1111-1111-1111-111111111111' -DisplayName 'Partners' -RequestorScope $Refused -Confirm:$false
    Set-OERAccessPackageAssignmentPolicy -Id '11111111-1111-1111-1111-111111111111' -DisplayName 'Partners' -RequestorScope $Refused -WhatIf
)
"REACHED:$(@($Results | Where-Object { $null -ne $_ }).Count)"
'@
        $script:Bl50AllowedCalls = @'
$Results = @(
    Set-OERAccessPackageAssignmentPolicy -Id '11111111-1111-1111-1111-111111111111' -DisplayName 'Partners' -RequestorScope $Named -Confirm:$false
)
"REACHED:$(@($Results | Where-Object { $null -ne $_ }).Count)"
'@
        $script:Bl50RefusedThenAllowedCalls = @'
$Results = @(
    Set-OERAccessPackageAssignmentPolicy -Id '11111111-1111-1111-1111-111111111111' -DisplayName 'Partners' -RequestorScope $Refused -Confirm:$false
    Set-OERAccessPackageAssignmentPolicy -Id '11111111-1111-1111-1111-111111111111' -DisplayName 'Partners' -RequestorScope $Named -Confirm:$false
)
"REACHED:$(@($Results | Where-Object { $null -ne $_ }).Count)"
'@
        function Get-Bl50RequestLog ([string]$Log) {
            if (Test-Path -LiteralPath $Log) { @(Get-Content -LiteralPath $Log) } else { @() }
        }
    }

    It 'reaches the end of the script, sends no PUT, and writes the refusal once per call (with and without -WhatIf)' {
        $Log = Join-Path $TestDrive ('{0}.log' -f [guid]::NewGuid())
        $Scenario = & $script:NewBl50NoTryScenario -Log $Log -Calls $script:Bl50RefusedCalls
        $Run = Invoke-OERWithConfirmAnswer -Answer '&Yes' -Script $Scenario
        ($Run.Output -join '|') | Should -Be 'REACHED:0|END'
        # Positive proof: each refused call read the live policy, and that was all it sent.
        @(Get-Bl50RequestLog -Log $Log) | Should -Be @('Invoke-OERGraphRequest GET', 'Invoke-OERGraphRequest GET')
        @($Run.Errors).Count | Should -Be 2
        @($Run.Errors | Where-Object { $_ -ceq $script:Bl50Message }).Count | Should -Be 2
    }

    It 'the control: the same script with a scope that names a connected organization sends the PUT' {
        $Log = Join-Path $TestDrive ('{0}.log' -f [guid]::NewGuid())
        $Scenario = & $script:NewBl50NoTryScenario -Log $Log -Calls $script:Bl50AllowedCalls
        $Run = Invoke-OERWithConfirmAnswer -Answer '&Yes' -Script $Scenario
        ($Run.Output -join '|') | Should -Be 'REACHED:1|END'
        @($Run.Errors).Count | Should -Be 0
        @(Get-Bl50RequestLog -Log $Log) | Should -Be @('Invoke-OERGraphRequest GET', 'Invoke-OERGraphRequest PUT targets=1')
    }

    It 'carries on after a refused call: the next call in the same script sends its PUT' {
        $Log = Join-Path $TestDrive ('{0}.log' -f [guid]::NewGuid())
        $Scenario = & $script:NewBl50NoTryScenario -Log $Log -Calls $script:Bl50RefusedThenAllowedCalls
        $Run = Invoke-OERWithConfirmAnswer -Answer '&Yes' -Script $Scenario
        ($Run.Output -join '|') | Should -Be 'REACHED:1|END'
        @($Run.Errors).Count | Should -Be 1
        @($Run.Errors | Where-Object { $_ -ceq $script:Bl50Message }).Count | Should -Be 1
        @(Get-Bl50RequestLog -Log $Log) | Should -Be @(
            'Invoke-OERGraphRequest GET'
            'Invoke-OERGraphRequest GET'
            'Invoke-OERGraphRequest PUT targets=1'
        )
    }
}

Describe 'Set-OERAccessPackageAssignmentPolicy keeps custom extension stages and automatic assignment settings (Sprint 11 step 3)' {
    # MEASURED 2026-10-13: (1) Microsoft Graph removes a policy's customExtensionStageSettings on a PUT
    # that omits them; (2) the read returns a stage as { id, stage } only, the extension's own id coming
    # with $expand=customExtensionStageSettings($expand=customExtension); (3) an update of an automatic
    # assignment policy that omits automaticRequestSettings is refused (400 InvalidSpecificAllowedTargets).
    BeforeAll {
        Import-Module $script:moduleName -Force
        $script:S11Id = 'aaaaaaaa-0000-0000-0000-000000000031'
        $script:S11GetUri = 'v1.0/identityGovernance/entitlementManagement/assignmentPolicies/aaaaaaaa-0000-0000-0000-000000000031?$expand=accessPackage,customExtensionStageSettings($expand=customExtension)'
        $script:S11Rules = @(@{ '@odata.type' = '#microsoft.graph.attributeRuleMembers'; description = 'rule'; membershipRule = '(user.department -eq "x")' })

        # The policy as Microsoft Graph returns it for the R3 URI. -Stage and -Automatic are optional.
        function New-S11Policy {
            param($Stage, $Automatic, [switch]$WithAutomatic)
            $Policy = @{
                id                 = 'aaaaaaaa-0000-0000-0000-000000000031'
                displayName        = 'Policy'
                description        = 'live description'
                accessPackage      = @{ id = 'ap-1' }
                allowedTargetScope = 'allMemberUsers'
                expiration         = @{ type = 'noExpiration' }
            }
            if ($PSBoundParameters.ContainsKey('Stage')) { $Policy.customExtensionStageSettings = $Stage }
            if ($WithAutomatic) {
                $Policy.allowedTargetScope = 'specificDirectoryUsers'
                $Policy.specificAllowedTargets = $script:S11Rules
                $Policy.automaticRequestSettings = $Automatic
            }
            $Policy
        }

        function New-S11Stage {
            @{
                id              = 'aaaaaaaa-0000-0000-0000-000000000032'
                stage           = 'assignmentRequestCreated'
                customExtension = @{
                    '@odata.type'         = '#microsoft.graph.accessPackageAssignmentRequestWorkflowExtension'
                    id                    = 'aaaaaaaa-0000-0000-0000-000000000033'
                    displayName           = 'ext'
                    endpointConfiguration = @{ url = 'https://example.invalid/x' }
                }
            }
        }

        function Invoke-S11Set {
            param([hashtable]$Extra = @{}, [bool]$UseWhatIf = $false)
            $Err = $null
            $Result = Set-OERAccessPackageAssignmentPolicy -Id $script:S11Id -DisplayName 'Policy' -Description 'new description' `
                @Extra -WhatIf:$UseWhatIf -Confirm:$false -ErrorAction SilentlyContinue -ErrorVariable Err
            [PSCustomObject]@{ Result = $Result; Errors = @($Err) }
        }
    }

    BeforeEach {
        InModuleScope $script:moduleName { $script:_OERAuthState = $null }
        Mock -ModuleName $script:moduleName Initialize-OERAuth { }
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {
            @{ id = 'aaaaaaaa-0000-0000-0000-000000000031'; displayName = 'Policy'; allowedTargetScope = 'allMemberUsers'; expiration = @{ type = 'noExpiration' } }
        } -ParameterFilter { $Method -eq 'PUT' }
    }

    Context 'custom extension stages' {
        It 'sends the stage the read returned in the update shape: the stage and the extension type and id only' {
            $Policy = New-S11Policy -Stage @(New-S11Stage)
            Mock -ModuleName $script:moduleName Invoke-OERGraphRequest { $Policy } -ParameterFilter { -not $Method -or $Method -eq 'GET' }

            $Run = Invoke-S11Set

            $Run.Errors.Count | Should -Be 0
            Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 1 -Exactly -ParameterFilter {
                (-not $Method -or $Method -eq 'GET') -and $Uri -ceq $script:S11GetUri
            }
            Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 1 -Exactly -ParameterFilter {
                $Method -eq 'PUT' -and
                @($Body.customExtensionStageSettings).Count -eq 1 -and
                $Body.customExtensionStageSettings[0].stage -eq 'assignmentRequestCreated' -and
                $Body.customExtensionStageSettings[0].customExtension.id -eq 'aaaaaaaa-0000-0000-0000-000000000033' -and
                $Body.customExtensionStageSettings[0].customExtension['@odata.type'] -eq '#microsoft.graph.accessPackageAssignmentRequestWorkflowExtension' -and
                (($Body.customExtensionStageSettings[0].Keys | Sort-Object) -join ',') -eq 'customExtension,stage' -and
                (($Body.customExtensionStageSettings[0].customExtension.Keys | Sort-Object) -join ',') -eq '@odata.type,id'
            }
        }

        It 'sends no customExtensionStageSettings when the live policy has <Name>' -ForEach @(
            @{ Name = 'an empty list'; Policy = @{ Stage = @() } }
            @{ Name = 'a null list'; Policy = @{ Stage = $null } }
            @{ Name = 'no list at all'; Policy = @{} }
        ) {
            $Params = $Policy
            $Live = New-S11Policy @Params
            Mock -ModuleName $script:moduleName Invoke-OERGraphRequest { $Live } -ParameterFilter { -not $Method -or $Method -eq 'GET' }

            $Run = Invoke-S11Set

            $Run.Errors.Count | Should -Be 0
            # Positive proof that the PUT was reached, then the absence of the key.
            Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 1 -Exactly -ParameterFilter { $Method -eq 'PUT' }
            Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 1 -Exactly -ParameterFilter {
                $Method -eq 'PUT' -and -not $Body.ContainsKey('customExtensionStageSettings')
            }
        }

        It 'refuses a stage whose extension id was not read: InvalidPolicyInput once, GET once, no PUT (WhatIf: <UseWhatIf>)' -ForEach @(
            @{ UseWhatIf = $false }
            @{ UseWhatIf = $true }
        ) {
            $Live = New-S11Policy -Stage @(@{ id = 'aaaaaaaa-0000-0000-0000-000000000032'; stage = 'assignmentRequestCreated' })
            Mock -ModuleName $script:moduleName Invoke-OERGraphRequest { $Live } -ParameterFilter { -not $Method -or $Method -eq 'GET' }

            $Run = Invoke-S11Set -UseWhatIf $UseWhatIf

            $Run.Result | Should -BeNullOrEmpty
            # The cmdlet-qualified record is the call's own; the engine also records the helper's throw.
            $Own = @($Run.Errors | Where-Object { $_.FullyQualifiedErrorId -eq 'InvalidPolicyInput,Set-OERAccessPackageAssignmentPolicy' })
            $Own.Count | Should -Be 1
            $Own[0].CategoryInfo.Category | Should -Be 'InvalidArgument'
            $Own[0].TargetObject | Should -Be 'ap-1'
            $Own[0].Exception.Message | Should -BeLike "Invalid policy input: The existing policy has a custom extension stage 'assignmentRequestCreated' whose custom extension id was not read*"
            $Own[0].Exception.Message | Should -BeLike '*No update was sent; read the policy with its custom extension stages (or remove the stage) before updating it.'
            # The path was reached (the live policy was read, once) and nothing was written.
            Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 1 -Exactly -ParameterFilter {
                (-not $Method -or $Method -eq 'GET') -and $Uri -ceq $script:S11GetUri
            }
            Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 0 -ParameterFilter { $Method -eq 'PUT' }
        }

        It 'refuses when the second of two stages has no extension id, and sends nothing' {
            $Live = New-S11Policy -Stage @((New-S11Stage), @{ id = 'aaaaaaaa-0000-0000-0000-000000000034'; stage = 'assignmentRequestGranted'; customExtension = @{ id = '' } })
            Mock -ModuleName $script:moduleName Invoke-OERGraphRequest { $Live } -ParameterFilter { -not $Method -or $Method -eq 'GET' }

            $Run = Invoke-S11Set

            @($Run.Errors | Where-Object { $_.FullyQualifiedErrorId -eq 'InvalidPolicyInput,Set-OERAccessPackageAssignmentPolicy' }).Count | Should -Be 1
            Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 1 -Exactly -ParameterFilter { -not $Method -or $Method -eq 'GET' }
            Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 0 -ParameterFilter { $Method -eq 'PUT' }
        }
    }

    Context 'automatic assignment settings' {
        BeforeEach {
            $script:S11Automatic = @{
                requestAccessForAllowedTargets             = $true
                removeAccessWhenTargetLeavesAllowedTargets = $true
                gracePeriodBeforeAccessRemoval             = 'P7D'
            }
            $script:S11Live = New-S11Policy -WithAutomatic -Automatic $script:S11Automatic
            Mock -ModuleName $script:moduleName Invoke-OERGraphRequest { $script:S11Live } -ParameterFilter { -not $Method -or $Method -eq 'GET' }
        }

        It 'sends the live automaticRequestSettings with the carried scope when -RequestorScope is omitted' {
            $Run = Invoke-S11Set

            $Run.Errors.Count | Should -Be 0
            Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 1 -Exactly -ParameterFilter {
                $Method -eq 'PUT' -and
                $Body.allowedTargetScope -ceq 'specificDirectoryUsers' -and
                @($Body.specificAllowedTargets).Count -eq 1 -and
                $Body.automaticRequestSettings.requestAccessForAllowedTargets -eq $true -and
                $Body.automaticRequestSettings.removeAccessWhenTargetLeavesAllowedTargets -eq $true -and
                $Body.automaticRequestSettings.gracePeriodBeforeAccessRemoval -ceq 'P7D'
            }
        }

        It 'sends no automaticRequestSettings when -RequestorScope is bound: a declared scope never inherits automatic assignment' {
            $Scope = New-OERAccessPackageRequestorScope -Scope AllMemberUsers

            $Run = Invoke-S11Set -Extra @{ RequestorScope = $Scope }

            $Run.Errors.Count | Should -Be 0
            # The declared scope replaced the live one (the PUT was reached), and the settings did not follow.
            Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 1 -Exactly -ParameterFilter {
                $Method -eq 'PUT' -and $Body.allowedTargetScope -ceq 'allMemberUsers'
            }
            Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 0 -ParameterFilter {
                $Method -eq 'PUT' -and $Body.ContainsKey('automaticRequestSettings')
            }
        }

        It 'sends no automaticRequestSettings for a request-based policy whose live value is null' {
            $script:S11Live = New-S11Policy -WithAutomatic -Automatic $null

            $Run = Invoke-S11Set

            $Run.Errors.Count | Should -Be 0
            Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 1 -Exactly -ParameterFilter {
                $Method -eq 'PUT' -and -not $Body.ContainsKey('automaticRequestSettings')
            }
        }
    }
}

Describe 'Set-OERAccessPackageAssignmentPolicy: the unreadable custom extension refusal in a script with no try (Sprint 11 step 3)' {
    # A refused call writes a NON-terminating error and the script goes on, so what it must not do is
    # send the PUT on the way. The script stands in no try, prints a sentinel at its end, and the
    # stubbed transport appends every request to a log file whose path is substituted into the text.
    # The control runs the same script with a stage that DOES carry its extension id, so a refused run
    # with no PUT in the log cannot be an artefact of a stub that never logs one. The stub writes its
    # log with -WhatIf:$false: a -WhatIf call passes its preference down to Add-Content, which would
    # otherwise skip the write and make a -WhatIf request invisible in the log.
    BeforeAll {
        $script:S11NoTryScenario = {
            param([string]$Log, [string]$Stage, [string]$Calls)
            [scriptblock]::Create((@'
Import-Module Omnicit.EntraRBAC -Force -ErrorAction Stop
$Module = Get-Module Omnicit.EntraRBAC
& $Module {
    Set-Item -Path function:script:Initialize-OERAuth -Value { }
    Set-Item -Path function:script:Remove-OERErrorRecord -Value { }
    Set-Item -Path function:script:Invoke-OERGraphRequest -Value {
        param([string]$Method = 'GET', [string]$Uri, $Body)
        if ($Method -eq 'PUT') {
            $Carried = if ($Body.ContainsKey('customExtensionStageSettings')) { @($Body.customExtensionStageSettings).Count } else { 'none' }
            Add-Content -LiteralPath '#LOG#' -WhatIf:$false -Value "Invoke-OERGraphRequest PUT stages=$Carried"
            return @{ id = 'aaaaaaaa-0000-0000-0000-000000000031'; displayName = 'Policy'; allowedTargetScope = 'allMemberUsers'; expiration = @{ type = 'noExpiration' } }
        }
        Add-Content -LiteralPath '#LOG#' -WhatIf:$false -Value "Invoke-OERGraphRequest $Method"
        @{
            id                           = 'aaaaaaaa-0000-0000-0000-000000000031'
            displayName                  = 'Policy'
            accessPackage                = @{ id = 'ap-1' }
            allowedTargetScope           = 'allMemberUsers'
            expiration                   = @{ type = 'noExpiration' }
            customExtensionStageSettings = @(#STAGE#)
        }
    }
}
#CALLS#
'END'
'@).Replace('#LOG#', $Log.Replace("'", "''")).Replace('#STAGE#', $Stage).Replace('#CALLS#', $Calls))
        }

        $script:S11UnreadStage = "@{ id = 'aaaaaaaa-0000-0000-0000-000000000032'; stage = 'assignmentRequestCreated' }"
        $script:S11ReadStage = "@{ id = 'aaaaaaaa-0000-0000-0000-000000000032'; stage = 'assignmentRequestCreated'; customExtension = @{ '@odata.type' = '#microsoft.graph.accessPackageAssignmentRequestWorkflowExtension'; id = 'aaaaaaaa-0000-0000-0000-000000000033' } }"
        $script:S11Calls = @'
$Results = @(
    Set-OERAccessPackageAssignmentPolicy -Id 'aaaaaaaa-0000-0000-0000-000000000031' -DisplayName 'Policy' -Description 'd' -Confirm:$false
    Set-OERAccessPackageAssignmentPolicy -Id 'aaaaaaaa-0000-0000-0000-000000000031' -DisplayName 'Policy' -Description 'd' -WhatIf
)
"REACHED:$(@($Results | Where-Object { $null -ne $_ }).Count)"
'@
        function Get-S11RequestLog ([string]$Log) {
            if (Test-Path -LiteralPath $Log) { @(Get-Content -LiteralPath $Log) } else { @() }
        }
    }

    It 'reaches the end of the script, sends no PUT, and writes the refusal once per call (with and without -WhatIf)' {
        $Log = Join-Path $TestDrive ('{0}.log' -f [guid]::NewGuid())
        $Scenario = & $script:S11NoTryScenario -Log $Log -Stage $script:S11UnreadStage -Calls $script:S11Calls
        $Run = Invoke-OERWithConfirmAnswer -Answer '&Yes' -Script $Scenario
        ($Run.Output -join '|') | Should -Be 'REACHED:0|END'
        # Positive proof: each refused call read the live policy, and that was all it sent.
        @(Get-S11RequestLog -Log $Log) | Should -Be @('Invoke-OERGraphRequest GET', 'Invoke-OERGraphRequest GET')
        @($Run.Errors | Where-Object { $_ -like "Invalid policy input: The existing policy has a custom extension stage 'assignmentRequestCreated' whose custom extension id was not read*" }).Count |
            Should -Be 2
    }

    It 'the control: the same script with a stage that carries its extension id sends the PUT, with the stage' {
        $Log = Join-Path $TestDrive ('{0}.log' -f [guid]::NewGuid())
        $Calls = @'
$Results = @(
    Set-OERAccessPackageAssignmentPolicy -Id 'aaaaaaaa-0000-0000-0000-000000000031' -DisplayName 'Policy' -Description 'd' -Confirm:$false
)
"REACHED:$(@($Results | Where-Object { $null -ne $_ }).Count)"
'@
        $Scenario = & $script:S11NoTryScenario -Log $Log -Stage $script:S11ReadStage -Calls $Calls
        $Run = Invoke-OERWithConfirmAnswer -Answer '&Yes' -Script $Scenario
        ($Run.Output -join '|') | Should -Be 'REACHED:1|END'
        @($Run.Errors).Count | Should -Be 0
        @(Get-S11RequestLog -Log $Log) | Should -Be @('Invoke-OERGraphRequest GET', 'Invoke-OERGraphRequest PUT stages=1')
    }
}

Describe 'Set-OERAccessPackageAssignmentPolicy renames with -DisplayName alone (A16, Sprint 11 step 4b)' {
    # A16: with no updatable property beyond -DisplayName, the call is a rename when -DisplayName
    # differs from the live policy's displayName, sent as the usual full PUT with everything else
    # carried forward, and NothingToUpdate when it equals that name ignoring case. The decision is
    # taken on the read the update makes anyway, so a refused call sends exactly that one GET.
    BeforeAll {
        Import-Module $script:moduleName -Force
        $script:A16Id = 'aaaaaaaa-0000-0000-0000-000000000041'
        $script:A16GetUri = 'v1.0/identityGovernance/entitlementManagement/assignmentPolicies/aaaaaaaa-0000-0000-0000-000000000041?$expand=accessPackage,customExtensionStageSettings($expand=customExtension)'
        $script:A16PutUri = 'v1.0/identityGovernance/entitlementManagement/assignmentPolicies/aaaaaaaa-0000-0000-0000-000000000041'
        $script:A16Message = "-DisplayName equals the current display name of assignment policy 'aaaaaaaa-0000-0000-0000-000000000041' (compared ignoring case) and no other updatable property was supplied, so there is nothing to update. To rename the policy, pass a different -DisplayName; to update it, pass at least one of -Description, -RequestorScope, -RequestorSettings, -ApprovalStage, -RequireApproval, -RequireRequestorJustification, -RequireApprovalForUpdate, -DurationInDays, -DurationInHours, -ExpirationDateTime, or -DisableAssignmentNotifications."

        # The live policy as Microsoft Graph returns it for the expanded read: an automatic assignment
        # policy with one custom extension stage, so a rename-only PUT has both to carry forward.
        function New-A16Policy {
            @{
                id                           = 'aaaaaaaa-0000-0000-0000-000000000041'
                displayName                  = 'Policy'
                description                  = 'live description'
                accessPackage                = @{ id = 'ap-1' }
                allowedTargetScope           = 'specificDirectoryUsers'
                specificAllowedTargets       = @(@{ '@odata.type' = '#microsoft.graph.attributeRuleMembers'; description = 'rule'; membershipRule = '(user.department -eq "x")' })
                automaticRequestSettings     = @{
                    requestAccessForAllowedTargets             = $true
                    removeAccessWhenTargetLeavesAllowedTargets = $true
                    gracePeriodBeforeAccessRemoval             = 'P7D'
                }
                expiration                   = @{ type = 'noExpiration' }
                customExtensionStageSettings = @(@{
                        id              = 'aaaaaaaa-0000-0000-0000-000000000042'
                        stage           = 'assignmentRequestCreated'
                        customExtension = @{
                            '@odata.type'         = '#microsoft.graph.accessPackageAssignmentRequestWorkflowExtension'
                            id                    = 'aaaaaaaa-0000-0000-0000-000000000043'
                            displayName           = 'ext'
                            endpointConfiguration = @{ url = 'https://example.invalid/x' }
                        }
                    })
            }
        }

        function Invoke-A16Set {
            param([string]$Name, [hashtable]$Extra = @{}, [bool]$UseWhatIf = $false)
            $Err = $null
            $Result = Set-OERAccessPackageAssignmentPolicy -Id $script:A16Id -DisplayName $Name @Extra `
                -WhatIf:$UseWhatIf -Confirm:$false -ErrorAction SilentlyContinue -ErrorVariable Err
            [PSCustomObject]@{ Result = $Result; Errors = @($Err) }
        }
    }

    BeforeEach {
        InModuleScope $script:moduleName { $script:_OERAuthState = $null }
        Mock -ModuleName $script:moduleName Initialize-OERAuth { }
        $script:A16Live = New-A16Policy
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest { $script:A16Live } -ParameterFilter { -not $Method -or $Method -eq 'GET' }
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {
            @{ id = 'aaaaaaaa-0000-0000-0000-000000000041'; displayName = $Body.displayName; allowedTargetScope = 'specificDirectoryUsers'; expiration = @{ type = 'noExpiration' } }
        } -ParameterFilter { $Method -eq 'PUT' }
    }

    Context 'a -DisplayName that differs from the live name' {
        It 'renames: one GET, then one PUT carrying the new name and everything else from the live policy' {
            $Run = Invoke-A16Set -Name 'Renamed'

            $Run.Errors.Count | Should -Be 0
            $Run.Result.PSObject.TypeNames[0] | Should -Be 'Omnicit.EntraRBAC.AssignmentPolicy'
            $Run.Result.DisplayName | Should -BeExactly 'Renamed'
            Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 2 -Exactly
            Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 1 -Exactly -ParameterFilter {
                (-not $Method -or $Method -eq 'GET') -and $Uri -ceq $script:A16GetUri
            }
            # The new name, the live description and package, the custom extension stage in the
            # update shape step 3 sends (the stage and the extension type and id only), and the
            # automatic assignment settings with the live scope they travel with.
            Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 1 -Exactly -ParameterFilter {
                $Method -eq 'PUT' -and
                $Uri -ceq $script:A16PutUri -and
                $Body.id -ceq 'aaaaaaaa-0000-0000-0000-000000000041' -and
                $Body.displayName -ceq 'Renamed' -and
                $Body.description -ceq 'live description' -and
                $Body.accessPackage.id -ceq 'ap-1' -and
                @($Body.customExtensionStageSettings).Count -eq 1 -and
                $Body.customExtensionStageSettings[0].stage -ceq 'assignmentRequestCreated' -and
                $Body.customExtensionStageSettings[0].customExtension.id -ceq 'aaaaaaaa-0000-0000-0000-000000000043' -and
                $Body.customExtensionStageSettings[0].customExtension['@odata.type'] -ceq '#microsoft.graph.accessPackageAssignmentRequestWorkflowExtension' -and
                (($Body.customExtensionStageSettings[0].Keys | Sort-Object) -join ',') -eq 'customExtension,stage' -and
                (($Body.customExtensionStageSettings[0].customExtension.Keys | Sort-Object) -join ',') -eq '@odata.type,id' -and
                $Body.allowedTargetScope -ceq 'specificDirectoryUsers' -and
                @($Body.specificAllowedTargets).Count -eq 1 -and
                $Body.automaticRequestSettings.requestAccessForAllowedTargets -eq $true -and
                $Body.automaticRequestSettings.removeAccessWhenTargetLeavesAllowedTargets -eq $true -and
                $Body.automaticRequestSettings.gracePeriodBeforeAccessRemoval -ceq 'P7D'
            }
        }

        It 'sends no PUT under -WhatIf, after the one read, and reports nothing' {
            $Run = Invoke-A16Set -Name 'Renamed' -UseWhatIf $true

            $Run.Result | Should -BeNullOrEmpty
            # No record at all: the call was planned as an update, not refused as NothingToUpdate.
            $Run.Errors.Count | Should -Be 0
            Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 1 -Exactly
            Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 1 -Exactly -ParameterFilter {
                (-not $Method -or $Method -eq 'GET') -and $Uri -ceq $script:A16GetUri
            }
            Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 0 -Exactly -ParameterFilter { $Method -eq 'PUT' }
        }

        It 'reports a read that names no access package as AccessPackageNotFound, and sends no PUT' {
            $script:A16Live = @{ id = 'aaaaaaaa-0000-0000-0000-000000000041'; displayName = 'Policy' }

            $Run = Invoke-A16Set -Name 'Renamed'

            $Run.Errors.Count | Should -Be 1
            $Run.Errors[0].FullyQualifiedErrorId | Should -Be 'AccessPackageNotFound,Set-OERAccessPackageAssignmentPolicy'
            Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 1 -Exactly
            Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 0 -Exactly -ParameterFilter { $Method -eq 'PUT' }
        }
    }

    Context 'a -DisplayName equal to the live name' {
        It 'reports NothingToUpdate after exactly one GET, and sends no PUT (-DisplayName <Name>)' -ForEach @(
            @{ Name = 'Policy' }
            @{ Name = 'policy' }
            @{ Name = 'POLICY' }
        ) {
            $Run = Invoke-A16Set -Name $Name

            $Run.Result | Should -BeNullOrEmpty
            $Run.Errors.Count | Should -Be 1
            $Run.Errors[0].FullyQualifiedErrorId | Should -Be 'NothingToUpdate,Set-OERAccessPackageAssignmentPolicy'
            $Run.Errors[0].CategoryInfo.Category | Should -Be 'InvalidArgument'
            $Run.Errors[0].TargetObject | Should -Be $script:A16Id
            $Run.Errors[0].Exception.Message | Should -BeExactly $script:A16Message
            Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 1 -Exactly
            Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 1 -Exactly -ParameterFilter {
                (-not $Method -or $Method -eq 'GET') -and $Uri -ceq $script:A16GetUri
            }
            Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 0 -Exactly -ParameterFilter { $Method -eq 'PUT' }
        }

        It 'reports NothingToUpdate under -WhatIf as well, after the one read' {
            $Run = Invoke-A16Set -Name 'policy' -UseWhatIf $true

            $Run.Errors.Count | Should -Be 1
            $Run.Errors[0].FullyQualifiedErrorId | Should -Be 'NothingToUpdate,Set-OERAccessPackageAssignmentPolicy'
            Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 1 -Exactly
            Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 0 -Exactly -ParameterFilter { $Method -eq 'PUT' }
        }

        It 'still sends the update when another property is supplied, with -DisplayName as given (-DisplayName <Name>)' -ForEach @(
            @{ Name = 'Policy' }
            @{ Name = 'policy' }
        ) {
            $script:A16ExpectedName = $Name

            $Run = Invoke-A16Set -Name $Name -Extra @{ Description = 'new description' }

            $Run.Errors.Count | Should -Be 0
            # Exactly two requests: the one read, then the one update.
            Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 2 -Exactly
            Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 1 -Exactly -ParameterFilter {
                (-not $Method -or $Method -eq 'GET') -and $Uri -ceq $script:A16GetUri
            }
            Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 1 -Exactly -ParameterFilter {
                $Method -eq 'PUT' -and
                $Body.displayName -ceq $script:A16ExpectedName -and
                $Body.description -ceq 'new description'
            }
        }

        It 'decides NothingToUpdate before the access package check: a read with the live name and no access package reports NothingToUpdate, not AccessPackageNotFound' {
            # The decision stands directly after the read; nothing would be sent either way, so the
            # caller learns that there is nothing to update rather than that the package is unknown.
            $script:A16Live = @{ id = 'aaaaaaaa-0000-0000-0000-000000000041'; displayName = 'Policy' }

            $Run = Invoke-A16Set -Name 'Policy'

            $Run.Result | Should -BeNullOrEmpty
            @($Run.Errors | Where-Object { $_.FullyQualifiedErrorId -eq 'NothingToUpdate,Set-OERAccessPackageAssignmentPolicy' }).Count | Should -Be 1
            @($Run.Errors | Where-Object { $_.FullyQualifiedErrorId -like 'AccessPackageNotFound*' }).Count | Should -Be 0
            $Run.Errors.Count | Should -Be 1
            Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 1 -Exactly
            Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 0 -Exactly -ParameterFilter { $Method -eq 'PUT' }
        }
    }

    Context 'a failed or empty read' {
        It 'publishes a failed GET as itself, not as NothingToUpdate, and sends no PUT (-DisplayName <Name>)' -ForEach @(
            @{ Name = 'Policy' }
            @{ Name = 'Renamed' }
        ) {
            Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {
                throw [System.Management.Automation.ErrorRecord]::new(
                    [System.Exception]::new('Request_ResourceNotFound: The policy was not found.'),
                    'Request_ResourceNotFound',
                    [System.Management.Automation.ErrorCategory]::ObjectNotFound,
                    $null)
            } -ParameterFilter { -not $Method -or $Method -eq 'GET' }

            $Run = Invoke-A16Set -Name $Name

            $Run.Result | Should -BeNullOrEmpty
            @($Run.Errors | Where-Object { $_.FullyQualifiedErrorId -eq 'Request_ResourceNotFound,Set-OERAccessPackageAssignmentPolicy' }).Count | Should -Be 1
            @($Run.Errors | Where-Object { $_.FullyQualifiedErrorId -like 'NothingToUpdate*' }).Count | Should -Be 0
            Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 1 -Exactly -ParameterFilter {
                (-not $Method -or $Method -eq 'GET') -and $Uri -ceq $script:A16GetUri
            }
            Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 0 -Exactly -ParameterFilter { $Method -eq 'PUT' }
        }

        It 'never takes a read that returned nothing for the live name: AccessPackageNotFound, not NothingToUpdate' {
            $script:A16Live = $null

            $Run = Invoke-A16Set -Name 'Policy'

            $Run.Errors.Count | Should -Be 1
            $Run.Errors[0].FullyQualifiedErrorId | Should -Be 'AccessPackageNotFound,Set-OERAccessPackageAssignmentPolicy'
            Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 1 -Exactly
            Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 0 -Exactly -ParameterFilter { $Method -eq 'PUT' }
        }

        It 'takes a read that carries no displayName for a rename: one GET, then one PUT carrying -DisplayName' {
            $script:A16Live.Remove('displayName')

            $Run = Invoke-A16Set -Name 'Policy'

            $Run.Errors.Count | Should -Be 0
            Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 2 -Exactly
            Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 1 -Exactly -ParameterFilter {
                $Method -eq 'PUT' -and $Body.displayName -ceq 'Policy'
            }
        }
    }
}

Describe 'Set-OERAccessPackageAssignmentPolicy: NothingToUpdate on the live name in a script with no try (A16, Sprint 11 step 4b)' {
    # The refusal writes a NON-terminating error and the script goes on, so what it must not do is
    # send the PUT on the way. Same shape as the two no-try Describes above: the script stands in no
    # try, prints a sentinel at its end, and the stubbed transport appends every request to a log file
    # whose path is substituted into the text. The control renames in the same script with the same
    # stub, after a refused call, so a refused run with no PUT in the log cannot be an artefact of a
    # stub that never logs one. The stub writes its log with -WhatIf:$false, so a -WhatIf request
    # still shows in the log.
    BeforeAll {
        $script:A16NoTryMessage = "-DisplayName equals the current display name of assignment policy 'aaaaaaaa-0000-0000-0000-000000000041' (compared ignoring case) and no other updatable property was supplied, so there is nothing to update. To rename the policy, pass a different -DisplayName; to update it, pass at least one of -Description, -RequestorScope, -RequestorSettings, -ApprovalStage, -RequireApproval, -RequireRequestorJustification, -RequireApprovalForUpdate, -DurationInDays, -DurationInHours, -ExpirationDateTime, or -DisableAssignmentNotifications."

        $script:A16NoTryScenario = {
            param([string]$Log, [string]$Calls)
            [scriptblock]::Create((@'
Import-Module Omnicit.EntraRBAC -Force -ErrorAction Stop
$Module = Get-Module Omnicit.EntraRBAC
& $Module {
    Set-Item -Path function:script:Initialize-OERAuth -Value { }
    Set-Item -Path function:script:Remove-OERErrorRecord -Value { }
    Set-Item -Path function:script:Invoke-OERGraphRequest -Value {
        param([string]$Method = 'GET', [string]$Uri, $Body)
        if ($Method -eq 'PUT') {
            Add-Content -LiteralPath '#LOG#' -WhatIf:$false -Value "Invoke-OERGraphRequest PUT name=$($Body.displayName)"
            return @{ id = 'aaaaaaaa-0000-0000-0000-000000000041'; displayName = $Body.displayName; allowedTargetScope = 'allMemberUsers'; expiration = @{ type = 'noExpiration' } }
        }
        Add-Content -LiteralPath '#LOG#' -WhatIf:$false -Value "Invoke-OERGraphRequest $Method"
        @{
            id                 = 'aaaaaaaa-0000-0000-0000-000000000041'
            displayName        = 'Policy'
            accessPackage      = @{ id = 'ap-1' }
            allowedTargetScope = 'allMemberUsers'
            expiration         = @{ type = 'noExpiration' }
        }
    }
}
#CALLS#
"OWN:$(@($Error | Where-Object { $_.FullyQualifiedErrorId -eq 'NothingToUpdate,Set-OERAccessPackageAssignmentPolicy' }).Count)"
'END'
'@).Replace('#LOG#', $Log.Replace("'", "''")).Replace('#CALLS#', $Calls))
        }

        $script:A16RefusedCalls = @'
$Results = @(
    Set-OERAccessPackageAssignmentPolicy -Id 'aaaaaaaa-0000-0000-0000-000000000041' -DisplayName 'Policy' -Confirm:$false
    Set-OERAccessPackageAssignmentPolicy -Id 'aaaaaaaa-0000-0000-0000-000000000041' -DisplayName 'POLICY' -Confirm:$false
    Set-OERAccessPackageAssignmentPolicy -Id 'aaaaaaaa-0000-0000-0000-000000000041' -DisplayName 'policy' -WhatIf
)
"REACHED:$(@($Results | Where-Object { $null -ne $_ }).Count)"
'@
        $script:A16RefusedThenRenamedCalls = @'
$Results = @(
    Set-OERAccessPackageAssignmentPolicy -Id 'aaaaaaaa-0000-0000-0000-000000000041' -DisplayName 'policy' -Confirm:$false
    Set-OERAccessPackageAssignmentPolicy -Id 'aaaaaaaa-0000-0000-0000-000000000041' -DisplayName 'Renamed' -Confirm:$false
)
"REACHED:$(@($Results | Where-Object { $null -ne $_ }).Count)"
'@
        function Get-A16RequestLog ([string]$Log) {
            if (Test-Path -LiteralPath $Log) { @(Get-Content -LiteralPath $Log) } else { @() }
        }
    }

    It 'reaches the end of the script, sends no PUT, and writes NothingToUpdate once per call (with and without -WhatIf)' {
        $Log = Join-Path $TestDrive ('{0}.log' -f [guid]::NewGuid())
        $Scenario = & $script:A16NoTryScenario -Log $Log -Calls $script:A16RefusedCalls
        $Run = Invoke-OERWithConfirmAnswer -Answer '&Yes' -Script $Scenario
        ($Run.Output -join '|') | Should -Be 'REACHED:0|OWN:3|END'
        # Positive proof: each refused call read the live policy, and that was all it sent.
        @(Get-A16RequestLog -Log $Log) | Should -Be @('Invoke-OERGraphRequest GET', 'Invoke-OERGraphRequest GET', 'Invoke-OERGraphRequest GET')
        @($Run.Errors).Count | Should -Be 3
        @($Run.Errors | Where-Object { $_ -ceq $script:A16NoTryMessage }).Count | Should -Be 3
    }

    It 'the control: a different name in the same script, after a refused call, sends the PUT with the new name' {
        $Log = Join-Path $TestDrive ('{0}.log' -f [guid]::NewGuid())
        $Scenario = & $script:A16NoTryScenario -Log $Log -Calls $script:A16RefusedThenRenamedCalls
        $Run = Invoke-OERWithConfirmAnswer -Answer '&Yes' -Script $Scenario
        ($Run.Output -join '|') | Should -Be 'REACHED:1|OWN:1|END'
        @($Run.Errors).Count | Should -Be 1
        @($Run.Errors | Where-Object { $_ -ceq $script:A16NoTryMessage }).Count | Should -Be 1
        @(Get-A16RequestLog -Log $Log) | Should -Be @(
            'Invoke-OERGraphRequest GET'
            'Invoke-OERGraphRequest GET'
            'Invoke-OERGraphRequest PUT name=Renamed'
        )
    }
}

Describe 'Set-OERAccessPackageAssignmentPolicy refuses a read allowedTargetScope of unknownFutureValue (Sprint 11 step 11, BL-49)' {
    # MEASURED LIVE (Sprint 11 step 11, check 1.1): a PUT whose allowedTargetScope is unknownFutureValue
    # answers 200 and STORES the placeholder as the policy's scope. Microsoft Graph names a scope it
    # does not model that way only when the caller sends 'Prefer: include-unknown-enum-members', which
    # this module never does -- so a policy that reads back so and is updated without -RequestorScope
    # would have the placeholder carried back and its real scope replaced. The cmdlet therefore refuses
    # BEFORE ConvertTo-OERPolicyBody, ShouldProcess and the PUT, the same read the apply engine already
    # refuses in Sync-OERStructureAccessPackage. A bound -RequestorScope writes as before.
    BeforeAll {
        $script:Bl49Id = 'bbbbbbbb-0000-0000-0000-000000000011'
        $script:Bl49Message = "Microsoft Graph returned allowedTargetScope 'unknownFutureValue' for assignment policy 'bbbbbbbb-0000-0000-0000-000000000011', a placeholder for a scope this module cannot read without the 'Prefer: include-unknown-enum-members' header; writing it back would replace the policy's requestor scope, so nothing was sent. Pass -RequestorScope to set the scope."

        function Invoke-Bl49Set {
            param([hashtable]$Splat, [bool]$UseWhatIf = $false)
            $Err = $null
            $Result = Set-OERAccessPackageAssignmentPolicy -Id $script:Bl49Id @Splat -WhatIf:$UseWhatIf -Confirm:$false `
                -ErrorAction SilentlyContinue -ErrorVariable Err
            [PSCustomObject]@{ Result = $Result; Errors = @($Err) }
        }
    }

    BeforeEach {
        InModuleScope $script:moduleName { $script:_OERAuthState = $null }
        Mock -ModuleName $script:moduleName Initialize-OERAuth { }
        # The live policy's scope is whatever the test sets in $script:Bl49ReadScope; $null omits the key.
        $script:Bl49ReadScope = 'unknownFutureValue'
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {
            $Live = @{
                id            = 'bbbbbbbb-0000-0000-0000-000000000011'
                displayName   = 'Policy'
                accessPackage = @{ id = 'ap-1' }
                expiration    = @{ type = 'noExpiration' }
            }
            if ($null -ne $script:Bl49ReadScope) { $Live.allowedTargetScope = $script:Bl49ReadScope }
            $Live
        } -ParameterFilter { -not $Method -or $Method -eq 'GET' }
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {
            @{
                id                 = 'bbbbbbbb-0000-0000-0000-000000000011'
                displayName        = $Body.displayName
                allowedTargetScope = $Body.allowedTargetScope
                expiration         = @{ type = 'noExpiration' }
            }
        } -ParameterFilter { $Method -eq 'PUT' }
    }

    Context 'the refusal' {
        It 'refuses a read scope of <ReadScope> without -RequestorScope: one record, no PUT, no output, the policy read once (WhatIf: <UseWhatIf>)' -ForEach @(
            @{ ReadScope = 'unknownFutureValue'; UseWhatIf = $false }
            @{ ReadScope = 'unknownFutureValue'; UseWhatIf = $true }
            @{ ReadScope = 'UNKNOWNFUTUREVALUE'; UseWhatIf = $false }
            @{ ReadScope = 'UnknownFutureValue'; UseWhatIf = $true }
        ) {
            $script:Bl49ReadScope = $ReadScope

            $Run = Invoke-Bl49Set -Splat @{ DisplayName = 'Policy'; DurationInDays = 30 } -UseWhatIf $UseWhatIf

            $Run.Result | Should -BeNullOrEmpty
            # The only record this call writes is its own: exactly one, cmdlet-qualified.
            $Run.Errors.Count | Should -Be 1
            $Run.Errors[0].FullyQualifiedErrorId | Should -Be 'UnknownAllowedTargetScope,Set-OERAccessPackageAssignmentPolicy'
            $Run.Errors[0].CategoryInfo.Category | Should -Be 'InvalidData'
            $Run.Errors[0].TargetObject | Should -Be $script:Bl49Id
            $Run.Errors[0].Exception.Message | Should -BeExactly $script:Bl49Message
            # Positive proof that the guard was reached: the live policy was read, once, and that was
            # the only request made.
            Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 1 -Exactly -ParameterFilter {
                (-not $Method -or $Method -eq 'GET') -and
                $Uri -ceq 'v1.0/identityGovernance/entitlementManagement/assignmentPolicies/bbbbbbbb-0000-0000-0000-000000000011?$expand=accessPackage,customExtensionStageSettings($expand=customExtension)'
            }
            Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 1 -Exactly
            Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 0 -ParameterFilter { $Method -eq 'PUT' }
        }

        It 'refuses a rename that supplies no other property (the full update would carry the placeholder back)' {
            $Run = Invoke-Bl49Set -Splat @{ DisplayName = 'Renamed' }

            $Run.Result | Should -BeNullOrEmpty
            $Run.Errors.Count | Should -Be 1
            $Run.Errors[0].FullyQualifiedErrorId | Should -Be 'UnknownAllowedTargetScope,Set-OERAccessPackageAssignmentPolicy'
            Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 1 -Exactly
            Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 0 -ParameterFilter { $Method -eq 'PUT' }
        }

        It 'reports the missing access package first: the refusal comes after the AccessPackageNotFound check' {
            Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {
                @{ id = 'bbbbbbbb-0000-0000-0000-000000000011'; displayName = 'Policy'; allowedTargetScope = 'unknownFutureValue' }
            } -ParameterFilter { -not $Method -or $Method -eq 'GET' }

            $Run = Invoke-Bl49Set -Splat @{ DisplayName = 'Policy'; DurationInDays = 30 }

            $Run.Errors.Count | Should -Be 1
            $Run.Errors[0].FullyQualifiedErrorId | Should -Be 'AccessPackageNotFound,Set-OERAccessPackageAssignmentPolicy'
            Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 1 -Exactly
            Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 0 -ParameterFilter { $Method -eq 'PUT' }
        }
    }

    Context 'what the refusal leaves alone' {
        It 'writes the bound -RequestorScope when the read scope is unknownFutureValue (<ReadScope>)' -ForEach @(
            @{ ReadScope = 'unknownFutureValue' }
            @{ ReadScope = 'UNKNOWNFUTUREVALUE' }
        ) {
            $script:Bl49ReadScope = $ReadScope
            $Scope = New-OERAccessPackageRequestorScope -Scope AllMemberUsers -ErrorAction Stop

            $Run = Invoke-Bl49Set -Splat @{ DisplayName = 'Policy'; RequestorScope = $Scope }

            $Run.Errors.Count | Should -Be 0
            $Run.Result.PSObject.TypeNames[0] | Should -Be 'Omnicit.EntraRBAC.AssignmentPolicy'
            Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 1 -Exactly -ParameterFilter {
                -not $Method -or $Method -eq 'GET'
            }
            Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 1 -Exactly -ParameterFilter {
                $Method -eq 'PUT' -and
                $Uri -like '*assignmentPolicies/bbbbbbbb-0000-0000-0000-000000000011' -and
                $Body.allowedTargetScope -ceq 'allMemberUsers'
            }
        }

        It 'carries a known read scope forward as before when -RequestorScope is omitted (<ReadScope>)' -ForEach @(
            @{ ReadScope = 'allMemberUsers' }
            @{ ReadScope = 'specificDirectoryUsers' }
            @{ ReadScope = 'unknownFutureValues' }
            @{ ReadScope = $null }
        ) {
            $script:Bl49ReadScope = $ReadScope

            $Run = Invoke-Bl49Set -Splat @{ DisplayName = 'Policy'; DurationInDays = 30 }

            $Run.Errors.Count | Should -Be 0
            $Run.Result.PSObject.TypeNames[0] | Should -Be 'Omnicit.EntraRBAC.AssignmentPolicy'
            Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 1 -Exactly -ParameterFilter {
                $Method -eq 'PUT' -and
                $Uri -like '*assignmentPolicies/bbbbbbbb-0000-0000-0000-000000000011' -and
                $Body.allowedTargetScope -ceq $script:Bl49ReadScope
            }
        }
    }
}

Describe 'Set-OERAccessPackageAssignmentPolicy: the unknownFutureValue refusal in a script with no try (Sprint 11 step 11, BL-49)' {
    # A refused call writes a NON-terminating error and the script goes on, so what it must not do is
    # send the PUT on the way. The script stands in no try, prints a sentinel at its end, and the
    # stubbed transport appends every request to a log file whose path is substituted into the text.
    # The control runs the allowed form (a bound -RequestorScope) in the same script with the same
    # stub, so a refused run with no PUT in the log cannot be an artefact of a stub that never logs
    # one. The stub writes its log with -WhatIf:$false, so a -WhatIf request would still show in it.
    BeforeAll {
        $script:Bl49NoTryMessage = "Microsoft Graph returned allowedTargetScope 'unknownFutureValue' for assignment policy 'bbbbbbbb-0000-0000-0000-000000000021', a placeholder for a scope this module cannot read without the 'Prefer: include-unknown-enum-members' header; writing it back would replace the policy's requestor scope, so nothing was sent. Pass -RequestorScope to set the scope."

        $script:Bl49NoTryScenario = {
            param([string]$Log, [string]$Calls)
            [scriptblock]::Create((@'
Import-Module Omnicit.EntraRBAC -Force -ErrorAction Stop
$Module = Get-Module Omnicit.EntraRBAC
& $Module {
    Set-Item -Path function:script:Initialize-OERAuth -Value { }
    Set-Item -Path function:script:Remove-OERErrorRecord -Value { }
    Set-Item -Path function:script:Invoke-OERGraphRequest -Value {
        param([string]$Method = 'GET', [string]$Uri, $Body)
        if ($Method -eq 'PUT') {
            Add-Content -LiteralPath '#LOG#' -WhatIf:$false -Value "Invoke-OERGraphRequest PUT scope=$($Body.allowedTargetScope)"
            return @{ id = 'bbbbbbbb-0000-0000-0000-000000000021'; displayName = 'Policy'; allowedTargetScope = $Body.allowedTargetScope; expiration = @{ type = 'noExpiration' } }
        }
        Add-Content -LiteralPath '#LOG#' -WhatIf:$false -Value "Invoke-OERGraphRequest $Method"
        @{
            id                 = 'bbbbbbbb-0000-0000-0000-000000000021'
            displayName        = 'Policy'
            accessPackage      = @{ id = 'ap-1' }
            allowedTargetScope = 'unknownFutureValue'
            expiration         = @{ type = 'noExpiration' }
        }
    }
}
$Scope = New-OERAccessPackageRequestorScope -Scope AllMemberUsers
#CALLS#
"OWN:$(@($Error | Where-Object { $_.FullyQualifiedErrorId -eq 'UnknownAllowedTargetScope,Set-OERAccessPackageAssignmentPolicy' }).Count)"
'END'
'@).Replace('#LOG#', $Log.Replace("'", "''")).Replace('#CALLS#', $Calls))
        }

        $script:Bl49RefusedCalls = @'
$Results = @(
    Set-OERAccessPackageAssignmentPolicy -Id 'bbbbbbbb-0000-0000-0000-000000000021' -DisplayName 'Policy' -DurationInDays 30 -Confirm:$false
    Set-OERAccessPackageAssignmentPolicy -Id 'bbbbbbbb-0000-0000-0000-000000000021' -DisplayName 'Renamed' -WhatIf
)
"REACHED:$(@($Results | Where-Object { $null -ne $_ }).Count)"
'@
        $script:Bl49AllowedCalls = @'
$Results = @(
    Set-OERAccessPackageAssignmentPolicy -Id 'bbbbbbbb-0000-0000-0000-000000000021' -DisplayName 'Policy' -RequestorScope $Scope -Confirm:$false
)
"REACHED:$(@($Results | Where-Object { $null -ne $_ }).Count)"
'@
        $script:Bl49RefusedThenAllowedCalls = @'
$Results = @(
    Set-OERAccessPackageAssignmentPolicy -Id 'bbbbbbbb-0000-0000-0000-000000000021' -DisplayName 'Policy' -DurationInDays 30 -Confirm:$false
    Set-OERAccessPackageAssignmentPolicy -Id 'bbbbbbbb-0000-0000-0000-000000000021' -DisplayName 'Policy' -RequestorScope $Scope -Confirm:$false
)
"REACHED:$(@($Results | Where-Object { $null -ne $_ }).Count)"
'@
        function Get-Bl49RequestLog ([string]$Log) {
            if (Test-Path -LiteralPath $Log) { @(Get-Content -LiteralPath $Log) } else { @() }
        }
    }

    It 'reaches the end of the script, sends no PUT, and writes the refusal once per call (with and without -WhatIf)' {
        $Log = Join-Path $TestDrive ('{0}.log' -f [guid]::NewGuid())
        $Scenario = & $script:Bl49NoTryScenario -Log $Log -Calls $script:Bl49RefusedCalls
        $Run = Invoke-OERWithConfirmAnswer -Answer '&Yes' -Script $Scenario
        ($Run.Output -join '|') | Should -Be 'REACHED:0|OWN:2|END'
        # Positive proof: each refused call read the live policy, and that was all it sent.
        @(Get-Bl49RequestLog -Log $Log) | Should -Be @('Invoke-OERGraphRequest GET', 'Invoke-OERGraphRequest GET')
        @($Run.Errors).Count | Should -Be 2
        @($Run.Errors | Where-Object { $_ -ceq $script:Bl49NoTryMessage }).Count | Should -Be 2
    }

    It 'the control: the same script with a bound -RequestorScope sends the PUT with that scope' {
        $Log = Join-Path $TestDrive ('{0}.log' -f [guid]::NewGuid())
        $Scenario = & $script:Bl49NoTryScenario -Log $Log -Calls $script:Bl49AllowedCalls
        $Run = Invoke-OERWithConfirmAnswer -Answer '&Yes' -Script $Scenario
        ($Run.Output -join '|') | Should -Be 'REACHED:1|OWN:0|END'
        @($Run.Errors).Count | Should -Be 0
        @(Get-Bl49RequestLog -Log $Log) | Should -Be @('Invoke-OERGraphRequest GET', 'Invoke-OERGraphRequest PUT scope=allMemberUsers')
    }

    It 'carries on after a refused call: the next call in the same script sends its PUT' {
        $Log = Join-Path $TestDrive ('{0}.log' -f [guid]::NewGuid())
        $Scenario = & $script:Bl49NoTryScenario -Log $Log -Calls $script:Bl49RefusedThenAllowedCalls
        $Run = Invoke-OERWithConfirmAnswer -Answer '&Yes' -Script $Scenario
        ($Run.Output -join '|') | Should -Be 'REACHED:1|OWN:1|END'
        @($Run.Errors).Count | Should -Be 1
        @($Run.Errors | Where-Object { $_ -ceq $script:Bl49NoTryMessage }).Count | Should -Be 1
        @(Get-Bl49RequestLog -Log $Log) | Should -Be @(
            'Invoke-OERGraphRequest GET'
            'Invoke-OERGraphRequest GET'
            'Invoke-OERGraphRequest PUT scope=allMemberUsers'
        )
    }
}
