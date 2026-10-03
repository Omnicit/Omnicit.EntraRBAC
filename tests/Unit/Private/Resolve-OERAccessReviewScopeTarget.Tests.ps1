BeforeAll { Import-Module Omnicit.EntraRBAC -Force }

Describe 'Resolve-OERAccessReviewScopeTarget' {
    BeforeEach { InModuleScope Omnicit.EntraRBAC { $script:_OERAuthState = $null } }
    It 'derives the catalog from the v1.0 accessPackage catalog relationship (expand), not a catalogId scalar' {
        InModuleScope Omnicit.EntraRBAC {
            Mock Resolve-OERAccessPackageId { 'ap-id' }
            Mock Invoke-OERGraphRequest {
                param($Uri)
                # v1.0 accessPackage has NO catalogId scalar; the catalog is a navigation property.
                if ($Uri -like '*accessPackages/ap-id*') { return @{ id = 'ap-id'; catalog = @{ id = 'cat-id' } } }
                if ($Uri -like '*assignmentPolicies*')   { return @{ value = @(@{ id = 'pol-id'; displayName = 'Standard' }) } }
            }
            $r = Resolve-OERAccessReviewScopeTarget -AccessPackage 'AP' -AssignmentPolicy 'Standard'
            $r.AccessPackageId    | Should -Be 'ap-id'
            $r.CatalogId          | Should -Be 'cat-id'
            $r.AssignmentPolicyId | Should -Be 'pol-id'
            # The package read must expand the catalog relationship (a $select of catalogId 400s in v1.0).
            Should -Invoke Invoke-OERGraphRequest -ParameterFilter { $Uri -like '*accessPackages/ap-id*' -and $Uri -like '*$expand=catalog*' }
        }
    }
    It 'still accepts a legacy catalogId scalar if Graph returns one' {
        InModuleScope Omnicit.EntraRBAC {
            Mock Resolve-OERAccessPackageId { 'ap-id' }
            Mock Invoke-OERGraphRequest {
                param($Uri)
                if ($Uri -like '*accessPackages/ap-id*') { return @{ id = 'ap-id'; catalogId = 'cat-id' } }
                if ($Uri -like '*assignmentPolicies*')   { return @{ value = @(@{ id = 'pol-id'; displayName = 'Standard' }) } }
            }
            $r = Resolve-OERAccessReviewScopeTarget -AccessPackage 'AP' -AssignmentPolicy 'Standard'
            $r.CatalogId | Should -Be 'cat-id'
        }
    }
    It 'passes through a GUID policy without a policy query' {
        InModuleScope Omnicit.EntraRBAC {
            Mock Resolve-OERAccessPackageId { 'ap-id' }
            Mock Invoke-OERGraphRequest { @{ id = 'ap-id'; catalog = @{ id = 'cat-id' } } }
            $g = '44444444-4444-4444-4444-444444444444'
            $r = Resolve-OERAccessReviewScopeTarget -AccessPackage 'ap-id' -AssignmentPolicy $g
            $r.AssignmentPolicyId | Should -Be $g
            $r.CatalogId          | Should -Be 'cat-id'
        }
    }
    It 'uses an explicit -Catalog GUID without reading the package catalog' {
        InModuleScope Omnicit.EntraRBAC {
            Mock Resolve-OERAccessPackageId { 'ap-id' }
            Mock Invoke-OERGraphRequest {
                param($Uri)
                if ($Uri -like '*assignmentPolicies*') { return @{ value = @(@{ id = 'pol-id'; displayName = 'Standard' }) } }
            }
            $cat = '55555555-5555-5555-5555-555555555555'
            $r = Resolve-OERAccessReviewScopeTarget -AccessPackage 'ap-id' -AssignmentPolicy 'Standard' -Catalog $cat
            $r.CatalogId | Should -Be $cat
            Should -Invoke Invoke-OERGraphRequest -ParameterFilter { $Uri -like '*accessPackages*' } -Times 0
        }
    }
    It 'reports Catalog failure when the package exposes neither catalogId nor a catalog relationship' {
        InModuleScope Omnicit.EntraRBAC {
            Mock Resolve-OERAccessPackageId { 'ap-id' }
            Mock Invoke-OERGraphRequest { @{ id = 'ap-id' } }
            $r = Resolve-OERAccessReviewScopeTarget -AccessPackage 'AP' -AssignmentPolicy 'Standard'
            $r.FailedKind | Should -Be 'Catalog'
        }
    }
    It 'reports an unresolved access package' {
        InModuleScope Omnicit.EntraRBAC {
            Mock Resolve-OERAccessPackageId { $null }
            $r = Resolve-OERAccessReviewScopeTarget -AccessPackage 'ghost' -AssignmentPolicy 'x'
            $r.FailedKind | Should -Be 'AccessPackage'
        }
    }
    It 'reports a derived-catalog failure distinctly from a missing catalog' {
        InModuleScope Omnicit.EntraRBAC {
            Mock Resolve-OERAccessPackageId { 'ap-1' }
            Mock Invoke-OERGraphRequest { @{} }   # no catalogId and no catalog nav property
            $r = Resolve-OERAccessReviewScopeTarget -AccessPackage 'AP-Sales' -AssignmentPolicy 'Standard'
            $r.FailedErrorId | Should -Be 'CatalogDerivationFailed'
            $r.FailedMessage | Should -Match 'derive the catalog'
            $r.FailedMessage | Should -Match 'AP-Sales'
        }
    }
    It 'keeps the plain Catalog failure shape when -Catalog was supplied explicitly' {
        InModuleScope Omnicit.EntraRBAC {
            Mock Resolve-OERAccessPackageId { 'ap-1' }
            Mock Resolve-OERCatalogId { $null }
            $r = Resolve-OERAccessReviewScopeTarget -AccessPackage 'AP-Sales' -AssignmentPolicy 'Standard' -Catalog 'Ghost'
            $r.FailedKind    | Should -Be 'Catalog'
            $r.FailedValue   | Should -Be 'Ghost'
            $r.FailedErrorId | Should -BeNullOrEmpty
        }
    }
}

