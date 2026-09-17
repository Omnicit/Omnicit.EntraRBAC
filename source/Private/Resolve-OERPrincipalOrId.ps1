function Resolve-OERPrincipalOrId {
    <#
    .SYNOPSIS
    Resolves a principal supplied either as a raw object id or as a friendly reference, returning
    the object id or a routable failure descriptor.

    .DESCRIPTION
    The single owner of the "raw object id OR friendly name" principal-input pattern shared by the
    PIM, group-membership, administrative-unit and entitlement-management cmdlets. When the raw id
    parameter is supplied it is validated with Test-OERGuid and returned verbatim (no Graph call).
    Otherwise exactly one of -User, -Group or -ServicePrincipal is fanned into Resolve-OERPrincipal.

    This helper never throws and never writes to the error stream. It always returns an object with
    PrincipalId, PrincipalType, ErrorId, Message, Category and TargetObject. On success ErrorId is
    null; on failure PrincipalId is null and the caller routes ErrorId/Message/Category/TargetObject
    through Write-CmdletError, keeping the guard, the error ids and the wording identical across
    every cmdlet that takes a principal. When a valid -PrincipalId is supplied alongside one or more
    friendly parameters, the id still wins (no error), but the helper writes a warning naming the
    ignored friendly parameter(s) so a mistaken combination is never silent.

    .PARAMETER PrincipalId
    The raw principal object id supplied by the caller. Must be a canonical hyphenated GUID; any
    other value produces the invalid-id failure. Takes precedence over the friendly parameters, so
    a pipeline-bound id never collides with an explicitly supplied name.

    .PARAMETER User
    A friendly user reference (user principal name or object id) resolved via Resolve-OERPrincipal.
    Mutually exclusive with -Group and -ServicePrincipal.

    .PARAMETER Group
    A friendly group reference (group display name or object id) resolved via Resolve-OERPrincipal.
    Mutually exclusive with -User and -ServicePrincipal.

    .PARAMETER GroupParameterName
    The name of the caller's friendly group parameter as it should appear in the precedence warning
    when -PrincipalId wins over a supplied -Group value, without the leading dash. Defaults to Group;
    pass GroupPrincipal on a cmdlet that renames it (because -Group already names a different, target
    object on that cmdlet) so the warning never names the wrong parameter.

    .PARAMETER ServicePrincipal
    A friendly service principal reference (display name or service principal object id) resolved
    via Resolve-OERPrincipal. Mutually exclusive with -User and -Group.

    .PARAMETER IdParameterName
    The name of the caller's raw id parameter as it appears in error messages, without the leading
    dash. Defaults to PrincipalId; pass TargetId or MemberId when the caller names it differently.

    .PARAMETER InvalidIdErrorId
    The FullyQualifiedErrorId reported when the raw id is not a canonical GUID. Defaults to
    InvalidPrincipalId; pass InvalidTargetId or InvalidMemberId to match the caller's parameter.

    .PARAMETER FriendlyParameterHint
    The human-readable list of friendly parameters the caller actually exposes, used verbatim in
    the failure messages so the guidance always names parameters that exist on that cmdlet.

    .PARAMETER NoPrincipalHint
    Optional extra guidance appended in parentheses to the NoPrincipal message, for example a note
    that the principal can be supplied by piping from a Get cmdlet.

    .EXAMPLE
    Resolve-OERPrincipalOrId -PrincipalId 'aaaa0000-0000-0000-0000-000000000001'
    Returns the id verbatim with no Graph call and no error.

    .EXAMPLE
    Resolve-OERPrincipalOrId -User 'anna.berg@contoso.com' -FriendlyParameterHint '-User or -GroupPrincipal'
    Resolves the user principal name to its object id, or returns a PrincipalNotFound failure.
    #>
    [OutputType([PSCustomObject])]
    [CmdletBinding()]
    param(
        [string]$PrincipalId,
        [string]$User,
        [string]$Group,
        [string]$GroupParameterName = 'Group',
        [string]$ServicePrincipal,
        [string]$IdParameterName = 'PrincipalId',
        [string]$InvalidIdErrorId = 'InvalidPrincipalId',
        [string]$FriendlyParameterHint = '-User, -Group or -ServicePrincipal',
        [string]$NoPrincipalHint
    )

    $Result = [PSCustomObject]@{
        PrincipalId   = $null
        PrincipalType = $null
        ErrorId       = $null
        Message       = $null
        Category      = $null
        TargetObject  = $null
    }

    if ($PrincipalId) {
        if (-not (Test-OERGuid -Value $PrincipalId)) {
            $Result.ErrorId = $InvalidIdErrorId
            $Result.Category = 'InvalidArgument'
            $Result.TargetObject = $PrincipalId
            $Result.Message = "'-$IdParameterName' expects a principal object id (GUID); '$PrincipalId' is not a valid GUID. To look up a principal by name, use $FriendlyParameterHint instead."
            return $Result
        }
        $IgnoredParameterNames = [System.Collections.Generic.List[string]]::new()
        if ($User) { $IgnoredParameterNames.Add('-User') }
        if ($Group) { $IgnoredParameterNames.Add("-$GroupParameterName") }
        if ($ServicePrincipal) { $IgnoredParameterNames.Add('-ServicePrincipal') }
        if ($IgnoredParameterNames.Count -gt 0) {
            Write-Warning "-$IdParameterName takes precedence: the supplied $($IgnoredParameterNames -join ', ') value is ignored and principal object id '$PrincipalId' is used. Supply only one." -WarningAction Continue
        }
        $Result.PrincipalId = $PrincipalId
        return $Result
    }

    $PrincipalParams = @{}
    if ($User) { $PrincipalParams.User = $User }
    if ($Group) { $PrincipalParams.Group = $Group }
    if ($ServicePrincipal) { $PrincipalParams.ServicePrincipal = $ServicePrincipal }

    if ($PrincipalParams.Count -eq 0) {
        $Suffix = if ($NoPrincipalHint) { " ($NoPrincipalHint)" } else { '' }
        $Result.ErrorId = 'NoPrincipal'
        $Result.Category = 'InvalidArgument'
        $Result.Message = "A principal is required: supply -$IdParameterName or one of $FriendlyParameterHint$Suffix."
        return $Result
    }
    if ($PrincipalParams.Count -gt 1) {
        $Result.ErrorId = 'AmbiguousPrincipal'
        $Result.Category = 'InvalidArgument'
        $Result.Message = "Supply only one of $FriendlyParameterHint."
        return $Result
    }

    try {
        $Principal = Resolve-OERPrincipal @PrincipalParams
    } catch {
        Remove-OERErrorRecord -Record $PSItem
        $Result.ErrorId = 'PrincipalNotFound'
        $Result.Category = 'ObjectNotFound'
        $Result.TargetObject = @($PrincipalParams.Values)[0]
        $Result.Message = $PSItem.Exception.Message
        return $Result
    }

    $Result.PrincipalId = $Principal.PrincipalId
    $Result.PrincipalType = $Principal.PrincipalType
    return $Result
}
