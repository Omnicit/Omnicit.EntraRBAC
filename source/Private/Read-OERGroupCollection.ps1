function Read-OERGroupCollection {
    <#
    .SYNOPSIS
    Reads one per-group collection (members, owners or PIM eligibility) and returns the read or its
    failure.

    .DESCRIPTION
    The single reader of the three per-group collections Get-OERGroup attaches: the members and the
    owners (through Get-OERGroupRelation, which reads the untyped and the typed service principal
    collection and emits nothing unless both succeed) and the PIM-for-Groups eligibility schedule
    instances (one Invoke-OERGraphRequest read).

    It returns ONE tagged Omnicit.EntraRBAC.GroupCollectionRead object and never writes an error
    record: a failed read comes back with Read false, Value null, and the ErrorId, Message and
    Exception a caller needs to publish it. Message is the exact text Get-OERGroup publishes. The
    caller decides what to do with a failure, so a failed read is never mistaken for an empty
    collection -- Value is an empty array only when the read SUCCEEDED and found nothing.

    The eligibility read declares ResourceTypeNotSupported to the transport at the request, so a
    group that is not onboarded to PIM for Groups comes back as a marker and is returned as a
    successful, empty read. The same answer arriving THROWN is recognised too, by the Graph error
    code as a whole token. Every other failure is returned as unread.

    Call it only for a group whose id is known; it makes no sign-in of its own, so the calling
    command must already have signed in (Initialize-OERAuth).

    .PARAMETER GroupId
    The object id of the group whose collection is read.

    .PARAMETER Collection
    Which collection to read: Members, Owners or PimEligibility.

    .EXAMPLE
    $Read = Read-OERGroupCollection -GroupId $Group.Id -Collection Owners
    if (-not $Read.Read) { Write-Verbose $Read.Message }
    Reads the owners of a group and reports the failure text when the read did not succeed.
    #>
    [OutputType([PSCustomObject])]
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$GroupId,

        [Parameter(Mandatory)]
        [ValidateSet('Members', 'Owners', 'PimEligibility')]
        [string]$Collection
    )

    # Untyped ErrorId and Message on purpose: a [string] parameter turns $null into '', and a read
    # that succeeded carries no error text at all rather than an empty one.
    $Result = {
        param([bool]$Read, [object[]]$Value, $ErrorId, $Message, [System.Exception]$Exception)
        $O = [PSCustomObject]@{
            Collection = $Collection
            Read       = $Read
            Value      = $Value
            ErrorId    = $ErrorId
            Message    = $Message
            Exception  = $Exception
        }
        $O.PSObject.TypeNames.Insert(0, 'Omnicit.EntraRBAC.GroupCollectionRead')
        $O
    }

    switch ($Collection) {
        'Members' {
            # A failed read is NOT an empty membership. Substituting @() made a throttled or
            # permission-denied read indistinguishable from a group that genuinely has none, and
            # Get-OERInventory wrote that @() into an apply document as a fact -- which
            # Invoke-OERStructure -Prune then deletes on (issue #76). Omitting the property
            # instead keeps the two cases apart, and the error is non-terminating so
            # -ErrorAction and -ErrorVariable can see it; a Write-Warning could not be. This
            # function returns the failure; the caller (Get-OERGroup) does the omitting and
            # writes the error.
            try {
                # Get-OERGroupRelation is the single reader of a group's members: the untyped
                # v1.0 read leaves service principals out, so it adds the typed read, and it
                # emits nothing unless both reads succeed. It also tags each member through the
                # shared ConvertTo-OERGroupMember, so Members carries formatted
                # Omnicit.EntraRBAC.GroupMember objects instead of raw Graph dictionaries.
                $Members = @(Get-OERGroupRelation -GroupId $GroupId -Relation members)
            } catch {
                Remove-OERErrorRecord -Record $PSItem
                return (& $Result $false $null 'GroupMemberReadFailed' "Could not read members for group $($GroupId): $($PSItem.Exception.Message). The Members property is omitted rather than reported as empty." $PSItem.Exception)
            }
            return (& $Result $true $Members $null $null $null)
        }
        'Owners' {
            # Same rule as members above: a failed read omits the property instead of claiming
            # an empty owner set, and errors instead of warning.
            try {
                # The same single reader as the Members branch above: the untyped owners
                # read leaves service principals out too, so the helper adds the typed read,
                # tags each owner (MemberType Owner), and emits nothing unless both succeed.
                $Owners = @(Get-OERGroupRelation -GroupId $GroupId -Relation owners)
            } catch {
                Remove-OERErrorRecord -Record $PSItem
                return (& $Result $false $null 'GroupOwnerReadFailed' "Could not read owners for group $($GroupId): $($PSItem.Exception.Message). The Owners property is omitted rather than reported as empty." $PSItem.Exception)
            }
            return (& $Result $true $Owners $null $null $null)
        }
        'PimEligibility' {
            $Elig = $null
            try {
                # -ExpectedErrorCode, not a catch: a group that is not onboarded to PIM for
                # Groups answers 400 ResourceTypeNotSupported on this beta endpoint, and that is
                # an ANSWER -- there is no eligibility -- not a failure. Declaring it makes the
                # wrapper return a marker instead of raising, so the not-onboarded case produces
                # no PowerShell error anywhere in the chain. It has to be declared at the
                # REQUEST, not recognised afterwards: a live Get-OERInventory read of 100 groups,
                # 96 of them not onboarded, put 261 records into the caller's -ErrorVariable even
                # though Get-OERGroup published none of them, because -ErrorVariable is filled by
                # the ENGINE and collects records raised inside nested calls that an inner catch
                # already swallowed. Nothing a catch here can do reaches those.
                $EligResponse = Invoke-OERGraphRequest -Uri (Get-OERPimGroupsGraphPath -Path ("identityGovernance/privilegedAccess/group/eligibilityScheduleInstances?`$filter=groupId eq '{0}'" -f $GroupId)) -All -ExpectedErrorCode 'ResourceTypeNotSupported'
                if (@($EligResponse.PSObject.TypeNames) -contains 'Omnicit.EntraRBAC.GraphExpectedError') {
                    # Not onboarded. A read that SUCCEEDED in telling us there is no eligibility,
                    # so the property is PRESENT and empty -- never omitted, which is what a
                    # failed read means here (issue #76).
                    $Elig = @()
                }
                else {
                    $Elig = @($EligResponse.value)
                }
            } catch {
                Remove-OERErrorRecord -Record $PSItem
                # The block below answers the same condition arriving THROWN rather than as the
                # marker above -- when this function's wrapper is mocked, or when a frame between
                # the two re-raises the record. IT IS NOT A BACKUP FOR THE WRAPPER'S GATE, and
                # the wrapper's gate is not a backup for this one: the two answer DIFFERENT
                # ARRIVAL SHAPES. Measured, not reasoned -- softening the wrapper's
                # Get-ExpectedGraphErrorMatch to an unconditional match with this block fully
                # intact brought the defect back completely and SILENTLY (PimEligibility
                # present, Count 0, zero error records), since a softened failure arrives as a
                # marker and never reaches this catch at all. Softening only this block instead
                # leaves PimEligibility = @() with 5 records. The wrapper's gate is the one that
                # fires in production. Keep the token rule here and in the wrapper in step, and
                # never delete either one on the strength of the other. Every other failure omits
                # the property and errors, same as members and owners above.
                #
                # MATCHED ON THE GRAPH ERROR CODE AS A WHOLE TOKEN, not on one exact
                # FullyQualifiedErrorId spelling. The code is the reliable signal; where the
                # converted record carries it is not:
                #
                #   * Convert-GraphHttpException builds the record with the Graph error.code as
                #     its ErrorId, so a record raised straight out of Invoke-OERGraphRequest
                #     reads 'ResourceTypeNotSupported'. But a FullyQualifiedErrorId is composed
                #     from every frame that re-raises the record, and the code is not always the
                #     FIRST comma-separated segment -- 'PathNotFound,Get-ItemCommand' is the
                #     engine's own shape. A prefix-only -like therefore misses it there.
                #   * When the error body cannot be parsed the converter falls back to a
                #     status-derived id ('BadRequest'), leaving the code only in the record's
                #     detail text.
                #   * A prefix-only -like also OVER-matches: a genuinely different code such as
                #     ResourceTypeNotSupportedInThisTenant would be swallowed as "no
                #     eligibility", turning a failed read into a silent empty collection -- the
                #     exact failure mode the members/owners handling above exists to prevent.
                #     A whole-token comparison refuses both mistakes.
                #
                # THE DETAIL TEXT IS A SECOND-CHOICE SOURCE, read ONLY when the id is one the
                # converter derived from the HTTP status rather than from a code Graph named
                # (its $StatusLabels vocabulary, 'HTTP<status>', or 'GraphError' -- keep this
                # pattern in step with that table, and with Invoke-OERGraphRequest's
                # Test-StatusDerivedErrorId, which carries the identical rule for the record
                # that arrives as a marker). Reading it unconditionally was a defect: a genuine
                #   {"code":"Authorization_RequestDenied",
                #    "message":"Insufficient privileges: ResourceTypeNotSupported"}
                # split on ':' yields 'ResourceTypeNotSupported' as a whole segment, so a real
                # 403 was recorded as PimEligibility = @() -- a failed read stored as an empty
                # fact, which is exactly what this block exists to prevent. When Graph has named
                # the failure, its name is the answer and the prose is not consulted.
                #
                # Splitting on ',' (FullyQualifiedErrorId composition) and ':' (the converter's
                # "<code>: <message>" detail form) and requiring an EXACT, case-insensitive
                # segment match is what makes this a token test rather than a substring test.
                #
                # $EligError, not $PSItem, inside the pipelines below: ForEach-Object rebinds
                # $PSItem to the string being trimmed, which would silently shadow the caught
                # record if the record were read there.
                $EligError = $PSItem
                [string[]]$ErrorIdSegment = @(([string]$EligError.FullyQualifiedErrorId) -split ',') |
                    ForEach-Object { $PSItem.Trim() }
                [string[]]$ErrorCodeCandidate = $ErrorIdSegment
                $StatusDerivedId = '^(?:BadRequest|Unauthorized|Forbidden|NotFound|Conflict|TooManyRequests|' +
                    'InternalServerError|ServiceUnavailable|GraphError|HTTP\d+)$'
                if (@($ErrorIdSegment | Where-Object { $PSItem -match $StatusDerivedId }).Count -gt 0) {
                    $ErrorCodeCandidate = @(
                        $ErrorIdSegment
                        ([string]$EligError.ErrorDetails.Message) -split ':'
                        ([string]$EligError.Exception.Message) -split ':'
                    ) | ForEach-Object { $PSItem.Trim() }
                }
                if ($ErrorCodeCandidate -contains 'ResourceTypeNotSupported') {
                    $Elig = @()
                } else {
                    return (& $Result $false $null 'GroupPimEligibilityReadFailed' "Could not read PIM eligibility for group $($GroupId): $($PSItem.Exception.Message). The PimEligibility property is omitted rather than reported as empty." $PSItem.Exception)
                }
            }
            return (& $Result $true $Elig $null $null $null)
        }
    }
}
