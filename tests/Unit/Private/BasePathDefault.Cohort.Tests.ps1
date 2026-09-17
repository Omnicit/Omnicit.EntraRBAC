BeforeAll {
    $script:moduleName = 'Omnicit.EntraRBAC'
    Get-Module $script:moduleName | Remove-Module -Force -ErrorAction SilentlyContinue
    Import-Module $script:moduleName -Force -ErrorAction Stop
}

Describe 'BasePath/-ProfileBasePath default carriers resolve cross-platform (issue #40)' {
    # Cross-cmdlet suite, named after no single function (like AccessReview.Pipeline.Tests.ps1,
    # AmbiguousName.Guard.Tests.ps1 and NothingToUpdate.Cohort.Tests.ps1). Issue #40's core complaint
    # was that the platform matrix proved nothing about platform-specific -BasePath defaults: only
    # Resolve-OERProfilePath and Get-OERConfiguration had coverage, leaving five of the seven carriers
    # unchecked. Invoking New-OERConfiguration or Connect-OER for real would write a profile into the
    # real user's home directory or authenticate, so instead each command's declared -BasePath /
    # -ProfileBasePath default EXPRESSION is discovered from its AST and evaluated directly -- no
    # cmdlet body runs, no file is written, no tenant call is made. Discovery is automatic, so a future
    # carrier is covered here without editing this test. Do not delete this file as an orphan when
    # auditing the one-test-file-per-function invariant.
    BeforeAll {
        $Mod = Get-Module $script:moduleName
        $Cmds = @(& $Mod { Get-Command -Module Omnicit.EntraRBAC -CommandType Function })
        $script:Carriers = @(
            foreach ($C in ($Cmds | Sort-Object Name -Unique)) {
                $Ast = $C.ScriptBlock.Ast
                if (-not $Ast.Body.ParamBlock) { continue }
                foreach ($P in $Ast.Body.ParamBlock.Parameters) {
                    $N = $P.Name.VariablePath.UserPath
                    if ($N -in 'BasePath', 'ProfileBasePath' -and $P.DefaultValue) {
                        [PSCustomObject]@{
                            Command       = $C.Name
                            ParameterName = $N
                            DefaultText   = $P.DefaultValue.Extent.Text
                        }
                    }
                }
            }
        )
    }

    It 'discovers exactly the seven known -BasePath default carriers' {
        # A cohort test that silently discovers zero carriers would pass while proving nothing -- pin
        # both the count and the exact name set so a future rename, removal or addition is caught here
        # rather than silently shrinking coverage.
        $script:Carriers.Count | Should -Be 7
        @($script:Carriers.Command | Sort-Object -Unique) | Should -Be @(
            'Connect-OER',
            'Get-OERConfiguration',
            'New-OERConfiguration',
            'Remove-OERConfiguration',
            'Resolve-OERProfilePath',
            'Resolve-OERTenantAliasCompletion',
            'Set-OERConfiguration'
        )
    }

    It 'evaluates every carrier default without throwing when USERPROFILE is unset' {
        # USERPROFILE is a Windows-only variable and the module declares CompatiblePSEditions Core, so
        # a default built from $env:USERPROFILE failed to bind on Linux and macOS before the affected
        # cmdlet's body ever ran. Every carrier's default now resolves through
        # [System.Environment]::GetFolderPath(UserProfile), falling back to $HOME.
        $Saved = $env:USERPROFILE
        try {
            Remove-Item Env:\USERPROFILE -ErrorAction SilentlyContinue
            foreach ($Carrier in $script:Carriers) {
                # A { ... } | Should -Not -Throw scriptblock is invoked in its own child scope, so an
                # assignment made inside it (e.g. $Result = ...) never reaches this outer scope. Capture
                # the thrown/not-thrown outcome explicitly with try/catch instead, so $Result is real.
                $Threw = $false
                $Result = $null
                try {
                    $Result = & ([scriptblock]::Create($Carrier.DefaultText))
                } catch {
                    $Threw = $true
                }
                $Threw | Should -BeFalse -Because "the $($Carrier.Command) -$($Carrier.ParameterName) default must bind on Linux and macOS"
                $Result | Should -Not -BeNullOrEmpty -Because "the $($Carrier.Command) -$($Carrier.ParameterName) default must produce a path"
                $Result | Should -Match 'Profiles$' -Because "the $($Carrier.Command) -$($Carrier.ParameterName) default must end in the profiles directory segment"
                $Result | Should -Match 'Omnicit\.EntraRBAC' -Because "the $($Carrier.Command) -$($Carrier.ParameterName) default must live under the module config folder"
            }
        } finally {
            if ($null -ne $Saved) { $env:USERPROFILE = $Saved }
        }
    }

    It 'binds the -BasePath default for real through the parameter binder when USERPROFILE is unset' {
        # The two tests above evaluate each default EXPRESSION from the AST in isolation -- sound, but
        # it never proves PowerShell's real parameter binder can actually bind one of those defaults on
        # a live cmdlet. Remove-OERConfiguration is called for real so the binder binds its default,
        # but that default is the REAL home directory (GetFolderPath ignores USERPROFILE on Windows),
        # so the body's first file-system call -- Test-Path on the resolved profile path -- is
        # intercepted, and Remove-Item is mocked so no later change to the body can delete a real
        # profile from here. The intercepted path shows the bound default reached the body
        # (docs/development/rationale.md#bearer-scrub-tests). Remove-OERConfiguration calls no
        # Graph/ARM endpoint (confirmed by reading source/Public/Remove-OERConfiguration.ps1), so no
        # auth mock is needed here.
        Mock -ModuleName $script:moduleName Test-Path { $false }
        Mock -ModuleName $script:moduleName Remove-Item { }
        $Saved = $env:USERPROFILE
        try {
            Remove-Item Env:\USERPROFILE -ErrorAction SilentlyContinue
            $Threw = $false
            try {
                Remove-OERConfiguration -TenantAlias "nonexistent-00000000-0000-0000-0000-000000000062" -WhatIf -ErrorAction SilentlyContinue
            } catch {
                $Threw = $true
            }
            $Threw | Should -Be $false -Because 'binding the -BasePath default must not throw once USERPROFILE is unset'
        } finally {
            if ($null -ne $Saved) { $env:USERPROFILE = $Saved }
        }
        Should -Invoke -ModuleName $script:moduleName Test-Path -Exactly -Times 1 -ParameterFilter {
            $Path -like '*Omnicit.EntraRBAC*Profiles*nonexistent-00000000-0000-0000-0000-000000000062.psd1'
        }
        Should -Invoke -ModuleName $script:moduleName Remove-Item -Exactly -Times 0
    }
}
