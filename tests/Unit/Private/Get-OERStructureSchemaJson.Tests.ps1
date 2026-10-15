BeforeAll {
    $script:moduleName = 'Omnicit.EntraRBAC'
    Get-Module $script:moduleName | Remove-Module -Force -ErrorAction SilentlyContinue
    Import-Module $script:moduleName -Force -ErrorAction Stop
    . "$PSScriptRoot/../TestHelpers/OERTransportTripwire.ps1"
    Install-OERTransportTripwire
    # Three Split-Path hops from tests\Unit\Private: tests\Unit\Private -> tests\Unit -> tests ->
    # repo root. A two-hop version resolves to tests\ and was corrected once already on this
    # branch (Task 1) -- do not repeat that mistake.
    $RepoRoot = $PSScriptRoot | Split-Path | Split-Path | Split-Path
    $script:sourceRoot = Join-Path -Path $RepoRoot -ChildPath 'source'
}

AfterAll {
    try { Assert-OERTransportTripwire } finally { Uninstall-OERTransportTripwire }
}

Describe 'Get-OERStructureSchemaJson' {
    It 'returns a string that parses as valid JSON with the expected shape' {
        InModuleScope $script:moduleName {
            $Schema = Get-OERStructureSchemaJson
            $Schema | Should -BeOfType ([string])
            $Obj = $Schema | ConvertFrom-Json
            $Obj.'$schema' | Should -Match 'draft-07'
            $Obj.required | Should -Contain 'version'
            $Obj.additionalProperties | Should -BeFalse
            $Obj.properties.PSObject.Properties.Name | Should -Contain 'roleManagementPolicies'
        }
    }

    It 'contains only ASCII characters' {
        InModuleScope $script:moduleName {
            $Bytes = [System.Text.Encoding]::UTF8.GetBytes((Get-OERStructureSchemaJson))
            ($Bytes | Where-Object { $_ -gt 127 }).Count | Should -Be 0
        }
    }

    It 'carries a match-key note on every section whose displayName is the match key' {
        InModuleScope $script:moduleName {
            $Schema = Get-OERStructureSchemaJson | ConvertFrom-Json
            $Sections = 'groups', 'administrativeUnits', 'catalogs', 'accessPackages',
                'accessReviews'
            foreach ($Section in $Sections) {
                $Desc = $Schema.properties.$Section.description
                $Desc | Should -Match 'match key' -Because "$Section matches on displayName"
            }
        }
    }

    It 'does not claim the roleManagementPolicies block is the full settable surface' {
        # The phrase this guards only ever lived in the function's comment-based help, never in
        # the JSON string it returns -- asserting against Get-OERStructureSchemaJson's own OUTPUT
        # here would pass identically whether the claim were present or absent in the help block.
        # Read the raw source text instead, the same way the Get-OERInventory.Tests.ps1 sibling
        # guard does.
        $SrcPath = Join-Path $script:sourceRoot 'Private/Get-OERStructureSchemaJson.ps1'
        $Text = Get-Content -Raw -Path $SrcPath
        $Text | Should -Not -Match 'full settable Azure PIM policy surface'
        $Text | Should -Match 'notification rule'
    }

    It 'documents the escalation-fallback loss on the approvalStages block' {
        InModuleScope $script:moduleName {
            $Schema = Get-OERStructureSchemaJson | ConvertFrom-Json
            $ApProps = $Schema.properties.accessPackages.items.properties
            $PolItems = $ApProps.assignmentPolicies.items.properties
            $StagesDesc = $PolItems.approvalStages.description
            $StagesDesc | Should -Match 'fallbackEscalationApprovers'
            $StagesDesc | Should -Match 'cleared'
        }
    }

    It 'declares groups[].onPremisesSynced as a boolean that the apply engine never sends (A15)' {
        InModuleScope $script:moduleName {
            $Schema = Get-OERStructureSchemaJson | ConvertFrom-Json
            $Prop = $Schema.properties.groups.items.properties.onPremisesSynced
            $Prop | Should -Not -BeNullOrEmpty
            $Prop.type | Should -Be 'boolean'
            $Prop.description | Should -Match 'never sends'
            $Prop.description | Should -Match 'live'
        }
    }

    It 'accepts a boolean groups[].onPremisesSynced and rejects any other type (draft-07 matches the validator)' -Skip:(-not (Get-Command Test-Json).Parameters.ContainsKey('Schema')) {
        InModuleScope $script:moduleName {
            $Schema = Get-OERStructureSchemaJson
            $Valid = '{ "version": "1.0", "groups": [ { "displayName": "g", "onPremisesSynced": true } ] }'
            $Invalid = '{ "version": "1.0", "groups": [ { "displayName": "g", "onPremisesSynced": "yes" } ] }'
            Test-Json -Json $Valid -Schema $Schema -ErrorAction SilentlyContinue | Should -BeTrue
            Test-Json -Json $Invalid -Schema $Schema -ErrorAction SilentlyContinue | Should -BeFalse
        }
    }

    It 'validates the example apply document as conforming (mirrors Test-OERStructureSchema)' -Skip:(-not (Get-Command Test-Json).Parameters.ContainsKey('Schema')) {
        InModuleScope $script:moduleName {
            $Schema = Get-OERStructureSchemaJson
            $ExamplePath = Join-Path $PSScriptRoot '../../../docs/examples/example-structure.json'
            $Json = Get-Content -Path $ExamplePath -Raw
            Test-Json -Json $Json -Schema $Schema -ErrorAction SilentlyContinue | Should -BeTrue
        }
    }

    It 'rejects a document missing the required version key' -Skip:(-not (Get-Command Test-Json).Parameters.ContainsKey('Schema')) {
        InModuleScope $script:moduleName {
            $Schema = Get-OERStructureSchemaJson
            $Json = '{ "groups": [] }'
            Test-Json -Json $Json -Schema $Schema -ErrorAction SilentlyContinue | Should -BeFalse
        }
    }

    It 'rejects an unknown top-level key (closed root)' {
        InModuleScope $script:moduleName {
            $Schema = Get-OERStructureSchemaJson
            $Json = '{ "version": "1.0", "managementGroups": [] }'
            Test-Json -Json $Json -Schema $Schema -ErrorAction SilentlyContinue | Should -BeFalse
        }
    }

    It 'rejects an out-of-enum role assignment principalType' {
        InModuleScope $script:moduleName {
            $Schema = Get-OERStructureSchemaJson
            $Json = '{ "version": "1.0", "roleAssignments": [ { "scope": "/s", "role": "Reader", "principal": "p", "principalType": "ForeignGroup" } ] }'
            Test-Json -Json $Json -Schema $Schema -ErrorAction SilentlyContinue | Should -BeFalse
        }
    }

    It 'declares roleAssignments[].principalStatus as the closed set Deleted and Unresolved, and says what the engine does with it (A18)' {
        InModuleScope $script:moduleName {
            $Schema = Get-OERStructureSchemaJson | ConvertFrom-Json
            $Prop = $Schema.properties.roleAssignments.items.properties.principalStatus
            $Prop | Should -Not -BeNullOrEmpty
            $Prop.type | Should -Be 'string'
            @($Prop.enum) | Should -Be @('Deleted', 'Unresolved')
            $Prop.description | Should -Match 'object id'
            $Prop.description | Should -Match 'never creates'
            $Prop.description | Should -Match 'Skipped'
            # The key sits beside principalType, and neither joins the required keys.
            @($Schema.properties.roleAssignments.items.properties.PSObject.Properties.Name) |
                Should -Be @('scope', 'role', 'principal', 'principalType', 'principalStatus', 'description', 'condition', 'conditionVersion')
            @($Schema.properties.roleAssignments.items.required) | Should -Be @('scope', 'role', 'principal')
            # directoryRoleAssignments takes no principalStatus: the status is the Azure section's alone.
            $Schema.properties.directoryRoleAssignments.items.properties.PSObject.Properties.Name | Should -Not -Contain 'principalStatus'
        }
    }

    It 'accepts principalStatus Deleted and Unresolved and rejects any other value, case-sensitively (A18)' -Skip:(-not (Get-Command Test-Json).Parameters.ContainsKey('Schema')) {
        InModuleScope $script:moduleName {
            $Schema = Get-OERStructureSchemaJson
            $Row = '{ "version": "1.0", "roleAssignments": [ { "scope": "/s", "role": "Reader", "principal": "11111111-1111-1111-1111-111111111111", "principalStatus": "#V#" } ] }'
            foreach ($Value in 'Deleted', 'Unresolved') {
                Test-Json -Json $Row.Replace('#V#', $Value) -Schema $Schema -ErrorAction SilentlyContinue | Should -BeTrue -Because "'$Value' is a canonical principalStatus"
            }
            foreach ($Value in 'Gone', 'deleted', 'UNRESOLVED', '') {
                Test-Json -Json $Row.Replace('#V#', $Value) -Schema $Schema -ErrorAction SilentlyContinue | Should -BeFalse -Because "'$Value' is not a canonical principalStatus"
            }
            Test-Json -Json '{ "version": "1.0", "roleAssignments": [ { "scope": "/s", "role": "Reader", "principal": "p", "principalStatus": 1 } ] }' -Schema $Schema -ErrorAction SilentlyContinue |
                Should -BeFalse
        }
    }

    It 'rejects an activationMaxHours outside the 1-24 range' {
        InModuleScope $script:moduleName {
            $Schema = Get-OERStructureSchemaJson
            $Json = '{ "version": "1.0", "roleManagementPolicies": [ { "scope": "/s", "role": "Owner", "activationMaxHours": 99 } ] }'
            Test-Json -Json $Json -Schema $Schema -ErrorAction SilentlyContinue | Should -BeFalse
        }
    }

    It 'validates a nested member/owner pimPolicy document' {
        InModuleScope $script:moduleName {
            $Schema = Get-OERStructureSchemaJson
            $Json = '{ "version": "1.0", "groups": [ { "displayName": "g1", "pimPolicy": { "member": { "activationMaxHours": 8, "activeEnablement": ["MultiFactorAuthentication"], "notifications": { "activeAlert": ["person18@example.com"] } }, "owner": { "activationMaxHours": 1 } } } ] }'
            Test-Json -Json $Json -Schema $Schema -ErrorAction SilentlyContinue | Should -BeTrue
        }
    }

    It 'still validates the flat member-only pimPolicy (back-compat)' {
        InModuleScope $script:moduleName {
            $Schema = Get-OERStructureSchemaJson
            $Json = '{ "version": "1.0", "groups": [ { "displayName": "g1", "pimPolicy": { "activationMaxHours": 8, "allowPermanentEligibility": true } } ] }'
            Test-Json -Json $Json -Schema $Schema -ErrorAction SilentlyContinue | Should -BeTrue
        }
    }

    It 'rejects a nested activationMaxHours outside 1-24' {
        InModuleScope $script:moduleName {
            $Schema = Get-OERStructureSchemaJson
            $Json = '{ "version": "1.0", "groups": [ { "displayName": "g1", "pimPolicy": { "member": { "activationMaxHours": 99 } } } ] }'
            Test-Json -Json $Json -Schema $Schema -ErrorAction SilentlyContinue | Should -BeFalse
        }
    }

    It 'rejects an enablement value outside the enum' {
        InModuleScope $script:moduleName {
            $Schema = Get-OERStructureSchemaJson
            $Json = '{ "version": "1.0", "groups": [ { "displayName": "g1", "pimPolicy": { "member": { "activeEnablement": ["Nope"] } } } ] }'
            Test-Json -Json $Json -Schema $Schema -ErrorAction SilentlyContinue | Should -BeFalse
        }
    }

    It 'assignmentPolicies items contain all new granular top-level fields' {
        InModuleScope $script:moduleName {
            $Parsed = Get-OERStructureSchemaJson | ConvertFrom-Json
            $APProps = $Parsed.properties.accessPackages.items.properties.assignmentPolicies.items.properties
            $APProps.PSObject.Properties.Name | Should -Contain 'requestorSettings'
            $APProps.PSObject.Properties.Name | Should -Contain 'requireApproval'
            $APProps.PSObject.Properties.Name | Should -Contain 'requireRequestorJustification'
            $APProps.PSObject.Properties.Name | Should -Contain 'requireApprovalForUpdate'
            $APProps.PSObject.Properties.Name | Should -Contain 'durationInHours'
            $APProps.PSObject.Properties.Name | Should -Contain 'expirationDateTime'
            $APProps.PSObject.Properties.Name | Should -Contain 'notificationsDisabled'
        }
    }

    It 'requestorScope.properties contains users and groups' {
        InModuleScope $script:moduleName {
            $Parsed = Get-OERStructureSchemaJson | ConvertFrom-Json
            $RSProps = $Parsed.properties.accessPackages.items.properties.assignmentPolicies.items.properties.requestorScope.properties
            $RSProps.PSObject.Properties.Name | Should -Contain 'users'
            $RSProps.PSObject.Properties.Name | Should -Contain 'groups'
        }
    }

    It 'requestorScope states the SpecificDirectoryUsers inference rule (issue #69)' {
        InModuleScope $script:moduleName {
            $Parsed = Get-OERStructureSchemaJson | ConvertFrom-Json
            $RScope = $Parsed.properties.accessPackages.items.properties.assignmentPolicies.items.properties.requestorScope
            $RScope.description | Should -Match 'infers scope as SpecificDirectoryUsers'
            $RScope.description | Should -Match 'An explicit scope always wins'
        }
    }

    It 'does not require requestorScope.scope, matching the offline validators relaxed rule (issue #69)' {
        InModuleScope $script:moduleName {
            $Parsed = Get-OERStructureSchemaJson | ConvertFrom-Json
            $RScope = $Parsed.properties.accessPackages.items.properties.assignmentPolicies.items.properties.requestorScope
            @($RScope.required) | Should -Not -Contain 'scope'
        }
    }

    It 'validates a case-1 document (users declared, scope omitted) against the shipped schema (issue #69)' {
        InModuleScope $script:moduleName {
            # This is the exact shape issue #69 is about: requestorScope declares a non-empty users
            # array and no scope. Invoke-OERStructure accepts it (a Warning, not an Error) since
            # Build-OERPolicyParts infers SpecificDirectoryUsers -- an external draft-07 consumer of
            # this schema string must accept it too, or the artifact contradicts the module.
            $Doc = @'
{ "version": "1.0", "accessPackages": [ { "displayName": "AP", "catalog": "CAT",
  "assignmentPolicies": [ { "displayName": "P", "requestorScope": { "users": ["u1@contoso.com"] } } ] } ] }
'@
            Test-Json -Json $Doc -Schema (Get-OERStructureSchemaJson) | Should -BeTrue
        }
    }

    It 'requestorSettings.properties contains the three new booleans (allowSelfRemove, allowOnBehalfUpdate, allowOnBehalfRemove)' {
        InModuleScope $script:moduleName {
            $Parsed = Get-OERStructureSchemaJson | ConvertFrom-Json
            $RstProps = $Parsed.properties.accessPackages.items.properties.assignmentPolicies.items.properties.requestorSettings.properties
            $RstProps.PSObject.Properties.Name | Should -Contain 'allowSelfRemove'
            $RstProps.PSObject.Properties.Name | Should -Contain 'allowOnBehalfUpdate'
            $RstProps.PSObject.Properties.Name | Should -Contain 'allowOnBehalfRemove'
        }
    }

    It 'validates a document declaring the three new requestorSettings booleans' {
        InModuleScope $script:moduleName {
            $Schema = Get-OERStructureSchemaJson
            $Json = @'
{
  "version": "1.0",
  "accessPackages": [
    {
      "displayName": "TestPkg",
      "catalog": "TestCat",
      "assignmentPolicies": [
        {
          "displayName": "TestPolicy",
          "requestorSettings": { "allowSelfRemove": true, "allowOnBehalfUpdate": true, "allowOnBehalfRemove": false }
        }
      ]
    }
  ]
}
'@
            Test-Json -Json $Json -Schema $Schema -ErrorAction SilentlyContinue | Should -BeTrue
        }
    }

    It 'approvalStages items contain new granular fields' {
        InModuleScope $script:moduleName {
            $Parsed = Get-OERStructureSchemaJson | ConvertFrom-Json
            $StageProps = $Parsed.properties.accessPackages.items.properties.assignmentPolicies.items.properties.approvalStages.items.properties
            $StageProps.PSObject.Properties.Name | Should -Contain 'managerLevel'
            $StageProps.PSObject.Properties.Name | Should -Contain 'users'
            $StageProps.PSObject.Properties.Name | Should -Contain 'groups'
            $StageProps.PSObject.Properties.Name | Should -Contain 'alternateUsers'
            $StageProps.PSObject.Properties.Name | Should -Contain 'alternateGroups'
            $StageProps.PSObject.Properties.Name | Should -Contain 'fallbackUsers'
            $StageProps.PSObject.Properties.Name | Should -Contain 'fallbackGroups'
            $StageProps.PSObject.Properties.Name | Should -Contain 'internalSponsor'
            $StageProps.PSObject.Properties.Name | Should -Contain 'externalSponsor'
            $StageProps.PSObject.Properties.Name | Should -Contain 'requireApproverJustification'
            $StageProps.PSObject.Properties.Name | Should -Contain 'escalationDays'
            $StageProps.PSObject.Properties.Name | Should -Contain 'approverInfoVisibility'
        }
    }

    It 'validates a document declaring approvalStages.fallbackUsers and fallbackGroups' {
        InModuleScope $script:moduleName {
            $Schema = Get-OERStructureSchemaJson
            $Json = @'
{
  "version": "1.0",
  "accessPackages": [
    {
      "displayName": "TestPkg",
      "catalog": "TestCat",
      "assignmentPolicies": [
        {
          "displayName": "TestPolicy",
          "approvalStages": [
            {
              "durationDays": 7,
              "manager": true,
              "fallbackUsers": ["person25@example.com"],
              "fallbackGroups": ["FB Group"]
            }
          ]
        }
      ]
    }
  ]
}
'@
            Test-Json -Json $Json -Schema $Schema -ErrorAction SilentlyContinue | Should -BeTrue
        }
    }

    It 'approverInfoVisibility has the correct enum values' {
        InModuleScope $script:moduleName {
            $Parsed = Get-OERStructureSchemaJson | ConvertFrom-Json
            $AivEnum = $Parsed.properties.accessPackages.items.properties.assignmentPolicies.items.properties.approvalStages.items.properties.approverInfoVisibility.enum
            $AivEnum | Should -Contain 'Default'
            $AivEnum | Should -Contain 'Visible'
            $AivEnum | Should -Contain 'NotVisible'
        }
    }

    It 'validates a document using the new granular AP fields' {
        InModuleScope $script:moduleName {
            $Schema = Get-OERStructureSchemaJson
            $Json = @'
{
  "version": "1.0",
  "accessPackages": [
    {
      "displayName": "TestPkg",
      "catalog": "TestCat",
      "assignmentPolicies": [
        {
          "displayName": "TestPolicy",
          "requestorScope": { "scope": "specificDirectorySubjects", "users": ["person44@example.com"], "groups": [] },
          "requestorSettings": { "allowSelfRequest": true, "allowManagerRequest": false, "managerLevel": 1, "allowCustomSchedule": false, "allowSelfExtend": false },
          "requireApproval": true,
          "requireRequestorJustification": true,
          "requireApprovalForUpdate": false,
          "notificationsDisabled": false,
          "durationInHours": 8,
          "expirationDateTime": "2030-01-01T00:00:00Z",
          "approvalStages": [
            {
              "durationDays": 7,
              "manager": false,
              "managerLevel": 1,
              "users": ["person44@example.com"],
              "groups": [],
              "alternateUsers": [],
              "alternateGroups": [],
              "internalSponsor": false,
              "externalSponsor": false,
              "requireApproverJustification": true,
              "escalationDays": 3,
              "approverInfoVisibility": "Visible"
            }
          ]
        }
      ]
    }
  ]
}
'@
            Test-Json -Json $Json -Schema $Schema -ErrorAction SilentlyContinue | Should -BeTrue
        }
    }

    It 'rejects approverInfoVisibility outside the enum' {
        InModuleScope $script:moduleName {
            $Schema = Get-OERStructureSchemaJson
            $Json = @'
{
  "version": "1.0",
  "accessPackages": [
    {
      "displayName": "TestPkg",
      "catalog": "TestCat",
      "assignmentPolicies": [
        {
          "displayName": "TestPolicy",
          "approvalStages": [ { "approverInfoVisibility": "InvalidValue" } ]
        }
      ]
    }
  ]
}
'@
            Test-Json -Json $Json -Schema $Schema -ErrorAction SilentlyContinue | Should -BeFalse
        }
    }

    It 'declares url on a catalog resource' {
        InModuleScope $script:moduleName {
            $Schema = Get-OERStructureSchemaJson | ConvertFrom-Json
            $Schema.properties.catalogs.items.properties.resources.items.properties.url.type |
                Should -Be 'string'
        }
    }

    It 'validates a document carrying a SharePoint resource url' {
        InModuleScope $script:moduleName {
            $Doc = @'
{ "version": "1.0", "catalogs": [ { "displayName": "CAT-Core", "resources": [
  { "name": "Finance", "type": "SharePointSite",
    "url": "https://contoso.sharepoint.com/sites/finance" } ] } ] }
'@
            Test-Json -Json $Doc -Schema (Get-OERStructureSchemaJson) | Should -BeTrue
        }
    }

    It 'declares mailNickname and administrativeUnit on a group' {
        InModuleScope $script:moduleName {
            $Schema = Get-OERStructureSchemaJson | ConvertFrom-Json
            $Props  = $Schema.properties.groups.items.properties
            $Props.mailNickname.type       | Should -Be 'string'
            $Props.administrativeUnit.type | Should -Be 'string'
        }
    }

    It 'documents the administrativeUnits[].members reciprocal placement rule on administrativeUnit (issue #59)' {
        InModuleScope $script:moduleName {
            $Schema = Get-OERStructureSchemaJson | ConvertFrom-Json
            $Description = $Schema.properties.groups.items.properties.administrativeUnit.description
            $Description | Should -Match 'administrativeUnits\[\]'
            $Description | Should -Match 'members'
            $Description | Should -Match '-Prune'
        }
    }

    It 'says how administrativeUnit is matched to the unit entry: a GUID by id compared as a GUID, any other value by displayName ignoring case (BL-100)' {
        # Since Sprint 9 step 6 (ruling R14) a value that parses as a GUID is compared AS A GUID with the
        # entry's declared id (so braced and dash-less forms match), and any other value is compared with
        # displayName ignoring case. The earlier text said displayName OR id matched "this value (ignoring
        # case)", which is no longer how the check reads it.
        InModuleScope $script:moduleName {
            $Schema = Get-OERStructureSchemaJson | ConvertFrom-Json
            $Description = $Schema.properties.groups.items.properties.administrativeUnit.description
            $Description | Should -Match ([regex]::Escape('by its declared id when the value parses as a GUID (compared as a GUID, so braced and dash-less forms match), otherwise by its displayName, ignoring case'))
            $Description | Should -Not -Match ([regex]::Escape('matches this value (ignoring case)'))
        }
    }

    It 'declares every access review field the apply handler consumes' {
        InModuleScope $script:moduleName {
            $Schema = Get-OERStructureSchemaJson | ConvertFrom-Json
            $Props  = $Schema.properties.accessReviews.items.properties
            foreach ($Name in @('reviewers', 'fallbackReviewers', 'descriptionForAdmins',
                                'descriptionForReviewers', 'durationInDays', 'startDate', 'endDate',
                                'occurrences', 'mailNotification', 'reminderNotification',
                                'requireJustification', 'recommendationsEnabled', 'autoApplyDecisions',
                                'defaultDecision')) {
                $Props.PSObject.Properties.Name | Should -Contain $Name
            }
            $Props.reviewers.items.type      | Should -Be 'string'
            $Props.durationInDays.maximum    | Should -Be 365
            @($Props.defaultDecision.enum)   | Should -Contain 'Recommendation'
        }
    }

    It 'validates a fully populated access review entry' {
        InModuleScope $script:moduleName {
            $Doc = @'
{ "version": "1.0", "accessReviews": [ {
  "displayName": "Q3 AP review", "accessPackage": "AP-Sales", "assignmentPolicy": "Standard",
  "recurrence": "Quarterly", "startDate": "2026-07-01", "occurrences": 4,
  "durationInDays": 14, "reviewers": [ "manager" ], "fallbackReviewers": [ "anna@contoso.com" ],
  "descriptionForAdmins": "a", "descriptionForReviewers": "r",
  "mailNotification": true, "reminderNotification": true, "requireJustification": true,
  "recommendationsEnabled": true, "autoApplyDecisions": false, "defaultDecision": "Deny" } ] }
'@
            Test-Json -Json $Doc -Schema (Get-OERStructureSchemaJson) | Should -BeTrue
        }
    }

    It 'declares every enum with exactly the canonical set Resolve-OERStructureEnumCasing owns' {
        InModuleScope $script:moduleName {
            # The rule has one owner. This gate fails if a future edit changes an "enum" array in the
            # schema without changing the owner, or the other way round -- which is precisely how the
            # validator and the schema drifted apart in the first place.
            $Raw = Get-OERStructureSchemaJson
            $Declared = [System.Collections.Generic.List[string]]::new()
            $NullBearing = 0
            foreach ($Match in [regex]::Matches($Raw, '"enum"\s*:\s*\[(?<Body>[^\]]*)\]')) {
                $Values = @($Match.Groups['Body'].Value -split ',' | ForEach-Object { $_.Trim().Trim('"') })
                # A bare JSON null member is the nullable-key marker, not a value of the enum.
                # Resolve-OERStructureEnumCasing owns the STRING values only, so strip it before
                # comparing -- otherwise a nullable enum would look like drift from its owner.
                if ($Values -contains 'null') {
                    $NullBearing++
                    $Values = @($Values | Where-Object { $_ -ne 'null' })
                }
                $Declared.Add(($Values -join ','))
            }
            $Declared.Count | Should -Be 15 -Because 'the schema declares 15 enum arrays across 10 distinct enums'
            $NullBearing | Should -Be 1 -Because 'accessReviews[].recurrence is the only nullable enum in the schema'

            $Owned = @{}
            foreach ($Name in 'accessType', 'enablement', 'membershipRuleProcessingState', 'catalogResourceType',
                'approverInfoVisibility', 'accessReviewRecurrence', 'accessReviewDefaultDecision', 'principalType',
                'directoryRoleAssignmentType', 'principalStatus') {
                $Owned[(@(Resolve-OERStructureEnumCasing -EnumName $Name -List) -join ',')] = $Name
            }
            foreach ($Set in $Declared) {
                $Owned.ContainsKey($Set) | Should -Be $true -Because "the schema declares [$Set], which no enum in Resolve-OERStructureEnumCasing owns"
            }
            foreach ($Set in $Owned.Keys) {
                $Declared -contains $Set | Should -Be $true -Because "Resolve-OERStructureEnumCasing owns [$Set], which the schema never declares"
            }
        }
    }
}

