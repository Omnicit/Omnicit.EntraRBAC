function ConvertTo-OERGroup {
    <#
    .SYNOPSIS
    Converts a raw Microsoft Graph group object into a tagged Omnicit.EntraRBAC.Group object.

    .DESCRIPTION
    Maps the relevant properties of a Graph group (returned by Invoke-OERGraphRequest as a hashtable)
    into a [PSCustomObject] tagged with the type name Omnicit.EntraRBAC.Group so Format and Types views
    apply. A friendly GroupType is derived: RoleEnabled when isAssignableToRole is true, Dynamic when
    groupTypes contains DynamicMembership, otherwise Regular. OnPremisesSyncEnabled carries Graph's
    onPremisesSyncEnabled as it is: True for a group synchronized from on-premises, False for one that
    no longer is, empty for one that never was, or whose source of authority was converted to the
    cloud. This private converter is the single owner of the group output shape and is used by
    New-OERGroup, Get-OERGroup, and Set-OERGroup.

    .PARAMETER InputObject
    The raw Graph group object (hashtable or PSObject) to convert into a tagged group object.

    .EXAMPLE
    $Group = ConvertTo-OERGroup -InputObject (Invoke-OERGraphRequest -Uri 'v1.0/groups/gid-1')
    Converts a single fetched group into a tagged Omnicit.EntraRBAC.Group object.
    #>
    [OutputType([PSCustomObject])]
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
        $InputObject
    )
    process {
        $GroupTypes = @($InputObject.groupTypes)
        $GroupType = if ($InputObject.isAssignableToRole) { 'RoleEnabled' }
            elseif ($GroupTypes -contains 'DynamicMembership') { 'Dynamic' }
            else { 'Regular' }

        $Out = [PSCustomObject]@{
            Id                            = $InputObject.id
            DisplayName                   = $InputObject.displayName
            Description                   = $InputObject.description
            MailNickname                  = $InputObject.mailNickname
            GroupType                     = $GroupType
            SecurityEnabled               = $InputObject.securityEnabled
            IsAssignableToRole            = [bool]$InputObject.isAssignableToRole
            GroupTypes                    = $GroupTypes
            MembershipRule                = $InputObject.membershipRule
            MembershipRuleProcessingState = $InputObject.membershipRuleProcessingState
            # Graph's own tri-state, carried as it is (Microsoft Learn, group resource type): true
            # while the group is synchronized from on-premises, false once it no longer is, null when
            # it never was (or its source of authority was converted to the cloud). A value that is
            # not a boolean is not an answer and reads as empty, never as true.
            # Test-OERGroupOnPremisesSynced is the single reader of what it means.
            OnPremisesSyncEnabled         = if ($InputObject.onPremisesSyncEnabled -is [bool]) { [bool]$InputObject.onPremisesSyncEnabled } else { $null }
        }
        $Out.PSObject.TypeNames.Insert(0, 'Omnicit.EntraRBAC.Group')
        $Out
    }
}
