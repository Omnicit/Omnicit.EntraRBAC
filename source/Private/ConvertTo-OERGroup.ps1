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
    cloud. MailEnabled carries Graph's mailEnabled as a boolean, or empty when Graph gave none, so
    a group's type can be read from SecurityEnabled, MailEnabled and GroupTypes together. Visibility
    carries Graph's visibility (Public, Private or HiddenMembership), or empty when Graph gave none,
    which is the case for most security groups. CreatedDateTime carries the time Graph gave for the
    group's creation as an ISO 8601 UTC string (yyyy-MM-ddTHH:mm:ssZ) whatever form it arrives in,
    or empty when it is missing or cannot be read. This private converter is the single owner of the
    group output shape and is used by New-OERGroup, Get-OERGroup, and Set-OERGroup.

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

        # Graph's createdDateTime reaches this converter in one of three forms: a [DateTime] (the Graph
        # SDK's own conversion of the JSON string, measured), a [DateTimeOffset], or the ISO 8601
        # string. All three are written as one UTC string. A [DateTime] of unspecified kind is taken
        # as UTC and never converted from local time; anything unreadable is empty, not an error.
        $CreatedDateTimeUtc = $null
        $CreatedRaw = $InputObject.createdDateTime
        if ($CreatedRaw -is [datetime]) {
            $CreatedUtc = if ($CreatedRaw.Kind -eq [System.DateTimeKind]::Unspecified) {
                [datetime]::SpecifyKind($CreatedRaw, [System.DateTimeKind]::Utc)
            } else {
                $CreatedRaw.ToUniversalTime()
            }
            $CreatedDateTimeUtc = $CreatedUtc.ToString("yyyy-MM-dd'T'HH:mm:ss'Z'", [System.Globalization.CultureInfo]::InvariantCulture)
        } elseif ($CreatedRaw -is [System.DateTimeOffset]) {
            $CreatedDateTimeUtc = $CreatedRaw.UtcDateTime.ToString("yyyy-MM-dd'T'HH:mm:ss'Z'", [System.Globalization.CultureInfo]::InvariantCulture)
        } elseif ($CreatedRaw -is [string] -and -not [string]::IsNullOrWhiteSpace($CreatedRaw)) {
            $CreatedParsed = [System.DateTimeOffset]::MinValue
            $CreatedStyles = [System.Globalization.DateTimeStyles]::AssumeUniversal -bor [System.Globalization.DateTimeStyles]::AdjustToUniversal
            if ([System.DateTimeOffset]::TryParse($CreatedRaw, [System.Globalization.CultureInfo]::InvariantCulture, $CreatedStyles, [ref]$CreatedParsed)) {
                $CreatedDateTimeUtc = $CreatedParsed.UtcDateTime.ToString("yyyy-MM-dd'T'HH:mm:ss'Z'", [System.Globalization.CultureInfo]::InvariantCulture)
            }
        }

        $Out = [PSCustomObject]@{
            Id                            = $InputObject.id
            DisplayName                   = $InputObject.displayName
            Description                   = $InputObject.description
            MailNickname                  = $InputObject.mailNickname
            GroupType                     = $GroupType
            SecurityEnabled               = $InputObject.securityEnabled
            # Graph's mailEnabled, read the way OnPremisesSyncEnabled is: a boolean is the answer, and
            # anything else (missing, null, a string) is no answer and reads as empty.
            MailEnabled                   = if ($InputObject.mailEnabled -is [bool]) { [bool]$InputObject.mailEnabled } else { $null }
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
            # Graph's visibility (Public, Private, HiddenMembership), null on most security groups.
            Visibility                    = if ([string]::IsNullOrEmpty([string]$InputObject.visibility)) { $null } else { [string]$InputObject.visibility }
            # The creation time as one UTC ISO 8601 string, whatever form Graph's value arrived in.
            CreatedDateTime               = $CreatedDateTimeUtc
        }
        $Out.PSObject.TypeNames.Insert(0, 'Omnicit.EntraRBAC.Group')
        $Out
    }
}
