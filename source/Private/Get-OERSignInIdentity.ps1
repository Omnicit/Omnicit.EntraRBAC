function Get-OERSignInIdentity {
    <#
    .SYNOPSIS
    Returns the identity the module's sign-in state carries, as one string, or nothing.

    .DESCRIPTION
    The single owner of what a sign-in's identity is. Returns five terms of the module's auth state
    that name who the module is signed in as and where -- the tenant, AuthMethod, ClientId,
    Environment and the account, in that order, each as a string (a missing one reads as an empty
    string) -- joined with a line feed. Returns nothing when the module holds no auth state.

    The tenant term is the tenant the Microsoft Graph token was issued for (TokenTenantId) when that
    is a GUID, and the tenant as named (TenantId) otherwise; it is never the tenant the Azure Resource
    Manager token was issued for, since that token is not always acquired. Every named tenant, by GUID
    or by domain, is checked against the Graph token, so one tenant named by its domain on one command
    and by its tenant ID on another is one identity, and so is one named by no tenant at all once the
    token says which tenant it is.

    The account term (BL-119) is the state's SignInAccountId: the object id of the account the session
    was established as, a GUID string or empty. Initialize-OERAuth writes it so that a renewal never
    moves it: a renewal of the session (a Graph token renewed near its expiry, or a transport's
    refresh), or a sign-in continuing it under another label of the same tenant, carries it over from
    the old state, and one answered by another account is refused before the state is touched; any
    other sign-in sets it to the new token's oid when that is a GUID, else leaves it empty. A token
    without an oid, on either side, therefore never moves the identity on a renewal or such a
    continuation (any other sign-in, a Connect-OER whose token has no oid included, leaves the term
    empty). It is an object id, never a name, a user principal name or a token, and it is read from
    the state's own key, not from SignedInObjectId (the oid of the signed-in identity, read by the
    prune's self-protection).

    The result never carries a token, an account name or any other field of the state: only these five
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
    # BL-77: the tenant the Microsoft Graph token was issued for, when it is a GUID, and the tenant as
    # named otherwise. Since BL-12 every named tenant is checked against that token, so the granted
    # tenant is the one the session acts on; one tenant named by GUID on one command and by domain on
    # another, or not named at all, is then one identity. Never ArmTokenTenantId: the ARM token is not
    # always acquired, and the identity must not change when it is.
    [string]$Tenant = if (Test-OERGuid -Value ([string]$State.TokenTenantId)) {
        [string]$State.TokenTenantId
    } else {
        [string]$State.TenantId
    }
    # BL-119: the account, last. Initialize-OERAuth carries it over a renewal, so a renewal answered by
    # the same account (or by a token with no oid) leaves it alone; see .DESCRIPTION.
    @($Tenant, [string]$State.AuthMethod, [string]$State.ClientId, [string]$State.Environment,
        [string]$State.SignInAccountId) -join "`n"
}
