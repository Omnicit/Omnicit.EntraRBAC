BeforeAll { Import-Module Omnicit.EntraRBAC -Force }

Describe 'New-OERPolicyNotificationRule' {
    It 'maps Event+Recipient to the correct rule id and tags the output' {
        $n = New-OERPolicyNotificationRule -Event Activation -Recipient Approver -Level All
        $n.PSObject.TypeNames[0] | Should -Be 'Omnicit.EntraRBAC.PolicyNotificationRule'
        $n.RuleId | Should -Be 'Notification_Approver_EndUser_Assignment'
        $n.NotificationLevel | Should -Be 'All'
    }
    It 'maps EligibleAssignment and ActiveAssignment event tokens' {
        (New-OERPolicyNotificationRule -Event EligibleAssignment -Recipient Admin -DefaultRecipientsEnabled $true).RuleId | Should -Be 'Notification_Admin_Admin_Eligibility'
        (New-OERPolicyNotificationRule -Event ActiveAssignment -Recipient Requestor -DefaultRecipientsEnabled $false).RuleId | Should -Be 'Notification_Requestor_Admin_Assignment'
    }
    It 'carries only the supplied change fields' {
        $n = New-OERPolicyNotificationRule -Event Activation -Recipient Admin -AdditionalRecipient 'person18@example.com','person22@example.com'
        $n.PSObject.Properties.Name | Should -Not -Contain 'NotificationLevel'
        $n.NotificationRecipients | Should -Contain 'person22@example.com'
    }
    It 'errors when no change field is supplied' {
        New-OERPolicyNotificationRule -Event Activation -Recipient Admin -ErrorVariable e -ErrorAction SilentlyContinue
        $e[0].FullyQualifiedErrorId | Should -Match 'NoNotificationChange'
    }
    It 'carries IsDefaultRecipientsEnabled with the supplied value' {
        $n = New-OERPolicyNotificationRule -Event EligibleAssignment -Recipient Admin -DefaultRecipientsEnabled $false
        $n.PSObject.Properties.Name | Should -Contain 'IsDefaultRecipientsEnabled'
        $n.IsDefaultRecipientsEnabled | Should -Be $false
    }
}
