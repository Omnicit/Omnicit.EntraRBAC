function ConvertTo-OERAuthenticationContext {
    <#
    .SYNOPSIS
    Converts a Graph authenticationContextClassReference into a tagged module object.

    .DESCRIPTION
    Single owner of the Omnicit.EntraRBAC.AuthenticationContext output shape. Maps the Graph
    authenticationContextClassReference response (id, displayName, description, isAvailable) onto the
    module's property names, coercing isAvailable to a real boolean because Graph omits the field
    entirely on some tenants and an absent value must read as not-published rather than as null.

    .PARAMETER InputObject
    One authenticationContextClassReference object as returned by Invoke-OERGraphRequest.

    .EXAMPLE
    ConvertTo-OERAuthenticationContext -InputObject $Response
    Converts a single authentication context into a tagged object.
    #>
    [OutputType([PSCustomObject])]
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
        $InputObject
    )
    process {
        $Out = [PSCustomObject]@{
            AuthenticationContextId = [string]$InputObject.id
            DisplayName             = [string]$InputObject.displayName
            Description             = [string]$InputObject.description
            IsAvailable             = [bool]$InputObject.isAvailable
        }
        $Out.PSObject.TypeNames.Insert(0, 'Omnicit.EntraRBAC.AuthenticationContext')
        $Out
    }
}
