function Resolve-OERDeclaredApprover {
    <#
    .SYNOPSIS
    Resolves a declared roleManagementPolicies[] approvers block from names to object ids.

    .DESCRIPTION
    Runs before every approval diff -- both the group pimPolicy block and each roleManagementPolicies[]
    entry -- so the diff that follows compares ids with ids, never a name with an id. approvers.users
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
    sees it as undeclared. Throws the message Resolve-OERPrincipal raises (e.g. "User 'x' was not
    found." or "Group 'x' was not found.") when a declared value does not resolve; the caller is
    responsible for catching it and reporting a Failed record.

    .PARAMETER Declared
    One roleManagementPolicies[] entry, or a group pimPolicy block, as a PSCustomObject produced by
    ConvertFrom-Json. Only the requireApproval and approvers.users/approvers.groups properties are
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
    $Copy = $Declared.PSObject.Copy()
    $Copy.approvers = [PSCustomObject]$Resolved
    $Copy
}
