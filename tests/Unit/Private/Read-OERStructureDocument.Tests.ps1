BeforeAll {
    $script:moduleName = 'Omnicit.EntraRBAC'
    Get-Module $script:moduleName | Remove-Module -Force -ErrorAction SilentlyContinue
    Import-Module $script:moduleName -Force -ErrorAction Stop
    . "$PSScriptRoot/../TestHelpers/OERTransportTripwire.ps1"
    Install-OERTransportTripwire
}

AfterAll {
    try { Assert-OERTransportTripwire } finally { Uninstall-OERTransportTripwire }
}

Describe 'Read-OERStructureDocument' {
    It 'parses a -Json string into an object' {
        InModuleScope $script:moduleName {
            $d = Read-OERStructureDocument -Json '{ "version": "1.0", "groups": [ { "displayName": "g1" } ] }'
            $d.version | Should -Be '1.0'
            @($d.groups).Count | Should -Be 1
            $d.groups[0].displayName | Should -Be 'g1'
        }
    }
    It 'parses a -Path file into an object' {
        InModuleScope $script:moduleName {
            $p = Join-Path $TestDrive 'doc.json'
            Set-Content -LiteralPath $p -Value '{ "version": "1.0" }' -Encoding utf8
            (Read-OERStructureDocument -Path $p).version | Should -Be '1.0'
        }
    }
    It 'throws on malformed JSON' {
        InModuleScope $script:moduleName {
            { Read-OERStructureDocument -Json '{ not json' } | Should -Throw
        }
    }
    It 'throws on a missing file' {
        InModuleScope $script:moduleName {
            { Read-OERStructureDocument -Path (Join-Path $TestDrive 'nope.json') } | Should -Throw
        }
    }
    It 'throws when JSON is not a single object' {
        InModuleScope $script:moduleName {
            { Read-OERStructureDocument -Json '[ 1, 2, 3 ]' } | Should -Throw
        }
    }
    It 'throws on an empty document' {
        InModuleScope $script:moduleName {
            { Read-OERStructureDocument -Json '   ' } | Should -Throw
        }
    }
    It 'parses a -InputObject PSCustomObject into an object with the expected property' {
        InModuleScope $script:moduleName {
            $Obj = [pscustomobject]@{ version = '1.0'; groups = @() }
            $d = Read-OERStructureDocument -InputObject $Obj
            $d.PSObject.Properties.Name | Should -Contain 'groups'
        }
    }
    It 'throws when the JSON root is the scalar <Json>' -TestCases @(
        @{ Json = 'true' }
        @{ Json = '42' }
        @{ Json = '"str"' }
        @{ Json = 'null' }
    ) {
        param($Json)
        InModuleScope $script:moduleName -Parameters @{ Json = $Json } {
            param($Json)
            { Read-OERStructureDocument -Json $Json } | Should -Throw
        }
    }
    It 'reads a PascalCase-root document written by an earlier module version' {
        InModuleScope $script:moduleName {
            # Backward-compatibility direction 2. Earlier module versions emitted this PascalCase-root
            # shape, so real documents already on an operator's disk are written this way; a document
            # in this shape must not start failing.
            $Path = Join-Path $TestDrive 'legacy-pascal.json'
            $Legacy = @'
{
  "Version": "1.0",
  "Groups": [ { "displayName": "role_sec_identity_reader" } ],
  "AdministrativeUnits": [],
  "Catalogs": [],
  "AccessPackages": [],
  "AccessReviews": [],
  "RoleAssignments": [],
  "RoleManagementPolicies": []
}
'@
            Set-Content -LiteralPath $Path -Value $Legacy -Encoding utf8
            $Doc = Read-OERStructureDocument -Path $Path
            $Doc.version | Should -Be '1.0'
            @($Doc.groups).Count | Should -Be 1
            $Doc.groups[0].displayName | Should -Be 'role_sec_identity_reader'
        }
    }

    It 'normalizes enum casing so the value that reaches a Graph body is the canonical one' {
        InModuleScope $script:moduleName {
            $Doc = Read-OERStructureDocument -Json @'
{
  "version": "1.0",
  "groups": [ {
      "displayName": "g1",
      "eligibility": [ { "principal": "person41@example.com", "accessType": "Member" } ],
      "pimPolicy": { "activationEnablement": [ "justification", "TICKETING" ] }
  } ],
  "administrativeUnits": [ { "displayName": "au1", "membershipRuleProcessingState": "paused" } ],
  "catalogs": [ { "displayName": "c1", "resources": [ { "name": "g1", "type": "group" } ] } ],
  "accessReviews": [ { "displayName": "ar1", "accessPackage": "ap1", "recurrence": "quarterly", "defaultDecision": "deny" } ],
  "roleAssignments": [ { "scope": "/subscriptions/x", "role": "Reader", "principal": "p", "principalType": "serviceprincipal" } ]
}
'@
            $Doc.groups[0].eligibility[0].accessType | Should -BeExactly 'member'
            @($Doc.groups[0].pimPolicy.activationEnablement) -join ',' | Should -BeExactly 'Justification,Ticketing'
            $Doc.administrativeUnits[0].membershipRuleProcessingState | Should -BeExactly 'Paused'
            $Doc.catalogs[0].resources[0].type | Should -BeExactly 'Group'
            $Doc.accessReviews[0].recurrence | Should -BeExactly 'Quarterly'
            $Doc.accessReviews[0].defaultDecision | Should -BeExactly 'Deny'
            $Doc.roleAssignments[0].principalType | Should -BeExactly 'ServicePrincipal'
        }
    }

    It 'normalizes enum casing in the nested member and owner pimPolicy blocks' {
        InModuleScope $script:moduleName {
            $Doc = Read-OERStructureDocument -Json @'
{
  "version": "1.0",
  "groups": [ {
      "displayName": "g1",
      "pimPolicy": {
        "member": { "activationEnablement": [ "multifactorauthentication" ] },
        "owner":  { "activeEnablement": [ "ticketing" ] }
      }
  } ]
}
'@
            @($Doc.groups[0].pimPolicy.member.activationEnablement) -join ',' | Should -BeExactly 'MultiFactorAuthentication'
            @($Doc.groups[0].pimPolicy.owner.activeEnablement) -join ',' | Should -BeExactly 'Ticketing'
        }
    }

    It 'normalizes approverInfoVisibility inside an access package assignment policy approval stage' {
        InModuleScope $script:moduleName {
            $Doc = Read-OERStructureDocument -Json @'
{
  "version": "1.0",
  "accessPackages": [ {
      "displayName": "ap1",
      "catalog": "c1",
      "assignmentPolicies": [ { "displayName": "p1", "approvalStages": [ { "approverInfoVisibility": "notvisible" } ] } ]
  } ]
}
'@
            $Doc.accessPackages[0].assignmentPolicies[0].approvalStages[0].approverInfoVisibility |
                Should -BeExactly 'NotVisible'
        }
    }

    It 'leaves a value that is not a member of the enum untouched so the validator can report it' {
        InModuleScope $script:moduleName {
            $Doc = Read-OERStructureDocument -Json '{ "version": "1.0", "roleAssignments": [ { "scope": "/s", "role": "Reader", "principal": "p", "principalType": "Robot" } ] }'
            $Doc.roleAssignments[0].principalType | Should -BeExactly 'Robot'
        }
    }

    It 'normalizes without adding a duplicate key and without touching the callers object' {
        InModuleScope $script:moduleName {
            $Source = '{ "version": "1.0", "roleAssignments": [ { "scope": "/s", "role": "Reader", "principal": "p", "principalType": "group" } ] }' | ConvertFrom-Json
            $Doc = Read-OERStructureDocument -InputObject $Source
            $Doc.roleAssignments[0].principalType | Should -BeExactly 'Group'
            @($Doc.roleAssignments[0].PSObject.Properties.Name).Count | Should -Be 4
            # -InputObject round-trips through ConvertTo-Json, so the caller's object is a different
            # instance and must be left exactly as it was.
            $Source.roleAssignments[0].principalType | Should -BeExactly 'group'
        }
    }

    It 'handles a document with no sections at all' {
        InModuleScope $script:moduleName {
            $Doc = Read-OERStructureDocument -Json '{ "version": "1.0" }'
            $Doc.version | Should -Be '1.0'
        }
    }

    It 'leaves the raw casing intact when -SkipEnumNormalization is passed' {
        InModuleScope $script:moduleName {
            $Json = '{ "version": "1.0", "roleAssignments": [ { "scope": "/s", "role": "Reader", "principal": "p", "principalType": "group" } ] }'
            $Doc = Read-OERStructureDocument -Json $Json -SkipEnumNormalization
            $Doc.roleAssignments[0].principalType | Should -BeExactly 'group'
        }
    }

    It 'normalizes the same document when -SkipEnumNormalization is not passed' {
        InModuleScope $script:moduleName {
            $Json = '{ "version": "1.0", "roleAssignments": [ { "scope": "/s", "role": "Reader", "principal": "p", "principalType": "group" } ] }'
            $Doc = Read-OERStructureDocument -Json $Json
            $Doc.roleAssignments[0].principalType | Should -BeExactly 'Group'
        }
    }

    It 'canonicalizes the casing of a roleAssignments principalStatus, and leaves it as written under -SkipEnumNormalization (A18)' {
        InModuleScope $script:moduleName {
            $Json = '{ "version": "1.0", "roleAssignments": [ { "scope": "/s", "role": "Reader", "principal": "11111111-1111-1111-1111-111111111111", "principalStatus": "deleted" }, { "scope": "/s", "role": "Owner", "principal": "22222222-2222-2222-2222-222222222222", "principalStatus": "UNRESOLVED" } ] }'
            $Doc = Read-OERStructureDocument -Json $Json
            $Doc.roleAssignments[0].principalStatus | Should -BeExactly 'Deleted'
            $Doc.roleAssignments[1].principalStatus | Should -BeExactly 'Unresolved'
            $Raw = Read-OERStructureDocument -Json $Json -SkipEnumNormalization
            $Raw.roleAssignments[0].principalStatus | Should -BeExactly 'deleted'
            $Raw.roleAssignments[1].principalStatus | Should -BeExactly 'UNRESOLVED'
        }
    }

    It 'leaves a principalStatus that is not a member of the enum untouched so the validator can report it, and an explicit null a null (A18)' {
        InModuleScope $script:moduleName {
            $Doc = Read-OERStructureDocument -Json '{ "version": "1.0", "roleAssignments": [ { "scope": "/s", "role": "Reader", "principal": "p", "principalStatus": "Gone" }, { "scope": "/s", "role": "Owner", "principal": "q", "principalStatus": null } ] }'
            $Doc.roleAssignments[0].principalStatus | Should -BeExactly 'Gone'
            $Doc.roleAssignments[1].PSObject.Properties.Name | Should -Contain 'principalStatus'
            $null -eq $Doc.roleAssignments[1].principalStatus | Should -BeTrue
        }
    }

    Context 'enum normalization reads declared-ness through Test-OERDeclaredProperty' {
        <#
            Write-OEREnumValue's guard was migrated from an inline
            "$null -eq $Node -or $Node.PSObject.Properties.Name -inotcontains $Key" chain (plus a
            separate null check on the value) to a single Test-OERDeclaredProperty call, so the
            single-owner rule in CLAUDE.md ## Code Style covers this apply-document walker too and the
            QA gate can see the file. The predicate folds all three of the old guards into one and is
            false for every one of them, so the migration is behaviour-PRESERVING -- these three cases
            pin that, with the null and omitted cases required to land on the same outcome.
        #>
        It 'canonicalizes a declared enum value' {
            InModuleScope $script:moduleName {
                $Json = '{ "version": "1.0", "roleAssignments": [ { "scope": "/s", "role": "Reader", "principal": "p", "principalType": "serviceprincipal" } ] }'
                $Doc = Read-OERStructureDocument -Json $Json
                $Doc.roleAssignments[0].principalType | Should -BeExactly 'ServicePrincipal' -Because (
                    'a declared value is the one case that actually has something to canonicalize')
            }
        }

        It 'leaves an explicitly null enum value as null rather than canonicalizing it' {
            InModuleScope $script:moduleName {
                $Json = '{ "version": "1.0", "roleAssignments": [ { "scope": "/s", "role": "Reader", "principal": "p", "principalType": null } ] }'
                $Doc = Read-OERStructureDocument -Json $Json
                $Doc.roleAssignments[0].principalType | Should -BeNullOrEmpty -Because (
                    'an explicit null carries no enum member to resolve, so the key must survive the walk untouched')
                # The KEY must still be present and still null -- the walk may not invent a value, and
                # may not delete the property either. A downstream handler reads its declared-ness with
                # the same predicate and must see the same document it was handed.
                $Doc.roleAssignments[0].PSObject.Properties.Name | Should -Contain 'principalType'
                $null -eq $Doc.roleAssignments[0].principalType | Should -BeTrue
            }
        }

        It 'leaves an omitted enum key absent, the same outcome as an explicit null' {
            InModuleScope $script:moduleName {
                $Json = '{ "version": "1.0", "roleAssignments": [ { "scope": "/s", "role": "Reader", "principal": "p" } ] }'
                $Doc = Read-OERStructureDocument -Json $Json
                $Doc.roleAssignments[0].principalType | Should -BeNullOrEmpty -Because (
                    'an omitted key and an explicit null must both come out of the walk with no value')
                $Doc.roleAssignments[0].PSObject.Properties.Name | Should -Not -Contain 'principalType' -Because (
                    'the walk must not ADD a key the document never declared -- an invented principalType would bind a parameter the author left unbound')
            }
        }

        It 'canonicalizes every other document node the walk visits, so the migration is not proven on one key alone' {
            InModuleScope $script:moduleName {
                # Write-OEREnumValue is called from nine sites with nine different keys; the single
                # migrated guard serves all of them. This re-pins a representative spread so a
                # regression in the shared guard cannot hide behind the roleAssignments cases above.
                $Doc = Read-OERStructureDocument -Json @'
{
  "version": "1.0",
  "groups": [ { "displayName": "g1", "eligibility": [ { "principal": "person41@example.com", "accessType": "OWNER" } ] } ],
  "administrativeUnits": [ { "displayName": "au1", "membershipRuleProcessingState": "ON" } ],
  "accessReviews": [ { "displayName": "ar1", "accessPackage": "ap1", "recurrence": "MONTHLY" } ]
}
'@
                $Doc.groups[0].eligibility[0].accessType | Should -BeExactly 'owner'
                $Doc.administrativeUnits[0].membershipRuleProcessingState | Should -BeExactly 'On'
                $Doc.accessReviews[0].recurrence | Should -BeExactly 'Monthly'
            }
        }
    }

    It 'scrubs the bearer-hygiene record when the JSON parse fails' {
        InModuleScope $script:moduleName {
            Mock Remove-OERErrorRecord { }
            { Read-OERStructureDocument -Json '{ not json' } | Should -Throw '*not valid JSON*'
            Should -Invoke Remove-OERErrorRecord -Times 1
        }
    }

    It 'routes a piped FileInfo -InputObject to the file reader instead of serializing it' {
        InModuleScope $script:moduleName {
            $p = Join-Path $TestDrive 'fileinfo-doc.json'
            Set-Content -LiteralPath $p -Value '{ "version": "1.0", "groups": [ { "displayName": "from-file" } ] }' -Encoding utf8
            $FileInfo = Get-Item -LiteralPath $p
            $d = Read-OERStructureDocument -InputObject $FileInfo
            $d.version | Should -Be '1.0'
            $d.groups[0].displayName | Should -Be 'from-file'
        }
    }

    It 'throws an explicit error for a piped DirectoryInfo -InputObject' {
        InModuleScope $script:moduleName {
            $DirInfo = Get-Item -LiteralPath $TestDrive
            { Read-OERStructureDocument -InputObject $DirInfo } | Should -Throw '*Pipe a file*'
        }
    }

    It 'routes a path-like string -InputObject to the file reader instead of serializing it as JSON' {
        InModuleScope $script:moduleName {
            $p = Join-Path $TestDrive 'string-doc.json'
            Set-Content -LiteralPath $p -Value '{ "version": "1.0", "groups": [ { "displayName": "from-string-path" } ] }' -Encoding utf8
            $d = Read-OERStructureDocument -InputObject $p
            $d.version | Should -Be '1.0'
            $d.groups[0].displayName | Should -Be 'from-string-path'
        }
    }

    It 'throws a not-found error (not a JSON-root error) for a missing path-like string -InputObject' {
        InModuleScope $script:moduleName {
            { Read-OERStructureDocument -InputObject (Join-Path $TestDrive 'missing.json') } | Should -Throw '*not found at path*'
        }
    }

    It 'routes a path-like string -InputObject with leading/trailing whitespace to the real trimmed path' {
        InModuleScope $script:moduleName {
            # The path is classified as path-like using the TRIMMED string, so it must also be opened
            # using the trimmed string -- resolving the untrimmed original (with the whitespace still
            # attached) would look for a differently-named, non-existent file and fail "not found".
            $p = Join-Path $TestDrive 'whitespace-doc.json'
            Set-Content -LiteralPath $p -Value '{ "version": "1.0", "groups": [ { "displayName": "from-whitespace-path" } ] }' -Encoding utf8
            $d = Read-OERStructureDocument -InputObject "  $p  "
            $d.version | Should -Be '1.0'
            $d.groups[0].displayName | Should -Be 'from-whitespace-path'
        }
    }

    It 'does not route a JSON-shaped string -InputObject to the path reader' {
        InModuleScope $script:moduleName {
            # -InputObject is documented to accept a PSCustomObject (the output of Get-OERInventory), not
            # a raw JSON string -- that is -Json's job. This guards that the new path-like-string
            # detection stays scoped to non-JSON-shaped text and does not swallow this case too.
            { Read-OERStructureDocument -InputObject '{ "version": "1.0" }' } | Should -Throw '*single JSON object*'
        }
    }
}

