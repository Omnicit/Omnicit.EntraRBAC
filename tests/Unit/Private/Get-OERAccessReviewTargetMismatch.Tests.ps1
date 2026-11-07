BeforeAll {
    Import-Module Omnicit.EntraRBAC -Force
    . "$PSScriptRoot/../TestHelpers/OERTransportTripwire.ps1"
    Install-OERTransportTripwire
}

AfterAll {
    try { Assert-OERTransportTripwire } finally { Uninstall-OERTransportTripwire }
}

# BL-127 (Sprint 11 step 2, Rulings R8 and R9). The apply engine finds a live access review by display
# name, and display names are not unique, so before it updates the review it found it asks this helper
# whether that review reviews the access package and assignment policy the document entry declares.
# The helper returns nothing on a match and one error record otherwise, which it never writes. The two
# resolvers are mocked here; their own tests prove the lookups. No id below is version-4 shaped.
Describe 'Get-OERAccessReviewTargetMismatch' {
    BeforeAll {
        $script:TcName = 'Q3 AP review'
        $script:TcPkgId = 'aaaa1111-0000-0000-0000-000000000001'
        $script:TcOtherPkgId = 'aaaa1111-0000-0000-0000-000000000002'
        $script:TcPolId = 'bbbb2222-0000-0000-0000-000000000001'
        $script:TcOtherPolId = 'bbbb2222-0000-0000-0000-000000000002'
        $script:TcGroupScope = '/groups/11111111-1111-1111-1111-111111111111/transitiveMembers'
        $script:TcNotUnique = 'Access review display names are not unique: give the entry or the review in the tenant another display name.'

        # The live definition as ConvertTo-OERAccessReviewDefinition shapes it.
        function New-TcLive {
            param([string]$Scope, [string]$AccessPackageId, [string]$AssignmentPolicyId)
            [PSCustomObject]@{
                AccessReviewDefinitionId = 'cccc3333-0000-0000-0000-000000000001'
                DisplayName              = $script:TcName
                Scope                    = $Scope
                AccessPackageId          = $AccessPackageId
                AssignmentPolicyId       = $AssignmentPolicyId
            }
        }
        function New-TcPackageLive {
            New-TcLive -Scope ("/identityGovernance/entitlementManagement/assignments?`$filter=(accessPackage/id eq '{0}' and assignmentPolicy/id eq '{1}')" -f $script:TcPkgId, $script:TcPolId) `
                -AccessPackageId $script:TcPkgId -AssignmentPolicyId $script:TcPolId
        }
        function New-TcEntry {
            param($AccessPackage, $AssignmentPolicy)
            [PSCustomObject]@{ displayName = $script:TcName; accessPackage = $AccessPackage; assignmentPolicy = $AssignmentPolicy; durationInDays = 21 }
        }
        # Runs the helper in module scope and returns what it output, and what it wrote as errors and
        # warnings.
        function Invoke-TargetCheck {
            param([Parameter(Mandatory)]$Declared, [Parameter(Mandatory)]$Current)
            InModuleScope Omnicit.EntraRBAC -Parameters @{ Declared = $Declared; Current = $Current } {
                param($Declared, $Current)
                $Ev = $null
                $Wv = $null
                $Out = @(Get-OERAccessReviewTargetMismatch -Declared $Declared -Current $Current -ErrorAction Continue -ErrorVariable Ev `
                        -WarningAction SilentlyContinue -WarningVariable Wv)
                [PSCustomObject]@{ Out = $Out; Errors = @($Ev); Warnings = @($Wv) }
            }
        }
    }

    BeforeEach {
        InModuleScope Omnicit.EntraRBAC { $script:_OERAuthState = $null }
        Mock -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest { throw 'Unexpected Graph request.' }
        Mock -ModuleName Omnicit.EntraRBAC Resolve-OERAccessPackageId { throw 'Unexpected access package lookup.' }
        Mock -ModuleName Omnicit.EntraRBAC Resolve-OERAssignmentPolicyId { throw 'Unexpected assignment policy lookup.' }
    }

    Context 'a live review that reviews no access package' {
        It 'refuses a group review by name before any lookup' {
            $R = Invoke-TargetCheck -Declared (New-TcEntry -AccessPackage 'AP-Sales' -AssignmentPolicy 'Standard') `
                -Current (New-TcLive -Scope $script:TcGroupScope)
            $R.Out.Count | Should -Be 1
            $Record = $R.Out[0]
            $Record | Should -BeOfType ([System.Management.Automation.ErrorRecord])
            [string]$Record.FullyQualifiedErrorId | Should -BeExactly 'AccessReviewScopeMismatch'
            $Record.CategoryInfo.Category | Should -Be 'InvalidOperation'
            $Record.TargetObject | Should -BeExactly $script:TcName
            $Record.Exception.Message | Should -BeExactly ("Access review 'Q3 AP review' in the tenant does not review an access package " +
                "(its scope is '$($script:TcGroupScope)'), so it is not the review this entry declares for access package 'AP-Sales' " +
                "and assignment policy 'Standard'. Nothing was written. $($script:TcNotUnique)")
            Should -Invoke -ModuleName Omnicit.EntraRBAC Resolve-OERAccessPackageId -Times 0
            Should -Invoke -ModuleName Omnicit.EntraRBAC Resolve-OERAssignmentPolicyId -Times 0
            $R.Errors.Count | Should -Be 0
            $R.Warnings.Count | Should -Be 0
        }

        It 'names the scope as none when the live review carries no scope' {
            $R = Invoke-TargetCheck -Declared (New-TcEntry -AccessPackage 'AP-Sales' -AssignmentPolicy 'Standard') `
                -Current (New-TcLive -Scope '')
            $R.Out.Count | Should -Be 1
            [string]$R.Out[0].FullyQualifiedErrorId | Should -BeExactly 'AccessReviewScopeMismatch'
            $R.Out[0].Exception.Message | Should -BeExactly ("Access review 'Q3 AP review' in the tenant does not review an access package " +
                "(its scope is 'none'), so it is not the review this entry declares for access package 'AP-Sales' " +
                "and assignment policy 'Standard'. Nothing was written. $($script:TcNotUnique)")
            Should -Invoke -ModuleName Omnicit.EntraRBAC Resolve-OERAccessPackageId -Times 0
            Should -Invoke -ModuleName Omnicit.EntraRBAC Resolve-OERAssignmentPolicyId -Times 0
        }
    }

    Context 'declared by id' {
        It 'returns nothing when both ids are the live ones, in any letter case, and looks nothing up' {
            $R = Invoke-TargetCheck -Declared (New-TcEntry -AccessPackage $script:TcPkgId.ToUpperInvariant() -AssignmentPolicy $script:TcPolId.ToUpperInvariant()) `
                -Current (New-TcPackageLive)
            $R.Out.Count | Should -Be 0
            Should -Invoke -ModuleName Omnicit.EntraRBAC Resolve-OERAccessPackageId -Times 0
            Should -Invoke -ModuleName Omnicit.EntraRBAC Resolve-OERAssignmentPolicyId -Times 0
            $R.Errors.Count | Should -Be 0
            $R.Warnings.Count | Should -Be 0
        }

        It 'refuses another package id, naming both, and looks nothing up' {
            $R = Invoke-TargetCheck -Declared (New-TcEntry -AccessPackage $script:TcOtherPkgId -AssignmentPolicy $script:TcPolId) `
                -Current (New-TcPackageLive)
            $R.Out.Count | Should -Be 1
            [string]$R.Out[0].FullyQualifiedErrorId | Should -BeExactly 'AccessReviewScopeMismatch'
            $R.Out[0].CategoryInfo.Category | Should -Be 'InvalidOperation'
            $R.Out[0].TargetObject | Should -BeExactly $script:TcName
            $R.Out[0].Exception.Message | Should -BeExactly ("Access review 'Q3 AP review' in the tenant reviews access package '$($script:TcPkgId)', " +
                "not the access package '$($script:TcOtherPkgId)' this entry declares, so it is not the review this entry declares. " +
                "Nothing was written. $($script:TcNotUnique)")
            Should -Invoke -ModuleName Omnicit.EntraRBAC Resolve-OERAccessPackageId -Times 0
            Should -Invoke -ModuleName Omnicit.EntraRBAC Resolve-OERAssignmentPolicyId -Times 0
        }

        It 'refuses another policy id of the same package, naming both' {
            $R = Invoke-TargetCheck -Declared (New-TcEntry -AccessPackage $script:TcPkgId -AssignmentPolicy $script:TcOtherPolId) `
                -Current (New-TcPackageLive)
            $R.Out.Count | Should -Be 1
            [string]$R.Out[0].FullyQualifiedErrorId | Should -BeExactly 'AccessReviewScopeMismatch'
            $R.Out[0].Exception.Message | Should -BeExactly ("Access review 'Q3 AP review' in the tenant reviews assignment policy '$($script:TcPolId)' " +
                "of access package '$($script:TcPkgId)', not the assignment policy '$($script:TcOtherPolId)' this entry declares, so it is " +
                "not the review this entry declares. Nothing was written. $($script:TcNotUnique)")
            Should -Invoke -ModuleName Omnicit.EntraRBAC Resolve-OERAccessPackageId -Times 0
            Should -Invoke -ModuleName Omnicit.EntraRBAC Resolve-OERAssignmentPolicyId -Times 0
        }

        It 'names the live policy as none when the live review of the package names no policy' {
            $R = Invoke-TargetCheck -Declared (New-TcEntry -AccessPackage $script:TcPkgId -AssignmentPolicy $script:TcPolId) `
                -Current (New-TcLive -Scope "accessPackage/id eq '$($script:TcPkgId)'" -AccessPackageId $script:TcPkgId)
            $R.Out.Count | Should -Be 1
            [string]$R.Out[0].FullyQualifiedErrorId | Should -BeExactly 'AccessReviewScopeMismatch'
            $R.Out[0].Exception.Message | Should -BeLike "*reviews assignment policy 'none' of access package '$($script:TcPkgId)', not the assignment policy '$($script:TcPolId)' this entry declares,*"
        }
    }

    Context 'declared by name' {
        It 'returns nothing when the names resolve to the live ids, looking each up once against the right package' {
            Mock -ModuleName Omnicit.EntraRBAC Resolve-OERAccessPackageId { 'aaaa1111-0000-0000-0000-000000000001' }
            Mock -ModuleName Omnicit.EntraRBAC Resolve-OERAssignmentPolicyId { 'bbbb2222-0000-0000-0000-000000000001' }
            $R = Invoke-TargetCheck -Declared (New-TcEntry -AccessPackage 'AP-Sales' -AssignmentPolicy 'Standard') -Current (New-TcPackageLive)
            $R.Out.Count | Should -Be 0
            Should -Invoke -ModuleName Omnicit.EntraRBAC Resolve-OERAccessPackageId -Times 1 -Exactly
            Should -Invoke -ModuleName Omnicit.EntraRBAC Resolve-OERAccessPackageId -Times 1 -Exactly -ParameterFilter { $DisplayName -eq 'AP-Sales' }
            Should -Invoke -ModuleName Omnicit.EntraRBAC Resolve-OERAssignmentPolicyId -Times 1 -Exactly
            Should -Invoke -ModuleName Omnicit.EntraRBAC Resolve-OERAssignmentPolicyId -Times 1 -Exactly -ParameterFilter {
                $AccessPackageId -eq 'aaaa1111-0000-0000-0000-000000000001' -and $AssignmentPolicy -eq 'Standard' -and $AccessPackageLabel -eq 'AP-Sales'
            }
            $R.Errors.Count | Should -Be 0
            $R.Warnings.Count | Should -Be 0
        }

        It 'refuses a package name that resolves to another package, naming the name, its id and the live id, and looks up no policy' {
            Mock -ModuleName Omnicit.EntraRBAC Resolve-OERAccessPackageId { 'aaaa1111-0000-0000-0000-000000000002' }
            $R = Invoke-TargetCheck -Declared (New-TcEntry -AccessPackage 'AP-Sales' -AssignmentPolicy 'Standard') -Current (New-TcPackageLive)
            $R.Out.Count | Should -Be 1
            [string]$R.Out[0].FullyQualifiedErrorId | Should -BeExactly 'AccessReviewScopeMismatch'
            $R.Out[0].Exception.Message | Should -BeExactly ("Access review 'Q3 AP review' in the tenant reviews access package '$($script:TcPkgId)', " +
                "not the access package 'AP-Sales' ('$($script:TcOtherPkgId)') this entry declares, so it is not the review this entry declares. " +
                "Nothing was written. $($script:TcNotUnique)")
            Should -Invoke -ModuleName Omnicit.EntraRBAC Resolve-OERAccessPackageId -Times 1 -Exactly
            Should -Invoke -ModuleName Omnicit.EntraRBAC Resolve-OERAssignmentPolicyId -Times 0
        }

        It 'refuses a policy name that resolves to another policy of the package, naming the name, its id and the live id' {
            Mock -ModuleName Omnicit.EntraRBAC Resolve-OERAccessPackageId { 'aaaa1111-0000-0000-0000-000000000001' }
            Mock -ModuleName Omnicit.EntraRBAC Resolve-OERAssignmentPolicyId { 'bbbb2222-0000-0000-0000-000000000002' }
            $R = Invoke-TargetCheck -Declared (New-TcEntry -AccessPackage 'AP-Sales' -AssignmentPolicy 'Standard') -Current (New-TcPackageLive)
            $R.Out.Count | Should -Be 1
            [string]$R.Out[0].FullyQualifiedErrorId | Should -BeExactly 'AccessReviewScopeMismatch'
            $R.Out[0].Exception.Message | Should -BeExactly ("Access review 'Q3 AP review' in the tenant reviews assignment policy '$($script:TcPolId)' " +
                "of access package '$($script:TcPkgId)', not the assignment policy 'Standard' ('$($script:TcOtherPolId)') this entry declares, " +
                "so it is not the review this entry declares. Nothing was written. $($script:TcNotUnique)")
            Should -Invoke -ModuleName Omnicit.EntraRBAC Resolve-OERAssignmentPolicyId -Times 1 -Exactly
        }

        It 'returns AccessPackageNotFound when the package name matches nothing, and looks up no policy' {
            Mock -ModuleName Omnicit.EntraRBAC Resolve-OERAccessPackageId { $null }
            $R = Invoke-TargetCheck -Declared (New-TcEntry -AccessPackage 'AP-Sales' -AssignmentPolicy 'Standard') -Current (New-TcPackageLive)
            $R.Out.Count | Should -Be 1
            [string]$R.Out[0].FullyQualifiedErrorId | Should -BeExactly 'AccessPackageNotFound'
            $R.Out[0].CategoryInfo.Category | Should -Be 'ObjectNotFound'
            $R.Out[0].TargetObject | Should -BeExactly 'AP-Sales'
            $R.Out[0].Exception.Message | Should -BeExactly "AccessPackage 'AP-Sales' not found."
            Should -Invoke -ModuleName Omnicit.EntraRBAC Resolve-OERAccessPackageId -Times 1 -Exactly
            Should -Invoke -ModuleName Omnicit.EntraRBAC Resolve-OERAssignmentPolicyId -Times 0
            $R.Errors.Count | Should -Be 0
            $R.Warnings.Count | Should -Be 0
        }

        It 'returns AssignmentPolicyNotFound when the policy name matches nothing' {
            Mock -ModuleName Omnicit.EntraRBAC Resolve-OERAccessPackageId { 'aaaa1111-0000-0000-0000-000000000001' }
            Mock -ModuleName Omnicit.EntraRBAC Resolve-OERAssignmentPolicyId { $null }
            $R = Invoke-TargetCheck -Declared (New-TcEntry -AccessPackage 'AP-Sales' -AssignmentPolicy 'Standard') -Current (New-TcPackageLive)
            $R.Out.Count | Should -Be 1
            [string]$R.Out[0].FullyQualifiedErrorId | Should -BeExactly 'AssignmentPolicyNotFound'
            $R.Out[0].CategoryInfo.Category | Should -Be 'ObjectNotFound'
            $R.Out[0].TargetObject | Should -BeExactly 'Standard'
            $R.Out[0].Exception.Message | Should -BeExactly "AssignmentPolicy 'Standard' not found."
        }
    }

    Context 'a lookup that fails is returned as itself' {
        It 'returns an AmbiguousName package lookup as that record, scrubbed, and looks up no policy' {
            Mock -ModuleName Omnicit.EntraRBAC Remove-OERErrorRecord { }
            Mock -ModuleName Omnicit.EntraRBAC Resolve-OERAccessPackageId {
                throw [System.Management.Automation.ErrorRecord]::new(
                    [System.Exception]::new("Access package display name 'AP-Sales' matches 2 access packages (aaaa1111-0000-0000-0000-000000000001, aaaa1111-0000-0000-0000-000000000002)."),
                    'AmbiguousName', [System.Management.Automation.ErrorCategory]::InvalidArgument, 'AP-Sales')
            }
            $R = Invoke-TargetCheck -Declared (New-TcEntry -AccessPackage 'AP-Sales' -AssignmentPolicy 'Standard') -Current (New-TcPackageLive)
            $R.Out.Count | Should -Be 1
            [string]$R.Out[0].FullyQualifiedErrorId | Should -BeLike 'AmbiguousName*'
            $R.Out[0].CategoryInfo.Category | Should -Be 'InvalidArgument'
            $R.Out[0].Exception.Message | Should -BeLike '*aaaa1111-0000-0000-0000-000000000001, aaaa1111-0000-0000-0000-000000000002*'
            Should -Invoke -ModuleName Omnicit.EntraRBAC Remove-OERErrorRecord -Times 1 -Exactly -ParameterFilter {
                $Record.Exception.Message -like "Access package display name 'AP-Sales' matches 2 access packages*"
            }
            Should -Invoke -ModuleName Omnicit.EntraRBAC Resolve-OERAssignmentPolicyId -Times 0
            $R.Warnings.Count | Should -Be 0
        }

        It 'returns a 403 out of the package lookup as that record, scrubbed' {
            Mock -ModuleName Omnicit.EntraRBAC Remove-OERErrorRecord { }
            Mock -ModuleName Omnicit.EntraRBAC Resolve-OERAccessPackageId {
                throw [System.Management.Automation.ErrorRecord]::new(
                    [System.Exception]::new('Authorization_RequestDenied: Insufficient privileges to complete the operation.'),
                    'Authorization_RequestDenied', [System.Management.Automation.ErrorCategory]::PermissionDenied, 'AP-Sales')
            }
            $R = Invoke-TargetCheck -Declared (New-TcEntry -AccessPackage 'AP-Sales' -AssignmentPolicy 'Standard') -Current (New-TcPackageLive)
            $R.Out.Count | Should -Be 1
            [string]$R.Out[0].FullyQualifiedErrorId | Should -BeLike 'Authorization_RequestDenied*'
            $R.Out[0].CategoryInfo.Category | Should -Be 'PermissionDenied'
            $R.Out[0].Exception.Message | Should -BeExactly 'Authorization_RequestDenied: Insufficient privileges to complete the operation.'
            Should -Invoke -ModuleName Omnicit.EntraRBAC Remove-OERErrorRecord -Times 1 -Exactly -ParameterFilter {
                $Record.Exception.Message -eq 'Authorization_RequestDenied: Insufficient privileges to complete the operation.'
            }
            Should -Invoke -ModuleName Omnicit.EntraRBAC Resolve-OERAssignmentPolicyId -Times 0
        }

        It 'returns a failed policy lookup as that record, scrubbed' {
            Mock -ModuleName Omnicit.EntraRBAC Remove-OERErrorRecord { }
            Mock -ModuleName Omnicit.EntraRBAC Resolve-OERAccessPackageId { 'aaaa1111-0000-0000-0000-000000000001' }
            Mock -ModuleName Omnicit.EntraRBAC Resolve-OERAssignmentPolicyId {
                throw [System.Management.Automation.ErrorRecord]::new(
                    [System.Exception]::new('TooManyRequests: policy listing marker.'),
                    'TooManyRequests', [System.Management.Automation.ErrorCategory]::LimitsExceeded, 'Standard')
            }
            $R = Invoke-TargetCheck -Declared (New-TcEntry -AccessPackage 'AP-Sales' -AssignmentPolicy 'Standard') -Current (New-TcPackageLive)
            $R.Out.Count | Should -Be 1
            [string]$R.Out[0].FullyQualifiedErrorId | Should -BeLike 'TooManyRequests*'
            $R.Out[0].CategoryInfo.Category | Should -Be 'LimitsExceeded'
            $R.Out[0].Exception.Message | Should -BeExactly 'TooManyRequests: policy listing marker.'
            Should -Invoke -ModuleName Omnicit.EntraRBAC Remove-OERErrorRecord -Times 1 -Exactly -ParameterFilter {
                $Record.Exception.Message -eq 'TooManyRequests: policy listing marker.'
            }
        }
    }

    Context 'an entry that declares no package or no policy is refused' {
        It 'refuses an entry <Case>, and looks nothing up' -ForEach @(
            @{ Case = 'without accessPackage'; Omit = 'accessPackage'; Nullify = '' }
            @{ Case = 'with "accessPackage": null'; Omit = ''; Nullify = 'accessPackage' }
            @{ Case = 'without assignmentPolicy'; Omit = 'assignmentPolicy'; Nullify = '' }
            @{ Case = 'with "assignmentPolicy": null'; Omit = ''; Nullify = 'assignmentPolicy' }
            @{ Case = 'with "accessPackage": ""'; Omit = ''; Nullify = ''; Blank = 'accessPackage'; BlankValue = '' }
            @{ Case = 'with "assignmentPolicy" of white space only'; Omit = ''; Nullify = ''; Blank = 'assignmentPolicy'; BlankValue = '   ' }
        ) {
            $Entry = New-TcEntry -AccessPackage $script:TcPkgId -AssignmentPolicy $script:TcPolId
            if ($Omit) { $Entry.PSObject.Properties.Remove($Omit) }
            if ($Nullify) { $Entry.$Nullify = $null }
            if ($Blank) { $Entry.$Blank = $BlankValue }
            $R = Invoke-TargetCheck -Declared $Entry -Current (New-TcPackageLive)
            $R.Out.Count | Should -Be 1
            [string]$R.Out[0].FullyQualifiedErrorId | Should -BeExactly 'AccessReviewScopeMismatch'
            $R.Out[0].CategoryInfo.Category | Should -Be 'InvalidOperation'
            $R.Out[0].TargetObject | Should -BeExactly $script:TcName
            $R.Out[0].Exception.Message | Should -BeExactly ("Access review entry 'Q3 AP review' declares no access package or no assignment policy, " +
                'so the review in the tenant with that display name cannot be shown to be the one it declares. Nothing was written.')
            Should -Invoke -ModuleName Omnicit.EntraRBAC Resolve-OERAccessPackageId -Times 0
            Should -Invoke -ModuleName Omnicit.EntraRBAC Resolve-OERAssignmentPolicyId -Times 0
            $R.Errors.Count | Should -Be 0
            $R.Warnings.Count | Should -Be 0
        }
    }
}

