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
