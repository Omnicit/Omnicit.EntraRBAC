BeforeAll {
    $script:moduleName = 'Omnicit.EntraRBAC'
    Get-Module $script:moduleName | Remove-Module -Force -ErrorAction SilentlyContinue
    Import-Module $script:moduleName -Force -ErrorAction Stop
}

Describe 'Test-OERStructureSchema' {
    It 'a minimal valid document is Valid with no errors' {
        InModuleScope $script:moduleName {
            $Doc = '{ "version": "1.0" }' | ConvertFrom-Json
            $V = Test-OERStructureSchema -Document $Doc
            $V.PSObject.TypeNames[0] | Should -Be 'Omnicit.EntraRBAC.StructureValidation'
            $V.Valid | Should -BeTrue
            @($V.Errors).Count | Should -Be 0
        }
    }

    It 'flags a missing version with Path version' {
        InModuleScope $script:moduleName {
            $Doc = '{ "groups": [] }' | ConvertFrom-Json
            $V = Test-OERStructureSchema -Document $Doc
            $V.Valid | Should -BeFalse
            @($V.Errors | Where-Object Path -eq 'version').Count | Should -BeGreaterThan 0
        }
    }

    It 'flags an empty string version with Path version' {
        InModuleScope $script:moduleName {
            $Doc = '{ "version": "" }' | ConvertFrom-Json
            $V = Test-OERStructureSchema -Document $Doc
            $V.Valid | Should -BeFalse
            @($V.Errors | Where-Object Path -eq 'version').Count | Should -BeGreaterThan 0
        }
    }

    It 'flags an unknown top-level key' {
        InModuleScope $script:moduleName {
            $Doc = '{ "version": "1.0", "grops": [] }' | ConvertFrom-Json
            $V = Test-OERStructureSchema -Document $Doc
            $V.Valid | Should -BeFalse
            @($V.Errors | Where-Object Path -eq 'grops').Count | Should -BeGreaterThan 0
        }
    }

    It 'allows tenantAlias as a known top-level key' {
        InModuleScope $script:moduleName {
            $Doc = '{ "version": "1.0", "tenantAlias": "contoso" }' | ConvertFrom-Json
            (Test-OERStructureSchema -Document $Doc).Valid | Should -BeTrue
        }
    }

    It 'flags a section that is not an array' {
        InModuleScope $script:moduleName {
            $Doc = '{ "version": "1.0", "groups": { "displayName": "g" } }' | ConvertFrom-Json
            (Test-OERStructureSchema -Document $Doc).Valid | Should -BeFalse
        }
    }

    It 'flags a group with both displayName and template at Path groups[0]' {
        InModuleScope $script:moduleName {
            $Doc = '{ "version": "1.0", "groups": [ { "displayName": "g", "template": "t" } ] }' | ConvertFrom-Json
            $V = Test-OERStructureSchema -Document $Doc
            @($V.Errors | Where-Object Path -eq 'groups[0]').Count | Should -BeGreaterThan 0
        }
    }

    It 'flags a group with neither displayName nor template' {
        InModuleScope $script:moduleName {
            $Doc = '{ "version": "1.0", "groups": [ { "description": "x" } ] }' | ConvertFrom-Json
            (Test-OERStructureSchema -Document $Doc).Valid | Should -BeFalse
        }
    }

    It 'accepts a group with only displayName' {
        InModuleScope $script:moduleName {
            $Doc = '{ "version": "1.0", "groups": [ { "displayName": "MyGroup" } ] }' | ConvertFrom-Json
            (Test-OERStructureSchema -Document $Doc).Valid | Should -BeTrue
        }
    }

    It 'accepts a group with template + tokens' {
        InModuleScope $script:moduleName {
            $Doc = '{ "version": "1.0", "groups": [ { "template": "role_{a}", "tokens": { "a": "x" } } ] }' | ConvertFrom-Json
            (Test-OERStructureSchema -Document $Doc).Valid | Should -BeTrue
        }
    }

    It 'flags a group with template but no tokens' {
        InModuleScope $script:moduleName {
            $Doc = '{ "version": "1.0", "groups": [ { "template": "role_{a}" } ] }' | ConvertFrom-Json
            (Test-OERStructureSchema -Document $Doc).Valid | Should -BeFalse
        }
    }

    It 'flags group members that is not an array' {
        InModuleScope $script:moduleName {
            $Doc = '{ "version": "1.0", "groups": [ { "displayName": "g", "members": "notanarray" } ] }' | ConvertFrom-Json
            (Test-OERStructureSchema -Document $Doc).Valid | Should -BeFalse
        }
    }

    It 'flags group eligibility that is not an array' {
        InModuleScope $script:moduleName {
            $Doc = '{ "version": "1.0", "groups": [ { "displayName": "g", "eligibility": "notanarray" } ] }' | ConvertFrom-Json
            (Test-OERStructureSchema -Document $Doc).Valid | Should -BeFalse
        }
    }

    It 'flags group owners that is not an array' {
        InModuleScope $script:moduleName {
            $Doc = '{ "version": "1.0", "groups": [ { "displayName": "g", "owners": "notanarray" } ] }' | ConvertFrom-Json
            (Test-OERStructureSchema -Document $Doc).Valid | Should -BeFalse
        }
    }

    It 'accepts a group declaring owners as a string array' {
        InModuleScope $script:moduleName {
            $Doc = '{ "version": "1.0", "groups": [ { "displayName": "g", "owners": [ "person19@example.com" ] } ] }' | ConvertFrom-Json
            (Test-OERStructureSchema -Document $Doc).Valid | Should -BeTrue
        }
    }

    It 'accepts a group declaring mailNickname and administrativeUnit' {
        InModuleScope $script:moduleName {
            $Doc = [PSCustomObject]@{
                version = '1.0'
                groups  = @([PSCustomObject]@{
                    displayName = 'role_sec_core'; mailNickname = 'rolesec-core'; administrativeUnit = 'au_hr'
                })
            }
            (Test-OERStructureSchema -Document $Doc).Valid | Should -BeTrue
        }
    }

    It 'accepts a group declaring a valid membershipRuleProcessingState' {
        InModuleScope $script:moduleName {
            $Doc = '{ "version": "1.0", "groups": [ { "displayName": "g", "dynamic": true, "membershipRule": "x", "membershipRuleProcessingState": "Paused" } ] }' | ConvertFrom-Json
            (Test-OERStructureSchema -Document $Doc).Valid | Should -BeTrue
        }
    }

    It 'rejects a group declaring an out-of-enum membershipRuleProcessingState' {
        InModuleScope $script:moduleName {
            $Doc = '{ "version": "1.0", "groups": [ { "displayName": "g", "membershipRuleProcessingState": "Disabled" } ] }' | ConvertFrom-Json
            (Test-OERStructureSchema -Document $Doc).Valid | Should -BeFalse
        }
    }

    It 'rejects a non-string mailNickname' {
        InModuleScope $script:moduleName {
            $Doc = [PSCustomObject]@{
                version = '1.0'
                groups  = @([PSCustomObject]@{ displayName = 'role_sec_core'; mailNickname = @(1, 2) })
            }
            $Result = Test-OERStructureSchema -Document $Doc
            $Result.Valid | Should -BeFalse
            @($Result.Errors).Path | Should -Contain 'groups[0].mailNickname'
        }
    }

    It 'flags eligibility durationDays out of range' {
        InModuleScope $script:moduleName {
            $Doc = '{ "version": "1.0", "groups": [ { "displayName": "g", "eligibility": [ { "principal": "u", "durationDays": 99999 } ] } ] }' | ConvertFrom-Json
            (Test-OERStructureSchema -Document $Doc).Valid | Should -BeFalse
        }
    }

    It 'flags eligibility durationDays of zero' {
        InModuleScope $script:moduleName {
            $Doc = '{ "version": "1.0", "groups": [ { "displayName": "g", "eligibility": [ { "principal": "u", "durationDays": 0 } ] } ] }' | ConvertFrom-Json
            (Test-OERStructureSchema -Document $Doc).Valid | Should -BeFalse
        }
    }

    It 'accepts eligibility durationDays at boundary values 1 and 3650' {
        InModuleScope $script:moduleName {
            $Doc = '{ "version": "1.0", "groups": [ { "displayName": "g", "eligibility": [ { "principal": "u1", "durationDays": 1 }, { "principal": "u2", "durationDays": 3650 } ] } ] }' | ConvertFrom-Json
            (Test-OERStructureSchema -Document $Doc).Valid | Should -BeTrue
        }
    }

    It 'flags missing eligibility principal at the right path' {
        InModuleScope $script:moduleName {
            $Doc = '{ "version": "1.0", "groups": [ { "displayName": "g", "eligibility": [ { "durationDays": 30 } ] } ] }' | ConvertFrom-Json
            $V = Test-OERStructureSchema -Document $Doc
            @($V.Errors | Where-Object Path -eq 'groups[0].eligibility[0].principal').Count | Should -BeGreaterThan 0
        }
    }

    It 'flags pimPolicy activationMaxHours out of range' {
        InModuleScope $script:moduleName {
            $Doc = '{ "version": "1.0", "groups": [ { "displayName": "g", "pimPolicy": { "activationMaxHours": 99 } } ] }' | ConvertFrom-Json
            (Test-OERStructureSchema -Document $Doc).Valid | Should -BeFalse
        }
    }

    It 'flags pimPolicy activationMaxHours of zero' {
        InModuleScope $script:moduleName {
            $Doc = '{ "version": "1.0", "groups": [ { "displayName": "g", "pimPolicy": { "activationMaxHours": 0 } } ] }' | ConvertFrom-Json
            (Test-OERStructureSchema -Document $Doc).Valid | Should -BeFalse
        }
    }

    It 'accepts pimPolicy activationMaxHours at boundary values 1 and 24' {
        InModuleScope $script:moduleName {
            $Doc = '{ "version": "1.0", "groups": [ { "displayName": "g", "pimPolicy": { "activationMaxHours": 1 } }, { "displayName": "g2", "pimPolicy": { "activationMaxHours": 24 } } ] }' | ConvertFrom-Json
            (Test-OERStructureSchema -Document $Doc).Valid | Should -BeTrue
        }
    }

    It 'flags an administrative unit missing displayName' {
        InModuleScope $script:moduleName {
            $Doc = '{ "version": "1.0", "administrativeUnits": [ { "description": "x" } ] }' | ConvertFrom-Json
            (Test-OERStructureSchema -Document $Doc).Valid | Should -BeFalse
        }
    }

    It 'accepts a valid administrative unit' {
        InModuleScope $script:moduleName {
            $Doc = '{ "version": "1.0", "administrativeUnits": [ { "displayName": "AU-Corp" } ] }' | ConvertFrom-Json
            (Test-OERStructureSchema -Document $Doc).Valid | Should -BeTrue
        }
    }

    It 'flags a scoped role missing principal' {
        InModuleScope $script:moduleName {
            $Doc = '{ "version": "1.0", "administrativeUnits": [ { "displayName": "au", "scopedRoles": [ { "role": "User Administrator" } ] } ] }' | ConvertFrom-Json
            (Test-OERStructureSchema -Document $Doc).Valid | Should -BeFalse
        }
    }

    It 'flags a scoped role missing role' {
        InModuleScope $script:moduleName {
            $Doc = '{ "version": "1.0", "administrativeUnits": [ { "displayName": "au", "scopedRoles": [ { "principal": "person21@example.com" } ] } ] }' | ConvertFrom-Json
            (Test-OERStructureSchema -Document $Doc).Valid | Should -BeFalse
        }
    }

    It 'flags a catalog missing displayName' {
        InModuleScope $script:moduleName {
            $Doc = '{ "version": "1.0", "catalogs": [ { "description": "x" } ] }' | ConvertFrom-Json
            (Test-OERStructureSchema -Document $Doc).Valid | Should -BeFalse
        }
    }

    It 'flags an invalid catalog resource type' {
        InModuleScope $script:moduleName {
            $Doc = '{ "version": "1.0", "catalogs": [ { "displayName": "c", "resources": [ { "type": "Widget", "name": "x" } ] } ] }' | ConvertFrom-Json
            (Test-OERStructureSchema -Document $Doc).Valid | Should -BeFalse
        }
    }

    It 'accepts valid catalog resource types Group Application SharePointSite' {
        InModuleScope $script:moduleName {
            $Doc = '{ "version": "1.0", "catalogs": [ { "displayName": "c", "resources": [ { "type": "Group", "name": "x" }, { "type": "Application", "name": "y" }, { "type": "SharePointSite", "name": "z" } ] } ] }' | ConvertFrom-Json
            (Test-OERStructureSchema -Document $Doc).Valid | Should -BeTrue
        }
    }

    It 'flags a catalog resource missing name' {
        InModuleScope $script:moduleName {
            $Doc = '{ "version": "1.0", "catalogs": [ { "displayName": "c", "resources": [ { "type": "Group" } ] } ] }' | ConvertFrom-Json
            (Test-OERStructureSchema -Document $Doc).Valid | Should -BeFalse
        }
    }

    It 'flags an access package missing displayName' {
        InModuleScope $script:moduleName {
            $Doc = '{ "version": "1.0", "accessPackages": [ { "catalog": "CAT-X" } ] }' | ConvertFrom-Json
            (Test-OERStructureSchema -Document $Doc).Valid | Should -BeFalse
        }
    }

    It 'flags an access package missing catalog' {
        InModuleScope $script:moduleName {
            $Doc = '{ "version": "1.0", "accessPackages": [ { "displayName": "ap" } ] }' | ConvertFrom-Json
            (Test-OERStructureSchema -Document $Doc).Valid | Should -BeFalse
        }
    }

    It 'flags an access package resourceRole missing resource' {
        InModuleScope $script:moduleName {
            $Doc = '{ "version": "1.0", "accessPackages": [ { "displayName": "ap", "catalog": "CAT-X", "resourceRoles": [ { "role": "Member" } ] } ] }' | ConvertFrom-Json
            (Test-OERStructureSchema -Document $Doc).Valid | Should -BeFalse
        }
    }

    It 'flags an access package resourceRole missing role' {
        InModuleScope $script:moduleName {
            $Doc = '{ "version": "1.0", "accessPackages": [ { "displayName": "ap", "catalog": "CAT-X", "resourceRoles": [ { "resource": "MyGroup" } ] } ] }' | ConvertFrom-Json
            (Test-OERStructureSchema -Document $Doc).Valid | Should -BeFalse
        }
    }

    It 'flags an assignment policy missing displayName' {
        InModuleScope $script:moduleName {
            $Doc = '{ "version": "1.0", "accessPackages": [ { "displayName": "ap", "catalog": "CAT-X", "assignmentPolicies": [ { "durationInDays": 30 } ] } ] }' | ConvertFrom-Json
            (Test-OERStructureSchema -Document $Doc).Valid | Should -BeFalse
        }
    }

    It 'flags an invalid accessReview recurrence' {
        InModuleScope $script:moduleName {
            $Doc = '{ "version": "1.0", "accessReviews": [ { "displayName": "r", "accessPackage": "ap", "assignmentPolicy": "p", "recurrence": "Hourly" } ] }' | ConvertFrom-Json
            (Test-OERStructureSchema -Document $Doc).Valid | Should -BeFalse
        }
    }

    It 'accepts a case-insensitive recurrence value' {
        InModuleScope $script:moduleName {
            $Doc = '{ "version": "1.0", "accessReviews": [ { "displayName": "r", "accessPackage": "ap", "assignmentPolicy": "p", "recurrence": "quarterly" } ] }' | ConvertFrom-Json
            (Test-OERStructureSchema -Document $Doc).Valid | Should -BeTrue
        }
    }

    It 'accepts all valid recurrence values' {
        InModuleScope $script:moduleName {
            foreach ($Rec in @('OneTime', 'Weekly', 'Monthly', 'Quarterly', 'Annually')) {
                $Doc = ('{ "version": "1.0", "accessReviews": [ { "displayName": "r", "accessPackage": "ap", "assignmentPolicy": "p", "recurrence": "' + $Rec + '" } ] }') | ConvertFrom-Json
                (Test-OERStructureSchema -Document $Doc).Valid | Should -BeTrue -Because "recurrence '$Rec' is valid"
            }
        }
    }

    It 'flags an accessReview missing displayName' {
        InModuleScope $script:moduleName {
            $Doc = '{ "version": "1.0", "accessReviews": [ { "accessPackage": "ap", "assignmentPolicy": "p" } ] }' | ConvertFrom-Json
            (Test-OERStructureSchema -Document $Doc).Valid | Should -BeFalse
        }
    }

    It 'flags an accessReview missing accessPackage' {
        InModuleScope $script:moduleName {
            $Doc = '{ "version": "1.0", "accessReviews": [ { "displayName": "r", "assignmentPolicy": "p" } ] }' | ConvertFrom-Json
            (Test-OERStructureSchema -Document $Doc).Valid | Should -BeFalse
        }
    }

    It 'flags an accessReview missing assignmentPolicy' {
        InModuleScope $script:moduleName {
            $Doc = '{ "version": "1.0", "accessReviews": [ { "displayName": "r", "accessPackage": "ap" } ] }' | ConvertFrom-Json
            (Test-OERStructureSchema -Document $Doc).Valid | Should -BeFalse
        }
    }

    It 'flags a role assignment missing scope/role/principal' {
        InModuleScope $script:moduleName {
            $Doc = '{ "version": "1.0", "roleAssignments": [ { "role": "Reader" } ] }' | ConvertFrom-Json
            (Test-OERStructureSchema -Document $Doc).Valid | Should -BeFalse
        }
    }

    It 'flags a role assignment missing scope' {
        InModuleScope $script:moduleName {
            $Doc = '{ "version": "1.0", "roleAssignments": [ { "role": "Reader", "principal": "person21@example.com" } ] }' | ConvertFrom-Json
            (Test-OERStructureSchema -Document $Doc).Valid | Should -BeFalse
        }
    }

    It 'flags a role assignment missing principal' {
        InModuleScope $script:moduleName {
            $Doc = '{ "version": "1.0", "roleAssignments": [ { "scope": "/subscriptions/sub1", "role": "Reader" } ] }' | ConvertFrom-Json
            (Test-OERStructureSchema -Document $Doc).Valid | Should -BeFalse
        }
    }

    It 'accepts a valid role assignment' {
        InModuleScope $script:moduleName {
            $Doc = '{ "version": "1.0", "roleAssignments": [ { "scope": "/subscriptions/sub1", "role": "Reader", "principal": "person21@example.com" } ] }' | ConvertFrom-Json
            (Test-OERStructureSchema -Document $Doc).Valid | Should -BeTrue
        }
    }

    It 'flags a role management policy missing scope' {
        InModuleScope $script:moduleName {
            $Doc = '{ "version": "1.0", "roleManagementPolicies": [ { "role": "Reader" } ] }' | ConvertFrom-Json
            (Test-OERStructureSchema -Document $Doc).Valid | Should -BeFalse
        }
    }

    It 'flags a role management policy missing role' {
        InModuleScope $script:moduleName {
            $Doc = '{ "version": "1.0", "roleManagementPolicies": [ { "scope": "sub:Prod" } ] }' | ConvertFrom-Json
            (Test-OERStructureSchema -Document $Doc).Valid | Should -BeFalse
        }
    }

    It 'flags a role management policy with non-boolean allowPermanentEligibility' {
        InModuleScope $script:moduleName {
            $Doc = '{ "version": "1.0", "roleManagementPolicies": [ { "scope": "sub:Prod", "role": "Reader", "allowPermanentEligibility": "yes" } ] }' | ConvertFrom-Json
            (Test-OERStructureSchema -Document $Doc).Valid | Should -BeFalse
        }
    }

    It 'accepts a role management policy with boolean allowPermanentEligibility' {
        InModuleScope $script:moduleName {
            $Doc = '{ "version": "1.0", "roleManagementPolicies": [ { "scope": "sub:Prod", "role": "Reader", "allowPermanentEligibility": true } ] }' | ConvertFrom-Json
            (Test-OERStructureSchema -Document $Doc).Valid | Should -BeTrue
        }
    }

    It 'flags a role management policy with activationMaxHours out of range' {
        InModuleScope $script:moduleName {
            $Doc = '{ "version": "1.0", "roleManagementPolicies": [ { "scope": "sub:Prod", "role": "Reader", "activationMaxHours": 25 } ] }' | ConvertFrom-Json
            (Test-OERStructureSchema -Document $Doc).Valid | Should -BeFalse
        }
    }

    It 'warns (but stays Valid) when an access package references an undeclared catalog' {
        InModuleScope $script:moduleName {
            # resourceRoles is declared so the omitted-collection Warning cannot stand in for the
            # catalog cross-reference Warning this test is about.
            $Doc = '{ "version": "1.0", "accessPackages": [ { "displayName": "ap", "catalog": "CAT-Absent", "resourceRoles": [] } ] }' | ConvertFrom-Json
            $V = Test-OERStructureSchema -Document $Doc
            $V.Valid | Should -BeTrue
            @($V.Errors | Where-Object Severity -eq 'Warning').Count | Should -BeGreaterThan 0
        }
    }

    It 'does not warn when the access package catalog is declared' {
        InModuleScope $script:moduleName {
            # resources and resourceRoles are declared so the omitted-collection Warning does not
            # count against the catalog cross-reference this test is about.
            $Doc = '{ "version": "1.0", "catalogs": [ { "displayName": "CAT-X", "resources": [] } ], "accessPackages": [ { "displayName": "ap", "catalog": "CAT-X", "resourceRoles": [] } ] }' | ConvertFrom-Json
            $V = Test-OERStructureSchema -Document $Doc
            @($V.Errors | Where-Object Severity -eq 'Warning').Count | Should -Be 0
        }
    }

    It 'has a registered format view' {
        $Doc = '{ "version": "1.0" }' | ConvertFrom-Json
        $Out = (InModuleScope $script:moduleName -Parameters @{ D = $Doc } { param($D) Test-OERStructureSchema -Document $D }) | Format-List | Out-String
        $Out | Should -Match 'Valid'
    }

    It 'returns an Errors array (not null) even when there are no findings' {
        InModuleScope $script:moduleName {
            $Doc = '{ "version": "1.0" }' | ConvertFrom-Json
            $V = Test-OERStructureSchema -Document $Doc
            $null -eq $V.Errors | Should -BeFalse
        }
    }

    It 'sets the Section field on findings' {
        InModuleScope $script:moduleName {
            $Doc = '{ "groups": [] }' | ConvertFrom-Json
            $V = Test-OERStructureSchema -Document $Doc
            ($V.Errors | Where-Object Path -eq 'version').Section | Should -Not -BeNullOrEmpty
        }
    }

    It 'sets the Message field on findings' {
        InModuleScope $script:moduleName {
            $Doc = '{}' | ConvertFrom-Json
            $V = Test-OERStructureSchema -Document $Doc
            ($V.Errors | Where-Object Path -eq 'version').Message | Should -Not -BeNullOrEmpty
        }
    }

    It 'flags a scalar where a nested sub-collection must be an array (<Json>)' -TestCases @(
        @{ Json = '{ "version": "1.0", "administrativeUnits": [ { "displayName": "au", "scopedRoles": "x" } ] }'; Path = 'administrativeUnits[0].scopedRoles' }
        @{ Json = '{ "version": "1.0", "catalogs": [ { "displayName": "c", "resources": "x" } ] }'; Path = 'catalogs[0].resources' }
        @{ Json = '{ "version": "1.0", "accessPackages": [ { "displayName": "ap", "catalog": "c", "resourceRoles": "x" } ] }'; Path = 'accessPackages[0].resourceRoles' }
        @{ Json = '{ "version": "1.0", "accessPackages": [ { "displayName": "ap", "catalog": "c", "assignmentPolicies": "x" } ] }'; Path = 'accessPackages[0].assignmentPolicies' }
    ) {
        param($Json, $Path)
        InModuleScope $script:moduleName -Parameters @{ Json = $Json; Path = $Path } {
            param($Json, $Path)
            $V = Test-OERStructureSchema -Document ($Json | ConvertFrom-Json)
            $V.Valid | Should -BeFalse
            @($V.Errors | Where-Object { $_.Path -eq $Path -and $_.Message -match 'must be an array' }).Count | Should -BeGreaterThan 0
        }
    }

    It 'accepts roleManagementPolicies activationMaxHours at boundary values <Hours>' -TestCases @(
        @{ Hours = 1 }
        @{ Hours = 24 }
    ) {
        param($Hours)
        InModuleScope $script:moduleName -Parameters @{ Hours = $Hours } {
            param($Hours)
            $Doc = ('{ "version": "1.0", "roleManagementPolicies": [ { "scope": "sub:Prod", "role": "Reader", "activationMaxHours": ' + $Hours + ' } ] }') | ConvertFrom-Json
            (Test-OERStructureSchema -Document $Doc).Valid | Should -BeTrue
        }
    }

    It 'accepts a valid nested member/owner pimPolicy' {
        InModuleScope $script:moduleName {
            $Json = @'
{ "version": "1.0", "groups": [ { "displayName": "g1", "pimPolicy": {
  "member": { "activationMaxHours": 8, "activationEnablement": ["Justification"], "allowPermanentEligibility": false,
    "eligibleDurationDays": 365, "activeDurationDays": 180, "activeEnablement": ["MultiFactorAuthentication"],
    "notifications": { "eligibleAlert": ["person18@example.com"], "activeAlert": ["person22@example.com"], "activationAlert": ["person24@example.com"] } },
  "owner": { "activationMaxHours": 1 } } } ] }
'@
            $R = Test-OERStructureSchema -Document ($Json | ConvertFrom-Json)
            $R.Valid | Should -BeTrue
        }
    }

    It 'rejects a nested member activationMaxHours outside 1-24' {
        InModuleScope $script:moduleName {
            $Json = '{ "version": "1.0", "groups": [ { "displayName": "g1", "pimPolicy": { "member": { "activationMaxHours": 99 } } } ] }'
            $R = Test-OERStructureSchema -Document ($Json | ConvertFrom-Json)
            $R.Valid | Should -BeFalse
        }
    }

    It 'rejects an enablement value outside the allowed set' {
        InModuleScope $script:moduleName {
            $Json = '{ "version": "1.0", "groups": [ { "displayName": "g1", "pimPolicy": { "member": { "activeEnablement": ["Nope"] } } } ] }'
            $R = Test-OERStructureSchema -Document ($Json | ConvertFrom-Json)
            $R.Valid | Should -BeFalse
        }
    }

    It 'warns (non-fatal) when flat and nested forms are mixed' {
        InModuleScope $script:moduleName {
            $Json = '{ "version": "1.0", "groups": [ { "displayName": "g1", "pimPolicy": { "activationMaxHours": 8, "owner": { "activationMaxHours": 1 } } } ] }'
            $R = Test-OERStructureSchema -Document ($Json | ConvertFrom-Json)
            $R.Valid | Should -BeTrue
            ($R.Errors | Where-Object { $_.Severity -eq 'Warning' -and $_.Path -match 'pimPolicy' }).Count | Should -BeGreaterThan 0
        }
    }

    It 'still accepts the flat member-only pimPolicy (back-compat)' {
        InModuleScope $script:moduleName {
            $Json = '{ "version": "1.0", "groups": [ { "displayName": "g1", "pimPolicy": { "activationMaxHours": 8, "allowPermanentEligibility": true } } ] }'
            (Test-OERStructureSchema -Document ($Json | ConvertFrom-Json)).Valid | Should -BeTrue
        }
    }

    Context 'PR3 optional fields' {
        It 'accepts a fully populated assignmentPolicy (requestorScope/approvalStages/durationInDays)' {
            InModuleScope 'Omnicit.EntraRBAC' {
                $doc = [PSCustomObject]@{
                    version = '1.0'
                    accessPackages = @([PSCustomObject]@{
                        displayName = 'AP'; catalog = 'CAT'
                        assignmentPolicies = @([PSCustomObject]@{
                            displayName = 'Default'
                            requestorScope = [PSCustomObject]@{ scope = 'AllMemberUsers' }
                            approvalStages = @([PSCustomObject]@{ durationDays = 7; manager = $true })
                            durationInDays = 30
                        })
                    })
                    catalogs = @([PSCustomObject]@{ displayName = 'CAT' })
                }
                (Test-OERStructureSchema -Document $doc).Valid | Should -BeTrue
            }
        }

        It 'still accepts a displayName-only assignmentPolicy' {
            InModuleScope 'Omnicit.EntraRBAC' {
                $doc = [PSCustomObject]@{
                    version = '1.0'
                    accessPackages = @([PSCustomObject]@{ displayName = 'AP'; catalog = 'CAT'; assignmentPolicies = @([PSCustomObject]@{ displayName = 'Default' }) })
                    catalogs = @([PSCustomObject]@{ displayName = 'CAT' })
                }
                (Test-OERStructureSchema -Document $doc).Valid | Should -BeTrue
            }
        }

        It 'rejects a non-string requestorScope.scope' {
            InModuleScope 'Omnicit.EntraRBAC' {
                $doc = [PSCustomObject]@{
                    version = '1.0'
                    accessPackages = @([PSCustomObject]@{ displayName = 'AP'; catalog = 'CAT'; assignmentPolicies = @([PSCustomObject]@{ displayName = 'Default'; requestorScope = [PSCustomObject]@{ scope = '' } }) })
                    catalogs = @([PSCustomObject]@{ displayName = 'CAT' })
                }
                $r = Test-OERStructureSchema -Document $doc
                $r.Valid | Should -BeFalse
                ($r.Errors | Where-Object Path -match 'requestorScope.scope').Count | Should -BeGreaterThan 0
            }
        }

        It 'rejects an out-of-range approvalStages durationDays' {
            InModuleScope 'Omnicit.EntraRBAC' {
                $doc = [PSCustomObject]@{
                    version = '1.0'
                    accessPackages = @([PSCustomObject]@{ displayName = 'AP'; catalog = 'CAT'; assignmentPolicies = @([PSCustomObject]@{ displayName = 'Default'; approvalStages = @([PSCustomObject]@{ durationDays = 0 }) }) })
                    catalogs = @([PSCustomObject]@{ displayName = 'CAT' })
                }
                (Test-OERStructureSchema -Document $doc).Valid | Should -BeFalse
            }
        }

        It 'accepts a roleAssignment with a valid principalType' {
            InModuleScope 'Omnicit.EntraRBAC' {
                $doc = [PSCustomObject]@{ version = '1.0'; roleAssignments = @([PSCustomObject]@{ scope = 'subscription:Prod'; role = 'Reader'; principal = 'sp'; principalType = 'ServicePrincipal' }) }
                (Test-OERStructureSchema -Document $doc).Valid | Should -BeTrue
            }
        }

        It 'rejects an invalid roleAssignment principalType' {
            InModuleScope 'Omnicit.EntraRBAC' {
                $doc = [PSCustomObject]@{ version = '1.0'; roleAssignments = @([PSCustomObject]@{ scope = 'subscription:Prod'; role = 'Reader'; principal = 'x'; principalType = 'Device' }) }
                $r = Test-OERStructureSchema -Document $doc
                $r.Valid | Should -BeFalse
                ($r.Errors | Where-Object Path -match 'principalType').Count | Should -BeGreaterThan 0
            }
        }
    }

    Context 'granular AP policy fields' {
        # Build a doc outside InModuleScope then pass it in via -Parameters.
        # This avoids the InModuleScope scope isolation that prevents calling helpers defined here.

        It 'accepts a policy with ALL new granular fields populated with valid values' {
            $Doc = [PSCustomObject]@{
                version        = '1.0'
                catalogs       = @([PSCustomObject]@{ displayName = 'CAT' })
                accessPackages = @([PSCustomObject]@{
                    displayName        = 'AP'
                    catalog            = 'CAT'
                    assignmentPolicies = @([PSCustomObject]@{
                        displayName                   = 'Default'
                        requireApproval               = $true
                        requireRequestorJustification = $false
                        requireApprovalForUpdate      = $true
                        notificationsDisabled         = $false
                        durationInHours               = 8
                        requestorScope                = [PSCustomObject]@{
                            scope  = 'AllMemberUsers'
                            users  = @('11111111-0000-0000-0000-000000000000')
                            groups = @('22222222-0000-0000-0000-000000000000')
                        }
                        requestorSettings             = [PSCustomObject]@{
                            allowSelfRequest    = $true
                            allowManagerRequest = $false
                            allowCustomSchedule = $true
                            allowSelfExtend     = $false
                            managerLevel        = 1
                        }
                        approvalStages                = @([PSCustomObject]@{
                            durationDays                 = 7
                            manager                      = $true
                            managerLevel                 = 2
                            escalationDays               = 3
                            users                        = @('aaaaaaaa-0000-0000-0000-000000000000')
                            groups                       = @('bbbbbbbb-0000-0000-0000-000000000000')
                            alternateUsers               = @('cccccccc-0000-0000-0000-000000000000')
                            alternateGroups              = @('dddddddd-0000-0000-0000-000000000000')
                            fallbackUsers                = @('eeeeeeee-0000-0000-0000-000000000000')
                            fallbackGroups               = @('ffffffff-0000-0000-0000-000000000000')
                            internalSponsor              = $false
                            externalSponsor              = $false
                            requireApproverJustification = $true
                            approverInfoVisibility       = 'Visible'
                        })
                    })
                })
            }
            InModuleScope 'Omnicit.EntraRBAC' -Parameters @{ Doc = $Doc } {
                param($Doc)
                $R = Test-OERStructureSchema -Document $Doc
                $R.Valid | Should -BeTrue
                @($R.Errors | Where-Object Severity -eq 'Error').Count | Should -Be 0
            }
        }

        It 'BACK-COMPAT: legacy flat shape (requestorScope/approvalStages/durationInDays) still valid' {
            $Doc = [PSCustomObject]@{
                version        = '1.0'
                catalogs       = @([PSCustomObject]@{ displayName = 'CAT' })
                accessPackages = @([PSCustomObject]@{
                    displayName        = 'AP'
                    catalog            = 'CAT'
                    assignmentPolicies = @([PSCustomObject]@{
                        displayName    = 'Default'
                        requestorScope = [PSCustomObject]@{ scope = 'AllMemberUsers' }
                        approvalStages = @([PSCustomObject]@{ durationDays = 7; manager = $true })
                        durationInDays = 30
                    })
                })
            }
            InModuleScope 'Omnicit.EntraRBAC' -Parameters @{ Doc = $Doc } {
                param($Doc)
                (Test-OERStructureSchema -Document $Doc).Valid | Should -BeTrue
            }
        }

        It 'flags approverInfoVisibility with invalid value Bogus' {
            $Doc = [PSCustomObject]@{
                version        = '1.0'
                catalogs       = @([PSCustomObject]@{ displayName = 'CAT' })
                accessPackages = @([PSCustomObject]@{
                    displayName        = 'AP'
                    catalog            = 'CAT'
                    assignmentPolicies = @([PSCustomObject]@{
                        displayName    = 'Default'
                        approvalStages = @([PSCustomObject]@{ durationDays = 7; approverInfoVisibility = 'Bogus' })
                    })
                })
            }
            InModuleScope 'Omnicit.EntraRBAC' -Parameters @{ Doc = $Doc } {
                param($Doc)
                $R = Test-OERStructureSchema -Document $Doc
                $R.Valid | Should -BeFalse
                @($R.Errors | Where-Object { $_.Path -match 'approverInfoVisibility' }).Count | Should -BeGreaterThan 0
            }
        }

        It 'flags approvalStages[0].escalationDays of 0 (below minimum 1)' {
            $Doc = [PSCustomObject]@{
                version        = '1.0'
                catalogs       = @([PSCustomObject]@{ displayName = 'CAT' })
                accessPackages = @([PSCustomObject]@{
                    displayName        = 'AP'
                    catalog            = 'CAT'
                    assignmentPolicies = @([PSCustomObject]@{
                        displayName    = 'Default'
                        approvalStages = @([PSCustomObject]@{ durationDays = 7; escalationDays = 0 })
                    })
                })
            }
            InModuleScope 'Omnicit.EntraRBAC' -Parameters @{ Doc = $Doc } {
                param($Doc)
                $R = Test-OERStructureSchema -Document $Doc
                $R.Valid | Should -BeFalse
                @($R.Errors | Where-Object { $_.Path -match 'escalationDays' }).Count | Should -BeGreaterThan 0
            }
        }

        It 'flags approvalStages[0].managerLevel of 0 (below minimum 1)' {
            $Doc = [PSCustomObject]@{
                version        = '1.0'
                catalogs       = @([PSCustomObject]@{ displayName = 'CAT' })
                accessPackages = @([PSCustomObject]@{
                    displayName        = 'AP'
                    catalog            = 'CAT'
                    assignmentPolicies = @([PSCustomObject]@{
                        displayName    = 'Default'
                        approvalStages = @([PSCustomObject]@{ durationDays = 7; managerLevel = 0 })
                    })
                })
            }
            InModuleScope 'Omnicit.EntraRBAC' -Parameters @{ Doc = $Doc } {
                param($Doc)
                $R = Test-OERStructureSchema -Document $Doc
                $R.Valid | Should -BeFalse
                @($R.Errors | Where-Object { $_.Path -match 'approvalStages\[0\]\.managerLevel' }).Count | Should -BeGreaterThan 0
            }
        }

        It 'flags requestorSettings.managerLevel of 0 (below minimum 1)' {
            $Doc = [PSCustomObject]@{
                version        = '1.0'
                catalogs       = @([PSCustomObject]@{ displayName = 'CAT' })
                accessPackages = @([PSCustomObject]@{
                    displayName        = 'AP'
                    catalog            = 'CAT'
                    assignmentPolicies = @([PSCustomObject]@{
                        displayName       = 'Default'
                        requestorSettings = [PSCustomObject]@{ managerLevel = 0 }
                    })
                })
            }
            InModuleScope 'Omnicit.EntraRBAC' -Parameters @{ Doc = $Doc } {
                param($Doc)
                $R = Test-OERStructureSchema -Document $Doc
                $R.Valid | Should -BeFalse
                @($R.Errors | Where-Object { $_.Path -match 'requestorSettings\.managerLevel' }).Count | Should -BeGreaterThan 0
            }
        }

        It 'flags durationInHours of 0 (below minimum 1)' {
            $Doc = [PSCustomObject]@{
                version        = '1.0'
                catalogs       = @([PSCustomObject]@{ displayName = 'CAT' })
                accessPackages = @([PSCustomObject]@{
                    displayName        = 'AP'
                    catalog            = 'CAT'
                    assignmentPolicies = @([PSCustomObject]@{ displayName = 'Default'; durationInHours = 0 })
                })
            }
            InModuleScope 'Omnicit.EntraRBAC' -Parameters @{ Doc = $Doc } {
                param($Doc)
                $R = Test-OERStructureSchema -Document $Doc
                $R.Valid | Should -BeFalse
                @($R.Errors | Where-Object { $_.Path -match 'durationInHours' }).Count | Should -BeGreaterThan 0
            }
        }

        It 'flags mutual exclusion when both durationInDays and durationInHours are present' {
            $Doc = [PSCustomObject]@{
                version        = '1.0'
                catalogs       = @([PSCustomObject]@{ displayName = 'CAT' })
                accessPackages = @([PSCustomObject]@{
                    displayName        = 'AP'
                    catalog            = 'CAT'
                    assignmentPolicies = @([PSCustomObject]@{
                        displayName    = 'Default'
                        durationInDays  = 30
                        durationInHours = 8
                    })
                })
            }
            InModuleScope 'Omnicit.EntraRBAC' -Parameters @{ Doc = $Doc } {
                param($Doc)
                $R = Test-OERStructureSchema -Document $Doc
                $R.Valid | Should -BeFalse
                @($R.Errors | Where-Object { $_.Message -match 'mutual' -or $_.Message -match 'at most one' }).Count | Should -BeGreaterThan 0
            }
        }

        It 'flags requestorSettings.allowSelfRequest = "yes" (non-bool)' {
            $Doc = [PSCustomObject]@{
                version        = '1.0'
                catalogs       = @([PSCustomObject]@{ displayName = 'CAT' })
                accessPackages = @([PSCustomObject]@{
                    displayName        = 'AP'
                    catalog            = 'CAT'
                    assignmentPolicies = @([PSCustomObject]@{
                        displayName       = 'Default'
                        requestorSettings = [PSCustomObject]@{ allowSelfRequest = 'yes' }
                    })
                })
            }
            InModuleScope 'Omnicit.EntraRBAC' -Parameters @{ Doc = $Doc } {
                param($Doc)
                $R = Test-OERStructureSchema -Document $Doc
                $R.Valid | Should -BeFalse
                @($R.Errors | Where-Object { $_.Path -match 'allowSelfRequest' }).Count | Should -BeGreaterThan 0
            }
        }

        It 'flags requestorSettings.allowSelfRemove = "yes" (non-bool)' {
            $Doc = [PSCustomObject]@{
                version        = '1.0'
                catalogs       = @([PSCustomObject]@{ displayName = 'CAT' })
                accessPackages = @([PSCustomObject]@{
                    displayName        = 'AP'
                    catalog            = 'CAT'
                    assignmentPolicies = @([PSCustomObject]@{
                        displayName       = 'Default'
                        requestorSettings = [PSCustomObject]@{ allowSelfRemove = 'yes' }
                    })
                })
            }
            InModuleScope 'Omnicit.EntraRBAC' -Parameters @{ Doc = $Doc } {
                param($Doc)
                $R = Test-OERStructureSchema -Document $Doc
                $R.Valid | Should -BeFalse
                @($R.Errors | Where-Object { $_.Path -match 'allowSelfRemove' }).Count | Should -BeGreaterThan 0
            }
        }

        It 'accepts requestorSettings.allowOnBehalfUpdate and allowOnBehalfRemove as valid booleans' {
            $Doc = [PSCustomObject]@{
                version        = '1.0'
                catalogs       = @([PSCustomObject]@{ displayName = 'CAT' })
                accessPackages = @([PSCustomObject]@{
                    displayName        = 'AP'
                    catalog            = 'CAT'
                    assignmentPolicies = @([PSCustomObject]@{
                        displayName       = 'Default'
                        requestorSettings = [PSCustomObject]@{ allowOnBehalfUpdate = $true; allowOnBehalfRemove = $false }
                    })
                })
            }
            InModuleScope 'Omnicit.EntraRBAC' -Parameters @{ Doc = $Doc } {
                param($Doc)
                $R = Test-OERStructureSchema -Document $Doc
                @($R.Errors | Where-Object { $_.Path -match 'allowOnBehalf' }).Count | Should -Be 0
            }
        }

        It 'flags approvalStages.fallbackUsers = "not-an-array" (string instead of array)' {
            $Doc = [PSCustomObject]@{
                version        = '1.0'
                catalogs       = @([PSCustomObject]@{ displayName = 'CAT' })
                accessPackages = @([PSCustomObject]@{
                    displayName        = 'AP'
                    catalog            = 'CAT'
                    assignmentPolicies = @([PSCustomObject]@{
                        displayName    = 'Default'
                        approvalStages = @([PSCustomObject]@{ durationDays = 7; manager = $true; fallbackUsers = 'not-an-array' })
                    })
                })
            }
            InModuleScope 'Omnicit.EntraRBAC' -Parameters @{ Doc = $Doc } {
                param($Doc)
                $R = Test-OERStructureSchema -Document $Doc
                $R.Valid | Should -BeFalse
                @($R.Errors | Where-Object { $_.Path -match 'fallbackUsers' }).Count | Should -BeGreaterThan 0
            }
        }

        It 'accepts approvalStages.fallbackUsers and fallbackGroups as valid arrays' {
            $Doc = [PSCustomObject]@{
                version        = '1.0'
                catalogs       = @([PSCustomObject]@{ displayName = 'CAT' })
                accessPackages = @([PSCustomObject]@{
                    displayName        = 'AP'
                    catalog            = 'CAT'
                    assignmentPolicies = @([PSCustomObject]@{
                        displayName    = 'Default'
                        approvalStages = @([PSCustomObject]@{
                                durationDays   = 7
                                manager        = $true
                                fallbackUsers  = @('person25@example.com')
                                fallbackGroups = @('FB Group')
                            })
                    })
                })
            }
            InModuleScope 'Omnicit.EntraRBAC' -Parameters @{ Doc = $Doc } {
                param($Doc)
                $R = Test-OERStructureSchema -Document $Doc
                @($R.Errors | Where-Object { $_.Path -match 'fallback' }).Count | Should -Be 0
            }
        }

        It 'flags requestorScope.users = "not-an-array" (string instead of array)' {
            $Doc = [PSCustomObject]@{
                version        = '1.0'
                catalogs       = @([PSCustomObject]@{ displayName = 'CAT' })
                accessPackages = @([PSCustomObject]@{
                    displayName        = 'AP'
                    catalog            = 'CAT'
                    assignmentPolicies = @([PSCustomObject]@{
                        displayName    = 'Default'
                        requestorScope = [PSCustomObject]@{ scope = 'SpecificDirectoryUsers'; users = 'not-an-array' }
                    })
                })
            }
            InModuleScope 'Omnicit.EntraRBAC' -Parameters @{ Doc = $Doc } {
                param($Doc)
                $R = Test-OERStructureSchema -Document $Doc
                $R.Valid | Should -BeFalse
                @($R.Errors | Where-Object { $_.Path -match 'requestorScope\.users' }).Count | Should -BeGreaterThan 0
            }
        }

        It 'accepts approverInfoVisibility Default Visible NotVisible (case-insensitive)' -TestCases @(
            @{ Vis = 'Default' }
            @{ Vis = 'Visible' }
            @{ Vis = 'NotVisible' }
            @{ Vis = 'notvisible' }
        ) {
            param($Vis)
            $Doc = [PSCustomObject]@{
                version        = '1.0'
                catalogs       = @([PSCustomObject]@{ displayName = 'CAT' })
                accessPackages = @([PSCustomObject]@{
                    displayName        = 'AP'
                    catalog            = 'CAT'
                    assignmentPolicies = @([PSCustomObject]@{
                        displayName    = 'Default'
                        approvalStages = @([PSCustomObject]@{ approverInfoVisibility = $Vis })
                    })
                })
            }
            InModuleScope 'Omnicit.EntraRBAC' -Parameters @{ Doc = $Doc; Vis = $Vis } {
                param($Doc, $Vis)
                (Test-OERStructureSchema -Document $Doc).Valid | Should -BeTrue -Because "approverInfoVisibility '$Vis' is valid"
            }
        }

        It 'flags requireApproval = "yes" (non-bool)' {
            $Doc = [PSCustomObject]@{
                version        = '1.0'
                catalogs       = @([PSCustomObject]@{ displayName = 'CAT' })
                accessPackages = @([PSCustomObject]@{
                    displayName        = 'AP'
                    catalog            = 'CAT'
                    assignmentPolicies = @([PSCustomObject]@{ displayName = 'Default'; requireApproval = 'yes' })
                })
            }
            InModuleScope 'Omnicit.EntraRBAC' -Parameters @{ Doc = $Doc } {
                param($Doc)
                $R = Test-OERStructureSchema -Document $Doc
                $R.Valid | Should -BeFalse
                @($R.Errors | Where-Object { $_.Path -match 'requireApproval' }).Count | Should -BeGreaterThan 0
            }
        }

        It 'flags expirationDateTime with an unparseable string' {
            $Doc = [PSCustomObject]@{
                version        = '1.0'
                catalogs       = @([PSCustomObject]@{ displayName = 'CAT' })
                accessPackages = @([PSCustomObject]@{
                    displayName        = 'AP'
                    catalog            = 'CAT'
                    assignmentPolicies = @([PSCustomObject]@{ displayName = 'Default'; expirationDateTime = 'not-a-date' })
                })
            }
            InModuleScope 'Omnicit.EntraRBAC' -Parameters @{ Doc = $Doc } {
                param($Doc)
                $R = Test-OERStructureSchema -Document $Doc
                $R.Valid | Should -BeFalse
                @($R.Errors | Where-Object { $_.Path -match 'expirationDateTime' }).Count | Should -BeGreaterThan 0
            }
        }

        It 'accepts a parseable expirationDateTime' {
            $Doc = [PSCustomObject]@{
                version        = '1.0'
                catalogs       = @([PSCustomObject]@{ displayName = 'CAT' })
                accessPackages = @([PSCustomObject]@{
                    displayName        = 'AP'
                    catalog            = 'CAT'
                    assignmentPolicies = @([PSCustomObject]@{ displayName = 'Default'; expirationDateTime = '2027-12-31T00:00:00Z' })
                })
            }
            InModuleScope 'Omnicit.EntraRBAC' -Parameters @{ Doc = $Doc } {
                param($Doc)
                (Test-OERStructureSchema -Document $Doc).Valid | Should -BeTrue
            }
        }

        It 'flags mutual exclusion when all three expiration fields are present' {
            $Doc = [PSCustomObject]@{
                version        = '1.0'
                catalogs       = @([PSCustomObject]@{ displayName = 'CAT' })
                accessPackages = @([PSCustomObject]@{
                    displayName        = 'AP'
                    catalog            = 'CAT'
                    assignmentPolicies = @([PSCustomObject]@{
                        displayName        = 'Default'
                        durationInDays     = 30
                        durationInHours    = 8
                        expirationDateTime = '2027-12-31T00:00:00Z'
                    })
                })
            }
            InModuleScope 'Omnicit.EntraRBAC' -Parameters @{ Doc = $Doc } {
                param($Doc)
                $R = Test-OERStructureSchema -Document $Doc
                $R.Valid | Should -BeFalse
                @($R.Errors | Where-Object { $_.Message -match 'mutual' -or $_.Message -match 'at most one' }).Count | Should -BeGreaterThan 0
            }
        }

        It 'flags requestorScope.groups = "not-an-array" (string instead of array)' {
            $Doc = [PSCustomObject]@{
                version        = '1.0'
                catalogs       = @([PSCustomObject]@{ displayName = 'CAT' })
                accessPackages = @([PSCustomObject]@{
                    displayName        = 'AP'
                    catalog            = 'CAT'
                    assignmentPolicies = @([PSCustomObject]@{
                        displayName    = 'Default'
                        requestorScope = [PSCustomObject]@{ scope = 'SpecificDirectoryUsers'; groups = 'not-an-array' }
                    })
                })
            }
            InModuleScope 'Omnicit.EntraRBAC' -Parameters @{ Doc = $Doc } {
                param($Doc)
                $R = Test-OERStructureSchema -Document $Doc
                $R.Valid | Should -BeFalse
                @($R.Errors | Where-Object { $_.Path -match 'requestorScope\.groups' }).Count | Should -BeGreaterThan 0
            }
        }

        It 'flags approvalStages[0].internalSponsor = "yes" (non-bool)' {
            $Doc = [PSCustomObject]@{
                version        = '1.0'
                catalogs       = @([PSCustomObject]@{ displayName = 'CAT' })
                accessPackages = @([PSCustomObject]@{
                    displayName        = 'AP'
                    catalog            = 'CAT'
                    assignmentPolicies = @([PSCustomObject]@{
                        displayName    = 'Default'
                        approvalStages = @([PSCustomObject]@{ durationDays = 7; internalSponsor = 'yes' })
                    })
                })
            }
            InModuleScope 'Omnicit.EntraRBAC' -Parameters @{ Doc = $Doc } {
                param($Doc)
                $R = Test-OERStructureSchema -Document $Doc
                $R.Valid | Should -BeFalse
                @($R.Errors | Where-Object { $_.Path -match 'internalSponsor' }).Count | Should -BeGreaterThan 0
            }
        }

        It 'flags requestorSettings = "not-an-object" (scalar) without throwing' {
            $Doc = [PSCustomObject]@{
                version        = '1.0'
                catalogs       = @([PSCustomObject]@{ displayName = 'CAT' })
                accessPackages = @([PSCustomObject]@{
                    displayName        = 'AP'
                    catalog            = 'CAT'
                    assignmentPolicies = @([PSCustomObject]@{
                        displayName       = 'Default'
                        requestorSettings = 'not-an-object'
                    })
                })
            }
            InModuleScope 'Omnicit.EntraRBAC' -Parameters @{ Doc = $Doc } {
                param($Doc)
                $R = Test-OERStructureSchema -Document $Doc
                $R.Valid | Should -BeFalse
                @($R.Errors | Where-Object { $_.Path -match 'requestorSettings' -and $_.Message -match 'must be an object' }).Count | Should -BeGreaterThan 0
            }
        }

        It 'accepts requestorSettings.managerLevel = 50 (high but valid value)' {
            $Doc = [PSCustomObject]@{
                version        = '1.0'
                catalogs       = @([PSCustomObject]@{ displayName = 'CAT' })
                accessPackages = @([PSCustomObject]@{
                    displayName        = 'AP'
                    catalog            = 'CAT'
                    assignmentPolicies = @([PSCustomObject]@{
                        displayName       = 'Default'
                        requestorSettings = [PSCustomObject]@{ managerLevel = 50 }
                    })
                })
            }
            InModuleScope 'Omnicit.EntraRBAC' -Parameters @{ Doc = $Doc } {
                param($Doc)
                $R = Test-OERStructureSchema -Document $Doc
                @($R.Errors | Where-Object { $_.Path -match 'managerLevel' }).Count | Should -Be 0
            }
        }
    }

    Context 'roleManagementPolicies full field set' {
        # Doc is built outside InModuleScope (matching the 'granular AP policy fields' context
        # above) and passed in via -Parameters, since InModuleScope isolates script-scope helpers.
        # New-RmpDoc must be defined in a BeforeAll: a function declared directly in a Context body
        # is only visible during Pester's Discovery pass, not during Run, so an It calling it
        # straight away would fail with CommandNotFoundException.
        BeforeAll {
            function New-RmpDoc {
                param([hashtable]$Extra)
                $Item = [ordered]@{ scope = '/subscriptions/sub-1'; role = 'Contributor' }
                foreach ($K in $Extra.Keys) { $Item[$K] = $Extra[$K] }
                [PSCustomObject]@{ version = '1.0'; roleManagementPolicies = @([PSCustomObject]$Item) }
            }
        }

        It 'accepts every supported field' {
            $Doc = New-RmpDoc -Extra @{
                allowPermanentEligibility = $true; eligibleDurationDays = 365
                allowPermanentActiveAssignment = $false; activeDurationDays = 180
                activationMaxHours = 4
                requireMfaOnActivation = $true; requireJustificationOnActivation = $true
                requireTicketOnActivation = $false; requireApproval = $true
                approvers = [PSCustomObject]@{ users = @('anna@contoso.com'); groups = @('sec-approvers') }
                authenticationContextId = 'c1'
                requireMfaOnActiveAssignment = $false; requireJustificationOnActiveAssignment = $true
            }
            # authenticationContextId with requireMfaOnActivation true is the one illegal combination,
            # so drop MFA for this all-fields case.
            $Doc.roleManagementPolicies[0].requireMfaOnActivation = $false
            InModuleScope 'Omnicit.EntraRBAC' -Parameters @{ Doc = $Doc } {
                param($Doc)
                (Test-OERStructureSchema -Document $Doc).Valid | Should -BeTrue
            }
        }

        It 'rejects a non-boolean toggle' {
            $Doc = New-RmpDoc -Extra @{ requireApproval = 'yes' }
            InModuleScope 'Omnicit.EntraRBAC' -Parameters @{ Doc = $Doc } {
                param($Doc)
                $Result = Test-OERStructureSchema -Document $Doc
                $Result.Valid | Should -BeFalse
                @($Result.Errors).Path | Should -Contain 'roleManagementPolicies[0].requireApproval'
            }
        }

        It 'rejects an out-of-range eligibleDurationDays' {
            $Doc = New-RmpDoc -Extra @{ eligibleDurationDays = 5000 }
            InModuleScope 'Omnicit.EntraRBAC' -Parameters @{ Doc = $Doc } {
                param($Doc)
                $Result = Test-OERStructureSchema -Document $Doc
                $Result.Valid | Should -BeFalse
                @($Result.Errors).Path | Should -Contain 'roleManagementPolicies[0].eligibleDurationDays'
            }
        }

        It 'rejects a non-array approvers.users' {
            $Doc = New-RmpDoc -Extra @{
                approvers = [PSCustomObject]@{ users = 'anna@contoso.com' }
            }
            InModuleScope 'Omnicit.EntraRBAC' -Parameters @{ Doc = $Doc } {
                param($Doc)
                $Result = Test-OERStructureSchema -Document $Doc
                $Result.Valid | Should -BeFalse
                @($Result.Errors).Path | Should -Contain 'roleManagementPolicies[0].approvers.users'
            }
        }

        It 'rejects a malformed authenticationContextId' {
            $Doc = New-RmpDoc -Extra @{ authenticationContextId = 'ctx1' }
            InModuleScope 'Omnicit.EntraRBAC' -Parameters @{ Doc = $Doc } {
                param($Doc)
                $Result = Test-OERStructureSchema -Document $Doc
                $Result.Valid | Should -BeFalse
                @($Result.Errors).Path | Should -Contain 'roleManagementPolicies[0].authenticationContextId'
            }
        }

        It 'accepts an empty authenticationContextId as an explicit disable' {
            $Doc = New-RmpDoc -Extra @{ authenticationContextId = '' }
            InModuleScope 'Omnicit.EntraRBAC' -Parameters @{ Doc = $Doc } {
                param($Doc)
                (Test-OERStructureSchema -Document $Doc).Valid | Should -BeTrue
            }
        }

        It 'rejects requireMfaOnActivation together with an authentication context' {
            $Doc = New-RmpDoc -Extra @{
                requireMfaOnActivation = $true; authenticationContextId = 'c1'
            }
            InModuleScope 'Omnicit.EntraRBAC' -Parameters @{ Doc = $Doc } {
                param($Doc)
                $Result = Test-OERStructureSchema -Document $Doc
                $Result.Valid | Should -BeFalse
                @($Result.Errors).Message -join ' ' | Should -Match 'mutually exclusive'
            }
        }
    }

    Context 'accessReviews full field set' {
        # New-ArDoc must be defined in a BeforeAll: a function declared directly in a Context body
        # is only visible during Pester's Discovery pass, not during Run (see the roleManagementPolicies
        # full field set Context above for the same pattern).
        BeforeAll {
            function New-ArDoc {
                param([hashtable]$Extra)
                $Item = [ordered]@{
                    displayName = 'Q3 AP review'; accessPackage = 'AP-Sales'; assignmentPolicy = 'Standard'
                }
                foreach ($K in $Extra.Keys) { $Item[$K] = $Extra[$K] }
                [PSCustomObject]@{ version = '1.0'; accessReviews = @([PSCustomObject]$Item) }
            }
        }

        It 'accepts every supported field' {
            $Doc = New-ArDoc -Extra @{
                recurrence = 'Quarterly'; startDate = '2026-07-01'; occurrences = 4
                durationInDays = 14; reviewers = @('manager'); fallbackReviewers = @('anna@contoso.com')
                descriptionForAdmins = 'a'; descriptionForReviewers = 'r'
                mailNotification = $true; reminderNotification = $true; requireJustification = $true
                recommendationsEnabled = $true; autoApplyDecisions = $false; defaultDecision = 'Deny'
            }
            InModuleScope 'Omnicit.EntraRBAC' -Parameters @{ Doc = $Doc } {
                param($Doc)
                (Test-OERStructureSchema -Document $Doc).Valid | Should -BeTrue
            }
        }

        It 'rejects a non-array reviewers' {
            $Doc = New-ArDoc -Extra @{ reviewers = 'manager' }
            InModuleScope 'Omnicit.EntraRBAC' -Parameters @{ Doc = $Doc } {
                param($Doc)
                $Result = Test-OERStructureSchema -Document $Doc
                $Result.Valid | Should -BeFalse
                @($Result.Errors).Path | Should -Contain 'accessReviews[0].reviewers'
            }
        }

        It 'rejects an out-of-range durationInDays' {
            $Doc = New-ArDoc -Extra @{ durationInDays = 0 }
            InModuleScope 'Omnicit.EntraRBAC' -Parameters @{ Doc = $Doc } {
                param($Doc)
                $Result = Test-OERStructureSchema -Document $Doc
                $Result.Valid | Should -BeFalse
                @($Result.Errors).Path | Should -Contain 'accessReviews[0].durationInDays'
            }
        }

        It 'rejects an unparseable startDate' {
            $Doc = New-ArDoc -Extra @{ startDate = 'not-a-date' }
            InModuleScope 'Omnicit.EntraRBAC' -Parameters @{ Doc = $Doc } {
                param($Doc)
                $Result = Test-OERStructureSchema -Document $Doc
                $Result.Valid | Should -BeFalse
                @($Result.Errors).Path | Should -Contain 'accessReviews[0].startDate'
            }
        }

        It 'rejects endDate together with occurrences' {
            $Doc = New-ArDoc -Extra @{
                recurrence = 'Monthly'; startDate = '2026-07-01'; endDate = '2027-07-01'; occurrences = 4
            }
            InModuleScope 'Omnicit.EntraRBAC' -Parameters @{ Doc = $Doc } {
                param($Doc)
                $Result = Test-OERStructureSchema -Document $Doc
                $Result.Valid | Should -BeFalse
                @($Result.Errors).Message -join ' ' | Should -Match 'mutually exclusive'
            }
        }

        It 'warns when a range is declared on a OneTime review' {
            $Doc = New-ArDoc -Extra @{
                recurrence = 'OneTime'; startDate = '2026-07-01'; occurrences = 4
            }
            InModuleScope 'Omnicit.EntraRBAC' -Parameters @{ Doc = $Doc } {
                param($Doc)
                $Result = Test-OERStructureSchema -Document $Doc
                $Result.Valid | Should -BeTrue
                $Finding = @($Result.Errors) | Where-Object { $_.Path -eq 'accessReviews[0].occurrences' }
                $Finding.Severity | Should -Be 'Warning'
            }
        }

        It 'rejects an invalid defaultDecision' {
            $Doc = New-ArDoc -Extra @{ defaultDecision = 'Maybe' }
            InModuleScope 'Omnicit.EntraRBAC' -Parameters @{ Doc = $Doc } {
                param($Doc)
                $Result = Test-OERStructureSchema -Document $Doc
                $Result.Valid | Should -BeFalse
                @($Result.Errors).Path | Should -Contain 'accessReviews[0].defaultDecision'
            }
        }

        It 'rejects a non-boolean setting toggle' {
            $Doc = New-ArDoc -Extra @{ autoApplyDecisions = 'yes' }
            InModuleScope 'Omnicit.EntraRBAC' -Parameters @{ Doc = $Doc } {
                param($Doc)
                $Result = Test-OERStructureSchema -Document $Doc
                $Result.Valid | Should -BeFalse
                @($Result.Errors).Path | Should -Contain 'accessReviews[0].autoApplyDecisions'
            }
        }

        It 'warns when reviewers declares manager without a fallback' {
            $Doc = New-ArDoc -Extra @{ reviewers = @('manager') }
            InModuleScope 'Omnicit.EntraRBAC' -Parameters @{ Doc = $Doc } {
                param($Doc)
                $Result = Test-OERStructureSchema -Document $Doc
                $Result.Valid | Should -BeTrue
                $Finding = @($Result.Errors) | Where-Object { $_.Path -eq 'accessReviews[0].fallbackReviewers' }
                $Finding.Severity | Should -Be 'Warning'
            }
        }

        # The four cases below pin the WHOLE manager-requires-fallback predicate, because the
        # validator once classified a declared-EMPTY reviewers list as "uses the manager default"
        # via a middle 'Count -eq 0' clause. Sync-OERStructureAccessReview now reads a declared-empty
        # list as a SELF review on both the create and the update path, and a self review needs no
        # fallback, so that clause made the validator demand a fallback for a correct document.
        # Dropping it must not weaken the two cases that DO take the manager default: an omitted key
        # and an explicit null. Note the trap the deleted clause hid -- @($AR.reviewers) on a node
        # with no such property is @($null), whose Count is 1 and not 0, so the clause never carried
        # the absent case in the first place; the Test-HasProp clause does.
        # Each case matches the finding by a message fragment unique in the source file, so no other
        # rule's finding can satisfy the assertion.
        It 'does NOT demand a fallback when reviewers is declared EMPTY (a self review)' {
            $Doc = New-ArDoc -Extra @{ reviewers = @() }
            InModuleScope 'Omnicit.EntraRBAC' -Parameters @{ Doc = $Doc } {
                param($Doc)
                $Result = Test-OERStructureSchema -Document $Doc
                $Result.Valid | Should -BeTrue
                $Fallback = @($Result.Errors | Where-Object { $_.Message -match "requires 'fallbackReviewers'" })
                $Fallback.Count | Should -Be 0
            }
        }

        It 'still warns when reviewers is OMITTED entirely and no fallback is declared' {
            $Doc = New-ArDoc -Extra @{}
            InModuleScope 'Omnicit.EntraRBAC' -Parameters @{ Doc = $Doc } {
                param($Doc)
                $Result = Test-OERStructureSchema -Document $Doc
                $Result.Valid | Should -BeTrue
                $Fallback = @($Result.Errors | Where-Object { $_.Message -match "requires 'fallbackReviewers'" })
                $Fallback.Count      | Should -Be 1
                $Fallback[0].Severity | Should -Be 'Warning'
                $Fallback[0].Path     | Should -Be 'accessReviews[0].fallbackReviewers'
            }
        }

        It 'still warns when reviewers is an explicit null and no fallback is declared' {
            $Doc = New-ArDoc -Extra @{ reviewers = $null }
            InModuleScope 'Omnicit.EntraRBAC' -Parameters @{ Doc = $Doc } {
                param($Doc)
                $Result = Test-OERStructureSchema -Document $Doc
                $Result.Valid | Should -BeTrue
                $Fallback = @($Result.Errors | Where-Object { $_.Message -match "requires 'fallbackReviewers'" })
                $Fallback.Count      | Should -Be 1
                $Fallback[0].Severity | Should -Be 'Warning'
                $Fallback[0].Path     | Should -Be 'accessReviews[0].fallbackReviewers'
            }
        }

        It 'still warns when reviewers declares manager and no fallback is declared' {
            $Doc = New-ArDoc -Extra @{ reviewers = @('manager') }
            InModuleScope 'Omnicit.EntraRBAC' -Parameters @{ Doc = $Doc } {
                param($Doc)
                $Result = Test-OERStructureSchema -Document $Doc
                $Result.Valid | Should -BeTrue
                $Fallback = @($Result.Errors | Where-Object { $_.Message -match "requires 'fallbackReviewers'" })
                $Fallback.Count      | Should -Be 1
                $Fallback[0].Severity | Should -Be 'Warning'
                $Fallback[0].Path     | Should -Be 'accessReviews[0].fallbackReviewers'
            }
        }

        # The five cases below pin the FALLBACK half of the same predicate, which is the mirror image
        # of the reviewers half above: there a 'Count -eq 0' clause had to go, here one had to be
        # added. Test-HasProp counts a DECLARED but EMPTY fallbackReviewers array as declared, so the
        # validator used to pass "reviewers": ["manager"] alongside "fallbackReviewers": [] with zero
        # findings -- while Sync-OERStructureAccessReview collects its fallback reviewers under a bare
        # truthiness test, [bool]@() is $false, and it therefore reported Failed and created nothing
        # on every run, forever (verified by execution on both sides before the clause was written).
        # An empty fallback list genuinely is no fallback and Graph rejects a manager reviewer that
        # has none, so the document IS invalid and the offline gate is what had to learn to say so.
        # Each case matches the finding by a message fragment unique in the source file.
        It 'warns when fallbackReviewers is declared EMPTY beside a declared manager reviewer' {
            $Doc = New-ArDoc -Extra @{ reviewers = @('manager'); fallbackReviewers = @() }
            InModuleScope 'Omnicit.EntraRBAC' -Parameters @{ Doc = $Doc } {
                param($Doc)
                $Result = Test-OERStructureSchema -Document $Doc
                $Fallback = @($Result.Errors | Where-Object { $_.Message -match "requires 'fallbackReviewers'" })
                $Fallback.Count       | Should -Be 1
                $Fallback[0].Severity | Should -Be 'Warning'
                $Fallback[0].Path     | Should -Be 'accessReviews[0].fallbackReviewers'
            }
        }

        It 'warns when fallbackReviewers is declared EMPTY and reviewers is omitted (the manager default)' {
            $Doc = New-ArDoc -Extra @{ fallbackReviewers = @() }
            InModuleScope 'Omnicit.EntraRBAC' -Parameters @{ Doc = $Doc } {
                param($Doc)
                $Result = Test-OERStructureSchema -Document $Doc
                $Fallback = @($Result.Errors | Where-Object { $_.Message -match "requires 'fallbackReviewers'" })
                $Fallback.Count       | Should -Be 1
                $Fallback[0].Severity | Should -Be 'Warning'
                $Fallback[0].Path     | Should -Be 'accessReviews[0].fallbackReviewers'
            }
        }

        It 'does NOT warn when fallbackReviewers is declared NON-EMPTY beside a manager reviewer' {
            $Doc = New-ArDoc -Extra @{ reviewers = @('manager'); fallbackReviewers = @('anna@contoso.com') }
            InModuleScope 'Omnicit.EntraRBAC' -Parameters @{ Doc = $Doc } {
                param($Doc)
                $Result = Test-OERStructureSchema -Document $Doc
                $Result.Valid | Should -BeTrue
                $Fallback = @($Result.Errors | Where-Object { $_.Message -match "requires 'fallbackReviewers'" })
                $Fallback.Count | Should -Be 0
            }
        }

        It 'still warns when fallbackReviewers is OMITTED beside the manager default' {
            # The absent case is carried by Test-HasProp, never by the count: @($AR.fallbackReviewers)
            # on a node with no such property is @($null), whose Count is 1 and not 0.
            $Doc = New-ArDoc -Extra @{}
            InModuleScope 'Omnicit.EntraRBAC' -Parameters @{ Doc = $Doc } {
                param($Doc)
                $Result = Test-OERStructureSchema -Document $Doc
                $Fallback = @($Result.Errors | Where-Object { $_.Message -match "requires 'fallbackReviewers'" })
                $Fallback.Count       | Should -Be 1
                $Fallback[0].Severity | Should -Be 'Warning'
                $Fallback[0].Path     | Should -Be 'accessReviews[0].fallbackReviewers'
            }
        }

        It 'does NOT warn for a declared-empty reviewers self review with no fallbackReviewers at all' {
            # The regression guard for the whole change. Commit 36fdde7 deliberately made this
            # document valid; adding the fallback count clause must not take that back, because a
            # self review has no manager reviewer and so needs no fallback.
            $Doc = New-ArDoc -Extra @{ reviewers = @() }
            InModuleScope 'Omnicit.EntraRBAC' -Parameters @{ Doc = $Doc } {
                param($Doc)
                $Result = Test-OERStructureSchema -Document $Doc
                $Result.Valid | Should -BeTrue
                $Fallback = @($Result.Errors | Where-Object { $_.Message -match "requires 'fallbackReviewers'" })
                $Fallback.Count | Should -Be 0
            }
        }
    }

    Context 'unknown keys in the azure-arm sections' {
        It 'warns about an unsupported roleManagementPolicies key without failing validation' {
            InModuleScope $script:moduleName {
                $Doc = [PSCustomObject]@{
                    version = '1.0'
                    roleManagementPolicies = @([PSCustomObject]@{
                        scope = '/subscriptions/sub-1'; role = 'Owner'; notifications = @('a@b.c')
                    })
                }
                $Result = Test-OERStructureSchema -Document $Doc
                $Result.Valid | Should -BeTrue
                $Finding = @($Result.Errors) | Where-Object { $_.Path -eq 'roleManagementPolicies[0].notifications' }
                $Finding.Severity | Should -Be 'Warning'
                $Finding.Message  | Should -Match 'not applied'
            }
        }

        It 'warns about an unsupported roleAssignments key' {
            InModuleScope $script:moduleName {
                $Doc = [PSCustomObject]@{
                    version = '1.0'
                    roleAssignments = @([PSCustomObject]@{
                        scope = '/subscriptions/sub-1'; role = 'Reader'; principal = 'anna@contoso.com'
                        delegatedManagedIdentityResourceId = '/x'
                    })
                }
                $Result = Test-OERStructureSchema -Document $Doc
                $Result.Valid | Should -BeTrue
                @($Result.Errors).Path | Should -Contain 'roleAssignments[0].delegatedManagedIdentityResourceId'
            }
        }

        It 'does not warn about the id key stamped by Get-OERInventory -IncludeId' {
            InModuleScope $script:moduleName {
                $Doc = [PSCustomObject]@{
                    version = '1.0'
                    roleManagementPolicies = @([PSCustomObject]@{
                        scope = '/subscriptions/sub-1'; role = 'Owner'; id = '/providers/.../policies/p1'
                    })
                    roleAssignments = @([PSCustomObject]@{
                        scope = '/subscriptions/sub-1'; role = 'Reader'; principal = 'anna@contoso.com'; id = 'ra-1'
                    })
                }
                $Result = Test-OERStructureSchema -Document $Doc
                @($Result.Errors) | Should -BeNullOrEmpty
            }
        }
    }

    Context 'unknown keys in groups items and pimPolicy blocks' {
        It 'warns once per legacy pimPolicy field name at the flat root, with a did-you-mean hint, and stays Valid' {
            InModuleScope $script:moduleName {
                $Doc = [PSCustomObject]@{
                    version = '1.0'
                    groups  = @([PSCustomObject]@{
                        displayName = 'role_sec_core'
                        pimPolicy   = [PSCustomObject]@{
                            activationEnabledRules    = @('Justification')
                            activeEnabledRules        = @('Justification')
                            eligibleAlertRecipients   = @('person1@example.com')
                            activeAlertRecipients     = @('person1@example.com')
                            activationAlertRecipients = @('person1@example.com')
                        }
                    })
                }
                $Result = Test-OERStructureSchema -Document $Doc
                $Result.Valid | Should -BeTrue

                $LegacyKeys = @('activationEnabledRules', 'activeEnabledRules', 'eligibleAlertRecipients',
                    'activeAlertRecipients', 'activationAlertRecipients')
                foreach ($LegacyKey in $LegacyKeys) {
                    $Finding = @($Result.Errors | Where-Object { $_.Path -eq "groups[0].pimPolicy.$LegacyKey" })
                    $Finding.Count | Should -Be 1
                    $Finding[0].Severity | Should -Be 'Warning'
                }

                $ActivationFinding = @($Result.Errors | Where-Object { $_.Path -eq 'groups[0].pimPolicy.activationEnabledRules' })
                $ActivationFinding[0].Message | Should -Match ([regex]::Escape("Did you mean 'activationEnablement'?"))
            }
        }

        It 'warns about the same legacy names inside pimPolicy.owner at the owner path' {
            InModuleScope $script:moduleName {
                $Doc = [PSCustomObject]@{
                    version = '1.0'
                    groups  = @([PSCustomObject]@{
                        displayName = 'role_sec_core'
                        pimPolicy   = [PSCustomObject]@{
                            owner = [PSCustomObject]@{
                                activationEnabledRules = @('Justification')
                            }
                        }
                    })
                }
                $Result = Test-OERStructureSchema -Document $Doc
                $Finding = @($Result.Errors | Where-Object { $_.Path -eq 'groups[0].pimPolicy.owner.activationEnabledRules' })
                $Finding.Count | Should -Be 1
                $Finding[0].Severity | Should -Be 'Warning'
                $Finding[0].Message | Should -Match ([regex]::Escape("Did you mean 'activationEnablement'?"))
            }
        }

        It 'warns about an unknown group key without a hint' {
            InModuleScope $script:moduleName {
                $Doc = [PSCustomObject]@{
                    version = '1.0'
                    groups  = @([PSCustomObject]@{ displayName = 'role_sec_core'; colour = 'blue' })
                }
                $Result = Test-OERStructureSchema -Document $Doc
                $Finding = @($Result.Errors | Where-Object { $_.Path -eq 'groups[0].colour' })
                $Finding.Count | Should -Be 1
                $Finding[0].Severity | Should -Be 'Warning'
                $Finding[0].Message | Should -Not -Match 'Did you mean'
            }
        }

        It 'does not warn about id on the group, the pimPolicy root, or the member/owner blocks' {
            InModuleScope $script:moduleName {
                $Doc = [PSCustomObject]@{
                    version = '1.0'
                    groups  = @([PSCustomObject]@{
                        displayName = 'role_sec_core'
                        id          = 'grp-1'
                        pimPolicy   = [PSCustomObject]@{
                            id     = 'policy-1'
                            member = [PSCustomObject]@{ id = 'member-policy-1' }
                            owner  = [PSCustomObject]@{ id = 'owner-policy-1' }
                        }
                    })
                }
                $Result = Test-OERStructureSchema -Document $Doc
                @($Result.Errors | Where-Object { $_.Message -match 'not applied' }) | Should -BeNullOrEmpty
            }
        }

        It 'does not warn about any documented key on the group or a flat pimPolicy block' {
            InModuleScope $script:moduleName {
                $Doc = [PSCustomObject]@{
                    version = '1.0'
                    groups  = @([PSCustomObject]@{
                        displayName                   = 'role_sec_core'
                        roleAssignable                 = $true
                        dynamic                        = $false
                        description                    = 'x'
                        membershipRule                 = 'x'
                        membershipRuleProcessingState  = 'On'
                        mailNickname                   = 'rolesec-core'
                        administrativeUnit             = 'au_hr'
                        members                        = @('person1@example.com')
                        owners                          = @('person2@example.com')
                        eligibility                    = @([PSCustomObject]@{ principal = 'person3@example.com'; durationDays = 30; accessType = 'member' })
                        id                              = 'grp-1'
                        pimPolicy                       = [PSCustomObject]@{
                            activationMaxHours        = 4
                            authenticationContextId   = 'c1'
                            activationEnablement      = @('Justification')
                            allowPermanentEligibility = $false
                            eligibleDurationDays      = 30
                            allowPermanentActive      = $false
                            activeDurationDays        = 30
                            activeEnablement          = @('Justification')
                            notifications             = [PSCustomObject]@{
                                eligibleAlert   = @('person1@example.com')
                                activeAlert     = @('person1@example.com')
                                activationAlert = @('person1@example.com')
                            }
                            requireApproval           = $true
                            approvers                 = [PSCustomObject]@{
                                users  = @('person4@example.com')
                                groups = @('grp-approver-1')
                            }
                            id                        = 'policy-1'
                        }
                    })
                }
                $Result = Test-OERStructureSchema -Document $Doc
                @($Result.Errors | Where-Object { $_.Message -match 'not applied' }) | Should -BeNullOrEmpty
            }
        }

        It 'does not warn about any documented key in nested member/owner pimPolicy blocks' {
            InModuleScope $script:moduleName {
                function New-FullPimBlock {
                    [PSCustomObject]@{
                        activationMaxHours        = 4
                        authenticationContextId   = 'c1'
                        activationEnablement      = @('Justification')
                        allowPermanentEligibility = $false
                        eligibleDurationDays      = 30
                        allowPermanentActive      = $false
                        activeDurationDays        = 30
                        activeEnablement          = @('Justification')
                        notifications             = [PSCustomObject]@{
                            eligibleAlert   = @('person1@example.com')
                            activeAlert     = @('person1@example.com')
                            activationAlert = @('person1@example.com')
                        }
                        requireApproval           = $true
                        approvers                 = [PSCustomObject]@{
                            users  = @('person4@example.com')
                            groups = @('grp-approver-1')
                        }
                        id                        = 'member-policy-1'
                    }
                }
                $Doc = [PSCustomObject]@{
                    version = '1.0'
                    groups  = @([PSCustomObject]@{
                        displayName = 'role_sec_core'
                        pimPolicy   = [PSCustomObject]@{
                            id     = 'policy-1'
                            member = New-FullPimBlock
                            owner  = New-FullPimBlock
                        }
                    })
                }
                $Result = Test-OERStructureSchema -Document $Doc
                @($Result.Errors | Where-Object { $_.Message -match 'not applied' }) | Should -BeNullOrEmpty
            }
        }

        It 'flags mixing nested member with a flat pim field at the pimPolicy root' {
            InModuleScope $script:moduleName {
                $Doc = [PSCustomObject]@{
                    version = '1.0'
                    groups  = @([PSCustomObject]@{
                        displayName = 'role_sec_core'
                        pimPolicy   = [PSCustomObject]@{
                            activationEnablement = @('Justification')
                            member                = [PSCustomObject]@{ activationMaxHours = 4 }
                        }
                    })
                }
                $Result = Test-OERStructureSchema -Document $Doc
                $Finding = @($Result.Errors | Where-Object { $_.Path -eq 'groups[0].pimPolicy' -and $_.Message -match 'mixes flat and nested' })
                $Finding.Count | Should -Be 1
                $Finding[0].Severity | Should -Be 'Warning'
            }
        }

        It 'keeps the roleAssignments and roleManagementPolicies unknown-key messages byte-identical' {
            InModuleScope $script:moduleName {
                $Doc = [PSCustomObject]@{
                    version = '1.0'
                    roleAssignments = @([PSCustomObject]@{
                        scope = '/subscriptions/sub-1'; role = 'Reader'; principal = 'anna@contoso.com'
                        delegatedManagedIdentityResourceId = '/x'
                    })
                    roleManagementPolicies = @([PSCustomObject]@{
                        scope = '/subscriptions/sub-1'; role = 'Owner'; notifications = @('a@b.c')
                    })
                }
                $Result = Test-OERStructureSchema -Document $Doc

                $RAFinding = @($Result.Errors | Where-Object { $_.Path -eq 'roleAssignments[0].delegatedManagedIdentityResourceId' })
                $RAFinding[0].Message | Should -Be "Unknown key 'delegatedManagedIdentityResourceId' at roleAssignments[0] is not applied by Invoke-OERStructure and will be ignored."

                $RMPFinding = @($Result.Errors | Where-Object { $_.Path -eq 'roleManagementPolicies[0].notifications' })
                $RMPFinding[0].Message | Should -Be "Unknown key 'notifications' at roleManagementPolicies[0] is not applied by Invoke-OERStructure and will be ignored."
            }
        }
    }

    It 'reports no Error for a PascalCase-root document written by an earlier module version' {
        InModuleScope $script:moduleName {
            $Doc = Read-OERStructureDocument -Json @'
{
  "Version": "1.0",
  "Groups": [ { "displayName": "role_sec_identity_reader" } ],
  "RoleAssignments": []
}
'@
            $Result = Test-OERStructureSchema -Document $Doc
            @($Result.Errors | Where-Object { $_.Severity -eq 'Error' }).Count | Should -Be 0
            $Result.Valid | Should -Be $true
        }
    }
}

