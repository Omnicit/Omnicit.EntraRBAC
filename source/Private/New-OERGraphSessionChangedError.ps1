function New-OERGraphSessionChangedError {
    <#
    .SYNOPSIS
    Builds the GraphSessionChanged error record.

    .DESCRIPTION
    The single owner of the GraphSessionChanged id and message. Initialize-OERAuth raises it at its
    entry and Invoke-OERGraphRequest before a Graph call, when the Microsoft Graph PowerShell SDK
    session in the process is not the one this module connected. The target is the module's own
    tenant, the one $script:_OERAuthState names. The message names no other tenant, no account and no
    token: the session that replaced the module's may belong to another tenant, and none of its values
    is repeated.

    .EXAMPLE
    throw (New-OERGraphSessionChangedError)

    Refuses the call with the GraphSessionChanged record.
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '',
        Justification = 'Pure in-memory error-record builder; returns an ErrorRecord and performs no state change, so ShouldProcess does not apply.')]
    [CmdletBinding()]
    [OutputType([System.Management.Automation.ErrorRecord])]
    param()
    [string]$Tenant = if ($script:_OERAuthState) { [string]$script:_OERAuthState.TenantId } else { '' }
    [System.Management.Automation.ErrorRecord]::new(
        [System.Exception]::new(
            "The Microsoft Graph PowerShell SDK session in this PowerShell process has changed since " +
            "Omnicit.EntraRBAC connected it for tenant '$Tenant': another Connect-MgGraph has replaced " +
            "it. Omnicit.EntraRBAC does not send its Microsoft Graph calls under a session it did not " +
            "connect, and it does not switch the session back by itself, since that would move the " +
            "other session's calls to this module's tenant. Run Connect-OER with the same sign-in you " +
            "used -- for an app-only session, its certificate or client secret -- to connect the module " +
            "again, or use a new PowerShell process."),
        'GraphSessionChanged',
        [System.Management.Automation.ErrorCategory]::AuthenticationError,
        $Tenant)
}
