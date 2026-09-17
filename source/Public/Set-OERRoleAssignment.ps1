function Set-OERRoleAssignment {
    <#
    .SYNOPSIS
    Edits the description and ABAC condition of an existing Azure role assignment in place.

    .DESCRIPTION
    Azure Resource Manager allows exactly three properties of an existing role assignment to be edited --
    description, condition and conditionVersion -- and only by writing to the SAME role assignment id
    with the Role Assignments Create API (api-version 2022-04-01). Every other property must be sent
    matching the existing assignment. This cmdlet performs that read-modify-write through
    Invoke-OERArmRequest: it reads the live assignment, carries roleDefinitionId, principalId and
    principalType forward verbatim, overlays only the parameters that were actually bound, and PUTs the
    result back to the same id. New-OERRoleAssignment cannot do this -- it always mints a fresh
    assignment GUID, and ARM rejects a second assignment for the same scope, principal and role. The
    non-editable properties -- roleDefinitionId, principalId, principalType, and
    delegatedManagedIdentityResourceId (the Azure Lighthouse / cross-tenant delegation link, when
    present) -- are carried forward verbatim from the live read, because ARM requires them to match the
    existing assignment; omitting delegatedManagedIdentityResourceId on the PUT would silently destroy
    the delegation.

    Overlay contract: an omitted parameter PRESERVES the live value. Every overlay is gated on whether
    the parameter was bound, never on whether its value is truthy, because an empty string is
    meaningful: passing -Condition '' REMOVES the condition, and it clears conditionVersion with it.
    Removing a condition WIDENS the principal's access, so the cmdlet warns explicitly before that call
    and carries ConfirmImpact High. Supplying -Condition on an assignment that had none defaults
    conditionVersion to 2.0, matching the ARM default.

    A condition is cleared by OMITTING both keys from the PUT body, not by sending them empty. The REST
    documentation says to set both to "either an empty string or null", but ARM rejects an empty
    conditionVersion outright ("The specified role assignment ConditionVersion '' is not supported",
    observed live). Since the PUT replaces the whole property bag, omitting both keys is what actually
    clears the condition -- the same body shape New-OERRoleAssignment sends when no condition is given.

    Returns the updated assignment as a tagged Omnicit.EntraRBAC.RoleAssignment object. Requires an ARM
    token; authentication is ensured at entry via Initialize-OERAuth -IncludeARM.

    .PARAMETER Id
    The full ARM role assignment resource id in the form
    {scope}/providers/Microsoft.Authorization/roleAssignments/{guid}. This is the Id / RoleAssignmentId
    property emitted by Get-OERRoleAssignment, and it is bound from the pipeline by property name
    through the RoleAssignmentId alias, so Get-OERRoleAssignment pipes straight in. The id already
    contains the scope, so no scope parameter is needed.

    .PARAMETER Description
    New free-text description for the role assignment. Omitting this parameter preserves the live
    description; passing an empty string clears it.

    .PARAMETER Condition
    New ABAC condition expression constraining the assignment. Omitting this parameter preserves the
    live condition; passing an empty string REMOVES the condition (and its version), which widens the
    principal's access at that scope.

    .PARAMETER ConditionVersion
    The condition syntax version, normally 2.0. Omitting this parameter preserves the live version, and
    a newly supplied -Condition with no version defaults to 2.0. Version 1.0 can be upgraded to 2.0 but
    not downgraded.

    .PARAMETER TenantId
    Optional tenant id or domain to authenticate against, forwarded to Initialize-OERAuth.

    .EXAMPLE
    Set-OERRoleAssignment -Id $Ra.RoleAssignmentId -Description 'Scoped to the finance container'
    Updates only the description, leaving any existing ABAC condition intact.

    .EXAMPLE
    Get-OERRoleAssignment -Subscription 'Prod' -Group 'role_sec_ops' | Set-OERRoleAssignment -Condition ''
    Removes the ABAC condition from the group's Prod assignments after confirmation, widening access.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory, ValueFromPipelineByPropertyName)]
        [Alias('RoleAssignmentId')]
        [string]$Id,

        [string]$Description,
        [string]$Condition,
        [string]$ConditionVersion,
        [string]$TenantId
    )
    begin {
        $AuthParams = @{}
        if ($TenantId) { $AuthParams.TenantId = $TenantId }
        Initialize-OERAuth @AuthParams -IncludeARM
    }
    process {
        if ($Id -notmatch '(?i)/providers/Microsoft\.Authorization/roleAssignments/[^/]+$') {
            Write-CmdletError `
                -Message ([System.Exception]::new("'$Id' is not an Azure role assignment resource id ({scope}/providers/Microsoft.Authorization/roleAssignments/{guid}).")) `
                -ErrorId 'InvalidRoleAssignmentId' -Category InvalidArgument -TargetObject $Id -Cmdlet $PSCmdlet
            return
        }

        $EditableBound = @('Description', 'Condition', 'ConditionVersion') |
            Where-Object { $PSBoundParameters.ContainsKey($_) }
        if (-not $EditableBound) {
            Write-CmdletError `
                -Message ([System.Exception]::new('No editable property was supplied. Pass at least one of -Description, -Condition, or -ConditionVersion; Azure allows editing only those three properties on an existing role assignment.')) `
                -ErrorId 'NothingToUpdate' -Category InvalidArgument -TargetObject $Id -Cmdlet $PSCmdlet
            return
        }

        # -- Read-modify-write: ARM requires every non-editable property to match the existing assignment.
        $Live = $null
        try {
            $Live = Invoke-OERArmRequest -Path "$Id`?api-version=2022-04-01"
        } catch {
            Remove-OERErrorRecord -Record $PSItem
            $PSCmdlet.WriteError($PSItem)
            return
        }
        if (-not $Live -or -not $Live.properties) {
            Write-CmdletError `
                -Message ([System.Exception]::new("Role assignment '$Id' was not found.")) `
                -ErrorId 'RoleAssignmentNotFound' -Category ObjectNotFound -TargetObject $Id -Cmdlet $PSCmdlet
            return
        }
        $LiveProps = $Live.properties
        Write-Verbose "[Set-OERRoleAssignment] Editing assignment '$Id' for principal '$($LiveProps.principalId)'."

        # Overlay: bound wins, omitted preserves live. $null means 'the live object has no value here'.
        $LiveDescription      = if ($null -ne $LiveProps.description) { [string]$LiveProps.description } else { $null }
        $LiveCondition        = if ($null -ne $LiveProps.condition) { [string]$LiveProps.condition } else { $null }
        $LiveConditionVersion = if ($null -ne $LiveProps.conditionVersion) { [string]$LiveProps.conditionVersion } else { $null }

        $EffectiveDescription      = if ($PSBoundParameters.ContainsKey('Description')) { $Description } else { $LiveDescription }
        $EffectiveCondition        = if ($PSBoundParameters.ContainsKey('Condition')) { $Condition } else { $LiveCondition }
        $EffectiveConditionVersion = if ($PSBoundParameters.ContainsKey('ConditionVersion')) { $ConditionVersion } else { $LiveConditionVersion }

        # Deleting a condition drops its version with it. The REST documentation says to set both to
        # "either an empty string or null", but ARM REJECTS an empty conditionVersion outright:
        # "InvalidCreateOrUpdateRoleAssignmentRequest: The specified role assignment ConditionVersion
        # '' is not supported" (observed live, 2026-08-12). Because the PUT replaces the whole property
        # bag, the shape that actually clears a condition is to OMIT both keys -- which is exactly what
        # New-OERRoleAssignment sends when no condition is supplied, a shape proven to work live.
        if ($PSBoundParameters.ContainsKey('Condition') -and [string]::IsNullOrEmpty($Condition)) {
            $EffectiveConditionVersion = $null
        }
        # ARM defaults conditionVersion to 2.0 when a condition is supplied without one.
        if (-not [string]::IsNullOrEmpty($EffectiveCondition) -and [string]::IsNullOrEmpty($EffectiveConditionVersion)) {
            $EffectiveConditionVersion = '2.0'
        }
        if ([string]::IsNullOrEmpty($EffectiveCondition) -and -not [string]::IsNullOrEmpty($EffectiveConditionVersion)) {
            if ($PSBoundParameters.ContainsKey('ConditionVersion')) {
                Write-CmdletError `
                    -Message ([System.Exception]::new('-ConditionVersion requires a condition: the assignment has none and -Condition was not supplied.')) `
                    -ErrorId 'ConditionVersionWithoutCondition' -Category InvalidArgument -TargetObject $ConditionVersion -Cmdlet $PSCmdlet
                return
            }
            # -ConditionVersion was never bound; this is an orphaned live conditionVersion with no
            # condition (blank/absent live condition). Do not blame a parameter the caller never
            # passed -- treat it as absent and simply omit it from the body.
            $EffectiveConditionVersion = $null
        }

        $Body = @{
            properties = @{
                roleDefinitionId = [string]$LiveProps.roleDefinitionId
                principalId      = [string]$LiveProps.principalId
            }
        }
        if ($LiveProps.principalType) { $Body.properties.principalType = [string]$LiveProps.principalType }
        if ($LiveProps.delegatedManagedIdentityResourceId) { $Body.properties.delegatedManagedIdentityResourceId = [string]$LiveProps.delegatedManagedIdentityResourceId }
        if ($null -ne $EffectiveDescription) { $Body.properties.description = $EffectiveDescription }
        # Carried only when non-empty. An empty effective condition means the caller is clearing it,
        # and both keys are omitted rather than sent empty -- see the note above.
        if (-not [string]::IsNullOrEmpty($EffectiveCondition)) {
            $Body.properties.condition        = $EffectiveCondition
            $Body.properties.conditionVersion = $EffectiveConditionVersion
        }

        $ClearingCondition = (-not [string]::IsNullOrEmpty($LiveCondition)) -and [string]::IsNullOrEmpty($EffectiveCondition)
        if ($PSCmdlet.ShouldProcess($Id, 'Update Azure role assignment description/condition')) {
            if ($ClearingCondition) {
                Write-Warning "Removing the ABAC condition from role assignment '$Id'. This WIDENS the principal's access at that scope."
            }
            try {
                $Response = Invoke-OERArmRequest -Method PUT -Path "$Id`?api-version=2022-04-01" -Body $Body
            } catch {
                Remove-OERErrorRecord -Record $PSItem
                $PSCmdlet.WriteError($PSItem)
                return
            }
            if ($null -eq $Response) {
                Write-CmdletError `
                    -Message ([System.Exception]::new("Role assignment '$Id' was not found.")) `
                    -ErrorId 'RoleAssignmentNotFound' -Category ObjectNotFound -TargetObject $Id -Cmdlet $PSCmdlet
                return
            }
            ConvertTo-OERRoleAssignment -InputObject $Response
        }
    }
}
