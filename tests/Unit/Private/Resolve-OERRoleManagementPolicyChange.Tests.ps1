BeforeAll {
    Import-Module Omnicit.EntraRBAC -Force
}

Describe 'Resolve-OERRoleManagementPolicyChange' {
    BeforeEach {
        # Declared in BeforeEach (not the Describe body) so it survives the Pester v5 discovery/run
        # phase boundary -- a bare Describe-scope variable is $null inside the It at run time.
        $script:CurrentPolicy = [PSCustomObject]@{
            ActivationMaxHours                     = 8
            RequireMfaOnActivation                 = $false
            RequireJustificationOnActivation       = $true
            RequireTicketOnActivation              = $false
            RequireApproval                        = $false
            Approvers                              = @()
            AuthenticationContextId                = $null
            AllowPermanentEligibility              = $false
            EligibleDurationDays                   = 365
            AllowPermanentActiveAssignment         = $false
            ActiveDurationDays                     = 180
            RequireMfaOnActiveAssignment           = $false
            RequireJustificationOnActiveAssignment = $false
        }
    }

    It 'reports no change when every declared field already matches' {
        $Declared = [PSCustomObject]@{
            scope = '/s'; role = 'Contributor'
            activationMaxHours = 8; allowPermanentEligibility = $false
            requireJustificationOnActivation = $true; eligibleDurationDays = 365
        }
        InModuleScope Omnicit.EntraRBAC -Parameters @{ Declared = $Declared; Current = $script:CurrentPolicy } {
            param($Declared, $Current)
            $Change = Resolve-OERRoleManagementPolicyChange -Declared $Declared -Current $Current
            $Change.Changed | Should -Be $false
            $Change.SetParams            | Should -BeOfType [hashtable]
            $Change.SetParams.Keys.Count | Should -Be 0
        }
    }

    It 'never touches a field the document does not declare' {
        $Declared = [PSCustomObject]@{ scope = '/s'; role = 'Contributor'; activationMaxHours = 4 }
        InModuleScope Omnicit.EntraRBAC -Parameters @{ Declared = $Declared; Current = $script:CurrentPolicy } {
            param($Declared, $Current)
            $Change = Resolve-OERRoleManagementPolicyChange -Declared $Declared -Current $Current
            $Change.Changed | Should -Be $true
            @($Change.SetParams.Keys) | Should -Be @('ActivationMaxHours')
            $Change.SetParams.ActivationMaxHours | Should -Be 4
        }
    }

    It 'maps every supported field to its Set-OERRoleManagementPolicy parameter' {
        $Declared = [PSCustomObject]@{
            scope = '/s'; role = 'Contributor'
            allowPermanentEligibility = $true; eligibleDurationDays = 30
            allowPermanentActiveAssignment = $true; activeDurationDays = 60
            activationMaxHours = 2
            requireMfaOnActivation = $true
            requireJustificationOnActivation = $false
            requireTicketOnActivation = $true
            requireApproval = $true
            requireMfaOnActiveAssignment = $true
            requireJustificationOnActiveAssignment = $true
        }
        InModuleScope Omnicit.EntraRBAC -Parameters @{ Declared = $Declared; Current = $script:CurrentPolicy } {
            param($Declared, $Current)
            $P = (Resolve-OERRoleManagementPolicyChange -Declared $Declared -Current $Current).SetParams
            $P.AllowPermanentEligibility              | Should -Be $true
            $P.EligibleDuration                       | Should -Be 30
            $P.AllowPermanentActiveAssignment         | Should -Be $true
            $P.ActiveDuration                         | Should -Be 60
            $P.ActivationMaxHours                     | Should -Be 2
            $P.RequireMfaOnActivation                 | Should -Be $true
            $P.RequireJustificationOnActivation       | Should -Be $false
            $P.RequireTicketOnActivation               | Should -Be $true
            $P.RequireApproval                        | Should -Be $true
            $P.RequireMfaOnActiveAssignment           | Should -Be $true
            $P.RequireJustificationOnActiveAssignment | Should -Be $true
        }
    }

    It 'matches an approver declared by id against the live approver id' {
        $Current = $script:CurrentPolicy.PSObject.Copy()
        $Current.Approvers = @([PSCustomObject]@{ DisplayName = 'Sec Approvers'; Id = 'grp-1'; UserType = 'Group' })
        $Declared = [PSCustomObject]@{
            scope = '/s'; role = 'Contributor'
            approvers = [PSCustomObject]@{ groups = @('grp-1') }
        }
        InModuleScope Omnicit.EntraRBAC -Parameters @{ Declared = $Declared; Current = $Current } {
            param($Declared, $Current)
            (Resolve-OERRoleManagementPolicyChange -Declared $Declared -Current $Current).Changed |
                Should -Be $false
        }
    }

    It 'never matches a declared display name against a live approver id' {
        $Current = $script:CurrentPolicy.PSObject.Copy()
        $Current.Approvers = @([PSCustomObject]@{ DisplayName = 'Sec Approvers'; Id = 'grp-1'; UserType = 'Group' })
        $Declared = [PSCustomObject]@{
            scope = '/s'; role = 'Contributor'
            approvers = [PSCustomObject]@{ groups = @('sec approvers') }
        }
        InModuleScope Omnicit.EntraRBAC -Parameters @{ Declared = $Declared; Current = $Current } {
            param($Declared, $Current)
            (Resolve-OERRoleManagementPolicyChange -Declared $Declared -Current $Current).Changed |
                Should -Be $true
        }
    }

    It 'matches an approver id case-insensitively' {
        $Current = $script:CurrentPolicy.PSObject.Copy()
        $Current.Approvers = @([PSCustomObject]@{ DisplayName = 'Sec Approvers'; Id = 'grp-1'; UserType = 'Group' })
        $Declared = [PSCustomObject]@{
            scope = '/s'; role = 'Contributor'
            approvers = [PSCustomObject]@{ groups = @('GRP-1') }
        }
        InModuleScope Omnicit.EntraRBAC -Parameters @{ Declared = $Declared; Current = $Current } {
            param($Declared, $Current)
            (Resolve-OERRoleManagementPolicyChange -Declared $Declared -Current $Current).Changed |
                Should -Be $false
        }
    }

    It 'sends both approver lists together when either differs' {
        $Current = $script:CurrentPolicy.PSObject.Copy()
        $Current.Approvers = @([PSCustomObject]@{ DisplayName = 'Old'; Id = 'grp-old'; UserType = 'Group' })
        $Declared = [PSCustomObject]@{
            scope = '/s'; role = 'Contributor'
            approvers = [PSCustomObject]@{ users = @('anna@contoso.com'); groups = @('grp-new') }
        }
        InModuleScope Omnicit.EntraRBAC -Parameters @{ Declared = $Declared; Current = $Current } {
            param($Declared, $Current)
            $P = (Resolve-OERRoleManagementPolicyChange -Declared $Declared -Current $Current).SetParams
            @($P.ApproverUser)  | Should -Be @('anna@contoso.com')
            @($P.ApproverGroup) | Should -Be @('grp-new')
        }
    }

    It 'seeds the undeclared approver half from the live policy so it is not wiped' {
        $Current = $script:CurrentPolicy.PSObject.Copy()
        $Current.Approvers = @(
            [PSCustomObject]@{ DisplayName = 'Alice'; Id = 'user-alice'; UserType = 'User' }
            [PSCustomObject]@{ DisplayName = 'Old Group'; Id = 'grp-old'; UserType = 'Group' }
        )
        $Declared = [PSCustomObject]@{
            scope = '/s'; role = 'Contributor'
            approvers = [PSCustomObject]@{ groups = @('grp-new') }
        }
        InModuleScope Omnicit.EntraRBAC -Parameters @{ Declared = $Declared; Current = $Current } {
            param($Declared, $Current)
            $P = (Resolve-OERRoleManagementPolicyChange -Declared $Declared -Current $Current).SetParams
            @($P.ApproverUser)  | Should -Be @('user-alice')
            @($P.ApproverGroup) | Should -Be @('grp-new')
        }
    }

    It 'does not let one live approver satisfy two identical declared entries' {
        $Current = $script:CurrentPolicy.PSObject.Copy()
        $Current.Approvers = @(
            [PSCustomObject]@{ DisplayName = 'Grp One'; Id = 'grp-1'; UserType = 'Group' }
            [PSCustomObject]@{ DisplayName = 'Grp Two'; Id = 'grp-2'; UserType = 'Group' }
        )
        $Declared = [PSCustomObject]@{
            scope = '/s'; role = 'Contributor'
            approvers = [PSCustomObject]@{ groups = @('grp-1', 'grp-1') }
        }
        InModuleScope Omnicit.EntraRBAC -Parameters @{ Declared = $Declared; Current = $Current } {
            param($Declared, $Current)
            (Resolve-OERRoleManagementPolicyChange -Declared $Declared -Current $Current).Changed |
                Should -Be $true
        }
    }

    It 'treats a null current policy as everything-changed' {
        $Declared = [PSCustomObject]@{ scope = '/s'; role = 'Contributor'; activationMaxHours = 8 }
        InModuleScope Omnicit.EntraRBAC -Parameters @{ Declared = $Declared } {
            param($Declared)
            $Change = Resolve-OERRoleManagementPolicyChange -Declared $Declared -Current $null
            $Change.Changed | Should -Be $true
            $Change.SetParams.ActivationMaxHours | Should -Be 8
        }
    }

    It 'treats an empty declared authenticationContextId as a disable request' {
        $Current = $script:CurrentPolicy.PSObject.Copy()
        $Current.AuthenticationContextId = 'c1'
        $Declared = [PSCustomObject]@{ scope = '/s'; role = 'Contributor'; authenticationContextId = '' }
        InModuleScope Omnicit.EntraRBAC -Parameters @{ Declared = $Declared; Current = $Current } {
            param($Declared, $Current)
            $P = (Resolve-OERRoleManagementPolicyChange -Declared $Declared -Current $Current).SetParams
            $P.Keys | Should -Contain 'AuthenticationContextId'
            $P.AuthenticationContextId | Should -Be ''
        }
    }

    It 'tags the result object' {
        $Declared = [PSCustomObject]@{ scope = '/s'; role = 'R' }
        InModuleScope Omnicit.EntraRBAC -Parameters @{ Declared = $Declared; Current = $script:CurrentPolicy } {
            param($Declared, $Current)
            $Change = Resolve-OERRoleManagementPolicyChange -Declared $Declared -Current $Current
            $Change.PSObject.TypeNames[0] | Should -Be 'Omnicit.EntraRBAC.RoleManagementPolicyChange'
        }
    }
}

