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
