function Sync-OERStructureRoleManagementPolicy {
    <#
    .SYNOPSIS
    Reconciles one roleManagementPolicies[] document entry against the live Azure PIM policy.

    .DESCRIPTION
    The orchestration handler for a single roleManagementPolicies entry from the structure document.
    It is called by the Invoke-OERStructure engine and emits one ConvertTo-OERStructureResult record
    describing what was updated or left unchanged.

    Updated-or-Unchanged only -- Azure PIM role management policies always exist (they are
    auto-created by ARM when PIM is enabled for a scope); there is nothing to create and nothing to
    delete. This handler therefore never emits Created, Removed, or Extra records, and -Prune is a
    no-op.

    Scope syntax: the document scope field is parsed into a Get-OERRoleManagementPolicy /
    Set-OERRoleManagementPolicy splat by ConvertTo-OERScopeSplat, which owns the structure document's
    scope syntax.
    - 'mg:<name>' -> -ManagementGroup <name>
    - 'subscription:<name>' or 'sub:<name>' -> -Subscription <name>
    - Any other value -> -Scope <value>, where a raw Azure Resource Manager path loses a trailing '/'
    When the engine passes -ResolvedScope (the scope its home tenant check resolved, BL-150), both cmdlets
    take -Scope <ResolvedScope> instead, and the document scope is not parsed here.

    Presence semantics: an OMITTED field in the document means "leave untouched", NOT "set to
    $false". Only the fields the document actually declares are compared and, when they differ,
    sent to Set-OERRoleManagementPolicy. If the document declares none of the supported fields,
    the policy is always Unchanged.

    Supported document fields (each maps to the matching Set-OERRoleManagementPolicy parameter;
    the diff is owned by Resolve-OERRoleManagementPolicyChange):
    - allowPermanentEligibility, eligibleDurationDays
    - allowPermanentActiveAssignment, activeDurationDays
    - activationMaxHours
    - requireMfaOnActivation, requireJustificationOnActivation, requireTicketOnActivation
    - requireApproval, approvers { users[], groups[] } -- users are UPNs or object ids and groups are
      group display names or object ids; both are resolved to object ids by Resolve-OERDeclaredApprover
      before the diff, so the diff only ever compares ids with ids. An approver that does not resolve
      reports Failed and changes nothing: the row carries ApproverNotFound for an approver that
      matches nothing, AmbiguousApproverName (naming the candidate ids) for a group display name
      several groups share, and the lookup's own error for a lookup that failed.
    - authenticationContextId (empty string disables it)
    - requireMfaOnActiveAssignment, requireJustificationOnActiveAssignment
    Fields the document does not declare are never compared and never sent. Notification rules and
    any other roleManagementPolicies field are NOT applied; Test-OERStructureSchema warns about
    unknown keys in this section so the drop is visible instead of silent.

    Every write is gated by $Caller.ShouldProcess. Under -WhatIf that returns $false and the
    handler emits Skipped instead of calling Set-OERRoleManagementPolicy. Reads always execute even
    under -WhatIf so the diff/plan is available.

    A read of the live policy that fails, or that returns no policy and no error, reports Failed --
    with the read's own error, or with PolicyNotFound -- before the approver lookup, the diff and the
    ShouldProcess gate, so nothing is written and -WhatIf reports the same row (BL-40).

    An entry whose change would send approvers naming nobody (the diff's ApproverRequired flag) is
    reported Failed, with the ApproverRequired error Set-OERRoleManagementPolicy publishes for the
    same refusal, before the ShouldProcess gate: the -WhatIf plan and the run report the same row,
    and nothing is sent. Name at least one approver, or declare requireApproval false.

    -Prune and -TenantAlias are accepted for a uniform Sync-OERStructure* signature but are no-ops
    in this handler.

    .PARAMETER Item
    One element from the roleManagementPolicies[] array in the structure document, as a
    PSCustomObject produced by ConvertFrom-Json. Expected properties: scope (string), role (string).
    All other fields are optional -- see the supported document fields list above.

    .PARAMETER Caller
    The engine's $PSCmdlet reference, used to gate writes with ShouldProcess and to route errors
    with WriteError. The engine passes its own $PSCmdlet here.

    .PARAMETER Prune
    Accepted for handler signature uniformity. Has no effect -- policies cannot be deleted.

    .PARAMETER TenantAlias
    Optional Tenant Profile alias forwarded for context. Accepted for handler signature uniformity
    but not used by this handler.

    .PARAMETER ResolvedScope
    Optional. The canonical scope the engine's home tenant check (Get-OERSubscriptionHomeTenant, BL-150)
    resolved the entry's scope to. When given, Get-OERRoleManagementPolicy and
    Set-OERRoleManagementPolicy are called with -Scope set to it instead of the splat
    ConvertTo-OERScopeSplat builds from the document scope, so the policy read and written is the one
    the check decided on. Every row still names the scope as the document wrote it.

    .EXAMPLE
    Sync-OERStructureRoleManagementPolicy -Item $DocItem -Caller $PSCmdlet
    Reconciles one role management policy entry from the document against the live Azure PIM policy.
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute(
        'PSShouldProcess', '',
        Justification = 'ShouldProcess is delegated to $Caller (the engine PSCmdlet) via $Caller.ShouldProcess(); this private handler does not carry its own SupportsShouldProcess because it never creates its own $PSCmdlet.'
    )]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute(
        'PSReviewUnusedParameter', 'TenantAlias',
        Justification = 'TenantAlias is part of the uniform Sync-OERStructure* handler signature; accepted for future use and caller consistency even though this handler does not resolve tenant defaults.'
    )]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute(
        'PSReviewUnusedParameter', 'Prune',
        Justification = 'Prune is part of the uniform Sync-OERStructure* handler signature; policies always exist so there is nothing to prune -- the switch is accepted for caller uniformity only.'
    )]
    [OutputType([PSCustomObject])]
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][PSCustomObject]$Item,
        [Parameter(Mandatory)][System.Management.Automation.PSCmdlet]$Caller,
        [switch]$Prune,
        [string]$TenantAlias,
        [string]$ResolvedScope
    )

    process {
        $Label   = "$($Item.role) @ $($Item.scope)"
        $Section = 'roleManagementPolicies'

        # BL-150: the engine resolved the scope once, in its home tenant check, and the policy read and
        # written must be at the scope that check decided on. The rows keep the document's own spelling.
        $ScopeSplat = if (-not [string]::IsNullOrEmpty($ResolvedScope)) {
            @{ Scope = $ResolvedScope }
        } else {
            ConvertTo-OERScopeSplat -Scope $Item.scope
        }

        # -- Read the current policy --------------------------------------------------------
        # BL-40: -ErrorAction Stop. Get-OERRoleManagementPolicy reports a failed read (a role or policy
        # it cannot find, a 403, a scope it cannot resolve) as a NON-terminating error and returns
        # nothing. Left at the preference's default, the error went to the stream and the read became
        # $null, which the diff took as "every declared field changed" -- and, for an entry declaring
        # one approver side, as an EMPTY undeclared side, so the write removed every live approver on
        # it. A failed read is reported as itself, with one Failed row, and nothing is written.
        $Cur = $null
        try {
            $Cur = Get-OERRoleManagementPolicy -Role $Item.role @ScopeSplat -ErrorAction Stop
        } catch {
            Remove-OERErrorRecord -Record $PSItem
            $Caller.WriteError($PSItem)
            ConvertTo-OERStructureResult -Section $Section -Item $Label -Action 'Failed' `
                -Detail "could not read role management policy for '$($Item.role)' at '$($Item.scope)': $($PSItem.Exception.Message)" `
                -ErrorRecord $PSItem
            return
        }
        if ($null -eq $Cur) {
            # A read that answered with no policy and no error is no evidence of the live policy either:
            # comparing the declared fields with $null would send every one of them. Refused before the
            # approver lookup, the diff, the ApproverRequired check and ShouldProcess, so the -WhatIf plan
            # reports the same row. PolicyNotFound is the id Get-OERRoleManagementPolicy publishes for a
            # policy it cannot find.
            $ErrRec = [System.Management.Automation.ErrorRecord]::new(
                [System.Exception]::new("Get-OERRoleManagementPolicy returned no role management policy for '$($Item.role)' at '$($Item.scope)' and no error, so the live policy is unknown. The policy was not changed."),
                'PolicyNotFound',
                [System.Management.Automation.ErrorCategory]::ObjectNotFound,
                $Label)
            $Caller.WriteError($ErrRec)
            ConvertTo-OERStructureResult -Section $Section -Item $Label -Action 'Failed' `
                -Detail "Get-OERRoleManagementPolicy returned no policy for '$($Item.role)' at '$($Item.scope)'; the policy was not changed" `
                -ErrorRecord $ErrRec
            return
        }

        # -- Resolve declared approver names to object ids BEFORE the diff ------------------
        # The diff compares ids with ids. A user declared by UPN never matched the live approver
        # (whose description is a display name), so the policy reported a change on every run.
        # Three outcomes, three records, one Failed row each and no write, the class decided by
        # Get-OERApproverErrorClass: an ambiguous name is AmbiguousApproverName (the resolver's text
        # names the candidate ids), only an approver that matches nothing (ApproverUnresolved) is
        # ApproverNotFound, and anything else -- a 403, an exhausted 429, a 5xx -- is not evidence that
        # the approver is missing, so it is published as itself. The caught record is kept in
        # $LookupError: inside the switch, $PSItem is the class.
        $Declared = $Item
        try {
            $Declared = Resolve-OERDeclaredApprover -Declared $Item
        } catch {
            Remove-OERErrorRecord -Record $PSItem
            $LookupError = $PSItem
            $ErrRec = $LookupError
            switch (Get-OERApproverErrorClass -Record $LookupError) {
                'Ambiguous' {
                    $ErrRec = [System.Management.Automation.ErrorRecord]::new(
                        [System.Exception]::new("Could not resolve an approver declared for '$($Item.role)' at '$($Item.scope)': $($LookupError.Exception.Message)", $LookupError.Exception),
                        'AmbiguousApproverName',
                        [System.Management.Automation.ErrorCategory]::InvalidArgument,
                        $LookupError.TargetObject)
                }
                'NotFound' {
                    $ErrRec = [System.Management.Automation.ErrorRecord]::new(
                        [System.Exception]::new("Could not resolve an approver declared for '$($Item.role)' at '$($Item.scope)': $($LookupError.Exception.Message)", $LookupError.Exception),
                        'ApproverNotFound',
                        [System.Management.Automation.ErrorCategory]::ObjectNotFound,
                        $Label)
                }
            }
            $Caller.WriteError($ErrRec)
            ConvertTo-OERStructureResult -Section $Section -Item $Label -Action 'Failed' `
                -Detail "could not resolve an approver: $($LookupError.Exception.Message); the policy was not changed" `
                -ErrorRecord $ErrRec
            return
        }

        # -- Diff the declared fields against the live policy --------------------------------
        # Resolve-OERRoleManagementPolicyChange is the single owner of the presence semantics and the
        # field-to-parameter mapping; it returns only the parameters that actually differ.
        $Change = Resolve-OERRoleManagementPolicyChange -Declared $Declared -Current $Cur
        $SetSplat = $Change.SetParams

        # -- Unchanged if nothing differs ---------------------------------------------------
        if (-not $Change.Changed) {
            ConvertTo-OERStructureResult -Section $Section -Item $Label -Action 'Unchanged' `
                -Detail "policy already matches for '$($Item.role)' at '$($Item.scope)'"
            return
        }

        # -- Approvers that name nobody: Failed before the gate (BL-97, F1) ------------------
        # Set-OERRoleManagementPolicy refuses this change with ApproverRequired before anything is
        # sent, so the run reported Failed while the -WhatIf plan said "would update". The diff flags
        # it (Resolve-OERRoleManagementPolicyChange owns the condition); refusing it here, before
        # ShouldProcess, gives the plan and the run the same Failed row, and nothing is sent. The
        # ErrorId is the one Set-OERRoleManagementPolicy publishes for the same refusal.
        if ($Change.ApproverRequired) {
            $Message = "Approval would be required with no approver for '$($Item.role)' at '$($Item.scope)': " +
                'the declared approvers, with any side the document does not declare kept from the live policy, ' +
                'name nobody, and Azure Resource Manager replaces the whole approver list. Name at least one ' +
                'approver, or declare requireApproval false. The policy was not changed.'
            $ErrRec = [System.Management.Automation.ErrorRecord]::new(
                [System.Exception]::new($Message),
                'ApproverRequired',
                [System.Management.Automation.ErrorCategory]::InvalidArgument,
                $Label)
            $Caller.WriteError($ErrRec)
            ConvertTo-OERStructureResult -Section $Section -Item $Label -Action 'Failed' `
                -Detail "approval would be required with no approver (ApproverRequired): the declared approvers, with any side the document does not declare kept from the live policy, name nobody; the policy was not changed" `
                -ErrorRecord $ErrRec
            return
        }

        # -- Gate the update on ShouldProcess -----------------------------------------------
        if (-not $Caller.ShouldProcess("$($Item.role) @ $($Item.scope)", 'Update role management policy')) {
            ConvertTo-OERStructureResult -Section $Section -Item $Label -Action 'Skipped' `
                -Detail "would update role management policy for '$($Item.role)' at '$($Item.scope)'"
            return
        }

        try {
            $null = Set-OERRoleManagementPolicy -Role $Item.role @ScopeSplat @SetSplat -Confirm:$false -ErrorAction Stop
            ConvertTo-OERStructureResult -Section $Section -Item $Label -Action 'Updated' `
                -Detail "updated role management policy for '$($Item.role)' at '$($Item.scope)' ($($Change.Changes -join ', '))"
        } catch {
            Remove-OERErrorRecord -Record $PSItem
            $Caller.WriteError($PSItem)
            ConvertTo-OERStructureResult -Section $Section -Item $Label -Action 'Failed' `
                -Detail "failed to update role management policy: $($PSItem.Exception.Message)" `
                -ErrorRecord $PSItem
        }
    }
}
