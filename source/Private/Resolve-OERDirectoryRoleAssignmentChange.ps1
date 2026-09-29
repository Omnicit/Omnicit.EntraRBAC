function Resolve-OERDirectoryRoleAssignmentChange {
    <#
    .SYNOPSIS
    Computes whether a declared directoryRoleAssignments[] entry differs from the live directory role
    eligibility or assignment schedule.

    .DESCRIPTION
    Pure, tenant-free diff used by the directory role assignment Sync handler so the apply document --
    not the tenant -- is the source of truth for a directory role assignment's window. Before this
    helper a handler could only match on role/principal/assignmentType, so a changed durationDays or a
    permanent-vs-time-bound switch would be silently reported Unchanged. It resolves the declared
    window (durationDays present and not null means time-bound, absent or explicit null means
    permanent, decided through Test-OERDeclaredProperty) and compares that intent against the current
    schedule via Resolve-OEREligibilityDuration. A null Current means the assignment is absent and
    everything is considered changed. No Graph, ARM, or authentication occurs.

    .PARAMETER Declared
    One directoryRoleAssignments[] entry from the apply document. Recognized field: durationDays, whose
    absence or explicit null declares a permanent assignment.

    .PARAMETER Current
    The matching live schedule -- one object Select-OERManagedDirectoryRoleAssignment kept, carrying
    StartDateTime and EndDateTime -- or null when the declared role/principal/assignmentType pair has
    no live assignment yet.

    .EXAMPLE
    Resolve-OERDirectoryRoleAssignmentChange -Declared $Entry -Current $Live
    Returns a change object whose Changed flag is false when the live window already matches the
    declared duration.

    .EXAMPLE
    Resolve-OERDirectoryRoleAssignmentChange -Declared ([PSCustomObject]@{ durationDays = 30 }) -Current $null
    Returns Changed = true with Reason Absent because no current assignment was supplied.
    #>
    [OutputType([PSCustomObject])]
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][AllowNull()][PSCustomObject]$Declared,
        [object]$Current
    )

    # Test-OERDeclaredProperty, never an inline PSObject.Properties.Name chain: $Declared is an
    # apply-document node (one directoryRoleAssignments[] entry), so the declared-value rule governs
    # it (CLAUDE.md ## Code Style; docs/development/rationale.md#declared-property). An explicit JSON
    # null for durationDays counts as NOT declared, the same outcome as an omitted key, which is why
    # the predicate is used rather than a bare PSObject.Properties.Name -icontains check plus a
    # separate null test.
    $DeclaredDays = $null
    if (Test-OERDeclaredProperty -Node $Declared -Name 'durationDays') {
        $DeclaredDays = [int]$Declared.durationDays
    }
    $Permanent = $null -eq $DeclaredDays

    $Changed = $false
    $Reason  = 'None'
    $Detail  = 'assignment matches'

    if ($null -eq $Current) {
        $Changed = $true
        $Reason  = 'Absent'
        $Detail  = $(if ($Permanent) { 'permanent assignment is absent' }
                     else { "time-bound assignment ($DeclaredDays days) is absent" })
    }
    else {
        $CurrentDays = Resolve-OEREligibilityDuration -StartDateTime $Current.StartDateTime -EndDateTime $Current.EndDateTime
        if (($null -eq $DeclaredDays) -ne ($null -eq $CurrentDays)) {
            $Changed = $true
            $Reason  = 'PermanenceChanged'
            $DeclaredText = $(if ($null -eq $DeclaredDays) { 'permanent' } else { "$DeclaredDays days" })
            $CurrentText  = $(if ($null -eq $CurrentDays)  { 'permanent' } else { "$CurrentDays days" })
            $Detail = "window differs (live $CurrentText, declared $DeclaredText)"
        }
        elseif ($null -ne $DeclaredDays -and [int]$DeclaredDays -ne [int]$CurrentDays) {
            $Changed = $true
            $Reason  = 'DurationChanged'
            $Detail  = "duration differs (live $CurrentDays days, declared $DeclaredDays days)"
        }
    }

    $Out = [PSCustomObject]@{
        Changed      = $Changed
        Reason       = $Reason
        DurationDays = $DeclaredDays
        Permanent    = $Permanent
        Detail       = $Detail
    }
    $Out.PSObject.TypeNames.Insert(0, 'Omnicit.EntraRBAC.DirectoryRoleAssignmentChange')
    $Out
}
