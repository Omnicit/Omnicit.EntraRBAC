function Disconnect-OER {
    <#
    .SYNOPSIS
    Clears the cached Omnicit.EntraRBAC authentication state and disconnects the Microsoft Graph session the module connected.

    .DESCRIPTION
    Removes the in-memory authentication cache used by Initialize-OERAuth, including the cached
    Microsoft Graph and Azure Resource Manager tokens and the session's tenant and cloud. After
    calling this command the next OER cmdlet will trigger a fresh sign-in.

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

    Disconnect-OER always clears the module's state, including its record of the Microsoft Graph
    PowerShell SDK session the module connected, and calls Disconnect-MgGraph only when the process
    still holds that session. A session the module did not connect, or holds no record of having
    connected -- one another Connect-MgGraph started or replaced the module's with, or one left by
    an earlier import of the module -- is left connected. Disconnect-OER writes a warning saying so
    before it asks for confirmation, so -WhatIf shows it; run Disconnect-MgGraph to end that session.
    The next OER cmdlet signs in again, and its own Connect-MgGraph then replaces that session, as
    any Connect-MgGraph does. This is the same stance as for an Az PowerShell session, below. If the
    session is closed with Disconnect-MgGraph instead of Disconnect-OER, the module keeps its state
    and the next OER cmdlet signs in again by itself, except on an app-only session (client secret
    or certificate), which reports AppOnlySessionCredentialUnavailable until Connect-OER is run with
    the secret or certificate.

    Disconnect-OER also ends the uncertainty a failed or refused sign-in leaves: after such a sign-in
    the module's session may not be the one that sign-in asked for, so an OER command that names no
    tenant sends nothing and reports a SignInRefused error. After Disconnect-OER there is no session to
    be uncertain about, and the next command signs in afresh.

    An Az PowerShell session you started yourself is deliberately LEFT ALONE. Omnicit.EntraRBAC
    never establishes an Az context: -IncludeARM only acquires an Azure Resource Manager token,
    which the module sends itself from its own Azure cmdlets. Any Az context on the machine
    therefore belongs to you, not to this module, and signing it out here would clear your own
    sign-in and your on-disk Az token cache as a side effect of ending an unrelated session.
    Use Disconnect-AzAccount yourself when you want that.

    Supports -WhatIf and -Confirm.

    .EXAMPLE
    Disconnect-OER
    Clears the cached Omnicit.EntraRBAC tokens and disconnects the Microsoft Graph session the
    module connected. An Az PowerShell session started outside this module, and a Graph SDK session
    the module did not connect, are left connected.

    .EXAMPLE
    Disconnect-OER; Disconnect-MgGraph
    Clears the module's session and also ends a Graph SDK session the module did not connect, which
    Disconnect-OER leaves connected with a warning.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([void])]
    param()
    process {
        # SEC (A4, BL-67): Disconnect-OER ends only the Microsoft Graph PowerShell SDK session the
        # module connected itself, the same stance as for an Az session: a session another
        # Connect-MgGraph started, or replaced the module's with, belongs to whoever started it.
        # Read once, here, before the state that holds the module's fingerprint is cleared, and before
        # the gate, so the warning below shows under -WhatIf and before a -Confirm prompt.
        $GraphSessionState = Get-OERGraphSessionState
        # A session that exists and is left: another one replaced the module's (Changed), or the module
        # holds no record of one of its own (Untracked) while the process holds a session -- one from
        # an earlier import of the module, say. The module cannot prove that one is its own, and
        # leaving it is the safe direction. Absent has no session, and Untracked with none has nothing
        # to leave.
        $LeavesOtherSession = ($GraphSessionState -eq 'Changed') -or
            ($GraphSessionState -eq 'Untracked' -and $null -ne (Get-OERGraphSessionFingerprint))
        if ($LeavesOtherSession) {
            Write-Warning ('Disconnect-OER leaves the Microsoft Graph PowerShell SDK session in this process ' +
                'connected, since Omnicit.EntraRBAC has no record of connecting it. Run Disconnect-MgGraph to end that session.')
        }
        if ($PSCmdlet.ShouldProcess('Omnicit.EntraRBAC session', 'Disconnect and clear cached auth state')) {
            $script:_OERAuthState = $null
            # SEC (A10, BL-89): with no session left, nothing is uncertain any more; a command that names
            # no tenant signs in afresh instead of being refused for an earlier failed sign-in.
            $null = Set-OERSessionUncertain -Value $false
            if ($GraphSessionState -eq 'Own') {
                Disconnect-MgGraph -ErrorAction SilentlyContinue | Out-Null
            }
        }
    }
}
