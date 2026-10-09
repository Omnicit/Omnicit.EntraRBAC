<#
    The publish job never runs on a pull request, so the guard in its tag step is proven here,
    offline: no network, no Gallery, no GitHub, nothing published, and the module is never
    imported. Two halves:

    - PublishArtefact.ps1 -Verify and -Compare, called directly, with Save-PSResource replaced by
      a stand-in that serves a fake Gallery out of a directory.
    - The publish job itself: each step's run: text is read out of the workflow, wrapped the way
      `shell: pwsh` wraps it, and run in a fresh pwsh process of its own, with the Gallery cmdlets
      and gh replaced by stand-ins over the same fake Gallery and a fake GitHub. Each It plays one
      shape of runs on main, or one v-tag run, and asserts what was published and what was tagged.

    OER_WORKFLOW_ROOT points both halves at a mutated copy of the repository's .github/ for a
    mutation run (docs/development/rationale.md#publish-on-merge). It is never set in CI.
#>

BeforeAll {
    $script:Root = $env:OER_WORKFLOW_ROOT

    if ([string]::IsNullOrEmpty($script:Root))
    {
        $script:Root = (Resolve-Path -LiteralPath (Join-Path -Path $PSScriptRoot -ChildPath '../..')).Path
    }

    $script:ScriptPath = Join-Path -Path $script:Root -ChildPath '.github/scripts/PublishArtefact.ps1'
    $script:ModuleName = 'Omnicit.EntraRBAC'
    $script:ShaA = 'a' * 40
    $script:ShaB = 'b' * 40
    $script:ShaC = 'c' * 40
    $script:RootCount = 0

    <#
        Offline stand-ins for everything the publish job reaches over the network: the three
        PSResourceGet cmdlets it calls and the gh CLI. A function outranks a cmdlet or a native
        command of the same name, so dot-sourcing this file is enough. State lives under
        $env:OER_FAKE_ROOT:

          gallery/<version>/   the files of a published version folder
          github.json          tags (name -> commit) and releases (name -> commit, prerelease)
          <name>.log           one line per call, for the assertions
          publish-answers-500  the next publish arrives, and the call fails with a 500 (one-shot)
          gh-create-fails      the next gh release create fails (one-shot)
          save-fails           every Save-PSResource fails with a 503 (standing)
          save-nothing         every Save-PSResource returns without saving anything (standing)
    #>
    $StandIns = @'
function Find-PSResource
{
    [CmdletBinding()]
    param ($Name, $Version, [switch] $Prerelease, $Repository)

    $Plain = $Version.Trim('[', ']')

    if (Test-Path -LiteralPath (Join-Path -Path $env:OER_FAKE_ROOT -ChildPath "gallery/$Plain"))
    {
        [PSCustomObject]@{ Name = $Name; Version = $Plain; Prerelease = '' }
    }
}

function Publish-PSResource
{
    [CmdletBinding()]
    param ($Path, $Repository, $ApiKey, [switch] $SkipDependenciesCheck)

    $Data = Import-PowerShellDataFile -LiteralPath (Join-Path -Path $Path -ChildPath 'Omnicit.EntraRBAC.psd1')
    $Version = $Data.ModuleVersion

    if ($Data.PrivateData.PSData.Prerelease)
    {
        $Version = '{0}-{1}' -f $Version, $Data.PrivateData.PSData.Prerelease
    }

    $Target = Join-Path -Path $env:OER_FAKE_ROOT -ChildPath "gallery/$Version"

    if (Test-Path -LiteralPath $Target)
    {
        throw "Response status code does not indicate success: 409 (Conflict). $Version is already on the repository."
    }

    $null = New-Item -ItemType Directory -Path $Target -Force
    Copy-Item -Path (Join-Path -Path $Path -ChildPath '*') -Destination $Target -Recurse
    Add-Content -LiteralPath (Join-Path -Path $env:OER_FAKE_ROOT -ChildPath 'publish.log') -Value $Version

    $Fault = Join-Path -Path $env:OER_FAKE_ROOT -ChildPath 'publish-answers-500'

    if (Test-Path -LiteralPath $Fault)
    {
        Remove-Item -LiteralPath $Fault
        throw 'Response status code does not indicate success: 500 (Internal Server Error).'
    }
}

function Save-PSResource
{
    [CmdletBinding()]
    param ($Name, $Version, [switch] $Prerelease, $Repository, $Path, [switch] $SkipDependencyCheck, [switch] $TrustRepository)

    $Call = [ordered]@{
        Name                = $Name
        Version             = $Version
        Repository          = $Repository
        Path                = $Path
        Prerelease          = $Prerelease.IsPresent
        SkipDependencyCheck = $SkipDependencyCheck.IsPresent
        TrustRepository     = $TrustRepository.IsPresent
    }
    Add-Content -LiteralPath (Join-Path -Path $env:OER_FAKE_ROOT -ChildPath 'save.log') -Value (ConvertTo-Json -InputObject $Call -Compress)

    if (Test-Path -LiteralPath (Join-Path -Path $env:OER_FAKE_ROOT -ChildPath 'save-fails'))
    {
        throw 'Response status code does not indicate success: 503 (Service Unavailable).'
    }

    if (Test-Path -LiteralPath (Join-Path -Path $env:OER_FAKE_ROOT -ChildPath 'save-nothing'))
    {
        return
    }

    if (-not (Test-Path -LiteralPath $Path))
    {
        throw "Cannot find path '$Path' because it does not exist."
    }

    $Source = Join-Path -Path $env:OER_FAKE_ROOT -ChildPath ('gallery/' + $Version.Trim('[', ']'))

    if (-not (Test-Path -LiteralPath $Source))
    {
        Write-Error -Message "Package(s) '$Name' could not be installed as it was not found in any registered repositories."
        return
    }

    $Data = Import-PowerShellDataFile -LiteralPath (Join-Path -Path $Source -ChildPath 'Omnicit.EntraRBAC.psd1')
    $Target = Join-Path -Path $Path -ChildPath ('{0}/{1}' -f $Name, $Data.ModuleVersion)
    $null = New-Item -ItemType Directory -Path $Target -Force
    Copy-Item -Path (Join-Path -Path $Source -ChildPath '*') -Destination $Target -Recurse
}

function gh
{
    $State = Join-Path -Path $env:OER_FAKE_ROOT -ChildPath 'github.json'
    $GitHub = Get-Content -LiteralPath $State -Raw | ConvertFrom-Json -AsHashtable
    Add-Content -LiteralPath (Join-Path -Path $env:OER_FAKE_ROOT -ChildPath 'gh.log') -Value ($args -join ' ')
    $global:LASTEXITCODE = 0

    if ($args[0] -ceq 'api')
    {
        # The compare call a v-tag run makes: the tagged commit is the main tip.
        'identical'
        return
    }

    if ($args[0] -ceq 'release' -and $args[1] -ceq 'view')
    {
        if (-not $GitHub['releases'].ContainsKey($args[2]))
        {
            $global:LASTEXITCODE = 1
        }

        return
    }

    if ($args[0] -ceq 'release' -and $args[1] -ceq 'create')
    {
        $Fault = Join-Path -Path $env:OER_FAKE_ROOT -ChildPath 'gh-create-fails'

        if (Test-Path -LiteralPath $Fault)
        {
            Remove-Item -LiteralPath $Fault
            $global:LASTEXITCODE = 1
            return
        }

        $Tag = $args[2]
        $Target = $args[[array]::IndexOf($args, '--target') + 1]

        # As the REST API does: target_commitish is unused when the tag already exists.
        if (-not $GitHub['tags'].ContainsKey($Tag))
        {
            $GitHub['tags'][$Tag] = $Target
        }

        $GitHub['releases'][$Tag] = @{ Commit = $GitHub['tags'][$Tag]; Prerelease = ($args -ccontains '--prerelease') }
        [System.IO.File]::WriteAllText($State, (ConvertTo-Json -InputObject $GitHub -Depth 5))
        return
    }

    throw ('The gh stand-in does not know this call: gh {0}' -f ($args -join ' '))
}
'@

    $script:StandInPath = Join-Path -Path (Get-Item -LiteralPath $TestDrive).FullName -ChildPath 'stand-ins.ps1'
    [System.IO.File]::WriteAllText($script:StandInPath, $StandIns)
    . $script:StandInPath

    function New-TestRoot
    {
        # A fresh directory, always in the long path form (see the Windows note in the plan).
        param ([Parameter(Mandatory = $true)] [string] $Name)

        $script:RootCount++
        $Base = (Get-Item -LiteralPath $TestDrive).FullName
        (New-Item -ItemType Directory -Path (Join-Path -Path $Base -ChildPath ('{0}-{1}' -f $Name, $script:RootCount))).FullName
    }

    function New-FakeWorld
    {
        # An empty Gallery and a GitHub with no tags and no releases.
        $World = New-TestRoot -Name 'world'
        $null = New-Item -ItemType Directory -Path (Join-Path -Path $World -ChildPath 'gallery')
        [System.IO.File]::WriteAllText((Join-Path -Path $World -ChildPath 'github.json'), '{"tags":{},"releases":{}}')
        $World
    }

    function Get-FakeLog
    {
        param ([Parameter(Mandatory = $true)] [string] $World, [Parameter(Mandatory = $true)] [string] $Name)

        $LogPath = Join-Path -Path $World -ChildPath ('{0}.log' -f $Name)

        if (Test-Path -LiteralPath $LogPath)
        {
            @(Get-Content -LiteralPath $LogPath)
        }
    }

    function Get-FakeGitHub
    {
        param ([Parameter(Mandatory = $true)] [string] $World)

        Get-Content -LiteralPath (Join-Path -Path $World -ChildPath 'github.json') -Raw | ConvertFrom-Json -AsHashtable
    }

    function Set-FakeGitHub
    {
        # What a person does by hand: push a tag, and optionally create a release on it.
        param (
            [Parameter(Mandatory = $true)] [string] $World,
            [Parameter(Mandatory = $true)] [string] $Tag,
            [Parameter(Mandatory = $true)] [string] $Sha,
            [switch] $WithRelease
        )

        $GitHub = Get-FakeGitHub -World $World
        $GitHub['tags'][$Tag] = $Sha

        if ($WithRelease)
        {
            $GitHub['releases'][$Tag] = @{ Commit = $Sha; Prerelease = $true }
        }

        [System.IO.File]::WriteAllText((Join-Path -Path $World -ChildPath 'github.json'), (ConvertTo-Json -InputObject $GitHub -Depth 5))
    }

    function New-TestBuild
    {
        <#
            A build the way the ubuntu-latest leg leaves it after its -Record step:
            module/<name>/<version>/ with a manifest, a root module and a help file, beside the
            publish-meta.json the real -Record writes. -Body is what makes two builds of the same
            version differ, the way two commits do.
        #>
        param (
            [Parameter(Mandatory = $true)] [string] $Sha,
            [Parameter(Mandatory = $true)] [string] $Version,
            [Parameter(Mandatory = $true)] [string] $Body
        )

        $Build = New-TestRoot -Name 'build'
        $Numeric, $Prerelease = $Version -split '-', 2
        $Folder = Join-Path -Path $Build -ChildPath ('module/{0}/{1}' -f $script:ModuleName, $Numeric)
        $null = New-Item -ItemType Directory -Path (Join-Path -Path $Folder -ChildPath 'en-US') -Force
        $PrereleaseLine = ''

        if ($Prerelease)
        {
            $PrereleaseLine = "Prerelease   = '$Prerelease'"
        }

        $Manifest = @"
@{
    RootModule    = '$($script:ModuleName).psm1'
    ModuleVersion = '$Numeric'
    PrivateData   = @{
        PSData = @{
            $PrereleaseLine
            ReleaseNotes = 'The release notes of build $Body.'
        }
    }
}
"@
        [System.IO.File]::WriteAllText((Join-Path -Path $Folder -ChildPath ('{0}.psd1' -f $script:ModuleName)), $Manifest)
        [System.IO.File]::WriteAllText((Join-Path -Path $Folder -ChildPath ('{0}.psm1' -f $script:ModuleName)), "# The root module of build $Body.`n")
        [System.IO.File]::WriteAllText((Join-Path -Path $Folder -ChildPath ('en-US/about_{0}.help.txt' -f $script:ModuleName)), "About build $Body.`n")
        $null = & $script:ScriptPath -Record -Path $Build -Sha $Sha -ModuleVersion $Version 6>$null
        $Build
    }

    function Copy-TestBuild
    {
        # An independent copy of a build, to tamper with.
        param ([Parameter(Mandatory = $true)] [string] $Build)

        $Copy = New-TestRoot -Name 'copy'
        Copy-Item -Path (Join-Path -Path $Build -ChildPath '*') -Destination $Copy -Recurse
        $Copy
    }

    function Get-TestVersionFolder
    {
        param ([Parameter(Mandatory = $true)] [string] $Build)

        (Get-ChildItem -LiteralPath (Join-Path -Path $Build -ChildPath ('module/{0}' -f $script:ModuleName)) -Directory)[0].FullName
    }

    function Publish-ToFakeGallery
    {
        # Puts a build's version folder on the fake Gallery under its composed version.
        param ([Parameter(Mandatory = $true)] [string] $Build, [Parameter(Mandatory = $true)] [string] $World)

        $Meta = Get-Content -LiteralPath (Join-Path -Path $Build -ChildPath 'publish-meta.json') -Raw | ConvertFrom-Json
        $Target = Join-Path -Path $World -ChildPath ('gallery/{0}' -f $Meta.ComposedVersion)
        $null = New-Item -ItemType Directory -Path $Target -Force
        Copy-Item -Path (Join-Path -Path (Get-TestVersionFolder -Build $Build) -ChildPath '*') -Destination $Target -Recurse
        $Target
    }
}

Describe 'PublishArtefact.ps1 -Verify, with the comparison in Compare-FileHashSet' {
    BeforeAll {
        $script:VerifyBuild = New-TestBuild -Sha $script:ShaA -Version '1.1.4-preview0003' -Body 'A'
    }

    It 'returns the version folder of an intact artefact' {
        $Result = & $script:ScriptPath -Verify -Path $script:VerifyBuild -Sha $script:ShaA 6>$null

        $Result | Should -Be (Get-TestVersionFolder -Build $script:VerifyBuild)
    }

    It 'refuses an artefact that <Case>' -ForEach @(
        @{ Case = 'lost a recorded file'; Expected = 'The artefact is missing 1 recorded file(s): en-US/about_Omnicit.EntraRBAC.help.txt'; Tamper = { param ($Folder) Remove-Item -LiteralPath (Join-Path -Path $Folder -ChildPath 'en-US/about_Omnicit.EntraRBAC.help.txt') } }
        @{ Case = 'gained a file'; Expected = 'The artefact holds 1 file(s) that were never recorded: Extra.ps1'; Tamper = { param ($Folder) [System.IO.File]::WriteAllText((Join-Path -Path $Folder -ChildPath 'Extra.ps1'), "'extra'`n") } }
        @{ Case = 'changed a file'; Expected = 'The SHA-256 of 1 file(s) does not match what was recorded: Omnicit.EntraRBAC.psm1'; Tamper = { param ($Folder) Add-Content -LiteralPath (Join-Path -Path $Folder -ChildPath 'Omnicit.EntraRBAC.psm1') -Value '# changed' } }
    ) {
        $Copy = Copy-TestBuild -Build $script:VerifyBuild
        & $Tamper (Get-TestVersionFolder -Build $Copy)

        { & $script:ScriptPath -Verify -Path $Copy -Sha $script:ShaA 6>$null } | Should -Throw -ExpectedMessage $Expected
    }
}

Describe 'PublishArtefact.ps1 -Compare' {
    BeforeAll {
        $script:Version = '1.1.4-preview0003'
        $script:BuildA = New-TestBuild -Sha $script:ShaA -Version $script:Version -Body 'A'
        $script:BuildB = New-TestBuild -Sha $script:ShaB -Version $script:Version -Body 'B'

        function Invoke-Compare
        {
            param (
                [Parameter(Mandatory = $true)] [string] $Build,
                [Parameter(Mandatory = $true)] [string] $Sha,
                [string] $DownloadPath
            )

            if ([string]::IsNullOrEmpty($DownloadPath))
            {
                $DownloadPath = Join-Path -Path (New-TestRoot -Name 'download') -ChildPath 'published-package'
            }

            & $script:ScriptPath -Compare -Path $Build -Sha $Sha -Repository 'PSGallery' -DownloadPath $DownloadPath 6>$null
        }
    }

    BeforeEach {
        $script:World = New-FakeWorld
        $env:OER_FAKE_ROOT = $script:World
    }

    AfterEach {
        Remove-Item -Path 'Env:OER_FAKE_ROOT' -ErrorAction 'SilentlyContinue'
    }

    It 'passes when the Gallery serves the build this run tested, and asks for exactly that version' {
        $null = Publish-ToFakeGallery -Build $script:BuildA -World $script:World

        { Invoke-Compare -Build $script:BuildA -Sha $script:ShaA } | Should -Not -Throw

        $Calls = @(Get-FakeLog -World $script:World -Name 'save' | ForEach-Object -Process { $_ | ConvertFrom-Json })
        $Calls.Count | Should -Be 1 -Because 'the package is read back exactly once'
        $Calls[0].Name | Should -BeExactly 'Omnicit.EntraRBAC'
        $Calls[0].Version | Should -BeExactly '[1.1.4-preview0003]' -Because 'the brackets make the NuGet range an exact version'
        $Calls[0].Repository | Should -BeExactly 'PSGallery'
        $Calls[0].Prerelease | Should -BeTrue -Because 'a preview is never found without -Prerelease'
        $Calls[0].SkipDependencyCheck | Should -BeTrue
        $Calls[0].TrustRepository | Should -BeTrue -Because 'an untrusted repository prompts, and a non-interactive run fails on the prompt'
    }

    It 'refuses a package built from another commit, and names the repair' {
        $null = Publish-ToFakeGallery -Build $script:BuildA -World $script:World

        $Thrown = { Invoke-Compare -Build $script:BuildB -Sha $script:ShaB } | Should -Throw -PassThru
        $Message = $Thrown.Exception.Message

        $Message | Should -BeLike 'REFUSING TO TAG. Omnicit.EntraRBAC 1.1.4-preview0003 on PSGallery is not the build this run tested for bbbb*'
        $Message | Should -BeLike '*the SHA-256 of 3 file(s) differs from the tested build: en-US/about_Omnicit.EntraRBAC.help.txt, Omnicit.EntraRBAC.psd1, Omnicit.EntraRBAC.psm1*'
        $Message | Should -BeLike '*NOTHING has been tagged and no release was created.*'
        $Message | Should -BeLike '*git tag v1.1.4-preview0003 <commit>, then git push origin v1.1.4-preview0003*'
        $Message | Should -BeLike '*re-run ALL jobs of this run, not only the failed ones*'
        @(Get-FakeLog -World $script:World -Name 'save').Count | Should -Be 1 -Because 'the refusal comes from the comparison, after the read'
    }

    It 'refuses a package that holds a file the tested build does not' {
        $Folder = Publish-ToFakeGallery -Build $script:BuildA -World $script:World
        [System.IO.File]::WriteAllText((Join-Path -Path $Folder -ChildPath 'Extra.ps1'), "'extra'`n")

        { Invoke-Compare -Build $script:BuildA -Sha $script:ShaA } | Should -Throw -ExpectedMessage '*: it holds 1 file(s) the tested build does not: Extra.ps1.*'
    }

    It 'refuses a package that lacks a file the tested build holds' {
        $Folder = Publish-ToFakeGallery -Build $script:BuildA -World $script:World
        Remove-Item -LiteralPath (Join-Path -Path $Folder -ChildPath 'en-US/about_Omnicit.EntraRBAC.help.txt')

        { Invoke-Compare -Build $script:BuildA -Sha $script:ShaA } | Should -Throw -ExpectedMessage '*: it lacks 1 file(s) the tested build holds: en-US/about_Omnicit.EntraRBAC.help.txt.*'
    }

    It 'refuses when the read fails, and says what failed' {
        $null = Publish-ToFakeGallery -Build $script:BuildA -World $script:World
        $null = New-Item -ItemType File -Path (Join-Path -Path $script:World -ChildPath 'save-fails')

        $Thrown = { Invoke-Compare -Build $script:BuildA -Sha $script:ShaA } | Should -Throw -PassThru
        $Message = $Thrown.Exception.Message

        $Message | Should -BeLike 'REFUSING TO TAG. Expected to read Omnicit.EntraRBAC 1.1.4-preview0003 back from PSGallery*'
        $Message | Should -BeLike '*(Response status code does not indicate success: 503 (Service Unavailable).)*'
        $Message | Should -BeLike '*If the failure was transient, re-run this job*'
        @(Get-FakeLog -World $script:World -Name 'save').Count | Should -Be 1 -Because 'the read was attempted, so the refusal is the read failure'
    }

    It 'refuses when the version is not on the repository' {
        { Invoke-Compare -Build $script:BuildA -Sha $script:ShaA } | Should -Throw -ExpectedMessage "*and could not (Package(s) 'Omnicit.EntraRBAC' could not be installed as it was not found in any registered repositories.)*"
    }

    It 'refuses when the read returns without saving anything' {
        $null = Publish-ToFakeGallery -Build $script:BuildA -World $script:World
        $null = New-Item -ItemType File -Path (Join-Path -Path $script:World -ChildPath 'save-nothing')

        { Invoke-Compare -Build $script:BuildA -Sha $script:ShaA } | Should -Throw -ExpectedMessage '*and could not (No module folder at *'
        @(Get-FakeLog -World $script:World -Name 'save').Count | Should -Be 1 -Because 'the read was attempted and returned'
    }

    It 'refuses a download directory that already holds something, before reading anything' {
        $null = Publish-ToFakeGallery -Build $script:BuildA -World $script:World
        $Download = Join-Path -Path (New-TestRoot -Name 'download') -ChildPath 'published-package'
        $null = New-Item -ItemType Directory -Path $Download
        [System.IO.File]::WriteAllText((Join-Path -Path $Download -ChildPath 'stale.txt'), "stale`n")

        { Invoke-Compare -Build $script:BuildA -Sha $script:ShaA -DownloadPath $Download } | Should -Throw -ExpectedMessage "REFUSING TO TAG. The download directory '*' is not empty*"
        @(Get-FakeLog -World $script:World -Name 'save').Count | Should -Be 0 -Because 'nothing is read into a directory that is not empty'
    }

    It 'verifies the artefact before it reads the Gallery: <Case>' -ForEach @(
        @{ Case = 'a changed file'; Sha = 'a' * 40; Expected = 'The SHA-256 of 1 file(s) does not match what was recorded: Omnicit.EntraRBAC.psm1'; Tamper = $true }
        @{ Case = 'another commit'; Sha = 'b' * 40; Expected = "*belongs to a different commit."; Tamper = $false }
    ) {
        $null = Publish-ToFakeGallery -Build $script:BuildA -World $script:World
        $Copy = Copy-TestBuild -Build $script:BuildA

        if ($Tamper)
        {
            Add-Content -LiteralPath (Join-Path -Path (Get-TestVersionFolder -Build $Copy) -ChildPath 'Omnicit.EntraRBAC.psm1') -Value '# changed'
        }

        { Invoke-Compare -Build $Copy -Sha $Sha } | Should -Throw -ExpectedMessage $Expected
        @(Get-FakeLog -World $script:World -Name 'save').Count | Should -Be 0 -Because 'an artefact that fails verification is never compared'
    }
}
