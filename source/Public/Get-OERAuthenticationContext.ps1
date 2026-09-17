function Get-OERAuthenticationContext {
    <#
    .SYNOPSIS
    Lists the Conditional Access authentication contexts defined in the tenant.

    .DESCRIPTION
    Reads identity/conditionalAccess/authenticationContextClassReferences through
    Invoke-OERGraphRequest and returns one tagged Omnicit.EntraRBAC.AuthenticationContext object per
    context, carrying the claim value, display name, description, and whether it is published. This
    is the same list the Microsoft Entra portal offers when a PIM policy asks for an authentication
    context on activation, and the portal offers only published ones -- so -Available narrows the
    result to the contexts that can actually be required. Graph does not validate a claim value on
    write, so an unpublished or non-existent context is accepted by a policy update and only fails
    later, for end users at activation time. A tenant with no contexts returns nothing, not an error.

    .PARAMETER Id
    Return only the context with this claim value (for example c1). Must look like the letter c
    followed by digits. When omitted, every context in the tenant is returned.

    .PARAMETER Available
    Return only contexts that are published (isAvailable), matching what the portal offers when a
    policy asks for an authentication context.

    .PARAMETER TenantId
    Optional tenant id or domain to authenticate against, forwarded to Initialize-OERAuth.

    .EXAMPLE
    Get-OERAuthenticationContext
    Lists every authentication context defined in the tenant, published or not.

    .EXAMPLE
    Get-OERAuthenticationContext -Available
    Lists only the published contexts, the ones a PIM policy can actually require.

    .EXAMPLE
    Get-OERAuthenticationContext -Id 'c1'
    Returns the single context whose claim value is c1, or nothing when it does not exist.
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [ValidatePattern('^c\d+$')]
        [Alias('AuthenticationContextId')]
        [string]$Id,

        [switch]$Available,

        [string]$TenantId
    )
    begin {
        $AuthParams = @{}
        if ($TenantId) { $AuthParams.TenantId = $TenantId }
        Initialize-OERAuth @AuthParams
    }
    process {
        try {
            $Response = Invoke-OERGraphRequest -Uri 'v1.0/identity/conditionalAccess/authenticationContextClassReferences' -All
        } catch {
            Remove-OERErrorRecord -Record $PSItem
            Write-CmdletError `
                -Message ([System.Exception]::new("Could not read the tenant's authentication contexts: $($PSItem.Exception.Message)")) `
                -ErrorId 'AuthenticationContextReadFailed' `
                -Category ReadError `
                -TargetObject 'authenticationContextClassReferences' `
                -Cmdlet $PSCmdlet
            return
        }

        foreach ($Item in @($Response.value)) {
            if ($null -eq $Item) { continue }
            $Context = ConvertTo-OERAuthenticationContext -InputObject $Item
            if ($Id -and $Context.AuthenticationContextId -ne $Id) { continue }
            if ($Available -and -not $Context.IsAvailable) { continue }
            $Context
        }
    }
}
