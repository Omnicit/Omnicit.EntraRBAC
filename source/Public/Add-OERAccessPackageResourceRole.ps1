function Add-OERAccessPackageResourceRole {
    <#
    .SYNOPSIS
    Binds a catalog resource role to an access package.

    .DESCRIPTION
    Creates an accessPackageResourceRoleScope through Microsoft Graph that grants a specific role of a
    catalog resource (for example a group's Member or Owner role, or an application role) to members of an
    access package. The access package is given by -AccessPackage (id or display name). The resource is
    located in -Catalog and identified by exactly one of -ResourceOriginId (the directory object id or
    site identifier, used verbatim), -Group (a group display name or id, resolved via Resolve-OERGroupId),
    or -Application (an enterprise application display name or service principal id, resolved via
    Resolve-OERApplicationId). -Role names the role to bind. Graph's create response carries only the
    binding id, so after the POST succeeds this cmdlet re-reads the binding through
    Get-OERAccessPackageResourceRole and emits that object -- making create output match read output BY
    CONSTRUCTION rather than by hand-composing the same fields twice. If the confirmation read fails or
    does not return a matching binding, a tagged object is instead composed from the already-resolved
    catalog resource and a verbose message explains why; the created binding is never rolled back or
    reported as failed just because the confirmation read could not complete. Output is a tagged
    Omnicit.EntraRBAC.AccessPackageResourceRole [PSCustomObject]. Supports -WhatIf and -Confirm.

    .PARAMETER AccessPackage
    The access package id or display name to add the resource role to. Accepts pipeline input by
    property name from Get-OERAccessPackage (binds Id or DisplayName).

    .PARAMETER Catalog
    The catalog id or display name that contains the resource.

    .PARAMETER ResourceOriginId
    The origin id (directory object id or site identifier) of the catalog resource whose role is bound,
    used verbatim with no lookup. Mutually exclusive with -Group and -Application; supply exactly one
    of the three.

    .PARAMETER Role
    The display name of the resource role to bind (for example 'Member' or 'Owner').

    .PARAMETER TenantId
    Optional tenant id or domain to authenticate against, forwarded to Initialize-OERAuth.

    .PARAMETER Group
    The display name or object id of a group resource, resolved to its origin id via Resolve-OERGroupId.
    Mutually exclusive with -ResourceOriginId and -Application; supply exactly one of the three. A
    display name matching more than one group is refused with AmbiguousGroupName naming the candidates.

    .PARAMETER Application
    The display name or service principal object id of an enterprise application resource, resolved to
    its origin id via Resolve-OERApplicationId. Mutually exclusive with -ResourceOriginId and -Group;
    supply exactly one of the three.

    .EXAMPLE
    Add-OERAccessPackageResourceRole -AccessPackage 'AP-Sales' -Catalog 'CAT-IT-Core' -ResourceOriginId 'grp-guid' -Role 'Member'
    Grants the group's Member role through the access package, given its origin id directly.

    .EXAMPLE
    Add-OERAccessPackageResourceRole -AccessPackage 'AP-Sales' -Catalog 'CAT-IT-Core' -Group 'Sales Team' -Role 'Member'
    Resolves the group named 'Sales Team' to its object id and grants its Member role.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory, ValueFromPipelineByPropertyName)]
        [Alias('Id', 'DisplayName', 'AccessPackageId')]
        [string]$AccessPackage,

        [Parameter(Mandatory)]
        [string]$Catalog,

        [ValidateNotNullOrEmpty()]
        [string]$ResourceOriginId,

        [Parameter(Mandatory)]
        [string]$Role,

        [string]$TenantId,

        # Declared after the pre-existing parameters so their positional binding is unchanged.
        [ValidateNotNullOrEmpty()]
        [string]$Group,

        [ValidateNotNullOrEmpty()]
        [string]$Application
    )
    begin {
        $AuthParams = @{}
        if ($TenantId) { $AuthParams.TenantId = $TenantId }
        Initialize-OERAuth @AuthParams
    }
    process {
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
            Write-CmdletError `
                -Message ([System.Exception]::new("Access package '$AccessPackage' not found.")) `
                -ErrorId 'AccessPackageNotFound' -Category ObjectNotFound -TargetObject $AccessPackage -Cmdlet $PSCmdlet
            return
        }

        # Refuse an ambiguous display name loudly; any other throw falls through to the not-found branch.
        $CatalogId = $null
        try {
            $CatalogId = Resolve-OERCatalogId -DisplayName $Catalog
        } catch {
            Remove-OERErrorRecord -Record $PSItem
            if (Test-OERAmbiguousNameError -Record $PSItem) {
                Write-CmdletError `
                    -Message ([System.Exception]::new($PSItem.Exception.Message)) `
                    -ErrorId 'AmbiguousCatalogName' -Category InvalidArgument `
                    -TargetObject $Catalog -Cmdlet $PSCmdlet
                return
            }
        }
        if (-not $CatalogId) {
            Write-CmdletError `
                -Message ([System.Exception]::new("Catalog '$Catalog' not found.")) `
                -ErrorId 'CatalogNotFound' -Category ObjectNotFound -TargetObject $Catalog -Cmdlet $PSCmdlet
            return
        }

        # Exactly one of -ResourceOriginId, -Group, -Application identifies the resource. A runtime
        # guard rather than a parameter-set cross product: the cmdlet already has -AccessPackage/
        # -Catalog dimensions, and three more sets would multiply against them.
        $ResourceInputCount = @('ResourceOriginId', 'Group', 'Application') |
            Where-Object { $PSBoundParameters.ContainsKey($_) } | Measure-Object | Select-Object -ExpandProperty Count
        if ($ResourceInputCount -eq 0) {
            Write-CmdletError `
                -Message ([System.Exception]::new('A resource is required: supply -ResourceOriginId, -Group, or -Application.')) `
                -ErrorId 'NoResourceInput' -Category InvalidArgument -TargetObject $PackageId -Cmdlet $PSCmdlet
            return
        }
        if ($ResourceInputCount -gt 1) {
            Write-CmdletError `
                -Message ([System.Exception]::new('Supply only one of -ResourceOriginId, -Group, or -Application.')) `
                -ErrorId 'AmbiguousResourceInput' -Category InvalidArgument -TargetObject $PackageId -Cmdlet $PSCmdlet
            return
        }

        # A separate local rather than reassigning $ResourceOriginId: that parameter carries
        # [ValidateNotNullOrEmpty()] (B5), and PowerShell re-validates EVERY assignment to a
        # validated parameter variable for the rest of the function, not only the initial bind --
        # `$ResourceOriginId = $null` below would itself throw ValidationMetadataException.
        $EffectiveOriginId = $ResourceOriginId
        if ($PSBoundParameters.ContainsKey('Group')) {
            # Refuse an ambiguous display name loudly; any other throw falls through to the not-found branch.
            $EffectiveOriginId = $null
            try {
                $EffectiveOriginId = Resolve-OERGroupId -DisplayName $Group
            } catch {
                Remove-OERErrorRecord -Record $PSItem
                if (Test-OERAmbiguousNameError -Record $PSItem) {
                    Write-CmdletError `
                        -Message ([System.Exception]::new($PSItem.Exception.Message)) `
                        -ErrorId 'AmbiguousGroupName' -Category InvalidArgument `
                        -TargetObject $Group -Cmdlet $PSCmdlet
                    return
                }
            }
            if (-not $EffectiveOriginId) {
                Write-CmdletError `
                    -Message ([System.Exception]::new("Group '$Group' not found.")) `
                    -ErrorId 'GroupNotFound' -Category ObjectNotFound -TargetObject $Group -Cmdlet $PSCmdlet
                return
            }
        } elseif ($PSBoundParameters.ContainsKey('Application')) {
            # Resolve-OERApplicationId has no GUID short-circuit on -DisplayName (unlike
            # Resolve-OERGroupId) -- only its separate -Id parameter returns verbatim. Without this
            # check, a GUID -Application would be sent as a literal displayName filter, matching
            # nothing and misleadingly reporting ApplicationNotFound. Test-OERGuid is the module's
            # single GUID predicate; this makes -Application's help claim ("display name or object
            # id") symmetric with -Group's, which is already true.
            $EffectiveOriginId = try {
                if (Test-OERGuid -Value $Application) { Resolve-OERApplicationId -Id $Application }
                else { Resolve-OERApplicationId -DisplayName $Application }
            } catch { Remove-OERErrorRecord -Record $PSItem; $null }
            if (-not $EffectiveOriginId) {
                Write-CmdletError `
                    -Message ([System.Exception]::new("Application '$Application' not found.")) `
                    -ErrorId 'ApplicationNotFound' -Category ObjectNotFound -TargetObject $Application -Cmdlet $PSCmdlet
                return
            }
        }

        $Resource = try { Resolve-OERCatalogResource -CatalogId $CatalogId -OriginId $EffectiveOriginId -IncludeRoles } catch { Remove-OERErrorRecord -Record $PSItem; $null }
        if (-not $Resource) {
            Write-CmdletError `
                -Message ([System.Exception]::new("Resource '$EffectiveOriginId' not found in catalog '$CatalogId'.")) `
                -ErrorId 'CatalogResourceNotFound' -Category ObjectNotFound -TargetObject $EffectiveOriginId -Cmdlet $PSCmdlet
            return
        }

        $ResourceRole = @($Resource.roles) | Where-Object { $_.displayName -eq $Role } | Select-Object -First 1
        if (-not $ResourceRole) {
            Write-CmdletError `
                -Message ([System.Exception]::new("Role '$Role' not found on resource '$EffectiveOriginId'.")) `
                -ErrorId 'ResourceRoleNotFound' -Category ObjectNotFound -TargetObject $Role -Cmdlet $PSCmdlet
            return
        }

        $Body = @{
            role  = @{
                displayName  = $ResourceRole.displayName
                originId     = $ResourceRole.originId
                originSystem = $Resource.originSystem
                resource     = @{ id = $Resource.id }
            }
            scope = @{
                originId     = $Resource.originId
                originSystem = $Resource.originSystem
                isRootScope  = $true
            }
        }

        if ($PSCmdlet.ShouldProcess($PackageId, "Bind resource role '$Role' of '$EffectiveOriginId'")) {
            try {
                $Created = Invoke-OERGraphRequest -Method POST `
                    -Uri ("v1.0/identityGovernance/entitlementManagement/accessPackages/{0}/resourceRoleScopes" -f $PackageId) `
                    -Body $Body
            } catch {
                Remove-OERErrorRecord -Record $PSItem
                $PSCmdlet.WriteError($PSItem)
                return
            }
            # Graph answers a resourceRoleScopes POST with only { id, createdDateTime } -- it does not
            # echo the role or the scope. Re-read the binding through Get-OERAccessPackageResourceRole
            # so create output matches read output BY CONSTRUCTION (read owns the ResourceDisplayName
            # catalog-resource join; hand-composing it here from the input previously caused create and
            # read to disagree -- create said the resolved resource name, read said the scope label).
            $Confirmed = $null
            try {
                $Confirmed = Get-OERAccessPackageResourceRole -AccessPackage $PackageId -ErrorAction Stop |
                    Where-Object { $_.ResourceRoleScopeId -eq $Created.id } | Select-Object -First 1
            } catch {
                Remove-OERErrorRecord -Record $PSItem
                Write-Verbose "Could not re-read the created resource role binding '$($Created.id)' from access package '$PackageId': $($PSItem.Exception.Message)"
            }

            if ($Confirmed) {
                $Confirmed
            } else {
                # The binding was already created -- a failed or empty confirmation read must never be
                # reported as a failure. Fall back to the values already resolved for the POST body.
                Write-Verbose "Falling back to the resolved catalog resource for binding '$($Created.id)' -- the confirmation read did not return a matching binding."
                $Fallback = [PSCustomObject]@{
                    id    = $Created.id
                    role  = [PSCustomObject]@{ displayName = $ResourceRole.displayName }
                    scope = [PSCustomObject]@{
                        originId     = $Resource.originId
                        originSystem = $Resource.originSystem
                    }
                }
                ConvertTo-OERAccessPackageResourceRole -InputObject $Fallback -AccessPackageId $PackageId `
                    -ResourceDisplayName $Resource.displayName
            }
        }
    }
}
