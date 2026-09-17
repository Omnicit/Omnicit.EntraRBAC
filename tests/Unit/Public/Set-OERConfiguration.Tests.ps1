BeforeAll {
    $script:moduleName = 'Omnicit.EntraRBAC'
    Get-Module $script:moduleName | Remove-Module -Force -ErrorAction SilentlyContinue
    Import-Module $script:moduleName -Force -ErrorAction Stop
}

Describe 'Set-OERConfiguration' {
    It 'updates defaults while preserving tenant id' {
        $Base = Join-Path $TestDrive 'SetProfiles'
        New-OERConfiguration -TenantAlias contoso -TenantId 'keep-me' -BasePath $Base | Out-Null
        Set-OERConfiguration -TenantAlias contoso -Defaults @{ ActivationMaxHours = 4 } -BasePath $Base | Out-Null
        $Cfg = Get-OERConfiguration -TenantAlias contoso -BasePath $Base
        $Cfg.TenantId | Should -Be 'keep-me'
        $Cfg.Defaults.ActivationMaxHours | Should -Be '4'
    }

    It 'errors when the alias does not exist' {
        $Base = Join-Path $TestDrive 'SetMissing'
        Set-OERConfiguration -TenantAlias none -TenantId 'x' -BasePath $Base -ErrorVariable err -ErrorAction SilentlyContinue | Out-Null
        $err.FullyQualifiedErrorId | Should -Match 'ProfileNotFound'
    }

    It 'accepts TenantAlias and TenantId from pipeline by property name' {
        $Base = Join-Path $TestDrive 'SetPipe'
        New-OERConfiguration -TenantAlias contoso -TenantId 'original-tid' -BasePath $Base | Out-Null
        $PipeObj = [pscustomobject]@{
            TenantAlias = 'contoso'
            TenantId    = 'piped-tid'
            Naming      = @{}
            Defaults    = @{}
        }
        $Result = $PipeObj | Set-OERConfiguration -BasePath $Base
        $Result.TenantId | Should -Be 'piped-tid'
        (Get-OERConfiguration -TenantAlias contoso -BasePath $Base).TenantId | Should -Be 'piped-tid'
    }

    It 'echoes the preserved Naming section when -Naming was not supplied' {
        $Base = Join-Path $TestDrive 'pr7set'
        $null = New-Item -ItemType Directory -Path $Base -Force
        $null = New-OERConfiguration -TenantAlias 'pr7set' -TenantId '33333333-3333-3333-3333-333333333333' `
            -Naming @{ Group = 'kept_{area}' } -BasePath $Base -Confirm:$false
        $Result = Set-OERConfiguration -TenantAlias 'pr7set' -TenantId '44444444-4444-4444-4444-444444444444' `
            -BasePath $Base -Confirm:$false
        $Result.TenantId | Should -Be '44444444-4444-4444-4444-444444444444'
        $Result.Naming.Group | Should -Be 'kept_{area}'
    }

    It 'rejects a traversal alias without writing a file' {
        Mock -ModuleName Omnicit.EntraRBAC Export-OERConfiguration { }
        $Base = Join-Path $TestDrive 'Profiles'
        Set-OERConfiguration -TenantAlias '../../../evil' -TenantId '00000000-0000-0000-0000-000000000001' `
            -BasePath $Base -ErrorAction SilentlyContinue -ErrorVariable Err
        # -ErrorVariable collects the raw record first; find the tagged one by ErrorId.
        @($Err).FullyQualifiedErrorId -join ';' | Should -Match 'InvalidTenantAlias'
        Should -Invoke -ModuleName Omnicit.EntraRBAC Export-OERConfiguration -Times 0
    }

    It 'converts a ProfilePathEscapesBase failure from Resolve-OERProfilePath into a non-terminating error' {
        # Test-OERTenantAlias already forbids every alias this cmdlet's own check would let through, so
        # a real caller can never reach the containment guard inside Resolve-OERProfilePath. Bypass the
        # alias check the same way Resolve-OERProfilePath.Tests.ps1 does, to prove the public cmdlet
        # wraps that guard's throw instead of letting it terminate the pipeline.
        Mock -ModuleName Omnicit.EntraRBAC Test-OERTenantAlias { $true }
        Mock -ModuleName Omnicit.EntraRBAC Export-OERConfiguration { }
        $Base = Join-Path $TestDrive 'ProfilesEscape'
        # A try/catch (unlike a scriptblock piped into Should -Not -Throw) does not introduce a new
        # variable scope, so -ErrorVariable Err stays visible below for the FullyQualifiedErrorId check.
        $Threw = $false
        try {
            Set-OERConfiguration -TenantAlias '..\..\evil' -TenantId 'x' -BasePath $Base `
                -ErrorAction SilentlyContinue -ErrorVariable Err | Out-Null
        } catch {
            $Threw = $true
        }
        $Threw | Should -BeFalse
        @($Err).FullyQualifiedErrorId -join ';' | Should -Match 'ProfilePathEscapesBase'
        Should -Invoke -ModuleName Omnicit.EntraRBAC Export-OERConfiguration -Times 0
    }

    It 'leaves an unparsable profile byte-unchanged on disk and reports TenantProfileMalformed' {
        # Unguarded, Import-PowerShellDataFile failed non-terminatingly and returned $null, so the
        # preserve-what-was-not-passed logic rewrote the file with an EMPTY TenantId -- destroying
        # the remaining good data and recreating the very profile Get-OERConfiguration now refuses.
        $Base = Join-Path $TestDrive 'SetUnparsable'
        New-Item -ItemType Directory -Path $Base -Force | Out-Null
        $File = Join-Path $Base 'broken.psd1'
        Set-Content -Path $File -Value "@{ Tenant Id = 'still-here' }" -Encoding utf8
        $Before = (Get-FileHash -Path $File -Algorithm SHA256).Hash

        Set-OERConfiguration -TenantAlias broken -Defaults @{ ActivationMaxHours = 4 } -BasePath $Base `
            -ErrorAction SilentlyContinue -ErrorVariable Err | Out-Null

        # The byte-unchanged assertion is the one that matters: it is the data-loss guard.
        (Get-FileHash -Path $File -Algorithm SHA256).Hash | Should -Be $Before
        @($Err | Where-Object { $_.FullyQualifiedErrorId -eq 'TenantProfileMalformed,Set-OERConfiguration' }).Count |
            Should -Be 1
    }

    It 'scrubs the error record when the profile read fails' {
        # NOT a bearer path. Every *-OERConfiguration catch guards local file IO
        # (Resolve-OERProfilePath / Import-PowerShellDataFile), so no HttpRequestMessage and no
        # Authorization: Bearer header can ever reach it. The Remove-OERErrorRecord call is still
        # required by CLAUDE.md SECURITY rule 6 (it is unconditional across the module), and this It
        # exists for rule conformance and regression cover, not as a security fix.
        # This drives the Import-PowerShellDataFile catch -- the one that refuses to rewrite an
        # unreadable profile -- by putting an unparsable PSD1 under a temp -BasePath rather than by
        # mocking any transport.
        Mock -ModuleName Omnicit.EntraRBAC Remove-OERErrorRecord { }
        $Base = Join-Path $TestDrive 'ScrubSetUnparsable'
        New-Item -ItemType Directory -Path $Base -Force | Out-Null
        Set-Content -Path (Join-Path $Base 'broken.psd1') -Value "@{ Tenant Id = 'still-here' }" -Encoding utf8

        Set-OERConfiguration -TenantAlias broken -Defaults @{ ActivationMaxHours = 4 } -BasePath $Base `
            -ErrorAction SilentlyContinue | Out-Null
        Should -Invoke -ModuleName Omnicit.EntraRBAC Remove-OERErrorRecord -Times 1
    }

    It 'leaves an unparsable profile byte-unchanged even when -TenantId is supplied' {
        # This is the silent data-loss variant, and the one the byte-unchanged assertion exists for.
        # With -TenantId supplied the resolved TenantId is non-empty, so an unguarded read would
        # sail past every other check and rewrite the file from a null $Existing -- silently
        # discarding the Naming and Defaults sections still sitting in the broken file.
        $Base = Join-Path $TestDrive 'SetUnparsableWithTid'
        New-Item -ItemType Directory -Path $Base -Force | Out-Null
        $File = Join-Path $Base 'broken2.psd1'
        Set-Content -Path $File -Value "@{ Tenant Id = 'x'; Naming = @{ Group = 'keep_me' } }" -Encoding utf8
        $Before = (Get-FileHash -Path $File -Algorithm SHA256).Hash

        Set-OERConfiguration -TenantAlias broken2 -TenantId 'new-tid' -BasePath $Base `
            -ErrorAction SilentlyContinue -ErrorVariable Err | Out-Null

        (Get-FileHash -Path $File -Algorithm SHA256).Hash | Should -Be $Before
        (Get-Content -Path $File -Raw) | Should -Match 'keep_me'
        @($Err | Where-Object { $_.FullyQualifiedErrorId -eq 'TenantProfileMalformed,Set-OERConfiguration' }).Count |
            Should -Be 1
    }

    It 'refuses an update that would leave the profile without a TenantId' {
        # This file parses cleanly, so only the resolved-TenantId guard catches it.
        $Base = Join-Path $TestDrive 'SetNoTenantId'
        New-Item -ItemType Directory -Path $Base -Force | Out-Null
        $File = Join-Path $Base 'empty.psd1'
        Set-Content -Path $File -Value "@{ Naming = @{ Group = 'role_{area}' } }" -Encoding utf8
        $Before = (Get-FileHash -Path $File -Algorithm SHA256).Hash

        Set-OERConfiguration -TenantAlias empty -Defaults @{ ActivationMaxHours = 4 } -BasePath $Base `
            -ErrorAction SilentlyContinue -ErrorVariable Err | Out-Null

        (Get-FileHash -Path $File -Algorithm SHA256).Hash | Should -Be $Before
        @($Err | Where-Object { $_.FullyQualifiedErrorId -eq 'TenantProfileMalformed,Set-OERConfiguration' }).Count |
            Should -Be 1
    }

    It 'still repairs a profile that lost its TenantId when -TenantId is supplied' {
        # The guard is on the RESOLVED value, not on the file, so the repair route named in
        # Get-OERConfiguration's own error message keeps working.
        $Base = Join-Path $TestDrive 'SetRepair'
        New-Item -ItemType Directory -Path $Base -Force | Out-Null
        Set-Content -Path (Join-Path $Base 'fixme.psd1') -Value "@{ Naming = @{ Group = 'role_{area}' } }" -Encoding utf8

        $Result = Set-OERConfiguration -TenantAlias fixme -TenantId 'repaired-tid' -BasePath $Base `
            -ErrorAction SilentlyContinue -ErrorVariable Err
        $Result.TenantId | Should -Be 'repaired-tid'
        @($Err | Where-Object { $_.FullyQualifiedErrorId -eq 'TenantProfileMalformed,Set-OERConfiguration' }).Count |
            Should -Be 0
        (Get-OERConfiguration -TenantAlias fixme -BasePath $Base).TenantId | Should -Be 'repaired-tid'
    }

    # -------------------------------------------------------------------------------------------
    # Sovereign clouds (Sprint 1.5, issue #81, Task 5): optional -Environment on the Tenant Profile.
    # -------------------------------------------------------------------------------------------
    Context '-Environment' {
        It 'adds Environment to a profile that had none' {
            $Base = Join-Path $TestDrive 'SetEnvAdd'
            New-OERConfiguration -TenantAlias contoso -TenantId 'tid-contoso' -BasePath $Base | Out-Null
            $Result = Set-OERConfiguration -TenantAlias contoso -Environment China -BasePath $Base
            $Result.Environment | Should -Be 'China'
            (Get-OERConfiguration -TenantAlias contoso -BasePath $Base).Environment | Should -Be 'China'
        }

        It 'leaves a stored Environment intact when a later update omits -Environment' {
            $Base = Join-Path $TestDrive 'SetEnvPreserve'
            New-OERConfiguration -TenantAlias usgov -TenantId 'tid-usgov' -Environment USGov -BasePath $Base | Out-Null
            $Result = Set-OERConfiguration -TenantAlias usgov -Defaults @{ ActivationMaxHours = 4 } -BasePath $Base
            $Result.Environment | Should -Be 'USGov'
            (Get-OERConfiguration -TenantAlias usgov -BasePath $Base).Environment | Should -Be 'USGov'
        }

        It 'does not invent an Environment where the profile never had one' {
            $Base = Join-Path $TestDrive 'SetEnvNoInvent'
            New-OERConfiguration -TenantAlias contoso -TenantId 'tid-contoso' -BasePath $Base | Out-Null
            $Result = Set-OERConfiguration -TenantAlias contoso -Defaults @{ ActivationMaxHours = 4 } -BasePath $Base
            $Result.Environment | Should -BeNullOrEmpty
            (Get-OERConfiguration -TenantAlias contoso -BasePath $Base).Environment | Should -BeNullOrEmpty
        }

        It 'replaces an existing Environment with a newly supplied one' {
            $Base = Join-Path $TestDrive 'SetEnvReplace'
            New-OERConfiguration -TenantAlias corp -TenantId 'tid-corp' -Environment USGov -BasePath $Base | Out-Null
            Set-OERConfiguration -TenantAlias corp -Environment USGovDoD -BasePath $Base | Out-Null
            (Get-OERConfiguration -TenantAlias corp -BasePath $Base).Environment | Should -Be 'USGovDoD'
        }

        It '-Environment alone satisfies the updatable-property guard (does not report NothingToUpdate)' {
            $Base = Join-Path $TestDrive 'SetEnvOnly'
            New-OERConfiguration -TenantAlias corp -TenantId 'tid-corp' -BasePath $Base | Out-Null
            $Err = $null
            Set-OERConfiguration -TenantAlias corp -Environment China -BasePath $Base `
                -ErrorAction SilentlyContinue -ErrorVariable Err | Out-Null
            @($Err | Where-Object { $_.FullyQualifiedErrorId -eq 'NothingToUpdate,Set-OERConfiguration' }).Count |
                Should -Be 0
            (Get-OERConfiguration -TenantAlias corp -BasePath $Base).Environment | Should -Be 'China'
        }

        It 'rejects a cloud that is not one of the four supported values' {
            $Base = Join-Path $TestDrive 'SetEnvInvalid'
            New-OERConfiguration -TenantAlias corp -TenantId 'tid-corp' -BasePath $Base | Out-Null
            { Set-OERConfiguration -TenantAlias corp -Environment 'Germany' -BasePath $Base } |
                Should -Throw '*Germany*'
        }

        It 'declares -Environment LAST in the param block, matching Connect-OER and New-OERConfiguration' {
            $CommandAst = (Get-Command -Name Set-OERConfiguration -Module $script:moduleName).ScriptBlock.Ast
            $ParamBlock = if ($CommandAst -is [System.Management.Automation.Language.FunctionDefinitionAst]) {
                $CommandAst.Body.ParamBlock
            } else {
                $CommandAst.ParamBlock
            }
            $Names = @($ParamBlock.Parameters.Name.VariablePath.ForEach({ $_.ToString() }))
            $Names[-1] | Should -Be 'Environment'
        }

        # Task 5 Phase 2: -Environment itself can never carry an invalid value (ValidateSet already
        # refuses that), but the PRESERVE path reads $Existing.Environment straight off disk with no
        # validation of its own -- a hand-edited or pre-validation profile's bad value must not
        # round-trip silently through this cmdlet's own returned object and back onto disk unreported.
        It 'refuses an update that would preserve and return an unsupported stored Environment value, leaving the file byte-unchanged' {
            $Base = Join-Path $TestDrive 'SetEnvPreserveInvalid'
            New-Item -ItemType Directory -Path $Base -Force | Out-Null
            $File = Join-Path $Base 'badcloud.psd1'
            Set-Content -Path $File -Value "@{ TenantId = 'x'; Environment = 'Mars' }" -Encoding utf8
            $Before = (Get-FileHash -Path $File -Algorithm SHA256).Hash

            $Result = Set-OERConfiguration -TenantAlias badcloud -Defaults @{ ActivationMaxHours = 4 } -BasePath $Base `
                -ErrorAction SilentlyContinue -ErrorVariable Err

            $Result | Should -BeNullOrEmpty
            (Get-FileHash -Path $File -Algorithm SHA256).Hash | Should -Be $Before
            @($Err | Where-Object {
                    $_.FullyQualifiedErrorId -eq 'TenantProfileMalformed,Set-OERConfiguration' -and
                    $_.Exception.Message -match 'unsupported stored Environment'
                }).Count | Should -Be 1
        }

        <#
            Final whole-branch review, Finding 1. -Environment was declared
            ValueFromPipelineByPropertyName next to its ValidateSet.
            ConvertTo-OERTenantConfiguration ALWAYS emits an Environment property, and an unbound
            [string] parameter bound from it is '', not absent, so every profile written before this
            key existed piped '' straight at the ValidateSet and the binder refused the whole call:

                ParameterArgumentValidationError,Set-OERConfiguration ::
                  The argument "" does not belong to the set "Global,USGov,USGovDoD,China"

            The profile was left unmodified and, under -ErrorAction SilentlyContinue, the update was
            lost in silence. Naming and Defaults never showed it: they are bare [hashtable]
            parameters with no ValidateSet, so a $null binds harmlessly.

            The pre-existing pipeline test in this file could not catch it either -- it pipes a
            hand-built [pscustomobject] carrying no Environment property at all, which binds fine.
            These two therefore pipe a GENUINE Get-OERConfiguration object, and assert the update
            lands ON DISK rather than only being echoed by the returned object.
        #>
        It 'round-trips a real Get-OERConfiguration object for a profile that stores no cloud' {
            $Base = Join-Path $TestDrive 'SetEnvRoundTripNone'
            New-OERConfiguration -TenantAlias plain -TenantId 'tid-plain' -BasePath $Base | Out-Null

            $Piped = Get-OERConfiguration -TenantAlias plain -BasePath $Base
            $Piped.PSObject.Properties.Name | Should -Contain 'Environment' -Because (
                'the converter always emits the property, so the round trip has to survive it being empty; if it stopped emitting it, this test would prove nothing')
            $Piped.Environment | Should -BeNullOrEmpty

            # -ErrorVariable does NOT see this defect, and an -ErrorVariable-only assertion here is
            # guard-shaped and inert. Measured, not assumed: with the binding deliberately re-added
            # and the module rebuilt, -ErrorVariable stayed EMPTY (count 0) while $Error gained
            # exactly one ParameterArgumentValidationError,Set-OERConfiguration record. A
            # parameter-binding validation failure on PIPELINE input is raised by the binder before
            # the common parameters it would populate are in force, so it reaches the caller's
            # $Error and nothing else. Both are asserted below: $Error for the binder, -ErrorVariable
            # for anything the cmdlet body itself would write.
            $Error.Clear()
            $Err = $null
            $Result = $Piped | Set-OERConfiguration -Defaults @{ ActivationMaxHours = 4 } -BasePath $Base `
                -ErrorAction SilentlyContinue -ErrorVariable Err

            @($Error | Where-Object { $_.FullyQualifiedErrorId -like 'ParameterArgumentValidation*' }).Count |
                Should -Be 0 -Because (
                    'an empty stored cloud must never reach the ValidateSet from the pipeline; the binder rejects it and refuses the entire update before the cmdlet body runs')
            @($Err).Count | Should -Be 0 -Because 'the cmdlet body must write no error of its own either'
            $Result.TenantId | Should -Be 'tid-plain'
            $Stored = Get-OERConfiguration -TenantAlias plain -BasePath $Base
            $Stored.Defaults.ActivationMaxHours | Should -Be '4' -Because (
                'the update has to land on disk, not merely be reported by the returned object')
            $Stored.Environment | Should -BeNullOrEmpty -Because (
                'a round trip must not invent a cloud for a profile that never had one')
        }

        It 'round-trips a real Get-OERConfiguration object for a profile that stores a cloud, keeping it' {
            $Base = Join-Path $TestDrive 'SetEnvRoundTripStored'
            New-OERConfiguration -TenantAlias govhigh -TenantId 'tid-gov' -Environment USGov -BasePath $Base | Out-Null

            $Piped = Get-OERConfiguration -TenantAlias govhigh -BasePath $Base
            $Piped.Environment | Should -Be 'USGov'

            # Same two-stream assertion as the test above, for the same measured reason.
            $Error.Clear()
            $Err = $null
            $Result = $Piped | Set-OERConfiguration -Defaults @{ ActivationMaxHours = 6 } -BasePath $Base `
                -ErrorAction SilentlyContinue -ErrorVariable Err

            @($Error | Where-Object { $_.FullyQualifiedErrorId -like 'ParameterArgumentValidation*' }).Count |
                Should -Be 0 -Because (
                    'a stored USGov must bind or be preserved, never be rejected at the ValidateSet from the pipeline')
            @($Err).Count | Should -Be 0
            $Result.Environment | Should -Be 'USGov'
            $Stored = Get-OERConfiguration -TenantAlias govhigh -BasePath $Base
            $Stored.Environment | Should -Be 'USGov' -Because (
                'the stored cloud survives a round trip through the preserve path, which needs no pipeline binding')
            $Stored.Defaults.ActivationMaxHours | Should -Be '6'
        }

        It 'does not declare -Environment ValueFromPipelineByPropertyName' {
            # The direct guard against re-adding the binding: the two round-trip tests above prove the
            # symptom is gone, this one pins the cause. A ParameterAttribute is present even when the
            # source declares no [Parameter()] of its own, so the filter below is not vacuous -- it
            # reads the flag off whatever attribute the runtime built.
            $Attributes = @((Get-Command -Name Set-OERConfiguration -Module $script:moduleName).Parameters['Environment'].Attributes |
                    Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] })
            @($Attributes | Where-Object { $_.ValueFromPipelineByPropertyName }).Count |
                Should -Be 0 -Because (
                    'the ValidateSet rejects the empty string that every profile without a stored cloud pipes, so property-name binding here breaks Get-OERConfiguration piped into Set-OERConfiguration for 100% of pre-existing profiles')
        }

        It 'still repairs a profile with an unsupported stored Environment when a valid -Environment is supplied' {
            # The guard is on the RESOLVED value, not on $Existing -- matching the TenantId repair
            # test above -- so supplying a valid -Environment explicitly bypasses the bad stored one.
            $Base = Join-Path $TestDrive 'SetEnvRepair'
            New-Item -ItemType Directory -Path $Base -Force | Out-Null
            Set-Content -Path (Join-Path $Base 'badcloud.psd1') -Value "@{ TenantId = 'x'; Environment = 'Mars' }" -Encoding utf8

            $Result = Set-OERConfiguration -TenantAlias badcloud -Environment USGov -BasePath $Base `
                -ErrorAction SilentlyContinue -ErrorVariable Err
            $Result.Environment | Should -Be 'USGov'
            @($Err | Where-Object { $_.FullyQualifiedErrorId -eq 'TenantProfileMalformed,Set-OERConfiguration' }).Count |
                Should -Be 0
            (Get-OERConfiguration -TenantAlias badcloud -BasePath $Base).Environment | Should -Be 'USGov'
        }
    }

    It 'still updates a valid profile exactly as before' {
        $Base = Join-Path $TestDrive 'SetStillWorks'
        New-OERConfiguration -TenantAlias good -TenantId 'keep-me' -BasePath $Base `
            -Naming @{ Group = 'role_{area}' } | Out-Null
        $Result = Set-OERConfiguration -TenantAlias good -Defaults @{ ActivationMaxHours = 8 } -BasePath $Base `
            -ErrorAction SilentlyContinue -ErrorVariable Err
        @($Err).Count | Should -Be 0
        $Result.TenantId | Should -Be 'keep-me'
        $Result.Naming.Group | Should -Be 'role_{area}'
        $Result.Defaults.ActivationMaxHours | Should -Be '8'
    }
}