Describe 'Test-OERStructureSchema eligibility accessType' {
    It 'accepts accessType owner' {
        InModuleScope Omnicit.EntraRBAC {
            $Doc = '{ "version": "1", "groups": [ { "displayName": "g", "eligibility": [ { "principal": "person17@example.com", "accessType": "owner" } ] } ] }' | ConvertFrom-Json
            (Test-OERStructureSchema -Document $Doc).Valid | Should -BeTrue
        }
    }

    It 'accepts an eligibility entry with no accessType' {
        InModuleScope Omnicit.EntraRBAC {
            $Doc = '{ "version": "1", "groups": [ { "displayName": "g", "eligibility": [ { "principal": "person17@example.com" } ] } ] }' | ConvertFrom-Json
            (Test-OERStructureSchema -Document $Doc).Valid | Should -BeTrue
        }
    }

    It 'reports an Error for an invalid accessType' {
        InModuleScope Omnicit.EntraRBAC {
            $Doc = '{ "version": "1", "groups": [ { "displayName": "g", "eligibility": [ { "principal": "person17@example.com", "accessType": "admin" } ] } ] }' | ConvertFrom-Json
            $R = Test-OERStructureSchema -Document $Doc
            $R.Valid | Should -BeFalse
            ($R.Errors | Where-Object { $_.Path -eq 'groups[0].eligibility[0].accessType' }).Message |
                Should -BeLike "*must be one of: member, owner*"
        }
    }
}

