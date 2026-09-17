BeforeAll {
    $script:moduleName = 'Omnicit.EntraRBAC'
    Get-Module $script:moduleName | Remove-Module -Force -ErrorAction SilentlyContinue
    Import-Module $script:moduleName -Force -ErrorAction Stop
}

Describe 'Convert-GraphHttpException' {
    It 'parses a JSON graph error body into code and message' {
        InModuleScope $script:moduleName {
            $Json = '{"error":{"code":"Request_BadRequest","message":"Invalid value."}}'
            $Ex = [System.Exception]::new($Json)
            $Record = [System.Management.Automation.ErrorRecord]::new($Ex, 'orig', 'NotSpecified', $null)
            $Result = Convert-GraphHttpException $Record
            $Result.FullyQualifiedErrorId | Should -Be 'Request_BadRequest'
            $Result.Exception.Message | Should -Match 'Invalid value'
        }
    }

    It 'sanitizes even when no JSON error is present, never returning the raw record (audit-pr8)' {
        InModuleScope $script:moduleName {
            # SECURITY: this used to assert the OPPOSITE -- that the raw record was returned
            # unchanged. That was the bug: the raw record's .Exception is the original SDK
            # exception, which for a real transport failure references the bearer-carrying
            # HttpRequestMessage. The "nothing extractable" fallback must now still sanitize.
            $Ex = [System.Exception]::new('plain text failure')
            $Record = [System.Management.Automation.ErrorRecord]::new($Ex, 'orig', 'NotSpecified', $null)
            $Result = Convert-GraphHttpException $Record

            $Result | Should -Not -Be $Record
            [object]::ReferenceEquals($Result.Exception, $Ex) | Should -BeFalse
            $Result.Exception.InnerException | Should -BeNullOrEmpty
            $Result.Exception.Message | Should -Match 'plain text failure'
            $Result.FullyQualifiedErrorId | Should -Not -BeNullOrEmpty
        }
    }

    It 'extracts code and message from a wrapped retry/aggregate message (throttling 429)' {
        InModuleScope $script:moduleName {
            # A Graph SDK retry AggregateException message: JSON error bodies embedded in non-JSON text.
            $Msg = 'Too many retries performed. More than 3 retries encountered while sending the request. ' +
                   '(HTTP request failed with status code: TooManyRequests.{"error":{"code":"TooManyRequests",' +
                   '"message":"Too many requests from Identifier under category:throttle.msgraph.accessreviews. ' +
                   'Please try again later.","innerError":{"date":"2026-06-11T15:06:41"}}})'
            $Ex = [System.Exception]::new($Msg)
            $Record = [System.Management.Automation.ErrorRecord]::new($Ex, 'orig', 'NotSpecified', $null)
            $Result = Convert-GraphHttpException $Record
            $Result.FullyQualifiedErrorId | Should -Be 'TooManyRequests'
            $Result.Exception.Message | Should -Match 'Too many requests'
            $Result.Exception.Message | Should -Match 'try again later'
            # The raw exception must not be chained (bearer-token safety).
            $Result.Exception.InnerException | Should -BeNullOrEmpty
        }
    }

    It 'surfaces a Graph error whose code is empty (403 unauthorized) using the message' {
        InModuleScope $script:moduleName {
            $Json = '{"error":{"code":"","message":"Attempted to perform an unauthorized operation."}}'
            $Record = [System.Management.Automation.ErrorRecord]::new([System.Exception]::new($Json), 'orig', 'NotSpecified', $null)
            $Result = Convert-GraphHttpException $Record
            $Result | Should -Not -Be $Record
            $Result.Exception.Message | Should -Match 'unauthorized operation'
            $Result.FullyQualifiedErrorId | Should -Not -BeNullOrEmpty
        }
    }

    It 'does not leave its own JSON parse failure in $Error when extracting from a wrapped message' {
        InModuleScope $script:moduleName {
            $Error.Clear()
            $Msg = 'wrapper text (HTTP request failed: {"error":{"code":"TooManyRequests","message":"slow down."}})'
            $Record = [System.Management.Automation.ErrorRecord]::new([System.Exception]::new($Msg), 'orig', 'NotSpecified', $null)
            $null = Convert-GraphHttpException $Record
            @($Error | Where-Object { $_.ToString() -match 'Conversion from JSON|parsing value' }).Count | Should -Be 0
        }
    }

    It 'does not chain the raw exception, so no bearer token can leak via InnerException' {
        InModuleScope $script:moduleName {
            $Json = '{"error":{"code":"InvalidRoleAssignmentRequest","message":"The role assignment request is invalid."}}'
            # Simulate the raw SDK exception carrying a request message with an Authorization header.
            $Raw = [System.Exception]::new($Json)
            $Raw.Data['Authorization'] = 'Bearer SECRET-TOKEN'
            $Record = [System.Management.Automation.ErrorRecord]::new($Raw, 'orig', 'NotSpecified', $null)
            $Result = Convert-GraphHttpException $Record
            $Result.Exception.InnerException | Should -BeNullOrEmpty
            $Result.FullyQualifiedErrorId | Should -Be 'InvalidRoleAssignmentRequest'
        }
    }

    It 'decodes a URL-encoded PIM claims body via the request retry path' {
        # Exercises Get-ClaimsFromException URL-decode branch through Invoke-OERGraphRequest.
        InModuleScope 'Omnicit.EntraRBAC' {
            $script:_OERAuthState = @{ TenantId = 'contoso'; AuthMethod = 'Interactive'; ClientId = $null }
        }
        $script:Attempt = 0
        Mock -ModuleName 'Omnicit.EntraRBAC' Initialize-OERAuth {}
        Mock -ModuleName 'Omnicit.EntraRBAC' Invoke-MgGraphRequest {
            $script:Attempt++
            if ($script:Attempt -eq 1) {
                throw [System.Exception]::new('RoleAssignmentRequestAcrsValidationFailed &claims=%7B%22access_token%22%3A%7B%22acrs%22%3A%7B%22essential%22%3Atrue%2C%22value%22%3A%22c1%22%7D%7D%7D')
            }
            @{ value = @('ok') }
        }
        InModuleScope 'Omnicit.EntraRBAC' {
            (Invoke-OERGraphRequest -Uri 'beta/policies/roleManagementPolicies/p/rules/r' -Method PATCH -Body @{ x = 1 }).value | Should -Be 'ok'
        }
        Should -Invoke -ModuleName 'Omnicit.EntraRBAC' Initialize-OERAuth -Times 1 -ParameterFilter { $ClaimsChallenge -match 'acrs' }
    }
}
