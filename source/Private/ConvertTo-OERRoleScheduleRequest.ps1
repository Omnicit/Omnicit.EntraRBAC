function ConvertTo-OERRoleScheduleRequest {
    <#
    .SYNOPSIS
    Converts a raw ARM role schedule request response into a tagged
    Omnicit.EntraRBAC.RoleScheduleRequest object.

    .DESCRIPTION
    Maps the role{Eligibility|Assignment}ScheduleRequest 201 response (both share this shape) into a
    flat PSCustomObject. Friendly RoleName/PrincipalDisplayName come from the response's
    expandedProperties (no extra lookups). The expiration is flattened into ExpirationType plus
    ExpirationDuration/ExpirationEndDateTime. LinkedRoleEligibilityScheduleId is present only on
    assignment (activation) requests. The ABAC condition and ticket information supplied on the
    request are projected as Condition/ConditionVersion and TicketNumber/TicketSystem so they can
    be read back.

    .PARAMETER InputObject
    The raw schedule request object (PSCustomObject) returned by the ARM PIM API.

    .EXAMPLE
    ConvertTo-OERRoleScheduleRequest -InputObject $Response
    Returns the tagged request object.
    #>
    [OutputType([PSCustomObject])]
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
        [object]$InputObject
    )
    process {
        $P = $InputObject.properties
        $Exp = $P.scheduleInfo.expiration
        $Out = [PSCustomObject]@{
            Id                              = [string]$InputObject.id
            Name                            = [string]$InputObject.name
            Scope                           = [string]$P.scope
            RoleDefinitionId                = [string]$P.roleDefinitionId
            RoleName                        = [string]$P.expandedProperties.roleDefinition.displayName
            PrincipalId                     = [string]$P.principalId
            PrincipalDisplayName            = [string]$P.expandedProperties.principal.displayName
            PrincipalType                   = [string]$P.principalType
            RequestType                     = [string]$P.requestType
            Status                          = [string]$P.status
            StartDateTime                   = $P.scheduleInfo.startDateTime
            ExpirationType                  = [string]$Exp.type
            ExpirationDuration              = [string]$Exp.duration
            ExpirationEndDateTime           = $Exp.endDateTime
            Justification                   = if ($null -ne $P.justification) { [string]$P.justification } else { $null }
            Condition                       = if ($null -ne $P.condition) { [string]$P.condition } else { $null }
            ConditionVersion                = if ($null -ne $P.conditionVersion) { [string]$P.conditionVersion } else { $null }
            TicketNumber                    = if ($null -ne $P.ticketInfo -and $null -ne $P.ticketInfo.ticketNumber) { [string]$P.ticketInfo.ticketNumber } else { $null }
            TicketSystem                    = if ($null -ne $P.ticketInfo -and $null -ne $P.ticketInfo.ticketSystem) { [string]$P.ticketInfo.ticketSystem } else { $null }
            ApprovalId                      = if ($null -ne $P.approvalId) { [string]$P.approvalId } else { $null }
            RequestorId                     = [string]$P.requestorId
            CreatedOn                       = $P.createdOn
            LinkedRoleEligibilityScheduleId = if ($P.PSObject.Properties['linkedRoleEligibilityScheduleId']) { [string]$P.linkedRoleEligibilityScheduleId } else { $null }
        }
        $Out.PSObject.TypeNames.Insert(0, 'Omnicit.EntraRBAC.RoleScheduleRequest')
        $Out
    }
}
