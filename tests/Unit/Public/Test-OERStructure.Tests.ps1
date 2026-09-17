BeforeAll {
    $script:moduleName = 'Omnicit.EntraRBAC'
    Get-Module $script:moduleName | Remove-Module -Force -ErrorAction SilentlyContinue
    Import-Module $script:moduleName -Force -ErrorAction Stop
}

Describe 'Test-OERStructure' {
    It 'validates inline JSON and returns a StructureValidation' {
        $V = Test-OERStructure -Json '{ "version": "1.0" }'
        $V.PSObject.TypeNames[0] | Should -Be 'Omnicit.EntraRBAC.StructureValidation'
        $V.Valid | Should -BeTrue
    }
    It 'reports Valid false for a bad document' {
        (Test-OERStructure -Json '{ "groups": [] }').Valid | Should -BeFalse
    }
    It 'validates a file via -Path' {
        $P = Join-Path $TestDrive 'd.json'
        Set-Content -LiteralPath $P -Value '{ "version": "1.0" }' -Encoding utf8
        (Test-OERStructure -Path $P).Valid | Should -BeTrue
    }
    It 'NEVER authenticates (no Initialize-OERAuth)' {
        Mock -ModuleName $script:moduleName Initialize-OERAuth {}
        Test-OERStructure -Json '{ "version": "1.0" }' | Out-Null
        Should -Invoke -ModuleName $script:moduleName Initialize-OERAuth -Times 0
    }
    It 'emits a clean non-terminating error on malformed JSON' {
        { Test-OERStructure -Json '{ bad' -ErrorAction Stop } | Should -Throw '*structure document*'
    }
    It 'is exported by the module' {
        Get-Command -Module $script:moduleName -Name Test-OERStructure | Should -Not -BeNullOrEmpty
    }
    It 'accepts a piped inventory-shaped object via -InputObject and returns Valid true' {
        $Inv = [pscustomobject]@{
            Version               = '1.0'
            Groups                = @()
            AdministrativeUnits   = @()
            Catalogs              = @()
            AccessPackages        = @()
            AccessReviews         = @()
            RoleAssignments       = @()
            RoleManagementPolicies = @()
        }
        $Inv.PSObject.TypeNames.Insert(0, 'Omnicit.EntraRBAC.Inventory')
        $V = $Inv | Test-OERStructure
        $V.Valid | Should -BeTrue
    }
    It 'produces the same Valid result via pipe as via -Json (round-trip fidelity)' {
        $Inv = [pscustomobject]@{
            Version = '1.0'
            Groups  = @(
                [pscustomobject]@{ displayName = 'g1'; description = 'test group'; mailNickname = 'g1' }
            )
            AdministrativeUnits    = @()
            Catalogs               = @()
            AccessPackages         = @()
            AccessReviews          = @()
            RoleAssignments        = @()
            RoleManagementPolicies = @()
        }
        $Inv.PSObject.TypeNames.Insert(0, 'Omnicit.EntraRBAC.Inventory')
        $ViaPipe = ($Inv | Test-OERStructure).Valid
        $ViaJson = (Test-OERStructure -Json ($Inv | ConvertTo-Json -Depth 32)).Valid
        $ViaPipe | Should -Be $ViaJson
    }
    It 'validates the shipped docs/examples/example-structure.json as Valid' {
        $ExamplePath = Join-Path $PSScriptRoot '..' '..' '..' 'docs' 'examples' 'example-structure.json'
        Test-Path -LiteralPath $ExamplePath | Should -BeTrue
        $V = Test-OERStructure -Path $ExamplePath
        $V.Valid | Should -BeTrue
        @($V.Errors | Where-Object Severity -eq 'Error').Count | Should -Be 0
    }
    It 'warns that a non-canonically cased principalType is rejected by a draft-07 validator, while staying Valid' {
        $Json = '{ "version": "1.0", "roleAssignments": [ { "scope": "/subscriptions/x", "role": "Reader", "principal": "p", "principalType": "group" } ] }'
        $V = Test-OERStructure -Json $Json
        $V.Valid | Should -BeTrue
        @($V.Errors).Count | Should -Be 1
        $V.Errors[0].Severity | Should -BeExactly 'Warning'
        $V.Errors[0].Message | Should -Match "canonical spelling is 'Group'"
    }
    It 'does not warn when principalType is already canonically cased' {
        $Json = '{ "version": "1.0", "roleAssignments": [ { "scope": "/subscriptions/x", "role": "Reader", "principal": "p", "principalType": "Group" } ] }'
        $V = Test-OERStructure -Json $Json
        $V.Valid | Should -BeTrue
        @($V.Errors | Where-Object { $_.Severity -eq 'Warning' }).Count | Should -Be 0
    }
    It 'validates a piped FileInfo (Get-ChildItem) reflecting the files real content, not a serialized FileInfo' {
        # Get-ChildItem *.json | Test-OERStructure binds the FileInfo BY VALUE to -InputObject. Before
        # the fix that FileInfo was serialized with ConvertTo-Json and validated as-is -- a bogus result
        # for a serialized FileInfo, not the document. principalType 'group' (lower-case) is a marker
        # that exists only in the FILE'S content: it triggers exactly one canonicalization Warning
        # naming 'Group'. A serialized FileInfo carries no roleAssignments key at all, so this specific
        # Warning is proof the real file content reached the validator.
        $P = Join-Path $TestDrive 'gci.json'
        Set-Content -LiteralPath $P -Value '{ "version": "1.0", "roleAssignments": [ { "scope": "/subscriptions/x", "role": "Reader", "principal": "p", "principalType": "group" } ] }' -Encoding utf8
        $V = Get-ChildItem -LiteralPath $P | Test-OERStructure
        $V.Valid | Should -BeTrue
        @($V.Errors).Count | Should -Be 1
        $V.Errors[0].Message | Should -Match "canonical spelling is 'Group'"
    }

    It 'validates a piped path-like string reflecting the files real content, not treating it as inline JSON' {
        $P = Join-Path $TestDrive 'str.json'
        Set-Content -LiteralPath $P -Value '{ "version": "1.0", "roleAssignments": [ { "scope": "/subscriptions/x", "role": "Reader", "principal": "p", "principalType": "group" } ] }' -Encoding utf8
        $V = $P | Test-OERStructure
        $V.Valid | Should -BeTrue
        @($V.Errors).Count | Should -Be 1
        $V.Errors[0].Message | Should -Match "canonical spelling is 'Group'"
    }

    It 'scrubs the error record when the structure document cannot be read' {
        # NOT a bearer path. Test-OERStructure is an offline validator: it never calls
        # Initialize-OERAuth, Graph or ARM, and its single Remove-OERErrorRecord site guards the
        # Read-OERStructureDocument catch, which fires on a file-read or JSON-parse failure. The
        # guard is still asserted at runtime here, because the static gate only proves the line is
        # WRITTEN first -- it cannot prove the catch is ever entered.
        #
        # Read-OERStructureDocument is mocked to throw rather than fed malformed JSON ON PURPOSE.
        # Malformed JSON makes the helper's OWN scrub fire too, so the count is 2 and the assertion
        # below would still pass with THIS cmdlet's Remove-OERErrorRecord line deleted -- a guard
        # that cannot fail. Mocking the helper away leaves Test-OERStructure's own catch as the only
        # possible caller.
        Mock -ModuleName $script:moduleName Read-OERStructureDocument { throw 'unreadable document' }
        Mock -ModuleName $script:moduleName Remove-OERErrorRecord { }
        Test-OERStructure -Json '{ "version": "1.0" }' -ErrorAction SilentlyContinue | Out-Null
        Should -Invoke -ModuleName $script:moduleName Remove-OERErrorRecord -Times 1
    }
    It 'surfaces a schema Warning to the caller' {
        $Doc = [pscustomobject]@{
            groups = @([pscustomobject]@{
                    displayName = 'g1'
                    pimPolicy   = [pscustomobject]@{
                        authenticationContextId = 'c1'
                        activationEnablement    = @('MultiFactorAuthentication')
                    }
                })
        }
        $V = Test-OERStructure -InputObject $Doc
        @($V.Errors | Where-Object { $_.Message -match 'mutually exclusive' }).Count | Should -BeGreaterThan 0
    }
    It 'surfaces the requireApproval vs empty approvalStages Warning without flipping Valid to false' {
        # Issue #56: a declared-empty approvalStages now really clears the live stages, so pairing it
        # with requireApproval true writes approval-required with no approvers. That is a Warning, not
        # an Error -- the apply still runs -- so the document must stay Valid while the finding reaches
        # the caller through .Errors.
        $Json = '{ "version": "1.0", "accessPackages": [ { "displayName": "ap1", "catalog": "cat1", "assignmentPolicies": [ { "displayName": "p1", "requireApproval": true, "approvalStages": [] } ] } ] }'
        $V = Test-OERStructure -Json $Json
        $V.Valid | Should -BeTrue
        $Hit = @($V.Errors | Where-Object { $_.Message -match 'declared as an empty array' })
        $Hit.Count | Should -Be 1
        $Hit[0].Severity | Should -BeExactly 'Warning'
        $Hit[0].Path | Should -BeExactly 'accessPackages[0].assignmentPolicies[0].approvalStages'
    }
}
