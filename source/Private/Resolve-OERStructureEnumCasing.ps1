function Resolve-OERStructureEnumCasing {
    <#
    .SYNOPSIS
    Resolves a structure-document enum value to its canonical spelling, or lists an enum's canonical set.

    .DESCRIPTION
    The single owner of every closed enum in the Phase 5 apply document. Two artifacts describe the
    same rule and used to describe it differently: Get-OERStructureSchemaJson emits a draft-07 schema,
    where "enum" matching is case-SENSITIVE, while Test-OERStructureSchema matched case-INSENSITIVELY.
    A document with "accessType": "Member" therefore passed Test-OERStructure and was rejected by the
    schema.json shipped in the same bundle. Both now read the canonical set from here:
    Test-OERStructureSchema keeps accepting any casing (so no document that validates today starts
    failing) but reports a Warning naming the canonical spelling, and Read-OERStructureDocument
    rewrites the value to the canonical spelling before the apply handlers build a Graph or ARM body.

    Given -Value, returns the canonical spelling when the value matches case-insensitively, and $null
    when it is not a member of the enum -- so a caller distinguishes "wrong casing" from "wrong value".
    Given -List, returns the whole canonical set in the order the schema declares it. Pure lookup: no
    Graph, ARM, or filesystem access.

    .PARAMETER EnumName
    The enum to resolve against. One of accessType, enablement, membershipRuleProcessingState,
    catalogResourceType, approverInfoVisibility, accessReviewRecurrence, accessReviewDefaultDecision,
    principalType. An unknown name is a caller error and fails parameter binding.

    .PARAMETER Value
    The document value to resolve. May be any casing, empty, or null; a value that is not a member of
    the enum returns $null rather than throwing.

    .PARAMETER List
    Returns the enum's full canonical set instead of resolving a single value.

    .EXAMPLE
    Resolve-OERStructureEnumCasing -EnumName 'accessType' -Value 'Member'
    Returns 'member', the spelling Get-OERStructureSchemaJson declares.

    .EXAMPLE
    Resolve-OERStructureEnumCasing -EnumName 'principalType' -List
    Returns User, Group, ServicePrincipal.
    #>
    [OutputType([string], ParameterSetName = 'Resolve')]
    [OutputType([string[]], ParameterSetName = 'List')]
    [CmdletBinding(DefaultParameterSetName = 'Resolve')]
    param(
        [Parameter(Mandatory, Position = 0)]
        [ValidateSet('accessType', 'enablement', 'membershipRuleProcessingState', 'catalogResourceType',
            'approverInfoVisibility', 'accessReviewRecurrence', 'accessReviewDefaultDecision', 'principalType')]
        [string]$EnumName,

        [Parameter(ParameterSetName = 'Resolve', Position = 1)]
        [AllowNull()][AllowEmptyString()]
        [string]$Value,

        [Parameter(Mandatory, ParameterSetName = 'List')]
        [switch]$List
    )
    # Order matters: the -List output is compared verbatim against the enums declared in
    # Get-OERStructureSchemaJson, so keep each set in the order the schema declares it.
    $CanonicalSet = @{
        accessType                    = @('member', 'owner')
        enablement                    = @('Justification', 'MultiFactorAuthentication', 'Ticketing')
        membershipRuleProcessingState = @('On', 'Paused')
        catalogResourceType           = @('Group', 'Application', 'SharePointSite')
        approverInfoVisibility        = @('Default', 'Visible', 'NotVisible')
        accessReviewRecurrence        = @('OneTime', 'Weekly', 'Monthly', 'Quarterly', 'Annually')
        accessReviewDefaultDecision   = @('None', 'Approve', 'Deny', 'Recommendation')
        principalType                 = @('User', 'Group', 'ServicePrincipal')
    }
    $Canonical = @($CanonicalSet[$EnumName])
    if ($List) {
        return [string[]]$Canonical
    }
    if ([string]::IsNullOrEmpty($Value)) {
        return $null
    }
    foreach ($Candidate in $Canonical) {
        # -eq on strings is case-insensitive, which is the whole point: any casing resolves.
        if ($Candidate -eq $Value) {
            return $Candidate
        }
    }
    return $null
}
