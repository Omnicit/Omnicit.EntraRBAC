function New-OERAccessPackageAssignment {
    <#
    .SYNOPSIS
    Assigns a user to an access package as an administrator (direct assignment).

    .DESCRIPTION
    Creates an accessPackageAssignmentRequest with requestType adminAdd through Microsoft Graph,
    directly assigning a user -- named with -User (user principal name or object id) or supplied
    as a raw object id with -TargetId -- to an access package under a specific assignment policy.
    The access package is given by -AccessPackage (id or display name) and the policy by -Policy
    (id). Output is the created assignment request as a tagged Omnicit.EntraRBAC.AssignmentRequest
    object exposing RequestId, RequestType, State and Status (the assignment itself is provisioned
    asynchronously by Graph; query it with Get-OERAccessPackageAssignment). Supports -WhatIf and
    -Confirm.

    .PARAMETER AccessPackage
    The access package id or display name to assign. Resolved via Resolve-OERAccessPackageId:
    a GUID costs one existence read that refuses an id no access package has; a display name
    triggers a filtered Graph query. Accepts pipeline input by property name via the
    AccessPackageId or DisplayName alias -- a tagged
    Omnicit.EntraRBAC.Assignment (from Get-OERAccessPackageAssignment) or
    Omnicit.EntraRBAC.AssignmentRequest (from this cmdlet's own output) binds directly. Deliberately
    NOT aliased to Id: an Assignment object carries its own (different) Id alongside AccessPackageId,
    and an Id alias would silently bind the wrong one.

    .PARAMETER Policy
    The assignment policy id under which the assignment is created. Must be a canonical GUID -- there
    is no display-name resolution for a policy. Accepts pipeline input by property name via the
    PolicyId or AssignmentPolicyId alias, so this cmdlet's own tagged AssignmentRequest output (which
    carries AssignmentPolicyId) can be re-piped to create another assignment under the same policy.

    .PARAMETER TargetId
    The object id (GUID) of the user to assign. Accepts pipeline input by property name so an
    existing assignment read with Get-OERAccessPackageAssignment can be re-targeted. A non-GUID
    value yields an InvalidTargetId error directing you to -User.

    .PARAMETER TenantId
    Optional tenant id or domain to authenticate against, forwarded to Initialize-OERAuth.

    .PARAMETER User
    The user to assign, given as a user principal name or object id (GUID) and resolved via
    Resolve-OERPrincipal. Mutually exclusive with -TargetId; supply exactly one.

    .EXAMPLE
    New-OERAccessPackageAssignment -AccessPackage 'AP-Sales' -Policy $policyId -TargetId $userId
    Directly assigns the user to the access package under the specified policy.

    .EXAMPLE
    New-OERAccessPackageAssignment -AccessPackage $packageId -Policy $policyId -TargetId $userId -WhatIf
    Shows what would be submitted without creating the assignment request.

    .EXAMPLE
    New-OERAccessPackageAssignment -AccessPackage 'AP-Sales' -Policy $policyId -User 'anna.berg@contoso.com'
    Assigns the user, named by UPN, to the access package under the specified policy.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory, ValueFromPipelineByPropertyName)]
        [Alias('AccessPackageId', 'DisplayName')]
        [string]$AccessPackage,

        [Parameter(Mandatory, ValueFromPipelineByPropertyName)]
        [Alias('PolicyId', 'AssignmentPolicyId')]
        [string]$Policy,

        [Parameter(ValueFromPipelineByPropertyName)]
        [string]$TargetId,

        [string]$TenantId,

        # Declared after the pre-existing parameters so their positional binding is unchanged.
        [string]$User
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

        $Target = Resolve-OERPrincipalOrId -PrincipalId $TargetId -User $User `
            -IdParameterName 'TargetId' -InvalidIdErrorId 'InvalidTargetId' `
            -FriendlyParameterHint '-User'
        if ($Target.ErrorId) {
            Write-CmdletError -Message ([System.Exception]::new($Target.Message)) `
                -ErrorId $Target.ErrorId -Category $Target.Category `
                -TargetObject $Target.TargetObject -Cmdlet $PSCmdlet
            return
        }
        $ResolvedTargetId = $Target.PrincipalId

        # -Policy has no display-name resolution -- it is documented and has always been an id -- so
        # once it also accepts pipeline input (a piped object's AssignmentPolicyId is normally a real
        # GUID, but a caller could still bind a stray non-GUID property), its shape is validated
        # before the request body is built.
        #
        # This check deliberately runs AFTER the access-package and principal resolvers, not before
        # them. Hoisting it to the top of process would save two Graph round-trips on a malformed
        # -Policy, but it would also mask the more useful diagnostic: given an ambiguous
        # -AccessPackage AND a non-GUID -Policy, the caller needs to hear AmbiguousAccessPackageName,
        # because the access package is the primary target. tests/Unit/Public/AmbiguousName.Guard.Tests.ps1
        # pins that precedence as a house invariant across every ambiguity-refusing resolver call
        # site, and it fails outright if this block is moved above the resolver. An earlier version of
        # this comment claimed the check ran "before spending a Graph call" -- it never did, and the
        # correct fix for that was this note, not a reorder.
        if (-not (Test-OERGuid -Value $Policy)) {
            Write-CmdletError `
                -Message ([System.Exception]::new("Policy '$Policy' is not a valid GUID. -Policy takes the assignment policy id directly; there is no display-name lookup.")) `
                -ErrorId 'InvalidPolicyId' -Category InvalidArgument -TargetObject $Policy -Cmdlet $PSCmdlet
            return
        }

        $Body = @{
            requestType = 'adminAdd'
            assignment  = @{
                targetId           = $ResolvedTargetId
                accessPackageId    = $PackageId
                assignmentPolicyId = $Policy
            }
        }

        if ($PSCmdlet.ShouldProcess($ResolvedTargetId, "Assign to access package $PackageId")) {
            try {
                $Request = Invoke-OERGraphRequest -Method POST `
                    -Uri 'v1.0/identityGovernance/entitlementManagement/assignmentRequests' -Body $Body
            } catch {
                Remove-OERErrorRecord -Record $PSItem
                $PSCmdlet.WriteError($PSItem)
                return
            }
            ConvertTo-OERAssignmentRequest -InputObject $Request `
                -AccessPackageId $PackageId -AssignmentPolicyId $Policy -TargetId $ResolvedTargetId
        }
    }
}