Describe 'Test-OERStructureSchema administrative unit dynamic membership' {
    It 'accepts a dynamic unit with a rule and an On processing state, with no finding raised for it' {
        InModuleScope Omnicit.EntraRBAC {
            $Doc = '{ "version": "1", "administrativeUnits": [ { "displayName": "au", "dynamic": true, "membershipRule": "(user.country -eq \"SE\")", "membershipRuleProcessingState": "On", "hiddenMembership": true } ] }' | ConvertFrom-Json
            $R = Test-OERStructureSchema -Document $Doc
            $R.Valid | Should -BeTrue
            ($R.Errors | Where-Object { $_.Path -eq 'administrativeUnits[0].membershipRuleProcessingState' }) | Should -BeNullOrEmpty
            ($R.Errors | Where-Object { $_.Path -eq 'administrativeUnits[0].membershipRule' }) | Should -BeNullOrEmpty
        }
    }

    It 'reports an Error for an invalid membershipRuleProcessingState' {
        InModuleScope Omnicit.EntraRBAC {
            $Doc = '{ "version": "1", "administrativeUnits": [ { "displayName": "au", "dynamic": true, "membershipRule": "x", "membershipRuleProcessingState": "Off" } ] }' | ConvertFrom-Json
            $R = Test-OERStructureSchema -Document $Doc
            $R.Valid | Should -BeFalse
            ($R.Errors | Where-Object { $_.Path -eq 'administrativeUnits[0].membershipRuleProcessingState' }).Message |
                Should -BeLike '*must be one of: On, Paused*'
        }
    }

    # The two tests above alone are not discriminating: pre-Task-7 code silently ignores unknown
    # per-item keys, so a document that never triggers a finding elsewhere is also "Valid" with no
    # findings pre-change. This test proves the enum check is actually evaluated PER ITEM (not
    # globally) by mixing a valid and an invalid unit in the same document: pre-change, neither item
    # produces a finding and $R.Valid stays $true, so this fails against the pre-change validator.
    It 'evaluates membershipRuleProcessingState per item: a valid unit stays clean while an invalid one in the same document is flagged' {
        InModuleScope Omnicit.EntraRBAC {
            $Doc = '{ "version": "1", "administrativeUnits": [ { "displayName": "au-valid", "dynamic": true, "membershipRule": "x", "membershipRuleProcessingState": "On" }, { "displayName": "au-invalid", "dynamic": true, "membershipRule": "y", "membershipRuleProcessingState": "Off" } ] }' | ConvertFrom-Json
            $R = Test-OERStructureSchema -Document $Doc
            $R.Valid | Should -BeFalse
            ($R.Errors | Where-Object { $_.Path -eq 'administrativeUnits[0].membershipRuleProcessingState' }) | Should -BeNullOrEmpty
            ($R.Errors | Where-Object { $_.Path -eq 'administrativeUnits[1].membershipRuleProcessingState' }).Message |
                Should -BeLike '*must be one of: On, Paused*'
        }
    }

    # Stays a Warning (not an Error) on purpose: an Error aborts the WHOLE document before any section
    # is written, and one case does apply cleanly -- a unit that is already dynamic whose rule is managed
    # outside the document. The message has to state the real consequences instead.
    It 'warns but stays valid when dynamic is true with no membershipRule' {
        InModuleScope Omnicit.EntraRBAC {
            $Doc = '{ "version": "1", "administrativeUnits": [ { "displayName": "au", "dynamic": true } ] }' | ConvertFrom-Json
            $R = Test-OERStructureSchema -Document $Doc
            $R.Valid | Should -BeTrue
            $Finding = $R.Errors | Where-Object { $_.Path -eq 'administrativeUnits[0].membershipRule' }
            $Finding.Severity | Should -Be 'Warning'
            # The apply no longer "creates it with an empty rule" -- it fails.
            $Finding.Message | Should -Not -BeLike '*created with an empty rule*'
            $Finding.Message | Should -BeLike '*Failed*'
        }
    }

    # A string "false" is truthy under a bare [bool] cast, so an unvalidated string here would flip the
    # create and update handlers to opposite outcomes (see Sync-OERStructureAdministrativeUnit).
    # These three catch the bad type offline, before it ever reaches a handler.
    It 'reports an Error for a string "false" hiddenMembership' {
        InModuleScope Omnicit.EntraRBAC {
            $Doc = '{ "version": "1", "administrativeUnits": [ { "displayName": "au", "hiddenMembership": "false" } ] }' | ConvertFrom-Json
            $R = Test-OERStructureSchema -Document $Doc
            $R.Valid | Should -BeFalse
            ($R.Errors | Where-Object { $_.Path -eq 'administrativeUnits[0].hiddenMembership' }).Message |
                Should -BeLike '*must be a boolean*'
        }
    }

    It 'reports an Error for a string dynamic' {
        InModuleScope Omnicit.EntraRBAC {
            $Doc = '{ "version": "1", "administrativeUnits": [ { "displayName": "au", "dynamic": "true" } ] }' | ConvertFrom-Json
            $R = Test-OERStructureSchema -Document $Doc
            $R.Valid | Should -BeFalse
            ($R.Errors | Where-Object { $_.Path -eq 'administrativeUnits[0].dynamic' }).Message |
                Should -BeLike '*must be a boolean*'
        }
    }

    It 'reports an Error for a string restricted' {
        InModuleScope Omnicit.EntraRBAC {
            $Doc = '{ "version": "1", "administrativeUnits": [ { "displayName": "au", "restricted": "true" } ] }' | ConvertFrom-Json
            $R = Test-OERStructureSchema -Document $Doc
            $R.Valid | Should -BeFalse
            ($R.Errors | Where-Object { $_.Path -eq 'administrativeUnits[0].restricted' }).Message |
                Should -BeLike '*must be a boolean*'
        }
    }

    It 'accepts boolean dynamic, restricted and hiddenMembership with no boolean-type finding' {
        InModuleScope Omnicit.EntraRBAC {
            $Doc = '{ "version": "1", "administrativeUnits": [ { "displayName": "au", "dynamic": false, "restricted": false, "hiddenMembership": false } ] }' | ConvertFrom-Json
            $R = Test-OERStructureSchema -Document $Doc
            ($R.Errors | Where-Object { $_.Message -like '*must be a boolean*' }) | Should -BeNullOrEmpty
        }
    }
}

