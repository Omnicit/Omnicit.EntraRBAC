function Get-OERSignInIdentity {
    <#
    .SYNOPSIS
    Returns the identity the module's sign-in state carries, as one string, or nothing.

    .DESCRIPTION
    The single owner of what a sign-in's identity is. Returns four terms of the module's auth state
    that name who the module is signed in as and where -- the tenant, AuthMethod, ClientId and
    Environment, in that order, each as a string (a missing one reads as an empty string) -- joined
    with a line feed. Returns nothing when the module holds no auth state.

    The tenant term is the tenant the Microsoft Graph token was issued for (TokenTenantId) when that
    is a GUID, and the tenant as named (TenantId) otherwise; it is never the tenant the Azure Resource
    Manager token was issued for, since that token is not always acquired. Every named tenant, by GUID
    or by domain, is checked against the Graph token, so one tenant named by its domain on one command
    and by its tenant ID on another is one identity, and so is one named by no tenant at all once the
    token says which tenant it is.

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
    @($Tenant, [string]$State.AuthMethod, [string]$State.ClientId, [string]$State.Environment) -join "`n"
}
