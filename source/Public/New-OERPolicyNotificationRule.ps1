function New-OERPolicyNotificationRule {
    <#
    .SYNOPSIS
    Builds one notification-change input object for Set-OERRoleManagementPolicy.

    .DESCRIPTION
    Produces a tagged Omnicit.EntraRBAC.PolicyNotificationRule object that targets exactly one of the
    nine Notification_* rules of an Azure PIM role management policy, identified by -Event (which
    assignment lifecycle stage) and -Recipient (who is notified). Only the change fields actually
    supplied (-Level, -DefaultRecipientsEnabled, -AdditionalRecipient) are carried, so
    Set-OERRoleManagementPolicy overlays a subset of the notification rule (true read-modify-write).
    This is a pure input builder (no authentication, no network), mirroring
    New-OERAccessPackageApprovalStage. Pipe one or more results into
    Set-OERRoleManagementPolicy -NotificationRule.

    .PARAMETER Event
    The assignment lifecycle stage the notification rule governs: EligibleAssignment (admin makes a
    principal eligible), ActiveAssignment (admin grants an active assignment), or Activation (an
    eligible user activates).

    .PARAMETER Recipient
    Who receives the notification: Admin, Requestor, or Approver.

    .PARAMETER Level
    The notification level: All (every event) or Critical (only critical events).

    .PARAMETER DefaultRecipientsEnabled
    Whether the rule's default recipients (the role admins) also receive the notification.

    .PARAMETER AdditionalRecipient
    Extra email addresses to notify (sets the rule's notificationRecipients list).

    .EXAMPLE
    New-OERPolicyNotificationRule -Event Activation -Recipient Approver -Level All -AdditionalRecipient 'secops@contoso.com'
    Builds a change that sets the approver activation notification to All and adds an extra recipient.
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '',
        Justification = 'Pure in-memory input builder; returns an object and performs no state change, so ShouldProcess does not apply.')]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidAssignmentToAutomaticVariable', 'Event',
        Justification = 'The automatic $Event variable is only populated inside Register-ObjectEvent action blocks; in a regular function it is always null, so using it as a parameter name here has no side effect. -Event is the natural user-facing name.')]
    [OutputType([PSCustomObject])]
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('EligibleAssignment', 'ActiveAssignment', 'Activation')]
        [string]$Event,

        [Parameter(Mandatory)]
        [ValidateSet('Admin', 'Requestor', 'Approver')]
        [string]$Recipient,

        [ValidateSet('All', 'Critical')]
        [string]$Level,

        [bool]$DefaultRecipientsEnabled,

        [string[]]$AdditionalRecipient
    )
    process {
        if (-not ($PSBoundParameters.ContainsKey('Level') -or $PSBoundParameters.ContainsKey('DefaultRecipientsEnabled') -or $PSBoundParameters.ContainsKey('AdditionalRecipient'))) {
            Write-CmdletError -Message ([System.Exception]::new('Supply at least one of -Level, -DefaultRecipientsEnabled or -AdditionalRecipient.')) -ErrorId 'NoNotificationChange' -Category InvalidArgument -TargetObject "$Event/$Recipient" -Cmdlet $PSCmdlet
            return
        }

        $EventToken = switch ($Event) {
            'EligibleAssignment' { 'Admin_Eligibility' }
            'ActiveAssignment'   { 'Admin_Assignment' }
            'Activation'         { 'EndUser_Assignment' }
        }

        $Out = [PSCustomObject]@{
            RuleId        = "Notification_${Recipient}_${EventToken}"
            Event         = $Event
            RecipientType = $Recipient
        }
        if ($PSBoundParameters.ContainsKey('Level')) { $Out | Add-Member -NotePropertyName NotificationLevel -NotePropertyValue $Level }
        if ($PSBoundParameters.ContainsKey('DefaultRecipientsEnabled')) { $Out | Add-Member -NotePropertyName IsDefaultRecipientsEnabled -NotePropertyValue $DefaultRecipientsEnabled }
        if ($PSBoundParameters.ContainsKey('AdditionalRecipient')) { $Out | Add-Member -NotePropertyName NotificationRecipients -NotePropertyValue $AdditionalRecipient }

        $Out.PSObject.TypeNames.Insert(0, 'Omnicit.EntraRBAC.PolicyNotificationRule')
        $Out
    }
}
