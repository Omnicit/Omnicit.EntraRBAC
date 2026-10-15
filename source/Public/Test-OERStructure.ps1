function Test-OERStructure {
    <#
    .SYNOPSIS
    Validates an orchestration document offline against the Phase 5 schema.

    .DESCRIPTION
    Parses a structure document from -Path, -Json, or -InputObject and runs the shared offline schema
    validation (Test-OERStructureSchema) WITHOUT any tenant call or authentication. Use it to confirm a
    document is well-formed and self-consistent before applying it with Invoke-OERStructure. Returns a
    tagged Omnicit.EntraRBAC.StructureValidation object with a Valid flag and an Errors collection that
    points at each offending node. This answers "is my JSON correct"; for "what would change in the
    tenant" use Invoke-OERStructure -WhatIf instead.

    The document is read with -SkipEnumNormalization, so validation runs against the document exactly
    as written, including its enum casing -- unlike Invoke-OERStructure, which always normalizes before
    it reads the document. This is why a document can validate here with a Warning saying it will be
    rejected by a draft-07 validator outside the module, even though Invoke-OERStructure would apply
    the very same document successfully: the apply path rewrites the casing first, this one does not.

    An omitted groups[].members, administrativeUnits[].members, administrativeUnits[].scopedRoles,
    catalogs[].resources or accessPackages[].resourceRoles key is reported as a Warning, since
    Invoke-OERStructure -Prune still removes every live entry in that collection; set the key to null
    to leave the collection untouched, or declare it. The members key of a group or administrative
    unit declared "dynamic": true is not reported.

    A roleAssignments entry whose scope is the Azure root scope '/', above every management group
    and subscription in the tenant, is reported as a Warning at the entry's scope path, which does
    not make the document invalid: a role assignment there is elevated access, and
    Invoke-OERStructure reports such an entry Skipped and never prunes the root scope. A
    roleManagementPolicies scope '/' is not reported.

    A roleAssignments entry that declares principalStatus, which Get-OERInventory and
    Export-OERInventory write for a role assignment whose principal the directory did not return, must
    carry Deleted or Unresolved (any other value, or one that is not a string, is an Error; a
    non-canonical letter case is a Warning) and must name its principal by object id (an Error
    otherwise). Invoke-OERStructure looks no principal up for such an entry and never creates a role
    assignment for it: where the entry would create one, it is reported Skipped.

    A previousDisplayName is read on a groups, administrativeUnits, catalogs, accessPackages or
    accessReviews entry, and on an assignmentPolicies entry of an access package, where
    Invoke-OERStructure renames the object it names in place: an access package within its catalog, an
    assignment policy within its access package. It must be a non-empty string (an Error otherwise);
    one equal to displayName, ignoring case, is a Warning, since both names then find one object and a
    case-only rename is not possible through the document (an assignment policy is given the declared
    letter case only together with another changed field of it). A second entry of a section that
    claims a name an earlier entry already claims, as its displayName or as its previousDisplayName,
    is an Error, and so is an assignment policy that claims a name an earlier policy of the same
    access package claims, two equal displayNames included; the same name in two access packages is
    two policies. An export made by an earlier version can hold two policies of one name in one
    access package, and such a document is refused. An explicit null counts as not declared.

    A reference that still names a renamed object by its previous name is a Warning at the reference:
    a groups entry's administrativeUnit, an accessPackages entry's catalog, or an accessReviews
    entry's accessPackage that equals, ignoring case, the previousDisplayName of an entry that renames
    the object, and an accessReviews entry's assignmentPolicy that equals the previousDisplayName of a
    policy the document renames in the access package the review names. Once the rename is applied no
    object carries the previous name, so the Warning says to name the object by its new name. A
    previousDisplayName that is an object id raises none, since a reference by id stays valid after a
    rename. When the same document renames the unit, the catalog, the access package or the assignment
    policy, Invoke-OERStructure reaches it by its object id in the same run for a reference that uses
    the new name -- a group created into the unit, a package declared in the catalog, an access review
    of the package or the policy -- and refuses the reference when that rename is refused or the run
    cannot decide it; its help describes both.

    An accessReviews entry whose accessPackage is a name, not an object id, that two or more
    accessPackages entries declare, as their displayName or as a previousDisplayName that renames, is
    an Error at the review's accessPackage, whether or not one of those entries renames its package.
    The same name in two catalogs is two packages, but Invoke-OERStructure keys every declared package,
    and the policies within it, by the package's name, without its catalog, so the run cannot tell
    which package the review means. Name the access package by its object id.

    A groups entry that uses PIM for Groups -- it declares a pimPolicy, or an eligibility with at least
    one entry -- in a restricted management administrative unit the same document declares (an
    administrativeUnits entry whose restricted is true) is a Warning, never an Error: at the group's
    administrativeUnit when it names such a unit, by display name or by the id the unit's entry
    declares, and at the group when such a unit lists the group in its members, by its name or its
    declared id. Microsoft Learn states that Privileged Identity Management does not support a group in
    a restricted management administrative unit; Invoke-OERStructure still sends the PIM settings and
    eligibility the document declares for such a group, and what Microsoft Graph answers to those
    writes has not been measured. A document Export-OERInventory writes raises neither Warning, since
    its groups carry no object id and no administrativeUnit; the export names such groups in its own
    warning and in its README.md instead.

    A top-level tenantId, when present, must be a string holding a canonical GUID (an explicit null, a
    value that is not a string, such as an array, or any other value is an Error; a document without
    the key is valid). The check is offline: Test-OERStructure does not compare tenantId with any
    session, while Invoke-OERStructure does and refuses a document that names another tenant.

    A worked apply document showing every section the engine understands is kept in the repository
    at docs/examples/example-structure.json, and the full export to apply walkthrough is documented
    in the repository at docs/inventory-to-llm/README.md. Neither ships inside the installed module,
    so clone or browse the repository to read them.

    .PARAMETER Path
    Path to a JSON structure document file to validate.

    .PARAMETER Json
    A literal JSON string to validate.

    .PARAMETER InputObject
    The document to validate: a PSCustomObject (such as the output of Get-OERInventory) to validate
    directly, eliminating the need for a manual ConvertTo-Json / ConvertFrom-Json round-trip; OR a
    file to read -- either a path string or a System.IO.FileInfo (for example piped from
    Get-ChildItem or Get-Item), read from disk exactly like -Path. A System.IO.DirectoryInfo is an
    error.

    .EXAMPLE
    Test-OERStructure -Path ./example-structure.json
    Validates the document and returns the validation result.

    .EXAMPLE
    Test-OERStructure -Json '{ "version": "1.0", "groups": [] }'
    Validates an inline JSON document.

    .EXAMPLE
    Get-OERInventory | Test-OERStructure
    Validates the current tenant inventory object directly without a manual JSON round-trip.

    .EXAMPLE
    Get-ChildItem ./structures/*.json | Test-OERStructure
    Validates every JSON file in the folder, one StructureValidation result per file.
    #>
    [OutputType([PSCustomObject])]
    [CmdletBinding(DefaultParameterSetName = 'Path')]
    param(
        [Parameter(ParameterSetName = 'Path', Mandatory)][string]$Path,
        [Parameter(ParameterSetName = 'Json', Mandatory)][string]$Json,
        [Parameter(ParameterSetName = 'InputObject', Mandatory, ValueFromPipeline)]
        [Alias('Inventory', 'Document')]
        [object]$InputObject
    )
    process {
        $ReadParams = @{}
        if ($PSCmdlet.ParameterSetName -eq 'Path') { $ReadParams.Path = $Path }
        elseif ($PSCmdlet.ParameterSetName -eq 'Json') { $ReadParams.Json = $Json }
        else { $ReadParams.InputObject = $InputObject }
        $ReadParams.SkipEnumNormalization = $true
        $DocumentTarget = if ($Path) { $Path } else { $PSCmdlet.ParameterSetName }
        $Document = try {
            Read-OERStructureDocument @ReadParams
        } catch {
            Remove-OERErrorRecord -Record $PSItem
            Write-CmdletError -Message ([System.Exception]::new("Could not read the structure document: $($PSItem.Exception.Message)")) `
                -ErrorId 'InvalidStructureDocument' -Category InvalidData -TargetObject $DocumentTarget -Cmdlet $PSCmdlet
            return
        }
        Test-OERStructureSchema -Document $Document
    }
}
