function Resolve-OERAccessReviewRoleScope {
    <#
    .SYNOPSIS
    Classifies an access review definition's scope as a review of one Microsoft Entra directory role,
    in one of the forms Microsoft Graph stores, or as no role scope at all.

    .DESCRIPTION
    Single owner of which access review scope is a review of the assignments to one directory role. The
    forms are those of Microsoft Learn, "Configure access review scope by using Microsoft Graph APIs",
    as measured live (2026-11-07) against the test tenant:

    - Learn's example 12.1 (an accessReviewQueryScope whose query is
      '/roleManagement/directory/roleDefinitions/{id}') is refused on write (400), so the module never
      writes it. The form the module writes (New-OERAccessReviewScopeQuery -DirectoryRoleId) is a
      '#microsoft.graph.principalResourceMembershipsScope' with one principal scope '/users' and one
      resource scope '/roleManagement/directory/roleDefinitions/{id}'. Graph reads it back with
      '/v1.0/users' and '/beta/roleManagement/directory/roleDefinitions/{id}', every inner scope an
      accessReviewQueryScope of queryType MicrosoftGraph with a null queryRoot.
    - The eligible-only and active-only forms (example 12.2) are accessReviewQueryScope queries over
      roleEligibilityScheduleInstances and roleAssignmentScheduleInstances, read back with a leading
      '/beta'.
    - The service principal form (example 11) is stored by Graph as the All form above.
    - A guest principal scope ('/users?$filter=(userType eq ''Guest'')') over the same resource scope is
      stored as written.

    Kind is one of:

    - 'All': the scope type is the principal resource memberships scope, there is no top-level query,
      exactly one principal scope ('/users') and exactly one resource scope (the role definition), both
      of the plain type with an empty queryRoot and a queryType of MicrosoftGraph or empty. This is the
      only form that may be exported as a declared 'directoryRole'.
    - 'Eligible' and 'Active': the whole top-level query is the measured example 12.2 text under the
      plain scope type.
    - 'OtherForm': the scope names a role definition with a GUID id but is none of the above -- a
      guest principal scope, two principal scopes, a queryRoot, a trailing slash, an inner scope of
      another type, a scope of another type. Reading it as 'All' would widen it on apply, so it never is.
    - 'NotRole': anything else, including a group or access package query, a role definition id that is
      not a GUID, and a $null or empty scope.

    RoleDefinitionId is the captured id, lower-cased, for every Kind but 'NotRole', where it is $null.

    Pure: no Graph, ARM, or authentication occurs.

    .PARAMETER Query
    The raw top-level scope query string. $null and an empty value are accepted.

    .PARAMETER ScopeType
    The scope's '@odata.type', as ConvertTo-OERAccessReviewDefinition surfaces it in ScopeType. $null and
    an empty value are read as the plain query scope; '#microsoft.graph.accessReviewQueryScope' is the
    plain query scope too, compared without regard to letter case.

    .PARAMETER PrincipalScope
    The principal scopes of a principal resource memberships scope, as ConvertTo-OERAccessReviewDefinition
    surfaces them in PrincipalScopes: objects with Query, QueryType, QueryRoot and ScopeType. $null and an
    empty collection are accepted.

    .PARAMETER ResourceScope
    The resource scopes of a principal resource memberships scope, in the same shape as -PrincipalScope.

    .EXAMPLE
    Resolve-OERAccessReviewRoleScope -Query '/beta/roleManagement/directory/roleDefinitions/00000000-0000-0000-0000-000000000041'
    Returns Kind 'OtherForm' with the role definition id: the bare 12.1 query is not the form the module writes.

    .EXAMPLE
    Resolve-OERAccessReviewRoleScope -ScopeType '#microsoft.graph.principalResourceMembershipsScope' -PrincipalScope $Principals -ResourceScope $Resources
    Returns Kind 'All' and the role definition id for the form the module writes.
    #>
    [OutputType([PSCustomObject])]
    [CmdletBinding()]
    param(
        [Parameter()]
        [AllowNull()]
        [AllowEmptyString()]
        [string]$Query,

        [Parameter()]
        [AllowNull()]
        [AllowEmptyString()]
        [string]$ScopeType,

        [Parameter()]
        [AllowNull()]
        [AllowEmptyCollection()]
        [object[]]$PrincipalScope,

        [Parameter()]
        [AllowNull()]
        [AllowEmptyCollection()]
        [object[]]$ResourceScope
    )

    $VersionPrefix = '(?:/(?:v\d+(?:\.\d+)?|beta))?'
    $PlainType = '#microsoft.graph.accessReviewQueryScope'
    $MembershipsType = '#microsoft.graph.principalResourceMembershipsScope'
    $Text = [string]$Query
    $Principals = @($PrincipalScope | Where-Object { $null -ne $_ })
    $Resources = @($ResourceScope | Where-Object { $null -ne $_ })
    $Kind = 'NotRole'
    $RoleId = $null

    $IsPlainType = {
        param([object]$Type)
        [string]::IsNullOrEmpty([string]$Type) -or
            ([string]$Type).Equals($PlainType, [System.StringComparison]::OrdinalIgnoreCase)
    }
    $IsPlainInner = {
        param([object]$Scope)
        (& $IsPlainType $Scope.ScopeType) -and
            [string]::IsNullOrEmpty([string]$Scope.QueryRoot) -and
            ([string]::IsNullOrEmpty([string]$Scope.QueryType) -or
                ([string]$Scope.QueryType).Equals('MicrosoftGraph', [System.StringComparison]::OrdinalIgnoreCase))
    }
    $ResourcePattern = '^' + $VersionPrefix + '/roleManagement/directory/roleDefinitions/([^/?#]+)'

    # All
    if (-not [string]::IsNullOrEmpty($ScopeType) -and
        $ScopeType.Equals($MembershipsType, [System.StringComparison]::OrdinalIgnoreCase) -and
        [string]::IsNullOrEmpty($Text) -and $Principals.Count -eq 1 -and $Resources.Count -eq 1 -and
        (& $IsPlainInner $Principals[0]) -and (& $IsPlainInner $Resources[0]) -and
        ([string]$Principals[0].Query) -match ('^' + $VersionPrefix + '/users$') -and
        ([string]$Resources[0].Query) -match ($ResourcePattern + '$') -and (Test-OERGuid -Value $Matches[1])) {
        $Kind = 'All'
        $RoleId = $Matches[1]
    }

    # Eligible and Active
    if ($Kind -eq 'NotRole' -and $Text -and (& $IsPlainType $ScopeType)) {
        $Forms = [ordered]@{
            Eligible = @("/roleManagement/directory/roleEligibilityScheduleInstances?`$expand=principal&`$filter=(isof(principal,'microsoft.graph.user') and roleDefinitionId eq '", "')")
            Active   = @("/roleManagement/directory/roleAssignmentScheduleInstances?`$expand=principal&`$filter=(assignmentType eq 'Assigned' and isof(principal,'microsoft.graph.user') and roleDefinitionId eq '", "')")
        }
        foreach ($Name in $Forms.Keys) {
            $Pattern = '^' + $VersionPrefix + [regex]::Escape($Forms[$Name][0]) + "([^']+)" + [regex]::Escape($Forms[$Name][1]) + '$'
            if ($Text -match $Pattern -and (Test-OERGuid -Value $Matches[1])) {
                $Kind = $Name
                $RoleId = $Matches[1]
                break
            }
        }
    }

    # OtherForm
    if ($Kind -eq 'NotRole') {
        foreach ($Resource in $Resources) {
            if (([string]$Resource.Query) -match $ResourcePattern -and (Test-OERGuid -Value $Matches[1])) {
                $Kind = 'OtherForm'
                $RoleId = $Matches[1]
                break
            }
        }
    }
    if ($Kind -eq 'NotRole' -and $Text -match ('^' + $VersionPrefix + '/roleManagement/directory/')) {
        if (($Text -match "roleDefinitionId eq '([^']+)'" -or $Text -match 'roleDefinitions/([^/?#]+)$') -and
            (Test-OERGuid -Value $Matches[1])) {
            $Kind = 'OtherForm'
            $RoleId = $Matches[1]
        }
    }

    $Out = [PSCustomObject]@{
        Kind             = $Kind
        RoleDefinitionId = if ($null -ne $RoleId) { $RoleId.ToLowerInvariant() } else { $null }
    }
    $Out.PSObject.TypeNames.Insert(0, 'Omnicit.EntraRBAC.AccessReviewRoleScope')
    $Out
}
