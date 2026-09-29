function Sync-OERStructureDirectoryRoleManagementPolicy {
    <#
    .SYNOPSIS
    Reconciles one directoryRoleManagementPolicies[] document entry against the live PIM policy of a
    Microsoft Entra directory role.

    .DESCRIPTION
    The orchestration handler for a single directoryRoleManagementPolicies entry from the structure
    document. It is called by the Invoke-OERStructure engine and emits one ConvertTo-OERStructureResult
    record, labelled with the entry's role, describing what was updated, left unchanged, skipped or
    failed.

    Updated-or-Unchanged only -- a directory role's PIM policy always exists; there is nothing to
    create and nothing to delete. This handler therefore never emits Created, Removed, or Extra
    records, and -Prune is a no-op. A directory role policy always lives at tenant scope, so an entry
    carries no scope field.

    Flow: the live policy is read with Get-OERDirectoryRoleManagementPolicy -Role, the only place the
    role name is resolved. The declared approvers are then resolved from names to object ids by
    Resolve-OERDeclaredApprover, and the declaration is diffed against the live policy by
    Resolve-OERRoleManagementPolicyChange -SendDeclaredApproverSideOnly. Any difference is written by
    Set-OERDirectoryRoleManagementPolicy -PolicyId with the id the read returned, so the role is never
    resolved a second time.

    Presence semantics: an OMITTED field in the document means "leave untouched", NOT "set to
    $false", and a field with an explicit JSON null counts as omitted. Only the fields the document
    actually declares are compared and, when they differ, sent. If the document declares none of the
    supported fields, the policy is always Unchanged.

    Supported document fields (each maps to the matching Set-OERDirectoryRoleManagementPolicy
    parameter; the diff is owned by Resolve-OERRoleManagementPolicyChange):
    - allowPermanentEligibility, eligibleDurationDays
    - allowPermanentActiveAssignment, activeDurationDays
    - activationMaxHours
    - requireMfaOnActivation, requireJustificationOnActivation, requireTicketOnActivation
    - requireApproval, approvers { users[], groups[] } -- users are UPNs or object ids and groups are
      group display names or object ids; both are resolved to object ids before the diff, so the diff
      only ever compares ids with ids. An approver that does not resolve reports Failed and changes
      nothing. Only the side the document declares is sent: declaring users alone leaves the live
      group approvers in place, and the reverse, and an empty array clears that side. A declared
      requireApproval false takes precedence and the approvers are not sent.
    - authenticationContextId (empty string disables it)
    - requireMfaOnActiveAssignment, requireJustificationOnActiveAssignment
    Notification rules and any other field are NOT applied; Test-OERStructureSchema warns about
    unknown keys in this section, a scope key included, so the drop is visible instead of silent.

    Every write is gated by $Caller.ShouldProcess. Under -WhatIf that returns $false and the
    handler emits Skipped, naming the changes, instead of calling
    Set-OERDirectoryRoleManagementPolicy. Reads always execute even under -WhatIf so the plan is
    available. Every call goes through Microsoft Graph; no Azure Resource Manager token is needed.

    -Prune and -TenantAlias are accepted for a uniform Sync-OERStructure* signature but are no-ops
    in this handler.

    .PARAMETER Item
    One element from the directoryRoleManagementPolicies[] array in the structure document, as a
    PSCustomObject produced by ConvertFrom-Json. Expected property: role (a directory role display
    name or role definition id). All other fields are optional -- see the supported document fields
    list above.

    .PARAMETER Caller
    The engine's $PSCmdlet reference, used to gate writes with ShouldProcess and to route errors
    with WriteError. The engine passes its own $PSCmdlet here.

    .PARAMETER Prune
    Accepted for handler signature uniformity. Has no effect -- policies cannot be deleted.

    .PARAMETER TenantAlias
    Optional Tenant Profile alias forwarded for context. Accepted for handler signature uniformity
    but not used by this handler.

    .EXAMPLE
    Sync-OERStructureDirectoryRoleManagementPolicy -Item $DocItem -Caller $PSCmdlet
    Reconciles one directory role management policy entry from the document against the live policy.
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
        [string]$TenantAlias
    )

    process {
        $Label   = [string]$Item.role
        $Section = 'directoryRoleManagementPolicies'

        # -- Read the current policy --------------------------------------------------------
        # -ErrorAction Stop: the Get cmdlet reports a missing role or policy as a non-terminating
        # error, which must land in this catch rather than leave $Cur empty.
        $Cur = $null
        try {
            $Cur = Get-OERDirectoryRoleManagementPolicy -Role $Item.role -ErrorAction Stop
        } catch {
            Remove-OERErrorRecord -Record $PSItem
            $Caller.WriteError($PSItem)
            ConvertTo-OERStructureResult -Section $Section -Item $Label -Action 'Failed' `
                -Detail "could not read directory role management policy for '$($Item.role)': $($PSItem.Exception.Message)" `
                -ErrorRecord $PSItem
            return
        }

        # -- Resolve declared approver names to object ids BEFORE the diff ------------------
        # The live approvers carry object ids, so a declared UPN or group name must become an id
        # first; otherwise the diff would compare a name with an id and report a change every run.
        $Declared = $Item
        try {
            $Declared = Resolve-OERDeclaredApprover -Declared $Item
        } catch {
            Remove-OERErrorRecord -Record $PSItem
            $ErrRec = [System.Management.Automation.ErrorRecord]::new(
                [System.Exception]::new("Could not resolve an approver declared for '$($Item.role)': $($PSItem.Exception.Message)", $PSItem.Exception),
                'ApproverNotFound',
                [System.Management.Automation.ErrorCategory]::ObjectNotFound,
                $Label)
            $Caller.WriteError($ErrRec)
            ConvertTo-OERStructureResult -Section $Section -Item $Label -Action 'Failed' `
                -Detail "could not resolve an approver: $($PSItem.Exception.Message); the policy was not changed" `
                -ErrorRecord $ErrRec
            return
        }

        # -- Diff the declared fields against the live policy --------------------------------
        # -SendDeclaredApproverSideOnly: Set-OERDirectoryRoleManagementPolicy replaces only the
        # approver side it is bound for, so only a declared side may be sent.
        $Change = Resolve-OERRoleManagementPolicyChange -Declared $Declared -Current $Cur -SendDeclaredApproverSideOnly
        $SetSplat = $Change.SetParams

        # -- Unchanged if nothing differs ---------------------------------------------------
        if (-not $Change.Changed) {
            ConvertTo-OERStructureResult -Section $Section -Item $Label -Action 'Unchanged' `
                -Detail "policy already matches for '$($Item.role)'"
            return
        }

        # -- Gate the update on ShouldProcess -----------------------------------------------
        if (-not $Caller.ShouldProcess($Item.role, 'Update directory role management policy')) {
            ConvertTo-OERStructureResult -Section $Section -Item $Label -Action 'Skipped' `
                -Detail "would update directory role management policy for '$($Item.role)' ($($Change.Changes -join ', '))"
            return
        }

        try {
            $null = Set-OERDirectoryRoleManagementPolicy -PolicyId $Cur.PolicyId @SetSplat -Confirm:$false -ErrorAction Stop
            ConvertTo-OERStructureResult -Section $Section -Item $Label -Action 'Updated' `
                -Detail "updated directory role management policy for '$($Item.role)' ($($Change.Changes -join ', '))"
        } catch {
            Remove-OERErrorRecord -Record $PSItem
            $Caller.WriteError($PSItem)
            ConvertTo-OERStructureResult -Section $Section -Item $Label -Action 'Failed' `
                -Detail "failed to update directory role management policy for '$($Item.role)': $($PSItem.Exception.Message)" `
                -ErrorRecord $PSItem
        }
    }
}
