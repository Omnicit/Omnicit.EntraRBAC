BeforeDiscovery {
    $projectPath = "$($PSScriptRoot)\..\.." | Convert-Path

    <#
        If the QA tests are run outside of the build script (e.g with Invoke-Pester)
        the parent scope has not set the variable $ProjectName.
    #>
    if (-not $ProjectName)
    {
        # Assuming project folder name is project name.
        $ProjectName = Get-SamplerProjectName -BuildRoot $projectPath
    }

    $script:moduleName = $ProjectName

    <#
        The eight command cohorts the about topic is expected to orient a reader across. Each
        entry lists cmdlets that belong to that cohort; naming any ONE of them satisfies the
        cohort. Defined at discovery so Pester can expand one test case per cohort.
    #>
    $cohortCases = @(
        @{
            Cohort = 'Authentication and configuration'
            Any    = @('Connect-OER', 'Disconnect-OER', 'New-OERConfiguration', 'Get-OERConfiguration',
                'Set-OERConfiguration', 'Remove-OERConfiguration')
        }
        @{
            Cohort = 'Groups and PIM for Groups'
            Any    = @('New-OERGroup', 'Get-OERGroup', 'Set-OERGroup', 'Remove-OERGroup',
                'Add-OERGroupMember', 'Get-OERGroupMember', 'Remove-OERGroupMember',
                'Get-OERGroupPimPolicy', 'Set-OERGroupPimPolicy')
        }
        @{
            Cohort = 'Administrative Units'
            Any    = @('New-OERAdministrativeUnit', 'Get-OERAdministrativeUnit',
                'Set-OERAdministrativeUnit', 'Remove-OERAdministrativeUnit',
                'Add-OERAdministrativeUnitMember', 'Remove-OERAdministrativeUnitMember',
                'Add-OERAdministrativeUnitScopedRole', 'Get-OERAdministrativeUnitScopedRole',
                'Remove-OERAdministrativeUnitScopedRole')
        }
        @{
            Cohort = 'Entitlement Management'
            Any    = @('New-OERCatalog', 'Get-OERCatalog', 'Set-OERCatalog', 'Remove-OERCatalog',
                'Add-OERCatalogResource', 'Get-OERCatalogResource', 'Remove-OERCatalogResource',
                'New-OERAccessPackage', 'Get-OERAccessPackage', 'Set-OERAccessPackage',
                'Remove-OERAccessPackage')
        }
        @{
            Cohort = 'Access Reviews'
            Any    = @('New-OERAccessReviewDefinition', 'Get-OERAccessReviewDefinition',
                'Set-OERAccessReviewDefinition', 'Remove-OERAccessReviewDefinition',
                'New-OERAccessReviewStage', 'Get-OERAccessReviewInstance',
                'Get-OERAccessReviewInstanceDecision', 'Stop-OERAccessReviewInstance',
                'Invoke-OERAccessReviewInstanceDecision', 'Send-OERAccessReviewReminder')
        }
        @{
            Cohort = 'Azure inventory and RBAC'
            Any    = @('Get-OERManagementGroup', 'Get-OERSubscription', 'Get-OERRoleDefinition',
                'Get-OERRoleAssignment', 'New-OERRoleAssignment', 'Set-OERRoleAssignment',
                'Remove-OERRoleAssignment', 'Get-OERResource', 'New-OERResourceGroup',
                'Get-OERResourceGroup', 'Set-OERResourceGroup', 'Remove-OERResourceGroup')
        }
        @{
            Cohort = 'Azure PIM'
            Any    = @('New-OEREligibleRoleAssignment', 'Get-OEREligibleRoleAssignment',
                'Remove-OEREligibleRoleAssignment', 'Enable-OEREligibleRoleAssignment',
                'Disable-OEREligibleRoleAssignment', 'New-OERActiveRoleAssignment',
                'Get-OERActiveRoleAssignment', 'Remove-OERActiveRoleAssignment',
                'Get-OERRoleManagementPolicy', 'Set-OERRoleManagementPolicy',
                'New-OERPolicyNotificationRule')
        }
        @{
            Cohort = 'Inventory and JSON orchestration'
            Any    = @('Get-OERInventory', 'Export-OERInventory', 'Test-OERStructure',
                'Invoke-OERStructure')
        }
    )
}

