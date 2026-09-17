BeforeAll {
    $script:moduleName = 'Omnicit.EntraRBAC'
    Get-Module $script:moduleName | Remove-Module -Force -ErrorAction SilentlyContinue
    Import-Module $script:moduleName -Force -ErrorAction Stop
}

Describe 'New-OERAccessPackageAssignment' {
    BeforeEach {
        InModuleScope $script:moduleName { $script:_OERAuthState = $null }
        Mock -ModuleName $script:moduleName Initialize-OERAuth {}
        Mock -ModuleName $script:moduleName Resolve-OERAccessPackageId { 'ap-1' }
    }

    It 'posts an adminAdd assignment request' {
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest { @{ id = 'req-1'; requestType = 'adminAdd'; requestState = 'Submitted' } } -ParameterFilter { $Method -eq 'POST' }
        New-OERAccessPackageAssignment -AccessPackage 'AP-Sales' -Policy '11111111-1111-1111-1111-111111111111' -TargetId 'aaaa0000-0000-0000-0000-000000000001' -Confirm:$false | Out-Null
        Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 1 -ParameterFilter {
            $Method -eq 'POST' -and $Uri -like '*assignmentRequests' -and
            $Body.requestType -eq 'adminAdd' -and $Body.assignment.targetId -eq 'aaaa0000-0000-0000-0000-000000000001' -and
            $Body.assignment.accessPackageId -eq 'ap-1' -and $Body.assignment.assignmentPolicyId -eq '11111111-1111-1111-1111-111111111111'
        }
    }

    It 'does not POST under -WhatIf' {
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {}
        New-OERAccessPackageAssignment -AccessPackage 'AP-Sales' -Policy '11111111-1111-1111-1111-111111111111' -TargetId 'aaaa0000-0000-0000-0000-000000000001' -WhatIf | Out-Null
        Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 0 -ParameterFilter { $Method -eq 'POST' }
    }

    It 'errors AccessPackageNotFound when the access package cannot be resolved' {
        Mock -ModuleName $script:moduleName Resolve-OERAccessPackageId { $null }
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {}
        New-OERAccessPackageAssignment -AccessPackage 'nope' -Policy '11111111-1111-1111-1111-111111111111' -TargetId 'aaaa0000-0000-0000-0000-000000000001' -ErrorVariable err -ErrorAction SilentlyContinue | Out-Null
        $err.FullyQualifiedErrorId | Should -Match 'AccessPackageNotFound'
        Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 0 -ParameterFilter { $Method -eq 'POST' }
    }

    It 'binds AccessPackage, Policy and a GUID TargetId positionally (pre-existing contract preserved)' {
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest { @{ id = 'req-1'; requestType = 'adminAdd' } }
        New-OERAccessPackageAssignment 'AP-Sales' '11111111-1111-1111-1111-111111111111' 'aaaa0000-0000-0000-0000-000000000001' -Confirm:$false | Out-Null
        Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 1 -ParameterFilter {
            $Body.assignment.targetId -eq 'aaaa0000-0000-0000-0000-000000000001'
        }
    }

    Context 'friendly target input' {
        BeforeEach {
            InModuleScope Omnicit.EntraRBAC { $script:_OERAuthState = $null }
            Mock -ModuleName Omnicit.EntraRBAC Initialize-OERAuth { }
            Mock -ModuleName Omnicit.EntraRBAC Resolve-OERAccessPackageId { 'pkgpkg0-0000-0000-0000-00000000000d' }
            Mock -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest { @{ id = 'req1'; requestType = 'adminAdd' } }
        }

        It 'resolves -User to an object id and sends it as assignment.targetId' {
            Mock -ModuleName Omnicit.EntraRBAC Resolve-OERPrincipal {
                [PSCustomObject]@{ PrincipalId = 'bbbb0000-0000-0000-0000-000000000002'; PrincipalType = 'User' }
            }
            New-OERAccessPackageAssignment -AccessPackage 'AP-Sales' -Policy '22222222-2222-2222-2222-222222222222' `
                -User 'anna.berg@contoso.com' -Confirm:$false
            Should -Invoke Invoke-OERGraphRequest -ModuleName Omnicit.EntraRBAC -Times 1 -ParameterFilter {
                $Method -eq 'POST' -and
                $Uri -eq 'v1.0/identityGovernance/entitlementManagement/assignmentRequests' -and
                $Body.requestType -eq 'adminAdd' -and
                $Body.assignment.targetId -eq 'bbbb0000-0000-0000-0000-000000000002' -and
                $Body.assignment.accessPackageId -eq 'pkgpkg0-0000-0000-0000-00000000000d' -and
                $Body.assignment.assignmentPolicyId -eq '22222222-2222-2222-2222-222222222222'
            }
        }

        It 'still accepts a raw GUID -TargetId with no lookup' {
            Mock -ModuleName Omnicit.EntraRBAC Resolve-OERPrincipal { throw 'should not be called' }
            New-OERAccessPackageAssignment -AccessPackage 'AP-Sales' -Policy '22222222-2222-2222-2222-222222222222' `
                -TargetId 'aaaa0000-0000-0000-0000-000000000001' -Confirm:$false
            Should -Invoke Invoke-OERGraphRequest -ModuleName Omnicit.EntraRBAC -Times 1 -ParameterFilter {
                $Body.assignment.targetId -eq 'aaaa0000-0000-0000-0000-000000000001'
            }
            Should -Invoke Resolve-OERPrincipal -ModuleName Omnicit.EntraRBAC -Times 0
        }

        It 'rejects a UPN passed to -TargetId with InvalidTargetId and does not call Graph' {
            $Err = $null
            New-OERAccessPackageAssignment -AccessPackage 'AP-Sales' -Policy '22222222-2222-2222-2222-222222222222' `
                -TargetId 'anna.berg@contoso.com' -Confirm:$false `
                -ErrorAction SilentlyContinue -ErrorVariable Err
            $Err[0].FullyQualifiedErrorId | Should -BeLike 'InvalidTargetId*'
            $Err[0].Exception.Message | Should -BeLike "*'-TargetId'*"
            $Err[0].Exception.Message | Should -BeLike '*-User*'
            Should -Invoke Invoke-OERGraphRequest -ModuleName Omnicit.EntraRBAC -Times 0 -ParameterFilter {
                $Method -eq 'POST'
            }
        }

        It 'binds -TargetId from the pipeline by property name' {
            $Existing = [PSCustomObject]@{ TargetId = 'aaaa0000-0000-0000-0000-000000000001' }
            $Existing | New-OERAccessPackageAssignment -AccessPackage 'AP-Sales' -Policy '22222222-2222-2222-2222-222222222222' -Confirm:$false
            Should -Invoke Invoke-OERGraphRequest -ModuleName Omnicit.EntraRBAC -Times 1 -ParameterFilter {
                $Body.assignment.targetId -eq 'aaaa0000-0000-0000-0000-000000000001'
            }
        }

        It 'reports NoPrincipal when neither -TargetId nor -User is supplied' {
            $Err = $null
            New-OERAccessPackageAssignment -AccessPackage 'AP-Sales' -Policy '22222222-2222-2222-2222-222222222222' -Confirm:$false `
                -ErrorAction SilentlyContinue -ErrorVariable Err
            $Err[0].FullyQualifiedErrorId | Should -BeLike 'NoPrincipal*'
        }
    }

    It 'returns a tagged assignment request stamped with the resolved package id and a raw GUID target id' {
        Mock -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest {
            @{ id = 'req-9'; requestType = 'adminAdd'; state = 'submitted'; status = 'Accepted' }
        }
        $Result = New-OERAccessPackageAssignment -AccessPackage '00000000-0000-0000-0000-0000000000ap' `
            -Policy '99999999-9999-9999-9999-999999999999' -TargetId '00000000-0000-0000-0000-0000000000aa' -Confirm:$false
        $Result.PSObject.TypeNames[0] | Should -Be 'Omnicit.EntraRBAC.AssignmentRequest'
        $Result.RequestId | Should -Be 'req-9'
        $Result.State | Should -Be 'submitted'
        $Result.TargetId | Should -Be '00000000-0000-0000-0000-0000000000aa'
        $Result.AccessPackageId | Should -Be 'ap-1'
        $Result.AssignmentPolicyId | Should -Be '99999999-9999-9999-9999-999999999999'
        $Result.PSObject.Properties.Name | Should -Not -Contain 'Id'
    }

    It 'stamps the RESOLVED target id (not the raw -User argument) when the principal is resolved by name' {
        Mock -ModuleName Omnicit.EntraRBAC Resolve-OERPrincipal {
            [PSCustomObject]@{ PrincipalId = 'cccc0000-0000-0000-0000-000000000003'; PrincipalType = 'User' }
        }
        Mock -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest {
            @{ id = 'req-10'; requestType = 'adminAdd'; state = 'submitted'; status = 'Accepted' }
        }
        $Result = New-OERAccessPackageAssignment -AccessPackage '00000000-0000-0000-0000-0000000000ap' `
            -Policy '99999999-9999-9999-9999-999999999999' -User 'anna.berg@contoso.com' -Confirm:$false
        $Result.TargetId | Should -Be 'cccc0000-0000-0000-0000-000000000003'
        $Result.TargetId | Should -Not -Be 'anna.berg@contoso.com'
        $Result.AccessPackageId | Should -Be 'ap-1'
    }

    It 'surfaces a Graph POST failure as a non-terminating error and emits nothing' {
        # Guards two things the cmdlet must do on a Graph failure: call Remove-OERErrorRecord (the
        # mandatory bearer-token-hygiene line -- asserted via Should -Invoke, since a deleted line
        # would otherwise pass unnoticed) and write its OWN non-terminating record. Match the
        # cmdlet-QUALIFIED ErrorId: PowerShell auto-records the mock's throw into -ErrorVariable a
        # dozen times before the catch runs, so matching the bare Graph code would pass even with
        # WriteError deleted.
        Mock -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest {
            throw [System.Management.Automation.ErrorRecord]::new(
                [System.Exception]::new('Request_BadRequest: The assignment policy is not valid.'),
                'Request_BadRequest',
                [System.Management.Automation.ErrorCategory]::InvalidOperation,
                $null)
        }
        Mock -ModuleName Omnicit.EntraRBAC Remove-OERErrorRecord { }
        $Err = $null
        $Result = New-OERAccessPackageAssignment -AccessPackage 'AP-Core' -Policy '99999999-9999-9999-9999-999999999999' `
            -TargetId '00000000-0000-0000-0000-0000000000aa' -Confirm:$false `
            -ErrorAction SilentlyContinue -ErrorVariable Err
        $Result | Should -BeNullOrEmpty
        @($Err | Where-Object { $_.FullyQualifiedErrorId -eq 'Request_BadRequest,New-OERAccessPackageAssignment' }).Count |
            Should -Be 1
        Should -Invoke -ModuleName Omnicit.EntraRBAC Remove-OERErrorRecord -Times 1
    }

    It 'binds -AccessPackage and -Policy from a piped real Assignment object, never the assignment''s own Id' {
        # ConvertTo-OERAssignment emits Id (the ASSIGNMENT id) alongside AccessPackageId -- a wrong
        # 'Id' alias on -AccessPackage would silently bind the assignment id as the package instead.
        # -Policy has no display-name resolution, so this also proves the AssignmentPolicyId alias
        # path independently of the mocked Resolve-OERAccessPackageId in the outer BeforeEach.
        $RawAssignment = @{
            id              = 'assignment-id-999'
            target          = @{ objectId = 'aaaa0000-0000-0000-0000-000000000001'; displayName = 'Anna' }
            accessPackage   = @{ id = 'ap-real-package-id'; displayName = 'AP-Sales' }
            assignmentState = 'Delivered'
        }
        $PipedAssignment = InModuleScope $script:moduleName -Parameters @{ Raw = $RawAssignment } {
            param($Raw)
            ConvertTo-OERAssignment -InputObject $Raw
        }
        # Echo back whatever -DisplayName the resolver was asked to look up, so a wrong bind (the
        # assignment's own Id) is visible in the POST body instead of being masked by the outer
        # BeforeEach's constant 'ap-1' mock.
        Mock -ModuleName $script:moduleName Resolve-OERAccessPackageId { $DisplayName }
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest { @{ id = 'req-1'; requestType = 'adminAdd' } } -ParameterFilter { $Method -eq 'POST' }

        $PipedAssignment | New-OERAccessPackageAssignment -Policy '33333333-3333-3333-3333-333333333333' -Confirm:$false | Out-Null

        Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 1 -Exactly -ParameterFilter {
            $Method -eq 'POST' -and $Body.assignment.accessPackageId -eq 'ap-real-package-id' -and
            $Body.assignment.accessPackageId -ne 'assignment-id-999'
        }
    }

    It 'errors InvalidPolicyId for a non-GUID -Policy and issues no Graph request' {
        # A non-null return, so that (pre-fix, before the guard exists) the call would complete rather
        # than crash on a coincidental null-InputObject binding failure unrelated to the guard.
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest { @{ id = 'should-not-be-called-req' } }
        $Err = $null
        New-OERAccessPackageAssignment -AccessPackage 'AP-Sales' -Policy 'not-a-guid' `
            -TargetId 'aaaa0000-0000-0000-0000-000000000001' -Confirm:$false `
            -ErrorAction SilentlyContinue -ErrorVariable Err | Out-Null
        $Err[0].FullyQualifiedErrorId | Should -Be 'InvalidPolicyId,New-OERAccessPackageAssignment'
        Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 0 -Exactly
    }

    It 'surfaces a resolver throw as itself and still scrubs the bearer token off it' {
        # REWRITTEN for issue #71 fix round 1. This used to assert that a resolver throw reached the
        # caller as AccessPackageNotFound, and that no resolver record survived in $Error. Both
        # halves described the OLD contract, in which the catch dropped the record and fell through
        # to the not-found branch -- which is precisely the failed-read-as-an-empty-fact defect that
        # fix round 1 removes. The record is now published deliberately, so it is SUPPOSED to be in
        # $Error, and the $Error-absence assertion could no longer mean anything.
        #
        # The bearer-hygiene half is kept, and is now proved directly instead of by that proxy.
        # Remove-OERErrorRecord's load-bearing step is not the $Error removal at all: it clears the
        # Authorization header on the shared HttpRequestMessage the record points at, which disarms
        # every copy that already escaped into the caller's -ErrorVariable. So hang a real request
        # message carrying a real-looking token off the thrown record and assert the header is gone
        # afterwards -- that survives publication, which the old shape did not.
        $Request = [System.Net.Http.HttpRequestMessage]::new(
            [System.Net.Http.HttpMethod]::Get, 'https://graph.microsoft.com/v1.0/me')
        $Request.Headers.Authorization =
            [System.Net.Http.Headers.AuthenticationHeaderValue]::new('Bearer', 'eyJ0eXAiOiJKV1QiLCJhbGciOiJSUzI1NiJ9.not-a-real-token')
        $Request.Headers.Authorization | Should -Not -BeNullOrEmpty -Because 'the guard is vacuous if the header was never set'

        Mock -ModuleName Omnicit.EntraRBAC Resolve-OERAccessPackageId {
            throw [System.Management.Automation.ErrorRecord]::new(
                [System.Exception]::new('resolver transport failure'),
                'GraphError',
                [System.Management.Automation.ErrorCategory]::ConnectionError,
                $Request)
        }
        Mock -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest { }
        $Err = $null
        New-OERAccessPackageAssignment -AccessPackage 'AP-Core' -Policy '99999999-9999-9999-9999-999999999999' `
            -TargetId '00000000-0000-0000-0000-0000000000aa' -Confirm:$false `
            -ErrorAction SilentlyContinue -ErrorVariable Err | Out-Null

        $Published = @($Err) | Where-Object {
            $_.InvocationInfo -and $_.InvocationInfo.MyCommand -and
            $_.InvocationInfo.MyCommand.Name -eq 'New-OERAccessPackageAssignment'
        }
        @($Published).Count | Should -Be 1
        $Published[0].Exception.Message | Should -Match 'resolver transport failure'
        $Published[0].FullyQualifiedErrorId | Should -Not -Match 'AccessPackageNotFound'
        $Request.Headers.Authorization | Should -BeNullOrEmpty -Because (
            'Remove-OERErrorRecord must clear the header on the shared request, so publishing the record cannot leak a token')
        Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest -Times 0 -Exactly
    }
}

Describe 'New-OERAccessPackageAssignment GUID access package pass-through' {
    BeforeAll {
        Import-Module $script:moduleName -Force
    }
    BeforeEach {
        InModuleScope $script:moduleName { $script:_OERAuthState = $null }
        Mock -ModuleName $script:moduleName Initialize-OERAuth { }
    }

    It 'passes a GUID -AccessPackage through to the request body without a display-name lookup' {
        # Makes the help's documented GUID pass-through real. The two existing tagged-output Its in
        # the main Describe assert AccessPackageId -eq 'ap-1' while passing a GUID -- they were only
        # re-asserting the outer BeforeEach mock's return value there (Resolve-OERAccessPackageId is
        # mocked to always return 'ap-1'), not proving the pass-through. This Describe deliberately
        # never mocks Resolve-OERAccessPackageId, so the real resolver's GUID path (Test-OERGuid ->
        # confirm the id exists -> return it unchanged) is what produces the value asserted below.
        # Since issue #71 that path costs ONE id-addressed existence read; what it must still never
        # do is the tenant-wide displayName filter, and that is what the throwing mock below pins.
        Mock -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest {
            @{ id = 'req-11'; requestType = 'adminAdd'; state = 'submitted'; status = 'Accepted' }
        } -ParameterFilter { $Method -eq 'POST' }
        Mock -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest {
            @{ id = 'dddd0000-0000-0000-0000-00000000000a' }
        } -ParameterFilter { $Method -ne 'POST' -and $Uri -like '*accessPackages/dddd0000-0000-0000-0000-00000000000a*' }
        Mock -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest {
            throw 'a GUID access package must not trigger a display-name lookup'
        } -ParameterFilter { $Method -ne 'POST' -and $Uri -notlike '*accessPackages/dddd0000-0000-0000-0000-00000000000a*' }
        $Result = New-OERAccessPackageAssignment `
            -AccessPackage 'dddd0000-0000-0000-0000-00000000000a' -Policy '99999999-9999-9999-9999-999999999999' `
            -TargetId '00000000-0000-0000-0000-0000000000aa' -Confirm:$false
        $Result.AccessPackageId | Should -Be 'dddd0000-0000-0000-0000-00000000000a'
        Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest -Times 1 -ParameterFilter {
            $Method -eq 'POST' -and $Body.assignment.accessPackageId -eq 'dddd0000-0000-0000-0000-00000000000a'
        }
    }
}

Describe 'New-OERAccessPackageAssignment -- a failed resolver read is not a not-found (issue #71, fix round 1)' {
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
        New-OERAccessPackageAssignment -AccessPackage 'AP-Sales' -Policy '99999999-9999-9999-9999-999999999999' `
            -TargetId 'aaaa0000-0000-0000-0000-000000000001' -Confirm:$false `
            -ErrorAction SilentlyContinue -ErrorVariable Err | Out-Null

        # NARROWED ON PURPOSE, and the narrowing is the whole guard. -ErrorVariable also collects
        # the engine's own capture of the INNER throw, whose FullyQualifiedErrorId is the bare
        # 'Authorization_RequestDenied' whether or not this cmdlet re-published it -- measured, not
        # assumed. An unnarrowed $Err[0] or -join match therefore passes with the fix reverted.
        # Only the record this cmdlet published carries its own name in InvocationInfo.
        $Published = @($Err) | Where-Object {
            $_.InvocationInfo -and $_.InvocationInfo.MyCommand -and
            $_.InvocationInfo.MyCommand.Name -eq 'New-OERAccessPackageAssignment'
        }
        @($Published).Count | Should -Be 1
        $Published[0].FullyQualifiedErrorId | Should -Match '^Authorization_RequestDenied'
        $Published[0].FullyQualifiedErrorId | Should -Not -Match 'AccessPackageNotFound' -Because (
            'a permission failure booked as a missing object is the failed-read-as-an-empty-fact defect of issue #76')
        $Published[0].CategoryInfo.Category | Should -Be 'PermissionDenied'
        Should -Invoke -ModuleName 'Omnicit.EntraRBAC' Invoke-OERGraphRequest -Times 0 -Exactly
    }
}