Describe 'Test-OERStructureSchema access package hidden' {
    It 'accepts a boolean hidden' {
        InModuleScope Omnicit.EntraRBAC {
            $Doc = '{ "version": "1", "accessPackages": [ { "displayName": "ap", "catalog": "c", "hidden": true } ] }' | ConvertFrom-Json
            ((Test-OERStructureSchema -Document $Doc).Errors | Where-Object { $_.Path -like '*hidden*' }) | Should -BeNullOrEmpty
        }
    }

    It 'reports an Error for a non-boolean hidden' {
        InModuleScope Omnicit.EntraRBAC {
            $Doc = '{ "version": "1", "accessPackages": [ { "displayName": "ap", "catalog": "c", "hidden": "yes" } ] }' | ConvertFrom-Json
            $R = Test-OERStructureSchema -Document $Doc
            $R.Valid | Should -BeFalse
            ($R.Errors | Where-Object { $_.Path -eq 'accessPackages[0].hidden' }).Message | Should -BeLike '*must be a boolean*'
        }
    }
}

Describe 'Test-OERStructureSchema role assignment condition' {
    It 'accepts a condition with a conditionVersion' {
        InModuleScope Omnicit.EntraRBAC {
            $Doc = '{ "version": "1", "roleAssignments": [ { "scope": "/subscriptions/s1", "role": "Reader", "principal": "person17@example.com", "condition": "x", "conditionVersion": "2.0" } ] }' | ConvertFrom-Json
            (Test-OERStructureSchema -Document $Doc).Valid | Should -BeTrue
        }
    }

    It 'warns when a condition is declared without a conditionVersion' {
        InModuleScope Omnicit.EntraRBAC {
            $Doc = '{ "version": "1", "roleAssignments": [ { "scope": "/subscriptions/s1", "role": "Reader", "principal": "person17@example.com", "condition": "x" } ] }' | ConvertFrom-Json
            $R = Test-OERStructureSchema -Document $Doc
            $R.Valid | Should -BeTrue
            ($R.Errors | Where-Object { $_.Path -eq 'roleAssignments[0].conditionVersion' }).Severity | Should -Be 'Warning'
        }
    }

    It 'reports an Error when conditionVersion is declared without a condition' {
        InModuleScope Omnicit.EntraRBAC {
            $Doc = '{ "version": "1", "roleAssignments": [ { "scope": "/subscriptions/s1", "role": "Reader", "principal": "person17@example.com", "conditionVersion": "2.0" } ] }' | ConvertFrom-Json
            $R = Test-OERStructureSchema -Document $Doc
            $R.Valid | Should -BeFalse
            ($R.Errors | Where-Object { $_.Path -eq 'roleAssignments[0].conditionVersion' }).Message | Should -BeLike "*requires a 'condition'*"
        }
    }
}

