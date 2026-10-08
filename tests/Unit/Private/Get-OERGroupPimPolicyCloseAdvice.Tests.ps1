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

Describe 'Get-OERGroupPimPolicyCloseAdvice' {
    # The single owner of the close advice Add-OERGroupEligibility (PolicyOpenedButGrantFailed and
    # EligibilityRequestFailed) and Sync-OERStructureGroup (GroupNotOnboarded) give for a group's
    # PIM-for-groups policy that was opened to allow permanent eligibility. The command sits inside ONE
    # single-quoted PowerShell string literal, so the group id's quotes are doubled in the text.

    It 'returns the close advice for <AccessType> access, the group id''s quotes doubled' -ForEach @(
        @{ AccessType = 'member' }
        @{ AccessType = 'owner' }
    ) {
        $Advice = InModuleScope $script:moduleName -Parameters @{ AccessType = $AccessType } {
            param($AccessType)
            Get-OERGroupPimPolicyCloseAdvice -GroupId 'g-1' -AccessType $AccessType
        }
        @($Advice).Count | Should -Be 1
        $Advice | Should -BeOfType [string]
        $Advice | Should -BeExactly ("close it with 'Set-OERGroupPimPolicy -Group ''g-1'' -AccessType $AccessType " +
            '-AllowPermanentEligibility:$false'' if you do not intend to retry.')
    }

    It 'refuses an access type other than member or owner' {
        # Caught inside the module scope: InModuleScope re-labels a record that leaves it.
        $Refusal = InModuleScope $script:moduleName {
            try {
                $null = Get-OERGroupPimPolicyCloseAdvice -GroupId 'g-1' -AccessType 'guest'
                $null
            } catch {
                $PSItem
            }
        }
        $Refusal | Should -Not -BeNullOrEmpty
        $Refusal.FullyQualifiedErrorId | Should -BeExactly 'ParameterArgumentValidationError,Get-OERGroupPimPolicyCloseAdvice'
    }

    Context 'the advice is held to what it does (Ruling R1)' {
        # The advice used to name 'Set-OERGroupPimPolicy -Group G -AccessType A -ActivationMaxHours <n>'
        # (without -AllowPermanentEligibility). Set-OERGroupPimPolicy patches Expiration_Admin_Eligibility
        # only when -EligibleDuration or -AllowPermanentEligibility is BOUND, so that command never
        # touched the rule that was opened. These tests take the command OUT of the helper's own output
        # -- not retyped -- run it against the real Set-OERGroupPimPolicy with its transport mocked, and
        # read what it would send.
        BeforeAll {
            # The text between 'close it with ' and ' if you do not intend to retry.' must be ONE
            # single-quoted PowerShell string literal; the parser, not a regex, reads its value (and so
            # turns each doubled quote back into one).
            function Get-TestAdviceCommand ([string]$Advice) {
                $Prefix = 'close it with '
                $Suffix = ' if you do not intend to retry.'
                $Advice.StartsWith($Prefix, [System.StringComparison]::Ordinal) | Should -BeTrue -Because "the advice starts with '$Prefix'"
                $Advice.EndsWith($Suffix, [System.StringComparison]::Ordinal) | Should -BeTrue -Because "the advice ends with '$Suffix'"
                $Literal = $Advice.Substring($Prefix.Length, $Advice.Length - $Prefix.Length - $Suffix.Length)
                $Tokens = $null
                $ParseErrors = $null
                $null = [System.Management.Automation.Language.Parser]::ParseInput($Literal, [ref]$Tokens, [ref]$ParseErrors)
                @($ParseErrors).Count | Should -Be 0 -Because "the command in the advice ($Literal) parses"
                # One single-quoted string literal and the end of the input, nothing else.
                @($Tokens).Count | Should -Be 2 -Because "the command in the advice ($Literal) is one string literal"
                $Tokens[0].Kind | Should -Be ([System.Management.Automation.Language.TokenKind]::StringLiteral)
                $Tokens[0].Extent.Text | Should -BeExactly $Literal
                $Tokens[1].Kind | Should -Be ([System.Management.Automation.Language.TokenKind]::EndOfInput)
                [string]$Tokens[0].Value
            }
        }

        BeforeEach {
            InModuleScope $script:moduleName { $script:_OERAuthState = $null }
            Mock -ModuleName $script:moduleName Initialize-OERAuth { }
            Mock -ModuleName $script:moduleName Resolve-OERGroupId { 'g-1' }
            Mock -ModuleName $script:moduleName Get-OERPimGroupPolicyId { 'pol-1' }
            # The live eligibility-expiration rule of a policy left open: permanent eligibility allowed,
            # a 180-day maximum kept for time-bound grants.
            Mock -ModuleName $script:moduleName Invoke-OERGraphRequest -ParameterFilter { $Uri -like '*/Expiration_Admin_Eligibility' -and $Method -ne 'PATCH' } {
                [PSCustomObject]@{ id = 'Expiration_Admin_Eligibility'; isExpirationRequired = $false; maximumDuration = 'P180D' }
            }
            Mock -ModuleName $script:moduleName Invoke-OERGraphRequest -ParameterFilter { $Method -eq 'PATCH' } { }
        }

        It 'closes the policy: the advice''s own command PATCHes Expiration_Admin_Eligibility with isExpirationRequired true and the live maximumDuration' {
            $Advice = InModuleScope $script:moduleName { Get-OERGroupPimPolicyCloseAdvice -GroupId 'g-1' -AccessType 'member' }
            $Command = Get-TestAdviceCommand -Advice $Advice
            $Command | Should -BeExactly 'Set-OERGroupPimPolicy -Group ''g-1'' -AccessType member -AllowPermanentEligibility:$false'
            $Result = & ([scriptblock]::Create($Command + ' -Confirm:$false'))
            Should -Invoke -ModuleName $script:moduleName Resolve-OERGroupId -Times 1 -Exactly -ParameterFilter { $DisplayName -ceq 'g-1' }
            Should -Invoke -ModuleName $script:moduleName Get-OERPimGroupPolicyId -Times 1 -Exactly -ParameterFilter { $GroupId -eq 'g-1' -and $AccessType -eq 'member' }
            # The live rule is read so its maximum is carried, not replaced by the parameter default.
            Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 1 -Exactly -ParameterFilter {
                $Uri -like '*/Expiration_Admin_Eligibility' -and $Method -ne 'PATCH'
            }
            Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 1 -Exactly -ParameterFilter {
                $Method -eq 'PATCH' -and $Uri -like '*policies/roleManagementPolicies/pol-1/rules/Expiration_Admin_Eligibility' -and
                $Body.isExpirationRequired -is [bool] -and $Body.isExpirationRequired -and
                $Body.maximumDuration -ceq 'P180D'
            }
            # That one rule and nothing else: the activation rule is left as it is.
            Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 1 -Exactly -ParameterFilter { $Method -eq 'PATCH' }
            Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 0 -ParameterFilter {
                $Method -eq 'PATCH' -and $Uri -like '*Expiration_EndUser_Assignment*'
            }
            $Result.Applied | Should -BeTrue
            $Result.AllowPermanentEligibility | Should -BeFalse
        }

        It 'the record of why the text changed: the OLD advice (-ActivationMaxHours, no switch) sends no Expiration_Admin_Eligibility rule' {
            # The old advice's command with '<n>' given a value, quoted exactly as the old text quoted it.
            $OldAdvice = "close it with 'Set-OERGroupPimPolicy -Group ''g-1'' -AccessType member -ActivationMaxHours 8' if you do not intend to retry."
            $Command = Get-TestAdviceCommand -Advice $OldAdvice
            $Result = & ([scriptblock]::Create($Command + ' -Confirm:$false'))
            # Only the activation rule is patched; the rule that was opened is neither read nor sent, so
            # the policy still allows permanent eligibility afterwards.
            Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 1 -Exactly -ParameterFilter { $Method -eq 'PATCH' }
            Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 1 -Exactly -ParameterFilter {
                $Method -eq 'PATCH' -and $Uri -like '*/Expiration_EndUser_Assignment'
            }
            Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 0 -ParameterFilter { $Uri -like '*Expiration_Admin_Eligibility*' }
            $Result.Applied | Should -BeTrue
            $Result.PSObject.Properties.Name | Should -Not -Contain 'AllowPermanentEligibility'
        }
    }
}
