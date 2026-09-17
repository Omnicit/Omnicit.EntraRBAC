BeforeAll {
    Import-Module Omnicit.EntraRBAC -Force
}

Describe 'Convert-ArmHttpException' {
    It 'parses code and message from an ARM error body' {
        InModuleScope Omnicit.EntraRBAC {
            $Response = [PSCustomObject]@{
                StatusCode = 409
                Content    = '{"error":{"code":"RoleAssignmentExists","message":"The role assignment already exists."}}'
            }
            $Record = Convert-ArmHttpException -Response $Response -Path '/subscriptions/x'
            $Record | Should -BeOfType [System.Management.Automation.ErrorRecord]
            $Record.FullyQualifiedErrorId | Should -Be 'RoleAssignmentExists'
            $Record.Exception.Message | Should -Be 'RoleAssignmentExists: The role assignment already exists.'
            $Record.ErrorDetails.Message | Should -Be 'RoleAssignmentExists: The role assignment already exists.'
            $Record.TargetObject | Should -Be '/subscriptions/x'
        }
    }

    It 'appends nested error.details to the message so InvalidPolicy is diagnosable' {
        InModuleScope Omnicit.EntraRBAC {
            $Response = [PSCustomObject]@{
                StatusCode = 400
                Content    = '{"error":{"code":"InvalidPolicy","message":"The policy is invalid.","details":[{"code":"RoleManagementPolicyRuleValidationError","message":"Permanent eligible assignment is not allowed for this role."}]}}'
            }
            $Record = Convert-ArmHttpException -Response $Response
            $Record.FullyQualifiedErrorId | Should -Be 'InvalidPolicy'
            $Record.Exception.Message | Should -Match 'The policy is invalid'
            $Record.Exception.Message | Should -Match 'Permanent eligible assignment is not allowed'
        }
    }

    It 'derives a label from the HTTP status when the body has no code' {
        InModuleScope Omnicit.EntraRBAC {
            $Response = [PSCustomObject]@{
                StatusCode = 403
                Content    = '{"error":{"code":"","message":"Attempted to perform an unauthorized operation."}}'
            }
            $Record = Convert-ArmHttpException -Response $Response
            $Record.FullyQualifiedErrorId | Should -Be 'Forbidden'
            $Record.Exception.Message | Should -Match 'unauthorized operation'
        }
    }

    It 'falls back to regex extraction when the content is not pure JSON' {
        InModuleScope Omnicit.EntraRBAC {
            $Before = $Error.Count
            $Response = [PSCustomObject]@{
                StatusCode = 429
                Content    = 'Some wrapper text {"code":"TooManyRequests","message":"Rate limited."} trailing'
            }
            $Record = Convert-ArmHttpException -Response $Response
            $Record.FullyQualifiedErrorId | Should -Be 'TooManyRequests'
            $Error.Count | Should -Be $Before
        }
    }

    It 'labels unknown statuses as HTTP<n> when there is no content' {
        InModuleScope Omnicit.EntraRBAC {
            $Response = [PSCustomObject]@{ StatusCode = 418; Content = '' }
            $Record = Convert-ArmHttpException -Response $Response
            $Record.FullyQualifiedErrorId | Should -Be 'HTTP418'
        }
    }

    It 'scrubs the bearer-hygiene record when the ARM error body is not valid JSON' {
        InModuleScope Omnicit.EntraRBAC {
            Mock Remove-OERErrorRecord { }
            $Response = [PSCustomObject]@{
                StatusCode = 400
                Content    = 'Some wrapper text {"code":"BadRequest","message":"Broken."} trailing'
            }
            $null = Convert-ArmHttpException -Response $Response -Path '/subscriptions/x'
            Should -Invoke Remove-OERErrorRecord -Times 1
        }
    }

    It 'ignores a Headers property on the normalized response and never surfaces it' {
        InModuleScope Omnicit.EntraRBAC {
            $Response = [PSCustomObject]@{
                StatusCode = 429
                Content    = '{"error":{"code":"TooManyRequests","message":"slow down"}}'
                Headers    = @{ 'Retry-After' = @('30'); 'Authorization' = @('Bearer LEAKED') }
            }
            $Record = Convert-ArmHttpException -Response $Response -Path '/x?api-version=2022-12-01'
            $Record.FullyQualifiedErrorId | Should -Be 'TooManyRequests'
            $Record.Exception.Message | Should -Be 'TooManyRequests: slow down'
            [string]$Record.ErrorDetails.Message | Should -Not -Match '(?i)bearer'
            [string]$Record.ErrorDetails.Message | Should -Not -Match 'Retry-After'
        }
    }
}
