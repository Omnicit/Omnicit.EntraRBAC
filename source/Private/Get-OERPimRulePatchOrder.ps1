function Get-OERPimRulePatchOrder {
    <#
    .SYNOPSIS
    Orders PIM policy rules for one-rule-at-a-time PATCHing around the MFA / authentication-context
    exclusion.

    .DESCRIPTION
    The single owner of the order in which a Microsoft Graph PIM write path PATCHes its rules. Graph
    validates the MFA / authentication-context exclusion ASYMMETRICALLY, so the order in which the
    AuthenticationContext_EndUser_Assignment and Enablement_EndUser_Assignment rules are PATCHed is
    load-bearing, not incidental. Each rule is a separate PATCH, so whichever goes second is
    validated against the state the first one left:
      - ENABLING an authentication context while MFA is still on is ACCEPTED (that acceptance is
        the defect issue #54 exists to reconcile);
      - ENABLING MFA while an authentication context is still on is REJECTED, observed live as
        'MfaAndAcrsConflict: The Mfa and Acrs policy settings cannot be enabled simultaneously.'
    A run that disabled the context AFTER sending MFA therefore lost the MFA rule to that
    rejection and left the policy with NEITHER protection in force.
    Order by what the authentication-context rule DOES, not by a fixed sequence: a rule that
    DISABLES the context goes FIRST (the Acrs side is already off when MFA is switched on), a
    rule that ENABLES it goes LAST (the MFA flag is already gone by then). Both orderings avoid
    a transient combination Graph rejects. This applies to any caller reaching its patch loop
    with both rules built -- a conflict reconcile is only one of the ways that happens. When only
    one of the two rules is present, or neither, the order is returned unchanged, and every other
    rule always keeps its position: the two rules trade places and nothing else moves.
    New-OERPimRuleSet is a shared, transport-free builder that owns rule SHAPE, not wire order:
    do not move this into New-OERPimRuleSet, and do not "tidy" it back into a fixed order.
    The rules may be hashtables or PSCustomObjects; only id and isEnabled are read. The same rule
    objects are returned (never clones), emitted one by one, so the caller wraps the call in @() to
    get an array; an empty input emits nothing. Pure; no Graph call.

    .PARAMETER Rule
    The rules the caller is about to PATCH, one request per rule, in the order they were built.

    .EXAMPLE
    $Rules = @(Get-OERPimRulePatchOrder -Rule @($Rules))
    Returns the same rules with a disabling authentication-context rule ahead of the activation
    enablement rule, or an enabling one behind it.
    #>
    [OutputType([object[]])]
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [object[]]$Rule
    )

    $Ordered = @($Rule)
    $AcAt = -1
    $EnAt = -1
    for ($Index = 0; $Index -lt $Ordered.Count; $Index++) {
        if ($Ordered[$Index].id -eq 'AuthenticationContext_EndUser_Assignment') { $AcAt = $Index }
        elseif ($Ordered[$Index].id -eq 'Enablement_EndUser_Assignment') { $EnAt = $Index }
    }
    # Both halves must be present: IndexOf-style -1 for a missing rule would otherwise address the
    # LAST element through PowerShell's negative indexing and swap an unrelated rule.
    if ($AcAt -ge 0 -and $EnAt -ge 0) {
        $AcMustLead = -not [bool]$Ordered[$AcAt].isEnabled
        $AcLeadsNow = $AcAt -lt $EnAt
        if ($AcMustLead -ne $AcLeadsNow) {
            $Swap = $Ordered[$AcAt]
            $Ordered[$AcAt] = $Ordered[$EnAt]
            $Ordered[$EnAt] = $Swap
        }
    }
    $Ordered
}
