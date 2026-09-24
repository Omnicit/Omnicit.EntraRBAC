BeforeAll {
    $script:moduleName = 'Omnicit.EntraRBAC'
    Get-Module $script:moduleName | Remove-Module -Force -ErrorAction SilentlyContinue
    Import-Module $script:moduleName -Force -ErrorAction Stop
}

Describe 'Get-OERGroupPimPolicy' {
    BeforeEach {
        InModuleScope $script:moduleName { $script:_OERAuthState = $null }
        Mock -ModuleName $script:moduleName Initialize-OERAuth {}
        Mock -ModuleName $script:moduleName Resolve-OERGroupId { 'gid-1' }
        Mock -ModuleName $script:moduleName Get-OERPimGroupPolicyId { 'pol-1' }
    }

    It 'reads the policy rules and surfaces the activation window' {
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {
            @{ value = @(
                @{ id = 'Expiration_EndUser_Assignment'; maximumDuration = 'PT8H' }
                @{ id = 'AuthenticationContext_EndUser_Assignment'; claimValue = 'c1'; isEnabled = $true }
            ) }
        } -ParameterFilter { $Uri -match 'roleManagementPolicies/pol-1/rules' }
        $Result = Get-OERGroupPimPolicy -Id 'gid-1'
        $Result.PolicyId | Should -Be 'pol-1'
        $Result.ActivationMaxHours | Should -Be 8
        $Result.AuthenticationContextId | Should -Be 'c1'
        $Result.PSObject.TypeNames[0] | Should -Be 'Omnicit.EntraRBAC.GroupPimPolicy'
    }

    It 'errors when the group is not onboarded to PIM' {
        Mock -ModuleName $script:moduleName Get-OERPimGroupPolicyId { $null }
        Get-OERGroupPimPolicy -Id 'gid-1' -ErrorVariable err -ErrorAction SilentlyContinue | Out-Null
        $err.FullyQualifiedErrorId | Should -Match 'PimPolicyNotFound'
    }

    It 'reports a FAILED policy-assignment lookup as PimPolicyReadFailed, never as PimPolicyNotFound' {
        # THE DISTINCTION THIS CMDLET OWNS. Get-OERPimGroupPolicyId returns $null only where it
        # LEARNED there is no assignment; a 403, a throttle or a dead transport throws instead. Both
        # used to arrive here as PimPolicyNotFound, so every caller that suppresses the ordinary
        # not-onboarded case -- which is most groups in most tenants -- suppressed the refusal with
        # it, and a live 403 on 96 groups reached the operator as zero errors and a silently short
        # inventory. Two ids, so a caller can suppress one and surface the other.
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest { @{ value = @() } }
        Mock -ModuleName $script:moduleName Get-OERPimGroupPolicyId {
            throw [System.Management.Automation.ErrorRecord]::new(
                [System.Exception]::new('Authorization_RequestDenied: Insufficient privileges to complete the operation.'),
                'Authorization_RequestDenied',
                [System.Management.Automation.ErrorCategory]::PermissionDenied, 'gid-1')
        }
        $Err = $null
        Get-OERGroupPimPolicy -Id 'gid-1' -ErrorVariable Err -ErrorAction SilentlyContinue | Out-Null

        $Published = @($Err) | Where-Object {
            $PSItem.InvocationInfo -and $PSItem.InvocationInfo.MyCommand -and
            $PSItem.InvocationInfo.MyCommand.Name -eq 'Get-OERGroupPimPolicy'
        }
        @($Published).Count | Should -BeGreaterThan 0 -Because 'the caller has to be told the lookup failed'
        [string]@($Published)[0].FullyQualifiedErrorId |
            Should -Match 'PimPolicyReadFailed' -Because 'a lookup nobody was allowed to perform is not a group without a policy'
        [string]@($Published)[0].FullyQualifiedErrorId |
            Should -Not -Match 'PimPolicyNotFound' -Because 'collapsing the two ids is the defect itself'
        [string]@($Published)[0].Exception.Message | Should -Match 'Authorization_RequestDenied'
        Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 0 -Exactly `
            -Because 'there is no policy id to read rules from, so no rules request may be issued'
    }

    It 'accepts -Group by display name and resolves it via Resolve-OERGroupId' {
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {
            @{ value = @( @{ id = 'Expiration_EndUser_Assignment'; maximumDuration = 'PT8H' } ) }
        } -ParameterFilter { $Uri -match 'roleManagementPolicies/pol-1/rules' }
        Get-OERGroupPimPolicy -Group 'role_sec_admins' | Out-Null
        Should -Invoke -ModuleName $script:moduleName Resolve-OERGroupId -Times 1 -ParameterFilter { $DisplayName -eq 'role_sec_admins' }
    }

    It 'still binds the legacy -DisplayName alias' {
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {
            @{ value = @( @{ id = 'Expiration_EndUser_Assignment'; maximumDuration = 'PT8H' } ) }
        } -ParameterFilter { $Uri -match 'roleManagementPolicies/pol-1/rules' }
        Get-OERGroupPimPolicy -DisplayName 'role_sec_admins' | Out-Null
        Should -Invoke -ModuleName $script:moduleName Resolve-OERGroupId -Times 1 -ParameterFilter { $DisplayName -eq 'role_sec_admins' }
    }

    It 'binds the group id from the pipeline via the GroupId alias' {
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {
            @{ value = @( @{ id = 'Expiration_EndUser_Assignment'; maximumDuration = 'PT8H' } ) }
        } -ParameterFilter { $Uri -match 'roleManagementPolicies/pol-1/rules' }
        $Result = [pscustomobject]@{ GroupId = 'gid-1' } | Get-OERGroupPimPolicy
        $Result.PolicyId | Should -Be 'pol-1'
    }

    It 'binds -AccessType from the pipeline so a re-piped policy re-reads the same access type' {
        # Built from the REAL ConvertTo-OERGroupPimPolicy converter (matching the pattern used at
        # Set-OERGroupPimPolicy.Tests.ps1's "carries AccessType through a Get-to-Set pipe" test),
        # not a hand-rolled pscustomobject: a hand-rolled object still passes this test even if
        # ConvertTo-OERGroupPimPolicy ever stops emitting an AccessType property or renames it, which
        # would silently break the real Get-to-Get re-pipe this test claims to cover.
        Mock -ModuleName $script:moduleName Get-OERPimGroupPolicyId {
            param($GroupId, $AccessType)
            if ($AccessType -eq 'owner') { 'OWNER-POLICY' } else { 'MEMBER-POLICY' }
        }
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {
            @{ value = @( @{ id = 'Expiration_EndUser_Assignment'; maximumDuration = 'PT1H' } ) }
        }

        $Policy = InModuleScope $script:moduleName {
            ConvertTo-OERGroupPimPolicy -GroupId 'gid-1' -PolicyId 'OWNER-POLICY' -AccessType 'owner' -Rules @()
        }

        $Policy | Get-OERGroupPimPolicy | Out-Null

        Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 1 -Exactly `
            -ParameterFilter { $Uri -like '*roleManagementPolicies/OWNER-POLICY/rules*' }
    }

    It 'errors GroupNotFound when the group cannot be resolved' {
        Mock -ModuleName $script:moduleName Resolve-OERGroupId { $null }
        Get-OERGroupPimPolicy -Group 'nope' -ErrorVariable err -ErrorAction SilentlyContinue | Out-Null
        $err.FullyQualifiedErrorId | Should -Match 'GroupNotFound'
    }

    It 'gives an actionable GroupNotFound message' {
        Mock -ModuleName $script:moduleName Resolve-OERGroupId { $null }
        Get-OERGroupPimPolicy -Group 'ghost' -ErrorAction SilentlyContinue -ErrorVariable Err
        $Joined = @($Err).FullyQualifiedErrorId -join ';'
        $Joined | Should -Match 'GroupNotFound'
        $Text = @($Err).Exception.Message -join ' '
        $Text | Should -Match 'display name'
        $Text | Should -Match 'object id'
    }

    It 'surfaces enablement, permanence, parsed day counts, and notification recipients' {
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {
            @{ value = @(
                @{ id = 'Expiration_EndUser_Assignment'; maximumDuration = 'PT8H' }
                @{ id = 'Enablement_EndUser_Assignment'; enabledRules = @('Justification') }
                @{ id = 'AuthenticationContext_EndUser_Assignment'; claimValue = 'c1'; isEnabled = $true }
                @{ id = 'Expiration_Admin_Eligibility'; isExpirationRequired = $true; maximumDuration = 'P365D' }
                @{ id = 'Expiration_Admin_Assignment'; isExpirationRequired = $false; maximumDuration = 'P180D' }
                @{ id = 'Enablement_Admin_Assignment'; enabledRules = @('MultiFactorAuthentication', 'Justification') }
                @{ id = 'Notification_Admin_Admin_Eligibility'; notificationRecipients = @('person38@example.com') }
                @{ id = 'Notification_Admin_Admin_Assignment'; notificationRecipients = @('person39@example.com') }
                @{ id = 'Notification_Admin_EndUser_Assignment'; notificationRecipients = @('person40@example.com') }
            ) }
        } -ParameterFilter { $Uri -match 'roleManagementPolicies/pol-1/rules' }
        $R = Get-OERGroupPimPolicy -Id 'gid-1'
        $R.ActivationEnabledRules    | Should -Contain 'Justification'
        $R.AllowPermanentEligibility | Should -Be $false
        $R.EligibleDurationDays      | Should -Be 365
        $R.AllowPermanentActive      | Should -BeTrue
        $R.ActiveDurationDays        | Should -Be 180
        $R.ActiveEnabledRules        | Should -Contain 'MultiFactorAuthentication'
        $R.Notifications.EligibleAlert   | Should -Contain 'person38@example.com'
        $R.Notifications.ActiveAlert     | Should -Contain 'person39@example.com'
        $R.Notifications.ActivationAlert | Should -Contain 'person40@example.com'
    }

    It 'reports a null AuthenticationContextId when the auth-context rule is disabled' {
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {
            @{ value = @(
                @{ id = 'Expiration_EndUser_Assignment'; maximumDuration = 'PT8H' }
                @{ id = 'AuthenticationContext_EndUser_Assignment'; claimValue = ''; isEnabled = $false }
            ) }
        } -ParameterFilter { $Uri -match 'roleManagementPolicies/pol-1/rules' }
        (Get-OERGroupPimPolicy -Id 'gid-1').AuthenticationContextId | Should -BeNullOrEmpty
    }

    It 'reads the owner policy when -AccessType owner' {
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {
            @{ value = @( @{ id = 'Expiration_EndUser_Assignment'; maximumDuration = 'PT1H' } ) }
        } -ParameterFilter { $Uri -match 'roleManagementPolicies/pol-1/rules' }
        Get-OERGroupPimPolicy -Id 'gid-1' -AccessType owner | Out-Null
        Should -Invoke -ModuleName $script:moduleName Get-OERPimGroupPolicyId -Times 1 -ParameterFilter { $AccessType -eq 'owner' }
    }

    It 'returns genuinely empty arrays (not a one-element null array) when a canonical rule is missing' {
        # The tenant's policy rules array below carries no 'Enablement_EndUser_Assignment' and no
        # 'Notification_Admin_Admin_Eligibility' rule. Without a null-filter, @($NullVar.Property)
        # wraps the missing rule's $null property access into a ONE-element array containing $null,
        # not an empty array -- which would leak a stray null into the inventory/apply schema's
        # enum-typed arrays.
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {
            @{ value = @(
                @{ id = 'Expiration_EndUser_Assignment'; maximumDuration = 'PT8H' }
                @{ id = 'Notification_Admin_Admin_Assignment'; notificationRecipients = @('person39@example.com') }
                @{ id = 'Notification_Admin_EndUser_Assignment'; notificationRecipients = @('person40@example.com') }
            ) }
        } -ParameterFilter { $Uri -match 'roleManagementPolicies/pol-1/rules' }
        $R = Get-OERGroupPimPolicy -Id 'gid-1'
        @($R.ActivationEnabledRules).Count      | Should -Be 0
        @($R.Notifications.EligibleAlert).Count | Should -Be 0
    }

    It 'still emits the unchanged read shape after the converter extraction' {
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {
            @{ value = @( @{ id = 'Expiration_EndUser_Assignment'; maximumDuration = 'PT8H' } ) }
        } -ParameterFilter { $Uri -match 'roleManagementPolicies/pol-1/rules' }
        $Result = Get-OERGroupPimPolicy -Id 'gid-1'
        $Result.PSObject.TypeNames[0] | Should -Be 'Omnicit.EntraRBAC.GroupPimPolicy'
        @($Result.PSObject.Properties.Name) -join ',' | Should -Be 'GroupId,PolicyId,AccessType,ActivationMaxHours,AuthenticationContextId,ActivationEnabledRules,AllowPermanentEligibility,EligibleDuration,EligibleDurationDays,AllowPermanentActive,ActiveDuration,ActiveDurationDays,ActiveEnabledRules,RequireApproval,Approvers,Notifications,Rules'
    }

    Context 'paging (-All opt-in, Task 7 closes PR36 deliberately-not-fixed item 3)' {
        It 'passes -All to the beta rules read' {
            Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {
                @{ value = @( @{ id = 'Expiration_EndUser_Assignment'; maximumDuration = 'PT8H' } ) }
            } -ParameterFilter { $Uri -match 'roleManagementPolicies/pol-1/rules' }
            Get-OERGroupPimPolicy -Id 'gid-1' | Out-Null
            Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 1 -Exactly -ParameterFilter {
                $Uri -eq 'beta/policies/roleManagementPolicies/pol-1/rules' -and $All
            }
        }
    }
}
