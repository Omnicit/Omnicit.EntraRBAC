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

Describe 'Resolve-OERStructureRoleAssignmentScope' {
    # Resolve-OERScope is mocked: it answers a subscription and a management group with a path that
    # carries a trailing '/', so the canonical form is visible in the result. ConvertTo-OERScopeSplat
    # and ConvertTo-OERCanonicalScope run for real. No id below is version-4 shaped.
    BeforeEach {
        InModuleScope $script:moduleName {
            Mock Initialize-OERAuth {}
            Mock Invoke-OERArmRequest { throw 'unexpected ARM request' }
            Mock Invoke-OERGraphRequest { throw 'unexpected Graph request' }
            Mock Resolve-OERScope {
                param($Scope, $Subscription, $ManagementGroup)
                if ($Subscription) { return '/subscriptions/aaaa1111-0000-0000-0000-000000000001/' }
                if ($ManagementGroup) { return "/providers/Microsoft.Management/managementGroups/$ManagementGroup/" }
                $Scope
            }
        }
    }

    It 'returns one record per entry, in order, with its index, entry, label, raw scope and canonical scope' {
        InModuleScope $script:moduleName {
            $First  = [PSCustomObject]@{ scope = 'sub:Prod'; role = 'Reader'; principal = 'a' }
            $Second = [PSCustomObject]@{ scope = 'mg:plat'; role = 'Owner'; principal = 'b' }
            $r = @(Resolve-OERStructureRoleAssignmentScope -Item @($First, $Second))
            $r.Count | Should -Be 2
            $r[0].Index | Should -Be 0
            $r[1].Index | Should -Be 1
            [object]::ReferenceEquals($r[0].Item, $First) | Should -BeTrue
            [object]::ReferenceEquals($r[1].Item, $Second) | Should -BeTrue
            $r[0].Label | Should -BeExactly 'Reader -> a @ sub:Prod'
            $r[1].Label | Should -BeExactly 'Owner -> b @ mg:plat'
            $r[0].RawScope | Should -BeExactly 'sub:Prod'
            $r[1].RawScope | Should -BeExactly 'mg:plat'
            $r[0].Scope | Should -BeExactly '/subscriptions/aaaa1111-0000-0000-0000-000000000001'
            $r[1].Scope | Should -BeExactly '/providers/Microsoft.Management/managementGroups/plat'
            $r[0].ErrorRecord | Should -BeNullOrEmpty
            $r[1].ErrorRecord | Should -BeNullOrEmpty
            Should -Invoke Resolve-OERScope -Times 1 -Exactly -ParameterFilter { $Subscription -eq 'Prod' }
            Should -Invoke Resolve-OERScope -Times 1 -Exactly -ParameterFilter { $ManagementGroup -eq 'plat' }
        }
    }

    It 'resolves two entries with the same scope text once' {
        InModuleScope $script:moduleName {
            $Items = @(
                [PSCustomObject]@{ scope = 'sub:Prod'; role = 'Reader'; principal = 'a' }
                [PSCustomObject]@{ scope = 'sub:Prod'; role = 'Reader'; principal = 'b' }
            )
            $r = @(Resolve-OERStructureRoleAssignmentScope -Item $Items)
            @($r.Scope) | Should -Be @('/subscriptions/aaaa1111-0000-0000-0000-000000000001', '/subscriptions/aaaa1111-0000-0000-0000-000000000001')
            Should -Invoke Resolve-OERScope -Times 1 -Exactly
        }
    }

    It 'returns a failed resolution as a null scope with its error record, and resolves the same text again for the next entry' {
        InModuleScope $script:moduleName {
            Mock Resolve-OERScope {
                throw [System.Management.Automation.ErrorRecord]::new(
                    [System.Exception]::new("Subscription display name 'Dup Sub' matches 2 subscriptions."),
                    'AmbiguousName',
                    [System.Management.Automation.ErrorCategory]::InvalidArgument,
                    'Dup Sub')
            }
            $Items = @(
                [PSCustomObject]@{ scope = 'sub:Dup Sub'; role = 'Reader'; principal = 'a' }
                [PSCustomObject]@{ scope = 'sub:Dup Sub'; role = 'Reader'; principal = 'b' }
            )
            $r = @(Resolve-OERStructureRoleAssignmentScope -Item $Items)
            $r.Count | Should -Be 2
            foreach ($Entry in $r) {
                $Entry.Scope | Should -BeNullOrEmpty
                $Entry.ErrorRecord | Should -Not -BeNullOrEmpty
                $Entry.ErrorRecord.FullyQualifiedErrorId | Should -BeLike 'AmbiguousName*'
                $Entry.ErrorRecord.TargetObject | Should -BeExactly 'Dup Sub'
                $Entry.ErrorRecord.Exception.Message | Should -Match 'matches 2 subscriptions'
            }
            $r[1].Label | Should -BeExactly 'Reader -> b @ sub:Dup Sub'
            # Failures are not cached: the second entry with the same text resolves again.
            Should -Invoke Resolve-OERScope -Times 2 -Exactly
        }
    }

    It 'scrubs the bearer-hygiene record of a failed resolution' {
        InModuleScope $script:moduleName {
            Mock Resolve-OERScope {
                throw [System.Management.Automation.ErrorRecord]::new(
                    [System.Exception]::new("Subscription display name 'Dup Sub' matches 2 subscriptions."),
                    'AmbiguousName',
                    [System.Management.Automation.ErrorCategory]::InvalidArgument,
                    'Dup Sub')
            }
            Mock Remove-OERErrorRecord {}
            $r = @(Resolve-OERStructureRoleAssignmentScope -Item @([PSCustomObject]@{ scope = 'sub:Dup Sub'; role = 'Reader'; principal = 'a' }))
            $r[0].ErrorRecord.FullyQualifiedErrorId | Should -BeLike 'AmbiguousName*'
            Should -Invoke Remove-OERErrorRecord -Times 1 -Exactly -ParameterFilter { $Record.FullyQualifiedErrorId -like 'AmbiguousName*' }
        }
    }
}