Describe 'Resolve-OERRoleManagementPolicyChange explicit JSON null' {
    BeforeEach {
        # A live policy with the security controls ON, so an explicit null that leaked through as a
        # declared value would visibly turn them OFF.
        $script:LivePolicy = [PSCustomObject]@{
            ActivationMaxHours                     = 8
            RequireMfaOnActivation                 = $true
            RequireJustificationOnActivation       = $true
            RequireTicketOnActivation              = $true
            RequireApproval                        = $true
            Approvers                              = @()
            AuthenticationContextId                = 'c1'
            AllowPermanentEligibility              = $false
            EligibleDurationDays                   = 365
            AllowPermanentActiveAssignment         = $false
            ActiveDurationDays                     = 180
            RequireMfaOnActiveAssignment           = $true
            RequireJustificationOnActiveAssignment = $true
        }
    }

    It 'treats an explicit null authenticationContextId as undeclared and leaves the live context alone' {
        $Declared = '{ "scope": "/s", "role": "Contributor", "authenticationContextId": null }' | ConvertFrom-Json
        InModuleScope Omnicit.EntraRBAC -Parameters @{ Declared = $Declared; Current = $script:LivePolicy } {
            param($Declared, $Current)
            $Change = Resolve-OERRoleManagementPolicyChange -Declared $Declared -Current $Current
            $Change.Changed | Should -Be $false
            @($Change.SetParams.Keys) | Should -Not -Contain 'AuthenticationContextId'
        }
    }

    It 'treats an explicit null requireMfaOnActivation as undeclared and does not disable MFA' {
        $Declared = '{ "scope": "/s", "role": "Contributor", "requireMfaOnActivation": null }' | ConvertFrom-Json
        InModuleScope Omnicit.EntraRBAC -Parameters @{ Declared = $Declared; Current = $script:LivePolicy } {
            param($Declared, $Current)
            $Change = Resolve-OERRoleManagementPolicyChange -Declared $Declared -Current $Current
            $Change.Changed | Should -Be $false
            @($Change.SetParams.Keys) | Should -Not -Contain 'RequireMfaOnActivation'
        }
    }

    It 'treats an explicit null on every remaining boolean toggle as undeclared' {
        $Json = '{ "scope": "/s", "role": "Contributor", "allowPermanentEligibility": null, ' +
                '"allowPermanentActiveAssignment": null, "requireJustificationOnActivation": null, ' +
                '"requireTicketOnActivation": null, "requireApproval": null, ' +
                '"requireMfaOnActiveAssignment": null, "requireJustificationOnActiveAssignment": null }'
        $Declared = $Json | ConvertFrom-Json
        InModuleScope Omnicit.EntraRBAC -Parameters @{ Declared = $Declared; Current = $script:LivePolicy } {
            param($Declared, $Current)
            $Change = Resolve-OERRoleManagementPolicyChange -Declared $Declared -Current $Current
            $Change.Changed | Should -Be $false
            $Change.SetParams            | Should -BeOfType [hashtable]
            $Change.SetParams.Keys.Count | Should -Be 0
        }
    }

    It 'treats an explicit null approvers half as undeclared and seeds it from the live policy' {
        $Current = $script:LivePolicy.PSObject.Copy()
        $Current.Approvers = @(
            [PSCustomObject]@{ DisplayName = 'Alice'; Id = 'user-alice'; UserType = 'User' }
            [PSCustomObject]@{ DisplayName = 'Old Group'; Id = 'grp-old'; UserType = 'Group' }
        )
        $Declared = '{ "scope": "/s", "role": "Contributor", "approvers": { "users": null, "groups": [ "grp-new" ] } }' | ConvertFrom-Json
        InModuleScope Omnicit.EntraRBAC -Parameters @{ Declared = $Declared; Current = $Current } {
            param($Declared, $Current)
            $P = (Resolve-OERRoleManagementPolicyChange -Declared $Declared -Current $Current).SetParams
            @($P.ApproverUser)  | Should -Be @('user-alice')
            @($P.ApproverGroup) | Should -Be @('grp-new')
        }
    }

    It 'still treats an empty string authenticationContextId as a declared disable' {
        $Declared = '{ "scope": "/s", "role": "Contributor", "authenticationContextId": "" }' | ConvertFrom-Json
        InModuleScope Omnicit.EntraRBAC -Parameters @{ Declared = $Declared; Current = $script:LivePolicy } {
            param($Declared, $Current)
            $P = (Resolve-OERRoleManagementPolicyChange -Declared $Declared -Current $Current).SetParams
            @($P.Keys) | Should -Contain 'AuthenticationContextId'
            $P.AuthenticationContextId | Should -BeExactly ''
        }
    }
}

