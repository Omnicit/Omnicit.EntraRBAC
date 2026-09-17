function Set-OERAccessPackageAssignmentPolicy {
    <#
    .SYNOPSIS
    Updates an access package assignment policy.

    .DESCRIPTION
    Replaces an assignment policy through Microsoft Graph (PUT, full update). The policy is given by -Id;
    its parent access package is read from the existing policy. The new definition is supplied with the
    same building blocks as New-OERAccessPackageAssignmentPolicy: -RequestorScope (optional; the live
    scope is preserved when omitted), -RequestorSettings, -ApprovalStage, -DurationInDays /
    -DurationInHours / -ExpirationDateTime (mutually exclusive; at most one may be supplied),
    -RequireApproval, -RequireRequestorJustification, -RequireApprovalForUpdate,
    -DisableAssignmentNotifications, -DisplayName, -Description.
    Read-modify-write semantics: the existing policy is fetched once (same GET used to resolve the access
    package id); undeclared settings (requestorScope, requestorSettings, requestApprovalSettings approval
    flags, reviewSettings, questions, expiration) are carried forward from the existing policy so only the
    fields you explicitly pass are changed. The body is assembled by the shared ConvertTo-OERPolicyBody
    helper. Output is the updated tagged Omnicit.EntraRBAC.AssignmentPolicy object. Supports -WhatIf and
    -Confirm. The duration parameters also accept the module-standard -DurationDays / -DurationHours names.

    At least one property beyond the mandatory -DisplayName must be supplied or a non-terminating
    NothingToUpdate error is emitted. Because -DisplayName is Mandatory it is re-sent on every call and
    cannot by itself signal an update, so this means a rename-only call (-Id and -DisplayName alone) is
    refused. To rename, pair -DisplayName with any other property -- for example, re-sending the current
    -Description -- so the call carries an update.

    Because reviewSettings is carried forward on every update, a policy whose Lifecycle access review has
    been deleted can no longer be updated at all: Graph validates the referenced definition and answers
    404 "BusinessFlow not found for id <guid>". That one failure is reported as a named
    AccessPackageLifecycleReviewMissing error that identifies the missing definition and the remedy
    (re-create the Lifecycle access review, or turn off "Require access reviews" on the policy); every
    other Graph failure is surfaced unchanged.

    .PARAMETER Id
    The assignment policy id (GUID) to update.

    .PARAMETER DisplayName
    The policy display name. Mandatory and re-sent on every call (a full PUT), but accepts pipeline
    input by property name so a tagged Omnicit.EntraRBAC.AssignmentPolicy object from
    Get-OERAccessPackageAssignmentPolicy pipes straight into an update without repeating the name by
    hand. Still counts toward the NothingToUpdate rename-only refusal: pass at least one other
    updatable property to make a real change.

    .PARAMETER Description
    Optional policy description. When omitted the existing description is preserved; an explicit
    value replaces it, and an explicit empty string clears it.

    .PARAMETER RequestorScope
    An optional tagged Omnicit.EntraRBAC.RequestorScope object from New-OERAccessPackageRequestorScope.
    When omitted, the policy keeps its live allowedTargetScope and specificAllowedTargets instead of
    being reset to a default scope.

    .PARAMETER RequestorSettings
    A tagged object from New-OERAccessPackageRequestorSettings controlling requestor self-service options.
    When omitted the existing requestorSettings block is preserved.

    .PARAMETER ApprovalStage
    Zero or more tagged objects from New-OERAccessPackageApprovalStage, in approval order.
    When omitted the existing approval stages are preserved.

    .PARAMETER RequireApproval
    Whether approval is required to add an assignment. When omitted the existing value is preserved.

    .PARAMETER RequireRequestorJustification
    Whether the requestor must supply a justification. When omitted the existing value is preserved.

    .PARAMETER RequireApprovalForUpdate
    Whether approval is required to update an existing assignment. When omitted the existing value is preserved.

    .PARAMETER DurationInDays
    Assignment lifetime in days. Mutually exclusive with -DurationInHours and -ExpirationDateTime.
    When omitted the existing expiration setting is preserved. Also bindable as -DurationDays, the
    module-standard name used by New-OERAccessPackageApprovalStage and the PIM cmdlets.

    .PARAMETER DurationInHours
    Assignment lifetime in hours. Mutually exclusive with -DurationInDays and -ExpirationDateTime.
    When omitted the existing expiration setting is preserved. Also bindable as -DurationHours, the
    module-standard name used by New-OERAccessPackageApprovalStage and the PIM cmdlets.

    .PARAMETER ExpirationDateTime
    Fixed assignment expiry. Mutually exclusive with -DurationInDays and -DurationInHours.
    When omitted the existing expiration setting is preserved.

    .PARAMETER DisableAssignmentNotifications
    When specified, controls whether assignment notification emails are suppressed.
    When omitted the existing notification setting is preserved.

    .PARAMETER TenantId
    Optional tenant id or domain to authenticate against, forwarded to Initialize-OERAuth.

    .EXAMPLE
    $scope = New-OERAccessPackageRequestorScope -Scope AllMemberUsers
    Set-OERAccessPackageAssignmentPolicy -Id $polId -DisplayName 'Default' -RequestorScope $scope -DurationInDays 60

    Replaces the policy definition with a 60-day lifetime, preserving other settings.

    .EXAMPLE
    $scope = New-OERAccessPackageRequestorScope -AdminAssignmentOnly
    $stage = New-OERAccessPackageApprovalStage -DurationDays 7 -Manager
    Set-OERAccessPackageAssignmentPolicy -Id $polId -DisplayName 'Manager Approval' -RequestorScope $scope -ApprovalStage $stage

    Replaces the policy to require manager approval, preserving expiration and notification settings.

    .EXAMPLE
    Set-OERAccessPackageAssignmentPolicy -Id $polId -DisplayName 'Default' -DurationInDays 90

    Changes only the expiration to 90 days. -RequestorScope is omitted, so the policy's live
    allowedTargetScope and specificAllowedTargets (for example a SpecificDirectoryUsers scope with its
    approved user and group list) are preserved unchanged rather than being reset to a default scope.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory, ValueFromPipelineByPropertyName)]
        [string]$Id,

        [Parameter(Mandatory, ValueFromPipelineByPropertyName)]
        [string]$DisplayName,

        [string]$Description,

        [PSCustomObject]$RequestorScope,

        [PSCustomObject]$RequestorSettings,

        [PSCustomObject[]]$ApprovalStage,

        [switch]$RequireApproval,

        [switch]$RequireRequestorJustification,

        [switch]$RequireApprovalForUpdate,

        [Alias('DurationDays')]
        [int]$DurationInDays,

        [Alias('DurationHours')]
        [int]$DurationInHours,

        [datetime]$ExpirationDateTime,

        [switch]$DisableAssignmentNotifications,

        [string]$TenantId
    )
    begin {
        $AuthParams = @{}
        if ($TenantId) { $AuthParams.TenantId = $TenantId }
        Initialize-OERAuth @AuthParams
    }
    process {
        # -DisplayName is Mandatory, so it is re-sent on every call and cannot by itself signal an
        # update -- a call carrying only -Id and -DisplayName would otherwise be a full PUT of the
        # policy's current state, indistinguishable in the caller's output from a real change. BREAKING
        # consequence, stated here rather than hidden: a rename-only call is now refused (issue #47).
        $UpdatableBound = @(
            'Description', 'RequestorScope', 'RequestorSettings', 'ApprovalStage', 'RequireApproval',
            'RequireRequestorJustification', 'RequireApprovalForUpdate', 'DurationInDays', 'DurationInHours',
            'ExpirationDateTime', 'DisableAssignmentNotifications') |
            Where-Object { $PSBoundParameters.ContainsKey($_) }
        if (-not $UpdatableBound) {
            Write-CmdletError `
                -Message ([System.Exception]::new(
                    'No updatable property beyond the mandatory -DisplayName was supplied. Pass at least one ' +
                    'of -Description, -RequestorScope, -RequestorSettings, -ApprovalStage, -RequireApproval, ' +
                    '-RequireRequestorJustification, -RequireApprovalForUpdate, -DurationInDays, ' +
                    '-DurationInHours, -ExpirationDateTime, or -DisableAssignmentNotifications.')) `
                -ErrorId 'NothingToUpdate' `
                -Category InvalidArgument `
                -TargetObject $Id `
                -Cmdlet $PSCmdlet
            return
        }

        # Three-way expiration mutual exclusion: at most one of DurationInDays, DurationInHours, ExpirationDateTime.
        $ExpirationCount = 0
        if ($PSBoundParameters.ContainsKey('DurationInDays'))     { $ExpirationCount++ }
        if ($PSBoundParameters.ContainsKey('DurationInHours'))    { $ExpirationCount++ }
        if ($PSBoundParameters.ContainsKey('ExpirationDateTime')) { $ExpirationCount++ }
        if ($ExpirationCount -gt 1) {
            Write-CmdletError -Message ([System.Exception]::new('Specify only one of -DurationInDays, -DurationInHours, or -ExpirationDateTime.')) `
                -ErrorId 'InvalidPolicyInput' -Category InvalidArgument -TargetObject $Id -Cmdlet $PSCmdlet
            return
        }

        # Validate builder objects up front. ConvertTo-OERPolicyBody also guards these, but a throw caught
        # from a called function is still recorded against the caller's -ErrorVariable (the engine writes
        # the terminating error to the error stream before the catch runs), which would leave a bare builder
        # message ahead of the structured InvalidPolicyInput error. Guarding here keeps InvalidPolicyInput
        # the single, first error the caller sees for a bad builder input.
        if ($PSBoundParameters.ContainsKey('RequestorScope')) {
            if ($RequestorScope.PSObject.TypeNames -notcontains 'Omnicit.EntraRBAC.RequestorScope') {
                Write-CmdletError -Message ([System.Exception]::new('-RequestorScope must be an object from New-OERAccessPackageRequestorScope.')) `
                    -ErrorId 'InvalidPolicyInput' -Category InvalidArgument -TargetObject $RequestorScope -Cmdlet $PSCmdlet
                return
            }
        }
        if ($PSBoundParameters.ContainsKey('RequestorSettings')) {
            if ($RequestorSettings.PSObject.TypeNames -notcontains 'Omnicit.EntraRBAC.RequestorSettings') {
                Write-CmdletError -Message ([System.Exception]::new('-RequestorSettings must be an object from New-OERAccessPackageRequestorSettings.')) `
                    -ErrorId 'InvalidPolicyInput' -Category InvalidArgument -TargetObject $RequestorSettings -Cmdlet $PSCmdlet
                return
            }
        }
        if ($PSBoundParameters.ContainsKey('ApprovalStage')) {
            foreach ($Stage in @($ApprovalStage)) {
                if ($null -ne $Stage -and $Stage.PSObject.TypeNames -notcontains 'Omnicit.EntraRBAC.ApprovalStage') {
                    Write-CmdletError -Message ([System.Exception]::new('-ApprovalStage entries must be objects from New-OERAccessPackageApprovalStage.')) `
                        -ErrorId 'InvalidPolicyInput' -Category InvalidArgument -TargetObject $Stage -Cmdlet $PSCmdlet
                    return
                }
            }
        }

        # Single GET: used both to resolve the access package id and as the -Existing baseline for
        # read-modify-write (undeclared settings are carried forward from this response).
        try {
            $Existing = Invoke-OERGraphRequest -Uri ("v1.0/identityGovernance/entitlementManagement/assignmentPolicies/{0}?`$expand=accessPackage" -f $Id)
        } catch {
            Remove-OERErrorRecord -Record $PSItem
            $PSCmdlet.WriteError($PSItem)
            return
        }
        $PackageId = $Existing.accessPackage.id
        if (-not $PackageId) {
            Write-CmdletError -Message ([System.Exception]::new("Could not determine the access package for policy '$Id'.")) `
                -ErrorId 'AccessPackageNotFound' -Category ObjectNotFound -TargetObject $Id -Cmdlet $PSCmdlet
            return
        }

        $BodyParams = @{
            DisplayName     = $DisplayName
            AccessPackageId = $PackageId
            Existing        = $Existing
        }
        if ($PSBoundParameters.ContainsKey('RequestorScope'))                { $BodyParams.RequestorScope                = $RequestorScope }
        if ($PSBoundParameters.ContainsKey('Description'))                   { $BodyParams.Description                   = $Description }
        if ($PSBoundParameters.ContainsKey('RequestorSettings'))             { $BodyParams.RequestorSettings             = $RequestorSettings }
        if ($PSBoundParameters.ContainsKey('ApprovalStage'))                 { $BodyParams.ApprovalStage                 = $ApprovalStage }
        if ($PSBoundParameters.ContainsKey('RequireApproval'))               { $BodyParams.RequireApproval               = [bool]$RequireApproval }
        if ($PSBoundParameters.ContainsKey('RequireRequestorJustification')) { $BodyParams.RequireRequestorJustification = [bool]$RequireRequestorJustification }
        if ($PSBoundParameters.ContainsKey('RequireApprovalForUpdate'))      { $BodyParams.RequireApprovalForUpdate      = [bool]$RequireApprovalForUpdate }
        if ($PSBoundParameters.ContainsKey('DurationInDays'))                { $BodyParams.DurationInDays                = $DurationInDays }
        if ($PSBoundParameters.ContainsKey('DurationInHours'))               { $BodyParams.DurationInHours               = $DurationInHours }
        if ($PSBoundParameters.ContainsKey('ExpirationDateTime'))            { $BodyParams.ExpirationDateTime            = $ExpirationDateTime }
        if ($PSBoundParameters.ContainsKey('DisableAssignmentNotifications')) { $BodyParams.DisableAssignmentNotifications = [bool]$DisableAssignmentNotifications }

        $Body = try {
            ConvertTo-OERPolicyBody @BodyParams
        } catch {
            Remove-OERErrorRecord -Record $PSItem
            Write-CmdletError -Message ([System.Exception]::new("Invalid policy input: $($PSItem.Exception.Message)")) `
                -InnerException $PSItem.Exception -ErrorId 'InvalidPolicyInput' -Category InvalidArgument -TargetObject $PackageId -Cmdlet $PSCmdlet
            return
        }
        $Body.id = $Id

        if ($PSCmdlet.ShouldProcess($Id, 'Update assignment policy')) {
            try {
                $Updated = Invoke-OERGraphRequest -Method PUT `
                    -Uri ("v1.0/identityGovernance/entitlementManagement/assignmentPolicies/{0}" -f $Id) -Body $Body
            } catch {
                Remove-OERErrorRecord -Record $PSItem
                # MEASURED LIVE: deleting an access package's OWN Lifecycle access review leaves this
                # policy permanently un-updatable. reviewSettings is one of the blocks carried forward
                # from $Existing on every PUT (read-modify-write), Microsoft Graph validates the access
                # review definition it references, and a deleted definition answers 404 with
                #   {"error":{"code":"","message":"BusinessFlow not found for id <guid>"}}
                # -- a message that names neither this policy, nor reviewSettings, nor any remedy. Its
                # empty error.code is why Convert-GraphHttpException falls back to the status-derived id
                # 'NotFound', so the id alone is far too broad: the message shape is what makes the
                # match narrow. Anything else falls through to the generic handling below unchanged --
                # this is a diagnostic translation, not a change to which updates succeed.
                $PutError = $PSItem
                [string[]]$PutErrorIdSegment = @(([string]$PutError.FullyQualifiedErrorId) -split ',') |
                    ForEach-Object { $PSItem.Trim() }
                $BusinessFlowText = @(
                    [string]$PutError.Exception.Message
                    [string]$PutError.ErrorDetails.Message
                ) -join ' '
                # The captured token is deliberately NOT a GUID regex -- Test-OERGuid is the module's
                # single GUID predicate, so the pattern only has to stop at the JSON quote/brace that
                # can follow the id, and the predicate decides whether what it caught is really one.
                $BusinessFlowMatch = [regex]::Match($BusinessFlowText, 'BusinessFlow not found for id\s+([\w-]+)')
                $MissingReviewId = if ($BusinessFlowMatch.Success) { $BusinessFlowMatch.Groups[1].Value } else { '' }
                if (($PutErrorIdSegment -contains 'NotFound') -and (Test-OERGuid -Value $MissingReviewId)) {
                    Write-CmdletError `
                        -Message ([System.Exception]::new(
                            "Assignment policy '$Id' could not be updated: its 'reviewSettings' still references access " +
                            "review definition '$MissingReviewId', which no longer exists. Microsoft Graph validates that " +
                            'reference on every update of the policy, so every update fails with NotFound until it is ' +
                            "resolved. Re-create the Lifecycle access review on this assignment policy, or turn off " +
                            "'Require access reviews' on it.")) `
                        -InnerException $PutError.Exception `
                        -ErrorId 'AccessPackageLifecycleReviewMissing' -Category ObjectNotFound `
                        -TargetObject $Id -Cmdlet $PSCmdlet
                    return
                }
                $PSCmdlet.WriteError($PutError)
                return
            }
            if ($Updated) { ConvertTo-OERAssignmentPolicy -InputObject $Updated -AccessPackageId $PackageId }
        }
    }
}
