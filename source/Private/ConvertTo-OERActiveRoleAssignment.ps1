function ConvertTo-OERActiveRoleAssignment {
    <#
    .SYNOPSIS
    Converts a raw ARM roleAssignmentSchedule into a tagged
    Omnicit.EntraRBAC.ActiveRoleAssignment object.

    .DESCRIPTION
    Maps a roleAssignmentSchedule list/read item (a current active assignment, either directly
    assigned or activated from an eligibility) into a flat PSCustomObject. RoleAssignmentScheduleId is
    the FULL ARM resource id, stored once; the generic Id is an AliasProperty of RoleAssignmentScheduleId,
    registered in suffix.ps1, rather than a second stored copy that could drift out of sync -- the
    pipeline-alias convention keeps working because the alias binds through
    ValueFromPipelineByPropertyName. AssignmentType is Activated or Assigned;
    LinkedRoleEligibilityScheduleId is set when the active assignment was activated from an
    eligibility. Friendly RoleName/PrincipalDisplayName come from expandedProperties. The ABAC
    condition set at grant time is projected as Condition/ConditionVersion so it can be read back;
    New-OERActiveRoleAssignment writes those fields and they were previously invisible on read.

    .PARAMETER InputObject
    The raw roleAssignmentSchedule object (PSCustomObject) returned by the ARM PIM API.

    .EXAMPLE
    ConvertTo-OERActiveRoleAssignment -InputObject $Item
    Returns the tagged active role assignment object.
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
            RoleAssignmentScheduleId        = [string]$InputObject.id
            Name                            = [string]$InputObject.name
            Scope                           = [string]$P.scope
            RoleDefinitionId                = [string]$P.roleDefinitionId
            RoleName                        = [string]$P.expandedProperties.roleDefinition.displayName
            PrincipalId                     = [string]$P.principalId
            PrincipalDisplayName            = [string]$P.expandedProperties.principal.displayName
            PrincipalType                   = [string]$P.principalType
            Status                          = [string]$P.status
            MemberType                      = [string]$P.memberType
            AssignmentType                  = [string]$P.assignmentType
            Condition                       = if ($null -ne $P.condition) { [string]$P.condition } else { $null }
            ConditionVersion                = if ($null -ne $P.conditionVersion) { [string]$P.conditionVersion } else { $null }
            StartDateTime                   = $P.startDateTime
            EndDateTime                     = $P.endDateTime
            CreatedOn                       = $P.createdOn
            UpdatedOn                       = $P.updatedOn
            LinkedRoleEligibilityScheduleId = if ($P.PSObject.Properties['linkedRoleEligibilityScheduleId']) { [string]$P.linkedRoleEligibilityScheduleId } else { $null }
            RoleAssignmentScheduleRequestId = [string]$P.roleAssignmentScheduleRequestId
        }
        $Out.PSObject.TypeNames.Insert(0, 'Omnicit.EntraRBAC.ActiveRoleAssignment')
        $Out
    }
}
