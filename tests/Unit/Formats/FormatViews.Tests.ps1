BeforeAll {
    $script:moduleName = 'Omnicit.EntraRBAC'
    Get-Module $script:moduleName | Remove-Module -Force -ErrorAction SilentlyContinue
    Import-Module $script:moduleName -Force -ErrorAction Stop
    $script:FormatPath = Join-Path (Split-Path (Get-Module $script:moduleName).Path -Parent) 'Formats/Omnicit.EntraRBAC.Format.ps1xml'
    if (-not (Test-Path $script:FormatPath)) {
        $script:FormatPath = "$PSScriptRoot/../../../source/Formats/Omnicit.EntraRBAC.Format.ps1xml"
    }
}

Describe 'Format views' {
    It 'is valid XML' {
        { [xml](Get-Content -Raw $script:FormatPath) } | Should -Not -Throw
    }

    It 'defines a view for every Phase 1 tagged type' {
        $Xml = [xml](Get-Content -Raw $script:FormatPath)
        $Types = $Xml.Configuration.ViewDefinitions.View.ViewSelectedBy.TypeName
        foreach ($T in 'Omnicit.EntraRBAC.TenantConfiguration', 'Omnicit.EntraRBAC.Group',
                       'Omnicit.EntraRBAC.GroupPimPolicy', 'Omnicit.EntraRBAC.GroupEligibility') {
            $Types | Should -Contain $T
        }
    }

    It 'declares a control and at least one selected type for every view' {
        # Fixture-free structural gate. Building a representative object for all 43 tagged types
        # would drift the moment a converter changes shape; this instead asserts the one thing that
        # is true of every view regardless of shape -- it selects at least one type and declares a
        # control. A view that selects nothing is dead weight, and a view with no control makes
        # Format-* fail at runtime for that type.
        $Xml = [xml](Get-Content -Raw $script:FormatPath)
        $Views = @($Xml.Configuration.ViewDefinitions.View)
        $Views.Count | Should -BeGreaterThan 40 -Because 'the format file declares 43 views; a selector that matched none would make the loop below assert nothing'
        foreach ($V in $Views) {
            @($V.ViewSelectedBy.TypeName).Where({ $_ }).Count |
                Should -BeGreaterThan 0 -Because "view '$($V.Name)' must select at least one type"
            ($null -ne $V.TableControl -or $null -ne $V.ListControl -or
             $null -ne $V.WideControl -or $null -ne $V.CustomControl) |
                Should -Be $true -Because "view '$($V.Name)' must declare a control"
        }
    }

    It 'renders a tagged Group through the registered view with the expected columns and values' {
        # Properties are declared in ConvertTo-OERGroup's own order (Id first, GroupType fifth) so
        # that the view's column order -- DisplayName, GroupType, Id -- is something ONLY the
        # registered view can produce; the default formatter would put Id first and Description and
        # MailNickname in between. Matching the header row alone would be weak, because the default
        # formatter emits property names as headers too and the view's headers are <Label> elements
        # that survive a renamed <PropertyName> unchanged. The ROW-VALUE match is the load-bearing
        # assertion: a <PropertyName> renamed out from under the view renders as an EMPTY cell
        # rather than throwing, which is exactly what the previous Should -Not -Throw check could
        # not see.
        $G = [PSCustomObject]@{
            Id                            = 'g1'
            DisplayName                   = 'role_sec_team'
            Description                   = $null
            MailNickname                  = 'role_sec_team'
            GroupType                     = 'RoleEnabled'
            SecurityEnabled               = $true
            IsAssignableToRole            = $true
            GroupTypes                    = @()
            MembershipRule                = $null
            MembershipRuleProcessingState = $null
        }
        $G.PSObject.TypeNames.Insert(0, 'Omnicit.EntraRBAC.Group')
        $Rendered = $G | Format-Table | Out-String -Width 200

        $Rendered | Should -Match 'DisplayName\s+GroupType\s+Id'
        $Rendered | Should -Match 'role_sec_team\s+RoleEnabled\s+g1'
        $Rendered | Should -Not -Match 'MailNickname' -Because 'the view declares exactly three columns; a MailNickname header means the default formatter ran instead'
    }

    It 'renders the nine Task 8a-affected shapes through their views with the alias-backed column populated' {
        <#
            Task 8a moved nine shapes' Id/Name column from a stored NoteProperty to an AliasProperty
            of a domain-specific stored value (fix round 1, M-1: the original seven omitted
            AdministrativeUnitMember, Format.ps1xml:259 column Id, and AccessReviewStage,
            Format.ps1xml:575 column Id -- both added below). A <PropertyName> in the format view
            resolves through PSObject.Properties the same way a script would, so an AliasProperty is
            invisible to the view engine ONLY if the type tag is missing -- but every one of these
            objects comes from its own converter, which always tags before returning. This pins that
            the column renders the real value (not blank) for all nine, using the REAL converters,
            not hand-built fixtures, so a future accidental order/registration break shows up here.

            RoleDefinition is a tenth entry kept for the same rendering sanity check, but its
            asserted column (Name) is a STORED value on that type, not alias-backed -- Task 2d
            deliberately keeps RoleDefinition without an Id alias, and the alias Task 8a DID add
            there (ResourceId, pointing at RoleDefinitionId) is not a format-view column at all. Its
            presence here proves the view still renders, not that an alias resolved.
        #>
        InModuleScope $script:moduleName {
            $Shapes = [ordered]@{
                GroupMember = @{
                    Object  = ConvertTo-OERGroupMember -InputObject @{ id = 'gm1'; displayName = 'Anna' } -GroupId 'g1'
                    Pattern = 'Anna\s+\S*\s*Member\s+gm1'
                }
                AccessReviewDefinition = @{
                    Object  = ConvertTo-OERAccessReviewDefinition -InputObject @{ id = 'ard1'; displayName = 'Q3'; status = 'InProgress' }
                    Pattern = 'Q3\s+InProgress\s+0\s+0\s+ard1'
                }
                AccessReviewInstance = @{
                    Object  = ConvertTo-OERAccessReviewInstance -InputObject @{ id = 'ari1'; status = 'InProgress'; startDateTime = '2026-01-01'; endDateTime = '2026-02-01' } -DefinitionId 'ard1'
                    Pattern = 'InProgress\s+2026-01-01\s+2026-02-01\s+ari1'
                }
                AccessReviewStage = @{
                    Object  = ConvertTo-OERAccessReviewStage -InputObject @{ id = 'stg1'; status = 'InProgress'; startDateTime = '2026-01-01'; endDateTime = '2026-01-08' }
                    Pattern = 'InProgress\s+2026-01-01\s+2026-01-08\s+stg1'
                }
                AdministrativeUnitMember = @{
                    Object  = ConvertTo-OERAdministrativeUnitMember -InputObject @{ id = 'aum1'; displayName = 'Jane'; '@odata.type' = '#microsoft.graph.user' }
                    Pattern = 'Jane\s+aum1\s+user'
                }
                ManagementGroup = @{
                    Object  = ConvertTo-OERManagementGroup -InputObject @{ id = '/providers/Microsoft.Management/managementGroups/mg1'; name = 'mg1'; properties = @{ tenantId = 't'; displayName = 'MG1' } }
                    Pattern = 'mg1\s+MG1'
                }
                ResourceGroup = @{
                    Object  = ConvertTo-OERResourceGroup -InputObject @{ id = '/subscriptions/1/resourceGroups/rg1'; name = 'rg1'; location = 'westeurope'; properties = @{ provisioningState = 'Succeeded' } }
                    Pattern = 'rg1\s+westeurope\s+Succeeded'
                }
                Resource = @{
                    Object  = ConvertTo-OERResource -InputObject @{ id = '/subscriptions/1/resourceGroups/rg1/providers/Microsoft.Storage/storageAccounts/s1'; name = 's1'; type = 'Microsoft.Storage/storageAccounts'; location = 'westeurope' }
                    Pattern = 's1\s+Microsoft\.Storage/storageAccounts\s+rg1'
                }
                RoleDefinition = @{
                    Object  = ConvertTo-OERRoleDefinition -InputObject @{ id = '/subscriptions/1/providers/Microsoft.Authorization/roleDefinitions/rd1'; name = 'rd1'; properties = @{ roleName = 'Reader'; type = 'BuiltInRole' } }
                    Pattern = 'Reader\s+BuiltInRole\s+rd1'
                }
            }

            foreach ($ShapeName in $Shapes.Keys) {
                $Rendered = $Shapes[$ShapeName].Object | Format-Table | Out-String -Width 200
                $Rendered | Should -Match $Shapes[$ShapeName].Pattern -Because (
                    "the $ShapeName view's asserted column must render the real value, not a blank cell")
            }
        }
    }
}

