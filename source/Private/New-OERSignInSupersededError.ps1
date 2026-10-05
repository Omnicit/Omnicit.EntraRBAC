function New-OERSignInSupersededError {
    <#
    .SYNOPSIS
    Builds the SignInSuperseded error record.

    .DESCRIPTION
    The single owner of the SignInSuperseded id and message. The module's transports raise it before a
    request made while a command on the call stack remembers another sign-in identity than the module's
    state now carries -- a command Get-OERSignInSupersession finds -- so nothing is sent, while that
    command runs, under a session another OER command in the same pipeline signed in to after it.

    The target is that command's name, and the request it refuses is one made while that command runs,
    which is not always one the command makes itself: it can be the command's own request, a request of
    a cmdlet the command calls, or a request of a command downstream of it in the pipeline, since a
    downstream command processes each object inside the upstream command's output call, with the
    upstream command's frame still on the call stack (Up | Down, Up | ForEach-Object { Inner }). The
    message therefore speaks of what happens while the command runs, not of the command's own requests.
    It names no tenant, no account and no token: it is fixed text, and the command's name is the only
    value the record carries.

    .PARAMETER Command
    The name of the command whose sign-in was superseded, as Get-OERSignInSupersession returns it ('a
    script block' when the frame carries no command name). It becomes the record's target object.

    .EXAMPLE
    throw (New-OERSignInSupersededError -Command 'New-OERGroup')

    Refuses a request made while New-OERGroup runs, after a later pipeline command signed in to another
    tenant.
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '',
        Justification = 'Pure in-memory error-record builder; returns an ErrorRecord and performs no state change, so ShouldProcess does not apply.')]
    [CmdletBinding()]
    [OutputType([System.Management.Automation.ErrorRecord])]
    param(
        [Parameter(Mandatory)]
        [string]$Command
    )
    [System.Management.Automation.ErrorRecord]::new(
        [System.Exception]::new(
            'Another OER command in the same pipeline signed in to a different tenant or identity after ' +
            'this command signed in, so Omnicit.EntraRBAC sends nothing while this command runs: this ' +
            'request was not sent. Run the commands as separate statements, so that each one signs in ' +
            'and finishes before the next one starts.'),
        'SignInSuperseded',
        [System.Management.Automation.ErrorCategory]::AuthenticationError,
        $Command)
}
