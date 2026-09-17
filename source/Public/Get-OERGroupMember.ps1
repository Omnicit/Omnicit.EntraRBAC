function Get-OERGroupMember {
    <#
    .SYNOPSIS
    Lists the members (or owners) of an Entra ID group.

    .DESCRIPTION
    Reads a group's direct members through Microsoft Graph (groups/{id}/members) via
    Invoke-OERGraphRequest, or its owners with -Owners (groups/{id}/owners), and returns one tagged
    Omnicit.EntraRBAC.GroupMember object per principal. The group is given by -Group (display name or
    GUID, resolved via Resolve-OERGroupId) and binds from the pipeline by property name so
    Get-OERGroup pipes straight in. A group with no members/owners returns nothing (not an error).

    .PARAMETER Group
    The group whose members or owners are listed, given as a display name or object id (GUID) and
    resolved via Resolve-OERGroupId. Binds from the pipeline by property name and accepts the Id,
    GroupId, and DisplayName aliases. GroupId is checked before Id during pipeline binding, so a
    piped Get-OERGroupMember object (which carries both the principal's Id and the group's GroupId)
    binds the group correctly instead of mistaking the principal for the target group.

    .PARAMETER Owners
    List the group's owners instead of its members. Equivalent to -AccessType owner; supplying both
    is fine as long as they agree, and a disagreement between the two is a non-terminating
    AmbiguousAccessType error rather than a silent pick between them.

    .PARAMETER TenantId
    Optional tenant id or domain to authenticate against, forwarded to Initialize-OERAuth.

    .PARAMETER AccessType
    Whether to list the group's member (default) or owner collection. Equivalent to -Owners when set
    to owner. Does not bind from the pipeline: ConvertTo-OERGroupMember emits a MemberType property
    (Member/Owner) that this parameter also carries as an alias, and pipeline binding it would make
    Get-OERGroupMember -Group X -Owners | Get-OERGroupMember silently switch to the owners
    collection instead of re-reading the members collection of whatever -Group resolves to.

    .EXAMPLE
    Get-OERGroupMember -Group 'role_sec_identity_administrator'
    Lists the direct members of the group.

    .EXAMPLE
    Get-OERGroup -DisplayName 'role_sec_identity_administrator' | Get-OERGroupMember -Owners
    Pipes a group in and lists its owners.

    .EXAMPLE
    Get-OERGroupMember -Group 'role_sec_identity_administrator' -AccessType owner
    Lists the group's owners using the -AccessType form instead of the -Owners switch.
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory, ValueFromPipelineByPropertyName)]
        # GroupId precedes Id so a piped GroupMember object binds the group's GroupId, not the
        # principal's Id, during ValueFromPipelineByPropertyName alias resolution.
        [Alias('GroupId', 'Id', 'DisplayName')]
        [string]$Group,

        [switch]$Owners,

        [string]$TenantId,

        # Declared after the pre-existing parameters so their positional binding is unchanged.
        # -TenantId is position 1; inserting -AccessType above it would push -TenantId to
        # position 2 and break `Get-OERGroupMember 'grp' 'contoso.com'`.
        [Alias('MemberType')]
        [ValidateSet('member', 'owner')]
        [string]$AccessType = 'member'
    )
    begin {
        $AuthParams = @{}
        if ($TenantId) { $AuthParams.TenantId = $TenantId }
        Initialize-OERAuth @AuthParams
    }
    process {
        if ($Owners -and $PSBoundParameters.ContainsKey('AccessType') -and $AccessType -ne 'owner') {
            Write-CmdletError `
                -Message ([System.Exception]::new("-Owners and -AccessType '$AccessType' disagree. Supply one.")) `
                -ErrorId 'AmbiguousAccessType' -Category InvalidArgument -TargetObject $Group -Cmdlet $PSCmdlet `
                -Details "-Owners and -AccessType '$AccessType' disagree. Supply -Owners or -AccessType, not both."
            return
        }

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
                -Message ([System.Exception]::new(
                    "Group '$Group' not found. Verify the display name matches exactly (leading or trailing spaces " +
                    "and punctuation count) or pass the group object id instead.")) `
                -ErrorId 'GroupNotFound' -Category ObjectNotFound -TargetObject $Group -Cmdlet $PSCmdlet
            return
        }
        $IsOwner = $Owners -or ($AccessType -eq 'owner')
        $MemberType = if ($IsOwner) { 'Owner' } else { 'Member' }
        $Segment = if ($IsOwner) { 'owners' } else { 'members' }
        try {
            $Response = Invoke-OERGraphRequest -Uri ("v1.0/groups/{0}/{1}" -f $GroupId, $Segment) -All
        } catch {
            Remove-OERErrorRecord -Record $PSItem
            $PSCmdlet.WriteError($PSItem)
            return
        }
        foreach ($Item in @($Response.value)) {
            if ($null -eq $Item) { continue }
            ConvertTo-OERGroupMember -InputObject $Item -GroupId $GroupId -MemberType $MemberType
        }
    }
}
