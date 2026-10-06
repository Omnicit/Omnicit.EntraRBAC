function Checkpoint-OERSignIn {
    <#
    .SYNOPSIS
    Takes a snapshot of the identity the module's sign-in state carries, or tells whether that identity
    has changed since an earlier snapshot.

    .DESCRIPTION
    The single owner of the session a command began with. Without -ChangedSince it returns a snapshot:
    an Omnicit.EntraRBAC.SignInSnapshot object whose only property, Identity, holds what
    Get-OERSignInIdentity returns now -- the tenant, method, client and cloud the module's state
    carries, as one string, never a token -- or $null when the module holds no state. With
    -ChangedSince it returns $true when the identity the state carries now differs from the
    snapshot's, and $false when it does not. The comparison is PowerShell's case-insensitive -eq, as
    Get-OERSignInSupersession compares the same string: no state matches a snapshot of no state and
    differs from every other.

    Invoke-OERStructure, and the three builders that sign in only when they look up a name
    (New-OERAccessPackageApprovalStage, New-OERAccessPackageRequestorScope, New-OERAccessReviewStage),
    take a snapshot in their begin block. In a pipeline every begin block runs before any process
    block, so the snapshot holds the session from before any later command in the pipeline signed
    in. Before such a command signs in in its process block without -TenantId -- a sign-in that would
    inherit whatever session the module holds by then -- it compares, and refuses with
    SignInSuperseded, sending nothing, when the identity changed.

    The snapshot is a value the command keeps in its own variable, not module state: nothing outside
    the command reads it, and it ends with the command.

    .PARAMETER ChangedSince
    A snapshot an earlier call returned. When given, the function compares instead of taking a new
    snapshot.

    .EXAMPLE
    $SignInSnapshot = Checkpoint-OERSignIn

    Takes a snapshot of the identity the module is signed in as, in a command's begin block.

    .EXAMPLE
    if (Checkpoint-OERSignIn -ChangedSince $SignInSnapshot) { ... }

    Tells whether another command has signed in to a different tenant or identity since the snapshot.
    #>
    [CmdletBinding(DefaultParameterSetName = 'Take')]
    [OutputType([PSCustomObject], ParameterSetName = 'Take')]
    [OutputType([bool], ParameterSetName = 'Compare')]
    param(
        [Parameter(ParameterSetName = 'Compare', Mandatory)]
        [PSTypeName('Omnicit.EntraRBAC.SignInSnapshot')]
        [PSCustomObject]$ChangedSince
    )

    $Identity = Get-OERSignInIdentity
    if ($PSCmdlet.ParameterSetName -eq 'Compare') {
        # $null -eq $null is $true, and a string is never -eq to $null in either order, so no state
        # matches only a snapshot of no state.
        return (-not ($ChangedSince.Identity -eq $Identity))
    }
    $Out = [PSCustomObject]@{ Identity = $Identity }
    $Out.PSObject.TypeNames.Insert(0, 'Omnicit.EntraRBAC.SignInSnapshot')
    $Out
}
