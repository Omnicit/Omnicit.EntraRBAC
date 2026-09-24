function ConvertFrom-OERGraphApprover {
    <#
    .SYNOPSIS
    Reads one Microsoft Graph PIM approver into a flat Id, UserType and DisplayName object.

    .DESCRIPTION
    The single owner of how a Microsoft Graph approver (a subjectSet in an approval stage) is read.
    Graph returns the same approver in two shapes: v1.0 and every PATCH body carry the object id as
    userId (#microsoft.graph.singleUser) or groupId (#microsoft.graph.groupMembers), while the beta
    endpoint PIM for Groups is pinned to returns it as id -- a group approver read from beta has no
    groupId at all. Reading groupId alone made every beta-read group approver id-less, so a declared
    approver list never matched the live one and every apply rewrote the rule. This helper reads
    userId or groupId with id as the fallback for both, and derives UserType from @odata.type ('User'
    or 'Group'), falling back to whichever of userId or groupId is present when the discriminator is
    missing. Any other approver kind (for example requestorManager) is returned with an empty
    UserType and its id, if it has one, so a caller can pass it through untouched. The output shape
    matches the approver shape ConvertTo-OERRoleManagementPolicy produces for Azure Resource Manager.
    Accepts a hashtable or a PSCustomObject. Pure; no Graph call.

    .PARAMETER Approver
    One approver object from an approval stage's primaryApprovers or escalationApprovers, as read from
    Microsoft Graph or as built by New-OERApproverObject.

    .EXAMPLE
    ConvertFrom-OERGraphApprover -Approver $Stage.primaryApprovers[0]
    Returns an object with the approver's object id in Id and User or Group in UserType.
    #>
    [OutputType([PSCustomObject])]
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowNull()]
        [object]$Approver
    )
    if ($null -eq $Approver) { return }

    $Type = [string]$Approver.'@odata.type'
    $UserId = [string]$Approver.userId
    $GroupId = [string]$Approver.groupId
    $RawId = [string]$Approver.id

    $UserType = ''
    if ($Type -match '(?i)^#?microsoft\.graph\.singleUser$') { $UserType = 'User' }
    elseif ($Type -match '(?i)^#?microsoft\.graph\.groupMembers$') { $UserType = 'Group' }
    elseif (-not $Type -and $UserId) { $UserType = 'User' }
    elseif (-not $Type -and $GroupId) { $UserType = 'Group' }

    $Id = $RawId
    if ($UserType -eq 'User' -and $UserId) { $Id = $UserId }
    elseif ($UserType -eq 'Group' -and $GroupId) { $Id = $GroupId }

    [PSCustomObject]@{
        Id          = $Id
        UserType    = $UserType
        DisplayName = [string]$Approver.description
    }
}
