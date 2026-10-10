function Get-OERGroup {
    <#
    .SYNOPSIS
    Reads one or more Entra ID groups by id, display name, OData filter, or the whole tenant.

    .DESCRIPTION
    Retrieves Entra ID groups through Microsoft Graph and returns them as tagged
    Omnicit.EntraRBAC.Group objects. Supply -Group as either an object id (GUID) for a direct read or
    a display name for an exact display-name match, -Filter for an arbitrary OData filter
    expression, or -All for every group in the tenant with no filter of any kind.
    With -IncludeMembers the group's direct members are attached as a Members property;
    with -IncludeOwners the group's owners are attached as an Owners property; with
    -IncludePimEligibility the group's PIM-for-groups eligibility schedule instances are attached
    as a PimEligibility property. Members and Owners include service principals, which Microsoft
    Graph's v1.0 member and owner lists leave out: each of those two reads also asks for the group's
    service principals through the typed servicePrincipal collection. A named group that does not
    exist produces a non-terminating GroupNotFound error. For each of those three collections, the
    property is attached only when its read succeeds (for members and owners, when both requests
    succeed); a failed read omits the property entirely and raises a non-terminating error instead,
    so an empty array in the result always means the group genuinely has none. Every group carries
    OnPremisesSyncEnabled, Microsoft Graph's own value: True for a group synchronized from
    on-premises Active Directory, which is managed there and read-only in the cloud
    (Invoke-OERStructure writes nothing to it), False for a group that was synchronized and no longer
    is, and empty for a group that never was, or whose source of authority was converted to the
    cloud. Nothing is filtered out on it.

    .PARAMETER Group
    The group to act on, given as either its object id (GUID) or its display name -- the same
    name-or-GUID target every membership, eligibility and PIM cmdlet in the module accepts. Binds
    from the pipeline by property name, and still accepts the historical -Id, -GroupId and
    -DisplayName parameter names as aliases. GroupId takes precedence during pipeline binding so a
    piped Get-OERGroupMember object binds the group's GroupId instead of a principal's Id.

    .PARAMETER Filter
    An OData filter expression (without the $filter= prefix) used to query groups.

    .PARAMETER All
    Lists every group in the tenant using an unfiltered, paged GET (following @odata.nextLink until
    exhausted). Use this rather than a filter such as 'securityEnabled eq true' whenever the result
    is meant to be a complete roster: a security-enabled filter silently omits distribution groups
    and every Microsoft 365 group whose securityEnabled is false, and their absence from the result
    is indistinguishable from their absence from the tenant.

    .PARAMETER IncludeMembers
    When set, attaches the group's direct members as a Members property on the returned object, as
    tagged Omnicit.EntraRBAC.GroupMember objects, service principals included (read through the
    typed servicePrincipal collection as well). The property is present only when the read succeeds,
    which takes both requests; a failed read is reported as a non-terminating GroupMemberReadFailed
    error and the Members property is omitted, so a returned empty array always means the group has
    no members.

    .PARAMETER IncludeOwners
    When set, attaches the group's owners as an Owners property on the returned object, as tagged
    Omnicit.EntraRBAC.GroupMember objects (MemberType Owner), service principals included (read
    through the typed servicePrincipal collection as well). The property is present only when the
    read succeeds, which takes both requests; a failed read is reported as a non-terminating
    GroupOwnerReadFailed error and the Owners property is omitted, so a returned empty array always
    means the group has no owners.

    .PARAMETER IncludePimEligibility
    When set, attaches the group's PIM-for-groups eligibility schedule instances as a
    PimEligibility property. A group that is not onboarded to PIM for Groups still reads back as an
    empty array with no error, since that genuinely means no eligibility exists. Any other failed
    read is reported as a non-terminating GroupPimEligibilityReadFailed error and the PimEligibility
    property is omitted, so a returned empty array always means there are no eligible assignments.

    .PARAMETER TenantId
    Optional tenant id or domain to authenticate against, forwarded to Initialize-OERAuth.

    .EXAMPLE
    Get-OERGroup -Group 'role_sec_identity_administrator' -IncludeMembers
    Returns the group with its direct members attached.

    .EXAMPLE
    Get-OERGroup -DisplayName 'role_sec_identity_administrator'
    Returns the group, using the historical -DisplayName alias for -Group.

    .EXAMPLE
    Get-OERGroup -Filter "startswith(displayName,'role_sec_')"
    Returns every group whose display name starts with role_sec_.

    .EXAMPLE
    Get-OERGroup -All
    Returns every group in the tenant, of every group type, with no filter applied.

    .EXAMPLE
    Get-OERGroup -All | Where-Object OnPremisesSyncEnabled
    Returns every group synchronized from on-premises Active Directory.
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', 'All',
        Justification = 'Switch is a parameter-set discriminator; ParameterSetName is used instead.')]
    [CmdletBinding(DefaultParameterSetName = 'ByGroup')]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(ParameterSetName = 'ByGroup', Mandatory, ValueFromPipelineByPropertyName)]
        # GroupId precedes Id so a piped GroupMember object binds the group's GroupId, not the
        # principal's Id, during ValueFromPipelineByPropertyName alias resolution.
        [Alias('GroupId', 'Id', 'DisplayName')]
        [string]$Group,

        [Parameter(ParameterSetName = 'ByFilter', Mandatory)]
        [string]$Filter,

        [Parameter(ParameterSetName = 'All', Mandatory)]
        [switch]$All,

        [switch]$IncludeMembers,
        [switch]$IncludePimEligibility,
        [switch]$IncludeOwners,
        [ValidateNotNullOrEmpty()]
        [string]$TenantId
    )
    begin {
        $AuthParams = @{}
        if ($TenantId) { $AuthParams.TenantId = $TenantId }
        Initialize-OERAuth @AuthParams
    }
    process {
        try {
            $Raw = switch ($PSCmdlet.ParameterSetName) {
                'ByGroup' {
                    if (Test-OERGuid -Value $Group) {
                        , @(Invoke-OERGraphRequest -Uri ("v1.0/groups/{0}" -f $Group))
                    }
                    else {
                        $Escaped = ConvertTo-OERODataFilterValue -Value $Group
                        @((Invoke-OERGraphRequest -Uri "v1.0/groups?`$filter=displayName eq '$Escaped'").value)
                    }
                }
                'ByFilter' {
                    $Encoded = [System.Uri]::EscapeDataString($Filter)
                    @((Invoke-OERGraphRequest -Uri "v1.0/groups?`$filter=$Encoded" -All).value)
                }
                'All' {
                    # No $filter at all, deliberately. Every filtered listing this module used to
                    # call a "full roster" was really a security-enabled one, so a distribution
                    # group and a Microsoft 365 group with securityEnabled false were missing from
                    # a result that claimed to be complete -- and nothing in the output said so.
                    # -All on the wrapper is the PAGING switch, unrelated to this parameter set's
                    # own -All; both are needed, since an unfiltered tenant read is exactly the
                    # shape that spans pages.
                    @((Invoke-OERGraphRequest -Uri 'v1.0/groups' -All).value)
                }
            }
        } catch {
            Remove-OERErrorRecord -Record $PSItem
            $PSCmdlet.WriteError($PSItem)
            return
        }

        $Raw = @($Raw | Where-Object { $_ })
        if ($Raw.Count -eq 0) {
            $Target = switch ($PSCmdlet.ParameterSetName) {
                'ByGroup' { $Group }
                'ByFilter' { $Filter }
                default { 'every group in the tenant' }
            }
            Write-CmdletError `
                -Message ([System.Exception]::new("No group found for '$Target'.")) `
                -ErrorId 'GroupNotFound' `
                -Category ObjectNotFound `
                -TargetObject $Target `
                -Cmdlet $PSCmdlet
            return
        }

        foreach ($GraphGroup in $Raw) {
            $GroupObj = ConvertTo-OERGroup -InputObject $GraphGroup
            # Each requested collection is read by Read-OERGroupCollection, in the order members,
            # owners, PIM eligibility. A failed read is NOT an empty collection (issue #76): the
            # reader returns the failure and its text, this loop omits the property and writes the
            # failure as a non-terminating error, so -ErrorAction and -ErrorVariable can see it and
            # a returned empty array always means the group genuinely has none. The reasons, and
            # the rule for a group that is not onboarded to PIM for Groups, are documented there.
            foreach ($Wanted in @(
                    @{ On = [bool]$IncludeMembers; Collection = 'Members' }
                    @{ On = [bool]$IncludeOwners; Collection = 'Owners' }
                    @{ On = [bool]$IncludePimEligibility; Collection = 'PimEligibility' })) {
                if (-not $Wanted.On) { continue }
                $CollectionRead = Read-OERGroupCollection -GroupId $GroupObj.Id -Collection $Wanted.Collection
                if ($CollectionRead.Read) {
                    $GroupObj | Add-Member -NotePropertyName $Wanted.Collection -NotePropertyValue $CollectionRead.Value -Force
                } else {
                    Write-CmdletError `
                        -Message ([System.Exception]::new($CollectionRead.Message)) `
                        -ErrorId $CollectionRead.ErrorId `
                        -Category ReadError `
                        -TargetObject $GroupObj.Id `
                        -InnerException $CollectionRead.Exception `
                        -Cmdlet $PSCmdlet
                }
            }
            $GroupObj
        }
    }
}
