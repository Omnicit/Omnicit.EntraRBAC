function Disconnect-OER {
    <#
    .SYNOPSIS
    Clears the cached Omnicit.EntraRBAC authentication state and disconnects Graph and Azure.

    .DESCRIPTION
    Removes the in-memory authentication cache used by Initialize-OERAuth and disconnects the
    Microsoft Graph session (Disconnect-MgGraph) and, when an Azure context exists, the Azure session
    (Disconnect-AzAccount). After calling this command the next OER cmdlet will trigger a fresh sign-in.
    Supports -WhatIf and -Confirm.

    .EXAMPLE
    Disconnect-OER
    Clears cached tokens and disconnects from Microsoft Graph and Azure.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([void])]
    param()
    process {
        if ($PSCmdlet.ShouldProcess('Omnicit.EntraRBAC session', 'Disconnect and clear cached auth state')) {
            $script:_OERAuthState = $null
            Disconnect-MgGraph -ErrorAction SilentlyContinue | Out-Null
            if (Get-Command Disconnect-AzAccount -ErrorAction SilentlyContinue) {
                Disconnect-AzAccount -ErrorAction SilentlyContinue | Out-Null
            }
        }
    }
}
