function Resolve-OERDirectoryRoleInput {
    <#
    .SYNOPSIS
    Resolves a directory role name or id for a public cmdlet, returning the id or a routable failure.

    .DESCRIPTION
    The single owner of how the directory role assignment cmdlets report a -Role that does not
    resolve. Calls Resolve-OERDirectoryRoleDefinitionId and never throws and never writes to the error
    stream: it returns an object with RoleDefinitionId, ErrorId, Message, Category, TargetObject and
    InnerException, and the caller routes a failure through Write-CmdletError. ErrorId is
    AmbiguousRoleName (the name matches more than one role definition; the message lists the ids),
    RoleDefinitionReadFailed (the lookup itself failed, so whether the role exists is unknown -- never
    reported as not found), or RoleDefinitionNotFound. The texts are the ones
    Get-OERDirectoryRoleManagementPolicy reports.

    .PARAMETER Role
    A directory role display name (any letter case) or role definition id.

    .EXAMPLE
    $R = Resolve-OERDirectoryRoleInput -Role 'Reports Reader'
    Returns the role definition id in RoleDefinitionId, or an ErrorId the caller reports.
    #>
    [OutputType([PSCustomObject])]
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Role
    )
    $Result = [PSCustomObject]@{
        RoleDefinitionId = $null
        ErrorId          = $null
        Message          = $null
        Category         = $null
        TargetObject     = $Role
        InnerException   = $null
    }
    try {
        $Id = Resolve-OERDirectoryRoleDefinitionId -Role $Role
    } catch {
        Remove-OERErrorRecord -Record $PSItem
        $Result.InnerException = $PSItem.Exception
        if (Test-OERAmbiguousNameError -Record $PSItem) {
            $Result.ErrorId = 'AmbiguousRoleName'
            $Result.Category = 'InvalidArgument'
            $Result.Message = $PSItem.Exception.Message
        } else {
            $Result.ErrorId = 'RoleDefinitionReadFailed'
            $Result.Category = 'ReadError'
            $Result.Message = "Looking up the Microsoft Entra directory role '$Role' failed, so whether it " +
                "exists could not be determined: $($PSItem.Exception.Message)"
        }
        return $Result
    }
    if (-not $Id) {
        $Result.ErrorId = 'RoleDefinitionNotFound'
        $Result.Category = 'ObjectNotFound'
        $Result.Message = "No Microsoft Entra directory role definition named '$Role' was found. Use Tab " +
            'completion on -Role, or pass the role definition id directly.'
        return $Result
    }
    $Result.RoleDefinitionId = [string]$Id
    $Result
}
