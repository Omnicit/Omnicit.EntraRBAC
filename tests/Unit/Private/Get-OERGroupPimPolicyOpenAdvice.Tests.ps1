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

Describe 'Get-OERGroupPimPolicyOpenAdvice' {
    # The single owner of the open advice Add-OERGroupEligibility gives in PolicyOpenFailed for a group's
    # PIM-for-groups policy it could not open to allow permanent eligibility. The command sits inside ONE
    # single-quoted PowerShell string literal, so the group id's quotes are doubled in the text.

    It 'returns the open advice for <AccessType> access, the group id''s quotes doubled' -ForEach @(
        @{ AccessType = 'member' }
        @{ AccessType = 'owner' }
    ) {
        $Advice = InModuleScope $script:moduleName -Parameters @{ AccessType = $AccessType } {
            param($AccessType)
            Get-OERGroupPimPolicyOpenAdvice -GroupId 'g-1' -AccessType $AccessType
        }
        @($Advice).Count | Should -Be 1
        $Advice | Should -BeOfType [string]
        $Advice | Should -BeExactly ("Run 'Set-OERGroupPimPolicy -Group ''g-1'' -AccessType $AccessType " +
            '-AllowPermanentEligibility'' with sufficient permissions, or grant a time-bound eligibility with -DurationDays.')
    }

    It 'refuses an access type other than member or owner' {
        # Caught inside the module scope: InModuleScope re-labels a record that leaves it.
        $Refusal = InModuleScope $script:moduleName {
            try {
                $null = Get-OERGroupPimPolicyOpenAdvice -GroupId 'g-1' -AccessType 'guest'
                $null
            } catch {
                $PSItem
            }
        }
        $Refusal | Should -Not -BeNullOrEmpty
        $Refusal.FullyQualifiedErrorId | Should -BeExactly 'ParameterArgumentValidationError,Get-OERGroupPimPolicyOpenAdvice'
    }

    Context 'the advice is held to what it does' {
        # The advice used to name 'Set-OERGroupPimPolicy -Group G -AccessType A -ActivationMaxHours <n>
        # -AllowPermanentEligibility'. As typed that does not parse ('<' is reserved), and with a value in
        # place of '<n>' it also rewrote the activation maximum, which the open does not need. These tests
        # take the command OUT of the helper's own output -- not retyped -- run it against the real
        # Set-OERGroupPimPolicy with its transport mocked, and read what it would send.
        BeforeAll {
            # The text between 'Run ' and ' with sufficient permissions, or grant a time-bound
            # eligibility with -DurationDays.' must be ONE single-quoted PowerShell string literal; the
            # parser, not a regex, reads its value (and so turns each doubled quote back into one).
            function Get-TestAdviceCommand ([string]$Advice) {
                $Prefix = 'Run '
                $Suffix = ' with sufficient permissions, or grant a time-bound eligibility with -DurationDays.'
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
            # The live eligibility-expiration rule of a policy that is closed: an expiration is required
            # and the maximum for a time-bound grant is 180 days.
            Mock -ModuleName $script:moduleName Invoke-OERGraphRequest -ParameterFilter { $Uri -like '*/Expiration_Admin_Eligibility' -and $Method -ne 'PATCH' } {
                [PSCustomObject]@{ id = 'Expiration_Admin_Eligibility'; isExpirationRequired = $true; maximumDuration = 'P180D' }
            }
            Mock -ModuleName $script:moduleName Invoke-OERGraphRequest -ParameterFilter { $Method -eq 'PATCH' } { }
        }

        It 'opens the policy: the advice''s own command PATCHes Expiration_Admin_Eligibility with isExpirationRequired false and leaves the activation maximum alone' {
            $Advice = InModuleScope $script:moduleName { Get-OERGroupPimPolicyOpenAdvice -GroupId 'g-1' -AccessType 'member' }
            $Command = Get-TestAdviceCommand -Advice $Advice
            $Command | Should -BeExactly 'Set-OERGroupPimPolicy -Group ''g-1'' -AccessType member -AllowPermanentEligibility'
            $Result = & ([scriptblock]::Create($Command + ' -Confirm:$false'))
            Should -Invoke -ModuleName $script:moduleName Resolve-OERGroupId -Times 1 -Exactly -ParameterFilter { $DisplayName -ceq 'g-1' }
            Should -Invoke -ModuleName $script:moduleName Get-OERPimGroupPolicyId -Times 1 -Exactly -ParameterFilter { $GroupId -eq 'g-1' -and $AccessType -eq 'member' }
            # The live rule is read so its maximum is carried, not replaced by the parameter default.
            Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 1 -Exactly -ParameterFilter {
                $Uri -like '*/Expiration_Admin_Eligibility' -and $Method -ne 'PATCH'
            }
            Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 1 -Exactly -ParameterFilter {
                $Method -eq 'PATCH' -and $Uri -like '*policies/roleManagementPolicies/pol-1/rules/Expiration_Admin_Eligibility' -and
                $Body.isExpirationRequired -is [bool] -and -not $Body.isExpirationRequired -and
                $Body.maximumDuration -ceq 'P180D'
            }
            # That one rule and nothing else: the activation rule is left as it is.
            Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 1 -Exactly -ParameterFilter { $Method -eq 'PATCH' }
            Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 0 -ParameterFilter {
                $Method -eq 'PATCH' -and $Uri -like '*Expiration_EndUser_Assignment*'
            }
            $Result.Applied | Should -BeTrue
            $Result.AllowPermanentEligibility | Should -BeTrue
        }

        It 'carries the owner access type into the command the same way' {
            $Advice = InModuleScope $script:moduleName { Get-OERGroupPimPolicyOpenAdvice -GroupId 'g-1' -AccessType 'owner' }
            $Command = Get-TestAdviceCommand -Advice $Advice
            $Command | Should -BeExactly 'Set-OERGroupPimPolicy -Group ''g-1'' -AccessType owner -AllowPermanentEligibility'
            $Result = & ([scriptblock]::Create($Command + ' -Confirm:$false'))
            Should -Invoke -ModuleName $script:moduleName Get-OERPimGroupPolicyId -Times 1 -Exactly -ParameterFilter { $GroupId -eq 'g-1' -and $AccessType -eq 'owner' }
            Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 1 -Exactly -ParameterFilter {
                $Method -eq 'PATCH' -and $Uri -like '*policies/roleManagementPolicies/pol-1/rules/Expiration_Admin_Eligibility' -and
                $Body.isExpirationRequired -is [bool] -and -not $Body.isExpirationRequired
            }
            Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 1 -Exactly -ParameterFilter { $Method -eq 'PATCH' }
            $Result.AllowPermanentEligibility | Should -BeTrue
        }

        It 'the record of why the text changed: the OLD advice, as written, does not parse (the less-than sign is reserved)' {
            $OldAdvice = "Run 'Set-OERGroupPimPolicy -Group ''g-1'' -AccessType member -ActivationMaxHours <n> -AllowPermanentEligibility' with sufficient permissions, or grant a time-bound eligibility with -DurationDays."
            $OldCommand = Get-TestAdviceCommand -Advice $OldAdvice
            $OldCommand | Should -BeExactly 'Set-OERGroupPimPolicy -Group ''g-1'' -AccessType member -ActivationMaxHours <n> -AllowPermanentEligibility'
            $Tokens = $null
            $ParseErrors = $null
            $null = [System.Management.Automation.Language.Parser]::ParseInput($OldCommand, [ref]$Tokens, [ref]$ParseErrors)
            @($ParseErrors).Count | Should -Be 1
            $ParseErrors[0].ErrorId | Should -BeExactly 'RedirectionNotSupported'
        }

        It 'the record of why the text changed: the OLD command with <n> given a value also rewrites the activation maximum' {
            $OldAdvice = "Run 'Set-OERGroupPimPolicy -Group ''g-1'' -AccessType member -ActivationMaxHours <n> -AllowPermanentEligibility' with sufficient permissions, or grant a time-bound eligibility with -DurationDays."
            $OldCommand = Get-TestAdviceCommand -Advice $OldAdvice
            $Filled = $OldCommand.Replace('<n>', '8')
            $Filled | Should -BeExactly 'Set-OERGroupPimPolicy -Group ''g-1'' -AccessType member -ActivationMaxHours 8 -AllowPermanentEligibility'
            $Result = & ([scriptblock]::Create($Filled + ' -Confirm:$false'))
            # It opens the policy, but sends the activation rule too: the operator is made to rewrite a
            # maximum the open does not need.
            Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 1 -Exactly -ParameterFilter {
                $Method -eq 'PATCH' -and $Uri -like '*/Expiration_Admin_Eligibility' -and
                $Body.isExpirationRequired -is [bool] -and -not $Body.isExpirationRequired
            }
            Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 1 -Exactly -ParameterFilter {
                $Method -eq 'PATCH' -and $Uri -like '*/Expiration_EndUser_Assignment'
            }
            Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 2 -Exactly -ParameterFilter { $Method -eq 'PATCH' }
            $Result.Applied | Should -BeTrue
            $Result.ActivationMaxHours | Should -Be 8
        }
    }
}
