function Resolve-OERAssignmentPolicyChange {
    <#
    .SYNOPSIS
    Reports whether the declared fields of an access package assignment policy differ between a desired
    and a current projection.

    .DESCRIPTION
    Pure, tenant-free diff used by the Invoke-OERStructure assignment-policy handler to decide Unchanged
    versus Updated. Both inputs are Omnicit.EntraRBAC.AssignmentPolicy projections as produced by
    ConvertTo-OERAssignmentPolicy (the desired side is the projection of a freshly built body, the current
    side the projection of the live policy), so the comparison is symmetric and order-insensitive. Only
    the keys listed in -DeclaredFields are compared; any field omitted from -DeclaredFields is left
    untouched (it never contributes to the result). Scalars compare with a typed -ne; identity lists
    (requestor users/groups and per-stage approver sets) compare as case-insensitive, order-insensitive
    sets with null lists treated as empty; expiration is compared as a single unit (its kind plus value)
    so a days-versus-hours or none-versus-set change is one difference rather than three; approval stages
    compare positionally with a per-stage scalar and approver-set diff. Returns a plain control object
    with a Differs flag and a ChangedFields list of the declared field names that differ. No Graph, ARM,
    or authentication occurs.

    .PARAMETER Desired
    The desired assignment policy projection (an Omnicit.EntraRBAC.AssignmentPolicy from
    ConvertTo-OERAssignmentPolicy, typically built from the declared apply-document block) to compare
    against the current state.

    .PARAMETER Current
    The current assignment policy projection (an Omnicit.EntraRBAC.AssignmentPolicy from
    ConvertTo-OERAssignmentPolicy of the live policy) that the desired projection is compared with.

    .PARAMETER DeclaredFields
    The lowercase names of the policy fields the caller actually declared and therefore wants compared;
    any field not in this list is ignored. Valid keys are description, requestorScope, requestorSettings,
    requireApproval, requireRequestorJustification, requireApprovalForUpdate, approvalStages, expiration,
    and notificationsDisabled.

    .EXAMPLE
    Resolve-OERAssignmentPolicyChange -Desired $Built -Current $Live -DeclaredFields @('description','expiration')
    Returns Differs = $true with ChangedFields = @('expiration') when only the expiration was declared and
    it changed, leaving every other policy attribute untouched.
    #>
    [OutputType([PSCustomObject])]
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][PSCustomObject]$Desired,
        [Parameter(Mandatory)][PSCustomObject]$Current,
        [Parameter(Mandatory)][AllowEmptyCollection()][string[]]$DeclaredFields
    )

    $Changed = [System.Collections.Generic.List[string]]::new()
    $Fields = @($DeclaredFields | ForEach-Object { [string]$_ })

    function Test-FieldDeclared {
        param([string]$Name)
        foreach ($F in $Fields) { if ($F -ieq $Name) { return $true } }
        return $false
    }

    # Case- and order-insensitive set equality over two id lists; null is treated as empty.
    function Test-SetEqual {
        param([object]$A, [object]$B)
        $LA = @($A | ForEach-Object { [string]$_ } | Where-Object { $_ } | ForEach-Object { $_.ToLowerInvariant() } | Sort-Object)
        $LB = @($B | ForEach-Object { [string]$_ } | Where-Object { $_ } | ForEach-Object { $_.ToLowerInvariant() } | Sort-Object)
        if ($LA.Count -ne $LB.Count) { return $false }
        for ($I = 0; $I -lt $LA.Count; $I++) { if ($LA[$I] -ne $LB[$I]) { return $false } }
        return $true
    }

    # Reduce (DurationInDays, DurationInHours, ExpirationDateTime) to a single kind+value tuple.
    function Get-ExpirationUnit {
        param([PSCustomObject]$Projection)
        if ($null -ne $Projection.DurationInDays) { return @{ Kind = 'days'; Value = [int]$Projection.DurationInDays } }
        if ($null -ne $Projection.DurationInHours) { return @{ Kind = 'hours'; Value = [int]$Projection.DurationInHours } }
        if (-not [string]::IsNullOrEmpty([string]$Projection.ExpirationDateTime)) {
            $Dto = [datetimeoffset]::MinValue
            if ([datetimeoffset]::TryParse([string]$Projection.ExpirationDateTime, [ref]$Dto)) {
                return @{ Kind = 'date'; Value = $Dto.ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ') }
            }
            return @{ Kind = 'date'; Value = [string]$Projection.ExpirationDateTime }
        }
        return @{ Kind = 'none'; Value = $null }
    }

    # -- description (string) ----------------------------------------------------------------
    if (Test-FieldDeclared 'description') {
        if ([string]$Desired.Description -ne [string]$Current.Description) { $Changed.Add('description') }
    }

    # -- simple boolean toggles --------------------------------------------------------------
    $BoolFields = @(
        @{ Name = 'requireApproval'; Prop = 'RequireApproval' }
        @{ Name = 'requireRequestorJustification'; Prop = 'RequireRequestorJustification' }
        @{ Name = 'requireApprovalForUpdate'; Prop = 'RequireApprovalForUpdate' }
        @{ Name = 'notificationsDisabled'; Prop = 'NotificationsDisabled' }
    )
    foreach ($B in $BoolFields) {
        if (Test-FieldDeclared $B.Name) {
            if ([bool]$Desired.($B.Prop) -ne [bool]$Current.($B.Prop)) { $Changed.Add($B.Name) }
        }
    }

    # -- requestorScope (scope string + user/group sets) -------------------------------------
    if (Test-FieldDeclared 'requestorScope') {
        $DS = $Desired.RequestorScope
        $CS = $Current.RequestorScope
        $Differs = $false
        if (($null -eq $DS) -ne ($null -eq $CS)) {
            $Differs = $true
        } elseif ($null -ne $DS -and $null -ne $CS) {
            if ([string]$DS.scope -ine [string]$CS.scope) { $Differs = $true }
            elseif (-not (Test-SetEqual $DS.users $CS.users)) { $Differs = $true }
            elseif (-not (Test-SetEqual $DS.groups $CS.groups)) { $Differs = $true }
        }
        if ($Differs) { $Changed.Add('requestorScope') }
    }

    # -- requestorSettings (bools + manager level int) ---------------------------------------
    if (Test-FieldDeclared 'requestorSettings') {
        $DR = $Desired.RequestorSettings
        $CR = $Current.RequestorSettings
        $Differs = $false
        if (($null -eq $DR) -ne ($null -eq $CR)) {
            $Differs = $true
        } elseif ($null -ne $DR -and $null -ne $CR) {
            if ([bool]$DR.allowSelfRequest -ne [bool]$CR.allowSelfRequest) { $Differs = $true }
            elseif ([bool]$DR.allowManagerRequest -ne [bool]$CR.allowManagerRequest) { $Differs = $true }
            elseif ([int]$DR.managerLevel -ne [int]$CR.managerLevel) { $Differs = $true }
            elseif ([bool]$DR.allowCustomSchedule -ne [bool]$CR.allowCustomSchedule) { $Differs = $true }
            elseif ([bool]$DR.allowSelfExtend -ne [bool]$CR.allowSelfExtend) { $Differs = $true }
            elseif ([bool]$DR.allowSelfRemove -ne [bool]$CR.allowSelfRemove) { $Differs = $true }
            elseif ([bool]$DR.allowOnBehalfUpdate -ne [bool]$CR.allowOnBehalfUpdate) { $Differs = $true }
            elseif ([bool]$DR.allowOnBehalfRemove -ne [bool]$CR.allowOnBehalfRemove) { $Differs = $true }
        }
        if ($Differs) { $Changed.Add('requestorSettings') }
    }

    # -- expiration (compared as a single kind+value unit) -----------------------------------
    if (Test-FieldDeclared 'expiration') {
        $DE = Get-ExpirationUnit $Desired
        $CE = Get-ExpirationUnit $Current
        if ($DE.Kind -ne $CE.Kind -or [string]$DE.Value -ne [string]$CE.Value) { $Changed.Add('expiration') }
    }

    # -- approvalStages (positional; scalars + approver sets) --------------------------------
    if (Test-FieldDeclared 'approvalStages') {
        $DStages = @($Desired.ApprovalStages)
        $CStages = @($Current.ApprovalStages)
        $Differs = $false
        if ($DStages.Count -ne $CStages.Count) {
            $Differs = $true
        } else {
            for ($I = 0; $I -lt $DStages.Count; $I++) {
                $D = $DStages[$I]
                $C = $CStages[$I]
                if ([string]$D.durationDays -ne [string]$C.durationDays) { $Differs = $true; break }
                if ([bool]$D.manager -ne [bool]$C.manager) { $Differs = $true; break }
                if ([int]$D.managerLevel -ne [int]$C.managerLevel) { $Differs = $true; break }
                if ([bool]$D.internalSponsor -ne [bool]$C.internalSponsor) { $Differs = $true; break }
                if ([bool]$D.externalSponsor -ne [bool]$C.externalSponsor) { $Differs = $true; break }
                if ([string]$D.escalationDays -ne [string]$C.escalationDays) { $Differs = $true; break }
                if ([bool]$D.requireApproverJustification -ne [bool]$C.requireApproverJustification) { $Differs = $true; break }
                if ([string]$D.approverInfoVisibility -ine [string]$C.approverInfoVisibility) { $Differs = $true; break }
                if (-not (Test-SetEqual $D.users $C.users)) { $Differs = $true; break }
                if (-not (Test-SetEqual $D.groups $C.groups)) { $Differs = $true; break }
                if (-not (Test-SetEqual $D.alternateUsers $C.alternateUsers)) { $Differs = $true; break }
                if (-not (Test-SetEqual $D.alternateGroups $C.alternateGroups)) { $Differs = $true; break }
                if (-not (Test-SetEqual $D.fallbackUsers $C.fallbackUsers)) { $Differs = $true; break }
                if (-not (Test-SetEqual $D.fallbackGroups $C.fallbackGroups)) { $Differs = $true; break }
            }
        }
        if ($Differs) { $Changed.Add('approvalStages') }
    }

    [PSCustomObject]@{
        Differs       = ($Changed.Count -gt 0)
        ChangedFields = $Changed.ToArray()
    }
}
