BeforeAll {
    $script:moduleName = 'Omnicit.EntraRBAC'
    Get-Module $script:moduleName | Remove-Module -Force -ErrorAction SilentlyContinue
    Import-Module $script:moduleName -Force -ErrorAction Stop
}

Describe 'ConvertTo-OERPolicyBody' {
    It 'assembles displayName, accessPackage reference, scope, stages and duration expiration' {
        InModuleScope $script:moduleName {
            $Scope = New-OERAccessPackageRequestorScope -Scope AllMemberUsers
            $Stage = New-OERAccessPackageApprovalStage -DurationDays 7 -Manager
            $Body = ConvertTo-OERPolicyBody -DisplayName 'Default' -AccessPackageId 'ap-1' `
                -RequestorScope $Scope -ApprovalStage $Stage -DurationInDays 30
            $Body.displayName | Should -Be 'Default'
            $Body.accessPackage.id | Should -Be 'ap-1'
            $Body.ContainsKey('accessPackageId') | Should -BeFalse
            $Body.ContainsKey('canExtend') | Should -BeFalse
            $Body.allowedTargetScope | Should -Be 'allMemberUsers'
            $Body.requestApprovalSettings.isApprovalRequiredForAdd | Should -BeTrue
            $Body.requestApprovalSettings.stages.Count | Should -Be 1
            $Body.requestApprovalSettings.stages[0].durationBeforeAutomaticDenial | Should -Be 'P7D'
            $Body.expiration.type | Should -Be 'afterDuration'
            $Body.expiration.duration | Should -Be 'P30D'
        }
    }

    It 'sets isApprovalRequiredForAdd false and noExpiration when no stages and no duration' {
        InModuleScope $script:moduleName {
            $Scope = New-OERAccessPackageRequestorScope -AdminAssignmentOnly
            $Body = ConvertTo-OERPolicyBody -DisplayName 'AdminOnly' -AccessPackageId 'ap-1' -RequestorScope $Scope
            $Body.requestApprovalSettings.isApprovalRequiredForAdd | Should -BeFalse
            $Body.expiration.type | Should -Be 'noExpiration'
        }
    }

    It 'uses afterDateTime expiration when -ExpirationDateTime is given' {
        InModuleScope $script:moduleName {
            $Scope = New-OERAccessPackageRequestorScope -Scope AllMemberUsers
            $When = [datetime]'2027-01-01T00:00:00Z'
            $Body = ConvertTo-OERPolicyBody -DisplayName 'd' -AccessPackageId 'ap-1' -RequestorScope $Scope -ExpirationDateTime $When
            $Body.expiration.type | Should -Be 'afterDateTime'
            $Body.expiration.endDateTime | Should -Match '2027-01-01'
        }
    }

    It 'always emits description defaulting to the display name when omitted' {
        InModuleScope $script:moduleName {
            $Scope = New-OERAccessPackageRequestorScope -Scope AllMemberUsers
            $Body = ConvertTo-OERPolicyBody -DisplayName 'Default' -AccessPackageId 'ap-1' -RequestorScope $Scope
            $Body.ContainsKey('description') | Should -BeTrue
            $Body.description | Should -Be 'Default'
        }
    }
}

Describe 'ConvertTo-OERPolicyBody (granular)' {
    It 'defaults description to display name when omitted' {
        InModuleScope Omnicit.EntraRBAC {
            $scope = New-OERAccessPackageRequestorScope -Scope AllMemberUsers
            (ConvertTo-OERPolicyBody -DisplayName 'P' -AccessPackageId 'ap' -RequestorScope $scope).description | Should -Be 'P'
        }
    }
    It 'keeps explicit description' {
        InModuleScope Omnicit.EntraRBAC {
            $scope = New-OERAccessPackageRequestorScope -Scope AllMemberUsers
            (ConvertTo-OERPolicyBody -DisplayName 'P' -Description 'D' -AccessPackageId 'ap' -RequestorScope $scope).description | Should -Be 'D'
        }
    }
    It 'embeds requestorSettings from the builder' {
        InModuleScope Omnicit.EntraRBAC {
            $scope = New-OERAccessPackageRequestorScope -Scope AllMemberUsers
            $rs = New-OERAccessPackageRequestorSettings -AllowSelfRequest
            (ConvertTo-OERPolicyBody -DisplayName 'P' -AccessPackageId 'ap' -RequestorScope $scope -RequestorSettings $rs).requestorSettings.enableTargetsToSelfAddAccess | Should -BeTrue
        }
    }
    It 'New default requestorSettings enables self add' {
        InModuleScope Omnicit.EntraRBAC {
            $scope = New-OERAccessPackageRequestorScope -Scope AllMemberUsers
            (ConvertTo-OERPolicyBody -DisplayName 'P' -AccessPackageId 'ap' -RequestorScope $scope).requestorSettings.enableTargetsToSelfAddAccess | Should -BeTrue
        }
    }
    It 'emits hours expiration as PT8H afterDuration' {
        InModuleScope Omnicit.EntraRBAC {
            $scope = New-OERAccessPackageRequestorScope -Scope AllMemberUsers
            $b = ConvertTo-OERPolicyBody -DisplayName 'P' -AccessPackageId 'ap' -RequestorScope $scope -DurationInHours 8
            $b.expiration.type | Should -Be 'afterDuration'
            $b.expiration.duration | Should -Be 'PT8H'
        }
    }
    It 'sets isApprovalRequiredForAdd from -RequireApproval even with no stages' {
        InModuleScope Omnicit.EntraRBAC {
            $scope = New-OERAccessPackageRequestorScope -Scope AllMemberUsers
            (ConvertTo-OERPolicyBody -DisplayName 'P' -AccessPackageId 'ap' -RequestorScope $scope -RequireApproval $true).requestApprovalSettings.isApprovalRequiredForAdd | Should -BeTrue
        }
    }
    It 'sets notificationSettings' {
        InModuleScope Omnicit.EntraRBAC {
            $scope = New-OERAccessPackageRequestorScope -Scope AllMemberUsers
            (ConvertTo-OERPolicyBody -DisplayName 'P' -AccessPackageId 'ap' -RequestorScope $scope -DisableAssignmentNotifications $true).notificationSettings.isAssignmentNotificationDisabled | Should -BeTrue
        }
    }
    It 'overlay: preserves Existing requestorSettings + reviewSettings + isApprovalRequiredForUpdate when not provided' {
        InModuleScope Omnicit.EntraRBAC {
            $scope = New-OERAccessPackageRequestorScope -Scope AllMemberUsers
            $existing = @{
                requestorSettings = @{ enableTargetsToSelfAddAccess=$false; allowCustomAssignmentSchedule=$true }
                reviewSettings = @{ isEnabled=$true }
                requestApprovalSettings = @{ isApprovalRequiredForAdd=$true; isApprovalRequiredForUpdate=$true; isRequestorJustificationRequired=$true; stages=@() }
                expiration = @{ type='noExpiration' }
            }
            $b = ConvertTo-OERPolicyBody -DisplayName 'P' -AccessPackageId 'ap' -RequestorScope $scope -Existing $existing
            $b.requestorSettings.allowCustomAssignmentSchedule | Should -BeTrue
            $b.reviewSettings.isEnabled | Should -BeTrue
            $b.requestApprovalSettings.isApprovalRequiredForUpdate | Should -BeTrue
        }
    }
    It 'rejects a -RequestorSettings that is not the builder type' {
        InModuleScope Omnicit.EntraRBAC {
            $scope = New-OERAccessPackageRequestorScope -Scope AllMemberUsers
            { ConvertTo-OERPolicyBody -DisplayName 'P' -AccessPackageId 'ap' -RequestorScope $scope -RequestorSettings ([pscustomobject]@{x=1}) } | Should -Throw
        }
    }

    It 'carries Existing expiration verbatim when no duration/date provided' {
        InModuleScope Omnicit.EntraRBAC {
            $scope = New-OERAccessPackageRequestorScope -Scope AllMemberUsers
            $existing = @{ expiration = @{ type='afterDuration'; duration='P90D' } }
            $b = ConvertTo-OERPolicyBody -DisplayName 'P' -AccessPackageId 'ap' -RequestorScope $scope -Existing $existing
            $b.expiration.type | Should -Be 'afterDuration'
            $b.expiration.duration | Should -Be 'P90D'
        }
    }

    It 'carries Existing approval stages and questions verbatim when not provided' {
        InModuleScope Omnicit.EntraRBAC {
            $scope = New-OERAccessPackageRequestorScope -Scope AllMemberUsers
            $existing = @{
                requestApprovalSettings = @{ isApprovalRequiredForAdd=$true; stages=@(@{ durationBeforeAutomaticDenial='P3D' }) }
                questions = @(@{ id='q1' })
            }
            $b = ConvertTo-OERPolicyBody -DisplayName 'P' -AccessPackageId 'ap' -RequestorScope $scope -Existing $existing
            $b.requestApprovalSettings.stages.Count | Should -Be 1
            $b.requestApprovalSettings.isApprovalRequiredForAdd | Should -BeTrue
            $b.questions.Count | Should -Be 1
        }
    }

    It 'provided ApprovalStage overrides Existing stages' {
        InModuleScope Omnicit.EntraRBAC {
            $scope = New-OERAccessPackageRequestorScope -Scope AllMemberUsers
            $stage = New-OERAccessPackageApprovalStage -DurationDays 7 -Manager
            $existing = @{ requestApprovalSettings = @{ isApprovalRequiredForAdd=$false; stages=@() } }
            $b = ConvertTo-OERPolicyBody -DisplayName 'P' -AccessPackageId 'ap' -RequestorScope $scope -ApprovalStage $stage -Existing $existing
            $b.requestApprovalSettings.stages.Count | Should -Be 1
            $b.requestApprovalSettings.isApprovalRequiredForAdd | Should -BeTrue
        }
    }

    It 'ApprovalStage bound to an EMPTY array clears the Existing stages and follows isApprovalRequiredForAdd down to false' {
        InModuleScope Omnicit.EntraRBAC {
            # Issue #56. The apply-engine fix rests on this exact binding, so it is pinned HERE at the
            # single owner rather than only through a mocked handler. Two things must hold together:
            # the stages go to [], and the DERIVED isApprovalRequiredForAdd follows them down to $false
            # (:229-230). If it did not, the body would carry isApprovalRequiredForAdd = true alongside
            # stages = [], which is self-contradictory -- and every handler-level test would still pass.
            $Scope = New-OERAccessPackageRequestorScope -Scope AllMemberUsers
            $Existing = @{
                allowedTargetScope      = 'allMemberUsers'
                expiration              = @{ type = 'noExpiration' }
                requestApprovalSettings = @{
                    isApprovalRequiredForAdd         = $true
                    isApprovalRequiredForUpdate      = $true
                    isRequestorJustificationRequired = $true
                    stages                           = @(@{ durationBeforeAutomaticDenial = 'P3D' })
                }
            }
            $Body = ConvertTo-OERPolicyBody -DisplayName 'P' -AccessPackageId 'ap' -RequestorScope $Scope -ApprovalStage @() -Existing $Existing

            @($Body.requestApprovalSettings.stages).Count | Should -Be 0
            # -Be $false rather than -BeFalse: -BeFalse also passes on $null, so it would pass if the
            # key vanished from the body entirely.
            $Body.requestApprovalSettings.isApprovalRequiredForAdd | Should -Be $false
            # requestApprovalSettings is assembled as ONE unit (:288-291), so clearing the stages must
            # not take the sibling booleans the caller never mentioned with it. That is the
            # composite-field-wiped-when-sent-empty hazard from audit PR-5 (#29).
            $Body.requestApprovalSettings.isApprovalRequiredForUpdate | Should -Be $true
            $Body.requestApprovalSettings.isRequestorJustificationRequired | Should -Be $true
        }
    }

    It 'ApprovalStage OMITTED against the same Existing carries the live stages forward instead of clearing them' {
        InModuleScope Omnicit.EntraRBAC {
            # The counterpart to the empty-array case above: only the PAIR pins the behaviour. A build
            # that emitted stages = [] unconditionally would pass the empty-array test on its own.
            $Scope = New-OERAccessPackageRequestorScope -Scope AllMemberUsers
            $Existing = @{
                allowedTargetScope      = 'allMemberUsers'
                expiration              = @{ type = 'noExpiration' }
                requestApprovalSettings = @{
                    isApprovalRequiredForAdd         = $true
                    isApprovalRequiredForUpdate      = $true
                    isRequestorJustificationRequired = $true
                    stages                           = @(@{ durationBeforeAutomaticDenial = 'P3D' })
                }
            }
            $Body = ConvertTo-OERPolicyBody -DisplayName 'P' -AccessPackageId 'ap' -RequestorScope $Scope -Existing $Existing

            @($Body.requestApprovalSettings.stages).Count | Should -Be 1
            $Body.requestApprovalSettings.stages[0].durationBeforeAutomaticDenial | Should -Be 'P3D'
            $Body.requestApprovalSettings.isApprovalRequiredForAdd | Should -Be $true
        }
    }

    It 'New default notificationSettings is not disabled' {
        InModuleScope Omnicit.EntraRBAC {
            $scope = New-OERAccessPackageRequestorScope -Scope AllMemberUsers
            (ConvertTo-OERPolicyBody -DisplayName 'P' -AccessPackageId 'ap' -RequestorScope $scope).notificationSettings.isAssignmentNotificationDisabled | Should -BeFalse
        }
    }

    It 'omits reviewSettings and questions on New (no Existing)' {
        InModuleScope Omnicit.EntraRBAC {
            $scope = New-OERAccessPackageRequestorScope -Scope AllMemberUsers
            $b = ConvertTo-OERPolicyBody -DisplayName 'P' -AccessPackageId 'ap' -RequestorScope $scope
            $b.ContainsKey('reviewSettings') | Should -BeFalse
            $b.ContainsKey('questions') | Should -BeFalse
        }
    }
}

Describe 'ConvertTo-OERPolicyBody description overlay' {
    BeforeAll {
        Import-Module Omnicit.EntraRBAC -Force
    }

    It 'carries the existing description forward when -Description is omitted' {
        InModuleScope Omnicit.EntraRBAC {
            $Scope = New-OERAccessPackageRequestorScope -Scope AllMemberUsers
            $Body = ConvertTo-OERPolicyBody -DisplayName 'Standard access' -AccessPackageId 'ap-1' `
                -RequestorScope $Scope -Existing @{ description = 'Business justification required'; expiration = @{ type = 'noExpiration' } }
            $Body.description | Should -Be 'Business justification required'
        }
    }

    It 'still defaults the description to the display name on New (no -Existing)' {
        InModuleScope Omnicit.EntraRBAC {
            $Scope = New-OERAccessPackageRequestorScope -Scope AllMemberUsers
            $Body = ConvertTo-OERPolicyBody -DisplayName 'Standard access' -AccessPackageId 'ap-1' -RequestorScope $Scope
            $Body.description | Should -Be 'Standard access'
        }
    }

    It 'defaults to the display name when -Existing carries no description' {
        InModuleScope Omnicit.EntraRBAC {
            $Scope = New-OERAccessPackageRequestorScope -Scope AllMemberUsers
            $Body = ConvertTo-OERPolicyBody -DisplayName 'Standard access' -AccessPackageId 'ap-1' `
                -RequestorScope $Scope -Existing @{ expiration = @{ type = 'noExpiration' } }
            $Body.description | Should -Be 'Standard access'
        }
    }

    It 'lets an explicit -Description win over the existing description' {
        InModuleScope Omnicit.EntraRBAC {
            $Scope = New-OERAccessPackageRequestorScope -Scope AllMemberUsers
            $Body = ConvertTo-OERPolicyBody -DisplayName 'Standard access' -AccessPackageId 'ap-1' `
                -RequestorScope $Scope -Description 'New text' -Existing @{ description = 'Old text' }
            $Body.description | Should -Be 'New text'
        }
    }
}

