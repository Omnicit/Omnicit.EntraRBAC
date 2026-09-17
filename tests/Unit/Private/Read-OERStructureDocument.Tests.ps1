BeforeAll {
    $script:moduleName = 'Omnicit.EntraRBAC'
    Get-Module $script:moduleName | Remove-Module -Force -ErrorAction SilentlyContinue
    Import-Module $script:moduleName -Force -ErrorAction Stop
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