Describe 'Test-OERStructureSchema catalog externallyVisible' {
    It 'accepts a catalog declaring externallyVisible as a boolean' {
        InModuleScope Omnicit.EntraRBAC {
            $Doc = [PSCustomObject]@{
                version  = '1.0'
                catalogs = @([PSCustomObject]@{ displayName = 'CAT-Core'; externallyVisible = $true })
            }
            (Test-OERStructureSchema -Document $Doc).Valid | Should -BeTrue
        }
    }

    It 'rejects a non-boolean externallyVisible' {
        InModuleScope Omnicit.EntraRBAC {
            $Doc = [PSCustomObject]@{
                version  = '1.0'
                catalogs = @([PSCustomObject]@{ displayName = 'CAT-Core'; externallyVisible = 'yes' })
            }
            $Result = Test-OERStructureSchema -Document $Doc
            $Result.Valid | Should -BeFalse
            @($Result.Errors).Path | Should -Contain 'catalogs[0].externallyVisible'
        }
    }
}

Describe 'Test-OERStructureSchema catalog resource url' {
    It 'accepts a SharePointSite resource declared with a url' {
        InModuleScope Omnicit.EntraRBAC {
            $Doc = [PSCustomObject]@{
                version  = '1.0'
                catalogs = @([PSCustomObject]@{
                    displayName = 'CAT-Core'
                    resources   = @([PSCustomObject]@{
                        name = 'Finance'; type = 'SharePointSite'
                        url  = 'https://contoso.sharepoint.com/sites/finance'
                    })
                })
            }
            (Test-OERStructureSchema -Document $Doc).Valid | Should -BeTrue
        }
    }

    It 'rejects a non-string url' {
        InModuleScope Omnicit.EntraRBAC {
            $Doc = [PSCustomObject]@{
                version  = '1.0'
                catalogs = @([PSCustomObject]@{
                    displayName = 'CAT-Core'
                    resources   = @([PSCustomObject]@{ name = 'Finance'; type = 'SharePointSite'; url = @(1, 2) })
                })
            }
            $Result = Test-OERStructureSchema -Document $Doc
            $Result.Valid | Should -BeFalse
            @($Result.Errors).Path | Should -Contain 'catalogs[0].resources[0].url'
        }
    }

    It 'warns when a SharePointSite resource has neither a url nor a URL-shaped name' {
        InModuleScope Omnicit.EntraRBAC {
            $Doc = [PSCustomObject]@{
                version  = '1.0'
                catalogs = @([PSCustomObject]@{
                    displayName = 'CAT-Core'
                    resources   = @([PSCustomObject]@{ name = 'Finance'; type = 'SharePointSite' })
                })
            }
            $Result = Test-OERStructureSchema -Document $Doc
            $Result.Valid | Should -BeTrue
            $Warning = @($Result.Errors) | Where-Object { $_.Path -eq 'catalogs[0].resources[0].url' }
            $Warning.Severity | Should -Be 'Warning'
        }
    }
}

