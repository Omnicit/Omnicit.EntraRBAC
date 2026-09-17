BeforeAll {
    $script:moduleName = 'Omnicit.EntraRBAC'
    Get-Module $script:moduleName | Remove-Module -Force -ErrorAction SilentlyContinue
    Import-Module $script:moduleName -Force -ErrorAction Stop
}

Describe 'Get-OERAccessPackageAssignment' {
    BeforeEach {
        InModuleScope $script:moduleName { $script:_OERAuthState = $null }
        Mock -ModuleName $script:moduleName Initialize-OERAuth {}
        Mock -ModuleName $script:moduleName Resolve-OERAccessPackageId { 'ap-1' }
    }

    It 'lists assignments filtered by access package and expands target/accessPackage' {
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {
            @{
                value = @(
                    @{
                        id              = '00000000-0000-0000-0000-000000000051'
                        state           = 'delivered'
                        expiredDateTime = '2026-12-31T23:59:59Z'
                        target          = @{ id = 'subject-record-id'; objectId = 'aaaaaaaa-0000-0000-0000-000000000001'; displayName = 'Ada Lovelace' }
                        accessPackage   = @{ id = 'ap-1'; displayName = 'AP-OER-Demo' }
                    }
                )
            }
        }
        $R = Get-OERAccessPackageAssignment -AccessPackage 'AP-OER-Demo'
        $R[0].PSObject.TypeNames[0] | Should -Be 'Omnicit.EntraRBAC.Assignment'
        $R[0].TargetDisplayName | Should -Be 'Ada Lovelace'
        $R[0].AccessPackageDisplayName | Should -Be 'AP-OER-Demo'
        $R[0].TargetId | Should -Be 'aaaaaaaa-0000-0000-0000-000000000001'
        Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 1 -ParameterFilter {
            $Uri -like "*accessPackage/id eq 'ap-1'*"
        }
    }

    It 'always requests $expand=target,accessPackage even with no filter' {
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest { @{ value = @() } }
        Get-OERAccessPackageAssignment | Out-Null
        Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 1 -ParameterFilter {
            $Uri -like '*$expand=target,accessPackage*'
        }
    }

    It 'combines $expand and $filter with & when a filter is present' {
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest { @{ value = @() } }
        Get-OERAccessPackageAssignment -AccessPackage 'AP-Sales' -State 'Delivered' | Out-Null
        Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 1 -ParameterFilter {
            $Uri -like '*$expand=target,accessPackage*' -and
            $Uri -like "*`$filter=*" -and
            $Uri -like "*accessPackage/id eq 'ap-1'*" -and
            $Uri -like "*state eq 'Delivered'*" -and
            $Uri -match '\$expand=target,accessPackage&\$filter='
        }
    }

    It 'adds a state filter with -State using the real v1.0 "state" field, not "assignmentState"' {
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest { @{ value = @() } }
        Get-OERAccessPackageAssignment -AccessPackage 'AP-Sales' -State 'Delivered' | Out-Null
        Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 1 -ParameterFilter {
            $Uri -like "*state eq 'Delivered'*" -and $Uri -notlike '*assignmentState eq*'
        }
    }

    Context '-State casing is bound and transmitted verbatim (issue #72)' {
        # ValidateSet is case-insensitive by default (IgnoreCase = True), so any casing of a valid
        # value binds, and the bound value is sent to Graph exactly as typed -- never normalised.
        # The suite before this task only ever pinned the 'Delivered' spelling, so the module has
        # never proven which casing it actually emits on the wire. These three tests pin both
        # spellings AND the fact that both bind, which is exactly what setting
        # IgnoreCase = $false on the [ValidateSet] attribute would break.
        # The open question they were written beside is now CLOSED: a live run on 2026-09-11
        # measured both spellings returning the same single delivered assignment, so entitlement
        # management compares the value case-insensitively and no normalisation is needed. These
        # tests therefore stay as the regression guard for a verified behaviour -- the day someone
        # adds a casing normaliser here, they go red and the verification is what says they should.
        It 'emits the state filter using the caller''s exact lowercase spelling' {
            # -clike (case-SENSITIVE) is deliberate: plain -like is case-insensitive in PowerShell, so
            # it would pass even if the emitted casing did not match at all -- exactly the
            # guard-shaped-but-inert failure mode this test exists to avoid.
            Mock -ModuleName $script:moduleName Invoke-OERGraphRequest { @{ value = @() } }
            Get-OERAccessPackageAssignment -State 'delivered' | Out-Null
            Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 1 -Exactly -ParameterFilter {
                $Uri -clike "*state eq 'delivered'*"
            }
        }

        It 'emits the state filter using the caller''s exact capitalised spelling' {
            # -clike, not -like -- see the lowercase test above for why plain -like cannot prove this.
            Mock -ModuleName $script:moduleName Invoke-OERGraphRequest { @{ value = @() } }
            Get-OERAccessPackageAssignment -State 'Delivered' | Out-Null
            Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 1 -Exactly -ParameterFilter {
                $Uri -clike "*state eq 'Delivered'*"
            }
        }

        It 'binds both a lowercase and a capitalised -State value without a validation error' {
            Mock -ModuleName $script:moduleName Invoke-OERGraphRequest { @{ value = @() } }
            { Get-OERAccessPackageAssignment -State 'delivered' | Out-Null } | Should -Not -Throw
            { Get-OERAccessPackageAssignment -State 'Delivered' | Out-Null } | Should -Not -Throw
        }
    }

    It 'errors AccessPackageNotFound when the access package cannot be resolved' {
        Mock -ModuleName $script:moduleName Resolve-OERAccessPackageId { $null }
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {}
        Get-OERAccessPackageAssignment -AccessPackage 'nope' -ErrorVariable Err -ErrorAction SilentlyContinue | Out-Null
        $Err.FullyQualifiedErrorId | Should -Match 'AccessPackageNotFound'
        Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 0
    }

    It 'lists all assignments when no filter is supplied' {
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {
            @{ value = @(@{ id = 'asg-2'; state = 'delivered'; target = @{}; accessPackage = @{} }) }
        }
        $R = Get-OERAccessPackageAssignment
        $R[0].PSObject.TypeNames[0] | Should -Be 'Omnicit.EntraRBAC.Assignment'
        Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 1 -ParameterFilter {
            $Uri -notlike '*$filter*'
        }
    }

    It 'filters by target object id with -Target using target/objectId, not target/id' {
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest { @{ value = @() } }
        Get-OERAccessPackageAssignment -Target '11111111-1111-1111-1111-111111111111' | Out-Null
        Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 1 -ParameterFilter {
            $Uri -like "*target/objectId eq '11111111-1111-1111-1111-111111111111'*" -and $Uri -notlike '*target/id eq*'
        }
    }

    It 'escapes a -Target value through the OData filter-value owner' {
        Mock -ModuleName $script:moduleName ConvertTo-OERODataFilterValue { $Value } -Verifiable
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest { @{ value = @() } }
        Get-OERAccessPackageAssignment -Target '11111111-1111-1111-1111-111111111111' | Out-Null
        Should -Invoke -ModuleName $script:moduleName ConvertTo-OERODataFilterValue -Times 1
    }

    It 'routes a -State value through the OData filter-value owner' {
        # -State is a ValidateSet, so no documented value can carry a reserved character to prove
        # encoding end-to-end; routing through the single escaping owner is the strongest available
        # proof here (matches the -Target test above).
        Mock -ModuleName $script:moduleName ConvertTo-OERODataFilterValue { $Value } -Verifiable
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest { @{ value = @() } }
        Get-OERAccessPackageAssignment -State 'delivered' | Out-Null
        Should -Invoke -ModuleName $script:moduleName ConvertTo-OERODataFilterValue -Times 1
    }

    It 'rejects a -Target that is not a GUID' {
        # Well-formed empty response so a broken guard is proven by the -Times 0 assertion itself
        # rather than by an unrelated null-input crash further down the pipeline.
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest { @{ value = @() } }
        Get-OERAccessPackageAssignment -Target 'not-a-guid' -ErrorAction SilentlyContinue -ErrorVariable Err | Out-Null
        @($Err | Where-Object { $_.FullyQualifiedErrorId -eq 'InvalidTargetId,Get-OERAccessPackageAssignment' }).Count | Should -Be 1
        Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 0
    }

    It 'rejects an undocumented -State value at bind time' {
        { Get-OERAccessPackageAssignment -State 'nonsense' } | Should -Throw
    }

    It 'resolves -User to an object id and filters on it' {
        Mock -ModuleName $script:moduleName Resolve-OERPrincipalOrId {
            [PSCustomObject]@{
                PrincipalId   = '22222222-2222-2222-2222-222222222222'
                PrincipalType = 'User'
                ErrorId       = $null
                Message       = $null
                Category      = $null
                TargetObject  = $null
            }
        }
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest { @{ value = @() } }
        Get-OERAccessPackageAssignment -User 'ada@contoso.com' | Out-Null
        Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 1 -ParameterFilter {
            $Uri -like "*target/objectId eq '22222222-2222-2222-2222-222222222222'*" -and $Uri -notlike '*target/id eq*'
        }
    }

    It 'keeps positional binding on -AccessPackage unchanged' {
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest { @{ value = @() } }
        { Get-OERAccessPackageAssignment 'Finance Access' } | Should -Not -Throw
        Should -Invoke -ModuleName $script:moduleName Resolve-OERAccessPackageId -Times 1 -ParameterFilter {
            $DisplayName -eq 'Finance Access'
        }
    }

    It 'accepts an AccessPackage object piped in and resolves its Id' {
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {
            @{ value = @(@{ id = 'asg-pipe'; state = 'delivered'; target = @{}; accessPackage = @{} }) }
        }
        $ApObj = [pscustomobject]@{ Id = 'AP-1'; DisplayName = 'AP Sales' }
        $ApObj.PSObject.TypeNames.Insert(0, 'Omnicit.EntraRBAC.AccessPackage')
        $ApObj | Get-OERAccessPackageAssignment | Out-Null
        Should -Invoke -ModuleName $script:moduleName Resolve-OERAccessPackageId -Times 1 -ParameterFilter {
            $DisplayName -eq 'AP-1'
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
        Mock -ModuleName $script:moduleName Remove-OERErrorRecord { }
        $Err = $null
        $Result = Get-OERAccessPackageAssignment -ErrorAction SilentlyContinue -ErrorVariable Err
        $Result | Should -BeNullOrEmpty
        @($Err | Where-Object { $_.FullyQualifiedErrorId -eq 'Authorization_RequestDenied,Get-OERAccessPackageAssignment' }).Count |
            Should -Be 1
        Should -Invoke -ModuleName $script:moduleName Remove-OERErrorRecord -Times 1
    }

    Context 'paging (-All opt-in, Task 7 closes PR36 deliberately-not-fixed item 3)' {
        It 'passes -All to the assignments list read' {
            Mock -ModuleName $script:moduleName Invoke-OERGraphRequest { @{ value = @() } }
            Get-OERAccessPackageAssignment | Out-Null
            Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 1 -Exactly -ParameterFilter {
                $Uri -eq 'v1.0/identityGovernance/entitlementManagement/assignments?$expand=target,accessPackage' -and $All
            }
        }
    }

    Context 'partial-read facts on a failed -All read survive to the callers ErrorVariable (issue #73)' {
        # 3c. Invoke-OERGraphRequest is deliberately NOT mocked in this test -- only
        # Invoke-MgGraphRequest, the one call the REAL wrapper makes -- so this proves the
        # note-property-on-Exception mechanism (docs/development/rationale.md#graph-wrapper) survives
        # out through a PRIVATE `throw` inside Invoke-OERGraphRequest's own paging loop, this PUBLIC
        # cmdlet's own catch/$PSCmdlet.WriteError, and the engine's -ErrorVariable capture: a real
        # module boundary, not an in-process illusion.
        #
        # Deliberately called with NO -AccessPackage (Task 3 ruling): Resolve-OERAccessPackageId gets
        # an extra existence read for a GUID-shaped -AccessPackage value as of Task 4, which has
        # nothing to do with issue #73 and would break this test for an unrelated reason. Omitting
        # -AccessPackage skips Resolve-OERAccessPackageId entirely.
        It '3c: PartialValue/NextLink/PageNumber from a mid-enumeration failure reach the caller via -ErrorVariable' {
            $script:AssignmentPage = 0
            Mock -ModuleName $script:moduleName Invoke-MgGraphRequest {
                $script:AssignmentPage++
                if ($script:AssignmentPage -eq 1) {
                    return @{
                        value             = @(
                            @{ id = 'asg-1'; state = 'delivered'; target = @{}; accessPackage = @{} }
                        )
                        '@odata.nextLink' = 'https://graph.microsoft.com/v1.0/identityGovernance/entitlementManagement/assignments?$skiptoken=P2'
                    }
                }
                $Ex = [System.Exception]::new('{"error":{"code":"InternalServerError","message":"boom"}}')
                $Resp = [System.Net.Http.HttpResponseMessage]::new([System.Net.HttpStatusCode]::InternalServerError)
                Add-Member -InputObject $Ex -NotePropertyName Response -NotePropertyValue $Resp
                throw $Ex
            }

            $Err = $null
            $Result = Get-OERAccessPackageAssignment -ErrorAction SilentlyContinue -ErrorVariable Err

            $Result | Should -BeNullOrEmpty

            # -ErrorVariable also accumulates Pester's own internal mock-invocation bookkeeping and
            # records the engine captures from nested calls even when an inner catch swallowed them,
            # which is noise no real (unmocked) caller could ever see -- restrict to the ONE record
            # actually published through this cmdlet's own $PSCmdlet.WriteError call (same technique
            # as Get-OERGroup.Tests.ps1's guard tests).
            $Published = @($Err) | Where-Object {
                $_.InvocationInfo -and $_.InvocationInfo.MyCommand -and
                $_.InvocationInfo.MyCommand.Name -eq 'Get-OERAccessPackageAssignment'
            }
            @($Published).Count | Should -Be 1
            $Published[0].Exception.PartialValue | Should -Not -BeNullOrEmpty
            @($Published[0].Exception.PartialValue).Count | Should -Be 1
            $Published[0].Exception.PartialValue[0].id | Should -Be 'asg-1'
            $Published[0].Exception.NextLink | Should -Be (
                'https://graph.microsoft.com/v1.0/identityGovernance/entitlementManagement/assignments?$skiptoken=P2')
            $Published[0].Exception.PageNumber | Should -Be 2
        }
    }
}

Describe 'Get-OERAccessPackageAssignment -- a stale access package id is not silence (issue #71)' {
    # Deliberately a SEPARATE Describe: the block above mocks Resolve-OERAccessPackageId in its own
    # BeforeEach, and this check has to run the REAL resolver end to end. Before the fix, a GUID
    # that no longer exists was handed back unchecked, the assignments query filtered on it, Graph
    # answered with an empty collection, and the operator got no output and no error -- unable to
    # tell "this package has nothing" from "this package is gone".
    BeforeEach {
        InModuleScope $script:moduleName { $script:_OERAuthState = $null }
        Mock -ModuleName $script:moduleName Initialize-OERAuth {}
    }

    It '4g: writes a non-terminating AccessPackageNotFound and emits nothing' {
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {
            if ($Uri -like '*accessPackages/77777777-7777-7777-7777-777777777777*') {
                $Marker = [PSCustomObject]@{
                    ExpectedErrorCode = 'ResourceNotFound'
                    StatusCode        = 404
                    Message           = 'ResourceNotFound: not found'
                    Uri               = $Uri
                }
                $Marker.PSObject.TypeNames.Insert(0, 'Omnicit.EntraRBAC.GraphExpectedError')
                return $Marker
            }
            # Reached only if the existence read is gone: the assignments query on a dead id, which
            # is exactly the empty-collection silence this test exists to refuse.
            return @{ value = @() }
        }

        $Err = $null
        $Result = Get-OERAccessPackageAssignment -AccessPackage '77777777-7777-7777-7777-777777777777' `
            -ErrorAction SilentlyContinue -ErrorVariable Err

        $Result | Should -BeNullOrEmpty

        # Same narrowing as the paging guard above: -ErrorVariable also picks up Pester's mock
        # bookkeeping and records swallowed by inner catches, so measure only what THIS cmdlet
        # published through its own $PSCmdlet.WriteError.
        $Published = @($Err) | Where-Object {
            $_.InvocationInfo -and $_.InvocationInfo.MyCommand -and
            $_.InvocationInfo.MyCommand.Name -eq 'Get-OERAccessPackageAssignment'
        }
        @($Published).Count | Should -Be 1
        $Published[0].FullyQualifiedErrorId | Should -Match '^AccessPackageNotFound'
        $Published[0].Exception.Message | Should -Match '77777777-7777-7777-7777-777777777777'

        # Exactly one call: the existence read. The assignments query is never issued, so no empty
        # collection can be mistaken for an answer.
        Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 1 -Exactly
    }
}

Describe 'Get-OERAccessPackageAssignment -- a failed resolver read is not a not-found (issue #71, fix round 1)' {
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
        Get-OERAccessPackageAssignment -AccessPackage 'AP-Sales' -ErrorAction SilentlyContinue -ErrorVariable Err | Out-Null

        # NARROWED ON PURPOSE, and the narrowing is the whole guard. -ErrorVariable also collects
        # the engine's own capture of the INNER throw, whose FullyQualifiedErrorId is the bare
        # 'Authorization_RequestDenied' whether or not this cmdlet re-published it -- measured, not
        # assumed. An unnarrowed $Err[0] or -join match therefore passes with the fix reverted.
        # Only the record this cmdlet published carries its own name in InvocationInfo.
        $Published = @($Err) | Where-Object {
            $_.InvocationInfo -and $_.InvocationInfo.MyCommand -and
            $_.InvocationInfo.MyCommand.Name -eq 'Get-OERAccessPackageAssignment'
        }
        @($Published).Count | Should -Be 1
        $Published[0].FullyQualifiedErrorId | Should -Match '^Authorization_RequestDenied'
        $Published[0].FullyQualifiedErrorId | Should -Not -Match 'AccessPackageNotFound' -Because (
            'a permission failure booked as a missing object is the failed-read-as-an-empty-fact defect of issue #76')
        $Published[0].CategoryInfo.Category | Should -Be 'PermissionDenied'
        Should -Invoke -ModuleName 'Omnicit.EntraRBAC' Invoke-OERGraphRequest -Times 0 -Exactly
    }
}
