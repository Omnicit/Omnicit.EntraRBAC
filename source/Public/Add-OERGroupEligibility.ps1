function Add-OERGroupEligibility {
    <#
    .SYNOPSIS
    Grants a principal PIM-for-groups eligibility for a group, onboarding the group to PIM.

    .DESCRIPTION
    Creates a PIM-for-groups eligibility schedule request that makes a principal eligible to activate
    the member (or owner) access of a group. The admin operation is selected by -Action: adminAssign
    (the default) creates a new eligibility, while adminUpdate changes an existing one -- the
    Invoke-OERStructure apply engine passes adminUpdate when re-issuing an eligibility whose declared
    duration or permanence has drifted from the live schedule, since Microsoft Graph rejects an
    adminAssign against a principal that is already eligible. The first eligibility request onboards
    the group to PIM for Groups if it was not onboarded yet, which cannot be undone (Microsoft Graph
    documentation, "Onboarding groups to PIM for Groups"); its activation policy is listed, and can be
    configured with Set-OERGroupPimPolicy, either way. The target group is given by -Group (display
    name or object id, resolved via Resolve-OERGroupId). The principal is named with -User (user
    principal name or object id),
    -GroupPrincipal (group display name or object id), or -ServicePrincipal (service principal display
    name or object id), or supplied as a raw object id with -PrincipalId. Supply exactly one. Note that
    -Group is the TARGET group whose access is granted, while -GroupPrincipal is the group that becomes
    eligible. The request body is built by the private New-OERGroupEligibilityBody helper. The result is
    a tagged Omnicit.EntraRBAC.GroupEligibility object. Supports -WhatIf and -Confirm. A permanent
    grant that needs the PIM-for-groups policy opened opens it only once the grant itself is
    confirmed (declining the prompt weakens nothing, while -WhatIf still plans the policy change),
    and a grant that then fails reports a PolicyOpenedButGrantFailed error naming the policy that is
    left open -- there is no public inverse for that surgical single-rule open, so it is not rolled
    back automatically.
    Microsoft Graph can accept a request and answer it with a status in the Failed family (Failed, or
    any status that starts with Failed, in any letter case), which grants nothing. The cmdlet then
    still emits the request object (its Status reads as answered) and afterwards writes a
    non-terminating EligibilityRequestFailed error (category InvalidResult, target the group id), so
    a caller running with -ErrorAction Stop still receives the object, for example through
    -OutVariable, before the error stops it. Re-running the same request usually succeeds: a group
    created moments ago can take a while to be known to PIM for Groups. Only the Failed family is an
    error; PendingApproval, Provisioned and every other status are not. When this invocation had
    opened the policy for a permanent grant, the EligibilityRequestFailed message also names that
    policy, which is left open, and how to close it, as PolicyOpenedButGrantFailed does.

    .PARAMETER Group
    The target group whose member or owner eligibility is granted, given as a display name or object id
    (GUID) and resolved via Resolve-OERGroupId. Accepts the GroupId, Id, and DisplayName aliases (GroupId
    takes precedence during pipeline binding so a piped Get-OERGroupMember object binds the group's
    GroupId instead of a principal's Id) and binds from the pipeline by property name so Get-OERGroup
    pipes straight in.

    .PARAMETER PrincipalId
    The object id (GUID) of the principal to make eligible -- a user, group, or service principal. Mutually
    exclusive with -User; supply exactly one. A non-GUID value yields an InvalidPrincipalId error directing
    you to -User, -GroupPrincipal or -ServicePrincipal.

    .PARAMETER User
    The user to make eligible, given as a user principal name or object id (GUID) and resolved via
    Resolve-OERPrincipal. Mutually exclusive with -PrincipalId, -GroupPrincipal and -ServicePrincipal;
    supply exactly one.

    .PARAMETER GroupPrincipal
    The group to make eligible, given as a group display name or object id (GUID) and resolved via
    Resolve-OERPrincipal. This is the principal that becomes eligible, not the target group -- the
    target group is -Group. Mutually exclusive with the other principal parameters. Group display
    names are not guaranteed unique in Entra ID; if more than one group shares the given name, the
    command fails with an error naming the candidate object ids, so re-run with the object id.

    .PARAMETER ServicePrincipal
    The service principal to make eligible, given as a service principal display name or object id
    (GUID) and resolved via Resolve-OERPrincipal. A GUID is treated as the service principal object
    id, never as an application id. Mutually exclusive with the other principal parameters.

    .PARAMETER AccessType
    Whether the eligibility is for member or owner access of the group. Defaults to member.

    .PARAMETER Duration
    Lifetime of the eligible assignment, as either a raw ISO 8601 duration (for example 'P365D' or
    'PT8H') or -- the form this cmdlet shipped with -- a bare whole number of days (for example 365,
    capped at 3650). Omitting every duration parameter requests a PERMANENT eligibility, which
    auto-opens the governing PIM-for-groups policy. Mutually exclusive with -DurationDays. Before
    submitting the request the cmdlet checks the group's PIM-for-groups policy and, if permanent
    eligibility is not yet allowed, automatically opens it with a loud warning (see
    Set-OERGroupPimPolicy -AllowPermanentEligibility for the manual equivalent). If Microsoft Graph
    does not list the group's policy for that access type yet (in practice a group created moments
    ago; a group never used with PIM for Groups does list its policies) the cmdlet writes a
    GroupNotOnboarded error and skips the POST -- re-run the permanent assignment after a short while.
    If the policy open fails (e.g. due to
    insufficient permissions) the cmdlet writes a PolicyOpenFailed error and skips the POST -- run
    Set-OERGroupPimPolicy with -AllowPermanentEligibility directly or supply -DurationDays instead.

    .PARAMETER DurationDays
    Lifetime of the eligible assignment in whole days (1-3650), the module-standard friendly form
    matching New-OEREligibleRoleAssignment. Converted to an ISO 8601 duration for Microsoft Graph.
    Mutually exclusive with the raw ISO -Duration.

    .PARAMETER Justification
    Justification text recorded on the eligibility schedule request for audit purposes.

    .PARAMETER TenantId
    Optional tenant id or domain to authenticate against, forwarded to Initialize-OERAuth.

    .PARAMETER Action
    The Microsoft Graph admin operation for the eligibility schedule request. adminAssign (the
    default) creates a new eligibility for a principal that is not yet eligible; adminUpdate changes
    an existing eligibility's window or access type instead. Sending adminAssign against a principal
    that already has an eligibility of the requested access type is rejected by Microsoft Graph, so
    the Invoke-OERStructure apply engine (via Sync-OERStructureGroup) passes -Action adminUpdate when
    it re-issues an eligibility whose declared durationDays or permanence has drifted from the live
    schedule instance.

    .EXAMPLE
    Add-OERGroupEligibility -Group 'role_sec_identity_administrator' -User 'anna.berg@contoso.com' -Duration 365
    Makes the user eligible for the group's member access for 365 days and onboards the group to PIM.

    .EXAMPLE
    Add-OERGroupEligibility -Group 'role_sec_identity_administrator' -GroupPrincipal 'Sales Team'
    Makes a group permanently eligible by name (requires the policy to allow permanent eligible assignments).

    .EXAMPLE
    Add-OERGroupEligibility -Group 'role_sec_identity_administrator' -User 'anna.berg@contoso.com' -DurationDays 365
    Grants a 365-day member eligibility using the module-standard day-count parameter.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory, ValueFromPipelineByPropertyName)]
        # GroupId precedes Id so a piped GroupMember object binds the group's GroupId, not the
        # principal's Id, during ValueFromPipelineByPropertyName alias resolution.
        [Alias('GroupId', 'Id', 'DisplayName')]
        [string]$Group,

        [string]$PrincipalId,

        [string]$User,

        [ValidateSet('member', 'owner')]
        [string]$AccessType = 'member',

        [string]$Duration,

        [string]$Justification = 'Omnicit.EntraRBAC: PIM-for-groups eligible assignment',

        [ValidateNotNullOrEmpty()]
        [string]$TenantId,

        # Declared after the pre-existing parameters so their positional binding is unchanged.
        [string]$GroupPrincipal,

        [string]$ServicePrincipal,

        # Declared after the pre-existing parameters so their positional binding is unchanged.
        [ValidateSet('adminAssign', 'adminUpdate')]
        [string]$Action = 'adminAssign',

        # Declared last so it never shifts any existing positional binding.
        [ValidateRange(1, 3650)]
        [int]$DurationDays
    )
    begin {
        $AuthParams = @{}
        if ($TenantId) { $AuthParams.TenantId = $TenantId }
        Initialize-OERAuth @AuthParams
    }
    process {
        # Refuse an ambiguous display name loudly, and surface any other throw as itself. Only a
        # $null return (a display name that matched nothing) reaches the not-found branch.
        $GroupId = $null
        try {
            $GroupId = Resolve-OERGroupId -DisplayName $Group
        } catch {
            Remove-OERErrorRecord -Record $PSItem
            if (Test-OERAmbiguousNameError -Record $PSItem) {
                Write-CmdletError `
                    -Message ([System.Exception]::new($PSItem.Exception.Message)) `
                    -ErrorId 'AmbiguousGroupName' -Category InvalidArgument `
                    -TargetObject $Group -Cmdlet $PSCmdlet
                return
            }
            # Anything else the resolver raised -- a 403, an exhausted 429, a 5xx -- is not evidence that
            # no such group exists: surface it as itself, never as the not-found below.
            $PSCmdlet.WriteError($PSItem)
            return
        }
        if (-not $GroupId) {
            Write-CmdletError `
                -Message ([System.Exception]::new(
                    "Group '$Group' not found. Verify the display name matches exactly (leading or trailing spaces " +
                    "and punctuation count) or pass the group object id instead.")) `
                -ErrorId 'GroupNotFound' -Category ObjectNotFound -TargetObject $Group -Cmdlet $PSCmdlet
            return
        }
        Write-Verbose "[Add-OERGroupEligibility] Resolved group to '$GroupId'."

        $Principal = Resolve-OERPrincipalOrId -PrincipalId $PrincipalId -User $User `
            -Group $GroupPrincipal -GroupParameterName 'GroupPrincipal' -ServicePrincipal $ServicePrincipal `
            -FriendlyParameterHint '-User, -GroupPrincipal or -ServicePrincipal'
        if ($Principal.ErrorId) {
            Write-CmdletError -Message ([System.Exception]::new($Principal.Message)) `
                -ErrorId $Principal.ErrorId -Category $Principal.Category `
                -TargetObject $Principal.TargetObject -Cmdlet $PSCmdlet
            return
        }
        $ResolvedPrincipalId = $Principal.PrincipalId
        Write-Verbose "[Add-OERGroupEligibility] Resolved principal to '$ResolvedPrincipalId'."

        # One duration vocabulary: -Duration takes a raw ISO 8601 duration (and, for back-compat with
        # the shipped signature, a bare whole day count), -DurationDays takes whole days. Supplying
        # neither still means a PERMANENT eligibility, which is what drives the policy self-heal below.
        if ($PSBoundParameters.ContainsKey('Duration') -and $PSBoundParameters.ContainsKey('DurationDays')) {
            Write-CmdletError -Message ([System.Exception]::new('Supply only one of -Duration or -DurationDays.')) `
                -ErrorId 'AmbiguousDuration' -Category InvalidArgument -TargetObject $GroupId -Cmdlet $PSCmdlet
            return
        }
        $IsoDuration = $null
        if ($PSBoundParameters.ContainsKey('Duration')) {
            try { $IsoDuration = Resolve-OERDurationInput -Value $Duration -Unit Days }
            catch {
                Remove-OERErrorRecord -Record $PSItem
                Write-CmdletError -Message ([System.Exception]::new("-Duration: $($PSItem.Exception.Message)")) `
                    -ErrorId 'InvalidDuration' -Category InvalidArgument -TargetObject $Duration -Cmdlet $PSCmdlet
                return
            }
        }
        elseif ($PSBoundParameters.ContainsKey('DurationDays')) {
            $IsoDuration = ConvertTo-OERDuration -Days $DurationDays
        }

        # The pre-check is a READ, so it runs BEFORE the gate and its warning is emitted before the
        # operator is asked. The confirmation prompt names only the eligibility grant, so hiding the
        # policy warning behind it would ask the operator to approve a change to ALL eligibility for
        # this group without saying so. Only the policy WRITE is gated below.
        $NeedsPolicyOpen = $false
        $PendingPolicyId = $null
        if (-not $IsoDuration) {
            $GroupState = $null
            try {
                $GroupState = Get-OERGroupPermanentEligibilityState -GroupId $GroupId -AccessType $AccessType
            } catch {
                Remove-OERErrorRecord -Record $PSItem
                Write-Verbose "[Add-OERGroupEligibility] Could not pre-check the PIM-for-groups policy: $($PSItem.Exception.Message). Proceeding; Microsoft Graph will enforce the policy."
            }
            if ($GroupState -and -not $GroupState.HasPolicy) {
                Write-CmdletError -Message ([System.Exception]::new("Microsoft Graph does not list a PIM-for-groups policy for '$AccessType' access on group '$GroupId' yet, so it cannot be opened for permanent eligibility. A group created moments ago can take a short while before its policies are listed (replication delay); re-run the permanent assignment after a short while.")) -ErrorId 'GroupNotOnboarded' -Category ObjectNotFound -TargetObject $GroupId -Cmdlet $PSCmdlet
                return
            }
            if ($GroupState -and $GroupState.HasPolicy -and -not $GroupState.PermanentAllowed) {
                $NeedsPolicyOpen = $true
                $PendingPolicyId = $GroupState.PolicyId
                Write-Warning "This eligibility requires opening the PIM-for-groups policy for group '$GroupId' ($AccessType access) to allow PERMANENT eligible assignments, which affects ALL $AccessType eligibility for this group."
                if ($GroupState.PolicyId) {
                    Write-Verbose "[Add-OERGroupEligibility] Resolved PIM policy id: '$($GroupState.PolicyId)'."
                }
            }
        }

        # Decide ONCE. Opening the policy is a mutation and must not run when the operator declines.
        # Under -WhatIf, ShouldProcess returns $false but $WhatIfPreference is $true, and the
        # self-gating Enable-OERGroupPermanentEligibility only prints its own plan line -- so the
        # -WhatIf plan still shows the policy open, while a DECLINED prompt ($Proceed false,
        # $WhatIfPreference false) weakens nothing.
        $Proceed = $PSCmdlet.ShouldProcess($GroupId, "Grant PIM $AccessType eligibility to '$ResolvedPrincipalId'")

        $PolicyOpened = $false
        $OpenedPolicyId = $null
        if (($Proceed -or $WhatIfPreference) -and $NeedsPolicyOpen) {
            try {
                # The helper is self-gating: under an explicit -Confirm the propagated
                # $ConfirmPreference makes it prompt on its own, and a declined prompt returns $false
                # having written nothing. Take the flag from its answer -- setting it unconditionally
                # would later name a policy that was never opened.
                $OpenResult = Enable-OERGroupPermanentEligibility -PolicyId $PendingPolicyId -ErrorAction Stop
                if ($OpenResult) {
                    $PolicyOpened = $true
                    $OpenedPolicyId = $PendingPolicyId
                }
            } catch {
                Remove-OERErrorRecord -Record $PSItem
                Write-CmdletError -Message ([System.Exception]::new("Could not open the PIM-for-groups policy to allow permanent eligibility: $($PSItem.Exception.Message) Run 'Set-OERGroupPimPolicy -Group ''$GroupId'' -AccessType $AccessType -ActivationMaxHours <n> -AllowPermanentEligibility' with sufficient permissions, or grant a time-bound eligibility with -DurationDays.")) -ErrorId 'PolicyOpenFailed' -Category PermissionDenied -TargetObject $PendingPolicyId -Cmdlet $PSCmdlet
                return
            }
        }

        $BodyParams = @{
            GroupId       = $GroupId
            PrincipalId   = $ResolvedPrincipalId
            AccessType    = $AccessType
            Action        = $Action
            Justification = $Justification
        }
        if ($IsoDuration) {
            $BodyParams.Duration = $IsoDuration
        }
        $Body = New-OERGroupEligibilityBody @BodyParams

        # The one place the advice for a policy this invocation left open is written: the two
        # messages below (PolicyOpenedButGrantFailed and EligibilityRequestFailed) both give it.
        $PolicyStillOpenAdvice = "The policy is still open; close it with 'Set-OERGroupPimPolicy -Group ''$GroupId'' -AccessType $AccessType -ActivationMaxHours <n>' (without -AllowPermanentEligibility) if you do not intend to retry."

        if ($Proceed) {
            try {
                $Response = Invoke-OERGraphRequest -Method POST -Uri (Get-OERPimGroupsGraphPath -Path 'identityGovernance/privilegedAccess/group/eligibilityScheduleRequests') -Body $Body
            } catch {
                Remove-OERErrorRecord -Record $PSItem
                $GrantError = $PSItem
                if ($PolicyOpened) {
                    # The grant failed AFTER this invocation weakened the governing policy. There is
                    # no public inverse for the surgical single-rule open, so name the policy that is
                    # left open instead of attempting a rollback this module cannot perform correctly.
                    # Report it FIRST, with the grant's own message inside it, and only then re-publish
                    # the grant's own error: under -ErrorAction Stop the first error written stops this
                    # command, so the advice must be in that first error or it is never written.
                    Write-CmdletError -Message ([System.Exception]::new("The PIM $AccessType eligibility grant failed after PIM-for-groups policy '$OpenedPolicyId' had been opened to allow permanent eligibility. $PolicyStillOpenAdvice The request failed with: $($GrantError.Exception.Message)")) -ErrorId 'PolicyOpenedButGrantFailed' -Category InvalidOperation -TargetObject $OpenedPolicyId -Cmdlet $PSCmdlet
                }
                $PSCmdlet.WriteError($GrantError)
                return
            }
            $Request = ConvertTo-OERGroupEligibilityRequest -InputObject $Response `
                -GroupId $GroupId -PrincipalId $ResolvedPrincipalId -AccessType $AccessType -Action $Action
            # Emitted first, as always, so a caller under -ErrorAction Stop still receives the request
            # (through -OutVariable, for example) before the error below stops it.
            $Request
            # Microsoft Graph can ACCEPT the request (201) and answer it with a status in the Failed
            # family, which grants nothing. Test-OERScheduleRequestFailed owns which statuses that is
            # (case-insensitive); PendingApproval, Provisioned and every other status are the request
            # applied or on its way.
            # $script:_OERGroupEligibilityFailedIsReplication is set by Sync-OERStructureGroup around
            # its call for a group created in the same run ONLY, where a Failed answer is replication
            # that the engine waits on and asks again from its shared budget. It cannot be told any
            # other way: a record written here lands in the engine caller's -ErrorVariable even when
            # the engine catches the throw (measured: the ActionPreferenceStopException and this record
            # both stay there), so a run that ends Updated would still hand back errors. Never set
            # anywhere else, and not a public parameter.
            if ((Test-OERScheduleRequestFailed -Status $Request.Status) -and -not $script:_OERGroupEligibilityFailedIsReplication) {
                $FailedMessage = "Microsoft Graph accepted the PIM $AccessType eligibility request '$($Request.RequestId)' for principal '$ResolvedPrincipalId' on group '$GroupId' but answered status $($Request.Status), so nothing was granted; re-running the same request usually succeeds (a group created moments ago can take a while to be known to PIM for Groups)."
                if ($PolicyOpened) {
                    # The same advice PolicyOpenedButGrantFailed gives: this invocation weakened the
                    # policy, nothing was granted, and there is no public inverse to roll it back.
                    $FailedMessage += " PIM-for-groups policy '$OpenedPolicyId' had been opened to allow permanent eligibility before the request was sent. $PolicyStillOpenAdvice"
                }
                Write-CmdletError -Message ([System.Exception]::new($FailedMessage)) `
                    -ErrorId 'EligibilityRequestFailed' -Category InvalidResult -TargetObject $GroupId -Cmdlet $PSCmdlet
            }
        }
    }
}
