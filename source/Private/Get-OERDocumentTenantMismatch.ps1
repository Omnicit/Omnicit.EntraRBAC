function Get-OERDocumentTenantMismatch {
    <#
    .SYNOPSIS
    Compares a structure document's tenantId with the tenant Invoke-OERStructure would act in, and
    builds the DocumentTenantMismatch error record when they differ.

    .DESCRIPTION
    The single owner of the comparison between a structure document's top-level tenantId and the tenant
    a document is applied in (BL-88, decision A14), and of the DocumentTenantMismatch id and message.
    Get-OERInventory writes tenantId as the tenant the exporting session's Microsoft Graph token was
    issued for (Get-OERInventoryTenantId), and Invoke-OERStructure calls this function for every
    document that was read, validated and not refused by the pipeline session rule, so a document that
    names its tenant is applied in that tenant only -- also when the command runs inside a script block
    in a pipeline, where the snapshot of the session it began with is taken too late to see another
    command's sign-in (BL-88).

    Returns nothing when the document has no tenantId key -- such a document is applied exactly as
    before, with no tenant check -- or when the comparison passes. Otherwise returns an ErrorRecord the
    caller writes as a non-terminating error before it returns, so that document is refused and the
    next piped document is tried on its own. It never signs in, sends nothing and reads nothing but the
    module's own state; the document's tenant is only compared, never signed in to (A6).

    With -RequestedTenantId (before the sign-in): the value a command names with -TenantId is compared
    only when it is a GUID (Test-OERGuid). A domain, 'organizations' or any other name is not a tenant
    ID, so it is compared after the sign-in instead, through the token it yields.

    Without it (after the sign-in): the document's tenantId must equal the session's TokenTenantId, the
    tenant the Microsoft Graph token was issued for, and, with -IncludeARM, also ArmTokenTenantId, the
    tenant the Azure Resource Manager token was issued for. A session with no state, or a token tenant
    that is not a GUID, cannot be shown to be the document's tenant, so the document is refused.

    Every comparison is PowerShell's case-insensitive -eq, so letter case in a GUID does not matter.

    .PARAMETER Document
    The parsed, validated structure document.

    .PARAMETER Target
    The record's target object: the document's path, or the parameter set it came through.

    .PARAMETER RequestedTenantId
    The tenant the command names with -TenantId, for the comparison before the sign-in.

    .PARAMETER IncludeARM
    After the sign-in: compare the Azure Resource Manager token's tenant too, as the document's Azure
    sections are applied with it.

    .EXAMPLE
    $Refusal = Get-OERDocumentTenantMismatch -Document $Document -Target $Path -IncludeARM:$NeedArm
    if ($Refusal) { $PSCmdlet.WriteError($Refusal); return }

    Refuses the document when the session's tokens were issued for another tenant than it names.
    #>
    [CmdletBinding(DefaultParameterSetName = 'Session')]
    [OutputType([System.Management.Automation.ErrorRecord])]
    param(
        [Parameter(Mandatory)][PSCustomObject]$Document,
        [Parameter(Mandatory)][string]$Target,
        [Parameter(ParameterSetName = 'Requested', Mandatory)][string]$RequestedTenantId,
        [Parameter(ParameterSetName = 'Session')][switch]$IncludeARM
    )
    $Property = $Document.PSObject.Properties['tenantId']
    if ($null -eq $Property) { return }
    [string]$DocumentTenant = $Property.Value

    $Reason = $null
    $NothingWas = 'read or written'
    if ($PSCmdlet.ParameterSetName -eq 'Requested') {
        if (-not (Test-OERGuid -Value $RequestedTenantId)) { return }
        if ($RequestedTenantId -eq $DocumentTenant) { return }
        $Reason = "-TenantId names tenant '$RequestedTenantId'"
        $NothingWas = 'signed in to, read or written'
    } else {
        $State = $script:_OERAuthState
        [string]$GraphTenant = if ($State) { $State.TokenTenantId } else { '' }
        if (-not (Test-OERGuid -Value $GraphTenant)) {
            $Reason = 'the session holds no Microsoft Graph token whose tenant can be compared with it'
        } elseif ($GraphTenant -ne $DocumentTenant) {
            $Reason = "the session's Microsoft Graph token was issued for tenant '$GraphTenant'"
        } elseif ($IncludeARM) {
            [string]$ArmTenant = $State.ArmTokenTenantId
            if (-not (Test-OERGuid -Value $ArmTenant)) {
                $Reason = 'the session holds no Azure Resource Manager token whose tenant can be compared with it'
            } elseif ($ArmTenant -ne $DocumentTenant) {
                $Reason = "the session's Azure Resource Manager token was issued for tenant '$ArmTenant'"
            }
        }
        if (-not $Reason) { return }
    }
    # The values are arguments of -f, never part of the format string.
    [string]$Message = ("The structure document names tenant '{0}', but {1}. Omnicit.EntraRBAC applies a " +
        'document only in the tenant its tenantId names, so nothing was {2} for this document. Name that ' +
        'tenant with -TenantId, or, to use the document as a template for another tenant, change or ' +
        'remove its tenantId.') -f $DocumentTenant, $Reason, $NothingWas
    [System.Management.Automation.ErrorRecord]::new(
        [System.Exception]::new($Message),
        'DocumentTenantMismatch',
        [System.Management.Automation.ErrorCategory]::InvalidOperation,
        $Target)
}
