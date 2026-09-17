function Get-OERPimGroupsGraphPath {
    <#
    .SYNOPSIS
    Returns a PIM-for-Groups Microsoft Graph request path prefixed with the pinned API version.

    .DESCRIPTION
    Every PIM-for-Groups call in this module routes through this helper so the Graph API version is
    declared in exactly one place. The pin is deliberately 'beta' and is NOT an oversight: the v1.0
    API reference documents these operations as GA, but the Graph how-to 'Update rules in PIM by
    using Microsoft Graph' still states that PIM for groups APIs are available on the beta endpoint
    only, and the Entra 'Configure PIM for Groups settings' article still shows the beta URL for the
    policy query. Those pages contradict each other, and these are the paths that grant and revoke
    standing privilege in customer tenants, so the version stays pinned until a read-only v1.0 diff
    has been run against a real tenant. The eligibility paths and the four policy paths must move
    together: Get-OERPimGroupPolicyId returns the policy id that the policy readers and writers all
    consume, and Microsoft Learn warns that PIM policy and policy-assignment ids change when a group
    is onboarded. Changing the constant below migrates all call sites at once. The helper is pure:
    it makes no Graph call, validates nothing about the path, and only prefixes the version.

    .PARAMETER Path
    The Graph path relative to the API version, with or without a leading slash, for example
    'identityGovernance/privilegedAccess/group/eligibilityScheduleRequests'. Any query string is
    passed through untouched, so callers keep owning their own OData escaping.

    .EXAMPLE
    Get-OERPimGroupsGraphPath -Path 'policies/roleManagementPolicies'
    Returns 'beta/policies/roleManagementPolicies' with the currently pinned API version.

    .EXAMPLE
    Get-OERPimGroupsGraphPath -Path ('policies/roleManagementPolicies/{0}/rules' -f $PolicyId)
    Returns the rules collection path for a group's PIM policy under the pinned API version.
    #>
    [OutputType([string])]
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )
    # The single switch point. See .DESCRIPTION before changing it.
    $ApiVersion = 'beta'
    return ('{0}/{1}' -f $ApiVersion, $Path.TrimStart('/'))
}
