function Resolve-OERApproverInput {
    <#
    .SYNOPSIS
    Resolves the -ApproverUser and -ApproverGroup values of a Microsoft Graph PIM policy cmdlet to
    object ids.

    .DESCRIPTION
    The single owner of how the Microsoft Graph PIM policy cmdlets -- Set-OERGroupPimPolicy and
    Set-OERDirectoryRoleManagementPolicy -- turn approver values into object ids. Each user value (a
    user principal name or object id) is resolved through Resolve-OERPrincipal -User and each group
    value (a display name or object id) through Resolve-OERPrincipal -Group. An empty or
    whitespace-only value is skipped, never resolved -- the same rule Resolve-OERDeclaredApprover
    applies to a document. The same principal named twice on one side (a user principal name and its
    id, or an id in another letter case) is kept once, in first-seen order; the user and group sides
    are de-duplicated separately.

    Resolution is all or nothing: the first value that does not resolve throws, so a caller never
    goes on with a partial list, and the throw tells three outcomes apart. Only a value that matches
    nothing (Resolve-OERPrincipal's PrincipalUnresolved record) is wrapped: an ErrorRecord with
    category ObjectNotFound, the value that did not resolve as its TargetObject, the resolver's
    message as its message and the resolver's exception as its inner exception; the caller reports it
    under its own ApproverNotFound id, with that message and target. Its ErrorId is
    ApproverUnresolved, deliberately NOT ApproverNotFound: PowerShell also collects a record thrown
    inside a nested command into the calling cmdlet's -ErrorVariable, even when the cmdlet catches
    it, so an ApproverNotFound thrown here would sit next to the one the cmdlet writes and a caller
    counting ApproverNotFound records would see it several times. An ambiguous display name (the
    resolver's AmbiguousName record, naming the candidate ids) and a lookup that failed (a 403, an
    exhausted 429, a 5xx) are not a missing approver: each is scrubbed and rethrown exactly as it was
    thrown, so the caller can report the first as AmbiguousApproverName and the second as itself.
    Returns one object whose User and Group are [string[]] arrays of object ids (empty when nothing
    was supplied). Makes one Resolve-OERPrincipal call per non-blank value; no other Graph call.

    .PARAMETER User
    The user approver values, each a user principal name or user object id. $null or an empty list
    resolves to no user.

    .PARAMETER Group
    The group approver values, each a group display name or group object id. $null or an empty list
    resolves to no group.

    .EXAMPLE
    Resolve-OERApproverInput -User 'person1@example.com' -Group 'PIM Approvers'
    Returns an object whose User holds the user's object id and whose Group holds the group's.
    #>
    [OutputType([PSCustomObject])]
    [CmdletBinding()]
    param(
        [AllowNull()]
        [AllowEmptyCollection()]
        [string[]]$User,

        [AllowNull()]
        [AllowEmptyCollection()]
        [string[]]$Group
    )

    $ResolvedUser = [System.Collections.Generic.List[string]]::new()
    $ResolvedGroup = [System.Collections.Generic.List[string]]::new()
    $SeenUser = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    $SeenGroup = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    $Value = $null
    try {
        foreach ($Value in @($User)) {
            if ([string]::IsNullOrWhiteSpace($Value)) { continue }
            $PrincipalId = [string](Resolve-OERPrincipal -User $Value).PrincipalId
            if ($SeenUser.Add($PrincipalId)) { $ResolvedUser.Add($PrincipalId) }
        }
        foreach ($Value in @($Group)) {
            if ([string]::IsNullOrWhiteSpace($Value)) { continue }
            $PrincipalId = [string](Resolve-OERPrincipal -Group $Value).PrincipalId
            if ($SeenGroup.Add($PrincipalId)) { $ResolvedGroup.Add($PrincipalId) }
        }
    } catch {
        Remove-OERErrorRecord -Record $PSItem
        # Only a value that matches nothing is a missing approver. An ambiguous name and a failed
        # lookup leave as they were thrown, for the caller to report as what they are.
        if (-not ([string]$PSItem.FullyQualifiedErrorId).StartsWith('PrincipalUnresolved', [System.StringComparison]::Ordinal)) {
            throw
        }
        throw [System.Management.Automation.ErrorRecord]::new(
            [System.Exception]::new($PSItem.Exception.Message, $PSItem.Exception),
            'ApproverUnresolved',
            [System.Management.Automation.ErrorCategory]::ObjectNotFound,
            $Value)
    }

    [PSCustomObject]@{
        User  = [string[]]$ResolvedUser.ToArray()
        Group = [string[]]$ResolvedGroup.ToArray()
    }
}
