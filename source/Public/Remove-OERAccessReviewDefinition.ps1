function Remove-OERAccessReviewDefinition {
    <#
    .SYNOPSIS
    Deletes an access review schedule definition.

    .DESCRIPTION
    Deletes an access review schedule definition through Microsoft Graph. Accepts the definition by -Id
    or -DisplayName (resolved via Resolve-OERAccessReviewDefinitionId). High-impact: emits an explicit
    warning and defaults to ConfirmImpact High. Deleting a definition with active instances will stop
    those instances; remove or stop all instances first if needed. Supports -WhatIf and -Confirm.

    Before the delete, the definition is read once so a definition whose scope targets an access
    package's assignments can be called out. That scope cannot tell an assignment policy's own
    Lifecycle access review apart from an ordinary review created over the same access package, so the
    warning is conditional: if the definition is the policy's Lifecycle access review, deleting it
    leaves that policy un-updatable, since the policy carries reviewSettings forward on every update
    and Graph refuses the write while it references a definition that no longer exists. That is an
    additional Warning only -- the delete still proceeds, and if the read fails no warning is invented
    and nothing is blocked.

    Both warnings, and the read that feeds the second one, are emitted BEFORE the confirmation prompt,
    so they also appear under -WhatIf and under -Confirm:$false. When the scope matches, the fact is
    folded into the ShouldProcess action text as well, so the "What if:" line and the Confirm prompt
    itself name it.

    .PARAMETER Id
    The access review definition id (GUID) to delete.

    .PARAMETER DisplayName
    The access review definition display name to resolve and delete.

    .PARAMETER TenantId
    Optional tenant id or domain to authenticate against, forwarded to Initialize-OERAuth.

    .EXAMPLE
    Remove-OERAccessReviewDefinition -DisplayName 'Q3 AP Review'
    Deletes the access review definition after confirmation.

    .EXAMPLE
    Remove-OERAccessReviewDefinition -Id '00000000-0000-0000-0000-000000000001' -Confirm:$false
    Deletes the access review definition by id without an interactive prompt (for automation).
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High', DefaultParameterSetName = 'ById')]
    [OutputType([void])]
    param(
        [Parameter(ParameterSetName = 'ById', Mandatory, ValueFromPipelineByPropertyName)]
        [Alias('AccessReviewDefinitionId')]
        [string]$Id,

        [Parameter(ParameterSetName = 'ByName', Mandatory)]
        [string]$DisplayName,

        [string]$TenantId
    )
    begin {
        $AuthParams = @{}
        if ($TenantId) { $AuthParams.TenantId = $TenantId }
        Initialize-OERAuth @AuthParams
    }
    process {
        $DefinitionId = try {
            if ($PSCmdlet.ParameterSetName -eq 'ByName') { Resolve-OERAccessReviewDefinitionId -DisplayName $DisplayName }
            else { $Id }
        }
        catch { Remove-OERErrorRecord -Record $PSItem; $null }
        if (-not $DefinitionId) {
            Write-CmdletError `
                -Message ([System.Exception]::new('Access review definition not found.')) `
                -ErrorId 'AccessReviewDefinitionNotFound' -Category ObjectNotFound `
                -TargetObject $(if ($Id) { $Id } else { $DisplayName }) -Cmdlet $PSCmdlet
            return
        }

        # MEASURED LIVE: both warnings below, and the diagnostic read that feeds the second one, sit
        # AHEAD of ShouldProcess on purpose. Emitted after it, they printed only once the operator had
        # already answered the ConfirmImpact = High prompt, and never at all under -WhatIf -- a guard
        # the operator sees only after committing to the delete is not a guard. The live run destroyed
        # an access package's own Lifecycle access review with the scope warning sitting unread below
        # the prompt. Do not move them back.
        Write-Warning "Deleting access review definition '$DefinitionId'. This is irreversible."

        # MEASURED LIVE: deleting an access package's OWN Lifecycle access review leaves the owning
        # assignment policy un-updatable. Set-OERAccessPackageAssignmentPolicy carries reviewSettings
        # forward on every PUT, Graph validates the referenced definition, and a deleted one answers
        # 404 "BusinessFlow not found for id <guid>" on every subsequent update.
        #
        # DIAGNOSTIC ONLY -- a Warning, never a refusal: refusing here would be a breaking change to
        # a delete that has always been allowed.
        #
        # Detected from the definition's own scope query, which for ANY access package review targets
        # the entitlement management assignments collection (see New-OERAccessReviewScopeQuery, the
        # single owner of that shape). NOT from the display name: a display name is operator-chosen
        # text and is not a contract, so it would both miss renamed reviews and fire on ordinary ones.
        #
        # ALSO MEASURED LIVE: that scope match is a SUPERSET, not an identification. Five ORDINARY
        # ad-hoc reviews created over an access package during the live run read back with exactly
        # the same shape a Lifecycle review does:
        #   /v1.0/identityGovernance/entitlementManagement/assignments?$filter=(accessPackage/id eq
        #   '<guid>' and assignmentPolicy/id eq '<guid>')
        # The real distinction is narrower and invisible here: a policy's Lifecycle access review is
        # the definition that the assignment policy's own reviewSettings references, and an ad-hoc
        # review over the same package is referenced by nothing. So the WARNING IS WORDED
        # CONDITIONALLY -- it states what was detected, then what follows only IF this is that
        # policy's Lifecycle review. Do not re-strengthen it into an unconditional claim.
        #
        # Deliberately NOT narrowed by reading the assignment policy and comparing ids: that
        # narrowing is unverified against the live reviewSettings shape, and on a destructive path a
        # false NEGATIVE (silently deleting a real Lifecycle review) costs far more than a slightly
        # broad but truthful warning.
        #
        # A failed read must not block the delete and must not invent a warning: the pre-existing
        # behaviour is that this cmdlet deletes what it was asked to delete, and this read is only
        # here to add context. Swallow to $null and carry on.
        #
        # DELIBERATE: this GET now runs under -WhatIf too, because it sits ahead of ShouldProcess. That
        # is the point -- the warning it feeds is what -WhatIf exists to show, and a -WhatIf run that
        # cannot say WHICH definition is at stake tells the operator nothing they did not already type.
        # It is a READ, so -WhatIf still changes nothing in the tenant. Do not "fix" it back behind
        # ShouldProcess.
        $ShouldProcessAction = 'Delete access review definition'
        $ScopeQuery = try {
            $Definition = Invoke-OERGraphRequest `
                -Uri ("v1.0/identityGovernance/accessReviews/definitions/{0}" -f $DefinitionId)
            [string]$Definition.scope.query
        }
        catch { Remove-OERErrorRecord -Record $PSItem; $null }
        if ($ScopeQuery -match 'entitlementManagement/assignments') {
            # Fold the scope fact into the action text as well, so the one line an operator cannot miss
            # -- the "What if:" line, or the Confirm prompt itself -- carries it. The Warning below is
            # the detail; this is the headline.
            $ShouldProcessAction = "Delete access review definition (targets an access package's assignments)"
            Write-Warning ("Access review definition '$DefinitionId' targets an access package's assignments " +
                '(its scope query targets entitlementManagement/assignments). That may be the assignment ' +
                "policy's own Lifecycle access review, or an ordinary review created over the same access " +
                'package -- the two are indistinguishable by scope alone. If it is the Lifecycle access ' +
                "review -- the one configured under 'Lifecycle > Require access reviews' on the assignment " +
                'policy -- then deleting it leaves that policy un-updatable: the policy carries ' +
                "'reviewSettings' forward on every update and Microsoft Graph refuses the write while it " +
                'references a definition that no longer exists. To tell the two apart, check that assignment ' +
                "policy's 'Lifecycle' tab: an ad-hoc review created by hand or by a document is not " +
                'referenced there. If this is the Lifecycle access review, re-create it on that policy, or ' +
                "turn off 'Require access reviews' on it, to make the policy updatable again.")
        }

        if ($PSCmdlet.ShouldProcess($DefinitionId, $ShouldProcessAction)) {
            try {
                $null = Invoke-OERGraphRequest -Method DELETE `
                    -Uri ("v1.0/identityGovernance/accessReviews/definitions/{0}" -f $DefinitionId)
            }
            catch {
                Remove-OERErrorRecord -Record $PSItem
                $PSCmdlet.WriteError($PSItem)
                return
            }
        }
    }
}
