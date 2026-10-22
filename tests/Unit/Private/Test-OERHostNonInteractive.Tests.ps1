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

Describe 'Test-OERHostNonInteractive (BL-100)' {
    BeforeAll {
        . "$PSScriptRoot/../TestHelpers/OERConfirmHost.ps1"
        $script:PwshPath = (Get-Process -Id $PID).Path

        # Starts a child pwsh that only imports the built module by name and asks the helper in module
        # scope. Nothing else runs in the child: no sign-in, no token request, no Graph call.
        function script:Invoke-ChildHostQuestion {
            param([string[]]$HostArgument)
            $Command = "Import-Module Omnicit.EntraRBAC -Force -ErrorAction Stop; " +
                "'ANSWER:' + (& (Get-Module Omnicit.EntraRBAC) { Test-OERHostNonInteractive })"
            $Output = & $script:PwshPath -NoProfile @HostArgument -Command $Command 2>&1
            [PSCustomObject]@{
                ExitCode = $LASTEXITCODE
                Output   = @($Output | ForEach-Object { "$_" })
            }
        }
    }

    It 'returns $true in a console host started with -NonInteractive' {
        $Run = Invoke-ChildHostQuestion -HostArgument '-NonInteractive'
        $Run.ExitCode | Should -Be 0
        $Run.Output | Should -Contain 'ANSWER:True'
    }

    It 'returns $true when the switch is spelled -noni, the shortest form' {
        $Run = Invoke-ChildHostQuestion -HostArgument '-noni'
        $Run.ExitCode | Should -Be 0
        $Run.Output | Should -Contain 'ANSWER:True'
    }

    It 'returns $false in a console host started without -NonInteractive' {
        $Run = Invoke-ChildHostQuestion -HostArgument @()
        $Run.ExitCode | Should -Be 0
        $Run.Output | Should -Contain 'ANSWER:False'
    }

    It 'returns $false in a runspace made with no PSHost (the Default Host)' {
        $Runspace = [runspacefactory]::CreateRunspace()
        $Runspace.Open()
        $Shell = [powershell]::Create()
        try {
            Install-OERTransportTripwireInRunspace -Runspace $Runspace
            $Shell.Runspace = $Runspace
            $null = $Shell.AddScript({
                    Import-Module Omnicit.EntraRBAC -Force -ErrorAction Stop
                    "HOST:$($Host.Name)"
                    "ANSWER:$(& (Get-Module Omnicit.EntraRBAC) { Test-OERHostNonInteractive })"
                }.ToString())
            $Output = @($Shell.Invoke())
            Test-OERTransportTripwireInRunspace -Runspace $Runspace
            $Output | Should -Be @('HOST:Default Host', 'ANSWER:False')
            $Shell.Streams.Error | Should -BeNullOrEmpty
        } finally {
            $Shell.Dispose()
            $Runspace.Dispose()
        }
    }

    It 'returns $false in a host that is not the console host (the answering host)' {
        $Run = Invoke-OERWithConfirmAnswer -Answer '&Yes' -Script {
            Import-Module Omnicit.EntraRBAC -Force -ErrorAction Stop
            "HOST:$($Host.Name)"
            "ANSWER:$(& (Get-Module Omnicit.EntraRBAC) { Test-OERHostNonInteractive })"
        }
        $Run.Output | Should -Be @('HOST:OERAnsweringHost', 'ANSWER:False')
        $Run.Errors | Should -BeNullOrEmpty
    }

    It 'returns a [bool] and writes no error record' {
        $Result = InModuleScope $script:moduleName {
            $Before = $global:Error.Count
            $Answer = Test-OERHostNonInteractive -ErrorAction SilentlyContinue
            [PSCustomObject]@{ IsBool = ($Answer -is [bool]); NewErrors = $global:Error.Count - $Before }
        }
        $Result.IsBool | Should -BeTrue
        $Result.NewErrors | Should -Be 0
    }
}

