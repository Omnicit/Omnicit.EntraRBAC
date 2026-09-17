function Add-OERGroupMember {
    <#
    .SYNOPSIS
    Adds one or more principals as direct members or owners of an Entra ID group.

    .DESCRIPTION
    Adds each principal to the group identified by -Group (name or GUID), as a direct member
    (default) or as an owner when -AccessType owner is set. Each principal is added through the
    group's members/$ref or owners/$ref navigation endpoint. A principal that is already present
    surfaces a Graph error that is reported per-principal without stopping the remaining additions.
    A group that cannot be resolved produces a non-terminating GroupNotFound error. Supports
    -WhatIf and -Confirm.

    Principals may be given as raw object ids with -PrincipalId or by name with -User (user
    principal name), -GroupPrincipal (group display name) and -ServicePrincipal (service principal
    display name); all four accept multiple values and are unioned into a single run. A non-GUID
    value passed to -PrincipalId produces a non-terminating InvalidPrincipalId error naming the
    friendly alternatives instead of an opaque Graph failure. Note that -Group is the TARGET group
    and -GroupPrincipal is a group being added as a member.

    The -Group parameter accepts group display names, object ids (GUIDs), and the pipeline aliases
    Id, GroupId, and DisplayName so that output from Get-OERGroup and Get-OERGroupMember pipes
    directly. -PrincipalId and -AccessType bind from piped Get-OERGroupMember output (via the
    MemberType alias) so the full round-trip works without extra parameters.

    .PARAMETER Group
    The display name or object id (GUID) of the target group. Accepts pipeline input by property
    name. Aliases: Id, GroupId, DisplayName. GroupId takes precedence during pipeline binding so
    that a piped Get-OERGroupMember object binds the group's GroupId instead of the principal's Id.

    .PARAMETER PrincipalId
    One or more object ids of the users, groups, or service principals to add to the group.
    Accepts pipeline input by property name. Each principal is processed individually so a failure
    on one does not block the others. Must be canonical GUIDs; to name a principal instead, use
    -User, -GroupPrincipal or -ServicePrincipal.

    .PARAMETER User
    One or more users to add, each given as a user principal name or object id (GUID) and resolved
    via Resolve-OERPrincipal. Combined with the other principal parameters rather than exclusive.

    .PARAMETER GroupPrincipal
    One or more groups to add as members or owners, each given as a group display name or object id
    (GUID). This is the principal being added, not the target group, which is -Group. Group display
    names are not guaranteed unique in Entra ID; if more than one group shares the given name, the
    command fails with an error naming the candidate object ids, so re-run with the object id.

    .PARAMETER ServicePrincipal
    One or more service principals to add, each given as a service principal display name or object
    id (GUID). A GUID is treated as the service principal object id, never as an application id.

    .PARAMETER AccessType
    Whether to add the principals as group members (default) or owners. Accepts member or owner.
    Alias: MemberType -- so a piped Get-OERGroupMember object whose MemberType is Owner routes
    to the owners/$ref collection automatically. Members are added via members/$ref; owners via
    owners/$ref.

    .PARAMETER TenantId
    Optional tenant id or domain to authenticate against, forwarded to Initialize-OERAuth.
    When omitted the currently active auth context is used.

    .EXAMPLE
    Add-OERGroupMember -Group 'role_sec_identity_administrator' -PrincipalId $UserId
    Adds the user as a direct member of the named group.

    .EXAMPLE
    Add-OERGroupMember -Group $GroupId -PrincipalId $UserId -AccessType owner
    Adds the user as an owner of the group.

    .EXAMPLE
    Get-OERGroupMember -Group 'role_sec_team' -Owners | Add-OERGroupMember -Group 'role_sec_leads'
    Copies the owners of one group as owners of another (the piped MemberType binds -AccessType and routes to the owners collection).

    .EXAMPLE
    Add-OERGroupMember -Group 'role_sec_leads' -User 'anna.berg@contoso.com' -GroupPrincipal 'Sales Team'
    Adds a user (by UPN) and a group (by display name) as members in a single call.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([void])]
    param(
        [Parameter(Mandatory, ValueFromPipelineByPropertyName)]
        [Alias('GroupId', 'Id', 'DisplayName')]
        [string]$Group,

        [Parameter(ValueFromPipelineByPropertyName)]
        [string[]]$PrincipalId,

        [Parameter(ValueFromPipelineByPropertyName)]
        [Alias('MemberType')]
        [ValidateSet('member', 'owner')]
        [string]$AccessType = 'member',

        [string]$TenantId,

        # Declared after the pre-existing parameters so their positional binding is unchanged.
        [string[]]$User,

        [string[]]$GroupPrincipal,

        [string[]]$ServicePrincipal
    )
    begin {
        $AuthParams = @{}
        if ($TenantId) { $AuthParams.TenantId = $TenantId }
        Initialize-OERAuth @AuthParams
        # Resolved once per invocation, immediately after Initialize-OERAuth populates the session
        # state it reads -- not per principal in the loop below, since Initialize-OERAuth itself
        # runs once per invocation and the session's cloud cannot change between pipeline items of
        # the same call.
        $GraphServiceRoot = Get-OERGraphServiceRoot
    }
    process {
        # Refuse an ambiguous display name loudly; any other throw falls through to the not-found branch.
        $ResolvedGroupId = $null
        try {
            $ResolvedGroupId = Resolve-OERGroupId -DisplayName $Group
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
        if (-not $ResolvedGroupId) {
            Write-CmdletError `
                -Message ([System.Exception]::new('No group found for the supplied group name or id.')) `
                -ErrorId 'GroupNotFound' `
                -Category ObjectNotFound `
                -TargetObject $Group `
                -Cmdlet $PSCmdlet
            return
        }
        Write-Verbose "[Add-OERGroupMember] Resolved group to '$ResolvedGroupId'."

        $Segment = if ($AccessType -eq 'owner') { 'owners' } else { 'members' }
        $Hint = '-User, -GroupPrincipal or -ServicePrincipal'

        $PrincipalSpecs = @()
        foreach ($Value in $PrincipalId) { $PrincipalSpecs += @{ PrincipalId = $Value } }
        foreach ($Value in $User) { $PrincipalSpecs += @{ User = $Value } }
        foreach ($Value in $GroupPrincipal) { $PrincipalSpecs += @{ Group = $Value } }
        foreach ($Value in $ServicePrincipal) { $PrincipalSpecs += @{ ServicePrincipal = $Value } }

        if ($PrincipalSpecs.Count -eq 0) {
            $NoPrincipal = Resolve-OERPrincipalOrId -FriendlyParameterHint $Hint
            Write-CmdletError -Message ([System.Exception]::new($NoPrincipal.Message)) `
                -ErrorId $NoPrincipal.ErrorId -Category $NoPrincipal.Category `
                -TargetObject $Group -Cmdlet $PSCmdlet
            return
        }

        foreach ($Spec in $PrincipalSpecs) {
            $Resolved = Resolve-OERPrincipalOrId @Spec -FriendlyParameterHint $Hint
            if ($Resolved.ErrorId) {
                Write-CmdletError -Message ([System.Exception]::new($Resolved.Message)) `
                    -ErrorId $Resolved.ErrorId -Category $Resolved.Category `
                    -TargetObject $Resolved.TargetObject -Cmdlet $PSCmdlet
                continue
            }
            $Principal = $Resolved.PrincipalId
            Write-Verbose "[Add-OERGroupMember] Resolved principal to '$Principal'."
            $Body = @{ '@odata.id' = "$GraphServiceRoot/directoryObjects/$Principal" }
            if ($PSCmdlet.ShouldProcess($ResolvedGroupId, "Add $AccessType '$Principal'")) {
                try {
                    Invoke-OERGraphRequest -Method POST -Uri ("v1.0/groups/{0}/{1}/`$ref" -f $ResolvedGroupId, $Segment) -Body $Body | Out-Null
                } catch {
                    Remove-OERErrorRecord -Record $PSItem
                    $PSCmdlet.WriteError($PSItem)
                    continue
                }
            }
        }
    }
}
