function Resolve-OERPimActivationConflict {
    <#
    .SYNOPSIS
    Decides how to resolve the PIM mutual exclusion between an enabled authentication context and
    multi-factor authentication on activation.

    .DESCRIPTION
    Pure, tenant-free decision helper and the module's single owner of the rule that PIM treats an
    enabled AuthenticationContext_EndUser_Assignment rule and MultiFactorAuthentication in the
    Enablement_EndUser_Assignment rule as mutually exclusive. Callers pass what the caller asked for
    and what the RESULTING policy state would be, and receive one of four actions: Conflict (the
    caller explicitly asked for both, which is refused), ClearMfa (the caller asked for the context,
    so MFA is removed from the enablement rules), DisableAuthContext (the caller asked for MFA, so
    the context rule is disabled), or None. The trigger is the resulting context rule being ENABLED,
    never merely present, and the decision is one-directional per call: disabling a context never
    re-adds MFA. No Graph, ARM, or authentication occurs; the caller applies the decision in its own
    idiom.

    .PARAMETER CallerRequestsAuthContext
    The caller explicitly asked to ENABLE an authentication context in this call (a non-empty claim
    value was bound or declared). An explicit empty string is a disable and is not a request.

    .PARAMETER CallerRequestsMfa
    The caller explicitly asked to REQUIRE multi-factor authentication on activation in this call.

    .PARAMETER EffectiveAuthContextEnabled
    The authentication context rule that would be in force after this call is enabled -- the
    caller's value when they supplied one, the live rule's isEnabled otherwise.

    .PARAMETER EffectiveAuthContextId
    The claim value that would be in force after this call, used only to build the Reason text.

    .PARAMETER EffectiveActivationEnabledRules
    The activation enabledRules that would be in force after this call -- the caller's list when
    they supplied one, the live list otherwise. Whether it contains MultiFactorAuthentication is
    what makes a combination invalid.

    .PARAMETER ResolveUnrequestedConflict
    Resolve an invalid combination the caller asked for neither side of, by clearing MFA. The ARM
    transport passes this because it PATCHes the FULL rule set, so ARM rejects a pre-existing
    invalid combination even on an unrelated change. The Graph transport patches one rule at a time
    and deliberately leaves an untouched combination alone.

    .EXAMPLE
    Resolve-OERPimActivationConflict -CallerRequestsAuthContext -EffectiveAuthContextEnabled -EffectiveAuthContextId 'c1' -EffectiveActivationEnabledRules @('MultiFactorAuthentication', 'Justification')
    Returns Action = ClearMfa with ActivationEnabledRules = @('Justification').
    #>
    [OutputType([PSCustomObject])]
    [CmdletBinding()]
    param(
        [switch]$CallerRequestsAuthContext,
        [switch]$CallerRequestsMfa,
        [switch]$EffectiveAuthContextEnabled,
        [string]$EffectiveAuthContextId,
        [string[]]$EffectiveActivationEnabledRules,
        [switch]$ResolveUnrequestedConflict
    )
    $EffectiveMfa = @($EffectiveActivationEnabledRules) -contains 'MultiFactorAuthentication'
    $Action       = 'None'
    $Rules        = $null
    $ContextId    = $null
    $Reason       = ''

    # Only an ENABLED context collides. A present-but-disabled rule is not a conflict, mirroring the
    # ARM guard's own isEnabled test.
    if ($EffectiveAuthContextEnabled -and $EffectiveMfa) {
        if ($CallerRequestsAuthContext -and $CallerRequestsMfa) {
            $Action = 'Conflict'
            $Reason = 'Cannot enable both multi-factor authentication and an authentication context on activation; PIM treats them as mutually exclusive. Set only one.'
        } elseif ($CallerRequestsMfa) {
            $Action    = 'DisableAuthContext'
            $ContextId = ''
            $Reason    = "authentication context '$EffectiveAuthContextId' disabled: mutually exclusive with multi-factor authentication on activation"
        } elseif ($CallerRequestsAuthContext -or $ResolveUnrequestedConflict) {
            $Action = 'ClearMfa'
            $Rules  = @(@($EffectiveActivationEnabledRules) | Where-Object { $_ -ne 'MultiFactorAuthentication' })
            $Reason = "mfa cleared: mutually exclusive with authenticationContextId=$EffectiveAuthContextId"
        }
    }

    $Out = [PSCustomObject]@{
        Action                 = $Action
        ActivationEnabledRules = $Rules
        AuthenticationContextId = $ContextId
        Reason                 = $Reason
    }
    $Out.PSObject.TypeNames.Insert(0, 'Omnicit.EntraRBAC.PimActivationConflict')
    $Out
}
