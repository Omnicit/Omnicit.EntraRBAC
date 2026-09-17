function New-OERAccessPackageApprovalStage {
    <#
    .SYNOPSIS
    Builds one approval stage for an access package assignment policy.

    .DESCRIPTION
    Returns a tagged Omnicit.EntraRBAC.ApprovalStage object describing a single approval stage, for
    use with the -ApprovalStage parameter of New/Set-OERAccessPackageAssignmentPolicy. Primary
    approvers are given as any combination of -User (user principal names or ids), -Group (group
    display names or ids), -Manager (with optional -ManagerLevel), -InternalSponsor, and
    -ExternalSponsor; at least one is required. Names are resolved to object ids and a GUID is used
    directly. -AlternateUser/-AlternateGroup supply escalation approvers. -EscalationDays enables
    forwarding to the alternates after the given number of days. Resolution authenticates lazily (only
    when a name is present), so a pure-GUID input performs no Graph call. The object carries a
    GraphStage member holding the Graph-ready stage body for direct insertion into the policy body.
    There is no builder support for a portal-set ESCALATION-approver fallback
    (fallbackEscalationApprovers): this cmdlet always emits an empty one, so building a stage with
    this cmdlet clears any escalation-approver fallback configured in the portal. -FallbackUser and
    -FallbackGroup cover only the PRIMARY approver's fallback -- the case that bites is a manager or
    sponsor escalation configured in the portal, since a -AlternateUser/-AlternateGroup escalation
    approver needs no fallback of its own.

    .PARAMETER DurationDays
    The number of days an approver has to decide before the request is automatically denied.
    Emitted as the ISO 8601 duration durationBeforeAutomaticDenial (for example 7 -> P7D).

    .PARAMETER User
    Zero or more primary approver user principal names or user object ids (GUIDs).

    .PARAMETER Group
    Zero or more primary approver group display names or group object ids (GUIDs).

    .PARAMETER Manager
    Add the requestor's manager as a primary approver (requestorManager).

    .PARAMETER ManagerLevel
    The manager chain depth used with -Manager. Defaults to 1.

    .PARAMETER InternalSponsor
    Add the access package's internal sponsors as primary approvers.

    .PARAMETER ExternalSponsor
    Add the access package's external sponsors as primary approvers.

    .PARAMETER AlternateUser
    Zero or more escalation approver user principal names or user object ids (GUIDs).

    .PARAMETER AlternateGroup
    Zero or more escalation approver group display names or group object ids (GUIDs).

    .PARAMETER RequireJustification
    Require approvers to provide a justification (isApproverJustificationRequired = $true).

    .PARAMETER EscalationDays
    Enable escalation to the alternate approvers after this many days. Sets isEscalationEnabled to
    $true and emits durationBeforeEscalation as the ISO 8601 duration (for example 8 -> P8D). When
    omitted, durationBeforeEscalation is PT0S and isEscalationEnabled is $false.

    .PARAMETER ApproverInfoVisibility
    Controls whether the requestor can see approver details (Graph approverInformationVisibility).
    Default leaves the Graph field as 'default' (tenant policy decides). Visible always shows approver
    details to the requestor. NotVisible always hides them. Maps to 'default', 'visible', 'notVisible'.

    .PARAMETER TenantId
    Optional tenant id or domain to authenticate against, forwarded to Initialize-OERAuth.

    .PARAMETER FallbackUser
    Zero or more user principal names or user object ids (GUIDs) who receive the request when
    entitlement management cannot find the manager or sponsor for the requestor (fallbackPrimaryApprovers).
    Only meaningful on a -Manager / -InternalSponsor / -ExternalSponsor stage. Declared last so
    existing positional callers are unaffected.

    .PARAMETER FallbackGroup
    Zero or more group display names or group object ids (GUIDs) who receive the request when
    entitlement management cannot find the manager or sponsor for the requestor (fallbackPrimaryApprovers).
    Only meaningful on a -Manager / -InternalSponsor / -ExternalSponsor stage. Declared last so
    existing positional callers are unaffected.

    .EXAMPLE
    New-OERAccessPackageApprovalStage -DurationDays 7 -Manager -RequireJustification
    Builds a single-stage manager-approval stage with a 7-day timeout and required justification.

    .EXAMPLE
    New-OERAccessPackageApprovalStage -DurationDays 14 -User 'anna.berg@contoso.com' -AlternateGroup 'Escalation Approvers' -EscalationDays 8
    Builds a stage that escalates to a group after 8 days if the primary approver has not acted.
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '',
        Justification = 'Read-only builder; resolves names via Graph lookups and returns an object, but changes no state.')]
    [OutputType([PSCustomObject])]
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [int]$DurationDays,

        [string[]]$User,

        [string[]]$Group,

        [switch]$Manager,

        [int]$ManagerLevel = 1,

        [switch]$InternalSponsor,

        [switch]$ExternalSponsor,

        [string[]]$AlternateUser,

        [string[]]$AlternateGroup,

        [switch]$RequireJustification,

        [int]$EscalationDays,

        [ValidateSet('Default', 'Visible', 'NotVisible')]
        [string]$ApproverInfoVisibility = 'Default',

        [string]$TenantId,

        # Declared last (after every pre-existing parameter) so positional binding for existing
        # callers is unchanged.
        [string[]]$FallbackUser,

        [string[]]$FallbackGroup
    )
    process {
        if (-not ($User -or $Group -or $Manager -or $InternalSponsor -or $ExternalSponsor)) {
            Write-CmdletError `
                -Message ([System.Exception]::new('At least one approver is required: supply -User, -Group, -Manager, -InternalSponsor, or -ExternalSponsor.')) `
                -ErrorId 'NoApprover' -Category InvalidArgument -TargetObject $DurationDays -Cmdlet $PSCmdlet
            return
        }

        $AuthParams = @{}
        if ($TenantId) { $AuthParams.TenantId = $TenantId }

        $PrimaryResolved = Resolve-OERTargetList -User $User -Group $Group @AuthParams
        if ($PrimaryResolved.FailedValue) {
            # A resolver that supplies its own ErrorId/message knows more about the failure than the
            # generic "<Kind> '<Value>' not found." construction can express -- prefer it when present.
            $ErrId = if ($PrimaryResolved.FailedErrorId) { $PrimaryResolved.FailedErrorId }
            elseif ($PrimaryResolved.FailedKind -eq 'User') { 'UserNotFound' } else { 'GroupNotFound' }
            $Msg = if ($PrimaryResolved.FailedMessage) { $PrimaryResolved.FailedMessage }
            else { "$($PrimaryResolved.FailedKind) '$($PrimaryResolved.FailedValue)' not found." }
            # An ambiguity is a bad argument, not a missing object. Resolve-OERTargetList sets
            # FailedErrorId only for that case, so the not-found path keeps ObjectNotFound unchanged.
            $Cat = if ($PrimaryResolved.FailedErrorId) { 'InvalidArgument' } else { 'ObjectNotFound' }
            Write-CmdletError `
                -Message ([System.Exception]::new($Msg)) `
                -ErrorId $ErrId -Category $Cat -TargetObject $PrimaryResolved.FailedValue -Cmdlet $PSCmdlet
            return
        }

        $Primary = @($PrimaryResolved.Approvers)
        if ($Manager) { $Primary += New-OERApproverObject -Spec @{ Manager = $true; ManagerLevel = $ManagerLevel } }
        if ($InternalSponsor) { $Primary += New-OERApproverObject -Spec @{ InternalSponsor = $true } }
        if ($ExternalSponsor) { $Primary += New-OERApproverObject -Spec @{ ExternalSponsor = $true } }

        $EscalationResolved = Resolve-OERTargetList -User $AlternateUser -Group $AlternateGroup @AuthParams
        if ($EscalationResolved.FailedValue) {
            # Prefer the resolver's own ErrorId/message (an ambiguous name names the candidate ids).
            $ErrId = if ($EscalationResolved.FailedErrorId) { $EscalationResolved.FailedErrorId }
            elseif ($EscalationResolved.FailedKind -eq 'User') { 'UserNotFound' } else { 'GroupNotFound' }
            $Msg = if ($EscalationResolved.FailedMessage) { $EscalationResolved.FailedMessage }
            else { "$($EscalationResolved.FailedKind) '$($EscalationResolved.FailedValue)' not found." }
            $Cat = if ($EscalationResolved.FailedErrorId) { 'InvalidArgument' } else { 'ObjectNotFound' }
            Write-CmdletError `
                -Message ([System.Exception]::new($Msg)) `
                -ErrorId $ErrId -Category $Cat -TargetObject $EscalationResolved.FailedValue -Cmdlet $PSCmdlet
            return
        }
        $Escalation = @($EscalationResolved.Approvers)

        $FallbackResolved = Resolve-OERTargetList -User $FallbackUser -Group $FallbackGroup @AuthParams
        if ($FallbackResolved.FailedValue) {
            # Prefer the resolver's own ErrorId/message (an ambiguous name names the candidate ids).
            $ErrId = if ($FallbackResolved.FailedErrorId) { $FallbackResolved.FailedErrorId }
            elseif ($FallbackResolved.FailedKind -eq 'User') { 'UserNotFound' } else { 'GroupNotFound' }
            $Msg = if ($FallbackResolved.FailedMessage) { $FallbackResolved.FailedMessage }
            else { "$($FallbackResolved.FailedKind) '$($FallbackResolved.FailedValue)' not found." }
            $Cat = if ($FallbackResolved.FailedErrorId) { 'InvalidArgument' } else { 'ObjectNotFound' }
            Write-CmdletError `
                -Message ([System.Exception]::new($Msg)) `
                -ErrorId $ErrId -Category $Cat -TargetObject $FallbackResolved.FailedValue -Cmdlet $PSCmdlet
            return
        }
        $Fallback = @($FallbackResolved.Approvers)

        $VisibilityMap = @{ Default = 'default'; Visible = 'visible'; NotVisible = 'notVisible' }

        $GraphStage = [ordered]@{
            durationBeforeAutomaticDenial   = ConvertTo-OERDuration -Days $DurationDays
            isApproverJustificationRequired = [bool]$RequireJustification
            approverInformationVisibility   = $VisibilityMap[$ApproverInfoVisibility]
            isEscalationEnabled             = [bool]($PSBoundParameters.ContainsKey('EscalationDays'))
            durationBeforeEscalation        = if ($PSBoundParameters.ContainsKey('EscalationDays')) {
                ConvertTo-OERDuration -Days $EscalationDays
            }
            else {
                'PT0S'
            }
            primaryApprovers                = @($Primary)
            fallbackPrimaryApprovers        = @($Fallback)
            escalationApprovers             = @($Escalation)
            # fallbackEscalationApprovers is not authorable through this builder -- Learn documents the
            # fallback mechanism in terms of a missing manager/sponsor on the PRIMARY approver, and the
            # Entra UI exposes a single "Add fallback" control. Sent as @() so the field stays modelled
            # on the write side without inventing a use nobody verified.
            fallbackEscalationApprovers     = @()
        }

        $Out = [PSCustomObject]@{
            DurationDays = $DurationDays
            Approvers    = @($Primary).Count
            GraphStage   = $GraphStage
        }
        $Out.PSObject.TypeNames.Insert(0, 'Omnicit.EntraRBAC.ApprovalStage')
        $Out
    }
}