Describe 'Resolve-OERAccessReviewScopeTarget ambiguity handling' {
    BeforeEach { InModuleScope Omnicit.EntraRBAC { $script:_OERAuthState = $null } }

    It 'reports an ambiguous access package name through FailedErrorId/FailedMessage' {
        # This helper already owns an ErrorId/message channel, so the ambiguity travels through it and
        # the caller reports the candidate ids rather than a misleading "AccessPackage 'x' not found.".
        InModuleScope Omnicit.EntraRBAC {
            Mock Initialize-OERAuth { }
            Mock Remove-OERErrorRecord { }
            Mock Invoke-OERGraphRequest { }
            Mock Resolve-OERAccessPackageId {
                throw [System.Management.Automation.ErrorRecord]::new(
                    [System.Exception]::new("Access package display name 'Dup' matches 2 access packages (aaa-1, bbb-2)."),
                    'AmbiguousName', [System.Management.Automation.ErrorCategory]::InvalidArgument, 'Dup')
            }
            $R = Resolve-OERAccessReviewScopeTarget -AccessPackage 'Dup' -AssignmentPolicy 'Standard'
            $R.FailedKind    | Should -Be 'AccessPackage'
            $R.FailedErrorId | Should -Be 'AmbiguousAccessPackageName'
            $R.FailedMessage | Should -Match 'aaa-1'
            Should -Invoke Remove-OERErrorRecord -Times 1
            Should -Invoke Invoke-OERGraphRequest -Times 0
        }
    }

    It 'reports an ambiguous catalog name through FailedErrorId/FailedMessage' {
        InModuleScope Omnicit.EntraRBAC {
            Mock Initialize-OERAuth { }
            Mock Remove-OERErrorRecord { }
            Mock Invoke-OERGraphRequest { }
            Mock Resolve-OERAccessPackageId { 'ap-id' }
            Mock Resolve-OERCatalogId {
                throw [System.Management.Automation.ErrorRecord]::new(
                    [System.Exception]::new("Catalog display name 'Dup' matches 2 catalogs (ccc-1, ddd-2)."),
                    'AmbiguousName', [System.Management.Automation.ErrorCategory]::InvalidArgument, 'Dup')
            }
            $R = Resolve-OERAccessReviewScopeTarget -AccessPackage 'AP' -AssignmentPolicy 'Standard' -Catalog 'Dup'
            $R.FailedKind    | Should -Be 'Catalog'
            $R.FailedErrorId | Should -Be 'AmbiguousCatalogName'
            $R.FailedMessage | Should -Match 'ccc-1'
        }
    }

    It 'still reports a genuine access package no-match with no ErrorId override' {
        InModuleScope Omnicit.EntraRBAC {
            Mock Initialize-OERAuth { }
            Mock Invoke-OERGraphRequest { }
            Mock Resolve-OERAccessPackageId { $null }
            $R = Resolve-OERAccessReviewScopeTarget -AccessPackage 'missing' -AssignmentPolicy 'Standard'
            $R.FailedKind    | Should -Be 'AccessPackage'
            $R.FailedValue   | Should -Be 'missing'
            $R.FailedErrorId | Should -Be $null
        }
    }
}

