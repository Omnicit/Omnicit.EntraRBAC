BeforeAll {
    Import-Module Omnicit.EntraRBAC -Force
    . "$PSScriptRoot/../TestHelpers/OERTransportTripwire.ps1"
    Install-OERTransportTripwire
}

AfterAll {
    try { Assert-OERTransportTripwire } finally { Uninstall-OERTransportTripwire }
}

Describe 'Get-OERGroupRelation' {
    BeforeEach {
        Mock -ModuleName Omnicit.EntraRBAC Initialize-OERAuth { }
    }

    It 'adds the service principal only the typed members read lists, once, with ObjectType servicePrincipal' {
        InModuleScope Omnicit.EntraRBAC {
            Mock Invoke-OERGraphRequest { @{ value = @(@{ '@odata.type' = '#microsoft.graph.group'; id = 'g-nested'; displayName = 'nested' }) } } -ParameterFilter { $Uri -eq 'v1.0/groups/22222222-2222-2222-2222-222222222222/members' }
            Mock Invoke-OERGraphRequest { @{ value = @(@{ id = 'sp-1'; displayName = 'an app' }) } } -ParameterFilter { $Uri -eq 'v1.0/groups/22222222-2222-2222-2222-222222222222/members/microsoft.graph.servicePrincipal' }
            $R = @(Get-OERGroupRelation -GroupId '22222222-2222-2222-2222-222222222222' -Relation members)
            $R.Count | Should -Be 2
            $R[0].PrincipalId | Should -Be 'g-nested'
            $R[0].ObjectType | Should -Be 'group'
            $R[1].PrincipalId | Should -Be 'sp-1'
            $R[1].ObjectType | Should -Be 'servicePrincipal'
            $R[1].MemberType | Should -Be 'Member'
            $R[1].GroupId | Should -Be '22222222-2222-2222-2222-222222222222'
            $R[1].PSObject.TypeNames[0] | Should -Be 'Omnicit.EntraRBAC.GroupMember'
        }
    }

    It 'adds the service principal only the typed owners read lists, as an Owner with ObjectType servicePrincipal' {
        InModuleScope Omnicit.EntraRBAC {
            Mock Invoke-OERGraphRequest { @{ value = @() } } -ParameterFilter { $Uri -eq 'v1.0/groups/22222222-2222-2222-2222-222222222222/owners' }
            Mock Invoke-OERGraphRequest { @{ value = @(@{ id = 'sp-1'; displayName = 'an app' }) } } -ParameterFilter { $Uri -eq 'v1.0/groups/22222222-2222-2222-2222-222222222222/owners/microsoft.graph.servicePrincipal' }
            $R = @(Get-OERGroupRelation -GroupId '22222222-2222-2222-2222-222222222222' -Relation owners)
            $R.Count | Should -Be 1
            $R[0].PrincipalId | Should -Be 'sp-1'
            $R[0].ObjectType | Should -Be 'servicePrincipal'
            $R[0].MemberType | Should -Be 'Owner'
            $R[0].GroupId | Should -Be '22222222-2222-2222-2222-222222222222'
            $R[0].PSObject.TypeNames[0] | Should -Be 'Omnicit.EntraRBAC.GroupMember'
        }
    }

    It 'lists a service principal both reads list exactly once, at the untyped position, even when the ids differ in case' {
        InModuleScope Omnicit.EntraRBAC {
            Mock Invoke-OERGraphRequest {
                @{ value = @(
                        @{ '@odata.type' = '#microsoft.graph.servicePrincipal'; id = 'SP-1'; displayName = 'an app' }
                        @{ '@odata.type' = '#microsoft.graph.group'; id = 'g-nested'; displayName = 'nested' }
                    ) }
            } -ParameterFilter { $Uri -eq 'v1.0/groups/22222222-2222-2222-2222-222222222222/members' }
            Mock Invoke-OERGraphRequest { @{ value = @(@{ id = 'sp-1'; displayName = 'an app' }) } } -ParameterFilter { $Uri -eq 'v1.0/groups/22222222-2222-2222-2222-222222222222/members/microsoft.graph.servicePrincipal' }
            $R = @(Get-OERGroupRelation -GroupId '22222222-2222-2222-2222-222222222222' -Relation members)
            $R.Count | Should -Be 2
            # The untyped read's own object, in its own position: the typed copy is the duplicate.
            $R[0].PrincipalId | Should -BeExactly 'SP-1'
            $R[0].ObjectType | Should -Be 'servicePrincipal'
            $R[1].PrincipalId | Should -Be 'g-nested'
            @($R | Where-Object { $_.PrincipalId -eq 'sp-1' }).Count | Should -Be 1
        }
    }

    It 'gives an untyped object with no @odata.type the type the typed read proves, and leaves any other one without' {
        InModuleScope Omnicit.EntraRBAC {
            Mock Invoke-OERGraphRequest {
                @{ value = @(
                        @{ id = 'sp-1'; displayName = 'an app' }
                        @{ id = 'x-1'; displayName = 'unannotated' }
                    ) }
            } -ParameterFilter { $Uri -eq 'v1.0/groups/22222222-2222-2222-2222-222222222222/members' }
            Mock Invoke-OERGraphRequest { @{ value = @(@{ id = 'SP-1'; displayName = 'an app' }) } } -ParameterFilter { $Uri -eq 'v1.0/groups/22222222-2222-2222-2222-222222222222/members/microsoft.graph.servicePrincipal' }
            $R = @(Get-OERGroupRelation -GroupId '22222222-2222-2222-2222-222222222222' -Relation members)
            $R.Count | Should -Be 2
            $R[0].PrincipalId | Should -Be 'sp-1'
            $R[0].ObjectType | Should -Be 'servicePrincipal'
            $R[1].PrincipalId | Should -Be 'x-1'
            ($null -eq $R[1].ObjectType) | Should -BeTrue -Because 'only an id the typed read lists carries a type the read proves'
        }
    }

    It 'sends both the untyped and the typed request with -All, for members and for owners' {
        InModuleScope Omnicit.EntraRBAC {
            Mock Invoke-OERGraphRequest { @{ value = @() } }
            $null = @(Get-OERGroupRelation -GroupId '22222222-2222-2222-2222-222222222222' -Relation members)
            $null = @(Get-OERGroupRelation -GroupId '22222222-2222-2222-2222-222222222222' -Relation owners)
            Should -Invoke Invoke-OERGraphRequest -Times 1 -Exactly -ParameterFilter { $Uri -eq 'v1.0/groups/22222222-2222-2222-2222-222222222222/members' -and $All }
            Should -Invoke Invoke-OERGraphRequest -Times 1 -Exactly -ParameterFilter { $Uri -eq 'v1.0/groups/22222222-2222-2222-2222-222222222222/members/microsoft.graph.servicePrincipal' -and $All }
            Should -Invoke Invoke-OERGraphRequest -Times 1 -Exactly -ParameterFilter { $Uri -eq 'v1.0/groups/22222222-2222-2222-2222-222222222222/owners' -and $All }
            Should -Invoke Invoke-OERGraphRequest -Times 1 -Exactly -ParameterFilter { $Uri -eq 'v1.0/groups/22222222-2222-2222-2222-222222222222/owners/microsoft.graph.servicePrincipal' -and $All }
            Should -Invoke Invoke-OERGraphRequest -Times 4 -Exactly
        }
    }

    It 'emits nothing, and writes no error, when both reads are empty' {
        InModuleScope Omnicit.EntraRBAC {
            Mock Invoke-OERGraphRequest { @{ value = @() } } -ParameterFilter { $Uri -eq 'v1.0/groups/22222222-2222-2222-2222-222222222222/members' }
            Mock Invoke-OERGraphRequest { @{ value = @() } } -ParameterFilter { $Uri -eq 'v1.0/groups/22222222-2222-2222-2222-222222222222/members/microsoft.graph.servicePrincipal' }
            # -ErrorAction Stop: an error record written by the call would throw here and fail the
            # test, so reaching the next line is the proof that none was written. (An unfiltered
            # -ErrorVariable count is not: newer Pester lets its own bookkeeping leak into it.)
            $R = @(Get-OERGroupRelation -GroupId '22222222-2222-2222-2222-222222222222' -Relation members -ErrorAction Stop)
            $R.Count | Should -Be 0
            Should -Invoke Invoke-OERGraphRequest -Times 2 -Exactly
        }
    }

    Context 'a failed read leaves the collection unread' {
        # A collection is read whole or not at all (A5): a failure of either read propagates to the
        # caller, and nothing was emitted before it. The failure is a thrown ErrorRecord, exactly how
        # Invoke-OERGraphRequest raises.
        It 'throws, and the collection never completes, when the typed members read fails after the untyped read succeeded' {
            InModuleScope Omnicit.EntraRBAC {
                Mock Invoke-OERGraphRequest { @{ value = @(@{ '@odata.type' = '#microsoft.graph.group'; id = 'g-nested'; displayName = 'nested' }) } } -ParameterFilter { $Uri -eq 'v1.0/groups/22222222-2222-2222-2222-222222222222/members' }
                Mock Invoke-OERGraphRequest {
                    throw [System.Management.Automation.ErrorRecord]::new([System.Exception]::new('Forbidden: denied'), 'Forbidden', 'PermissionDenied', $null)
                } -ParameterFilter { $Uri -eq 'v1.0/groups/22222222-2222-2222-2222-222222222222/members/microsoft.graph.servicePrincipal' }
                $Collected = 'unset'
                $Caught = $null
                try {
                    $Collected = @(Get-OERGroupRelation -GroupId '22222222-2222-2222-2222-222222222222' -Relation members)
                } catch {
                    $Caught = $PSItem
                }
                # The catch was reached, by the typed read's own record.
                $null -ne $Caught | Should -BeTrue
                $Caught.Exception.Message | Should -Be 'Forbidden: denied'
                $Caught.FullyQualifiedErrorId | Should -BeLike 'Forbidden*'
                # The assignment never completed: the untyped member was not handed out on its own.
                $Collected | Should -Be 'unset'
                Should -Invoke Invoke-OERGraphRequest -Times 1 -Exactly -ParameterFilter { $Uri -eq 'v1.0/groups/22222222-2222-2222-2222-222222222222/members/microsoft.graph.servicePrincipal' }
                Should -Invoke Invoke-OERGraphRequest -Times 2 -Exactly
            }
        }

        It 'throws, and the collection never completes, when the typed owners read fails after the untyped read succeeded' {
            InModuleScope Omnicit.EntraRBAC {
                Mock Invoke-OERGraphRequest { @{ value = @(@{ '@odata.type' = '#microsoft.graph.user'; id = 'u-1'; displayName = 'a user' }) } } -ParameterFilter { $Uri -eq 'v1.0/groups/22222222-2222-2222-2222-222222222222/owners' }
                Mock Invoke-OERGraphRequest {
                    throw [System.Management.Automation.ErrorRecord]::new([System.Exception]::new('Forbidden: denied'), 'Forbidden', 'PermissionDenied', $null)
                } -ParameterFilter { $Uri -eq 'v1.0/groups/22222222-2222-2222-2222-222222222222/owners/microsoft.graph.servicePrincipal' }
                $Collected = 'unset'
                $Caught = $null
                try {
                    $Collected = @(Get-OERGroupRelation -GroupId '22222222-2222-2222-2222-222222222222' -Relation owners)
                } catch {
                    $Caught = $PSItem
                }
                $null -ne $Caught | Should -BeTrue
                $Caught.Exception.Message | Should -Be 'Forbidden: denied'
                $Caught.FullyQualifiedErrorId | Should -BeLike 'Forbidden*'
                $Collected | Should -Be 'unset'
                Should -Invoke Invoke-OERGraphRequest -Times 1 -Exactly -ParameterFilter { $Uri -eq 'v1.0/groups/22222222-2222-2222-2222-222222222222/owners/microsoft.graph.servicePrincipal' }
                Should -Invoke Invoke-OERGraphRequest -Times 2 -Exactly
            }
        }

        # The two tests above collect the call with @(...), which discards whatever a helper emitted
        # before it threw. These two STREAM the call into a list instead, so a helper that handed the
        # untyped objects to the pipeline before the typed read had succeeded is caught here: the
        # caller of a pipeline sees each object the moment it is emitted.
        It 'streams nothing to the pipeline before it throws when the typed members read fails' {
            InModuleScope Omnicit.EntraRBAC {
                Mock Invoke-OERGraphRequest { @{ value = @(@{ '@odata.type' = '#microsoft.graph.group'; id = 'g-nested'; displayName = 'nested' }) } } -ParameterFilter { $Uri -eq 'v1.0/groups/22222222-2222-2222-2222-222222222222/members' }
                Mock Invoke-OERGraphRequest {
                    throw [System.Management.Automation.ErrorRecord]::new([System.Exception]::new('Forbidden: denied'), 'Forbidden', 'PermissionDenied', $null)
                } -ParameterFilter { $Uri -eq 'v1.0/groups/22222222-2222-2222-2222-222222222222/members/microsoft.graph.servicePrincipal' }
                $Streamed = [System.Collections.Generic.List[object]]::new()
                $Caught = $null
                try {
                    Get-OERGroupRelation -GroupId '22222222-2222-2222-2222-222222222222' -Relation members | ForEach-Object { $Streamed.Add($_) }
                } catch {
                    $Caught = $PSItem
                }
                # The catch was reached, by the typed read's own record, with the untyped read already done.
                $null -ne $Caught | Should -BeTrue
                $Caught.Exception.Message | Should -Be 'Forbidden: denied'
                Should -Invoke Invoke-OERGraphRequest -Times 1 -Exactly -ParameterFilter { $Uri -eq 'v1.0/groups/22222222-2222-2222-2222-222222222222/members' }
                Should -Invoke Invoke-OERGraphRequest -Times 1 -Exactly -ParameterFilter { $Uri -eq 'v1.0/groups/22222222-2222-2222-2222-222222222222/members/microsoft.graph.servicePrincipal' }
                $Streamed.Count | Should -Be 0
            }
        }

        It 'streams nothing to the pipeline before it throws when the typed owners read fails' {
            InModuleScope Omnicit.EntraRBAC {
                Mock Invoke-OERGraphRequest { @{ value = @(@{ '@odata.type' = '#microsoft.graph.user'; id = 'u-1'; displayName = 'a user' }) } } -ParameterFilter { $Uri -eq 'v1.0/groups/22222222-2222-2222-2222-222222222222/owners' }
                Mock Invoke-OERGraphRequest {
                    throw [System.Management.Automation.ErrorRecord]::new([System.Exception]::new('Forbidden: denied'), 'Forbidden', 'PermissionDenied', $null)
                } -ParameterFilter { $Uri -eq 'v1.0/groups/22222222-2222-2222-2222-222222222222/owners/microsoft.graph.servicePrincipal' }
                $Streamed = [System.Collections.Generic.List[object]]::new()
                $Caught = $null
                try {
                    Get-OERGroupRelation -GroupId '22222222-2222-2222-2222-222222222222' -Relation owners | ForEach-Object { $Streamed.Add($_) }
                } catch {
                    $Caught = $PSItem
                }
                $null -ne $Caught | Should -BeTrue
                $Caught.Exception.Message | Should -Be 'Forbidden: denied'
                Should -Invoke Invoke-OERGraphRequest -Times 1 -Exactly -ParameterFilter { $Uri -eq 'v1.0/groups/22222222-2222-2222-2222-222222222222/owners' }
                Should -Invoke Invoke-OERGraphRequest -Times 1 -Exactly -ParameterFilter { $Uri -eq 'v1.0/groups/22222222-2222-2222-2222-222222222222/owners/microsoft.graph.servicePrincipal' }
                $Streamed.Count | Should -Be 0
            }
        }

        It 'throws, and never sends the typed members read, when the untyped members read fails' {
            InModuleScope Omnicit.EntraRBAC {
                Mock Invoke-OERGraphRequest {
                    throw [System.Management.Automation.ErrorRecord]::new([System.Exception]::new('Forbidden: denied'), 'Forbidden', 'PermissionDenied', $null)
                } -ParameterFilter { $Uri -eq 'v1.0/groups/22222222-2222-2222-2222-222222222222/members' }
                # Answered, so that a typed read that IS sent shows up as the -Times 0 failure below
                # and not as a "no mock matched" error the catch would also swallow.
                Mock Invoke-OERGraphRequest { @{ value = @() } } -ParameterFilter { $Uri -eq 'v1.0/groups/22222222-2222-2222-2222-222222222222/members/microsoft.graph.servicePrincipal' }
                $Collected = 'unset'
                $Caught = $null
                try {
                    $Collected = @(Get-OERGroupRelation -GroupId '22222222-2222-2222-2222-222222222222' -Relation members)
                } catch {
                    $Caught = $PSItem
                }
                $null -ne $Caught | Should -BeTrue
                $Caught.Exception.Message | Should -Be 'Forbidden: denied'
                $Collected | Should -Be 'unset'
                Should -Invoke Invoke-OERGraphRequest -Times 1 -Exactly -ParameterFilter { $Uri -eq 'v1.0/groups/22222222-2222-2222-2222-222222222222/members' }
                Should -Invoke Invoke-OERGraphRequest -Times 0 -ParameterFilter { $Uri -eq 'v1.0/groups/22222222-2222-2222-2222-222222222222/members/microsoft.graph.servicePrincipal' }
            }
        }

        It 'throws, and never sends the typed owners read, when the untyped owners read fails' {
            InModuleScope Omnicit.EntraRBAC {
                Mock Invoke-OERGraphRequest {
                    throw [System.Management.Automation.ErrorRecord]::new([System.Exception]::new('Forbidden: denied'), 'Forbidden', 'PermissionDenied', $null)
                } -ParameterFilter { $Uri -eq 'v1.0/groups/22222222-2222-2222-2222-222222222222/owners' }
                Mock Invoke-OERGraphRequest { @{ value = @() } } -ParameterFilter { $Uri -eq 'v1.0/groups/22222222-2222-2222-2222-222222222222/owners/microsoft.graph.servicePrincipal' }
                $Collected = 'unset'
                $Caught = $null
                try {
                    $Collected = @(Get-OERGroupRelation -GroupId '22222222-2222-2222-2222-222222222222' -Relation owners)
                } catch {
                    $Caught = $PSItem
                }
                $null -ne $Caught | Should -BeTrue
                $Caught.Exception.Message | Should -Be 'Forbidden: denied'
                $Collected | Should -Be 'unset'
                Should -Invoke Invoke-OERGraphRequest -Times 1 -Exactly -ParameterFilter { $Uri -eq 'v1.0/groups/22222222-2222-2222-2222-222222222222/owners' }
                Should -Invoke Invoke-OERGraphRequest -Times 0 -ParameterFilter { $Uri -eq 'v1.0/groups/22222222-2222-2222-2222-222222222222/owners/microsoft.graph.servicePrincipal' }
            }
        }
    }

    Context 'the typed read list is the measured one' {
        # Scope 3 of Sprint 9 step 1: the typed read covers servicePrincipal only, for both relations.
        # The user, group, device and organizational contact casts showed nothing missing, so a type
        # added to the helper's list without a measurement is a defect this Context turns red.
        It 'reads the untyped collection and exactly one typed collection, servicePrincipal, for members (the list is the 2026-10-06 measurement)' {
            InModuleScope Omnicit.EntraRBAC {
                Mock Invoke-OERGraphRequest { @{ value = @() } }
                $null = @(Get-OERGroupRelation -GroupId '22222222-2222-2222-2222-222222222222' -Relation members)
                Should -Invoke Invoke-OERGraphRequest -Times 2 -Exactly
                Should -Invoke Invoke-OERGraphRequest -Times 1 -Exactly -ParameterFilter { $Uri -notmatch 'microsoft\.graph' }
                Should -Invoke Invoke-OERGraphRequest -Times 1 -Exactly -ParameterFilter { $Uri -match 'microsoft\.graph' }
                Should -Invoke Invoke-OERGraphRequest -Times 1 -Exactly -ParameterFilter { $Uri -like '*/microsoft.graph.servicePrincipal' }
                Should -Invoke Invoke-OERGraphRequest -Times 0 -ParameterFilter { $Uri -match 'microsoft\.graph\.(device|orgContact|user|group)$' }
            }
        }

        It 'reads the untyped collection and exactly one typed collection, servicePrincipal, for owners (the list is the 2026-10-06 measurement)' {
            InModuleScope Omnicit.EntraRBAC {
                Mock Invoke-OERGraphRequest { @{ value = @() } }
                $null = @(Get-OERGroupRelation -GroupId '22222222-2222-2222-2222-222222222222' -Relation owners)
                Should -Invoke Invoke-OERGraphRequest -Times 2 -Exactly
                Should -Invoke Invoke-OERGraphRequest -Times 1 -Exactly -ParameterFilter { $Uri -notmatch 'microsoft\.graph' }
                Should -Invoke Invoke-OERGraphRequest -Times 1 -Exactly -ParameterFilter { $Uri -match 'microsoft\.graph' }
                Should -Invoke Invoke-OERGraphRequest -Times 1 -Exactly -ParameterFilter { $Uri -like '*/microsoft.graph.servicePrincipal' }
                Should -Invoke Invoke-OERGraphRequest -Times 0 -ParameterFilter { $Uri -match 'microsoft\.graph\.(device|orgContact|user|group)$' }
            }
        }
    }

    Context 'the helper is the single reader of a group collection' {
        BeforeAll {
            # Not module code: the scan reads source files with the AST and imports nothing. Unset,
            # OER_COHORT_SOURCE_ROOT leaves it on the repository's own source/; a mutation proof sets
            # it to a scratch copy of source/ so the scan reads the mutated tree and not this one.
            $SourceRoot = if ($env:OER_COHORT_SOURCE_ROOT) {
                $env:OER_COHORT_SOURCE_ROOT
            } else {
                Join-Path -Path $PSScriptRoot -ChildPath '../../../source'
            }
            $SourceRoot = (Resolve-Path -Path $SourceRoot).Path

            # A Graph read of a group's members or owners collection: the Graph path ends at the
            # collection (the {1} of the helper's own format string included). A write (the /$ref
            # suffix), an administrative unit read and the export's unread-collection label
            # (groups/<name>/members, no v1.0 prefix) are no read of this collection.
            $CollectionPattern = '^(v1\.0|beta)/groups/[^/]+/(members|owners|\{1\})$'

            # Every string literal of the tree the AST holds, single quoted and expandable alike,
            # that matches the pattern.
            $GetCollectionReads = {
                param($Ast, $RelativePath)
                foreach ($Node in $Ast.FindAll({
                            param($Candidate)
                            $Candidate -is [System.Management.Automation.Language.StringConstantExpressionAst] -or
                            $Candidate -is [System.Management.Automation.Language.ExpandableStringExpressionAst]
                        }, $true)) {
                    if ($Node.Value -match $CollectionPattern) {
                        [PSCustomObject]@{ Path = $RelativePath; Line = $Node.Extent.StartLineNumber; Value = $Node.Value }
                    }
                }
            }

            $Reads = @(
                foreach ($File in (Get-ChildItem -Path $SourceRoot -Filter '*.ps1' -File -Recurse | Where-Object { $_.Extension -eq '.ps1' })) {
                    $FileAst = [System.Management.Automation.Language.Parser]::ParseFile($File.FullName, [ref]$null, [ref]$null)
                    $Relative = [System.IO.Path]::GetRelativePath($SourceRoot, $File.FullName) -replace '\\', '/'
                    & $GetCollectionReads $FileAst $Relative
                }
            )
        }

        It 'finds no read of a group collection outside Get-OERGroupRelation' {
            $Outside = @($Reads | Where-Object { $_.Path -ne 'Private/Get-OERGroupRelation.ps1' } |
                    ForEach-Object { '{0}:{1} {2}' -f $_.Path, $_.Line, $_.Value })
            $Outside | Should -BeNullOrEmpty -Because 'a second reader of a group collection would leave out the service principals again'
        }

        It 'does find the helper''s own read, so the scan is not vacuous' {
            $Own = @($Reads | Where-Object { $_.Path -eq 'Private/Get-OERGroupRelation.ps1' })
            $Own.Count | Should -BeGreaterOrEqual 1
            $Own.Value | Should -Contain 'v1.0/groups/{0}/{1}'
        }

        It 'reads a double quoted literal as well as a single quoted one' {
            $Snippet = 'Invoke-OERGraphRequest -Uri "v1.0/groups/$Id/members" -All; Invoke-OERGraphRequest -Uri ''v1.0/groups/{0}/owners'' -All'
            $SnippetAst = [System.Management.Automation.Language.Parser]::ParseInput($Snippet, [ref]$null, [ref]$null)
            $Found = @(& $GetCollectionReads $SnippetAst 'snippet.ps1')
            $Found.Count | Should -Be 2
            $Found.Value | Should -Contain 'v1.0/groups/$Id/members'
            $Found.Value | Should -Contain 'v1.0/groups/{0}/owners'
        }

        It 'matches the shapes of a group collection read and not the writes, an administrative unit read or the export label' {
            foreach ($Shape in @('v1.0/groups/{0}/members', 'v1.0/groups/{0}/owners', 'v1.0/groups/{0}/{1}', 'beta/groups/{0}/members')) {
                $Shape | Should -Match $CollectionPattern
            }
            foreach ($Shape in @('v1.0/groups/{0}/{1}/$ref', 'v1.0/directory/administrativeUnits/{0}/members', 'groups/role_sec_x/members')) {
                $Shape | Should -Not -Match $CollectionPattern
            }
        }
    }
}