BeforeAll {
    # Convert-Path required for PS7 or Join-Path fails
    $projectPath = "$($PSScriptRoot)\..\.." | Convert-Path

    if (-not $ProjectName)
    {
        $ProjectName = Get-SamplerProjectName -BuildRoot $projectPath
    }

    $script:moduleName = $ProjectName
    $script:aboutFileName = 'about_{0}.help.txt' -f $script:moduleName

    $script:sourceAboutPath = Join-Path -Path $projectPath -ChildPath 'source' |
        Join-Path -ChildPath 'en-US' |
            Join-Path -ChildPath $script:aboutFileName

    $script:sourceManifestPath = Join-Path -Path $projectPath -ChildPath 'source' |
        Join-Path -ChildPath ('{0}.psd1' -f $script:moduleName)

    $script:exportedNames = (Import-PowerShellDataFile -Path $script:sourceManifestPath).FunctionsToExport

    <#
        Read the raw bytes rather than Get-Content so the BOM and any non-ASCII byte are
        observable. Authored files in this module are UTF-8 without BOM and ASCII-only, which
        means a BOM-less file with a high byte fails the PSUseBOMForUnicodeEncodedFile gate.
    #>
    $script:aboutBytes = [System.IO.File]::ReadAllBytes($script:sourceAboutPath)
    $script:aboutText = [System.Text.Encoding]::UTF8.GetString($script:aboutBytes)
}

Describe 'About topic' -Tags 'helpQuality' {
    It 'Should exist in the source tree' {
        Test-Path -Path $script:sourceAboutPath | Should -BeTrue -Because 'the about topic is the in-box overview'
    }

    It 'Should ship in the built module' {
        $builtModule = Get-Module -Name $script:moduleName -ListAvailable | Select-Object -First 1
        $builtModule | Should -Not -BeNullOrEmpty -Because 'the built module must be discoverable'

        $builtAbout = Join-Path -Path (Split-Path -Path $builtModule.Path -Parent) -ChildPath 'en-US' |
            Join-Path -ChildPath $script:aboutFileName

        Test-Path -Path $builtAbout | Should -BeTrue -Because 'build.yaml CopyPaths must copy en-US into the built module'
    }

    It 'Should ship the same bytes that the source tree holds' {
        <#
            Every content assertion below reads the SOURCE file, but the copy a consumer reads
            through Get-Help about_Omnicit.EntraRBAC is the built one. Without this check a stale
            built copy -- an edit without a rebuild, or a CopyPaths regression -- passes them all.
        #>
        $builtModule = Get-Module -Name $script:moduleName -ListAvailable | Select-Object -First 1
        $builtAbout = Join-Path -Path (Split-Path -Path $builtModule.Path -Parent) -ChildPath 'en-US' |
            Join-Path -ChildPath $script:aboutFileName

        (Get-FileHash -Path $builtAbout).Hash |
            Should -Be (Get-FileHash -Path $script:sourceAboutPath).Hash -Because (
                'the built about topic must match source; run ./build.ps1 -Tasks build after editing it')
    }

    It 'Should be UTF-8 without a BOM' {
        $script:aboutBytes.Length | Should -BeGreaterThan 0

        $hasBom = $script:aboutBytes.Length -ge 3 -and
            $script:aboutBytes[0] -eq 0xEF -and
            $script:aboutBytes[1] -eq 0xBB -and
            $script:aboutBytes[2] -eq 0xBF

        $hasBom | Should -BeFalse -Because 'authored files in this module are UTF-8 without BOM'
    }

    It 'Should contain only ASCII characters' {
        $nonAscii = @($script:aboutBytes | Where-Object { $_ -gt 0x7F })

        $nonAscii.Count | Should -Be 0 -Because 'a BOM-less file must be ASCII-only; use -- rather than an em-dash'
    }

    It 'Should name only cmdlets that are exported' {
        $named = [regex]::Matches($script:aboutText, '\b[A-Z][a-z]+-OER[A-Za-z]*\b') |
            ForEach-Object { $_.Value } |
                Sort-Object -Unique

        $named | Should -Not -BeNullOrEmpty -Because 'the about topic must name the module cmdlets'

        $unknown = @($named | Where-Object { $_ -notin $script:exportedNames })

        $unknown | Should -BeNullOrEmpty -Because (
            'every Verb-OER name in the about topic must be an exported cmdlet; unknown: {0}' -f ($unknown -join ', '))
    }

    It 'Should name every exported cmdlet' {
        $missing = @($script:exportedNames | Where-Object {
                $script:aboutText -notmatch ('\b{0}\b' -f [regex]::Escape($_))
            })

        $missing | Should -BeNullOrEmpty -Because (
            'the COMMAND COHORTS section is generated from FunctionsToExport; missing: {0}' -f ($missing -join ', '))
    }

    It 'Should name at least one cmdlet from the <Cohort> cohort' -ForEach $cohortCases {
        $found = @($Any | Where-Object { $script:aboutText -match ('\b{0}\b' -f [regex]::Escape($_)) })

        $found | Should -Not -BeNullOrEmpty -Because (
            'the about topic is the in-box orientation and must cover the {0} cohort' -f $Cohort)
    }
}
