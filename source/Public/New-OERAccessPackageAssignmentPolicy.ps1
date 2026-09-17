function New-OERAccessPackageAssignmentPolicy {
    <#
    .SYNOPSIS
    Creates an assignment policy on an access package.

    .DESCRIPTION
    Creates an access package assignment policy through Microsoft Graph. The access package is given by
    -AccessPackage (id or display name). The requestor scope is supplied as a -RequestorScope object from
    New-OERAccessPackageRequestorScope; the approval workflow as zero or more -ApprovalStage objects from
    New-OERAccessPackageApprovalStage (in order). Requestor settings are supplied via -RequestorSettings
    from New-OERAccessPackageRequestorSettings. Approval behavior is controlled by -RequireApproval,
    -RequireRequestorJustification, and -RequireApprovalForUpdate. Lifecycle is set with -DurationInDays,
    -DurationInHours, or -ExpirationDateTime (mutually exclusive; at most one may be supplied). Assignment
    notification emails can be suppressed with -DisableAssignmentNotifications. The full Graph body is
    assembled by the private ConvertTo-OERPolicyBody helper so New and Set stay consistent. Output is a
    tagged Omnicit.EntraRBAC.AssignmentPolicy object. Supports -WhatIf and -Confirm. The duration
    parameters also accept the module-standard -DurationDays / -DurationHours names.

    .PARAMETER AccessPackage
    The access package id or display name to attach the policy to. Accepts pipeline input by property
    name from Get-OERAccessPackage (binds Id or AccessPackageId).

    .PARAMETER DisplayName
    The policy display name.

    .PARAMETER Description
    Optional policy description. Defaults to the display name when omitted.

    .PARAMETER RequestorScope
    A tagged object from New-OERAccessPackageRequestorScope describing who can request the package.

    .PARAMETER RequestorSettings
    A tagged object from New-OERAccessPackageRequestorSettings controlling requestor self-service options.

    .PARAMETER ApprovalStage
    Zero or more tagged objects from New-OERAccessPackageApprovalStage, in approval order.

    .PARAMETER RequireApproval
    Whether approval is required to add an assignment. Overrides the stage-count default when provided.

    .PARAMETER RequireRequestorJustification
    Whether the requestor must supply a justification when requesting access.

    .PARAMETER RequireApprovalForUpdate
    Whether approval is required to update an existing assignment.

    .PARAMETER DurationInDays
    Assignment lifetime in days. Mutually exclusive with -DurationInHours and -ExpirationDateTime.
    Also bindable as -DurationDays, the module-standard name used by New-OERAccessPackageApprovalStage
    and the PIM cmdlets.

    .PARAMETER DurationInHours
    Assignment lifetime in hours. Mutually exclusive with -DurationInDays and -ExpirationDateTime.
    Also bindable as -DurationHours, the module-standard name used by New-OERAccessPackageApprovalStage
    and the PIM cmdlets.

    .PARAMETER ExpirationDateTime
    Fixed assignment expiry. Mutually exclusive with -DurationInDays and -DurationInHours.

    .PARAMETER DisableAssignmentNotifications
    When specified, suppresses assignment notification emails for this policy.

    .PARAMETER TenantId
    Optional tenant id or domain to authenticate against, forwarded to Initialize-OERAuth.

    .EXAMPLE
    $scope = New-OERAccessPackageRequestorScope -Scope AllMemberUsers
    $stage = New-OERAccessPackageApprovalStage -DurationDays 7 -Manager
    New-OERAccessPackageAssignmentPolicy -AccessPackage 'AP-Sales' -DisplayName 'Default' -RequestorScope $scope -ApprovalStage $stage -DurationInDays 30

    Creates a self-service policy with manager approval and a 30-day assignment lifetime.

    .EXAMPLE
    $scope = New-OERAccessPackageRequestorScope -Scope AllMemberUsers
    $rs = New-OERAccessPackageRequestorSettings -AllowSelfRequest
    New-OERAccessPackageAssignmentPolicy -AccessPackage 'AP-Sales' -DisplayName 'Quick' -RequestorScope $scope -RequestorSettings $rs -RequireApproval -DurationInHours 8 -DisableAssignmentNotifications

    Creates a policy with explicit requestor settings, approval required, an 8-hour lifetime, and notifications disabled.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory, ValueFromPipelineByPropertyName)]
        [Alias('Id', 'AccessPackageId')]
        [string]$AccessPackage,

        [Parameter(Mandatory)]
        [string]$DisplayName,

        [string]$Description,

        [Parameter(Mandatory)]
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
        # Three-way expiration mutual exclusion: at most one of DurationInDays, DurationInHours, ExpirationDateTime.
        $ExpirationCount = 0
        if ($PSBoundParameters.ContainsKey('DurationInDays'))     { $ExpirationCount++ }
        if ($PSBoundParameters.ContainsKey('DurationInHours'))    { $ExpirationCount++ }
        if ($PSBoundParameters.ContainsKey('ExpirationDateTime')) { $ExpirationCount++ }
        if ($ExpirationCount -gt 1) {
            Write-CmdletError -Message ([System.Exception]::new('Specify only one of -DurationInDays, -DurationInHours, or -ExpirationDateTime.')) `
                -ErrorId 'InvalidPolicyInput' -Category InvalidArgument -TargetObject $AccessPackage -Cmdlet $PSCmdlet
            return
        }

        # Validate the builder objects up front. ConvertTo-OERPolicyBody also guards these, but a
        # throw caught from a called function is still recorded against the caller's -ErrorVariable
        # (the engine writes the terminating error to the error stream before the catch runs), which
        # would leave a bare builder message ahead of the structured InvalidPolicyInput error. Guarding
        # here keeps InvalidPolicyInput the single, first error the caller sees for a bad builder input.
        if ($RequestorScope.PSObject.TypeNames -notcontains 'Omnicit.EntraRBAC.RequestorScope') {
            Write-CmdletError -Message ([System.Exception]::new('-RequestorScope must be an object from New-OERAccessPackageRequestorScope.')) `
                -ErrorId 'InvalidPolicyInput' -Category InvalidArgument -TargetObject $RequestorScope -Cmdlet $PSCmdlet
            return
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

        $BodyParams = @{
            DisplayName     = $DisplayName
            AccessPackageId = $PackageId
            RequestorScope  = $RequestorScope
        }
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

        if ($PSCmdlet.ShouldProcess($DisplayName, "Create assignment policy on $PackageId")) {
            try {
                $Created = Invoke-OERGraphRequest -Method POST `
                    -Uri 'v1.0/identityGovernance/entitlementManagement/assignmentPolicies' -Body $Body
            } catch {
                Remove-OERErrorRecord -Record $PSItem
                $PSCmdlet.WriteError($PSItem)
                return
            }
            ConvertTo-OERAssignmentPolicy -InputObject $Created -AccessPackageId $PackageId
        }
    }
}
