function ConvertTo-OERDirectoryRoleAssignment {
    <#
    .SYNOPSIS
    Converts a Microsoft Graph directory role eligibility or assignment schedule into a tagged object.

    .DESCRIPTION
    The single owner of the output shape of Get-OEREligibleDirectoryRoleAssignment and
    Get-OERActiveDirectoryRoleAssignment. Maps one unifiedRoleEligibilitySchedule (-Kind Eligible) or
    unifiedRoleAssignmentSchedule (-Kind Active) from Microsoft Graph v1.0 into a flat object tagged
    Omnicit.EntraRBAC.EligibleDirectoryRoleAssignment or Omnicit.EntraRBAC.ActiveDirectoryRoleAssignment.
    The schedule id is exposed as ScheduleId and the directory scope as DirectoryScopeId -- never as
    RoleEligibilityScheduleId or Scope, which Azure cmdlets bind from the pipeline. AssignmentType
    (Assigned or Activated) exists on Active objects only; an eligibility has no such field. The end
    of the window is scheduleInfo.expiration.endDateTime, or, when Graph returns only the requested
    duration, the start plus that duration; DurationDays is that window in whole days through
    Resolve-OEREligibilityDuration, and null for a permanent assignment. PrincipalType comes from the
    expanded principal's @odata.type. No Graph call is made.

    .PARAMETER InputObject
    One schedule object from Microsoft Graph, with principal and roleDefinition expanded.

    .PARAMETER Kind
    Eligible for a roleEligibilitySchedule, Active for a roleAssignmentSchedule.

    .EXAMPLE
    ConvertTo-OERDirectoryRoleAssignment -InputObject $Schedule -Kind Active
    Returns the tagged active directory role assignment object.
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
        $Start = $Info.startDateTime
        $Expiration = $Info.expiration
        $End = $Expiration.endDateTime
        if (-not $End -and $Expiration.duration -and $Start) {
            # ConvertFrom-OERDuration is the single ISO-to-number decoder (CLAUDE.md, duration
            # vocabulary); hours keep a whole-day or whole-hour window exact.
            $Hours = ConvertFrom-OERDuration -Duration ([string]$Expiration.duration) -Unit Hours
            $Parsed = [datetimeoffset]::MinValue
            if ($null -ne $Hours -and [datetimeoffset]::TryParse([string]$Start, [ref]$Parsed)) {
                $End = $Parsed.AddHours($Hours).UtcDateTime.ToString('o')
            }
        }
        $Principal = $InputObject.principal
        $PrincipalType = switch -Regex ([string]$Principal.'@odata.type') {
            'servicePrincipal$' { 'ServicePrincipal'; break }
            'group$' { 'Group'; break }
            'user$' { 'User'; break }
            default { $null }
        }
        $Out = [ordered]@{
            ScheduleId           = [string]$InputObject.id
            RoleDefinitionId     = [string]$InputObject.roleDefinitionId
            RoleName             = [string]$InputObject.roleDefinition.displayName
            PrincipalId          = [string]$InputObject.principalId
            PrincipalDisplayName = [string]$Principal.displayName
            PrincipalType        = $PrincipalType
            DirectoryScopeId     = [string]$InputObject.directoryScopeId
            MemberType           = [string]$InputObject.memberType
        }
        if ($Kind -eq 'Active') { $Out.AssignmentType = [string]$InputObject.assignmentType }
        $Out.Status = [string]$InputObject.status
        $Out.StartDateTime = $Start
        $Out.EndDateTime = $End
        $Out.ExpirationType = [string]$Expiration.type
        $Out.DurationDays = Resolve-OEREligibilityDuration -StartDateTime $Start -EndDateTime $End
        $Out.CreatedDateTime = $InputObject.createdDateTime
        $Result = [PSCustomObject]$Out
        $Result.PSObject.TypeNames.Insert(0, "Omnicit.EntraRBAC.$($Kind)DirectoryRoleAssignment")
        $Result
    }
}
