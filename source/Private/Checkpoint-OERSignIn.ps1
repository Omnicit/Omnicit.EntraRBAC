function Checkpoint-OERSignIn {
    <#
    .SYNOPSIS
    Takes a snapshot of the identity the module's sign-in state carries, or tells whether that identity
    has changed since an earlier snapshot.

    .DESCRIPTION
    The single owner of the session a command began with. Without -ChangedSince it returns a snapshot:
    an Omnicit.EntraRBAC.SignInSnapshot object whose only property, Identity, holds what
    Get-OERSignInIdentity returns now -- the tenant, method, client, cloud and account the module's
    state carries, as one string, never a token -- or $null when the module holds no state. With
    -ChangedSince it returns $true when the identity the state carries now differs from the
    snapshot's, and $false when it does not. The comparison is PowerShell's case-insensitive -eq, as
    Get-OERSignInSupersession compares the same string: no state matches a snapshot of no state and
    differs from every other.

    Invoke-OERStructure, and the three builders that sign in only when they look up a name
    (New-OERAccessPackageApprovalStage, New-OERAccessPackageRequestorScope, New-OERAccessReviewStage),
    take a snapshot in their begin block. In a pipeline every begin block runs before any process
    block, so the snapshot holds the session from before any later command in the pipeline signed
    in. Each of them compares in its process block, before the sign-in or lookup that would inherit
    whatever session the module holds by then, and refuses with SignInSuperseded, sending nothing,
    when the identity changed. A sign-in that names no tenant inherits whatever session the module
    holds; one that names a tenant (-TenantId) inherits it only when Test-OERSessionUsable says the
    session is for that tenant as named (BL-90). So a command compares with its -TenantId, when it has
    one; it is refused in that case too, also when the module held no session as it began, while a
    command naming a tenant the session is not for signs in itself, as the identity it asked for,
    and is not refused. Invoke-OERStructure compares for each document after the
    document is read and validated, directly before its sign-in, and takes the snapshot again after
    every sign-in, refused or not, so the next piped document is compared with the session that
    sign-in left. The builders compare directly before their first lookup call (Resolve-OERTargetList
    or Resolve-OERReviewerScope), after their own argument checks and whether or not a value is a
    name -- New-OERAccessPackageRequestorScope only when it has -User or -Group targets to resolve
    for SpecificDirectoryUsers -- and take no pipeline input, so they never take it again.

    The snapshot is a value the command keeps in its own variable, not module state: nothing outside
    the command reads it, and it ends with the command.

    .PARAMETER ChangedSince
    A snapshot an earlier call returned. When given, the function compares instead of taking a new
    snapshot.

    .PARAMETER TenantId
    The tenant the sign-in that follows the comparison names, as the command received it. Only with
    -ChangedSince. When it is not empty the function returns $true only when the identity changed AND
    Test-OERSessionUsable says a sign-in naming this tenant takes the module's session (the state
    exists and was built for exactly this tenant name): a sign-in naming a tenant inherits the
    session's identity only then, and otherwise signs in itself as the identity it was asked for, so
    the identity another command left is not the one it would use. When it is empty or not given,
    the function compares the identity alone.

    .EXAMPLE
    $SignInSnapshot = Checkpoint-OERSignIn

    Takes a snapshot of the identity the module is signed in as, in a command's begin block.

    .EXAMPLE
    if (Checkpoint-OERSignIn -ChangedSince $SignInSnapshot) { ... }

    Tells whether another command has signed in to a different tenant or identity since the snapshot.

    .EXAMPLE
    if (Checkpoint-OERSignIn -ChangedSince $SignInSnapshot -TenantId $TenantId) { ... }

    Tells the same, but only when a sign-in naming that tenant would take the session another command
    left.
    #>
    [CmdletBinding(DefaultParameterSetName = 'Take')]
    [OutputType([PSCustomObject], ParameterSetName = 'Take')]
    [OutputType([bool], ParameterSetName = 'Compare')]
    param(
        [Parameter(ParameterSetName = 'Compare', Mandatory)]
        [PSTypeName('Omnicit.EntraRBAC.SignInSnapshot')]
        [PSCustomObject]$ChangedSince,

        [Parameter(ParameterSetName = 'Compare')]
        [AllowEmptyString()]
        [string]$TenantId
    )

    $Identity = Get-OERSignInIdentity
    if ($PSCmdlet.ParameterSetName -eq 'Compare') {
        # $null -eq $null is $true, and a string is never -eq to $null in either order, so no state
        # matches only a snapshot of no state.
        [bool]$Changed = -not ($ChangedSince.Identity -eq $Identity)
        # BL-90: a sign-in that names a tenant inherits the session's identity only when the session
        # is for that tenant as named (Test-OERSessionUsable, the term Initialize-OERAuth reads for
        # its own defaults); otherwise it signs in as the identity it was asked for, and the identity
        # another command left is not the one it would use.
        if ($Changed -and $TenantId) {
            return (Test-OERSessionUsable -TenantId $TenantId)
        }
        return $Changed
    }
    $Out = [PSCustomObject]@{ Identity = $Identity }
    $Out.PSObject.TypeNames.Insert(0, 'Omnicit.EntraRBAC.SignInSnapshot')
    $Out
}