Describe 'Resolve-OERAccessReviewScopeTarget -- a failed resolver read is not a not-found (issue #71, fix round 1)' {
    BeforeAll {
        $script:moduleName = 'Omnicit.EntraRBAC'
        Import-Module $script:moduleName -Force -ErrorAction Stop
    }

    It 'carries a 403 out of Resolve-OERAccessPackageId through the Fail channel with its own id, message and category' {
        $Result = InModuleScope $script:moduleName {
            Mock Resolve-OERAccessPackageId {
                throw [System.Management.Automation.ErrorRecord]::new(
                    [System.Exception]::new('Authorization_RequestDenied: Insufficient privileges to complete the operation.'),
                    'Authorization_RequestDenied',
                    [System.Management.Automation.ErrorCategory]::PermissionDenied,
                    'ap-target')
            }
            Mock Invoke-OERGraphRequest {}
            Resolve-OERAccessReviewScopeTarget -AccessPackage 'AP-Sales' -AssignmentPolicy '11111111-1111-1111-1111-111111111111'
        }
        $Result.FailedKind | Should -Be 'AccessPackage'
        $Result.FailedErrorId | Should -Be 'Authorization_RequestDenied'
        $Result.FailedErrorId | Should -Not -Be 'AccessPackageNotFound'
        $Result.FailedMessage | Should -Match 'Insufficient privileges'
        $Result.FailedCategory | Should -Be 'PermissionDenied'
    }

    It 'carries the resolver AccessPackageNotFound message rather than the generic not-found text' {
        $Result = InModuleScope $script:moduleName {
            Mock Resolve-OERAccessPackageId {
                throw [System.Management.Automation.ErrorRecord]::new(
                    [System.Exception]::new("The access package id '33333333-3333-3333-3333-333333333333' does not resolve to an access package in this tenant."),
                    'AccessPackageNotFound',
                    [System.Management.Automation.ErrorCategory]::ObjectNotFound,
                    '33333333-3333-3333-3333-333333333333')
            }
            Mock Invoke-OERGraphRequest {}
            Resolve-OERAccessReviewScopeTarget -AccessPackage '33333333-3333-3333-3333-333333333333' -AssignmentPolicy '11111111-1111-1111-1111-111111111111'
        }
        $Result.FailedErrorId | Should -Be 'AccessPackageNotFound'
        $Result.FailedMessage | Should -Match 'does not resolve to an access package in this tenant'
        $Result.FailedCategory | Should -Be 'ObjectNotFound'
    }

    It 'still leaves FailedErrorId and FailedCategory null on a plain $null no-match, so the caller keeps its own derivation' {
        $Result = InModuleScope $script:moduleName {
            Mock Resolve-OERAccessPackageId { $null }
            Mock Invoke-OERGraphRequest {}
            Resolve-OERAccessReviewScopeTarget -AccessPackage 'No-Such-Package' -AssignmentPolicy '11111111-1111-1111-1111-111111111111'
        }
        $Result.FailedKind | Should -Be 'AccessPackage'
        $Result.FailedValue | Should -Be 'No-Such-Package'
        $Result.FailedErrorId | Should -BeNullOrEmpty
        $Result.FailedCategory | Should -BeNullOrEmpty
    }
}