Describe 'Get-OERStructureSchemaJson group pimPolicy approval' {
    It 'declares requireApproval and approvers identically in both the definitions block and the flat pimPolicy block' {
        InModuleScope $script:moduleName {
            $Schema = Get-OERStructureSchemaJson | ConvertFrom-Json
            $DefProps = $Schema.definitions.pimPolicyBlock.properties
            $FlatProps = $Schema.properties.groups.items.properties.pimPolicy.properties

            $DefProps.requireApproval.type | Should -Be 'boolean'
            $FlatProps.requireApproval.type | Should -Be 'boolean'

            $DefProps.approvers.type | Should -Be 'object'
            $FlatProps.approvers.type | Should -Be 'object'
            $DefProps.approvers.properties.users.items.type | Should -Be 'string'
            $DefProps.approvers.properties.groups.items.type | Should -Be 'string'
            $FlatProps.approvers.properties.users.items.type | Should -Be 'string'
            $FlatProps.approvers.properties.groups.items.type | Should -Be 'string'

            # The flat pimPolicy fields must equal the definitions block fields for these two keys.
            ($FlatProps.requireApproval | ConvertTo-Json -Compress) |
                Should -Be ($DefProps.requireApproval | ConvertTo-Json -Compress)
            ($FlatProps.approvers | ConvertTo-Json -Compress -Depth 6) |
                Should -Be ($DefProps.approvers | ConvertTo-Json -Compress -Depth 6)
        }
    }

    It 'documents the requireApproval-false precedence on the pimPolicy approvers block' {
        InModuleScope $script:moduleName {
            $Schema = Get-OERStructureSchemaJson | ConvertFrom-Json
            $Schema.definitions.pimPolicyBlock.properties.approvers.description | Should -Match 'requireApproval'
            $Schema.properties.groups.items.properties.pimPolicy.properties.approvers.description | Should -Match 'requireApproval'
        }
    }

    It 'validates a document declaring requireApproval and approvers on both the nested and flat forms' {
        InModuleScope $script:moduleName {
            $Schema = Get-OERStructureSchemaJson
            $Json = @'
{
  "version": "1.0",
  "groups": [
    {
      "displayName": "g1",
      "pimPolicy": {
        "member": { "requireApproval": true, "approvers": { "users": ["person1@example.com"], "groups": ["Sec Approvers"] } },
        "owner": { "requireApproval": false }
      }
    },
    {
      "displayName": "g2",
      "pimPolicy": { "requireApproval": true, "approvers": { "groups": ["Sec Approvers"] } }
    }
  ]
}
'@
            Test-Json -Json $Json -Schema $Schema -ErrorAction SilentlyContinue | Should -BeTrue
        }
    }

    It 'rejects a non-boolean requireApproval' {
        InModuleScope $script:moduleName {
            $Schema = Get-OERStructureSchemaJson
            $Json = '{ "version": "1.0", "groups": [ { "displayName": "g1", "pimPolicy": { "requireApproval": "yes" } } ] }'
            Test-Json -Json $Json -Schema $Schema -ErrorAction SilentlyContinue | Should -BeFalse
        }
    }
}

