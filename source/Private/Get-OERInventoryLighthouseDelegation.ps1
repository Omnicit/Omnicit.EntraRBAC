function Get-OERInventoryLighthouseDelegation {
    <#
    .SYNOPSIS
    Reads the Azure Lighthouse delegations at the subscriptions of an inventory's Azure scopes as
    read-only context.

    .DESCRIPTION
    Single owner of the bounded read behind Export-OERInventory's lighthouseDelegations.json (Sprint 11
    step 6b, BL-133; docs/development/rationale.md#lighthouse-delegations). Azure Lighthouse lets
    another tenant manage subscriptions or resource groups of this one: a registration definition
    (the offer, the managing tenant and its authorizations) is created at the subscription, and a
    registration assignment in each delegated scope, the subscription or a resource group. Every read
    goes through Invoke-OERArmRequest, api-version 2022-10-01 for Microsoft.ManagedServices; Reader's
    */read covers the actions (measured: an identity without an Azure role is answered
    AuthorizationFailed naming registrationAssignments/read and registrationDefinitions/read).

    The scopes are grouped per subscription, letter case ignored, in the order first named; a scope
    that is not under /subscriptions/ (a management group, the root scope '/') is skipped with no
    request. A scope that is a subscription marks it whole. A scope below a subscription (reached only
    through Export-OERInventory -Scope) names its resource group and nothing more is read for it.

    Per subscription two paged reads are made: the registration assignments with the definition
    expanded ($expandRegistrationDefinition=true), and the registration definitions. A subscription
    named whole whose definitions are not all named by an assignment of its own list may hold a
    delegation at a resource group that the list did not return (Microsoft Learn does not say whether
    a subscription's list returns the assignments of its resource groups): then ONE resource group
    listing (api-version 2025-04-01) is read and the assignment list of every resource group. When
    every definition is named, no resource group is listed. A subscription named only through scopes
    below it reads the assignment list of each resource group it names, and keeps the delegations at the
    subscription and at those resource groups.

    A subscription is read whole or not at all: a failed read of any of its lists, or an assignment
    whose definition is neither expanded nor listed, leaves it with no row. The failure is never
    written as an empty list. It is returned in Unread (one entry per scope of the subscription, as
    'lighthouseDelegations at <scope>'), in Causes (the message and the subscription), and written as
    ONE warning. A resource provider that is not registered does not fail a list: it answers an empty
    one (measured).

    The role names are read after every subscription, one request per distinct role GUID, at the
    subscription of the first row that carries it (api-version 2022-04-01, no paging). A role that
    does not exist (RoleDefinitionDoesNotExist, NotFound) leaves roleName null and is not unread; any
    other failure leaves roleName null wherever the role appears, adds 'lighthouseDelegations role
    <guid>' to Unread and a cause, and writes one warning.

    Assignments are deduplicated on their id (a blank id on scope and definition id), letter case
    ignored, and the rows are sorted by scope, managedByTenantId, offerName and
    registrationAssignmentId. ConvertTo-OERLighthouseDelegation owns the row. The function never writes
    an error record; it may write warnings.

    Returns one object, tagged Omnicit.EntraRBAC.InventoryLighthouseDelegation: Delegations (the sorted
    rows), Unread (string[]) and Causes (objects with Cause and Target).

    .PARAMETER Scope
    The ARM scopes to read, as Resolve-OERInventoryScopeTree returns them.

    .EXAMPLE
    Get-OERInventoryLighthouseDelegation -Scope '/subscriptions/11111111-1111-1111-1111-111111111111'
    Returns the delegations at that subscription and at its resource groups.
    #>
    [OutputType([PSCustomObject])]
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][AllowEmptyCollection()][string[]]$Scope
    )

    $AssignmentsPath = '/providers/Microsoft.ManagedServices/registrationAssignments?$expandRegistrationDefinition=true&api-version=2022-10-01'
    $DefinitionsPath = '/providers/Microsoft.ManagedServices/registrationDefinitions?api-version=2022-10-01'

    # 1. The scopes per subscription, in the order first named. A subscription id is compared without
    # regard to letter case; the state keeps the spelling of the first scope that named it.
    $Subscriptions = [System.Collections.Generic.Dictionary[string, object]]::new([System.StringComparer]::OrdinalIgnoreCase)
    $SubscriptionOrder = [System.Collections.Generic.List[object]]::new()
    foreach ($S in @($Scope)) {
        $Trimmed = $S.TrimEnd('/')
        $SubscriptionId = $null
        $GroupName = $null
        $IsWhole = $false
        if ($Trimmed -match '^/subscriptions/([^/]+)$') {
            $SubscriptionId = $Matches[1]
            $IsWhole = $true
        } elseif ($Trimmed -match '^/subscriptions/([^/]+)/resourceGroups/([^/]+)') {
            $SubscriptionId = $Matches[1]
            $GroupName = $Matches[2]
        } elseif ($Trimmed -match '^/subscriptions/([^/]+)/') {
            $SubscriptionId = $Matches[1]
        }
        if (-not $SubscriptionId) { continue }
        if (-not $Subscriptions.ContainsKey($SubscriptionId)) {
            $Subscriptions[$SubscriptionId] = [PSCustomObject]@{
                Id     = $SubscriptionId
                Whole  = $false
                Groups = [System.Collections.Generic.List[string]]::new()
                Scopes = [System.Collections.Generic.List[string]]::new()
            }
            $SubscriptionOrder.Add($Subscriptions[$SubscriptionId])
        }
        $State = $Subscriptions[$SubscriptionId]
        if ($IsWhole) { $State.Whole = $true }
        if ($GroupName -and -not ($State.Groups | Where-Object { $_ -eq $GroupName })) { $State.Groups.Add($GroupName) }
        # A scope named twice, in any letter case, is named once.
        if (-not ($State.Scopes | Where-Object { $_ -ieq $S })) { $State.Scopes.Add($S) }
    }

    $Rows = [System.Collections.Generic.List[object]]::new()
    $Unread = [System.Collections.Generic.List[string]]::new()
    $Causes = [System.Collections.Generic.List[object]]::new()

    # 2. Each subscription whole or not at all: its rows are collected in a local list and join the
    # result only when every read succeeded.
    foreach ($State in $SubscriptionOrder) {
        $SubscriptionScope = "/subscriptions/$($State.Id)"
        try {
            $Collected = [System.Collections.Generic.List[object]]::new()
            # Each read: the scope whose list returned the assignments, and the assignments.
            $Reads = [System.Collections.Generic.List[object]]::new()

            $FirstRead = Invoke-OERArmRequest -Path "$SubscriptionScope$AssignmentsPath" -All
            $FirstAssignments = @(@($FirstRead.value) | Where-Object { $null -ne $_ })
            $Reads.Add([PSCustomObject]@{ ReadAt = $SubscriptionScope; Assignments = $FirstAssignments })

            $DefinitionRead = Invoke-OERArmRequest -Path "$SubscriptionScope$DefinitionsPath" -All
            $Definitions = @(@($DefinitionRead.value) | Where-Object { $null -ne $_ })
            $DefinitionById = [System.Collections.Generic.Dictionary[string, object]]::new([System.StringComparer]::OrdinalIgnoreCase)
            foreach ($ListedDefinition in $Definitions) {
                if (-not [string]::IsNullOrWhiteSpace([string]$ListedDefinition.id)) { $DefinitionById[[string]$ListedDefinition.id] = $ListedDefinition }
            }

            if ($State.Whole) {
                # A definition no assignment of the subscription list names may have its assignment at
                # a resource group the list did not return.
                $Referenced = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
                foreach ($FirstAssignment in $FirstAssignments) {
                    $ReferencedId = [string]$FirstAssignment.properties.registrationDefinitionId
                    if (-not [string]::IsNullOrWhiteSpace($ReferencedId)) { [void]$Referenced.Add($ReferencedId) }
                }
                $Unreferenced = @($DefinitionById.Keys | Where-Object { -not $Referenced.Contains($_) })
                if ($Unreferenced.Count -gt 0) {
                    $GroupListing = Invoke-OERArmRequest -Path "$SubscriptionScope/resourcegroups?api-version=2025-04-01" -All
                    foreach ($Group in @(@($GroupListing.value) | Where-Object { $null -ne $_ })) {
                        $GroupScope = [string]$Group.id
                        # A resource group listed without its id cannot be read, and its delegations
                        # cannot be told from none: the subscription is unread, not silently short.
                        if ([string]::IsNullOrWhiteSpace($GroupScope)) { throw "A resource group of the subscription '$($State.Id)' was listed without an id, so its Azure Lighthouse delegations could not be read." }
                        $GroupRead = Invoke-OERArmRequest -Path "$GroupScope$AssignmentsPath" -All
                        $Reads.Add([PSCustomObject]@{ ReadAt = $GroupScope; Assignments = @(@($GroupRead.value) | Where-Object { $null -ne $_ }) })
                    }
                }
            } else {
                foreach ($GroupName in $State.Groups) {
                    $GroupScope = "$SubscriptionScope/resourceGroups/$GroupName"
                    $GroupRead = Invoke-OERArmRequest -Path "$GroupScope$AssignmentsPath" -All
                    $Reads.Add([PSCustomObject]@{ ReadAt = $GroupScope; Assignments = @(@($GroupRead.value) | Where-Object { $null -ne $_ }) })
                }
            }

            # An assignment found by several reads counts once.
            $Seen = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
            foreach ($Read in $Reads) {
                foreach ($Assignment in $Read.Assignments) {
                    $AssignmentDefinition = $null
                    $Inline = $Assignment.properties.registrationDefinition
                    if ($Inline -and $Inline.properties) {
                        $AssignmentDefinition = $Inline
                    } else {
                        $NamedId = [string]$Assignment.properties.registrationDefinitionId
                        if (-not [string]::IsNullOrWhiteSpace($NamedId) -and $DefinitionById.ContainsKey($NamedId)) { $AssignmentDefinition = $DefinitionById[$NamedId] }
                    }
                    if ($null -eq $AssignmentDefinition) {
                        throw "The registration definition of the registration assignment '$([string]$Assignment.id)' could not be read."
                    }
                    $Row = ConvertTo-OERLighthouseDelegation -Assignment $Assignment -Definition $AssignmentDefinition -ReadAt $Read.ReadAt
                    $Key = if (-not [string]::IsNullOrWhiteSpace([string]$Row.registrationAssignmentId)) {
                        [string]$Row.registrationAssignmentId
                    } else {
                        '{0}|{1}' -f $Row.scope, $Row.registrationDefinitionId
                    }
                    if ($Seen.Add($Key)) { $Collected.Add([PSCustomObject]@{ Row = $Row; SubscriptionId = $State.Id }) }
                }
            }

            # A subscription named only through a scope below it keeps the delegations at the
            # subscription and at the resource groups it names, and nothing else it was handed.
            if (-not $State.Whole) {
                $Kept = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
                [void]$Kept.Add($SubscriptionScope)
                foreach ($KeptGroup in $State.Groups) { [void]$Kept.Add("$SubscriptionScope/resourceGroups/$KeptGroup") }
                $Collected = [System.Collections.Generic.List[object]]::new([object[]]@($Collected | Where-Object { $Kept.Contains([string]$_.Row.scope) }))
            }
            foreach ($Item in $Collected) { $Rows.Add($Item) }
        } catch {
            Remove-OERErrorRecord -Record $PSItem
            $Message = $PSItem.Exception.Message
            foreach ($OriginalScope in $State.Scopes) { $Unread.Add("lighthouseDelegations at $OriginalScope") }
            $Causes.Add([PSCustomObject]@{ Cause = $Message; Target = $SubscriptionScope })
            Write-Warning "Could not read the Azure Lighthouse delegations at scope '$($State.Scopes -join ', ')', so lighthouseDelegations.json holds none of them: $Message"
        }
    }

    # 3. The role names, one read per distinct role GUID, at the subscription of the first row that
    # carries it. The last segment of roleDefinitionId, lower-cased; anything that is not a GUID is
    # left alone.
    $RoleSubscription = [ordered]@{}
    foreach ($Item in $Rows) {
        foreach ($Authorization in @(@($Item.Row.authorizations) + @($Item.Row.eligibleAuthorizations))) {
            if ($null -eq $Authorization -or [string]::IsNullOrWhiteSpace([string]$Authorization.roleDefinitionId)) { continue }
            $RoleGuid = ([string]$Authorization.roleDefinitionId -split '/')[-1].ToLowerInvariant()
            if ((Test-OERGuid -Value $RoleGuid) -and -not $RoleSubscription.Contains($RoleGuid)) {
                $RoleSubscription[$RoleGuid] = if (-not [string]::IsNullOrWhiteSpace([string]$Item.Row.subscriptionId)) { [string]$Item.Row.subscriptionId } else { $Item.SubscriptionId }
            }
        }
    }
    $RoleName = @{}
    foreach ($RoleGuid in $RoleSubscription.Keys) {
        try {
            $RoleDefinition = Invoke-OERArmRequest -Path "/subscriptions/$($RoleSubscription[$RoleGuid])/providers/Microsoft.Authorization/roleDefinitions/$($RoleGuid)?api-version=2022-04-01"
            $Name = [string]$RoleDefinition.properties.roleName
            if (-not [string]::IsNullOrWhiteSpace($Name)) { $RoleName[$RoleGuid] = $Name }
        } catch {
            Remove-OERErrorRecord -Record $PSItem
            # A role that does not exist is a fact about the role, not a failed read.
            if ($PSItem.FullyQualifiedErrorId -like 'RoleDefinitionDoesNotExist*' -or $PSItem.FullyQualifiedErrorId -like 'NotFound*') { continue }
            $Message = $PSItem.Exception.Message
            $Unread.Add("lighthouseDelegations role $RoleGuid")
            $Causes.Add([PSCustomObject]@{ Cause = $Message; Target = $RoleGuid })
            Write-Warning "Could not read the name of the role '$RoleGuid' for lighthouseDelegations.json, so roleName is null where it appears: $Message"
        }
    }
    foreach ($Item in $Rows) {
        foreach ($Authorization in @(@($Item.Row.authorizations) + @($Item.Row.eligibleAuthorizations))) {
            if ($null -eq $Authorization -or [string]::IsNullOrWhiteSpace([string]$Authorization.roleDefinitionId)) { continue }
            $RoleGuid = ([string]$Authorization.roleDefinitionId -split '/')[-1].ToLowerInvariant()
            if ($RoleName.ContainsKey($RoleGuid)) { $Authorization.roleName = $RoleName[$RoleGuid] }
        }
    }

    # 4. Sorted, as the file lists them.
    $Sorted = @($Rows | ForEach-Object { $_.Row } | Sort-Object -Property scope, managedByTenantId, offerName, registrationAssignmentId)
    $Out = [PSCustomObject]@{ Delegations = $Sorted; Unread = $Unread.ToArray(); Causes = $Causes.ToArray() }
    $Out.PSObject.TypeNames.Insert(0, 'Omnicit.EntraRBAC.InventoryLighthouseDelegation')
    $Out
}