Describe 'ConvertTo-OERPolicyBody explicit empty description' {
    # NOTE: the task brief's sample used [PSCustomObject]@{ description = 'live text' } for -Existing,
    # but -Existing is typed [hashtable] (it is documented as "the raw Graph hashtable" and every other
    # test in this file passes a hashtable literal). A PSCustomObject fails parameter binding outright
    # with a type-conversion error, before the code under test ever runs, so it cannot exercise the
    # truthiness-vs-binding fix. Using a hashtable here matches the real signature and the rest of the file.
    It 'writes an explicitly empty description instead of carrying the live one forward' {
        InModuleScope 'Omnicit.EntraRBAC' {
            $Existing = @{ description = 'live text' }
            $Body = ConvertTo-OERPolicyBody -DisplayName 'P' -AccessPackageId 'ap-1' -Description '' -Existing $Existing
            $Body.description | Should -BeExactly ''
        }
    }

    It 'still carries the live description forward when -Description is not bound at all' {
        InModuleScope 'Omnicit.EntraRBAC' {
            $Existing = @{ description = 'live text' }
            $Body = ConvertTo-OERPolicyBody -DisplayName 'P' -AccessPackageId 'ap-1' -Existing $Existing
            $Body.description | Should -BeExactly 'live text'
        }
    }

    # NOTE: the review's sample called ConvertTo-OERPolicyBody with -RequestorScope 'AllMemberUsers'
    # (a raw string), but -RequestorScope validates its argument's PSObject.TypeNames and throws
    # '-RequestorScope must be an object from New-OERAccessPackageRequestorScope.' for anything that
    # is not that builder's output -- confirmed by direct execution. Omitting -RequestorScope entirely
    # (as the two tests above already do) satisfies the function's "-RequestorScope or -Existing"
    # requirement via -Existing alone, since a one-key hashtable is truthy, so it is unnecessary here.
    It 'carries an already-empty live description forward instead of stamping the display name' {
        InModuleScope 'Omnicit.EntraRBAC' {
            $Existing = @{ description = '' }
            $Body = ConvertTo-OERPolicyBody -DisplayName 'P' -AccessPackageId 'ap-1' -Existing $Existing
            $Body.description | Should -BeExactly ''
        }
    }

    # NOTE: the brief's sample called ConvertTo-OERPolicyBody with neither -RequestorScope nor
    # -Existing, but the function requires one of the two (see the "requestor scope overlay" Describe
    # below) and throws before the description logic runs. Supplying -RequestorScope keeps the "no
    # -Existing" condition this test is actually about while letting the call succeed.
    It 'still defaults an unbound description to the display name when there is no existing policy' {
        InModuleScope 'Omnicit.EntraRBAC' {
            $Scope = New-OERAccessPackageRequestorScope -Scope AllMemberUsers
            $Body = ConvertTo-OERPolicyBody -DisplayName 'P' -AccessPackageId 'ap-1' -RequestorScope $Scope
            $Body.description | Should -BeExactly 'P'
        }
    }
}