Describe 'Test-OERHostNonInteractive answers $false when the reflection fails (BL-100)' {
    BeforeAll {
        # A host that calls itself 'ConsoleHost', so the helper gets past its host name check and into the
        # reflection, but whose user interface is not ConsoleHostUserInterface: it has no
        # _throwOnReadAndPrompt field, and with ThrowOnUi set its UI getter throws. Both are the "any step of
        # the reflection fails" path of the helper's help, which must answer $false ("not proven") and write
        # no error record. ThrowOnUi is set only after the runspace is open, since opening it reads the UI.
        class OERNamedConsoleHostUI : System.Management.Automation.Host.PSHostUserInterface {
            [System.Management.Automation.Host.PSHostRawUserInterface] get_RawUI() { return $null }
            [string] ReadLine() { return '' }
            [System.Security.SecureString] ReadLineAsSecureString() { return $null }
            [void] Write([string]$Value) { }
            [void] Write([System.ConsoleColor]$Foreground, [System.ConsoleColor]$Background, [string]$Value) { }
            [void] WriteLine([string]$Value) { }
            [void] WriteErrorLine([string]$Value) { }
            [void] WriteDebugLine([string]$Value) { }
            [void] WriteVerboseLine([string]$Value) { }
            [void] WriteWarningLine([string]$Value) { }
            [void] WriteProgress([long]$SourceId, [System.Management.Automation.ProgressRecord]$Record) { }
            [System.Collections.Generic.Dictionary[string, psobject]] Prompt(
                [string]$Caption,
                [string]$Message,
                [System.Collections.ObjectModel.Collection[System.Management.Automation.Host.FieldDescription]]$Descriptions) {
                return $null
            }
            [int] PromptForChoice(
                [string]$Caption,
                [string]$Message,
                [System.Collections.ObjectModel.Collection[System.Management.Automation.Host.ChoiceDescription]]$Choices,
                [int]$DefaultChoice) {
                return $DefaultChoice
            }
            [pscredential] PromptForCredential([string]$Caption, [string]$Message, [string]$UserName, [string]$TargetName) { return $null }
            [pscredential] PromptForCredential(
                [string]$Caption,
                [string]$Message,
                [string]$UserName,
                [string]$TargetName,
                [System.Management.Automation.PSCredentialTypes]$AllowedCredentialTypes,
                [System.Management.Automation.PSCredentialUIOptions]$Options) {
                return $null
            }
        }

        class OERNamedConsoleHost : System.Management.Automation.Host.PSHost {
            hidden [OERNamedConsoleHostUI]$HostUi = [OERNamedConsoleHostUI]::new()
            hidden [guid]$Id = [guid]::NewGuid()
            [bool]$ThrowOnUi = $false

            [string] get_Name() { return 'ConsoleHost' }
            [version] get_Version() { return [version]'1.0.0' }
            [guid] get_InstanceId() { return $this.Id }
            [System.Management.Automation.Host.PSHostUserInterface] get_UI() {
                if ($this.ThrowOnUi) { throw 'This host has no user interface to read.' }
                return $this.HostUi
            }
            [System.Globalization.CultureInfo] get_CurrentCulture() { return [System.Globalization.CultureInfo]::InvariantCulture }
            [System.Globalization.CultureInfo] get_CurrentUICulture() { return [System.Globalization.CultureInfo]::InvariantCulture }
            [void] EnterNestedPrompt() { }
            [void] ExitNestedPrompt() { }
            [void] NotifyBeginApplication() { }
            [void] NotifyEndApplication() { }
            [void] SetShouldExit([int]$ExitCode) { }
        }

        # Runs the helper in a runspace on that host and reports what it answered, whether the reflection
        # step really fails there (so the answer came from the catch, not from a host name check), how many
        # records it left in $Error and the runspace's error stream.
        function script:Invoke-NamedConsoleHostQuestion {
            param([bool]$ThrowOnUi)
            $FakeHost = [OERNamedConsoleHost]::new()
            $Runspace = [runspacefactory]::CreateRunspace($FakeHost)
            $Runspace.Open()
            $FakeHost.ThrowOnUi = $ThrowOnUi
            $Shell = [powershell]::Create()
            try {
                Install-OERTransportTripwireInRunspace -Runspace $Runspace
                $Shell.Runspace = $Runspace
                $null = $Shell.AddScript({
                        Import-Module Omnicit.EntraRBAC -Force -ErrorAction Stop
                        $Instance = [System.Reflection.BindingFlags]'NonPublic,Instance'
                        $ReflectionFails = try {
                            $Ui = $Host.GetType().GetProperty('ExternalHost', $Instance).GetValue($Host).UI
                            $null -eq $Ui.GetType().GetField('_throwOnReadAndPrompt', $Instance)
                        } catch {
                            $true
                        }
                        $global:Error.Clear()
                        $Answer = & (Get-Module Omnicit.EntraRBAC) { Test-OERHostNonInteractive }
                        [PSCustomObject]@{
                            HostName        = $Host.Name
                            ReflectionFails = $ReflectionFails
                            Answer          = $Answer
                            IsBool          = $Answer -is [bool]
                            ErrorCount      = $global:Error.Count
                        }
                    }.ToString())
                $Output = @($Shell.Invoke())
                Test-OERTransportTripwireInRunspace -Runspace $Runspace
                [PSCustomObject]@{
                    Result = $Output[-1]
                    Errors = @($Shell.Streams.Error | ForEach-Object { $_.ToString() })
                }
            } finally {
                $Shell.Dispose()
                $Runspace.Dispose()
            }
        }
    }

    It 'returns $false and writes no error record when the user interface has no _throwOnReadAndPrompt field' {
        $Run = Invoke-NamedConsoleHostQuestion -ThrowOnUi $false
        $Run.Result.HostName | Should -BeExactly 'ConsoleHost'
        $Run.Result.ReflectionFails | Should -BeTrue
        $Run.Result.IsBool | Should -BeTrue
        $Run.Result.Answer | Should -BeFalse
        $Run.Result.ErrorCount | Should -Be 0
        $Run.Errors | Should -BeNullOrEmpty
    }

    It 'returns $false and writes no error record when reading the user interface throws' {
        $Run = Invoke-NamedConsoleHostQuestion -ThrowOnUi $true
        $Run.Result.HostName | Should -BeExactly 'ConsoleHost'
        $Run.Result.ReflectionFails | Should -BeTrue
        $Run.Result.IsBool | Should -BeTrue
        $Run.Result.Answer | Should -BeFalse
        $Run.Result.ErrorCount | Should -Be 0
        $Run.Errors | Should -BeNullOrEmpty
    }
}

Describe 'Test-OERHostNonInteractive is the single owner of the host question (BL-100)' {
    It 'is the only file under source that names _throwOnReadAndPrompt' {
        $SourceRoot = (Resolve-Path (Join-Path $PSScriptRoot '../../../source')).Path
        $Named = @(Get-ChildItem -Path $SourceRoot -Recurse -File -Filter '*.ps1' |
                Where-Object { (Get-Content -LiteralPath $_.FullName -Raw) -match '_throwOnReadAndPrompt' } |
                ForEach-Object { $_.Name })
        $Named | Should -Be @('Test-OERHostNonInteractive.ps1')
    }

    It 'is called in Initialize-OERAuth and by no other file under source' {
        $SourceRoot = (Resolve-Path (Join-Path $PSScriptRoot '../../../source')).Path
        $Callers = @(Get-ChildItem -Path $SourceRoot -Recurse -File -Filter '*.ps1' |
                Where-Object { $_.Name -ne 'Test-OERHostNonInteractive.ps1' -and
                    (Get-Content -LiteralPath $_.FullName -Raw) -match 'Test-OERHostNonInteractive' } |
                ForEach-Object { $_.Name })
        $Callers | Should -Be @('Initialize-OERAuth.ps1')
    }
}