Describe 'Test-OERStructureSchema role management policy approver precedence' {
    It 'warns when requireApproval is false but approvers are declared' {
        InModuleScope Omnicit.EntraRBAC {
            $Doc = [PSCustomObject]@{
                version                = '1.0'
                roleManagementPolicies = @([PSCustomObject]@{
                    scope           = '/subscriptions/sub-1'
                    role            = 'Contributor'
                    requireApproval = $false
                    approvers       = [PSCustomObject]@{ groups = @('sec-approvers') }
                })
            }
            $Result = Test-OERStructureSchema -Document $Doc
            $Result.Valid | Should -BeTrue
            $Finding = @($Result.Errors) | Where-Object { $_.Path -eq 'roleManagementPolicies[0].approvers' }
            $Finding | Should -Not -BeNullOrEmpty
            $Finding.Severity | Should -Be 'Warning'
            $Finding.Message | Should -Match 'requireApproval'
        }
    }

    It 'does not warn when requireApproval is true' {
        InModuleScope Omnicit.EntraRBAC {
            $Doc = [PSCustomObject]@{
                version                = '1.0'
                roleManagementPolicies = @([PSCustomObject]@{
                    scope = '/subscriptions/sub-1'; role = 'Contributor'; requireApproval = $true
                    approvers = [PSCustomObject]@{ groups = @('sec-approvers') }
                })
            }
            @((Test-OERStructureSchema -Document $Doc).Errors) |
                Where-Object { $_.Path -eq 'roleManagementPolicies[0].approvers' } |
                Should -BeNullOrEmpty
        }
    }

    It 'does not warn when the approvers block is empty' {
        InModuleScope Omnicit.EntraRBAC {
            $Doc = [PSCustomObject]@{
                version                = '1.0'
                roleManagementPolicies = @([PSCustomObject]@{
                    scope = '/subscriptions/sub-1'; role = 'Contributor'; requireApproval = $false
                    approvers = [PSCustomObject]@{ groups = @() }
                })
            }
            @((Test-OERStructureSchema -Document $Doc).Errors) |
                Where-Object { $_.Path -eq 'roleManagementPolicies[0].approvers' } |
                Should -BeNullOrEmpty
        }
    }
}

Describe 'Test-OERStructureSchema enum casing' {
    It 'accepts a non-canonically cased enum value without an Error' {
        InModuleScope $script:moduleName {
            # ConvertFrom-Json, not Read-OERStructureDocument: Task 6 makes the reader normalize, and
            # a test that routes through it would stop exercising the raw casing it is named after.
            $Doc = '{ "version": "1.0", "roleAssignments": [ { "scope": "/subscriptions/x", "role": "Reader", "principal": "p", "principalType": "GROUP" } ] }' | ConvertFrom-Json
            $Result = Test-OERStructureSchema -Document $Doc
            @($Result.Errors | Where-Object { $_.Severity -eq 'Error' }).Count | Should -Be 0
        }
    }

    It 'warns that a non-canonically cased enum value fails a draft-07 validator, naming the canonical spelling' {
        InModuleScope $script:moduleName {
            # Read-OERStructureDocument normalizes, so build the document object directly to reach
            # the validator with the raw casing a hand-authored or LLM-authored file would carry.
            $Doc = '{ "version": "1.0", "administrativeUnits": [ { "displayName": "au1", "membershipRuleProcessingState": "paused" } ] }' | ConvertFrom-Json
            $Result = Test-OERStructureSchema -Document $Doc
            $Warnings = @($Result.Errors | Where-Object { $_.Severity -eq 'Warning' -and $_.Path -eq 'administrativeUnits[0].membershipRuleProcessingState' })
            $Warnings.Count | Should -Be 1
            $Warnings[0].Message | Should -Match "canonical spelling is 'Paused'"
            $Warnings[0].Message | Should -Match 'case-sensitively'
        }
    }

    It 'does not warn when the casing is already canonical' {
        InModuleScope $script:moduleName {
            $Doc = '{ "version": "1.0", "administrativeUnits": [ { "displayName": "au1", "membershipRuleProcessingState": "Paused" } ] }' | ConvertFrom-Json
            $Result = Test-OERStructureSchema -Document $Doc
            @($Result.Errors | Where-Object { $_.Path -eq 'administrativeUnits[0].membershipRuleProcessingState' }).Count | Should -Be 0
        }
    }

    It 'still reports an Error for a value that is not a member of the enum at all' {
        InModuleScope $script:moduleName {
            $Doc = '{ "version": "1.0", "administrativeUnits": [ { "displayName": "au1", "membershipRuleProcessingState": "Halted" } ] }' | ConvertFrom-Json
            $Result = Test-OERStructureSchema -Document $Doc
            $Errors = @($Result.Errors | Where-Object { $_.Severity -eq 'Error' -and $_.Path -eq 'administrativeUnits[0].membershipRuleProcessingState' })
            $Errors.Count | Should -Be 1
            $Errors[0].Message | Should -Match 'must be one of: On, Paused'
        }
    }

    It 'warns on a non-canonically cased value inside an enablement array' {
        InModuleScope $script:moduleName {
            $Doc = '{ "version": "1.0", "groups": [ { "displayName": "g1", "pimPolicy": { "activationEnablement": [ "justification" ] } } ] }' | ConvertFrom-Json
            $Result = Test-OERStructureSchema -Document $Doc
            @($Result.Errors | Where-Object { $_.Severity -eq 'Error' }).Count | Should -Be 0
            $Warnings = @($Result.Errors | Where-Object { $_.Severity -eq 'Warning' -and $_.Message -match "canonical spelling is 'Justification'" })
            $Warnings.Count | Should -Be 1
        }
    }
}

Describe 'Test-OERStructureSchema group pimPolicy MFA/auth-context warning' {
    It 'warns when a group declares both an authentication context and MFA on activation' {
        InModuleScope $script:moduleName {
            $Doc = [pscustomobject]@{
                groups = @(
                    [pscustomobject]@{
                        displayName = 'g1'
                        pimPolicy   = [pscustomobject]@{
                            authenticationContextId = 'c1'
                            activationEnablement    = @('MultiFactorAuthentication', 'Justification')
                        }
                    }
                )
            }
            $F = @((Test-OERStructureSchema -Document $Doc).Errors)
            $Hit = @($F | Where-Object { $_.Message -match 'mutually exclusive' -and $_.Section -eq 'groups' })
            $Hit.Count | Should -Be 1
            $Hit[0].Severity | Should -Be 'Warning'
        }
    }

    It 'does not warn when only one of the two is declared' {
        InModuleScope $script:moduleName {
            $Doc = [pscustomobject]@{
                groups = @([pscustomobject]@{ displayName = 'g1'; pimPolicy = [pscustomobject]@{ authenticationContextId = 'c1' } })
            }
            @((Test-OERStructureSchema -Document $Doc).Errors | Where-Object { $_.Message -match 'mutually exclusive' }).Count | Should -Be 0
        }
    }

    It 'warns for the nested member form, naming the member path' {
        InModuleScope $script:moduleName {
            $Doc = [pscustomobject]@{
                groups = @(
                    [pscustomobject]@{
                        displayName = 'g1'
                        pimPolicy   = [pscustomobject]@{
                            member = [pscustomobject]@{
                                authenticationContextId = 'c1'
                                activationEnablement    = @('MultiFactorAuthentication')
                            }
                        }
                    }
                )
            }
            $Hit = @((Test-OERStructureSchema -Document $Doc).Errors | Where-Object { $_.Message -match 'mutually exclusive' })
            $Hit.Count | Should -Be 1
            $Hit[0].Path | Should -Be 'groups[0].pimPolicy.member'
        }
    }

    It 'warns for the nested owner form, naming the owner path' {
        InModuleScope $script:moduleName {
            $Doc = [pscustomobject]@{
                groups = @(
                    [pscustomobject]@{
                        displayName = 'g1'
                        pimPolicy   = [pscustomobject]@{
                            owner = [pscustomobject]@{
                                authenticationContextId = 'c1'
                                activationEnablement    = @('MultiFactorAuthentication')
                            }
                        }
                    }
                )
            }
            $Hit = @((Test-OERStructureSchema -Document $Doc).Errors | Where-Object { $_.Message -match 'mutually exclusive' })
            $Hit.Count | Should -Be 1
            $Hit[0].Path | Should -Be 'groups[0].pimPolicy.owner'
        }
    }

    It 'does not warn when authenticationContextId is an explicit empty string (the documented disable value)' {
        InModuleScope $script:moduleName {
            $Doc = [pscustomobject]@{
                groups = @(
                    [pscustomobject]@{
                        displayName = 'g1'
                        pimPolicy   = [pscustomobject]@{
                            authenticationContextId = ''
                            activationEnablement    = @('MultiFactorAuthentication')
                        }
                    }
                )
            }
            @((Test-OERStructureSchema -Document $Doc).Errors | Where-Object { $_.Message -match 'mutually exclusive' }).Count | Should -Be 0
        }
    }

    It 'does not warn when authenticationContextId is an explicit JSON null (undeclared)' {
        InModuleScope $script:moduleName {
            $Doc = '{ "version": "1.0", "groups": [ { "displayName": "g1", "pimPolicy": { "authenticationContextId": null, "activationEnablement": [ "MultiFactorAuthentication" ] } } ] }' | ConvertFrom-Json
            @((Test-OERStructureSchema -Document $Doc).Errors | Where-Object { $_.Message -match 'mutually exclusive' }).Count | Should -Be 0
        }
    }
}

Describe 'Test-OERStructureSchema group pimPolicy approval' {
    It 'flags a non-boolean requireApproval on the flat form' {
        InModuleScope $script:moduleName {
            $Doc = [PSCustomObject]@{
                groups = @([PSCustomObject]@{
                    displayName = 'g1'
                    pimPolicy   = [PSCustomObject]@{ requireApproval = 'yes' }
                })
            }
            $Result = Test-OERStructureSchema -Document $Doc
            $Result.Valid | Should -BeFalse
            $Hit = @($Result.Errors) | Where-Object { $_.Path -eq 'groups[0].pimPolicy.requireApproval' -and $_.Severity -eq 'Error' }
            $Hit.Count | Should -Be 1
            $Hit[0].Message | Should -Be "'requireApproval' at groups[0].pimPolicy must be a boolean."
        }
    }

    It 'flags a non-boolean requireApproval on pimPolicy.owner' {
        InModuleScope $script:moduleName {
            $Doc = [PSCustomObject]@{
                groups = @([PSCustomObject]@{
                    displayName = 'g1'
                    pimPolicy   = [PSCustomObject]@{
                        owner = [PSCustomObject]@{ requireApproval = 'yes' }
                    }
                })
            }
            $Result = Test-OERStructureSchema -Document $Doc
            $Result.Valid | Should -BeFalse
            $Hit = @($Result.Errors) | Where-Object { $_.Path -eq 'groups[0].pimPolicy.owner.requireApproval' -and $_.Severity -eq 'Error' }
            $Hit.Count | Should -Be 1
            $Hit[0].Message | Should -Be "'requireApproval' at groups[0].pimPolicy.owner must be a boolean."
        }
    }

    It 'flags a non-object approvers block on the flat form' {
        InModuleScope $script:moduleName {
            $Doc = [PSCustomObject]@{
                groups = @([PSCustomObject]@{
                    displayName = 'g1'
                    pimPolicy   = [PSCustomObject]@{ approvers = 'sec-approvers' }
                })
            }
            $Result = Test-OERStructureSchema -Document $Doc
            $Result.Valid | Should -BeFalse
            $Hit = @($Result.Errors) | Where-Object { $_.Path -eq 'groups[0].pimPolicy.approvers' -and $_.Severity -eq 'Error' }
            $Hit.Count | Should -Be 1
            $Hit[0].Message | Should -Be "'approvers' at groups[0].pimPolicy must be an object with optional users and groups arrays."
        }
    }

    It 'flags a non-object approvers block on pimPolicy.owner' {
        InModuleScope $script:moduleName {
            $Doc = [PSCustomObject]@{
                groups = @([PSCustomObject]@{
                    displayName = 'g1'
                    pimPolicy   = [PSCustomObject]@{
                        owner = [PSCustomObject]@{ approvers = 'sec-approvers' }
                    }
                })
            }
            $Result = Test-OERStructureSchema -Document $Doc
            $Result.Valid | Should -BeFalse
            $Hit = @($Result.Errors) | Where-Object { $_.Path -eq 'groups[0].pimPolicy.owner.approvers' -and $_.Severity -eq 'Error' }
            $Hit.Count | Should -Be 1
            $Hit[0].Message | Should -Be "'approvers' at groups[0].pimPolicy.owner must be an object with optional users and groups arrays."
        }
    }

    It 'flags a non-array approvers.users on the flat form' {
        InModuleScope $script:moduleName {
            $Doc = [PSCustomObject]@{
                groups = @([PSCustomObject]@{
                    displayName = 'g1'
                    pimPolicy   = [PSCustomObject]@{
                        approvers = [PSCustomObject]@{ users = 'anna@contoso.com' }
                    }
                })
            }
            $Result = Test-OERStructureSchema -Document $Doc
            $Result.Valid | Should -BeFalse
            $Hit = @($Result.Errors) | Where-Object { $_.Path -eq 'groups[0].pimPolicy.approvers.users' -and $_.Severity -eq 'Error' }
            $Hit.Count | Should -Be 1
            $Hit[0].Message | Should -Be "'approvers.users' at groups[0].pimPolicy must be an array."
        }
    }

    It 'flags a non-array approvers.groups on pimPolicy.owner' {
        InModuleScope $script:moduleName {
            $Doc = [PSCustomObject]@{
                groups = @([PSCustomObject]@{
                    displayName = 'g1'
                    pimPolicy   = [PSCustomObject]@{
                        owner = [PSCustomObject]@{
                            approvers = [PSCustomObject]@{ groups = 'sec-approvers' }
                        }
                    }
                })
            }
            $Result = Test-OERStructureSchema -Document $Doc
            $Result.Valid | Should -BeFalse
            $Hit = @($Result.Errors) | Where-Object { $_.Path -eq 'groups[0].pimPolicy.owner.approvers.groups' -and $_.Severity -eq 'Error' }
            $Hit.Count | Should -Be 1
            $Hit[0].Message | Should -Be "'approvers.groups' at groups[0].pimPolicy.owner must be an array."
        }
    }

    It 'warns when requireApproval is false but approvers are declared on the flat form' {
        InModuleScope $script:moduleName {
            $Doc = [PSCustomObject]@{
                version = '1.0'
                groups  = @([PSCustomObject]@{
                    displayName = 'g1'
                    pimPolicy   = [PSCustomObject]@{
                        requireApproval = $false
                        approvers       = [PSCustomObject]@{ groups = @('sec-approvers') }
                    }
                })
            }
            $Result = Test-OERStructureSchema -Document $Doc
            $Result.Valid | Should -BeTrue
            $Finding = @($Result.Errors) | Where-Object { $_.Path -eq 'groups[0].pimPolicy.approvers' }
            $Finding | Should -Not -BeNullOrEmpty
            $Finding.Severity | Should -Be 'Warning'
            $Finding.Message | Should -Be "'requireApproval' is false at groups[0].pimPolicy, so the declared 'approvers' are ignored; requireApproval takes precedence and the approvers are not written. Set 'requireApproval' to true to apply them, or drop the approvers block."
        }
    }

    It 'warns when requireApproval is false but approvers are declared on pimPolicy.owner' {
        InModuleScope $script:moduleName {
            $Doc = [PSCustomObject]@{
                version = '1.0'
                groups  = @([PSCustomObject]@{
                    displayName = 'g1'
                    pimPolicy   = [PSCustomObject]@{
                        owner = [PSCustomObject]@{
                            requireApproval = $false
                            approvers       = [PSCustomObject]@{ users = @('anna@contoso.com') }
                        }
                    }
                })
            }
            $Result = Test-OERStructureSchema -Document $Doc
            $Result.Valid | Should -BeTrue
            $Finding = @($Result.Errors) | Where-Object { $_.Path -eq 'groups[0].pimPolicy.owner.approvers' }
            $Finding | Should -Not -BeNullOrEmpty
            $Finding.Severity | Should -Be 'Warning'
            $Finding.Message | Should -Match 'requireApproval'
        }
    }

    It 'does not warn when requireApproval is true' {
        InModuleScope $script:moduleName {
            $Doc = [PSCustomObject]@{
                groups = @([PSCustomObject]@{
                    displayName = 'g1'
                    pimPolicy   = [PSCustomObject]@{
                        requireApproval = $true
                        approvers       = [PSCustomObject]@{ groups = @('sec-approvers') }
                    }
                })
            }
            @((Test-OERStructureSchema -Document $Doc).Errors) |
                Where-Object { $_.Path -eq 'groups[0].pimPolicy.approvers' } |
                Should -BeNullOrEmpty
        }
    }

    It 'does not warn when the approvers block is empty' {
        InModuleScope $script:moduleName {
            $Doc = [PSCustomObject]@{
                groups = @([PSCustomObject]@{
                    displayName = 'g1'
                    pimPolicy   = [PSCustomObject]@{
                        requireApproval = $false
                        approvers       = [PSCustomObject]@{ groups = @() }
                    }
                })
            }
            @((Test-OERStructureSchema -Document $Doc).Errors) |
                Where-Object { $_.Path -eq 'groups[0].pimPolicy.approvers' } |
                Should -BeNullOrEmpty
        }
    }

    It 'gives no finding for a fully valid pimPolicy approval block' {
        InModuleScope $script:moduleName {
            $Doc = [PSCustomObject]@{
                groups = @([PSCustomObject]@{
                    displayName = 'g1'
                    pimPolicy   = [PSCustomObject]@{
                        member = [PSCustomObject]@{
                            requireApproval = $true
                            approvers       = [PSCustomObject]@{ users = @('anna@contoso.com'); groups = @('sec-approvers') }
                        }
                        owner  = [PSCustomObject]@{ requireApproval = $false }
                    }
                })
            }
            $Result = Test-OERStructureSchema -Document $Doc
            @($Result.Errors | Where-Object { $_.Path -like 'groups[0].pimPolicy*' }) | Should -BeNullOrEmpty
        }
    }
}

