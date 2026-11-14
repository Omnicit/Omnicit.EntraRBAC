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

Describe 'Test-OERConfirmPromptFailure (BL-53)' {
    BeforeAll {
        # The message ShouldProcess's MethodInvocationException carries (measured 2026-10-20 in plain PowerShell):
        # 'Exception calling "ShouldProcess" with "2" argument(s): "<inner message>"'.
        function script:New-PromptFailureRecord {
            param([System.Exception]$Inner, [string]$Method = 'ShouldProcess')
            $Outer = [System.Management.Automation.MethodInvocationException]::new(
                "Exception calling `"$Method`" with `"2`" argument(s): `"$($Inner.Message)`"", $Inner)
            [System.Management.Automation.ErrorRecord]::new($Outer, 'MethodInvocationException', 'NotSpecified', $null)
        }
    }

    It 'returns $true for the <Kind> a ShouldProcess prompt raised' -TestCases @(
        @{ Kind = 'HostException (the Default Host)'; Inner = [System.Management.Automation.Host.HostException]::new('A command that prompts the user failed because the host program or the command type does not support user interaction.') }
        @{ Kind = 'PSInvalidOperationException (pwsh -NonInteractive)'; Inner = [System.Management.Automation.PSInvalidOperationException]::new('PowerShell is in NonInteractive mode. Read and Prompt functionality is not available.') }
        @{ Kind = 'NullReferenceException (standard input at its end)'; Inner = [System.NullReferenceException]::new('Object reference not set to an instance of an object.') }
        @{ Kind = 'PromptingException, derived from HostException'; Inner = [System.Management.Automation.Host.PromptingException]::new('prompting failed') }
    ) {
        $Record = New-PromptFailureRecord -Inner $Inner
        InModuleScope $script:moduleName -Parameters @{ Record = $Record } {
            param($Record)
            Test-OERConfirmPromptFailure -Record $Record
        } | Should -BeExactly $true
    }

    It 'returns $false for a ShouldProcess MethodInvocationException whose inner exception is <Kind>' -TestCases @(
        @{ Kind = 'an InvalidOperationException (the base of PSInvalidOperationException)'; Inner = [System.InvalidOperationException]::new('not a prompt failure') }
        @{ Kind = 'an ArgumentException'; Inner = [System.ArgumentException]::new('not a prompt failure') }
        @{ Kind = 'a RuntimeException'; Inner = [System.Management.Automation.RuntimeException]::new('not a prompt failure') }
    ) {
        $Record = New-PromptFailureRecord -Inner $Inner
        # Reached: the record is the measured shape in every part but the inner type.
        $Record.Exception | Should -BeOfType ([System.Management.Automation.MethodInvocationException])
        $Record.Exception.Message | Should -BeLike '*"ShouldProcess"*'
        InModuleScope $script:moduleName -Parameters @{ Record = $Record } {
            param($Record)
            Test-OERConfirmPromptFailure -Record $Record
        } | Should -BeExactly $false
    }

    It 'returns $false for a MethodInvocationException of a measured inner type whose message does not name ShouldProcess' {
        $Record = New-PromptFailureRecord -Inner ([System.Management.Automation.Host.HostException]::new('host failure')) -Method 'ShouldContinue'
        $Record.Exception.InnerException | Should -BeOfType ([System.Management.Automation.Host.HostException])
        InModuleScope $script:moduleName -Parameters @{ Record = $Record } {
            param($Record)
            Test-OERConfirmPromptFailure -Record $Record
        } | Should -BeExactly $false
    }

    It 'compares the method name with letter case (ordinal)' {
        $Record = New-PromptFailureRecord -Inner ([System.Management.Automation.Host.HostException]::new('host failure')) -Method 'shouldprocess'
        InModuleScope $script:moduleName -Parameters @{ Record = $Record } {
            param($Record)
            Test-OERConfirmPromptFailure -Record $Record
        } | Should -BeExactly $false
    }

    It 'returns $false for <Kind>' -TestCases @(
        @{ Kind = 'a measured inner exception thrown on its own, not wrapped by a method call'; Exception = [System.Management.Automation.Host.HostException]::new('Exception calling "ShouldProcess": host failure') }
        @{ Kind = 'a plain exception naming ShouldProcess'; Exception = [System.Exception]::new('ShouldProcess failed') }
        @{ Kind = 'another exception type naming ShouldProcess and wrapping a measured inner type'; Exception = [System.Management.Automation.RuntimeException]::new('Exception calling "ShouldProcess" with "2" argument(s): "host failure"', [System.Management.Automation.Host.HostException]::new('host failure')) }
        @{ Kind = 'a MethodInvocationException with no inner exception'; Exception = [System.Management.Automation.MethodInvocationException]::new('Exception calling "ShouldProcess" with "2" argument(s): "x"') }
    ) {
        $Record = [System.Management.Automation.ErrorRecord]::new($Exception, 'Other', 'NotSpecified', $null)
        InModuleScope $script:moduleName -Parameters @{ Record = $Record } {
            param($Record)
            Test-OERConfirmPromptFailure -Record $Record
        } | Should -BeExactly $false
    }

    It 'returns $false for a null record' {
        InModuleScope $script:moduleName { Test-OERConfirmPromptFailure -Record $null } | Should -BeExactly $false
    }

    It 'returns $false for a null record under Set-StrictMode -Version Latest, where a member of $null cannot be read' {
        InModuleScope $script:moduleName {
            Set-StrictMode -Version Latest
            Test-OERConfirmPromptFailure -Record $null
        } | Should -BeExactly $false
    }

    It 'returns $true for the record a real ShouldProcess raised in a runspace made with no PSHost' {
        # A plain advanced function with ConfirmImpact High calls ShouldProcess in the Default Host, where it
        # throws; the caught record is handed to the helper in the same runspace. No module command but the
        # helper runs there.
        $Runspace = [runspacefactory]::CreateRunspace()
        $Runspace.Open()
        $Shell = [powershell]::Create()
        try {
            Install-OERTransportTripwireInRunspace -Runspace $Runspace
            $Shell.Runspace = $Runspace
            $null = $Shell.AddScript({
                    Import-Module Omnicit.EntraRBAC -Force -ErrorAction Stop
                    function Test-Prompt {
                        [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
                        param()
                        $PSCmdlet.ShouldProcess('target', 'action')
                    }
                    try { Test-Prompt } catch {
                        "INNER:$($PSItem.Exception.InnerException.GetType().FullName)"
                        "ANSWER:$(& (Get-Module Omnicit.EntraRBAC) { param($Caught) Test-OERConfirmPromptFailure -Record $Caught } $PSItem)"
                    }
                    'END'
                }.ToString())
            $Output = @($Shell.Invoke())
            Test-OERTransportTripwireInRunspace -Runspace $Runspace
        } finally {
            $Shell.Dispose()
            $Runspace.Dispose()
        }
        $Output | Should -Be @('INNER:System.Management.Automation.Host.HostException', 'ANSWER:True', 'END')
    }
}

Describe 'Test-OERConfirmPromptFailure, the RemoteException a background job raises' {
    BeforeAll {
        # What a Start-Job job's ShouldProcess throws when its receiver cannot answer (measured 2026-11-14):
        # a MethodInvocationException whose inner exception is a RemoteException carrying the deserialized
        # type names of the exception raised in the receiver.
        function script:New-RemotePromptFailureRecord {
            param(
                [string[]]$Names,
                [string]$Method = 'ShouldProcess',
                [switch]$NoSerialized
            )
            $InnerMessage = 'PowerShell is in NonInteractive mode. Read and Prompt functionality is not available.'
            $Serialized = $null
            if (-not $NoSerialized) {
                $Serialized = [PSObject]::new()
                $Serialized.PSObject.TypeNames.Clear()
                foreach ($N in $Names) { $Serialized.PSObject.TypeNames.Add($N) }
            }
            # The (string, PSObject, PSObject) constructor is internal: bind it through reflection.
            $Remote = [System.Activator]::CreateInstance(
                [System.Management.Automation.RemoteException],
                [System.Reflection.BindingFlags]'Instance,NonPublic,Public',
                $null,
                @($InnerMessage, $Serialized, $null),
                $null)
            $Outer = [System.Management.Automation.MethodInvocationException]::new(
                "Exception calling `"$Method`" with `"2`" argument(s): `"$InnerMessage`"", $Remote)
            [System.Management.Automation.ErrorRecord]::new($Outer, 'MethodInvocationException', 'NotSpecified', $null)
        }

        $script:PsInvalid = @(
            'Deserialized.System.Management.Automation.PSInvalidOperationException'
            'Deserialized.System.InvalidOperationException'
            'Deserialized.System.SystemException'
            'Deserialized.System.Exception'
            'Deserialized.System.Object'
        )
        $script:NullRef = @(
            'Deserialized.System.NullReferenceException'
            'Deserialized.System.SystemException'
            'Deserialized.System.Exception'
            'Deserialized.System.Object'
        )
        $script:HostEx = @(
            'Deserialized.System.Management.Automation.Host.HostException'
            'Deserialized.System.Management.Automation.RuntimeException'
            'Deserialized.System.SystemException'
            'Deserialized.System.Exception'
            'Deserialized.System.Object'
        )
        $script:Prompting = @('Deserialized.System.Management.Automation.Host.PromptingException') + $script:HostEx

        # Runs a child pwsh on a script that starts a job and receives it; returns the child's output lines.
        function script:Invoke-JobChild {
            param([string]$Name, [switch]$NonInteractive, [switch]$EmptyInput)
            $Script = Join-Path $TestDrive "$Name.ps1"
            $OutFile = Join-Path $TestDrive "$Name.out.txt"
            $ErrFile = Join-Path $TestDrive "$Name.err.txt"
            $InFile = Join-Path $TestDrive "$Name.in.txt"
            Set-Content -LiteralPath $Script -Encoding ascii -Value @'
$Job = Start-Job -ScriptBlock {
    Import-Module Omnicit.EntraRBAC -Force -ErrorAction Stop
    function Test-Prompt {
        [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
        param()
        $PSCmdlet.ShouldProcess('target', 'action')
    }
    try { Test-Prompt } catch {
        "INNER:$($PSItem.Exception.InnerException.GetType().FullName)"
        "ANSWER:$(& (Get-Module Omnicit.EntraRBAC) { param($Caught) Test-OERConfirmPromptFailure -Record $Caught } $PSItem)"
    }
}
Receive-Job -Job $Job -Wait
Remove-Job -Job $Job -Force
'@
            $ArgList = @('-NoProfile')
            if ($NonInteractive) { $ArgList += '-NonInteractive' }
            $ArgList += @('-File', $Script)
            $Params = @{
                FilePath = (Get-Process -Id $PID).Path
                ArgumentList = $ArgList
                RedirectStandardOutput = $OutFile
                RedirectStandardError = $ErrFile
                PassThru = $true
                ErrorAction = 'Stop'
            }
            if ($EmptyInput) {
                Set-Content -LiteralPath $InFile -Value '' -NoNewline
                $Params.RedirectStandardInput = $InFile
            }
            $Process = Start-Process @Params
            try {
                $Exited = $Process.WaitForExit(120000)
            } finally {
                if (-not $Process.HasExited) { Stop-Process -Id $Process.Id -Force -ErrorAction SilentlyContinue }
            }
            if (-not $Exited) { return @('TIMEOUT') }
            @(Get-Content -LiteralPath $OutFile -ErrorAction SilentlyContinue)
        }
    }

    It 'builds the measured shape: a RemoteException whose SerializedRemoteException keeps its type names' {
        $Record = New-RemotePromptFailureRecord -Names $script:NullRef
        $Record.Exception.InnerException | Should -BeOfType ([System.Management.Automation.RemoteException])
        $Record.Exception.InnerException.SerializedRemoteException.PSObject.TypeNames[0] | Should -BeExactly 'Deserialized.System.NullReferenceException'
        $Record.Exception.InnerException.SerializedRemoteException.PSObject.TypeNames.Count | Should -Be 4
    }

    It 'returns $true for a RemoteException carrying <Kind>' -TestCases @(
        @{ Kind = 'a PSInvalidOperationException (receiver pwsh -NonInteractive)'; Which = 'PsInvalid' }
        @{ Kind = 'a NullReferenceException (receiver input at its end)'; Which = 'NullRef' }
        @{ Kind = 'a HostException'; Which = 'HostEx' }
        @{ Kind = 'a PromptingException, derived from HostException'; Which = 'Prompting' }
    ) {
        $Record = New-RemotePromptFailureRecord -Names (Get-Variable -Scope Script -Name $Which -ValueOnly)
        $Record.Exception.InnerException | Should -BeOfType ([System.Management.Automation.RemoteException])
        $Record.Exception.InnerException.SerializedRemoteException.PSObject.TypeNames.Count | Should -BeGreaterThan 3
        InModuleScope $script:moduleName -Parameters @{ Record = $Record } {
            param($Record)
            Test-OERConfirmPromptFailure -Record $Record
        } | Should -BeExactly $true
    }

    It 'returns $false for a RemoteException <Kind>' -TestCases @(
        @{ Kind = 'carrying an InvalidOperationException only'; Names = @('Deserialized.System.InvalidOperationException', 'Deserialized.System.SystemException', 'Deserialized.System.Exception', 'Deserialized.System.Object'); Method = 'ShouldProcess'; NoSerialized = $false }
        @{ Kind = 'with no SerializedRemoteException'; Names = @(); Method = 'ShouldProcess'; NoSerialized = $true }
        @{ Kind = 'of the right types whose method is not ShouldProcess'; Names = @('Deserialized.System.NullReferenceException', 'Deserialized.System.Object'); Method = 'ShouldContinue'; NoSerialized = $false }
        @{ Kind = 'whose type name differs in letter case'; Names = @('deserialized.system.nullreferenceexception', 'Deserialized.System.Object'); Method = 'ShouldProcess'; NoSerialized = $false }
    ) {
        $Record = New-RemotePromptFailureRecord -Names $Names -Method $Method -NoSerialized:$NoSerialized
        $Record.Exception.InnerException | Should -BeOfType ([System.Management.Automation.RemoteException])
        $Record.Exception.Message | Should -BeLike 'Exception calling "*"*'
        InModuleScope $script:moduleName -Parameters @{ Record = $Record } {
            param($Record)
            Test-OERConfirmPromptFailure -Record $Record
        } | Should -BeExactly $false
    }

    It 'returns $true for the record a real background job raised, received in pwsh -NonInteractive' {
        $Lines = Invoke-JobChild -Name 'NonInteractive' -NonInteractive
        $Lines | Should -Contain 'INNER:System.Management.Automation.RemoteException'
        $Lines | Should -Contain 'ANSWER:True'
    }

    It 'returns $true for the record a real background job raised, received with standard input at its end' {
        $Lines = Invoke-JobChild -Name 'InputAtEnd' -EmptyInput
        $Lines | Should -Contain 'INNER:System.Management.Automation.RemoteException'
        $Lines | Should -Contain 'ANSWER:True'
    }
}
