BeforeAll {
    $script:moduleName = 'Omnicit.EntraRBAC'
    Get-Module $script:moduleName | Remove-Module -Force -ErrorAction SilentlyContinue
    Import-Module $script:moduleName -Force -ErrorAction Stop
}

Describe 'Get-OERAccessPackage' {
    BeforeEach {
        InModuleScope $script:moduleName { $script:_OERAuthState = $null }
        Mock -ModuleName $script:moduleName Initialize-OERAuth {}
    }

    It 'gets an access package by id' {
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest { @{ id = 'ap-1'; displayName = 'AP-Sales' } } -ParameterFilter { $Uri -like '*accessPackages/ap-1*' }
        $R = Get-OERAccessPackage -Id 'ap-1'
        $R.PSObject.TypeNames[0] | Should -Be 'Omnicit.EntraRBAC.AccessPackage'
        $R.Id | Should -Be 'ap-1'
    }

    It 'lists all access packages when no filter is given' {
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest { @{ value = @(@{ id = 'a'; displayName = 'A' }, @{ id = 'b'; displayName = 'B' }) } }
        $All = Get-OERAccessPackage
        $All.Count | Should -Be 2
        $All[0].PSObject.TypeNames[0] | Should -Be 'Omnicit.EntraRBAC.AccessPackage'
    }

    It 'expands policies with -IncludePolicies' {
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest { @{ value = @() } }
        Get-OERAccessPackage -IncludePolicies | Out-Null
        # $expand is a multi-valued list now that catalog is always present, so match
        # assignmentPolicies as an entry inside $expand rather than assuming it is the first one.
        Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 1 -ParameterFilter {
            $Uri -match '\$expand=[^&]*\bassignmentPolicies\b'
        }
    }

    It 'percent-encodes a display name containing reserved characters so the query survives transport' {
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {
            @{ value = @(@{ id = 'ap-9'; displayName = 'R&D + Core' }) }
        }
        $Result = Get-OERAccessPackage -DisplayName 'R&D + Core'
        $Result.Id | Should -Be 'ap-9'
        Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 1 -ParameterFilter {
            $Uri -like "*displayName eq 'R%26D%20%2B%20Core'*"
        }
    }

    It 'percent-encodes a -Filter value containing reserved characters' {
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {
            @{ value = @() }
        }
        Get-OERAccessPackage -Filter "startswith(displayName,'R&D')" | Out-Null
        Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 1 -ParameterFilter {
            $Uri -notmatch '&D' -and $Uri -match '%26D'
        }
    }

    It 'surfaces a Graph failure as a non-terminating error for -Id and emits nothing' {
        # Guards two things the cmdlet must do on a Graph failure: call Remove-OERErrorRecord (the
        # mandatory bearer-token-hygiene line -- asserted via Should -Invoke, since a deleted line
        # would otherwise pass unnoticed) and write its OWN non-terminating record. Match the
        # cmdlet-QUALIFIED ErrorId: PowerShell auto-records the mock's throw into -ErrorVariable a
        # dozen times before the catch runs, so matching the bare Graph code would pass even with
        # WriteError deleted.
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {
            throw [System.Management.Automation.ErrorRecord]::new(
                [System.Exception]::new('Authorization_RequestDenied: Insufficient privileges.'),
                'Authorization_RequestDenied',
                [System.Management.Automation.ErrorCategory]::PermissionDenied,
                $null)
        } -ParameterFilter { $Uri -like '*accessPackages/ap-1*' }
        Mock -ModuleName $script:moduleName Remove-OERErrorRecord { }
        $Err = $null
        $Result = Get-OERAccessPackage -Id 'ap-1' -ErrorAction SilentlyContinue -ErrorVariable Err
        $Result | Should -BeNullOrEmpty
        @($Err | Where-Object { $_.FullyQualifiedErrorId -eq 'Authorization_RequestDenied,Get-OERAccessPackage' }).Count |
            Should -Be 1
        Should -Invoke -ModuleName $script:moduleName Remove-OERErrorRecord -Times 1
    }

    It 'surfaces a Graph failure as a non-terminating error for the list path and emits nothing' {
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {
            throw [System.Management.Automation.ErrorRecord]::new(
                [System.Exception]::new('TooManyRequests: throttled.'),
                'TooManyRequests',
                [System.Management.Automation.ErrorCategory]::LimitsExceeded,
                $null)
        }
        Mock -ModuleName $script:moduleName Remove-OERErrorRecord { }
        $Err = $null
        $Result = Get-OERAccessPackage -ErrorAction SilentlyContinue -ErrorVariable Err
        $Result | Should -BeNullOrEmpty
        @($Err | Where-Object { $_.FullyQualifiedErrorId -eq 'TooManyRequests,Get-OERAccessPackage' }).Count |
            Should -Be 1
        Should -Invoke -ModuleName $script:moduleName Remove-OERErrorRecord -Times 1
    }

    It 'passes -All to the list read (closes rt-graph-list-reads-first-page-only)' {
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest { @{ value = @(@{ id = 'a'; displayName = 'A' }, @{ id = 'b'; displayName = 'B' }) } }
        Get-OERAccessPackage | Out-Null
        Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 1 -Exactly -ParameterFilter { $All }
    }

    It 'does NOT pass -All to the single-entity -Id read' {
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest { @{ id = 'ap-1'; displayName = 'AP-Sales' } } -ParameterFilter { $Uri -like '*accessPackages/ap-1*' }
        Get-OERAccessPackage -Id 'ap-1' | Out-Null
        Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 1 -Exactly -ParameterFilter { -not $All }
    }


    It 'expands resourceRoleScopes with -IncludeResourceRoles, never the beta accessPackageResourceRoleScopes' {
        # The v1.0 accessPackage relationships are accessPackagesIncompatibleWith, assignmentPolicies,
        # catalog, incompatibleAccessPackages, incompatibleGroups and resourceRoleScopes.
        # accessPackageResourceRoleScopes is the BETA spelling; sending it to this v1.0 endpoint is
        # rejected, so the switch used to break the whole read rather than just failing to expand.
        # Get-OERAccessPackageResourceRole already uses the v1.0 name against the same v1.0 URI.
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest { @{ value = @() } }
        Get-OERAccessPackage -IncludeResourceRoles | Out-Null
        Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 1 -Exactly -ParameterFilter {
            $Uri -like '*$expand=catalog,resourceRoleScopes*' -and $Uri -notlike '*accessPackageResourceRoleScopes*'
        }
    }

    Context 'catalog is always expanded so CatalogId is never structurally empty' {
        # The v1.0 accessPackage entity has NO catalogId property -- it exposes only createdDateTime,
        # description, displayName, id, isHidden and modifiedDateTime -- and catalog is a navigation
        # property, so without $expand=catalog the CatalogId that the Omnicit.EntraRBAC.AccessPackage
        # shape advertises (and that the table view prints as a column) is $null on every object the
        # module returns. Same class of gap, and the same fix, as the $expand=target,accessPackage
        # added to Get-OERAccessPackageAssignment.

        It 'requests $expand=catalog on the by-id read' {
            Mock -ModuleName $script:moduleName Invoke-OERGraphRequest { @{ id = 'ap-1'; displayName = 'AP-Sales' } }
            Get-OERAccessPackage -Id 'ap-1' | Out-Null
            Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 1 -Exactly -ParameterFilter {
                $Uri -match '\$expand=[^&]*\bcatalog\b'
            }
        }

        It 'requests $expand=catalog on the unfiltered list read' {
            Mock -ModuleName $script:moduleName Invoke-OERGraphRequest { @{ value = @() } }
            Get-OERAccessPackage | Out-Null
            Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 1 -Exactly -ParameterFilter {
                $Uri -match '\$expand=[^&]*\bcatalog\b'
            }
        }

        It 'keeps $expand=catalog alongside the -Catalog filter on the list read' {
            # The catalog-scoped list is the read Sync-OERStructureAccessPackage depends on, so the
            # filter and the expand have to survive the same query-string join.
            Mock -ModuleName $script:moduleName Resolve-OERCatalogId { 'cat-77' }
            Mock -ModuleName $script:moduleName Invoke-OERGraphRequest { @{ value = @() } }
            Get-OERAccessPackage -Catalog 'CAT-IT-Core' | Out-Null
            Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 1 -Exactly -ParameterFilter {
                $Uri -like "*filter=catalog/id eq 'cat-77'*" -and $Uri -match '\$expand=[^&]*\bcatalog\b'
            }
        }

        It 'binds -Catalog from a piped real Catalog object via the CatalogId alias, staying in the List parameter set' {
            # A real ConvertTo-OERCatalog object (not a hand-built pscustomobject) so the CatalogId
            # AliasProperty registered on Omnicit.EntraRBAC.Catalog is genuinely exercised. A GUID-shaped
            # id keeps Resolve-OERCatalogId's short-circuit in play (no Graph call to resolve it), so the
            # single Invoke-OERGraphRequest call below is unambiguously the accessPackages list read --
            # proving both the $filter and that ParameterSetName resolved to 'List' (only the List
            # branch ever builds a catalog/id filter).
            $CatalogObj = InModuleScope $script:moduleName {
                ConvertTo-OERCatalog -InputObject @{ id = 'aaaaaaaa-0000-0000-0000-000000000042'; displayName = 'CAT-IT-Core' }
            }
            Mock -ModuleName $script:moduleName Invoke-OERGraphRequest { @{ value = @() } }
            $CatalogObj | Get-OERAccessPackage | Out-Null
            Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 1 -Exactly -ParameterFilter {
                $Uri -like "*filter=catalog/id eq 'aaaaaaaa-0000-0000-0000-000000000042'*"
            }
        }

        It 'populates CatalogId from the expanded catalog navigation property' {
            Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {
                @{ id = 'ap-1'; displayName = 'AP-Sales'; catalog = @{ id = 'cat-77'; displayName = 'CAT-IT-Core' } }
            }
            $R = Get-OERAccessPackage -Id 'ap-1'
            # Prove the object exists before measuring it: $null.CatalogId is also $null, so a bare
            # property assertion would pass on nothing at all.
            $R | Should -Not -BeNullOrEmpty
            $R.Id | Should -BeExactly 'ap-1'
            $R.CatalogId | Should -BeExactly 'cat-77'
        }
    }

    Context 'expanded collections are surfaced (#58)' {
        # Get-OERAccessPackage -IncludeResourceRoles and -IncludePolicies correctly built the
        # $expand query all along; the bug was that ConvertTo-OERAccessPackage threw the expanded
        # collection away, so only these object-level assertions (not the URI-only assertions in
        # the 'expands ... with -Include*' tests above) can catch it.

        It 'surfaces AssignmentPolicies with -IncludePolicies (closes #58)' {
            # Asserts the returned OBJECT, not the URI -- the pre-existing 'expands policies with
            # -IncludePolicies' test above asserts only that the URI contains the expand, which is
            # exactly the shape that let the converter drop the expanded collection on the floor.
            Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {
                @{
                    id                 = 'ap-1'
                    displayName        = 'AP-Sales'
                    catalog            = @{ id = 'cat-1' }
                    assignmentPolicies = @(
                        @{ id = 'pol-1'; displayName = 'Default'; accessPackage = @{ id = 'ap-1' } }
                    )
                }
            }
            $R = Get-OERAccessPackage -Id 'ap-1' -IncludePolicies
            $R.AssignmentPolicies.Count | Should -Be 1
            $R.AssignmentPolicies[0].DisplayName | Should -Be 'Default'
            $R.AssignmentPolicies[0].PSObject.TypeNames[0] | Should -Be 'Omnicit.EntraRBAC.AssignmentPolicy'
        }

        It 'surfaces ResourceRoleScopes with -IncludeResourceRoles (closes #58)' {
            Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {
                @{
                    id                 = 'ap-1'
                    displayName        = 'AP-Sales'
                    catalog            = @{ id = 'cat-1' }
                    resourceRoleScopes = @(
                        @{ id = 'rrs-1'; role = @{ displayName = 'Member' }; scope = @{ displayName = 'Root'; originId = 'grp-1'; originSystem = 'AadGroup' } }
                    )
                }
            }
            $R = Get-OERAccessPackage -Id 'ap-1' -IncludeResourceRoles
            $R.ResourceRoleScopes.Count | Should -Be 1
            $R.ResourceRoleScopes[0].RoleName | Should -Be 'Member'
            $R.ResourceRoleScopes[0].PSObject.TypeNames[0] | Should -Be 'Omnicit.EntraRBAC.AccessPackageResourceRole'
        }

        It 'emits neither AssignmentPolicies nor ResourceRoleScopes when neither switch is supplied' {
            Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {
                @{ id = 'ap-1'; displayName = 'AP-Sales'; catalog = @{ id = 'cat-1' } }
            }
            $R = Get-OERAccessPackage -Id 'ap-1'
            $R.PSObject.Properties.Name | Should -Not -Contain 'AssignmentPolicies'
            $R.PSObject.Properties.Name | Should -Not -Contain 'ResourceRoleScopes'
        }

        It 'still binds the PACKAGE Id (not a policy Id) when a -IncludePolicies result is piped into Set-OERAccessPackageAssignmentPolicy' {
            # The pipeline binder does not descend into nested collections -- AssignmentPolicies being
            # visible on the object looks like it should let a policy inside it bind, but it cannot;
            # -Id on Set-OERAccessPackageAssignmentPolicy only ever sees the top-level (package) Id.
            Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {
                @{
                    id                 = 'ap-1'
                    displayName        = 'AP-Sales'
                    catalog            = @{ id = 'cat-1' }
                    assignmentPolicies = @(
                        @{ id = 'pol-1'; displayName = 'Default'; accessPackage = @{ id = 'ap-1' } }
                    )
                }
            } -ParameterFilter { $Uri -like '*accessPackages/ap-1*' }
            $Package = Get-OERAccessPackage -Id 'ap-1' -IncludePolicies
            $Package.AssignmentPolicies.Count | Should -Be 1

            Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {
                @{ id = 'pol-1'; accessPackage = @{ id = 'ap-1' }; displayName = 'Default' }
            } -ParameterFilter { -not $Method -or $Method -eq 'GET' }
            Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {
                @{ id = 'pol-1'; displayName = 'Default'; allowedTargetScope = 'allMemberUsers'; expiration = @{ type = 'noExpiration' } }
            } -ParameterFilter { $Method -eq 'PUT' }

            $Package | Set-OERAccessPackageAssignmentPolicy -DisplayName 'Default' -DurationInDays 30 -Confirm:$false | Out-Null

            Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 1 -Exactly -ParameterFilter {
                (-not $Method -or $Method -eq 'GET') -and $Uri -like '*assignmentPolicies/ap-1?*'
            }
        }
    }
}