Describe 'Resolve-OERRoleManagementPolicyChange null live property' {
    # Pins the behaviour when the LIVE policy could be read but one property could not be derived:
    # ConvertTo-OERRoleManagementPolicy leaves ActivationMaxHours null whenever the live
    # maximumDuration is not PT<n>H (for example PT30M), and AllowPermanentEligibility null whenever
    # the policy carries no Expiration_Admin_Eligibility rule.
    It 'writes a declared activationMaxHours when the live value could not be parsed' {
        $Current = [PSCustomObject]@{ ActivationMaxHours = $null; RequireMfaOnActivation = $false; Approvers = @() }
        $Declared = [PSCustomObject]@{ scope = '/s'; role = 'Contributor'; activationMaxHours = 8 }
        InModuleScope Omnicit.EntraRBAC -Parameters @{ Declared = $Declared; Current = $Current } {
            param($Declared, $Current)
            # Correct: the live window is provably NOT 8 hours (it is an unparseable, non-whole-hour
            # duration), so the declared value must be written. The next run reads back PT8H and is
            # idempotent from then on.
            $Change = Resolve-OERRoleManagementPolicyChange -Declared $Declared -Current $Current
            $Change.Changed | Should -Be $true
            $Change.SetParams.ActivationMaxHours | Should -Be 8
        }
    }

    It 'writes a declared allowPermanentEligibility when the live value is null' {
        $Current = [PSCustomObject]@{ AllowPermanentEligibility = $null; Approvers = @() }
        $Declared = [PSCustomObject]@{ scope = '/s'; role = 'Contributor'; allowPermanentEligibility = $false }
        InModuleScope Omnicit.EntraRBAC -Parameters @{ Declared = $Declared; Current = $Current } {
            param($Declared, $Current)
            # A null live property cannot be proven equal to the declared value, and PowerShell's
            # -ne $null is true for EVERY non-null left operand (including $false and 0), so the field
            # is written rather than silently dropped. Dropping it would be exactly the silent data
            # loss this branch closes.
            $Change = Resolve-OERRoleManagementPolicyChange -Declared $Declared -Current $Current
            $Change.Changed | Should -Be $true
            $Change.SetParams.AllowPermanentEligibility | Should -Be $false
        }
    }
}

