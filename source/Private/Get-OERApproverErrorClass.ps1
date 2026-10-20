function Get-OERApproverErrorClass {
    <#
    .SYNOPSIS
    Classifies a failed approver lookup as Ambiguous, NotFound or Other.

    .DESCRIPTION
    The single owner of how an approver lookup failure is told apart (BL-52). Six sites resolve
    declared or bound approvers and report each failure in one of three ways -- Set-OERGroupPimPolicy,
    Set-OERDirectoryRoleManagementPolicy, Set-OERRoleManagementPolicy and the three apply handlers
    Sync-OERStructureGroup, Sync-OERStructureDirectoryRoleManagementPolicy and
    Sync-OERStructureRoleManagementPolicy -- and each asks this helper which way, then builds its own
    record with its own message, target and inner exception:

      - 'Ambiguous' when Test-OERAmbiguousNameError says the record is the AmbiguousName refusal of a
        display name several objects share. The site publishes AmbiguousApproverName.
      - 'NotFound' when the FullyQualifiedErrorId starts, ordinally, with ApproverUnresolved (the
        record Resolve-OERApproverInput and Resolve-OERDeclaredApprover throw for an approver that
        matches nothing) or with PrincipalUnresolved (the record Resolve-OERPrincipal throws for the
        same, which Set-OERRoleManagementPolicy catches directly). The site publishes ApproverNotFound.
      - 'Other' for anything else -- a 403, an exhausted 429, a 5xx, a null record. That is no
        evidence that the approver is missing, so the site publishes the record as itself.

    The two internal ids are never published. A prefix test, so a record that has already crossed a
    WriteError boundary and carries the qualified '<ErrorId>,<CommandName>' form is still recognised.
    Pure: no Graph call, and it never throws. The cohort check in
    tests/Unit/Private/Get-OERApproverErrorClass.Tests.ps1 holds that no other file under source/ tests
    either internal id, the three resolvers that produce them excepted, and that each of the six sites
    calls this helper.

    .PARAMETER Record
    The ErrorRecord caught around an approver lookup. A null record is 'Other'.

    .EXAMPLE
    switch (Get-OERApproverErrorClass -Record $LookupError) { 'Ambiguous' { ... } 'NotFound' { ... } default { ... } }
    Routes a caught approver lookup failure to the record the site publishes for it.
    #>
    [OutputType([string])]
    [CmdletBinding()]
    param(
        [AllowNull()]
        [System.Management.Automation.ErrorRecord]$Record
    )

    if (Test-OERAmbiguousNameError -Record $Record) { return 'Ambiguous' }
    $ErrorId = if ($null -ne $Record) { [string]$Record.FullyQualifiedErrorId } else { '' }
    if ($ErrorId.StartsWith('ApproverUnresolved', [System.StringComparison]::Ordinal) -or
        $ErrorId.StartsWith('PrincipalUnresolved', [System.StringComparison]::Ordinal)) {
        return 'NotFound'
    }
    'Other'
}
