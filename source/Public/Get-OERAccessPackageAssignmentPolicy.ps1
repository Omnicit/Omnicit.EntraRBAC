function Get-OERAccessPackageAssignmentPolicy {
    <#
    .SYNOPSIS
    Gets one or more access package assignment policies.

    .DESCRIPTION
    Retrieves assignment policies through Microsoft Graph. Supply -Id for a single policy or -AccessPackage
    (id or display name) to list all policies on a package. Output is one or more tagged
    Omnicit.EntraRBAC.AssignmentPolicy objects.

    .PARAMETER Id
    The assignment policy id (GUID) to fetch directly.

    .PARAMETER AccessPackage
    The access package id or display name whose policies are listed. Accepts pipeline input by
    property name from Get-OERAccessPackage (binds DisplayName or AccessPackageId; the Id alias is
    not used here because this cmdlet has its own -Id parameter for the ById set).

    .PARAMETER TenantId
    Optional tenant id or domain to authenticate against, forwarded to Initialize-OERAuth.

    .EXAMPLE
    Get-OERAccessPackageAssignmentPolicy -Id '00000000-0000-0000-0000-000000000001'
    Returns the assignment policy with the given id.

    .EXAMPLE
    Get-OERAccessPackageAssignmentPolicy -AccessPackage 'AP-Sales'
    Lists all assignment policies on the access package named AP-Sales.

    .EXAMPLE
    Get-OERAccessPackageAssignmentPolicy -AccessPackage '00000000-0000-0000-0000-000000000002'
    Lists all assignment policies on the access package with the given id.
    #>
    [CmdletBinding(DefaultParameterSetName = 'ByPackage')]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(ParameterSetName = 'ById', Mandatory)]
        [string]$Id,

        [Parameter(ParameterSetName = 'ByPackage', Mandatory, ValueFromPipelineByPropertyName)]
        [Alias('DisplayName', 'AccessPackageId')]
        [string]$AccessPackage,

        [string]$TenantId
    )
    begin {
        $AuthParams = @{}
        if ($TenantId) { $AuthParams.TenantId = $TenantId }
        Initialize-OERAuth @AuthParams
    }
    process {
        $Base = 'v1.0/identityGovernance/entitlementManagement/assignmentPolicies'
        if ($PSCmdlet.ParameterSetName -eq 'ById') {
            try {
                $Response = Invoke-OERGraphRequest -Uri "$Base/$Id`?`$expand=accessPackage"
            } catch {
                Remove-OERErrorRecord -Record $PSItem
                $PSCmdlet.WriteError($PSItem)
                return
            }
            ConvertTo-OERAssignmentPolicy -InputObject $Response
            return
        }

        # Refuse an ambiguous display name loudly, and surface any other throw as itself. Only a
        # $null return (a display name that matched nothing) reaches the not-found branch.
        $PackageId = $null
        try {
            $PackageId = Resolve-OERAccessPackageId -DisplayName $AccessPackage
        } catch {
            Remove-OERErrorRecord -Record $PSItem
            if (Test-OERAmbiguousNameError -Record $PSItem) {
                Write-CmdletError `
                    -Message ([System.Exception]::new($PSItem.Exception.Message)) `
                    -ErrorId 'AmbiguousAccessPackageName' -Category InvalidArgument `
                    -TargetObject $AccessPackage -Cmdlet $PSCmdlet
                return
            }
            # Anything else the resolver raised is surfaced AS ITSELF, never folded into the
            # not-found branch below. Its own AccessPackageNotFound already names the id and why it
            # may be wrong, and a 403 or an exhausted 429 from its existence read is not evidence
            # that no such package exists -- reporting either as not found is the failed-read-as-an-
            # empty-fact defect of issue #76. A display name matching nothing still returns $null
            # rather than throwing, so the not-found branch below is unchanged for it.
            $PSCmdlet.WriteError($PSItem)
            return
        }
        if (-not $PackageId) {
            Write-CmdletError -Message ([System.Exception]::new("Access package '$AccessPackage' not found.")) `
                -ErrorId 'AccessPackageNotFound' -Category ObjectNotFound -TargetObject $AccessPackage -Cmdlet $PSCmdlet
            return
        }
        $Uri = "$Base`?`$filter=accessPackage/id eq '$PackageId'&`$expand=accessPackage"
        try {
            $Response = Invoke-OERGraphRequest -Uri $Uri -All
        } catch {
            Remove-OERErrorRecord -Record $PSItem
            $PSCmdlet.WriteError($PSItem)
            return
        }
        foreach ($Item in @($Response.value)) {
            ConvertTo-OERAssignmentPolicy -InputObject $Item
        }
    }
}
