function ConvertTo-OEREligibleRoleAssignment {
    <#
    .SYNOPSIS
    Converts a raw ARM roleEligibilitySchedule into a tagged
    Omnicit.EntraRBAC.EligibleRoleAssignment object.

    .DESCRIPTION
    Maps a roleEligibilitySchedule list/read item into a flat PSCustomObject. RoleEligibilityScheduleId
    is the FULL ARM resource id, stored once; the generic Id is an AliasProperty of
    RoleEligibilityScheduleId, registered in suffix.ps1, rather than a second stored copy that could
    drift out of sync -- the result still pipes into Enable-OEREligibleRoleAssignment (which binds -Id)
    and Remove-OEREligibleRoleAssignment (which binds PrincipalId/RoleDefinitionId/Scope). Friendly
    RoleName/PrincipalDisplayName come from expandedProperties. The ABAC condition set at grant time
    is projected as Condition/ConditionVersion so it can be read back; New-OEREligibleRoleAssignment
    writes those fields and they were previously invisible on read.

    .PARAMETER InputObject
    The raw roleEligibilitySchedule object (PSCustomObject) returned by the ARM PIM API.

    .EXAMPLE
    ConvertTo-OEREligibleRoleAssignment -InputObject $Item
    Returns the tagged eligible role assignment object.
    #>
    [OutputType([PSCustomObject])]
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
        [object]$InputObject
    )
    process {
        $P = $InputObject.properties
        $Out = [PSCustomObject]@{
            RoleEligibilityScheduleId        = [string]$InputObject.id
            Name                             = [string]$InputObject.name
            Scope                            = [string]$P.scope
            RoleDefinitionId                 = [string]$P.roleDefinitionId
            RoleName                         = [string]$P.expandedProperties.roleDefinition.displayName
            PrincipalId                      = [string]$P.principalId
            PrincipalDisplayName             = [string]$P.expandedProperties.principal.displayName
            PrincipalType                    = [string]$P.principalType
            Status                           = [string]$P.status
            MemberType                       = [string]$P.memberType
            Condition                        = if ($null -ne $P.condition) { [string]$P.condition } else { $null }
            ConditionVersion                 = if ($null -ne $P.conditionVersion) { [string]$P.conditionVersion } else { $null }
            StartDateTime                    = $P.startDateTime
            EndDateTime                      = $P.endDateTime
            CreatedOn                        = $P.createdOn
            UpdatedOn                        = $P.updatedOn
            RoleEligibilityScheduleRequestId = [string]$P.roleEligibilityScheduleRequestId
        }
        $Out.PSObject.TypeNames.Insert(0, 'Omnicit.EntraRBAC.EligibleRoleAssignment')
        $Out
    }
}
