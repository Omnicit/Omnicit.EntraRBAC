function Get-OERRequestorScopeMap {
    <#
    .SYNOPSIS
    Returns the requestor scope names and the allowedTargetScope value each one is sent as.

    .DESCRIPTION
    The single owner of the requestor scope names of an access package assignment policy.
    New-OERAccessPackageRequestorScope sends the VALUES of this map, and Test-OERStructureSchema checks
    a declared requestorScope.scope against its KEYS, so the builder and the offline validator cannot
    drift apart. The builder's -Scope ValidateSet is a static attribute and cannot read this map; a unit
    test holds it equal to the keys, in order.

    Returns a new ordered dictionary on every call, so a caller can never change what another reads.
    Each key is a friendly scope name; each value is the Microsoft Graph v1.0 allowedTargetScope the
    builder sends for it, or $null for SpecificDirectoryServicePrincipals, which binds so the
    inventory's value is recognised but is never built (the builder refuses it).

    NoSubjects maps to notSpecified, NOT to noSubjects (issue #86). noSubjects is the legacy BETA
    requestorSettings.scopeType spelling and is not a member of the v1.0 allowedTargetScope enum at
    all, so sending it put an out-of-enum value on the wire and entitlement management rejected the
    whole policy with "InvalidModel: The model is invalid." -- measured on 2026-09-11 against a create
    body whose only unusual field was this one. Its v1.0 equivalent is notSpecified: no subjects and
    administrator direct assignment only are the same state. The name stays in the map so existing
    scripts and apply documents keep binding -- nothing can depend on the old behaviour, since the old
    behaviour was a hard Graph rejection -- and the builder warns about the substitution on every
    call. This is the ONLY place the mapping lives: both the cmdlet path and
    Sync-OERStructureAccessPackage funnel through the builder.

    unknownFutureValue is deliberately not a key: it is what Microsoft Graph returns for a scope this
    module cannot read, never a scope to declare. No Graph or ARM call; pure.

    .EXAMPLE
    (Get-OERRequestorScopeMap).Keys
    Lists the requestor scope names in the order the builder's -Scope parameter lists them.

    .EXAMPLE
    (Get-OERRequestorScopeMap)['NoSubjects']
    Returns notSpecified, the value the builder sends for the legacy NoSubjects spelling.
    #>
    [OutputType([System.Collections.Specialized.OrderedDictionary])]
    [CmdletBinding()]
    param()

    [ordered]@{
        AllMemberUsers                          = 'allMemberUsers'
        AllDirectoryUsers                       = 'allDirectoryUsers'
        AllExternalUsers                        = 'allExternalUsers'
        SpecificDirectoryUsers                  = 'specificDirectoryUsers'
        SpecificConnectedOrganizationUsers      = 'specificConnectedOrganizationUsers'
        AllConfiguredConnectedOrganizationUsers = 'allConfiguredConnectedOrganizationUsers'
        AllDirectoryServicePrincipals           = 'allDirectoryServicePrincipals'
        AllDirectoryAgentIdentities             = 'allDirectoryAgentIdentities'
        SpecificDirectoryServicePrincipals      = $null
        NoSubjects                              = 'notSpecified'
        NotSpecified                            = 'notSpecified'
    }
}