Describe 'Get-OERStructureSchemaJson eligibility accessType' {
    It 'declares accessType on the eligibility item with the member/owner enum' {
        InModuleScope Omnicit.EntraRBAC {
            $Schema = Get-OERStructureSchemaJson | ConvertFrom-Json
            $Elig = $Schema.properties.groups.items.properties.eligibility.items
            $Elig.properties.accessType.enum | Should -Be @('member', 'owner')
        }
    }

    It 'still validates a document that omits accessType (back-compat)' {
        InModuleScope Omnicit.EntraRBAC {
            $Doc = @{
                version = '1'
                groups  = @(@{ displayName = 'g'; eligibility = @(@{ principal = 'person17@example.com'; durationDays = 30 }) })
            } | ConvertTo-Json -Depth 8
            Test-Json -Json $Doc -Schema (Get-OERStructureSchemaJson) | Should -BeTrue
        }
    }

    It 'rejects an out-of-enum accessType' {
        InModuleScope Omnicit.EntraRBAC {
            $Doc = @{
                version = '1'
                groups  = @(@{ displayName = 'g'; eligibility = @(@{ principal = 'person17@example.com'; accessType = 'admin' }) })
            } | ConvertTo-Json -Depth 8
            Test-Json -Json $Doc -Schema (Get-OERStructureSchemaJson) -ErrorAction SilentlyContinue | Should -BeFalse
        }
    }
}

