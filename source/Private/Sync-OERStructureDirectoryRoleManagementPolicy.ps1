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
      nothing: the row carries ApproverNotFound for an approver that matches nothing,
      AmbiguousApproverName (naming the candidate ids) for a group display name several groups share,
      and the lookup's own error for a lookup that failed. Only the side the document declares is
      sent: declaring users alone leaves the live group approvers in place, and the reverse, and an
      empty array clears that side. A declared requireApproval false takes precedence and the
      approvers are not sent.
    - authenticationContextId (empty string disables it)
    - requireMfaOnActiveAssignment, requireJustificationOnActiveAssignment
    Notification rules and any other field are NOT applied; Test-OERStructureSchema warns about
    unknown keys in this section, a scope key included, so the drop is visible instead of silent.

    Every write is gated by $Caller.ShouldProcess. Under -WhatIf that returns $false and the
    handler emits Skipped, naming the changes, instead of calling
    Set-OERDirectoryRoleManagementPolicy. Reads always execute even under -WhatIf so the plan is
    available. Every call goes through Microsoft Graph; no Azure Resource Manager token is needed.

    A change that reconciles the MFA / authentication context pair -- a declared non-empty
    authenticationContextId that clears MFA on activation, or a declared requireMfaOnActivation true
    that disables a live authentication context -- makes Set-OERDirectoryRoleManagementPolicy warn
    before its own gate. Under -WhatIf, where that cmdlet is never called, the handler takes the same
    decision (Resolve-OERPimActivationConflict, from the changed parameters and the live rules the
    read returned) and writes the cmdlet's warning, "Policy '<policy id>': <reason>", before its gate.
    A real run leaves the warning to the cmdlet, so it is written once either way.

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
        # Three outcomes, three records, one Failed row each and no write: an ambiguous name is
        # AmbiguousApproverName (the resolver's text names the candidate ids), only an approver that
        # matches nothing (ApproverUnresolved) is ApproverNotFound, and anything else -- a 403, an
        # exhausted 429, a 5xx -- is not evidence that the approver is missing, so it is published as
        # itself.
        $Declared = $Item
        try {
            $Declared = Resolve-OERDeclaredApprover -Declared $Item
        } catch {
            Remove-OERErrorRecord -Record $PSItem
            $ErrRec = $PSItem
            if (Test-OERAmbiguousNameError -Record $PSItem) {
                $ErrRec = [System.Management.Automation.ErrorRecord]::new(
                    [System.Exception]::new("Could not resolve an approver declared for '$($Item.role)': $($PSItem.Exception.Message)", $PSItem.Exception),
                    'AmbiguousApproverName',
                    [System.Management.Automation.ErrorCategory]::InvalidArgument,
                    $PSItem.TargetObject)
            } elseif (([string]$PSItem.FullyQualifiedErrorId).StartsWith('ApproverUnresolved', [System.StringComparison]::Ordinal)) {
                $ErrRec = [System.Management.Automation.ErrorRecord]::new(
                    [System.Exception]::new("Could not resolve an approver declared for '$($Item.role)': $($PSItem.Exception.Message)", $PSItem.Exception),
                    'ApproverNotFound',
                    [System.Management.Automation.ErrorCategory]::ObjectNotFound,
                    $Label)
            }
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

        # -- The warning the write would give, for the plan --------------------------------
        # Set-OERDirectoryRoleManagementPolicy resolves the MFA / authentication context pair in
        # Resolve-OERPolicyRulePatch (-ResolveUnrequestedConflict $false) and, before its own gate,
        # warns when that clears MFA on activation or disables the authentication context. Under
        # -WhatIf the engine never calls it, so the plan would not show the warning a real run gives:
        # the decision is taken here, through the same owner, from the inputs the patch builder derives
        # from this splat and the live rules, and the cmdlet's own warning written before the gate.
        # Only under -WhatIf -- a real run calls the cmdlet, which writes it, and a second copy here
        # would warn twice. The live rules are the ones the read above returned (EffectiveRules, the
        # policy's rules, which the cmdlet reads again by this same policy id).
        if ($WhatIfPreference) {
            $LiveRules = @(@($Cur.EffectiveRules) | Where-Object { $null -ne $_ })
            $LiveEnablement = $LiveRules | Where-Object { [string]$_.id -eq 'Enablement_EndUser_Assignment' } | Select-Object -First 1
            $LiveContext = $LiveRules | Where-Object { [string]$_.id -eq 'AuthenticationContext_EndUser_Assignment' } | Select-Object -First 1

            # The activation rules once the splat is applied: the live list, with MFA set or cleared by
            # a splatted RequireMfaOnActivation (the builder's toggle).
            $EffectiveRules = [System.Collections.Generic.List[string]]::new()
            foreach ($Entry in @($LiveEnablement.enabledRules)) { if ($Entry) { $EffectiveRules.Add([string]$Entry) } }
            $RequestsMfa = $SetSplat.ContainsKey('RequireMfaOnActivation') -and [bool]$SetSplat.RequireMfaOnActivation
            if ($SetSplat.ContainsKey('RequireMfaOnActivation')) {
                if ($RequestsMfa) {
                    if (-not $EffectiveRules.Contains('MultiFactorAuthentication')) { $EffectiveRules.Add('MultiFactorAuthentication') }
                } else {
                    [void]$EffectiveRules.Remove('MultiFactorAuthentication')
                }
            }

            # The context once the splat is applied: the splatted one (non-empty enables it with that
            # id, empty disables it), otherwise the live rule's.
            $RequestsContext = $false
            if ($SetSplat.ContainsKey('AuthenticationContextId')) {
                $EffectiveContextId = [string]$SetSplat.AuthenticationContextId
                $EffectiveContextEnabled = -not [string]::IsNullOrEmpty($EffectiveContextId)
                $RequestsContext = $EffectiveContextEnabled
            } else {
                $EffectiveContextId = [string]$LiveContext.claimValue
                $EffectiveContextEnabled = [bool]$LiveContext.isEnabled
            }

            $ConflictParams = @{
                EffectiveAuthContextId          = $EffectiveContextId
                EffectiveActivationEnabledRules = $EffectiveRules.ToArray()
            }
            if ($EffectiveContextEnabled) { $ConflictParams.EffectiveAuthContextEnabled = $true }
            if ($RequestsContext) { $ConflictParams.CallerRequestsAuthContext = $true }
            if ($RequestsMfa) { $ConflictParams.CallerRequestsMfa = $true }
            $Resolution = Resolve-OERPimActivationConflict @ConflictParams
            if ($Resolution.Action -in @('ClearMfa', 'DisableAuthContext')) {
                Write-Warning "Policy '$($Cur.PolicyId)': $($Resolution.Reason)"
            }
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
