function New-OERSignInRefusedError {
    <#
    .SYNOPSIS
    Builds the SignInRefused error record.

    .DESCRIPTION
    The single owner of the SignInRefused id and message. The module's transports raise it before a
    request made on behalf of a command whose sign-in was refused -- a command Get-OERSignInRefusal
    finds latched on the call stack -- so nothing is sent for that command under the session or the
    token an earlier sign-in left. Invoke-OERGraphRequest checks its session gate first, so a Graph
    request made while the Graph SDK session is changed is refused as GraphSessionChanged instead. The
    target is the latched command's name, which is the immediate caller of Initialize-OERAuth: the
    cmdlet, for a sign-in refused at its entry; a private helper that signs in itself
    (Resolve-OERInventoryScopeTree, Resolve-OERReviewerScope, Resolve-OERTargetList); or the
    transport's nested function (Invoke-GraphSingle, Invoke-ArmCallWithRefresh), for one refused during
    that transport's own refresh. The message names no tenant, no account and no token: it is fixed
    text, and the command's name is the only value the record carries.

    Initialize-OERAuth raises it too, as a terminating error before any token call or Connect-MgGraph
    and before it latches its own caller, when a command OUTSIDE the one that called it is latched
    (Get-OERSignInRefusal -OutsideCaller): a cmdlet that a refused command calls, or a sign-in made
    inside a refused command's output. The target is then that latched outer command's name, and
    the request the fixed message calls "this request" is the sign-in, which is not made.

    With -SessionUncertain it builds the record Initialize-OERAuth raises for A10 (BL-89): an earlier
    sign-in in the session failed or was refused, so the module's session is not the one that sign-in
    asked for, and a sign-in that names no tenant is refused before any token call or Connect-MgGraph. The
    id and the category are the same, and the target is the command whose sign-in is refused, which stays
    latched; the message is fixed text of its own, which names no tenant and tells the operator to name
    the tenant or to run Connect-OER or Disconnect-OER. It is one text for every sign-in that sets the
    marker (BL-93), since the marker holds one boolean and nothing about the sign-in that set it: a
    sign-in for another tenant that was refused or failed, a renewal of the session's own token that
    failed within the same tenant, an Azure Resource Manager step that failed after the Graph half
    connected, and a Microsoft Graph PowerShell SDK session another Connect-MgGraph changed. So it does
    not say whose session the module still holds, only that the session is not the one the sign-in
    asked for.

    .PARAMETER Command
    The name of the command whose sign-in was refused, as Get-OERSignInRefusal returns it, with or
    without -OutsideCaller ('a script block' when the held frame carries no command name). It becomes
    the record's target object.

    .PARAMETER SessionUncertain
    Builds the session-uncertain variant (A10): the same id, category and target, with the message for a
    sign-in that names no tenant while an earlier sign-in's failure leaves the session uncertain. The
    message is the same whichever sign-in set the marker.

    .EXAMPLE
    throw (New-OERSignInRefusedError -Command 'Get-OERGroup')

    Refuses a request made on behalf of Get-OERGroup after its sign-in was refused.

    .EXAMPLE
    Write-CmdletError -ErrorRecord (New-OERSignInRefusedError -Command 'Invoke-OERStructure' -SessionUncertain) -Cmdlet $PSCmdlet -Terminating

    Refuses the sign-in of Invoke-OERStructure, which names no tenant, after an earlier sign-in failed.
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '',
        Justification = 'Pure in-memory error-record builder; returns an ErrorRecord and performs no state change, so ShouldProcess does not apply.')]
    [CmdletBinding()]
    [OutputType([System.Management.Automation.ErrorRecord])]
    param(
        [Parameter(Mandatory)]
        [string]$Command,

        [switch]$SessionUncertain
    )
    [string]$Message = if ($SessionUncertain) {
        "An earlier sign-in in this PowerShell session failed or was refused, so the module's session " +
        "is not the one that sign-in asked for, and Omnicit.EntraRBAC sends nothing for a command that " +
        "names no tenant: this request was not sent. Name the tenant with -TenantId, or run Connect-OER or " +
        "Disconnect-OER, to send requests again."
    }
    else {
        "The module's sign-in for this command was refused, so Omnicit.EntraRBAC sends nothing for " +
        "this command: this request was not sent. Run Connect-OER, or run a new command whose " +
        "sign-in succeeds, to send requests again."
    }
    [System.Management.Automation.ErrorRecord]::new(
        [System.Exception]::new($Message),
        'SignInRefused',
        [System.Management.Automation.ErrorCategory]::AuthenticationError,
        $Command)
}
