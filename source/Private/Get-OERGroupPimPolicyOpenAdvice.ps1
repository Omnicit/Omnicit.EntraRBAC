function Get-OERGroupPimPolicyOpenAdvice {
    <#
    .SYNOPSIS
    Returns the advice that opens a group's PIM-for-groups policy to allow permanent eligibility by hand.

    .DESCRIPTION
    The single owner of the open instruction Add-OERGroupEligibility gives in PolicyOpenFailed, when it
    tried to open a group's PIM-for-groups policy to allow permanent eligibility and could not. Pure: it
    makes no request and writes nothing but the string. It is the opening counterpart of
    Get-OERGroupPimPolicyCloseAdvice.

    The text returned is "Run '<command>' with sufficient permissions, or grant a time-bound eligibility
    with -DurationDays.", where the command is
    Set-OERGroupPimPolicy -Group '<GroupId>' -AccessType <AccessType> -AllowPermanentEligibility.
    The command sits inside ONE single-quoted PowerShell string literal, so the quotes around the group
    id are doubled in the text, exactly as a message shows it; read as that literal, it is the command,
    and it runs as typed.

    Why that command opens the policy: Set-OERGroupPimPolicy patches the Expiration_Admin_Eligibility
    rule when -EligibleDuration or -AllowPermanentEligibility is BOUND. -AllowPermanentEligibility binds
    the switch with the value true, so the cmdlet reads the live rule's maximumDuration, carries it
    forward unchanged and sends the rule with isExpirationRequired false: permanent eligibility is
    allowed, and the maximum for a time-bound grant stays what it was.

    Why -ActivationMaxHours is not in it: the open does not need it. -ActivationMaxHours patches only the
    activation rule (Expiration_EndUser_Assignment), so naming it would ask the operator to rewrite a
    maximum this open leaves alone. The advice used to carry "-ActivationMaxHours <n>" as a placeholder,
    and that text did not run as typed either: PowerShell reserves the less-than operator, so the command
    failed to parse until the placeholder was replaced, and a value put in its place then rewrote the
    activation maximum.

    .PARAMETER GroupId
    The object id of the group whose policy could not be opened, as the caller resolved it (a GUID).

    .PARAMETER AccessType
    The access type of the policy that could not be opened, member or owner.

    .EXAMPLE
    Get-OERGroupPimPolicyOpenAdvice -GroupId $GroupId -AccessType member
    Returns "Run 'Set-OERGroupPimPolicy -Group ''<GroupId>'' -AccessType member -AllowPermanentEligibility'
    with sufficient permissions, or grant a time-bound eligibility with -DurationDays." with the group's
    id in place of <GroupId>, for a message that names a member-access policy that could not be opened.
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
    "Run 'Set-OERGroupPimPolicy -Group ''$GroupId'' -AccessType $AccessType -AllowPermanentEligibility' with sufficient permissions, or grant a time-bound eligibility with -DurationDays."
}