Describe 'Test-OERStructureSchema accessPackages requireApproval vs empty approvalStages warning' {
    # Two mutually exclusive Warnings live on this path, so every assertion below filters on the
    # phrase unique to ONE of them, never on a phrase both could produce:
    #   'declared as an empty array'  -> the self-contradictory requireApproval:true document
    #   'clears every approval stage' -> the emptied stages with an approval flag left in force
    It 'warns, without failing validation, when requireApproval is true and approvalStages is an empty array' {
        InModuleScope $script:moduleName {
            $Doc = '{ "version": "1.0", "accessPackages": [ { "displayName": "ap1", "catalog": "cat1", "assignmentPolicies": [ { "displayName": "p1", "requireApproval": true, "approvalStages": [] } ] } ] }' | ConvertFrom-Json
            $V = Test-OERStructureSchema -Document $Doc
            $Hit = @($V.Errors | Where-Object { $_.Message -match 'declared as an empty array' })
            $Hit.Count | Should -Be 1
            $Hit[0].Severity | Should -BeExactly 'Warning'
            $Hit[0].Section | Should -BeExactly 'accessPackages'
            $Hit[0].Item | Should -BeExactly 'ap1'
            $Hit[0].Path | Should -BeExactly 'accessPackages[0].assignmentPolicies[0].approvalStages'
            # Both keys must be named, so the operator can act on the finding without opening the source.
            $Hit[0].Message | Should -Match "requireApproval"
            $Hit[0].Message | Should -Match "approvalStages"
            # A Warning must never fail the document: the apply still runs.
            $V.Valid | Should -BeTrue
            @($V.Errors | Where-Object { $_.Severity -eq 'Error' }).Count | Should -Be 0
        }
    }

    It 'names the MEASURED outcome -- Graph refuses the write, the policy is Failed and unchanged -- not a written dead policy' {
        InModuleScope $script:moduleName {
            # Live-corrected: the old wording claimed the policy was WRITTEN with approval required and
            # no approver stages. Graph refuses the PUT with InvalidApprovalStages and the policy is left
            # completely unchanged, so the document reports Failed on every run and never converges.
            $Doc = '{ "version": "1.0", "accessPackages": [ { "displayName": "ap1", "catalog": "cat1", "assignmentPolicies": [ { "displayName": "p1", "requireApproval": true, "approvalStages": [] } ] } ] }' | ConvertFrom-Json
            $Hit = @((Test-OERStructureSchema -Document $Doc).Errors | Where-Object { $_.Message -match 'declared as an empty array' })
            $Hit.Count | Should -Be 1
            $Hit[0].Message | Should -Match 'InvalidApprovalStages'
            $Hit[0].Message | Should -Match 'Failed'
            $Hit[0].Message | Should -Match 'unchanged'
            $Hit[0].Message | Should -Match 'never converges'
            # The old, disproved claim must not survive anywhere in the text.
            $Hit[0].Message | Should -Not -Match 'takes precedence over the stage count'
            $Hit[0].Message | Should -Not -Match 'no request can ever be approved'
            # The remedy sentence is unchanged.
            $Hit[0].Message | Should -Match "Add at least one entry to 'approvalStages'"
        }
    }

    It 'does not warn when requireApproval is true and approvalStages is NON-empty' {
        InModuleScope $script:moduleName {
            $Doc = '{ "version": "1.0", "accessPackages": [ { "displayName": "ap1", "catalog": "cat1", "assignmentPolicies": [ { "displayName": "p1", "requireApproval": true, "approvalStages": [ { "durationDays": 7, "manager": true } ] } ] } ] }' | ConvertFrom-Json
            $V = Test-OERStructureSchema -Document $Doc
            @($V.Errors | Where-Object { $_.Message -match 'declared as an empty array' }).Count | Should -Be 0
            @($V.Errors | Where-Object { $_.Message -match 'clears every approval stage' }).Count | Should -Be 0
        }
    }

    It 'does not raise the requireApproval-true warning when approvalStages is an empty array and requireApproval is not declared' {
        InModuleScope $script:moduleName {
            $Doc = '{ "version": "1.0", "accessPackages": [ { "displayName": "ap1", "catalog": "cat1", "assignmentPolicies": [ { "displayName": "p1", "approvalStages": [] } ] } ] }' | ConvertFrom-Json
            $V = Test-OERStructureSchema -Document $Doc
            @($V.Errors | Where-Object { $_.Message -match 'declared as an empty array' }).Count | Should -Be 0
        }
    }

    It 'does not raise the requireApproval-true warning when approvalStages is an empty array and requireApproval is false' {
        InModuleScope $script:moduleName {
            $Doc = '{ "version": "1.0", "accessPackages": [ { "displayName": "ap1", "catalog": "cat1", "assignmentPolicies": [ { "displayName": "p1", "requireApproval": false, "approvalStages": [] } ] } ] }' | ConvertFrom-Json
            $V = Test-OERStructureSchema -Document $Doc
            @($V.Errors | Where-Object { $_.Message -match 'declared as an empty array' }).Count | Should -Be 0
        }
    }

    It 'does not warn when requireApproval is true and approvalStages is OMITTED (the live stages are kept)' {
        InModuleScope $script:moduleName {
            $Doc = '{ "version": "1.0", "accessPackages": [ { "displayName": "ap1", "catalog": "cat1", "assignmentPolicies": [ { "displayName": "p1", "requireApproval": true } ] } ] }' | ConvertFrom-Json
            $V = Test-OERStructureSchema -Document $Doc
            @($V.Errors | Where-Object { $_.Message -match 'declared as an empty array' }).Count | Should -Be 0
            @($V.Errors | Where-Object { $_.Message -match 'clears every approval stage' }).Count | Should -Be 0
        }
    }

    It 'does not warn when requireApproval is true and approvalStages is an explicit JSON null (undeclared)' {
        InModuleScope $script:moduleName {
            $Doc = '{ "version": "1.0", "accessPackages": [ { "displayName": "ap1", "catalog": "cat1", "assignmentPolicies": [ { "displayName": "p1", "requireApproval": true, "approvalStages": null } ] } ] }' | ConvertFrom-Json
            $V = Test-OERStructureSchema -Document $Doc
            @($V.Errors | Where-Object { $_.Message -match 'declared as an empty array' }).Count | Should -Be 0
            @($V.Errors | Where-Object { $_.Message -match 'clears every approval stage' }).Count | Should -Be 0
        }
    }
}

Describe 'Test-OERStructureSchema accessPackages emptied approvalStages with an approval flag left in force' {
    # LIVE-MEASURED: a document declaring ONLY "approvalStages": [] failed on all three runs with
    # InvalidApprovalStages, even though isApprovalRequiredForAdd was correctly derived as false from
    # the declared stage count. isApprovalRequiredForUpdate falls to ConvertTo-OERPolicyBody's
    # -Existing carry-forward branch and re-sends the live policy's value, so Graph's refusal covers
    # the UPDATE approval flag too. This Warning is the offline report of that gap; the transport is
    # deliberately left alone (clearing a live flag the document never mentioned is the composite-field
    # carry-forward hazard the -Existing design exists to prevent).
    It 'warns, without failing validation, when approvalStages is empty and neither approval flag is declared false' {
        InModuleScope $script:moduleName {
            $Doc = '{ "version": "1.0", "accessPackages": [ { "displayName": "ap1", "catalog": "cat1", "assignmentPolicies": [ { "displayName": "p1", "approvalStages": [] } ] } ] }' | ConvertFrom-Json
            $V = Test-OERStructureSchema -Document $Doc
            $Hit = @($V.Errors | Where-Object { $_.Message -match 'clears every approval stage' })
            $Hit.Count | Should -Be 1
            $Hit[0].Severity | Should -BeExactly 'Warning'
            $Hit[0].Section | Should -BeExactly 'accessPackages'
            $Hit[0].Item | Should -BeExactly 'ap1'
            $Hit[0].Path | Should -BeExactly 'accessPackages[0].assignmentPolicies[0].approvalStages'
            # The four things the message has to carry for an operator to act on it unaided.
            $Hit[0].Message | Should -Match 'InvalidApprovalStages'
            $Hit[0].Message | Should -Match 'requireApprovalForUpdate'
            $Hit[0].Message | Should -Match 'carried forward from the live policy'
            $Hit[0].Message | Should -Match 'EXISTING policy'
            # A Warning must never fail the document.
            $V.Valid | Should -BeTrue
            @($V.Errors | Where-Object { $_.Severity -eq 'Error' }).Count | Should -Be 0
        }
    }

    It 'warns when requireApproval is declared false but requireApprovalForUpdate is not declared at all' {
        InModuleScope $script:moduleName {
            # The shape the one outstanding live question settles: 'requireApproval' declared false
            # with the only approval still in force the carried-forward 'requireApprovalForUpdate'.
            # No tracked checklist carries that check yet -- the measured refusal was one step
            # short of it, on a document declaring neither flag. Warned on as written; if Graph
            # accepts this one, the Warning narrows to requireApprovalForUpdate alone and this test
            # inverts with it.
            $Doc = '{ "version": "1.0", "accessPackages": [ { "displayName": "ap1", "catalog": "cat1", "assignmentPolicies": [ { "displayName": "p1", "requireApproval": false, "approvalStages": [] } ] } ] }' | ConvertFrom-Json
            $V = Test-OERStructureSchema -Document $Doc
            @($V.Errors | Where-Object { $_.Message -match 'clears every approval stage' }).Count | Should -Be 1
            $V.Valid | Should -BeTrue
        }
    }

    It 'warns when requireApproval is false but requireApprovalForUpdate is declared TRUE' {
        InModuleScope $script:moduleName {
            $Doc = '{ "version": "1.0", "accessPackages": [ { "displayName": "ap1", "catalog": "cat1", "assignmentPolicies": [ { "displayName": "p1", "requireApproval": false, "requireApprovalForUpdate": true, "approvalStages": [] } ] } ] }' | ConvertFrom-Json
            @((Test-OERStructureSchema -Document $Doc).Errors | Where-Object { $_.Message -match 'clears every approval stage' }).Count | Should -Be 1
        }
    }

    It 'does NOT warn when both requireApproval and requireApprovalForUpdate are declared false (the remedy)' {
        InModuleScope $script:moduleName {
            $Doc = '{ "version": "1.0", "accessPackages": [ { "displayName": "ap1", "catalog": "cat1", "assignmentPolicies": [ { "displayName": "p1", "requireApproval": false, "requireApprovalForUpdate": false, "approvalStages": [] } ] } ] }' | ConvertFrom-Json
            $V = Test-OERStructureSchema -Document $Doc
            @($V.Errors | Where-Object { $_.Message -match 'clears every approval stage' }).Count | Should -Be 0
            @($V.Errors | Where-Object { $_.Message -match 'declared as an empty array' }).Count | Should -Be 0
        }
    }

    It 'does NOT double-warn: a requireApproval-true document raises the contradiction warning and this one only' {
        InModuleScope $script:moduleName {
            $Doc = '{ "version": "1.0", "accessPackages": [ { "displayName": "ap1", "catalog": "cat1", "assignmentPolicies": [ { "displayName": "p1", "requireApproval": true, "requireApprovalForUpdate": true, "approvalStages": [] } ] } ] }' | ConvertFrom-Json
            $V = Test-OERStructureSchema -Document $Doc
            @($V.Errors | Where-Object { $_.Message -match 'declared as an empty array' }).Count | Should -Be 1
            @($V.Errors | Where-Object { $_.Message -match 'clears every approval stage' }).Count | Should -Be 0
            # Exactly one finding at that Path, whichever it is.
            @($V.Errors | Where-Object { $_.Path -eq 'accessPackages[0].assignmentPolicies[0].approvalStages' }).Count | Should -Be 1
        }
    }

    It 'does NOT warn when approvalStages is omitted or an explicit JSON null (nothing is being cleared)' {
        InModuleScope $script:moduleName {
            foreach ($Json in @(
                    '{ "version": "1.0", "accessPackages": [ { "displayName": "ap1", "catalog": "cat1", "assignmentPolicies": [ { "displayName": "p1" } ] } ] }',
                    '{ "version": "1.0", "accessPackages": [ { "displayName": "ap1", "catalog": "cat1", "assignmentPolicies": [ { "displayName": "p1", "approvalStages": null } ] } ] }')) {
                $V = Test-OERStructureSchema -Document ($Json | ConvertFrom-Json)
                @($V.Errors | Where-Object { $_.Message -match 'clears every approval stage' }).Count |
                    Should -Be 0 -Because "an undeclared approvalStages clears nothing, so neither warning applies: $Json"
            }
        }
    }

    It 'does NOT warn when approvalStages is non-empty, whatever the approval flags say' {
        InModuleScope $script:moduleName {
            $Doc = '{ "version": "1.0", "accessPackages": [ { "displayName": "ap1", "catalog": "cat1", "assignmentPolicies": [ { "displayName": "p1", "requireApprovalForUpdate": true, "approvalStages": [ { "durationDays": 7, "manager": true } ] } ] } ] }' | ConvertFrom-Json
            @((Test-OERStructureSchema -Document $Doc).Errors | Where-Object { $_.Message -match 'clears every approval stage' }).Count | Should -Be 0
        }
    }
}