Describe 'Get-OERStructureSchemaJson administrative unit dynamic and visibility' {
    It 'declares dynamic, membershipRule, membershipRuleProcessingState and hiddenMembership' {
        InModuleScope Omnicit.EntraRBAC {
            $Au = (Get-OERStructureSchemaJson | ConvertFrom-Json).properties.administrativeUnits.items.properties
            $Au.dynamic.type | Should -Be 'boolean'
            $Au.membershipRule.type | Should -Be 'string'
            $Au.membershipRuleProcessingState.enum | Should -Be @('On', 'Paused')
            $Au.hiddenMembership.type | Should -Be 'boolean'
        }
    }
}

Describe 'Get-OERStructureSchemaJson group owners' {
    It 'declares owners as an array of strings on the group item' {
        InModuleScope Omnicit.EntraRBAC {
            $Grp = (Get-OERStructureSchemaJson | ConvertFrom-Json).properties.groups.items.properties
            $Grp.owners.type | Should -Be 'array'
            $Grp.owners.items.type | Should -Be 'string'
        }
    }
}

Describe 'Get-OERStructureSchemaJson group membershipRuleProcessingState' {
    It 'declares membershipRuleProcessingState with the On/Paused enum on the group item' {
        InModuleScope Omnicit.EntraRBAC {
            $Grp = (Get-OERStructureSchemaJson | ConvertFrom-Json).properties.groups.items.properties
            $Grp.membershipRuleProcessingState.enum | Should -Be @('On', 'Paused')
        }
    }
}

Describe 'Get-OERStructureSchemaJson catalog externallyVisible' {
    It 'declares the externallyVisible boolean on the catalog item' {
        InModuleScope Omnicit.EntraRBAC {
            (Get-OERStructureSchemaJson | ConvertFrom-Json).properties.catalogs.items.properties.externallyVisible.type |
                Should -Be 'boolean'
        }
    }
}

Describe 'Get-OERStructureSchemaJson access package hidden' {
    It 'declares the hidden boolean on the access package item' {
        InModuleScope Omnicit.EntraRBAC {
            (Get-OERStructureSchemaJson | ConvertFrom-Json).properties.accessPackages.items.properties.hidden.type |
                Should -Be 'boolean'
        }
    }
}

Describe 'Get-OERStructureSchemaJson role assignment condition' {
    It 'declares description, condition and conditionVersion' {
        InModuleScope Omnicit.EntraRBAC {
            $Ra = (Get-OERStructureSchemaJson | ConvertFrom-Json).properties.roleAssignments.items.properties
            $Ra.description.type | Should -Be 'string'
            $Ra.condition.type | Should -Be 'string'
            $Ra.conditionVersion.type | Should -Be 'string'
        }
    }
}

Describe 'Get-OERStructureSchemaJson role management policy full field set' {
    It 'declares the full role management policy field set' {
        InModuleScope Omnicit.EntraRBAC {
            $Schema = Get-OERStructureSchemaJson | ConvertFrom-Json
            $Props  = $Schema.properties.roleManagementPolicies.items.properties
            foreach ($Name in @('allowPermanentEligibility', 'eligibleDurationDays',
                                'allowPermanentActiveAssignment', 'activeDurationDays', 'activationMaxHours',
                                'requireMfaOnActivation', 'requireJustificationOnActivation',
                                'requireTicketOnActivation', 'requireApproval', 'approvers',
                                'authenticationContextId', 'requireMfaOnActiveAssignment',
                                'requireJustificationOnActiveAssignment')) {
                $Props.PSObject.Properties.Name | Should -Contain $Name
            }
            $Props.eligibleDurationDays.maximum | Should -Be 3650
            $Props.activationMaxHours.maximum   | Should -Be 24
            $Props.approvers.properties.users.items.type | Should -Be 'string'
        }
    }

    It 'validates a fully populated role management policy entry' {
        InModuleScope Omnicit.EntraRBAC {
            $Doc = @'
{ "version": "1.0", "roleManagementPolicies": [ {
  "scope": "/subscriptions/sub-1", "role": "Contributor",
  "allowPermanentEligibility": true, "eligibleDurationDays": 365,
  "allowPermanentActiveAssignment": false, "activeDurationDays": 180,
  "activationMaxHours": 4, "requireMfaOnActivation": true,
  "requireJustificationOnActivation": true, "requireTicketOnActivation": false,
  "requireApproval": true, "approvers": { "groups": [ "sec-approvers" ] },
  "requireMfaOnActiveAssignment": false, "requireJustificationOnActiveAssignment": true } ] }
'@
            Test-Json -Json $Doc -Schema (Get-OERStructureSchemaJson) | Should -BeTrue
        }
    }
}

Describe 'Get-OERStructureSchemaJson round-trip precedence documentation' {
    It 'documents that a null authenticationContextId means undeclared' {
        InModuleScope Omnicit.EntraRBAC {
            $Props = (Get-OERStructureSchemaJson | ConvertFrom-Json).properties.roleManagementPolicies.items.properties
            $Props.authenticationContextId.type | Should -Contain 'null'
            $Props.authenticationContextId.description | Should -Match 'null'
            $Props.authenticationContextId.description | Should -Match 'untouched'
        }
    }

    It 'documents that requireApproval false takes precedence over approvers' {
        InModuleScope Omnicit.EntraRBAC {
            $Props = (Get-OERStructureSchemaJson | ConvertFrom-Json).properties.roleManagementPolicies.items.properties
            $Props.approvers.description | Should -Match 'requireApproval'
        }
    }

    It 'documents the access review update carry-forward limitation' {
        InModuleScope Omnicit.EntraRBAC {
            (Get-OERStructureSchemaJson | ConvertFrom-Json).properties.accessReviews.description |
                Should -Match 'PUT'
        }
    }

    It 'documents that an existing access review is updated only when it reviews the declared package and policy (BL-127)' {
        InModuleScope Omnicit.EntraRBAC {
            (Get-OERStructureSchemaJson | ConvertFrom-Json).properties.accessReviews.description |
                Should -Match ([regex]::Escape('an existing review is updated in place only when it reviews the declared accessPackage and assignmentPolicy; otherwise the entry fails and nothing is written.'))
        }
    }

    It 'still recommends rather than requires a SharePointSite url' {
        InModuleScope Omnicit.EntraRBAC {
            $Res = (Get-OERStructureSchemaJson | ConvertFrom-Json).properties.catalogs.items.properties.resources.items
            $Res.required | Should -Not -Contain 'url'
            $Res.properties.url.description | Should -Match 'Strongly recommended'
        }
    }
}

