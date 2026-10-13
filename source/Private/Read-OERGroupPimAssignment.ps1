function Read-OERGroupPimAssignment {
    <#
    .SYNOPSIS
    Reads a group's PIM for Groups assignment schedule instances and returns the read or its failure.

    .DESCRIPTION
    The single reader of a group's PIM for Groups assignment schedule instances (BL-125, A3): ONE
    Invoke-OERGraphRequest read of identityGovernance/privilegedAccess/group/assignmentScheduleInstances
    filtered on the group id, every page, through the pinned PIM for Groups path
    (Get-OERPimGroupsGraphPath). Microsoft Graph lists there every direct member and owner of the
    group -- a standing membership or ownership added outside PIM as well as an activation or a
    time-bound active assignment -- also for a group never onboarded to PIM for Groups (measured live
    2026-10-13). An eligibility is not listed there. Get-OERGroupPimHeldAccess reads the instances and
    owns the rule that tells a standing one from one PIM for Groups holds.

    It returns ONE tagged Omnicit.EntraRBAC.GroupPimAssignmentRead object and never writes an error
    record:
    - Read: true when the read succeeded, false when it failed.
    - Value: the instances read; an empty array when the read succeeded and found none; null when
      the read failed. A failed read is never an empty one.
    - Message: null on success; on failure 'Could not read the PIM for Groups assignments of group
      <id>: <reason>.'
    - Exception: the failure's exception, or null.

    The request declares ResourceTypeNotSupported to the transport as an answer, as the eligibility
    read does (R10): a group PIM for Groups cannot manage then comes back as the transport's marker and
    is returned as a successful, empty read. That answer is not measured for this endpoint (a group
    never onboarded answered 200 with its members and owners). Every failure that arrives thrown, of
    any kind and whatever its code, is returned as unread, the safe direction: a caller that cannot
    tell a standing member from one PIM for Groups holds writes neither as standing. The catch scrubs
    the record first (Remove-OERErrorRecord).

    Call it only for a group whose id is known; it makes no sign-in of its own, so the calling command
    must already have signed in (Initialize-OERAuth).

    .PARAMETER GroupId
    The object id of the group whose assignment schedule instances are read. An empty or null id is
    accepted rather than refused at binding, so a caller is never ended outside its own try by a
    binding error, and the request is sent with the id as given, as the eligibility read does.

    .EXAMPLE
    $Read = Read-OERGroupPimAssignment -GroupId $Group.Id
    if ($Read.Read) { $Held = @(Get-OERGroupPimHeldAccess -Assignment @($Read.Value)) }
    else { Write-Verbose $Read.Message }
    Reads a group's PIM for Groups assignment schedule instances and, when the read succeeded, asks
    the rule which members and owners PIM for Groups holds.
    #>
    [OutputType([PSCustomObject])]
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowNull()]
        [AllowEmptyString()]
        [string]$GroupId
    )

    # Untyped Message on purpose: a [string] parameter turns $null into '', and a read that succeeded
    # carries no error text at all rather than an empty one.
    $Result = {
        param([bool]$Read, [object[]]$Value, $Message, [System.Exception]$Exception)
        $O = [PSCustomObject]@{
            Read      = $Read
            Value     = $Value
            Message   = $Message
            Exception = $Exception
        }
        $O.PSObject.TypeNames.Insert(0, 'Omnicit.EntraRBAC.GroupPimAssignmentRead')
        $O
    }

    try {
        # -ExpectedErrorCode, not a catch: declared at the REQUEST, so the answer arrives as a marker and
        # raises no PowerShell error anywhere in the chain (the reason is the eligibility read's, in
        # Read-OERGroupCollection). Unlike that read, a thrown record is never recognised afterwards:
        # whatever arrives thrown is unread.
        $Response = Invoke-OERGraphRequest -Uri (Get-OERPimGroupsGraphPath -Path ("identityGovernance/privilegedAccess/group/assignmentScheduleInstances?`$filter=groupId eq '{0}'" -f $GroupId)) -All -ExpectedErrorCode 'ResourceTypeNotSupported'
    } catch {
        Remove-OERErrorRecord -Record $PSItem
        return (& $Result $false $null "Could not read the PIM for Groups assignments of group $($GroupId): $($PSItem.Exception.Message)." $PSItem.Exception)
    }

    if (@($Response.PSObject.TypeNames) -contains 'Omnicit.EntraRBAC.GraphExpectedError') {
        # The declared answer: a read that SUCCEEDED in telling us there is nothing listed.
        return (& $Result $true @() $null $null)
    }
    # The null-filter is load-bearing: an answer without a value would otherwise become @($null), one
    # instance that is not there.
    $Instances = @(@($Response.value) | Where-Object { $null -ne $PSItem })
    return (& $Result $true $Instances $null $null)
}