Describe 'Read-OERStructureDocument directoryRoleManagementPolicies' {
    # The section carries no enum-valued field, so the casing normalization has nothing to rewrite in
    # it: the document must come out exactly as it went in, and still validate.
    It 'passes the section through unchanged, and the result validates' {
        InModuleScope $script:moduleName {
            $Json = @'
{ "version": "1.0", "directoryRoleManagementPolicies": [ {
  "role": "reports reader", "activationMaxHours": 4, "requireMfaOnActivation": false,
  "requireApproval": true, "approvers": { "users": [ "Person1@Example.com" ], "groups": [] },
  "authenticationContextId": null, "eligibleDurationDays": 365 } ] }
'@
            $Before = $Json | ConvertFrom-Json -Depth 32 | ConvertTo-Json -Depth 10
            $Doc = Read-OERStructureDocument -Json $Json
            ($Doc | ConvertTo-Json -Depth 10) | Should -BeExactly $Before
            $V = Test-OERStructureSchema -Document $Doc
            @($V.Errors) | Should -BeNullOrEmpty
            $V.Valid | Should -BeTrue
        }
    }
}

Describe 'Read-OERStructureDocument directoryRoleAssignments' {
    # assignmentType decides which cmdlet pair the handler calls and appears in every row label, and
    # principalType is forwarded to the principal resolver, so both are canonicalized before apply.
    It 'canonicalizes assignmentType and principalType' {
        InModuleScope $script:moduleName {
            $Doc = Read-OERStructureDocument -Json '{ "version": "1.0", "directoryRoleAssignments": [ { "role": "Reports Reader", "principal": "Reporting Readers", "principalType": "group", "assignmentType": "active" } ] }'
            $Doc.directoryRoleAssignments[0].assignmentType | Should -BeExactly 'Active'
            $Doc.directoryRoleAssignments[0].principalType | Should -BeExactly 'Group'
        }
    }

    It 'leaves both untouched under -SkipEnumNormalization, and leaves an out-of-enum value for the validator' {
        InModuleScope $script:moduleName {
            $Json = '{ "version": "1.0", "directoryRoleAssignments": [ { "role": "Reports Reader", "principal": "p", "principalType": "group", "assignmentType": "active" }, { "role": "Reports Reader", "principal": "p", "assignmentType": "Pending" } ] }'
            $Raw = Read-OERStructureDocument -Json $Json -SkipEnumNormalization
            $Raw.directoryRoleAssignments[0].assignmentType | Should -BeExactly 'active'
            $Raw.directoryRoleAssignments[0].principalType | Should -BeExactly 'group'
            (Read-OERStructureDocument -Json $Json).directoryRoleAssignments[1].assignmentType | Should -BeExactly 'Pending'
        }
    }
}