Describe 'Get-OERStructureSchemaJson nullable accessReviews recurrence' {
    # CHANGELOG advertises that an explicit "recurrence": null means a one-time review, and
    # Test-OERStructureSchema accepts it (Test-OERDeclaredProperty is false for a null, so the
    # OneTime default applies). The schema.json written into every export bundle is the artefact an
    # LLM authors against, so it must not reject what the module accepts.
    It 'types recurrence as string or null' {
        InModuleScope $script:moduleName {
            $Props = (Get-OERStructureSchemaJson | ConvertFrom-Json).properties.accessReviews.items.properties
            @($Props.recurrence.type) | Should -Be @('string', 'null')
        }
    }

    It 'carries a null member in the recurrence enum alongside the six canonical values' {
        InModuleScope $script:moduleName {
            # draft-07 applies "type" and "enum" independently against the same instance, so widening
            # only "type" leaves the enum rejecting null. Measured: with null in "type" but not in
            # "enum", Test-Json reports 'Value should match one of the values specified by the enum'.
            $Props = (Get-OERStructureSchemaJson | ConvertFrom-Json).properties.accessReviews.items.properties
            $Enum  = @($Props.recurrence.enum)
            $Enum.Count | Should -Be 7 -Because 'the six canonical spellings plus one JSON null'
            @($Enum | Where-Object { $null -ne $_ }) |
                Should -Be @('OneTime', 'Weekly', 'Monthly', 'Quarterly', 'SemiAnnually', 'Annually')
        }
    }

    It 'documents that an explicit null means a one-time review' {
        InModuleScope $script:moduleName {
            $Props = (Get-OERStructureSchemaJson | ConvertFrom-Json).properties.accessReviews.items.properties
            $Props.recurrence.description | Should -Match 'one-time'
            $Props.recurrence.description | Should -Match 'null'
        }
    }

    It 'validates a document declaring recurrence null, and still rejects a bogus recurrence' {
        InModuleScope $script:moduleName {
            $Schema = Get-OERStructureSchemaJson
            $Base = '{ "version": "1", "accessReviews": [ { "displayName": "R", "accessPackage": "AP", "assignmentPolicy": "P", "recurrence": %V% } ] }'
            # Positive identity first: the canonical value validates, so the fixture itself is sound.
            Test-Json -Json ($Base -replace '%V%', '"Quarterly"') -Schema $Schema | Should -BeTrue
            Test-Json -Json ($Base -replace '%V%', '"SemiAnnually"') -Schema $Schema |
                Should -BeTrue -Because 'the semi-annual cadence is part of the vocabulary'
            Test-Json -Json ($Base -replace '%V%', 'null') -Schema $Schema |
                Should -BeTrue -Because 'an explicit null is the one-time default, not a validation failure'
            # The null member must not have neutered the enum for strings.
            Test-Json -Json ($Base -replace '%V%', '"Fortnightly"') -Schema $Schema -ErrorAction SilentlyContinue |
                Should -BeFalse -Because 'an out-of-set recurrence spelling is still invalid'
            Test-Json -Json ($Base -replace '%V%', '5') -Schema $Schema -ErrorAction SilentlyContinue |
                Should -BeFalse -Because 'a non-string, non-null recurrence is still invalid'
        }
    }

    It 'agrees with the offline validator, which treats a null recurrence as undeclared' {
        InModuleScope $script:moduleName {
            $Doc = @'
{ "version": "1", "accessReviews": [ { "displayName": "R", "accessPackage": "AP",
  "assignmentPolicy": "P", "recurrence": null } ] }
'@ | ConvertFrom-Json
            $Result = Test-OERStructureSchema -Document $Doc
            @($Result | Where-Object { $_.Severity -eq 'Error' }) | Should -BeNullOrEmpty
        }
    }

    It 'widened no other key as a side effect' {
        InModuleScope $script:moduleName {
            # The complete inventory of nullable-typed keys, asserted in BOTH directions so a stray
            # widening elsewhere in the schema fails here rather than shipping unnoticed.
            $Schema = Get-OERStructureSchemaJson | ConvertFrom-Json
            $Found = [System.Collections.Generic.List[string]]::new()
            function Get-NullableTypePath {
                param([object]$Node, [string]$Path, [System.Collections.Generic.List[string]]$Sink)
                if ($Node -isnot [PSCustomObject]) { return }
                if (($Node.PSObject.Properties.Name -contains 'type') -and
                    ($Node.type -is [System.Array]) -and (@($Node.type) -contains 'null')) {
                    $Sink.Add($Path)
                }
                foreach ($Prop in $Node.PSObject.Properties) {
                    if ($Prop.Value -is [PSCustomObject]) {
                        Get-NullableTypePath -Node $Prop.Value -Path "$Path/$($Prop.Name)" -Sink $Sink
                    }
                }
            }
            Get-NullableTypePath -Node $Schema -Path '' -Sink $Found

            $Expected = @(
                '/definitions/pimPolicyBlock/properties/authenticationContextId'
                '/properties/accessPackages/items/properties/assignmentPolicies/items/properties/description'
                '/properties/accessPackages/items/properties/description'
                '/properties/accessPackages/items/properties/resourceRoles'
                '/properties/accessReviews/items/properties/recurrence'
                '/properties/administrativeUnits/items/properties/description'
                '/properties/administrativeUnits/items/properties/members'
                '/properties/administrativeUnits/items/properties/scopedRoles'
                '/properties/catalogs/items/properties/description'
                '/properties/catalogs/items/properties/resources'
                '/properties/directoryRoleManagementPolicies/items/properties/authenticationContextId'
                '/properties/groups/items/properties/description'
                '/properties/groups/items/properties/members'
                '/properties/groups/items/properties/pimPolicy/properties/authenticationContextId'
                '/properties/roleManagementPolicies/items/properties/authenticationContextId'
            )
            @($Found | Sort-Object) | Should -Be $Expected
            # owners and eligibility stay non-nullable on purpose: an omitted key is already
            # hands-off for them, so a null there would be surface with no producer.
            $GroupProps = $Schema.properties.groups.items.properties
            $GroupProps.owners.type      | Should -Be 'array'
            $GroupProps.eligibility.type | Should -Be 'array'
        }
    }
}

Describe 'Get-OERStructureSchemaJson directory role management policies' {
    # directoryRoleManagementPolicies[] is roleManagementPolicies[] without scope: a directory role
    # policy always lives at tenant scope, so role is the only required key.
    It 'declares directoryRoleManagementPolicies at the root as an array of objects requiring only role, with no scope' {
        InModuleScope $script:moduleName {
            $Schema = Get-OERStructureSchemaJson | ConvertFrom-Json
            $Schema.properties.PSObject.Properties.Name | Should -Contain 'directoryRoleManagementPolicies'
            $Section = $Schema.properties.directoryRoleManagementPolicies
            $Section.type | Should -BeExactly 'array'
            $Section.items.type | Should -BeExactly 'object'
            @($Section.items.required) | Should -Be @('role')
            $Section.items.properties.PSObject.Properties.Name | Should -Not -Contain 'scope'
        }
    }

    It 'types every directory field exactly like the matching roleManagementPolicies field' {
        InModuleScope $script:moduleName {
            $Schema = Get-OERStructureSchemaJson | ConvertFrom-Json
            $Azure = $Schema.properties.roleManagementPolicies.items.properties
            $Directory = $Schema.properties.directoryRoleManagementPolicies.items.properties
            # Everything but the description text: type, bounds and nested shape.
            function Get-TypeShape {
                param([object]$Node)
                if ($Node -isnot [PSCustomObject]) { return $Node }
                $Out = [ordered]@{}
                foreach ($Prop in $Node.PSObject.Properties) {
                    if ($Prop.Name -eq 'description') { continue }
                    $Out[$Prop.Name] = Get-TypeShape -Node $Prop.Value
                }
                [PSCustomObject]$Out
            }
            $Expected = @($Azure.PSObject.Properties.Name | Where-Object { $_ -ne 'scope' })
            @($Directory.PSObject.Properties.Name) | Should -Be $Expected
            foreach ($Name in $Expected) {
                (Get-TypeShape -Node $Directory.$Name | ConvertTo-Json -Depth 10 -Compress) |
                    Should -BeExactly (Get-TypeShape -Node $Azure.$Name | ConvertTo-Json -Depth 10 -Compress) -Because "'$Name' carries the same type in both sections"
            }
        }
    }

    It 'documents on approvers that only the declared side is replaced and that requireApproval false wins' {
        InModuleScope $script:moduleName {
            $Props = (Get-OERStructureSchemaJson | ConvertFrom-Json).properties.directoryRoleManagementPolicies.items.properties
            $Props.approvers.description | Should -Match 'requireApproval false TAKES PRECEDENCE'
            $Props.approvers.description | Should -Match 'Only the declared side is replaced'
            $Props.approvers.description | Should -Match 'object id'
            $Props.authenticationContextId.description | Should -Match 'NOT DECLARED'
        }
    }

    It 'validates a fully populated directory role management policy entry' -Skip:(-not (Get-Command Test-Json).Parameters.ContainsKey('Schema')) {
        InModuleScope $script:moduleName {
            $Doc = @'
{ "version": "1.0", "directoryRoleManagementPolicies": [ {
  "role": "Reports Reader",
  "allowPermanentEligibility": false, "eligibleDurationDays": 365,
  "allowPermanentActiveAssignment": false, "activeDurationDays": 180,
  "activationMaxHours": 4, "requireMfaOnActivation": true,
  "requireJustificationOnActivation": true, "requireTicketOnActivation": false,
  "requireApproval": true, "approvers": { "users": [ "person1@example.com" ], "groups": [ "Approvers" ] },
  "authenticationContextId": null,
  "requireMfaOnActiveAssignment": false, "requireJustificationOnActiveAssignment": true } ] }
'@
            Test-Json -Json $Doc -Schema (Get-OERStructureSchemaJson) | Should -BeTrue
        }
    }

    It 'rejects a directory entry without role, and one with activationMaxHours outside 1-24' -Skip:(-not (Get-Command Test-Json).Parameters.ContainsKey('Schema')) {
        InModuleScope $script:moduleName {
            $Schema = Get-OERStructureSchemaJson
            Test-Json -Json '{ "version": "1.0", "directoryRoleManagementPolicies": [ { "activationMaxHours": 4 } ] }' -Schema $Schema -ErrorAction SilentlyContinue |
                Should -BeFalse
            Test-Json -Json '{ "version": "1.0", "directoryRoleManagementPolicies": [ { "role": "Reports Reader", "activationMaxHours": 25 } ] }' -Schema $Schema -ErrorAction SilentlyContinue |
                Should -BeFalse
        }
    }
}

