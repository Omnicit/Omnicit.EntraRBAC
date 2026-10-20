function Set-OERAccessPackageAssignmentPolicy {
    <#
    .SYNOPSIS
    Updates an access package assignment policy.

    .DESCRIPTION
    Replaces an assignment policy through Microsoft Graph (PUT, full update). The policy is given by -Id;
    its parent access package is read from the existing policy. The new definition is supplied with the
    same building blocks as New-OERAccessPackageAssignmentPolicy: -RequestorScope (optional; the live
    scope is preserved when omitted, unless it is an unreadable unknownFutureValue, below),
    -RequestorSettings, -ApprovalStage, -DurationInDays /
    -DurationInHours / -ExpirationDateTime (mutually exclusive; at most one may be supplied),
    -RequireApproval, -RequireRequestorJustification, -RequireApprovalForUpdate,
    -DisableAssignmentNotifications, -DisplayName, -Description.
    Read-modify-write semantics: the existing policy is fetched once (same GET used to resolve the access
    package id); undeclared settings (requestorScope, requestorSettings, requestApprovalSettings approval
    flags, reviewSettings, questions, expiration, custom extension stages and, while -RequestorScope is
    not passed, automatic assignment settings) are carried forward from the existing policy so only the
    fields you explicitly pass are changed. Microsoft Graph removes the custom extension stages from a
    policy on an update that does not send them (measured), so the read expands each stage's custom
    extension and the update sends every stage back; a stage whose custom extension id could not be read
    is refused with a non-terminating InvalidPolicyInput error, also under -WhatIf, and nothing is sent.
    The automatic assignment settings travel with the live scope: a declared -RequestorScope replaces
    the allowed targets and never inherits them. The body is assembled by the shared
    ConvertTo-OERPolicyBody helper. Output is the updated tagged Omnicit.EntraRBAC.AssignmentPolicy
    object. Supports -WhatIf and -Confirm. The duration parameters also accept the module-standard
    -DurationDays / -DurationHours names.

    A call that supplies no updatable property beyond the mandatory -DisplayName is a rename when
    -DisplayName differs from the live policy's display name: it is sent as the usual full update, with
    every other setting carried forward from the live policy as described above (custom extension stages
    and automatic assignment settings included). When -DisplayName equals the live display name,
    compared ignoring case, such a call emits a non-terminating NothingToUpdate error after its one read
    of the live policy and sends no update; a failed read is reported as itself, not as NothingToUpdate.
    A change of letter case alone is therefore not sent; together with any other updatable property it
    is.

    Because reviewSettings is carried forward on every update, a policy whose Lifecycle access review has
    been deleted can no longer be updated at all: Graph validates the referenced definition and answers
    404 "BusinessFlow not found for id <guid>". That one failure is reported as a named
    AccessPackageLifecycleReviewMissing error that identifies the missing definition and the remedy
    (re-create the Lifecycle access review, or turn off "Require access reviews" on the policy); every
    other Graph failure is surfaced unchanged.

    A policy whose live allowedTargetScope reads as unknownFutureValue is refused, unless -RequestorScope
    is given. Microsoft Graph names a scope it does not model that way only when asked with the 'Prefer:
    include-unknown-enum-members' header, which this module never sends, so the real scope cannot be read.
    An update that carried the value forward would replace the policy's scope with the placeholder itself:
    measured, a PUT with allowedTargetScope unknownFutureValue answers 200 and stores it as the scope. The
    call is refused with a non-terminating UnknownAllowedTargetScope error (category InvalidData) after the
    live policy is read once and before anything is sent, also under -WhatIf, and that holds for a rename
    too. Pass -RequestorScope to set the scope, and the update is sent as usual; apply the same policy
    through Invoke-OERStructure and its row is Failed for the same reason whatever its entry declares,
    a requestorScope included, since the engine has no such escape, with nothing written.

    .PARAMETER Id
    The assignment policy id (GUID) to update.

    .PARAMETER DisplayName
    The policy display name. Mandatory and sent with every update (a full PUT), and accepts pipeline
    input by property name so a tagged Omnicit.EntraRBAC.AssignmentPolicy object from
    Get-OERAccessPackageAssignmentPolicy pipes straight into an update without repeating the name by
    hand. A value that differs from the live policy's display name renames the policy, on its own or
    together with other properties. Supplied with no other updatable property and equal to the live
    name (compared ignoring case), it reports NothingToUpdate after the policy is read once, and no
    update is sent. A piped policy object's DisplayName is sent as given, so piping an object that was
    read before the policy was renamed elsewhere renames the policy back to the name the object holds.

    .PARAMETER Description
    Optional policy description. When omitted the existing description is preserved; an explicit
    value replaces it, and an explicit empty string clears it.

    .PARAMETER RequestorScope
    An optional tagged Omnicit.EntraRBAC.RequestorScope object from New-OERAccessPackageRequestorScope.
    When omitted, the policy keeps its live allowedTargetScope and specificAllowedTargets, and the
    automatic assignment settings that go with them, instead of being reset to a default scope; a
    declared scope never inherits the automatic assignment settings. A scope whose allowedTargetScope is SpecificConnectedOrganizationUsers
    and that names no connected organization is refused with a non-terminating InvalidPolicyInput error
    after the live policy is read and before anything is sent, also under -WhatIf: that is the scope
    New-OERAccessPackageRequestorScope -Scope SpecificConnectedOrganizationUsers builds, since the
    module does not model connected organization targets, and the full update would replace every
    connected organization the live policy names with an empty list. Omit -RequestorScope to keep the
    live scope and its connected organizations. Every other scope, and a tagged scope object that
    does carry a connected organization target, is unaffected. When the live policy's
    allowedTargetScope reads as unknownFutureValue (a scope this module cannot read), omitting
    -RequestorScope is refused with a non-terminating UnknownAllowedTargetScope error and nothing is
    sent: pass -RequestorScope to replace the scope.

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

    .EXAMPLE
    Set-OERAccessPackageAssignmentPolicy -Id $polId -DisplayName 'Contractors (external)'

    Renames the policy. No other property is supplied, so every other setting -- requestor scope,
    approval, expiration, custom extension stages and automatic assignment settings among them -- is
    carried forward from the live policy. Run with the policy's current name instead, the call reports
    NothingToUpdate and sends no update.
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

        [ValidateNotNullOrEmpty()]
        [string]$TenantId
    )
    begin {
        $AuthParams = @{}
        if ($TenantId) { $AuthParams.TenantId = $TenantId }
        Initialize-OERAuth @AuthParams
    }
    process {
        # -DisplayName is Mandatory, so it is sent with every update. When it is the only property bound,
        # whether the call is an update depends on the live policy (A16, Sprint 11 step 4b): a
        # -DisplayName that differs from the live displayName is a rename, sent as the full update
        # below with everything else carried forward; one equal to it, ignoring case, is NothingToUpdate.
        # That decision needs the live name, so it is taken after the read below, not here. (Issue #47
        # refused every call with -DisplayName alone; A16 replaced that.)
        $UpdatableBound = @(
            'Description', 'RequestorScope', 'RequestorSettings', 'ApprovalStage', 'RequireApproval',
            'RequireRequestorJustification', 'RequireApprovalForUpdate', 'DurationInDays', 'DurationInHours',
            'ExpirationDateTime', 'DisableAssignmentNotifications') |
            Where-Object { $PSBoundParameters.ContainsKey($_) }

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
        # read-modify-write (undeclared settings are carried forward from this response). It expands
        # the custom extension of each stage as well as the access package: $expand=accessPackage alone
        # returns a stage as { id, stage } WITHOUT the extension's own id (measured 2026-10-13, Sprint 11
        # step 3), and a PUT that omits the stages removes them, so the id is what lets them be sent back.
        try {
            $Existing = Invoke-OERGraphRequest -Uri ("v1.0/identityGovernance/entitlementManagement/assignmentPolicies/{0}?`$expand=accessPackage,customExtensionStageSettings(`$expand=customExtension)" -f $Id)
        } catch {
            Remove-OERErrorRecord -Record $PSItem
            $PSCmdlet.WriteError($PSItem)
            return
        }

        # A16 (Sprint 11 step 4b): with no updatable property beyond -DisplayName, the call is
        # NothingToUpdate only when -DisplayName equals the live displayName ignoring case -- the full
        # update would then re-send the policy's own state. A differing name falls through to the PUT
        # as any update does. Decided on the read above, so no second request is made; a failed read
        # was reported as itself in its catch and never reaches this point.
        if (-not $UpdatableBound -and $null -ne $Existing -and [string]$Existing.displayName -ieq $DisplayName) {
            Write-CmdletError `
                -Message ([System.Exception]::new(
                    "-DisplayName equals the current display name of assignment policy '$Id' (compared " +
                    'ignoring case) and no other updatable property was supplied, so there is nothing to ' +
                    'update. To rename the policy, pass a different -DisplayName; to update it, pass at ' +
                    'least one of -Description, -RequestorScope, -RequestorSettings, -ApprovalStage, ' +
                    '-RequireApproval, -RequireRequestorJustification, -RequireApprovalForUpdate, ' +
                    '-DurationInDays, -DurationInHours, -ExpirationDateTime, or -DisableAssignmentNotifications.')) `
                -ErrorId 'NothingToUpdate' `
                -Category InvalidArgument `
                -TargetObject $Id `
                -Cmdlet $PSCmdlet
            return
        }

        $PackageId = $Existing.accessPackage.id
        if (-not $PackageId) {
            Write-CmdletError -Message ([System.Exception]::new("Could not determine the access package for policy '$Id'.")) `
                -ErrorId 'AccessPackageNotFound' -Category ObjectNotFound -TargetObject $Id -Cmdlet $PSCmdlet
            return
        }

        # BL-50: New-OERAccessPackageRequestorScope builds SpecificConnectedOrganizationUsers with no
        # specificAllowedTargets -- the module does not model connected organization targets -- and
        # this cmdlet PUTs the declared scope whole, so the update would replace every connected
        # organization the live policy names with an empty list. Refused here, after the read of the
        # live policy and its AccessPackageNotFound check and BEFORE ConvertTo-OERPolicyBody and
        # ShouldProcess, so it reads the same under -WhatIf and no PUT is ever sent. Only a scope that
        # names the connected-organization scope AND holds no non-null target is caught: a hand-built
        # tagged scope that carries a target, and every other scope, go through unchanged. -eq compares
        # case-insensitively, so every casing of the scope name is caught.
        if ($PSBoundParameters.ContainsKey('RequestorScope') -and
            $RequestorScope.AllowedTargetScope -eq 'specificConnectedOrganizationUsers' -and
            @(@($RequestorScope.SpecificAllowedTargets) | Where-Object { $null -ne $_ }).Count -eq 0) {
            Write-CmdletError `
                -Message ([System.Exception]::new(
                    '-RequestorScope names allowedTargetScope SpecificConnectedOrganizationUsers but no ' +
                    'connected organization -- New-OERAccessPackageRequestorScope cannot name one -- so the ' +
                    "full update of assignment policy '$Id' would replace every connected organization the " +
                    'live policy names with an empty list. Nothing was sent. Omit -RequestorScope to keep ' +
                    'the live scope and its connected organizations.')) `
                -ErrorId 'InvalidPolicyInput' -Category InvalidArgument -TargetObject $Id -Cmdlet $PSCmdlet
            return
        }

        # BL-49 (Sprint 11 step 11, A24): a policy whose allowedTargetScope reads as unknownFutureValue
        # carries a scope Microsoft Graph names that way only when asked with 'Prefer:
        # include-unknown-enum-members', which this module never sends. MEASURED LIVE (Sprint 11 step
        # 11, check 1.1): a PUT with allowedTargetScope unknownFutureValue answers 200 and STORES the
        # placeholder as the policy's scope, so carrying the read value back (ConvertTo-OERPolicyBody
        # does, when -RequestorScope is omitted) would replace the real scope. Refused here, after the
        # read and its AccessPackageNotFound check and BEFORE ConvertTo-OERPolicyBody and ShouldProcess,
        # so it reads the same under -WhatIf and no PUT is ever sent. A bound -RequestorScope replaces
        # the scope outright and goes through (the BL-50 check above is the other side of that term and
        # the two never both apply). -eq compares case-insensitively, so every casing is caught. The
        # apply engine refuses the same read in Sync-OERStructureAccessPackage.
        if (-not $PSBoundParameters.ContainsKey('RequestorScope') -and
            [string]$Existing.allowedTargetScope -eq 'unknownFutureValue') {
            Write-CmdletError `
                -Message ([System.Exception]::new(
                    "Microsoft Graph returned allowedTargetScope 'unknownFutureValue' for assignment policy '$Id', " +
                    'a placeholder for a scope this module cannot read without the ' +
                    "'Prefer: include-unknown-enum-members' header; writing it back would replace the policy's " +
                    'requestor scope, so nothing was sent. Pass -RequestorScope to set the scope.')) `
                -ErrorId 'UnknownAllowedTargetScope' -Category InvalidData -TargetObject $Id -Cmdlet $PSCmdlet
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
