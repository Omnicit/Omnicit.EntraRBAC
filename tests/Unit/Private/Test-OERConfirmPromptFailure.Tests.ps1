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
