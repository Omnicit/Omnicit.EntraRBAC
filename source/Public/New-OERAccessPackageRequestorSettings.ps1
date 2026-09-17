function New-OERAccessPackageRequestorSettings {
    <#
    .SYNOPSIS
    Builds a requestor-settings object for an access package assignment policy.

    .DESCRIPTION
    Returns a tagged Omnicit.EntraRBAC.RequestorSettings object describing who may request an
    access package, for use with the -RequestorSettings parameter of
    New/Set-OERAccessPackageAssignmentPolicy. All parameters are optional switches; omitting them
    all produces an admin-only (all-false) settings object. When -AllowManagerRequest is set, a
    requestorManager onBehalfRequestor entry is included with the given -ManagerLevel. The object
    carries a GraphRequestorSettings member holding the Graph-ready
    accessPackageAssignmentRequestorSettings body for direct insertion into the policy body.

    .PARAMETER AllowSelfRequest
    Allow the target user to request access for themselves
    (enableTargetsToSelfAddAccess = $true).

    .PARAMETER AllowManagerRequest
    Allow the requestor's manager to submit a request on their behalf. Adds a requestorManager
    entry to onBehalfRequestors (enableOnBehalfRequestorsToAddAccess = $true).

    .PARAMETER ManagerLevel
    The manager chain depth used with -AllowManagerRequest. Defaults to 1 (direct manager).

    .PARAMETER AllowCustomSchedule
    Allow the requestor to specify a custom assignment schedule when requesting access
    (allowCustomAssignmentSchedule = $true).

    .PARAMETER AllowSelfExtend
    Allow the target user to extend their own assignment before it expires
    (enableTargetsToSelfUpdateAccess = $true).

    .PARAMETER AllowSelfRemove
    True allows requestors to create a request to remove their own access before it expires
    (enableTargetsToSelfRemoveAccess = $true). Declared last so existing positional callers are
    unaffected.

    .PARAMETER AllowOnBehalfUpdate
    True allows on-behalf-of requestors to create a request to update a target user's access
    (enableOnBehalfRequestorsToUpdateAccess = $true). Declared last so existing positional
    callers are unaffected.

    .PARAMETER AllowOnBehalfRemove
    True allows on-behalf-of requestors to create a request to remove a target user's access
    (enableOnBehalfRequestorsToRemoveAccess = $true). Declared last so existing positional
    callers are unaffected.

    .EXAMPLE
    New-OERAccessPackageRequestorSettings -AllowSelfRequest
    Builds a settings object that allows targets to request access for themselves.

    .EXAMPLE
    New-OERAccessPackageRequestorSettings -AllowManagerRequest -ManagerLevel 2
    Builds a settings object that allows a skip-level manager to request on behalf of a user.

    .EXAMPLE
    New-OERAccessPackageRequestorSettings -AllowSelfRequest -AllowCustomSchedule -AllowSelfExtend
    Builds a settings object with self-request, custom schedule, and self-extend all enabled.
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '',
        Justification = 'Read-only builder; constructs and returns an in-memory object, performs no state change.')]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseSingularNouns', '',
        Justification = 'The plural noun RequestorSettings mirrors the Graph accessPackageAssignmentRequestorSettings resource and the -RequestorSettings parameter it builds; a singular form would obscure that mapping.')]
    [OutputType([PSCustomObject])]
    [CmdletBinding()]
    param(
        [switch]$AllowSelfRequest,

        [switch]$AllowManagerRequest,

        [int]$ManagerLevel = 1,

        [switch]$AllowCustomSchedule,

        [switch]$AllowSelfExtend,

        # Declared last (after every pre-existing parameter) so positional binding for existing
        # callers is unchanged.
        [switch]$AllowSelfRemove,

        [switch]$AllowOnBehalfUpdate,

        [switch]$AllowOnBehalfRemove
    )
    process {
        $OnBehalfRequestors = @()
        if ($AllowManagerRequest) {
            $OnBehalfRequestors = @(New-OERApproverObject -Spec @{ Manager = $true; ManagerLevel = $ManagerLevel })
        }

        $GraphRequestorSettings = @{
            enableTargetsToSelfAddAccess           = [bool]$AllowSelfRequest
            enableTargetsToSelfUpdateAccess        = [bool]$AllowSelfExtend
            enableTargetsToSelfRemoveAccess        = [bool]$AllowSelfRemove
            allowCustomAssignmentSchedule          = [bool]$AllowCustomSchedule
            enableOnBehalfRequestorsToAddAccess    = [bool]$AllowManagerRequest
            enableOnBehalfRequestorsToUpdateAccess = [bool]$AllowOnBehalfUpdate
            enableOnBehalfRequestorsToRemoveAccess = [bool]$AllowOnBehalfRemove
            onBehalfRequestors                     = $OnBehalfRequestors
        }

        $Out = [PSCustomObject]@{
            AllowSelfRequest       = [bool]$AllowSelfRequest
            AllowManagerRequest    = [bool]$AllowManagerRequest
            ManagerLevel           = $ManagerLevel
            AllowCustomSchedule    = [bool]$AllowCustomSchedule
            AllowSelfExtend        = [bool]$AllowSelfExtend
            AllowSelfRemove        = [bool]$AllowSelfRemove
            AllowOnBehalfUpdate    = [bool]$AllowOnBehalfUpdate
            AllowOnBehalfRemove    = [bool]$AllowOnBehalfRemove
            GraphRequestorSettings = $GraphRequestorSettings
        }
        $Out.PSObject.TypeNames.Insert(0, 'Omnicit.EntraRBAC.RequestorSettings')
        $Out
    }
}
