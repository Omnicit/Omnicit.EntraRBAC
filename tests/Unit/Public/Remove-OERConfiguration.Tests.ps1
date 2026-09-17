BeforeAll {
    $script:moduleName = 'Omnicit.EntraRBAC'
    Get-Module $script:moduleName | Remove-Module -Force -ErrorAction SilentlyContinue
    Import-Module $script:moduleName -Force -ErrorAction Stop
}

Describe 'Remove-OERConfiguration' {
    It 'deletes an existing profile' {
        $Base = Join-Path $TestDrive 'RemProfiles'
        New-OERConfiguration -TenantAlias gone -TenantId 'x' -BasePath $Base | Out-Null
        Remove-OERConfiguration -TenantAlias gone -BasePath $Base -Confirm:$false
        (Get-OERConfiguration -TenantAlias gone -BasePath $Base) | Should -BeNullOrEmpty
    }

    It 'errors when the alias does not exist' {
        $Base = Join-Path $TestDrive 'RemMissing'
        Remove-OERConfiguration -TenantAlias none -BasePath $Base -Confirm:$false -ErrorVariable err -ErrorAction SilentlyContinue
        $err.FullyQualifiedErrorId | Should -Match 'ProfileNotFound'
    }

    It 'accepts TenantAlias from pipeline by property name' {
        $Base = Join-Path $TestDrive 'RemPipe'
        New-OERConfiguration -TenantAlias contoso -TenantId 'pipe-tid' -BasePath $Base | Out-Null
        [pscustomobject]@{ TenantAlias = 'contoso' } | Remove-OERConfiguration -BasePath $Base -Confirm:$false
        (Get-OERConfiguration -TenantAlias contoso -BasePath $Base) | Should -BeNullOrEmpty
    }

    It 'rejects a traversal alias without deleting an unrelated profile' {
        $Base = Join-Path $TestDrive 'RemTraversal'
        $null = New-Item -ItemType Directory -Path $Base -Force
        $ProfilePath = Join-Path $Base 'contoso.psd1'
        New-OERConfiguration -TenantAlias contoso -TenantId 'x' -BasePath $Base | Out-Null

        Remove-OERConfiguration -TenantAlias '../../../evil' -BasePath $Base -Confirm:$false `
            -ErrorAction SilentlyContinue -ErrorVariable Err

        Test-Path $ProfilePath | Should -BeTrue
        # -ErrorVariable collects the raw record first; find the tagged one by ErrorId.
        @($Err).FullyQualifiedErrorId -join ';' | Should -Match 'InvalidTenantAlias'
    }

    It 'converts a ProfilePathEscapesBase failure from Resolve-OERProfilePath into a non-terminating error' {
        # Test-OERTenantAlias already forbids every alias this cmdlet's own check would let through, so
        # a real caller can never reach the containment guard inside Resolve-OERProfilePath. Bypass the
        # alias check the same way Resolve-OERProfilePath.Tests.ps1 does, to prove the public cmdlet
        # wraps that guard's throw instead of letting it terminate the pipeline.
        Mock -ModuleName Omnicit.EntraRBAC Test-OERTenantAlias { $true }
        $Base = Join-Path $TestDrive 'ProfilesEscape'
        New-Item -ItemType Directory -Path $Base -Force | Out-Null
        # A try/catch (unlike a scriptblock piped into Should -Not -Throw) does not introduce a new
        # variable scope, so -ErrorVariable Err stays visible below for the FullyQualifiedErrorId check.
        $Threw = $false
        try {
            Remove-OERConfiguration -TenantAlias '..\..\evil' -BasePath $Base -Confirm:$false `
                -ErrorAction SilentlyContinue -ErrorVariable Err
        } catch {
            $Threw = $true
        }
        $Threw | Should -BeFalse
        @($Err).FullyQualifiedErrorId -join ';' | Should -Match 'ProfilePathEscapesBase'
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
        Mock -ModuleName Omnicit.EntraRBAC Remove-OERErrorRecord { }
        $Base = Join-Path $TestDrive 'ScrubRemoveEscape'
        New-Item -ItemType Directory -Path $Base -Force | Out-Null
        Remove-OERConfiguration -TenantAlias '..\..\evil' -BasePath $Base -Confirm:$false `
            -ErrorAction SilentlyContinue
        Should -Invoke -ModuleName Omnicit.EntraRBAC Remove-OERErrorRecord -Times 1
    }
}
