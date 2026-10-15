function Get-OERSubscriptionHomeTenant {
    <#
    .SYNOPSIS
    Decides whether a subscription belongs to the tenant the session's Microsoft Graph token was issued
    for.

    .DESCRIPTION
    The single owner of decision A19 (BL-150): whether the Azure subscription a scope lies in, or a
    subscription the subscription list returned, belongs to the tenant the module's session works in.
    The export's Azure walk enters only such a subscription, and Invoke-OERStructure reads and writes a
    role assignment or a role management policy only at a scope in one.

    The subscription's home tenant is read from the tenantId field Azure Resource Manager returns for
    it (Subscriptions - Get and Subscriptions - List, api-version 2022-12-01, documented as "The
    subscription tenant ID"; measured live 2026-10-15: present, a GUID). The REST answer has no
    homeTenantId field; Az PowerShell calls the same value HomeTenantId. The session's tenant is the
    tenant the session's Microsoft Graph token was issued for, read through Get-OERInventoryTenantId
    (TokenTenantId when it is a canonical GUID, nothing otherwise). The two are compared without regard
    to letter case, and only when both are canonical GUIDs (Test-OERGuid).

    It returns one object with four possible verdicts:
    - NoSubscription: the scope lies in no subscription (a management group or the root scope '/'),
      so there is nothing to decide. No request is sent.
    - Home: the subscription's tenantId is the session's tenant.
    - Foreign: the subscription's tenantId is another tenant, for example a customer subscription
      another tenant delegated to this one through Azure Lighthouse.
    - Undecided: the home tenant could not be decided -- the scope could not be resolved, the read of
      the subscription failed, the subscription gave no tenantId that is a GUID, or the session holds no
      Graph token whose tenant ID is a GUID.
    A Foreign verdict, and an Undecided one, carries a Reason and an ErrorRecord: the record of the
    resolution or the read that failed, as itself, or otherwise a new record with the ErrorId
    SubscriptionTenantMismatch (category InvalidOperation, target the scope as given) whose message
    names the scope and the reason.

    -Scope takes a scope in the structure document's syntax. It is parsed by ConvertTo-OERScopeSplat:
    an 'mg:' form is NoSubscription with no request and no resolution; any other form is resolved by
    Resolve-OERScope (a subscription named by its display name costs one read of the subscription list)
    and made canonical by ConvertTo-OERCanonicalScope. A resolved scope outside '/subscriptions/<id>'
    -- a management group path, or the root scope '/' -- is NoSubscription with no request. A scope
    inside one is compared after one GET of that subscription; with no session tenant nothing is read
    and the verdict is Undecided. -Cache holds what one read of a subscription gave, keyed on its id in
    lower case, failures included, so a subscription is read at most once per cache however its id is
    written; without -Cache every call reads.

    -Subscription takes an object Get-OERSubscription returns (SubscriptionId, ResourceId,
    DisplayName, TenantId) and decides on its TenantId. It reads nothing.

    It never writes an error record and never throws for a scope it cannot decide: the caller decides
    what an Undecided or Foreign verdict means for it.

    .PARAMETER Scope
    A scope as a structure document writes it: an Azure Resource Manager path, 'sub:<id or name>',
    'subscription:<id or name>' or 'mg:<name>'.

    .PARAMETER Cache
    A dictionary the caller keeps for one run (Invoke-OERStructure keeps one per document). The facts
    one read of a subscription gave -- a failed read included -- are stored under the subscription id
    in lower case and reused, so the subscription is read once per cache.

    .PARAMETER Subscription
    A subscription object as Get-OERSubscription returns it. Its TenantId is the home tenant compared;
    nothing is read.

    .EXAMPLE
    $Verdict = Get-OERSubscriptionHomeTenant -Scope '/subscriptions/aaaa1111-0000-0000-0000-000000000001/resourceGroups/rg1' -Cache $Cache

    Reads the subscription once for this cache, and returns Home when its tenantId is the tenant the
    session's Microsoft Graph token was issued for, Foreign when it is another tenant, and Undecided
    when it cannot be told.

    .EXAMPLE
    Get-OERSubscription | ForEach-Object { Get-OERSubscriptionHomeTenant -Subscription $_ }

    Decides each listed subscription from the tenantId the list returned, with no request of its own.
    #>
    [OutputType([PSCustomObject])]
    [CmdletBinding(DefaultParameterSetName = 'Scope')]
    param(
        [Parameter(Mandatory, ParameterSetName = 'Scope')]
        [AllowEmptyString()]
        [string]$Scope,

        [Parameter(ParameterSetName = 'Scope')]
        [System.Collections.IDictionary]$Cache,

        [Parameter(Mandatory, ParameterSetName = 'Listed')]
        [object]$Subscription
    )

    # The SubscriptionTenantMismatch record, built here and nowhere else in this function. The scope and
    # the reason are arguments of -f, never part of the format string, so a brace in either is text.
    function Get-SubscriptionTenantMismatchRecord {
        param([string]$ScopeText, [string]$Reason)
        [System.Management.Automation.ErrorRecord]::new(
            [System.Exception]::new((("Scope '{0}' was refused: {1}. Omnicit.EntraRBAC reads and writes a role assignment or a role management policy only in a subscription it can show to belong to the tenant the session's Microsoft Graph token was issued for -- not in one another tenant delegated to it, for example through Azure Lighthouse -- so none was read or written at that scope. Sign in to the subscription's home tenant to manage it there.") -f $ScopeText, $Reason)),
            'SubscriptionTenantMismatch',
            [System.Management.Automation.ErrorCategory]::InvalidOperation,
            $ScopeText)
    }

    # The one output shape, its properties in this order.
    function Get-HomeTenantVerdict {
        param($VerdictScope, $SubscriptionId, $DisplayName, [string]$Verdict, $HomeTenantId, $SessionTenantId, $Reason, $ErrorRecord)
        [PSCustomObject]@{
            Scope           = $VerdictScope
            SubscriptionId  = $SubscriptionId
            DisplayName     = $DisplayName
            Verdict         = $Verdict
            HomeTenantId    = $HomeTenantId
            SessionTenantId = $SessionTenantId
            Reason          = $Reason
            ErrorRecord     = $ErrorRecord
        }
    }

    # The tenant the session's Graph token was issued for, or $null. Reads the module's state only.
    $SessionTenantId = Get-OERInventoryTenantId
    if ([string]::IsNullOrEmpty([string]$SessionTenantId)) { $SessionTenantId = $null }

    if ($PSCmdlet.ParameterSetName -eq 'Listed') {
        $SubscriptionId = [string]$Subscription.SubscriptionId
        $ScopeText = [string]$Subscription.ResourceId
        if ([string]::IsNullOrWhiteSpace($ScopeText)) { $ScopeText = "/subscriptions/$SubscriptionId" }
        if ([string]::IsNullOrEmpty($SubscriptionId)) { $SubscriptionId = $null }
        $VerdictScope = $ScopeText
        $Facts = @{ Read = $true; TenantId = [string]$Subscription.TenantId; DisplayName = [string]$Subscription.DisplayName; ErrorRecord = $null }
    } else {
        $ScopeText = $Scope
        # 1. A management group named in the document's syntax lies in no subscription: nothing is resolved
        # or read for it.
        $Splat = ConvertTo-OERScopeSplat -Scope $Scope
        if ($Splat.ContainsKey('ManagementGroup')) {
            return Get-HomeTenantVerdict -VerdictScope $null -SubscriptionId $null -DisplayName $null -Verdict 'NoSubscription' `
                -HomeTenantId $null -SessionTenantId $SessionTenantId -Reason $null -ErrorRecord $null
        }
        # 2. Any other form is resolved to an Azure Resource Manager scope. A resolution that fails is
        # Undecided, with the resolver's own record.
        try {
            $Resolved = ConvertTo-OERCanonicalScope -Scope (Resolve-OERScope @Splat)
        } catch {
            Remove-OERErrorRecord -Record $PSItem
            return Get-HomeTenantVerdict -VerdictScope $null -SubscriptionId $null -DisplayName $null -Verdict 'Undecided' `
                -HomeTenantId $null -SessionTenantId $SessionTenantId `
                -Reason "scope '$Scope' could not be resolved: $($PSItem.Exception.Message)" -ErrorRecord $PSItem
        }
        # 3. A scope outside '/subscriptions/<id>' (a management group path, or the root scope '/') lies in
        # no subscription. The match ignores letter case, as Azure Resource Manager does.
        if ($Resolved -notmatch '^/subscriptions/([^/]+)(?:/|$)') {
            return Get-HomeTenantVerdict -VerdictScope $Resolved -SubscriptionId $null -DisplayName $null -Verdict 'NoSubscription' `
                -HomeTenantId $null -SessionTenantId $SessionTenantId -Reason $null -ErrorRecord $null
        }
        $SubscriptionId = $Matches[1]
        $VerdictScope = $Resolved
        $Facts = $null
    }

    # 4. With no session tenant there is nothing to compare with, so nothing is read.
    if ($null -eq $SessionTenantId) {
        $NoSessionReason = "the session holds no Microsoft Graph token whose tenant ID subscription '$SubscriptionId' could be compared with"
        return Get-HomeTenantVerdict -VerdictScope $VerdictScope -SubscriptionId $SubscriptionId -DisplayName $null -Verdict 'Undecided' `
            -HomeTenantId $null -SessionTenantId $null -Reason $NoSessionReason `
            -ErrorRecord (Get-SubscriptionTenantMismatchRecord -ScopeText $ScopeText -Reason $NoSessionReason)
    }

    # 5. The read, once per cache: a failed read is stored too, since the check is made once per
    # subscription and run.
    if ($null -eq $Facts) {
        $CacheKey = $SubscriptionId.ToLowerInvariant()
        if ($null -ne $Cache -and $null -ne $Cache[$CacheKey]) {
            $Facts = $Cache[$CacheKey]
        } else {
            try {
                $Response = Invoke-OERArmRequest -Path "/subscriptions/$([uri]::EscapeDataString($SubscriptionId))?api-version=2022-12-01"
                $Facts = @{ Read = $true; TenantId = [string]$Response.tenantId; DisplayName = [string]$Response.displayName; ErrorRecord = $null }
            } catch {
                Remove-OERErrorRecord -Record $PSItem
                $Facts = @{ Read = $false; TenantId = $null; DisplayName = $null; ErrorRecord = $PSItem }
            }
            if ($null -ne $Cache) { $Cache[$CacheKey] = $Facts }
        }
    }

    # 6. The decision, the same for a scope and for a listed subscription.
    $DisplayName = [string]$Facts.DisplayName
    if ([string]::IsNullOrWhiteSpace($DisplayName)) { $DisplayName = $null }
    if (-not $Facts.Read) {
        return Get-HomeTenantVerdict -VerdictScope $VerdictScope -SubscriptionId $SubscriptionId -DisplayName $null -Verdict 'Undecided' `
            -HomeTenantId $null -SessionTenantId $SessionTenantId `
            -Reason "the read of subscription '$SubscriptionId' failed: $($Facts.ErrorRecord.Exception.Message)" -ErrorRecord $Facts.ErrorRecord
    }
    $TenantId = [string]$Facts.TenantId
    if (-not (Test-OERGuid -Value $TenantId)) {
        $NoFieldReason = "Azure Resource Manager gave no home tenant (tenantId) for subscription '$SubscriptionId'"
        return Get-HomeTenantVerdict -VerdictScope $VerdictScope -SubscriptionId $SubscriptionId -DisplayName $DisplayName -Verdict 'Undecided' `
            -HomeTenantId $null -SessionTenantId $SessionTenantId -Reason $NoFieldReason `
            -ErrorRecord (Get-SubscriptionTenantMismatchRecord -ScopeText $ScopeText -Reason $NoFieldReason)
    }
    if ($TenantId -eq $SessionTenantId) {
        return Get-HomeTenantVerdict -VerdictScope $VerdictScope -SubscriptionId $SubscriptionId -DisplayName $DisplayName -Verdict 'Home' `
            -HomeTenantId $TenantId -SessionTenantId $SessionTenantId -Reason $null -ErrorRecord $null
    }
    $ForeignReason = "subscription '$SubscriptionId' belongs to tenant '$TenantId', not to tenant '$SessionTenantId', the tenant the session's Microsoft Graph token was issued for"
    Get-HomeTenantVerdict -VerdictScope $VerdictScope -SubscriptionId $SubscriptionId -DisplayName $DisplayName -Verdict 'Foreign' `
        -HomeTenantId $TenantId -SessionTenantId $SessionTenantId -Reason $ForeignReason `
        -ErrorRecord (Get-SubscriptionTenantMismatchRecord -ScopeText $ScopeText -Reason $ForeignReason)
}
