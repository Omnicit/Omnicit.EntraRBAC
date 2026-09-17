function ConvertTo-OERGroupMember {
    <#
    .SYNOPSIS
    Converts a raw Graph group member/owner directory object into a tagged Omnicit.EntraRBAC.GroupMember.

    .DESCRIPTION
    Maps a directory object returned by groups/{id}/members or groups/{id}/owners into a
    [PSCustomObject] tagged Omnicit.EntraRBAC.GroupMember so Format views apply. The @odata.type is
    reduced to a friendly ObjectType (user, group, servicePrincipal, device); when the annotation is
    absent ObjectType is $null, matching ConvertTo-OERAdministrativeUnitMember. MemberType records
    whether the object came from the members or owners collection. PrincipalId is the member's own
    object id, stored once; the generic Id is an AliasProperty of PrincipalId, registered in
    suffix.ps1, rather than a second stored copy that could drift out of sync -- piped output still
    round-trips into Add-OERGroupMember and Remove-OERGroupMember via -PrincipalId
    ValueFromPipelineByPropertyName binding, and every existing .Id read keeps resolving to the same
    value. This private converter is the single owner of the group-member output shape and is used by
    Get-OERGroupMember and Get-OERGroup -IncludeMembers.

    .PARAMETER InputObject
    The raw Graph directory object (hashtable or PSObject) to convert. Accepts pipeline input.

    .PARAMETER GroupId
    The id of the group the member/owner belongs to, stamped onto the output.

    .PARAMETER MemberType
    Whether the object is a Member or an Owner of the group.

    .EXAMPLE
    ConvertTo-OERGroupMember -InputObject $obj -GroupId 'g1' -MemberType 'Member'
    Converts a single group member into a tagged object.
    #>
    [OutputType([PSCustomObject])]
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
        $InputObject,

        [string]$GroupId,

        [ValidateSet('Member', 'Owner')]
        [string]$MemberType = 'Member'
    )
    process {
        $OdataType = $InputObject.'@odata.type'
        $ObjectType = if ($OdataType) { ([string]$OdataType -replace '^#microsoft\.graph\.', '') } else { $null }
        $Out = [PSCustomObject]@{
            PrincipalId       = $InputObject.id
            DisplayName       = $InputObject.displayName
            UserPrincipalName = $InputObject.userPrincipalName
            ObjectType        = $ObjectType
            MemberType        = $MemberType
            GroupId           = $GroupId
        }
        $Out.PSObject.TypeNames.Insert(0, 'Omnicit.EntraRBAC.GroupMember')
        $Out
    }
}