# Sprint 12 step 6 (BL-137): an entry that declares group is a review of a group's members. The group
# branch runs first and decides alone; the live scope is classified by Resolve-OERAccessReviewGroupScope
# (real here), the group name by Resolve-OERGroupId (mocked, its own tests prove the lookup).
Describe 'Get-OERAccessReviewTargetMismatch for an entry that declares group' {
    BeforeAll {
        $script:GrName = 'Q3 group review'
        $script:GrId = '11111111-1111-1111-1111-111111111111'
        $script:GrOtherId = '22222222-2222-2222-2222-222222222222'
        $script:GrNotUnique = 'Access review display names are not unique: give the entry or the review in the tenant another display name.'

        function New-GrLive {
            param([string]$Scope, [string]$ScopeType)
            [PSCustomObject]@{
                AccessReviewDefinitionId = 'cccc3333-0000-0000-0000-000000000001'
                DisplayName              = $script:GrName
                Scope                    = $Scope
                ScopeType                = $(if ($ScopeType) { $ScopeType } else { $null })
                AccessPackageId          = $null
                AssignmentPolicyId       = $null
            }
        }
        function New-GrEntry {
            param($Group)
            [PSCustomObject]@{ displayName = $script:GrName; group = $Group; durationInDays = 21 }
        }
        function Invoke-GrCheck {
            param([Parameter(Mandatory)]$Declared, [Parameter(Mandatory)]$Current)
            InModuleScope Omnicit.EntraRBAC -Parameters @{ Declared = $Declared; Current = $Current } {
                param($Declared, $Current)
                $Ev = $null
                $Wv = $null
                $Out = @(Get-OERAccessReviewTargetMismatch -Declared $Declared -Current $Current -ErrorAction Continue -ErrorVariable Ev `
                        -WarningAction SilentlyContinue -WarningVariable Wv)
                [PSCustomObject]@{ Out = $Out; Errors = @($Ev); Warnings = @($Wv) }
            }
        }
    }

    BeforeEach {
        InModuleScope Omnicit.EntraRBAC { $script:_OERAuthState = $null }
        Mock -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest { throw 'Unexpected Graph request.' }
        Mock -ModuleName Omnicit.EntraRBAC Resolve-OERGroupId { throw 'Unexpected group lookup.' }
        Mock -ModuleName Omnicit.EntraRBAC Resolve-OERAccessPackageId { throw 'Unexpected access package lookup.' }
        Mock -ModuleName Omnicit.EntraRBAC Resolve-OERAssignmentPolicyId { throw 'Unexpected assignment policy lookup.' }
    }

    It 'returns nothing for a group GUID that matches the live scope read back as <Form>' -ForEach @(
        @{ Form = 'the module-written query'; Scope = '/groups/11111111-1111-1111-1111-111111111111/transitiveMembers' }
        @{ Form = 'the Graph read-back'; Scope = '/v1.0/groups/11111111-1111-1111-1111-111111111111/transitiveMembers/microsoft.graph.user' }
    ) {
        $R = Invoke-GrCheck -Declared (New-GrEntry -Group $script:GrId) -Current (New-GrLive -Scope $Scope)
        $R.Out.Count | Should -Be 0
        $R.Errors.Count | Should -Be 0
        Should -Invoke -ModuleName Omnicit.EntraRBAC Resolve-OERGroupId -Times 0
        Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest -Times 0
    }

    It 'returns nothing for a group name that resolves to the live group, with one lookup' {
        Mock -ModuleName Omnicit.EntraRBAC Resolve-OERGroupId { '11111111-1111-1111-1111-111111111111' }
        $R = Invoke-GrCheck -Declared (New-GrEntry -Group 'Sales') `
            -Current (New-GrLive -Scope '/v1.0/groups/11111111-1111-1111-1111-111111111111/transitiveMembers/microsoft.graph.user')
        $R.Out.Count | Should -Be 0
        Should -Invoke -ModuleName Omnicit.EntraRBAC Resolve-OERGroupId -Times 1 -Exactly -ParameterFilter { $DisplayName -ceq 'Sales' }
    }

    It 'compares the group ids ignoring letter case' {
        $R = Invoke-GrCheck -Declared (New-GrEntry -Group 'AAAAAAAA-1111-1111-1111-111111111111') `
            -Current (New-GrLive -Scope '/v1.0/groups/aaaaaaaa-1111-1111-1111-111111111111/transitiveMembers/microsoft.graph.user')
        $R.Out.Count | Should -Be 0
    }

    It 'refuses a live review of another group, naming both ids, after the group lookup only' {
        Mock -ModuleName Omnicit.EntraRBAC Resolve-OERGroupId { '11111111-1111-1111-1111-111111111111' }
        $R = Invoke-GrCheck -Declared (New-GrEntry -Group 'Sales') `
            -Current (New-GrLive -Scope '/v1.0/groups/22222222-2222-2222-2222-222222222222/transitiveMembers/microsoft.graph.user')
        $R.Out.Count | Should -Be 1
        [string]$R.Out[0].FullyQualifiedErrorId | Should -BeExactly 'AccessReviewScopeMismatch'
        $R.Out[0].CategoryInfo.Category | Should -Be 'InvalidOperation'
        $R.Out[0].TargetObject | Should -BeExactly $script:GrName
        $R.Out[0].Exception.Message | Should -BeExactly ("Access review 'Q3 group review' in the tenant reviews the members of group " +
            "'22222222-2222-2222-2222-222222222222', not the group 'Sales' ('11111111-1111-1111-1111-111111111111') this entry declares, " +
            "so it is not the review this entry declares. Nothing was written. $($script:GrNotUnique)")
        Should -Invoke -ModuleName Omnicit.EntraRBAC Resolve-OERGroupId -Times 1 -Exactly
        Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest -Times 0
        $R.Errors.Count | Should -Be 0
    }

    It 'refuses a declared group GUID that is not the live group, with no lookup' {
        $R = Invoke-GrCheck -Declared (New-GrEntry -Group $script:GrId) `
            -Current (New-GrLive -Scope '/v1.0/groups/22222222-2222-2222-2222-222222222222/transitiveMembers/microsoft.graph.user')
        $R.Out.Count | Should -Be 1
        $R.Out[0].Exception.Message | Should -BeExactly ("Access review 'Q3 group review' in the tenant reviews the members of group " +
            "'22222222-2222-2222-2222-222222222222', not the group '11111111-1111-1111-1111-111111111111' this entry declares, " +
            "so it is not the review this entry declares. Nothing was written. $($script:GrNotUnique)")
        Should -Invoke -ModuleName Omnicit.EntraRBAC Resolve-OERGroupId -Times 0
    }

    It 'refuses a live scope in <Case>, naming the live scope, with no request and no lookup' -ForEach @(
        @{ Case = 'the guest form'; Scope = "/v1.0/groups/11111111-1111-1111-1111-111111111111/transitiveMembers/microsoft.graph.user/?`$count=true&`$filter=(userType eq 'Guest')" }
        @{ Case = 'the direct members form'; Scope = '/v1.0/groups/11111111-1111-1111-1111-111111111111/members' }
        @{ Case = 'the owners form'; Scope = '/v1.0/groups/11111111-1111-1111-1111-111111111111/owners' }
        @{ Case = 'a package review scope'; Scope = "/identityGovernance/entitlementManagement/assignments?`$filter=(accessPackage/id eq 'x')" }
        @{ Case = 'an empty scope'; Scope = '' }
    ) {
        $R = Invoke-GrCheck -Declared (New-GrEntry -Group $script:GrId) -Current (New-GrLive -Scope $Scope)
        $R.Out.Count | Should -Be 1
        [string]$R.Out[0].FullyQualifiedErrorId | Should -BeExactly 'AccessReviewScopeMismatch'
        $Shown = if ($Scope) { $Scope } else { 'none' }
        $R.Out[0].Exception.Message | Should -BeExactly ("Access review 'Q3 group review' in the tenant does not review the members of a group in the form this module " +
            "writes (its scope is '$Shown'), so it is not the review this entry declares for group '11111111-1111-1111-1111-111111111111'. " +
            "Nothing was written. $($script:GrNotUnique)")
        Should -Invoke -ModuleName Omnicit.EntraRBAC Resolve-OERGroupId -Times 0
        Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest -Times 0
    }

    It 'refuses a review of the group''s INACTIVE users that shares the members query, naming its scope type, with no request and no lookup' {
        $R = Invoke-GrCheck -Declared (New-GrEntry -Group $script:GrId) `
            -Current (New-GrLive -Scope '/v1.0/groups/11111111-1111-1111-1111-111111111111/transitiveMembers' -ScopeType '#microsoft.graph.accessReviewInactiveUsersQueryScope')
        $R.Out.Count | Should -Be 1
        [string]$R.Out[0].FullyQualifiedErrorId | Should -BeExactly 'AccessReviewScopeMismatch'
        $R.Out[0].Exception.Message | Should -BeExactly ("Access review 'Q3 group review' in the tenant does not review the members of a group in the form this module " +
            "writes (its scope is '/v1.0/groups/11111111-1111-1111-1111-111111111111/transitiveMembers' and its scope type is '#microsoft.graph.accessReviewInactiveUsersQueryScope'), " +
            "so it is not the review this entry declares for group '11111111-1111-1111-1111-111111111111'. Nothing was written. $($script:GrNotUnique)")
        Should -Invoke -ModuleName Omnicit.EntraRBAC Resolve-OERGroupId -Times 0
        Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest -Times 0
    }

    It 'accepts the members query read back with the plain query scope type' {
        $R = Invoke-GrCheck -Declared (New-GrEntry -Group $script:GrId) `
            -Current (New-GrLive -Scope '/v1.0/groups/11111111-1111-1111-1111-111111111111/transitiveMembers/microsoft.graph.user' -ScopeType '#microsoft.graph.accessReviewQueryScope')
        $R.Out.Count | Should -Be 0
    }

    It 'refuses an entry that declares group beside <Name>, with no request' -ForEach @(
        @{ Name = 'accessPackage' }
        @{ Name = 'assignmentPolicy' }
    ) {
        $Entry = New-GrEntry -Group $script:GrId
        $Entry | Add-Member -NotePropertyName $Name -NotePropertyValue 'x'
        $R = Invoke-GrCheck -Declared $Entry `
            -Current (New-GrLive -Scope '/v1.0/groups/11111111-1111-1111-1111-111111111111/transitiveMembers/microsoft.graph.user')
        $R.Out.Count | Should -Be 1
        [string]$R.Out[0].FullyQualifiedErrorId | Should -BeExactly 'AccessReviewScopeMismatch'
        $R.Out[0].Exception.Message | Should -BeExactly ("Access review entry 'Q3 group review' declares a group together with an access package or assignment policy, " +
            'or declares no group name, so the review in the tenant with that display name cannot be shown to be the one it declares. Nothing was written.')
        Should -Invoke -ModuleName Omnicit.EntraRBAC Resolve-OERGroupId -Times 0
    }

    It 'refuses an entry whose group is white space only, with no request' {
        $R = Invoke-GrCheck -Declared (New-GrEntry -Group '   ') `
            -Current (New-GrLive -Scope '/v1.0/groups/11111111-1111-1111-1111-111111111111/transitiveMembers/microsoft.graph.user')
        $R.Out.Count | Should -Be 1
        [string]$R.Out[0].FullyQualifiedErrorId | Should -BeExactly 'AccessReviewScopeMismatch'
        Should -Invoke -ModuleName Omnicit.EntraRBAC Resolve-OERGroupId -Times 0
    }

    It 'refuses a package entry against a live group review (rule 2 is unchanged)' {
        $Entry = [PSCustomObject]@{ displayName = $script:GrName; accessPackage = 'aaaa1111-0000-0000-0000-000000000001'; assignmentPolicy = 'bbbb2222-0000-0000-0000-000000000001' }
        $R = Invoke-GrCheck -Declared $Entry `
            -Current (New-GrLive -Scope '/v1.0/groups/11111111-1111-1111-1111-111111111111/transitiveMembers/microsoft.graph.user')
        $R.Out.Count | Should -Be 1
        $R.Out[0].Exception.Message | Should -BeLike '*does not review an access package*'
    }

    It 'returns GroupNotFound for a name that matches no group' {
        Mock -ModuleName Omnicit.EntraRBAC Resolve-OERGroupId { $null }
        $R = Invoke-GrCheck -Declared (New-GrEntry -Group 'Nobody') `
            -Current (New-GrLive -Scope '/v1.0/groups/11111111-1111-1111-1111-111111111111/transitiveMembers/microsoft.graph.user')
        $R.Out.Count | Should -Be 1
        [string]$R.Out[0].FullyQualifiedErrorId | Should -BeExactly 'GroupNotFound'
        $R.Out[0].CategoryInfo.Category | Should -Be 'ObjectNotFound'
        $R.Out[0].TargetObject | Should -BeExactly 'Nobody'
        $R.Out[0].Exception.Message | Should -BeExactly "Group 'Nobody' not found."
    }

    It 'returns an ambiguous group name as that record, scrubbed' {
        Mock -ModuleName Omnicit.EntraRBAC Remove-OERErrorRecord { }
        Mock -ModuleName Omnicit.EntraRBAC Resolve-OERGroupId {
            throw [System.Management.Automation.ErrorRecord]::new(
                [System.Exception]::new("Group display name 'Dup' matches 2 groups (11111111-1111-1111-1111-111111111111, 22222222-2222-2222-2222-222222222222)."),
                'AmbiguousName', [System.Management.Automation.ErrorCategory]::InvalidArgument, 'Dup')
        }
        $R = Invoke-GrCheck -Declared (New-GrEntry -Group 'Dup') `
            -Current (New-GrLive -Scope '/v1.0/groups/11111111-1111-1111-1111-111111111111/transitiveMembers/microsoft.graph.user')
        $R.Out.Count | Should -Be 1
        [string]$R.Out[0].FullyQualifiedErrorId | Should -BeLike 'AmbiguousName*'
        $R.Out[0].Exception.Message | Should -BeLike '*11111111-1111-1111-1111-111111111111, 22222222-2222-2222-2222-222222222222*'
        Should -Invoke -ModuleName Omnicit.EntraRBAC Remove-OERErrorRecord -Times 1 -Exactly
    }

    It 'returns a 403 out of the group lookup as that record, scrubbed' {
        Mock -ModuleName Omnicit.EntraRBAC Remove-OERErrorRecord { }
        Mock -ModuleName Omnicit.EntraRBAC Resolve-OERGroupId {
            throw [System.Management.Automation.ErrorRecord]::new(
                [System.Exception]::new('Authorization_RequestDenied: Insufficient privileges to complete the operation.'),
                'Authorization_RequestDenied', [System.Management.Automation.ErrorCategory]::PermissionDenied, 'Sales')
        }
        $R = Invoke-GrCheck -Declared (New-GrEntry -Group 'Sales') `
            -Current (New-GrLive -Scope '/v1.0/groups/11111111-1111-1111-1111-111111111111/transitiveMembers/microsoft.graph.user')
        $R.Out.Count | Should -Be 1
        [string]$R.Out[0].FullyQualifiedErrorId | Should -BeLike 'Authorization_RequestDenied*'
        $R.Out[0].CategoryInfo.Category | Should -Be 'PermissionDenied'
    }
}

# Sprint 13 step 4: an entry that declares directoryRole is a review of every user's assignments to one
# directory role. The role branch runs first and decides alone; the live scope is classified by
# Resolve-OERAccessReviewRoleScope (real here), the role name by Resolve-OERDirectoryRoleInput (mocked).
Describe 'Get-OERAccessReviewTargetMismatch for an entry that declares directoryRole' {
    BeforeAll {
        $script:RlName = 'Reports Reader review'
        $script:RlId = '00000000-0000-0000-0000-000000000041'
        $script:RlOtherId = '00000000-0000-0000-0000-000000000042'
        $script:RlNotUnique = 'Access review display names are not unique: give the entry or the review in the tenant another display name.'
        $script:RlMemberships = '#microsoft.graph.principalResourceMembershipsScope'
        $script:RlPlain = '#microsoft.graph.accessReviewQueryScope'

        function New-RlInner {
            param([string]$Query)
            [PSCustomObject]@{ Query = $Query; QueryType = 'MicrosoftGraph'; QueryRoot = $null; ScopeType = $script:RlPlain }
        }
        function New-RlLive {
            param([string]$Scope, [string]$ScopeType, $PrincipalScopes, $ResourceScopes)
            [PSCustomObject]@{
                AccessReviewDefinitionId = 'cccc3333-0000-0000-0000-000000000001'
                DisplayName              = $script:RlName
                Scope                    = $Scope
                ScopeType                = $(if ($ScopeType) { $ScopeType } else { $null })
                PrincipalScopes          = @($PrincipalScopes)
                ResourceScopes           = @($ResourceScopes)
                AccessPackageId          = $null
                AssignmentPolicyId       = $null
            }
        }
        function New-RlAllLive {
            param([string]$RoleId)
            New-RlLive -ScopeType $script:RlMemberships `
                -PrincipalScopes (New-RlInner '/v1.0/users') `
                -ResourceScopes (New-RlInner "/beta/roleManagement/directory/roleDefinitions/$RoleId")
        }
        function New-RlEntry {
            param($Role)
            [PSCustomObject]@{ displayName = $script:RlName; directoryRole = $Role; durationInDays = 21 }
        }
        function Invoke-RlCheck {
            param([Parameter(Mandatory)]$Declared, [Parameter(Mandatory)]$Current)
            InModuleScope Omnicit.EntraRBAC -Parameters @{ Declared = $Declared; Current = $Current } {
                param($Declared, $Current)
                $Ev = $null
                $Wv = $null
                $Out = @(Get-OERAccessReviewTargetMismatch -Declared $Declared -Current $Current -ErrorAction Continue -ErrorVariable Ev `
                        -WarningAction SilentlyContinue -WarningVariable Wv)
                [PSCustomObject]@{ Out = $Out; Errors = @($Ev); Warnings = @($Wv) }
            }
        }
    }

    BeforeEach {
        InModuleScope Omnicit.EntraRBAC { $script:_OERAuthState = $null }
        Mock -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest { throw 'Unexpected Graph request.' }
        Mock -ModuleName Omnicit.EntraRBAC Resolve-OERDirectoryRoleInput { throw 'Unexpected directory role lookup.' }
        Mock -ModuleName Omnicit.EntraRBAC Resolve-OERGroupId { throw 'Unexpected group lookup.' }
        Mock -ModuleName Omnicit.EntraRBAC Resolve-OERAccessPackageId { throw 'Unexpected access package lookup.' }
        Mock -ModuleName Omnicit.EntraRBAC Resolve-OERAssignmentPolicyId { throw 'Unexpected assignment policy lookup.' }
    }

    It 'returns nothing for a role GUID that matches the live role, in <Case>, with no lookup' -ForEach @(
        @{ Case = 'lower case'; Declared = '00000000-0000-0000-0000-000000000041'; LiveId = '00000000-0000-0000-0000-000000000041' }
        @{ Case = 'upper case'; Declared = '0000000A-0000-0000-0000-000000000041'; LiveId = '0000000a-0000-0000-0000-000000000041' }
    ) {
        $R = Invoke-RlCheck -Declared (New-RlEntry -Role $Declared) -Current (New-RlAllLive -RoleId $LiveId)
        $R.Out.Count | Should -Be 0
        $R.Errors.Count | Should -Be 0
        Should -Invoke -ModuleName Omnicit.EntraRBAC Resolve-OERDirectoryRoleInput -Times 0
        Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest -Times 0
    }

    It 'returns nothing for a role name in another letter case that the resolver maps to the live id, with one lookup' {
        Mock -ModuleName Omnicit.EntraRBAC Resolve-OERDirectoryRoleInput { [PSCustomObject]@{ RoleDefinitionId = '00000000-0000-0000-0000-000000000041'; ErrorId = $null } }
        $R = Invoke-RlCheck -Declared (New-RlEntry -Role 'REPORTS reader') -Current (New-RlAllLive -RoleId $script:RlId)
        $R.Out.Count | Should -Be 0
        Should -Invoke -ModuleName Omnicit.EntraRBAC Resolve-OERDirectoryRoleInput -Times 1 -Exactly -ParameterFilter { $Role -ceq 'REPORTS reader' }
    }

    It 'refuses an entry that declares directoryRole beside <Name>, with no request and no lookup' -ForEach @(
        @{ Name = 'group' }
        @{ Name = 'accessPackage' }
        @{ Name = 'assignmentPolicy' }
    ) {
        $Entry = New-RlEntry -Role $script:RlId
        $Entry | Add-Member -NotePropertyName $Name -NotePropertyValue 'x'
        $R = Invoke-RlCheck -Declared $Entry -Current (New-RlAllLive -RoleId $script:RlId)
        $R.Out.Count | Should -Be 1
        [string]$R.Out[0].FullyQualifiedErrorId | Should -BeExactly 'AccessReviewScopeMismatch'
        $R.Out[0].CategoryInfo.Category | Should -Be 'InvalidOperation'
        $R.Out[0].TargetObject | Should -BeExactly $script:RlName
        $R.Out[0].Exception.Message | Should -BeExactly ("Access review entry 'Reports Reader review' declares a directory role together with another review target (a group, " +
            'an access package or an assignment policy), or declares no role, so the review in the tenant with that display name ' +
            'cannot be shown to be the one it declares. Nothing was written.')
        Should -Invoke -ModuleName Omnicit.EntraRBAC Resolve-OERDirectoryRoleInput -Times 0
        Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest -Times 0
    }

    It 'refuses an entry whose directoryRole is white space only, with no request and no lookup' {
        $R = Invoke-RlCheck -Declared (New-RlEntry -Role '   ') -Current (New-RlAllLive -RoleId $script:RlId)
        $R.Out.Count | Should -Be 1
        [string]$R.Out[0].FullyQualifiedErrorId | Should -BeExactly 'AccessReviewScopeMismatch'
        $R.Out[0].Exception.Message | Should -BeLike '*declares no role*'
        Should -Invoke -ModuleName Omnicit.EntraRBAC Resolve-OERDirectoryRoleInput -Times 0
    }

    It 'decides the role branch before the group branch for an entry declaring both' {
        $Entry = New-RlEntry -Role $script:RlId
        $Entry | Add-Member -NotePropertyName group -NotePropertyValue '11111111-1111-1111-1111-111111111111'
        $R = Invoke-RlCheck -Declared $Entry `
            -Current (New-RlLive -Scope '/v1.0/groups/11111111-1111-1111-1111-111111111111/transitiveMembers/microsoft.graph.user')
        $R.Out.Count | Should -Be 1
        $R.Out[0].Exception.Message | Should -BeLike '*declares a directory role together with another review target*'
    }

    It 'refuses a live scope in <Case>, naming the live scope, with no request and no lookup' -ForEach @(
        @{ Case = 'a group review'; Scope = '/v1.0/groups/11111111-1111-1111-1111-111111111111/transitiveMembers/microsoft.graph.user' }
        @{ Case = 'a package review'; Scope = "/identityGovernance/entitlementManagement/assignments?`$filter=(accessPackage/id eq 'x')" }
        @{ Case = 'an empty scope'; Scope = '' }
        @{ Case = 'the eligible form'; Scope = "/beta/roleManagement/directory/roleEligibilityScheduleInstances?`$expand=principal&`$filter=(isof(principal,'microsoft.graph.user') and roleDefinitionId eq '00000000-0000-0000-0000-000000000041')" }
        @{ Case = 'the active form'; Scope = "/beta/roleManagement/directory/roleAssignmentScheduleInstances?`$expand=principal&`$filter=(assignmentType eq 'Assigned' and isof(principal,'microsoft.graph.user') and roleDefinitionId eq '00000000-0000-0000-0000-000000000041')" }
    ) {
        $R = Invoke-RlCheck -Declared (New-RlEntry -Role $script:RlId) -Current (New-RlLive -Scope $Scope)
        $R.Out.Count | Should -Be 1
        [string]$R.Out[0].FullyQualifiedErrorId | Should -BeExactly 'AccessReviewScopeMismatch'
        $Shown = if ($Scope) { $Scope } else { 'none' }
        $R.Out[0].Exception.Message | Should -BeExactly ("Access review 'Reports Reader review' in the tenant does not review every user's assignments to a directory role in the form " +
            "this module writes (its scope is '$Shown'), so it is not the review this entry declares for directory " +
            "role '00000000-0000-0000-0000-000000000041'. Nothing was written. $($script:RlNotUnique)")
        Should -Invoke -ModuleName Omnicit.EntraRBAC Resolve-OERDirectoryRoleInput -Times 0
        Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest -Times 0
    }

    It 'refuses the guest form of the RIGHT role under the entry''s name, naming the principal and resource queries' {
        $Live = New-RlLive -ScopeType $script:RlMemberships `
            -PrincipalScopes (New-RlInner "/v1.0/users?`$filter=(userType eq 'Guest')") `
            -ResourceScopes (New-RlInner "/beta/roleManagement/directory/roleDefinitions/$($script:RlId)")
        $R = Invoke-RlCheck -Declared (New-RlEntry -Role $script:RlId) -Current $Live
        $R.Out.Count | Should -Be 1
        [string]$R.Out[0].FullyQualifiedErrorId | Should -BeExactly 'AccessReviewScopeMismatch'
        $R.Out[0].Exception.Message | Should -BeExactly ("Access review 'Reports Reader review' in the tenant does not review every user's assignments to a directory role in the form " +
            "this module writes (its scope is principals '/v1.0/users?`$filter=(userType eq 'Guest')' and resources " +
            "'/beta/roleManagement/directory/roleDefinitions/00000000-0000-0000-0000-000000000041'), so it is not the review this entry declares for directory " +
            "role '00000000-0000-0000-0000-000000000041'. Nothing was written. $($script:RlNotUnique)")
        Should -Invoke -ModuleName Omnicit.EntraRBAC Resolve-OERDirectoryRoleInput -Times 0
    }

    It 'names an empty principal resource memberships scope as none and a scope of another type beside the query' {
        $R = Invoke-RlCheck -Declared (New-RlEntry -Role $script:RlId) -Current (New-RlLive -ScopeType $script:RlMemberships)
        $R.Out.Count | Should -Be 1
        $R.Out[0].Exception.Message | Should -BeLike "*(its scope is principals 'none' and resources 'none')*"
        $R2 = Invoke-RlCheck -Declared (New-RlEntry -Role $script:RlId) `
            -Current (New-RlLive -Scope '/v1.0/groups/11111111-1111-1111-1111-111111111111/transitiveMembers' -ScopeType '#microsoft.graph.accessReviewInactiveUsersQueryScope')
        $R2.Out[0].Exception.Message | Should -BeLike "*and its scope type is '#microsoft.graph.accessReviewInactiveUsersQueryScope')*"
    }

    It 'returns <ErrorId> from the role lookup as itself, with one lookup and the inner exception kept' -ForEach @(
        @{ ErrorId = 'RoleDefinitionNotFound'; Category = 'ObjectNotFound' }
        @{ ErrorId = 'AmbiguousRoleName'; Category = 'InvalidArgument' }
        @{ ErrorId = 'RoleDefinitionReadFailed'; Category = 'ReadError' }
    ) {
        Mock -ModuleName Omnicit.EntraRBAC Resolve-OERDirectoryRoleInput -MockWith {
            param([string]$Role)
            [PSCustomObject]@{
                RoleDefinitionId = $null
                ErrorId          = $ErrorId
                Message          = "lookup said $ErrorId"
                Category         = $Category
                TargetObject     = $Role
                InnerException   = [System.InvalidOperationException]::new('inner')
            }
        }
        $R = Invoke-RlCheck -Declared (New-RlEntry -Role 'Reports Reader') -Current (New-RlAllLive -RoleId $script:RlId)
        $R.Out.Count | Should -Be 1
        [string]$R.Out[0].FullyQualifiedErrorId | Should -BeExactly $ErrorId
        $R.Out[0].CategoryInfo.Category | Should -Be $Category
        $R.Out[0].TargetObject | Should -BeExactly 'Reports Reader'
        $R.Out[0].Exception.Message | Should -BeExactly "lookup said $ErrorId"
        $R.Out[0].Exception.InnerException.Message | Should -BeExactly 'inner'
        Should -Invoke -ModuleName Omnicit.EntraRBAC Resolve-OERDirectoryRoleInput -Times 1 -Exactly
        Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest -Times 0
    }

    It 'refuses a live review of another role, naming both ids, after the role lookup only' {
        Mock -ModuleName Omnicit.EntraRBAC Resolve-OERDirectoryRoleInput { [PSCustomObject]@{ RoleDefinitionId = '00000000-0000-0000-0000-000000000041'; ErrorId = $null } }
        $R = Invoke-RlCheck -Declared (New-RlEntry -Role 'Reports Reader') -Current (New-RlAllLive -RoleId $script:RlOtherId)
        $R.Out.Count | Should -Be 1
        [string]$R.Out[0].FullyQualifiedErrorId | Should -BeExactly 'AccessReviewScopeMismatch'
        $R.Out[0].CategoryInfo.Category | Should -Be 'InvalidOperation'
        $R.Out[0].TargetObject | Should -BeExactly $script:RlName
        $R.Out[0].Exception.Message | Should -BeExactly ("Access review 'Reports Reader review' in the tenant reviews the assignments to directory role " +
            "'00000000-0000-0000-0000-000000000042', not the directory role 'Reports Reader' ('00000000-0000-0000-0000-000000000041') this entry declares, " +
            "so it is not the review this entry declares. Nothing was written. $($script:RlNotUnique)")
        Should -Invoke -ModuleName Omnicit.EntraRBAC Resolve-OERDirectoryRoleInput -Times 1 -Exactly
        Should -Invoke -ModuleName Omnicit.EntraRBAC Invoke-OERGraphRequest -Times 0
    }

    It 'refuses a declared role GUID that is not the live role, with no lookup' {
        $R = Invoke-RlCheck -Declared (New-RlEntry -Role $script:RlId) -Current (New-RlAllLive -RoleId $script:RlOtherId)
        $R.Out.Count | Should -Be 1
        $R.Out[0].Exception.Message | Should -BeExactly ("Access review 'Reports Reader review' in the tenant reviews the assignments to directory role " +
            "'00000000-0000-0000-0000-000000000042', not the directory role '00000000-0000-0000-0000-000000000041' this entry declares, " +
            "so it is not the review this entry declares. Nothing was written. $($script:RlNotUnique)")
        Should -Invoke -ModuleName Omnicit.EntraRBAC Resolve-OERDirectoryRoleInput -Times 0
    }

    It 'still refuses a group entry against a live role review by the group check' {
        $Entry = [PSCustomObject]@{ displayName = $script:RlName; group = '11111111-1111-1111-1111-111111111111' }
        $R = Invoke-RlCheck -Declared $Entry -Current (New-RlAllLive -RoleId $script:RlId)
        $R.Out.Count | Should -Be 1
        $R.Out[0].Exception.Message | Should -BeLike '*does not review the members of a group*'
    }

    It 'still refuses a package entry against a live role review by the package check' {
        $Entry = [PSCustomObject]@{ displayName = $script:RlName; accessPackage = 'aaaa1111-0000-0000-0000-000000000001'; assignmentPolicy = 'bbbb2222-0000-0000-0000-000000000001' }
        $R = Invoke-RlCheck -Declared $Entry -Current (New-RlAllLive -RoleId $script:RlId)
        $R.Out.Count | Should -Be 1
        $R.Out[0].Exception.Message | Should -BeLike '*does not review an access package*'
    }
}
