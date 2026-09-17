function ConvertTo-OERAdministrativeUnit {
    <#
    .SYNOPSIS
    Converts a raw Microsoft Graph administrative unit into a tagged Omnicit.EntraRBAC.AdministrativeUnit object.

    .DESCRIPTION
    Maps the relevant properties of a Graph administrativeUnit (returned by Invoke-OERGraphRequest as a
    hashtable) into a [PSCustomObject] tagged with the type name Omnicit.EntraRBAC.AdministrativeUnit so
    Format and Types views apply. MembershipType defaults to Assigned when the Graph object omits it
    (Graph leaves it null for assigned units). This private converter is the single owner of the AU output
    shape and is used by New/Get/Set-OERAdministrativeUnit.

    .PARAMETER InputObject
    The raw Graph administrativeUnit object (hashtable or PSObject) to convert into a tagged object.

    .EXAMPLE
    $Au = ConvertTo-OERAdministrativeUnit -InputObject (Invoke-OERGraphRequest -Uri 'v1.0/directory/administrativeUnits/au-1')
    Converts a single fetched administrative unit into a tagged object.
    #>
    [OutputType([PSCustomObject])]
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
        $InputObject
    )
    process {
        $MembershipType = if ($InputObject.membershipType) { $InputObject.membershipType } else { 'Assigned' }
        $Out = [PSCustomObject]@{
            Id                            = $InputObject.id
            DisplayName                   = $InputObject.displayName
            Description                   = $InputObject.description
            MembershipType                = $MembershipType
            MembershipRule                = $InputObject.membershipRule
            MembershipRuleProcessingState = $InputObject.membershipRuleProcessingState
            IsMemberManagementRestricted  = [bool]$InputObject.isMemberManagementRestricted
            Visibility                    = $InputObject.visibility
        }
        $Out.PSObject.TypeNames.Insert(0, 'Omnicit.EntraRBAC.AdministrativeUnit')
        $Out
    }
}