Describe 'Resolve-OERAccessReviewScopeTarget -- a failed catalog or policy read is not a not-found' {
    BeforeEach { InModuleScope 'Omnicit.EntraRBAC' { $script:_OERAuthState = $null } }

    # The access package branch already carries a failure out through FailedErrorId/FailedMessage/
    # FailedCategory. The explicit -Catalog branch and the assignment policy listing used to swallow
    # a failed read into the plain not-found shape; they now hand the caught record out in FailedRecord,
    # the ONE carrier all three descriptor resolvers share, and leave the three companions null.

    It 'carries a 403 out of Resolve-OERCatalogId for an explicit -Catalog name in FailedRecord' {
        InModuleScope 'Omnicit.EntraRBAC' {
            Mock Remove-OERErrorRecord { }
            Mock Invoke-OERGraphRequest { }
            Mock Resolve-OERAccessPackageId { 'ap-1' }
            Mock Resolve-OERCatalogId {
                throw [System.Management.Automation.ErrorRecord]::new(
                    [System.Exception]::new('Authorization_RequestDenied: Insufficient privileges to complete the operation.'),
                    'Authorization_RequestDenied', [System.Management.Automation.ErrorCategory]::PermissionDenied, 'Denied Catalog')
            }
            $R = Resolve-OERAccessReviewScopeTarget -AccessPackage 'AP-Sales' -AssignmentPolicy 'Standard' -Catalog 'Denied Catalog'
            $R.FailedRecord                       | Should -Not -BeNullOrEmpty
            $R.FailedRecord.FullyQualifiedErrorId | Should -Match '^Authorization_RequestDenied'
            $R.FailedRecord.CategoryInfo.Category | Should -Be 'PermissionDenied'
            $R.FailedKind                         | Should -Be 'Catalog'
            $R.FailedValue                        | Should -Be 'Denied Catalog'
            $R.FailedErrorId                      | Should -BeNullOrEmpty
            $R.FailedMessage                      | Should -BeNullOrEmpty
            $R.FailedCategory                     | Should -BeNullOrEmpty
            Should -Invoke Invoke-OERGraphRequest -Times 0
        }
    }

    It 'carries a 403 out of the assignment policy listing in FailedRecord' {
        InModuleScope 'Omnicit.EntraRBAC' {
            Mock Remove-OERErrorRecord { }
            Mock Resolve-OERAccessPackageId { 'ap-1' }
            Mock Invoke-OERGraphRequest {
                param($Uri)
                if ($Uri -like '*assignmentPolicies*') {
                    throw [System.Management.Automation.ErrorRecord]::new(
                        [System.Exception]::new('Authorization_RequestDenied: Insufficient privileges to complete the operation.'),
                        'Authorization_RequestDenied', [System.Management.Automation.ErrorCategory]::PermissionDenied, 'ap-1')
                }
                return @{ id = 'ap-1'; catalog = @{ id = 'cat-1' } }
            }
            $R = Resolve-OERAccessReviewScopeTarget -AccessPackage 'AP-Sales' -AssignmentPolicy 'Standard'
            $R.FailedRecord                       | Should -Not -BeNullOrEmpty
            $R.FailedRecord.FullyQualifiedErrorId | Should -Match '^Authorization_RequestDenied'
            $R.FailedRecord.CategoryInfo.Category | Should -Be 'PermissionDenied'
            $R.FailedKind                         | Should -Be 'AssignmentPolicy'
            $R.FailedValue                        | Should -Be 'Standard'
            $R.FailedErrorId                      | Should -BeNullOrEmpty
            $R.FailedMessage                      | Should -BeNullOrEmpty
            $R.FailedCategory                     | Should -BeNullOrEmpty
            # The listing was reached: the descriptor is a failure of that read, not of an earlier step.
            Should -Invoke Invoke-OERGraphRequest -Times 1 -Exactly -ParameterFilter { $Uri -like '*assignmentPolicies*' }
        }
    }

    It 'still reports a policy name that matched nothing as a plain not-found, with no FailedRecord' {
        InModuleScope 'Omnicit.EntraRBAC' {
            Mock Resolve-OERAccessPackageId { 'ap-1' }
            Mock Invoke-OERGraphRequest {
                param($Uri)
                if ($Uri -like '*assignmentPolicies*') { return @{ value = @(@{ id = 'pol-1'; displayName = 'Other' }) } }
                return @{ id = 'ap-1'; catalog = @{ id = 'cat-1' } }
            }
            $R = Resolve-OERAccessReviewScopeTarget -AccessPackage 'AP-Sales' -AssignmentPolicy 'Standard'
            $R.FailedKind    | Should -Be 'AssignmentPolicy'
            $R.FailedValue   | Should -Be 'Standard'
            $R.FailedErrorId | Should -BeNullOrEmpty
            $R.FailedRecord  | Should -BeNullOrEmpty
            $R.ContainsKey('FailedRecord') | Should -BeTrue
        }
    }

    It 'still reports an explicit catalog name that matched nothing as a plain not-found, with no FailedRecord' {
        InModuleScope 'Omnicit.EntraRBAC' {
            Mock Resolve-OERAccessPackageId { 'ap-1' }
            Mock Resolve-OERCatalogId { $null }
            $R = Resolve-OERAccessReviewScopeTarget -AccessPackage 'AP-Sales' -AssignmentPolicy 'Standard' -Catalog 'Ghost'
            $R.FailedKind    | Should -Be 'Catalog'
            $R.FailedValue   | Should -Be 'Ghost'
            $R.FailedErrorId | Should -BeNullOrEmpty
            $R.FailedRecord  | Should -BeNullOrEmpty
            $R.ContainsKey('FailedRecord') | Should -BeTrue
        }
    }

    It 'leaves FailedRecord null on the ambiguity and access package paths, which keep their own companions' {
        InModuleScope 'Omnicit.EntraRBAC' {
            Mock Remove-OERErrorRecord { }
            Mock Resolve-OERAccessPackageId { 'ap-1' }
            Mock Resolve-OERCatalogId {
                throw [System.Management.Automation.ErrorRecord]::new(
                    [System.Exception]::new("Catalog display name 'Dup' matches 2 catalogs (ccc-1, ddd-2)."),
                    'AmbiguousName', [System.Management.Automation.ErrorCategory]::InvalidArgument, 'Dup')
            }
            $R = Resolve-OERAccessReviewScopeTarget -AccessPackage 'AP' -AssignmentPolicy 'Standard' -Catalog 'Dup'
            $R.FailedErrorId | Should -Be 'AmbiguousCatalogName'
            $R.FailedRecord  | Should -BeNullOrEmpty

            Mock Resolve-OERAccessPackageId {
                throw [System.Management.Automation.ErrorRecord]::new(
                    [System.Exception]::new('Authorization_RequestDenied: Insufficient privileges to complete the operation.'),
                    'Authorization_RequestDenied', [System.Management.Automation.ErrorCategory]::PermissionDenied, 'AP')
            }
            $P = Resolve-OERAccessReviewScopeTarget -AccessPackage 'AP' -AssignmentPolicy 'Standard'
            $P.FailedErrorId  | Should -Be 'Authorization_RequestDenied'
            $P.FailedCategory | Should -Be 'PermissionDenied'
            $P.FailedRecord   | Should -BeNullOrEmpty
        }
    }

    It 'keeps CatalogDerivationFailed, with no FailedRecord, when the derived-catalog read of the package throws' {
        # A failure id already, so it is deliberately left as it was (Ruling S3 / task brief).
        InModuleScope 'Omnicit.EntraRBAC' {
            Mock Remove-OERErrorRecord { }
            Mock Resolve-OERAccessPackageId { 'ap-1' }
            Mock Invoke-OERGraphRequest {
                throw [System.Management.Automation.ErrorRecord]::new(
                    [System.Exception]::new('Authorization_RequestDenied: Insufficient privileges to complete the operation.'),
                    'Authorization_RequestDenied', [System.Management.Automation.ErrorCategory]::PermissionDenied, 'ap-1')
            }
            $R = Resolve-OERAccessReviewScopeTarget -AccessPackage 'AP-Sales' -AssignmentPolicy 'Standard'
            $R.FailedKind    | Should -Be 'Catalog'
            $R.FailedErrorId | Should -Be 'CatalogDerivationFailed'
            $R.FailedRecord  | Should -BeNullOrEmpty
        }
    }

    It 'carries a FailedRecord key, null, on a successful descriptor' {
        InModuleScope 'Omnicit.EntraRBAC' {
            Mock Resolve-OERAccessPackageId { 'ap-1' }
            Mock Invoke-OERGraphRequest {
                param($Uri)
                if ($Uri -like '*assignmentPolicies*') { return @{ value = @(@{ id = 'pol-1'; displayName = 'Standard' }) } }
                return @{ id = 'ap-1'; catalog = @{ id = 'cat-1' } }
            }
            $R = Resolve-OERAccessReviewScopeTarget -AccessPackage 'AP-Sales' -AssignmentPolicy 'Standard'
            $R.AssignmentPolicyId          | Should -Be 'pol-1'
            $R.ContainsKey('FailedRecord') | Should -BeTrue
            $R.FailedRecord                | Should -BeNullOrEmpty
            $R.FailedValue                 | Should -BeNullOrEmpty
        }
    }

    It 'scrubs the failed Resolve-OERCatalogId record before carrying it out (bearer hygiene)' {
        # The catch hands the record on instead of discarding it, so an $Error-count proof stays green with
        # the scrub deleted. Guard the call itself (rationale.md, #bearer-scrub-tests); the FailedRecord
        # assertion beside it is the positive proof that this catch was reached.
        InModuleScope 'Omnicit.EntraRBAC' {
            Mock Remove-OERErrorRecord { }
            Mock Invoke-OERGraphRequest { }
            Mock Resolve-OERAccessPackageId { 'ap-1' }
            Mock Resolve-OERCatalogId {
                throw [System.Management.Automation.ErrorRecord]::new(
                    [System.Exception]::new('Authorization_RequestDenied: catalog lookup scrub marker.'),
                    'Authorization_RequestDenied', [System.Management.Automation.ErrorCategory]::PermissionDenied, 'Denied Catalog')
            }
            $R = Resolve-OERAccessReviewScopeTarget -AccessPackage 'AP-Sales' -AssignmentPolicy 'Standard' -Catalog 'Denied Catalog'
            $R.FailedRecord.Exception.Message | Should -Be 'Authorization_RequestDenied: catalog lookup scrub marker.'
            Should -Invoke Remove-OERErrorRecord -Times 1 -Exactly -ParameterFilter {
                $Record.Exception.Message -eq 'Authorization_RequestDenied: catalog lookup scrub marker.'
            }
        }
    }

    It 'scrubs the failed assignment policy listing record before carrying it out (bearer hygiene)' {
        InModuleScope 'Omnicit.EntraRBAC' {
            Mock Remove-OERErrorRecord { }
            Mock Resolve-OERAccessPackageId { 'ap-1' }
            Mock Invoke-OERGraphRequest {
                param($Uri)
                if ($Uri -like '*assignmentPolicies*') {
                    throw [System.Management.Automation.ErrorRecord]::new(
                        [System.Exception]::new('Authorization_RequestDenied: policy listing scrub marker.'),
                        'Authorization_RequestDenied', [System.Management.Automation.ErrorCategory]::PermissionDenied, 'ap-1')
                }
                return @{ id = 'ap-1'; catalog = @{ id = 'cat-1' } }
            }
            $R = Resolve-OERAccessReviewScopeTarget -AccessPackage 'AP-Sales' -AssignmentPolicy 'Standard'
            $R.FailedRecord.Exception.Message | Should -Be 'Authorization_RequestDenied: policy listing scrub marker.'
            Should -Invoke Remove-OERErrorRecord -Times 1 -Exactly -ParameterFilter {
                $Record.Exception.Message -eq 'Authorization_RequestDenied: policy listing scrub marker.'
            }
        }
    }
}

