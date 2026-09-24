function Resolve-OERRoleManagementPolicyChange {
    <#
    .SYNOPSIS
    Computes the Azure PIM role management policy parameter changes needed to make the live policy
    match a declared apply-document entry.

    .DESCRIPTION
    Pure, tenant-free diff used by the Invoke-OERStructure role management policy handler. Compares a
    declared roleManagementPolicies[] entry against the current Get-OERRoleManagementPolicy object and
    returns a tagged result with a Changed flag, a SetParams hashtable ready to splat into
    Set-OERRoleManagementPolicy (only the fields that differ, never the scope or role targeting
    parameters), and a human-readable Changes list. Presence semantics apply: a field the document
    does not declare is never compared and never sent, so an omitted field means "leave the live
    setting untouched", not "set it to false". A field present with an explicit JSON null counts as
    UNDECLARED for exactly the same reason -- it matches the offline validator Test-OERStructureSchema,
    and it is what stops "authenticationContextId": null from disabling a live authentication context
    or "requireMfaOnActivation": null from disabling MFA. An empty string is still a declared value:
    authenticationContextId "" remains the documented "disable the authentication context" request.
    A document that explicitly declares requireApproval = false suppresses the approver parameters
    entirely (Resolve-OERPolicyRulePatch forces isApprovalRequired = true whenever approvers are sent,
    so sending both would re-enable approval); the suppression is recorded in the Changes list.
    Declared approver values are object ids by the time this diff sees them -- the handler resolves a
    declared UPN or group display name to its object id first, through Resolve-OERDeclaredApprover --
    so approver lists are compared offline as case-insensitive sets of ids against the live approver
    ids; a name is never compared with an id. When either list differs both are sent, because Azure
    Resource Manager replaces the whole primaryApprovers array in one patch. The approvers.users and
    approvers.groups sub-fields
    are independently presence-gated: when the document declares only one side, the other side is
    seeded from the live policy's approver ids (rather than defaulted to empty) so the write does not
    silently wipe the half the document left alone. A null Current (the policy could not be read) is
    treated as everything-declared-is-changed. No Graph, ARM, or authentication occurs.

    .PARAMETER Declared
    One roleManagementPolicies[] entry from the structure document. Recognized fields:
    allowPermanentEligibility, eligibleDurationDays, allowPermanentActiveAssignment,
    activeDurationDays, activationMaxHours, requireMfaOnActivation,
    requireJustificationOnActivation, requireTicketOnActivation, requireApproval, approvers
    (an object whose users and groups arrays are each independently optional -- declaring only one
    preserves the other from the live policy, and the whole block is ignored when requireApproval is
    explicitly false), authenticationContextId (an empty string disables the context; an explicit null
    means "not declared"), requireMfaOnActiveAssignment and requireJustificationOnActiveAssignment.

    .PARAMETER Current
    The live policy as returned by Get-OERRoleManagementPolicy for the same role and scope, or null
    when the policy could not be read, in which case every declared field is considered changed.

    .EXAMPLE
    Resolve-OERRoleManagementPolicyChange -Declared $DocItem -Current (Get-OERRoleManagementPolicy -Role 'Owner' -Subscription 'Prod')
    Returns the SetParams needed to reconcile the Owner policy, or Changed = $false when it matches.
    #>
    [OutputType([PSCustomObject])]
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][PSCustomObject]$Declared,
        [PSCustomObject]$Current
    )

    $SetParams = @{}
    $Changes   = [System.Collections.Generic.List[string]]::new()

    # A property that is present but NULL counts as UNDECLARED, exactly as the offline validator's
    # Test-HasProp does. The two layers have to agree on what "declared" means: schema.json permits an
    # explicit null on authenticationContextId, and Invoke-OERStructure validates with
    # Test-OERStructureSchema (not Test-Json), so a null on any field reaches this diff. Without the
    # null guard, "authenticationContextId": null would cast to '' and DISABLE a live authentication
    # context, and "requireMfaOnActivation": null would cast to $false and DISABLE MFA on activation.
    # An empty string is still a declared value -- it stays the documented "disable" request.
    # Delegates to Test-OERDeclaredProperty, the module's one owner of this rule.
    function Test-DeclHas {
        param([object]$Node, [string]$Name)
        Test-OERDeclaredProperty -Node $Node -Name $Name
    }

    # Hoisted alongside Test-DeclHas so every nested helper the function uses lives at the same
    # scope, regardless of which branch below ends up calling it.
    # Each current approver can satisfy at most one declared value -- a plain "some current approver
    # matches" lookup (with no consumption) would let one live approver silently satisfy two declared
    # entries (e.g. a duplicate declared id) and still report equal counts as a false match. Matching
    # one declared value at a time and removing the matched candidate from the pool forces a true
    # one-to-one pairing: equal iff every declared value consumes a distinct current approver and every
    # current approver is consumed. A declared value is always an object id by the time it reaches
    # here (the handler resolves a UPN or group display name through Resolve-OERDeclaredApprover
    # first), so this only ever compares ids with ids -- a name is never compared against a live
    # approver's id.
    function Test-ApproverSetEqual {
        param([string[]]$DeclaredValue, [object[]]$CurrentApprover)
        $Declared  = @($DeclaredValue)
        $Available = [System.Collections.Generic.List[object]]::new()
        foreach ($Item in @($CurrentApprover)) { $Available.Add($Item) }
        if ($Declared.Count -ne $Available.Count) { return $false }
        foreach ($Value in $Declared) {
            $HitIndex = -1
            for ($Index = 0; $Index -lt $Available.Count; $Index++) {
                $Candidate = $Available[$Index]
                if ([string]$Candidate.Id -ieq $Value) {
                    $HitIndex = $Index
                    break
                }
            }
            if ($HitIndex -lt 0) { return $false }
            $Available.RemoveAt($HitIndex)
        }
        return $true
    }

    # Scalar toggles and integers share one shape: declared field -> Set parameter -> current property.
    $ScalarMap = @(
        @{ Decl = 'allowPermanentEligibility';              Param = 'AllowPermanentEligibility';              Cur = 'AllowPermanentEligibility';              Kind = 'Bool' }
        @{ Decl = 'allowPermanentActiveAssignment';         Param = 'AllowPermanentActiveAssignment';         Cur = 'AllowPermanentActiveAssignment';         Kind = 'Bool' }
        @{ Decl = 'requireMfaOnActivation';                 Param = 'RequireMfaOnActivation';                 Cur = 'RequireMfaOnActivation';                 Kind = 'Bool' }
        @{ Decl = 'requireJustificationOnActivation';       Param = 'RequireJustificationOnActivation';       Cur = 'RequireJustificationOnActivation';       Kind = 'Bool' }
        @{ Decl = 'requireTicketOnActivation';              Param = 'RequireTicketOnActivation';              Cur = 'RequireTicketOnActivation';              Kind = 'Bool' }
        @{ Decl = 'requireApproval';                        Param = 'RequireApproval';                        Cur = 'RequireApproval';                        Kind = 'Bool' }
        @{ Decl = 'requireMfaOnActiveAssignment';           Param = 'RequireMfaOnActiveAssignment';           Cur = 'RequireMfaOnActiveAssignment';           Kind = 'Bool' }
        @{ Decl = 'requireJustificationOnActiveAssignment'; Param = 'RequireJustificationOnActiveAssignment'; Cur = 'RequireJustificationOnActiveAssignment'; Kind = 'Bool' }
        @{ Decl = 'activationMaxHours';                     Param = 'ActivationMaxHours';                     Cur = 'ActivationMaxHours';                     Kind = 'Int' }
        @{ Decl = 'eligibleDurationDays';                   Param = 'EligibleDuration';                       Cur = 'EligibleDurationDays';                   Kind = 'Int' }
        @{ Decl = 'activeDurationDays';                     Param = 'ActiveDuration';                         Cur = 'ActiveDurationDays';                     Kind = 'Int' }
    )
    foreach ($Map in $ScalarMap) {
        if (-not (Test-DeclHas $Declared $Map.Decl)) { continue }
        if ($Map.Kind -eq 'Bool') {
            $D = [bool]$Declared.($Map.Decl)
            $C = if ($null -ne $Current -and $null -ne $Current.($Map.Cur)) { [bool]$Current.($Map.Cur) } else { $null }
        } else {
            $D = [int]$Declared.($Map.Decl)
            $C = if ($null -ne $Current -and $null -ne $Current.($Map.Cur)) { [int]$Current.($Map.Cur) } else { $null }
        }
        # An unreadable policy (null Current) forces every declared field to be written, matching the
        # sibling Resolve-OERGroupPimPolicyChange. A live policy that WAS read but whose single
        # property could not be derived leaves $C null -- and PowerShell's -ne $null is true for every
        # non-null left operand (including $false and 0) -- so that field is written too. That is the
        # right call: it cannot be proven equal, and for the durations the live value genuinely is not
        # the declared one (ConvertTo-OERRoleManagementPolicy leaves ActivationMaxHours null whenever
        # the live maximumDuration is not PT<n>H, for example PT30M). Dropping it instead would be
        # silent data loss.
        if ($null -eq $Current -or $D -ne $C) {
            $SetParams[$Map.Param] = $D
            $Changes.Add("$($Map.Decl)=$D")
        }
    }

    # authenticationContextId: an empty string is the explicit "disable" value, so compare on the
    # string form where null and empty are the same "no context" state.
    if (Test-DeclHas $Declared 'authenticationContextId') {
        $D = [string]$Declared.authenticationContextId
        $C = if ($null -ne $Current) { [string]$Current.AuthenticationContextId } else { $null }
        if ($null -eq $Current -or $D -ne $C) {
            $SetParams.AuthenticationContextId = $D
            $Changes.Add("authenticationContextId=$D")
        }
    }

    # Approvers: users and groups are independently presence-gated -- a document that declares only
    # one side means "change this side, leave the other alone". Because Set-OERRoleManagementPolicy
    # replaces the WHOLE primaryApprovers array whenever either -ApproverUser or -ApproverGroup is
    # bound, an undeclared side is seeded from the live approvers' ids (not defaulted to empty) so it
    # survives the write unchanged. Only the declared side(s) participate in the changed/unchanged
    # decision; the seeded side never forces an update on its own.
    #
    # A document that EXPLICITLY declares requireApproval = false cannot also mean "use these
    # approvers": Resolve-OERPolicyRulePatch sets isApprovalRequired = $true UNCONDITIONALLY whenever
    # PrimaryApprovers are supplied, so sending both would silently RE-ENABLE approval on a policy the
    # document says must have it off. The explicit false wins and the approver parameters are never
    # sent. Get-OERInventory can produce exactly that document: ConvertTo-OERRoleManagementPolicy
    # reads primaryApprovers regardless of isApprovalRequired, so an approval-off policy with leftover
    # stage approvers exports both keys. An OMITTED requireApproval keeps the old behaviour -- the
    # approvers are applied and ARM turns approval on, which is what declaring approvers means.
    $HasDeclUser  = Test-DeclHas $Declared.approvers 'users'
    $HasDeclGroup = Test-DeclHas $Declared.approvers 'groups'
    $ApprovalExplicitlyOff = (Test-DeclHas $Declared 'requireApproval') -and (-not [bool]$Declared.requireApproval)
    if (($HasDeclUser -or $HasDeclGroup) -and $ApprovalExplicitlyOff) {
        $Changes.Add('approvers ignored: requireApproval=False takes precedence (approvers only apply when approval is required)')
    }
    elseif ($HasDeclUser -or $HasDeclGroup) {
        $CurAll   = @(@($Current.Approvers) | Where-Object { $_ })
        $CurUser  = @($CurAll | Where-Object { [string]$_.UserType -eq 'User' })
        $CurGroup = @($CurAll | Where-Object { [string]$_.UserType -eq 'Group' })

        $DeclUser = if ($HasDeclUser) {
            @(@($Declared.approvers.users) | ForEach-Object { [string]$_ } | Where-Object { $_ })
        } elseif ($null -ne $Current) {
            @($CurUser | ForEach-Object { [string]$_.Id } | Where-Object { $_ })
        } else {
            @()
        }
        $DeclGroup = if ($HasDeclGroup) {
            @(@($Declared.approvers.groups) | ForEach-Object { [string]$_ } | Where-Object { $_ })
        } elseif ($null -ne $Current) {
            @($CurGroup | ForEach-Object { [string]$_.Id } | Where-Object { $_ })
        } else {
            @()
        }

        $UserChanged  = $HasDeclUser  -and (($null -eq $Current) -or -not (Test-ApproverSetEqual -DeclaredValue $DeclUser  -CurrentApprover $CurUser))
        $GroupChanged = $HasDeclGroup -and (($null -eq $Current) -or -not (Test-ApproverSetEqual -DeclaredValue $DeclGroup -CurrentApprover $CurGroup))
        if ($UserChanged -or $GroupChanged) {
            $SetParams.ApproverUser  = $DeclUser
            $SetParams.ApproverGroup = $DeclGroup
            $Changes.Add("approvers(users=[$($DeclUser -join ',')],groups=[$($DeclGroup -join ',')])")
        }
    }

    $Out = [PSCustomObject]@{
        Changed   = ($SetParams.Keys.Count -gt 0)
        SetParams = $SetParams
        Changes   = $Changes.ToArray()
    }
    $Out.PSObject.TypeNames.Insert(0, 'Omnicit.EntraRBAC.RoleManagementPolicyChange')
    $Out
}
