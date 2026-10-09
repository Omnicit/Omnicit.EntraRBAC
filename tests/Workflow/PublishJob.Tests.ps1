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
    $script:WorkflowText = [System.IO.File]::ReadAllText((Join-Path -Path $script:Root -ChildPath '.github/workflows/build-and-test.yml'))
    $script:Pwsh = Join-Path -Path $PSHOME -ChildPath $(if ($IsWindows) { 'pwsh.exe' } else { 'pwsh' })
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
        # A fresh directory, always in the long path form. On Windows, Resolve-Path keeps an 8.3 short
        # component (RUNNER~1) while Get-ChildItem returns the long one, which would break the relative
        # paths PublishArtefact.ps1 records; Get-Item's FullName is the long form.
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

    function Get-WorkflowStepRun
    {
        <#
            The run: text of one step of the publish job, exactly as the workflow holds it: the
            lines after 'run: |' that are blank or indented deeper than 'run:', less the first
            line's indentation, the way a YAML literal block is read. Throws unless the job, the
            step and its run block are each found exactly once, so a renamed step fails here
            instead of leaving a check that runs nothing.
        #>
        param ([Parameter(Mandatory = $true)] [string] $Step)

        $Lines = $script:WorkflowText -split '\r?\n'
        $JobStart = @(for ($Index = 0; $Index -lt $Lines.Count; $Index++) { if ($Lines[$Index] -cmatch '^  publish:\s*$') { $Index } })

        if ($JobStart.Count -ne 1)
        {
            throw ("Expected one 'publish:' job in the workflow, found {0}." -f $JobStart.Count)
        }

        $StepStart = @(for ($Index = $JobStart[0] + 1; $Index -lt $Lines.Count; $Index++) { if ($Lines[$Index] -ceq ('      - name: {0}' -f $Step)) { $Index } })

        if ($StepStart.Count -ne 1)
        {
            throw ("Expected one step named '{0}' in the publish job, found {1}." -f $Step, $StepStart.Count)
        }

        $RunLine = -1
        $RunIndent = 0

        for ($Index = $StepStart[0] + 1; $Index -lt $Lines.Count; $Index++)
        {
            if ($Lines[$Index] -cmatch '^      - name: ')
            {
                break
            }

            if ($Lines[$Index] -cmatch '^(\s+)run: \|\s*$')
            {
                $RunLine = $Index
                $RunIndent = $Matches[1].Length
                break
            }
        }

        if ($RunLine -lt 0)
        {
            throw ("The step '{0}' has no 'run: |' block." -f $Step)
        }

        $Block = [System.Collections.Generic.List[string]]::new()

        for ($Index = $RunLine + 1; $Index -lt $Lines.Count; $Index++)
        {
            $Line = $Lines[$Index]

            if ($Line.Trim().Length -eq 0)
            {
                $Block.Add('')
                continue
            }

            if (($Line.Length - $Line.TrimStart(' ').Length) -le $RunIndent)
            {
                break
            }

            $Block.Add($Line)
        }

        while ($Block.Count -gt 0 -and $Block[$Block.Count - 1] -eq '')
        {
            $Block.RemoveAt($Block.Count - 1)
        }

        $First = @($Block | Where-Object -FilterScript { $_ -ne '' })[0]
        $Strip = $First.Length - $First.TrimStart(' ').Length

        (@($Block | ForEach-Object -Process { if ($_ -eq '') { '' } else { $_.Substring($Strip) } }) -join "`n")
    }

    function Invoke-PublishJob
    {
        <#
            One attempt of the publish job on a fresh runner: a new workspace holding the checked
            out script and the downloaded artefact, a new GITHUB_ENV and a new RUNNER_TEMP. The
            steps that reach the network (checkout, download, dependency install) are not run;
            the five that decide what is published and tagged are, in order, each in a pwsh
            process of its own, wrapped the way `shell: pwsh` wraps a step:
            $ErrorActionPreference = 'stop' first, the exit-code check last, the file dot-sourced
            by -Command. The stand-ins are dot-sourced directly after the first line. What each
            step writes to GITHUB_ENV reaches the steps after it, as on a runner. The job stops at
            the first step that exits nonzero.

            One line is the harness's own: $ErrorView = 'NormalView'. The default concise view
            wraps a long error message at the width of the host, and that width differs between
            hosts, so a phrase of a message such as 're-run this job' would match on one machine
            and be split across two lines on another. NormalView prints the message on one line.
            It changes how an error is shown and nothing about whether a step fails.

            A re-run of the failed job in the same run is this function called again with the
            same -Build: the artefact of a run does not change between its attempts.
        #>
        param (
            [Parameter(Mandatory = $true)] [string] $Build,
            [Parameter(Mandatory = $true)] [string] $Sha,
            [Parameter(Mandatory = $true)] [string] $World,
            [string] $Ref = 'refs/heads/main'
        )

        $Workspace = New-TestRoot -Name 'runner'
        $RunnerTemp = New-TestRoot -Name 'runner-temp'
        $Scripts = Join-Path -Path $Workspace -ChildPath '.github/scripts'
        $null = New-Item -ItemType Directory -Path $Scripts -Force
        Copy-Item -LiteralPath $script:ScriptPath -Destination $Scripts
        $Artefact = Join-Path -Path $Workspace -ChildPath 'artefact'
        $null = New-Item -ItemType Directory -Path $Artefact
        Copy-Item -Path (Join-Path -Path $Build -ChildPath '*') -Destination $Artefact -Recurse
        $GitHubEnv = Join-Path -Path $RunnerTemp -ChildPath 'github-env'
        [System.IO.File]::WriteAllText($GitHubEnv, '')

        $Environment = [ordered]@{
            GITHUB_SHA        = $Sha
            GITHUB_REF        = $Ref
            GITHUB_REF_NAME   = ($Ref -replace '^refs/(heads|tags)/', '')
            GITHUB_REPOSITORY = 'Omnicit/Omnicit.EntraRBAC'
            GITHUB_ENV        = $GitHubEnv
            RUNNER_TEMP       = $RunnerTemp
            EXPECTED_SHA      = $Sha
            GH_TOKEN          = 'NOT-A-REAL-TOKEN'
            GALLERY_API_TOKEN = 'NOT-A-REAL-TOKEN'
            OER_FAKE_ROOT     = $World
        }

        $Steps = @(
            'Verify the artefact against publish-meta.json'
            'Refuse a version the triggering ref does not call for'
            'Publish to the PowerShell Gallery'
            'Confirm the version is on the Gallery'
            'Tag the published commit and create the release'
        )

        $Ran = [System.Collections.Generic.List[string]]::new()
        $Log = [System.Text.StringBuilder]::new()
        $Failed = $null
        $StepNumber = 0

        foreach ($Step in $Steps)
        {
            $StepNumber++
            $StepFile = Join-Path -Path $RunnerTemp -ChildPath ('step-{0}.ps1' -f $StepNumber)
            $Wrapped = "`$ErrorActionPreference = 'stop'`n`$ErrorView = 'NormalView'`n. '{0}'`n{1}`nif ((Test-Path -LiteralPath variable:\LASTEXITCODE)) {{ exit `$LASTEXITCODE }}`n" -f $script:StandInPath, (Get-WorkflowStepRun -Step $Step)
            [System.IO.File]::WriteAllText($StepFile, $Wrapped)

            $Info = [System.Diagnostics.ProcessStartInfo]::new($script:Pwsh)
            foreach ($Argument in @('-NoProfile', '-NonInteractive', '-Command', (". '{0}'" -f $StepFile)))
            {
                $Info.ArgumentList.Add($Argument)
            }
            $Info.WorkingDirectory = $Workspace
            $Info.UseShellExecute = $false
            $Info.RedirectStandardOutput = $true
            $Info.RedirectStandardError = $true

            foreach ($Key in $Environment.Keys)
            {
                $Info.Environment[$Key] = [string]$Environment[$Key]
            }

            $Process = [System.Diagnostics.Process]::Start($Info)
            $StandardOutput = $Process.StandardOutput.ReadToEndAsync()
            $StandardError = $Process.StandardError.ReadToEndAsync()

            if (-not $Process.WaitForExit(180000))
            {
                $Process.Kill($true)
                throw ("The step '{0}' did not finish within three minutes." -f $Step)
            }

            $Process.WaitForExit()
            $null = $Log.AppendLine(('=== {0} (exit {1})' -f $Step, $Process.ExitCode))
            $null = $Log.AppendLine($StandardOutput.Result)
            $null = $Log.AppendLine($StandardError.Result)
            $Ran.Add($Step)

            foreach ($Line in [System.IO.File]::ReadAllLines($GitHubEnv))
            {
                if ($Line -match '^([^=]+)=(.*)$')
                {
                    $Environment[$Matches[1]] = $Matches[2]
                }
            }

            if ($Process.ExitCode -ne 0)
            {
                $Failed = $Step
                break
            }
        }

        [PSCustomObject]@{
            Ran    = $Ran.ToArray()
            Failed = $Failed
            Output = $Log.ToString()
        }
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

Describe 'The publish job, run step by step against a fake Gallery and a fake GitHub' {
    BeforeAll {
        $script:Tag = 'Tag the published commit and create the release'
        $script:V3 = '1.1.4-preview0003'
        $script:V4 = '1.1.4-preview0004'
        $script:JobA = New-TestBuild -Sha $script:ShaA -Version $script:V3 -Body 'A'
        $script:JobB = New-TestBuild -Sha $script:ShaB -Version $script:V3 -Body 'B'
        # GitVersion counts up from a tag (the measured table in rationale.md#publish-on-merge),
        # so once the repair tag is on A, B's rebuild carries the next preview. This build plays
        # that rebuild.
        $script:JobB4 = New-TestBuild -Sha $script:ShaB -Version $script:V4 -Body 'B'
        $script:JobC = New-TestBuild -Sha $script:ShaC -Version '1.1.4' -Body 'C'

        function Assert-Refused
        {
            # The tag step ran and refused, and NOTHING reached GitHub from it.
            param ([Parameter(Mandatory = $true)] $Job, [Parameter(Mandatory = $true)] [string] $World, [int] $ReleaseCreates = 0)

            $Job.Failed | Should -Be $script:Tag -Because ('the tag step must stop the job; its log follows:{0}{1}' -f [System.Environment]::NewLine, $Job.Output)
            $Job.Output | Should -BeLike '*REFUSING TO TAG.*'
            @(Get-FakeLog -World $World -Name 'gh' | Where-Object -FilterScript { $_ -like 'release create*' }).Count | Should -Be $ReleaseCreates -Because 'a refused run sends no gh release create'
        }
    }

    It 'publishes and tags its own commit on an ordinary merge, as before' {
        $World = New-FakeWorld

        $Job = Invoke-PublishJob -Build $script:JobA -Sha $script:ShaA -World $World

        $Job.Failed | Should -BeNullOrEmpty -Because ('the job runs green; its log follows:{0}{1}' -f [System.Environment]::NewLine, $Job.Output)
        @(Get-FakeLog -World $World -Name 'publish') | Should -Be @($script:V3)
        @(Get-FakeLog -World $World -Name 'save').Count | Should -Be 1 -Because 'an ordinary merge is compared too, before it is tagged'
        $GitHub = Get-FakeGitHub -World $World
        $GitHub['tags']["v$script:V3"] | Should -Be $script:ShaA
        $GitHub['releases']["v$script:V3"]['Commit'] | Should -Be $script:ShaA
        $GitHub['releases']["v$script:V3"]['Prerelease'] | Should -BeTrue
    }

    It 'tags its own commit when the failed job is re-run in the same run after a 500 whose upload arrived (2026-10-08)' {
        $World = New-FakeWorld
        $null = New-Item -ItemType File -Path (Join-Path -Path $World -ChildPath 'publish-answers-500')

        $First = Invoke-PublishJob -Build $script:JobA -Sha $script:ShaA -World $World
        $First.Failed | Should -Be 'Publish to the PowerShell Gallery'
        @(Get-FakeLog -World $World -Name 'publish') | Should -Be @($script:V3) -Because 'the upload arrived although the call failed'
        (Get-FakeGitHub -World $World)['tags'].Count | Should -Be 0

        $Rerun = Invoke-PublishJob -Build $script:JobA -Sha $script:ShaA -World $World

        $Rerun.Failed | Should -BeNullOrEmpty -Because ('the re-run runs green; its log follows:{0}{1}' -f [System.Environment]::NewLine, $Rerun.Output)
        $Rerun.Output | Should -BeLike '*SKIPPING THE PUBLISH*'
        @(Get-FakeLog -World $World -Name 'publish') | Should -Be @($script:V3) -Because 'nothing is published twice'
        $GitHub = Get-FakeGitHub -World $World
        $GitHub['tags']["v$script:V3"] | Should -Be $script:ShaA
        $GitHub['releases']["v$script:V3"]['Commit'] | Should -Be $script:ShaA
    }

    It 'refuses to tag the next merge when the version is already there from another commit, after <Case>' -ForEach @(
        @{ Case = 'a tag step that failed'; Fault = 'gh-create-fails'; FailedStep = 'Tag the published commit and create the release'; ReleaseCreates = 1 }
        @{ Case = 'a 500 nobody re-ran (the near miss of 2026-10-08)'; Fault = 'publish-answers-500'; FailedStep = 'Publish to the PowerShell Gallery'; ReleaseCreates = 0 }
    ) {
        $World = New-FakeWorld
        $null = New-Item -ItemType File -Path (Join-Path -Path $World -ChildPath $Fault)
        $JobForA = Invoke-PublishJob -Build $script:JobA -Sha $script:ShaA -World $World
        $JobForA.Failed | Should -Be $FailedStep

        $JobForB = Invoke-PublishJob -Build $script:JobB -Sha $script:ShaB -World $World

        Assert-Refused -Job $JobForB -World $World -ReleaseCreates $ReleaseCreates
        $JobForB.Output | Should -BeLike '*SKIPPING THE PUBLISH*'
        $JobForB.Output | Should -BeLike "*git tag v$($script:V3) <commit>*"
        $JobForB.Output | Should -BeLike '*re-run ALL jobs of this run*'
        @(Get-FakeLog -World $World -Name 'publish') | Should -Be @($script:V3) -Because 'B published nothing'
        $GitHub = Get-FakeGitHub -World $World
        $GitHub['tags'].Count | Should -Be 0
        $GitHub['releases'].Count | Should -Be 0
    }

    It 'refuses again when only the failed jobs are re-run after a refusal, before and after the repair tag' {
        $World = New-FakeWorld
        $null = New-Item -ItemType File -Path (Join-Path -Path $World -ChildPath 'gh-create-fails')
        $null = Invoke-PublishJob -Build $script:JobA -Sha $script:ShaA -World $World
        Assert-Refused -Job (Invoke-PublishJob -Build $script:JobB -Sha $script:ShaB -World $World) -World $World -ReleaseCreates 1

        # Re-run of the failed jobs: the same run, so the same artefact.
        Assert-Refused -Job (Invoke-PublishJob -Build $script:JobB -Sha $script:ShaB -World $World) -World $World -ReleaseCreates 1
        (Get-FakeGitHub -World $World)['tags'].Count | Should -Be 0

        # The repair tag goes on A by hand, but only the failed jobs are re-run.
        Set-FakeGitHub -World $World -Tag "v$script:V3" -Sha $script:ShaA
        Assert-Refused -Job (Invoke-PublishJob -Build $script:JobB -Sha $script:ShaB -World $World) -World $World -ReleaseCreates 1
        $GitHub = Get-FakeGitHub -World $World
        $GitHub['tags']["v$script:V3"] | Should -Be $script:ShaA
        $GitHub['releases'].Count | Should -Be 0 -Because "no release with B's notes is attached to A's tag"

        # Even with a release made on A by hand, B's run does not go green.
        Set-FakeGitHub -World $World -Tag "v$script:V3" -Sha $script:ShaA -WithRelease
        Assert-Refused -Job (Invoke-PublishJob -Build $script:JobB -Sha $script:ShaB -World $World) -World $World -ReleaseCreates 1
    }

    It 'publishes and tags the refused commit once the repair tag is on the published commit and all its jobs are re-run' {
        $World = New-FakeWorld
        $null = New-Item -ItemType File -Path (Join-Path -Path $World -ChildPath 'gh-create-fails')
        $null = Invoke-PublishJob -Build $script:JobA -Sha $script:ShaA -World $World
        Assert-Refused -Job (Invoke-PublishJob -Build $script:JobB -Sha $script:ShaB -World $World) -World $World -ReleaseCreates 1
        Set-FakeGitHub -World $World -Tag "v$script:V3" -Sha $script:ShaA

        $Rebuilt = Invoke-PublishJob -Build $script:JobB4 -Sha $script:ShaB -World $World

        $Rebuilt.Failed | Should -BeNullOrEmpty -Because ('the re-run of all jobs runs green; its log follows:{0}{1}' -f [System.Environment]::NewLine, $Rebuilt.Output)
        @(Get-FakeLog -World $World -Name 'publish') | Should -Be @($script:V3, $script:V4)
        $GitHub = Get-FakeGitHub -World $World
        $GitHub['tags']["v$script:V3"] | Should -Be $script:ShaA
        $GitHub['tags']["v$script:V4"] | Should -Be $script:ShaB
        $GitHub['releases']["v$script:V4"]['Commit'] | Should -Be $script:ShaB
    }

    It 'refuses to tag when the package cannot be read back, and tags once a re-run can read it' {
        $World = New-FakeWorld
        $Fault = Join-Path -Path $World -ChildPath 'save-fails'
        $null = New-Item -ItemType File -Path $Fault

        $First = Invoke-PublishJob -Build $script:JobA -Sha $script:ShaA -World $World

        Assert-Refused -Job $First -World $World
        $First.Output | Should -BeLike '*503 (Service Unavailable)*'
        $First.Output | Should -BeLike '*re-run this job*'
        (Get-FakeGitHub -World $World)['tags'].Count | Should -Be 0

        Remove-Item -LiteralPath $Fault
        $Rerun = Invoke-PublishJob -Build $script:JobA -Sha $script:ShaA -World $World

        $Rerun.Failed | Should -BeNullOrEmpty -Because ('the re-run runs green; its log follows:{0}{1}' -f [System.Environment]::NewLine, $Rerun.Output)
        (Get-FakeGitHub -World $World)['tags']["v$script:V3"] | Should -Be $script:ShaA
    }

    It 'leaves a v-tag run as it was: no comparison, and the release goes on the tag that started the run' {
        $World = New-FakeWorld
        Set-FakeGitHub -World $World -Tag 'v1.1.4' -Sha $script:ShaC

        $Job = Invoke-PublishJob -Build $script:JobC -Sha $script:ShaC -World $World -Ref 'refs/tags/v1.1.4'

        $Job.Failed | Should -BeNullOrEmpty -Because ('the job runs green; its log follows:{0}{1}' -f [System.Environment]::NewLine, $Job.Output)
        $Job.Output | Should -BeLike '*A v-tag run: v1.1.4 started this run*'
        @(Get-FakeLog -World $World -Name 'save').Count | Should -Be 0 -Because 'a v-tag run reads nothing back'
        @(Get-FakeLog -World $World -Name 'publish') | Should -Be @('1.1.4')
        $GitHub = Get-FakeGitHub -World $World
        $GitHub['tags']['v1.1.4'] | Should -Be $script:ShaC
        $GitHub['releases']['v1.1.4']['Commit'] | Should -Be $script:ShaC
        $GitHub['releases']['v1.1.4']['Prerelease'] | Should -BeFalse
    }
}