Describe 'Read-OERStructureDocument administrativeUnits scopedRoles principalType (Sprint 11 step 8, R-7)' {
    # The validator's casing Warning says Invoke-OERStructure normalizes the case, so the reader
    # canonicalizes a scoped role row's principalType the way it canonicalizes a role assignment's,
    # although the apply engine does not use it to match or write. Every row of every unit is visited.
    It 'canonicalizes the principalType of every scoped role row of every unit' {
        InModuleScope $script:moduleName {
            $Json = '{ "version": "1.0", "administrativeUnits": [ ' +
                '{ "displayName": "AU-One", "scopedRoles": [ { "role": "User Administrator", "principal": "p-1", "principalType": "user" }, ' +
                '{ "role": "User Administrator", "principal": "p-2", "principalType": "GROUP" } ] }, ' +
                '{ "displayName": "AU-Two", "scopedRoles": [ { "role": "Helpdesk Administrator", "principal": "p-3", "principalType": "serviceprincipal" } ] } ] }'
            $Doc = Read-OERStructureDocument -Json $Json
            @($Doc.administrativeUnits[0].scopedRoles | ForEach-Object { $_.principalType }) | Should -BeExactly @('User', 'Group')
            $Doc.administrativeUnits[1].scopedRoles[0].principalType | Should -BeExactly 'ServicePrincipal'
        }
    }

    It 'leaves the casing as written under -SkipEnumNormalization, an out-of-enum value for the validator, and a row without the key or with a null as it was' {
        InModuleScope $script:moduleName {
            $Json = '{ "version": "1.0", "administrativeUnits": [ null, { "displayName": "AU-One", "scopedRoles": [ ' +
                '{ "role": "User Administrator", "principal": "p-1", "principalType": "user" }, ' +
                '{ "role": "User Administrator", "principal": "p-2", "principalType": "Device" }, ' +
                '{ "role": "User Administrator", "principal": "p-3" }, ' +
                '{ "role": "User Administrator", "principal": "p-4", "principalType": null } ] }, ' +
                '{ "displayName": "AU-Two", "scopedRoles": null } ] }'
            $Raw = Read-OERStructureDocument -Json $Json -SkipEnumNormalization
            $Raw.administrativeUnits[1].scopedRoles[0].principalType | Should -BeExactly 'user'
            $Doc = Read-OERStructureDocument -Json $Json
            # Positive control: the walk reached this unit's rows.
            $Doc.administrativeUnits[1].scopedRoles[0].principalType | Should -BeExactly 'User'
            $Doc.administrativeUnits[1].scopedRoles[1].principalType | Should -BeExactly 'Device'
            $Doc.administrativeUnits[1].scopedRoles[2].PSObject.Properties.Name | Should -Not -Contain 'principalType'
            $Doc.administrativeUnits[1].scopedRoles[3].PSObject.Properties.Name | Should -Contain 'principalType'
            $null -eq $Doc.administrativeUnits[1].scopedRoles[3].principalType | Should -BeTrue
            $null -eq $Doc.administrativeUnits[2].scopedRoles | Should -BeTrue
        }
    }
}

