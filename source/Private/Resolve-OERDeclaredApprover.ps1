function Resolve-OERDeclaredApprover {
    <#
    .SYNOPSIS
    Resolves the declared approvers of a roleManagementPolicies[] or directoryRoleManagementPolicies[]
    entry, or of a group pimPolicy block, from names to object ids.

    .DESCRIPTION
    Runs before every approval diff, for all three callers: Sync-OERStructureRoleManagementPolicy
    passes each roleManagementPolicies[] entry, Sync-OERStructureDirectoryRoleManagementPolicy each
    directoryRoleManagementPolicies[] entry, and Sync-OERStructureGroup each group pimPolicy block
    (member, owner, or the flat form) -- so the diff that follows compares ids with ids, never a name
    with an id. approvers.users
    entries resolve through Resolve-OERPrincipal -User (a user principal name or an object id both
    pass); approvers.groups entries resolve through Resolve-OERPrincipal -Group (a group display name
    or an object id both pass). Results are de-duplicated case-insensitively after resolution, so the
    same person declared twice -- once by UPN and once by their object id, or the same id in different
    letter case -- collapses to one entry instead of forcing a spurious change every run. Empty and
    whitespace-only entries are ignored. An approvers block that is omitted or explicitly null, or a
    document that declares requireApproval = false (the approvers are ignored downstream in that case,
    so resolving them would only risk a Failed record for a name that never mattered), returns the
    input object untouched -- the SAME reference, not a copy -- and makes no Resolve-OERPrincipal call
    at all. Otherwise the input is never mutated: a shallow copy is returned whose approvers property
    holds only the declared sides (users, groups), each as a de-duplicated array of object ids: a side
    the document does not declare is left off the copy's approvers object entirely, so the diff still
    sees it as undeclared.

    The first declared value that does not resolve throws, and the throw tells three outcomes apart,
    in the same shape Resolve-OERApproverInput uses for the cmdlets. A value that matches nothing
    (Resolve-OERPrincipal's PrincipalUnresolved record) throws an ErrorRecord with ErrorId
    ApproverUnresolved, category ObjectNotFound, the value as its TargetObject, the resolver's
    message (for example "User 'x' was not found." or "Group 'x' was not found.") as its message and
    the resolver's exception as its inner exception. ApproverUnresolved is internal: the caller
    reports it under its own ApproverNotFound id. An ambiguous display name (the resolver's
    AmbiguousName record, naming the candidate ids) and a lookup that failed (a 403, an exhausted
    429, a 5xx) are scrubbed and rethrown exactly as they were thrown, for the caller to report as
    AmbiguousApproverName and as itself. Either way the caller is responsible for catching the throw
    and reporting a Failed record before anything is written.

    .PARAMETER Declared
    One roleManagementPolicies[] or directoryRoleManagementPolicies[] entry, or a group pimPolicy
    block, as a PSCustomObject produced by ConvertFrom-Json. Only the requireApproval and approvers.users/approvers.groups properties are
    read; every other property is preserved unchanged on the returned copy.

    .EXAMPLE
    Resolve-OERDeclaredApprover -Declared $DocItem
    Returns a copy of $DocItem whose approvers.users and approvers.groups hold resolved object ids,
    or $DocItem itself when approvers is not declared or requireApproval is explicitly false.
    #>
    [OutputType([PSCustomObject])]
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [PSCustomObject]$Declared
    )
    if (-not (Test-OERDeclaredProperty -Node $Declared -Name 'approvers')) { return $Declared }
    if ((Test-OERDeclaredProperty -Node $Declared -Name 'requireApproval') -and -not [bool]$Declared.requireApproval) {
        return $Declared
    }

    $Resolved = [ordered]@{}
    $Text = $null
    try {
        foreach ($Side in @(@{ Key = 'users'; Kind = 'User' }, @{ Key = 'groups'; Kind = 'Group' })) {
            if (-not (Test-OERDeclaredProperty -Node $Declared.approvers -Name $Side.Key)) { continue }
            $Ids = [System.Collections.Generic.List[string]]::new()
            $Seen = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
            foreach ($Value in @($Declared.approvers.($Side.Key))) {
                $Text = [string]$Value
                if ([string]::IsNullOrWhiteSpace($Text)) { continue }
                $Lookup = @{ $Side.Kind = $Text }
                $Id = [string](Resolve-OERPrincipal @Lookup).PrincipalId
                if ($Seen.Add($Id)) { $Ids.Add($Id) }
            }
            $Resolved[$Side.Key] = $Ids.ToArray()
        }
    } catch {
        Remove-OERErrorRecord -Record $PSItem
        # Only a value that matches nothing is a missing approver -- the same shape
        # Resolve-OERApproverInput throws. An ambiguous name and a failed lookup leave as they were
        # thrown, for the handler to report as what they are.
        if (-not ([string]$PSItem.FullyQualifiedErrorId).StartsWith('PrincipalUnresolved', [System.StringComparison]::Ordinal)) {
            throw
        }
        throw [System.Management.Automation.ErrorRecord]::new(
            [System.Exception]::new($PSItem.Exception.Message, $PSItem.Exception),
            'ApproverUnresolved',
            [System.Management.Automation.ErrorCategory]::ObjectNotFound,
            $Text)
    }
    $Copy = $Declared.PSObject.Copy()
    $Copy.approvers = [PSCustomObject]$Resolved
    $Copy
}