Describe 'ConvertTo-OERPolicyBody requestor scope overlay' {
    It 'carries allowedTargetScope and specificAllowedTargets from Existing when -RequestorScope is omitted' {
        InModuleScope Omnicit.EntraRBAC {
            $Existing = @{
                allowedTargetScope     = 'specificDirectoryUsers'
                specificAllowedTargets = @(@{ '@odata.type' = '#microsoft.graph.singleUser'; userId = 'u-1' })
                expiration             = @{ type = 'noExpiration' }
            }
            $Body = ConvertTo-OERPolicyBody -DisplayName 'p' -AccessPackageId 'ap-1' -Existing $Existing -DurationInDays 30
            $Body.allowedTargetScope | Should -Be 'specificDirectoryUsers'
            @($Body.specificAllowedTargets).Count | Should -Be 1
            @($Body.specificAllowedTargets)[0].userId | Should -Be 'u-1'
        }
    }

    It 'throws when neither -RequestorScope nor -Existing is supplied' {
        InModuleScope Omnicit.EntraRBAC {
            { ConvertTo-OERPolicyBody -DisplayName 'p' -AccessPackageId 'ap-1' } |
                Should -Throw '*-RequestorScope is required*'
        }
    }

    It 'lets an explicit -RequestorScope win over Existing' {
        InModuleScope Omnicit.EntraRBAC {
            $Scope = New-OERAccessPackageRequestorScope -Scope AllMemberUsers
            $Existing = @{ allowedTargetScope = 'specificDirectoryUsers'; specificAllowedTargets = @(@{ userId = 'u-1' }) }
            $Body = ConvertTo-OERPolicyBody -DisplayName 'p' -AccessPackageId 'ap-1' -RequestorScope $Scope -Existing $Existing
            $Body.allowedTargetScope | Should -Be 'allMemberUsers'
            @($Body.specificAllowedTargets).Count | Should -Be 0
        }
    }
}

