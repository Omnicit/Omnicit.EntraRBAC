function Test-OERGroupPimInUse {
    <#
    .SYNOPSIS
    Decides whether a group uses PIM for Groups -- the single owner of that rule.

    .DESCRIPTION
    Microsoft Graph lists PIM-for-Groups policies for every group, including one never used with PIM
    for Groups, and the first policy update or eligibility request onboards the group, which cannot be
    undone. This helper decides "in use": the group has PIM eligibility (-EligibilityCount above 0, no
    request made), or one of its policies has been modified -- a non-empty lastModifiedDateTime,
    lastModifiedBy.id or lastModifiedBy.displayName, read in one request through
    Get-OERPimGroupsGraphPath. An untouched policy reports lastModifiedDateTime null and a
    lastModifiedBy whose id and displayName are null (Microsoft Learn, List roleManagementPolicies).
    A 404 ResourceNotFound means PIM does not know the group: not in use, but still Manageable --
    onboarding it is possible and has simply not happened yet. A 400 ResourceTypeNotSupported means
    PIM for Groups cannot manage the group at all -- Microsoft Learn names dynamic groups and groups
    synchronized from on-premises -- which this helper reports as neither in use NOR Manageable, as
    the sibling PIM-for-Groups reads (Get-OERGroup's eligibility read, Get-OERPimGroupPolicyId)
    already read it. Any other failure throws. The criterion is documented, not yet measured: see
    docs/development/rationale.md#pim-in-use-criterion.

    The returned object's Manageable property is the stable signal for "can this group ever be
    onboarded to PIM for Groups at all" -- $false only for the ResourceTypeNotSupported case. A
    caller deciding whether to warn about onboarding should branch on Manageable, never by matching
    the text of Reason, which is prose for a human and may be reworded.

    .PARAMETER GroupId
    The object id of the group whose use of PIM for Groups is decided.

    .PARAMETER EligibilityCount
    How many PIM eligibility entries the caller already read for the group; 0 when none or unread.

    .EXAMPLE
    Test-OERGroupPimInUse -GroupId '11111111-1111-1111-1111-111111111111'
    Returns InUse, the Reason for it, and whether the group is Manageable by PIM for Groups at all.
    #>
    [OutputType([PSCustomObject])]
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$GroupId,

        [int]$EligibilityCount = 0
    )
    $Result = {
        param([bool]$InUse, [string]$Reason, [bool]$Manageable = $true)
        $O = [PSCustomObject]@{ InUse = $InUse; Reason = $Reason; Manageable = $Manageable }
        $O.PSObject.TypeNames.Insert(0, 'Omnicit.EntraRBAC.GroupPimUsage')
        $O
    }
    if ($EligibilityCount -gt 0) { return (& $Result $true 'the group has PIM eligibility') }

    $Escaped = ConvertTo-OERODataFilterValue -Value $GroupId
    $Uri = Get-OERPimGroupsGraphPath -Path "policies/roleManagementPolicies?`$filter=scopeId eq '$Escaped' and scopeType eq 'Group'&`$select=id,lastModifiedDateTime,lastModifiedBy"
    # A 404 ResourceNotFound is read as a group PIM does not know at all, which is certainly not in
    # use. That is the answer measured live (2026-09-28) on the policy-ASSIGNMENT listing of the same
    # family (Get-OERPimGroupPolicyId); on this listing it is expected, not yet measured. It is
    # declared to the transport so it leaves no record in a caller's -ErrorVariable. The same code
    # with any other status is not that answer and is thrown, as is every other failure: the
    # callers account for a criterion they could not read, and never guess it.
    # A 400 ResourceTypeNotSupported is declared the same way and read as "PIM for Groups cannot
    # manage this group" (Microsoft Learn: a dynamic group, or one synchronized from on-premises),
    # which is certainly not in use -- the answer Get-OERGroup's eligibility read and
    # Get-OERPimGroupPolicyId already take from the same family. Left undeclared, every such group
    # threw here and turned a clean export into InventoryPartial.
    $Response = Invoke-OERGraphRequest -Uri $Uri -All -ExpectedErrorCode 'ResourceNotFound', 'ResourceTypeNotSupported'
    if (@($Response.PSObject.TypeNames) -contains 'Omnicit.EntraRBAC.GraphExpectedError') {
        if ([string]$Response.ExpectedErrorCode -eq 'ResourceTypeNotSupported') {
            return (& $Result $false 'PIM for Groups cannot manage the group (ResourceTypeNotSupported)' $false)
        }
        if (($Response.StatusCode -as [int]) -ne 404) {
            throw [System.Management.Automation.ErrorRecord]::new(
                [System.Exception]::new([string]$Response.Message),
                'ResourceNotFound',
                [System.Management.Automation.ErrorCategory]::ObjectNotFound,
                $GroupId)
        }
        return (& $Result $false 'PIM for Groups does not know the group (404 ResourceNotFound)')
    }

    foreach ($Policy in @($Response.value)) {
        if ($null -eq $Policy) { continue }
        if (-not [string]::IsNullOrWhiteSpace([string]$Policy.lastModifiedDateTime) -or
            -not [string]::IsNullOrWhiteSpace([string]$Policy.lastModifiedBy.id) -or
            -not [string]::IsNullOrWhiteSpace([string]$Policy.lastModifiedBy.displayName)) {
            return (& $Result $true 'a PIM policy of the group has been modified')
        }
    }
    & $Result $false 'no PIM policy of the group has been modified and no PIM eligibility was counted'
}
