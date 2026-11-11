function Resolve-OERRoleDefinitionId {
    <#
    .SYNOPSIS
    Resolves a role display name, GUID, or full ARM id into the full ARM role definition id.

    .DESCRIPTION
    Azure role assignment bodies require roleDefinitionId to be the FULL ARM resource id, never a
    bare GUID. This helper accepts the three input forms the public cmdlets allow on -Role: a full
    ARM id (begins with '/' and contains '/providers/Microsoft.Authorization/roleDefinitions/') is
    passed through; a
    bare GUID is expanded to '{scope}/providers/Microsoft.Authorization/roleDefinitions/{guid}'
    without a network call; anything else is treated as the exact role display name and resolved via
    the documented $filter=roleName eq '...' list call at the target scope (single quotes doubled,
    value URL-encoded). Exactly one match returns that role's full ARM id. No match throws a
    not-found error that names Get-OERRoleDefinition so the operator can list the valid names, and
    more than one match throws an ErrorRecord with ErrorId 'AmbiguousName' listing the candidate
    ids, because a display name that resolves at more than one inherited scope cannot identify a
    single role and picking the first would silently act on an arbitrary one. The public cmdlets
    catch and route both.

    A failed read (a 403, an exhausted 429, a 5xx, a paging refusal) is never turned into the
    not-found throw: the ARM transport's own error propagates. An answer with an empty body, a
    body of JSON null or no value member is refused by the transport (-RequireValue) as
    ArmPagingIncomplete, so it too is a failed read and never the no-match case. With
    -ThrowUnresolved the no-match case, which is a lookup that SUCCEEDED and found nothing, is thrown
    as an ErrorRecord with the internal id RoleDefinitionUnresolved (same message, category
    ObjectNotFound, target the role) so a caller can tell it from a failed read through
    Test-OERRoleLookupUnresolved. The id is never published. Without the switch the no-match throw is a plain string, as before:
    Sync-OERStructureRoleAssignment republishes that record as itself.

    .PARAMETER Role
    The role display name (e.g. 'Reader'), the role definition GUID, or the full ARM id.

    .PARAMETER Scope
    The ARM scope at which name lookups are performed and bare GUIDs are anchored.

    .PARAMETER ThrowUnresolved
    Throws the no-match case as an ErrorRecord with the internal id RoleDefinitionUnresolved instead
    of a plain string. Used by the two role management policy cmdlets and the seven Azure role
    assignment cmdlets, which classify it through Test-OERRoleLookupUnresolved.

    .EXAMPLE
    Resolve-OERRoleDefinitionId -Role 'Reader' -Scope '/subscriptions/00000000-0000-0000-0000-000000000001'
    Returns the full ARM id of the Reader role definition.
    #>
    [OutputType([string])]
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Role,

        [Parameter(Mandatory)]
        [string]$Scope,

        [switch]$ThrowUnresolved
    )

    if ($Role.StartsWith('/', [System.StringComparison]::Ordinal) -and $Role -like '*/providers/Microsoft.Authorization/roleDefinitions/*') {
        return $Role
    }
    if (Test-OERGuid -Value $Role) {
        return "$Scope/providers/Microsoft.Authorization/roleDefinitions/$Role"
    }

    $Escaped = $Role.Replace("'", "''")
    $Filter = [uri]::EscapeDataString("roleName eq '$Escaped'")
    $Response = Invoke-OERArmRequest -Path "$Scope/providers/Microsoft.Authorization/roleDefinitions?api-version=2022-04-01&`$filter=$Filter" -RequireValue
    # The null filter is load-bearing: @($null).Count is 1, so without it a response whose value
    # array holds a single null would be counted as a match and return an empty string.
    $Candidates = @($Response.value | Where-Object { $null -ne $_ })
    if ($Candidates.Count -gt 1) {
        $Ids = ($Candidates | ForEach-Object { [string]$_.id }) -join ', '
        throw [System.Management.Automation.ErrorRecord]::new(
            [System.Exception]::new(
                "Role name '$Role' matches $($Candidates.Count) role definitions at scope '$Scope' ($Ids). " +
                'Azure surfaces role definitions inherited from every parent scope, so this name cannot ' +
                'identify a single role here. Re-run with the role definition GUID or its full ARM id ' +
                'instead of the name.'),
            'AmbiguousName',
            [System.Management.Automation.ErrorCategory]::InvalidArgument,
            $Role)
    }
    if ($Candidates.Count -eq 0) {
        # The scope in the example is quoted with every single-quote character doubled
        # (CodeGeneration.EscapeSingleQuotedStringContent: the straight one and the curly ones the
        # PowerShell tokenizer also reads as quotes), so the example stays valid as typed.
        $NotFoundMessage = "Role definition '$Role' was not found at scope '$Scope'. " +
            "Run Get-OERRoleDefinition -Scope '$([System.Management.Automation.Language.CodeGeneration]::EscapeSingleQuotedStringContent([string]$Scope))' without -Role to list the roles available " +
            'there, or supply the role definition GUID or its full ARM id.'
        if ($ThrowUnresolved) {
            throw [System.Management.Automation.ErrorRecord]::new(
                [System.Exception]::new($NotFoundMessage),
                'RoleDefinitionUnresolved',
                [System.Management.Automation.ErrorCategory]::ObjectNotFound,
                $Role)
        }
        throw $NotFoundMessage
    }
    return [string]$Candidates[0].id
}
