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
    as a PimEligibility property. A named group that does not exist produces a non-terminating
    GroupNotFound error. For each of those three collections, the property is attached only when its
    read succeeds; a failed read omits the property entirely and raises a non-terminating error
    instead, so an empty array in the result always means the group genuinely has none.

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
    tagged Omnicit.EntraRBAC.GroupMember objects. The property is present only when the read
    succeeds; a failed read is reported as a non-terminating GroupMemberReadFailed error and the
    Members property is omitted, so a returned empty array always means the group has no members.

    .PARAMETER IncludeOwners
    When set, attaches the group's owners as an Owners property on the returned object, as tagged
    Omnicit.EntraRBAC.GroupMember objects (MemberType Owner). The property is present only when the
    read succeeds; a failed read is reported as a non-terminating GroupOwnerReadFailed error and the
    Owners property is omitted, so a returned empty array always means the group has no owners.

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
            if ($IncludeMembers) {
                # A failed read is NOT an empty membership. Substituting @() made a throttled or
                # permission-denied read indistinguishable from a group that genuinely has none, and
                # Get-OERInventory wrote that @() into an apply document as a fact -- which
                # Invoke-OERStructure -Prune then deletes on (issue #76). Omitting the property
                # instead keeps the two cases apart, and the error is non-terminating so
                # -ErrorAction and -ErrorVariable can see it; a Write-Warning could not be.
                $Members = $null
                $MembersRead = $true
                try {
                    $Members = @((Invoke-OERGraphRequest -Uri ("v1.0/groups/{0}/members" -f $GroupObj.Id) -All).value)
                    # Tag each member through the shared converter, exactly as Get-OERAdministrativeUnit
                    # does with ConvertTo-OERAdministrativeUnitMember, so Members carries formatted
                    # Omnicit.EntraRBAC.GroupMember objects instead of raw Graph dictionaries.
                    $Members = @($Members | Where-Object { $_ } | ForEach-Object {
                            ConvertTo-OERGroupMember -InputObject $_ -GroupId $GroupObj.Id -MemberType 'Member'
                        })
                } catch {
                    Remove-OERErrorRecord -Record $PSItem
                    $MembersRead = $false
                    Write-CmdletError `
                        -Message ([System.Exception]::new("Could not read members for group $($GroupObj.Id): $($PSItem.Exception.Message). The Members property is omitted rather than reported as empty.")) `
                        -ErrorId 'GroupMemberReadFailed' `
                        -Category ReadError `
                        -TargetObject $GroupObj.Id `
                        -InnerException $PSItem.Exception `
                        -Cmdlet $PSCmdlet
                }
                if ($MembersRead) {
                    $GroupObj | Add-Member -NotePropertyName Members -NotePropertyValue $Members -Force
                }
            }
            if ($IncludeOwners) {
                # Same rule as members above: a failed read omits the property instead of claiming
                # an empty owner set, and errors instead of warning.
                $Owners = $null
                $OwnersRead = $true
                try {
                    $Owners = @((Invoke-OERGraphRequest -Uri ("v1.0/groups/{0}/owners" -f $GroupObj.Id) -All).value)
                    # Tag each owner through the shared converter, exactly as the -IncludeMembers block
                    # above does, so Owners carries formatted Omnicit.EntraRBAC.GroupMember objects
                    # instead of raw Graph dictionaries.
                    $Owners = @($Owners | Where-Object { $_ } | ForEach-Object {
                            ConvertTo-OERGroupMember -InputObject $_ -GroupId $GroupObj.Id -MemberType 'Owner'
                        })
                } catch {
                    Remove-OERErrorRecord -Record $PSItem
                    $OwnersRead = $false
                    Write-CmdletError `
                        -Message ([System.Exception]::new("Could not read owners for group $($GroupObj.Id): $($PSItem.Exception.Message). The Owners property is omitted rather than reported as empty.")) `
                        -ErrorId 'GroupOwnerReadFailed' `
                        -Category ReadError `
                        -TargetObject $GroupObj.Id `
                        -InnerException $PSItem.Exception `
                        -Cmdlet $PSCmdlet
                }
                if ($OwnersRead) {
                    $GroupObj | Add-Member -NotePropertyName Owners -NotePropertyValue $Owners -Force
                }
            }
            if ($IncludePimEligibility) {
                $Elig = $null
                $EligRead = $true
                try {
                    # -ExpectedErrorCode, not a catch: a group that is not onboarded to PIM for
                    # Groups answers 400 ResourceTypeNotSupported on this beta endpoint, and that is
                    # an ANSWER -- there is no eligibility -- not a failure. Declaring it makes the
                    # wrapper return a marker instead of raising, so the not-onboarded case produces
                    # no PowerShell error anywhere in the chain. It has to be declared at the
                    # REQUEST, not recognised afterwards: a live Get-OERInventory read of 100 groups,
                    # 96 of them not onboarded, put 261 records into the caller's -ErrorVariable even
                    # though this cmdlet published none of them, because -ErrorVariable is filled by
                    # the ENGINE and collects records raised inside nested calls that an inner catch
                    # already swallowed. Nothing a catch here can do reaches those.
                    $EligResponse = Invoke-OERGraphRequest -Uri (Get-OERPimGroupsGraphPath -Path ("identityGovernance/privilegedAccess/group/eligibilityScheduleInstances?`$filter=groupId eq '{0}'" -f $GroupObj.Id)) -All -ExpectedErrorCode 'ResourceTypeNotSupported'
                    if (@($EligResponse.PSObject.TypeNames) -contains 'Omnicit.EntraRBAC.GraphExpectedError') {
                        # Not onboarded. A read that SUCCEEDED in telling us there is no eligibility,
                        # so the property is PRESENT and empty -- never omitted, which is what a
                        # failed read means here (issue #76).
                        $Elig = @()
                    }
                    else {
                        $Elig = @($EligResponse.value)
                    }
                } catch {
                    Remove-OERErrorRecord -Record $PSItem
                    # The block below answers the same condition arriving THROWN rather than as the
                    # marker above -- when this cmdlet's wrapper is mocked, or when a frame between
                    # the two re-raises the record. IT IS NOT A BACKUP FOR THE WRAPPER'S GATE, and
                    # the wrapper's gate is not a backup for this one: the two answer DIFFERENT
                    # ARRIVAL SHAPES. Measured, not reasoned -- softening the wrapper's
                    # Get-ExpectedGraphErrorMatch to an unconditional match with this block fully
                    # intact brought the defect back completely and SILENTLY (PimEligibility
                    # present, Count 0, zero error records), since a softened failure arrives as a
                    # marker and never reaches this catch at all. Softening only this block instead
                    # leaves PimEligibility = @() with 5 records. The wrapper's gate is the one that
                    # fires in production. Keep the token rule here and in the wrapper in step, and
                    # never delete either one on the strength of the other. Every other failure omits
                    # the property and errors, same as members and owners above.
                    #
                    # MATCHED ON THE GRAPH ERROR CODE AS A WHOLE TOKEN, not on one exact
                    # FullyQualifiedErrorId spelling. The code is the reliable signal; where the
                    # converted record carries it is not:
                    #
                    #   * Convert-GraphHttpException builds the record with the Graph error.code as
                    #     its ErrorId, so a record raised straight out of Invoke-OERGraphRequest
                    #     reads 'ResourceTypeNotSupported'. But a FullyQualifiedErrorId is composed
                    #     from every frame that re-raises the record, and the code is not always the
                    #     FIRST comma-separated segment -- 'PathNotFound,Get-ItemCommand' is the
                    #     engine's own shape. A prefix-only -like therefore misses it there.
                    #   * When the error body cannot be parsed the converter falls back to a
                    #     status-derived id ('BadRequest'), leaving the code only in the record's
                    #     detail text.
                    #   * A prefix-only -like also OVER-matches: a genuinely different code such as
                    #     ResourceTypeNotSupportedInThisTenant would be swallowed as "no
                    #     eligibility", turning a failed read into a silent empty collection -- the
                    #     exact failure mode the members/owners handling above exists to prevent.
                    #     A whole-token comparison refuses both mistakes.
                    #
                    # THE DETAIL TEXT IS A SECOND-CHOICE SOURCE, read ONLY when the id is one the
                    # converter derived from the HTTP status rather than from a code Graph named
                    # (its $StatusLabels vocabulary, 'HTTP<status>', or 'GraphError' -- keep this
                    # pattern in step with that table, and with Invoke-OERGraphRequest's
                    # Test-StatusDerivedErrorId, which carries the identical rule for the record
                    # that arrives as a marker). Reading it unconditionally was a defect: a genuine
                    #   {"code":"Authorization_RequestDenied",
                    #    "message":"Insufficient privileges: ResourceTypeNotSupported"}
                    # split on ':' yields 'ResourceTypeNotSupported' as a whole segment, so a real
                    # 403 was recorded as PimEligibility = @() -- a failed read stored as an empty
                    # fact, which is exactly what this block exists to prevent. When Graph has named
                    # the failure, its name is the answer and the prose is not consulted.
                    #
                    # Splitting on ',' (FullyQualifiedErrorId composition) and ':' (the converter's
                    # "<code>: <message>" detail form) and requiring an EXACT, case-insensitive
                    # segment match is what makes this a token test rather than a substring test.
                    #
                    # $EligError, not $PSItem, inside the pipelines below: ForEach-Object rebinds
                    # $PSItem to the string being trimmed, which would silently shadow the caught
                    # record if the record were read there.
                    $EligError = $PSItem
                    [string[]]$ErrorIdSegment = @(([string]$EligError.FullyQualifiedErrorId) -split ',') |
                        ForEach-Object { $PSItem.Trim() }
                    [string[]]$ErrorCodeCandidate = $ErrorIdSegment
                    $StatusDerivedId = '^(?:BadRequest|Unauthorized|Forbidden|NotFound|Conflict|TooManyRequests|' +
                        'InternalServerError|ServiceUnavailable|GraphError|HTTP\d+)$'
                    if (@($ErrorIdSegment | Where-Object { $PSItem -match $StatusDerivedId }).Count -gt 0) {
                        $ErrorCodeCandidate = @(
                            $ErrorIdSegment
                            ([string]$EligError.ErrorDetails.Message) -split ':'
                            ([string]$EligError.Exception.Message) -split ':'
                        ) | ForEach-Object { $PSItem.Trim() }
                    }
                    if ($ErrorCodeCandidate -contains 'ResourceTypeNotSupported') {
                        $Elig = @()
                    } else {
                        $EligRead = $false
                        Write-CmdletError `
                            -Message ([System.Exception]::new("Could not read PIM eligibility for group $($GroupObj.Id): $($PSItem.Exception.Message). The PimEligibility property is omitted rather than reported as empty.")) `
                            -ErrorId 'GroupPimEligibilityReadFailed' `
                            -Category ReadError `
                            -TargetObject $GroupObj.Id `
                            -InnerException $PSItem.Exception `
                            -Cmdlet $PSCmdlet
                    }
                }
                if ($EligRead) {
                    $GroupObj | Add-Member -NotePropertyName PimEligibility -NotePropertyValue $Elig -Force
                }
            }
            $GroupObj
        }
    }
}