Describe 'Resolve-OERRoleManagementPolicyChange approver precedence' {
    BeforeEach {
        $script:ApprovalPolicy = [PSCustomObject]@{
            RequireApproval = $true
            Approvers       = @([PSCustomObject]@{ DisplayName = 'Old Group'; Id = 'grp-old'; UserType = 'Group' })
        }
    }

    It 'drops the approver parameters when the document explicitly declares requireApproval false' {
        $Declared = '{ "scope": "/s", "role": "Contributor", "requireApproval": false, "approvers": { "groups": [ "grp-new" ] } }' | ConvertFrom-Json
        InModuleScope Omnicit.EntraRBAC -Parameters @{ Declared = $Declared; Current = $script:ApprovalPolicy } {
            param($Declared, $Current)
            $Change = Resolve-OERRoleManagementPolicyChange -Declared $Declared -Current $Current
            @($Change.SetParams.Keys) | Should -Not -Contain 'ApproverUser'
            @($Change.SetParams.Keys) | Should -Not -Contain 'ApproverGroup'
            $Change.SetParams.RequireApproval | Should -Be $false
        }
    }

    It 'records the dropped approvers in the Changes list' {
        $Declared = '{ "scope": "/s", "role": "Contributor", "requireApproval": false, "approvers": { "groups": [ "grp-new" ] } }' | ConvertFrom-Json
        InModuleScope Omnicit.EntraRBAC -Parameters @{ Declared = $Declared; Current = $script:ApprovalPolicy } {
            param($Declared, $Current)
            $Change = Resolve-OERRoleManagementPolicyChange -Declared $Declared -Current $Current
            ($Change.Changes -join '; ') | Should -Match 'approvers ignored'
            ($Change.Changes -join '; ') | Should -Match 'requireApproval'
        }
    }

    It 'still applies the approvers when requireApproval is declared true' {
        $Declared = '{ "scope": "/s", "role": "Contributor", "requireApproval": true, "approvers": { "groups": [ "grp-new" ] } }' | ConvertFrom-Json
        InModuleScope Omnicit.EntraRBAC -Parameters @{ Declared = $Declared; Current = $script:ApprovalPolicy } {
            param($Declared, $Current)
            $P = (Resolve-OERRoleManagementPolicyChange -Declared $Declared -Current $Current).SetParams
            @($P.ApproverGroup) | Should -Be @('grp-new')
        }
    }

    It 'still applies the approvers when the document does not declare requireApproval at all' {
        $Declared = '{ "scope": "/s", "role": "Contributor", "approvers": { "groups": [ "grp-new" ] } }' | ConvertFrom-Json
        InModuleScope Omnicit.EntraRBAC -Parameters @{ Declared = $Declared; Current = $script:ApprovalPolicy } {
            param($Declared, $Current)
            $P = (Resolve-OERRoleManagementPolicyChange -Declared $Declared -Current $Current).SetParams
            @($P.ApproverGroup) | Should -Be @('grp-new')
        }
    }
}
