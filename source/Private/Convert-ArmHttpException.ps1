using namespace System.Management.Automation

function Convert-ArmHttpException {
    <#
    .SYNOPSIS
    Converts a non-success Azure Resource Manager HTTP response into a structured ErrorRecord.

    .DESCRIPTION
    Sibling of Convert-GraphHttpException for the ARM side. This module never calls
    Invoke-AzRestMethod: Invoke-OERArmRequest sends every ARM request directly with
    Invoke-WebRequest -SkipHttpErrorCheck, so a non-2xx response is returned rather than thrown, and
    is normalized to a plain object exposing StatusCode, Content and the raw response Headers before
    it ever reaches this helper. This helper reads StatusCode and Content only: the header collection
    is deliberately never consulted, never included in the message, and never attached to the
    ErrorRecord, since ARM response headers carry correlation ids and quota telemetry that have no
    place in an error surfaced to a caller. This helper parses the ARM error body ({ "error": { "code", "message", "details" } })
    from the response content and builds an ErrorRecord whose FullyQualifiedErrorId is the ARM error
    code. When error.details[] is present -- ARM's nested-reason shape for an otherwise opaque
    top-level code such as InvalidPolicy -- each detail's own code/message pair is appended in
    parentheses, so the surfaced message names which policy rule or field is wrong instead of just
    repeating the generic top-level message. When the body is not pure JSON the code and message are
    extracted with targeted regular expressions. When no code can be found at all, a label is
    derived from the HTTP status (400=BadRequest, 401=Unauthorized, 403=Forbidden, 404=NotFound,
    409=Conflict, 429=TooManyRequests, 500=InternalServerError, 503=ServiceUnavailable, otherwise
    HTTP<status>) so authorization and throttling failures always surface clearly. ErrorDetails is
    set via the constructor. No exception chaining is performed, keeping parity with the Graph
    converter's bearer-token hygiene posture.

    .PARAMETER Response
    The normalized ARM response object built by Invoke-OERArmRequest -- NOT the PSHttpResponse
    Invoke-AzRestMethod would have returned, since this module never calls that cmdlet. Only the
    StatusCode and Content properties are read; a Headers property, when present, is ignored.

    .PARAMETER Path
    Optional ARM request path used as the TargetObject of the resulting ErrorRecord for caller
    diagnostics.

    .EXAMPLE
    throw (Convert-ArmHttpException -Response $Response -Path $Path)
    Converts a failed ARM response into a typed ErrorRecord and throws it to the caller.
    #>
    [OutputType([ErrorRecord])]
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$Response,

        [string]$Path
    )

    $StatusCode = 0
    try { $StatusCode = [int]$Response.StatusCode } catch { Remove-OERErrorRecord -Record $PSItem }
    $Content = [string]$Response.Content

    $ErrorCode = $null
    $ErrorMessage = $null
    $NestedDetail = $null
    if ($Content) {
        # Preferred path: clean ARM error JSON. -ErrorAction Stop makes a parse failure terminating
        # so the catch actually runs and the failure can be removed from $Error.
        try {
            $ErrorInfo = ($Content | ConvertFrom-Json -ErrorAction Stop).error
            if ($ErrorInfo) {
                $ErrorCode    = [string]$ErrorInfo.code
                $ErrorMessage = [string]$ErrorInfo.message
                # ARM hides the actionable reason for opaque top-level codes (e.g. InvalidPolicy --
                # which policy rule/field is wrong) under error.details[]. Surface those nested
                # code/message pairs so the failure is diagnosable instead of just "The policy is
                # invalid". Only appended when present, so simple errors keep their plain message.
                if ($ErrorInfo.details) {
                    $DetailParts = foreach ($Item in @($ErrorInfo.details)) {
                        $ItemCode = [string]$Item.code
                        $ItemMessage = [string]$Item.message
                        if ($ItemCode -and $ItemMessage) { "$ItemCode`: $ItemMessage" }
                        elseif ($ItemMessage) { $ItemMessage }
                        elseif ($ItemCode) { $ItemCode }
                    }
                    $DetailParts = @($DetailParts | Where-Object { $_ })
                    if ($DetailParts.Count -gt 0) { $NestedDetail = $DetailParts -join '; ' }
                }
            }
        } catch {
            Remove-OERErrorRecord -Record $PSItem
        }

        # Fallback: pull the first embedded code/message out of wrapped text.
        if (-not $ErrorMessage -and $Content -match '"message"\s*:\s*"([^"]+)"') { $ErrorMessage = $Matches[1] }
        if (-not $ErrorCode    -and $Content -match '"code"\s*:\s*"([^"]+)"')    { $ErrorCode    = $Matches[1] }
    }

    if (-not $ErrorCode) {
        $StatusLabels = @{
            400 = 'BadRequest'; 401 = 'Unauthorized'; 403 = 'Forbidden'; 404 = 'NotFound'
            409 = 'Conflict'; 429 = 'TooManyRequests'; 500 = 'InternalServerError'; 503 = 'ServiceUnavailable'
        }
        $ErrorCode = if ($StatusLabels.ContainsKey($StatusCode)) { $StatusLabels[$StatusCode] }
        elseif ($StatusCode) { "HTTP$StatusCode" }
        else { 'ArmError' }
    }

    $Detail = if ($ErrorMessage) { "$ErrorCode`: $ErrorMessage" } else { [string]$ErrorCode }
    if ($NestedDetail) { $Detail = "$Detail ($NestedDetail)" }
    $NewException = [System.Exception]::new($Detail)
    $ErrorRecord = [ErrorRecord]::new(
        $NewException,
        $ErrorCode,
        [System.Management.Automation.ErrorCategory]::OperationStopped,
        $Path
    )
    $ErrorRecord.ErrorDetails = [System.Management.Automation.ErrorDetails]::new($Detail)
    return $ErrorRecord
}
