# Test helper -- NOT a Pester file (no *.Tests.ps1 suffix, so Pester discovery ignores it).
#
# Why this exists: a genuinely DECLINED ShouldProcess prompt is the state the PIM permanent
# self-heal has to be safe in, and it is the one state Pester cannot reach. -Confirm:$false is a
# confirmation and -WhatIf sets $WhatIfPreference, so neither produces the decline case
# ($Proceed false AND $WhatIfPreference false). ShouldProcess asks the runspace's PSHost, and a
# runspace's host is fixed at creation, so the only way to answer "No" is to run the command in a
# second runspace built on a host that answers for us.
#
# Pester mocks do not cross a runspace boundary, so the caller's scriptblock must install its own
# fakes. Do that with Set-Item on function:script: inside & (Get-Module Omnicit.EntraRBAC) { ... },
# which replaces the function in that runspace's private copy of the module only -- the parent
# runspace's module, and therefore every other test, is untouched.

class OERAnsweringHostUI : System.Management.Automation.Host.PSHostUserInterface {
    [string]$Answer = '&No'

    # An optional PER-PROMPT answer list. Some decline shapes cannot be reached with one answer for
    # every prompt: Set-OERGroupPimPolicy now patches the rule that REMOVES the MFA/authentication-
    # context conflict FIRST (see docs/development/rationale.md#mfa-authcontext-exclusion), so the
    # half-applied state that leaves BOTH controls on needs the FIRST prompt declined and a LATER
    # one accepted -- the opposite of what a single answer, or the fake-flips-the-answer trick used
    # elsewhere in these tests, can produce. When this list is empty the host behaves exactly as
    # before and $Answer still governs every prompt, including a mid-run mutation of it. The last
    # entry repeats for any prompt beyond the list.
    [string[]]$AnswerSequence = @()
    [int]$AnswerIndex = 0

    # Every confirmation prompt this host answers is recorded here. -WhatIf and the confirmation
    # prompt both render the ShouldProcess TARGET, and neither is capturable by stream redirection
    # (both go straight to the host), so this is the only way a test can assert on that text.
    [System.Collections.Generic.List[string]]$Prompts = [System.Collections.Generic.List[string]]::new()

    OERAnsweringHostUI([string]$Answer) { $this.Answer = $Answer }

    OERAnsweringHostUI([string]$Answer, [string[]]$AnswerSequence) {
        $this.Answer = $Answer
        $this.AnswerSequence = @($AnswerSequence)
    }

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

    # ShouldProcess offers Yes / Yes to All / No / No to All / Suspend, and the index of each is an
    # implementation detail -- match on the label so this cannot silently start answering Yes.
    [int] PromptForChoice(
        [string]$Caption,
        [string]$Message,
        [System.Collections.ObjectModel.Collection[System.Management.Automation.Host.ChoiceDescription]]$Choices,
        [int]$DefaultChoice) {
        $this.Prompts.Add(($Caption + ' ' + $Message))
        $Wanted = $this.Answer
        if ($this.AnswerSequence.Count -gt 0) {
            $At = [Math]::Min($this.AnswerIndex, $this.AnswerSequence.Count - 1)
            $Wanted = $this.AnswerSequence[$At]
            $this.AnswerIndex = $this.AnswerIndex + 1
        }
        for ($Index = 0; $Index -lt $Choices.Count; $Index++) {
            if ($Choices[$Index].Label -eq $Wanted) { return $Index }
        }
        throw "The confirmation prompt offered no choice labelled '$Wanted'."
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

class OERAnsweringHost : System.Management.Automation.Host.PSHost {
    hidden [OERAnsweringHostUI]$HostUi
    hidden [guid]$Id = [guid]::NewGuid()

    OERAnsweringHost([string]$Answer) { $this.HostUi = [OERAnsweringHostUI]::new($Answer) }

    OERAnsweringHost([string]$Answer, [string[]]$AnswerSequence) {
        $this.HostUi = [OERAnsweringHostUI]::new($Answer, $AnswerSequence)
    }

    [string] get_Name() { return 'OERAnsweringHost' }
    [version] get_Version() { return [version]'1.0.0' }
    [guid] get_InstanceId() { return $this.Id }
    [System.Management.Automation.Host.PSHostUserInterface] get_UI() { return $this.HostUi }
    [System.Globalization.CultureInfo] get_CurrentCulture() { return [System.Globalization.CultureInfo]::InvariantCulture }
    [System.Globalization.CultureInfo] get_CurrentUICulture() { return [System.Globalization.CultureInfo]::InvariantCulture }
    [void] EnterNestedPrompt() { }
    [void] ExitNestedPrompt() { }
    [void] NotifyBeginApplication() { }
    [void] NotifyEndApplication() { }
    [void] SetShouldExit([int]$ExitCode) { }

    [string[]] GetPrompts() { return $this.HostUi.Prompts.ToArray() }
}

function Invoke-OERWithConfirmAnswer {
    <#
    .SYNOPSIS
    Runs a scriptblock in a runspace whose host answers every confirmation prompt the same way.
    .DESCRIPTION
    Creates a runspace on a PSHost whose PromptForChoice returns the choice labelled -Answer, runs
    -Script in it, and returns the output plus the warning and error streams and the text of every
    confirmation prompt that was answered. Used to exercise a genuinely declined ShouldProcess,
    which no in-process Pester construct can produce, and to assert on the ShouldProcess target
    text, which goes straight to the host and so survives no stream redirection. The scriptblock is
    transported as text, so it must be self-contained -- it cannot close over variables from the
    calling test.
    .PARAMETER Script
    The self-contained scriptblock to run inside the answering runspace. It is responsible for
    importing the module and installing its own fakes, because Pester mocks do not cross runspaces.
    .PARAMETER Answer
    The label of the confirmation choice to answer with: '&No' to decline (the default) or '&Yes'
    to accept. Accepting is what makes a declining assertion meaningful, so tests should pin both.
    .PARAMETER AnswerSequence
    An optional per-prompt answer list, for a decline shape that needs DIFFERENT answers to the
    first and to later prompts (for example declining the first rule and accepting the second). The
    last entry repeats for any prompt beyond the list. When omitted, -Answer governs every prompt.
    .EXAMPLE
    Invoke-OERWithConfirmAnswer -Answer '&No' -Script { Import-Module Omnicit.EntraRBAC; 'ran' }

    Runs the scriptblock with every confirmation prompt answered No and returns its output.
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory)]
        [scriptblock]$Script,

        [ValidateSet('&Yes', '&No')]
        [string]$Answer = '&No',

        [ValidateSet('&Yes', '&No')]
        [string[]]$AnswerSequence
    )
    $AnsweringHost = if ($PSBoundParameters.ContainsKey('AnswerSequence')) {
        [OERAnsweringHost]::new($Answer, $AnswerSequence)
    } else {
        [OERAnsweringHost]::new($Answer)
    }
    $Runspace = [runspacefactory]::CreateRunspace($AnsweringHost)
    $Runspace.Open()
    $Shell = [powershell]::Create()
    try {
        $Shell.Runspace = $Runspace
        $null = $Shell.AddScript($Script.ToString())
        $Output = $Shell.Invoke()
        [PSCustomObject]@{
            Output   = @($Output)
            Warnings = @($Shell.Streams.Warning | ForEach-Object { $_.Message })
            Errors   = @($Shell.Streams.Error | ForEach-Object { $_.ToString() })
            Prompts  = @($AnsweringHost.GetPrompts())
        }
    } finally {
        $Shell.Dispose()
        $Runspace.Dispose()
    }
}
