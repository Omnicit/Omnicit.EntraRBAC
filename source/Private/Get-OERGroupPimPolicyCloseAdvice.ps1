function Get-OERGroupPimPolicyCloseAdvice {
    <#
    .SYNOPSIS
    Returns the advice that closes a group's PIM-for-groups policy opened to allow permanent eligibility.

    .DESCRIPTION
    The single owner of the close instruction the module gives when a group's PIM-for-groups policy was
    opened to allow permanent eligibility and may have been left open. Add-OERGroupEligibility gives it
    in PolicyOpenedButGrantFailed and EligibilityRequestFailed, and Sync-OERStructureGroup in the
    GroupNotOnboarded record of a group created in the same run, so both say the same thing from one
    place. Pure: it makes no request and writes nothing but the string.

    The text returned is "close it with '<command>' if you do not intend to retry.", where the command is
    Set-OERGroupPimPolicy -Group '<GroupId>' -AccessType <AccessType> -AllowPermanentEligibility:$false.
    The command sits inside ONE single-quoted PowerShell string literal, so the quotes around the group
    id are doubled in the text, exactly as a message shows it; read as that literal, it is the command.

    Why that command closes the policy: Set-OERGroupPimPolicy patches the Expiration_Admin_Eligibility
    rule only when -EligibleDuration or -AllowPermanentEligibility is BOUND. -AllowPermanentEligibility:$false
    binds the switch with the value false, so the cmdlet reads the live rule's maximumDuration, carries
    it forward unchanged and sends the rule with isExpirationRequired true: permanent eligibility is no
    longer allowed, and the maximum for a time-bound grant stays what it was. -ActivationMaxHours alone,
    the advice this module gave before, patches only the activation rule (Expiration_EndUser_Assignment)
    and never touches the eligibility-expiration rule, so it left the policy open.

    .PARAMETER GroupId
    The object id of the group whose policy was opened, as the caller resolved it (a GUID).

    .PARAMETER AccessType
    The access type of the policy that was opened, member or owner.

    .EXAMPLE
    Get-OERGroupPimPolicyCloseAdvice -GroupId $GroupId -AccessType member
    Returns "close it with 'Set-OERGroupPimPolicy -Group ''<GroupId>'' -AccessType member
    -AllowPermanentEligibility:$false' if you do not intend to retry." with the group's id in place of
    <GroupId>, for a message that names a member-access policy left open.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [string]$GroupId,

        [Parameter(Mandatory)]
        [ValidateSet('member', 'owner')]
        [string]$AccessType
    )
    "close it with 'Set-OERGroupPimPolicy -Group ''$GroupId'' -AccessType $AccessType -AllowPermanentEligibility:`$false' if you do not intend to retry."
}
