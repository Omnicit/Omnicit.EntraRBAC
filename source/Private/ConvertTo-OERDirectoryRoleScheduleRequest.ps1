function ConvertTo-OERDirectoryRoleScheduleRequest {
    <#
    .SYNOPSIS
    Converts a Microsoft Graph directory role eligibility or assignment schedule request response
    into a tagged Omnicit.EntraRBAC.DirectoryRoleScheduleRequest object.

    .DESCRIPTION
    The single owner of the output shape of New-/Remove-OEREligibleDirectoryRoleAssignment and
    New-/Remove-OERActiveDirectoryRoleAssignment. Maps the POST response from
    roleManagement/directory/roleEligibilityScheduleRequests (-Kind Eligible) or
    roleAssignmentScheduleRequests (-Kind Active) into a flat object. The expiration is flattened
    into ExpirationType plus Duration/EndDateTime, mirroring the ARM ConvertTo-OERRoleScheduleRequest
    shape. No Graph call is made.

    .PARAMETER InputObject
    The raw schedule request object returned by Microsoft Graph.

    .PARAMETER Kind
    Eligible for a roleEligibilityScheduleRequest, Active for a roleAssignmentScheduleRequest.

    .EXAMPLE
    ConvertTo-OERDirectoryRoleScheduleRequest -InputObject $Response -Kind Eligible
    Returns the tagged eligible directory role schedule request object.
    #>
    [OutputType([PSCustomObject])]
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
        [object]$InputObject,

        [Parameter(Mandatory)]
        [ValidateSet('Eligible', 'Active')]
        [string]$Kind
    )
    process {
        $Info = $InputObject.scheduleInfo
        $Expiration = $Info.expiration
        $Out = [PSCustomObject]@{
            ScheduleRequestId = [string]$InputObject.id
            Kind              = $Kind
            Action            = [string]$InputObject.action
            Status            = [string]$InputObject.status
            RoleDefinitionId  = [string]$InputObject.roleDefinitionId
            PrincipalId       = [string]$InputObject.principalId
            DirectoryScopeId  = [string]$InputObject.directoryScopeId
            Justification     = if ($null -ne $InputObject.justification) { [string]$InputObject.justification } else { $null }
            ExpirationType    = [string]$Expiration.type
            StartDateTime     = $Info.startDateTime
            EndDateTime       = $Expiration.endDateTime
            Duration          = if ($null -ne $Expiration.duration) { [string]$Expiration.duration } else { $null }
            CreatedDateTime   = $InputObject.createdDateTime
        }
        $Out.PSObject.TypeNames.Insert(0, 'Omnicit.EntraRBAC.DirectoryRoleScheduleRequest')
        $Out
    }
}
