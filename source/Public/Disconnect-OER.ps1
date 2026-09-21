function Disconnect-OER {
    <#
    .SYNOPSIS
    Clears the cached Omnicit.EntraRBAC authentication state and disconnects Microsoft Graph.

    .DESCRIPTION
    Removes the in-memory authentication cache used by Initialize-OERAuth, including the cached
    Microsoft Graph and Azure Resource Manager tokens and the session's tenant and cloud, and
    disconnects the Microsoft Graph session (Disconnect-MgGraph). After calling this command the
    next OER cmdlet will trigger a fresh sign-in.

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
