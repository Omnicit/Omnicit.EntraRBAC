function ConvertTo-OERGroupPimPolicyResult {
    <#
    .SYNOPSIS
    Builds the tagged Omnicit.EntraRBAC.GroupPimPolicyResult summary for a PIM-for-groups policy patch.

    .DESCRIPTION
    Set-OERGroupPimPolicy patches only the rules whose parameters the caller bound, so its result is a
    patch summary and not the resulting policy state. This converter owns that summary shape: the
    group, policy and access type identify the target, Applied and FailedRules report the outcome, and
    the fields in -Patched are the ONLY setting properties emitted. A field the caller never bound is
    absent rather than null or false, so the summary can no longer be mistaken for an authoritative
    read of the policy. The object carries Omnicit.EntraRBAC.GroupPimPolicy underneath its own type
    name so consumers written against the shared type keep working, while the Format view and
    TypeNames[0] resolve to the more specific result type.

    .PARAMETER GroupId
    The object id of the group whose policy was patched, stamped onto the summary for correlation.

    .PARAMETER PolicyId
    The roleManagementPolicy id that was patched, stamped onto the summary so a caller can re-read it.

    .PARAMETER AccessType
    The PIM access type whose policy was patched, either member or owner.

    .PARAMETER Patched
    An ordered hashtable of the setting name and value for each field that was actually sent to Graph;
    only these become properties on the summary object.

    .PARAMETER FailedRules
    The ids of the policy rules whose PATCH was rejected, empty when the whole patch was applied.

    .EXAMPLE
    ConvertTo-OERGroupPimPolicyResult -GroupId $Gid -PolicyId $Pid -AccessType member -Patched @{ ActivationMaxHours = 4 } -FailedRules @()
    Returns a summary reporting that only the activation maximum was changed and the patch succeeded.
    #>
    [OutputType([PSCustomObject])]
    [CmdletBinding()]
    param(
        [string]$GroupId,

        [string]$PolicyId,

        [string]$AccessType,

        [System.Collections.IDictionary]$Patched,

        [string[]]$FailedRules
    )
    process {
        $Fields = [ordered]@{
            GroupId    = $GroupId
            PolicyId   = $PolicyId
            AccessType = $AccessType
        }
        if ($Patched) {
            foreach ($Key in $Patched.Keys) { $Fields[[string]$Key] = $Patched[$Key] }
        }
        $Failed = @($FailedRules | Where-Object { $_ })
        $Fields['Applied'] = ($Failed.Count -eq 0)
        $Fields['FailedRules'] = $Failed
        $Out = [PSCustomObject]$Fields
        # The shared policy type goes on first so the more specific result type ends up at index 0 and
        # wins both view selection and a TypeNames[0] check, while PSTypeNames still contains the
        # shared name for any consumer written against it. Same pattern as RoleAssignmentResolved.
        $Out.PSObject.TypeNames.Insert(0, 'Omnicit.EntraRBAC.GroupPimPolicy')
        $Out.PSObject.TypeNames.Insert(0, 'Omnicit.EntraRBAC.GroupPimPolicyResult')
        $Out
    }
}
