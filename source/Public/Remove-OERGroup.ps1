function Remove-OERGroup {
    <#
    .SYNOPSIS
    Deletes an Entra ID group. High-impact: prompts for confirmation by default.

    .DESCRIPTION
    Permanently deletes an Entra ID group identified by -Group through Microsoft Graph.
    Deleting a group is a high-impact, hard-to-reverse operation, so the command declares
    ConfirmImpact = High (it prompts unless -Confirm:$false is passed) and emits an explicit warning
    before the delete. The warning is written BEFORE the confirmation prompt, so it also appears under
    -WhatIf and under -Confirm:$false. A group that cannot be resolved produces a non-terminating
    GroupNotFound error. Supports -WhatIf and -Confirm.

    .PARAMETER Group
    The group to act on, given as either its object id (GUID) or its display name -- the same
    name-or-GUID target every membership, eligibility and PIM cmdlet in the module accepts. Binds
    from the pipeline by property name, and still accepts the historical -Id, -GroupId and
    -DisplayName parameter names as aliases. GroupId takes precedence during pipeline binding so a
    piped Get-OERGroupMember object binds the group's GroupId instead of a principal's Id.

    .PARAMETER TenantId
    Optional tenant id or domain to authenticate against, forwarded to Initialize-OERAuth.

    .EXAMPLE
    Remove-OERGroup -Group 'role_sec_obsolete' -Confirm:$false
    Deletes the named group without an interactive prompt (for automation).

    .EXAMPLE
    Remove-OERGroup -DisplayName 'role_sec_obsolete' -Confirm:$false
    Deletes the group, using the historical -DisplayName alias for -Group.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    [OutputType([void])]
    param(
        [Parameter(Mandatory, ValueFromPipelineByPropertyName)]
        # GroupId precedes Id so a piped GroupMember object binds the group's GroupId, not the
        # principal's Id, during ValueFromPipelineByPropertyName alias resolution.
        [Alias('GroupId', 'Id', 'DisplayName')]
        [string]$Group,

        [string]$TenantId
    )
    begin {
        $AuthParams = @{}
        if ($TenantId) { $AuthParams.TenantId = $TenantId }
        Initialize-OERAuth @AuthParams
    }
    process {
        # Refuse an ambiguous display name loudly; any other throw falls through to the not-found branch.
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
        }
        if (-not $GroupId) {
            Write-CmdletError `
                -Message ([System.Exception]::new("No group found to delete for '$Group'.")) `
                -ErrorId 'GroupNotFound' `
                -Category ObjectNotFound `
                -TargetObject $Group `
                -Cmdlet $PSCmdlet
            return
        }

        # MEASURED LIVE: this warning sits AHEAD of ShouldProcess on purpose. Emitted after it, it
        # printed only once the operator had already answered the ConfirmImpact = High prompt, and never
        # at all under -WhatIf -- a warning the operator sees only after committing to the delete is not
        # a guard. Do not move it back.
        Write-Warning "Deleting Entra ID group '$GroupId'. This is a high-impact, hard-to-reverse operation."
        if ($PSCmdlet.ShouldProcess($GroupId, 'Permanently delete Entra ID group')) {
            try {
                Invoke-OERGraphRequest -Method DELETE -Uri ("v1.0/groups/{0}" -f $GroupId) | Out-Null
            } catch {
                Remove-OERErrorRecord -Record $PSItem
                $PSCmdlet.WriteError($PSItem)
                return
            }
        }
    }
}
