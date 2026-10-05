BeforeAll {
    Import-Module Omnicit.EntraRBAC -Force
    . "$PSScriptRoot/../TestHelpers/OERTransportTripwire.ps1"
    Install-OERTransportTripwire
}

AfterAll {
    try { Assert-OERTransportTripwire } finally { Uninstall-OERTransportTripwire }
}

Describe 'Send-OERAccessReviewReminder' {
    BeforeEach {
        InModuleScope Omnicit.EntraRBAC { $script:_OERAuthState = $null }
        Mock -ModuleName Omnicit.EntraRBAC Initialize-OERAuth { }
        Mock -ModuleName Omnicit.EntraRBAC Resolve-OERAccessReviewDefinitionId { 'def-id' }
        Mock -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest { }
    }

    It 'POSTs the sendReminder action with exact URI' {
        Send-OERAccessReviewReminder -Definition 'Q3' -Instance 'i1' -Confirm:$false
        Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest -ParameterFilter {
            $Method -eq 'POST' -and
            $Uri -eq 'v1.0/identityGovernance/accessReviews/definitions/def-id/instances/i1/sendReminder'
        }
    }

    It 'honors -WhatIf and makes no Graph call' {
        Send-OERAccessReviewReminder -Definition 'Q3' -Instance 'i1' -WhatIf
        Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest -Times 0
    }

    It 'writes a non-terminating error when definition is not found' {
        Mock -ModuleName Omnicit.EntraRBAC Resolve-OERAccessReviewDefinitionId { $null }
        Send-OERAccessReviewReminder -Definition 'ghost' -Instance 'i1' -ErrorVariable e -ErrorAction SilentlyContinue
        $e | Should -Not -BeNullOrEmpty
        Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest -Times 0
    }

    It 'accepts pipeline input via AccessReviewDefinitionId and AccessReviewInstanceId aliases' {
        [pscustomobject]@{
            AccessReviewDefinitionId = 'Q3'
            AccessReviewInstanceId   = 'i1'
        } | Send-OERAccessReviewReminder -Confirm:$false
        Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest -ParameterFilter {
            $Method -eq 'POST' -and
            $Uri -eq 'v1.0/identityGovernance/accessReviews/definitions/def-id/instances/i1/sendReminder'
        }
    }

    It 'passes TenantId to Initialize-OERAuth' {
        Send-OERAccessReviewReminder -Definition 'Q3' -Instance 'i1' -TenantId 'contoso.onmicrosoft.com' -Confirm:$false
        Should -Invoke -ModuleName Omnicit.EntraRBAC Initialize-OERAuth -ParameterFilter {
            $TenantId -eq 'contoso.onmicrosoft.com'
        }
    }

    It 'surfaces a Graph failure as a non-terminating error and emits nothing' {
        # Guards two things the cmdlet must do on a Graph failure: call Remove-OERErrorRecord (the
        # mandatory bearer-token-hygiene line -- asserted via Should -Invoke, since a deleted line
        # would otherwise pass unnoticed) and write its OWN non-terminating record. Match the
        # cmdlet-QUALIFIED ErrorId: PowerShell auto-records the mock's throw into -ErrorVariable a
        # dozen times before the catch runs, so matching the bare Graph code would pass even with
        # WriteError deleted.
        Mock -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest {
            throw [System.Management.Automation.ErrorRecord]::new(
                [System.Exception]::new('Authorization_RequestDenied: Insufficient privileges.'),
                'Authorization_RequestDenied',
                [System.Management.Automation.ErrorCategory]::PermissionDenied,
                $null)
        }
        Mock -ModuleName Omnicit.EntraRBAC Remove-OERErrorRecord { }
        $Err = $null
        $Result = Send-OERAccessReviewReminder -Definition 'Q3' -Instance 'i1' -Confirm:$false `
            -ErrorAction SilentlyContinue -ErrorVariable Err
        $Result | Should -BeNullOrEmpty
        Should -Invoke -ModuleName Omnicit.EntraRBAC Remove-OERErrorRecord -Times 1
        @($Err | Where-Object { $_.FullyQualifiedErrorId -eq 'Authorization_RequestDenied,Send-OERAccessReviewReminder' }).Count |
            Should -Be 1
    }

    It 'surfaces a definition-resolution failure and scrubs the record' {
        # Drives the resolver catch that no test in this tree had ever entered --
        # source/Public/Send-OERAccessReviewReminder.ps1:52. Until now
        # Resolve-OERAccessReviewDefinitionId was only ever mocked to a value or to $null,
        # never to throw. That catch SWALLOWS -- it scrubs, builds a fresh
        # exception and returns -- so the scrub proof has to be Mock + Should -Invoke; a
        # $global:Error reference-identity check would be inert here.
        # Should -Invoke Invoke-OERGraphRequest -Times 0 is what separates this from the
        # Graph-failure It above: the resolver fails before the transport is ever reached.
        Mock -ModuleName Omnicit.EntraRBAC Resolve-OERAccessReviewDefinitionId {
            throw [System.Management.Automation.ErrorRecord]::new(
                [System.Exception]::new('Authorization_RequestDenied: Insufficient privileges.'),
                'Authorization_RequestDenied',
                [System.Management.Automation.ErrorCategory]::PermissionDenied,
                $null)
        }
        Mock -ModuleName Omnicit.EntraRBAC Remove-OERErrorRecord { }
        $Err = $null
        $Result = Send-OERAccessReviewReminder -Definition 'Q3' -Instance 'i1' -Confirm:$false `
            -ErrorAction SilentlyContinue -ErrorVariable Err
        $Result | Should -BeNullOrEmpty
        Should -Invoke -ModuleName Omnicit.EntraRBAC Remove-OERErrorRecord -Times 1
        Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest -Times 0
        @($Err | Where-Object { $_.FullyQualifiedErrorId -eq 'AccessReviewDefinitionResolveFailed,Send-OERAccessReviewReminder' }).Count |
            Should -Be 1
    }

    Context 'a definition lookup that cannot name one definition' {
        # Resolve-OERAccessReviewDefinitionId now refuses a display name that matches more than one
        # definition (Graph does not enforce unique review names), and every other lookup failure still
        # arrives here as a throw. Neither is "not found". The refusal is published as itself, with the
        # candidate ids the operator needs to disambiguate; any other failure keeps
        # AccessReviewDefinitionResolveFailed, as a ReadError that carries the cause. Both stop before Graph is reached.
        It 'publishes an ambiguous definition name as AmbiguousName with the candidate ids, not as AccessReviewDefinitionResolveFailed' {
            Mock -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest { }
            Mock -ModuleName Omnicit.EntraRBAC Resolve-OERAccessReviewDefinitionId {
                throw [System.Management.Automation.ErrorRecord]::new(
                    [System.Exception]::new(
                        "Access review definition display name 'Dup' matches 2 definitions " +
                        '(11111111-1111-1111-1111-111111111111, 22222222-2222-2222-2222-222222222222).'),
                    'AmbiguousName', [System.Management.Automation.ErrorCategory]::InvalidArgument, 'Dup')
            }
            $Err = $null
            $Result = Send-OERAccessReviewReminder -Definition 'Q3' -Instance 'i1' -Confirm:$false `
                -ErrorAction SilentlyContinue -ErrorVariable Err
            # NARROWED ON PURPOSE: -ErrorVariable also holds the engine's own capture of the INNER throw,
            # whose id is the bare 'AmbiguousName' whether or not this cmdlet re-published it, so an
            # unnarrowed match passes with the fix reverted (measured; see the issue #71 Describe in
            # Add-OERAccessPackageResourceRole.Tests.ps1). Exactly one record this cmdlet itself
            # published is also what rules out a fall-through that adds a second one.
            $Published = @(@($Err) | Where-Object {
                    $_.InvocationInfo -and $_.InvocationInfo.MyCommand -and
                    $_.InvocationInfo.MyCommand.Name -eq 'Send-OERAccessReviewReminder'
                })
            # The positive half: the lookup was reached, once, so the no-Graph assertion below is not a
            # cmdlet that never got that far.
            Should -Invoke -ModuleName Omnicit.EntraRBAC Resolve-OERAccessReviewDefinitionId -Times 1 -Exactly
            $Published.Count | Should -Be 1
            $Published[0].FullyQualifiedErrorId | Should -Be 'AmbiguousName,Send-OERAccessReviewReminder'
            $Published[0].CategoryInfo.Category | Should -Be 'InvalidArgument'
            $Published[0].Exception.Message | Should -Match '11111111-1111-1111-1111-111111111111'
            $Published[0].Exception.Message | Should -Match '22222222-2222-2222-2222-222222222222'
            $Result | Should -BeNullOrEmpty
            Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest -Times 0 -Exactly
        }

        It 'keeps AccessReviewDefinitionResolveFailed for any other lookup failure, now carrying the cause in the message and chaining it' {
            Mock -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest { }
            Mock -ModuleName Omnicit.EntraRBAC Resolve-OERAccessReviewDefinitionId {
                throw [System.Management.Automation.ErrorRecord]::new(
                    [System.Exception]::new('Authorization_RequestDenied: Insufficient privileges to complete the operation.'),
                    'Authorization_RequestDenied', [System.Management.Automation.ErrorCategory]::PermissionDenied, 'Q3')
            }
            $Err = $null
            $Result = Send-OERAccessReviewReminder -Definition 'Q3' -Instance 'i1' -Confirm:$false `
                -ErrorAction SilentlyContinue -ErrorVariable Err
            $Published = @(@($Err) | Where-Object {
                    $_.InvocationInfo -and $_.InvocationInfo.MyCommand -and
                    $_.InvocationInfo.MyCommand.Name -eq 'Send-OERAccessReviewReminder'
                })
            Should -Invoke -ModuleName Omnicit.EntraRBAC Resolve-OERAccessReviewDefinitionId -Times 1 -Exactly
            $Published.Count | Should -Be 1
            $Published[0].FullyQualifiedErrorId | Should -Be 'AccessReviewDefinitionResolveFailed,Send-OERAccessReviewReminder'
            # A failed read is never a not-found: the category is ReadError, as RoleDefinitionReadFailed uses it.
            $Published[0].CategoryInfo.Category | Should -Be 'ReadError'
            # The cause used to be dropped: the operator read "Failed to resolve" and nothing else.
            $Published[0].Exception.Message | Should -Be (
                "Failed to resolve access review definition 'Q3': " +
                'Authorization_RequestDenied: Insufficient privileges to complete the operation.')
            $Published[0].Exception.InnerException | Should -Not -BeNullOrEmpty
            $Published[0].Exception.InnerException.Message | Should -Be 'Authorization_RequestDenied: Insufficient privileges to complete the operation.'
            $Result | Should -BeNullOrEmpty
            Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest -Times 0 -Exactly
        }

        It 'scrubs the lookup record before publishing it, on the failure path and on the ambiguity path (bearer hygiene)' {
            # Both paths publish the record, so an $Error-count proof would stay green with the
            # Remove-OERErrorRecord call deleted. The proof is the mocked call: exactly one per record,
            # for THIS record, beside a positive assertion that the catch was reached and a record
            # published. The ambiguity path is driven as well as the failure path, since a scrub that
            # sat below the ambiguity branch's return would leave that record unscrubbed.
            Mock -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest { }
            Mock -ModuleName Omnicit.EntraRBAC Remove-OERErrorRecord { }

            Mock -ModuleName Omnicit.EntraRBAC Resolve-OERAccessReviewDefinitionId {
                throw [System.Management.Automation.ErrorRecord]::new(
                    [System.Exception]::new('Authorization_RequestDenied: definition lookup scrub marker.'),
                    'Authorization_RequestDenied', [System.Management.Automation.ErrorCategory]::PermissionDenied, 'Q3')
            }
            $Err = $null
            Send-OERAccessReviewReminder -Definition 'Q3' -Instance 'i1' -Confirm:$false `
                -ErrorAction SilentlyContinue -ErrorVariable Err
            $Published = @(@($Err) | Where-Object {
                    $_.InvocationInfo -and $_.InvocationInfo.MyCommand -and
                    $_.InvocationInfo.MyCommand.Name -eq 'Send-OERAccessReviewReminder'
                })
            $Published.Count | Should -Be 1
            $Published[0].FullyQualifiedErrorId | Should -Be 'AccessReviewDefinitionResolveFailed,Send-OERAccessReviewReminder'
            Should -Invoke -ModuleName Omnicit.EntraRBAC Remove-OERErrorRecord -Times 1 -Exactly -ParameterFilter {
                $Record.Exception.Message -eq 'Authorization_RequestDenied: definition lookup scrub marker.'
            }

            Mock -ModuleName Omnicit.EntraRBAC Resolve-OERAccessReviewDefinitionId {
                throw [System.Management.Automation.ErrorRecord]::new(
                    [System.Exception]::new('Access review definition display name ''Dup'' ambiguity scrub marker.'),
                    'AmbiguousName', [System.Management.Automation.ErrorCategory]::InvalidArgument, 'Dup')
            }
            $Err = $null
            Send-OERAccessReviewReminder -Definition 'Q3' -Instance 'i1' -Confirm:$false `
                -ErrorAction SilentlyContinue -ErrorVariable Err
            $Published = @(@($Err) | Where-Object {
                    $_.InvocationInfo -and $_.InvocationInfo.MyCommand -and
                    $_.InvocationInfo.MyCommand.Name -eq 'Send-OERAccessReviewReminder'
                })
            $Published.Count | Should -Be 1
            $Published[0].FullyQualifiedErrorId | Should -Be 'AmbiguousName,Send-OERAccessReviewReminder'
            Should -Invoke -ModuleName Omnicit.EntraRBAC Remove-OERErrorRecord -Times 1 -Exactly -ParameterFilter {
                $Record.Exception.Message -eq 'Access review definition display name ''Dup'' ambiguity scrub marker.'
            }
        }
    }
}
