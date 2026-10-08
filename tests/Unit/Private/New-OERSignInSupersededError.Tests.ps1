BeforeAll {
    Import-Module Omnicit.EntraRBAC -Force
    . "$PSScriptRoot/../TestHelpers/OERTransportTripwire.ps1"
    Install-OERTransportTripwire
}

AfterAll {
    try { Assert-OERTransportTripwire } finally { Uninstall-OERTransportTripwire }
}

Describe 'New-OERSignInSupersededError' {
    BeforeAll {
        # Builds a record while the module holds a state with a tenant (-WithState) or no state at all,
        # and puts back the state it found, whatever the build does. BL-92: the text depends on whether
        # the module still holds a session, so every variant is built under the state it names.
        function script:New-SupersededProbe {
            param([string]$Command, [bool]$Document, [bool]$WithState)
            InModuleScope Omnicit.EntraRBAC -Parameters @{ C = $Command; D = $Document; S = $WithState } {
                param($C, $D, $S)
                $Found = $script:_OERAuthState
                try {
                    $script:_OERAuthState = if ($S) {
                        @{
                            TenantId    = '11111111-1111-1111-1111-111111111111'
                            AuthMethod  = 'Interactive'
                            ClientId    = '33333333-3333-3333-3333-333333333333'
                            Environment = 'Global'
                        }
                    } else {
                        $null
                    }
                    New-OERSignInSupersededError -Command $C -Document:$D
                } finally {
                    $script:_OERAuthState = $Found
                }
            }
        }
        # The four texts by cause, with the command's name as a marker the tests replace, so a text is
        # written once here and never rebuilt with the module's own format string.
        $script:RequestIdentityText = 'Another OER command in the same pipeline signed in to a different tenant or identity after @@NAME@@ ' +
            'began, so Omnicit.EntraRBAC sends nothing while @@NAME@@ runs: this request was not sent. Run ' +
            'the commands as separate statements, so that each one signs in and finishes before the next one starts.'
        $script:RequestEndedText = "Disconnect-OER ended the module's session after @@NAME@@ began, so Omnicit.EntraRBAC sends nothing " +
            'while @@NAME@@ runs: this request was not sent. Run Disconnect-OER as a statement of its own, after the ' +
            'commands that use the session.'
        $script:DocumentIdentityText = 'Another OER command in the same pipeline signed in to a different tenant or identity after @@NAME@@ ' +
            'began, so @@NAME@@ did not apply this document and Omnicit.EntraRBAC sent nothing for it. Run the ' +
            'commands as separate statements, so that each one signs in and finishes before the next one starts.'
        $script:DocumentEndedText = "Disconnect-OER ended the module's session after @@NAME@@ began, so @@NAME@@ did not apply this " +
            'document and Omnicit.EntraRBAC sent nothing for it. Run Disconnect-OER as a statement of its own, ' +
            'after the commands that use the session.'

        # Built while the module holds a state with a tenant, so the message can be shown not to carry it.
        $script:Record = New-SupersededProbe -Command 'New-OERGroup' -Document $false -WithState $true
        $script:EndedRecord = New-SupersededProbe -Command 'New-OERGroup' -Document $false -WithState $false
        $script:DocumentRecord = New-SupersededProbe -Command 'Invoke-OERStructure' -Document $true -WithState $true
        $script:DocumentEndedRecord = New-SupersededProbe -Command 'Invoke-OERStructure' -Document $true -WithState $false
    }

    It 'returns an ErrorRecord' {
        $script:Record | Should -BeOfType ([System.Management.Automation.ErrorRecord])
    }

    It 'carries the id SignInSuperseded' {
        $script:Record.FullyQualifiedErrorId | Should -BeExactly 'SignInSuperseded'
    }

    It 'carries the category AuthenticationError' {
        $script:Record.CategoryInfo.Category | Should -Be ([System.Management.Automation.ErrorCategory]::AuthenticationError)
    }

    It 'targets the superseded command' {
        $script:Record.TargetObject | Should -BeOfType ([string])
        $script:Record.TargetObject | Should -BeExactly 'New-OERGroup'
    }

    It 'carries the exact message, naming the command it targets' {
        $script:Record.Exception | Should -BeOfType ([System.Exception])
        $script:Record.Exception.Message | Should -BeExactly (
            'Another OER command in the same pipeline signed in to a different tenant or identity after New-OERGroup ' +
            'began, so Omnicit.EntraRBAC sends nothing while New-OERGroup runs: this request was not sent. Run ' +
            'the commands as separate statements, so that each one signs in and finishes before the next one starts.')
    }

    It 'names no tenant in its message' {
        # The name passed holds no tenant, so a tenant in the text could only come from the state.
        $script:Record.TargetObject | Should -Not -Match '11111111-1111-1111-1111-111111111111'
        $script:Record.Exception.Message | Should -Not -Match '11111111-1111-1111-1111-111111111111'
        $script:Record.ToString() | Should -Not -Match '11111111-1111-1111-1111-111111111111'
    }

    It 'names the command it targets exactly as passed, and changes nothing else in the message' {
        $Other = New-SupersededProbe -Command 'a script block' -Document $false -WithState $true
        $Other.TargetObject | Should -BeExactly 'a script block'
        $Other.Exception.Message | Should -BeExactly (
            'Another OER command in the same pipeline signed in to a different tenant or identity after a script block ' +
            'began, so Omnicit.EntraRBAC sends nothing while a script block runs: this request was not sent. Run ' +
            'the commands as separate statements, so that each one signs in and finishes before the next one starts.')
        # The name is the only value in the text: with each name taken out, the two messages are one.
        $Other.Exception.Message.Replace('a script block', '#') |
            Should -BeExactly $script:Record.Exception.Message.Replace('New-OERGroup', '#')
    }

    It 'writes a name that holds a format item as it is' {
        $Braced = New-SupersededProbe -Command 'Invoke-{0}Probe' -Document $false -WithState $true
        $Braced.TargetObject | Should -BeExactly 'Invoke-{0}Probe'
        $Braced.Exception.Message | Should -BeLike '*after Invoke-{0}Probe began,*while Invoke-{0}Probe runs:*'
    }

    It 'requires the command it targets' {
        $Parameter = InModuleScope Omnicit.EntraRBAC { (Get-Command New-OERSignInSupersededError).Parameters['Command'] }
        $Parameter.ParameterType | Should -Be ([string])
        @($Parameter.Attributes | Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] -and $_.Mandatory }).Count |
            Should -Be 1
    }

    It 'declares -Document as an optional switch' {
        $Parameter = InModuleScope Omnicit.EntraRBAC { (Get-Command New-OERSignInSupersededError).Parameters['Document'] }
        $Parameter.ParameterType | Should -Be ([switch])
        @($Parameter.Attributes | Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] -and $_.Mandatory }).Count |
            Should -Be 0
    }

    Context 'after Disconnect-OER ended the session, for a request (BL-92)' {
        It 'carries the same id, category and target' {
            $script:EndedRecord | Should -BeOfType ([System.Management.Automation.ErrorRecord])
            $script:EndedRecord.FullyQualifiedErrorId | Should -BeExactly 'SignInSuperseded'
            $script:EndedRecord.CategoryInfo.Category | Should -Be ([System.Management.Automation.ErrorCategory]::AuthenticationError)
            $script:EndedRecord.TargetObject | Should -BeOfType ([string])
            $script:EndedRecord.TargetObject | Should -BeExactly 'New-OERGroup'
        }

        It 'carries the exact message, saying Disconnect-OER ended the session' {
            $script:EndedRecord.Exception | Should -BeOfType ([System.Exception])
            $script:EndedRecord.Exception.Message | Should -BeExactly (
                "Disconnect-OER ended the module's session after New-OERGroup began, so Omnicit.EntraRBAC sends nothing " +
                'while New-OERGroup runs: this request was not sent. Run Disconnect-OER as a statement of its own, after ' +
                'the commands that use the session.')
        }

        It 'does not speak of another sign-in' {
            $script:EndedRecord.Exception.Message | Should -Not -Match 'signed in'
            $script:EndedRecord.Exception.Message | Should -Not -Match 'different tenant'
        }

        It 'carries the name as the only value in the text, written as passed' {
            $Other = New-SupersededProbe -Command 'a script block' -Document $false -WithState $false
            $Other.TargetObject | Should -BeExactly 'a script block'
            $Other.Exception.Message | Should -BeExactly $script:RequestEndedText.Replace('@@NAME@@', 'a script block')
            $Other.Exception.Message.Replace('a script block', '#') |
                Should -BeExactly $script:EndedRecord.Exception.Message.Replace('New-OERGroup', '#')
            $Braced = New-SupersededProbe -Command 'Invoke-{0}Probe' -Document $false -WithState $false
            $Braced.TargetObject | Should -BeExactly 'Invoke-{0}Probe'
            $Braced.Exception.Message | Should -BeExactly $script:RequestEndedText.Replace('@@NAME@@', 'Invoke-{0}Probe')
        }
    }

    Context 'with -Document, for a session another sign-in replaced (BL-92)' {
        It 'carries the same id, category and target' {
            $script:DocumentRecord | Should -BeOfType ([System.Management.Automation.ErrorRecord])
            $script:DocumentRecord.FullyQualifiedErrorId | Should -BeExactly 'SignInSuperseded'
            $script:DocumentRecord.CategoryInfo.Category | Should -Be ([System.Management.Automation.ErrorCategory]::AuthenticationError)
            $script:DocumentRecord.TargetObject | Should -BeOfType ([string])
            $script:DocumentRecord.TargetObject | Should -BeExactly 'Invoke-OERStructure'
        }

        It 'carries the exact message, saying the document was not applied' {
            $script:DocumentRecord.Exception | Should -BeOfType ([System.Exception])
            $script:DocumentRecord.Exception.Message | Should -BeExactly (
                'Another OER command in the same pipeline signed in to a different tenant or identity after Invoke-OERStructure ' +
                'began, so Invoke-OERStructure did not apply this document and Omnicit.EntraRBAC sent nothing for it. Run the ' +
                'commands as separate statements, so that each one signs in and finishes before the next one starts.')
        }

        It 'does not say that a request was not sent' {
            $script:DocumentRecord.Exception.Message | Should -Not -Match 'this request'
            $script:DocumentRecord.Exception.Message | Should -Not -Match 'while Invoke-OERStructure runs'
        }

        It 'carries the name as the only value in the text, written as passed' {
            $Other = New-SupersededProbe -Command 'a script block' -Document $true -WithState $true
            $Other.TargetObject | Should -BeExactly 'a script block'
            $Other.Exception.Message | Should -BeExactly $script:DocumentIdentityText.Replace('@@NAME@@', 'a script block')
            $Other.Exception.Message.Replace('a script block', '#') |
                Should -BeExactly $script:DocumentRecord.Exception.Message.Replace('Invoke-OERStructure', '#')
            $Braced = New-SupersededProbe -Command 'Invoke-{0}Probe' -Document $true -WithState $true
            $Braced.TargetObject | Should -BeExactly 'Invoke-{0}Probe'
            $Braced.Exception.Message | Should -BeExactly $script:DocumentIdentityText.Replace('@@NAME@@', 'Invoke-{0}Probe')
        }
    }

    Context 'with -Document, after Disconnect-OER ended the session (BL-92)' {
        It 'carries the same id, category and target' {
            $script:DocumentEndedRecord | Should -BeOfType ([System.Management.Automation.ErrorRecord])
            $script:DocumentEndedRecord.FullyQualifiedErrorId | Should -BeExactly 'SignInSuperseded'
            $script:DocumentEndedRecord.CategoryInfo.Category | Should -Be ([System.Management.Automation.ErrorCategory]::AuthenticationError)
            $script:DocumentEndedRecord.TargetObject | Should -BeOfType ([string])
            $script:DocumentEndedRecord.TargetObject | Should -BeExactly 'Invoke-OERStructure'
        }

        It 'carries the exact message, saying Disconnect-OER ended the session and the document was not applied' {
            $script:DocumentEndedRecord.Exception | Should -BeOfType ([System.Exception])
            $script:DocumentEndedRecord.Exception.Message | Should -BeExactly (
                "Disconnect-OER ended the module's session after Invoke-OERStructure began, so Invoke-OERStructure did not " +
                'apply this document and Omnicit.EntraRBAC sent nothing for it. Run Disconnect-OER as a statement of its own, ' +
                'after the commands that use the session.')
        }

        It 'carries the name as the only value in the text, written as passed' {
            $Other = New-SupersededProbe -Command 'a script block' -Document $true -WithState $false
            $Other.TargetObject | Should -BeExactly 'a script block'
            $Other.Exception.Message | Should -BeExactly $script:DocumentEndedText.Replace('@@NAME@@', 'a script block')
            $Other.Exception.Message.Replace('a script block', '#') |
                Should -BeExactly $script:DocumentEndedRecord.Exception.Message.Replace('Invoke-OERStructure', '#')
            $Braced = New-SupersededProbe -Command 'Invoke-{0}Probe' -Document $true -WithState $false
            $Braced.TargetObject | Should -BeExactly 'Invoke-{0}Probe'
            $Braced.Exception.Message | Should -BeExactly $script:DocumentEndedText.Replace('@@NAME@@', 'Invoke-{0}Probe')
        }
    }

    Context 'the text is chosen by the state alone' {
        It 'reads a held session of any shape as a session another sign-in replaced, and only no state as ended' {
            # Get-OERSignInIdentity reads $null as not signed in and nothing else; the text follows the same test.
            $Message = InModuleScope Omnicit.EntraRBAC {
                $Found = $script:_OERAuthState
                try {
                    $script:_OERAuthState = @{}
                    (New-OERSignInSupersededError -Command 'New-OERGroup').Exception.Message
                } finally {
                    $script:_OERAuthState = $Found
                }
            }
            $Message | Should -BeExactly $script:RequestIdentityText.Replace('@@NAME@@', 'New-OERGroup')
        }

        It 'puts back the state it found, a session or none' {
            $Same = InModuleScope Omnicit.EntraRBAC {
                $Found = $script:_OERAuthState
                $Held = @{ TenantId = '11111111-1111-1111-1111-111111111111' }
                try {
                    $script:_OERAuthState = $Held
                    $null = New-OERSignInSupersededError -Command 'New-OERGroup' -Document
                    $HeldKept = [object]::ReferenceEquals($script:_OERAuthState, $Held)
                    $script:_OERAuthState = $null
                    $null = New-OERSignInSupersededError -Command 'New-OERGroup'
                    [PSCustomObject]@{ HeldKept = $HeldKept; NoneKept = ($null -eq $script:_OERAuthState) }
                } finally {
                    $script:_OERAuthState = $Found
                }
            }
            $Same.HeldKept | Should -BeTrue
            $Same.NoneKept | Should -BeTrue
        }
    }
}
