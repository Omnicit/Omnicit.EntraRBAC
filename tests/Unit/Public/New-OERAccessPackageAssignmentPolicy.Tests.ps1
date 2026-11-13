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

Describe 'New-OERAccessPackageAssignmentPolicy' {
    BeforeEach {
        InModuleScope $script:moduleName { $script:_OERAuthState = $null }
        Mock -ModuleName $script:moduleName Initialize-OERAuth {}
        Mock -ModuleName $script:moduleName Resolve-OERAccessPackageId { 'ap-1' }
    }

    It 'posts the assembled policy body' {
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {
            @{ id = 'pol-1'; displayName = 'Default'; allowedTargetScope = 'allMemberUsers'; expiration = @{ type = 'afterDuration'; duration = 'P30D' } }
        } -ParameterFilter { $Method -eq 'POST' }
        $Scope = New-OERAccessPackageRequestorScope -Scope AllMemberUsers
        $Stage = New-OERAccessPackageApprovalStage -DurationDays 7 -Manager
        $R = New-OERAccessPackageAssignmentPolicy -AccessPackage 'AP-Sales' -DisplayName 'Default' -RequestorScope $Scope -ApprovalStage $Stage -DurationInDays 30
        $R.PSObject.TypeNames[0] | Should -Be 'Omnicit.EntraRBAC.AssignmentPolicy'
        Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 1 -ParameterFilter {
            $Method -eq 'POST' -and $Uri -like '*assignmentPolicies' -and
            $Body.accessPackage.id -eq 'ap-1' -and $Body.allowedTargetScope -eq 'allMemberUsers' -and
            $Body.requestApprovalSettings.stages.Count -eq 1
        }
    }

    It 'documents only alias names that actually bind on -AccessPackage (T1NEW-ap-policy-displayname-alias-help-mismatch)' {
        # Derive the CLAIMED alias names from the SHIPPED help text itself -- via Get-Help, not a
        # source grep, and not a hardcoded list -- so this test actually guards the help wording. A
        # hardcoded 'Id', 'AccessPackageId' list would keep passing even if the help block regressed
        # back to the stale "binds Id or DisplayName" wording; reading the parenthetical out of
        # Get-Help's own description text is what makes reverting that wording fail this test.
        # Get-Help word-wraps .description.Text to console width with embedded real newlines, so
        # collapse whitespace before matching (learned the hard way in the -Role caveat-sentence
        # test earlier in this task).
        $Description = ((Get-Help New-OERAccessPackageAssignmentPolicy -Parameter AccessPackage).description.Text -join ' ') -replace '\s+', ' '
        # Use the native -match operator (not Should -Match) so $Matches is actually populated in
        # this scope -- Pester's assertion does not guarantee that.
        $MatchedClause = $Description -match 'binds ([A-Za-z]+(?:(?:\s+or\s+|\s*,\s*)[A-Za-z]+)*)\)'
        $MatchedClause | Should -BeTrue -Because 'the help text should contain a (binds ...) clause naming the claimed pipeline aliases'
        $ClaimedAliases = @($Matches[1] -split '\s+or\s+|\s*,\s*' | Where-Object { $_ })
        $ClaimedAliases | Should -Not -BeNullOrEmpty

        # Rather than asserting a shared alias-set invariant across the whole -AccessPackage cohort:
        # that invariant is impossible here, because -AccessPackage also carries the real mandatory
        # -DisplayName parameter, and adding a DisplayName alias alongside it raises
        # ParameterNameConflictsWithAlias on every invocation (verified by execution) -- it would
        # brick the cmdlet, not fix a help mismatch.
        $ActualAliases = (Get-Command New-OERAccessPackageAssignmentPolicy).Parameters['AccessPackage'].Aliases
        foreach ($Claimed in $ClaimedAliases) {
            $ActualAliases | Should -Contain $Claimed
        }
        $ActualAliases | Should -Not -Contain 'DisplayName'
    }

    It 'errors when -RequestorScope is not a builder object' {
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {}
        New-OERAccessPackageAssignmentPolicy -AccessPackage 'AP-Sales' -DisplayName 'd' -RequestorScope ([pscustomobject]@{ x = 1 }) -ErrorVariable err -ErrorAction SilentlyContinue | Out-Null
        $err.FullyQualifiedErrorId | Should -Match 'InvalidPolicyInput'
        Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 0 -ParameterFilter { $Method -eq 'POST' }
    }

    It 'errors InvalidPolicyInput when both -DurationInDays and -ExpirationDateTime are supplied' {
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {}
        $Scope = New-OERAccessPackageRequestorScope -Scope AllMemberUsers
        New-OERAccessPackageAssignmentPolicy -AccessPackage 'AP-Sales' -DisplayName 'd' -RequestorScope $Scope -DurationInDays 30 -ExpirationDateTime ([datetime]'2027-01-01') -ErrorVariable Err -ErrorAction SilentlyContinue | Out-Null
        $Err[-1].FullyQualifiedErrorId | Should -Match 'InvalidPolicyInput'
        Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 0 -ParameterFilter { $Method -eq 'POST' }
    }

    It 'does not POST under -WhatIf' {
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {}
        $Scope = New-OERAccessPackageRequestorScope -AdminAssignmentOnly
        New-OERAccessPackageAssignmentPolicy -AccessPackage 'AP-Sales' -DisplayName 'd' -RequestorScope $Scope -WhatIf | Out-Null
        Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 0 -ParameterFilter { $Method -eq 'POST' }
    }

    It 'posts requestorSettings, require-approval, hours expiration, notifications; description defaults to name' {
        $script:NewBody = $null
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {
            $script:NewBody = $Body
            @{ id = 'pol-1'; displayName = 'Pol'; allowedTargetScope = 'allMemberUsers'; expiration = @{ type = 'afterDuration'; duration = 'PT8H' } }
        } -ParameterFilter { $Method -eq 'POST' }
        $Scope = New-OERAccessPackageRequestorScope -Scope AllMemberUsers
        $Rs = New-OERAccessPackageRequestorSettings -AllowSelfRequest
        New-OERAccessPackageAssignmentPolicy -AccessPackage 'AP' -DisplayName 'Pol' -RequestorScope $Scope `
            -RequestorSettings $Rs -RequireApproval -DurationInHours 8 -DisableAssignmentNotifications `
            -Confirm:$false | Out-Null
        InModuleScope $script:moduleName -Parameters @{ B = $script:NewBody } {
            param($B)
            $B.requestorSettings.enableTargetsToSelfAddAccess | Should -BeTrue
            $B.requestApprovalSettings.isApprovalRequiredForAdd | Should -BeTrue
            $B.expiration.duration | Should -Be 'PT8H'
            $B.notificationSettings.isAssignmentNotificationDisabled | Should -BeTrue
            $B.description | Should -Be 'Pol'
        }
    }

    It 'three-way expiration conflict (DurationInDays+DurationInHours) -> InvalidPolicyInput non-terminating' {
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest { @{ id = 'p' } }
        $Scope = New-OERAccessPackageRequestorScope -Scope AllMemberUsers
        New-OERAccessPackageAssignmentPolicy -AccessPackage 'AP' -DisplayName 'D' -RequestorScope $Scope `
            -DurationInDays 1 -DurationInHours 1 -ErrorVariable E -ErrorAction SilentlyContinue | Out-Null
        $E[0].FullyQualifiedErrorId | Should -BeLike 'InvalidPolicyInput*'
        Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 0 -ParameterFilter { $Method -eq 'POST' }
    }

    It 'three-way expiration conflict (DurationInHours+ExpirationDateTime) -> InvalidPolicyInput non-terminating' {
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest { @{ id = 'p' } }
        $Scope = New-OERAccessPackageRequestorScope -Scope AllMemberUsers
        New-OERAccessPackageAssignmentPolicy -AccessPackage 'AP' -DisplayName 'D' -RequestorScope $Scope `
            -DurationInHours 1 -ExpirationDateTime ([datetime]'2027-01-01') -ErrorVariable E -ErrorAction SilentlyContinue | Out-Null
        $E[0].FullyQualifiedErrorId | Should -BeLike 'InvalidPolicyInput*'
        Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 0 -ParameterFilter { $Method -eq 'POST' }
    }

    It 'rejects a -RequestorSettings of the wrong type' {
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest { @{ id = 'p' } }
        $Scope = New-OERAccessPackageRequestorScope -Scope AllMemberUsers
        New-OERAccessPackageAssignmentPolicy -AccessPackage 'AP' -DisplayName 'D' -RequestorScope $Scope `
            -RequestorSettings ([pscustomobject]@{ x = 1 }) -ErrorVariable E -ErrorAction SilentlyContinue | Out-Null
        $E[0].FullyQualifiedErrorId | Should -BeLike 'InvalidPolicyInput*'
        Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 0 -ParameterFilter { $Method -eq 'POST' }
    }

    It 'accepts an AccessPackage object piped in and resolves its Id' {
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {
            @{ id = 'pol-pipe'; displayName = 'PipePol'; allowedTargetScope = 'allMemberUsers'; expiration = @{ type = 'noExpiration' } }
        } -ParameterFilter { $Method -eq 'POST' }
        $Scope = New-OERAccessPackageRequestorScope -Scope AllMemberUsers
        $ApObj = [pscustomobject]@{ Id = 'AP-1'; DisplayName = 'AP Sales' }
        $ApObj.PSObject.TypeNames.Insert(0, 'Omnicit.EntraRBAC.AccessPackage')
        $ApObj | New-OERAccessPackageAssignmentPolicy -DisplayName 'PipePol' -RequestorScope $Scope | Out-Null
        Should -Invoke -ModuleName $script:moduleName Resolve-OERAccessPackageId -Times 1 -ParameterFilter {
            $DisplayName -eq 'AP-1'
        }
    }

    Context 'duration vocabulary aliases (audit PR6)' {
        It 'binds -DurationDays to the day-count expiration' {
            Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {
                @{ id = 'pol-1'; displayName = 'P'; allowedTargetScope = 'allMemberUsers'; expiration = @{ type = 'afterDuration'; duration = 'P30D' } }
            } -ParameterFilter { $Method -eq 'POST' }
            $Scope = New-OERAccessPackageRequestorScope -Scope AllMemberUsers
            New-OERAccessPackageAssignmentPolicy -AccessPackage 'ap-1' -DisplayName 'P' -RequestorScope $Scope -DurationDays 30 -Confirm:$false | Out-Null
            Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 1 -ParameterFilter {
                $Method -eq 'POST' -and $Body.expiration.duration -eq 'P30D'
            }
        }

        It 'binds -DurationHours to the hour-count expiration' {
            Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {
                @{ id = 'pol-1'; displayName = 'P'; allowedTargetScope = 'allMemberUsers'; expiration = @{ type = 'afterDuration'; duration = 'PT8H' } }
            } -ParameterFilter { $Method -eq 'POST' }
            $Scope = New-OERAccessPackageRequestorScope -Scope AllMemberUsers
            New-OERAccessPackageAssignmentPolicy -AccessPackage 'ap-1' -DisplayName 'P' -RequestorScope $Scope -DurationHours 8 -Confirm:$false | Out-Null
            Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 1 -ParameterFilter {
                $Method -eq 'POST' -and $Body.expiration.duration -eq 'PT8H'
            }
        }

        It 'still rejects two expiration forms when one is supplied by its alias' {
            Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {}
            $Scope = New-OERAccessPackageRequestorScope -Scope AllMemberUsers
            New-OERAccessPackageAssignmentPolicy -AccessPackage 'ap-1' -DisplayName 'P' -RequestorScope $Scope `
                -DurationDays 30 -DurationInHours 8 -Confirm:$false -ErrorAction SilentlyContinue -ErrorVariable Err | Out-Null
            $Err | Where-Object { $_.FullyQualifiedErrorId -like 'InvalidPolicyInput*' } | Should -Not -BeNullOrEmpty
            Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 0 -ParameterFilter { $Method -eq 'POST' }
        }
    }

    It 'errors InvalidPolicyInput with the builder failure chained as the inner exception when ConvertTo-OERPolicyBody throws' {
        # This catch (source :186) does not simply re-surface the record: it wraps whatever
        # ConvertTo-OERPolicyBody threw into a new InvalidPolicyInput/InvalidArgument error with the
        # original as -InnerException, so a raw Graph-style ErrorRecord would be the wrong fixture
        # here -- ConvertTo-OERPolicyBody is a private pure helper (per CLAUDE.md) that throws bare
        # on caller error, never a pre-built ErrorRecord. This is a DOMAIN ErrorId (not a
        # pass-through of the Graph code), so the cmdlet-qualified match target is
        # InvalidPolicyInput,New-OERAccessPackageAssignmentPolicy -- matching the bare 'InvalidPolicyInput'
        # substring would be looser than needed but is not itself vacuous here (the raw thrown text
        # 'body assembly failed...' never contains it); the exact match plus the Remove-OERErrorRecord
        # guard below make both of the cmdlet's own obligations on this path explicit.
        Mock -ModuleName $script:moduleName ConvertTo-OERPolicyBody { throw 'body assembly failed: incompatible settings' }
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {}
        Mock -ModuleName $script:moduleName Remove-OERErrorRecord { }
        $Scope = New-OERAccessPackageRequestorScope -Scope AllMemberUsers
        $Err = $null
        New-OERAccessPackageAssignmentPolicy -AccessPackage 'AP-Sales' -DisplayName 'Default' -RequestorScope $Scope `
            -Confirm:$false -ErrorAction SilentlyContinue -ErrorVariable Err | Out-Null
        $Owned = @($Err | Where-Object { $_.FullyQualifiedErrorId -eq 'InvalidPolicyInput,New-OERAccessPackageAssignmentPolicy' })
        $Owned.Count | Should -Be 1
        $Owned[0].Exception.InnerException.Message | Should -Match 'body assembly failed'
        Should -Invoke -ModuleName $script:moduleName Remove-OERErrorRecord -Times 1 -Exactly
        Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 0 -ParameterFilter { $Method -eq 'POST' }
    }

    It 'surfaces a Graph POST failure as a non-terminating error and emits nothing' {
        # Guards two things the cmdlet must do on a Graph failure: call Remove-OERErrorRecord (the
        # mandatory bearer-token-hygiene line -- asserted via Should -Invoke, since a deleted line
        # would otherwise pass unnoticed) and write its OWN non-terminating record. Match the
        # cmdlet-QUALIFIED ErrorId: PowerShell auto-records the mock's throw into -ErrorVariable a
        # dozen times before the catch runs, so matching the bare Graph code would pass even with
        # WriteError deleted.
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {
            throw [System.Management.Automation.ErrorRecord]::new(
                [System.Exception]::new('Request_BadRequest: The assignment policy is not valid.'),
                'Request_BadRequest',
                [System.Management.Automation.ErrorCategory]::InvalidOperation,
                $null)
        } -ParameterFilter { $Method -eq 'POST' }
        Mock -ModuleName $script:moduleName Remove-OERErrorRecord { }
        $Scope = New-OERAccessPackageRequestorScope -Scope AllMemberUsers
        $Err = $null
        $Result = New-OERAccessPackageAssignmentPolicy -AccessPackage 'AP-Sales' -DisplayName 'Default' -RequestorScope $Scope `
            -Confirm:$false -ErrorAction SilentlyContinue -ErrorVariable Err
        $Result | Should -BeNullOrEmpty
        @($Err | Where-Object { $_.FullyQualifiedErrorId -eq 'Request_BadRequest,New-OERAccessPackageAssignmentPolicy' }).Count |
            Should -Be 1
        Should -Invoke -ModuleName $script:moduleName Remove-OERErrorRecord -Times 1 -Exactly
    }

    Context '-Catalog (BL-184)' {
        BeforeEach {
            Mock -ModuleName $script:moduleName Invoke-OERGraphRequest { @{ value = @() } }
            $script:Scope = [pscustomobject]@{ Type = 'AllMemberUsers' }
            $script:Scope.PSObject.TypeNames.Insert(0, 'Omnicit.EntraRBAC.RequestorScope')
        }

        It 'passes the bound -Catalog and the package name to the resolver' {
            New-OERAccessPackageAssignmentPolicy -AccessPackage 'AP-Sales' -DisplayName 'Default' -RequestorScope $script:Scope -Catalog 'CAT-IT-Core' -WhatIf -ErrorAction SilentlyContinue | Out-Null
            Should -Invoke -ModuleName $script:moduleName Resolve-OERAccessPackageId -Times 1 -Exactly -ParameterFilter {
                $PesterBoundParameters.ContainsKey('Catalog') -and $Catalog -eq 'CAT-IT-Core' -and $DisplayName -eq 'AP-Sales'
            }
        }

        It 'calls the resolver without a Catalog key when -Catalog is not bound' {
            New-OERAccessPackageAssignmentPolicy -AccessPackage 'AP-Sales' -DisplayName 'Default' -RequestorScope $script:Scope -WhatIf -ErrorAction SilentlyContinue | Out-Null
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
            New-OERAccessPackageAssignmentPolicy -AccessPackage 'AP-Sales' -DisplayName 'Default' -RequestorScope $script:Scope -Catalog 'CAT-IT-Core' -Confirm:$false -ErrorAction SilentlyContinue -ErrorVariable Err | Out-Null
            $Own = @($Err | Where-Object { $_.FullyQualifiedErrorId -eq 'AccessPackageNotFound,New-OERAccessPackageAssignmentPolicy' })
            $Own.Count | Should -Be 1
            $Own[0].Exception.Message | Should -BeExactly "Access package 'AP-Sales' not found in catalog 'CAT-IT-Core'."
            $Err = $null
            New-OERAccessPackageAssignmentPolicy -AccessPackage 'AP-Sales' -DisplayName 'Default' -RequestorScope $script:Scope -Confirm:$false -ErrorAction SilentlyContinue -ErrorVariable Err | Out-Null
            $Own = @($Err | Where-Object { $_.FullyQualifiedErrorId -eq 'AccessPackageNotFound,New-OERAccessPackageAssignmentPolicy' })
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
            New-OERAccessPackageAssignmentPolicy -AccessPackage 'AP-Sales' -DisplayName 'Default' -RequestorScope $script:Scope -Catalog 'CAT-IT-Core' -Confirm:$false -ErrorAction SilentlyContinue -ErrorVariable Err | Out-Null
            $Own = @($Err | Where-Object { $_.FullyQualifiedErrorId -match '^AccessPackageNotInCatalog,New-OERAccessPackageAssignmentPolicy$' })
            $Own.Count | Should -Be 1
            $Own[0].InvocationInfo.MyCommand.Name | Should -BeExactly 'New-OERAccessPackageAssignmentPolicy'
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
            New-OERAccessPackageAssignmentPolicy -AccessPackage 'AP-Sales' -DisplayName 'Default' -RequestorScope $script:Scope -Catalog 'CAT-IT-Core' -Confirm:$false -ErrorAction SilentlyContinue -ErrorVariable Err | Out-Null
            $Own = @($Err | Where-Object { $_.FullyQualifiedErrorId -match '^AmbiguousCatalogName,New-OERAccessPackageAssignmentPolicy$' })
            $Own.Count | Should -Be 1
            $Own[0].InvocationInfo.MyCommand.Name | Should -BeExactly 'New-OERAccessPackageAssignmentPolicy'
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
            New-OERAccessPackageAssignmentPolicy -AccessPackage 'AP-Sales' -DisplayName 'Default' -RequestorScope $script:Scope -Catalog 'CAT-IT-Core' -Confirm:$false -ErrorAction SilentlyContinue -ErrorVariable Err | Out-Null
            $Own = @($Err | Where-Object { $_.FullyQualifiedErrorId -match '^CatalogNotFound,New-OERAccessPackageAssignmentPolicy$' })
            $Own.Count | Should -Be 1
            $Own[0].InvocationInfo.MyCommand.Name | Should -BeExactly 'New-OERAccessPackageAssignmentPolicy'
            @($Err | Where-Object { $_.FullyQualifiedErrorId -match '^AmbiguousAccessPackageName' }).Count | Should -Be 0
            Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 0
        }

        It 'declares -Catalog last, validated, aliasless and not bound from the pipeline' {
            $Cmd = Get-Command New-OERAccessPackageAssignmentPolicy
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

Describe 'New-OERAccessPackageAssignmentPolicy -- a failed resolver read is not a not-found (issue #71, fix round 1)' {
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
        $Scope = New-OERAccessPackageRequestorScope -Scope AllMemberUsers
        New-OERAccessPackageAssignmentPolicy -AccessPackage 'AP-Sales' -DisplayName 'Default' `
            -RequestorScope $Scope -DurationInDays 30 -Confirm:$false `
            -ErrorAction SilentlyContinue -ErrorVariable Err | Out-Null

        # NARROWED ON PURPOSE, and the narrowing is the whole guard. -ErrorVariable also collects
        # the engine's own capture of the INNER throw, whose FullyQualifiedErrorId is the bare
        # 'Authorization_RequestDenied' whether or not this cmdlet re-published it -- measured, not
        # assumed. An unnarrowed $Err[0] or -join match therefore passes with the fix reverted.
        # Only the record this cmdlet published carries its own name in InvocationInfo.
        $Published = @($Err) | Where-Object {
            $_.InvocationInfo -and $_.InvocationInfo.MyCommand -and
            $_.InvocationInfo.MyCommand.Name -eq 'New-OERAccessPackageAssignmentPolicy'
        }
        @($Published).Count | Should -Be 1
        $Published[0].FullyQualifiedErrorId | Should -Match '^Authorization_RequestDenied'
        $Published[0].FullyQualifiedErrorId | Should -Not -Match 'AccessPackageNotFound' -Because (
            'a permission failure booked as a missing object is the failed-read-as-an-empty-fact defect of issue #76')
        $Published[0].CategoryInfo.Category | Should -Be 'PermissionDenied'
        Should -Invoke -ModuleName 'Omnicit.EntraRBAC' Invoke-OERGraphRequest -Times 0 -Exactly
    }
}

Describe 'New-OERAccessPackageAssignmentPolicy -- a piped AccessPackageId binds before the object''s own Id (BL-192)' {
    BeforeEach {
        InModuleScope $script:moduleName { $script:_OERAuthState = $null }
        Mock -ModuleName $script:moduleName Initialize-OERAuth {}
        Mock -ModuleName $script:moduleName Resolve-OERAccessPackageId { 'ap-1' }
    }
    BeforeEach {
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest { @{ id = 'pol-new'; displayName = 'Default' } }
        $script:Scope = New-OERAccessPackageRequestorScope -Scope AllMemberUsers
    }

    It 'an assignment policy binds its access package id, never its own Id' {
        $Policy = [PSCustomObject]@{ Id = 'policy-id-1'; DisplayName = 'Policy One'; AccessPackageId = 'package-id-1' }
        $Policy.PSObject.TypeNames.Insert(0, 'Omnicit.EntraRBAC.AssignmentPolicy')
        $Policy | New-OERAccessPackageAssignmentPolicy -DisplayName 'Default' -RequestorScope $script:Scope -Confirm:$false | Out-Null
        Should -Invoke -ModuleName $script:moduleName Resolve-OERAccessPackageId -Times 1 -Exactly -ParameterFilter { $DisplayName -eq 'package-id-1' }
        Should -Invoke -ModuleName $script:moduleName Resolve-OERAccessPackageId -Times 0 -ParameterFilter { $DisplayName -eq 'policy-id-1' }
    }

    It 'a resource role binds its AccessPackageId' {
        $Role = [PSCustomObject]@{
            ResourceRoleScopeId = 'scope-id-1'; RoleName = 'Member'; ResourceDisplayName = 'Sales'
            ScopeDisplayName = 'Root'; OriginId = 'grp-1'; OriginSystem = 'AadGroup'; AccessPackageId = 'package-id-2'
        }
        $Role.PSObject.TypeNames.Insert(0, 'Omnicit.EntraRBAC.AccessPackageResourceRole')
        $Role | New-OERAccessPackageAssignmentPolicy -DisplayName 'Default' -RequestorScope $script:Scope -Confirm:$false | Out-Null
        Should -Invoke -ModuleName $script:moduleName Resolve-OERAccessPackageId -Times 1 -Exactly -ParameterFilter { $DisplayName -eq 'package-id-2' }
    }

    It 'an access package from Get-OERAccessPackage carries no AccessPackageId and binds its Id as before' {
        $Package = [PSCustomObject]@{ Id = 'package-id-3'; DisplayName = 'AP-Sales'; Description = 'd'; CatalogId = 'cat-1'; IsHidden = $false }
        $Package.PSObject.TypeNames.Insert(0, 'Omnicit.EntraRBAC.AccessPackage')
        $Package | New-OERAccessPackageAssignmentPolicy -DisplayName 'Default' -RequestorScope $script:Scope -Confirm:$false | Out-Null
        Should -Invoke -ModuleName $script:moduleName Resolve-OERAccessPackageId -Times 1 -Exactly -ParameterFilter { $DisplayName -eq 'package-id-3' }
    }

    It 'a piped object whose AccessPackageId is null fails binding and nothing is sent' {
        $Review = [PSCustomObject]@{ Id = 'review-id-1'; DisplayName = 'Review'; AccessPackageId = $null }
        { $Review | New-OERAccessPackageAssignmentPolicy -DisplayName 'Default' -RequestorScope $script:Scope -Confirm:$false } |
            Should -Throw -ErrorId 'ParameterArgumentValidationErrorEmptyStringNotAllowed,New-OERAccessPackageAssignmentPolicy'
        Should -Invoke -ModuleName $script:moduleName Resolve-OERAccessPackageId -Times 0
        Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 0

        # Control: the same pipeline with a value gets past binding and sends the request.
        $Review.AccessPackageId = 'package-id-9'
        $Review | New-OERAccessPackageAssignmentPolicy -DisplayName 'Default' -RequestorScope $script:Scope -Confirm:$false | Out-Null
        Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 1 -Exactly
    }
}