Describe 'ConvertTo-OERPolicyBody requestorSettings merge (stop-loss)' {
    # -Existing is declared [hashtable] and Graph returns nested hashtables for requestorSettings too --
    # this is the PRODUCTION shape, since Set-OERAccessPackageAssignmentPolicy passes what
    # Invoke-OERGraphRequest returned. A merge written with .PSObject.Properties instead of .Keys copies
    # nothing from a hashtable and the stop-loss is silently inert while a PSCustomObject-fixture suite
    # still passes -- so every test in this Describe uses a HASHTABLE -Existing.requestorSettings.
    It 'preserves an existing requestorSettings member the builder does not model' {
        InModuleScope 'Omnicit.EntraRBAC' {
            $Existing = @{
                requestorSettings = @{
                    enableTargetsToSelfAddAccess           = $true
                    enableTargetsToSelfRemoveAccess        = $true
                    enableOnBehalfRequestorsToUpdateAccess = $true
                    someFutureGraphFlag                    = $true
                }
            }
            $Built = New-OERAccessPackageRequestorSettings -AllowSelfRequest
            $Body = ConvertTo-OERPolicyBody -DisplayName 'P' -AccessPackageId 'ap-1' -RequestorSettings $Built -Existing $Existing
            $Body.requestorSettings.someFutureGraphFlag | Should -Be $true
        }
    }

    It 'lets an explicitly declared switch win over the existing value, including when it is false' {
        InModuleScope 'Omnicit.EntraRBAC' {
            $Existing = @{ requestorSettings = @{ enableTargetsToSelfRemoveAccess = $true } }
            $Built = New-OERAccessPackageRequestorSettings -AllowSelfRequest
            $Body = ConvertTo-OERPolicyBody -DisplayName 'P' -AccessPackageId 'ap-1' -RequestorSettings $Built -Existing $Existing
            $Body.requestorSettings.enableTargetsToSelfRemoveAccess | Should -Be $false
        }
    }

    It 'also merges when -Existing.requestorSettings arrives as a PSCustomObject (defensive fallback path)' {
        InModuleScope 'Omnicit.EntraRBAC' {
            $Existing = @{ requestorSettings = [PSCustomObject]@{ someFutureGraphFlag = $true } }
            $Built = New-OERAccessPackageRequestorSettings -AllowSelfRequest
            $Body = ConvertTo-OERPolicyBody -DisplayName 'P' -AccessPackageId 'ap-1' -RequestorSettings $Built -Existing $Existing
            $Body.requestorSettings.someFutureGraphFlag | Should -Be $true
        }
    }

    It 'carries the full existing requestorSettings forward verbatim when -RequestorSettings is not supplied' {
        InModuleScope 'Omnicit.EntraRBAC' {
            $Existing = @{ requestorSettings = @{ enableTargetsToSelfRemoveAccess = $true; someFutureGraphFlag = $true } }
            $Scope = New-OERAccessPackageRequestorScope -Scope AllMemberUsers
            $Body = ConvertTo-OERPolicyBody -DisplayName 'P' -AccessPackageId 'ap-1' -RequestorScope $Scope -Existing $Existing
            $Body.requestorSettings.enableTargetsToSelfRemoveAccess | Should -Be $true
            $Body.requestorSettings.someFutureGraphFlag | Should -Be $true
        }
    }

    It 'New default requestorSettings states all seven booleans, including the two on-behalf update/remove flags' {
        InModuleScope 'Omnicit.EntraRBAC' {
            $Scope = New-OERAccessPackageRequestorScope -Scope AllMemberUsers
            $Body = ConvertTo-OERPolicyBody -DisplayName 'P' -AccessPackageId 'ap-1' -RequestorScope $Scope
            $Body.requestorSettings.ContainsKey('enableOnBehalfRequestorsToUpdateAccess') | Should -Be $true
            $Body.requestorSettings.enableOnBehalfRequestorsToUpdateAccess | Should -Be $false
            $Body.requestorSettings.ContainsKey('enableOnBehalfRequestorsToRemoveAccess') | Should -Be $true
            $Body.requestorSettings.enableOnBehalfRequestorsToRemoveAccess | Should -Be $false
        }
    }
}
