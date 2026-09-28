function Get-OERGroupPermanentEligibilityState {
    <#
    .SYNOPSIS
    Reports whether a group's PIM-for-groups policy currently allows permanent eligible assignments.

    .DESCRIPTION
    Resolves the roleManagementPolicy governing a group's PIM-for-groups access (member or owner) via
    the private Get-OERPimGroupPolicyId and inspects its Expiration_Admin_Eligibility rule. A lookup
    that returns null (Microsoft Graph lists no policy for that access type, in practice for a group
    created moments ago) or throws is reported as no policy (the throw is removed from $Error). A group
    that was never used with PIM for Groups is not such a case: Graph lists its policies before the
    group is onboarded. The result reports HasPolicy (whether a policy is listed), the PolicyId, and
    PermanentAllowed (true only when the eligibility rule does NOT require expiration; a missing rule
    yields true so no unjustified policy write is attempted). This is a pure read used by the permanent
    self-heal in Add-OERGroupEligibility. The rules read is guarded: Invoke-OERGraphRequest already
    converts any non-recoverable failure into a sanitized ErrorRecord before throwing it, so the catch
    here only scrubs that record from $global:Error and rethrows it unchanged, preserving the real
    Graph error code for the caller instead of destroying it with a second conversion pass.

    .PARAMETER GroupId
    The object id of the group whose PIM-for-groups eligibility policy state is read.

    .PARAMETER AccessType
    Which access policy to inspect: 'member' (default) or 'owner'.

    .EXAMPLE
    Get-OERGroupPermanentEligibilityState -GroupId '00000000-0000-0000-0000-000000000001' -AccessType member
    Returns whether the group's member eligibility policy allows permanent assignments.
    #>
    [OutputType([PSCustomObject])]
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$GroupId,

        [ValidateSet('member', 'owner')]
        [string]$AccessType = 'member'
    )

    $PolicyId = try { Get-OERPimGroupPolicyId -GroupId $GroupId -AccessType $AccessType } catch { Remove-OERErrorRecord -Record $PSItem; $null }
    if (-not $PolicyId) {
        return [PSCustomObject]@{ HasPolicy = $false; PolicyId = $null; PermanentAllowed = $false }
    }

    # SECURITY: guard the read so a swallowed failure record is scrubbed from $global:Error before it
    # is rethrown. Invoke-OERGraphRequest itself already routes every non-recoverable failure through
    # Convert-GraphHttpException, so the record caught here is already a sanitized, freshly built
    # ErrorRecord (never the raw Graph SDK exception carrying the bearer token) -- it is rethrown
    # unchanged (bare `throw`) so its real Graph error code and FullyQualifiedErrorId survive for the
    # caller instead of being destroyed by a second conversion pass. Callers must not have to remember
    # to do the $global:Error scrub for us.
    $Rules = try {
        @((Invoke-OERGraphRequest -Uri (Get-OERPimGroupsGraphPath -Path ("policies/roleManagementPolicies/{0}/rules" -f $PolicyId)) -All).value)
    } catch {
        Remove-OERErrorRecord -Record $PSItem
        throw
    }
    $Rule = $Rules | Where-Object { $PSItem.id -eq 'Expiration_Admin_Eligibility' } | Select-Object -First 1

    [PSCustomObject]@{
        HasPolicy        = $true
        PolicyId         = [string]$PolicyId
        PermanentAllowed = -not [bool]$Rule.isExpirationRequired
    }
}