Describe 'Read-OERStructureDocument reads the file with -ErrorAction Stop and says the real reason (BL-154)' {
    # Get-Content writes a NON-terminating GetContentReaderIOError for a file it cannot open (a lock, no
    # read permission) and returns nothing, so the reader used to answer "The structure document is
    # empty." on top of the raw read error. Pester runs a mock body under its own Stop preference, so a
    # mocked Get-Content cannot stand in for that write; the Its prove the halves apart -- the message and
    # the scrub with a mock that throws, the -ErrorAction Stop the reader passes with a parameter filter
    # (which sees the common parameter), and the whole path with a real file another process holds open.
    BeforeAll {
        function Write-DocumentFile {
            param([string]$Name, [string]$Json = '{ "version": "1.0" }')
            $Path = Join-Path -Path $TestDrive -ChildPath $Name
            [System.IO.File]::WriteAllText($Path, $Json, [System.Text.UTF8Encoding]::new($false))
            $Path
        }
        # The message of the exception Read-OERStructureDocument -Path throws, or $null when it returns.
        function Get-ReadFailure {
            param([string]$Path)
            InModuleScope $script:moduleName -Parameters @{ Path = $Path } {
                param($Path)
                # -ErrorAction Continue pins the preference the reader's own Get-Content inherits; the global one
                # may be Stop (GitHub Actions, Azure Pipelines), which would end a non-terminating read error
                # whether or not the reader asks for it.
                try { $null = Read-OERStructureDocument -Path $Path -ErrorAction Continue } catch { return $PSItem.Exception.Message }
                $null
            }
        }
    }

    It 'throws one message that says the file could not be read, with the reason, when Get-Content throws an IOException' {
        Mock -ModuleName $script:moduleName Get-Content {
            param($LiteralPath, $Raw)
            throw [System.IO.IOException]::new("The process cannot access the file '$LiteralPath' as another process is using it.")
        }
        $File = Write-DocumentFile -Name 'locked.json'
        Get-ReadFailure -Path $File | Should -BeExactly "The structure document at '$File' could not be read: The process cannot access the file '$File' as another process is using it."
        Should -Invoke -ModuleName $script:moduleName Get-Content -Exactly -Times 1
    }

    It 'reads the file with -ErrorAction Stop, so a non-terminating read error cannot read as an empty document' {
        Mock -ModuleName $script:moduleName Get-Content { '{ "version": "1.0" }' }
        $File = Write-DocumentFile -Name 'stop.json'
        Get-ReadFailure -Path $File | Should -BeNullOrEmpty
        Should -Invoke -ModuleName $script:moduleName Get-Content -ParameterFilter { $ErrorAction -ceq 'Stop' } -Exactly -Times 1
    }

    It 'removes the read error record before it throws for a file Get-Content cannot read' {
        Mock -ModuleName $script:moduleName Remove-OERErrorRecord {}
        Mock -ModuleName $script:moduleName Get-Content {
            param($LiteralPath, $Raw)
            throw [System.IO.IOException]::new('read refused')
        }
        $File = Write-DocumentFile -Name 'locked2.json'
        Get-ReadFailure -Path $File | Should -BeExactly "The structure document at '$File' could not be read: read refused"
        Should -Invoke -ModuleName $script:moduleName Remove-OERErrorRecord -Times 1 -Exactly
    }

    It 'throws that the file could not be read, not that it is empty, for a file another process holds open' {
        $File = Write-DocumentFile -Name 'held.json'
        $Held = [System.IO.File]::Open($File, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::None)
        try {
            # Whether the lock is honoured is the platform's: a system that ignores it reads the file. The
            # probe opens the file the way Get-Content does, with FileShare.ReadWrite.
            $Honoured = $false
            try { [System.IO.File]::Open($File, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite).Dispose() } catch [System.IO.IOException] { $Honoured = $true }
            if (-not $Honoured) {
                Set-ItResult -Skipped -Because 'this platform does not enforce FileShare.None against another reader'
                return
            }
            $Message = Get-ReadFailure -Path $File
        } finally {
            $Held.Dispose()
        }
        $Message | Should -BeLike "The structure document at '$File' could not be read: *"
        $Message | Should -Not -BeLike '*is empty*'
    }

    It 'leaves a file it can read as it was: the document comes back, with no read error' {
        $File = Write-DocumentFile -Name 'fine.json' -Json '{ "version": "1.0", "groups": [ { "displayName": "g1" } ] }'
        $Doc = InModuleScope $script:moduleName -Parameters @{ Path = $File } {
            param($Path)
            Read-OERStructureDocument -Path $Path -ErrorAction Stop
        }
        $Doc.groups[0].displayName | Should -BeExactly 'g1'
    }

    It 'still says the document is empty for a readable file that holds only white space' {
        $File = Write-DocumentFile -Name 'blank.json' -Json "   `n"
        Get-ReadFailure -Path $File | Should -BeExactly 'The structure document is empty.'
    }

    It 'still says the file was not found for a path that is not a file, before it reads anything' {
        Mock -ModuleName $script:moduleName Get-Content { '{ "version": "1.0" }' }
        $Missing = Join-Path -Path $TestDrive -ChildPath 'missing.json'
        Get-ReadFailure -Path $Missing | Should -BeExactly "Structure document not found at path '$Missing'."
        Should -Invoke -ModuleName $script:moduleName Get-Content -Times 0
    }
}