Describe 'Omnicit.EntraRBAC.TenantConfiguration format view' {
    It 'renders the stored sovereign cloud as a column of its own' {
        <#
            Final whole-branch review, Finding 2. The sovereign-cloud branch added a sixth property
            (Environment) to this shape and never touched the view, so Get-OERConfiguration's default
            output could not show WHICH tenant is sovereign -- the only reason the value is stored at
            all. Built through the real converter rather than a hand-built fixture, matching the
            nine-shape test above.

            The ROW-VALUE match is the load-bearing assertion, for the same reason the Group test
            above gives: a <PropertyName> renamed out from under the view renders as an EMPTY cell
            instead of throwing, and the <Label> headers survive that unchanged. Column order --
            TenantAlias, TenantId, Environment, Path -- is something only the registered view can
            produce: the default formatter would emit Naming and Defaults between Environment and
            Path, which the last assertion pins.
        #>
        $Cfg = InModuleScope $script:moduleName {
            ConvertTo-OERTenantConfiguration -TenantAlias 'govhigh' -TenantId 'tid-gov' `
                -Environment 'USGov' -Naming @{ Group = 'role_{area}' } -Path 'gh.psd1'
        }
        $Rendered = $Cfg | Format-Table | Out-String -Width 200

        $Rendered | Should -Match 'TenantAlias\s+TenantId\s+Environment\s+Path'
        $Rendered | Should -Match 'govhigh\s+tid-gov\s+USGov\s+gh\.psd1'
        $Rendered | Should -Not -Match 'Naming' -Because (
            'the view declares exactly four columns; a Naming header means the default formatter ran instead of the registered view')
    }
}

Describe 'Omnicit.EntraRBAC.Inventory format view' {
    It 'renders Version and the section counts from the lowercase root keys' {
        $Inv = InModuleScope Omnicit.EntraRBAC {
            ConvertTo-OERInventory `
                -Groups @([PSCustomObject]@{ displayName = 'g1' }, [PSCustomObject]@{ displayName = 'g2' }) `
                -AdministrativeUnits @([PSCustomObject]@{ displayName = 'au1' }, [PSCustomObject]@{ displayName = 'au2' }, [PSCustomObject]@{ displayName = 'au3' }) `
                -Catalogs @([PSCustomObject]@{ displayName = 'c1' }) `
                -AccessPackages @([PSCustomObject]@{ displayName = 'ap1' }, [PSCustomObject]@{ displayName = 'ap2' }, [PSCustomObject]@{ displayName = 'ap3' }, [PSCustomObject]@{ displayName = 'ap4' }) `
                -AccessReviews @([PSCustomObject]@{ displayName = 'ar1' }, [PSCustomObject]@{ displayName = 'ar2' }, [PSCustomObject]@{ displayName = 'ar3' }, [PSCustomObject]@{ displayName = 'ar4' }, [PSCustomObject]@{ displayName = 'ar5' }) `
                -RoleAssignments @(1..6 | ForEach-Object { [PSCustomObject]@{ scope = "s$_" } }) `
                -RoleManagementPolicies @(1..7 | ForEach-Object { [PSCustomObject]@{ scope = "s$_" } })
        }
        $Rendered = ($Inv | Format-Table | Out-String -Width 200)
        $Rendered | Should -Match '1\.0'
        # Column order is Version, Groups, AdminUnits, Catalogs, AccessPackages, AccessReviews,
        # RoleAssignments, RoleMgmtPolicies. Every counted column below carries a distinct non-zero
        # value, so the assertion cannot pass on a property lookup that silently returned $null --
        # unlike a zero, a blank cell here has no digit for the regex to match at all.
        $Rendered | Should -Match '2\s+3\s+1\s+4\s+5\s+6\s+7\s'
    }
}
