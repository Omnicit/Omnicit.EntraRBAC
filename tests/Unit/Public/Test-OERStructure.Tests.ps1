BeforeAll {
    $script:moduleName = 'Omnicit.EntraRBAC'
    Get-Module $script:moduleName | Remove-Module -Force -ErrorAction SilentlyContinue
    Import-Module $script:moduleName -Force -ErrorAction Stop
    . "$PSScriptRoot/../TestHelpers/OERTransportTripwire.ps1"
    Install-OERTransportTripwire
    . "$PSScriptRoot/../TestHelpers/OERConfirmHost.ps1"
}

AfterAll {
    try { Assert-OERTransportTripwire } finally { Uninstall-OERTransportTripwire }
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
    It 'validates a principalStatus entry as the export writes it, and refuses one that names the principal by name (A18)' {
        $Exported = '{ "version": "1.0", "roleAssignments": [ { "scope": "/subscriptions/x", "role": "Reader", "principal": "dddd9999-0000-0000-0000-000000000001", "principalType": "User", "principalStatus": "Deleted" }, { "scope": "/subscriptions/x", "role": "Owner", "principal": "dddd9999-0000-0000-0000-000000000002", "principalStatus": "Unresolved" } ] }'
        $V = Test-OERStructure -Json $Exported
        $V.Valid | Should -BeTrue
        @($V.Errors).Count | Should -Be 0
        $Named = '{ "version": "1.0", "roleAssignments": [ { "scope": "/subscriptions/x", "role": "Reader", "principal": "person1@example.com", "principalStatus": "Deleted" } ] }'
        $Bad = Test-OERStructure -Json $Named
        $Bad.Valid | Should -BeFalse
        @($Bad.Errors).Count | Should -Be 1
        $Bad.Errors[0].Path | Should -BeExactly 'roleAssignments[0].principal'
        $Bad.Errors[0].Message | Should -BeLike "*must be an object id (a GUID) when 'principalStatus' is declared*"
        # The document is read as written: a lower-cased status warns, and stays Valid.
        $Cased = Test-OERStructure -Json $Exported.Replace('"Deleted"', '"deleted"')
        $Cased.Valid | Should -BeTrue
        @($Cased.Errors).Count | Should -Be 1
        $Cased.Errors[0].Severity | Should -BeExactly 'Warning'
        $Cased.Errors[0].Message | Should -Match "canonical spelling is 'Deleted'"
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
    It 'surfaces the omitted-collection Warning for an omitted group members key without flipping Valid to false' {
        # An omitted members key is still reconciled against an empty declared set, so
        # Invoke-OERStructure -Prune removes every live member; the offline validator must say so.
        $V = Test-OERStructure -Json '{ "version": "1.0", "groups": [ { "displayName": "g1" } ] }'
        $V.Valid | Should -BeTrue
        $Hit = @($V.Errors | Where-Object { $_.Path -eq 'groups[0].members' })
        $Hit.Count | Should -Be 1
        $Hit[0].Severity | Should -BeExactly 'Warning'
        $Hit[0].Message | Should -Match 'Invoke-OERStructure -Prune removes every live entry'
    }
}

Describe 'Test-OERStructure help pointer to the worked example' {
    # The help points at docs/examples/example-structure.json as showing every section the engine
    # understands. Each schema section the example lacks must be named there as missing, and a
    # section named as missing must really be missing -- so the sentence goes stale in neither
    # direction when the example or the schema changes.
    It 'names exactly the schema sections the worked example does not declare' {
        $Schema = InModuleScope $script:moduleName { Get-OERStructureSchemaJson } | ConvertFrom-Json
        $Sections = @($Schema.properties.PSObject.Properties.Name | Where-Object { $_ -notin @('version', 'tenantId', 'tenantAlias') })
        $ExamplePath = Join-Path $PSScriptRoot '../../../docs/examples/example-structure.json'
        $Example = Get-Content -LiteralPath $ExamplePath -Raw | ConvertFrom-Json
        $Missing = @($Sections | Where-Object { $Example.PSObject.Properties.Name -notcontains $_ } | Sort-Object)
        $Help = (Get-Command -Module $script:moduleName -Name 'Test-OERStructure').Definition
        $Help | Should -Match 'docs/examples/example-structure\.json'
        # "except a and b, which are not in the example yet" (or "except a, which is ..."): the list
        # between "except" and that phrase, split on commas and "and".
        $Clause = [regex]::Match($Help, 'except\s+(?<List>[\w\s,]+?),\s+which\s+(?:is|are)\s+not\s+in\s+the\s+example\s+yet')
        $Named = @($Clause.Groups['List'].Value -split ',|\band\b' | ForEach-Object { $_.Trim() } | Where-Object { $_ } | Sort-Object)
        ($Named -join ',') | Should -BeExactly ($Missing -join ',')
    }
}

Describe 'Test-OERStructure help documents principalStatus (A18)' {
    It 'says which values and which principal form a roleAssignments entry that declares principalStatus takes' {
        # Whitespace collapsed first, so the assertions do not depend on where the prose wraps.
        $Help = Get-Help Test-OERStructure -Full
        $Description = ((@($Help.Description) | ForEach-Object { $_.Text }) -join ' ') -replace '\s+', ' '

        $Description | Should -Match ([regex]::Escape('A roleAssignments entry that declares principalStatus, which Get-OERInventory and Export-OERInventory write for a role assignment whose principal the directory did not return, must carry Deleted or Unresolved (any other value, or one that is not a string, is an Error; a non-canonical letter case is a Warning) and must name its principal by object id (an Error otherwise).'))
        $Description | Should -Match ([regex]::Escape('Invoke-OERStructure looks no principal up for such an entry and never creates a role assignment for it: where the entry would create one, it is reported Skipped.'))
    }
}

Describe 'Test-OERStructure help documents the restricted-unit PIM warning (Rule 16, Sprint 11 step 6, BL-134)' {
    It 'says a group that uses PIM for Groups in a restricted unit the document declares is a Warning, never an Error, and that an export raises none' {
        # Whitespace collapsed first, so the assertions do not depend on where the prose wraps.
        $Help = Get-Help Test-OERStructure -Full
        $Description = ((@($Help.Description) | ForEach-Object { $_.Text }) -join ' ') -replace '\s+', ' '

        $Description | Should -Match ([regex]::Escape('in a restricted management administrative unit the same document declares (an administrativeUnits entry whose restricted is true) is a Warning, never an Error'))
        $Description | Should -Match ([regex]::Escape('Microsoft Learn states that Privileged Identity Management does not support a group in a restricted management administrative unit'))
        $Description | Should -Match ([regex]::Escape('what Microsoft Graph answers to those writes has not been measured'))
        $Description | Should -Match ([regex]::Escape('A document Export-OERInventory writes raises neither Warning'))
    }
}

Describe 'Test-OERStructure help documents the tenantId (BL-88, A14)' {
    It 'says tenantId must be a string holding a canonical GUID and that only Invoke-OERStructure compares it with a session' {
        # Whitespace collapsed first, so the assertions do not depend on where the prose wraps.
        $Help = Get-Help Test-OERStructure -Full
        $Description = ((@($Help.Description) | ForEach-Object { $_.Text }) -join ' ') -replace '\s+', ' '

        $Description | Should -Match ([regex]::Escape('A top-level tenantId, when present, must be a string holding a canonical GUID (an explicit null, a value that is not a string, such as an array, or any other value is an Error; a document without the key is valid).'))
        $Description | Should -Match ([regex]::Escape('The check is offline: Test-OERStructure does not compare tenantId with any session, while Invoke-OERStructure does and refuses a document that names another tenant.'))
    }
}

Describe 'Test-OERStructure -NamingStandard (Sprint 11 step 7)' {
    # -NamingStandard names a naming standard file. Test-OERStructure reads it ONCE, in begin, and hands
    # the object to Test-OERStructureSchema, which adds one Warning per object and broken rule (Rule 17)
    # and never makes a document invalid. A standard that cannot be read is refused with
    # InvalidNamingStandard, once, and nothing is read or validated after it. The rules themselves are
    # held by Test-OERNamingStandardName.Tests.ps1 and Test-OERStructureSchema.Tests.ps1. The check is
    # offline, so Initialize-OERAuth is mocked and must stay uncalled in every test here.
    BeforeAll {
        $script:NsStandardJson = @'
{
  "$schema": "./naming-standard.schema.json",
  "version": "1.0",
  "description": "A neutral standard for the tests.",
  "separator": "-",
  "maxLength": 64,
  "sections": [ "groups", "administrativeUnits", "catalogs", "accessPackages", "assignmentPolicies", "accessReviews" ],
  "includeSyncedGroups": false,
  "segments": [
    { "name": "kind", "values": [ "SG", "AU", "CAT", "AP", "POL", "AR" ], "case": "UPPERCASE" },
    { "name": "area", "values": [ "Finance", "Sales", "IT" ] },
    { "name": "purpose", "case": "PascalCase" },
    { "name": "environment", "values": [ "Prod", "Test" ], "optional": true }
  ],
  "exceptions": [ "All Users", "(?i)legacy-.*" ]
}
'@
        # One name that follows the standard and two that do not (the separator, then a value outside the
        # list), every group with an explicit empty members key so no other Warning stands in the way.
        $script:NsDocumentJson = '{ "version": "1.0", "groups": [ ' +
        '{ "displayName": "SG-Finance-Readers", "members": [] }, ' +
        '{ "displayName": "bad_group", "members": [] }, ' +
        '{ "displayName": "SG-Legal-Readers", "members": [] } ] }'

        function New-NsFile {
            param([string]$Name, [string]$Text)
            $Path = Join-Path -Path $TestDrive -ChildPath $Name
            [System.IO.File]::WriteAllText($Path, $Text, [System.Text.UTF8Encoding]::new($false))
            $Path
        }
    }

    BeforeEach {
        Mock -ModuleName $script:moduleName Initialize-OERAuth {}
        $script:NsDoc = New-NsFile -Name 'doc.json' -Text $script:NsDocumentJson
        $script:NsStd = New-NsFile -Name 'standard.json' -Text $script:NsStandardJson
        # segments[0].case is not one of the four letter cases.
        $script:NsBadStd = New-NsFile -Name 'bad-standard.json' -Text $script:NsStandardJson.Replace('"case": "UPPERCASE"', '"case": "Pascal"')
    }

    AfterEach {
        Should -Invoke -ModuleName $script:moduleName Initialize-OERAuth -Times 0 -Scope It
    }

    Context 'a valid standard' {
        It 'gives one result, still Valid, with exactly one Warning for each name that does not follow the standard' {
            $Result = @(Test-OERStructure -Path $script:NsDoc -NamingStandard $script:NsStd)
            $Result.Count | Should -Be 1
            $Result[0].PSObject.TypeNames[0] | Should -Be 'Omnicit.EntraRBAC.StructureValidation'
            $Result[0].Valid | Should -BeTrue
            $Findings = @($Result[0].Errors)
            $Findings.Count | Should -Be 2
            foreach ($Finding in $Findings) {
                $Finding.Severity | Should -BeExactly 'Warning'
                $Finding.Message | Should -BeLike "Name '*"
                $Finding.Message | Should -BeLike '*does not follow the naming standard (rule ''*'
            }
            ($Findings | ForEach-Object { $_.Path }) | Should -Be @('groups[1].displayName', 'groups[2].displayName')
            ($Findings | ForEach-Object { $_.Item }) | Should -Be @('bad_group', 'SG-Legal-Readers')
            ($Findings | ForEach-Object { $_.Section } | Select-Object -Unique) | Should -Be 'groups'
            $Findings[0].Message | Should -BeLike "Name 'bad_group' at groups[[]1].displayName does not follow the naming standard (rule 'separator'):*"
            $Findings[1].Message | Should -BeLike "Name 'SG-Legal-Readers' at groups[[]2].displayName does not follow the naming standard (rule 'values', segment 2 'area'):*"
        }

        It 'raises nothing about names for the same document without -NamingStandard' {
            $Result = @(Test-OERStructure -Path $script:NsDoc)
            $Result.Count | Should -Be 1
            $Result[0].Valid | Should -BeTrue
            @($Result[0].Errors).Count | Should -Be 0
        }

        It 'applies the standard to a document given as -Json and to one given as -InputObject' {
            $FromJson = @(Test-OERStructure -Json $script:NsDocumentJson -NamingStandard $script:NsStd)
            $FromObject = @(Test-OERStructure -InputObject ($script:NsDocumentJson | ConvertFrom-Json) -NamingStandard $script:NsStd)
            foreach ($Result in @($FromJson, $FromObject)) {
                $Result.Count | Should -Be 1
                $Result[0].Valid | Should -BeTrue
                (@($Result[0].Errors) | ForEach-Object { $_.Path }) | Should -Be @('groups[1].displayName', 'groups[2].displayName')
            }
        }

        It 'checks a piped inventory object as Get-OERInventory shapes it, with Pascal-case section keys' {
            $Inv = [PSCustomObject]@{
                Version                = '1.0'
                Groups                 = @([PSCustomObject]@{ displayName = 'bad_group'; members = @() }, [PSCustomObject]@{ displayName = 'SG-Finance-Readers'; members = @() })
                AdministrativeUnits    = @()
                Catalogs               = @()
                AccessPackages         = @()
                AccessReviews          = @()
                RoleAssignments        = @()
                RoleManagementPolicies = @()
            }
            $Inv.PSObject.TypeNames.Insert(0, 'Omnicit.EntraRBAC.Inventory')
            $Result = @($Inv | Test-OERStructure -NamingStandard $script:NsStd)
            $Result.Count | Should -Be 1
            $Result[0].Valid | Should -BeTrue
            @($Result[0].Errors).Count | Should -Be 1
            $Result[0].Errors[0].Path | Should -BeExactly 'groups[0].displayName'
            $Result[0].Errors[0].Item | Should -BeExactly 'bad_group'
        }

        It 'keeps an invalid document invalid and adds the naming Warnings after its own findings' {
            $Json = '{ "version": "1.0", "grops": [], "groups": [ { "displayName": "bad_group", "members": [] } ] }'
            $Without = Test-OERStructure -Json $Json
            $With = Test-OERStructure -Json $Json -NamingStandard $script:NsStd
            $Without.Valid | Should -BeFalse
            $With.Valid | Should -BeFalse
            @($With.Errors).Count | Should -Be (@($Without.Errors).Count + 1)
            @($With.Errors)[-1].Message | Should -BeLike '*does not follow the naming standard*'
        }

        It 'passes the object Read-OERNamingStandard returned on to Test-OERStructureSchema, and none without -NamingStandard' {
            Mock -ModuleName $script:moduleName Test-OERStructureSchema { [PSCustomObject]@{ Valid = $true; Errors = @() } }
            $null = Test-OERStructure -Path $script:NsDoc -NamingStandard $script:NsStd
            Should -Invoke -ModuleName $script:moduleName Test-OERStructureSchema -Exactly -Times 1 -ParameterFilter {
                $null -ne $NamingStandard -and $NamingStandard.Separator -ceq '-' -and @($NamingStandard.Segments).Count -eq 4 -and @($Document.groups).Count -eq 3
            }
            $null = Test-OERStructure -Path $script:NsDoc
            Should -Invoke -ModuleName $script:moduleName Test-OERStructureSchema -Exactly -Times 1 -ParameterFilter { $null -eq $NamingStandard }
            Should -Invoke -ModuleName $script:moduleName Test-OERStructureSchema -Exactly -Times 2
        }

        It 'checks the shipped docs/examples/example-structure.json against docs/examples/naming-standard.json: still Valid, with one Warning per name and broken rule' {
            # The two shipped examples are neutral and were written apart: the apply example uses the
            # names of an older demo, so the example standard has something to say about each of its six
            # names (OER-AU-Demo breaks two rules, which makes seven Warnings).
            # The rows below are what the example standard produces, in the order the document holds them.
            $Example = Join-Path $PSScriptRoot '..' '..' '..' 'docs' 'examples' 'example-structure.json'
            $Standard = Join-Path $PSScriptRoot '..' '..' '..' 'docs' 'examples' 'naming-standard.json'
            Test-Path -LiteralPath $Standard -PathType Leaf | Should -BeTrue -Because 'the Test-OERStructure help names docs/examples/naming-standard.json'
            $Plain = Test-OERStructure -Path $Example
            $Result = @(Test-OERStructure -Path $Example -NamingStandard $Standard)
            $Result.Count | Should -Be 1
            $Result[0].Valid | Should -BeTrue
            @($Result[0].Errors | Where-Object Severity -eq 'Error').Count | Should -Be 0
            # What the document raises without a standard stands first and unchanged; the naming rows follow.
            @($Result[0].Errors).Count | Should -Be (@($Plain.Errors).Count + 7)
            $Naming = @(@($Result[0].Errors) | Select-Object -Skip @($Plain.Errors).Count)
            $Naming.Count | Should -Be 7
            foreach ($Finding in $Naming) {
                $Finding.Severity | Should -BeExactly 'Warning'
                $Finding.Message | Should -BeLike "Name '*' at * does not follow the naming standard (rule '*"
            }
            $Expected = @(
                @{ Section = 'groups'; Item = 'role_sec_identity_administrator'; Path = 'groups[0].displayName'; Rule = "(rule 'separator'):" }
                @{ Section = 'administrativeUnits'; Item = 'OER-AU-Demo'; Path = 'administrativeUnits[0].displayName'; Rule = "(rule 'values', segment 1 'kind'):" }
                @{ Section = 'administrativeUnits'; Item = 'OER-AU-Demo'; Path = 'administrativeUnits[0].displayName'; Rule = "(rule 'values', segment 2 'area'):" }
                @{ Section = 'catalogs'; Item = 'CAT-OER-Demo'; Path = 'catalogs[0].displayName'; Rule = "(rule 'values', segment 2 'area'):" }
                @{ Section = 'accessPackages'; Item = 'AP-OER-Demo'; Path = 'accessPackages[0].displayName'; Rule = "(rule 'values', segment 2 'area'):" }
                @{ Section = 'accessPackages'; Item = 'Default'; Path = 'accessPackages[0].assignmentPolicies[0].displayName'; Rule = "(rule 'separator'):" }
                @{ Section = 'accessReviews'; Item = 'AR-OER-Demo'; Path = 'accessReviews[0].displayName'; Rule = "(rule 'values', segment 2 'area'):" }
            )
            for ($I = 0; $I -lt $Expected.Count; $I++) {
                $Naming[$I].Section | Should -BeExactly $Expected[$I].Section
                $Naming[$I].Item | Should -BeExactly $Expected[$I].Item
                $Naming[$I].Path | Should -BeExactly $Expected[$I].Path
                $Naming[$I].Message | Should -BeLike ("*does not follow the naming standard " + $Expected[$I].Rule + '*')
            }
        }
    }

    Context 'a standard that cannot be read' {
        It 'refuses once with InvalidNamingStandard that names the problem, and gives no result, reading and validating nothing' {
            Mock -ModuleName $script:moduleName Read-OERStructureDocument { [PSCustomObject]@{ version = '1.0' } }
            Mock -ModuleName $script:moduleName Test-OERStructureSchema { [PSCustomObject]@{ Valid = $true; Errors = @() } }
            $Err = $null
            $Out = @(Test-OERStructure -Path $script:NsDoc -NamingStandard $script:NsBadStd -ErrorAction SilentlyContinue -ErrorVariable Err)

            $Out.Count | Should -Be 0
            $Own = @($Err | Where-Object { [string]$_.FullyQualifiedErrorId -like 'InvalidNamingStandard,*' })
            $Own.Count | Should -Be 1
            $Own[0].CategoryInfo.Category | Should -Be ([System.Management.Automation.ErrorCategory]::InvalidData)
            $Own[0].TargetObject | Should -BeExactly $script:NsBadStd
            $Own[0].Exception.Message | Should -BeLike 'Could not read the naming standard: *'
            $Own[0].Exception.Message | Should -Match ([regex]::Escape('segments[0].case'))
            Should -Invoke -ModuleName $script:moduleName Read-OERStructureDocument -Times 0
            Should -Invoke -ModuleName $script:moduleName Test-OERStructureSchema -Times 0

            # Reach proof: both mocks stand where Test-OERStructure calls them, since the same call with a
            # valid standard reaches each exactly once.
            $Valid = @(Test-OERStructure -Path $script:NsDoc -NamingStandard $script:NsStd)
            $Valid.Count | Should -Be 1
            Should -Invoke -ModuleName $script:moduleName Read-OERStructureDocument -Exactly -Times 1
            Should -Invoke -ModuleName $script:moduleName Test-OERStructureSchema -Exactly -Times 1
        }

        It 'scrubs the error record the reader threw, before it writes its own' {
            Mock -ModuleName $script:moduleName Remove-OERErrorRecord {}
            $null = Test-OERStructure -Path $script:NsDoc -NamingStandard $script:NsBadStd -ErrorAction SilentlyContinue
            Should -Invoke -ModuleName $script:moduleName Remove-OERErrorRecord -Exactly -Times 1
        }

        It 'refuses a standard path that is <Kind>' -ForEach @(
            @{ Kind = 'a file that does not exist'; Make = { Join-Path $TestDrive 'no-such-standard.json' } }
            @{ Kind = 'a directory'; Make = { $Dir = Join-Path $TestDrive 'a-folder'; $null = New-Item -ItemType Directory -Path $Dir -Force; $Dir } }
            @{ Kind = 'an empty file'; Make = { New-NsFile -Name 'empty-standard.json' -Text '' } }
            @{ Kind = 'malformed JSON'; Make = { New-NsFile -Name 'malformed-standard.json' -Text '{ bad' } }
            @{ Kind = 'white space only'; Make = { '   ' } }
        ) {
            $Given = & $Make
            $Err = $null
            $Out = @(Test-OERStructure -Path $script:NsDoc -NamingStandard $Given -ErrorAction SilentlyContinue -ErrorVariable Err)
            $Out.Count | Should -Be 0
            $Own = @($Err | Where-Object { [string]$_.FullyQualifiedErrorId -like 'InvalidNamingStandard,*' })
            $Own.Count | Should -Be 1
            $Own[0].TargetObject | Should -BeExactly $Given
            $Own[0].Exception.Message | Should -BeLike 'Could not read the naming standard: *'
        }

        It 'says a missing file was not found at the path as given' {
            $Given = Join-Path $TestDrive 'no-such-standard.json'
            $Err = $null
            $null = Test-OERStructure -Path $script:NsDoc -NamingStandard $Given -ErrorAction SilentlyContinue -ErrorVariable Err
            $Own = @($Err | Where-Object { [string]$_.FullyQualifiedErrorId -like 'InvalidNamingStandard,*' })
            $Own[0].Exception.Message | Should -BeExactly "Could not read the naming standard: The naming standard was not found at path '$Given'."
        }

        # Get-Content writes a non-terminating GetContentReaderIOError for a file it cannot open (a lock, no read
        # permission) and returns nothing. The reader reads with -ErrorAction Stop, so that error never reaches
        # the caller and the file is not called empty: the caller sees ONE error, the command's own. What the
        # caller sees is the error STREAM (redirected here, with -ErrorAction pinned to Continue so a global Stop
        # preference does not turn the first write into a throw) and $Error. -ErrorVariable is no measure: it
        # also holds the records the command's inner layers raised and caught (measured: seven for one refusal).
        It 'gives one error, with its reason, for a naming standard Get-Content throws on' {
            Mock -ModuleName $script:moduleName Get-Content {
                param($LiteralPath, $Raw)
                throw [System.IO.IOException]::new("The process cannot access the file '$LiteralPath' as another process is using it.")
            }
            $Stream = @(Test-OERStructure -Path $script:NsDoc -NamingStandard $script:NsStd -ErrorAction Continue 2>&1)

            @($Stream | Where-Object { $_ -isnot [System.Management.Automation.ErrorRecord] }).Count | Should -Be 0 -Because 'no result reaches the pipeline'
            $Records = @($Stream | Where-Object { $_ -is [System.Management.Automation.ErrorRecord] })
            $Records.Count | Should -Be 1
            $Records[0].FullyQualifiedErrorId | Should -BeExactly 'InvalidNamingStandard,Test-OERStructure'
            $Records[0].Exception.Message | Should -BeExactly "Could not read the naming standard: The naming standard at '$script:NsStd' could not be read: The process cannot access the file '$script:NsStd' as another process is using it."
            Should -Invoke -ModuleName $script:moduleName Get-Content -Exactly -Times 1
        }

        It 'gives one error, not two, and does not call the file empty, for a naming standard another process holds open' {
            $Held = [System.IO.File]::Open($script:NsStd, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::None)
            try {
                # Whether the lock is honoured is the platform's: a system that ignores it reads the file. The
                # probe opens the file the way Get-Content does, with .NET so that no GetContentReaderIOError
                # of its own lands in $Error, which is checked below.
                $Honoured = $false
                try { [System.IO.File]::Open($script:NsStd, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite).Dispose() } catch [System.IO.IOException] { $Honoured = $true }
                if (-not $Honoured) {
                    Set-ItResult -Skipped -Because 'this platform does not enforce FileShare.None against another reader'
                    return
                }
                $Stream = @(Test-OERStructure -Path $script:NsDoc -NamingStandard $script:NsStd -ErrorAction Continue 2>&1)
            } finally {
                $Held.Dispose()
            }

            @($Stream | Where-Object { $_ -isnot [System.Management.Automation.ErrorRecord] }).Count | Should -Be 0 -Because 'no result reaches the pipeline'
            $Records = @($Stream | Where-Object { $_ -is [System.Management.Automation.ErrorRecord] })
            $Records.Count | Should -Be 1
            $Records[0].FullyQualifiedErrorId | Should -BeExactly 'InvalidNamingStandard,Test-OERStructure'
            $Records[0].Exception.Message | Should -BeLike "Could not read the naming standard: The naming standard at '$script:NsStd' could not be read: *"
            $Records[0].Exception.Message | Should -Not -BeLike '*is empty*'
            @($global:Error | Where-Object { [string]$_.FullyQualifiedErrorId -like 'GetContentReaderIOError*' -and $_.Exception.Message -like '*standard.json*' }).Count | Should -Be 0
        }

        It 'throws a message that names the naming standard under -ErrorAction Stop' {
            { Test-OERStructure -Path $script:NsDoc -NamingStandard $script:NsBadStd -ErrorAction Stop } | Should -Throw '*naming standard*'
        }

        It 'is refused whichever way the document is given: <Set>' -ForEach @(
            @{ Set = 'Json'; Splat = { @{ Json = '{ "version": "1.0" }' } } }
            @{ Set = 'InputObject'; Splat = { @{ InputObject = [PSCustomObject]@{ version = '1.0' } } } }
        ) {
            $Params = & $Splat
            $Err = $null
            $Out = @(Test-OERStructure @Params -NamingStandard $script:NsBadStd -ErrorAction SilentlyContinue -ErrorVariable Err)
            $Out.Count | Should -Be 0
            @($Err | Where-Object { [string]$_.FullyQualifiedErrorId -like 'InvalidNamingStandard,*' }).Count | Should -Be 1
        }
    }

    Context 'a pipeline of documents' {
        BeforeEach {
            $script:NsDir = Join-Path $TestDrive 'three-documents'
            $null = New-Item -ItemType Directory -Path $script:NsDir -Force
            foreach ($Name in 'one.json', 'two.json', 'three.json') {
                [System.IO.File]::WriteAllText((Join-Path $script:NsDir $Name), $script:NsDocumentJson, [System.Text.UTF8Encoding]::new($false))
            }
        }

        It 'reads the standard once for three documents and gives three results' {
            # The real reader builds the object first; the mock then hands it out and counts the reads.
            $script:NsBuilt = InModuleScope $script:moduleName -Parameters @{ Path = $script:NsStd } {
                param($Path)
                Read-OERNamingStandard -Path $Path
            }
            $script:NsBuilt.Separator | Should -BeExactly '-'
            Mock -ModuleName $script:moduleName Read-OERNamingStandard { $script:NsBuilt }

            $Results = @(Get-ChildItem -LiteralPath $script:NsDir -Filter '*.json' | Test-OERStructure -NamingStandard $script:NsStd)

            $Results.Count | Should -Be 3
            foreach ($Result in $Results) {
                $Result.Valid | Should -BeTrue
                (@($Result.Errors) | ForEach-Object { $_.Path }) | Should -Be @('groups[1].displayName', 'groups[2].displayName')
            }
            Should -Invoke -ModuleName $script:moduleName Read-OERNamingStandard -Exactly -Times 1
        }

        It 'refuses an invalid standard once for three documents and gives no result' {
            $Err = $null
            $Results = @(Get-ChildItem -LiteralPath $script:NsDir -Filter '*.json' | Test-OERStructure -NamingStandard $script:NsBadStd -ErrorAction SilentlyContinue -ErrorVariable Err)
            $Results.Count | Should -Be 0
            @($Err | Where-Object { [string]$_.FullyQualifiedErrorId -like 'InvalidNamingStandard,*' }).Count | Should -Be 1
        }

        It 'gives three results with no naming Warning when -NamingStandard is not given' {
            $Results = @(Get-ChildItem -LiteralPath $script:NsDir -Filter '*.json' | Test-OERStructure)
            $Results.Count | Should -Be 3
            @($Results | ForEach-Object { @($_.Errors).Count } | Select-Object -Unique) | Should -Be 0
        }
    }

    Context 'a script with no try' {
        It 'goes on after the refusal and outputs only what comes after it' {
            # A body-wide stop would end the script at the refusal. Pester stands in a try, so the command
            # runs in a runspace and a script with no try, as the export's control flow test does. The
            # runspace's copy of the module is the one under test; Initialize-OERAuth is replaced there and
            # logs a call, and the id of the command's own error is written to the log, since the answering
            # host returns only the messages. -ErrorVariable holds the reader's inner records too, so the
            # command's own is picked by its id.
            $Log = Join-Path $TestDrive ('{0}.log' -f [guid]::NewGuid())
            $Scenario = [scriptblock]::Create((@'
Import-Module Omnicit.EntraRBAC -Force -ErrorAction Stop
& (Get-Module Omnicit.EntraRBAC) {
    Set-Item -Path function:script:Initialize-OERAuth -Value { Add-Content -LiteralPath '#LOG#' -WhatIf:$false -Value 'Initialize-OERAuth' }
}
Test-OERStructure -Path '#DOC#' -NamingStandard '#STD#' -ErrorVariable NsErr
Add-Content -LiteralPath '#LOG#' -WhatIf:$false -Value ('IDS:' + (@($NsErr | Where-Object { [string]$_.FullyQualifiedErrorId -like 'InvalidNamingStandard,*' } | ForEach-Object { [string]$_.FullyQualifiedErrorId }) -join '|'))
'END'
'@).Replace('#LOG#', $Log.Replace("'", "''")).Replace('#DOC#', $script:NsDoc.Replace("'", "''")).Replace('#STD#', $script:NsBadStd.Replace("'", "''")))

            $Run = Invoke-OERWithConfirmAnswer -Answer '&Yes' -Script $Scenario

            # The script reached its end, and no StructureValidation reached the pipeline.
            ($Run.Output -join '|') | Should -BeExactly 'END'
            @($Run.Errors | Where-Object { $_ -like 'Could not read the naming standard: *segments`[0`].case*' }).Count | Should -Be 1
            $Lines = @(Get-Content -LiteralPath $Log)
            $Lines | Should -Contain 'IDS:InvalidNamingStandard,Test-OERStructure'
            $Lines | Should -Not -Contain 'Initialize-OERAuth'
        }
    }

    Context 'the parameter' {
        It 'refuses <Label> at parameter binding, before anything is read' -ForEach @(
            @{ Label = 'an empty string'; Value = '' }
            @{ Label = 'null'; Value = $null }
        ) {
            Mock -ModuleName $script:moduleName Read-OERNamingStandard {}
            $Caught = $null
            try {
                Test-OERStructure -Json '{ "version": "1.0" }' -NamingStandard $Value -ErrorAction Stop
            } catch {
                $Caught = $PSItem
            }
            $Caught | Should -Not -BeNullOrEmpty
            $Caught.FullyQualifiedErrorId | Should -BeExactly 'ParameterArgumentValidationError,Test-OERStructure'
            $Caught.Exception | Should -BeOfType ([System.Management.Automation.ParameterBindingException])
            Should -Invoke -ModuleName $script:moduleName Read-OERNamingStandard -Times 0
        }

        It 'is a string in every parameter set, with no alias and no position, and refuses an empty value' {
            $Parameter = (Get-Command -Module $script:moduleName -Name Test-OERStructure).Parameters['NamingStandard']
            $Parameter | Should -Not -BeNullOrEmpty
            $Parameter.ParameterType | Should -Be ([string])
            @($Parameter.ParameterSets.Keys) | Should -Be @('__AllParameterSets')
            @($Parameter.Aliases).Count | Should -Be 0
            @($Parameter.Attributes | Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] } | ForEach-Object { $_.Position }) | Should -Be @([int]::MinValue)
            @($Parameter.Attributes | Where-Object { $_ -is [System.Management.Automation.ValidateNotNullOrEmptyAttribute] }).Count | Should -Be 1
        }

        It 'is the only parameter the naming standard added, and Invoke-OERStructure takes none' {
            (Get-Command -Module $script:moduleName -Name Test-OERStructure).Parameters.Keys | Where-Object { $_ -like '*Naming*' } | Should -Be @('NamingStandard')
            (Get-Command -Module $script:moduleName -Name Invoke-OERStructure).Parameters.Keys | Should -Not -Contain 'NamingStandard'
        }
    }
}

Describe 'Test-OERStructure help documents -NamingStandard (Sprint 11 step 7)' {
    BeforeAll {
        # Whitespace collapsed first, so the assertions do not depend on where the prose wraps.
        $Help = Get-Help Test-OERStructure -Full
        $script:NsParameterHelp = ((@($Help.parameters.parameter | Where-Object { $_.name -eq 'NamingStandard' } | ForEach-Object { $_.description }) | ForEach-Object { $_.Text }) -join ' ') -replace '\s+', ' '
        $script:NsDescription = ((@($Help.Description) | ForEach-Object { $_.Text }) -join ' ') -replace '\s+', ' '
        $script:NsExamples = ((@($Help.examples.example) | ForEach-Object { ($_.code, ((@($_.remarks) | ForEach-Object { $_.Text }) -join ' ')) -join ' ' }) -join ' ') -replace '\s+', ' '
    }

    It 'describes the parameter: the file, the rules, Warning only, the refusal, the inventory and the example' {
        $script:NsParameterHelp | Should -Match 'naming standard file'
        $script:NsParameterHelp | Should -Match 'separator'
        $script:NsParameterHelp | Should -Match 'maxLength'
        $script:NsParameterHelp | Should -Match 'Warning'
        $script:NsParameterHelp | Should -Match 'never makes a document invalid'
        $script:NsParameterHelp | Should -Match 'InvalidNamingStandard'
        $script:NsParameterHelp | Should -Match 'nothing is validated'
        $script:NsParameterHelp | Should -Match 'inventory\.json'
        $script:NsParameterHelp | Should -Match 'rename map'
        $script:NsParameterHelp | Should -Match ([regex]::Escape('docs/examples/naming-standard.json'))
        $script:NsParameterHelp | Should -Match ([regex]::Escape('docs/examples/naming-standard.schema.json'))
        $script:NsParameterHelp | Should -Match 'Invoke-OERStructure takes no naming standard'
    }

    It 'names the six rules in the parameter help' {
        foreach ($Rule in 'maxLength', 'separator', 'segmentCount', 'values', 'pattern', 'case') {
            $script:NsParameterHelp | Should -Match ('\b' + $Rule + '\b')
        }
    }

    It 'says which groups an exported inventory.json holds, and that a template with no name is warned about' {
        $script:NsParameterHelp | Should -Match ([regex]::Escape('It covers the groups inventory.json holds, by default the RBAC-relevant security groups'))
        $script:NsParameterHelp | Should -Match ([regex]::Escape('Export-OERInventory -AllGroupsDetailed keeps every security group in full detail'))
        $script:NsParameterHelp | Should -Match ([regex]::Escape('a Microsoft 365 group is in groupsRoster.json only'))
        $script:NsParameterHelp | Should -Match ([regex]::Escape('only when the export was made with Export-OERInventory -IncludeSyncedGroups'))
        $script:NsParameterHelp | Should -Match ([regex]::Escape("Group at groups[i].template was not checked against the naming standard: its name could not be computed from 'template' and 'tokens'."))
        $script:NsParameterHelp | Should -Match ([regex]::Escape('includeSyncedGroups is true, and its Warning says so'))
        $script:NsParameterHelp | Should -Not -Match 'its row says so'
    }

    It 'words the example as one Warning for each rule a name breaks' {
        $script:NsExamples | Should -Match ([regex]::Escape('adds one Warning for each rule a name breaks'))
        $script:NsExamples | Should -Not -Match 'one Warning for each name'
    }

    It 'carries a description paragraph and an example that runs it on an exported inventory' {
        $script:NsDescription | Should -Match 'naming standard'
        $script:NsDescription | Should -Match ([regex]::Escape('-NamingStandard'))
        $script:NsExamples | Should -Match ([regex]::Escape('Test-OERStructure -Path ./exports/oer-inventory-contoso-20261018-120000/inventory.json -NamingStandard ./naming-standard.json'))
    }
}
