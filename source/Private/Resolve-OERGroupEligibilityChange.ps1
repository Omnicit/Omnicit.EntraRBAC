function Resolve-OERGroupEligibilityChange {
    <#
    .SYNOPSIS
    Computes whether a declared groups[].eligibility[] entry differs from the live PIM-for-groups
    eligibility schedule instance.

    .DESCRIPTION
    Pure, tenant-free diff used by the Invoke-OERStructure group handler so the apply document -- not
    the tenant -- is the source of truth for an eligibility. Before this helper the handler matched on
    principal id alone, so a changed durationDays or a member/owner switch was silently reported
    Unchanged. It resolves the declared access type (defaulting to member), resolves the declared
    window (durationDays present means time-bound, absent means permanent), and compares that intent
    against the current schedule instance via Resolve-OEREligibilityDuration. A null Current means the
    eligibility is absent and everything is considered changed. No Graph, ARM, or authentication occurs.

    .PARAMETER Declared
    One eligibility entry from the apply document. Recognized fields: principal (required by the
    caller, not read here), accessType (member or owner, defaulting to member), and durationDays whose
    absence declares a permanent eligibility.

    .PARAMETER Current
    The matching live privilegedAccessGroupEligibilityScheduleInstance (raw Graph hashtable or
    PSObject with startDateTime and endDateTime), or null when the principal has no eligibility of the
    declared access type yet.

    .EXAMPLE
    Resolve-OERGroupEligibilityChange -Declared $Entry -Current $Instance
    Returns a change object whose Changed flag is false when the live window already matches the
    declared duration and access type.

    .EXAMPLE
    Resolve-OERGroupEligibilityChange -Declared ([PSCustomObject]@{ principal = 'person17@example.com'; accessType = 'owner' })
    Returns Changed = true with Reason Absent because no current instance was supplied.
    #>
    [OutputType([PSCustomObject])]
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][AllowNull()][PSCustomObject]$Declared,
        [object]$Current
    )

    # Test-OERDeclaredProperty, never an inline PSObject.Properties.Name chain: $Declared is an
    # apply-document node (one groups[].eligibility[] entry), so the declared-value rule governs it
    # (CLAUDE.md ## Code Style; docs/development/rationale.md#declared-property). The truthiness
    # clause stays: a declared-but-EMPTY accessType is not a valid access type and must still fall
    # back to 'member', which the predicate alone would not do (it counts '' as declared).
    $AccessType = 'member'
    if ((Test-OERDeclaredProperty -Node $Declared -Name 'accessType') -and $Declared.accessType) {
        $AccessType = [string]$Declared.accessType
    }

    $DeclaredDays = $null
    if (Test-OERDeclaredProperty -Node $Declared -Name 'durationDays') {
        $DeclaredDays = [int]$Declared.durationDays
    }

    $Changed = $false
    $Reason  = 'None'
    $Detail  = 'eligibility matches'

    if ($null -eq $Current) {
        $Changed = $true
        $Reason  = 'Absent'
        $Detail  = $(if ($null -eq $DeclaredDays) { "permanent $AccessType eligibility is absent" }
                     else { "time-bound $AccessType eligibility ($DeclaredDays days) is absent" })
    }
    else {
        $CurrentDays = Resolve-OEREligibilityDuration -StartDateTime $Current.startDateTime -EndDateTime $Current.endDateTime
        if (($null -eq $DeclaredDays) -ne ($null -eq $CurrentDays)) {
            $Changed = $true
            $Reason  = 'PermanenceChanged'
            $DeclaredText = $(if ($null -eq $DeclaredDays) { 'permanent' } else { "$DeclaredDays days" })
            $CurrentText  = $(if ($null -eq $CurrentDays)  { 'permanent' } else { "$CurrentDays days" })
            $Detail = "$AccessType eligibility window differs (live $CurrentText, declared $DeclaredText)"
        }
        elseif ($null -ne $DeclaredDays -and [int]$DeclaredDays -ne [int]$CurrentDays) {
            $Changed = $true
            $Reason  = 'DurationChanged'
            $Detail  = "$AccessType eligibility duration differs (live $CurrentDays days, declared $DeclaredDays days)"
        }
    }

    $Out = [PSCustomObject]@{
        Changed      = $Changed
        Reason       = $Reason
        AccessType   = $AccessType
        DurationDays = $DeclaredDays
        Detail       = $Detail
    }
    $Out.PSObject.TypeNames.Insert(0, 'Omnicit.EntraRBAC.GroupEligibilityChange')
    $Out
}