Describe 'New-OERAccessReviewDefinition -- a failed scope resolve is not a not-found (issue #71, fix round 1)' {
    BeforeEach {
        InModuleScope 'Omnicit.EntraRBAC' { $script:_OERAuthState = $null }
        Mock -ModuleName 'Omnicit.EntraRBAC' Initialize-OERAuth {}
        Mock -ModuleName 'Omnicit.EntraRBAC' Invoke-OERGraphRequest {}
    }

    It 'reports the resolver 403 with its own id and PermissionDenied, and POSTs nothing' {
        Mock -ModuleName 'Omnicit.EntraRBAC' Resolve-OERAccessPackageId {
            throw [System.Management.Automation.ErrorRecord]::new(
                [System.Exception]::new('Authorization_RequestDenied: Insufficient privileges to complete the operation.'),
                'Authorization_RequestDenied',
                [System.Management.Automation.ErrorCategory]::PermissionDenied,
                'ap-target')
        }
        $Err = $null
        New-OERAccessReviewDefinition -DisplayName 'Q3' -DescriptionForAdmins 'x' -DescriptionForReviewers 'x' `
            -AccessPackage 'AP-Sales' -AssignmentPolicy '11111111-1111-1111-1111-111111111111' `
            -Recurrence OneTime -StartDate (Get-Date) -SelfReview -Confirm:$false `
            -ErrorAction SilentlyContinue -ErrorVariable Err | Out-Null

        # Narrowed to the record this cmdlet published: see the note in the public guard suites --
        # -ErrorVariable also holds the engine's capture of the inner throw, which carries the bare
        # id regardless of what this cmdlet did with it.
        $Published = @($Err) | Where-Object {
            $_.InvocationInfo -and $_.InvocationInfo.MyCommand -and
            $_.InvocationInfo.MyCommand.Name -eq 'New-OERAccessReviewDefinition'
        }
        @($Published).Count | Should -Be 1
        $Published[0].FullyQualifiedErrorId | Should -Match '^Authorization_RequestDenied'
        $Published[0].FullyQualifiedErrorId | Should -Not -Match 'AccessPackageNotFound'
        $Published[0].CategoryInfo.Category | Should -Be 'PermissionDenied'
        Should -Invoke -ModuleName 'Omnicit.EntraRBAC' Invoke-OERGraphRequest -Times 0 -Exactly -ParameterFilter { $Method -eq 'POST' }
    }
}

# Decision D3 (Philip, 2026-10-03): the assignment policy listing used to be cut down with
# Select-Object -First 1 on the display name, so a package whose policies share a name had its review
# scoped to whichever policy Graph listed first. Graph does not enforce unique policy display names
# within a package. The descriptor now says so, through the same FailedErrorId/FailedMessage/
# FailedCategory triple the access package branch already uses, and carries no ids at all.
Describe 'Resolve-OERAccessReviewScopeTarget -- an ambiguous assignment policy name is refused (decision D3)' {
    BeforeEach { InModuleScope 'Omnicit.EntraRBAC' { $script:_OERAuthState = $null } }

    It 'returns the AmbiguousName descriptor naming every candidate id, and resolves no policy id' {
        InModuleScope 'Omnicit.EntraRBAC' {
            Mock Initialize-OERAuth { }
            Mock Resolve-OERAccessPackageId { 'ap-1' }
            Mock Invoke-OERGraphRequest {
                param($Uri)
                if ($Uri -like '*assignmentPolicies*') {
                    return @{ value = @(
                            @{ id = '11111111-1111-1111-1111-111111111111'; displayName = 'Standard' }
                            @{ id = '22222222-2222-2222-2222-222222222222'; displayName = 'Standard' }
                        ) }
                }
                return @{ id = 'ap-1'; catalog = @{ id = 'cat-1' } }
            }
            $R = Resolve-OERAccessReviewScopeTarget -AccessPackage 'AP-Sales' -AssignmentPolicy 'Standard'

            # Positive proof first: the listing was reached, once, so the descriptor below is the
            # answer to that listing and not to an earlier step.
            Should -Invoke Invoke-OERGraphRequest -Times 1 -Exactly -ParameterFilter { $Uri -like '*assignmentPolicies*' }

            $R.FailedKind     | Should -Be 'AssignmentPolicy'
            $R.FailedValue    | Should -Be 'Standard'
            $R.FailedErrorId  | Should -Be 'AmbiguousName'
            $R.FailedCategory | Should -Be 'InvalidArgument'
            $R.FailedRecord   | Should -BeNullOrEmpty
            $R.AssignmentPolicyId | Should -BeNullOrEmpty
            $R.AccessPackageId    | Should -BeNullOrEmpty
            $R.CatalogId          | Should -BeNullOrEmpty
            $R.FailedMessage | Should -BeLike "Assignment policy display name 'Standard' matches 2 policies (*) in access package 'AP-Sales'.*"
            $R.FailedMessage | Should -BeLike '*11111111-1111-1111-1111-111111111111*'
            $R.FailedMessage | Should -BeLike '*22222222-2222-2222-2222-222222222222*'
            $R.FailedMessage | Should -BeLike '*Access packages do not enforce unique policy display names, so this name cannot identify a single policy.*'
            # A GUID -AssignmentPolicy skips the listing, so here the id IS the way out.
            $R.FailedMessage | Should -BeLike '*Re-run with the assignment policy id instead of the display name.'
        }
    }

    It 'names every candidate and the right count when three policies share the name' {
        InModuleScope 'Omnicit.EntraRBAC' {
            Mock Initialize-OERAuth { }
            Mock Resolve-OERAccessPackageId { 'ap-1' }
            Mock Invoke-OERGraphRequest {
                param($Uri)
                if ($Uri -like '*assignmentPolicies*') {
                    return @{ value = @(
                            @{ id = '11111111-1111-1111-1111-111111111111'; displayName = 'Standard' }
                            @{ id = '22222222-2222-2222-2222-222222222222'; displayName = 'Standard' }
                            @{ id = '33333333-3333-3333-3333-333333333333'; displayName = 'Standard' }
                        ) }
                }
                return @{ id = 'ap-1'; catalog = @{ id = 'cat-1' } }
            }
            $R = Resolve-OERAccessReviewScopeTarget -AccessPackage 'AP-Sales' -AssignmentPolicy 'Standard'

            Should -Invoke Invoke-OERGraphRequest -Times 1 -Exactly -ParameterFilter { $Uri -like '*assignmentPolicies*' }
            $R.FailedErrorId | Should -Be 'AmbiguousName'
            $R.FailedMessage | Should -BeLike "*matches 3 policies (*33333333-3333-3333-3333-333333333333*) in access package 'AP-Sales'.*"
            $R.FailedMessage | Should -BeLike '*11111111-1111-1111-1111-111111111111*'
            $R.FailedMessage | Should -BeLike '*22222222-2222-2222-2222-222222222222*'
        }
    }

    It 'resolves a single matching policy even when the package holds policies of other names (no ambiguity)' {
        InModuleScope 'Omnicit.EntraRBAC' {
            Mock Initialize-OERAuth { }
            Mock Resolve-OERAccessPackageId { 'ap-1' }
            Mock Invoke-OERGraphRequest {
                param($Uri)
                if ($Uri -like '*assignmentPolicies*') {
                    return @{ value = @(
                            @{ id = '11111111-1111-1111-1111-111111111111'; displayName = 'Standard' }
                            @{ id = '22222222-2222-2222-2222-222222222222'; displayName = 'Other' }
                        ) }
                }
                return @{ id = 'ap-1'; catalog = @{ id = 'cat-1' } }
            }
            $R = Resolve-OERAccessReviewScopeTarget -AccessPackage 'AP-Sales' -AssignmentPolicy 'Standard'

            Should -Invoke Invoke-OERGraphRequest -Times 1 -Exactly -ParameterFilter { $Uri -like '*assignmentPolicies*' }
            $R.AssignmentPolicyId | Should -Be '11111111-1111-1111-1111-111111111111'
            $R.FailedKind         | Should -BeNullOrEmpty
            $R.FailedErrorId      | Should -BeNullOrEmpty
        }
    }

    It 'does not list the policies at all when -AssignmentPolicy is a GUID, so the id is the way out of the ambiguity' {
        InModuleScope 'Omnicit.EntraRBAC' {
            Mock Initialize-OERAuth { }
            Mock Resolve-OERAccessPackageId { 'ap-1' }
            Mock Invoke-OERGraphRequest {
                param($Uri)
                if ($Uri -like '*assignmentPolicies*') {
                    throw 'Unexpected assignment policy listing for a GUID -AssignmentPolicy.'
                }
                return @{ id = 'ap-1'; catalog = @{ id = 'cat-1' } }
            }
            $R = Resolve-OERAccessReviewScopeTarget -AccessPackage 'AP-Sales' -AssignmentPolicy '22222222-2222-2222-2222-222222222222'

            # Positive proof first: the package read was reached, so the descriptor is a success and not
            # a lookup that stopped early.
            Should -Invoke Invoke-OERGraphRequest -Times 1 -Exactly -ParameterFilter { $Uri -like '*accessPackages/ap-1*' }
            Should -Invoke Invoke-OERGraphRequest -Times 0 -ParameterFilter { $Uri -like '*assignmentPolicies*' }
            $R.AssignmentPolicyId | Should -Be '22222222-2222-2222-2222-222222222222'
            $R.FailedErrorId      | Should -BeNullOrEmpty
        }
    }
}
