BeforeAll {
    $script:moduleName = 'Omnicit.EntraRBAC'
    Get-Module $script:moduleName | Remove-Module -Force -ErrorAction SilentlyContinue
    Import-Module $script:moduleName -Force -ErrorAction Stop
}

Describe 'New-OERConfiguration' {
    It 'creates a profile file that Get-OERConfiguration can read' {
        $Base = Join-Path $TestDrive 'Profiles'
        New-OERConfiguration -TenantAlias contoso -TenantId 'tid-1' -BasePath $Base | Out-Null
        $Cfg = Get-OERConfiguration -TenantAlias contoso -BasePath $Base
        $Cfg.TenantId | Should -Be 'tid-1'
    }

    It 'errors (non-terminating) when the alias already exists' {
        $Base = Join-Path $TestDrive 'Profiles2'
        New-OERConfiguration -TenantAlias dup -TenantId 'x' -BasePath $Base | Out-Null
        New-OERConfiguration -TenantAlias dup -TenantId 'y' -BasePath $Base -ErrorVariable err -ErrorAction SilentlyContinue | Out-Null
        $err.FullyQualifiedErrorId | Should -Match 'ProfileAlreadyExists'
    }

    It 'does not write when -WhatIf is used' {
        $Base = Join-Path $TestDrive 'Profiles3'
        New-OERConfiguration -TenantAlias whatif -TenantId 'x' -BasePath $Base -WhatIf | Out-Null
        (Get-OERConfiguration -TenantAlias whatif -BasePath $Base) | Should -BeNullOrEmpty
    }

    It 'returns the full tenant configuration shape including Naming and Defaults' {
        $Base = Join-Path $TestDrive 'pr7new'
        $null = New-Item -ItemType Directory -Path $Base -Force
        $Result = New-OERConfiguration -TenantAlias 'pr7' -TenantId '22222222-2222-2222-2222-222222222222' `
            -Naming @{ Group = 'g_{area}' } -Defaults @{ ActivationMaxHours = 4 } -BasePath $Base -Confirm:$false
        $Result.PSObject.TypeNames[0] | Should -Be 'Omnicit.EntraRBAC.TenantConfiguration'
        $Result.Naming.Group | Should -Be 'g_{area}'
        $Result.Defaults.ActivationMaxHours | Should -Be 4
    }

    It 'rejects a traversal alias without writing a file' {
        Mock -ModuleName Omnicit.EntraRBAC Export-OERConfiguration { }
        $Base = Join-Path $TestDrive 'Profiles'
        New-OERConfiguration -TenantAlias '../../../evil' -TenantId '00000000-0000-0000-0000-000000000001' `
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
            New-OERConfiguration -TenantAlias '..\..\evil' -TenantId 'x' -BasePath $Base `
                -ErrorAction SilentlyContinue -ErrorVariable Err | Out-Null
        } catch {
            $Threw = $true
        }
        $Threw | Should -BeFalse
        @($Err).FullyQualifiedErrorId -join ';' | Should -Match 'ProfilePathEscapesBase'
        Should -Invoke -ModuleName Omnicit.EntraRBAC Export-OERConfiguration -Times 0
    }

    # -------------------------------------------------------------------------------------------
    # Sovereign clouds (Sprint 1.5, issue #81, Task 5): optional -Environment on the Tenant Profile.
    # -------------------------------------------------------------------------------------------
    Context '-Environment' {
        It 'round-trips a stored Environment through Get-OERConfiguration' {
            $Base = Join-Path $TestDrive 'EnvProfiles'
            New-OERConfiguration -TenantAlias usgov -TenantId 'tid-usgov' -Environment USGov -BasePath $Base | Out-Null
            (Get-OERConfiguration -TenantAlias usgov -BasePath $Base).Environment | Should -Be 'USGov'
        }

        It 'writes the Environment key to the PSD1 file on disk' {
            $Base = Join-Path $TestDrive 'EnvProfilesDisk'
            New-OERConfiguration -TenantAlias usgov -TenantId 'tid-usgov' -Environment USGov -BasePath $Base | Out-Null
            $Raw = Get-Content -Path (Join-Path $Base 'usgov.psd1') -Raw
            $Raw | Should -Match "'Environment'\s*=\s*'USGov'"
        }

        It 'returns Environment on the object returned from the create call itself' {
            $Base = Join-Path $TestDrive 'EnvProfilesReturn'
            $Result = New-OERConfiguration -TenantAlias china -TenantId 'tid-china' -Environment China -BasePath $Base
            $Result.Environment | Should -Be 'China'
        }

        It 'writes no Environment key at all when -Environment is omitted, and Get-OERConfiguration returns the same shape as before this parameter existed' {
            $Base = Join-Path $TestDrive 'NoEnvProfiles'
            New-OERConfiguration -TenantAlias contoso -TenantId 'tid-contoso' -BasePath $Base | Out-Null

            $Raw = Get-Content -Path (Join-Path $Base 'contoso.psd1') -Raw
            $Raw | Should -Not -Match 'Environment'

            $Cfg = Get-OERConfiguration -TenantAlias contoso -BasePath $Base
            $Cfg.PSObject.Properties.Name | Should -Contain 'Environment'
            $Cfg.Environment | Should -BeNullOrEmpty
        }

        It 'rejects a cloud that is not one of the four supported values' {
            $Base = Join-Path $TestDrive 'EnvProfilesInvalid'
            { New-OERConfiguration -TenantAlias bad -TenantId 'tid-bad' -Environment 'Germany' -BasePath $Base } |
                Should -Throw '*Germany*'
        }

        It 'declares -Environment LAST in the param block, matching Connect-OER and Set-OERConfiguration' {
            # Positional binding follows DECLARATION order. A new parameter inserted above an
            # existing one silently changes what an existing positional argument binds to, so the
            # newest parameter is declared last -- the same rule the two alias-order cohort suites
            # machine-check elsewhere in this repo.
            $CommandAst = (Get-Command -Name New-OERConfiguration -Module $script:moduleName).ScriptBlock.Ast
            $ParamBlock = if ($CommandAst -is [System.Management.Automation.Language.FunctionDefinitionAst]) {
                $CommandAst.Body.ParamBlock
            } else {
                $CommandAst.ParamBlock
            }
            $Names = @($ParamBlock.Parameters.Name.VariablePath.ForEach({ $_.ToString() }))
            $Names[-1] | Should -Be 'Environment'
        }
    }

    It 'scrubs the error record when the profile path cannot be resolved' {
        # NOT a bearer path. This cmdlet's only catch guards Resolve-OERProfilePath -- local path
        # arithmetic, no HTTP record and no Authorization: Bearer header can ever reach it. The
        # Remove-OERErrorRecord call is still required by CLAUDE.md SECURITY rule 6 (it is
        # unconditional across the module), and this It exists for rule conformance and regression
        # cover, not as a security fix. There is no profile READ on this path to fail, so the
        # containment guard is driven the same way the ProfilePathEscapesBase It above drives it:
        # by bypassing the alias check, never by mocking a transport.
        Mock -ModuleName Omnicit.EntraRBAC Test-OERTenantAlias { $true }
        Mock -ModuleName Omnicit.EntraRBAC Export-OERConfiguration { }
        Mock -ModuleName Omnicit.EntraRBAC Remove-OERErrorRecord { }
        $Base = Join-Path $TestDrive 'ScrubNewEscape'
        $null = New-OERConfiguration -TenantAlias '..\..\evil' -TenantId 'x' -BasePath $Base `
            -ErrorAction SilentlyContinue
        Should -Invoke -ModuleName Omnicit.EntraRBAC Remove-OERErrorRecord -Times 1
        Should -Invoke -ModuleName Omnicit.EntraRBAC Export-OERConfiguration -Times 0
    }
}
