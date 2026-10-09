function Get-OERTokenRenewalThreshold {
    <#
    .SYNOPSIS
    Returns the instant at or before which the module renews a cached token.

    .DESCRIPTION
    The single owner of the module's token renewal window: five minutes from now, in UTC. A cached
    Microsoft Graph or Azure Resource Manager token that expires at or before the returned instant is
    due for renewal; one that expires after it is used as it is. Initialize-OERAuth reads it for its
    cached return, and Invoke-OERGraphRequest and Invoke-OERArmRequest read it before every request,
    to renew a delegated or managed identity session's token before it expires, and after a 401, to
    tell an expired token from one that is still valid (A11, BL-105). Never compute the window
    anywhere else.

    .OUTPUTS
    System.DateTime, in UTC.

    .EXAMPLE
    $script:_OERAuthState.GraphTokenExpiry -le (Get-OERTokenRenewalThreshold)

    True when the session's Microsoft Graph token is due for renewal.
    #>
    [CmdletBinding()]
    [OutputType([datetime])]
    param()

    [DateTime]::UtcNow.AddMinutes(5)
}