Describe 'Get-OERStructureSchemaJson directory role assignments' {
    # directoryRoleAssignments[] holds eligible and active assignments of Microsoft Entra directory
    # roles at tenant scope, matched on role, principal and assignmentType.
    It 'declares directoryRoleAssignments at the root, requiring role, principal and assignmentType, with no scope' {
        InModuleScope $script:moduleName {
            $Schema = Get-OERStructureSchemaJson | ConvertFrom-Json
            $Schema.properties.PSObject.Properties.Name | Should -Contain 'directoryRoleAssignments'
            $Section = $Schema.properties.directoryRoleAssignments
            $Section.type | Should -BeExactly 'array'
            $Section.items.type | Should -BeExactly 'object'
            @($Section.items.required) | Should -Be @('role', 'principal', 'assignmentType')
            @($Section.items.properties.PSObject.Properties.Name) |
                Should -Be @('role', 'principal', 'principalType', 'assignmentType', 'durationDays', 'permanent', 'justification')
            @($Section.items.properties.assignmentType.enum) | Should -Be @('Eligible', 'Active')
            @($Section.items.properties.principalType.enum) | Should -Be @('User', 'Group', 'ServicePrincipal')
            $Section.items.properties.durationDays.minimum | Should -Be 1
            $Section.items.properties.durationDays.maximum | Should -Be 3650
            $Section.items.properties.permanent.type | Should -BeExactly 'boolean'
            $Section.items.properties.justification.type | Should -BeExactly 'string'
        }
    }

    It 'documents the match key, the permanent default and what -Prune never touches' {
        InModuleScope $script:moduleName {
            $Desc = (Get-OERStructureSchemaJson | ConvertFrom-Json).properties.directoryRoleAssignments.description
            $Desc | Should -Match 'matched on role, principal and assignmentType'
            $Desc | Should -Match 'without durationDays, or with permanent true, it is permanent'
            $Desc | Should -Match 'an activation is never counted or removed'
            # R9: an unresolved principal withholds its own pair, an unresolved role every pair of its kind.
            $Desc | Should -Match 'an entry whose principal cannot be resolved withholds the prune of its own pair'
            $Desc | Should -Match 'one whose role cannot be resolved withholds the prune of every pair of its assignmentType'
            # A group's own direct assignment IS a candidate: removing it ends the role for its members,
            # unless the signed-in identity is one of them; an unreadable membership withholds.
            $Desc | Should -Match "A role-assignable group's own direct assignment is a prune candidate"
            $Desc | Should -Match 'the role of every member who holds it through the group, unless the signed-in identity is a member of that group \(directly or through nesting\), in which case it is left in place and reported Skipped'
            $Desc | Should -Match "when the signed-in identity's group memberships cannot be read, every group \(or unknown-type\) candidate is withheld"
            $Desc | Should -Not -Match 'the signed-in identity included'
            # The shared service principal lookup refuses an ambiguous name rather than taking a first match.
            $Desc | Should -Match 'service principal display names are not unique, and an ambiguous name is refused at apply time \(the entry fails\)'
            $Desc | Should -Not -Match 'first match'
            $Desc | Should -Match 'Microsoft Graph only'
        }
    }

    It 'validates a time-bound eligible and a permanent active entry' -Skip:(-not (Get-Command Test-Json).Parameters.ContainsKey('Schema')) {
        InModuleScope $script:moduleName {
            $Doc = @'
{ "version": "1.0", "directoryRoleAssignments": [
  { "role": "Reports Reader", "principal": "person1@example.com", "principalType": "User", "assignmentType": "Eligible", "durationDays": 30, "justification": "Quarterly reporting" },
  { "role": "Message Center Reader", "principal": "Reporting Readers", "principalType": "Group", "assignmentType": "Active", "permanent": true } ] }
'@
            Test-Json -Json $Doc -Schema (Get-OERStructureSchemaJson) | Should -BeTrue
        }
    }

    It 'rejects an entry <Case>' -Skip:(-not (Get-Command Test-Json).Parameters.ContainsKey('Schema')) -TestCases @(
        @{ Case = 'without assignmentType'; Item = '{ "role": "Reports Reader", "principal": "person1@example.com" }' }
        @{ Case = 'with an assignmentType outside the enum'; Item = '{ "role": "Reports Reader", "principal": "person1@example.com", "assignmentType": "Pending" }' }
        @{ Case = 'with durationDays outside 1-3650'; Item = '{ "role": "Reports Reader", "principal": "person1@example.com", "assignmentType": "Eligible", "durationDays": 3651 }' }
    ) {
        InModuleScope $script:moduleName -Parameters @{ Item = $Item } {
            param($Item)
            Test-Json -Json ('{ "version": "1.0", "directoryRoleAssignments": [ ' + $Item + ' ] }') -Schema (Get-OERStructureSchemaJson) -ErrorAction SilentlyContinue |
                Should -BeFalse
        }
    }
}

Describe 'Get-OERStructureSchemaJson group previousDisplayName' {
    # R9: a group is renamed through the document by declaring its new name as displayName and its
    # current name as previousDisplayName. The groups description states the three outcomes, and the
    # property itself is a non-empty string that Get-OERInventory never exports.
    It 'states the rename rule in the groups description, keeping displayName as the match key' {
        InModuleScope $script:moduleName {
            $Schema = Get-OERStructureSchemaJson | ConvertFrom-Json
            $Schema.properties.groups.description |
                Should -BeExactly 'Entra ID groups. displayName is the match key: an existing group is matched and updated by it. To rename a group, declare its new name as displayName and its current name as previousDisplayName: when only previousDisplayName matches a live group, that group is renamed; when both names match different groups, the entry fails and the groups are never merged; when neither matches, the entry fails and nothing is created, since a rename names an existing group (declare a new group without previousDisplayName).'
        }
    }

    It 'declares previousDisplayName as a non-empty string on the group item' {
        InModuleScope $script:moduleName {
            $Prev = (Get-OERStructureSchemaJson | ConvertFrom-Json).properties.groups.items.properties.previousDisplayName
            $Prev.type | Should -BeExactly 'string'
            $Prev.minLength | Should -Be 1
            # Not "ignored once displayName matches": a different group under the old name, or an
            # ambiguous old name, fails the entry, so the description must tell the author to remove it.
            $Prev.description |
                Should -BeExactly 'The group''s current display name or object id, when displayName declares a new one. When only this value matches a live group, that group is renamed; when displayName also matches a different group, the entry fails and nothing is merged. Microsoft Graph''s name lookup can follow a rename with a delay: keep this value and wait until the new name resolves before re-applying, since a re-run while neither name resolves yet fails the entry and creates nothing, and a reference to the new name elsewhere in the same document can fail on the renaming run and is safe to re-run. Remove it once the new name resolves. Not exported by Get-OERInventory.'
            $Prev.description | Should -Not -Match 'ignored once displayName matches'
        }
    }

    It 'validates a group declaring previousDisplayName, and rejects an empty one' -Skip:(-not (Get-Command Test-Json).Parameters.ContainsKey('Schema')) {
        InModuleScope $script:moduleName {
            $Schema = Get-OERStructureSchemaJson
            $Good = '{ "version": "1.0", "groups": [ { "displayName": "role_sec_hr_emea", "previousDisplayName": "role_sec_hr" } ] }'
            $Empty = '{ "version": "1.0", "groups": [ { "displayName": "role_sec_hr_emea", "previousDisplayName": "" } ] }'
            Test-Json -Json $Good -Schema $Schema | Should -BeTrue
            Test-Json -Json $Empty -Schema $Schema -ErrorAction SilentlyContinue | Should -BeFalse
        }
    }
}

Describe 'Get-OERStructureSchemaJson refuses an empty name (A10)' {
    # The five names an entry is identified by (an access package binding's resource and role, a catalog
    # resource's name, an administrative unit scoped role's role and principal) are non-empty strings,
    # exactly as Test-OERStructureSchema refuses them. draft-07 minLength 1 cannot see a whitespace-only
    # value, which only the offline validator refuses, so the schema is the looser of the two.
    It 'declares minLength 1 on the five name properties, still as strings' {
        InModuleScope $script:moduleName {
            $Props = (Get-OERStructureSchemaJson | ConvertFrom-Json).properties
            $Named = [ordered]@{
                'scopedRoles.role'       = $Props.administrativeUnits.items.properties.scopedRoles.items.properties.role
                'scopedRoles.principal'  = $Props.administrativeUnits.items.properties.scopedRoles.items.properties.principal
                'resources.name'         = $Props.catalogs.items.properties.resources.items.properties.name
                'resourceRoles.resource' = $Props.accessPackages.items.properties.resourceRoles.items.properties.resource
                'resourceRoles.role'     = $Props.accessPackages.items.properties.resourceRoles.items.properties.role
            }
            $Named.Count | Should -Be 5
            foreach ($Key in $Named.Keys) {
                $Named[$Key] | Should -Not -BeNullOrEmpty -Because "the property $Key must exist for its minLength to be read"
                $Named[$Key].type | Should -BeExactly 'string'
                $Named[$Key].minLength | Should -Be 1 -Because "$Key is refused when empty"
            }
        }
    }

    It 'refuses an empty <Label> and accepts a named one' -Skip:(-not (Get-Command Test-Json).Parameters.ContainsKey('Schema')) -ForEach @(
        @{ Label = 'scoped role role'; Section = 'administrativeUnits'; Good = '{ "displayName": "AU-One", "scopedRoles": [ { "role": "User Administrator", "principal": "p-1" } ] }'; Empty = '{ "displayName": "AU-One", "scopedRoles": [ { "role": "", "principal": "p-1" } ] }' }
        @{ Label = 'scoped role principal'; Section = 'administrativeUnits'; Good = '{ "displayName": "AU-One", "scopedRoles": [ { "role": "User Administrator", "principal": "p-1" } ] }'; Empty = '{ "displayName": "AU-One", "scopedRoles": [ { "role": "User Administrator", "principal": "" } ] }' }
        @{ Label = 'catalog resource name'; Section = 'catalogs'; Good = '{ "displayName": "CAT-One", "resources": [ { "name": "role_sec_x", "type": "Group" } ] }'; Empty = '{ "displayName": "CAT-One", "resources": [ { "name": "", "type": "Group" } ] }' }
        @{ Label = 'binding resource'; Section = 'accessPackages'; Good = '{ "displayName": "AP-One", "catalog": "CAT-One", "resourceRoles": [ { "resource": "role_sec_x", "role": "Member" } ] }'; Empty = '{ "displayName": "AP-One", "catalog": "CAT-One", "resourceRoles": [ { "resource": "", "role": "Member" } ] }' }
        @{ Label = 'binding role'; Section = 'accessPackages'; Good = '{ "displayName": "AP-One", "catalog": "CAT-One", "resourceRoles": [ { "resource": "role_sec_x", "role": "Member" } ] }'; Empty = '{ "displayName": "AP-One", "catalog": "CAT-One", "resourceRoles": [ { "resource": "role_sec_x", "role": "" } ] }' }
    ) {
        InModuleScope $script:moduleName -Parameters @{ Section = $Section; Good = $Good; Empty = $Empty } {
            param($Section, $Good, $Empty)
            $Schema = Get-OERStructureSchemaJson
            Test-Json -Json ("{ `"version`": `"1.0`", `"$Section`": [ $Good ] }") -Schema $Schema | Should -BeTrue
            Test-Json -Json ("{ `"version`": `"1.0`", `"$Section`": [ $Empty ] }") -Schema $Schema -ErrorAction SilentlyContinue | Should -BeFalse
        }
    }
}

