function Test-OERSessionUsable {
    <#
    .SYNOPSIS
    Tells whether a sign-in that names this tenant, or none, may take the module's session as its
    source of defaults.

    .DESCRIPTION
    The single owner of whether the module's sign-in state is usable by a sign-in for the tenant
    named. It returns $true when the module holds a sign-in state and either no tenant is named (an
    empty -TenantId) or the state's TenantId, the tenant as it was NAMED when the state was built, is
    the tenant named now. The comparison is PowerShell's case-insensitive -eq on the name as given,
    never on the tenant ID a token was issued for: a tenant named by domain on one command and by its
    tenant ID on another is two names, and the second does not take the first's session.

    For a sign-in that passes no -AuthMethod and no -ClientId, this is whether it inherits the
    session's identity (method, client, cloud and tenant): Initialize-OERAuth takes its defaults from
    the state exactly when this answers $true, and signs in itself, as the identity it was asked for,
    when it answers $false. Checkpoint-OERSignIn asks the same question for a command that signs in
    naming a tenant, so a command's refusal of a changed session and the sign-in it guards cannot
    drift apart. Nothing else reads the state's TenantId for this decision.

    The function reads module state and changes none; it sends no request and reads no token.

    .PARAMETER TenantId
    The tenant the sign-in names, as the caller wrote it. An empty value, or none, names no tenant:
    the sign-in is then for whichever tenant the session is for.

    .EXAMPLE
    Test-OERSessionUsable -TenantId '44444444-4444-4444-4444-444444444444'

    Returns $true when the module is signed in and the session was built for exactly that tenant name.

    .EXAMPLE
    Test-OERSessionUsable -TenantId ''

    Returns $true whenever the module holds a sign-in state, whichever tenant it is for.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [AllowEmptyString()]
        [string]$TenantId
    )

    # An empty -TenantId (Connect-OER passes '' when neither -TenantId nor -TenantAlias is bound) names
    # no tenant, so it is emptiness and not $PSBoundParameters.ContainsKey that reads as "none".
    [bool]$script:_OERAuthState -and
        (-not $TenantId -or $script:_OERAuthState.TenantId -eq $TenantId)
}