Describe 'Read-OERStructureDocument keeps a date-and-time string as written (BL-154, R-11)' {
    # ConvertFrom-Json on PowerShell before 7.5 turns a string that holds an ISO 8601 date and time with
    # seconds into a [datetime]; 7.5 added -DateKind, and -DateKind String leaves every string as
    # written. The reader asks Test-OERJsonDateKindSupport, so a test mocks either answer whatever
    # PowerShell runs it.
    BeforeAll {
        $script:DateJson = '{ "version": "1.0", "groups": [ { "displayName": "2026-01-01T10:00:00", "description": "2026-01-01T10:00:00Z", "members": [ "2026-01-01T10:00:00+02:00" ] } ], ' +
            '"accessReviews": [ { "displayName": "ar1", "accessPackage": "ap1", "assignmentPolicy": "p1", "startDate": "2026-03-01T00:00:00Z", "endDate": "2026-09-01" } ] }'
    }

    It 'adds -DateKind String to the parse when the PowerShell supports it: every date-and-time string stays the text written' -Skip:(-not ($PSVersionTable.PSVersion -ge [version]'7.5')) {
        InModuleScope $script:moduleName -Parameters @{ Json = $script:DateJson } {
            param($Json)
            Mock Test-OERJsonDateKindSupport { $true }
            $Doc = Read-OERStructureDocument -Json $Json
            $Doc.groups[0].displayName | Should -BeOfType [string]
            $Doc.groups[0].displayName | Should -BeExactly '2026-01-01T10:00:00'
            $Doc.groups[0].description | Should -BeExactly '2026-01-01T10:00:00Z'
            $Doc.groups[0].members[0] | Should -BeExactly '2026-01-01T10:00:00+02:00'
            $Doc.accessReviews[0].startDate | Should -BeExactly '2026-03-01T00:00:00Z'
            $Doc.accessReviews[0].endDate | Should -BeExactly '2026-09-01'
            Should -Invoke Test-OERJsonDateKindSupport -Exactly -Times 1
        }
    }

    It 'leaves the parse as it was when the PowerShell has no -DateKind: the date-and-time strings come back as dates' {
        InModuleScope $script:moduleName -Parameters @{ Json = $script:DateJson } {
            param($Json)
            Mock Test-OERJsonDateKindSupport { $false }
            $Doc = Read-OERStructureDocument -Json $Json
            $Doc.groups[0].displayName | Should -BeOfType [datetime]
            $Doc.groups[0].description | Should -BeOfType [datetime]
            $Doc.groups[0].members[0] | Should -BeOfType [datetime]
            $Doc.accessReviews[0].startDate | Should -BeOfType [datetime]
            $Doc.accessReviews[0].endDate | Should -BeOfType [string] -Because 'a date without a time is no date-and-time form, so no PowerShell converts it'
            Should -Invoke Test-OERJsonDateKindSupport -Exactly -Times 1
        }
    }

    It 'asks the seam for a file read through -Path too' -Skip:(-not ($PSVersionTable.PSVersion -ge [version]'7.5')) {
        $File = Join-Path -Path $TestDrive -ChildPath 'dates.json'
        [System.IO.File]::WriteAllText($File, $script:DateJson, [System.Text.UTF8Encoding]::new($false))
        InModuleScope $script:moduleName -Parameters @{ File = $File } {
            param($File)
            Mock Test-OERJsonDateKindSupport { $true }
            (Read-OERStructureDocument -Path $File).groups[0].displayName | Should -BeExactly '2026-01-01T10:00:00'
            Should -Invoke Test-OERJsonDateKindSupport -Exactly -Times 1
        }
    }

    It 'reads the real answer end to end: a string on PowerShell 7.5 or later, a date before' {
        InModuleScope $script:moduleName -Parameters @{ Json = $script:DateJson } {
            param($Json)
            $Doc = Read-OERStructureDocument -Json $Json
            if ($PSVersionTable.PSVersion -ge [version]'7.5') {
                $Doc.groups[0].displayName | Should -BeOfType [string]
            } else {
                $Doc.groups[0].displayName | Should -BeOfType [datetime]
            }
        }
    }

    It 'canonicalizes enum values as before when -DateKind is in force' -Skip:(-not ($PSVersionTable.PSVersion -ge [version]'7.5')) {
        InModuleScope $script:moduleName {
            Mock Test-OERJsonDateKindSupport { $true }
            $Doc = Read-OERStructureDocument -Json '{ "version": "1.0", "accessReviews": [ { "displayName": "ar1", "accessPackage": "ap1", "recurrence": "monthly", "startDate": "2026-03-01T00:00:00Z" } ] }'
            $Doc.accessReviews[0].recurrence | Should -BeExactly 'Monthly'
            $Doc.accessReviews[0].startDate | Should -BeExactly '2026-03-01T00:00:00Z'
        }
    }

    It 'reads an -InputObject whose values the caller already turned into dates as ConvertTo-Json writes them (documented limit)' -Skip:(-not ($PSVersionTable.PSVersion -ge [version]'7.5')) {
        InModuleScope $script:moduleName {
            Mock Test-OERJsonDateKindSupport { $true }
            $Object = [PSCustomObject]@{
                version = '1.0'
                groups  = @([PSCustomObject]@{ displayName = 'g1'; description = [datetime]::new(2026, 1, 1, 10, 0, 0, [System.DateTimeKind]::Utc) })
            }
            $Written = (($Object | ConvertTo-Json -Depth 32 | ConvertFrom-Json -DateKind String).groups[0].description)
            $Written | Should -BeOfType [string]
            $Doc = Read-OERStructureDocument -InputObject $Object
            $Doc.groups[0].description | Should -BeOfType [string]
            $Doc.groups[0].description | Should -BeExactly $Written
        }
    }

    It 'parses with the module-qualified cmdlet, so a function of the same name in the session is never the one called' {
        InModuleScope $script:moduleName {
            # Test-OERJsonDateKindSupport asks about Microsoft.PowerShell.Utility\ConvertFrom-Json; the
            # parse must call that same command, or a shadowing function decides what the document holds
            # (and whether -DateKind is accepted at all). A plain ConvertFrom-Json finds the function first
            # (functions outrank cmdlets), so the control shows the shadow is in force.
            function script:ConvertFrom-Json {
                param([Parameter(ValueFromPipeline)]$InputObject, $Depth, $DateKind)
                throw 'the shadowing ConvertFrom-Json was called'
            }
            try {
                (Get-Command -Name ConvertFrom-Json).CommandType | Should -Be 'Function' -Because 'the shadow must be what an unqualified call finds'
                $Doc = Read-OERStructureDocument -Json '{ "version": "1.0", "groups": [ { "displayName": "g1" } ] }'
                $Doc.version | Should -BeExactly '1.0'
                $Doc.groups[0].displayName | Should -BeExactly 'g1'
            } finally {
                Remove-Item -LiteralPath 'function:ConvertFrom-Json'
            }
            Get-Command -Name ConvertFrom-Json | ForEach-Object { $_.CommandType } | Should -Be 'Cmdlet'
        }
    }
}
