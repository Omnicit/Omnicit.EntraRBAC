function New-OERApproverObject {
    <#
    .SYNOPSIS
    Translates an approver-spec hashtable into a Microsoft Graph approver element.

    .DESCRIPTION
    Maps a single approver specification into the corresponding Graph approver object with its
    @odata.type discriminator. Recognized spec keys: User (singleUser), Group (groupMembers),
    Manager with optional ManagerLevel (requestorManager, default level 1), InternalSponsor
    (internalSponsors), ExternalSponsor (externalSponsors). Throws on an unrecognized spec; the
    public builder catches and routes the error. This private helper is shared by the approval-stage
    and requestor-scope builders.

    .PARAMETER Spec
    A hashtable describing one approver. Exactly one of User, Group, Manager, InternalSponsor, or
    ExternalSponsor must be present as a key. When Manager is used, an optional ManagerLevel key
    (integer) sets the manager chain depth; it defaults to 1.

    .EXAMPLE
    New-OERApproverObject -Spec @{ User = 'a1b2c3d4-...' }
    Returns a singleUser approver element with the given userId.

    .EXAMPLE
    New-OERApproverObject -Spec @{ Manager = $true; ManagerLevel = 2 }
    Returns a requestorManager approver element with managerLevel 2.
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '',
        Justification = 'Pure in-memory approver-object builder; returns a hashtable and performs no state change, so ShouldProcess does not apply.')]
    [OutputType([hashtable])]
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [hashtable]$Spec
    )

    if ($Spec.ContainsKey('User')) {
        return @{ '@odata.type' = '#microsoft.graph.singleUser'; userId = [string]$Spec.User }
    }
    if ($Spec.ContainsKey('Group')) {
        return @{ '@odata.type' = '#microsoft.graph.groupMembers'; groupId = [string]$Spec.Group }
    }
    if ($Spec.ContainsKey('Manager')) {
        $Level = if ($Spec.ContainsKey('ManagerLevel')) { [int]$Spec.ManagerLevel } else { 1 }
        return @{ '@odata.type' = '#microsoft.graph.requestorManager'; managerLevel = $Level }
    }
    if ($Spec.ContainsKey('InternalSponsor')) {
        return @{ '@odata.type' = '#microsoft.graph.internalSponsors' }
    }
    if ($Spec.ContainsKey('ExternalSponsor')) {
        return @{ '@odata.type' = '#microsoft.graph.externalSponsors' }
    }
    throw "Unrecognized approver spec. Use one of: User, Group, Manager, InternalSponsor, ExternalSponsor. Got keys: $($Spec.Keys -join ', ')."
}
