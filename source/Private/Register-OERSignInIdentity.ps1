function Register-OERSignInIdentity {
    <#
    .SYNOPSIS
    Remembers which identity a command signed in as, after its sign-in succeeded.

    .DESCRIPTION
    Called only by Initialize-OERAuth, directly after each of its two Unlock-OERSignIn calls: at its
    cached return, and as the last statement of a new connection that went the whole way. It stores
    the identity the module's state now carries (Get-OERSignInIdentity: tenant, method, client and
    cloud, never a token) for the given invocation -- the one Lock-OERSignIn returned at entry -- and
    replaces whatever that invocation remembered before. When the module holds no state it removes
    that invocation's entry instead, so the command is no longer compared.

    Both transports then read the memory through Get-OERSignInSupersession before every request and
    refuse a request made while any command on the call stack remembers another identity than the
    state now carries (SignInSuperseded). In a pipeline every begin block runs first, so without it
    New-OERGroup -TenantId A ... | Add-OERGroupMember -TenantId B would create the group in B.

    The table ($script:_OERSignInIdentity, created here on first use) is a ConditionalWeakTable keyed
    on the commands' own invocation objects, held weakly, so the table keeps no command alive, and used
    only for their identity: the decision is a lookup by reference and never reads a key.

    .PARAMETER Invocation
    The invocation of the command whose sign-in succeeded, exactly as Lock-OERSignIn returned it at the
    entry of the same Initialize-OERAuth call.

    .EXAMPLE
    Register-OERSignInIdentity -Invocation $SignInCaller

    Remembers the identity the command Lock-OERSignIn latched at the entry of this Initialize-OERAuth
    call signed in as.
    #>
    [CmdletBinding()]
    [OutputType([void])]
    param(
        [Parameter(Mandatory)]
        [System.Management.Automation.InvocationInfo]$Invocation
    )

    $Identity = Get-OERSignInIdentity
    if ($null -eq $Identity) {
        if ($null -ne $script:_OERSignInIdentity) {
            $null = $script:_OERSignInIdentity.Remove($Invocation)
        }
        return
    }

    if ($null -eq $script:_OERSignInIdentity) {
        $script:_OERSignInIdentity = [System.Runtime.CompilerServices.ConditionalWeakTable[object, object]]::new()
    }
    $script:_OERSignInIdentity.AddOrUpdate($Invocation, [string]$Identity)
}
