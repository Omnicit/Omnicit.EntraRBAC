function Get-OERSignInIdentity {
    <#
    .SYNOPSIS
    Returns the identity the module's sign-in state carries, as one string, or nothing.

    .DESCRIPTION
    The single owner of what a sign-in's identity is. Returns the four terms of the module's auth
    state that name who the module is signed in as and where -- TenantId, AuthMethod, ClientId and
    Environment, in that order, each as a string (a missing one reads as an empty string) -- joined
    with a line feed. These are the terms Initialize-OERAuth's ARM identity predicate compares. Returns
    nothing when the module holds no auth state.

    The result never carries a token, an account name or any other field of the state: only these four
    terms. Register-OERSignInIdentity remembers it for a command whose sign-in succeeded,
    Get-OERSignInSupersession compares each remembered value with the one this function returns now,
    and Checkpoint-OERSignIn takes it as the snapshot of the session a command began with and
    compares that snapshot with it again later.

    .EXAMPLE
    $Identity = Get-OERSignInIdentity

    Reads the identity the module is signed in as, or $null when it is not signed in.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param()

    $State = $script:_OERAuthState
    if ($null -eq $State) {
        return
    }
    @([string]$State.TenantId, [string]$State.AuthMethod, [string]$State.ClientId, [string]$State.Environment) -join "`n"
}
