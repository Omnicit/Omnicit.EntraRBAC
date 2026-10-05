function Disconnect-OER {
    <#
    .SYNOPSIS
    Clears the cached Omnicit.EntraRBAC authentication state and disconnects Microsoft Graph.

    .DESCRIPTION
    Removes the in-memory authentication cache used by Initialize-OERAuth, including the cached
    Microsoft Graph and Azure Resource Manager tokens and the session's tenant and cloud, and
    disconnects the Microsoft Graph session (Disconnect-MgGraph). After calling this command the
    next OER cmdlet will trigger a fresh sign-in.

    Connect-OER sets up a Microsoft Graph PowerShell SDK session in the current process: it calls
    Connect-MgGraph with the module's token, and so does the automatic sign-in of any other OER
    cmdlet. If another Connect-MgGraph -- your own, or another tool's -- replaces that session in
    the same process, the next OER cmdlet sends nothing: it refuses its Microsoft Graph calls with a
    GraphSessionChanged error instead of sending them under that session, and its Azure Resource
    Manager calls with a SignInRefused error. An error can be reported more than once for one
    cmdlet. The module never switches the session back by itself:
    Connect-OER, run with the same sign-in the session used -- for an app-only session, its
    certificate or client secret, since a bare Connect-OER signs in interactively -- connects the
    module again and takes the session back, and a new PowerShell process is the other way.

    Disconnect-OER closes whichever Microsoft Graph PowerShell SDK session the process holds: it
    clears the module's state, including its record of the session the module connected, and calls
    Disconnect-MgGraph. After another Connect-MgGraph has replaced the module's session,
    Disconnect-OER therefore ends that other session too. If the session is closed with
    Disconnect-MgGraph instead of Disconnect-OER, the module keeps its state and the next OER cmdlet
    signs in again by itself, except on an app-only session (client secret or certificate), which
    reports AppOnlySessionCredentialUnavailable until Connect-OER is run with the secret or
    certificate.

    An Az PowerShell session you started yourself is deliberately LEFT ALONE. Omnicit.EntraRBAC
    never establishes an Az context: -IncludeARM only acquires an Azure Resource Manager token,
    which the module sends itself from its own Azure cmdlets. Any Az context on the machine
    therefore belongs to you, not to this module, and signing it out here would clear your own
    sign-in and your on-disk Az token cache as a side effect of ending an unrelated session.
    Use Disconnect-AzAccount yourself when you want that.

    Supports -WhatIf and -Confirm.

    .EXAMPLE
    Disconnect-OER
    Clears the cached Omnicit.EntraRBAC tokens and disconnects from Microsoft Graph. An Az
    PowerShell session started outside this module is left connected.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([void])]
    param()
    process {
        if ($PSCmdlet.ShouldProcess('Omnicit.EntraRBAC session', 'Disconnect and clear cached auth state')) {
            $script:_OERAuthState = $null
            Disconnect-MgGraph -ErrorAction SilentlyContinue | Out-Null
        }
    }
}