Describe 'Test-OERStructureSchema requestorScope scope inference (issue #69)' {
    # Case 1: scope absent (or explicit null) + non-empty users/groups -> Warning, document stays Valid.
    # This is the split half of the old blanket Error that must relax, since Build-OERPolicyParts now
    # infers SpecificDirectoryUsers for exactly this shape and Invoke-OERStructure would otherwise abort
    # on the very document issue #69 exists to support.
    It 'warns, without failing validation, when scope is absent and users is non-empty' {
        InModuleScope $script:moduleName {
            $Doc = '{ "version": "1.0", "accessPackages": [ { "displayName": "ap1", "catalog": "cat1", "assignmentPolicies": [ { "displayName": "p1", "requestorScope": { "users": ["u1@contoso.com"] } } ] } ] }' | ConvertFrom-Json
            $V = Test-OERStructureSchema -Document $Doc
            $Hit = @($V.Errors | Where-Object { $_.Path -eq 'accessPackages[0].assignmentPolicies[0].requestorScope.scope' })
            $Hit.Count | Should -Be 1
            $Hit[0].Severity | Should -BeExactly 'Warning'
            $Hit[0].Message | Should -Match 'infers'
            $Hit[0].Message | Should -Match 'SpecificDirectoryUsers'
            $V.Valid | Should -BeTrue
            @($V.Errors | Where-Object { $_.Severity -eq 'Error' }).Count | Should -Be 0
        }
    }

    It 'warns, without failing validation, when scope is absent and groups is non-empty' {
        InModuleScope $script:moduleName {
            $Doc = '{ "version": "1.0", "accessPackages": [ { "displayName": "ap1", "catalog": "cat1", "assignmentPolicies": [ { "displayName": "p1", "requestorScope": { "groups": ["g1"] } } ] } ] }' | ConvertFrom-Json
            $V = Test-OERStructureSchema -Document $Doc
            $Hit = @($V.Errors | Where-Object { $_.Path -eq 'accessPackages[0].assignmentPolicies[0].requestorScope.scope' })
            $Hit.Count | Should -Be 1
            $Hit[0].Severity | Should -BeExactly 'Warning'
            $V.Valid | Should -BeTrue
        }
    }

    It 'warns the same way when scope is an explicit JSON null (not just omitted) and users is non-empty' {
        InModuleScope $script:moduleName {
            $Doc = '{ "version": "1.0", "accessPackages": [ { "displayName": "ap1", "catalog": "cat1", "assignmentPolicies": [ { "displayName": "p1", "requestorScope": { "scope": null, "users": ["u1@contoso.com"] } } ] } ] }' | ConvertFrom-Json
            $V = Test-OERStructureSchema -Document $Doc
            $Hit = @($V.Errors | Where-Object { $_.Path -eq 'accessPackages[0].assignmentPolicies[0].requestorScope.scope' })
            $Hit.Count | Should -Be 1
            $Hit[0].Severity | Should -BeExactly 'Warning'
            $V.Valid | Should -BeTrue
        }
    }

    # Case 2: scope absent + no non-empty users/groups -> the Error is unchanged. Nothing is inferable,
    # so this document fails today and keeps failing -- no relaxation applies.
    It 'still errors when scope is absent and neither users nor groups is declared' {
        InModuleScope $script:moduleName {
            $Doc = '{ "version": "1.0", "accessPackages": [ { "displayName": "ap1", "catalog": "cat1", "assignmentPolicies": [ { "displayName": "p1", "requestorScope": {} } ] } ] }' | ConvertFrom-Json
            $V = Test-OERStructureSchema -Document $Doc
            $Hit = @($V.Errors | Where-Object { $_.Path -eq 'accessPackages[0].assignmentPolicies[0].requestorScope.scope' })
            $Hit.Count | Should -Be 1
            $Hit[0].Severity | Should -BeExactly 'Error'
            $V.Valid | Should -BeFalse
        }
    }

    It 'still errors when scope is absent and users/groups are declared but empty (an empty list names nobody)' {
        InModuleScope $script:moduleName {
            $Doc = '{ "version": "1.0", "accessPackages": [ { "displayName": "ap1", "catalog": "cat1", "assignmentPolicies": [ { "displayName": "p1", "requestorScope": { "users": [], "groups": [] } } ] } ] }' | ConvertFrom-Json
            $V = Test-OERStructureSchema -Document $Doc
            $Hit = @($V.Errors | Where-Object { $_.Path -eq 'accessPackages[0].assignmentPolicies[0].requestorScope.scope' })
            $Hit.Count | Should -Be 1
            $Hit[0].Severity | Should -BeExactly 'Error'
            $V.Valid | Should -BeFalse
        }
    }

    It 'still errors on a declared-empty-string scope even with a non-empty users list (the value is invalid regardless)' {
        InModuleScope $script:moduleName {
            $Doc = '{ "version": "1.0", "accessPackages": [ { "displayName": "ap1", "catalog": "cat1", "assignmentPolicies": [ { "displayName": "p1", "requestorScope": { "scope": "", "users": ["u1@contoso.com"] } } ] } ] }' | ConvertFrom-Json
            $V = Test-OERStructureSchema -Document $Doc
            $Hit = @($V.Errors | Where-Object { $_.Path -eq 'accessPackages[0].assignmentPolicies[0].requestorScope.scope' })
            $Hit.Count | Should -Be 1
            $Hit[0].Severity | Should -BeExactly 'Error'
            $V.Valid | Should -BeFalse
        }
    }

    # Case 3 (Ruling R-3, new diagnostics only): an explicit scope other than SpecificDirectoryUsers,
    # together with a non-empty users/groups, is a Warning naming that those targets are unused. No
    # inference happens here -- the explicit scope always wins.
    It 'warns when an explicit non-SpecificDirectoryUsers scope is declared together with a non-empty users list' {
        InModuleScope $script:moduleName {
            $Doc = '{ "version": "1.0", "accessPackages": [ { "displayName": "ap1", "catalog": "cat1", "assignmentPolicies": [ { "displayName": "p1", "requestorScope": { "scope": "AllMemberUsers", "users": ["u1@contoso.com"] } } ] } ] }' | ConvertFrom-Json
            $V = Test-OERStructureSchema -Document $Doc
            $Hit = @($V.Errors | Where-Object { $_.Path -eq 'accessPackages[0].assignmentPolicies[0].requestorScope.scope' })
            $Hit.Count | Should -Be 1
            $Hit[0].Severity | Should -BeExactly 'Warning'
            $Hit[0].Message | Should -Match 'AllMemberUsers'
            $Hit[0].Message | Should -Match 'ignored'
            $V.Valid | Should -BeTrue
            @($V.Errors | Where-Object { $_.Severity -eq 'Error' }).Count | Should -Be 0
        }
    }

    It 'does not warn when the explicit scope is SpecificDirectoryUsers with a non-empty users list' {
        InModuleScope $script:moduleName {
            $Doc = '{ "version": "1.0", "accessPackages": [ { "displayName": "ap1", "catalog": "cat1", "assignmentPolicies": [ { "displayName": "p1", "requestorScope": { "scope": "SpecificDirectoryUsers", "users": ["u1@contoso.com"] } } ] } ] }' | ConvertFrom-Json
            $V = Test-OERStructureSchema -Document $Doc
            @($V.Errors | Where-Object { $_.Path -eq 'accessPackages[0].assignmentPolicies[0].requestorScope.scope' }).Count | Should -Be 0
        }
    }

    It 'does not warn when an explicit non-SpecificDirectoryUsers scope has no users/groups declared (unchanged)' {
        InModuleScope $script:moduleName {
            $Doc = '{ "version": "1.0", "accessPackages": [ { "displayName": "ap1", "catalog": "cat1", "assignmentPolicies": [ { "displayName": "p1", "requestorScope": { "scope": "AllMemberUsers" } } ] } ] }' | ConvertFrom-Json
            $V = Test-OERStructureSchema -Document $Doc
            @($V.Errors | Where-Object { $_.Path -eq 'accessPackages[0].assignmentPolicies[0].requestorScope.scope' }).Count | Should -Be 0
        }
    }
}

Describe 'Test-OERStructureSchema approvalStages undeclared durationDays warning (issue #70 site 3)' {
    # Build-OERPolicyParts keeps the applied DurationDays at 0 for an absent or explicit-null
    # durationDays (New-OERAccessPackageApprovalStage's -DurationDays is Mandatory, so the splat key
    # can never be dropped). Measured, not assumed: 0 does NOT quietly become a P0D stage --
    # New-OERAccessPackageApprovalStage's own duration encoder rejects a value below 1, so the stage
    # build throws and the whole assignmentPolicy is reported Failed instead of being created or
    # updated (see the companion Sync-OERStructureAccessPackage.Tests.ps1 coverage that exercises the
    # real builder end to end). This validator warns offline about that outcome rather than only
    # catching an out-of-range VALUE, since an undeclared key passed Test-IsInt's guard entirely
    # before this task.
    It 'does not warn when durationDays is declared with a value' {
        InModuleScope $script:moduleName {
            $Doc = '{ "version": "1.0", "accessPackages": [ { "displayName": "ap1", "catalog": "cat1", "assignmentPolicies": [ { "displayName": "p1", "approvalStages": [ { "durationDays": 7, "manager": true } ] } ] } ] }' | ConvertFrom-Json
            $V = Test-OERStructureSchema -Document $Doc
            @($V.Errors | Where-Object { $_.Path -eq 'accessPackages[0].assignmentPolicies[0].approvalStages[0].durationDays' }).Count | Should -Be 0
            $V.Valid | Should -BeTrue
        }
    }

    It 'warns naming the Failed outcome when durationDays is an explicit JSON null' {
        InModuleScope $script:moduleName {
            $Doc = '{ "version": "1.0", "accessPackages": [ { "displayName": "ap1", "catalog": "cat1", "assignmentPolicies": [ { "displayName": "p1", "approvalStages": [ { "durationDays": null, "manager": true } ] } ] } ] }' | ConvertFrom-Json
            $V = Test-OERStructureSchema -Document $Doc
            $Hit = @($V.Errors | Where-Object { $_.Path -eq 'accessPackages[0].assignmentPolicies[0].approvalStages[0].durationDays' })
            $Hit.Count | Should -Be 1
            $Hit[0].Severity | Should -BeExactly 'Warning'
            $Hit[0].Message | Should -Match 'fails to create or update'
            # A Warning must never fail the document: the apply still runs.
            $V.Valid | Should -BeTrue
        }
    }

    It 'warns naming the Failed outcome when durationDays is omitted, identically to the explicit-null case' {
        InModuleScope $script:moduleName {
            $Doc = '{ "version": "1.0", "accessPackages": [ { "displayName": "ap1", "catalog": "cat1", "assignmentPolicies": [ { "displayName": "p1", "approvalStages": [ { "manager": true } ] } ] } ] }' | ConvertFrom-Json
            $V = Test-OERStructureSchema -Document $Doc
            $Hit = @($V.Errors | Where-Object { $_.Path -eq 'accessPackages[0].assignmentPolicies[0].approvalStages[0].durationDays' })
            $Hit.Count | Should -Be 1
            $Hit[0].Severity | Should -BeExactly 'Warning'
            $Hit[0].Message | Should -Match 'fails to create or update'
            $V.Valid | Should -BeTrue
        }
    }
}

Describe 'Test-OERStructureSchema group administrativeUnit placement warning (issue #59)' {
    # administrativeUnit on a group is create-only (Sync-OERStructureGroup.ps1) and never round-trips,
    # so the ONLY way a document keeps a group inside a unit across repeated applies is by also naming
    # the group in that unit's own administrativeUnits[].members. Warning, never Error (spec
    # Foerhandsbeslut option A+B, not C): the prune pass stays independent of the groups section, and a
    # document that validates today must keep validating.
    It 'warns exactly once, at the group administrativeUnit path, naming the -Prune consequence, and keeps the document Valid' {
        InModuleScope $script:moduleName {
            $Doc = ('{ "version": "1.0", ' +
                '"groups": [ { "displayName": "GroupX", "administrativeUnit": "AU-1" } ], ' +
                '"administrativeUnits": [ { "displayName": "AU-1", "members": [ "SomeoneElse" ] } ] }') | ConvertFrom-Json
            $V = Test-OERStructureSchema -Document $Doc
            $Hit = @($V.Errors | Where-Object { $_.Path -eq 'groups[0].administrativeUnit' })
            $Hit.Count | Should -Be 1
            $Hit[0].Severity | Should -BeExactly 'Warning'
            $Hit[0].Message | Should -Match '-Prune'
            $V.Valid | Should -BeTrue
        }
    }

    It 'does not warn when the group is named in the matching unit members' {
        InModuleScope $script:moduleName {
            $Doc = ('{ "version": "1.0", ' +
                '"groups": [ { "displayName": "GroupX", "administrativeUnit": "AU-1" } ], ' +
                '"administrativeUnits": [ { "displayName": "AU-1", "members": [ "GroupX" ] } ] }') | ConvertFrom-Json
            $V = Test-OERStructureSchema -Document $Doc
            @($V.Errors | Where-Object { $_.Path -eq 'groups[0].administrativeUnit' }).Count | Should -Be 0
            $V.Valid | Should -BeTrue
        }
    }

    It 'does not warn when the referenced unit is not declared in the same document' {
        InModuleScope $script:moduleName {
            $Doc = ('{ "version": "1.0", ' +
                '"groups": [ { "displayName": "GroupX", "administrativeUnit": "AU-Ghost" } ], ' +
                '"administrativeUnits": [ { "displayName": "AU-1", "members": [ "SomeoneElse" ] } ] }') | ConvertFrom-Json
            $V = Test-OERStructureSchema -Document $Doc
            @($V.Errors | Where-Object { $_.Path -eq 'groups[0].administrativeUnit' }).Count | Should -Be 0
            $V.Valid | Should -BeTrue
        }
    }

    It 'does not warn when the matching unit declares members as an explicit null, the documented hands-off signal' {
        InModuleScope $script:moduleName {
            $Doc = ('{ "version": "1.0", ' +
                '"groups": [ { "displayName": "GroupX", "administrativeUnit": "AU-1" } ], ' +
                '"administrativeUnits": [ { "displayName": "AU-1", "members": null } ] }') | ConvertFrom-Json
            $V = Test-OERStructureSchema -Document $Doc
            @($V.Errors | Where-Object { $_.Path -eq 'groups[0].administrativeUnit' }).Count | Should -Be 0
            $V.Valid | Should -BeTrue
        }
    }

    It 'warns when the matching unit declares members as an explicit empty array, since a declared-empty list still prunes' {
        InModuleScope $script:moduleName {
            $Doc = ('{ "version": "1.0", ' +
                '"groups": [ { "displayName": "GroupX", "administrativeUnit": "AU-1" } ], ' +
                '"administrativeUnits": [ { "displayName": "AU-1", "members": [] } ] }') | ConvertFrom-Json
            $V = Test-OERStructureSchema -Document $Doc
            $Hit = @($V.Errors | Where-Object { $_.Path -eq 'groups[0].administrativeUnit' })
            $Hit.Count | Should -Be 1
            $Hit[0].Severity | Should -BeExactly 'Warning'
            $V.Valid | Should -BeTrue
        }
    }

    It 'matches the unit displayName and the group displayName case-insensitively' {
        InModuleScope $script:moduleName {
            $Doc = ('{ "version": "1.0", ' +
                '"groups": [ { "displayName": "GroupX", "administrativeUnit": "au-1" } ], ' +
                '"administrativeUnits": [ { "displayName": "AU-1", "members": [ "groupx" ] } ] }') | ConvertFrom-Json
            $V = Test-OERStructureSchema -Document $Doc
            @($V.Errors | Where-Object { $_.Path -eq 'groups[0].administrativeUnit' }).Count | Should -Be 0
            $V.Valid | Should -BeTrue
        }
    }

    It 'emits nothing, and does not throw, for a template-based group, since its real displayName is resolved only at apply time' {
        InModuleScope $script:moduleName {
            $Doc = ('{ "version": "1.0", ' +
                '"groups": [ { "template": "grp-{Region}", "tokens": { "Region": "EU" }, "administrativeUnit": "AU-1" } ], ' +
                '"administrativeUnits": [ { "displayName": "AU-1", "members": [ "SomeoneElse" ] } ] }') | ConvertFrom-Json
            $V = Test-OERStructureSchema -Document $Doc
            @($V.Errors | Where-Object { $_.Path -eq 'groups[0].administrativeUnit' }).Count | Should -Be 0
            $V.Valid | Should -BeTrue
        }
    }
}

Describe 'Test-OERStructureSchema omitted collection key warning' {
    # Five collections are reconciled against an empty declared set when their key is omitted, so
    # Invoke-OERStructure -Prune removes every live entry in them. Get-OEROmittedPruneCollection owns
    # which keys those are; the validator turns each one into a Warning, never an Error.
    It 'warns exactly once for an omitted group members key, at groups[0].members, and keeps the document Valid' {
        InModuleScope $script:moduleName {
            $Doc = '{ "version": "1.0", "groups": [ { "displayName": "g1" } ] }' | ConvertFrom-Json
            $V = Test-OERStructureSchema -Document $Doc
            @($V.Errors).Count | Should -Be 1
            $Hit = @($V.Errors | Where-Object { $_.Path -eq 'groups[0].members' })
            $Hit.Count | Should -Be 1
            $Hit[0].Severity | Should -BeExactly 'Warning'
            $Hit[0].Section  | Should -BeExactly 'groups'
            $Hit[0].Item     | Should -BeExactly 'g1'
            $Hit[0].Message | Should -BeExactly "'members' is omitted at groups[0]. An omitted members key is still reconciled, against an empty declared set, so Invoke-OERStructure -Prune removes every live entry in it. Declare the key (an empty array removes them deliberately), or set it to null to leave the collection untouched."
            $V.Valid | Should -BeTrue
        }
    }

    It 'does not warn when group members is an explicit null' {
        InModuleScope $script:moduleName {
            $Doc = '{ "version": "1.0", "groups": [ { "displayName": "g1", "members": null } ] }' | ConvertFrom-Json
            $V = Test-OERStructureSchema -Document $Doc
            @($V.Errors | Where-Object { $_.Path -eq 'groups[0].members' }).Count | Should -Be 0
            $V.Valid | Should -BeTrue
        }
    }

    It 'does not warn for the omitted members of a group declared dynamic true' {
        InModuleScope $script:moduleName {
            $Doc = '{ "version": "1.0", "groups": [ { "displayName": "g1", "dynamic": true, "membershipRule": "(user.department -eq \"IT\")" } ] }' | ConvertFrom-Json
            $V = Test-OERStructureSchema -Document $Doc
            @($V.Errors | Where-Object { $_.Path -eq 'groups[0].members' }).Count | Should -Be 0
            $V.Valid | Should -BeTrue
        }
    }

    It 'warns for an omitted catalog resources key and an omitted access package resourceRoles key' {
        InModuleScope $script:moduleName {
            $Doc = ('{ "version": "1.0", ' +
                '"catalogs": [ { "displayName": "c1" } ], ' +
                '"accessPackages": [ { "displayName": "ap1", "catalog": "c1" } ] }') | ConvertFrom-Json
            $V = Test-OERStructureSchema -Document $Doc
            $Resources = @($V.Errors | Where-Object { $_.Path -eq 'catalogs[0].resources' })
            $Resources.Count | Should -Be 1
            $Resources[0].Severity | Should -BeExactly 'Warning'
            $Resources[0].Item     | Should -BeExactly 'c1'
            $Resources[0].Message  | Should -BeLike "'resources' is omitted at catalogs[[]0]. An omitted resources key*"
            $RoleWarnings = @($V.Errors | Where-Object { $_.Path -eq 'accessPackages[0].resourceRoles' })
            $RoleWarnings.Count | Should -Be 1
            $RoleWarnings[0].Severity | Should -BeExactly 'Warning'
            $RoleWarnings[0].Item     | Should -BeExactly 'ap1'
            $RoleWarnings[0].Message  | Should -BeLike "'resourceRoles' is omitted at accessPackages[[]0]. An omitted resourceRoles key*"
            $V.Valid | Should -BeTrue
        }
    }

    It 'warns for the omitted scopedRoles, but not the omitted members, of an administrative unit declared dynamic true' {
        InModuleScope $script:moduleName {
            $Doc = '{ "version": "1.0", "administrativeUnits": [ { "displayName": "au1", "dynamic": true, "membershipRule": "(user.department -eq \"IT\")" } ] }' | ConvertFrom-Json
            $V = Test-OERStructureSchema -Document $Doc
            @($V.Errors | Where-Object { $_.Path -eq 'administrativeUnits[0].scopedRoles' -and $_.Severity -eq 'Warning' }).Count | Should -Be 1
            @($V.Errors | Where-Object { $_.Path -eq 'administrativeUnits[0].members' }).Count | Should -Be 0
            $V.Valid | Should -BeTrue
        }
    }
}
