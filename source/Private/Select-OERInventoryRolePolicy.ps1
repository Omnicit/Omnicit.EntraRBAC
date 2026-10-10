function Select-OERInventoryRolePolicy {
    <#
    .SYNOPSIS
    Selects the Azure role management policies Export-OERInventory exports -- the single owner of that rule.

    .DESCRIPTION
    Without -AllRolePolicies, Export-OERInventory keeps a role's policy at a scope only when the role
    is in use exactly at that scope or the policy has been changed. This pure function makes that
    decision; it sends nothing, signs in to nothing and writes nothing but its result.

    Every side is keyed on the scope in its canonical form (ConvertTo-OERCanonicalScope) and the role
    definition guid, the last '/'-segment of the role definition id, compared without regard to letter
    case, so a subscription-scoped and a tenant-scoped id of one role match. A role assignment or an
    eligibility whose role definition id is empty is ignored. The scope must match exactly: an
    assignment or eligibility at a management group above, or at a resource group below, does not
    keep the policy. Each policy is decided in this order:

    1. a role assignment of its role stands at its scope: kept;
    2. an eligibility of its role stands at its scope: kept;
    3. it has been changed (Modified is $true): kept;
    4. it cannot be judged -- Modified is $null (no policy metadata), its role definition guid is
       empty, or its scope is one of -UnreadScope (a read the selection needs failed there): kept,
       and its scope is named in UnjudgedScopes;
    5. otherwise it is omitted.

    So a policy that cannot be judged is never dropped: it is kept and named.

    .PARAMETER Policy
    The candidates, as Get-OERInventoryRolePolicy emits them: Entry, Scope, RoleDefinitionId and
    Modified. Pass an empty array when there are none. A null element in this list or in the two
    below is skipped.

    .PARAMETER Assignment
    The role assignments read for the selection, objects with Scope and RoleDefinitionId (the
    Get-OERRoleAssignment output). Pass an empty array when there are none.

    .PARAMETER Eligibility
    The eligibilities read for the selection, objects with Scope and RoleDefinitionId (the RoleScopes
    of Get-OERInventoryAzureEligibility). Pass an empty array when there are none.

    .PARAMETER UnreadScope
    The scopes whose role assignment read or eligibility read failed, so no policy there can be
    judged unused. Pass an empty array when there are none.

    .EXAMPLE
    Select-OERInventoryRolePolicy -Policy $Candidates -Assignment $Assignments -Eligibility $EligibilityScopes -UnreadScope @()
    Returns Kept, the entries of the kept policies in input order, and UnjudgedScopes, each scope
    whose policies were kept without being judged, once, in the order first seen.
    #>
    [OutputType([PSCustomObject])]
    [CmdletBinding()]
    param(
        # [AllowNull()] lets a null element bind (a mandatory array refuses one otherwise), so a
        # stray null in a list is skipped below instead of failing the whole selection.
        [Parameter(Mandatory)][AllowNull()][AllowEmptyCollection()][object[]]$Policy,
        [Parameter(Mandatory)][AllowNull()][AllowEmptyCollection()][object[]]$Assignment,
        [Parameter(Mandatory)][AllowNull()][AllowEmptyCollection()][object[]]$Eligibility,
        [Parameter(Mandatory)][AllowEmptyCollection()][string[]]$UnreadScope
    )
    # The role definition guid: the last '/'-segment of the role definition id.
    $RoleGuidOf = {
        param([string]$RoleDefinitionId)
        ($RoleDefinitionId -split '/')[-1]
    }
    # The scope|guid keys of the facts that stand at a scope, an empty role definition id ignored --
    # which also skips a null fact, whose role definition id reads as empty.
    $KeysOf = {
        param([object[]]$Fact)
        $Keys = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
        foreach ($Item in @($Fact)) {
            $Guid = & $RoleGuidOf ([string]$Item.RoleDefinitionId)
            if (-not $Guid) { continue }
            $null = $Keys.Add("$(ConvertTo-OERCanonicalScope -Scope ([string]$Item.Scope))|$Guid")
        }
        , $Keys
    }
    $AssignmentKeys = & $KeysOf $Assignment
    $EligibilityKeys = & $KeysOf $Eligibility
    $UnreadKeys = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($Unread in @($UnreadScope)) {
        if ([string]::IsNullOrWhiteSpace($Unread)) { continue }
        $null = $UnreadKeys.Add((ConvertTo-OERCanonicalScope -Scope $Unread))
    }

    $Kept = [System.Collections.Generic.List[object]]::new()
    $Unjudged = [System.Collections.Generic.List[string]]::new()
    $UnjudgedSeen = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($Candidate in @($Policy)) {
        if ($null -eq $Candidate) { continue }
        $CandidateScope = ConvertTo-OERCanonicalScope -Scope ([string]$Candidate.Scope)
        $CandidateGuid = & $RoleGuidOf ([string]$Candidate.RoleDefinitionId)
        $Key = "$CandidateScope|$CandidateGuid"
        if ($AssignmentKeys.Contains($Key)) { $Kept.Add($Candidate.Entry); continue }
        if ($EligibilityKeys.Contains($Key)) { $Kept.Add($Candidate.Entry); continue }
        if ($Candidate.Modified -eq $true) { $Kept.Add($Candidate.Entry); continue }
        if ($null -eq $Candidate.Modified -or -not $CandidateGuid -or $UnreadKeys.Contains($CandidateScope)) {
            $Kept.Add($Candidate.Entry)
            if ($UnjudgedSeen.Add($CandidateScope)) { $Unjudged.Add($CandidateScope) }
        }
    }
    [PSCustomObject]@{
        Kept           = $Kept.ToArray()
        UnjudgedScopes = $Unjudged.ToArray()
    }
}
