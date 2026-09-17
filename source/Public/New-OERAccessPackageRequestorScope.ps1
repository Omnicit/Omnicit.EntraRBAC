function New-OERAccessPackageRequestorScope {
    <#
    .SYNOPSIS
    Builds the requestor scope for an access package assignment policy.

    .DESCRIPTION
    Returns a tagged Omnicit.EntraRBAC.RequestorScope object describing who can request the access
    package under a policy, for use with the -RequestorScope parameter of
    New/Set-OERAccessPackageAssignmentPolicy. -Scope selects the allowedTargetScope. For the
    SpecificDirectoryUsers scope, -User and -Group supply the specificAllowedTargets: each value is
    either a name (user principal name, or group display name) or an object id (GUID); names are
    resolved to ids and a GUID is used directly. Resolution authenticates lazily (only when a name is
    present), so a pure-GUID input performs no Graph call. -User/-Group are ignored with a warning for
    any scope other than SpecificDirectoryUsers. -AdminAssignmentOnly produces a policy that permits
    administrator direct assignment only (allowedTargetScope notSpecified).

    NoSubjects is accepted but is NOT sent: it is the legacy beta requestorSettings.scopeType
    spelling and is not a member of the v1.0 allowedTargetScope enum, so entitlement management
    rejects a policy carrying it with "InvalidModel: The model is invalid." It is mapped to
    notSpecified -- the same state, administrator direct assignment only -- and every call that
    uses it emits a warning naming the substitution.

    .PARAMETER Scope
    The allowed target scope. Must be one of:
    AllMemberUsers, AllDirectoryUsers, SpecificDirectoryUsers,
    SpecificConnectedOrganizationUsers, AllConfiguredConnectedOrganizationUsers,
    NoSubjects, or NotSpecified. NotSpecified is the administrator-direct-assignment-only
    scope (equivalent to -AdminAssignmentOnly) and is what the portal "Who can get access: None"
    option produces; it round-trips through the inventory. NoSubjects stays bindable for
    compatibility with existing scripts and apply documents but is mapped to notSpecified with a
    warning, since the v1.0 service has no noSubjects value to send.

    .PARAMETER User
    Zero or more user principal names or user object ids (GUIDs) allowed to request the package. Used
    with -Scope SpecificDirectoryUsers.

    .PARAMETER Group
    Zero or more group display names or group object ids (GUIDs) whose members are allowed to request
    the package. Used with -Scope SpecificDirectoryUsers.

    .PARAMETER AdminAssignmentOnly
    Build an administrator-direct-assignment-only scope (allowedTargetScope notSpecified). Mutually
    exclusive with -Scope, -User, and -Group.

    .PARAMETER TenantId
    Optional tenant id or domain to authenticate against, forwarded to Initialize-OERAuth.

    .EXAMPLE
    New-OERAccessPackageRequestorScope -Scope AllMemberUsers
    Allows any member user to request the package.

    .EXAMPLE
    New-OERAccessPackageRequestorScope -Scope SpecificDirectoryUsers -Group 'Sales Team' -User 'anna.berg@contoso.com'
    Restricts requests to the named group's members and the named user.

    .EXAMPLE
    New-OERAccessPackageRequestorScope -AdminAssignmentOnly
    Produces an admin-assignment-only scope -- no end-user requests permitted.
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '',
        Justification = 'Read-only builder; resolves names via Graph lookups and returns an object, but changes no state.')]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', 'AdminAssignmentOnly',
        Justification = 'Switch is a parameter-set discriminator; ParameterSetName is used instead.')]
    [OutputType([PSCustomObject])]
    [CmdletBinding(DefaultParameterSetName = 'Scoped')]
    param(
        [Parameter(ParameterSetName = 'Scoped', Mandatory)]
        [ValidateSet(
            'AllMemberUsers',
            'AllDirectoryUsers',
            'SpecificDirectoryUsers',
            'SpecificConnectedOrganizationUsers',
            'AllConfiguredConnectedOrganizationUsers',
            'NoSubjects',
            'NotSpecified'
        )]
        [string]$Scope,

        [Parameter(ParameterSetName = 'Scoped')]
        [string[]]$User,

        [Parameter(ParameterSetName = 'Scoped')]
        [string[]]$Group,

        [Parameter(ParameterSetName = 'AdminOnly', Mandatory)]
        [switch]$AdminAssignmentOnly,

        [string]$TenantId
    )
    process {
        $ScopeMap = @{
            AllMemberUsers                          = 'allMemberUsers'
            AllDirectoryUsers                       = 'allDirectoryUsers'
            SpecificDirectoryUsers                  = 'specificDirectoryUsers'
            SpecificConnectedOrganizationUsers      = 'specificConnectedOrganizationUsers'
            AllConfiguredConnectedOrganizationUsers = 'allConfiguredConnectedOrganizationUsers'
            # Issue #86: NoSubjects maps to notSpecified, NOT to 'noSubjects'. 'noSubjects' is the
            # legacy BETA requestorSettings.scopeType spelling and is not a member of the v1.0
            # allowedTargetScope enum at all, so sending it put an out-of-enum value on the wire and
            # entitlement management rejected the whole policy with "InvalidModel: The model is
            # invalid." -- measured on 2026-09-11 against a create body whose only unusual field was
            # this one. Its v1.0 equivalent is notSpecified: no subjects and administrator direct
            # assignment only are the same state, which this cmdlet's own help already said. The
            # value stays in the ValidateSet so existing scripts and apply documents keep binding --
            # nothing can depend on the old behaviour, since the old behaviour was a hard Graph
            # rejection -- and the substitution is warned about on every call below. This is the
            # ONLY place the mapping lives: both the cmdlet path and Sync-OERStructureAccessPackage
            # funnel through this builder.
            NoSubjects                              = 'notSpecified'
            NotSpecified                            = 'notSpecified'
        }

        $AllowedTargetScope = if ($PSCmdlet.ParameterSetName -eq 'AdminOnly') {
            'notSpecified'
        }
        else {
            if ($Scope -eq 'NoSubjects') {
                Write-Warning ("[New-OERAccessPackageRequestorScope] -Scope NoSubjects is the legacy beta " +
                    "requestorSettings.scopeType spelling and is not a v1.0 allowedTargetScope value; " +
                    "entitlement management rejects a policy carrying it with 'InvalidModel: The model is " +
                    "invalid.'. Sending allowedTargetScope 'notSpecified' instead -- the same state " +
                    '(administrator direct assignment only). Use -AdminAssignmentOnly or -Scope NotSpecified ' +
                    'to silence this warning.')
            }
            $ScopeMap[$Scope]
        }

        $SpecificAllowedTargets = @()
        if ($User -or $Group) {
            if ($Scope -ne 'SpecificDirectoryUsers') {
                Write-Warning "[New-OERAccessPackageRequestorScope] -User/-Group apply only to -Scope SpecificDirectoryUsers; ignoring them for scope '$Scope'."
            }
            else {
                $AuthParams = @{}
                if ($TenantId) { $AuthParams.TenantId = $TenantId }
                $Resolved = Resolve-OERTargetList -User $User -Group $Group @AuthParams
                if ($Resolved.FailedValue) {
                    # Prefer the resolver's own ErrorId/message (an ambiguous name names the candidate ids).
                    $ErrId = if ($Resolved.FailedErrorId) { $Resolved.FailedErrorId }
                    elseif ($Resolved.FailedKind -eq 'User') { 'UserNotFound' } else { 'GroupNotFound' }
                    $Msg = if ($Resolved.FailedMessage) { $Resolved.FailedMessage }
                    else { "$($Resolved.FailedKind) '$($Resolved.FailedValue)' not found." }
                    # An ambiguity is a bad argument, not a missing object; the not-found path is unchanged.
                    $Cat = if ($Resolved.FailedErrorId) { 'InvalidArgument' } else { 'ObjectNotFound' }
                    Write-CmdletError `
                        -Message ([System.Exception]::new($Msg)) `
                        -ErrorId $ErrId -Category $Cat -TargetObject $Resolved.FailedValue -Cmdlet $PSCmdlet
                    return
                }
                $SpecificAllowedTargets = $Resolved.Approvers
            }
        }

        $Out = [PSCustomObject]@{
            AllowedTargetScope     = $AllowedTargetScope
            SpecificAllowedTargets = @($SpecificAllowedTargets)
        }
        $Out.PSObject.TypeNames.Insert(0, 'Omnicit.EntraRBAC.RequestorScope')
        $Out
    }
}
