function Get-OERServicePrincipalAccess {
    <#
    .SYNOPSIS
    Reads the application permissions, delegated permission grants and owners of a tenant's service
    principals and app registrations, as read-only context.

    .DESCRIPTION
    Single reader behind Export-OERInventory -IncludeServicePrincipalAccess and the bundle file
    servicePrincipalAccess.json (Sprint 11 step 8). It makes four reads, each through
    Invoke-OERGraphRequest with -All, which follows @odata.nextLink:

    1. v1.0/servicePrincipals?$select=id,appId,displayName,appRoles&$expand=appRoleAssignments&$top=999
       -- every service principal: its name, the app roles it declares as a resource, and its OWN app
       role assignments, the client side. The application permissions are read from the client side,
       expanded on this one list: measured in a test tenant, the expanded assignments equal the
       per-client read of every service principal, while the resource side (appRoleAssignedTo)
       missed 2 of 133 service principal assignments that the client side shows.
    2. v1.0/servicePrincipals?$select=id,displayName&$expand=owners($select=id,displayName,userPrincipalName)&$top=999
       -- the owners of each service principal.
    3. v1.0/applications?$select=id,appId,displayName&$expand=owners($select=id,displayName,userPrincipalName)&$top=999
       -- the app registrations and the owners of each.
    4. v1.0/oauth2PermissionGrants?$top=999 -- the delegated permission grants. The users that the
       grants with consentType Principal name are looked up with ONE Resolve-OERPrincipalName -Detailed
       call (directoryObjects/getByIds, 1,000 ids per request). Read 4 is made only when read 1 was
       read, since the grants name their client and resource through it.

    Microsoft Graph documents a maximum of 20 entries for an expanded directory relationship, and no
    next link for it. So an object whose expanded appRoleAssignments or owners holds 20 or more
    entries is read again in full with a paged read of its own, and that read is used instead of the
    expanded entries: v1.0/servicePrincipals/{id}/appRoleAssignments?$top=999 for read 1, and
    v1.0/servicePrincipals/{id}/owners or v1.0/applications/{id}/owners, each with
    $select=id,displayName,userPrincipalName&$top=999, for reads 2 and 3. An object with 19 or fewer
    is not read again (measured: no object in the test tenant reached 20).

    The cost: one request per page of each of the three lists and of the grants, one
    directoryObjects/getByIds per 1,000 users named in grants, and one extra paged read per object
    with 20 or more expanded entries; measured 27 requests for a tenant of 1,129 service principals
    and 67 app registrations. The function itself sends GET requests only; the getByIds POST is
    Resolve-OERPrincipalName's.

    A part is read whole or not at all: any failure inside a part leaves it $null, never an empty
    array, and names it in Unread. Read 1 failing -- the list, the full read of one of its objects, or
    an object listed without an id or without an appRoleAssignments collection (the expansion did
    not happen, which is never read as none) -- leaves applicationPermissions AND
    delegatedPermissionGrants unread, since the grants are named through that list, and the grants are
    then not read at all. Read 2 failing, the same way with its owners, leaves servicePrincipalOwners
    unread, read 3 applicationOwners, and read 4, or a user lookup that answers Read false for any
    user (or gives no answer for one), delegatedPermissionGrants. A list answer that carries no value
    collection is a failed read too. One part failing never stops another, and a part that was read
    and holds nothing is an empty array. An object listed twice (by id, letter case ignored) counts
    once.

    The rows, each an ordered object with its keys in this order; every id is written lower-cased,
    every blank text is written $null, and nothing is invented:
    applicationPermissions -- servicePrincipalId, servicePrincipalDisplayName (the client the list
    returned), resourceId, resourceDisplayName (the resource's displayName from read 1, else the
    assignment's resourceDisplayName, else $null), appRoleId and appRoleValue (the value of the
    resource's app role whose id equals appRoleId, letter case ignored; $null when the resource does
    not declare it, as for the default access role 00000000-0000-0000-0000-000000000000 or a role
    since removed). delegatedPermissionGrants -- clientId, clientDisplayName, resourceId,
    resourceDisplayName (both names from read 1, $null for an id it did not list), consentType,
    principalId, principalDisplayName ($null for AllPrincipals; for Principal the lookup's Name when
    the directory returned the user, $null when it did not) and scope (the grant's space-separated
    scope string, trimmed). applicationOwners -- applicationId, appId, applicationDisplayName,
    ownerId, ownerType, ownerDisplayName, ownerUserPrincipalName. servicePrincipalOwners --
    servicePrincipalId, servicePrincipalDisplayName, ownerId, ownerType, ownerDisplayName,
    ownerUserPrincipalName. ownerType is ConvertTo-OERPrincipalType of the owner's @odata.type, else
    that type without its '#microsoft.graph.' prefix, else $null. Each part is sorted, ordinally and
    without regard to letter case, by its first display name, then its second, then its ids, so two
    exports of an unchanged tenant write the same file.

    The function never throws and never writes an error record or a warning: every catch removes the
    record first (Remove-OERErrorRecord), and what could not be read is returned for the caller to
    name. It performs no authentication of its own: the caller signs in first.

    Returns one object, tagged Omnicit.EntraRBAC.ServicePrincipalAccess: ApplicationPermissions,
    DelegatedPermissionGrants, ApplicationOwners and ServicePrincipalOwners (each the sorted rows, or
    $null when that part could not be read), Unread (string[], one path per unread part in that
    order: 'servicePrincipalAccess/applicationPermissions',
    'servicePrincipalAccess/delegatedPermissionGrants', 'servicePrincipalAccess/applicationOwners'
    and 'servicePrincipalAccess/servicePrincipalOwners') and Causes (objects with Cause, the message,
    and Target, the object id or the list request, per failure).

    .EXAMPLE
    $Access = Get-OERServicePrincipalAccess
    Reads the four parts. $Access.Unread names each part that could not be read, and that part is $null.
    #>
    [OutputType([PSCustomObject])]
    [CmdletBinding()]
    param()

    # Microsoft Graph documents a maximum of 20 entries for an expanded directory relationship.
    $ExpandedCap = 20
    $PermissionListUri = 'v1.0/servicePrincipals?$select=id,appId,displayName,appRoles&$expand=appRoleAssignments&$top=999'
    $PermissionReReadFormat = 'v1.0/servicePrincipals/{0}/appRoleAssignments?$top=999'
    $ServicePrincipalOwnerListUri = 'v1.0/servicePrincipals?$select=id,displayName&$expand=owners($select=id,displayName,userPrincipalName)&$top=999'
    $ServicePrincipalOwnerReReadFormat = 'v1.0/servicePrincipals/{0}/owners?$select=id,displayName,userPrincipalName&$top=999'
    $ApplicationOwnerListUri = 'v1.0/applications?$select=id,appId,displayName&$expand=owners($select=id,displayName,userPrincipalName)&$top=999'
    $ApplicationOwnerReReadFormat = 'v1.0/applications/{0}/owners?$select=id,displayName,userPrincipalName&$top=999'
    $GrantListUri = 'v1.0/oauth2PermissionGrants?$top=999'

    # A value as text: $null for a missing or blank value.
    function Get-TextOrNull {
        param([object]$Value)
        $Text = [string]$Value
        if ([string]::IsNullOrWhiteSpace($Text)) { return $null }
        $Text
    }

    # An id as text, lower-cased: $null for a missing or blank value.
    function Get-IdOrNull {
        param([object]$Value)
        $Text = Get-TextOrNull -Value $Value
        if ($null -eq $Text) { return $null }
        $Text.ToLowerInvariant()
    }

    # Whether a Graph object (a hashtable from the transport, or an object) carries a key at all.
    function Test-HasKey {
        param([object]$Item, [string]$Key)
        if ($null -eq $Item) { return $false }
        if ($Item -is [System.Collections.IDictionary]) { return $Item.Contains($Key) }
        return $null -ne $Item.PSObject.Properties[$Key]
    }

    # The items of a list answer. An answer with no value collection says nothing about the list, so it
    # is a failed read, never an empty one.
    function Get-ListValue {
        param([object]$Response)
        if (-not (Test-HasKey -Item $Response -Key 'value') -or $null -eq $Response.value) {
            throw 'Microsoft Graph returned no value collection for the list.'
        }
        , [object[]]@(@($Response.value) | Where-Object { $null -ne $_ })
    }

    # The id of a listed object. An object listed without one cannot be keyed or read again.
    function Get-ListedId {
        param([object]$Item, [string]$Kind)
        $ItemId = Get-IdOrNull -Value $Item.id
        if ($null -eq $ItemId) { throw "Microsoft Graph listed a $Kind without an id." }
        $ItemId
    }

    # The entries of an expanded relationship of a listed object: the expanded ones, or, when 20 or more
    # were expanded, the object's own paged read instead. An object that carries no such collection --
    # the expansion did not happen -- is a failed read, never one with no entries.
    function Get-ExpandedEntry {
        param([object]$Item, [string]$Key, [string]$ItemId, [string]$ReReadFormat)
        if (-not (Test-HasKey -Item $Item -Key $Key) -or $null -eq $Item.$Key) {
            throw "Microsoft Graph returned it without its expanded $Key collection, so the expansion did not happen."
        }
        $Entries = [object[]]@(@($Item.$Key) | Where-Object { $null -ne $_ })
        if ($Entries.Count -ge $ExpandedCap) {
            $Entries = Get-ListValue -Response (Invoke-OERGraphRequest -Uri ($ReReadFormat -f $ItemId) -All)
        }
        , $Entries
    }

    # The type of an owner: the document's principal type, else the Graph type without its prefix.
    function Get-OwnerType {
        param([object]$Owner)
        $ODataType = Get-TextOrNull -Value $Owner.'@odata.type'
        if ($null -eq $ODataType) { return $null }
        $Mapped = ConvertTo-OERPrincipalType -ODataType $ODataType
        if ($Mapped) { return $Mapped }
        Get-TextOrNull -Value ($ODataType -replace '^#microsoft\.graph\.', '')
    }

    # The rows sorted, ordinally and without regard to letter case, on the keys in the order given. The
    # keys are joined with a NUL, which sorts before every other character, so the joined text sorts as
    # the keys do one after the other. The casts pick Array.Sort(Array, Array, IComparer), which sorts
    # the rows in place beside their keys: without them PowerShell picks the generic overload and hands
    # it a COPY of the rows, so the keys are sorted and the rows are not (measured in PowerShell 7).
    function Get-SortedRow {
        param([object[]]$Row, [string[]]$Key)
        $Items = [object[]]@(@($Row) | Where-Object { $null -ne $_ })
        $SortKeys = [string[]]::new($Items.Count)
        for ($Index = 0; $Index -lt $Items.Count; $Index++) {
            $SortKeys[$Index] = @(foreach ($Name in $Key) { [string]$Items[$Index].$Name }) -join "`0"
        }
        [System.Array]::Sort([System.Array]$SortKeys, [System.Array]$Items, [System.Collections.IComparer][System.StringComparer]::OrdinalIgnoreCase)
        , $Items
    }

    $Causes = [System.Collections.Generic.List[object]]::new()

    # 1. The service principals, the app roles each declares, and each one's own app role assignments.
    # The names and roles are kept for the grants below.
    $ServicePrincipals = [System.Collections.Generic.Dictionary[string, object]]::new([System.StringComparer]::OrdinalIgnoreCase)
    $ApplicationPermissions = $null
    $Step = 'the service principal list with its app role assignments'
    $Target = $PermissionListUri
    try {
        $Listed = Get-ListValue -Response (Invoke-OERGraphRequest -Uri $PermissionListUri -All)
        $Held = [System.Collections.Generic.List[object]]::new()
        foreach ($Listing in $Listed) {
            $Step = 'the service principal list with its app role assignments'
            $Target = $PermissionListUri
            $ServicePrincipalId = Get-ListedId -Item $Listing -Kind 'service principal'
            if ($ServicePrincipals.ContainsKey($ServicePrincipalId)) { continue }
            $Step = "the app role assignments of the service principal '$ServicePrincipalId'"
            $Target = $ServicePrincipalId
            $RoleValue = [System.Collections.Generic.Dictionary[string, object]]::new([System.StringComparer]::OrdinalIgnoreCase)
            foreach ($AppRole in @(@($Listing.appRoles) | Where-Object { $null -ne $_ })) {
                $AppRoleId = Get-IdOrNull -Value $AppRole.id
                if ($AppRoleId -and -not $RoleValue.ContainsKey($AppRoleId)) { $RoleValue[$AppRoleId] = Get-TextOrNull -Value $AppRole.value }
            }
            $ServicePrincipals[$ServicePrincipalId] = [PSCustomObject]@{ DisplayName = (Get-TextOrNull -Value $Listing.displayName); RoleValue = $RoleValue }
            foreach ($Assignment in (Get-ExpandedEntry -Item $Listing -Key 'appRoleAssignments' -ItemId $ServicePrincipalId -ReReadFormat $PermissionReReadFormat)) {
                $Held.Add([PSCustomObject]@{ ClientId = $ServicePrincipalId; Assignment = $Assignment })
            }
        }
        # The rows are built once every service principal is listed, since a resource can be listed
        # after the client that holds its roles.
        $Rows = foreach ($HeldAssignment in $Held) {
            $Assignment = $HeldAssignment.Assignment
            $ResourceId = Get-IdOrNull -Value $Assignment.resourceId
            $AppRoleId = Get-IdOrNull -Value $Assignment.appRoleId
            $Resource = $null
            if ($ResourceId -and $ServicePrincipals.ContainsKey($ResourceId)) { $Resource = $ServicePrincipals[$ResourceId] }
            $ResourceDisplayName = $null
            if ($Resource -and $Resource.DisplayName) { $ResourceDisplayName = $Resource.DisplayName } else { $ResourceDisplayName = Get-TextOrNull -Value $Assignment.resourceDisplayName }
            $AppRoleValue = $null
            if ($Resource -and $AppRoleId -and $Resource.RoleValue.ContainsKey($AppRoleId)) { $AppRoleValue = $Resource.RoleValue[$AppRoleId] }
            [PSCustomObject][ordered]@{
                servicePrincipalId          = $HeldAssignment.ClientId
                servicePrincipalDisplayName = $ServicePrincipals[$HeldAssignment.ClientId].DisplayName
                resourceId                  = $ResourceId
                resourceDisplayName         = $ResourceDisplayName
                appRoleId                   = $AppRoleId
                appRoleValue                = $AppRoleValue
            }
        }
        $ApplicationPermissions = Get-SortedRow -Row @($Rows) -Key @('servicePrincipalDisplayName', 'resourceDisplayName', 'servicePrincipalId', 'resourceId', 'appRoleId')
    } catch {
        Remove-OERErrorRecord -Record $PSItem
        $ApplicationPermissions = $null
        $Causes.Add([PSCustomObject]@{ Cause = "Could not read $($Step): $($PSItem.Exception.Message)"; Target = $Target })
    }

    # 2. The owners of each service principal.
    $ServicePrincipalOwners = $null
    $Step = 'the service principal list with its owners'
    $Target = $ServicePrincipalOwnerListUri
    try {
        $Listed = Get-ListValue -Response (Invoke-OERGraphRequest -Uri $ServicePrincipalOwnerListUri -All)
        $Seen = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
        $Rows = foreach ($Listing in $Listed) {
            $Step = 'the service principal list with its owners'
            $Target = $ServicePrincipalOwnerListUri
            $ServicePrincipalId = Get-ListedId -Item $Listing -Kind 'service principal'
            if (-not $Seen.Add($ServicePrincipalId)) { continue }
            $Step = "the owners of the service principal '$ServicePrincipalId'"
            $Target = $ServicePrincipalId
            $ServicePrincipalDisplayName = Get-TextOrNull -Value $Listing.displayName
            foreach ($Owner in (Get-ExpandedEntry -Item $Listing -Key 'owners' -ItemId $ServicePrincipalId -ReReadFormat $ServicePrincipalOwnerReReadFormat)) {
                [PSCustomObject][ordered]@{
                    servicePrincipalId          = $ServicePrincipalId
                    servicePrincipalDisplayName = $ServicePrincipalDisplayName
                    ownerId                     = Get-IdOrNull -Value $Owner.id
                    ownerType                   = Get-OwnerType -Owner $Owner
                    ownerDisplayName            = Get-TextOrNull -Value $Owner.displayName
                    ownerUserPrincipalName      = Get-TextOrNull -Value $Owner.userPrincipalName
                }
            }
        }
        $ServicePrincipalOwners = Get-SortedRow -Row @($Rows) -Key @('servicePrincipalDisplayName', 'ownerDisplayName', 'servicePrincipalId', 'ownerId')
    } catch {
        Remove-OERErrorRecord -Record $PSItem
        $ServicePrincipalOwners = $null
        $Causes.Add([PSCustomObject]@{ Cause = "Could not read $($Step): $($PSItem.Exception.Message)"; Target = $Target })
    }

    # 3. The app registrations and the owners of each.
    $ApplicationOwners = $null
    $Step = 'the app registration list with its owners'
    $Target = $ApplicationOwnerListUri
    try {
        $Listed = Get-ListValue -Response (Invoke-OERGraphRequest -Uri $ApplicationOwnerListUri -All)
        $Seen = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
        $Rows = foreach ($Listing in $Listed) {
            $Step = 'the app registration list with its owners'
            $Target = $ApplicationOwnerListUri
            $ApplicationId = Get-ListedId -Item $Listing -Kind 'app registration'
            if (-not $Seen.Add($ApplicationId)) { continue }
            $Step = "the owners of the app registration '$ApplicationId'"
            $Target = $ApplicationId
            $AppId = Get-IdOrNull -Value $Listing.appId
            $ApplicationDisplayName = Get-TextOrNull -Value $Listing.displayName
            foreach ($Owner in (Get-ExpandedEntry -Item $Listing -Key 'owners' -ItemId $ApplicationId -ReReadFormat $ApplicationOwnerReReadFormat)) {
                [PSCustomObject][ordered]@{
                    applicationId          = $ApplicationId
                    appId                  = $AppId
                    applicationDisplayName = $ApplicationDisplayName
                    ownerId                = Get-IdOrNull -Value $Owner.id
                    ownerType              = Get-OwnerType -Owner $Owner
                    ownerDisplayName       = Get-TextOrNull -Value $Owner.displayName
                    ownerUserPrincipalName = Get-TextOrNull -Value $Owner.userPrincipalName
                }
            }
        }
        $ApplicationOwners = Get-SortedRow -Row @($Rows) -Key @('applicationDisplayName', 'ownerDisplayName', 'applicationId', 'appId', 'ownerId')
    } catch {
        Remove-OERErrorRecord -Record $PSItem
        $ApplicationOwners = $null
        $Causes.Add([PSCustomObject]@{ Cause = "Could not read $($Step): $($PSItem.Exception.Message)"; Target = $Target })
    }

    # 4. The delegated permission grants, named through read 1: read only when read 1 was read. The users
    # a Principal grant names are looked up once, all of them in one call; one the lookup could not read
    # leaves the whole part unread, never written with a name missing for a reason nobody knows.
    $DelegatedPermissionGrants = $null
    if ($null -ne $ApplicationPermissions) {
        $Step = 'the delegated permission grants'
        $Target = $GrantListUri
        try {
            $Grants = Get-ListValue -Response (Invoke-OERGraphRequest -Uri $GrantListUri -All)
            $PrincipalIds = [System.Collections.Generic.List[string]]::new()
            $SeenPrincipal = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
            foreach ($Grant in $Grants) {
                if (-not [string]::Equals([string]$Grant.consentType, 'Principal', [System.StringComparison]::OrdinalIgnoreCase)) { continue }
                $PrincipalId = Get-IdOrNull -Value $Grant.principalId
                if ($PrincipalId -and $SeenPrincipal.Add($PrincipalId)) { $PrincipalIds.Add($PrincipalId) }
            }
            $Answers = [System.Collections.Generic.Dictionary[string, object]]::new([System.StringComparer]::OrdinalIgnoreCase)
            $LookupFailed = $false
            if ($PrincipalIds.Count -gt 0) {
                $Step = 'the users named in the delegated permission grants'
                $Target = 'v1.0/directoryObjects/getByIds'
                foreach ($Answer in @(Resolve-OERPrincipalName -Id $PrincipalIds.ToArray() -Detailed)) {
                    if ($null -ne $Answer -and -not [string]::IsNullOrWhiteSpace([string]$Answer.Id)) { $Answers[[string]$Answer.Id] = $Answer }
                }
                foreach ($PrincipalId in $PrincipalIds) {
                    $Answer = $null
                    if ($Answers.ContainsKey($PrincipalId)) { $Answer = $Answers[$PrincipalId] }
                    if ($null -ne $Answer -and $Answer.Read -eq $true) { continue }
                    $LookupFailed = $true
                    $Why = 'the lookup gave no answer for it'
                    if ($null -ne $Answer -and -not [string]::IsNullOrWhiteSpace([string]$Answer.Cause)) { $Why = [string]$Answer.Cause }
                    $Causes.Add([PSCustomObject]@{ Cause = "Could not look up the user '$PrincipalId' named in a delegated permission grant: $Why"; Target = $PrincipalId })
                }
            }
            if (-not $LookupFailed) {
                $Rows = foreach ($Grant in $Grants) {
                    $ClientId = Get-IdOrNull -Value $Grant.clientId
                    $ResourceId = Get-IdOrNull -Value $Grant.resourceId
                    $ConsentType = Get-TextOrNull -Value $Grant.consentType
                    $IsAllPrincipals = [string]::Equals($ConsentType, 'AllPrincipals', [System.StringComparison]::OrdinalIgnoreCase)
                    $IsPrincipal = [string]::Equals($ConsentType, 'Principal', [System.StringComparison]::OrdinalIgnoreCase)
                    $PrincipalId = $null
                    if (-not $IsAllPrincipals) { $PrincipalId = Get-IdOrNull -Value $Grant.principalId }
                    $PrincipalDisplayName = $null
                    if ($IsPrincipal -and $PrincipalId -and $Answers.ContainsKey($PrincipalId) -and $Answers[$PrincipalId].Found -eq $true) {
                        $PrincipalDisplayName = Get-TextOrNull -Value $Answers[$PrincipalId].Name
                    }
                    $ClientDisplayName = $null
                    if ($ClientId -and $ServicePrincipals.ContainsKey($ClientId)) { $ClientDisplayName = $ServicePrincipals[$ClientId].DisplayName }
                    $ResourceDisplayName = $null
                    if ($ResourceId -and $ServicePrincipals.ContainsKey($ResourceId)) { $ResourceDisplayName = $ServicePrincipals[$ResourceId].DisplayName }
                    $GrantScope = Get-TextOrNull -Value (([string]$Grant.scope).Trim())
                    [PSCustomObject][ordered]@{
                        clientId             = $ClientId
                        clientDisplayName    = $ClientDisplayName
                        resourceId           = $ResourceId
                        resourceDisplayName  = $ResourceDisplayName
                        consentType          = $ConsentType
                        principalId          = $PrincipalId
                        principalDisplayName = $PrincipalDisplayName
                        scope                = $GrantScope
                    }
                }
                $DelegatedPermissionGrants = Get-SortedRow -Row @($Rows) -Key @('clientDisplayName', 'resourceDisplayName', 'clientId', 'resourceId', 'principalId')
            }
        } catch {
            Remove-OERErrorRecord -Record $PSItem
            $DelegatedPermissionGrants = $null
            $Causes.Add([PSCustomObject]@{ Cause = "Could not read $($Step): $($PSItem.Exception.Message)"; Target = $Target })
        }
    }

    # What could not be read, one path per part, in the part order.
    $Unread = [System.Collections.Generic.List[string]]::new()
    if ($null -eq $ApplicationPermissions) { $Unread.Add('servicePrincipalAccess/applicationPermissions') }
    if ($null -eq $DelegatedPermissionGrants) { $Unread.Add('servicePrincipalAccess/delegatedPermissionGrants') }
    if ($null -eq $ApplicationOwners) { $Unread.Add('servicePrincipalAccess/applicationOwners') }
    if ($null -eq $ServicePrincipalOwners) { $Unread.Add('servicePrincipalAccess/servicePrincipalOwners') }

    $Out = [PSCustomObject]@{
        ApplicationPermissions    = $ApplicationPermissions
        DelegatedPermissionGrants = $DelegatedPermissionGrants
        ApplicationOwners         = $ApplicationOwners
        ServicePrincipalOwners    = $ServicePrincipalOwners
        Unread                    = $Unread.ToArray()
        Causes                    = $Causes.ToArray()
    }
    $Out.PSObject.TypeNames.Insert(0, 'Omnicit.EntraRBAC.ServicePrincipalAccess')
    $Out
}
