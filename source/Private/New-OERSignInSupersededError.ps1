function New-OERSignInSupersededError {
    <#
    .SYNOPSIS
    Builds the SignInSuperseded error record.

    .DESCRIPTION
    The single owner of the SignInSuperseded id and message. The module's transports raise it before a
    request made while a command on the call stack remembers another sign-in identity than the module's
    state now carries -- a command Get-OERSignInSupersession finds -- so nothing is sent, while that
    command runs, under a session another OER command in the same pipeline signed in to after it.
    Invoke-OERStructure raises it too, before it signs in for a document without -TenantId, and so do
    New-OERAccessPackageApprovalStage, New-OERAccessPackageRequestorScope and New-OERAccessReviewStage
    before their name lookup without -TenantId, when the identity changed after the command's begin
    block took a snapshot of the session (Checkpoint-OERSignIn), which is why the message says the
    other sign-in came after the command began, not after it signed in: a command refused there has
    not signed in at all.

    The target is that command's name, and the request it refuses is one made while that command runs,
    which is not always one the command makes itself: it can be the command's own request, a request of
    a cmdlet the command calls, or a request of a command downstream of it in the pipeline, since a
    downstream command processes each object inside the upstream command's output call, with the
    upstream command's frame still on the call stack (Up | Down, Up | ForEach-Object { Inner }). The
    message therefore names the command and speaks of what happens while it runs, not of the command's
    own requests, so a record that a downstream command writes, or that a cmdlet re-publishes under an
    error of its own, still says whose sign-in was replaced. The target and the message both carry the
    name. The record names no tenant, no account and no token: the text is fixed apart from the name,
    and the command's name is the only value the record carries.

    The text fits its cause (BL-92), so there are four, all with the same id, category and target. By
    cause: when the module still holds a session, another OER command in the same pipeline signed in to
    a different tenant or identity after the command began; when it holds none, Disconnect-OER ended
    the module's session after the command began, and the advice is to run Disconnect-OER as a
    statement of its own. The function reads that from the module's state ($null is no session, the
    same test Get-OERSignInIdentity makes for 'not signed in', and Disconnect-OER is the only place
    that sets the state to $null), so the transports and the builders call it with no extra argument.
    By effect: a request says it was not sent, and the module sends nothing while the command runs;
    with -Document the refusal is of a whole document, which the command did not apply, and the text
    says so.

    .PARAMETER Command
    The name of the command the record names. From a transport, that is the command whose remembered
    sign-in was superseded, as Get-OERSignInSupersession returns it ('a script block' when the frame
    carries no command name). From Invoke-OERStructure or one of the three builders, it is the
    refusing command's own name, passed before that command signs in, when the session changed after
    its begin block -- or, for Invoke-OERStructure, after its last sign-in for an earlier document.
    It becomes the record's target object, and the message names it exactly as passed.

    .PARAMETER Document
    Builds the variant for a refused document: the same id, category and target, with a message that
    says the command did not apply this document and sent nothing for it, in place of the one for a
    request. Only Invoke-OERStructure passes it, because what it refuses is a whole document before it
    signs in. The transports refuse one request and the three builders refuse their name lookup, so
    they pass nothing and keep the wording for a request.

    .EXAMPLE
    throw (New-OERSignInSupersededError -Command 'New-OERGroup')

    Refuses a request made while New-OERGroup runs, after a later pipeline command signed in to another
    tenant.

    .EXAMPLE
    $PSCmdlet.WriteError((New-OERSignInSupersededError -Command 'Invoke-OERStructure' -Document))

    Refuses a whole document that Invoke-OERStructure did not apply, after another pipeline command
    signed in to a different tenant or identity, or Disconnect-OER ended the session.
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '',
        Justification = 'Pure in-memory error-record builder; returns an ErrorRecord and performs no state change, so ShouldProcess does not apply.')]
    [CmdletBinding()]
    [OutputType([System.Management.Automation.ErrorRecord])]
    param(
        [Parameter(Mandatory)]
        [string]$Command,

        [switch]$Document
    )
    # BL-92: the text fits its cause. No state at all means Disconnect-OER ended the module's session
    # (the only place under source/ that sets it to $null), not another sign-in. -Document is
    # Invoke-OERStructure's: it refuses a whole document before it signs in, not one request.
    # The command's name is the only value in the text. It is an argument of -f, never part of the
    # format string, so a name is written exactly as passed, whatever characters it holds.
    [bool]$SessionEnded = $null -eq $script:_OERAuthState
    [string]$Cause = if ($SessionEnded) {
        "Disconnect-OER ended the module's session after {0} began"
    } else {
        'Another OER command in the same pipeline signed in to a different tenant or identity after {0} began'
    }
    [string]$Effect = if ($Document) {
        'so {0} did not apply this document and Omnicit.EntraRBAC sent nothing for it'
    } else {
        'so Omnicit.EntraRBAC sends nothing while {0} runs: this request was not sent'
    }
    [string]$Advice = if ($SessionEnded) {
        'Run Disconnect-OER as a statement of its own, after the commands that use the session.'
    } else {
        'Run the commands as separate statements, so that each one signs in and finishes before the next one starts.'
    }
    [string]$Message = ('{0}, {1}. {2}' -f $Cause, $Effect, $Advice) -f $Command
    [System.Management.Automation.ErrorRecord]::new(
        [System.Exception]::new($Message),
        'SignInSuperseded',
        [System.Management.Automation.ErrorCategory]::AuthenticationError,
        $Command)
}
