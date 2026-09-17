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

    Scope DSL: the document scope field is parsed into a Get-OERRoleManagementPolicy / Set-OERRoleManagementPolicy
    splat by a nested Get-ScopeSplat helper.
    - 'mg:<name>' -> -ManagementGroup <name>
    - 'subscription:<name>' or 'sub:<name>' -> -Subscription <name>
    - Any other value -> -Scope <raw>

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
    - requireApproval, approvers { users[], groups[] }
    - authenticationContextId (empty string disables it)
    - requireMfaOnActiveAssignment, requireJustificationOnActiveAssignment
    Fields the document does not declare are never compared and never sent. Notification rules and
    any other roleManagementPolicies field are NOT applied; Test-OERStructureSchema warns about
    unknown keys in this section so the drop is visible instead of silent.

    Every write is gated by $Caller.ShouldProcess. Under -WhatIf that returns $false and the
    handler emits Skipped instead of calling Set-OERRoleManagementPolicy. Reads always execute even
    under -WhatIf so the diff/plan is available.

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
        [string]$TenantAlias
    )

    process {
        # Nested helper: parse the scope DSL string into a Get/Set-OERRoleManagementPolicy splat.
        # Takes a named param to avoid the PSReviewUnusedParameter-closure gotcha.
        function Get-ScopeSplat {
            param([string]$Scope)
            if ($Scope -match '^(?i)mg:(.+)$')                   { return @{ ManagementGroup = $Matches[1] } }
            if ($Scope -match '^(?i)(?:subscription|sub):(.+)$') { return @{ Subscription = $Matches[1] } }
            return @{ Scope = $Scope }
        }

        $Label   = "$($Item.role) @ $($Item.scope)"
        $Section = 'roleManagementPolicies'

        $ScopeSplat = Get-ScopeSplat -Scope $Item.scope

        # -- Read the current policy --------------------------------------------------------
        $Cur = $null
        try {
            $Cur = Get-OERRoleManagementPolicy -Role $Item.role @ScopeSplat
        } catch {
            Remove-OERErrorRecord -Record $PSItem
            $Caller.WriteError($PSItem)
            ConvertTo-OERStructureResult -Section $Section -Item $Label -Action 'Failed' `
                -Detail "could not read role management policy for '$($Item.role)' at '$($Item.scope)': $($PSItem.Exception.Message)" `
                -ErrorRecord $PSItem
            return
        }

        # -- Diff the declared fields against the live policy --------------------------------
        # Resolve-OERRoleManagementPolicyChange is the single owner of the presence semantics and the
        # field-to-parameter mapping; it returns only the parameters that actually differ.
        $Change = Resolve-OERRoleManagementPolicyChange -Declared $Item -Current $Cur
        $SetSplat = $Change.SetParams

        # -- Unchanged if nothing differs ---------------------------------------------------
        if (-not $Change.Changed) {
            ConvertTo-OERStructureResult -Section $Section -Item $Label -Action 'Unchanged' `
                -Detail "policy already matches for '$($Item.role)' at '$($Item.scope)'"
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
