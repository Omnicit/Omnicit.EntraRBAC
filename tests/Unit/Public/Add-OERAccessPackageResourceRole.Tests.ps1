BeforeAll {
    $script:moduleName = 'Omnicit.EntraRBAC'
    Get-Module $script:moduleName | Remove-Module -Force -ErrorAction SilentlyContinue
    Import-Module $script:moduleName -Force -ErrorAction Stop
}

Describe 'Add-OERAccessPackageResourceRole' {
    BeforeEach {
        InModuleScope $script:moduleName { $script:_OERAuthState = $null }
        Mock -ModuleName $script:moduleName Initialize-OERAuth {}
        Mock -ModuleName $script:moduleName Resolve-OERAccessPackageId { 'ap-1' }
        Mock -ModuleName $script:moduleName Resolve-OERCatalogId { 'cat-1' }
        Mock -ModuleName $script:moduleName Resolve-OERCatalogResource {
            @{
                id           = 'res-1'
                originId     = 'grp-guid'
                originSystem = 'AadGroup'
                roles = @(
                    @{ id = 'role-member'; displayName = 'Member'; originId = 'Member_x' }
                )
            }
        }
        # Default: the confirmation read finds no matching binding, forcing the composed fallback path
        # on every test below that does not override this mock. Individual tests override it to prove
        # the primary re-read path instead.
        Mock -ModuleName $script:moduleName Get-OERAccessPackageResourceRole { $null }
    }

    It 'posts a resourceRoleScope binding the Member role' {
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest { @{ id = 'scope-1' } } -ParameterFilter { $Method -eq 'POST' }
        Add-OERAccessPackageResourceRole -AccessPackage 'AP-Sales' -Catalog 'cat-1' -ResourceOriginId 'grp-guid' -Role 'Member' | Out-Null
        Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 1 -ParameterFilter {
            $Method -eq 'POST' -and $Uri -like '*accessPackages/ap-1/resourceRoleScopes' -and
            $Body.role.displayName -eq 'Member' -and
            $Body.role.originSystem -eq 'AadGroup' -and
            $Body.role.originId -eq 'Member_x' -and
            $Body.scope.isRootScope -eq $true
        }
    }

    It 'errors when the named role is not found on the resource' {
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {}
        Add-OERAccessPackageResourceRole -AccessPackage 'AP-Sales' -Catalog 'cat-1' -ResourceOriginId 'grp-guid' -Role 'Owner' -ErrorVariable err -ErrorAction SilentlyContinue | Out-Null
        $err.FullyQualifiedErrorId | Should -Match 'ResourceRoleNotFound'
    }

    It 'errors with AccessPackageNotFound when the access package is not resolved' {
        Mock -ModuleName $script:moduleName Resolve-OERAccessPackageId { $null }
        Add-OERAccessPackageResourceRole -AccessPackage 'NoSuch' -Catalog 'cat-1' -ResourceOriginId 'grp-guid' -Role 'Member' -ErrorVariable err -ErrorAction SilentlyContinue | Out-Null
        $err.FullyQualifiedErrorId | Should -Match 'AccessPackageNotFound'
    }

    It 'errors with CatalogNotFound when the catalog is not resolved' {
        Mock -ModuleName $script:moduleName Resolve-OERCatalogId { $null }
        Add-OERAccessPackageResourceRole -AccessPackage 'AP-Sales' -Catalog 'NoCat' -ResourceOriginId 'grp-guid' -Role 'Member' -ErrorVariable err -ErrorAction SilentlyContinue | Out-Null
        $err.FullyQualifiedErrorId | Should -Match 'CatalogNotFound'
    }

    It 'errors with CatalogResourceNotFound when the resource is not in the catalog' {
        Mock -ModuleName $script:moduleName Resolve-OERCatalogResource { $null }
        Add-OERAccessPackageResourceRole -AccessPackage 'AP-Sales' -Catalog 'cat-1' -ResourceOriginId 'no-res' -Role 'Member' -ErrorVariable err -ErrorAction SilentlyContinue | Out-Null
        $err.FullyQualifiedErrorId | Should -Match 'CatalogResourceNotFound'
    }

    It 'does not POST under -WhatIf' {
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {}
        Add-OERAccessPackageResourceRole -AccessPackage 'AP-Sales' -Catalog 'cat-1' -ResourceOriginId 'grp-guid' -Role 'Member' -WhatIf | Out-Null
        Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 0 -ParameterFilter { $Method -eq 'POST' }
        Should -Invoke -ModuleName $script:moduleName Get-OERAccessPackageResourceRole -Times 0
    }

    It 'calls Initialize-OERAuth once' {
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest { @{ id = 'scope-1' } } -ParameterFilter { $Method -eq 'POST' }
        Add-OERAccessPackageResourceRole -AccessPackage 'AP-Sales' -Catalog 'cat-1' -ResourceOriginId 'grp-guid' -Role 'Member' | Out-Null
        Should -Invoke -ModuleName $script:moduleName Initialize-OERAuth -Times 1
    }

    It 'returns the created object with the id from the Graph response' {
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest { @{ id = 'scope-1' } } -ParameterFilter { $Method -eq 'POST' }
        $Result = Add-OERAccessPackageResourceRole -AccessPackage 'AP-Sales' -Catalog 'cat-1' -ResourceOriginId 'grp-guid' -Role 'Member'
        $Result.ResourceRoleScopeId | Should -Be 'scope-1'
    }

    It 're-reads the created binding through Get-OERAccessPackageResourceRole' {
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest { @{ id = 'scope-1' } } -ParameterFilter { $Method -eq 'POST' }
        Add-OERAccessPackageResourceRole -AccessPackage 'AP-Sales' -Catalog 'cat-1' -ResourceOriginId 'grp-guid' -Role 'Member' | Out-Null
        Should -Invoke -ModuleName $script:moduleName Get-OERAccessPackageResourceRole -Times 1 -ParameterFilter {
            $AccessPackage -eq 'ap-1'
        }
    }

    It 'emits exactly what the confirmation read returns for the created binding' {
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {
            @{ id = 'rrs-1'; createdDateTime = '2026-08-13T07:42:49.12Z' }
        } -ParameterFilter { $Method -eq 'POST' }
        # The confirmation read owns ResourceDisplayName (a catalog-resource join) and ScopeDisplayName
        # (the raw scope label) -- neither is derivable from what Add- itself resolved, so matching
        # these specific values proves pass-through rather than local recomposition.
        $ReadBinding = [PSCustomObject]@{
            ResourceRoleScopeId = 'rrs-1'
            RoleName            = 'Member'
            ResourceDisplayName = 'role_sec_finance'
            ScopeDisplayName    = 'Root'
            OriginId            = 'grp-guid'
            OriginSystem        = 'AadGroup'
            AccessPackageId     = 'ap-1'
        }
        $ReadBinding.PSObject.TypeNames.Insert(0, 'Omnicit.EntraRBAC.AccessPackageResourceRole')
        $OtherBinding = [PSCustomObject]@{ ResourceRoleScopeId = 'rrs-unrelated'; RoleName = 'Owner' }
        Mock -ModuleName $script:moduleName Get-OERAccessPackageResourceRole { @($OtherBinding, $ReadBinding) }

        $Result = Add-OERAccessPackageResourceRole -AccessPackage 'AP-Sales' -Catalog 'cat-1' -ResourceOriginId 'grp-guid' -Role 'Member'

        $Result.ResourceRoleScopeId | Should -Be 'rrs-1'
        $Result.ResourceDisplayName | Should -Be 'role_sec_finance'
        $Result.ScopeDisplayName    | Should -Be 'Root'
        $Result.AccessPackageId     | Should -Be 'ap-1'
        # Proves the exact read object was emitted, not a locally recomposed lookalike.
        [object]::ReferenceEquals($Result, $ReadBinding) | Should -BeTrue
    }

    It 'falls back to a composed tagged object when the confirmation read throws' {
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest { @{ id = 'scope-1' } } -ParameterFilter { $Method -eq 'POST' }
        Mock -ModuleName $script:moduleName Get-OERAccessPackageResourceRole { throw 'Simulated confirmation read failure' }

        $Result = Add-OERAccessPackageResourceRole -AccessPackage 'AP-Sales' -Catalog 'cat-1' -ResourceOriginId 'grp-guid' -Role 'Member'
        $Result.PSObject.TypeNames[0] | Should -Be 'Omnicit.EntraRBAC.AccessPackageResourceRole'
        $Result.ResourceRoleScopeId | Should -Be 'scope-1'
        $Result.RoleName | Should -Be 'Member'
        $Result.AccessPackageId | Should -Not -BeNullOrEmpty
    }

    It 'falls back to a composed tagged object when the confirmation read finds no matching binding' {
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest { @{ id = 'scope-1' } } -ParameterFilter { $Method -eq 'POST' }
        Mock -ModuleName $script:moduleName Get-OERAccessPackageResourceRole { [PSCustomObject]@{ ResourceRoleScopeId = 'rrs-unrelated' } }

        $Result = Add-OERAccessPackageResourceRole -AccessPackage 'AP-Sales' -Catalog 'cat-1' -ResourceOriginId 'grp-guid' -Role 'Member'
        $Result.PSObject.TypeNames[0] | Should -Be 'Omnicit.EntraRBAC.AccessPackageResourceRole'
        $Result.ResourceRoleScopeId | Should -Be 'scope-1'
    }

    It 'returns a composed tagged resource role object with the role and scope facets filled in from the resolved catalog resource when the read finds nothing' {
        # originId on the mocked resource DELIBERATELY differs from the -ResourceOriginId argument
        # below, so the OriginId assertion cannot pass on an echo of the input parameter -- it can
        # only pass if the source reads $Resource.originId (the resolved value).
        Mock -ModuleName $script:moduleName Resolve-OERCatalogResource {
            @{
                id           = 'res-1'
                displayName  = 'Sales Group'
                originId     = 'grp-origin-resolved'
                originSystem = 'AadGroup'
                roles        = @(@{ displayName = 'Member'; originId = 'Member_grp-origin' })
            }
        }
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {
            @{ id = 'rrs-1'; createdDateTime = '2026-08-12T09:00:00Z' }
        } -ParameterFilter { $Method -eq 'POST' }

        $Result = Add-OERAccessPackageResourceRole -AccessPackage 'AP-Sales' -Catalog 'CAT-1' `
            -ResourceOriginId 'grp-origin' -Role 'Member' -Confirm:$false
        $Result.PSObject.TypeNames[0] | Should -Be 'Omnicit.EntraRBAC.AccessPackageResourceRole'
        # RoleName cannot discriminate resolved-vs-echoed by construction ($ResourceRole is
        # selected via `Where-Object { $_.displayName -eq $Role }`, so the two are always equal) --
        # kept for shape coverage only, not as proof of resolution.
        $Result.RoleName | Should -Be 'Member'
        # OriginId and ResourceDisplayName are resolved-only facets: OriginId proves the source reads
        # $Resource.originId (not the raw -ResourceOriginId argument); ResourceDisplayName has no
        # analogous input parameter at all, so it is the strongest proof.
        $Result.OriginId | Should -Be 'grp-origin-resolved'
        $Result.OriginId | Should -Not -Be 'grp-origin'
        $Result.ResourceDisplayName | Should -Be 'Sales Group'
        $Result.OriginSystem | Should -Be 'AadGroup'
        $Result.ResourceRoleScopeId | Should -Not -BeNullOrEmpty
        $Result.AccessPackageId | Should -Not -BeNullOrEmpty
    }

    It 'resolves -Group to the origin id via Resolve-OERGroupId, passed through to Resolve-OERCatalogResource' {
        Mock -ModuleName $script:moduleName Resolve-OERGroupId { 'grp-resolved-guid' }
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest { @{ id = 'scope-1' } } -ParameterFilter { $Method -eq 'POST' }
        Add-OERAccessPackageResourceRole -AccessPackage 'AP-Sales' -Catalog 'cat-1' -Group 'Sales Team' -Role 'Member' -Confirm:$false | Out-Null
        Should -Invoke -ModuleName $script:moduleName Resolve-OERGroupId -Times 1 -Exactly -ParameterFilter { $DisplayName -eq 'Sales Team' }
        Should -Invoke -ModuleName $script:moduleName Resolve-OERCatalogResource -Times 1 -Exactly -ParameterFilter { $OriginId -eq 'grp-resolved-guid' }
    }

    It 'errors AmbiguousGroupName when -Group matches multiple groups, surfacing the candidate ids, and issues no Graph request' {
        Mock -ModuleName $script:moduleName Resolve-OERGroupId {
            throw [System.Management.Automation.ErrorRecord]::new(
                [System.Exception]::new(
                    "Group display name 'Dup' matches 2 groups (11111111-1111-1111-1111-111111111111, 22222222-2222-2222-2222-222222222222)."),
                'AmbiguousName', [System.Management.Automation.ErrorCategory]::InvalidArgument, 'Dup')
        }
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {}
        $Err = $null
        Add-OERAccessPackageResourceRole -AccessPackage 'AP-Sales' -Catalog 'cat-1' -Group 'Dup' -Role 'Member' `
            -ErrorAction SilentlyContinue -ErrorVariable Err | Out-Null
        # Cmdlet-qualified id: a bare-code match would pass even with the WriteError deleted, because
        # PowerShell re-records the mock's thrown record into -ErrorVariable at every call boundary.
        $Reported = @($Err | Where-Object { $_.FullyQualifiedErrorId -eq 'AmbiguousGroupName,Add-OERAccessPackageResourceRole' })
        $Reported.Count | Should -Be 1
        $Reported[0].Exception.Message | Should -Match '11111111-1111-1111-1111-111111111111'
        $Reported[0].Exception.Message | Should -Match '22222222-2222-2222-2222-222222222222'
        Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 0 -Exactly
    }

    It 'errors GroupNotFound when -Group cannot be resolved and issues no Graph request' {
        Mock -ModuleName $script:moduleName Resolve-OERGroupId { $null }
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {}
        $Err = $null
        Add-OERAccessPackageResourceRole -AccessPackage 'AP-Sales' -Catalog 'cat-1' -Group 'nope' -Role 'Member' `
            -ErrorAction SilentlyContinue -ErrorVariable Err | Out-Null
        $Err[0].FullyQualifiedErrorId | Should -Be 'GroupNotFound,Add-OERAccessPackageResourceRole'
        Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 0 -Exactly
    }

    It 'resolves -Application to the origin id via Resolve-OERApplicationId, passed through to Resolve-OERCatalogResource' {
        Mock -ModuleName $script:moduleName Resolve-OERApplicationId { 'sp-resolved-guid' }
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest { @{ id = 'scope-1' } } -ParameterFilter { $Method -eq 'POST' }
        Add-OERAccessPackageResourceRole -AccessPackage 'AP-Sales' -Catalog 'cat-1' -Application 'Contoso Expense Portal' -Role 'Member' -Confirm:$false | Out-Null
        Should -Invoke -ModuleName $script:moduleName Resolve-OERApplicationId -Times 1 -Exactly -ParameterFilter { $DisplayName -eq 'Contoso Expense Portal' }
        Should -Invoke -ModuleName $script:moduleName Resolve-OERCatalogResource -Times 1 -Exactly -ParameterFilter { $OriginId -eq 'sp-resolved-guid' }
    }

    It 'passes a GUID -Application straight through with no servicePrincipals read (symmetric with -Group)' {
        # -Group's help claim ("display name or object id") is true because Resolve-OERGroupId
        # short-circuits a GUID via -Id with no Graph call. Resolve-OERApplicationId has NO such
        # short-circuit on its -DisplayName parameter -- only its separate -Id parameter returns
        # verbatim -- so this cmdlet must choose which one to call. Deliberately does NOT mock
        # Resolve-OERApplicationId, so the real -Id short-circuit is what proves this, not a stub.
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest { @{ id = 'scope-1' } } -ParameterFilter { $Method -eq 'POST' }
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {
            throw 'a GUID -Application must not trigger a servicePrincipals lookup'
        } -ParameterFilter { $Uri -like '*servicePrincipals*' }
        $Guid = 'aaaaaaaa-0000-0000-0000-00000000aaaa'
        Add-OERAccessPackageResourceRole -AccessPackage 'AP-Sales' -Catalog 'cat-1' -Application $Guid -Role 'Member' -Confirm:$false | Out-Null
        Should -Invoke -ModuleName $script:moduleName Resolve-OERCatalogResource -Times 1 -Exactly -ParameterFilter { $OriginId -eq $Guid }
        Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 0 -Exactly -ParameterFilter { $Uri -like '*servicePrincipals*' }
    }

    It 'errors ApplicationNotFound when -Application cannot be resolved and issues no Graph request' {
        Mock -ModuleName $script:moduleName Resolve-OERApplicationId { $null }
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {}
        $Err = $null
        Add-OERAccessPackageResourceRole -AccessPackage 'AP-Sales' -Catalog 'cat-1' -Application 'nope' -Role 'Member' `
            -ErrorAction SilentlyContinue -ErrorVariable Err | Out-Null
        $Err[0].FullyQualifiedErrorId | Should -Be 'ApplicationNotFound,Add-OERAccessPackageResourceRole'
        Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 0 -Exactly
    }

    It 'errors NoResourceInput when none of -ResourceOriginId, -Group, -Application is supplied' {
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {}
        $Err = $null
        Add-OERAccessPackageResourceRole -AccessPackage 'AP-Sales' -Catalog 'cat-1' -Role 'Member' `
            -ErrorAction SilentlyContinue -ErrorVariable Err | Out-Null
        $Err[0].FullyQualifiedErrorId | Should -Be 'NoResourceInput,Add-OERAccessPackageResourceRole'
        Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 0 -Exactly
    }

    It 'errors AmbiguousResourceInput when more than one of -ResourceOriginId, -Group, -Application is supplied' {
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {}
        $Err = $null
        Add-OERAccessPackageResourceRole -AccessPackage 'AP-Sales' -Catalog 'cat-1' -ResourceOriginId 'grp-guid' -Group 'Sales Team' -Role 'Member' `
            -ErrorAction SilentlyContinue -ErrorVariable Err | Out-Null
        $Err[0].FullyQualifiedErrorId | Should -Be 'AmbiguousResourceInput,Add-OERAccessPackageResourceRole'
        Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 0 -Exactly
    }

    It 'rejects an empty -ResourceOriginId at bind time rather than satisfying the resource-input guard' {
        # Dropping Mandatory (to allow -Group/-Application) also dropped the automatic rejection of an
        # empty value -- without ValidateNotNullOrEmpty, -ResourceOriginId '' binds, counts as
        # "supplied" for the exactly-one guard, and only fails later inside Resolve-OERCatalogResource.
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {}
        { Add-OERAccessPackageResourceRole -AccessPackage 'AP-Sales' -Catalog 'cat-1' -ResourceOriginId '' -Role 'Member' -Confirm:$false } |
            Should -Throw
        Should -Invoke -ModuleName $script:moduleName Resolve-OERCatalogResource -Times 0 -Exactly
    }

    It 'rejects an empty -Group at bind time' {
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {}
        { Add-OERAccessPackageResourceRole -AccessPackage 'AP-Sales' -Catalog 'cat-1' -Group '' -Role 'Member' -Confirm:$false } |
            Should -Throw
        Should -Invoke -ModuleName $script:moduleName Resolve-OERCatalogResource -Times 0 -Exactly
    }

    It 'rejects an empty -Application at bind time' {
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {}
        { Add-OERAccessPackageResourceRole -AccessPackage 'AP-Sales' -Catalog 'cat-1' -Application '' -Role 'Member' -Confirm:$false } |
            Should -Throw
        Should -Invoke -ModuleName $script:moduleName Resolve-OERCatalogResource -Times 0 -Exactly
    }

    It 'still binds -ResourceOriginId positionally (pre-existing contract preserved)' {
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest { @{ id = 'scope-1' } } -ParameterFilter { $Method -eq 'POST' }
        Add-OERAccessPackageResourceRole 'AP-Sales' 'cat-1' 'grp-guid' 'Member' -Confirm:$false | Out-Null
        Should -Invoke -ModuleName $script:moduleName Resolve-OERCatalogResource -Times 1 -Exactly -ParameterFilter { $OriginId -eq 'grp-guid' }
        Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 1 -Exactly -ParameterFilter { $Method -eq 'POST' }
    }

    It 'accepts an AccessPackage object piped in and resolves its Id' {
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest { @{ id = 'scope-pipe' } } -ParameterFilter { $Method -eq 'POST' }
        $ApObj = [pscustomobject]@{ Id = 'AP-1'; DisplayName = 'AP Sales' }
        $ApObj.PSObject.TypeNames.Insert(0, 'Omnicit.EntraRBAC.AccessPackage')
        $ApObj | Add-OERAccessPackageResourceRole -Catalog 'cat-1' -ResourceOriginId 'grp-guid' -Role 'Member' | Out-Null
        Should -Invoke -ModuleName $script:moduleName Resolve-OERAccessPackageId -Times 1 -ParameterFilter {
            $DisplayName -eq 'AP-1'
        }
    }

    It 'surfaces a Graph POST failure as a non-terminating error and emits nothing' {
        # Guards two things the cmdlet must do on a Graph failure: call Remove-OERErrorRecord (the
        # mandatory bearer-token-hygiene line -- asserted via Should -Invoke, since a deleted line
        # would otherwise pass unnoticed) and write its OWN non-terminating record. Match the
        # cmdlet-QUALIFIED ErrorId: PowerShell auto-records the mock's throw into -ErrorVariable a
        # dozen times before the catch runs, so matching the bare Graph code would pass even with
        # WriteError deleted.
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {
            throw [System.Management.Automation.ErrorRecord]::new(
                [System.Exception]::new('Request_BadRequest: The resource role scope is not valid.'),
                'Request_BadRequest',
                [System.Management.Automation.ErrorCategory]::InvalidOperation,
                $null)
        } -ParameterFilter { $Method -eq 'POST' }
        Mock -ModuleName $script:moduleName Remove-OERErrorRecord { }
        $Err = $null
        $Result = Add-OERAccessPackageResourceRole -AccessPackage 'AP-Sales' -Catalog 'cat-1' -ResourceOriginId 'grp-guid' -Role 'Member' `
            -Confirm:$false -ErrorAction SilentlyContinue -ErrorVariable Err
        $Result | Should -BeNullOrEmpty
        @($Err | Where-Object { $_.FullyQualifiedErrorId -eq 'Request_BadRequest,Add-OERAccessPackageResourceRole' }).Count |
            Should -Be 1
        Should -Invoke -ModuleName $script:moduleName Remove-OERErrorRecord -Times 1
    }

    It 'still falls back to a composed tagged object when the confirmation read throws a Graph error record' {
        # This catch (source :129) does not re-surface the record -- it logs via Write-Verbose and
        # falls through to the composed fallback, so the correct assertion here is the fallback
        # shape, not an -ErrorVariable. Still throws a pre-built ErrorRecord (rather than a plain
        # string) so the test models the real shape Invoke-OERGraphRequest -> Get-OERAccessPackageResourceRole
        # would produce, exercising Remove-OERErrorRecord against a genuine ErrorRecord. The catch
        # also calls Remove-OERErrorRecord as its first statement (bearer-hygiene, mandatory even on
        # this fallback path), so that line is guarded here too via Should -Invoke.
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest { @{ id = 'scope-1' } } -ParameterFilter { $Method -eq 'POST' }
        Mock -ModuleName $script:moduleName Get-OERAccessPackageResourceRole {
            throw [System.Management.Automation.ErrorRecord]::new(
                [System.Exception]::new('ServiceNotAvailable: transient failure.'),
                'ServiceNotAvailable',
                [System.Management.Automation.ErrorCategory]::ConnectionError,
                $null)
        }
        Mock -ModuleName $script:moduleName Remove-OERErrorRecord { }
        $Result = Add-OERAccessPackageResourceRole -AccessPackage 'AP-Sales' -Catalog 'cat-1' -ResourceOriginId 'grp-guid' -Role 'Member' -Confirm:$false
        $Result.PSObject.TypeNames[0] | Should -Be 'Omnicit.EntraRBAC.AccessPackageResourceRole'
        $Result.ResourceRoleScopeId | Should -Be 'scope-1'
        $Result.RoleName | Should -Be 'Member'
        Should -Invoke -ModuleName $script:moduleName Remove-OERErrorRecord -Times 1
    }
}

Describe 'Add-OERAccessPackageResourceRole -- a failed resolver read is not a not-found (issue #71, fix round 1)' {
    BeforeEach {
        InModuleScope 'Omnicit.EntraRBAC' { $script:_OERAuthState = $null }
        Mock -ModuleName 'Omnicit.EntraRBAC' Initialize-OERAuth {}
        Mock -ModuleName 'Omnicit.EntraRBAC' Invoke-OERGraphRequest {}
    }

    It 'surfaces a 403 out of Resolve-OERAccessPackageId as itself, never as AccessPackageNotFound' {
        Mock -ModuleName 'Omnicit.EntraRBAC' Resolve-OERAccessPackageId {
            throw [System.Management.Automation.ErrorRecord]::new(
                [System.Exception]::new('Authorization_RequestDenied: Insufficient privileges to complete the operation.'),
                'Authorization_RequestDenied',
                [System.Management.Automation.ErrorCategory]::PermissionDenied,
                'ap-target')
        }
        $Err = $null
        Add-OERAccessPackageResourceRole -AccessPackage 'AP-Sales' -Catalog 'cat-1' -ResourceOriginId 'grp-guid' `
            -Role 'Member' -ErrorAction SilentlyContinue -ErrorVariable Err | Out-Null

        # NARROWED ON PURPOSE, and the narrowing is the whole guard. -ErrorVariable also collects
        # the engine's own capture of the INNER throw, whose FullyQualifiedErrorId is the bare
        # 'Authorization_RequestDenied' whether or not this cmdlet re-published it -- measured, not
        # assumed. An unnarrowed $Err[0] or -join match therefore passes with the fix reverted.
        # Only the record this cmdlet published carries its own name in InvocationInfo.
        $Published = @($Err) | Where-Object {
            $_.InvocationInfo -and $_.InvocationInfo.MyCommand -and
            $_.InvocationInfo.MyCommand.Name -eq 'Add-OERAccessPackageResourceRole'
        }
        @($Published).Count | Should -Be 1
        $Published[0].FullyQualifiedErrorId | Should -Match '^Authorization_RequestDenied'
        $Published[0].FullyQualifiedErrorId | Should -Not -Match 'AccessPackageNotFound' -Because (
            'a permission failure booked as a missing object is the failed-read-as-an-empty-fact defect of issue #76')
        $Published[0].CategoryInfo.Category | Should -Be 'PermissionDenied'
        Should -Invoke -ModuleName 'Omnicit.EntraRBAC' Invoke-OERGraphRequest -Times 0 -Exactly
    }
}
