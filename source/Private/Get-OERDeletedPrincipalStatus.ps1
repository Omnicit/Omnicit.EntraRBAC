function Get-OERDeletedPrincipalStatus {
    <#
    .SYNOPSIS
    Tells whether a principal the directory did not return is among its deleted items.

    .DESCRIPTION
    Sprint 11 step 6 (BL-133, A18). A role assignment can name a principal that a successful
    directoryObjects/getByIds lookup did not return. This helper reads
    v1.0/directory/deletedItems/{id} once, through Invoke-OERGraphRequest with the not-found codes
    declared (Request_ResourceNotFound, ResourceNotFound and NotFound), and answers with one object:
    Id, Status, Read and Cause.

    An object in the answer means the principal is among the directory's deleted items: Status Deleted,
    Read true. The not-found marker means it is found nowhere -- deleted beyond the retention period, a
    principal of another tenant, or not readable: Status Unresolved, Read true (measured live on
    2026-10-15: an unknown id answers 404 Request_ResourceNotFound). A read that fails, and an empty
    answer, which is neither an object nor the marker, give Status Unresolved, Read false, with the
    failure's message as Cause: the status could not be read, which a caller reports as unread and
    never states as a fact. The failure's record is scrubbed first.

    It never throws and never writes an error record. With -Cache, an answer that was read (Deleted, or
    Unresolved from the marker) is kept in the dictionary under the lower-cased id and returned from
    there the next time, so each id is read once per cache; a failed read and an empty answer are not
    kept, so the next call reads again. The id is escaped into the request path. It performs no
    authentication of its own -- the caller authenticates first.

    .PARAMETER Id
    The object id of the principal to look for among the directory's deleted items.

    .PARAMETER Cache
    A dictionary that keeps the answers read, keyed on the lower-cased id. Export-OERInventory hands its
    run context's PrincipalStatus dictionary here, so an id whose read succeeds is read once per export;
    Get-OERInventory alone hands one that lives for its own invocation. A read that fails is not kept,
    so the next call for that id reads again. Without it every call reads.

    .EXAMPLE
    Get-OERDeletedPrincipalStatus -Id '11111111-1111-1111-1111-111111111111' -Cache $Cache
    Returns Status Deleted when the principal is among the directory's deleted items, Unresolved when it
    is not (Read true), and Unresolved with Read false and the Cause when the read failed.
    #>
    [OutputType([PSCustomObject])]
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$Id,

        [System.Collections.IDictionary]$Cache
    )

    $Key = $Id.ToLowerInvariant()
    # Cast first: a generic Dictionary implements IDictionary.Contains explicitly, so PowerShell finds it
    # only on the interface.
    if ($null -ne $Cache -and ([System.Collections.IDictionary]$Cache).Contains($Key)) { return $Cache[$Key] }

    try {
        $Response = Invoke-OERGraphRequest -Uri "v1.0/directory/deletedItems/$([uri]::EscapeDataString($Id))" `
            -ExpectedErrorCode 'Request_ResourceNotFound', 'ResourceNotFound', 'NotFound'
    } catch {
        Remove-OERErrorRecord -Record $PSItem
        return [PSCustomObject]@{ Id = $Id; Status = 'Unresolved'; Read = $false; Cause = [string]$PSItem.Exception.Message }
    }

    # An empty answer is neither an object nor the marker: nothing says where the principal is, so it is
    # not read, and not kept.
    if ($null -eq $Response) {
        return [PSCustomObject]@{ Id = $Id; Status = 'Unresolved'; Read = $false; Cause = 'Microsoft Graph returned an empty answer.' }
    }

    $Status = if (@($Response.PSObject.TypeNames) -contains 'Omnicit.EntraRBAC.GraphExpectedError') { 'Unresolved' } else { 'Deleted' }
    $Answer = [PSCustomObject]@{ Id = $Id; Status = $Status; Read = $true; Cause = $null }
    if ($null -ne $Cache) { $Cache[$Key] = $Answer }
    $Answer
}