Describe 'Get-OERStructureSchemaJson tenantId (BL-88, A14)' {
    It 'declares tenantId as a canonical-GUID string whose description says never to invent one' {
        InModuleScope $script:moduleName {
            $Obj = Get-OERStructureSchemaJson | ConvertFrom-Json
            $Obj.properties.PSObject.Properties.Name | Should -Contain 'tenantId'
            $Obj.properties.tenantId.type | Should -BeExactly 'string'
            $Obj.properties.tenantId.pattern | Should -BeExactly '^[0-9a-fA-F]{8}-([0-9a-fA-F]{4}-){3}[0-9a-fA-F]{12}$'
            $Obj.properties.tenantId.description | Should -Not -BeNullOrEmpty
            $Obj.properties.tenantId.description | Should -Match 'never invent'
        }
    }

    It 'does not make tenantId required' {
        InModuleScope $script:moduleName {
            $Obj = Get-OERStructureSchemaJson | ConvertFrom-Json
            $Obj.required | Should -Not -Contain 'tenantId'
        }
    }

    It 'validates a document carrying a GUID tenantId' -Skip:(-not (Get-Command Test-Json).Parameters.ContainsKey('Schema')) {
        InModuleScope $script:moduleName {
            $Schema = Get-OERStructureSchemaJson
            $Json = '{ "version": "1.0", "tenantId": "44444444-4444-4444-4444-444444444444" }'
            Test-Json -Json $Json -Schema $Schema -ErrorAction SilentlyContinue | Should -BeTrue
        }
    }

    It 'rejects a tenantId that is not a canonical GUID' -Skip:(-not (Get-Command Test-Json).Parameters.ContainsKey('Schema')) {
        InModuleScope $script:moduleName {
            $Schema = Get-OERStructureSchemaJson
            $Json = '{ "version": "1.0", "tenantId": "contoso" }'
            Test-Json -Json $Json -Schema $Schema -ErrorAction SilentlyContinue | Should -BeFalse
        }
    }

    It 'rejects an explicit null tenantId' -Skip:(-not (Get-Command Test-Json).Parameters.ContainsKey('Schema')) {
        InModuleScope $script:moduleName {
            $Schema = Get-OERStructureSchemaJson
            $Json = '{ "version": "1.0", "tenantId": null }'
            Test-Json -Json $Json -Schema $Schema -ErrorAction SilentlyContinue | Should -BeFalse
        }
    }
}

Describe 'Get-OERStructureSchemaJson renames, mail aliases and scope spelling (BL-128, BL-132, BL-141)' {
    # Sprint 11 step 3. The offline validator refuses a mailNickname Microsoft Graph refuses, and a scope
    # spelled with a dot segment, a '%', a '\', a '?', a '#' or white space where a resource name cannot
    # hold it (decision A13 as narrowed in round 1); the schema says so in its descriptions and bounds the
    # alias length. It carries no regular-expression pattern for the characters, which the validator
    # alone enforces. (Step 3 also refused previousDisplayName on an assignment policy and an access
    # review; every kind accepts it since step 4 and step 4b, the Describe below.)
    It 'bounds a group mailNickname to 1 to 64 characters and declares no pattern' -Skip:(-not (Get-Command Test-Json).Parameters.ContainsKey('Schema')) {
        InModuleScope $script:moduleName {
            $Schema = Get-OERStructureSchemaJson
            $Nick = ($Schema | ConvertFrom-Json).properties.groups.items.properties.mailNickname
            $Nick.type | Should -BeExactly 'string'
            $Nick.minLength | Should -Be 1
            $Nick.maxLength | Should -Be 64
            $Nick.PSObject.Properties.Name | Should -Not -Contain 'pattern'
            $At64 = '{ "version": "1.0", "groups": [ { "displayName": "g", "mailNickname": "' + ('a' * 64) + '" } ] }'
            $At65 = '{ "version": "1.0", "groups": [ { "displayName": "g", "mailNickname": "' + ('a' * 65) + '" } ] }'
            $Empty = '{ "version": "1.0", "groups": [ { "displayName": "g", "mailNickname": "" } ] }'
            Test-Json -Json $At64 -Schema $Schema | Should -BeTrue
            Test-Json -Json $At65 -Schema $Schema -ErrorAction SilentlyContinue | Should -BeFalse
            Test-Json -Json $Empty -Schema $Schema -ErrorAction SilentlyContinue | Should -BeFalse
        }
    }

    It 'keeps what Microsoft Graph was measured to refuse apart from what only the validator refuses, and says the alias is not derived again on a rename' {
        InModuleScope $script:moduleName {
            $Description = (Get-OERStructureSchemaJson | ConvertFrom-Json).properties.groups.items.properties.mailNickname.description
            $Description | Should -Match ([regex]::Escape('Microsoft Graph was measured to refuse the empty string, more than 64 characters, a space, a tab and each of @ ( ) \ [ ] " ; : < > , and Test-OERStructure refuses those as well as any other white space or control character, which was not measured.'))
            $Description | Should -Not -Match ([regex]::Escape('since Microsoft Graph refuses each of them'))
            $Description | Should -Match ([regex]::Escape('The alias is not derived again on a rename: a renamed group keeps its alias unless the document declares one'))
            $Description | Should -Match 'DerivedMailNicknameInvalid'
        }
    }

    It 'says in no section that renaming is not supported or that previousDisplayName is refused (every kind can be renamed since step 4b)' {
        InModuleScope $script:moduleName {
            $Props = (Get-OERStructureSchemaJson | ConvertFrom-Json).properties
            $Can = [ordered]@{
                groups              = $Props.groups.description
                administrativeUnits = $Props.administrativeUnits.description
                catalogs            = $Props.catalogs.description
                accessPackages      = $Props.accessPackages.description
                assignmentPolicies  = $Props.accessPackages.items.properties.assignmentPolicies.description
                accessReviews       = $Props.accessReviews.description
            }
            $Can.Count | Should -Be 6
            foreach ($Name in $Can.Keys) {
                $Can[$Name] | Should -Not -BeNullOrEmpty -Because "the $Name description must exist to be read"
                $Can[$Name] | Should -Not -Match ([regex]::Escape('Renaming is not supported yet')) -Because "the $Name section can be renamed"
                $Can[$Name] | Should -Not -Match ([regex]::Escape('Renaming through the document is not possible')) -Because "the $Name section can be renamed"
                $Can[$Name] | Should -Not -Match 'refuses previousDisplayName' -Because "the $Name section accepts previousDisplayName"
                $Can[$Name] | Should -Not -Match 'beside the old one' -Because "the $Name section no longer describes a refused duplicate"
            }
        }
    }

    It 'states the refused scope spellings in the roleAssignments and roleManagementPolicies scope descriptions' {
        InModuleScope $script:moduleName {
            $Props = (Get-OERStructureSchemaJson | ConvertFrom-Json).properties
            $Scopes = [ordered]@{
                roleAssignments        = $Props.roleAssignments.items.properties.scope.description
                roleManagementPolicies = $Props.roleManagementPolicies.items.properties.scope.description
            }
            foreach ($Name in $Scopes.Keys) {
                $Scopes[$Name] | Should -Match ([regex]::Escape("without a trailing or doubled '/', a '.' or '..' segment, a '%', a '\', a '?' or a '#', white space at the start or end of the scope or of a segment, white space other than a space, and a control character: Test-OERStructure refuses each of them as an Error.")) -Because "the $Name scope names the spellings"
                $Scopes[$Name] | Should -Match ([regex]::Escape('The mg:, sub: and subscription: forms are resolved by a lookup and never sent as written, so only the rule about ''/'' applies to them.')) -Because "the $Name scope names the exempt forms"
                # Decision A13 as narrowed on 2026-10-14: a space between other characters of a segment is
                # accepted, as a legal Azure resource name can hold one, and the limit that remains is stated.
                $Scopes[$Name] | Should -Match ([regex]::Escape('One or more spaces between other characters of a segment, as an Azure resource name can hold, are accepted.')) -Because "the $Name scope says what is accepted"
                $Scopes[$Name] | Should -Match ([regex]::Escape('a resource whose name holds one of these cannot be declared.')) -Because "the $Name scope states the limit"
                $Scopes[$Name] | Should -Not -Match ([regex]::Escape('white space is refused as a whole')) -Because "the $Name scope no longer refuses every space"
                $Scopes[$Name] | Should -Not -Match ([regex]::Escape('without white space')) -Because "the $Name scope no longer refuses every space"
            }
        }
    }
}

