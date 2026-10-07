function Send-OERPimRulePatch {
    <#
    .SYNOPSIS
    Sends a Microsoft Graph PIM rule set one PATCH per rule, and puts back the accepted half of the
    MFA / authentication-context pair when the other half is rejected.

    .DESCRIPTION
    The single owner of sending a Microsoft Graph PIM role management policy rule set, used by
    Set-OERGroupPimPolicy (PIM for Groups) and Set-OERDirectoryRoleManagementPolicy (Microsoft
    Entra directory roles). Each rule in -Rule is PATCHed on its own, in the order given, to
    -RulesPath followed by a slash and the rule id. A rule Microsoft Graph rejects does not stop the
    rules after it: its id is listed in Failed and a message is returned for it.

    The caller has already passed ShouldProcess for every rule it hands in, and has ordered them with
    Get-OERPimRulePatchOrder, which owns the order the authentication-context rule and the
    activation enablement rule must be sent in. This helper therefore asks for no confirmation.

    The authentication-context rule (AuthenticationContext_EndUser_Assignment) and the activation
    enablement rule (Enablement_EndUser_Assignment) together decide whether activation requires
    multi-factor authentication or an authentication context, so when both are sent they are
    applied together or not at all. Should Microsoft Graph accept the first of the two (in -Rule
    order) and reject the second, the first is PATCHed straight back, directly after the rejected
    PATCH, to its live version from -LiveRule: left half-applied, the pair can leave activation with
    neither control. The live version is sent as a new hashtable made by a JSON round trip, without
    its read-only '@odata.context' key. When -LiveRule holds no live version of the first rule,
    nothing is sent and the put-back is reported as failed. A rejected FIRST half needs nothing: the
    second was then validated against an unchanged policy.

    The helper writes no warning, error or host output. It returns its messages instead, in the
    order they arose, so the caller writes them only after the last PATCH and the put-back were
    sent: a caller running with -WarningAction Stop, or $WarningPreference set to Stop, can never be
    stopped half-way through the rule set or between a rejected rule and its put-back.

    Returns exactly one object with Accepted (the accepted rule ids, without a rule that was put
    back), Failed (the rejected rule ids), Restored (the rule id put back, or $null), RestoreError
    (why the put-back failed, or $null), PairFirst and PairSecond (the pair in -Rule order, or $null
    when -Rule does not hold both) and Warning (the messages).

    .PARAMETER Rule
    The confirmed rules, already in patch order. Each carries its id. A dictionary is sent as it is;
    any other rule (a PSCustomObject clone, for example) is converted to a hashtable with a JSON
    round trip first.

    .PARAMETER RulesPath
    The policy's rules collection path, for example the PIM for Groups path that
    Get-OERPimGroupsGraphPath returns or a v1.0 directory role policy path. Each rule is sent to this
    path followed by a slash and its id.

    .PARAMETER LiveRule
    The live rule versions available for the put-back, matched on their id. Only the first rule of
    the pair is ever read from it. May be empty or $null.

    .PARAMETER PolicyLabel
    Names the policy in the returned messages, for example "PIM policy 'p1'".

    .EXAMPLE
    $SendResult = Send-OERPimRulePatch -Rule $ToSend -RulesPath $RulesPath -LiveRule $LiveRules -PolicyLabel "PIM policy '$PolicyId'"
    foreach ($Message in $SendResult.Warning) { Write-Warning $Message }

    Sends every confirmed rule, puts back the accepted half of a half-rejected pair, and then writes
    the messages once every request has been sent.
    #>
    [OutputType([PSCustomObject])]
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [object[]]$Rule,

        [Parameter(Mandatory)]
        [string]$RulesPath,

        [AllowNull()]
        [AllowEmptyCollection()]
        [object[]]$LiveRule,

        [Parameter(Mandatory)]
        [string]$PolicyLabel
    )

    # The pair is complete only when both rules are sent; the first of them in -Rule order is the
    # one that may have to be put back.
    $PairRuleIds = @('AuthenticationContext_EndUser_Assignment', 'Enablement_EndUser_Assignment')
    $PairIds = @(foreach ($Item in $Rule) { if ([string]$Item.id -in $PairRuleIds) { [string]$Item.id } })
    $PairFirst = $null
    $PairSecond = $null
    if ($PairIds.Count -eq 2 -and $PairIds[0] -ne $PairIds[1]) {
        $PairFirst = $PairIds[0]
        $PairSecond = $PairIds[1]
    }

    $LiveById = @{}
    foreach ($Live in @($LiveRule)) {
        if ($null -ne $Live -and $Live.id) { $LiveById[[string]$Live.id] = $Live }
    }

    $Accepted = [System.Collections.Generic.List[string]]::new()
    $Failed = [System.Collections.Generic.List[string]]::new()
    $Warning = [System.Collections.Generic.List[string]]::new()
    $Restored = $null
    $RestoreError = $null

    foreach ($Item in $Rule) {
        $RuleId = [string]$Item.id
        # Invoke-OERGraphRequest takes a [hashtable] body. A builder's dictionary goes as it is; a
        # PSCustomObject clone is converted with a JSON round trip (the idiom
        # Enable-OERGroupPermanentEligibility uses for a single-rule PATCH).
        $Body = if ($Item -is [System.Collections.IDictionary]) { $Item } else { $Item | ConvertTo-Json -Depth 100 | ConvertFrom-Json -AsHashtable }
        try {
            Invoke-OERGraphRequest -Method PATCH -Uri ('{0}/{1}' -f $RulesPath, $RuleId) -Body $Body | Out-Null
            $Accepted.Add($RuleId)
        } catch {
            Remove-OERErrorRecord -Record $PSItem
            $Failed.Add($RuleId)
            $Warning.Add("Rule '$RuleId' of $PolicyLabel was not applied: $($PSItem.Exception.Message)")
        }

        if ($PairSecond -and $RuleId -eq $PairSecond -and $Failed.Contains($RuleId) -and $Accepted.Contains($PairFirst)) {
            if ($LiveById.ContainsKey($PairFirst)) {
                # Always a new hashtable, so the caller's live rule is left as it was read; the
                # '@odata.context' key a single-rule read carries is read-only and is not sent.
                $LiveBody = $LiveById[$PairFirst] | ConvertTo-Json -Depth 100 | ConvertFrom-Json -AsHashtable
                $LiveBody.Remove('@odata.context')
                try {
                    Invoke-OERGraphRequest -Method PATCH -Uri ('{0}/{1}' -f $RulesPath, $PairFirst) -Body $LiveBody | Out-Null
                    [void]$Accepted.Remove($PairFirst)
                    $Restored = $PairFirst
                } catch {
                    Remove-OERErrorRecord -Record $PSItem
                    $RestoreError = $PSItem.Exception.Message
                }
            } else {
                $RestoreError = 'its value before this call was not read'
            }
            if ($RestoreError) {
                $Warning.Add("Rule '$PairFirst' of $PolicyLabel could not be put back to its value before this call: $RestoreError")
            }
        }
    }

    [PSCustomObject]@{
        Accepted     = [string[]]$Accepted.ToArray()
        Failed       = [string[]]$Failed.ToArray()
        Restored     = $Restored
        RestoreError = $RestoreError
        PairFirst    = $PairFirst
        PairSecond   = $PairSecond
        Warning      = [string[]]$Warning.ToArray()
    }
}
