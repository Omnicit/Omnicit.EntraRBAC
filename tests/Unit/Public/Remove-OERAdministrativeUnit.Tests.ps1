BeforeAll {
    $script:moduleName = 'Omnicit.EntraRBAC'
    Get-Module $script:moduleName | Remove-Module -Force -ErrorAction SilentlyContinue
    Import-Module $script:moduleName -Force -ErrorAction Stop
}

Describe 'Remove-OERAdministrativeUnit' {
    BeforeEach {
        InModuleScope $script:moduleName { $script:_OERAuthState = $null }
        Mock -ModuleName $script:moduleName Initialize-OERAuth {}
    }

    It 'deletes the AU when confirmed' {
        Mock -ModuleName $script:moduleName Resolve-OERAdministrativeUnitId { 'au-1' }
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {} -ParameterFilter { $Method -eq 'DELETE' }
        Remove-OERAdministrativeUnit -Id 'au-1' -Confirm:$false
        Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 1 -ParameterFilter {
            $Method -eq 'DELETE' -and $Uri -eq 'v1.0/directory/administrativeUnits/au-1'
        }
    }

    It 'warns before deleting and still issues the DELETE' {
        # CLAUDE.md SECURITY rule #4: audit PR9 Task 7 sweep -- the cmdlet emits an operator warning
        # before the destructive DELETE, but no It captured it. The Write-Warning is lexically
        # unconditional immediately before the ShouldProcess gate.
        Mock -ModuleName $script:moduleName Resolve-OERAdministrativeUnitId { 'au-1' }
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {}
        $Warnings = @()
        Remove-OERAdministrativeUnit -Id 'au-1' -Confirm:$false -WarningVariable Warnings -WarningAction SilentlyContinue
        $Warnings.Count | Should -BeGreaterThan 0
        $Warnings -join ' ' | Should -Match 'high-impact'
        Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 1 -ParameterFilter {
            $Method -eq 'DELETE' -and $Uri -eq 'v1.0/directory/administrativeUnits/au-1'
        }
    }

    It 'emits AdministrativeUnitNotFound when the unit cannot be resolved' {
        Mock -ModuleName $script:moduleName Resolve-OERAdministrativeUnitId { $null }
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {}
        Remove-OERAdministrativeUnit -DisplayName 'nope' -Confirm:$false -ErrorVariable err -ErrorAction SilentlyContinue
        $err.FullyQualifiedErrorId | Should -Match 'AdministrativeUnitNotFound'
    }

    It 'reports AdministrativeUnitResolveFailed when the lookup itself fails' {
        Mock -ModuleName $script:moduleName Resolve-OERAdministrativeUnitId { throw 'Forbidden: insufficient privileges' }
        Remove-OERAdministrativeUnit -DisplayName 'au1' -Confirm:$false `
            -ErrorAction SilentlyContinue -ErrorVariable Err
        @($Err).FullyQualifiedErrorId -join ';' | Should -Match 'AdministrativeUnitResolveFailed'
        @($Err).FullyQualifiedErrorId -join ';' | Should -Not -Match 'AdministrativeUnitNotFound'
    }

    It 'does not DELETE under -WhatIf' {
        Mock -ModuleName $script:moduleName Resolve-OERAdministrativeUnitId { 'au-1' }
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {}
        Remove-OERAdministrativeUnit -Id 'au-1' -WhatIf
        Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 0 -ParameterFilter { $Method -eq 'DELETE' }
    }

    It 'DOES warn under -WhatIf, and still destroys nothing' {
        # LIVE-MEASURED (check 13.7): with the Write-Warning sitting behind ShouldProcess, the
        # high-impact warning printed only AFTER the operator had already answered the ConfirmImpact
        # High prompt, and under -WhatIf it never printed at all -- the run whose entire purpose is to
        # show what a delete would do showed the least. The warning now precedes the gate; the DELETE
        # assertion is what still pins that -WhatIf destroys nothing.
        Mock -ModuleName $script:moduleName Resolve-OERAdministrativeUnitId { 'au-1' }
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {}
        $Warnings = @()
        Remove-OERAdministrativeUnit -Id 'au-1' -WhatIf -WarningVariable Warnings -WarningAction SilentlyContinue
        ($Warnings | ForEach-Object { [string]$_ }) -join ' ' | Should -Match 'high-impact' -Because 'a -WhatIf run is exactly when an operator is deciding, so it is the run that most needs the warning'
        Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 0 -Exactly -ParameterFilter { $Method -eq 'DELETE' }
    }

    It 'accepts -DisplayName from the pipeline by property name (name-only object | Remove-OERAdministrativeUnit)' {
        Mock -ModuleName $script:moduleName Resolve-OERAdministrativeUnitId { 'au-3' }
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {}
        [pscustomobject]@{ DisplayName = 'au_hr' } | Remove-OERAdministrativeUnit -Confirm:$false
        Should -Invoke -ModuleName $script:moduleName Resolve-OERAdministrativeUnitId -Times 1 -ParameterFilter {
            $DisplayName -eq 'au_hr'
        }
        Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 1 -ParameterFilter {
            $Method -eq 'DELETE'
        }
    }

    Context 'identity parameter collapse (-AdministrativeUnit and its historical aliases)' {
        It 'dispatches a GUID value to Resolve-OERAdministrativeUnitId -Id' {
            Mock -ModuleName $script:moduleName Resolve-OERAdministrativeUnitId { '77777777-7777-7777-7777-777777777777' }
            Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {}
            Remove-OERAdministrativeUnit -AdministrativeUnit '77777777-7777-7777-7777-777777777777' -Confirm:$false
            Should -Invoke -ModuleName $script:moduleName Resolve-OERAdministrativeUnitId -Times 1 -Exactly -ParameterFilter {
                $Id -eq '77777777-7777-7777-7777-777777777777' -and -not $DisplayName
            }
        }

        It 'dispatches a non-GUID value to Resolve-OERAdministrativeUnitId -DisplayName' {
            Mock -ModuleName $script:moduleName Resolve-OERAdministrativeUnitId { 'au-1' }
            Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {}
            Remove-OERAdministrativeUnit -AdministrativeUnit 'au_hr' -Confirm:$false
            Should -Invoke -ModuleName $script:moduleName Resolve-OERAdministrativeUnitId -Times 1 -Exactly -ParameterFilter {
                $DisplayName -eq 'au_hr' -and -not $Id
            }
        }

        It 'reaches the same resolved id through every historical spelling: -Id, -DisplayName, -AdministrativeUnitId' {
            Mock -ModuleName $script:moduleName Resolve-OERAdministrativeUnitId { 'au-1' }
            Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {}
            foreach ($Spelling in 'Id', 'DisplayName', 'AdministrativeUnitId') {
                $Splat = @{ $Spelling = 'au_hr'; Confirm = $false }
                Remove-OERAdministrativeUnit @Splat
            }
            Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 3 -Exactly -ParameterFilter {
                $Method -eq 'DELETE' -and $Uri -eq 'v1.0/directory/administrativeUnits/au-1'
            }
        }

        It 'round-trips a real ConvertTo-OERAdministrativeUnit object: the AU id (not the display name) reaches the DELETE URI' {
            # Resolve-OERAdministrativeUnitId is NOT mocked here: the piped object binds via the Id
            # alias (Id precedes DisplayName in the alias declaration order), so the value is already a
            # canonical GUID, Test-OERGuid dispatches to -Id, and Resolve-OERAdministrativeUnitId's own
            # real implementation returns it verbatim with no Graph call at all.
            #
            # Built through the REAL private converter (fix-round M5), not a hand-rolled pscustomobject:
            # a hand-rolled stand-in is property-equivalent today but would not notice a future change
            # to ConvertTo-OERAdministrativeUnit's own output shape.
            Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {}
            $Au = InModuleScope $script:moduleName {
                ConvertTo-OERAdministrativeUnit -InputObject @{ id = '88888888-8888-8888-8888-888888888888'; displayName = 'au_hr' }
            }
            $Au | Remove-OERAdministrativeUnit -Confirm:$false
            Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 1 -Exactly -ParameterFilter {
                $Method -eq 'DELETE' -and $Uri -eq 'v1.0/directory/administrativeUnits/88888888-8888-8888-8888-888888888888'
            }
        }

        It 'still binds when splatted, e.g. an apply-engine-style @{ Id = ... } call' {
            Mock -ModuleName $script:moduleName Resolve-OERAdministrativeUnitId { 'au-1' }
            Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {}
            $Splat = @{ Id = 'au-1'; Confirm = $false }
            Remove-OERAdministrativeUnit @Splat
            Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 1 -Exactly -ParameterFilter {
                $Method -eq 'DELETE' -and $Uri -eq 'v1.0/directory/administrativeUnits/au-1'
            }
        }

        It 'positional binding: collapsing ById/ByName into a single parameter set ADDS positional binding (a capability, not a break)' {
            # Before the collapse this cmdlet had two parameter sets (ById/ByName), which suppressed
            # ALL implicit positional binding. After the collapse there is exactly one parameter set
            # and -AdministrativeUnit is its only mandatory parameter, so it now binds positionally.
            # Nothing that worked before stops working -- this only adds a capability that could not
            # exist before -- but it must be asserted explicitly.
            Mock -ModuleName $script:moduleName Resolve-OERAdministrativeUnitId { 'au-1' }
            Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {}
            Remove-OERAdministrativeUnit 'au-1' -Confirm:$false
            Should -Invoke -ModuleName $script:moduleName Resolve-OERAdministrativeUnitId -Times 1 -Exactly -ParameterFilter {
                $DisplayName -eq 'au-1'
            }
            Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 1 -Exactly -ParameterFilter {
                $Method -eq 'DELETE' -and $Uri -eq 'v1.0/directory/administrativeUnits/au-1'
            }
        }
    }
}

Describe 'Remove-OERAdministrativeUnit ambiguous display name' {
    BeforeEach {
        InModuleScope $script:moduleName { $script:_OERAuthState = $null }
        Mock -ModuleName $script:moduleName Initialize-OERAuth {}
    }

    It 'refuses to delete and surfaces the candidate ids through the existing resolve guard' {
        # Ruling 1: this cohort already carries an AdministrativeUnitResolveFailed guard that stops on
        # ANY resolver throw and interpolates $PSItem.Exception.Message, so a second ambiguity-specific
        # guard would give one condition two error paths. This test pins the consequence that matters:
        # the resolver's candidate ids really do reach the operator under that generic ErrorId.
        Mock -ModuleName $script:moduleName Resolve-OERAdministrativeUnitId {
            throw [System.Management.Automation.ErrorRecord]::new(
                [System.Exception]::new(
                    "Administrative unit display name 'Dup' matches 2 units (11111111-1111-1111-1111-111111111111, 22222222-2222-2222-2222-222222222222)."),
                'AmbiguousName', [System.Management.Automation.ErrorCategory]::InvalidArgument, 'Dup')
        }
        Mock -ModuleName $script:moduleName Invoke-OERGraphRequest {}
        Mock -ModuleName $script:moduleName Remove-OERErrorRecord { }
        $Err = $null
        Remove-OERAdministrativeUnit -DisplayName 'Dup' -Confirm:$false -WarningAction SilentlyContinue `
            -ErrorAction SilentlyContinue -ErrorVariable Err
        Should -Invoke -ModuleName $script:moduleName Invoke-OERGraphRequest -Times 0 -ParameterFilter { $Method -eq 'DELETE' }
        Should -Invoke -ModuleName $script:moduleName Remove-OERErrorRecord -Times 1
        @($Err | Where-Object { $_.FullyQualifiedErrorId -eq 'AdministrativeUnitResolveFailed,Remove-OERAdministrativeUnit' }).Count | Should -Be 1
        $Reported = @($Err | Where-Object { $_.FullyQualifiedErrorId -eq 'AdministrativeUnitResolveFailed,Remove-OERAdministrativeUnit' })[0]
        $Reported.Exception.Message | Should -Match '11111111-1111-1111-1111-111111111111'
        $Reported.Exception.Message | Should -Match '22222222-2222-2222-2222-222222222222'
        # No AdministrativeUnitNotFound alongside it: the resolve guard returns.
        @($Err | Where-Object { $_.FullyQualifiedErrorId -eq 'AdministrativeUnitNotFound,Remove-OERAdministrativeUnit' }).Count | Should -Be 0
    }
}