Describe 'Get-OERStructureSchemaJson renames of administrative units, catalogs and access packages (BL-128, A5)' {
    # Sprint 11 step 4: an administrative unit, a catalog and an access package are renamed through the
    # document like a group, by declaring the new name as displayName and the current name (or object id)
    # as previousDisplayName. The item schemas declare the key, the section descriptions say how to
    # declare a rename, and the property descriptions say what the apply engine does with it. Step 4b
    # adds an assignment policy (inside its package) and an access review; they are nested or differ in
    # wording, so they have tests of their own below.
    BeforeDiscovery {
        $script:SchemaRenameCase = @(
            @{
                Section             = 'administrativeUnits'
                Good                = '{ "displayName": "AU-New", "previousDisplayName": "AU-Old" }'
                Empty               = '{ "displayName": "AU-New", "previousDisplayName": "" }'
                SectionDescription  = 'Administrative units. displayName is the match key: an existing unit is matched and updated by it. To rename a unit, declare its new name as displayName and its current name (or object id) as previousDisplayName.'
                PropertyDescription = 'The administrative unit''s current display name or object id, when displayName declares a new one. When only this value matches a live administrative unit, that administrative unit is renamed in place; when displayName also matches a different administrative unit, the entry fails and nothing is merged; when neither matches, the entry fails and nothing is created. An object id is checked with one read. Microsoft Graph''s name lookup can follow a rename with a delay: keep this value until the new name resolves, then remove it. Not exported by Get-OERInventory.'
            }
            @{
                Section             = 'catalogs'
                Good                = '{ "displayName": "CAT-New", "previousDisplayName": "CAT-Old" }'
                Empty               = '{ "displayName": "CAT-New", "previousDisplayName": "" }'
                SectionDescription  = 'Entitlement Management catalogs. displayName is the match key: an existing catalog is matched and updated by it. To rename a catalog, declare its new name as displayName and its current name (or object id) as previousDisplayName.'
                PropertyDescription = 'The catalog''s current display name or object id, when displayName declares a new one. When only this value matches a live catalog, that catalog is renamed in place; when displayName also matches a different catalog, the entry fails and nothing is merged; when neither matches, the entry fails and nothing is created. An object id is checked with one read. Microsoft Graph''s name lookup can follow a rename with a delay: keep this value until the new name resolves, then remove it. Not exported by Get-OERInventory.'
            }
            @{
                Section             = 'accessPackages'
                Good                = '{ "displayName": "AP-New", "catalog": "CAT-One", "previousDisplayName": "AP-Old" }'
                Empty               = '{ "displayName": "AP-New", "catalog": "CAT-One", "previousDisplayName": "" }'
                SectionDescription  = 'Entitlement Management access packages. displayName is the match key within the declared catalog (names are unique per catalog, not tenant-wide): an existing package is matched and updated by it. To rename a package, declare its new name as displayName and its current name (or object id) as previousDisplayName, within its catalog; a package whose catalog is renamed in the same document names the catalog''s new name. There is no top-level Extra reporting for this section.'
                PropertyDescription = 'The access package''s current display name or object id, when displayName declares a new one. When only this value matches a live access package in the declared catalog, that access package is renamed in place; when displayName also matches a different access package in the declared catalog, the entry fails and nothing is merged; when neither matches, the entry fails and nothing is created. An object id matches only a package of the declared catalog. Microsoft Graph''s name lookup can follow a rename with a delay: keep this value until the new name resolves, then remove it. Not exported by Get-OERInventory.'
            }
        )
    }

    It 'declares previousDisplayName on the <Section> item as a non-empty string and describes what the engine does with it' -ForEach $script:SchemaRenameCase {
        InModuleScope $script:moduleName -Parameters @{ Section = $Section; PropertyDescription = $PropertyDescription } {
            param($Section, $PropertyDescription)
            $Prev = (Get-OERStructureSchemaJson | ConvertFrom-Json).properties.$Section.items.properties.previousDisplayName
            $Prev | Should -Not -BeNullOrEmpty
            $Prev.type | Should -BeExactly 'string'
            $Prev.minLength | Should -Be 1
            $Prev.description | Should -BeExactly $PropertyDescription
        }
    }

    It 'tells in the <Section> description how to declare a rename, and no longer says it is impossible or unsupported' -ForEach $script:SchemaRenameCase {
        InModuleScope $script:moduleName -Parameters @{ Section = $Section; SectionDescription = $SectionDescription } {
            param($Section, $SectionDescription)
            $Description = (Get-OERStructureSchemaJson | ConvertFrom-Json).properties.$Section.description
            $Description | Should -BeExactly $SectionDescription
            $Description | Should -Not -Match 'Renaming is not supported yet'
            $Description | Should -Not -Match 'Renaming through the document is not possible'
        }
    }

    It 'declares previousDisplayName on the assignmentPolicies item as a non-empty string and describes what the engine does with it (step 4b)' {
        InModuleScope $script:moduleName {
            $Policies = (Get-OERStructureSchemaJson | ConvertFrom-Json).properties.accessPackages.items.properties.assignmentPolicies
            $Prev = $Policies.items.properties.previousDisplayName
            $Prev | Should -Not -BeNullOrEmpty
            $Prev.type | Should -BeExactly 'string'
            $Prev.minLength | Should -Be 1
            $Prev.description | Should -BeExactly 'The assignment policy''s current display name or object id, when displayName declares a new one. When only this value matches a live assignment policy of this access package, that policy is renamed in place; when displayName also matches a different policy of the access package, the entry fails and nothing is merged; when neither matches, the entry fails and nothing is created. An object id matches only a policy of this access package. A name lookup can follow a rename with a delay: keep this value until the new name resolves, then remove it. An access review that names the policy must name it by its new name or object id once the rename is applied. Not exported by Get-OERInventory.'
            # The policy is renamed within its package, and the section description says how.
            $Policies.description | Should -BeExactly 'Assignment policies of the package. displayName is the match key within the package: an existing policy is matched and updated by it. To rename a policy, declare its new name as displayName and its current name (or object id) as previousDisplayName, within its package; an access review that names the policy must name it by its new name (or object id) once the rename is applied.'
        }
    }

    It 'declares previousDisplayName on the accessReviews item as a non-empty string and describes the tenant-wide lookup and the target check (step 4b)' {
        InModuleScope $script:moduleName {
            $Reviews = (Get-OERStructureSchemaJson | ConvertFrom-Json).properties.accessReviews
            $Prev = $Reviews.items.properties.previousDisplayName
            $Prev | Should -Not -BeNullOrEmpty
            $Prev.type | Should -BeExactly 'string'
            $Prev.minLength | Should -Be 1
            $Prev.description | Should -BeExactly 'The access review''s current display name or object id, when displayName declares a new one. The name is looked up tenant-wide, as displayName is. When only this value matches a live access review, that review is renamed in place; when displayName also matches a different review, the entry fails and nothing is merged; when neither matches, the entry fails and nothing is created. The review found under either name must review the declared accessPackage and assignmentPolicy, or the entry fails and nothing is written. A name lookup can follow a rename with a delay: keep this value until the new name resolves, then remove it. Not exported by Get-OERInventory.'
            # The section description keeps what it said about the update and the match key, and adds the rename.
            $Reviews.description | Should -Match ([regex]::Escape('displayName is the match key: an existing review is updated in place only when it reviews the declared accessPackage and assignmentPolicy; otherwise the entry fails and nothing is written.'))
            $Reviews.description | Should -Match ([regex]::Escape('To rename a review, declare its new name as displayName and its current name (or object id) as previousDisplayName: the name is looked up tenant-wide, as displayName is, and the review found under either name must review the declared accessPackage and assignmentPolicy, or the entry fails and nothing is written. When the same document renames the access package or the policy, name it by its new name (or object id) here.'))
        }
    }

    It 'declares previousDisplayName on the group, policy and review items alike' {
        InModuleScope $script:moduleName {
            $Props = (Get-OERStructureSchemaJson | ConvertFrom-Json).properties
            $Props.groups.items.properties.PSObject.Properties.Name | Should -Contain 'previousDisplayName'
            $Props.accessPackages.items.properties.assignmentPolicies.items.properties.PSObject.Properties.Name | Should -Contain 'previousDisplayName'
            $Props.accessReviews.items.properties.PSObject.Properties.Name | Should -Contain 'previousDisplayName'
            # Declaring it never makes it required: a policy and a review without a rename stay valid.
            $Props.accessPackages.items.properties.assignmentPolicies.items.required | Should -Not -Contain 'previousDisplayName'
            $Props.accessReviews.items.required | Should -Not -Contain 'previousDisplayName'
        }
    }

    It 'validates a policy and a review declaring previousDisplayName, and rejects an empty one' -Skip:(-not (Get-Command Test-Json).Parameters.ContainsKey('Schema')) {
        InModuleScope $script:moduleName {
            $Schema = Get-OERStructureSchemaJson
            $Policy = '"accessPackages": [ { "displayName": "AP-One", "catalog": "CAT-One", "assignmentPolicies": [ { "displayName": "POL-New", "previousDisplayName": "%PREV%" } ] } ]'
            $Review = '"accessReviews": [ { "displayName": "REV-New", "previousDisplayName": "%PREV%", "accessPackage": "AP-One", "assignmentPolicy": "POL-New" } ]'
            foreach ($Section in @($Policy, $Review)) {
                Test-Json -Json ('{ "version": "1.0", ' + $Section.Replace('%PREV%', 'Old') + ' }') -Schema $Schema | Should -BeTrue
                Test-Json -Json ('{ "version": "1.0", ' + $Section.Replace('%PREV%', '') + ' }') -Schema $Schema -ErrorAction SilentlyContinue | Should -BeFalse
                Test-Json -Json ('{ "version": "1.0", ' + $Section.Replace('"%PREV%"', '5') + ' }') -Schema $Schema -ErrorAction SilentlyContinue | Should -BeFalse
            }
        }
    }

    It 'validates an item of <Section> declaring previousDisplayName, and rejects an empty one' -Skip:(-not (Get-Command Test-Json).Parameters.ContainsKey('Schema')) -ForEach $script:SchemaRenameCase {
        InModuleScope $script:moduleName -Parameters @{ Section = $Section; Good = $Good; Empty = $Empty } {
            param($Section, $Good, $Empty)
            $Schema = Get-OERStructureSchemaJson
            Test-Json -Json ("{ `"version`": `"1.0`", `"$Section`": [ $Good ] }") -Schema $Schema | Should -BeTrue
            Test-Json -Json ("{ `"version`": `"1.0`", `"$Section`": [ $Empty ] }") -Schema $Schema -ErrorAction SilentlyContinue | Should -BeFalse
        }
    }

    It 'validates one document that renames a unit, a catalog and an access package together' -Skip:(-not (Get-Command Test-Json).Parameters.ContainsKey('Schema')) {
        InModuleScope $script:moduleName {
            $Json = '{ "version": "1.0", "administrativeUnits": [ { "displayName": "AU-New", "previousDisplayName": "AU-Old" } ], "catalogs": [ { "displayName": "CAT-New", "previousDisplayName": "CAT-Old" } ], "accessPackages": [ { "displayName": "AP-New", "catalog": "CAT-New", "previousDisplayName": "AP-Old" } ] }'
            Test-Json -Json $Json -Schema (Get-OERStructureSchemaJson) | Should -BeTrue
        }
    }
}
