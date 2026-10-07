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
                (-not $Method -or $Method -eq 'GET') -and $Uri -like '*assignmentPolicies/11111111-1111-1111-1111-111111111111?*expand=accessPackage*'
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
